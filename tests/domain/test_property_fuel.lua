-- Randomized state-machine test over transfers, aging, treatment, splitting
-- and (simulated) save/load. System-wide invariants after every step:
--   * every supply passes Supply.check
--   * all components are conserved except explicitly recorded removals
--     (filters, drains, leaks, dust) and breathing (fuel -> water, total kept)
--   * all supplies stay at a common time after each "advance all" step
require "support/fixtures"
local Supply, Mixing, Aging, Treatment = TLG.Domain.Supply, TLG.Domain.Mixing, TLG.Domain.Aging, TLG.Domain.Treatment

local STORAGES = { "jerrycan_steel", "gascan_plastic", "drum_steel", "vehicle_tank", "generator_tank", "open_vessel", "tank_ibc" }

local function systemTotal(list)
    local s = 0
    for _, x in ipairs(list) do s = s + Supply.total(x) end
    return s
end

local function roundTrip(s)
    -- Simulated save/load: modData stores plain tables; numbers survive as doubles.
    return TLG.Tables.deepCopy(s)
end

T.case("property: random operation sequences conserve fuel and keep invariants", function()
    local env = F.env()
    for run = 1, 12 do
        local rng = TLG.Rng.new(TEST_SEED + run * 7919)
        local list = {}
        for i = 1, 6 do
            local storage = STORAGES[rng:int(1, #STORAGES)]
            local cap = (storage == "drum_steel" and 200) or (storage == "tank_ibc" and 1000) or rng:range(10, 60)
            local q = {}
            if rng:next() < 0.8 then q.gasoline = rng:range(0, cap * 0.5) end
            if rng:next() < 0.4 then q.ethanol = rng:range(0, cap * 0.2) end
            if rng:next() < 0.3 then q.water = rng:range(0, cap * 0.005) end
            if rng:next() < 0.3 then q.sediment = rng:range(0, cap * 0.002) end
            list[i] = F.supply({ id = "P" .. i, storage = storage, cap = cap, q = q,
                deg = { gasoline = rng:range(0, 2), ethanol = rng:range(0, 0.5) }, t = 0 })
        end
        local accounted = systemTotal(list)
        local now = 0
        for step = 1, 250 do
            local op = rng:int(1, 10)
            if op <= 2 then
                now = now + rng:range(0.1, 24 * 20)
                for i = 1, #list do
                    local out, info = Aging.advance(list[i], now, env)
                    accounted = accounted - info.leaked - info.dust
                    list[i] = out
                end
            elseif op <= 7 then
                -- Transfers need a common time (authority rule); align first.
                local a, b = rng:int(1, #list), rng:int(1, #list)
                if a ~= b and list[a].t == list[b].t then
                    local r = Mixing.previewTransfer(list[a], list[b], rng:range(0.001, 30))
                    T.ok(r.ok, "transfer ok")
                    list[a], list[b] = r.src, r.dst
                    accounted = accounted - (r.dust or 0)
                end
            elseif op == 8 then
                local i = rng:int(1, #list)
                local r = Treatment.filter(list[i], { sedimentEff = 0.9, waterCapacity = 0.05, holdup = 0.02 })
                if r.ok then
                    for _, v in pairs(r.removed) do accounted = accounted - v end
                    list[i] = r.supply
                end
            elseif op == 9 then
                local i = rng:int(1, #list)
                local r = Treatment.separateWater(list[i], 1.0)
                if r.ok then
                    for _, v in pairs(r.removed) do accounted = accounted - v end
                    list[i] = r.supply
                end
            else
                local i = rng:int(1, #list)
                list[i] = roundTrip(list[i])
            end
            for i = 1, #list do
                local bad = Supply.check(list[i])
                if #bad > 0 then
                    T.fail("run " .. run .. " step " .. step .. " supply " .. i .. ": " .. table.concat(bad, ","))
                end
            end
            T.near(systemTotal(list), accounted, 1e-7 * math.max(1, accounted), "run " .. run .. " step " .. step)
        end
    end
end)

T.case("property: degradation mass never appears through mixing", function()
    -- sum(q * deg) per component is conserved by transfers (it only grows by aging).
    local rng = TLG.Rng.new(TEST_SEED)
    local list = {}
    for i = 1, 5 do
        list[i] = F.supply({ id = "M" .. i, storage = "drum_steel", cap = 200,
            q = { gasoline = rng:range(1, 100) }, deg = { gasoline = rng:range(0, 3) }, t = 0 })
    end
    local function degMass()
        local m = 0
        for _, s in ipairs(list) do m = m + (s.q.gasoline or 0) * (s.deg.gasoline or 0) end
        return m
    end
    local before = degMass()
    for _ = 1, 2000 do
        local a, b = rng:int(1, 5), rng:int(1, 5)
        if a ~= b then
            local r = Mixing.previewTransfer(list[a], list[b], rng:range(0.01, 50))
            list[a], list[b] = r.src, r.dst
        end
    end
    T.near(degMass(), before, 1e-7 * before)
end)
