-- The gas-feed commands (D-040, propane; TLG/Authority/GasHandlers.lua) on
-- the audit's mocks: what the authority does with gas.connect, gas.remove and
-- gas.status, refused requests included. Single player (no vault).
-- Run: tools\run-tests.ps1 -Entry tests/audit/run_audit.lua
require "audit/mocks"
require "TLG/Authority/Handlers"
require "TLG/Authority/ConversionHandlers"
require "TLG/Authority/GasHandlers"

local M = AUD
local H = TLG.Authority.Handlers
local G, GasFeed, Gas, Tables = TLG.Integration.Generators, TLG.Domain.GasFeed, TLG.Domain.Gas, TLG.Tables

local n = 0
local function rid()
    n = n + 1
    return "gas-" .. n
end

M.ensureWorld()

-- A generator at x,y whose conversion to gas is Commissioned (written as
-- the audit's V-01 case writes one), and a player beside it.
local function gasGenerator(x, y, fuel)
    local gen = M.square(x, y, 0):add(M.object("IsoGenerator", { fuel = fuel or 0, maxFuel = 10 }))
    local md = gen:getModData()
    md.tlgDeviceId, md.tlgEngineId = "GASD-" .. x, "GASE-" .. x
    md.tlgConv = {
        v = 1, id = "GASC-" .. x, rev = 1, conversion = "gas_generator", state = "Commissioned", t = 0,
        snap = { targetConsumerProfile = "generator_gas", fuelStorageChanges = {}, cargoAndWeightImpact = {},
            visualConfiguration = {}, workStages = {}, requiredModules = {}, requiredTools = {},
            reversalAndSalvageRules = {} },
        hours = {}, delivered = {}, workers = {}, credit = {}, deviceKey = "gen:GASD-" .. x,
        chassis = "Base.Generator", deviceKind = "generator", engineId = "GASE-" .. x,
        originalProfile = "generator_si_stock", commissionedAt = 0,
    }
    local player = M.player("gasser" .. x, M.square(x + 1, y, 0))
    return gen, player, TLG.Authority.Resolver.refForObject(gen, "generator")
end

local function ask(player, command, ref, id)
    return H.dispatch(player, command, { device = ref, requestId = id or rid() })
end

local function tanksIn(player)
    local out = {}
    for _, it in ipairs(player:getInventory().items) do
        if it:getFullType() == "Base.PropaneTank" then out[#out + 1] = it end
    end
    return out
end

local L_PER_USE = Gas.NM3_PER_USE * 93 / 32

T.case("gas: a tank from the inventory goes in and fills the buffer at once", function()
    local gen, player, ref = gasGenerator(300, 300, 0)
    T.ok(G.isGas(gen), "the conversion gives the gas profile")
    player:getInventory():AddItem(M.tank(5000))
    local r = ask(player, "gas.connect", ref)
    T.ok(r.ok, tostring(r.reason))
    T.eq(r.uses, 5000)
    T.eq(r.moved, 3840)
    T.eq(r.from, "inventory")
    T.eq(#tanksIn(player), 0, "the tank went in")
    T.near(gen:getFuel(), 3840 * L_PER_USE, 1e-6)
    T.eq(gen:getModData().tlgGas.tank.uses, 5000 - 3840)
    T.ok(G.holdsGas(gen))
end)

T.case("gas: the same request id is answered once", function()
    local gen, player, ref = gasGenerator(310, 300, 0)
    player:getInventory():AddItem(M.tank(5000))
    local id = rid()
    T.ok(ask(player, "gas.connect", ref, id).ok)
    player:getInventory():AddItem(M.tank(4000))
    local again = ask(player, "gas.connect", ref, id)
    T.ok(again.duplicate, "answered from the ledger")
    T.eq(#tanksIn(player), 1, "no second tank taken")
end)

T.case("gas: refused requests leave the record and the inventory as they were", function()
    local gen, player, ref = gasGenerator(320, 300, 0)
    player:getInventory():AddItem(M.tank(5000))
    T.ok(ask(player, "gas.connect", ref).ok)
    player:getInventory():AddItem(M.tank(2000))
    local before, fuel = Tables.deepCopy(gen:getModData().tlgGas), gen:getFuel()
    T.eq(ask(player, "gas.connect", ref).reason, "tank_connected")
    T.ok(Tables.deepEqual(gen:getModData().tlgGas, before), "the record as it was")
    T.eq(gen:getFuel(), fuel)
    T.eq(#tanksIn(player), 1, "the second tank stays in the inventory")
    -- Out of reach.
    local far = M.player("far", M.square(340, 340, 0))
    far:getInventory():AddItem(M.tank(100))
    T.eq(ask(far, "gas.connect", ref).reason, "no_access")
    T.eq(#tanksIn(far), 1)
    -- A generator not converted to gas.
    local plain = M.square(330, 300, 0):add(M.object("IsoGenerator", { fuel = 0, maxFuel = 10 }))
    local p2 = M.player("plain", M.square(331, 300, 0))
    p2:getInventory():AddItem(M.tank(100))
    T.eq(ask(p2, "gas.connect", TLG.Authority.Resolver.refForObject(plain, "generator")).reason, "not_gas_generator")
    T.eq(plain:getModData().tlgGas, nil)
    -- No tank with gas left anywhere near.
    local _, p3, ref3 = gasGenerator(350, 300, 0)
    p3:getInventory():AddItem(M.tank(0))
    T.eq(ask(p3, "gas.connect", ref3).reason, "no_propane_tank")
    T.eq(ask(p3, "gas.remove", ref3).reason, "no_tank")
end)

T.case("gas: a converted generator from a save of before the feed still holds petrol: drain it first", function()
    local gen, player, ref = gasGenerator(360, 300, 3)
    player:getInventory():AddItem(M.tank(5000))
    T.ok(not G.holdsGas(gen), "its litres are petrol")
    local r = ask(player, "gas.connect", ref)
    T.eq(r.reason, "not_drained")
    T.eq(#tanksIn(player), 1)
    T.eq(gen:getModData().tlgGas, nil)
    -- Its liquid paths answer as for any generator.
    local ep = TLG.Authority.Resolver.resolve(ref, H.context(player))
    local rec = ep:read()
    T.ok(rec ~= nil, "the fuel record reads")
    T.near(TLG.Domain.Supply.total(rec), 3, 1e-6)
end)

T.case("gas: a tank on the floor beside the generator is taken when the inventory has none", function()
    local gen, player, ref = gasGenerator(370, 300, 0)
    local tank = M.tank(800)
    local floor = M.square(371, 301, 0)
    M.onFloor(floor, tank)
    local r = ask(player, "gas.connect", ref)
    T.ok(r.ok, tostring(r.reason))
    T.eq(r.from, "floor")
    T.eq(#floor.worldObjects, 0, "taken off the floor")
    T.eq(tank:getWorldItem(), nil)
end)

T.case("gas: the tank comes out with the propane not burned, less at most a use", function()
    local gen, player, ref = gasGenerator(380, 300, 0)
    player:getInventory():AddItem(M.tank(5000))
    T.ok(ask(player, "gas.connect", ref).ok)
    local r = ask(player, "gas.remove", ref)
    T.ok(r.ok, tostring(r.reason))
    T.ok(r.uses == 5000 or r.uses == 4999, "uses back: " .. tostring(r.uses))
    local back = tanksIn(player)
    T.eq(#back, 1)
    T.eq(H.tankUses(back[1]), r.uses, "the tank item holds those uses")
    T.eq(gen:getModData().tlgGas.tank, nil)
    T.ok(gen:getFuel() < L_PER_USE, "less than a use stays in the buffer")
end)

T.case("gas: status reads the buffer and the tank", function()
    local gen, player, ref = gasGenerator(390, 300, 0)
    player:getInventory():AddItem(M.tank(5000))
    T.ok(ask(player, "gas.connect", ref).ok)
    local s = H.dispatch(player, "gas.status", { device = ref, requestId = rid() })
    T.ok(s.ok)
    T.ok(s.gas and s.holdsGas)
    T.near(s.fuel, 3840 * L_PER_USE, 1e-6)
    T.near(s.propaneKg, Gas.toKg("propane", 3840 * Gas.NM3_PER_USE), 1e-6)
    T.eq(s.tankUses, 1160)
    T.eq(s.cap, 10)
end)

T.case("gas: over connect, hourly steps, refills and removal no propane is made or lost", function()
    local gen, player, ref = gasGenerator(400, 300, 0)
    player:getInventory():AddItem(M.tank(5000))
    T.ok(ask(player, "gas.connect", ref).ok)
    local burned = 0
    for i = 1, 12 do
        local step = 0.015 * i
        burned = burned + step
        gen:setFuel(gen:getFuel() - step)
        G.gasRefill(gen)
    end
    local r = ask(player, "gas.remove", ref)
    T.ok(r.ok)
    local left = GasFeed.current(gen:getModData().tlgGas, gen:getFuel()).propane or 0
    local total = r.uses * Gas.NM3_PER_USE + left + burned * 32 / 93
    T.near(total, 5000 * Gas.NM3_PER_USE, 1e-6, "tank + buffer + burned = what went in")
end)
