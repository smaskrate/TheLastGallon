-- MigrationService.upgrade(savedState, targetSchema)
--
-- Every persistent record carries `v`. Upgrades are deterministic and
-- idempotent (upgrading a current record returns an equal record). Records
-- from a NEWER schema than this build understands are preserved untouched and
-- reported read-only, so an older mod version never overwrites them.
-- Migrations never turn custom fuel into fresh gasoline (spec §15).
require "TLG/Util/Tables"

TLG.Persistence = TLG.Persistence or {}
TLG.Persistence.Migrations = TLG.Persistence.Migrations or {}
local M = TLG.Persistence.Migrations
local Tables = TLG.Tables

-- Current schema per record kind (mirrors TLG.SCHEMA in Core.lua).
M.CURRENT = { supply = 1, process = 1, project = 1, world = 1, network = 1, gas = 1 }

-- steps[kind][from] = function(record) -> record at version from + 1
M.steps = M.steps or { supply = {}, process = {}, project = {}, world = {}, network = {}, gas = {} }

-- v0: pre-release development sidecars (before schema numbers existed):
-- condition stored as `age` (hours) and composition under `comp`.
M.steps.supply[0] = function(r)
    local out = Tables.deepCopy(r)
    out.q = out.q or out.comp or {}
    out.comp = nil
    if out.deg == nil then
        out.deg = {}
        -- Pre-release builds stored only gasoline age; map it conservatively
        -- (never fresher): 1 deg per 2000 h of recorded age.
        if out.age and out.q.gasoline then out.deg.gasoline = out.age / 2000 end
    end
    out.age = nil
    out.rev = out.rev or 0
    out.v = 1
    return out
end

-- Upgrades one record. Returns record, status where status is
-- "current" | "upgraded" | "future" (read-only) | "invalid".
function M.upgrade(kind, record, target)
    if type(record) ~= "table" then return nil, "invalid" end
    target = target or M.CURRENT[kind]
    if target == nil then return nil, "invalid" end
    local v = record.v
    if v == nil then v = 0 end
    if type(v) ~= "number" or v ~= math.floor(v) or v < 0 then return nil, "invalid" end
    if v > target then return record, "future" end
    if v == target then return record, "current" end
    local out = record
    while v < target do
        local step = M.steps[kind] and M.steps[kind][v]
        if step == nil then return nil, "invalid" end
        out = step(out)
        if out.v ~= v + 1 then return nil, "invalid" end
        v = out.v
    end
    return out, "upgraded"
end

-- Adapter helper: returns a usable sidecar, or nil plus a reason when the
-- record must be left alone ("future") or ignored ("invalid").
function M.sidecar(kind, side)
    if side == nil then return nil, "absent" end
    local rec, status = M.upgrade(kind, side)
    if status == "future" then return nil, "future_schema" end
    if status == "invalid" then return nil, "invalid_schema" end
    return rec, status
end

return M
