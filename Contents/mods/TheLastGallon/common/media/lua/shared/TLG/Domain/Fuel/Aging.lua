-- Time advancement of a supply (FuelService.advance).
--
-- Processes, all in closed form over cumulative drivers so that advancing
-- [t0,t2] equals advancing [t0,t1] then [t1,t2] up to floating-point error:
--   oxidation   d(deg)/dt = k(t) (1 + a deg)        per aging component
--   breathing   fuel F' = -r(t) F, water W' = r(t) F (moisture exchange;
--               the displaced fuel is the evaporated fraction)
--   microbial   m' = g (1 - m) while free water exists, m' = -d m otherwise;
--               the dry->wet switch time is solved exactly
--   gas leak    q' = -l(t) q
-- Environment comes from TLG.Domain.Climate segments (day-aligned).
require "TLG/Domain/Fuel/Supply"
require "TLG/Domain/Balance"
require "TLG/Domain/Climate"

TLG.Domain.Aging = TLG.Domain.Aging or {}
local Aging = TLG.Domain.Aging
local Supply, Balance = TLG.Domain.Supply, TLG.Domain.Balance
local Registry, Tables, Num = TLG.Registry, TLG.Tables, TLG.Num

local function expm1(x)
    if math.abs(x) < 1e-5 then
        return x + x * x / 2 + x * x * x / 6
    end
    return math.exp(x) - 1
end

-- Closed-form oxidation: deg after cumulative driver K with autocatalysis a.
function Aging.oxidize(deg0, K, a)
    if K <= 0 then return deg0 end
    if a <= 0 then return deg0 + K end
    return deg0 + expm1(a * K) * (1 + a * deg0) / a
end

local function sealMultiplier(s, storage, aging)
    if storage.vented then return 1 end
    if storage.sealable and s.sealed then return 1 end
    return aging.unsealed
end

local function breathingSeal(s, storage)
    if storage.vented then return 1 end
    if storage.sealable and s.sealed then return Balance.SEALED_BREATHING end
    return 1
end

-- Composition-weighted properties that stay constant during an advance
-- (breathing scales all non-contaminant components by the same factor).
local function composition(s)
    local F, hygroNum, microbialQ = 0, 0, 0
    for _, id in ipairs(Tables.sortedKeys(s.q)) do
        local f = Registry.need("fuel", id)
        if f.role ~= "contaminant" and f.phase == "liquid" then
            local q = s.q[id]
            F = F + q
            hygroNum = hygroNum + q * (f.hygroscopic or 0)
            if f.microbial then microbialQ = microbialQ + q end
        end
    end
    local hygro, microbialFrac = 0, 0
    if F > Num.DUST then
        hygro = hygroNum / F
        microbialFrac = microbialQ / F
    end
    return F, hygro, microbialFrac
end

-- Advances `s` to world hour `toT` using `env` (a Climate instance).
-- Returns a new record and an info table; `s` is not modified.
function Aging.advance(s, toT, env)
    local out = Supply.copy(s)
    local info = { from = s.t, to = toT, waterIngress = 0, leaked = 0, dust = 0 }
    if not Num.isFinite(toT) then
        error("advance: invalid target time")
    end
    if toT < s.t - 1e-9 then
        info.reason = "clock_regression"
        return out, info
    end
    if toT <= s.t then
        return out, info
    end
    local storage = Registry.need("storage", out.storage)
    local segs = env:segments(out.t, toT, storage.thermal)
    local condAging = 1 + Balance.AGING_DAMAGE * (1 - out.cond)
    local stabLevel = math.min(out.stab, 1)

    -- Per-component aging constants.
    local agingIds, K = {}, {}
    for _, id in ipairs(Tables.sortedKeys(out.q)) do
        local f = Registry.need("fuel", id)
        if f.aging and out.deg[id] ~= nil then
            agingIds[#agingIds + 1] = id
            K[id] = 0
        end
    end

    local F0, hygro, microbialFrac = composition(out)
    local W0 = out.q.water or 0
    local C0 = Supply.waterCapacity(out)
    local Rstar = -math.huge
    if F0 > Num.DUST and W0 + F0 > 0 and W0 < C0 then
        Rstar = math.log((F0 + C0) / (W0 + F0))
    end
    local R = 0
    local m = out.mic
    local leakSum = 0
    local leakBase = storage.leakPerHour or 0
    local condLeak = 1 + Balance.LEAK_DAMAGE * (1 - out.cond)
    local condBreath = 1 + Balance.BREATHING_DAMAGE * (1 - out.cond)
    local sealB = breathingSeal(out, storage)

    for _, seg in ipairs(segs) do
        local p = seg.profile
        local dt = seg.dt
        for _, id in ipairs(agingIds) do
            local a = Registry.need("fuel", id).aging
            local k = a.rate * p.agingMul * storage.agingMul * condAging
                * math.pow(a.q10, (seg.tempC - 20) / 10)
                * sealMultiplier(out, storage, a)
                * (1 - a.stabilizerMax * stabLevel)
            K[id] = K[id] + k * dt
        end
        local r = 0
        if storage.phase == "liquid" and F0 > Num.DUST then
            r = storage.breathing * p.breathingMul * seg.rh * sealB * hygro * condBreath
        end
        if microbialFrac > 0 then
            local g = Balance.MICROBIAL_GROWTH * p.microbialMul * microbialFrac
            local d = Balance.MICROBIAL_DECAY
            local Ra, Rb = R, R + r * dt
            local dtDry, dtWet
            if Ra > Rstar then
                dtDry, dtWet = 0, dt
            elseif Rb > Rstar and r > 0 then
                dtDry = (Rstar - Ra) / r
                dtWet = dt - dtDry
            else
                dtDry, dtWet = dt, 0
            end
            if dtDry > 0 then m = m * math.exp(-d * dtDry) end
            if dtWet > 0 then m = 1 - (1 - m) * math.exp(-g * dtWet) end
        end
        R = R + r * dt
        leakSum = leakSum + leakBase * condLeak * dt
    end

    for _, id in ipairs(agingIds) do
        local a = Registry.need("fuel", id).aging
        out.deg[id] = Aging.oxidize(out.deg[id], K[id], a.autocat)
    end
    if R > 0 then
        local keep = math.exp(-R)
        for _, id in ipairs(Tables.sortedKeys(out.q)) do
            local f = Registry.need("fuel", id)
            if f.role ~= "contaminant" then
                out.q[id] = out.q[id] * keep
            end
        end
        local ingress = F0 * (1 - keep)
        out.q.water = W0 + ingress
        info.waterIngress = ingress
    end
    if leakSum > 0 and storage.phase == "gas" then
        local keep = math.exp(-leakSum)
        for _, id in ipairs(Tables.sortedKeys(out.q)) do
            local before = out.q[id]
            out.q[id] = before * keep
            info.leaked = info.leaked + (before - out.q[id])
        end
    end
    out.mic = Num.clamp(m, 0, 1)
    out.t = toT
    info.dust = Supply.normalize(out)
    return out, info
end

return Aging
