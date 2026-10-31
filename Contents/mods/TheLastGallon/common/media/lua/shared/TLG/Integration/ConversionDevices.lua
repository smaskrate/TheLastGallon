-- Adapter: vehicles and generators as conversion devices (ConversionService).
-- Runtime status: verified RT-SP 2026-10-31 (run 8) for flex_generator on a
-- Base.Generator and flex_car_normal on a Base.CarNormal: begin, deliver,
-- work to Commissioned, flex profile, project after save and reload.
-- Commands were sent directly; the workshop menu, cancel, remove, engine
-- replacement, other chassis and MP are NOT RUN.
--
--   project store   vehicle Engine part modData "tlgConv"; generator object
--                   modData "tlgConv" (carried through pickup/placement by the
--                   generator adapter wrappers)
--   device key      stable id stamped once ("tlgDeviceId"), never positional
--   engine identity vanilla engines are not items (template_engine has no
--                   itemType), so the adapter stamps "tlgEngineId" once
--   effects         V.profile / G.profile resolve through effectiveProfile, so
--                   a conversion only changes the engine when Commissioned
require "TLG/Domain/Conversions/Project"
require "TLG/Content/Conversions"
require "TLG/Integration/World"
require "TLG/Persistence/Migrations"

TLG.Integration.ConversionDevices = TLG.Integration.ConversionDevices or {}
local CD = TLG.Integration.ConversionDevices
local CS, World, Tables = TLG.Domain.ConversionService, TLG.World, TLG.Tables

CD.KEY = "tlgConv"

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
        project = withProject and md[CD.KEY] or nil,
    }, md
end

-- Stored project after the schema check: nil plus "future_schema" or
-- "invalid_schema" means the record must be left untouched (docs/migrations.md).
function CD.project(md)
    local raw = md and md[CD.KEY]
    if raw == nil then return nil, "absent" end
    return TLG.Persistence.Migrations.sidecar("project", raw)
end

-- Effective profile for a stored project (nil unless Commissioned and valid).
function CD.effective(md, device)
    local p = CD.project(md)
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

function CD.store(md, holder, project)
    md[CD.KEY] = project
    if holder and holder.getVehicle then
        holder:getVehicle():transmitPartModData(holder)
    elseif holder and holder.transmitModData then
        holder:transmitModData()
    end
end

return CD
