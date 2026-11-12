require "support/fixtures"
require "TLG/Integration/Containers"
-- Generators registers its installer through Boot, which hooks the game's
-- Events as it loads: a stand-in for this require only (see Boot.lua).
local savedEvents = Events
Events = setmetatable({}, { __index = function() return { Add = function() end } end })
require "TLG/Integration/Generators"
require "TLG/Authority/Resolver"
Events = savedEvents
local G, GasFeed, Gas, Tables = TLG.Integration.Generators, TLG.Domain.GasFeed, TLG.Domain.Gas, TLG.Tables

-- The adapter's gas paths (D-040) on stand-ins for a generator, its square
-- and the clock. The conversion is stood in for by the profile: a generator
-- whose mod data says gasConverted has the gas profile.
local GLOBALS = { "getGameTime", "getCell", "isServer", "isClient", "instanceof", "getClimateManager", "ModData" }
local GZ, Gasifier = TLG.Integration.Gasifiers, TLG.Domain.Gas.Gasifier

local function fakeGame()
    local saved = {}
    for _, k in ipairs(GLOBALS) do saved[k] = _G[k] end
    local savedProfile, savedFail = G.profile, G.failRoll
    local g = { squares = {}, hours = 100, store = {} }
    ModData = { getOrCreate = function(k)
        g.store[k] = g.store[k] or { nextId = 1, seed = 7 }
        return g.store[k]
    end }
    local clock = {}
    function clock:getWorldAgeHours() return g.hours end
    getGameTime = function() return clock end
    local cell = {}
    function cell:getGridSquare(x, y, z) return g.squares[x .. "," .. y .. "," .. z] end
    getCell = function() return cell end
    instanceof = function(o, class) return type(o) == "table" and o.class == class end
    isServer = function() return false end
    isClient = function() return false end
    getClimateManager = function() return { getTemperature = function() return 20 end } end
    G.profile = function(gen) return gen:getModData().gasConverted and "generator_gas" or "generator_si_stock" end
    G.failRoll = function() return 1 end
    G.gasSquares, G.woodgasWait = {}, {}
    function g.restore()
        for _, k in ipairs(GLOBALS) do _G[k] = saved[k] end
        G.profile, G.failRoll = savedProfile, savedFail
        G.gasSquares, G.woodgasWait = {}, {}
    end
    return g
end

local function list(t)
    return { size = function() return #t end, get = function(_, i) return t[i + 1] end }
end

-- A floor tile: its objects (a generator first) and the items lying on it.
local function squareAt(g, x, y)
    local key = x .. "," .. y .. ",0"
    if g.squares[key] then return g.squares[key] end
    local sq = { objs = {}, wobjs = {} }
    function sq:getX() return x end
    function sq:getY() return y end
    function sq:getZ() return 0 end
    function sq:getObjects() return list(self.objs) end
    function sq:getWorldObjects() return list(self.wobjs) end
    function sq:getGenerator()
        local o = self.objs[1]
        return o and o.class == "IsoGenerator" and o or nil
    end
    g.squares[key] = sq
    return sq
end

local function generatorAt(g, x, y, fuel, converted)
    local sq = squareAt(g, x, y)
    -- A converted generator has a project (tlgConv), which keeps it on the
    -- refills' list before it has a gas record.
    local o = { class = "IsoGenerator", md = { gasConverted = converted, tlgConv = converted and { v = 1 } or nil },
        fuel = fuel, cond = 100, sent = 0, load = 0.015 }
    -- The hourly step, as getTotalPowerUsing gives it (load x setting).
    function o:getTotalPowerUsing() return self.load end
    function o:getModData() return self.md end
    function o:getFuel() return self.fuel end
    -- As the game keeps it: a float clamped to 0-10 (BC IsoGenerator.setFuel).
    function o:setFuel(f) self.fuel = math.max(0, math.min(10, f)) end
    function o:getMaxFuel() return 10 end
    function o:getSquare() return sq end
    function o:transmitModData() self.sent = self.sent + 1 end
    function o:getCondition() return self.cond end
    function o:setCondition(c) self.cond = c end
    function o:getGeneratorItemType() return "Base.Generator" end
    function o:getObjectIndex() return 0 end
    sq.objs[1] = o
    return o, sq
end

-- A gasifier item lying on tile (x, y); `moveTo` puts it on another tile,
-- `pickUp` takes it off the floor.
local function gasifierAt(g, x, y, id)
    local item = { id = id or 900, md = {}, synced = 0 }
    local wi = {}
    function wi:getItem() return item end
    function wi:getSquare() return item.sq end
    function wi:transmitModData() end
    function item:getFullType() return "TLG.Gasifier" end
    function item:getID() return self.id end
    function item:getModData() return self.md end
    function item:syncItemFields() self.synced = self.synced + 1 end
    function item:getWorldItem() return self.sq and wi or nil end
    function item:moveTo(nx, ny)
        if self.sq then
            for i, w in ipairs(self.sq.wobjs) do
                if w == wi then table.remove(self.sq.wobjs, i) break end
            end
        end
        self.sq = nx and squareAt(g, nx, ny) or nil
        if self.sq then self.sq.wobjs[#self.sq.wobjs + 1] = wi end
    end
    function item:pickUp() self:moveTo(nil) end
    item:moveTo(x, y)
    return item
end

-- Loads and lights a gasifier at the clock's hour.
local function lightGasifier(g, item, kg)
    local st = GZ.read(item, true)
    st = Gasifier.load(st, { firewood = kg }, g.hours).st
    st = Gasifier.start(st, g.hours).st
    st.site = GZ.siteOf(GZ.square(item))
    GZ.write(item, st)
    return st
end

-- A gas record with a tank of `uses` and nothing burned yet.
local function connect(gen, uses)
    local r = GasFeed.connect(GasFeed.new({ id = "GS-T", t = 100 }), uses, 100)
    r.rec.fuel = gen:getFuel()
    G.writeGas(gen, r.rec)
end

local function inGame(name, fn)
    T.case(name, function()
        local g = fakeGame()
        local ok, err = pcall(fn, g)
        g.restore()
        if not ok then error(err, 0) end
    end)
end

inGame("integration: the minute pass fills a gas generator from its tank and writes only when gas moves", function(g)
    local gen = generatorAt(g, 5, 5, 0, true)
    connect(gen, 5000)
    T.ok(G.gasSquares["5,5,0"], "watched once it has a record")
    G.gasMinute()
    local rec = gen.md.tlgGas
    T.eq(rec.tank.uses, 5000 - 3840)
    T.near(gen.fuel, 3840 * Gas.NM3_PER_USE * 93 / 32, 1e-6)
    T.eq(rec.fuel, gen.fuel, "the litres as the game keeps them")
    T.ok(G.holdsGas(gen))
    G.gasMinute()
    T.ok(rawequal(gen.md.tlgGas, rec), "a full buffer writes nothing")
    -- An hourly step of 0.015 L, then the next pass.
    gen.fuel = gen.fuel - 0.015
    g.hours = 101
    G.gasMinute()
    local after = gen.md.tlgGas
    T.ok(not rawequal(after, rec), "the step was refilled")
    T.eq(rec.tank.uses - after.tank.uses, Gas.nm3ToUses((10 - (rec.fuel - 0.015)) * 32 / 93))
    T.ok(gen.fuel <= 10 and 10 - gen.fuel < Gas.NM3_PER_USE * 93 / 32, "less than one use below the cap")
end)

inGame("integration: a converted generator that holds petrol is not refilled with gas", function(g)
    local gen = generatorAt(g, 6, 5, 3, true)
    local r = GasFeed.connect(GasFeed.new({ id = "GS-P", t = 100 }), 100, 100)
    gen.md.tlgGas = r.rec
    T.ok(not G.holdsGas(gen), "the litres are not gas")
    T.eq(G.gasRefill(gen), 0)
    T.eq(gen.fuel, 3)
    T.eq(gen.md.tlgGas.tank.uses, 100)
    -- Not converted: no gas either.
    local stock = generatorAt(g, 7, 5, 0, false)
    stock.md.tlgGas = Tables.deepCopy(r.rec)
    T.eq(G.gasRefill(stock), 0)
end)

inGame("integration: the minute pass drops squares that lost their generator and keeps unloaded ones", function(g)
    local gen, sq = generatorAt(g, 8, 5, 0, true)
    connect(gen, 10)
    G.gasSquares["9,9,0"] = true
    sq.objs = {}
    G.gasMinute()
    T.eq(G.gasSquares["8,5,0"], nil, "no generator there now")
    T.ok(G.gasSquares["9,9,0"], "a square not loaded stays")
end)

inGame("integration: while it holds gas the generator is read and evaluated as gas", function(g)
    local gen = generatorAt(g, 10, 5, 0, true)
    connect(gen, 5000)
    G.gasRefill(gen)
    local e, s = G.evaluate(gen)
    T.ok(e.compatible, table.concat(e.reasons, ","))
    T.eq(s.storage, "gas_buffer")
    T.ok((s.q.propane or 0) > 3, "the buffer's propane")
    local Res = TLG.Authority.Resolver
    local ep = Res.resolve({ kind = "generator", x = 10, y = 5, z = 0, index = 0 }, { now = 100 })
    T.ok(ep ~= nil, "the endpoint resolves")
    local rec, why = ep:read()
    T.eq(rec, nil)
    T.eq(why, "gas_generator", "pours, drains, samples and status are refused")
end)

inGame("integration: liquid written where the gas burned out lets the gas record go, keeping its tank", function(g)
    local gen = generatorAt(g, 11, 5, 0, true)
    connect(gen, 5000)
    G.gasRefill(gen)
    local uses = gen.md.tlgGas.tank.uses
    gen.fuel = 0
    T.ok(not G.holdsGas(gen), "burned out")
    gen.fuel = 4
    G.writeSidecar(gen, TLG.Domain.Supply.new({ id = "G-1", storage = "generator_tank", cap = 10,
        q = { gasoline = 4 }, t = 100 }))
    T.eq(gen.md.tlgGas.fuel, 0)
    T.ok(Tables.isEmpty(gen.md.tlgGas.buf))
    T.eq(gen.md.tlgGas.tank.uses, uses)
    T.ok(not G.holdsGas(gen), "the petrol is not taken for gas")
    T.eq(G.gasRefill(gen), 0, "no gas goes in on top of it")
end)

inGame("integration: wear is charged on the gas record's litres", function(g)
    local gen = generatorAt(g, 12, 5, 0, true)
    connect(gen, 5000)
    G.gasRefill(gen)
    local written = gen.md.tlgGas.fuel
    gen.fuel = written - 1
    G.chargeWear(gen)
    local w = gen.md[G.WEAR_KEY]
    T.ok(w ~= nil, "wear recorded")
    T.near(w.charged, 1, 1e-6, "one litre-equivalent burned")
    T.ok(string.find(w.k, "GS-T", 1, true) ~= nil, "keyed on the gas record")
    -- The refill after it starts the wear key again from the new record.
    G.gasRefill(gen)
    G.chargeWear(gen)
    T.near(gen.md[G.WEAR_KEY].charged, 0, 1e-6)
end)

-- Wood gas (D-040): no tank, a lit gasifier within two tiles.
local NM3_PER_L = 32 / 5

inGame("integration: without a tank a lit gasifier beside the generator feeds it one step and a margin", function(g)
    local gen = generatorAt(g, 20, 5, 0, true)
    local item = gasifierAt(g, 21, 6)
    lightGasifier(g, item, 100)
    G.watchGas(gen)
    -- Warming: no gas yet, and the scan waits before the next.
    g.hours = 100.2
    G.gasMinute()
    T.eq(gen.fuel, 0)
    T.eq(gen.md.tlgGas, nil, "nothing written")
    T.ok(G.woodgasWait["20,5,0"] ~= nil)
    g.hours = 100.3
    local before = item.md.tlgGasifier
    G.gasMinute()
    T.ok(rawequal(item.md.tlgGasifier, before), "not scanned while it waits")
    -- Warmed: the room up to one step and the margin comes from its buffer.
    g.hours = 101
    G.gasMinute()
    local cap = 0.015 + GasFeed.MARGIN
    T.near(gen.fuel, cap, 1e-9)
    local rec = gen.md.tlgGas
    T.near(rec.buf.woodgas, cap * NM3_PER_L, 1e-9)
    T.eq(rec.fuel, gen.fuel)
    T.eq(rec.tank, nil)
    T.ok(G.gasSquares["20,5,0"])
    local st = item.md.tlgGasifier
    T.eq(st.state, "Processing", "the draw took its buffer below full")
    T.near(st.totals.delivered, cap * NM3_PER_L, 1e-9)
    T.ok(G.holdsGas(gen))
    local e = G.evaluate(gen)
    T.ok(e.compatible, table.concat(e.reasons, ","))
    -- The hour's step, then the next minute's refill.
    gen.fuel = gen.fuel - 0.015
    T.ok(G.holdsGas(gen), "the margin left still reads as gas")
    g.hours = 102 + 1 / 60
    G.gasMinute()
    T.near(gen.fuel, cap, 1e-9)
    T.near(item.md.tlgGasifier.totals.delivered, (cap + 0.015) * NM3_PER_L, 1e-9)
    -- A bigger load: the next refill fills to the new step.
    gen.load = 0.035
    g.hours = 102.5
    G.gasMinute()
    T.near(gen.fuel, 0.035 + GasFeed.MARGIN, 1e-9)
end)

inGame("integration: a gasifier put out or picked up feeds no more; one moved to another tile goes out", function(g)
    local gen = generatorAt(g, 30, 5, 0, true)
    local item = gasifierAt(g, 30, 7)
    lightGasifier(g, item, 100)
    G.watchGas(gen)
    g.hours = 101
    G.gasMinute()
    T.ok(gen.fuel > 0.015)
    -- Picked up: not on the floor, so not found.
    gen.fuel = GasFeed.MARGIN
    item:pickUp()
    g.hours = 102
    G.gasMinute()
    T.near(gen.fuel, GasFeed.MARGIN, 1e-12, "no gas")
    -- Put down on another tile within reach: put out at its next read, its
    -- wood kept, and nothing given.
    item:moveTo(31, 6)
    G.watchGas(gen)
    g.hours = 102.5
    local hopper = Gasifier.status(item.md.tlgGasifier).hopperKg
    G.gasMinute()
    T.near(gen.fuel, GasFeed.MARGIN, 1e-12)
    local st = item.md.tlgGasifier
    T.eq(st.state, "Ready", "out")
    T.eq(st.buffer, 0)
    T.ok(Gasifier.status(st).hopperKg > 0 and Gasifier.status(st).hopperKg <= hopper, "its wood kept")
    -- Relit there, then put out by the player: no more gas.
    lightGasifier(g, item, 1)
    g.hours = 104
    G.watchGas(gen)
    G.gasMinute()
    T.ok(gen.fuel > 0.015, "fed from its new tile")
    local p = Gasifier.putOut(GZ.advance(item, item.md.tlgGasifier, g.hours), g.hours)
    GZ.write(item, p.st)
    gen.fuel = GasFeed.MARGIN
    g.hours = 105
    G.watchGas(gen)
    G.gasMinute()
    T.near(gen.fuel, GasFeed.MARGIN, 1e-12, "the generator runs out at its next step")
end)

inGame("integration: a tank with uses left is the source; an empty one lets the gasifier feed", function(g)
    local gen = generatorAt(g, 40, 5, 0, true)
    local item = gasifierAt(g, 41, 5)
    lightGasifier(g, item, 100)
    connect(gen, 5000)
    g.hours = 101
    G.gasMinute()
    T.ok(gen.fuel > 9.99, "filled from the tank to its capacity")
    T.ok((gen.md.tlgGas.buf.woodgas or 0) == 0, "no wood gas")
    T.eq(item.md.tlgGasifier.totals.delivered, 0, "the gasifier was not drawn from")
    -- The tank empty, the buffer burned down: wood gas.
    gen.md.tlgGas.tank.uses = 0
    gen.fuel = 0.0005
    g.hours = 102
    G.gasMinute()
    T.near(gen.fuel, 0.015 + GasFeed.MARGIN, 1e-9)
    T.ok(gen.md.tlgGas.buf.woodgas > 0)
    T.ok((gen.md.tlgGas.buf.propane or 0) > 0, "the propane left stays in the mix")
end)

inGame("integration: a generator that holds petrol takes no wood gas; the watch keeps gas generators only", function(g)
    local gen = generatorAt(g, 50, 5, 3, true)
    local item = gasifierAt(g, 50, 6)
    lightGasifier(g, item, 100)
    g.hours = 101
    T.eq(G.gasRefill(gen), 0)
    T.eq(gen.fuel, 3)
    T.eq(item.md.tlgGasifier.totals.delivered, 0)
    -- Loaded squares: a generator with a conversion is watched, and dropped
    -- at the minute pass when the conversion is not to gas.
    local flex = generatorAt(g, 52, 5, 0, false)
    flex.md.tlgConv = { v = 1 }
    G.onLoadSquare(flex:getSquare())
    T.ok(G.gasSquares["52,5,0"], "watched on load")
    G.gasMinute()
    T.eq(G.gasSquares["52,5,0"], nil, "not gas: dropped")
    gen.md.tlgConv = { v = 1 }
    G.onLoadSquare(gen:getSquare())
    G.gasMinute()
    T.ok(G.gasSquares["50,5,0"], "a gas conversion stays watched without a record")
    -- A gasifier's action watches the generators beside it.
    G.gasSquares = {}
    T.eq(GZ.watchGenerators(item), 2)
    T.ok(G.gasSquares["50,5,0"] and G.gasSquares["52,5,0"])
end)

inGame("integration: hours away: no draw, the gasifier goes out its hold after the last one", function(g)
    local gen = generatorAt(g, 60, 5, 0, true)
    local item = gasifierAt(g, 60, 6)
    lightGasifier(g, item, 100)
    G.watchGas(gen)
    g.hours = 101
    G.gasMinute()
    local fed = item.md.tlgGasifier.totals.fed
    -- Away for ten hours: the game burned the generator's buffer (one step,
    -- then the margin was not enough) and switched it off.
    gen.fuel = 0
    g.hours = 111
    G.gasMinute()
    T.eq(gen.fuel, 0, "nothing to give: the fire went out")
    local st = GZ.advance(item, item.md.tlgGasifier, g.hours)
    T.eq(st.state, "Ready")
    T.near(st.totals.fed - fed, 0.1024 / 2.2, 1e-6, "only the wood for the gas drawn")
end)
