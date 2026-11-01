require "support/fixtures"
require "TLG/Integration/Machines"
local Machines, World, Process = TLG.Integration.Machines, TLG.World, TLG.Domain.Process

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
    local list, others = {}, {}
    function list:size() return #sq.objs end
    function list:get(i) return sq.objs[i + 1] end
    function sq:getWorldObjects() return list end
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

local function machine(sq, rec)
    local item, wi, md = {}, {}, { tlgProc = rec }
    function wi:getSquare() return item.on end
    function wi:getItem() return item end
    function item:getFullType() return "TLG.FermenterVessel" end
    function item:getModData() return md end
    function item:getWorldItem() return item.on and wi or nil end
    function item:getID() return 7 end
    item.on = sq
    if sq then sq.objs[#sq.objs + 1] = wi end
    return item
end

local function running(id, t)
    local f = Process.new({ id = id, machine = "fermenter_barrel", t = t })
    f = Process.load(f, "ethanol_ferment", { sugar_eq = 6, water = 30 }).proc
    return Process.start(f, t).proc
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
        T.eq(item:getModData().tlgProc.site.room, true)
        -- The hearth out, the barbecue gives the air: its note has a fixed radius.
        hearth.lit = false
        sq.air = Climate.warmed(t0, -2, 0, 3, false, 25)
        g.now = 11.0
        Machines.observeFires()
        note = item:getModData().tlgProc.fires[11]
        T.eq(note.c, 25); T.eq(note.rad, 3); T.eq(note.f, 100); T.eq(note.r, false); T.eq(note.x, -2)
        -- Nothing warms it: false, the hour's last note wins, written once an hour.
        bbq.lit = false
        sq.air = t0
        g.now = 11.17
        Machines.observeFires()
        T.eq(item:getModData().tlgProc.fires[11], false)
        local writes, write = 0, Machines.write
        Machines.write = function(...)
            writes = writes + 1
            return write(...)
        end
        g.now = 11.33
        Machines.observeFires()
        Machines.write = write
        T.eq(writes, 0, "an hour already noted cold is not written again")
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
