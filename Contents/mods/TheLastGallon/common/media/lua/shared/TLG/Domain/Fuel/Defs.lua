-- Validation and accessors for FuelDefinition, StorageProfile and
-- ConsumerProfile registry entries. Content lives in TLG/Content/*.
--
-- Canonical units (docs/balance.md): liquids in litres (L), gases in normal
-- cubic metres (Nm3), solids in kilograms (kg), energy in MJ (fuel) or kWh
-- (electricity/heat), time in world hours.
require "TLG/Registry/Registry"
require "TLG/Util/Num"

TLG.Domain = TLG.Domain or {}
TLG.Domain.FuelDefs = TLG.Domain.FuelDefs or {}
local Defs = TLG.Domain.FuelDefs
local Registry = TLG.Registry
local Num = TLG.Num

Defs.KINDS = { liquid = "L", gas = "Nm3", solid = "kg" }
Defs.ROLES = { fuel = true, contaminant = true, additive = true, feedstock = true, product = true }
Defs.IGNITION = { spark = true, compression = true, gaseous = true, none = true }

local function positive(v) return Num.isFinite(v) and v > 0 end
local function nonneg(v) return Num.isFinite(v) and v >= 0 end

Registry.addValidator("fuel", function(def, problem)
    if Defs.KINDS[def.phase] == nil then problem("phase must be liquid, gas or solid") end
    if not Defs.ROLES[def.role] then problem("invalid role " .. tostring(def.role)) end
    if def.role == "fuel" then
        if not positive(def.energyMJ) then problem("fuel needs positive energyMJ") end
        if not Defs.IGNITION[def.ignition] then problem("fuel needs ignition class") end
    end
    if def.aging then
        local a = def.aging
        if not nonneg(a.rate) or not nonneg(a.autocat) or not positive(a.q10) or
            not positive(a.unsealed) or not nonneg(a.stabilizerMax) or a.stabilizerMax > 0.95 then
            problem("invalid aging parameters")
        end
    end
    if def.waterSolubility ~= nil and not nonneg(def.waterSolubility) then problem("negative waterSolubility") end
    if def.hygroscopic ~= nil and not nonneg(def.hygroscopic) then problem("negative hygroscopic") end
end)

Registry.addValidator("storage", function(def, problem)
    if Defs.KINDS[def.phase] == nil then problem("phase must be liquid, gas or solid") end
    if def.capacity ~= nil and not positive(def.capacity) then problem("invalid capacity") end
    if not positive(def.agingMul) then problem("agingMul must be positive") end
    if not nonneg(def.breathing) then problem("breathing must be >= 0") end
    if def.thermal ~= "outdoor" and def.thermal ~= "sheltered" and def.thermal ~= "ground" then
        problem("thermal must be outdoor, sheltered or ground")
    end
    if def.leakPerHour ~= nil and not nonneg(def.leakPerHour) then problem("negative leakPerHour") end
end)

Registry.addValidator("consumer", function(def, problem)
    if not Defs.IGNITION[def.ignition] then problem("consumer needs ignition class") end
    if type(def.accepts) ~= "table" then
        problem("consumer needs accepts table")
    else
        for fuelId, rule in pairs(def.accepts) do
            local f = Registry.get("fuel", fuelId)
            if not f then
                problem("accepts unknown fuel " .. tostring(fuelId))
            elseif f.role ~= "fuel" then
                problem("accepts non-fuel " .. fuelId)
            end
            if not Num.isFinite(rule.max) or rule.max <= 0 or rule.max > 1 then
                problem("accepts." .. tostring(fuelId) .. ".max must be in (0,1]")
            end
        end
    end
    if not positive(def.maxDeg) then problem("maxDeg must be positive") end
    if Registry.get("fuel", def.referenceFuel) == nil then
        problem("unknown referenceFuel " .. tostring(def.referenceFuel))
    end
end)

function Defs.fuel(id)
    return Registry.need("fuel", id)
end

function Defs.storage(id)
    return Registry.need("storage", id)
end

function Defs.consumer(id)
    return Registry.need("consumer", id)
end

function Defs.isContaminant(id)
    local f = Registry.get("fuel", id)
    return f ~= nil and f.role == "contaminant"
end

return Defs
