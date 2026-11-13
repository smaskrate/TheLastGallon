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
require "TLG/Domain/GasFeed"
require "TLG/Integration/Gasifiers"
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
local GasFeed = TLG.Domain.GasFeed

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
-- A save loaded without the mod drops the sprite of a placed generator of
-- the mod's, whose tile sheet it no longer has, and saves the object
-- without one (launches 255 and 256). The object keeps its item type in
-- its mod data: a generator with no sprite and a type of G.SPRITES gets
-- that sprite back. Returns true when it gave one.
function G.restoreSprite(gen)
    if not gen or not getSprite then return false end
    local has = gen:getSprite()
    if has ~= nil and has:getName() ~= nil then return false end
    local md = gen:getModData()
    local name = G.SPRITES[md and md.generatorFullType or ""]
    local sprite = name and getSprite(name)
    if not sprite then return false end
    gen:setSprite(sprite)
    if isServer and isServer() and gen.transmitUpdatedSpriteToClients then gen:transmitUpdatedSpriteToClients() end
    TLG.Log.info("generator %s: its sprite %s was missing and is back", tostring(md.generatorFullType), name)
    return true
end

-- For each square as the game loads it. Hooked as this file loads: the
-- squares around the player load before OnGameStart, when the adapter is
-- installed (launch 299). A gas generator, or one with a conversion that
-- may be gas, joins the refills' list (the minute pass drops the others).
function G.onLoadSquare(square)
    local gen = square and square:getGenerator()
    if gen then
        G.restoreSprite(gen)
        local md = gen:getModData()
        if md[G.GAS_KEY] ~= nil or md.tlgConv ~= nil then G.watchGas(gen) end
    end
end
if Events and Events.LoadGridsquare then Events.LoadGridsquare.Add(G.onLoadSquare) end

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

-- A gas generator (D-040): its effective profile burns gas. Its own fuel
-- then holds gas already taken from its source, recorded in mod data
-- "tlgGas" (TLG/Domain/GasFeed), checked against the vault on a server as
-- the fuel record is, and carried with the generator.
G.GAS_KEY = "tlgGas"

function G.isGas(gen)
    local def = TLG.Registry.get("consumer", G.profile(gen))
    return def ~= nil and def.ignition == "gaseous"
end

-- The gas record after the vault's check and the schema check: nil when
-- there is none, or one written by a newer build (left as it is).
function G.gasRecord(gen)
    local raw = Vault.guard("gas", function() return G.keyOf(gen) end, gen:getModData(), G.GAS_KEY, sendFn(gen))
    if raw == nil then return nil end
    return (TLG.Persistence.Migrations.sidecar("gas", raw))
end

-- Whether the generator's fuel is gas. Only then are its liquid paths
-- refused: a converted generator that still holds petrol, from a save of
-- before the feed, is drained as any other.
function G.holdsGas(gen)
    return GasFeed.holdsGas(G.gasRecord(gen), gen:getFuel())
end

-- The litres a refill from a propane tank fills to: the generator's
-- capacity, at most the 10 L setFuel keeps (BC IsoGenerator.setFuel,
-- MaximumGeneratorFuel).
function G.gasCap(gen)
    return math.min(gen:getMaxFuel(), 10)
end

-- The litres a refill of wood gas fills to (D-040): the generator's hourly
-- step now and a margin (GasFeed.MARGIN). getTotalPowerUsing is its load as
-- last counted times the fuel setting: 0 for a generator never switched on,
-- the last running load after it stopped (launch 358). The margin alone is
-- enough to start on; switching on counts the load, and the next minute's
-- refill fills to it before the first step, an hour later at most.
function G.woodgasCap(gen)
    local step = 0
    local ok, v = pcall(function() return gen:getTotalPowerUsing() end)
    if ok and type(v) == "number" and v == v and v > 0 then step = v end
    return math.min(step + GasFeed.MARGIN, G.gasCap(gen))
end

-- The gas generators the authority refills, by square ("x,y,z"). The game
-- gives Lua no list of its generators, and the object is looked up again
-- at each refill rather than held across its chunk's unloading.
G.gasSquares = G.gasSquares or {}
-- Wood gas looked for and none found: the time before which a generator's
-- square is not scanned again (G.woodgasRefill), cleared when it is watched.
G.woodgasWait = G.woodgasWait or {}
G.WOODGAS_RETRY = 10 / 60

local function squareKey(sq)
    return sq:getX() .. "," .. sq:getY() .. "," .. sq:getZ()
end

function G.watchGas(gen)
    local sq = gen and gen:getSquare()
    if sq then
        local key = squareKey(sq)
        G.gasSquares[key] = true
        G.woodgasWait[key] = nil
    end
end

-- Writes the gas record as given (callers set its litres, read back after
-- setFuel).
function G.writeGas(gen, rec)
    gen:getModData()[G.GAS_KEY] = rec
    Vault.put("gas", function() return G.keyOf(gen) end, rec)
    gen:transmitModData()
    G.watchGas(gen)
end

-- Wood gas for a generator with room below the wood-gas cap, drawn from the
-- gasifiers beside it (TLG/Integration/Gasifiers). A scan that finds none
-- with gas waits WOODGAS_RETRY before the next. Returns the Nm3 taken.
function G.woodgasRefill(gen, rec, fuel, cap)
    local key, now = squareKey(gen:getSquare()), World.now()
    local wait = G.woodgasWait[key]
    if wait ~= nil and now < wait then return 0 end
    local got = TLG.Integration.Gasifiers.drawNear(gen:getSquare(), GasFeed.nm3For("woodgas", cap - fuel), now)
    if got <= 0 then
        G.woodgasWait[key] = now + G.WOODGAS_RETRY
        return 0
    end
    G.woodgasWait[key] = nil
    rec = rec or GasFeed.new({ id = World.newId("GS"), t = now })
    pcall(G.chargeWear, gen)
    local f = GasFeed.feed(rec, fuel, cap, "woodgas", got, now)
    gen:setFuel(f.fuel)
    f.rec.fuel = gen:getFuel()
    G.writeGas(gen, f.rec)
    return got
end

-- One refill on the authority, from one source: a propane tank with uses
-- left when one is in (to the generator's capacity), else the gasifiers
-- beside it (to one hourly step and a margin, D-040). What burned since the
-- record was written is charged as wear first (the record changes), then
-- the buffer is topped up. Nothing is written when no gas moves, and nothing
-- goes into a generator that holds other fuel. The cheap tests come first:
-- this runs every game minute. Returns the uses moved, or the Nm3 of wood
-- gas taken.
function G.gasRefill(gen)
    if not World.isAuthority() then return 0 end
    local rec = G.gasRecord(gen)
    -- A newer build's record is left as it is.
    if rec == nil and gen:getModData()[G.GAS_KEY] ~= nil then return 0 end
    local fuel = gen:getFuel()
    local tank = rec ~= nil and rec.tank ~= nil and rec.tank.uses >= 1
    local cap = tank and G.gasCap(gen) or G.woodgasCap(gen)
    if cap - fuel <= GasFeed.TOLERANCE then return 0 end
    -- With a tank in, a room of less than one use moves nothing (whole uses
    -- only), and that is how most minutes find a propane generator: a refill
    -- leaves the rest of the room below the cap. The gas checks below read
    -- the conversion record, so the pass returns first (launches 398-401:
    -- 0.042 ms a minute for such a generator, 0.011 ms for a full one).
    if tank and GasFeed.usesFor(cap - fuel) < 1 then return 0 end
    if fuel > GasFeed.TOLERANCE and not GasFeed.holdsGas(rec, fuel) then return 0 end
    if not G.isGas(gen) then return 0 end
    if not tank then return G.woodgasRefill(gen, rec, fuel, cap) end
    local r = GasFeed.refill(rec, fuel, cap, World.now())
    if r.moved < 1 then return 0 end
    pcall(G.chargeWear, gen)
    gen:setFuel(r.fuel)
    r.rec.fuel = gen:getFuel()
    G.writeGas(gen, r.rec)
    return r.moved
end

-- The authority's minute pass over the gas generators whose squares are
-- loaded (D-040: the hour's first minute event runs before its burn,
-- launches 345-349). A square without its generator, or with one that has
-- no gas record and is not converted to gas, leaves the list.
function G.gasMinute()
    if not World.isAuthority() then return end
    local cell = getCell()
    if cell == nil then return end
    for _, key in ipairs(Tables.sortedKeys(G.gasSquares)) do
        local x, y, z = string.match(key, "^(-?%d+),(-?%d+),(-?%d+)$")
        local sq = x and cell:getGridSquare(tonumber(x), tonumber(y), tonumber(z))
        if sq ~= nil then
            local gen = sq:getGenerator()
            local md = gen and gen:getModData()
            if gen == nil or (md[G.GAS_KEY] == nil and (md.tlgConv == nil or not G.isGas(gen))) then
                G.gasSquares[key] = nil
                G.woodgasWait[key] = nil
            else
                local ok, err = pcall(G.gasRefill, gen)
                if not ok then TLG.Log.error("gas refill at %s: %s", key, tostring(err)) end
            end
        end
    end
end

-- Device identity, conversion projects, the wear fraction and the gas
-- record travel with the generator.
G.WEAR_KEY = "tlgWear"
G.CARRIED_KEYS = { "tlgConv", "tlgDeviceId", "tlgEngineId", G.WEAR_KEY, G.GAS_KEY }

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
    local md = gen:getModData()
    md.tlg = side
    Vault.put("supply", function() return G.keyOf(gen) end, side)
    -- Liquid came in where the gas had burned out: the gas record no longer
    -- stands for the litres (its tank stays).
    local gas = md[G.GAS_KEY] ~= nil and G.gasRecord(gen) or nil
    if gas and (gas.fuel or 0) > 0 then
        local vented = GasFeed.vent(gas, World.now())
        md[G.GAS_KEY] = vented
        Vault.put("gas", function() return G.keyOf(gen) end, vented)
    end
    gen:transmitModData()
end

-- While the buffer holds gas, the gas record is the fuel (D-040).
function G.evaluate(gen)
    local ambient
    pcall(function() ambient = getClimateManager():getTemperature() end)
    local gas, fuel = G.gasRecord(gen), gen:getFuel()
    if GasFeed.holdsGas(gas, fuel) then
        local s = GasFeed.supply(gas, fuel)
        return Consumers.evaluate(G.profile(gen), s, { ambientC = ambient }), s
    end
    local rec = G.read(gen, false)
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
-- What the wear is charged on: the gas record when it held gas at its last
-- write (D-040: its litres are petrol-equivalent, worn as petrol's), else
-- the fuel record. Returns the record's id, the litres written, the key of
-- that write and a function giving the fuel to evaluate; nil without one.
local function wearBasis(gen, fuel)
    local gas = G.gasRecord(gen)
    if gas ~= nil and (gas.fuel or 0) > GasFeed.TOLERANCE then
        return gas.id, gas.fuel, string.format("%.6f|%s|%s", gas.fuel, tostring(gas.id), tostring(gas.t)),
            function() return GasFeed.supply(gas, gas.fuel) end
    end
    local side = sidecarIn(gen)
    if type(side) ~= "table" or side.q == nil then return nil end
    local rec = fromSidecar(side, math.max(gen:getMaxFuel(), fuel))
    local written = Supply.total(rec)
    return side.id, written, string.format("%.6f|%s|%s", written, tostring(side.rev), tostring(side.t)),
        function() return Aging.advance(rec, World.now(), World.env()) end
end

function G.chargeWear(gen)
    if not World.isAuthority() then return 0 end
    local md = gen:getModData()
    local fuel = gen:getFuel()
    local id, written, key, fuelOf = wearBasis(gen, fuel)
    if written == nil then return 0 end
    -- Kept in the vault under the record's id; one the vault does not know
    -- yet (a save from before it) is taken as found once.
    local w = Vault.guardKeyed("wear", id, md, G.WEAR_KEY, sendFn(gen))
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
        local e = Consumers.evaluate(G.profile(gen), fuelOf(), { ambientC = ambient })
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
    Vault.putKeyed("wear", id, w)
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
                -- A generator that holds gas takes no liquid (refused below).
                if G.holdsGas(generator) then return end
                -- Before the refuel moves the tank past what burned.
                G.chargeWear(generator)
                o.tlgGenBefore = G.read(generator, true)
                o.tlgCanBefore = C.read(petrol, "item", true)
                o.tlgFuelStart = generator:getFuel()
            end)
        end
        return o
    end
    -- A generator whose fuel is gas takes no liquid (D-040): the menu's
    -- action is not valid, and the authority refuses it at complete, which a
    -- server runs for a client's action (engine-capabilities, RT-MP).
    wrap(ISAddFuel, "isValid", function(orig, self, ...)
        local ok, gas = pcall(G.holdsGas, self.generator)
        if ok and gas then return false end
        return orig(self, ...)
    end)
    wrap(ISAddFuel, "complete", function(orig, self)
        if World.isAuthority() and self.generator then
            local ok, gas = pcall(G.holdsGas, self.generator)
            if ok and gas then
                TLG.Notify.send(self.character, "IGUI_TLG_Note_GasOnly")
                return true
            end
        end
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
                local gas = G.holdsGas(self.generator)
                local rec = Aging.advance((G.read(self.generator, true)), World.now(), World.env())
                -- Litres that are gas carry no petrol-looking fuel record:
                -- the gas record goes with the carried keys (D-040).
                if gas then rec.q, rec.deg = {}, {} end
                side = sidecarOf(rec, G.baseProfile(self.generator))
                local omd = self.generator:getModData()
                -- Taken before the generator leaves its square.
                from = Vault.active() and G.keyOf(self.generator) or nil
                -- The project, the wear and the gas record as the vault has
                -- them (they are put back in omd when they differ).
                local CD = TLG.Integration.ConversionDevices
                if CD then CD.project(omd, from, sendFn(self.generator)) end
                Vault.guardKeyed("wear", rec.id, omd, G.WEAR_KEY, sendFn(self.generator))
                if from then Vault.guard("gas", from, omd, G.GAS_KEY, sendFn(self.generator)) end
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
            Vault.release("gas", from)
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
    if omd[G.GAS_KEY] ~= nil then
        Vault.put("gas", holder, omd[G.GAS_KEY])
        G.watchGas(obj)
    else
        Vault.release("gas", holder)
    end
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
        -- The gas generators' refills (D-040).
        if Events.EveryOneMinute then Events.EveryOneMinute.Add(G.gasMinute) end
    end
    TLG.Log.info("generator adapter installed")
end

TLG.Boot.addInstaller("generators", G.install)

return G
