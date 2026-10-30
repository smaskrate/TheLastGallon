-- Canonical supply record (schema 1). Plain data so it can live in modData.
--
--   v        schema version              id     stable supply id
--   rev      revision (authority bumps)  phase  liquid | gas | solid
--   cap      capacity (canonical units)  q      { component = quantity }
--   deg      { component = degradation index } for components that age
--   stab     stabilizer concentration as a fraction of a full dose (fuel volume)
--   mic      microbial growth index 0..1 (diesel family)
--   storage  StorageProfile id           sealed  boolean
--   cond     storage condition 0..1       dirty   residue film 0..1 (empty vessel)
--   t        last simulated world hour    label   player label (cosmetic only)
--   prov     bounded provenance list (<= 4 entries, display only)
--
-- Labels, provenance and container identity never influence condition, so
-- relabelling or rewrapping cannot rejuvenate fuel.
require "TLG/Domain/Fuel/Defs"
require "TLG/Util/Tables"
require "TLG/Util/Num"

TLG.Domain.Supply = TLG.Domain.Supply or {}
local Supply = TLG.Domain.Supply
local Tables, Num, Registry = TLG.Tables, TLG.Num, TLG.Registry

Supply.SCHEMA = 1
Supply.MAX_PROVENANCE = 4

function Supply.new(o)
    local storage = Registry.need("storage", o.storage or "unknown")
    local s = {
        v = Supply.SCHEMA,
        id = o.id,
        rev = o.rev or 0,
        phase = storage.phase,
        cap = o.cap or storage.capacity,
        q = {},
        deg = {},
        stab = o.stab or 0,
        mic = o.mic or 0,
        storage = storage.id,
        sealed = (o.sealed ~= false) and (storage.sealable == true),
        cond = o.cond or 1,
        dirty = o.dirty or 0,
        t = o.t or 0,
        label = o.label,
        prov = {},
    }
    if s.cap == nil then
        error("supply needs a capacity (storage " .. storage.id .. " has no default)")
    end
    for id, amount in pairs(o.q or {}) do
        if amount > 0 then s.q[id] = amount end
    end
    for id, d in pairs(o.deg or {}) do
        if s.q[id] then s.deg[id] = d end
    end
    for id in pairs(s.q) do
        local f = Registry.need("fuel", id)
        if f.aging and s.deg[id] == nil then s.deg[id] = 0 end
    end
    return s
end

function Supply.copy(s)
    return Tables.deepCopy(s)
end

local function sumOver(s, pred)
    local values = {}
    for _, id in ipairs(Tables.sortedKeys(s.q)) do
        if pred == nil or pred(id) then values[#values + 1] = s.q[id] end
    end
    return Num.sum(values)
end

function Supply.total(s)
    return sumOver(s, nil)
end

-- Everything except contaminants (water, sediment).
function Supply.fuelTotal(s)
    return sumOver(s, function(id) return not TLG.Domain.FuelDefs.isContaminant(id) end)
end

function Supply.free(s)
    return math.max(0, s.cap - Supply.total(s))
end

function Supply.amount(s, id)
    return s.q[id] or 0
end

function Supply.fraction(s, id)
    local total = Supply.total(s)
    if total <= Num.DUST then return 0 end
    return (s.q[id] or 0) / total
end

-- Volume-weighted degradation over components that age.
function Supply.blendDeg(s)
    local num, den = 0, 0
    for _, id in ipairs(Tables.sortedKeys(s.deg)) do
        local q = s.q[id] or 0
        num = num + q * s.deg[id]
        den = den + q
    end
    if den <= Num.DUST then return 0 end
    return num / den
end

-- Water held in solution before free water appears.
function Supply.waterCapacity(s)
    local cap = 0
    for _, id in ipairs(Tables.sortedKeys(s.q)) do
        local f = Registry.need("fuel", id)
        cap = cap + s.q[id] * (f.waterSolubility or 0)
    end
    return cap
end

function Supply.freeWater(s)
    return math.max(0, (s.q.water or 0) - Supply.waterCapacity(s))
end

-- Phase separation: free water in a blend that contains both gasoline and
-- ethanol pulls ethanol into a lower water phase.
function Supply.isPhaseSeparated(s)
    return (s.q.gasoline or 0) > Num.DUST and (s.q.ethanol or 0) > Num.DUST and Supply.freeWater(s) > Num.DUST
end

function Supply.isEmpty(s)
    return Supply.total(s) <= Num.DUST
end

-- Removes rounding dust and clamps values that drifted below zero by less than
-- the tolerance. Returns the quantity destroyed (never created).
function Supply.normalize(s)
    local dust = 0
    for _, id in ipairs(Tables.sortedKeys(s.q)) do
        local v = s.q[id]
        if v < Num.DUST then
            if v < -1e-6 then error("negative component " .. id .. " = " .. tostring(v)) end
            if v > 0 then dust = dust + v end
            s.q[id] = nil
            s.deg[id] = nil
        end
    end
    for id in pairs(s.deg) do
        if s.q[id] == nil then s.deg[id] = nil end
    end
    if Supply.isEmpty(s) then
        s.stab = 0
        s.mic = math.max(s.mic, s.dirty * 0.2)
    end
    return dust
end

-- Invariant check (spec §6). Returns a list of violations; empty when valid.
function Supply.check(s, tol)
    tol = tol or 1e-6
    local bad = {}
    local function fail(msg) bad[#bad + 1] = msg end
    if s.v ~= Supply.SCHEMA then fail("schema " .. tostring(s.v)) end
    if not Num.isFinite(s.cap) or s.cap <= 0 then fail("capacity") end
    for _, id in ipairs(Tables.sortedKeys(s.q)) do
        local v = s.q[id]
        if not Num.isFinite(v) or v < 0 then fail("quantity " .. id) end
        if Registry.get("fuel", id) == nil then fail("unknown component " .. id) end
    end
    for _, id in ipairs(Tables.sortedKeys(s.deg)) do
        if not Num.isFinite(s.deg[id]) or s.deg[id] < 0 then fail("deg " .. id) end
    end
    if Supply.total(s) > s.cap + tol then fail("over capacity") end
    if not Num.isFinite(s.stab) or s.stab < 0 then fail("stab") end
    if not Num.isFinite(s.mic) or s.mic < 0 or s.mic > 1 then fail("mic") end
    if not Num.isFinite(s.cond) or s.cond < 0 or s.cond > 1 then fail("cond") end
    if not Num.isFinite(s.t) then fail("time") end
    return bad
end

function Supply.addProvenance(s, entry)
    local prov = s.prov or {}
    prov[#prov + 1] = entry
    while #prov > Supply.MAX_PROVENANCE do
        table.remove(prov, 1)
    end
    s.prov = prov
end

-- Dominant fuel component, for display and native fluid choice.
function Supply.primary(s)
    local best, bestQ
    for _, id in ipairs(Tables.sortedKeys(s.q)) do
        if not TLG.Domain.FuelDefs.isContaminant(id) and (bestQ == nil or s.q[id] > bestQ) then
            best, bestQ = id, s.q[id]
        end
    end
    return best
end

return Supply
