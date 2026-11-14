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
        T.ok(type(s.progress) == "table" and s.progress.workLeft > 0, "a batch in it: how far it is")
        T.near(s.progress.stageDone, still:getModData().tlgProc.stageDone, 1e-12)
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
        -- An hour into distilling (the heat-up hour makes no spirit).
        g.now = 4
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

-- A fermentation vessel lying on `sq`, with a mash loaded and started at
-- hour 2.
local function fermenting(sq, id)
    local rec = Process.new({ id = id, machine = "fermenter_barrel", t = 2 })
    rec = Process.start(Process.load(rec, "ethanol_ferment", { sugar_eq = 10, water = 50 }).proc, 2).proc
    local item = potStill(sq, rec)
    function item:getFullType() return "TLG.FermenterVessel" end
    return item
end

T.case("authority: Status of a running batch gives an estimate the batch then keeps", function()
    inGame(function(g)
        local vessel = fermenting(square(g, 1, 1), "P9")
        local p = player(nil)
        -- Just loaded: the first Status already has the temperature to estimate with.
        local s = H.commands["machine.status"](p, req(vessel))
        T.eq(s.state, "Processing"); T.eq(s.stage, "prepare")
        T.ok(type(s.siteC) == "number", "the site's temperature is known at the first Status")
        T.ok(type(s.progress) == "table" and type(s.progress.etaHours) == "number", "an estimate from the first Status")
        T.near(s.progress.workLeft, 97, 1e-9)
        -- Ten hours in, in a room at 22 C: full rate, the same end.
        g.now = 12
        s = H.commands["machine.status"](p, req(vessel))
        T.eq(s.stage, "ferment")
        T.near(s.progress.stageDone, 9, 1e-9); T.near(s.progress.stageHours, 96, 1e-9)
        T.ok(s.progress.tempBound == true and s.progress.slowed == nil, "22 C: not slowed")
        T.near(s.progress.etaHours, 87, 1e-9)
        local finish = g.now + s.progress.etaHours
        g.now = finish - 0.25
        T.eq(H.commands["machine.status"](p, req(vessel)).state, "Processing", "a quarter of an hour before the estimate")
        g.now = finish + 0.25
        s = H.commands["machine.status"](p, req(vessel))
        T.eq(s.state, "OutputReady", "a quarter of an hour after it")
        T.eq(s.progress, nil)
    end)
end)

-- A player carrying items of the given types ({ type, favourite }); the
-- inventory removes what the handler takes.
local function carrier(list)
    local p, inv, items = player(), {}, {}
    for i, spec in ipairs(list) do
        local item = { type = spec[1], fav = spec.favourite == true, id = 100 + i }
        function item:getFullType() return self.type end
        function item:isFavorite() return self.fav end
        function item:getID() return self.id end
        function item:getContainer() return inv end
        items[#items + 1] = item
    end
    function inv:Remove(item)
        for i = #items, 1, -1 do
            if items[i] == item then table.remove(items, i) end
        end
    end
    function inv:getAllEvalRecurse(pred)
        local out = {}
        for _, item in ipairs(items) do
            if pred(item) then out[#out + 1] = item end
        end
        return { size = function() return #out end, get = function(_, i) return out[i + 1] end }
    end
    function inv:getFirstTypeRecurse(t)
        for _, item in ipairs(items) do
            if item.type == t then return item end
        end
        return nil
    end
    function inv:getItemWithIDRecursiv() return nil end
    function p:getInventory() return inv end
    p.count = function(t)
        local n = 0
        for _, item in ipairs(items) do
            if item.type == t then n = n + 1 end
        end
        return n
    end
    return p
end

T.case("authority: Repair gives a worn, idle machine a quarter of its condition for a pipe, with a screwdriver", function()
    inGame(function(g)
        local Picks = TLG.Integration.Picks
        local sq = square(g, 10, 10)
        local worn = Process.new({ id = "M-repair", machine = "pot_still", t = 2, cond = 0.4 })
        local still = potStill(sq, worn)
        -- Nothing carried: refused, with what is missing; nothing changes.
        local r = H.dispatch(player(), "machine.repair", req(still))
        T.eq(r.ok, false); T.eq(r.reason, "needs_repair_parts")
        T.eq(table.concat(r.missing, ","), "Base.Screwdriver,Base.MetalPipe")
        T.near(still:getModData().tlgProc.cond, 0.4, 1e-12)
        -- The tool without the part, and a favourite pipe, which is left alone.
        local p = carrier({ { "Base.Screwdriver" }, { "Base.MetalPipe", favourite = true } })
        r = H.dispatch(p, "machine.repair", req(still))
        T.eq(r.reason, "needs_repair_parts"); T.eq(table.concat(r.missing, ","), "Base.MetalPipe")
        T.eq(p.count("Base.MetalPipe"), 1)
        -- Tool and part: a quarter back, one pipe gone, the screwdriver kept.
        p = carrier({ { "Base.Screwdriver_Old", favourite = true }, { "Base.MetalPipe" }, { "Base.MetalPipe" } })
        r = H.dispatch(p, "machine.repair", req(still))
        T.eq(r.ok, true); T.eq(r.command, "machine.repair"); T.eq(r.state, "Ready")
        T.near(r.cond, 0.65, 1e-12); T.eq(r.used["Base.MetalPipe"], 1)
        T.near(still:getModData().tlgProc.cond, 0.65, 1e-12)
        T.eq(p.count("Base.MetalPipe"), 1); T.eq(p.count("Base.Screwdriver_Old"), 1)
        -- Again at 65 %; at 90 % a whole quarter no longer fits: refused,
        -- nothing taken.
        r = H.dispatch(p, "machine.repair", req(still))
        T.near(r.cond, 0.9, 1e-12); T.eq(p.count("Base.MetalPipe"), 0)
        p = carrier({ { "Base.Screwdriver" }, { "Base.MetalPipe" } })
        r = H.dispatch(p, "machine.repair", req(still))
        T.eq(r.ok, false); T.eq(r.reason, "not_worn"); T.eq(p.count("Base.MetalPipe"), 1)
        T.near(still:getModData().tlgProc.cond, 0.9, 1e-12)
        T.near(Picks.REPAIR_STEP, 0.25, 1e-12)
        T.ok(Picks.repairable(0.75) and Picks.repairable(0) and not Picks.repairable(0.76) and not Picks.repairable(1)
            and not Picks.repairable(nil))
    end)
end)

T.case("authority: Repair is refused while the machine holds a batch, and a worn-out one loads again after it", function()
    inGame(function(g)
        local sq = square(g, 10, 10)
        local busy = distilling("M-busy")
        busy.cond = 0.5
        local still = potStill(sq, busy)
        local p = carrier({ { "Base.Screwdriver" }, { "Base.MetalPipe" } })
        local r = H.dispatch(p, "machine.repair", req(still))
        T.eq(r.ok, false); T.eq(r.reason, "machine_busy"); T.eq(p.count("Base.MetalPipe"), 1)
        -- Worn out: the load's plan refuses it, a repair makes it take loads again.
        local dead = Process.new({ id = "M-dead", machine = "pot_still", t = 2, cond = 0 })
        T.eq(Process.plan("ethanol_distill", { ethanol = 3.3, water = 30 }, dead).reason, "needs_repair")
        local other = potStill(square(g, 12, 10), dead)
        function other:getID() return 8 end
        r = H.dispatch(p, "machine.repair", req(other))
        T.eq(r.ok, true); T.near(r.cond, 0.25, 1e-12)
        T.eq(Process.plan("ethanol_distill", { ethanol = 3.3, water = 30 }, other:getModData().tlgProc).ok, true)
        -- The fermenter is wood: a plank and two nails, with a hammer.
        local Picks = TLG.Integration.Picks
        T.eq(Picks.repairSpec("fermenter_barrel"), Picks.REPAIRS.wood)
        T.eq(Picks.repairSpec("gasifier_stationary"), Picks.REPAIRS.metal)
        local pick = Picks.repair(carrier({ { "Base.ClubHammer" }, { "Base.Plank" }, { "Base.Nails" } }), "fermenter_barrel")
        T.eq(pick.ok, false); T.eq(table.concat(pick.missing, ","), "Base.Nails")
        pick = Picks.repair(carrier({ { "Base.Hammer" }, { "Base.Plank" }, { "Base.Nails" }, { "Base.Nails" } }), "fermenter_barrel")
        T.eq(pick.ok, true); T.eq(#pick.items, 3)
    end)
end)
