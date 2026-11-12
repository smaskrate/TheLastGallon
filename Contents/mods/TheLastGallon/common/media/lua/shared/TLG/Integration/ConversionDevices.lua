-- Adapter: vehicles and generators as conversion devices (ConversionService).
-- Runtime status: verified RT-SP 2026-10-31 (runs 8-9) for flex_generator on
-- a Base.Generator and flex_car_normal on a Base.CarNormal: begin, deliver,
-- work to Commissioned through ISTLGConversionWork (run 9), flex profile,
-- project after save and reload; every step from the workshop menu (run
-- 12). On a dedicated server both again from the workshop's steps (RT-MP
-- runs 162 and 169), each then run on ethanol. Cancel, remove, engine
-- replacement and other chassis are NOT RUN.
--
--   project store   vehicle Engine part modData "tlgConv"; generator object
--                   modData "tlgConv" (carried through pickup/placement by the
--                   generator adapter wrappers)
--   device key      stable id stamped once ("tlgDeviceId"), never positional
--   engine identity vanilla engines are not items (template_engine has no
--                   itemType), so the adapter stamps "tlgEngineId" once
--   effects         V.profile / G.profile resolve through effectiveProfile, so
--                   a conversion only changes the engine when Commissioned
--   server copy     a generator's project is checked against the vault on a
--                   server (TLG/Authority/Vault.lua; audit V-01): clients can
--                   rewrite an object's mod data there, not an Engine
--                   part's (BaseVehicle.transmitPartModData acts only on
--                   the server, and the audit found no other way), so a
--                   vehicle's project is read as stored
require "TLG/Domain/Conversions/Project"
require "TLG/Content/Conversions"
require "TLG/Integration/World"
require "TLG/Persistence/Migrations"
require "TLG/Authority/Vault"

TLG.Integration.ConversionDevices = TLG.Integration.ConversionDevices or {}
local CD = TLG.Integration.ConversionDevices
local CS, World, Tables = TLG.Domain.ConversionService, TLG.World, TLG.Tables
local Vault = TLG.Authority.Vault

CD.KEY = "tlgConv"
-- Work is the timed action ISTLGConversionWork: it reports every
-- REPORT_EVERY_HOURS of world time while the worker stays at the device, and
-- the authority credits at most WORKER_TIMEOUT_HOURS per report, so time away
-- from the device is not credited.
CD.REPORT_EVERY_HOURS = 0.25
CD.WORKER_TIMEOUT_HOURS = 1

local function stamp(md, field, prefix)
    if md[field] == nil and World.isAuthority() then md[field] = World.newId(prefix) end
    return md[field]
end

function CD.vehicleStore(vehicle)
    local engine = vehicle:getPartById("Engine")
    return engine and engine:getModData() or nil, engine
end

function CD.describeVehicle(vehicle, withProject)
    local md, engine = CD.vehicleStore(vehicle)
    if md == nil then return nil end
    local tank = vehicle:getPartById("GasTank")
    return {
        key = "veh:" .. tostring(stamp(md, "tlgDeviceId", "D")),
        kind = "vehicle",
        chassis = vehicle:getScriptName(),
        engineId = stamp(md, "tlgEngineId", "E"),
        engineProfile = TLG.Integration.Vehicles.baseProfile(vehicle),
        tankAmount = tank and tank:getContainerContentAmount() or 0,
        destroyed = false,
        available = not vehicle:isEngineRunning(),
        project = withProject and md[CD.KEY] or nil,
    }, md, engine
end

-- The vault's holder for a placed generator ("gen:x,y,z", as the generator
-- adapter keys it).
function CD.generatorHolder(gen)
    local G = TLG.Integration.Generators
    return G and G.keyOf and G.keyOf(gen) or nil
end

function CD.describeGenerator(gen, withProject)
    local md = gen:getModData()
    return {
        key = "gen:" .. tostring(stamp(md, "tlgDeviceId", "D")),
        kind = "generator",
        chassis = gen:getGeneratorItemType(),
        engineId = stamp(md, "tlgEngineId", "E"),
        engineProfile = TLG.Integration.Generators.baseProfile(gen),
        tankAmount = gen:getFuel(),
        destroyed = false,
        available = not gen:isActivated(),
        project = withProject and (CD.project(md, function() return CD.generatorHolder(gen) end,
            function() gen:transmitModData() end)) or nil,
    }, md
end

-- Stored project after the schema check: nil plus "future_schema" or
-- "invalid_schema" means the record must be left untouched (docs/migrations.md).
-- `holder` (a generator's "gen:x,y,z") has it checked against the vault
-- first; `sync` sends a project put back.
function CD.project(md, holder, sync)
    if md == nil then return nil, "absent" end
    local raw = md[CD.KEY]
    if holder ~= nil then raw = Vault.guard("project", holder, md, CD.KEY, sync) end
    if raw == nil then return nil, "absent" end
    return TLG.Persistence.Migrations.sidecar("project", raw)
end

-- Whether the game offers a conversion (0.4.2). One whose engine burns gas
-- from an outside vessel (fuelStorageChanges.external: gas_generator) has
-- nothing to run on until the gas feed of 0.5.0 (D-040), so its Start entry
-- is hidden and the authority refuses to begin it. A project already begun
-- can still be cancelled or removed. An unknown id is left to the domain.
function CD.offered(conversionId)
    local def = TLG.Registry.get("conversion", conversionId)
    if def == nil then return true end
    local fs = def.fuelStorageChanges
    return not (type(fs) == "table" and fs.external ~= nil)
end

-- Effective profile for a stored project (nil unless Commissioned and valid).
function CD.effective(md, device, holder)
    local p = CD.project(md, holder)
    if p == nil then return nil end
    local ok, profile = pcall(CS.effectiveProfile, p, device)
    if ok then return profile end
    return nil
end

-- Counts only the items the definitions name. `conversion` is the definition
-- conversion.begin is about to start: its project does not exist yet, so
-- without it nothing was counted and every first conversion failed with
-- missing_tool (RT-SP 2026-10-31, run 7).
function CD.actor(player, project, conversion)
    local actor = { id = TLG.Authority.Handlers and TLG.Authority.Handlers.actorKey(player) or tostring(player),
        skills = {}, recipes = {}, inventory = {} }
    for _, perk in ipairs({ "Mechanics", "Electricity", "MetalWelding", "Woodwork" }) do
        pcall(function() actor.skills[perk] = player:getPerkLevel(Perks[perk]) end)
    end
    local wanted = {}
    local function collect(list)
        for k, v in pairs(list or {}) do
            if type(k) == "string" and string.find(k, "%.") then wanted[k] = true end
            if type(v) == "string" and string.find(v, "%.") then wanted[v] = true end
            if type(v) == "table" then collect(v) end
        end
    end
    local function collectDef(def)
        if def == nil then return end
        collect(def.requiredTools); collect(def.requiredModules); collect(def.workStages)
        collect(def.reversalAndSalvageRules)
    end
    collectDef(project and (project.snap or TLG.Registry.get("conversion", project.conversion)) or nil)
    if type(conversion) == "string" then collectDef(TLG.Registry.get("conversion", conversion)) end
    for _, id in ipairs(Tables.sortedKeys(wanted)) do
        actor.inventory[id] = player:getInventory():getCountTypeRecurse(id)
    end
    pcall(function()
        local known = player:getKnownRecipes()
        for i = 0, known:size() - 1 do actor.recipes[known:get(i)] = true end
    end)
    return actor
end

-- `vaultHolder`: a generator's "gen:x,y,z", whose project the vault keeps.
function CD.store(md, holder, project, vaultHolder)
    md[CD.KEY] = project
    if vaultHolder ~= nil then Vault.put("project", vaultHolder, project) end
    if holder and holder.getVehicle then
        holder:getVehicle():transmitPartModData(holder)
    elseif holder and holder.transmitModData then
        holder:transmitModData()
    end
end

return CD
