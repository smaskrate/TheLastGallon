-- Adapter: production machines as placeable items (decision D-015).
-- Runtime status: verified RT-SP 2026-10-31: a placed fermenter, reflux
-- still and drying column each ran a batch (load, firebox, wash, collect
-- into a can, dry, collect) with real inventory items, through the commands
-- (run 7) and through the context menu (run 12), and their records
-- survived save and reload. Runs 13-14 let the game clock run the batch (97.2 h
-- of fermentation) and unloaded the machines' chunk for 24 game hours: the
-- next access caught up exactly. Runs 17-19 (January, grid off) ran
-- fermenters outdoors, in a room and on a tile warmed by a heat source: the
-- readings filed equalled the game's, nothing was filed while unloaded,
-- and the batches followed the day temperatures exactly (D-021). Distilling
-- in the pot still, pickup while processing, a real fireplace or fire, upper
-- floors and MP replication are NOT RUN.
--
--   state store        machine item modData "tlgProc" (TLG.Domain.Process)
--   processing         only while the item lies on the ground; picking it up
--                      pauses the batch at the next access without crediting
--                      the unknown carried time (conservative)
--   unloaded           lazy, event-exact catch-up on access (Process.advance)
--   owner of           machine inputs, outputs, firebox fuel (all TLG-owned)
--   temperature        where it stands (D-021): the site (in a room or not,
--                      floor) is recorded on every access; every game hour the
--                      authority reads the game's air temperature at each
--                      loaded, placed machine with a batch running (rooms, grid
--                      power and lit fires, fireplaces and barbecues included,
--                      BC 42.21 ClimateManager.getAirTemperatureForSquare)
--                      into the record. Records only: the batch still advances
--                      on access. A machine moved without being used in
--                      between counts at its new place for that time.
require "TLG/Domain/Production/Process"
require "TLG/Persistence/Migrations"
require "TLG/Integration/World"
require "TLG/Content/Production"

TLG.Integration.Machines = TLG.Integration.Machines or {}
local M = TLG.Integration.Machines
local Process, World, Tables, Climate = TLG.Domain.Process, TLG.World, TLG.Tables, TLG.Domain.Climate

M.SIDECAR = "tlgProc"
-- Placed machines the hourly reading visits, at most.
M.MAX_INDEXED = 256
-- Hourly readings kept per record (20 days unaccessed; older hours fall back
-- to the site's unheated value).
M.MAX_READINGS = 24 * 20
M.ITEMS = {
    ["TLG.FermenterVessel"] = "fermenter_barrel",
    ["TLG.PotStill"] = "pot_still",
    ["TLG.RefluxStill"] = "reflux_still",
    ["TLG.DryingColumn"] = "drying_column",
}

function M.machineFor(item)
    return item and M.ITEMS[item:getFullType()] or nil
end

function M.isPlaced(item)
    return item:getWorldItem() ~= nil
end

function M.square(item)
    local wi = item:getWorldItem()
    return wi and wi:getSquare() or nil
end

-- Committed process record for a machine item (nil for non-machines or
-- unknown future schemas, which stay untouched).
function M.read(item, persist)
    local machine = M.machineFor(item)
    if machine == nil then return nil, "not_a_machine" end
    local raw = item:getModData()[M.SIDECAR]
    local rec, status = TLG.Persistence.Migrations.sidecar("process", raw)
    if raw ~= nil and rec == nil then return nil, status end
    if rec == nil then
        rec = Process.new({ id = persist and World.newId("P") or nil, machine = machine, t = World.now() })
    end
    return Tables.deepCopy(rec), "ok"
end

-- Where a placed machine stands, as the game's air temperature sees it:
-- IsoGridSquare.isInARoom() (map rooms and player-built rooms, BC) and the
-- floor.
function M.siteOf(sq)
    local room = false
    pcall(function() room = sq:isInARoom() == true end)
    return { room = room, z = sq:getZ() }
end

-- The game's air temperature at a tile now, what a character standing there
-- would feel (BC 42.21 ClimateManager.getAirTemperatureForSquare).
function M.airAt(sq)
    local ok, t = pcall(function() return getClimateManager():getAirTemperatureForSquare(sq) end)
    if ok and type(t) == "number" and t == t then return t end
    if not M.airWarned then
        M.airWarned = true
        TLG.Log.warn("machine air temperature unreadable: %s", tostring(t))
    end
    return nil
end

-- Readings the batch no longer needs: hours before the day it has reached
-- (that day's mean is still recomputed), except the hour just before it,
-- which stands in for the day's first hour until that hour is filed
-- (Climate.siteDayMean; pruned, the status after midnight showed the
-- unheated value, RT-SP run 18), and all of them once the batch is done.
function M.trimTemps(rec, env)
    if rec.temps == nil then return end
    if rec.state ~= "Processing" and rec.state ~= "Paused" then
        rec.temps = nil
        return
    end
    Climate.pruneSlots(rec.temps, math.floor(env:dayStart(env:dayIndex(rec.t))) - 1)
    local keys = Tables.sortedKeys(rec.temps)
    if #keys > M.MAX_READINGS then Climate.pruneSlots(rec.temps, keys[#keys - M.MAX_READINGS + 1]) end
end

local function advanceFrom(item, rec, now, env)
    if rec.state == "Processing" or rec.state == "Paused" then
        if not M.isPlaced(item) then
            local out = Tables.deepCopy(rec)
            if out.state == "Processing" then
                out.state, out.pause = "Paused", "not_placed"
            end
            out.t = now
            return out
        end
        if rec.pause == "not_placed" then
            local out = Tables.deepCopy(rec)
            out.state, out.pause, out.t = "Processing", nil, now
            return Process.advance(out, now, env)
        end
    end
    return (Process.advance(rec, now, env))
end

-- Brings a machine to `now`: processing only counts while placed, at the
-- temperature of where it stands.
function M.advance(item, rec, now, env)
    local sq = M.square(item)
    if sq ~= nil then
        rec = Tables.copy(rec)
        rec.site = M.siteOf(sq)
    end
    local out = advanceFrom(item, rec, now, env)
    M.trimTemps(out, env)
    return out
end

-- Today's temperature at a placed machine: with a batch running, the day
-- mean its batch counts so far; otherwise the air there now. Returns the
-- value, whether it is the reading now, and the site kind for the UI.
function M.siteTemp(item, rec, now, env)
    local sq = M.square(item)
    if sq == nil or rec.site == nil then return nil end
    local kind = rec.site.room and ((rec.site.z or 0) >= 1 and "room_upper" or "room") or "outdoors"
    if rec.state == "Processing" or rec.state == "Paused" then
        return (env:siteDayMean(env:dayIndex(now), Process.site(rec), now)), false, kind
    end
    return M.airAt(sq), true, kind
end

-- The hourly reading's list of placed machines: world record machineSites,
-- { [process id] = { x, y, z } }, written on every authority access.
function M.index(item, rec)
    if rec == nil or rec.id == nil or not World.isAuthority() then return end
    local md = World.get()
    if md.v == nil then return end
    local sites = md.machineSites or {}
    md.machineSites = sites
    local sq = M.square(item)
    if sq == nil then
        sites[rec.id] = nil
    elseif sites[rec.id] ~= nil or Tables.count(sites) < M.MAX_INDEXED then
        sites[rec.id] = { x = sq:getX(), y = sq:getY(), z = sq:getZ() }
    end
end

local function onSquareById(sq, id)
    local wobjs = sq:getWorldObjects()
    for i = 0, wobjs:size() - 1 do
        local it = wobjs:get(i):getItem()
        local p = it and M.machineFor(it) and it:getModData()[M.SIDECAR]
        if type(p) == "table" and p.id == id then return it end
    end
    return nil
end

-- Every game hour on the authority, after the climate record: one reading of
-- the air at each loaded, placed machine with a batch running, filed under
-- the hour that just ended. Squares not loaded are skipped (their hours use
-- the site's unheated value); a loaded square without the machine drops it
-- from the list until its next access.
function M.sampleSites()
    if not World.isAuthority() then return end
    local md = World.get()
    local sites = md.machineSites
    if md.v == nil or sites == nil then return end
    local now, env, cell = World.now(), World.env(), getCell()
    local slot = math.floor(now - 0.5)
    for _, id in ipairs(Tables.sortedKeys(sites)) do
        local p = sites[id]
        local sq = cell:getGridSquare(p.x, p.y, p.z)
        if sq ~= nil then
            local item = onSquareById(sq, id)
            if item == nil then
                sites[id] = nil
            else
                local rec = M.read(item, false)
                local t = rec and (rec.state == "Processing" or rec.state == "Paused") and M.airAt(sq) or nil
                if t ~= nil then
                    rec.site = M.siteOf(sq)
                    rec.temps = rec.temps or {}
                    rec.temps[slot] = t
                    M.trimTemps(rec, env)
                    M.write(item, rec)
                end
            end
        end
    end
end

function M.write(item, rec)
    item:getModData()[M.SIDECAR] = rec
    if item.syncItemFields then item:syncItemFields() end
    local wi = item:getWorldItem()
    if wi and wi.transmitModData then pcall(function() wi:transmitModData() end) end
end

-- Machine items within reach of a square (for still <- fermenter loading).
function M.nearbyMachines(square, radius, kind)
    local out = {}
    if square == nil then return out end
    local cell = getCell()
    for dx = -radius, radius do
        for dy = -radius, radius do
            local sq = cell:getGridSquare(square:getX() + dx, square:getY() + dy, square:getZ())
            if sq then
                local wobjs = sq:getWorldObjects()
                for i = 0, wobjs:size() - 1 do
                    local it = wobjs:get(i):getItem()
                    local mid = M.machineFor(it)
                    if mid and (kind == nil or TLG.Registry.need("machine", mid).kind == kind) then
                        out[#out + 1] = it
                    end
                end
            end
        end
    end
    return out
end

-- Finds a machine item by id on a square or in the player's inventory.
function M.find(player, ref)
    if type(ref) ~= "table" or type(ref.id) ~= "number" then return nil end
    if ref.x and ref.y and ref.z then
        local sq = getCell():getGridSquare(ref.x, ref.y, ref.z)
        if sq then
            local wobjs = sq:getWorldObjects()
            for i = 0, wobjs:size() - 1 do
                local it = wobjs:get(i):getItem()
                if it and it:getID() == ref.id then return it end
            end
        end
    end
    return player and player:getInventory():getItemWithIDRecursiv(ref.id) or nil
end

function M.refFor(item)
    local sq = M.square(item)
    if sq then return { kind = "machine", id = item:getID(), x = sq:getX(), y = sq:getY(), z = sq:getZ() } end
    return { kind = "machine", id = item:getID() }
end

return M
