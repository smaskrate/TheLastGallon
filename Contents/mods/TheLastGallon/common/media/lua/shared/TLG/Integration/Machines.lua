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
-- from save, exit to menu and continue. In run 26 running fermenters were
-- picked up and put down through the player's actions: the record travelled
-- unchanged, but the work around the move failed D-015. With the move hooks
-- below, run 27 counted the placed hours exactly and credited a grab no Lua
-- saw up to the last time the machine was found placed. In run 28 a pot
-- still took a wash larger than it holds in two loads, ran out of fuel and
-- was fed again, and matched the definitions exactly. In run 34 a
-- barbecue's warmth was read, noted and credited over a trip exactly; a
-- campfire built by the player (a Lua campfire over a permanent IsoFire,
-- not an IsoFireplace) was read but never noted. With M.fireOf, run 35
-- noted it in every hour and credited its warmth over the trip exactly.
-- A still or drying column picked up while processing and upper floors are
-- NOT RUN. In multiplayer (RT-MP runs 145-147) a vessel's status was
-- answered for both players, and on a dedicated server the mod takes the
-- vessel off the floor into both arms itself (M.takeOnServer, D-030; the
-- game's own way fails there): its batch was carried on the server and the
-- record reached the player's client with the item. A carrier's death drops
-- the vessel where no Lua sees it: in single player the death event puts it
-- down (run 202); a server fires none, and the hands' events do it there
-- (M.onHands, RT-MP run 210: put down where the player died, from the
-- death). The hourly readings and
-- ten-minute notes of 32 fermenters were timed in RT-SP runs 181-185
-- (performance mode). Since D-032 one scan serves every machine a fire
-- warms, a trim sorts nothing, and a catch-up sorts the notes once, with
-- the same results (equivalence tests; fireplace mode, run 184).
--
--   state store        machine item modData "tlgProc" (TLG.Domain.Process)
--   processing         only while the item lies on the ground (D-015). The
--                      moves the game's Lua makes (M.install: Grab, floor
--                      transfers, the place action) bring the batch to the
--                      moment it is picked up and start it again from the
--                      moment it is put down. A move no Lua sees (in MP the
--                      server grabs in a Java item transaction) is found at
--                      the next access or put-down: the batch counts up to
--                      the last time the authority found it placed (`seen`,
--                      at most ten minutes off while its area is loaded)
--   unloaded           lazy, event-exact catch-up on access (Process.advance)
--   owner of           machine inputs, outputs, firebox fuel (all TLG-owned)
--   temperature        where it stands (D-021): the site (in a room or not,
--                      its tile) is recorded on every access; every game hour the
--                      authority reads the game's air temperature at each
--                      loaded, placed machine with a batch running (rooms, grid
--                      power and lit fires, fireplaces and barbecues included,
--                      BC 42.21 ClimateManager.getAirTemperatureForSquare)
--                      into the record. Records only: the batch still advances
--                      on access.
--   fires              every ten game minutes the authority notes the fire
--                      (fireplace, wood stove, brazier, barbecue, campfire)
--                      that gives each such machine its air, with its fuel;
--                      hours the area is not loaded keep that fire's warmth
--                      while the fuel noted last would last (D-022).
-- On a server every read of a record is checked against the vault
-- (TLG/Authority/Vault.lua, holder the machine item; audit V-01): a client
-- can rewrite an item's mod data there. The vault saves the readings and
-- fire notes only as digests (Vault.DIGESTED), so a note keeps to the
-- fields in Vault.NOTE_FIELDS, or after a restart it reads as forged and the
-- notes are dropped.
require "TLG/Domain/Production/Process"
require "TLG/Persistence/Migrations"
require "TLG/Integration/World"
require "TLG/Content/Production"
require "TLG/Content/Biodiesel"
require "TLG/Authority/Vault"

TLG.Integration.Machines = TLG.Integration.Machines or {}
local M = TLG.Integration.Machines
local Process, World, Tables, Climate = TLG.Domain.Process, TLG.World, TLG.Tables, TLG.Domain.Climate
local Vault = TLG.Authority.Vault

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
    -- The biodiesel chain (D-036). The wood retort and the lye leacher
    -- hand their methanol and lye to a reactor beside them, and the reactor
    -- its crude to a wash tank, as a fermenter hands its wash to a still.
    ["TLG.WoodRetort"] = "wood_retort",
    ["TLG.AshBarrel"] = "ash_pit",
    ["TLG.LyeLeacher"] = "lye_leacher",
    ["TLG.BiodieselReactor"] = "biodiesel_reactor",
    ["TLG.BiodieselWashTank"] = "biodiesel_wash_tank",
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

local function send(item)
    if item.syncItemFields then item:syncItemFields() end
    local wi = item:getWorldItem()
    if wi and wi.transmitModData then pcall(function() wi:transmitModData() end) end
end

-- The record in the item's mod data as stored, checked against the vault on
-- a server (put back there when it differs).
function M.stored(item)
    return Vault.guard("process", Vault.itemHolder(item), item:getModData(), M.SIDECAR, function() send(item) end)
end

-- Committed process record for a machine item (nil for non-machines or
-- unknown future schemas, which stay untouched).
function M.read(item, persist)
    local machine = M.machineFor(item)
    if machine == nil then return nil, "not_a_machine" end
    local raw = M.stored(item)
    local rec, status = TLG.Persistence.Migrations.sidecar("process", raw)
    if raw ~= nil and rec == nil then return nil, status end
    if rec == nil then
        rec = Process.new({ id = persist and World.newId("P") or nil, machine = machine, t = World.now() })
    end
    return Tables.deepCopy(rec), "ok"
end

-- Where a placed machine stands, as the game's air temperature sees it:
-- IsoGridSquare.isInARoom() (map rooms and player-built rooms, BC) and the
-- floor, with its tile (a move is told by it).
function M.siteOf(sq)
    local room = false
    pcall(function() room = sq:isInARoom() == true end)
    return { room = room, z = sq:getZ(), x = sq:getX(), y = sq:getY() }
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

-- The campfire a player builds, on its square (SCampfireSystem, SRC 42.21):
-- the object named "Campfire", whose mod data holds the campfire's fuel in
-- minutes, whether it burns and whether it stands outside, copied there at
-- every change (SCampfireGlobalObject:saveData).
function M.campfireData(s)
    local objs = s:getObjects()
    for i = 0, objs:size() - 1 do
        local o = objs:get(i)
        local ok, name = pcall(function() return o:getName() end)
        if ok and name == "Campfire" then return o:getModData() end
    end
    return nil
end

-- What object o on square s warms with, when it is a lit fire with fuel:
-- heat c, fuel f in minutes, radius now, and a barbecue's fixed radius
-- (rad) or a campfire's kind and largest radius (k, rmax). A campfire heats
-- through the permanent IsoFire it keeps lit (BC IsoFire.update: 35 C, its
-- light radius); other open fires have no fuel to count.
function M.fireOf(o, s)
    if instanceof(o, "IsoFireplace") then
        local fuel = o:isLit() and o:getFuelAmount() or 0
        if fuel > 0 then return { c = Climate.FIREPLACE_C, f = fuel, radius = Climate.fireRadius(fuel) } end
    elseif instanceof(o, "IsoBarbecue") then
        local fuel = o:isLit() and o:getFuelAmount() or 0
        if fuel > 0 then
            return { c = Climate.BARBECUE_C, f = fuel, radius = Climate.BARBECUE_RADIUS, rad = Climate.BARBECUE_RADIUS }
        end
    elseif instanceof(o, "IsoFire") and o:isPermanent() then
        local md = M.campfireData(s)
        if md and md.isLit == true and type(md.fuelAmt) == "number" and md.fuelAmt > 0 then
            return { c = Climate.CAMPFIRE_C, f = md.fuelAmt, radius = o:getLightRadius(), k = "campfire",
                rmax = md.exterior == false and Climate.CAMPFIRE_RADIUS_INSIDE or Climate.CAMPFIRE_RADIUS }
        end
    end
    return nil
end

-- The fire that gives a machine's tile its air now, as a note for the record
-- ({ t = now, f = fuel minutes, x, y = its offset, r = its tile in a room,
-- c = its heat, rad = a fixed radius, or k = "campfire" and rmax = its
-- largest radius }), or nil. A lit fireplace (any IsoFireplace: fireplace,
-- wood stove, the map's campfire tiles, brazier, barrel oven), barbecue
-- (IsoBarbecue) or campfire a player built (M.fireOf) on the same floor
-- within reach whose heat at the tile by the game's formula is the air read
-- there, so nothing blocks it; the one with most fuel if several match.
-- Their fuel is minutes burned one per game minute, also while the area is
-- not loaded (BC update; a campfire's one per minute event, RT-SP run 34).
-- `fires`: M.firesNear's list for squares that include this one (the
-- ten-minute note scans once for all machines); without it, this square's
-- reach is scanned.
function M.warmingFire(sq, air, now, fires)
    if air == nil then return nil end
    local t0 = M.unwarmedAt(sq)
    if air <= t0 + M.FIRE_TOL then return nil end
    local x, y, z, best = sq:getX(), sq:getY(), sq:getZ(), nil
    local reach = Climate.FIRE_REACH
    for _, e in ipairs(fires or M.firesNear({ sq })) do
        local dx, dy, fire = e.x - x, e.y - y, e.fire
        if e.z == z and dx * dx + dy * dy < reach * reach then
            local w = Climate.warmed(t0, dx, dy, fire.radius, e.room, fire.c)
            if math.abs(w - air) <= M.FIRE_TOL and (best == nil or fire.f > best.f) then
                best = { t = now, f = fire.f, x = dx, y = dy, r = e.room, c = fire.c, rad = fire.rad,
                    k = fire.k, rmax = fire.rmax }
            end
        end
    end
    return best
end

-- Every lit fire (M.fireOf) on the same floor within reach of any of the
-- given squares: the squares closer than Climate.FIRE_REACH, each visited
-- once however many of the given squares it is near. 32 fermenters beside
-- one fire each scanned the same 1,000 squares every ten minutes, 90 ms
-- (docs/performance.md). Each entry: x, y, z, the object's index i on its
-- square, fire, and room (its square in a room). Listed in the order a scan
-- of one square's reach meets them (x, then y, then i), so M.warmingFire
-- picks the same fire among several that match.
function M.firesNear(squares)
    local reach, cell, rows = Climate.FIRE_REACH, getCell(), {}
    for _, sq in ipairs(squares) do
        local x, y, z = sq:getX(), sq:getY(), sq:getZ()
        rows[z] = rows[z] or {}
        for dy = 1 - reach, reach - 1 do
            local w = reach
            while w * w + dy * dy >= reach * reach do w = w - 1 end
            local row = rows[z][y + dy] or {}
            rows[z][y + dy] = row
            row[#row + 1] = { x - w, x + w }
        end
    end
    local out = {}
    for _, z in ipairs(Tables.sortedKeys(rows)) do
        for _, y in ipairs(Tables.sortedKeys(rows[z])) do
            local spans = Tables.sort(rows[z][y], function(a, b) return a[1] < b[1] end)
            local last
            for _, span in ipairs(spans) do
                for x = (last ~= nil and last >= span[1]) and last + 1 or span[1], span[2] do
                    local s = cell:getGridSquare(x, y, z)
                    local objs = s and s:getObjects()
                    for i = 0, (objs and objs:size() or 0) - 1 do
                        local fire = M.fireOf(objs:get(i), s)
                        if fire then
                            local room = false
                            pcall(function() room = s:isInARoom() == true end)
                            out[#out + 1] = { x = x, y = y, z = z, i = i, fire = fire, room = room }
                        end
                    end
                end
                if last == nil or span[2] > last then last = span[2] end
            end
        end
    end
    return Tables.sort(out, function(a, b)
        if a.x ~= b.x then return a.x < b.x end
        if a.y ~= b.y then return a.y < b.y end
        if a.z ~= b.z then return a.z < b.z end
        return a.i < b.i
    end)
end

-- Readings and fire notes the batch no longer needs: hours before the day it
-- has reached (that day's mean is still recomputed), except the reading of
-- the hour just before it, which stands in for the day's first hour until
-- that hour is filed (Climate.siteDayMean; pruned, the status after midnight
-- showed the unheated value, RT-SP run 18), and the latest note before it,
-- which still governs the unread hours after it; all of them once the batch
-- is done.
-- The key from which only `limit` keys of t remain, as Tables.sortedKeys
-- gives it, or nil when t holds no more than `limit + spare` (keys a prune
-- would keep anyway). A reading or a note usually puts a record one or two
-- over, so the key is picked in a pass. Sorting up to 480 keys twice on
-- every reading and note cost a record left unopened 6 ms each time
-- (docs/performance.md).
local function keepFrom(t, limit, spare)
    local n = Tables.count(t)
    if n <= limit + (spare or 0) then return nil end
    local k = n - limit + 1
    if k <= 8 then return Tables.kthKey(t, k) end
    return Tables.sortedKeys(t)[k]
end

function M.trimTemps(rec, env)
    if rec.state ~= "Processing" and rec.state ~= "Paused" then
        rec.temps, rec.fires = nil, nil
        return
    end
    local cut = math.floor(env:dayStart(env:dayIndex(rec.t))) - 1
    if rec.temps ~= nil then
        Climate.pruneSlots(rec.temps, cut)
        local from = keepFrom(rec.temps, M.MAX_READINGS)
        if from ~= nil then Climate.pruneSlots(rec.temps, from) end
    end
    if rec.fires ~= nil then
        Climate.pruneNotes(rec.fires, cut)
        -- One note over stays: pruneNotes keeps the latest note below its
        -- bound, and with one over the bound is the second note. The notes
        -- of a record left unopened settle there.
        local from = keepFrom(rec.fires, M.MAX_READINGS, 1)
        if from ~= nil then Climate.pruneNotes(rec.fires, from) end
    end
end

function M.running(rec)
    return rec.state == "Processing" or rec.state == "Paused"
end

-- A machine item with a process record (the move hooks never create one).
function M.tracked(item)
    return item ~= nil and M.machineFor(item) ~= nil and item:getModData()[M.SIDECAR] ~= nil
end

-- Whether the record's site is another tile than `sq` (records from before
-- the site kept its tile cannot tell: false).
function M.movedFrom(rec, sq)
    local s = rec.site
    return s ~= nil and s.x ~= nil and (s.x ~= sq:getX() or s.y ~= sq:getY() or (s.z or 0) ~= sq:getZ())
end

-- Marks a running batch carried from `now`: nothing counts until it is put
-- down. A carried record is never advanced: Process.advance would resume a
-- Paused batch and count the time.
local function carry(rec, now)
    if M.running(rec) then rec.state, rec.pause = "Paused", "not_placed" end
    rec.t = now
end

-- A move no Lua saw: the batch counts at its old site up to the last time
-- the authority found it placed (`seen`, stamped on every access, hourly
-- reading and ten-minute note), nothing after.
local function creditUntilSeen(rec, now, env)
    local out = (Process.advance(rec, math.min(now, math.max(rec.t, rec.seen or rec.t)), env))
    out.t = now
    return out
end

-- Brings a machine to `now`: processing only counts while placed, at the
-- temperature of where it stands. The moves the game's Lua makes are
-- accounted when they happen (M.pickedUp, M.putDown); one found here was
-- not seen.
function M.advance(item, rec, now, env)
    local sq = M.square(item)
    local out
    if not M.running(rec) then
        out = (Process.advance(rec, now, env))
    elseif rec.pause == "not_placed" then
        -- Carried; put down where no Lua saw it: from now.
        out = Tables.deepCopy(rec)
        out.t = now
        if sq ~= nil then out.state, out.pause = "Processing", nil end
    elseif sq == nil then
        out = creditUntilSeen(rec, now, env)
        carry(out, now)
    elseif M.movedFrom(rec, sq) then
        out = creditUntilSeen(rec, now, env)
    else
        out = Tables.copy(rec)
        out.site = M.siteOf(sq)
        out = (Process.advance(out, now, env))
    end
    if sq ~= nil then out.site, out.seen = M.siteOf(sq), now end
    M.trimTemps(out, env)
    return out
end

-- After the game's Lua lifted a machine off the ground: the batch counts up
-- to this moment where it stood, then waits, carried, until it is put down.
function M.pickedUp(item, now)
    local rec = M.read(item, false)
    if rec == nil then return end
    local env = World.env()
    if M.running(rec) and rec.pause ~= "not_placed" then
        rec = (Process.advance(rec, now, env))
        rec.seen = now
        carry(rec, now)
    end
    M.trimTemps(rec, env)
    M.index(item, rec)
    M.write(item, rec)
end

-- After the game's Lua put a machine down: a carried batch starts again
-- from this moment, here, and the hourly reading lists it at once. One
-- lifted where no Lua saw it first counts up to the last time it was seen.
function M.putDown(item, now)
    local rec, sq = M.read(item, false), M.square(item)
    if rec == nil or sq == nil then return end
    local env = World.env()
    if rec.pause == "not_placed" then
        rec.state, rec.pause, rec.t = "Processing", nil, now
    elseif M.running(rec) and M.movedFrom(rec, sq) then
        rec = creditUntilSeen(rec, now, env)
    end
    rec.site, rec.seen = M.siteOf(sq), now
    M.trimTemps(rec, env)
    M.index(item, rec)
    M.write(item, rec)
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

-- The hourly reading's list of placed machines: machineSites in the server
-- store (World.server(), never sent to clients; audit V-03),
-- { [process id] = { x, y, z } }, written on every authority access.
function M.index(item, rec)
    if rec == nil or rec.id == nil or not World.isAuthority() then return end
    local md = World.get()
    if md.v == nil then return end
    local srv = World.server()
    local sites = srv.machineSites or {}
    srv.machineSites = sites
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

-- The record as stored, for the hourly reading and the ten-minute note: they
-- change a few fields of it and write it back at once, so the copy M.read
-- makes for everyone else is spared (with 20 days of readings it cost them
-- 0.3 ms a machine, docs/performance.md). An older schema comes upgraded, a
-- new table; a newer schema or none gives nil, as M.read leaves those alone.
local function stored(item)
    local raw = M.machineFor(item) and M.stored(item)
    if raw == nil then return nil end
    return (TLG.Persistence.Migrations.sidecar("process", raw))
end

-- Every game hour on the authority, after the climate record: one reading of
-- the air at each loaded, placed machine with a batch running, filed under
-- the hour that just ended. Squares not loaded are skipped (their hours use
-- the site's unheated value); a loaded square without the machine drops it
-- from the list until its next access.
function M.sampleSites()
    if not World.isAuthority() then return end
    local md = World.get()
    local sites = World.server().machineSites
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
                local rec = stored(item)
                local t = rec and (rec.state == "Processing" or rec.state == "Paused") and M.airAt(sq) or nil
                if t ~= nil then
                    rec.site, rec.seen = M.siteOf(sq), now
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
-- (the hour's last note wins; false when no fire warms it, noted once an
-- hour), and the time it was found placed (`seen`, what a move no Lua saw is
-- credited up to). Records only, kept on the authority: clients never read
-- them.
function M.observeFires()
    if not World.isAuthority() then return end
    local md = World.get()
    local sites = World.server().machineSites
    if md.v == nil or sites == nil then return end
    local now, env, cell = World.now(), World.env(), getCell()
    local hour = math.floor(now)
    -- The machines and the air at each first, then one scan for the fires
    -- near those a heat source warms, then the notes in the same order.
    local found, warmed = {}, {}
    for _, id in ipairs(Tables.sortedKeys(sites)) do
        local p = sites[id]
        local sq = cell:getGridSquare(p.x, p.y, p.z)
        local item = sq and onSquareById(sq, id)
        local rec = item and stored(item)
        local air = rec and (rec.state == "Processing" or rec.state == "Paused") and M.airAt(sq) or nil
        if air ~= nil then
            local warm = air > M.unwarmedAt(sq) + M.FIRE_TOL
            found[#found + 1] = { sq = sq, item = item, rec = rec, air = air, warm = warm }
            if warm then warmed[#warmed + 1] = sq end
        end
    end
    local near = #warmed > 0 and M.firesNear(warmed) or nil
    for _, e in ipairs(found) do
        local rec = e.rec
        local note = M.warmingFire(e.sq, e.air, now, e.warm and near or nil) or false
        local fires = rec.fires or {}
        if note or fires[hour] ~= false then
            fires[hour] = note
            rec.fires = fires
        end
        rec.site, rec.seen = M.siteOf(e.sq), now
        M.trimTemps(rec, env)
        M.write(e.item, rec, true)
    end
end

-- On a server, a record written for a machine on the floor goes to the
-- clients: an item's mod data reaches only the client whose inventory holds
-- it (syncItemFields sends nothing for an item in no container, and the
-- world object's transmitModData sends that object's own mod data;
-- engine-capabilities, RT-MP), and the menu decides Pause, Resume and Abort
-- batch from the client's copy (D-023; RT-MP launch 362). The hourly
-- readings and fire notes stay on the server: up to 480 entries each, and
-- the menu needs only the state.
M.PUSH_DROP = { temps = true, fires = true }

local function push(item, rec)
    if not (isServer and isServer()) or sendServerCommand == nil then return end
    local sq = M.square(item)
    if sq == nil then return end
    local view = {}
    for k, v in pairs(rec) do
        if not M.PUSH_DROP[k] then view[k] = v end
    end
    sendServerCommand("TLG", "machine", { id = item:getID(), x = sq:getX(), y = sq:getY(), z = sq:getZ(), rec = view })
end

-- quiet: kept on the authority, not sent to clients (fire notes).
function M.write(item, rec, quiet)
    item:getModData()[M.SIDECAR] = rec
    Vault.put("process", Vault.itemHolder(item), rec)
    if quiet then return end
    send(item)
    push(item, rec)
end

-- On a client: a record the server sent for a machine on the floor, put in
-- this client's copy of the item. Returns whether the item was found (a
-- square this client has not loaded is skipped; the item comes with its
-- record when it loads).
function M.received(args)
    if type(args) ~= "table" or type(args.rec) ~= "table" or getCell() == nil then return false end
    local sq = getCell():getGridSquare(args.x, args.y, args.z)
    local wobjs = sq and sq:getWorldObjects()
    for i = 0, (wobjs and wobjs:size() or 0) - 1 do
        local it = wobjs:get(i):getItem()
        if it and it:getID() == args.id and M.machineFor(it) then
            it:getModData()[M.SIDECAR] = args.rec
            return true
        end
    end
    return false
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

local function wrap(class, method, fn)
    local orig = class and class[method]
    if orig == nil then return false end
    class[method] = function(self, ...) return fn(orig, self, ...) end
    return true
end

-- Takes a machine's world object off its square as the game's floor
-- transfer does (SRC ISTransferAction.lua:131-158).
function M.liftFromGround(item)
    local wi = item:getWorldItem()
    local sq = wi and wi:getSquare()
    if sq == nil then return false end
    if DesignationZoneAnimal and DesignationZoneAnimal.removeItemFromGround then
        DesignationZoneAnimal.removeItemFromGround(wi)
    end
    sq:transmitRemoveItemFromSquare(wi)
    sq:removeWorldObject(wi)
    item:setWorldItem(nil)
    return true
end

-- A mod error must never break the game's move itself.
local function account(fn, item)
    local ok, err = pcall(fn, item, World.now())
    if not ok then TLG.Log.error("machine move: %s", tostring(err)) end
end

-- The landing watch: a machine that left a character's hands where no Lua
-- hook saw where it went (a death, a climb) is looked at every tick until
-- it lies on the ground, then put down from that tick; after LANDING_TICKS
-- it is given up (it went into a container, a body's among them, and stays
-- carried). A hook that saw the move put it down already: its record no
-- longer says carried and its site is this tile, so nothing is written
-- twice.
M.landing = M.landing or {}
M.LANDING_TICKS = 300

local function landed(item, now)
    local rec, sq = M.read(item, false), M.square(item)
    if rec == nil or sq == nil then return end
    if rec.pause == "not_placed" or rec.site == nil or M.movedFrom(rec, sq) then M.putDown(item, now) end
end

local function watchLandings()
    local keep = {}
    for _, w in ipairs(M.landing) do
        w.ticks = w.ticks + 1
        local ok, placed = pcall(M.isPlaced, w.item)
        if not ok then
            TLG.Log.error("machine move: %s", tostring(placed))
        elseif placed then
            account(landed, w.item)
        elseif w.ticks < M.LANDING_TICKS then
            keep[#keep + 1] = w
        end
    end
    M.landing = keep
    if #keep == 0 then
        Events.OnTick.Remove(watchLandings)
        M.watching = false
    end
end

-- Watches a machine until it lands (from the start again if already watched).
function M.watchLanding(item)
    for _, w in ipairs(M.landing) do
        if w.item == item then
            w.ticks = 0
            return
        end
    end
    M.landing[#M.landing + 1] = { item = item, ticks = 0 }
    if not M.watching then
        M.watching = true
        Events.OnTick.Add(watchLandings)
    end
end

-- A carrier's death in single player. The game drops a heavy item at the
-- body's feet where no Lua hook sees it (RT-SP runs 198-199), and the batch
-- stayed paused until the vessel was next read, losing the time between
-- (D-015 amendment). The machines in the dying character's hands are
-- watched until they land; should the drop come before the event (as
-- 42.21 does it, run 202), a machine at the feet whose record still says
-- carried is put down from the death. A dedicated server fires no death
-- event for a client's player (RT-MP run 209): there M.onHands sees the
-- drop.
function M.onDeath(character)
    if character == nil or not World.isAuthority() then return end
    local primary, secondary = character:getPrimaryHandItem(), character:getSecondaryHandItem()
    local held = {}
    if M.tracked(primary) then held[#held + 1] = primary end
    if secondary ~= primary and M.tracked(secondary) then held[#held + 1] = secondary end
    for _, it in ipairs(held) do
        if M.isPlaced(it) then
            account(M.putDown, it)
        else
            M.watchLanding(it)
        end
    end
    local sq = character:getSquare()
    local atFeet = 0
    if #held == 0 and sq ~= nil and getCell then
        for dx = -1, 1 do
            for dy = -1, 1 do
                local s = getCell():getGridSquare(sq:getX() + dx, sq:getY() + dy, sq:getZ())
                local objs = s and s:getWorldObjects()
                for i = 0, (objs and objs:size() or 0) - 1 do
                    local it = objs:get(i):getItem()
                    if M.tracked(it) then
                        local rec = M.read(it, false)
                        if rec and rec.pause == "not_placed" then
                            account(M.putDown, it)
                            atFeet = atFeet + 1
                        end
                    end
                end
            end
        end
    end
    if #held > 0 or atFeet > 0 then
        TLG.Log.info("a carrier died: %d machine(s) in the hands, %d already at the feet", #held, atFeet)
    end
end

-- Machines in characters' hands, on the authority: { [item] = character }.
-- On a dedicated server a client's player dies in Java, and no Lua event
-- tells the death, the body or the drop (RT-MP run 209; BC 42.21:
-- IsoPlayer.OnDeath returns at once on a server, IsoDeadBody fires
-- OnDeadBodySpawn only off one); IsoGameCharacter.die puts what the hands
-- held on the floor (dropHeldItems). What the server's Lua does see is the
-- hands emptying: setPrimaryHandItem and setSecondaryHandItem fire
-- OnEquipPrimary and OnEquipSecondary wherever they run, and every drop
-- empties the hands through them (dropHeldItems, dropHeavyItems,
-- removeFromHands). So the authority remembers a machine that enters a
-- hand, and one that has left both is watched until it lands. That also
-- covers a climb's drop (over a wall, through a window, on a sheet rope):
-- dropHeavyItems in single player, and on a server the dropHeldItems a
-- client's PlayerDropHeldItems asks for.
M.inHands = M.inHands or {}

function M.onHands(character, item)
    if character == nil or not World.isAuthority() then return end
    local tracked = M.tracked(item)
    if not tracked and Tables.isEmpty(M.inHands) then return end
    local primary, secondary = character:getPrimaryHandItem(), character:getSecondaryHandItem()
    local left = {}
    for held, who in pairs(M.inHands) do
        if who == character and held ~= primary and held ~= secondary then left[#left + 1] = held end
    end
    for _, held in ipairs(left) do
        M.inHands[held] = nil
        M.watchLanding(held)
    end
    if tracked and (item == primary or item == secondary) then M.inHands[item] = character end
end

-- The characters in the game: a server's connected players, else the local
-- ones.
local function charactersInGame()
    local out = {}
    if isServer() then
        local list = getOnlinePlayers()
        for i = 0, (list and list:size() or 0) - 1 do out[#out + 1] = list:get(i) end
    elseif getSpecificPlayer then
        for i = 0, (getNumActivePlayers and getNumActivePlayers() or 1) - 1 do
            local p = getSpecificPlayer(i)
            if p ~= nil then out[#out + 1] = p end
        end
    end
    return out
end

-- Every ten game minutes on the authority: the machines in the hands of the
-- characters in the game, for a hold no equip event told (a player loaded
-- holding one: IsoGameCharacter.load sets the hands directly, BC). One no
-- longer in its holder's hands is watched until it lands; one whose holder
-- left the server is forgotten.
function M.censusHands()
    if not World.isAuthority() then return end
    local present = {}
    for _, p in ipairs(charactersInGame()) do
        present[p] = true
        local primary, secondary = p:getPrimaryHandItem(), p:getSecondaryHandItem()
        if M.tracked(primary) then M.inHands[primary] = p end
        if M.tracked(secondary) then M.inHands[secondary] = p end
    end
    local gone, left = {}, {}
    for item, who in pairs(M.inHands) do
        if isServer() and not present[who] then
            gone[#gone + 1] = item
        elseif who:getPrimaryHandItem() ~= item and who:getSecondaryHandItem() ~= item then
            left[#left + 1] = item
        end
    end
    for _, item in ipairs(gone) do M.inHands[item] = nil end
    for _, item in ipairs(left) do
        M.inHands[item] = nil
        M.watchLanding(item)
    end
end

-- The machine carried in both arms (the fermentation vessel, drawn there
-- by its own carry pose, D-025), or nil.
function M.carriedInArms(character)
    if character == nil then return nil end
    local item = character:getPrimaryHandItem() or character:getSecondaryHandItem()
    if item and M.machineFor(item) and item:isForceDropHeavyItem() then return item end
    return nil
end

-- Puts the carried machine down at the character's feet as the vehicle
-- entry does (SRC ISEnterVehicle.lua:55-61): forceDropHeavyItems, or from a
-- multiplayer client the server's command for it.
function M.putDownForAction(character)
    if isClient() then
        sendClientCommand(character, "player", "onDropHeavyItem", { id = character:getOnlineID() })
    else
        forceDropHeavyItems(character)
    end
end

-- How far from a machine the server lets a character take it off the floor:
-- the machines' requests' reach (MachineHandlers).
M.TAKE_REACH = 2.5

-- A machine taken into both arms on a dedicated server (D-030). There 42.21's
-- ISEquipHeavyItem.complete cannot take an item off the floor (RT-MP runs
-- 140-145; vanilla's meteorite too, without the mod, run 144): the server
-- looks up the item the loot window named among the square's world objects
-- and lists it in a floor container of its own without adding it (BC
-- ContainerID.collectFloorItems appends IsoWorldInventoryObject.getItem()),
-- so the item has no container and that complete fails at its line 63.
-- For the mod's machines (the fermentation vessel is the one carried in both
-- arms) the server does that complete's work itself: any heavy item in hand
-- put down first, the world object taken off its square as the floor
-- transfer takes it, the item into the inventory and both hands, the clients
-- told as that complete tells them (sendAddItemToContainer, sendEquip). The
-- batch is accounted before the item is sent, so the carried record goes
-- with it. Returns true when taken; false when refused (the action is
-- rejected): already in another character's inventory (two players took it
-- off the floor at once and the other's action completed first; vanilla's
-- complete would take it from them), on no square, or out of reach; nil
-- when vanilla's complete applies (the machine in a container).
function M.takeOnServer(character, item)
    if item:getContainer() ~= nil then
        local outer = item:getOutermostContainer()
        local holder = outer and outer:getParent()
        if holder ~= nil and holder ~= character and instanceof(holder, "IsoGameCharacter") then return false end
        return nil
    end
    local sq, at = M.square(item), character:getSquare()
    if sq == nil or at == nil or at:DistToProper(sq) > M.TAKE_REACH then return false end
    forceDropHeavyItems(character)
    M.liftFromGround(item)
    if M.tracked(item) then account(M.pickedUp, item) end
    local inv = character:getInventory()
    inv:AddItem(item)
    sendAddItemToContainer(inv, item)
    character:setPrimaryHandItem(item)
    character:setSecondaryHandItem(item)
    sendEquip(character)
    return true
end

-- The moves the game's Lua makes (SRC 42.21), accounted on the authority:
-- the world menu's Grab (ISGrabItemAction.transferItem, given the world
-- object; single player only: in multiplayer the server grabs in a Java
-- item transaction), every transfer to or from the floor
-- (ISTransferAction.transferItem: the loot window's Grab, the inventory
-- menu's Drop, the server's dropOnFloor transaction) and the place cursor's
-- action (ISDropWorldItemAction.complete). A machine carried in both hands
-- (the fermentation vessel: Tags base:heavyitem) is also taken into both
-- hands by ISEquipHeavyItem.complete (the loot and inventory windows' take,
-- from the floor too) and put down at the character's feet by
-- ISUnequipAction.complete, for any reason but drop or place (SRC
-- ISUnequipAction.lua:134: the menus unequip the hands first when another
-- heavy item or a generator is taken or a weapon equipped), and by
-- forceDropHeavyItems (SRC ISEquipWeaponAction.lua:75: when a vehicle is
-- entered, an animal handled, a trap set). Told apart by whether the item
-- lies on the ground before and after, not by container types. On a
-- dedicated server a machine is taken into both hands by M.takeOnServer
-- instead of that complete, which fails there for an item on the floor.
-- The mod adds one put-down: an action that plays its own animation
-- (ISBaseTimedAction.setActionAnim: looting, dressing, eating, the mod's
-- work action) replaces the vessel's carry pose on the arms' layer
-- (RT-SP run 96), so the vessel goes down at the feet first (D-025
-- amendment). The game keeps a carried generator in both hands through
-- such actions, undrawn (run 99). Not for an action on the vessel itself:
-- its unequip (which puts it down when it completes) and the transfers
-- that move it.
function M.install()
    wrap(ISGrabItemAction, "transferItem", function(orig, self, witem, ...)
        local item = World.isAuthority() and witem and witem.getItem and witem:getItem() or nil
        local r = orig(self, witem, ...)
        if M.tracked(item) and not M.isPlaced(item) then account(M.pickedUp, item) end
        return r
    end)
    wrap(ISTransferAction, "transferItem", function(orig, self, character, item, ...)
        local tracked = World.isAuthority() and M.tracked(item)
        local was = tracked and M.isPlaced(item)
        local r = orig(self, character, item, ...)
        if tracked then
            local placed = M.isPlaced(item)
            if was and not placed then
                account(M.pickedUp, item)
            elseif placed and not was then
                account(M.putDown, item)
            end
        end
        return r
    end)
    wrap(ISDropWorldItemAction, "complete", function(orig, self, ...)
        local item = World.isAuthority() and M.tracked(self.item) and self.item or nil
        local r = orig(self, ...)
        if item and M.isPlaced(item) then account(M.putDown, item) end
        return r
    end)
    wrap(ISEquipHeavyItem, "complete", function(orig, self, ...)
        local item = World.isAuthority() and self.item and M.machineFor(self.item) and self.item or nil
        if item and isServer() then
            local taken = M.takeOnServer(self.character, item)
            if taken ~= nil then return taken end
        end
        local was = item and M.isPlaced(item)
        local r = orig(self, ...)
        if was then
            -- 42.21 takes the item off the loot window's floor container and
            -- into both hands but leaves its world object on the square
            -- (sendRemoveItemFromContainer acts only in multiplayer, BC):
            -- vanilla's meteorite stays behind the same way (RT-SP runs
            -- 77-78). A machine is taken off the ground as the floor
            -- transfer takes an item, whether or not it has a record yet.
            local inv = self.character and self.character:getInventory()
            if M.isPlaced(item) and inv and inv:contains(item) then
                local ok, err = pcall(M.liftFromGround, item)
                if not ok then TLG.Log.error("machine move: %s", tostring(err)) end
            end
            if M.tracked(item) and not M.isPlaced(item) then account(M.pickedUp, item) end
        end
        return r
    end)
    -- Called on every unequip, clothing too: the record is checked first.
    wrap(ISUnequipAction, "complete", function(orig, self, ...)
        local item = World.isAuthority() and M.tracked(self.item) and self.item or nil
        local was = item and M.isPlaced(item)
        local r = orig(self, ...)
        if item and not was and M.isPlaced(item) then account(M.putDown, item) end
        return r
    end)
    -- Wrapped like the generators' (Generators.lua); the two compose.
    if forceDropHeavyItems then
        local origDrop = forceDropHeavyItems
        forceDropHeavyItems = function(character, ...)
            local held = {}
            if character and World.isAuthority() then
                local primary, secondary = character:getPrimaryHandItem(), character:getSecondaryHandItem()
                if M.tracked(primary) and not M.isPlaced(primary) then held[#held + 1] = primary end
                if secondary ~= primary and M.tracked(secondary) and not M.isPlaced(secondary) then
                    held[#held + 1] = secondary
                end
            end
            local r = origDrop(character, ...)
            for _, it in ipairs(held) do
                if M.isPlaced(it) then account(M.putDown, it) end
            end
            return r
        end
    end
    if Events and Events.OnPlayerDeath then Events.OnPlayerDeath.Add(M.onDeath) end
    -- The hands, for the drops no hook above sees (M.onHands).
    local function onHands(character, item)
        local ok, err = pcall(M.onHands, character, item)
        if not ok then TLG.Log.error("machine move: %s", tostring(err)) end
    end
    if Events and Events.OnEquipPrimary then Events.OnEquipPrimary.Add(onHands) end
    if Events and Events.OnEquipSecondary then Events.OnEquipSecondary.Add(onHands) end
    -- Derived actions look the method up at call time.
    wrap(ISBaseTimedAction, "setActionAnim", function(orig, self, ...)
        local ok, err = pcall(function()
            local held = M.carriedInArms(self.character)
            if held and self.item ~= held then M.putDownForAction(self.character) end
        end)
        if not ok then TLG.Log.error("machine move: %s", tostring(err)) end
        return orig(self, ...)
    end)
    TLG.Log.info("machine move hooks installed")
end

return M
