require "support/fixtures"
-- The handlers' adapters register game events when they load (TLG/Boot); a
-- stand-in event list takes them (as tests/authority/test_sample.lua).
local savedEvents = Events
Events = setmetatable({}, { __index = function(t, k)
    local e = { Add = function() end }
    rawset(t, k, e)
    return e
end })
require "TLG/Authority/MachineHandlers"
Events = savedEvents
local H, Machines, World, Process = TLG.Authority.Handlers, TLG.Integration.Machines, TLG.World, TLG.Domain.Process

-- Stand-ins for the game calls a machine command makes: global ModData, the
-- clock, the cell's squares and a warm day (as
-- tests/integration/test_machine_sites.lua). Installed for one case and
-- removed again.
local GLOBALS = { "ModData", "getGameTime", "getCell", "getClimateManager", "isServer", "isClient", "getWorld" }

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
    local cm, values, world = {}, {}, {}
    function cm:getAirTemperatureForSquare() return 22 end
    function cm:getTemperature() return 22 end
    function values:getDayLightLagged() return 0.5 end
    function cm:getClimateValuesCopy() return values end
    getClimateManager = function() return cm end
    function world:isHydroPowerOn() return false end
    getWorld = function() return world end
    isServer = function() return false end
    isClient = function() return false end
    local md = World.get()
    md.v, md.calendar, md.climateLog = 1, { dayOfYear = 180, hourOfDay = 0 }, { [0] = { t = 22, rh = 0.7 } }
    function g.restore()
        for _, k in ipairs(GLOBALS) do _G[k] = saved[k] end
    end
    return g
end

local function square(g, x, y)
    local sq = { x = x, y = y, objs = {} }
    function sq:getX() return self.x end
    function sq:getY() return self.y end
    function sq:getZ() return 0 end
    function sq:isInARoom() return true end
    local list = {}
    function list:size() return #sq.objs end
    function list:get(i) return sq.objs[i + 1] end
    function sq:getWorldObjects() return list end
    g.squares[x .. "," .. y .. ",0"] = sq
    return sq
end

-- A pot still lying on `sq` (machines are items on the ground, D-015).
local function potStill(sq, rec)
    local item, wi, md = {}, {}, { tlgProc = rec }
    function wi:getSquare() return item.on end
    function wi:getItem() return item end
    function item:getFullType() return "TLG.PotStill" end
    function item:getModData() return md end
    function item:getWorldItem() return item.on and wi or nil end
    function item:getID() return 7 end
    item.on, item.wi = sq, wi
    sq.objs[#sq.objs + 1] = wi
    return item
end

-- Moves as the game makes them: off the ground into the inventory, or onto
-- a square.
local function lift(item)
    local sq = item.on
    for i = #sq.objs, 1, -1 do
        if sq.objs[i] == item.wi then table.remove(sq.objs, i) end
    end
    item.on = nil
end

local function place(item, sq)
    item.on = sq
    sq.objs[#sq.objs + 1] = item.wi
end

-- The requesting player, carrying `carried` (or nothing); no wood, no cans.
local function player(carried)
    local p, inv, none = {}, {}, {}
    function none:size() return 0 end
    function inv:getItemWithIDRecursiv(id)
        if carried and carried:getWorldItem() == nil and carried:getID() == id then return carried end
        return nil
    end
    function inv:getAllEvalRecurse() return none end
    function inv:getFirstTypeRecurse() return nil end
    function p:getInventory() return inv end
    function p:getUsername() return "tester" end
    function p:getSquare() return nil end
    function p:getPerkLevel() return 0 end
    return p
end

-- A request naming the machine as the menu does (Machines.refFor).
local requests = 0
local function req(item, extra)
    requests = requests + 1
    local args = { requestId = "machine-" .. requests, target = Machines.refFor(item) }
    for k, v in pairs(extra or {}) do args[k] = v end
    return args
end

-- A pot still distilling 33.3 L of wash from hour 2 with 27 kg of wood, and
-- the wood it burns per hour (6 kW at 4.2 kWh/kg and 45 %).
local function distilling(id)
    local p = Process.new({ id = id, machine = "pot_still", t = 2 })
    p = Process.addFirebox(p, 27).proc
    p = Process.load(p, "ethanol_distill", { ethanol = 3.3, water = 30 }).proc
    return Process.start(p, 2).proc
end

local function burnPerHour()
    local m = TLG.Registry.need("machine", "pot_still")
    return TLG.Registry.need("recipe", "ethanol_distill").stages[1].heatKW / (m.firebox.kwhPerKg * m.firebox.efficiency)
end

-- Stage hours done (heating up 1 h, then distilling).
local function work(rec)
    local done = 0
    for i, st in ipairs(rec.recipe.params.stages) do
        if i < rec.stage then done = done + (st.hours or 0) elseif i == rec.stage then done = done + rec.stageDone end
    end
    return done
end

-- Placed at 2, accessed (site, seen), picked up with the game's Grab at 3.
local function carriedStill(g, id)
    local sq = square(g, 1, 1)
    local still = potStill(sq, distilling(id))
    Machines.write(still, Machines.advance(still, Machines.read(still, false), 2, World.env()))
    g.now = 3
    lift(still)
    Machines.pickedUp(still, 3)
    return still, sq
end

local function inGame(fn)
    local g = fakeGame(2)
    local ok, err = pcall(fn, g)
    g.restore()
    if not ok then error(err, 0) end
end

T.case("authority: a carried machine answers Status only", function()
    inGame(function(g)
        local still = carriedStill(g, "P1")
        local held = TLG.Tables.deepCopy(still:getModData().tlgProc)
        g.now = 4
        local p = player(still)
        for _, c in ipairs({ "machine.addFuel", "machine.collect", "machine.pause", "machine.resume", "machine.abort" }) do
            local r = H.commands[c](p, req(still, { destination = { kind = "item", id = 99 } }))
            T.eq(r.ok, false, c)
            T.eq(r.reason, "not_placed", c)
        end
        T.ok(TLG.Tables.deepEqual(held, still:getModData().tlgProc), "the record is untouched")
        local s = H.commands["machine.status"](p, req(still))
        T.eq(s.ok, true)
        T.eq(s.state, "Paused")
        T.eq(s.pause, "not_placed")
        T.near(work(still:getModData().tlgProc), 1, 1e-9, "the hour it stood, none carried")
        T.near(s.firebox, 27 - burnPerHour(), 1e-9, "wood burned only while it stood")
    end)
end)

T.case("authority: a placed machine takes the same commands", function()
    inGame(function(g)
        local still = potStill(square(g, 1, 1), distilling("P2"))
        local p = player(nil)
        g.now = 3
        T.eq(H.commands["machine.addFuel"](p, req(still)).reason, "needs_wood", "refused only for want of wood")
        T.eq(H.commands["machine.collect"](p, req(still, { destination = { kind = "item", id = 99 } })).reason,
            "no_destination", "refused only for want of a can")
        local r = H.commands["machine.pause"](p, req(still))
        T.eq(r.ok, true)
        T.eq(r.state, "Paused")
        r = H.commands["machine.resume"](p, req(still))
        T.eq(r.ok, true)
        T.eq(r.state, "Processing")
        r = H.commands["machine.abort"](p, req(still))
        T.eq(r.ok, true)
        T.eq(still:getModData().tlgProc.state, "OutputReady", "the spirit made so far kept")
    end)
end)

T.case("authority: a Resume sent for a carried machine cannot make its carried hours count", function()
    inGame(function(g)
        local still, sq = carriedStill(g, "P3")
        g.now = 4
        T.eq(H.commands["machine.resume"](player(still), req(still)).reason, "not_placed")
        -- Back down on the tile it came from, two hours later. The Resume used
        -- to be taken: the batch then counted from it, carried hours included.
        g.now = 6
        place(still, sq)
        Machines.putDown(still, 6)
        local rec = Machines.advance(still, Machines.read(still, false), 7, World.env())
        T.near(work(rec), 2, 1e-9, "an hour before the pickup and an hour since the put-down")
        T.near(rec.firebox, 27 - 2 * burnPerHour(), 1e-9, "wood burned only while it stood")
    end)
end)
