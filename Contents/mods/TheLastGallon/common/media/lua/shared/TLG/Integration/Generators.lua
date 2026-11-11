-- Adapter: vanilla generators (IsoGenerator objects and carried generator items).
-- Runtime status: refuel, burn reconciliation, pickup, all Lua drop paths and
-- the start gate verified RT-SP 2026-10-31; on a dedicated server refuel,
-- burn reconciliation, the gate, take and the place action (RT-MP run 160);
-- wear charged at a refuel RT-SP run 179 (D-031).
--
--   quantity owner     native IsoGenerator.fuel (litres, getMaxFuel())
--   composition owner  TLG sidecar (object modData "tlg"; item modData "tlg"
--                      while carried, kind = "generator")
--   consumption owner  native burn in IsoGenerator.update(); TLG never subtracts
--   replication        object:transmitModData()
--   reconciliation     like vehicles (D-006)
--   lifecycle          vanilla carries only fuel + condition between object and
--                      item (SRC ISTakeGenerator.lua:41-53; BC setInfoFromItem
--                      copies condition, modData "fuel" and sets modData
--                      "generatorFullType", nothing else). TLG wraps pickup,
--                      IsoGenerator.new and every Lua drop path (Java converts
--                      the dropped item in IsoGridSquare.AddWorldInventoryItem):
--                      ISDropWorldItemAction, ISUnequipAction (the menus'
--                      unequip), forceDropHeavyItems and ISTransferAction to
--                      the floor. Drops done by Java alone are not seen; such
--                      a generator reads as untracked fuel.
--   effects            start gate on ISActivateGenerator: failToStart() when the
--                      fuel is incompatible or the start roll fails; wear for
--                      the fuel burned since the record was last written,
--                      charged when the mod next handles the generator
--                      (refuel, pickup, switching, its commands; D-031)
--   server copy        the record, the conversion project and the wear are
--                      checked against the vault on a server (TLG/Authority/
--                      Vault.lua, holder "gen:x,y,z" or the carried item;
--                      audit V-01)
require "TLG/Integration/Containers"
require "TLG/Domain/EngineEffects"
require "TLG/Notify"
require "TLG/Boot"
require "TLG/Authority/Vault"

TLG.Integration.Generators = TLG.Integration.Generators or {}
local G = TLG.Integration.Generators
local C, World = TLG.Integration.Containers, TLG.World
local Supply, Mixing, Aging, Tx, Consumers = TLG.Domain.Supply, TLG.Domain.Mixing, TLG.Domain.Aging,
    TLG.Authority.Transactions, TLG.Domain.Consumers
local Tables = TLG.Tables
local EngineEffects = TLG.Domain.EngineEffects
local Vault = TLG.Authority.Vault

G.DEFAULT_PROFILE = "generator_si_stock"
G.ITEM_TYPES = { ["Base.Generator"] = true, ["Base.Generator_Old"] = true, ["Base.Generator_Yellow"] = true,
    ["Base.Generator_Blue"] = true, ["TLG.DieselGenerator"] = true }
-- Generator items with a profile of their own (D-036); the others have
-- DEFAULT_PROFILE. The game keeps the item's type on the object it becomes
-- (mod data "generatorFullType").
G.ITEM_PROFILES = { ["TLG.DieselGenerator"] = "generator_ci_bio" }

-- The mod's own generator sprites (D-036). The game reads a generator's
-- item type from its sprite's name (BC IsoGenerator.getGeneratorItemType)
-- and saves an object's sprite by its tile-sheet number, so each is a
-- tile of the mod's own sheet (media/tlg_generators.tiles, named in
-- mod.info; tools/make-tile-sprites.ps1 writes it). The mod ships no
-- texture pack: the tile's picture is a single file, given to the sprite
-- here. Launch 235, with the picture's path as the sprite's name and no
-- sheet: the generator lost its sprite and its type when the save was
-- continued.
G.SPRITES = { ["TLG.DieselGenerator"] = "tlg_generators_01_0" }
G.PICTURES = { ["tlg_generators_01_0"] = "media/textures/TLG/Tile_DieselGenerator.png" }

function G.loadSprites()
    if not getSprite or (isServer and isServer()) then return end
    for name, picture in pairs(G.PICTURES) do
        pcall(function()
            local s = getSprite(name)
            if s then s:LoadSingleTexture(picture) end
        end)
    end
end
-- The diesel generator in loot (D-036: loot only). Wherever a loot list
-- offers vanilla's Base.Generator, it offers the diesel one at half that
-- weight: in a list's items, its junk, or its junk's items (42.22.2: the
-- crate list CrateGenerator and eleven truck beds of VehicleDistributions).
-- `lists` is ProceduralDistributions.list or VehicleDistributions, before
-- the game parses them. A list that has the diesel generator already is
-- left as it is. Returns the names of the lists it was added to.
G.LOOT_ITEM, G.LOOT_BESIDE, G.LOOT_SHARE = "TLG.DieselGenerator", "Generator", 0.5

function G.addToLoot(lists)
    local added = {}
    if type(lists) ~= "table" then return added end
    local function offer(items)
        if type(items) ~= "table" then return false end
        local weight, present
        for i = 1, #items - 1, 2 do
            if items[i] == G.LOOT_BESIDE and type(items[i + 1]) == "number" then weight = weight or items[i + 1] end
            if items[i] == G.LOOT_ITEM then present = true end
        end
        if not weight or present then return false end
        items[#items + 1] = G.LOOT_ITEM
        items[#items + 1] = weight * G.LOOT_SHARE
        return true
    end
    local names = {}
    for name, list in pairs(lists) do
        if type(name) == "string" and type(list) == "table" then names[#names + 1] = name end
    end
    table.sort(names)
    for _, name in ipairs(names) do
        local list = lists[name]
        local junk = type(list.junk) == "table" and list.junk or nil
        local a, b, c = offer(list.items), offer(junk), offer(junk and junk.items)
        if a or b or c then added[#added + 1] = name end
    end
    return added
end

function G.keyOf(gen)
    local sq = gen:getSquare()
    return string.format("gen:%d,%d,%d", sq and sq:getX() or -1, sq and sq:getY() or -1, sq and sq:getZ() or -1)
end

local function sendFn(gen)
    return function() gen:transmitModData() end
end

-- The object's fuel record, checked against the vault on a server.
local function sidecarIn(gen)
    return Vault.guard("supply", function() return G.keyOf(gen) end, gen:getModData(), "tlg", sendFn(gen))
end

function G.baseProfile(gen)
    local side = sidecarIn(gen)
    if side and side.profile then return side.profile end
    local md = gen:getModData()
    return G.ITEM_PROFILES[md and md.generatorFullType or ""] or G.DEFAULT_PROFILE
end

-- The fuel a generator is taken to hold when it has litres and no record:
-- its profile's reference fuel (petrol, or diesel for a diesel generator).
function G.referenceFuel(gen)
    local def = TLG.Registry.get("consumer", G.baseProfile(gen))
    return (def and def.referenceFuel) or "gasoline"
end

-- Effective profile: a Commissioned conversion wins (see ConversionDevices).
function G.profile(gen)
    local CD = TLG.Integration.ConversionDevices
    if CD then
        local md, holder = gen:getModData(), function() return G.keyOf(gen) end
        if CD.project(md, holder, sendFn(gen)) then
            local p = CD.effective(md, CD.describeGenerator(gen, false), holder)
            if p then return p end
        end
    end
    return G.baseProfile(gen)
end

-- Device identity, conversion projects and the wear fraction travel with the
-- generator.
G.WEAR_KEY = "tlgWear"
G.CARRIED_KEYS = { "tlgConv", "tlgDeviceId", "tlgEngineId", G.WEAR_KEY }

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
    local raw = sidecarIn(gen)
    local side, schemaStatus = TLG.Persistence.Migrations.sidecar("supply", raw)
    if raw ~= nil and side == nil then return nil, schemaStatus end
    if side == nil then
        local rec
        if fuel <= 1e-6 then
            rec = Supply.new({ storage = "generator_tank", cap = cap, t = World.now() })
        else
            rec = World.baseline(G.keyOf(gen), { storage = "generator_tank", cap = cap, q = { [G.referenceFuel(gen)] = fuel } })
        end
        rec.cap = cap
        if persist then rec.id = World.newId("G") end
        return rec, "initialized"
    end
    local rec = fromSidecar(side, cap)
    if math.abs(fuel - Supply.total(rec)) <= 1e-4 then return rec, "ok" end
    local base, at = { deg = 0, mic = 0 }, nil
    if fuel > Supply.total(rec) then base, at = C.inflowAt() end
    local out = Tx.reconcile(rec, { total = fuel }, base, Supply.primary(rec) or G.referenceFuel(gen), at)
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
    local side = sidecarOf(rec, G.baseProfile(gen))
    gen:getModData().tlg = side
    Vault.put("supply", function() return G.keyOf(gen) end, side)
    gen:transmitModData()
end

function G.evaluate(gen)
    local rec = G.read(gen, false)
    local ambient
    pcall(function() ambient = getClimateManager():getTemperature() end)
    return Consumers.evaluate(G.profile(gen), rec, { ambientC = ambient }), rec
end

-- The generator item's ConditionLowerChanceOneIn: vanilla takes condition
-- once in that many running hours (BC IsoGenerator.update; 30 for
-- Base.Generator, 24-36 for the others). nil when the script is not found.
function G.lowerChanceOneIn(gen)
    local n
    pcall(function()
        local item = getScriptManager():FindItem(gen:getGeneratorItemType())
        n = item and item:getConditionLowerChance()
    end)
    return n
end

-- Wear for the fuel burned since the generator's record was last written
-- (D-031). The game burns the fuel; the record keeps what was in the tank
-- when the mod last wrote it (every write holds the tank's litres then), so
-- the drop since then is what burned. Each litre is charged once: `charged`
-- holds what was charged against the record `k` (its total, revision and
-- time), and a rewritten record starts again from zero. The fuel evaluated is
-- the record as written, aged to now: a tank run dry still tells what it
-- burned. Called on the authority before the mod acts on the generator.
-- Returns the whole points taken off.
function G.chargeWear(gen)
    if not World.isAuthority() then return 0 end
    local md = gen:getModData()
    local side = sidecarIn(gen)
    if type(side) ~= "table" or side.q == nil then return 0 end
    local fuel = gen:getFuel()
    local rec = fromSidecar(side, math.max(gen:getMaxFuel(), fuel))
    local written = Supply.total(rec)
    local key = string.format("%.6f|%s|%s", written, tostring(side.rev), tostring(side.t))
    -- Kept in the vault under the record's id; one the vault does not know
    -- yet (a save from before it) is taken as found once.
    local w = Vault.guardKeyed("wear", side.id, md, G.WEAR_KEY, sendFn(gen))
    if type(w) ~= "table" then w = { c = 0 } end
    if w.k ~= key then w.k, w.charged = key, 0 end
    local burned = written - fuel
    local due = burned - (w.charged or 0)
    local whole = 0
    if due < -1e-6 then
        -- Fuel came in that the mod did not see: charge from here on.
        w.charged = burned
    elseif due > 1e-6 then
        local ambient
        pcall(function() ambient = getClimateManager():getTemperature() end)
        local e = Consumers.evaluate(G.profile(gen), Aging.advance(rec, World.now(), World.env()), { ambientC = ambient })
        local perLitre = EngineEffects.generatorWearPerLitre(G.lowerChanceOneIn(gen),
            SandboxVars and SandboxVars.GeneratorFuelConsumption)
        local carry
        carry, whole = EngineEffects.accrue(w.c, due, e.wearFactor, perLitre)
        w.c, w.charged = carry, burned
        if whole > 0 then gen:setCondition(math.max(0, gen:getCondition() - whole)) end
        -- Wrong fuel (D-037): the chance that it fails, for these litres as
        -- the hours they lasted. At condition 0 the game does not switch a
        -- generator on (SRC ISActivateGenerator.isValid) but leaves a running
        -- one running until its next wear roll (launch 261), so it is
        -- switched off here.
        local reference = EngineEffects.generatorReferenceLitres(due, SandboxVars and SandboxVars.GeneratorFuelConsumption)
        if e.failureChance and G.failRoll() < EngineEffects.failureOdds(e.failureChance, reference) then
            whole = whole + gen:getCondition()
            gen:setCondition(0)
            if gen.setActivated then pcall(function() gen:setActivated(false) end) end
            if gen.sync then pcall(function() gen:sync() end) end
            TLG.Log.debug("generator failed on wrong fuel: %s", table.concat(e.reasons, ","))
        end
    end
    md[G.WEAR_KEY] = w
    Vault.putKeyed("wear", side.id, w)
    return whole
end

-- Not for a constructor: those keep vanilla's parameters (below), as a
-- multiplayer client sends a timed action's fields named as its new's
-- parameters (BC NetTimedAction.set; Stations.lua says more, RT-MP run 156).
local function wrap(class, method, fn)
    local orig = class and class[method]
    if orig == nil then return false end
    class[method] = function(self, ...) return fn(orig, self, ...) end
    return true
end

-- Can -> generator (SRC ISAddFuel.lua:47-61, litres map 1:1 to fuel; new at
-- :70, new(character, generator, petrol, maxTime)).
local function installAddFuel()
    local orig = ISAddFuel and ISAddFuel.new
    if orig == nil then return end
    ISAddFuel.new = function(class, character, generator, petrol, maxTime)
        local o = orig(class, character, generator, petrol, maxTime)
        if World.isAuthority() and o and generator and petrol and petrol:getFluidContainer() then
            pcall(function()
                -- Before the refuel moves the tank past what burned.
                G.chargeWear(generator)
                o.tlgGenBefore = G.read(generator, true)
                o.tlgCanBefore = C.read(petrol, "item", true)
                o.tlgFuelStart = generator:getFuel()
            end)
        end
        return o
    end
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
        local side, from
        if World.isAuthority() then
            pcall(function()
                G.chargeWear(self.generator)
                local rec = Aging.advance((G.read(self.generator, true)), World.now(), World.env())
                side = sidecarOf(rec, G.baseProfile(self.generator))
                local omd = self.generator:getModData()
                -- Taken before the generator leaves its square.
                from = Vault.active() and G.keyOf(self.generator) or nil
                -- The project and the wear as the vault has them (they are
                -- put back in omd when they differ).
                local CD = TLG.Integration.ConversionDevices
                if CD then CD.project(omd, from, sendFn(self.generator)) end
                Vault.guardKeyed("wear", rec.id, omd, G.WEAR_KEY, sendFn(self.generator))
                for _, k in ipairs(G.CARRIED_KEYS) do side[k] = TLG.Tables.deepCopy(omd[k]) end
            end)
        end
        local r = orig(self)
        if side then
            -- Vanilla equips the new item in both hands (SRC ISTakeGenerator.lua:46-47).
            -- It is found by hand, not by inventory index: forceDropHeavyItems
            -- may have removed a carried generator from the list first.
            local it = self.character:getPrimaryHandItem()
            if not (it and G.ITEM_TYPES[it:getFullType()] and it:getModData().tlg == nil) then
                it = nil
                local items = self.character:getInventory():getItems()
                for i = items:size() - 1, 0, -1 do
                    local x = items:get(i)
                    if x and G.ITEM_TYPES[x:getFullType()] and x:getModData().tlg == nil then
                        it = x
                        break
                    end
                end
            end
            if it then
                it:getModData().tlg = side
                Vault.put("supply", Vault.itemHolder(it), side)
                it:syncItemFields()
            end
            -- The records travel with the item; the tile keeps none.
            Vault.release("supply", from)
            Vault.release("project", from)
        end
        return r
    end)
end

local function attach(obj, side)
    local copy = Tables.deepCopy(side)
    local omd = obj:getModData()
    for _, k in ipairs(G.CARRIED_KEYS) do
        omd[k] = copy[k]
        copy[k] = nil
    end
    omd.tlg = copy
    local holder = function() return G.keyOf(obj) end
    Vault.put("supply", holder, copy)
    if omd.tlgConv ~= nil then Vault.put("project", holder, omd.tlgConv) else Vault.release("project", holder) end
    if omd[G.WEAR_KEY] ~= nil then Vault.putKeyed("wear", copy.id, omd[G.WEAR_KEY]) end
end

-- A carried generator's record, checked against the vault on a server.
local function itemSidecar(item)
    return Vault.guard("supply", function() return Vault.itemHolder(item) end, item:getModData(), "tlg",
        function() item:syncItemFields() end)
end

-- Item sidecar -> object sidecar: the generator converted from `item` is the
-- one within `radius` squares that has no sidecar, the item's type (or none)
-- and the item's fuel (setInfoFromItem copies both, BC).
function G.attachNear(square, item, radius)
    local side = item and itemSidecar(item)
    if square == nil or side == nil or side.kind ~= "generator" then return false end
    local fuel = tonumber(item:getModData().fuel) or 0
    local r = radius or 0
    for dx = -r, r do
        for dy = -r, r do
            local s = square
            if dx ~= 0 or dy ~= 0 then s = getCell():getGridSquare(square:getX() + dx, square:getY() + dy, square:getZ()) end
            local objs = s and s:getObjects()
            for i = 0, (objs and objs:size() or 0) - 1 do
                local o = objs:get(i)
                local omd = instanceof(o, "IsoGenerator") and o:getModData() or nil
                if omd and omd.tlg == nil and (omd.generatorFullType == nil or omd.generatorFullType == item:getFullType())
                    and math.abs(o:getFuel() - fuel) <= 1e-3 then
                    attach(o, side)
                    o:transmitModData()
                    return true
                end
            end
        end
    end
    return false
end

-- Distinct generator items among `a`, `b` that carry a sidecar (a two-handed
-- generator is both the primary and the secondary hand item).
local function carriedGenerators(a, b)
    local out = {}
    for _, it in ipairs({ a or false, b or false }) do
        if it and G.ITEM_TYPES[it:getFullType()] and it:getModData().tlg ~= nil
            and not (out[1] and out[1]:getID() == it:getID()) then
            out[#out + 1] = it
        end
    end
    return out
end

local function reattach(items, square, radius)
    for _, it in ipairs(items) do
        local ok, done = pcall(G.attachNear, square, it, radius)
        if not (ok and done) then TLG.Log.debug("generator sidecar not re-attached: %s", tostring(done)) end
    end
end

local function installPlacement()
    wrap(ISDropWorldItemAction, "complete", function(orig, self)
        local items = World.isAuthority() and carriedGenerators(self.item) or {}
        local sq = self.sq
        local r = orig(self)
        reattach(items, sq, 0)
        return r
    end)
    -- The menus unequip the hands before a generator or another heavy item is
    -- taken or a weapon equipped (SRC ISWorldObjectContextMenu.lua:664-673,
    -- ISInventoryPaneContextMenu.lua:3734, :4166-4171), and the unequip drops
    -- a heavy hand item at the feet itself unless it is unequipped to be
    -- dropped or placed (ISUnequipAction.lua:134). Only a generator that left
    -- the inventory is looked for.
    wrap(ISUnequipAction, "complete", function(orig, self, ...)
        local items, sq = {}, nil
        if World.isAuthority() and self.character then
            items = carriedGenerators(self.item)
            sq = self.character:getCurrentSquare()
        end
        local r = orig(self, ...)
        local inv, dropped = self.character and self.character:getInventory(), {}
        for _, it in ipairs(items) do
            if not (inv and inv:contains(it)) then dropped[#dropped + 1] = it end
        end
        reattach(dropped, sq, 1)
        return r
    end)
    -- Heavy items are also dropped at the character's feet by
    -- forceDropHeavyItems (SRC ISEquipWeaponAction.lua:75, called from 17
    -- places: a vehicle entered, an animal handled, a trap set, the takes).
    if forceDropHeavyItems then
        local origDrop = forceDropHeavyItems
        forceDropHeavyItems = function(character, ...)
            local items, sq = {}, nil
            if character and World.isAuthority() then
                items = carriedGenerators(character:getPrimaryHandItem(), character:getSecondaryHandItem())
                sq = character:getCurrentSquare()
            end
            local r = origDrop(character, ...)
            reattach(items, sq, 1)
            return r
        end
    end
    -- Inventory -> floor transfers (SRC ISTransferAction.lua:95-112).
    wrap(ISTransferAction, "transferItem", function(orig, self, character, item, src, dest, dropSquare, ...)
        local items = {}
        if World.isAuthority() and dest and dest:getType() == "floor" then items = carriedGenerators(item) end
        local r = orig(self, character, item, src, dest, dropSquare, ...)
        reattach(items, dropSquare, 1)
        return r
    end)
    if IsoGenerator and IsoGenerator.new then
        local origNew = IsoGenerator.new
        IsoGenerator.new = function(item, cell, square)
            local g = origNew(item, cell, square)
            local side = g and item and item:getModData().tlg and itemSidecar(item)
            if side and side.kind == "generator" then attach(g, side) end
            return g
        end
    end
end

-- Start gate: the fuel decides whether an activation succeeds.
G.startRoll = function() return ZombRandFloat(0, 1) end
-- Wrong fuel (D-037), replaceable by tests: the condition a refused start
-- costs, and the draw against the chance of a sudden failure.
G.attemptRoll = function(min, max) return ZombRand(min, max + 1) end
G.failRoll = function() return ZombRandFloat(0, 1) end

-- A start the wrong fuel refused costs the generator condition.
function G.attemptDamage(gen, e, player)
    if e == nil or e.compatible or e.attemptDamage == nil then return 0 end
    local n = G.attemptRoll(e.attemptDamage[1], e.attemptDamage[2])
    if n > 0 then gen:setCondition(math.max(0, gen:getCondition() - n)) end
    TLG.Notify.send(player, "IGUI_TLG_Note_StartDamage", e.wrongFuel)
    return n
end

local function installStartGate()
    wrap(ISActivateGenerator, "complete", function(orig, self)
        -- Switched on or off: what burned since the last charge (D-031).
        if World.isAuthority() and self.generator then pcall(G.chargeWear, self.generator) end
        if self.activate and World.isAuthority() then
            local ok, e = pcall(G.evaluate, self.generator)
            if ok and e and e.grade ~= "empty" and (not e.compatible or G.startRoll() > e.startFactor) then
                self.generator:failToStart()
                G.attemptDamage(self.generator, e, self.character)
                self.generator:sync()
                TLG.Log.debug("generator start refused: %s", table.concat(e.reasons, ","))
                return true
            end
            -- Let through on fuel that harms it: the player is told.
            if ok and e and e.harmful then TLG.Notify.send(self.character, "IGUI_TLG_Note_WrongFuel", e.wrongFuel) end
        end
        return orig(self)
    end)
end

function G.install()
    installAddFuel()
    installPickup()
    installPlacement()
    installStartGate()
    -- Before a generator of the world is drawn.
    if Events then
        for _, e in ipairs({ "OnGameStart", "OnLoad" }) do
            if Events[e] then Events[e].Add(G.loadSprites) end
        end
    end
    TLG.Log.info("generator adapter installed")
end

TLG.Boot.addInstaller("generators", G.install)

return G
