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
-- and the batches followed the day temperatures exactly (D-021). Runs 21
-- and 23 did the same beside a map fireplace; in run 23 the fire notes
-- matched the harness's and the hours away were credited exactly (D-022);
-- in run 25 such a record, "no fire" notes included, came back unchanged
-- from save, exit to menu and continue.
-- Distilling in the pot still, pickup while processing, a barbecue or open
-- fire, upper floors and MP replication are NOT RUN.
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
--   fires              every ten game minutes the authority notes the fire
--                      (fireplace, wood stove, campfire, brazier, barbecue)
--                      that gives each such machine its air, with its fuel;
--                      hours the area is not loaded keep that fire's warmth
--                      while the fuel noted last would last (D-022).
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
-- to the site's unheated value), and as many hours of fire notes.
M.MAX_READINGS = 24 * 20
-- A fire is the one warming a machine when the game's formula for it gives
-- the air read there to within this (C); the formula matched the game to
-- 0.00000 C in RT-SP run 21.
M.FIRE_TOL = 1e-3
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

-- The air at a tile without heat sources now, as the game computes it before
-- adding them: outdoors the air, in a room the room formula (Climate.roomAir,
-- matched exactly in RT-SP runs 17-22).
function M.unwarmedAt(sq)
    local cm = getClimateManager()
    local t = cm:getTemperature()
    local room = false
    pcall(function() room = sq:isInARoom() == true end)
    if not room then return t end
    local dl, power = Climate.ROOM_DAYLIGHT, false
    pcall(function() dl = cm:getClimateValuesCopy():getDayLightLagged() end)
    pcall(function() power = getWorld():isHydroPowerOn() == true end)
    return Climate.roomAir(t, sq:getZ() >= 1, dl, power)
end

-- The fire that gives a machine's tile its air now, as a note for the record
-- ({ t = now, f = fuel minutes, x, y = its offset, r = its tile in a room,
-- c = its heat, rad = a fixed radius }), or nil. A lit fireplace (any
-- IsoFireplace: fireplace, wood stove, campfire, brazier, barrel oven) or
-- barbecue (IsoBarbecue) on the same floor within reach whose heat at the
-- tile by the game's formula is the air read there, so nothing blocks it;
-- the one with most fuel if several match. Their fuel is minutes burned one
-- per game minute, also while the area is not loaded (BC update).
function M.warmingFire(sq, air, now)
    if air == nil then return nil end
    local t0 = M.unwarmedAt(sq)
    if air <= t0 + M.FIRE_TOL then return nil end
    local x, y, z, cell, best = sq:getX(), sq:getY(), sq:getZ(), getCell(), nil
    local reach = Climate.FIRE_REACH
    for dx = -reach, reach do
        for dy = -reach, reach do
            local s = dx * dx + dy * dy < reach * reach and cell:getGridSquare(x + dx, y + dy, z) or nil
            local objs = s and s:getObjects()
            for i = 0, (objs and objs:size() or 0) - 1 do
                local o = objs:get(i)
                local c, rad
                if instanceof(o, "IsoFireplace") then
                    c = Climate.FIREPLACE_C
                elseif instanceof(o, "IsoBarbecue") then
                    c, rad = Climate.BARBECUE_C, Climate.BARBECUE_RADIUS
                end
                if c and o:isLit() and o:getFuelAmount() > 0 then
                    local fuel, srcRoom = o:getFuelAmount(), false
                    pcall(function() srcRoom = s:isInARoom() == true end)
                    local w = Climate.warmed(t0, dx, dy, rad or Climate.fireRadius(fuel), srcRoom, c)
                    if math.abs(w - air) <= M.FIRE_TOL and (best == nil or fuel > best.f) then
                        best = { t = now, f = fuel, x = dx, y = dy, r = srcRoom, c = c, rad = rad }
                    end
                end
            end
        end
    end
    return best
end

-- Readings and fire notes the batch no longer needs: hours before the day it
-- has reached (that day's mean is still recomputed), except the reading of
-- the hour just before it, which stands in for the day's first hour until
-- that hour is filed (Climate.siteDayMean; pruned, the status after midnight
-- showed the unheated value, RT-SP run 18), and the latest note before it,
-- which still governs the unread hours after it; all of them once the batch
-- is done.
function M.trimTemps(rec, env)
    if rec.state ~= "Processing" and rec.state ~= "Paused" then
        rec.temps, rec.fires = nil, nil
        return
    end
    local cut = math.floor(env:dayStart(env:dayIndex(rec.t))) - 1
    if rec.temps ~= nil then
        Climate.pruneSlots(rec.temps, cut)
        local keys = Tables.sortedKeys(rec.temps)
        if #keys > M.MAX_READINGS then Climate.pruneSlots(rec.temps, keys[#keys - M.MAX_READINGS + 1]) end
    end
    if rec.fires ~= nil then
        Climate.pruneNotes(rec.fires, cut)
        local keys = Tables.sortedKeys(rec.fires)
        if #keys > M.MAX_READINGS then Climate.pruneNotes(rec.fires, keys[#keys - M.MAX_READINGS + 1]) end
    end
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

-- Every ten game minutes on the authority: a note of the fire warming each
-- loaded, placed machine with a batch running, under the hour it is taken in
-- (the hour's last note wins; false when no fire warms it, written once an
-- hour). Records only, kept on the authority: clients never read them.
function M.observeFires()
    if not World.isAuthority() then return end
    local md = World.get()
    local sites = md.machineSites
    if md.v == nil or sites == nil then return end
    local now, env, cell = World.now(), World.env(), getCell()
    local hour = math.floor(now)
    for _, id in ipairs(Tables.sortedKeys(sites)) do
        local p = sites[id]
        local sq = cell:getGridSquare(p.x, p.y, p.z)
        local item = sq and onSquareById(sq, id)
        local rec = item and M.read(item, false)
        local air = rec and (rec.state == "Processing" or rec.state == "Paused") and M.airAt(sq) or nil
        if air ~= nil then
            local note = M.warmingFire(sq, air, now) or false
            local fires = rec.fires or {}
            if note or fires[hour] ~= false then
                fires[hour] = note
                rec.fires = fires
                rec.site = M.siteOf(sq)
                M.trimTemps(rec, env)
                M.write(item, rec, true)
            end
        end
    end
end

-- quiet: kept on the authority, not sent to clients (fire notes).
function M.write(item, rec, quiet)
    item:getModData()[M.SIDECAR] = rec
    if quiet then return end
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
