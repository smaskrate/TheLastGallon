-- Stable, validated content registries (FuelDefinition, StorageProfile,
-- ConsumerProfile, RecipeDefinition, MachineDefinition, ConversionDefinition,
-- SiteDefinition, AssetDefinition).
--
-- Definitions are plain data. Duplicate ids fail at definition time; reference
-- and value checks run in Registry.validate(), which the development build and
-- the test suite call before anything uses the content.
require "TLG/Util/Tables"
require "TLG/Util/Rng"

TLG.Registry = TLG.Registry or {}
local Registry = TLG.Registry
local Tables = TLG.Tables

Registry.KINDS = { "fuel", "storage", "consumer", "recipe", "machine", "conversion", "site", "asset" }
Registry.entries = Registry.entries or {}
Registry.validators = Registry.validators or {}

for _, kind in ipairs(Registry.KINDS) do
    Registry.entries[kind] = Registry.entries[kind] or {}
end

local function checkKind(kind)
    if Registry.entries[kind] == nil then
        error("unknown registry kind: " .. tostring(kind))
    end
end

function Registry.define(kind, def)
    checkKind(kind)
    if type(def) ~= "table" or type(def.id) ~= "string" or def.id == "" then
        error("registry " .. kind .. ": definition without string id")
    end
    if Registry.entries[kind][def.id] ~= nil then
        error("registry " .. kind .. ": duplicate id " .. def.id)
    end
    -- The registry name is kept separately: definitions may carry their own
    -- `kind` field (machines use it for fermenter/still/dryer).
    def.registryKind = kind
    Registry.entries[kind][def.id] = def
    return def
end

-- Replaces an existing definition (used by tests and by balance profiles).
function Registry.redefine(kind, def)
    checkKind(kind)
    Registry.entries[kind][def.id] = nil
    return Registry.define(kind, def)
end

function Registry.get(kind, id)
    checkKind(kind)
    if id == nil then return nil end
    return Registry.entries[kind][id]
end

function Registry.need(kind, id)
    local def = Registry.get(kind, id)
    if def == nil then
        error("registry " .. kind .. ": unknown id " .. tostring(id))
    end
    return def
end

function Registry.ids(kind)
    checkKind(kind)
    return Tables.sortedKeys(Registry.entries[kind])
end

function Registry.all(kind)
    local out = {}
    for _, id in ipairs(Registry.ids(kind)) do
        out[#out + 1] = Registry.entries[kind][id]
    end
    return out
end

function Registry.addValidator(kind, fn)
    checkKind(kind)
    local list = Registry.validators[kind] or {}
    list[#list + 1] = fn
    Registry.validators[kind] = list
end

-- Runs every validator; returns a sorted list of problem strings.
function Registry.validate()
    local problems = {}
    local function report(kind, id, msg)
        problems[#problems + 1] = kind .. ":" .. tostring(id) .. ": " .. msg
    end
    for _, kind in ipairs(Registry.KINDS) do
        local validators = Registry.validators[kind] or {}
        for _, id in ipairs(Registry.ids(kind)) do
            local def = Registry.entries[kind][id]
            for _, fn in ipairs(validators) do
                fn(def, function(msg) report(kind, id, msg) end)
            end
        end
    end
    return Tables.sort(problems)
end

-- Canonical text of plain data, used for content fingerprints.
local function canonical(v, out)
    local t = type(v)
    if t == "table" then
        out[#out + 1] = "{"
        for _, k in ipairs(Tables.sortedKeys(v)) do
            out[#out + 1] = tostring(k) .. "="
            canonical(v[k], out)
            out[#out + 1] = ";"
        end
        out[#out + 1] = "}"
    elseif t == "number" then
        out[#out + 1] = string.format("%.9g", v)
    elseif t ~= "function" then
        out[#out + 1] = tostring(v)
    end
end

function Registry.canonical(v)
    local out = {}
    canonical(v, out)
    return table.concat(out)
end

-- Fingerprint of one definition; stored with active processes and adapter
-- records so that a content update is detectable (docs/migrations.md).
function Registry.fingerprint(kind, id)
    local def = Registry.need(kind, id)
    return string.format("%s:%s:%d", kind, id, TLG.Rng.hash(Registry.canonical(def), 7))
end

return Registry
