-- Campaign balance profiles (docs/balance.md). A profile scales the exposure
-- rates only; the mapping from exposure to suitability (grades, consumer
-- effects) is separate so campaign speed can be tuned coherently.
-- Profile changes are recorded as dated history entries (Climate history) so
-- that past intervals keep the profile that was active at the time.
require "TLG/Core"

TLG.Domain = TLG.Domain or {}
TLG.Domain.Balance = TLG.Domain.Balance or {}
local Balance = TLG.Domain.Balance

Balance.REVISION = 1

Balance.profiles = {
    default = { id = "default", agingMul = 1.0, breathingMul = 1.0, microbialMul = 1.0 },
    fast = { id = "fast", agingMul = 2.0, breathingMul = 1.5, microbialMul = 1.5 },
    slow = { id = "slow", agingMul = 0.5, breathingMul = 0.7, microbialMul = 0.7 },
    off = { id = "off", agingMul = 0.0, breathingMul = 0.0, microbialMul = 0.0 },
}

-- Microbial growth (per hour, free water present) and die-off (dry).
Balance.MICROBIAL_GROWTH = 0.004
Balance.MICROBIAL_DECAY = 0.001
-- Aging multiplier for damaged containers: 1 + AGING_DAMAGE * (1 - cond).
Balance.AGING_DAMAGE = 0.5
-- Moisture ingress multiplier for damaged containers.
Balance.BREATHING_DAMAGE = 3.0
-- Moisture ingress multiplier for sealed (non-vented) containers.
Balance.SEALED_BREATHING = 0.05
-- Gas leak multiplier for damaged vessels.
Balance.LEAK_DAMAGE = 4.0

-- Grade thresholds on the blend degradation index, with UI hysteresis.
Balance.GRADES = { { id = "good", below = 1.0 }, { id = "weathered", below = 2.0 }, { id = "poor", below = math.huge } }
Balance.GRADE_HYSTERESIS = 0.08

function Balance.profile(id)
    return Balance.profiles[id] or Balance.profiles.default
end

return Balance
