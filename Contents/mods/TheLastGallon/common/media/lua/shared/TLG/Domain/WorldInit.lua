-- World fuel-history epoch, installation policies and deterministic seeding.
--
-- The world record is created once by the authority and persisted (global
-- ModData "TLG_World"); later calls never re-create it, so reconnecting or
-- reinstalling cannot grant fresh reserves (spec §7).
--
-- Policies for discovering fuel TLG has no record of:
--   new_world     aged since the world epoch (world hour 0)
--   world_age     existing save, aged since the world epoch
--   install_now   existing save, aging starts at installation time
--   transition    existing save, starts near install_now and converges on
--                 world_age over `transitionHours`
require "TLG/Domain/Fuel/Aging"
require "TLG/Util/Rng"

TLG.Domain.WorldInit = TLG.Domain.WorldInit or {}
local WorldInit = TLG.Domain.WorldInit
local Supply, Aging = TLG.Domain.Supply, TLG.Domain.Aging
local Rng, Num = TLG.Rng, TLG.Num

WorldInit.SCHEMA = 1
WorldInit.POLICIES = { new_world = true, world_age = true, install_now = true, transition = true }
-- Fuel already in tanks/cans at the outbreak was up to this old (hours).
WorldInit.MAX_PRE_AGE = 30 * 24
-- Station reservoirs vary more (deliveries were irregular).
WorldInit.MAX_STATION_PRE_AGE = 75 * 24

function WorldInit.create(opts)
    local policy = opts.policy or "new_world"
    if not WorldInit.POLICIES[policy] then
        error("unknown init policy " .. tostring(policy))
    end
    return {
        v = WorldInit.SCHEMA,
        seed = math.floor(opts.seed or 1),
        epoch = 0,
        policy = policy,
        installedAt = opts.now or 0,
        transitionHours = opts.transitionHours or (30 * 24),
        nextId = 1,
        balanceHistory = opts.balanceHistory or {
            { from = -math.huge, id = "default", agingMul = 1, breathingMul = 1, microbialMul = 1 },
        },
    }
end

-- Allocates a stable supply id (authority only).
function WorldInit.newId(world, prefix)
    local n = world.nextId
    world.nextId = n + 1
    return string.format("%s%d-%d", prefix or "S", world.seed, n)
end

-- Start of aging for untracked original fuel under the world's policy.
local function agingStart(world, now)
    if world.policy == "install_now" then
        return world.installedAt
    end
    if world.policy == "transition" then
        return world.installedAt
    end
    return world.epoch
end

-- Builds the baseline record for original fuel discovered at `now`.
-- key: stable identity (site id, item id...) used for deterministic variation.
-- spec: { storage, cap, q = { component = quantity }, preAgeMax }
function WorldInit.baseline(world, env, key, spec, now)
    local u = Rng.unit(world.seed, key)
    local preAge = u * (spec.preAgeMax or WorldInit.MAX_PRE_AGE)
    local start = agingStart(world, now)
    local s = Supply.new({ storage = spec.storage, cap = spec.cap, q = spec.q, t = start, sealed = spec.sealed })
    -- Pre-outbreak age: advance over the preceding days with the same climate
    -- model. install_now/transition start from installation instead.
    if preAge > 0 and (world.policy == "new_world" or world.policy == "world_age") then
        s.t = start - preAge
    end
    local aged = Aging.advance(s, now, env)
    if world.policy == "transition" then
        local full = Supply.new({ storage = spec.storage, cap = spec.cap, q = spec.q, t = world.epoch - preAge, sealed = spec.sealed })
        full = Aging.advance(full, now, env)
        local w = Num.clamp((now - world.installedAt) / math.max(1, world.transitionHours), 0, 1)
        for id, d in pairs(aged.deg) do
            aged.deg[id] = d + (full.deg[id] - d) * w
        end
        aged.q = full.q
        aged.mic = aged.mic + (full.mic - aged.mic) * w
    end
    aged.t = now
    return aged
end

-- Station reservoir water at the outbreak (volume fractions). Most stations
-- stay below the stock spark engine's 0.2 % free-water tolerance; about one
-- in ten is badly contaminated (balance decision 2026-10-31, docs/balance.md).
WorldInit.STATION_WATER = { cleanMax = 0.0015, badShare = 0.1, badMin = 0.002, badMax = 0.004 }
WorldInit.STATION_SEDIMENT_MAX = 0.001

-- Deterministic contamination for a station reservoir, seeded by site id.
function WorldInit.stationContamination(world, siteKey, litres)
    local w = WorldInit.STATION_WATER
    local r = Rng.new(Rng.hash(siteKey, world.seed))
    r:next()
    local bad = r:next() < w.badShare
    local u = r:next()
    local waterFrac = bad and (w.badMin + u * (w.badMax - w.badMin)) or (u * w.cleanMax)
    local sedFrac = r:next() * WorldInit.STATION_SEDIMENT_MAX
    return { water = litres * waterFrac, sediment = litres * sedFrac }
end

-- What a station pump held at the outbreak: diesel for about one pump in
-- four, petrol for the others (D-036; the share is a design value).
-- Seeded by the pump's key, apart from its contamination's draw.
WorldInit.STATION_DIESEL_SHARE = 0.25

function WorldInit.stationProduct(world, siteKey)
    local r = Rng.new(Rng.hash(siteKey .. ":product", world.seed))
    r:next()
    return r:next() < WorldInit.STATION_DIESEL_SHARE and "diesel" or "gasoline"
end

return WorldInit
