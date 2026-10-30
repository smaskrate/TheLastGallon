-- Adapter: vanilla generators (IsoGenerator objects and carried generator items).
-- Runtime status: SOURCE EVIDENCE ONLY (G04/G05 NOT RUN, engine-capabilities).
--
--   quantity owner     native IsoGenerator.fuel (litres, getMaxFuel())
--   composition owner  TLG sidecar (object modData "tlg"; item modData "tlg"
--                      while carried, kind = "generator")
--   consumption owner  native burn in IsoGenerator.update(); TLG never subtracts
--   replication        object:transmitModData()
--   reconciliation     like vehicles (D-006)
--   lifecycle          vanilla carries only fuel + condition between object and
--                      item (SRC ISTakeGenerator.lua:41-53, BC setInfoFromItem);
--                      TLG wraps pickup, drop (Java converts the dropped item in
--                      IsoGridSquare.AddWorldInventoryItem) and IsoGenerator.new
--   effects            start gate on ISActivateGenerator: failToStart() when the
--                      fuel is incompatible or the start roll fails
require "TLG/Integration/Containers"
require "TLG/Boot"

TLG.Integration.Generators = TLG.Integration.Generators or {}
local G = TLG.Integration.Generators
local C, World = TLG.Integration.Containers, TLG.World
local Supply, Mixing, Aging, Tx, Consumers = TLG.Domain.Supply, TLG.Domain.Mixing, TLG.Domain.Aging,
    TLG.Authority.Transactions, TLG.Domain.Consumers
local Tables = TLG.Tables

G.DEFAULT_PROFILE = "generator_si_stock"
G.ITEM_TYPES = { ["Base.Generator"] = true, ["Base.Generator_Old"] = true, ["Base.Generator_Yellow"] = true,
    ["Base.Generator_Blue"] = true }

function G.keyOf(gen)
    local sq = gen:getSquare()
    return string.format("gen:%d,%d,%d", sq and sq:getX() or -1, sq and sq:getY() or -1, sq and sq:getZ() or -1)
end

function G.baseProfile(gen)
    local side = gen:getModData().tlg
    return (side and side.profile) or G.DEFAULT_PROFILE
end

-- Effective profile: a Commissioned conversion wins (see ConversionDevices).
function G.profile(gen)
    local CD = TLG.Integration.ConversionDevices
    if CD and gen:getModData()[CD.KEY] then
        local p = CD.effective(gen:getModData(), CD.describeGenerator(gen, false))
        if p then return p end
    end
    return G.baseProfile(gen)
end

-- Device identity and conversion projects travel with the generator.
G.CARRIED_KEYS = { "tlgConv", "tlgDeviceId", "tlgEngineId" }

local function fromSidecar(side, cap)
    local rec = Supply.new({ storage = "generator_tank", cap = cap, t = side.t, cond = side.cond, stab = side.stab,
        mic = side.mic })
    rec.id, rec.rev = side.id, side.rev or 0
    for id, q in pairs(side.q or {}) do rec.q[id] = q end
    for id, d in pairs(side.deg or {}) do rec.deg[id] = d end
    rec.prov = Tables.deepCopy(side.prov or {})
    return rec
end

function G.read(gen, persist)
    local fuel = gen:getFuel()
    local cap = math.max(gen:getMaxFuel(), fuel)
    local raw = gen:getModData().tlg
    local side, schemaStatus = TLG.Persistence.Migrations.sidecar("supply", raw)
    if raw ~= nil and side == nil then return nil, schemaStatus end
    if side == nil then
        local rec
        if fuel <= 1e-6 then
            rec = Supply.new({ storage = "generator_tank", cap = cap, t = World.now() })
        else
            rec = World.baseline(G.keyOf(gen), { storage = "generator_tank", cap = cap, q = { gasoline = fuel } })
        end
        rec.cap = cap
        if persist then rec.id = World.newId("G") end
        return rec, "initialized"
    end
    local rec = fromSidecar(side, cap)
    if math.abs(fuel - Supply.total(rec)) <= 1e-4 then return rec, "ok" end
    local base = { deg = 0, mic = 0 }
    if fuel > Supply.total(rec) then base.deg = C.untrackedDeg() end
    local out = Tx.reconcile(rec, { total = fuel }, base, Supply.primary(rec) or "gasoline")
    out.cap = cap
    return out, "reconciled"
end

local function sidecarOf(rec, profile)
    local side = { v = C.SCHEMA, kind = "generator", profile = profile }
    for _, f in ipairs({ "id", "rev", "deg", "stab", "mic", "t", "cond", "prov", "q" }) do
        side[f] = Tables.deepCopy(rec[f])
    end
    return side
end

function G.writeSidecar(gen, rec)
    gen:getModData().tlg = sidecarOf(rec, G.baseProfile(gen))
    gen:transmitModData()
end

function G.evaluate(gen)
    local rec = G.read(gen, false)
    local ambient
    pcall(function() ambient = getClimateManager():getTemperature() end)
    return Consumers.evaluate(G.profile(gen), rec, { ambientC = ambient }), rec
end

local function wrap(class, method, fn)
    local orig = class and class[method]
    if orig == nil then return false end
    class[method] = function(self, ...) return fn(orig, self, ...) end
    return true
end

-- Can -> generator (SRC ISAddFuel.lua:47-61, litres map 1:1 to fuel).
local function installAddFuel()
    wrap(ISAddFuel, "new", function(orig, class, character, generator, petrol, maxTime)
        local o = orig(class, character, generator, petrol, maxTime)
        if World.isAuthority() and o and generator and petrol and petrol:getFluidContainer() then
            pcall(function()
                o.tlgGenBefore = G.read(generator, true)
                o.tlgCanBefore = C.read(petrol, "item", true)
                o.tlgFuelStart = generator:getFuel()
            end)
        end
        return o
    end)
    wrap(ISAddFuel, "complete", function(orig, self)
        local r = orig(self)
        if self.tlgGenBefore and self.tlgCanBefore and not self.tlgSettled then
            self.tlgSettled = true
            local ok, err = pcall(function()
                local moved = self.generator:getFuel() - self.tlgFuelStart
                if moved <= 1e-6 then return end
                local now, env = World.now(), World.env()
                local before = Aging.advance(self.tlgGenBefore, now, env)
                local can = Aging.advance(self.tlgCanBefore, now, env)
                local parcel = Supply.copy(can)
                local frac = math.min(1, moved / math.max(1e-9, Supply.total(can)))
                for id, q in pairs(parcel.q) do parcel.q[id] = q * frac end
                local merged = Mixing.previewBlend({ { supply = before, amount = Supply.total(before) },
                    { supply = parcel, amount = Supply.total(parcel) } }, "generator_tank", before.cap)
                merged.id, merged.rev, merged.cap = before.id, (before.rev or 0) + 1, before.cap
                Supply.addProvenance(merged, { k = "in", from = can.id, t = now, n = moved })
                G.writeSidecar(self.generator, merged)
            end)
            if not ok then TLG.Log.error("generator refuel settle: %s", tostring(err)) end
        end
        return r
    end)
end

-- Pickup: object sidecar -> item sidecar.
local function installPickup()
    wrap(ISTakeGenerator, "complete", function(orig, self)
        local side
        if World.isAuthority() then
            pcall(function()
                local rec = Aging.advance((G.read(self.generator, true)), World.now(), World.env())
                side = sidecarOf(rec, G.baseProfile(self.generator))
                local omd = self.generator:getModData()
                for _, k in ipairs(G.CARRIED_KEYS) do side[k] = TLG.Tables.deepCopy(omd[k]) end
            end)
        end
        local inv = self.character:getInventory()
        local before = inv:getItems():size()
        local r = orig(self)
        if side then
            local items = inv:getItems()
            for i = before, items:size() - 1 do
                local it = items:get(i)
                if it and G.ITEM_TYPES[it:getFullType()] then
                    it:getModData().tlg = side
                    it:syncItemFields()
                end
            end
        end
        return r
    end)
end

-- Item sidecar -> object sidecar, for any IsoGenerator on `square` without one.
function G.attachFromItem(square, item)
    local side = item and item:getModData().tlg
    if square == nil or side == nil or side.kind ~= "generator" then return false end
    local objs = square:getObjects()
    for i = 0, objs:size() - 1 do
        local o = objs:get(i)
        if instanceof(o, "IsoGenerator") and o:getModData().tlg == nil then
            local copy = Tables.deepCopy(side)
            local omd = o:getModData()
            for _, k in ipairs(G.CARRIED_KEYS) do
                omd[k] = copy[k]
                copy[k] = nil
            end
            omd.tlg = copy
            o:transmitModData()
            return true
        end
    end
    return false
end

local function installPlacement()
    wrap(ISDropWorldItemAction, "complete", function(orig, self)
        local item, sq = self.item, self.sq
        local isGen = item and G.ITEM_TYPES[item:getFullType()] and item:getModData().tlg ~= nil
        local r = orig(self)
        if isGen and World.isAuthority() then pcall(G.attachFromItem, sq, item) end
        return r
    end)
    if IsoGenerator and IsoGenerator.new then
        local origNew = IsoGenerator.new
        IsoGenerator.new = function(item, cell, square)
            local g = origNew(item, cell, square)
            if g and item and item:getModData().tlg and item:getModData().tlg.kind == "generator" then
                local copy = Tables.deepCopy(item:getModData().tlg)
                local omd = g:getModData()
                for _, k in ipairs(G.CARRIED_KEYS) do
                    omd[k] = copy[k]
                    copy[k] = nil
                end
                omd.tlg = copy
            end
            return g
        end
    end
end

-- Start gate: the fuel decides whether an activation succeeds.
G.startRoll = function() return ZombRandFloat(0, 1) end

local function installStartGate()
    wrap(ISActivateGenerator, "complete", function(orig, self)
        if self.activate and World.isAuthority() then
            local ok, e = pcall(G.evaluate, self.generator)
            if ok and e and e.grade ~= "empty" and (not e.compatible or G.startRoll() > e.startFactor) then
                self.generator:failToStart()
                self.generator:sync()
                TLG.Log.debug("generator start refused: %s", table.concat(e.reasons, ","))
                return true
            end
        end
        return orig(self)
    end)
end

function G.install()
    installAddFuel()
    installPickup()
    installPlacement()
    installStartGate()
    TLG.Log.info("generator adapter installed")
end

TLG.Boot.addInstaller("generators", G.install)

return G
