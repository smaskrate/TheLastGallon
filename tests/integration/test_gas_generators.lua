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
local GLOBALS = { "getGameTime", "getCell", "isServer", "isClient", "instanceof", "getClimateManager" }

local function fakeGame()
    local saved = {}
    for _, k in ipairs(GLOBALS) do saved[k] = _G[k] end
    local savedProfile, savedFail = G.profile, G.failRoll
    local g = { squares = {}, hours = 100 }
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
    G.gasSquares = {}
    function g.restore()
        for _, k in ipairs(GLOBALS) do _G[k] = saved[k] end
        G.profile, G.failRoll = savedProfile, savedFail
        G.gasSquares = {}
    end
    return g
end

local function generatorAt(g, x, y, fuel, converted)
    local sq = { objs = {} }
    function sq:getX() return x end
    function sq:getY() return y end
    function sq:getZ() return 0 end
    function sq:getObjects()
        local t = self.objs
        return { size = function() return #t end, get = function(_, i) return t[i + 1] end }
    end
    function sq:getGenerator() return self.objs[1] end
    g.squares[x .. "," .. y .. ",0"] = sq
    local o = { class = "IsoGenerator", md = { gasConverted = converted }, fuel = fuel, cond = 100, sent = 0 }
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
