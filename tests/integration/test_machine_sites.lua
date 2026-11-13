require "support/fixtures"
require "TLG/Integration/Machines"
require "TLG/Util/Rng"
local Machines, World, Process = TLG.Integration.Machines, TLG.World, TLG.Domain.Process

-- A note has only the fields the vault digests (Vault.NOTE_FIELDS): one with
-- another would read as forged after every restart (audit V-01).
local function noteFieldsKnown(note)
    local known = {}
    for _, f in ipairs(TLG.Authority.Vault.NOTE_FIELDS) do known[f] = true end
    for f in pairs(note) do T.ok(known[f], "note field " .. tostring(f) .. " is one the vault digests") end
end

-- Stand-ins for the game calls the machine site adapter makes: global ModData,
-- the clock, the cell's squares, the air temperature per square and outdoors,
-- the daylight, grid power and the fire objects' classes. Installed for one
-- case and removed again (the domain suite runs without them).
local GLOBALS = { "ModData", "getGameTime", "getCell", "getClimateManager", "isServer", "isClient", "getWorld",
    "instanceof" }

local function fakeGame(now)
    local saved = {}
    for _, k in ipairs(GLOBALS) do saved[k] = _G[k] end
    local g = { now = now, squares = {}, store = {}, outC = -3, dl = 0.5, power = false }
    ModData = { getOrCreate = function(k)
        g.store[k] = g.store[k] or {}
        return g.store[k]
    end }
    local clock = {}
    function clock:getWorldAgeHours() return g.now end
    getGameTime = function() return clock end
    local cell = {}
    function cell:getGridSquare(x, y, z) return g.squares[x .. "," .. y .. "," .. z] end
    getCell = function() return cell end
    local cm, values, world = {}, {}, {}
    function cm:getAirTemperatureForSquare(sq) return sq.air end
    function cm:getTemperature() return g.outC end
    function values:getDayLightLagged() return g.dl end
    function cm:getClimateValuesCopy() return values end
    getClimateManager = function() return cm end
    function world:isHydroPowerOn() return g.power end
    getWorld = function() return world end
    instanceof = function(o, class) return type(o) == "table" and o.class == class end
    isServer = function() return false end
    isClient = function() return false end
    local md = World.get()
    md.v, md.calendar, md.climateLog = 1, { dayOfYear = 15, hourOfDay = 0 }, { [0] = { t = -3, rh = 0.7 } }
    function g.restore()
        for _, k in ipairs(GLOBALS) do _G[k] = saved[k] end
    end
    return g
end

-- A square with world objects (machines are items on it, D-015) and other
-- objects (fires).
local function square(g, x, y, z, room, air)
    local sq = { x = x, y = y, z = z, room = room, air = air, objs = {}, fires = {} }
    function sq:getX() return self.x end
    function sq:getY() return self.y end
    function sq:getZ() return self.z end
    function sq:isInARoom() return self.room end
    function sq:DistToProper(o)
        local dx, dy = self.x - o.x, self.y - o.y
        return math.sqrt(dx * dx + dy * dy)
    end
    local list, others = {}, {}
    function list:size() return #sq.objs end
    function list:get(i) return sq.objs[i + 1] end
    function sq:getWorldObjects() return list end
    function sq:transmitRemoveItemFromSquare(o) self.transmitted = (self.transmitted or 0) + 1 end
    function sq:removeWorldObject(o)
        for i = #self.objs, 1, -1 do
            if self.objs[i] == o then table.remove(self.objs, i) end
        end
    end
    function others:size() return #sq.fires end
    function others:get(i) return sq.fires[i + 1] end
    function sq:getObjects() return others end
    g.squares[x .. "," .. y .. "," .. z] = sq
    return sq
end

-- A fire on a square as the notes see it: IsoFireplace or IsoBarbecue.
local function fireOn(sq, class, lit, fuel)
    local o = { class = class, lit = lit, fuel = fuel }
    function o:isLit() return self.lit end
    function o:getFuelAmount() return self.fuel end
    sq.fires[#sq.fires + 1] = o
    return o
end

-- A campfire a player built (SCampfireSystem): the object named "Campfire"
-- holding its fuel in mod data, and the permanent IsoFire it keeps lit,
-- whose light radius is its heat radius.
local function campfireOn(sq, fuel, exterior, radius)
    local camp, md = { class = "IsoObject" }, { fuelAmt = fuel, isLit = true, exterior = exterior }
    function camp:getName() return "Campfire" end
    function camp:getModData() return md end
    local flame = { class = "IsoFire", radius = radius }
    function flame:isPermanent() return true end
    function flame:getLightRadius() return self.radius end
    sq.fires[#sq.fires + 1] = camp
    sq.fires[#sq.fires + 1] = flame
    return md
end

local function machine(sq, rec)
    local item, wi, md = {}, {}, { tlgProc = rec }
    function wi:getSquare() return item.on end
    function wi:getItem() return item end
    function item:getFullType() return "TLG.FermenterVessel" end
    function item:getModData() return md end
    function item:getWorldItem() return item.on and wi or nil end
    function item:setWorldItem(w) if w == nil then item.on = nil end end
    function item:getID() return 7 end
    function item:getOutermostContainer() return item.outer end
    item.on, item.wi = sq, wi
    if sq then sq.objs[#sq.objs + 1] = wi end
    return item
end

-- Moves as the game makes them: off the ground into a container, or onto a
-- square (the same item, its world object on the square's list).
local function lift(item)
    local sq = item.on
    for i = #(sq and sq.objs or {}), 1, -1 do
        if sq.objs[i] == item.wi then table.remove(sq.objs, i) end
    end
    item.on = nil
end

local function place(item, sq)
    lift(item)
    item.on = sq
    sq.objs[#sq.objs + 1] = item.wi
end

-- Stage hours done on the batch (ethanol_ferment: preparing 1 h, then 96 h).
local function work(rec)
    local done = 0
    for i, st in ipairs(rec.recipe.params.stages) do
        if i < rec.stage then done = done + st.hours elseif i == rec.stage then done = done + rec.stageDone end
    end
    return done
end

-- A warm day 0 (22 C outdoors, no readings needed): every placed hour is a
-- full stage hour.
local function warmDay(g)
    g.outC = 22
    World.get().climateLog = { [0] = { t = 22, rh = 0.7 } }
    return World.env()
end

local function running(id, t)
    local f = Process.new({ id = id, machine = "fermenter_barrel", t = t })
    f = Process.load(f, "ethanol_ferment", { sugar_eq = 6, water = 30 }).proc
    return Process.start(f, t).proc
end

-- A batch started at 2 on `sq`, accessed once (site, seen, hourly list).
local function startedOn(sq, id, env)
    local item = machine(sq, running(id, 2))
    local rec = Machines.advance(item, Machines.read(item, false), 2, env)
    Machines.write(item, rec)
    Machines.index(item, rec)
    return item
end

T.case("integration: the hourly reading files the air at each loaded, placed, running machine", function()
    local g = fakeGame(2)
    local ok, err = pcall(function()
        local warm = square(g, 1, 1, 0, true, 21.5)
        local item = machine(warm, running("P1", 2))
        local idle = machine(square(g, 2, 1, 0, false, -4), Process.new({ id = "P2", machine = "fermenter_barrel", t = 2 }))
        Machines.index(item, Machines.read(item, false))
        Machines.index(idle, Machines.read(idle, false))
        g.now = 10.02
        Machines.sampleSites()
        local rec = item:getModData().tlgProc
        T.eq(rec.temps[9], 21.5, "filed under the hour that just ended")
        T.eq(rec.site.room, true); T.eq(rec.site.z, 0)
        T.ok(idle:getModData().tlgProc.temps == nil, "no batch, no reading")
        -- Unloaded square: skipped, still listed. Machine gone: dropped.
        g.squares["1,1,0"] = nil
        g.now = 11.01
        Machines.sampleSites()
        T.ok(rec.temps[10] == nil and World.get().machineSites.P1 ~= nil)
        g.squares["1,1,0"] = warm
        warm.objs = {}
        Machines.sampleSites()
        T.ok(World.get().machineSites.P1 == nil, "a loaded square without the machine drops it")
        T.ok(World.get().machineSites.P2 ~= nil)
    end)
    g.restore()
    if not ok then error(err, 0) end
end)

T.case("integration: an access records the site and keeps only the readings still needed", function()
    local g = fakeGame(30)
    local ok, err = pcall(function()
        local sq = square(g, 5, 5, 1, true, 12)
        local rec = running("P3", 2)
        rec.temps = { [3] = 20, [22] = 21, [23] = 19, [26] = 18, [29] = 17 }
        local item = machine(sq, rec)
        local env = World.env()
        local out = Machines.advance(item, Machines.read(item, false), 30, env)
        T.eq(out.site.room, true); T.eq(out.site.z, 1)
        T.ok(out.temps[3] == nil and out.temps[22] == nil, "day 0 is behind the batch")
        T.eq(out.temps[23], 19, "kept: it stands in for the first hour of day 1 (run 18)")
        T.eq(out.temps[26], 18); T.eq(out.temps[29], 17)
        local early = Machines.advance(item, Machines.read(item, false), 24.5, env)
        T.eq(early.temps[23], 19)
        T.near((Machines.siteTemp(item, early, 24.5, env)), 19, 1e-9, "just after midnight: yesterday's last hour")
        local c, now, kind = Machines.siteTemp(item, out, 30, env)
        T.near(c, (18 + 17 + 4 * env:siteBase(1, out.site)) / 6, 1e-9, "today so far: two readings, four hours at the base")
        T.eq(now, false); T.eq(kind, "room_upper")
        out.state, out.temps = "Ready", nil
        local air, isNow = Machines.siteTemp(item, out, 30, env)
        T.eq(air, 12); T.eq(isNow, true)
        item.on = nil
        T.ok(Machines.siteTemp(item, out, 30, env) == nil, "not placed: no site temperature")
        local done = Machines.advance(item, rec, 30, env)
        T.eq(done.pause, "not_placed")
    end)
    g.restore()
    if not ok then error(err, 0) end
end)

T.case("integration: every ten minutes the fire warming a machine is noted with its fuel", function()
    local g = fakeGame(2)
    local ok, err = pcall(function()
        local Climate = TLG.Domain.Climate
        local t0 = Climate.roomAir(-3, false, 0.5, false)
        local sq = square(g, 10, 10, 0, true, t0)
        local item = machine(sq, running("P4", 2))
        Machines.index(item, Machines.read(item, false))
        local hearth = fireOn(square(g, 11, 12, 0, true, 0), "IsoFireplace", true, 365)
        fireOn(square(g, 10, 13, 0, true, 0), "IsoFireplace", false, 480)
        local bbq = fireOn(square(g, 8, 10, 0, false, 0), "IsoBarbecue", true, 100)
        sq.air = Climate.warmed(t0, 1, 2, 8, true, 35)
        g.now = 10.83
        Machines.observeFires()
        local note = item:getModData().tlgProc.fires[10]
        T.eq(note.f, 365); T.eq(note.x, 1); T.eq(note.y, 2); T.eq(note.r, true); T.eq(note.c, 35)
        T.near(note.t, 10.83, 1e-12); T.ok(note.rad == nil, "a fireplace's radius follows its fuel")
        noteFieldsKnown(note)
        T.eq(item:getModData().tlgProc.site.room, true)
        -- The hearth out, the barbecue gives the air: its note has a fixed radius.
        hearth.lit = false
        sq.air = Climate.warmed(t0, -2, 0, 3, false, 25)
        g.now = 11.0
        Machines.observeFires()
        note = item:getModData().tlgProc.fires[11]
        T.eq(note.c, 25); T.eq(note.rad, 3); T.eq(note.f, 100); T.eq(note.r, false); T.eq(note.x, -2)
        noteFieldsKnown(note)
        -- Nothing warms it: false, the hour's last note wins, noted once an
        -- hour; the time it was found placed is kept every ten minutes.
        bbq.lit = false
        sq.air = t0
        g.now = 11.17
        Machines.observeFires()
        T.eq(item:getModData().tlgProc.fires[11], false)
        local writes, quiet, write = 0, nil, Machines.write
        Machines.write = function(it, r, q)
            writes, quiet = writes + 1, q
            return write(it, r, q)
        end
        g.now = 11.33
        Machines.observeFires()
        Machines.write = write
        T.eq(writes, 1); T.eq(quiet, true, "kept on the authority, not sent")
        T.eq(item:getModData().tlgProc.fires[11], false, "the hour's note as it was")
        T.eq(item:getModData().tlgProc.seen, 11.33, "found placed at 11.33")
        -- Warmer than the room by a heat source that is no fire it knows: false.
        sq.air = t0 + 5
        g.now = 12.0
        Machines.observeFires()
        T.eq(item:getModData().tlgProc.fires[12], false)
        -- Not loaded: skipped.
        g.squares["10,10,0"] = nil
        g.now = 13.5
        Machines.observeFires()
        T.ok(item:getModData().tlgProc.fires[13] == nil)
        -- The status credits the last note before an absence: hour 10's, had it stood last.
        local rec = Machines.read(item, false)
        rec.fires = { [10] = { t = 10.83, f = 365, x = 1, y = 2, r = true, c = 35 } }
        rec.temps = { [9] = 20 }
        local env = World.env()
        local base = env:siteBase(0, rec.site)
        local w8, w7 = Climate.warmed(base, 1, 2, 8, true, 35), Climate.warmed(base, 1, 2, 7, true, 35)
        local stop = 10.83 + 365 / 60
        local c = Machines.siteTemp(item, rec, 23, env)
        T.near(c, (7 * base + 20 + 6 * w8 + (stop - 16) * w7 + (23 - stop) * base) / 21, 1e-9,
            "from the batch start at 2: hours 2-8 at the base, 9 read, warm from 10 to 16.9 (radius 7 in its last hour)")
        -- An access keeps the latest note before its day; a finished batch drops them.
        rec.fires[3] = false
        local out = Machines.advance(item, rec, 30, env)
        T.ok(out.fires[3] == nil and out.fires[10] ~= nil, "the latest note before day 1 stays")
        out.state = "Ready"
        Machines.trimTemps(out, env)
        T.ok(out.fires == nil and out.temps == nil)
    end)
    g.restore()
    if not ok then error(err, 0) end
end)

T.case("integration: a campfire a player built is noted with its fuel and largest radius", function()
    local g = fakeGame(2)
    local ok, err = pcall(function()
        local Climate = TLG.Domain.Climate
        local sq = square(g, 10, 10, 0, false, -3)
        local item = machine(sq, running("P5", 2))
        Machines.index(item, Machines.read(item, false))
        -- Nine tiles away, past a fireplace's reach, with 397 minutes of fuel
        -- (radius 10; RT-SP run 34's last note before its trip).
        local cs = square(g, 19, 10, 0, false, 0)
        local md = campfireOn(cs, 397, true, 10)
        sq.air = Climate.warmed(-3, 9, 0, 10, false, 35)
        g.now = 10.5
        Machines.observeFires()
        local note = item:getModData().tlgProc.fires[10]
        T.eq(note.k, "campfire"); T.eq(note.rmax, 10); T.eq(note.f, 397); T.eq(note.c, 35)
        T.eq(note.x, 9); T.eq(note.y, 0); T.eq(note.r, false)
        T.ok(note.rad == nil, "its radius follows its fuel"); T.near(note.t, 10.5, 1e-12)
        noteFieldsKnown(note)
        -- Built inside: up to 18 tiles.
        md.exterior = false
        g.now = 11.0
        Machines.observeFires()
        T.eq(item:getModData().tlgProc.fires[11].rmax, 18)
        -- The flame without its campfire (another open fire): no fuel to count.
        table.remove(cs.fires, 1)
        g.now = 12.0
        Machines.observeFires()
        T.eq(item:getModData().tlgProc.fires[12], false)
    end)
    g.restore()
    if not ok then error(err, 0) end
end)

-- The fire scan and the trim as they were before docs/performance.md's fix
-- (each machine's reach scanned on its own; both key sets sorted on every
-- trim). The fixed code must leave every record exactly as these did.
local function oldWarmingFire(sq, air, now)
    local Climate = TLG.Domain.Climate
    if air == nil then return nil end
    local t0 = Machines.unwarmedAt(sq)
    if air <= t0 + Machines.FIRE_TOL then return nil end
    local x, y, z, cell, best = sq:getX(), sq:getY(), sq:getZ(), getCell(), nil
    local reach = Climate.FIRE_REACH
    for dx = -reach, reach do
        for dy = -reach, reach do
            local s = dx * dx + dy * dy < reach * reach and cell:getGridSquare(x + dx, y + dy, z) or nil
            local objs = s and s:getObjects()
            for i = 0, (objs and objs:size() or 0) - 1 do
                local fire = Machines.fireOf(objs:get(i), s)
                if fire then
                    local srcRoom = false
                    pcall(function() srcRoom = s:isInARoom() == true end)
                    local w = Climate.warmed(t0, dx, dy, fire.radius, srcRoom, fire.c)
                    if math.abs(w - air) <= Machines.FIRE_TOL and (best == nil or fire.f > best.f) then
                        best = { t = now, f = fire.f, x = dx, y = dy, r = srcRoom, c = fire.c, rad = fire.rad,
                            k = fire.k, rmax = fire.rmax }
                    end
                end
            end
        end
    end
    return best
end

local function oldTrim(rec, env)
    local Climate, Tables = TLG.Domain.Climate, TLG.Tables
    if rec.state ~= "Processing" and rec.state ~= "Paused" then
        rec.temps, rec.fires = nil, nil
        return
    end
    local cut = math.floor(env:dayStart(env:dayIndex(rec.t))) - 1
    if rec.temps ~= nil then
        Climate.pruneSlots(rec.temps, cut)
        local keys = Tables.sortedKeys(rec.temps)
        if #keys > Machines.MAX_READINGS then Climate.pruneSlots(rec.temps, keys[#keys - Machines.MAX_READINGS + 1]) end
    end
    if rec.fires ~= nil then
        Climate.pruneNotes(rec.fires, cut)
        local keys = Tables.sortedKeys(rec.fires)
        if #keys > Machines.MAX_READINGS then Climate.pruneNotes(rec.fires, keys[#keys - Machines.MAX_READINGS + 1]) end
    end
end

-- The air a fire on `fsq` gives a machine on `sq` (as Machines.fireOf reads it).
local function warmthFrom(fsq, sq, t0)
    local Climate, air = TLG.Domain.Climate, nil
    local objs = fsq:getObjects()
    for i = 0, objs:size() - 1 do
        local f = Machines.fireOf(objs:get(i), fsq)
        if f then air = Climate.warmed(t0, fsq.x - sq.x, fsq.y - sq.y, f.radius, fsq:isInARoom() == true, f.c) end
    end
    return air
end

T.case("integration: trimming a record keeps exactly the readings and notes sorting them kept", function()
    local g = fakeGame(2)
    local ok, err = pcall(function()
        local r = TLG.Rng.new(TEST_SEED or 20261030)
        local env = World.env()
        local over = 0
        for trial = 1, 80 do
            local rec = running("R" .. trial, 2)
            rec.t = 100 + r:int(0, 400) + r:next()
            rec.state = ({ "Processing", "Paused", "Processing", "OutputReady" })[r:int(1, 4)]
            rec.temps, rec.fires = {}, {}
            local back = ({ 0, 0, 0, 30, 300 })[r:int(1, 5)]
            local step = r:int(1, 2)
            local h = math.floor(rec.t) - back
            for _ = 1, ({ 0, 3, 479, 480, 481, 482, 487, 488, 489, 700 })[r:int(1, 10)] do
                h = h + step
                rec.temps[h] = r:next() * 30
            end
            h = math.floor(rec.t) - back
            for _ = 1, ({ 0, 2, 480, 481, 482, 483, 488, 489, 600 })[r:int(1, 9)] do
                h = h + step
                rec.fires[h] = r:next() < 0.5 and false or { t = h + 0.5, f = r:int(0, 600), x = 1, y = 2, r = false, c = 35 }
            end
            if r:int(0, 9) == 0 then rec.fires = nil end
            if TLG.Tables.count(rec.temps) > Machines.MAX_READINGS then over = over + 1 end
            local a, b = TLG.Tables.deepCopy(rec), TLG.Tables.deepCopy(rec)
            oldTrim(a, env)
            Machines.trimTemps(b, env)
            T.ok(TLG.Tables.deepEqual(a.temps, b.temps, 0) and TLG.Tables.deepEqual(a.fires, b.fires, 0),
                string.format("trial %d: %d readings, %d notes left", trial, TLG.Tables.count(a.temps or {}),
                    TLG.Tables.count(a.fires or {})))
        end
        T.ok(over > 10, "records over the limit: " .. over)
    end)
    g.restore()
    if not ok then error(err, 0) end
end)

T.case("integration: one scan for all machines notes exactly the fire each machine's own scan found", function()
    local g = fakeGame(2)
    local ok, err = pcall(function()
        local Climate = TLG.Domain.Climate
        local r = TLG.Rng.new(TEST_SEED or 20261030)
        local noted, compared = 0, 0
        for trial = 1, 12 do
            g.squares = {}
            World.get().machineSites = {}
            local fires, machines = {}, {}
            local function addMachine(x, y, room)
                local sq = square(g, x, y, 0, room, 0)
                local item = machine(sq, running("T" .. trial .. "M" .. #machines, 2))
                Machines.index(item, Machines.read(item, false))
                machines[#machines + 1] = { item = item, sq = sq }
                return sq
            end
            -- Fires on two floors in a 50-tile square: fireplaces lit and
            -- not (fuel from 30 to 300 minutes: radius 4 to 8), barbecues,
            -- campfires a player built.
            for k = 1, 16 do
                local z, x, y = (k % 5 == 0) and 1 or 0, r:int(0, 50), r:int(0, 50)
                local sq = g.squares[x .. "," .. y .. "," .. z] or square(g, x, y, z, r:int(0, 1) == 1, 0)
                local kind = r:int(1, 4)
                if kind <= 2 then
                    fireOn(sq, "IsoFireplace", r:int(0, 5) > 0, ({ 30, 59, 60, 120, 300 })[r:int(1, 5)])
                elseif kind == 3 then
                    fireOn(sq, "IsoBarbecue", true, r:int(1, 200))
                else
                    campfireOn(sq, r:int(30, 400), r:int(0, 1) == 1, r:int(2, 10))
                end
                fires[#fires + 1] = sq
            end
            -- Machines among them: warmed by one of the fires, warmer than
            -- the room by something else, or not warmed.
            for _ = 1, 10 do
                local x, y = r:int(0, 50), r:int(0, 50)
                if g.squares[x .. "," .. y .. ",0"] == nil then
                    local sq = addMachine(x, y, r:int(0, 1) == 1)
                    local t0 = Machines.unwarmedAt(sq)
                    local choice = r:int(1, 3)
                    sq.air = t0
                    if choice == 1 then sq.air = warmthFrom(fires[r:int(1, #fires)], sq, t0) or t0 end
                    if choice == 2 then sq.air = t0 + 5 end
                end
            end
            -- Ties, far from the rest: two lit fireplaces at the same distance
            -- with 300 and 100 minutes of fuel (both radius 8: the most fuel
            -- wins), and two with 120 each (the first the scan meets wins).
            local tie = addMachine(300, 300, false)
            fireOn(square(g, 302, 303, 0, false, 0), "IsoFireplace", true, 100)
            local more = square(g, 303, 302, 0, false, 0)
            fireOn(more, "IsoFireplace", true, 300)
            tie.air = warmthFrom(more, tie, Machines.unwarmedAt(tie))
            local even = addMachine(400, 400, false)
            local first = square(g, 397, 398, 0, false, 0)
            fireOn(first, "IsoFireplace", true, 120)
            fireOn(square(g, 398, 397, 0, false, 0), "IsoFireplace", true, 120)
            even.air = warmthFrom(first, even, Machines.unwarmedAt(even))
            -- The edge of the reach (17 and 5 tiles off: in; 18 off: not),
            -- and a fire on the floor above.
            local edge = addMachine(500, 500, false)
            local inside = square(g, 517, 505, 0, false, 0)
            campfireOn(inside, 400, false, 18)
            campfireOn(square(g, 482, 500, 0, false, 0), 400, false, 18)
            fireOn(square(g, 500, 501, 1, false, 0), "IsoFireplace", true, 300)
            edge.air = warmthFrom(inside, edge, Machines.unwarmedAt(edge))
            g.now = 10.5 + trial
            local want = {}
            for i, mm in ipairs(machines) do want[i] = oldWarmingFire(mm.sq, mm.sq.air, g.now) or false end
            Machines.observeFires()
            local hour = math.floor(g.now)
            for i, mm in ipairs(machines) do
                local got = mm.item:getModData().tlgProc.fires[hour]
                T.ok(TLG.Tables.deepEqual(got, want[i], 0), string.format("trial %d, machine %d", trial, i))
                compared = compared + 1
                if want[i] then noted = noted + 1 end
            end
            T.eq(want[#machines - 2].f, 300, "the most fuel wins a tie")
            T.eq(want[#machines - 1].x, -3, "the first the scan meets wins an even tie")
            T.eq(want[#machines].x, 17, "17 and 5 tiles off is within reach")
        end
        T.ok(noted > 30 and compared > 100, string.format("%d notes of %d machines", noted, compared))
    end)
    g.restore()
    if not ok then error(err, 0) end
end)

T.case("integration: a machine picked up counts up to that moment, waits while carried, starts again where put down", function()
    local g = fakeGame(2)
    local ok, err = pcall(function()
        local env = warmDay(g)
        local a, b = square(g, 1, 1, 0, false, 22), square(g, 4, 1, 0, false, 22)
        local item = startedOn(a, "P5", env)
        local rec = item:getModData().tlgProc
        T.eq(rec.site.x, 1); T.eq(rec.site.y, 1); T.eq(rec.seen, 2)
        lift(item)
        Machines.pickedUp(item, 5)
        rec = item:getModData().tlgProc
        T.near(work(rec), 3, 1e-9, "the 3 h it stood there count")
        T.eq(rec.state, "Paused"); T.eq(rec.pause, "not_placed"); T.eq(rec.t, 5); T.eq(rec.seen, 5)
        T.ok(World.get().machineSites.P5 == nil, "off the hourly list at once")
        local carried = Machines.advance(item, Machines.read(item, false), 7, env)
        T.near(work(carried), 3, 1e-9, "nothing while carried"); T.eq(carried.pause, "not_placed"); T.eq(carried.t, 7)
        Machines.write(item, carried)
        place(item, b)
        Machines.putDown(item, 8)
        rec = item:getModData().tlgProc
        T.eq(rec.state, "Processing"); T.ok(rec.pause == nil); T.eq(rec.t, 8); T.eq(rec.site.x, 4); T.eq(rec.seen, 8)
        T.eq(World.get().machineSites.P5.x, 4, "listed at the new tile at once")
        local later = Machines.advance(item, Machines.read(item, false), 10, env)
        T.near(work(later), 5, 1e-9, "3 h before the pickup and 2 h since, none of the 3 h carried")
        -- Picked up again, then a second pickup event while carried: no change.
        lift(item)
        Machines.write(item, later)
        Machines.pickedUp(item, 11)
        Machines.pickedUp(item, 12)
        rec = item:getModData().tlgProc
        T.near(work(rec), 6, 1e-9); T.eq(rec.t, 11, "the second pickup finds it carried")
    end)
    g.restore()
    if not ok then error(err, 0) end
end)

T.case("integration: a move no Lua saw counts only up to the last time the machine was found placed", function()
    local g = fakeGame(2)
    local ok, err = pcall(function()
        local env = warmDay(g)
        local a, b = square(g, 1, 1, 0, false, 22), square(g, 4, 1, 0, false, 22)
        -- Found placed at 4.5 (the ten-minute note); lifted unseen; read while carried.
        local c = startedOn(a, "P6", env)
        g.now = 4.5
        Machines.observeFires()
        T.eq(c:getModData().tlgProc.seen, 4.5, "stamped by the note")
        lift(c)
        local r = Machines.advance(c, Machines.read(c, false), 6, env)
        T.near(work(r), 2.5, 1e-9, "up to 4.5"); T.eq(r.state, "Paused"); T.eq(r.pause, "not_placed"); T.eq(r.t, 6)
        -- Lifted unseen, put down where the game's Lua sees it (the multiplayer case).
        local d = startedOn(a, "P7", env)
        g.now = 4.5
        Machines.observeFires()
        lift(d); place(d, b)
        Machines.putDown(d, 7)
        r = d:getModData().tlgProc
        T.near(work(r), 2.5, 1e-9); T.eq(r.state, "Processing"); T.eq(r.t, 7); T.eq(r.site.x, 4)
        T.eq(World.get().machineSites.P7.x, 4)
        -- Neither move seen: found on another tile at the next access.
        local e = startedOn(a, "P8", env)
        g.now = 4.5
        Machines.sampleSites()
        T.eq(e:getModData().tlgProc.seen, 4.5, "stamped by the hourly reading")
        lift(e); place(e, b)
        r = Machines.advance(e, Machines.read(e, false), 8, env)
        T.near(work(r), 2.5, 1e-9, "nothing after 4.5"); T.eq(r.t, 8); T.eq(r.site.x, 4); T.eq(r.seen, 8)
        -- Carried after a seen pickup, put down unseen: from the next access.
        local f = startedOn(a, "P9", env)
        lift(f)
        Machines.pickedUp(f, 3)
        place(f, b)
        r = Machines.advance(f, Machines.read(f, false), 9, env)
        T.near(work(r), 1, 1e-9); T.eq(r.state, "Processing"); T.eq(r.t, 9); T.eq(r.site.x, 4)
    end)
    g.restore()
    if not ok then error(err, 0) end
end)

T.case("integration: older records, finished batches and paused ones around a pickup", function()
    local g = fakeGame(2)
    local ok, err = pcall(function()
        local env = warmDay(g)
        local a, b = square(g, 1, 1, 0, false, 22), square(g, 4, 1, 0, false, 22)
        -- No seen time: nothing beyond the last access (the old rule).
        local old = machine(a, running("P10", 2))
        lift(old)
        local r = Machines.advance(old, Machines.read(old, false), 6, env)
        T.near(work(r), 0, 1e-9); T.eq(r.pause, "not_placed")
        -- A site without its tile cannot tell a move: counted as before.
        local tileless = machine(b, running("P11", 2))
        tileless:getModData().tlgProc.site = { room = false, z = 0 }
        r = Machines.advance(tileless, Machines.read(tileless, false), 6, env)
        T.near(work(r), 4, 1e-9); T.eq(r.site.x, 4)
        -- A batch that finishes before the pickup is not marked carried.
        local done = startedOn(a, "P12", env)
        local rec = done:getModData().tlgProc
        rec.stage, rec.stageDone = 2, 95.5
        lift(done)
        Machines.pickedUp(done, 3)
        rec = done:getModData().tlgProc
        T.eq(rec.state, "OutputReady"); T.ok(rec.pause == nil)
        -- Paused by the player: still paused once put down again.
        local held = startedOn(a, "P13", env)
        rec = held:getModData().tlgProc
        rec.state, rec.pause, rec.manualPause = "Paused", "paused_by_player", true
        lift(held)
        Machines.pickedUp(held, 4)
        T.eq(held:getModData().tlgProc.pause, "not_placed")
        place(held, b)
        Machines.putDown(held, 5)
        r = Machines.advance(held, Machines.read(held, false), 6, env)
        T.eq(r.state, "Paused"); T.eq(r.pause, "paused_by_player"); T.near(work(r), 0, 1e-9)
    end)
    g.restore()
    if not ok then error(err, 0) end
end)

T.case("integration: the game's Grab, floor transfers and place action account a machine's moves", function()
    local g = fakeGame(2)
    local names = { "ISGrabItemAction", "ISTransferAction", "ISDropWorldItemAction" }
    local saved = {}
    for _, k in ipairs(names) do saved[k] = _G[k] end
    local ok, err = pcall(function()
        local env = warmDay(g)
        local a, b = square(g, 1, 1, 0, false, 22), square(g, 4, 1, 0, false, 22)
        -- What the vanilla methods do to the item (SRC 42.21), with their
        -- signatures: Grab gets the world object, the transfer is called on
        -- the class with the character, the place action keeps item and square.
        ISGrabItemAction = { transferItem = function(self, witem) lift(witem:getItem()) end }
        ISTransferAction = { transferItem = function(self, character, item, src, dest, dropSquare)
            if dropSquare then place(item, dropSquare) else lift(item) end
            return item
        end }
        ISDropWorldItemAction = { complete = function(self)
            place(self.item, self.sq)
            return true
        end }
        Machines.install()
        local item = startedOn(a, "P14", env)
        g.now = 4
        local grab = setmetatable({}, { __index = ISGrabItemAction })
        grab:transferItem(item:getWorldItem())
        local rec = item:getModData().tlgProc
        T.near(work(rec), 2, 1e-9, "Grab: counted to the pickup"); T.eq(rec.pause, "not_placed")
        g.now = 6
        local drop = setmetatable({ item = item, sq = b }, { __index = ISDropWorldItemAction })
        T.eq(drop:complete(), true)
        rec = item:getModData().tlgProc
        T.eq(rec.state, "Processing"); T.eq(rec.t, 6); T.eq(rec.site.x, 4)
        g.now = 7
        T.eq(ISTransferAction:transferItem({}, item, "floor", "inventory", nil), item)
        rec = item:getModData().tlgProc
        T.near(work(rec), 3, 1e-9, "floor -> inventory: counted to the pickup"); T.eq(rec.pause, "not_placed")
        g.now = 9
        ISTransferAction:transferItem({}, item, "inventory", "floor", a)
        rec = item:getModData().tlgProc
        T.eq(rec.state, "Processing"); T.eq(rec.t, 9); T.eq(rec.site.x, 1)
        T.eq(World.get().machineSites.P14.x, 1)
        -- A machine without a record passes untouched.
        local bare = machine(b, nil)
        ISTransferAction:transferItem({}, bare, "floor", "inventory", nil)
        T.ok(bare:getModData().tlgProc == nil, "no record created")
        -- A failing account never breaks the move.
        local pickedUp, log, logged = Machines.pickedUp, TLG.Log.error, nil
        Machines.pickedUp = function() error("boom") end
        TLG.Log.error = function(fmt, ...) logged = string.format(fmt, ...) end
        ISTransferAction:transferItem({}, item, "floor", "inventory", nil)
        Machines.pickedUp, TLG.Log.error = pickedUp, log
        T.ok(item.on == nil, "moved anyway"); T.ok(logged ~= nil and string.find(logged, "boom", 1, true) ~= nil)
    end)
    for _, k in ipairs(names) do _G[k] = saved[k] end
    g.restore()
    if not ok then error(err, 0) end
end)

T.case("integration: a machine carried in both hands is accounted when taken and when dropped", function()
    local g = fakeGame(2)
    local names = { "ISGrabItemAction", "ISTransferAction", "ISDropWorldItemAction", "ISEquipHeavyItem", "ISUnequipAction",
        "forceDropHeavyItems" }
    local saved = {}
    for _, k in ipairs(names) do saved[k] = _G[k] end
    local ok, err = pcall(function()
        local env = warmDay(g)
        local a, b = square(g, 1, 1, 0, false, 22), square(g, 4, 1, 0, false, 22)
        -- What the vanilla functions do (42.21): ISEquipHeavyItem takes the
        -- item into the inventory and both hands but, off the floor, leaves
        -- its world object on the square (RT-SP runs 77-78); ISUnequipAction
        -- puts a heavy hand item at the character's feet unless it is
        -- unequipped to be dropped or placed; forceDropHeavyItems puts a
        -- heavy hand item at the character's feet.
        local hands, carried = { square = b }, {}
        local inventory = { contains = function(self, it) return carried[it] == true end }
        local character = {
            getPrimaryHandItem = function() return hands.primary end,
            getSecondaryHandItem = function() return hands.secondary end,
            getCurrentSquare = function() return hands.square end,
            getInventory = function() return inventory end,
        }
        ISGrabItemAction, ISTransferAction, ISDropWorldItemAction = {}, {}, {}
        ISEquipHeavyItem = { complete = function(self)
            carried[self.item] = true
            hands.primary, hands.secondary = self.item, self.item
            return true
        end }
        ISUnequipAction = { complete = function(self)
            hands.primary, hands.secondary = nil, nil
            if self.reason ~= "drop" and self.reason ~= "place" then
                place(self.item, self.character:getCurrentSquare())
                carried[self.item] = nil
            end
            return true
        end }
        forceDropHeavyItems = function(chr)
            local held = chr:getPrimaryHandItem()
            if held then
                place(held, chr:getCurrentSquare())
                carried[held] = nil
            end
            hands.primary, hands.secondary = nil, nil
        end
        Machines.install()
        local item = startedOn(a, "P15", env)
        g.now = 4
        local take = setmetatable({ item = item, character = character }, { __index = ISEquipHeavyItem })
        T.eq(take:complete(), true)
        T.ok(item:getWorldItem() == nil and #a.objs == 0 and a.transmitted == 1,
            "the world object vanilla left on the square is taken off as the floor transfer does")
        local rec = item:getModData().tlgProc
        T.near(work(rec), 2, 1e-9, "taken into both hands: counted to the pickup"); T.eq(rec.pause, "not_placed")
        g.now = 6
        forceDropHeavyItems(character)
        rec = item:getModData().tlgProc
        T.eq(rec.state, "Processing"); T.eq(rec.t, 6); T.eq(rec.site.x, 4, "dropped at the character's feet")
        T.eq(World.get().machineSites.P15.x, 4, "listed at the new tile at once")
        local later = Machines.advance(item, Machines.read(item, false), 8, env)
        T.near(work(later), 4, 1e-9, "2 h before the pickup and 2 h since the drop, none of the 2 h carried")
        -- Nothing in hand: the drop changes nothing.
        g.now = 9
        forceDropHeavyItems(character)
        T.eq(item:getModData().tlgProc.t, 6)
        -- Taken from the inventory (the machine was not standing): no pickup.
        lift(item)
        Machines.pickedUp(item, 9)
        g.now = 10
        setmetatable({ item = item, character = character }, { __index = ISEquipHeavyItem }):complete()
        T.eq(item:getModData().tlgProc.t, 9, "already carried")
        -- Unequipped to be dropped, it stays in the inventory (the floor
        -- transfer that follows puts it down): nothing yet.
        g.now = 11
        setmetatable({ item = item, character = character, reason = "drop" }, { __index = ISUnequipAction }):complete()
        T.eq(item:getModData().tlgProc.pause, "not_placed", "not put down by the drop's unequip")
        -- Unequipped for anything else (the menus unequip the hands before
        -- another heavy item is taken or a weapon equipped): at the
        -- character's feet, resumed from then.
        setmetatable({ item = item, character = character }, { __index = ISEquipHeavyItem }):complete()
        hands.square = a
        g.now = 12
        setmetatable({ item = item, character = character }, { __index = ISUnequipAction }):complete()
        rec = item:getModData().tlgProc
        T.eq(rec.state, "Processing"); T.eq(rec.t, 12); T.eq(rec.site.x, 1, "unequipped at the character's feet")
        T.eq(World.get().machineSites.P15.x, 1, "listed at the new tile at once")
        later = Machines.advance(item, Machines.read(item, false), 14, env)
        T.near(work(later), 7, 1e-9, "5 h placed before the pickup at 9 and 2 h since the drop, none of the 3 h carried")
        -- A machine without a record yet is taken off the ground too, and no
        -- record is created; a vanilla heavy item is left as vanilla leaves it.
        local bare = machine(b, nil)
        setmetatable({ item = bare, character = character }, { __index = ISEquipHeavyItem }):complete()
        T.ok(bare:getWorldItem() == nil, "lifted"); T.ok(bare:getModData().tlgProc == nil, "no record created")
        setmetatable({ item = bare, character = character }, { __index = ISUnequipAction }):complete()
        T.ok(bare:getWorldItem() ~= nil and bare:getModData().tlgProc == nil, "unequipped at the feet, still no record")
        local rock = machine(b, nil)
        function rock:getFullType() return "Base.LargeMeteorite" end
        setmetatable({ item = rock, character = character }, { __index = ISEquipHeavyItem }):complete()
        T.ok(rock:getWorldItem() ~= nil, "not the mod's item: untouched")
    end)
    for _, k in ipairs(names) do _G[k] = saved[k] end
    g.restore()
    if not ok then error(err, 0) end
end)

T.case("integration: on a dedicated server the mod takes a machine off the floor into both hands", function()
    local g = fakeGame(2)
    local names = { "ISGrabItemAction", "ISTransferAction", "ISDropWorldItemAction", "ISEquipHeavyItem", "ISUnequipAction",
        "forceDropHeavyItems", "sendAddItemToContainer", "sendEquip" }
    local saved = {}
    for _, k in ipairs(names) do saved[k] = _G[k] end
    local ok, err = pcall(function()
        local env = warmDay(g)
        isServer = function() return true end
        local a, b, far = square(g, 1, 1, 0, false, 22), square(g, 2, 1, 0, false, 22), square(g, 6, 1, 0, false, 22)
        -- What the server's game does (42.21): the action's item is the world
        -- object's own, without a container (BC ContainerID.collectFloorItems),
        -- and ISEquipHeavyItem.complete removes it from its container (line
        -- 63, failing without one); sendAddItemToContainer and sendEquip tell
        -- the clients; forceDropHeavyItems puts a heavy hand item down.
        local vanilla, sent, equips, drops = 0, {}, {}, 0
        local function person(at)
            local p, inv = { class = "IsoGameCharacter", at = at, hands = {} }, { items = {} }
            function inv:AddItem(it) self.items[it], it.container = true, self end
            function inv:DoRemoveItem(it) self.items[it], it.container = nil, nil end
            function inv:contains(it) return self.items[it] == true end
            function inv:getParent() return p end
            function p:getInventory() return inv end
            function p:getSquare() return self.at end
            function p:getCurrentSquare() return self.at end
            function p:getPrimaryHandItem() return self.hands.primary end
            function p:getSecondaryHandItem() return self.hands.secondary end
            function p:setPrimaryHandItem(it) self.hands.primary = it end
            function p:setSecondaryHandItem(it) self.hands.secondary = it end
            return p
        end
        local function held(item)
            function item:getContainer() return self.container end
            function item:getOutermostContainer() return self.container end
            return item
        end
        forceDropHeavyItems = function(chr)
            drops = drops + 1
            local it = chr:getPrimaryHandItem()
            if it then
                chr:getInventory():DoRemoveItem(it)
                place(it, chr:getCurrentSquare())
            end
            chr.hands.primary, chr.hands.secondary = nil, nil
        end
        ISGrabItemAction, ISTransferAction, ISDropWorldItemAction, ISUnequipAction = {}, {}, {}, {}
        ISEquipHeavyItem = { complete = function(self)
            vanilla = vanilla + 1
            forceDropHeavyItems(self.character)
            local src = self.item:getContainer()
            src:DoRemoveItem(self.item)
            self.character:getInventory():AddItem(self.item)
            self.character:setPrimaryHandItem(self.item)
            self.character:setSecondaryHandItem(self.item)
            return true
        end }
        sendAddItemToContainer = function(inv, it)
            local rec = it:getModData().tlgProc
            sent[#sent + 1] = { inv = inv, item = it, pause = rec and rec.pause }
        end
        sendEquip = function(chr) equips[#equips + 1] = chr end
        Machines.install()
        local function take(item, chr)
            return setmetatable({ item = item, character = chr }, { __index = ISEquipHeavyItem }):complete()
        end
        local item = held(startedOn(a, "P17", env))
        local ann, ben = person(b), person(b)
        g.now = 4
        T.eq(take(item, ann), true)
        T.eq(vanilla, 0, "the game's complete, which fails here, is not called")
        T.eq(drops, 1, "heavy items in hand put down first, as that complete does")
        T.ok(item:getWorldItem() == nil and #a.objs == 0 and a.transmitted == 1, "off its square, the clients told")
        T.ok(ann:getInventory():contains(item) and ann.hands.primary == item and ann.hands.secondary == item,
            "in the inventory and both hands")
        T.eq(#sent, 1); T.ok(sent[1].inv == ann:getInventory() and sent[1].item == item, "the item sent to her client")
        T.eq(sent[1].pause, "not_placed", "sent with the carried record")
        T.eq(#equips, 1); T.ok(equips[1] == ann, "her hands sent")
        local rec = item:getModData().tlgProc
        T.near(work(rec), 2, 1e-9, "counted to the pickup"); T.ok(World.get().machineSites.P17 == nil, "no longer listed")
        -- Ben's action on the same vessel, completing after hers (both taken
        -- off the floor at once): refused, she keeps it.
        T.eq(take(item, ben), false)
        T.ok(ann.hands.primary == item and ann:getInventory():contains(item) and not ben:getInventory():contains(item),
            "still hers alone")
        T.eq(vanilla, 0); T.eq(#sent, 1); T.eq(drops, 1, "nothing put down for a refused take")
        -- Out of reach (4 tiles from Ben) or on no square: refused, left as it is.
        local distant = held(machine(far, nil))
        T.eq(take(distant, ben), false)
        T.ok(distant:getWorldItem() ~= nil and far.transmitted == nil and #sent == 1, "left where it lies")
        T.eq(take(held(machine(nil, nil)), ben), false)
        -- In a container, his own inventory or a crate: the game's complete,
        -- which works there.
        local own = held(machine(nil, nil))
        ben:getInventory():AddItem(own)
        T.eq(take(own, ben), true); T.eq(vanilla, 1); T.ok(ben.hands.primary == own)
        local crate = { items = {} }
        function crate:DoRemoveItem(it) self.items[it], it.container = nil, nil end
        function crate:getParent() return { class = "IsoObject" } end
        local boxed = held(machine(nil, nil))
        boxed.container = crate
        T.eq(take(boxed, ben), true); T.eq(vanilla, 2); T.ok(ben.hands.primary == boxed)
        -- A heavy item that is not the mod's is left to the game: its
        -- complete fails on the floor as it does without the mod.
        local rock = held(machine(b, nil))
        function rock:getFullType() return "Base.LargeMeteorite" end
        T.raises(function() take(rock, ben) end)
        T.eq(vanilla, 3); T.ok(rock:getWorldItem() ~= nil, "still on the floor")
    end)
    for _, k in ipairs(names) do _G[k] = saved[k] end
    g.restore()
    if not ok then error(err, 0) end
end)

T.case("integration: a machine carried in both arms goes down at the feet when another action plays its animation", function()
    local g = fakeGame(2)
    local names = { "ISGrabItemAction", "ISTransferAction", "ISDropWorldItemAction", "ISEquipHeavyItem", "ISUnequipAction",
        "forceDropHeavyItems", "ISBaseTimedAction", "sendClientCommand" }
    local saved = {}
    for _, k in ipairs(names) do saved[k] = _G[k] end
    local ok, err = pcall(function()
        local env = warmDay(g)
        local a, b = square(g, 1, 1, 0, false, 22), square(g, 4, 1, 0, false, 22)
        -- The vanilla calls as in the case above; every action that plays
        -- an animation calls ISBaseTimedAction.setActionAnim, and a derived
        -- action finds it through its class's metatable at call time.
        local hands, carried, drops, sent = { square = b }, {}, 0, {}
        local inventory = { contains = function(self, it) return carried[it] == true end }
        local character = {
            getPrimaryHandItem = function() return hands.primary end,
            getSecondaryHandItem = function() return hands.secondary end,
            getCurrentSquare = function() return hands.square end,
            getInventory = function() return inventory end,
            getOnlineID = function() return 3 end,
        }
        ISGrabItemAction, ISTransferAction, ISDropWorldItemAction, ISUnequipAction = {}, {}, {}, {}
        ISEquipHeavyItem = { complete = function(self)
            carried[self.item] = true
            hands.primary, hands.secondary = self.item, self.item
            return true
        end }
        forceDropHeavyItems = function(chr)
            drops = drops + 1
            local held = chr:getPrimaryHandItem()
            if held then
                place(held, chr:getCurrentSquare())
                carried[held] = nil
            end
            hands.primary, hands.secondary = nil, nil
        end
        sendClientCommand = function(chr, module, command, args)
            sent[#sent + 1] = { module = module, command = command, id = args.id }
        end
        ISBaseTimedAction = { setActionAnim = function(self, anim) self.played = anim end }
        local Loot = setmetatable({}, { __index = ISBaseTimedAction })
        Machines.install()
        local function action(item)
            return setmetatable({ character = character, item = item }, { __index = Loot })
        end
        local item = startedOn(a, "P16", env)
        function item:isForceDropHeavyItem() return true end
        g.now = 4
        setmetatable({ item = item, character = character }, { __index = ISEquipHeavyItem }):complete()
        T.eq(item:getModData().tlgProc.pause, "not_placed")
        -- An action on another item (the loot window's transfer of a nail)
        -- puts the vessel down at the feet before its animation plays.
        g.now = 6
        local loot = action({})
        loot:setActionAnim("Loot")
        T.eq(loot.played, "Loot", "the animation still plays")
        T.eq(drops, 1); T.ok(hands.primary == nil and item.on == b, "at the character's feet")
        local rec = item:getModData().tlgProc
        T.eq(rec.state, "Processing"); T.eq(rec.t, 6); T.eq(rec.site.x, 4, "resumed where it went down")
        local later = Machines.advance(item, Machines.read(item, false), 8, env)
        T.near(work(later), 4, 1e-9, "2 h before the pickup and 2 h since the drop, none of the 2 h carried")
        -- Hands empty: nothing more to put down.
        loot:setActionAnim("Loot")
        T.eq(drops, 1)
        -- An action on the vessel itself (its unequip) leaves it to that
        -- action: in the arms until the unequip completes.
        lift(item)
        setmetatable({ item = item, character = character }, { __index = ISEquipHeavyItem }):complete()
        local unequip = action(item)
        unequip:setActionAnim("UnequipItem")
        T.eq(unequip.played, "UnequipItem"); T.eq(drops, 1); T.ok(hands.primary == item, "still in the arms")
        -- From a multiplayer client the server is asked to put it down, as
        -- the vehicle entry asks.
        isClient = function() return true end
        local mp = action({})
        mp:setActionAnim("Eat")
        T.eq(mp.played, "Eat"); T.eq(drops, 1)
        T.eq(#sent, 1); T.eq(sent[1].module, "player"); T.eq(sent[1].command, "onDropHeavyItem"); T.eq(sent[1].id, 3)
        isClient = function() return false end
        -- A heavy item that is not the mod's, and a mod machine carried in
        -- one hand, are left to the game.
        local gen = machine(nil, nil)
        function gen:getFullType() return "Base.Generator" end
        function gen:isForceDropHeavyItem() return true end
        hands.primary, hands.secondary = gen, gen
        action({}):setActionAnim("Loot")
        T.eq(drops, 1); T.ok(hands.primary == gen, "the generator stays in both hands")
        local still = machine(nil, nil)
        function still:getFullType() return "TLG.PotStill" end
        function still:isForceDropHeavyItem() return false end
        hands.primary, hands.secondary = still, nil
        action({}):setActionAnim("Loot")
        T.eq(drops, 1); T.ok(hands.primary == still, "not carried in both arms")
        -- A failing put-down is logged and the animation still plays.
        hands.primary, hands.secondary = item, item
        forceDropHeavyItems = function() error("boom") end
        local log, logged = TLG.Log.error, nil
        TLG.Log.error = function(fmt, ...) logged = string.format(fmt, ...) end
        local failing = action({})
        failing:setActionAnim("Loot")
        T.eq(failing.played, "Loot"); T.ok(logged ~= nil and string.find(logged, "boom", 1, true) ~= nil)
        -- So is a failing look at the hands (Kahlua reports this error
        -- without its message).
        logged = nil
        local blind = setmetatable({ character = { getPrimaryHandItem = function() error("no hands") end }, item = {} },
            { __index = Loot })
        blind:setActionAnim("Loot")
        TLG.Log.error = log
        T.eq(blind.played, "Loot"); T.ok(logged ~= nil and string.find(logged, "machine move:", 1, true) == 1)
    end)
    for _, k in ipairs(names) do _G[k] = saved[k] end
    g.restore()
    if not ok then error(err, 0) end
end)

T.case("integration: a carrier's death puts the dropped machine down where it lands; one in the body stays carried", function()
    local g = fakeGame(2)
    local savedEvents = Events
    local ok, err = pcall(function()
        local env = warmDay(g)
        local a, b = square(g, 1, 1, 0, false, 22), square(g, 4, 1, 0, false, 22)
        -- The tick event as a list the case runs by hand.
        local ticks = {}
        Events = { OnTick = {
            Add = function(fn) ticks[#ticks + 1] = fn end,
            Remove = function(fn)
                for i = #ticks, 1, -1 do if ticks[i] == fn then table.remove(ticks, i) end end
            end,
        } }
        local function tick()
            local now = {}
            for i, fn in ipairs(ticks) do now[i] = fn end
            for _, fn in ipairs(now) do fn() end
        end
        local item = startedOn(a, "P21", env)
        lift(item)
        Machines.pickedUp(item, 4)
        local hands = { primary = item, secondary = item }
        local character = {
            getPrimaryHandItem = function() return hands.primary end,
            getSecondaryHandItem = function() return hands.secondary end,
            getSquare = function() return b end,
        }
        -- Dead, still holding it: watched until it lands.
        g.now = 4
        Machines.onDeath(character)
        T.eq(#ticks, 1, "a watch for the landing")
        tick()
        T.eq(item:getModData().tlgProc.pause, "not_placed", "not landed yet: still carried")
        g.now = 4.01
        place(item, b)
        tick()
        local rec = item:getModData().tlgProc
        T.eq(rec.state, "Processing"); T.ok(rec.pause == nil)
        T.near(rec.t, 4.01, 1e-9, "put down when it landed"); T.eq(rec.site.x, 4, "at the body's feet")
        T.eq(#ticks, 0, "the watch ends")
        T.eq(World.get().machineSites.P21.x, 4, "listed for the hourly reading at once")
        local later = Machines.advance(item, Machines.read(item, false), 6, env)
        T.near(work(later), 3.99, 1e-6, "2 h before the pickup and 1.99 h since it landed")
        -- Into the body's inventory instead: the watch gives up, still carried.
        lift(item)
        Machines.write(item, later)
        Machines.pickedUp(item, 6)
        hands.primary, hands.secondary = item, item
        Machines.onDeath(character)
        for _ = 1, Machines.LANDING_TICKS do tick() end
        T.eq(#ticks, 0, "the watch gave up")
        T.eq(item:getModData().tlgProc.pause, "not_placed", "in the body: still carried, nothing counts")
        -- Already at the feet when the event comes: put down from the event.
        hands.primary, hands.secondary = nil, nil
        place(item, b)
        g.now = 7
        Machines.onDeath(character)
        rec = item:getModData().tlgProc
        T.eq(rec.state, "Processing"); T.eq(rec.t, 7, "put down at the death")
        T.eq(#ticks, 0, "nothing to watch")
        -- A death with nothing carried changes nothing.
        g.now = 8
        Machines.onDeath(character)
        T.eq(item:getModData().tlgProc.t, 7)
    end)
    Events = savedEvents
    g.restore()
    if not ok then error(err, 0) end
end)

-- The game's events as lists the cases fire by hand: OnTick, and the two a
-- character's hand setters fire.
local function fakeEvents()
    local ev = { handlers = {} }
    local function event(name)
        local list = {}
        ev.handlers[name] = list
        return {
            Add = function(fn) list[#list + 1] = fn end,
            Remove = function(fn)
                for i = #list, 1, -1 do if list[i] == fn then table.remove(list, i) end end
            end,
        }
    end
    Events = { OnTick = event("OnTick"), OnEquipPrimary = event("OnEquipPrimary"),
        OnEquipSecondary = event("OnEquipSecondary") }
    function ev.fire(name, a, b)
        local now = {}
        for i, fn in ipairs(ev.handlers[name]) do now[i] = fn end
        for _, fn in ipairs(now) do fn(a, b) end
    end
    function ev.tick() ev.fire("OnTick") end
    function ev.watching() return #ev.handlers.OnTick end
    return ev
end

-- A character's hands as 42.21 sets them (BC): setPrimaryHandItem and
-- setSecondaryHandItem fire OnEquipPrimary and OnEquipSecondary when the
-- hand changes, on a server too; removeFromHands empties them through the
-- two.
local function handsOf(at, ev)
    local p = { at = at, hands = {} }
    function p:getPrimaryHandItem() return self.hands.primary end
    function p:getSecondaryHandItem() return self.hands.secondary end
    function p:getSquare() return self.at end
    function p:getCurrentSquare() return self.at end
    function p:setPrimaryHandItem(it)
        if self.hands.primary == it then return end
        self.hands.primary = it
        ev.fire("OnEquipPrimary", self, it)
    end
    function p:setSecondaryHandItem(it)
        if self.hands.secondary == it then return end
        self.hands.secondary = it
        ev.fire("OnEquipSecondary", self, it)
    end
    function p:removeFromHands(it)
        if self.hands.primary == it then self:setPrimaryHandItem(nil) end
        if self.hands.secondary == it then self:setSecondaryHandItem(nil) end
    end
    return p
end

-- What a server does with a client's dying player's hands (BC 42.21,
-- IsoGameCharacter.die -> dropHeldItems): the primary hand emptied and its
-- item put on the floor, then the secondary hand emptied and its item put
-- there too unless it is the same.
local function dropHeldItems(p)
    local primary, secondary = p.hands.primary, p.hands.secondary
    if primary then
        p:setPrimaryHandItem(nil)
        place(primary, p.at)
    end
    if secondary then
        p:setSecondaryHandItem(nil)
        if secondary ~= primary then place(secondary, p.at) end
    end
end

T.case("integration: on a server a machine that leaves the hands where no hook sees it is put down where it lands", function()
    local g = fakeGame(2)
    local savedEvents, savedDrop, savedWrite = Events, forceDropHeavyItems, Machines.write
    local ok, err = pcall(function()
        local env = warmDay(g)
        isServer = function() return true end
        Machines.landing, Machines.watching, Machines.inHands = {}, false, {}
        local ev = fakeEvents()
        -- Vanilla's (SRC ISEquipWeaponAction.lua:75): onto the floor, then
        -- out of the hands.
        forceDropHeavyItems = function(chr)
            local it = chr:getPrimaryHandItem()
            if it then
                place(it, chr:getCurrentSquare())
                chr:removeFromHands(it)
            end
        end
        Machines.install()
        local writes = 0
        Machines.write = function(...)
            writes = writes + 1
            return savedWrite(...)
        end
        local a, b, c = square(g, 1, 1, 0, false, 22), square(g, 4, 1, 0, false, 22), square(g, 6, 1, 0, false, 22)
        local item = startedOn(a, "P31", env)
        local ann = handsOf(a, ev)
        -- Taken into both arms on the server (M.takeOnServer: the batch
        -- counted to the pickup, then the hands set).
        g.now = 4
        lift(item)
        Machines.pickedUp(item, 4)
        ann:setPrimaryHandItem(item)
        ann:setSecondaryHandItem(item)
        T.ok(Machines.inHands[item] == ann, "remembered in her hands")
        -- She dies two squares on: the server drops it in Java, no death
        -- event; the hands empty around the drop.
        ann.at = b
        g.now = 4.5
        dropHeldItems(ann)
        T.ok(item.on == b, "on the floor where she died")
        T.eq(item:getModData().tlgProc.pause, "not_placed", "nothing written at the events themselves")
        T.ok(Machines.inHands[item] == nil, "out of her hands"); T.eq(ev.watching(), 1, "watched until it lands")
        g.now = 4.502
        ev.tick()
        local rec = item:getModData().tlgProc
        T.eq(rec.state, "Processing"); T.ok(rec.pause == nil)
        T.near(rec.t, 4.502, 1e-9, "put down from the tick it was found on the floor"); T.eq(rec.site.x, 4)
        T.eq(World.get().machineSites.P31.x, 4, "listed for the hourly reading at once")
        T.eq(ev.watching(), 0, "the watch ends")
        local later = Machines.advance(item, Machines.read(item, false), 6.502, env)
        T.near(work(later), 4, 1e-9, "2 h before the pickup and 2 h since it landed, none of the carried half hour")
        -- A machine in one hand: the one event comes before it lands, and
        -- the next tick finds it on the floor.
        local still = startedOn(c, "P32", env)
        function still:getFullType() return "TLG.PotStill" end
        function still:getID() return 8 end
        g.now = 7
        lift(still)
        Machines.pickedUp(still, 7)
        local ben = handsOf(c, ev)
        ben:setPrimaryHandItem(still)
        g.now = 8
        dropHeldItems(ben)
        T.eq(still:getModData().tlgProc.pause, "not_placed"); T.eq(ev.watching(), 1)
        ev.tick()
        rec = still:getModData().tlgProc
        T.eq(rec.state, "Processing"); T.eq(rec.t, 8, "put down where he dropped it"); T.eq(rec.site.x, 6)
        -- Into the inventory (an unequip): never lands, given up, still
        -- carried, nothing written.
        lift(item)
        Machines.write(item, later)
        Machines.pickedUp(item, 9)
        ann:setPrimaryHandItem(item)
        ann:setSecondaryHandItem(item)
        writes = 0
        ann:setPrimaryHandItem(nil)
        ann:setSecondaryHandItem(nil)
        for _ = 1, Machines.LANDING_TICKS do ev.tick() end
        T.eq(ev.watching(), 0, "the watch gave up")
        T.eq(item:getModData().tlgProc.pause, "not_placed", "still carried"); T.eq(writes, 0, "nothing written")
        -- A drop a hook sees (forceDropHeavyItems: a vehicle entered) is put
        -- down by that hook, once: the watch finds it done.
        ann:setPrimaryHandItem(item)
        ann:setSecondaryHandItem(item)
        ann.at = a
        g.now = 10
        forceDropHeavyItems(ann)
        T.eq(item:getModData().tlgProc.t, 10, "put down by the hook"); T.eq(writes, 1)
        T.eq(ev.watching(), 1)
        g.now = 10.01
        ev.tick()
        T.eq(ev.watching(), 0); T.eq(writes, 1, "not written again"); T.eq(item:getModData().tlgProc.t, 10)
        -- A machine that is not tracked, and other items, are not remembered.
        local bare = machine(nil, nil)
        ann:setPrimaryHandItem(bare)
        ann:setPrimaryHandItem({ getFullType = function() return "Base.BaseballBat" end })
        T.ok(TLG.Tables.isEmpty(Machines.inHands), "nothing remembered")
        -- A client leaves it all to the server.
        isServer = function() return false end
        isClient = function() return true end
        lift(item)
        ann:setPrimaryHandItem(item)
        T.ok(TLG.Tables.isEmpty(Machines.inHands), "not on a client")
        isServer = function() return true end
        isClient = function() return false end
        -- A failing look at the hands is logged; the game's setter goes on.
        local log, logged = TLG.Log.error, nil
        TLG.Log.error = function(fmt, ...) logged = string.format(fmt, ...) end
        ev.fire("OnEquipPrimary", { getPrimaryHandItem = function() error("no hands") end }, item)
        TLG.Log.error = log
        T.ok(logged ~= nil and string.find(logged, "machine move:", 1, true) == 1, "logged")
    end)
    Events, forceDropHeavyItems, Machines.write = savedEvents, savedDrop, savedWrite
    Machines.landing, Machines.watching, Machines.inHands = {}, false, {}
    g.restore()
    if not ok then error(err, 0) end
end)

T.case("integration: every ten game minutes the hands of the characters in the game are looked at again", function()
    local g = fakeGame(2)
    local names = { "Events", "getOnlinePlayers", "getSpecificPlayer", "getNumActivePlayers" }
    local saved = {}
    for _, k in ipairs(names) do saved[k] = _G[k] end
    local ok, err = pcall(function()
        local env = warmDay(g)
        isServer = function() return true end
        Machines.landing, Machines.watching, Machines.inHands = {}, false, {}
        local ev = fakeEvents()
        Machines.install()
        local online = {}
        getOnlinePlayers = function()
            local list = {}
            function list:size() return #online end
            function list:get(i) return online[i + 1] end
            return list
        end
        local a, b = square(g, 1, 1, 0, false, 22), square(g, 4, 1, 0, false, 22)
        local item = startedOn(a, "P33", env)
        g.now = 4
        lift(item)
        Machines.pickedUp(item, 4)
        -- Ben was saved carrying the vessel and joined again: the game's
        -- load sets his hands directly, with no event.
        local ben = handsOf(b, ev)
        ben.hands.primary, ben.hands.secondary = item, item
        online = { ben }
        T.ok(Machines.inHands[item] == nil, "no event told it")
        Machines.censusHands()
        T.ok(Machines.inHands[item] == ben, "found in his hands")
        -- He dies: put down where he fell.
        g.now = 5
        dropHeldItems(ben)
        ev.tick()
        local rec = item:getModData().tlgProc
        T.eq(rec.state, "Processing"); T.eq(rec.t, 5); T.eq(rec.site.x, 4)
        -- Hands emptied with no event (no path 42.21 has): the next look
        -- finds it gone from them and watches it land.
        lift(item)
        Machines.pickedUp(item, 6)
        ben.hands.primary, ben.hands.secondary = item, item
        Machines.censusHands()
        ben.hands.primary, ben.hands.secondary = nil, nil
        place(item, a)
        g.now = 7
        Machines.censusHands()
        T.ok(Machines.inHands[item] == nil); T.eq(ev.watching(), 1)
        ev.tick()
        rec = item:getModData().tlgProc
        T.eq(rec.state, "Processing"); T.eq(rec.t, 7); T.eq(rec.site.x, 1)
        -- A holder who left the server is forgotten: the vessel went with
        -- him, carried, in his saved inventory.
        lift(item)
        Machines.pickedUp(item, 8)
        ben:setPrimaryHandItem(item)
        ben:setSecondaryHandItem(item)
        T.ok(Machines.inHands[item] == ben)
        online = {}
        Machines.censusHands()
        T.ok(Machines.inHands[item] == nil, "forgotten with him"); T.eq(ev.watching(), 0, "nothing to watch")
        T.eq(item:getModData().tlgProc.pause, "not_placed")
        -- In single player the local players are looked at, and nobody is
        -- forgotten for being off a server's list.
        isServer = function() return false end
        getOnlinePlayers = nil
        getNumActivePlayers = function() return 1 end
        getSpecificPlayer = function(i) return i == 0 and ben or nil end
        Machines.censusHands()
        T.ok(Machines.inHands[item] == ben, "found in the local player's hands")
        getSpecificPlayer = function() return nil end
        Machines.censusHands()
        T.ok(Machines.inHands[item] == ben, "kept while still in his hands")
    end)
    for _, k in ipairs(names) do _G[k] = saved[k] end
    Machines.landing, Machines.watching, Machines.inHands = {}, false, {}
    g.restore()
    if not ok then error(err, 0) end
end)

T.case("integration: on a server a machine's record goes to the clients without its readings; a client puts it in its copy", function()
    local g = fakeGame(100)
    local sent, savedSend = {}, sendServerCommand
    sendServerCommand = function(module, command, args) sent[#sent + 1] = { module = module, command = command, args = args } end
    local ok, err = pcall(function()
        local sq = square(g, 10, 20, 0, true, 20)
        local rec = Process.new({ id = "P-push", machine = "fermenter_barrel", t = 100 })
        rec.temps, rec.fires = { [99] = 20 }, { [99] = false }
        local item = machine(sq, rec)
        Machines.write(item, rec)
        T.eq(#sent, 0, "single player sends nothing")
        isServer = function() return true end
        Machines.write(item, rec)
        T.eq(#sent, 1)
        local m = sent[1]
        T.eq(m.module, "TLG"); T.eq(m.command, "item"); T.eq(m.args.key, "tlgProc")
        T.eq(m.args.id, 7); T.eq(m.args.x, 10); T.eq(m.args.y, 20); T.eq(m.args.z, 0)
        T.eq(m.args.rec.id, "P-push")
        T.eq(m.args.rec.state, rec.state)
        T.eq(m.args.rec.temps, nil, "no readings sent")
        T.eq(m.args.rec.fires, nil, "no fire notes sent")
        T.ok(rec.temps ~= nil and rec.fires ~= nil, "the record kept on the server keeps both")
        Machines.write(item, rec, true)
        T.eq(#sent, 1, "a quiet write is not sent")
        lift(item)
        Machines.write(item, rec)
        T.eq(#sent, 1, "carried: its holder gets it with the item's fields")
        -- A client's copy of the item on the floor takes the record sent.
        isServer = function() return false end
        local copy = machine(sq, nil)
        local FR = TLG.Integration.WorldItemRecords
        T.ok(FR.received(m.args))
        T.eq(copy:getModData().tlgProc.id, "P-push")
        T.ok(not FR.received({ id = 8, x = 10, y = 20, z = 0, key = "tlgProc", rec = m.args.rec }), "another item")
        T.ok(not FR.received({ id = 7, x = 1, y = 1, z = 0, key = "tlgProc", rec = m.args.rec }), "a square not loaded")
        T.ok(not FR.received({ id = 7, x = 10, y = 20, z = 0, key = "tlgProc" }), "no record")
        T.ok(not FR.received({ id = 7, x = 10, y = 20, z = 0, key = "other", rec = m.args.rec }), "a key not sent")
    end)
    sendServerCommand = savedSend
    g.restore()
    if not ok then error(err, 0) end
end)

-- Why a multiplayer client's menu judges on the record as sent
-- (MachineMenu.controls) rather than bringing it forward.
T.case("integration: a record sent without its readings and brought forward disagrees with the server's; the hourly reading sends nothing", function()
    local g = fakeGame(2)
    local sent, savedSend = {}, sendServerCommand
    sendServerCommand = function(module, command, args) sent[#sent + 1] = { module = module, command = command, args = args } end
    local ok, err = pcall(function()
        -- A cold day; a room warmed to 22 C by a fire, which the hourly
        -- readings filed.
        g.outC = -3
        World.get().climateLog = { [0] = { t = -3, rh = 0.7 } }
        local env = World.env()
        local sq = square(g, 30, 30, 0, true, 22)
        local rec = running("P-cold", 2)
        rec.temps = {}
        for h = 2, 9 do rec.temps[h] = 22 end
        local item = machine(sq, rec)
        local server = Machines.advance(item, Machines.read(item, false), 10, env)
        local view = {}
        for k, v in pairs(server) do
            if not TLG.Integration.WorldItemRecords.KEYS.tlgProc[k] then view[k] = v end
        end
        local copy = machine(sq, view)
        local full = Machines.advance(item, server, 12, env)
        local stripped = Machines.advance(copy, TLG.Tables.deepCopy(view), 12, env)
        local function said(r) return string.format("%s/%s stage %s done %.4f", tostring(r.state), tostring(r.pause),
            tostring(r.stage), r.stageDone or -1) end
        T.ok(said(full) ~= said(stripped), "the server " .. said(full) .. "; the copy without readings " .. said(stripped))
        -- On a server the hourly reading files the air quietly: nothing goes
        -- to the clients.
        isServer = function() return true end
        Machines.write(item, full, true)
        Machines.index(item, full)
        g.now = 12.02
        Machines.sampleSites()
        T.eq(item:getModData().tlgProc.temps[11], 22, "the reading filed")
        T.eq(#sent, 0, "and not sent")
    end)
    sendServerCommand = savedSend
    g.restore()
    if not ok then error(err, 0) end
end)
