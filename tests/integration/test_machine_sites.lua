require "support/fixtures"
require "TLG/Integration/Machines"
local Machines, World, Process = TLG.Integration.Machines, TLG.World, TLG.Domain.Process

-- Stand-ins for the game calls the machine site adapter makes: global ModData,
-- the clock, the cell's squares, the air temperature per square. Installed
-- for one case and removed again (the domain suite runs without them).
local GLOBALS = { "ModData", "getGameTime", "getCell", "getClimateManager", "isServer", "isClient" }

local function fakeGame(now)
    local saved = {}
    for _, k in ipairs(GLOBALS) do saved[k] = _G[k] end
    local g = { now = now, squares = {}, store = {} }
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
    local cm = {}
    function cm:getAirTemperatureForSquare(sq) return sq.air end
    getClimateManager = function() return cm end
    isServer = function() return false end
    isClient = function() return false end
    local md = World.get()
    md.v, md.calendar, md.climateLog = 1, { dayOfYear = 15, hourOfDay = 0 }, { [0] = { t = -3, rh = 0.7 } }
    function g.restore()
        for _, k in ipairs(GLOBALS) do _G[k] = saved[k] end
    end
    return g
end

-- A square with world objects; machines are items on it (D-015).
local function square(g, x, y, z, room, air)
    local sq = { x = x, y = y, z = z, room = room, air = air, objs = {} }
    function sq:getX() return self.x end
    function sq:getY() return self.y end
    function sq:getZ() return self.z end
    function sq:isInARoom() return self.room end
    local list = {}
    function list:size() return #sq.objs end
    function list:get(i) return sq.objs[i + 1] end
    function sq:getWorldObjects() return list end
    g.squares[x .. "," .. y .. "," .. z] = sq
    return sq
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
        rec.temps = { [3] = 20, [26] = 18, [29] = 17 }
        local item = machine(sq, rec)
        local env = World.env()
        local out = Machines.advance(item, Machines.read(item, false), 30, env)
        T.eq(out.site.room, true); T.eq(out.site.z, 1)
        T.ok(out.temps[3] == nil, "day 0 is behind the batch")
        T.eq(out.temps[26], 18); T.eq(out.temps[29], 17)
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
