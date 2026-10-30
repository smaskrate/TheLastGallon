-- Adapter: vehicles and generators as conversion devices (ConversionService).
-- Runtime status: SOURCE EVIDENCE ONLY.
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

-- Effective profile for a stored project (nil unless Commissioned and valid).
function CD.effective(md, device)
    local p = md and md[CD.KEY]
    if p == nil then return nil end
    local ok, profile = pcall(CS.effectiveProfile, p, device)
    if ok then return profile end
    return nil
end

function CD.actor(player, project)
    local actor = { id = TLG.Authority.Handlers and TLG.Authority.Handlers.actorKey(player) or tostring(player),
        skills = {}, recipes = {}, inventory = {} }
    for _, perk in ipairs({ "Mechanics", "Electricity", "MetalWelding", "Woodwork" }) do
        pcall(function() actor.skills[perk] = player:getPerkLevel(Perks[perk]) end)
    end
    local def = project and (project.snap or TLG.Registry.get("conversion", project.conversion)) or nil
    local wanted = {}
    local function collect(list)
        for k, v in pairs(list or {}) do
            if type(k) == "string" and string.find(k, "%.") then wanted[k] = true end
            if type(v) == "string" and string.find(v, "%.") then wanted[v] = true end
            if type(v) == "table" then collect(v) end
        end
    end
    if def then collect(def.requiredTools); collect(def.requiredModules); collect(def.workStages) end
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
