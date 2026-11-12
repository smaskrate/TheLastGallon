-- The gasifier commands (D-040, wood gas; TLG/Authority/GasifierHandlers.lua)
-- on the audit's mocks: load, light, put out, clean out and status, refused
-- requests included, and a gas generator beside it fed through the minute
-- pass. Single player (no vault) unless a case says otherwise.
-- Run: tools\run-tests.ps1 -Entry tests/audit/run_audit.lua
require "audit/mocks"
require "TLG/Authority/Handlers"
require "TLG/Authority/ConversionHandlers"
require "TLG/Authority/GasHandlers"
require "TLG/Authority/GasifierHandlers"

local M = AUD
local H = TLG.Authority.Handlers
local G, GZ, GasFeed, Gasifier = TLG.Integration.Generators, TLG.Integration.Gasifiers, TLG.Domain.GasFeed,
    TLG.Domain.Gas.Gasifier
local Vault = TLG.Authority.Vault

local n = 0
local function rid()
    n = n + 1
    return "gz-" .. n
end

M.ensureWorld()

-- A gasifier lying at x,y and a player beside it carrying `wood`
-- (item type -> count).
local function gasifierAt(x, y, wood)
    local item = M.item("TLG.Gasifier")
    M.onFloor(M.square(x, y, 0), item)
    local player = M.player("stoker" .. x, M.square(x + 1, y, 0))
    for t, count in pairs(wood or {}) do
        for _ = 1, count do player:getInventory():AddItem(M.item(t)) end
    end
    return item, player, GZ.refFor(item)
end

local function ask(player, command, ref, id)
    return H.dispatch(player, command, { target = ref, requestId = id or rid() })
end

local function count(player, fullType)
    return player:getInventory():getCountTypeRecurse(fullType)
end

T.case("gasifier: wood and charcoal go into the hopper as whole pieces while they fit", function()
    local item, player, ref = gasifierAt(500, 500, { ["Base.Log"] = 2, ["Base.Firewood"] = 2, ["Base.Charcoal"] = 1,
        ["Base.Twigs"] = 3 })
    local r = ask(player, "gasifier.load", ref)
    T.ok(r.ok, tostring(r.reason))
    T.near(r.loadedKg, 2 * 9 + 2 * 2 + 1 + 3 * 0.3, 1e-9)
    T.eq(r.items, 8)
    T.near(r.hopperKg, r.loadedKg, 1e-9)
    T.eq(r.state, "Ready")
    T.eq(count(player, "Base.Log") + count(player, "Base.Firewood") + count(player, "Base.Charcoal"), 0)
    local st = item:getModData().tlgGasifier
    T.near(st.hopper.firewood, 2 * 9 + 2 * 2 + 0.9, 1e-9)
    T.near(st.hopper.charcoal, 1, 1e-9)
    T.ok(type(st.id) == "string", "the record has its id")
    -- Nothing left to load.
    T.eq(ask(player, "gasifier.load", ref).reason, "needs_wood")
    -- Logs of 9 kg until the hopper is nearly full, then only what fits.
    for _ = 1, 12 do player:getInventory():AddItem(M.item("Base.Log")) end
    player:getInventory():AddItem(M.item("Base.Plank"))
    local more = ask(player, "gasifier.load", ref)
    T.ok(more.ok, tostring(more.reason))
    T.ok(more.hopperKg <= 120 + 1e-9, "no more than the hopper holds")
    T.ok(count(player, "Base.Log") > 0, "a log that does not fit stays")
    T.ok(120 - more.hopperKg < 1.5 or count(player, "Base.Plank") == 0, "a smaller piece fills the gap")
end)

T.case("gasifier: light, the same request once, put out, light again", function()
    local item, player, ref = gasifierAt(510, 500, { ["Base.Log"] = 4 })
    T.eq(ask(player, "gasifier.light", ref).reason, "hopper_empty")
    T.ok(ask(player, "gasifier.load", ref).ok)
    local id = rid()
    local lit = ask(player, "gasifier.light", ref, id)
    T.ok(lit.ok, tostring(lit.reason))
    T.eq(lit.state, "Processing")
    T.eq(lit.mode, "warming")
    local st = item:getModData().tlgGasifier
    T.eq(st.site.x, 510)
    T.eq(st.site.y, 500)
    T.ok(ask(player, "gasifier.light", ref, id).duplicate, "answered from the ledger")
    T.eq(ask(player, "gasifier.light", ref).reason, "busy", "already lit")
    M.now = M.now + 2
    local s = ask(player, "gasifier.status", ref)
    T.eq(s.state, "Paused")
    T.eq(s.pause, "buffer_full")
    T.near(s.buffer, 2.0, 1e-9)
    T.ok(s.holdLeft > 0 and s.holdLeft < 3)
    local out = ask(player, "gasifier.putOut", ref)
    T.ok(out.ok, tostring(out.reason))
    T.eq(out.state, "Ready")
    T.near(out.vented, 2.0, 1e-9)
    T.ok(out.hopperKg > 30, "the wood stays")
    T.eq(ask(player, "gasifier.putOut", ref).reason, "not_lit")
    T.ok(ask(player, "gasifier.light", ref).ok, "lit again from cold")
end)

T.case("gasifier: clean out only when it does not burn; what it held is thrown away", function()
    local item, player, ref = gasifierAt(520, 500, { ["Base.Log"] = 4 })
    T.ok(ask(player, "gasifier.load", ref).ok)
    T.ok(ask(player, "gasifier.light", ref).ok)
    T.eq(ask(player, "gasifier.service", ref).reason, "busy", "not while warming")
    -- Tar and ash from what it burned, as the record holds them.
    M.now = M.now + 1
    local s = ask(player, "gasifier.status", ref)
    T.ok((s.held.wood_tar or 0) > 0 and (s.held.wood_ash or 0) > 0)
    T.ok(s.filter > 0)
    local c = ask(player, "gasifier.service", ref)
    T.ok(c.ok, tostring(c.reason))
    T.near(c.thrownAway.wood_tar, s.held.wood_tar, 1e-12)
    T.eq(c.filter, 0)
    T.ok(TLG.Tables.isEmpty(c.held))
    T.eq(item:getModData().tlgGasifier.filter, 0)
end)

T.case("gasifier: carried it answers Status only; out of reach nothing", function()
    local item, player, ref = gasifierAt(530, 500, { ["Base.Log"] = 4 })
    T.ok(ask(player, "gasifier.load", ref).ok)
    T.ok(ask(player, "gasifier.light", ref).ok)
    -- Taken into the inventory while lit: it goes out at its next read.
    local wi = item:getWorldItem()
    wi:getSquare():removeWorldObject(wi)
    item:setWorldItem(nil)
    player:getInventory():AddItem(item)
    local carriedRef = GZ.refFor(item)
    local s = ask(player, "gasifier.status", carriedRef)
    T.ok(s.ok, tostring(s.reason))
    T.eq(s.placed, false)
    T.eq(s.state, "Ready", "put out when carried")
    T.ok(s.hopperKg > 0)
    T.eq(ask(player, "gasifier.light", carriedRef).reason, "not_placed")
    T.eq(ask(player, "gasifier.load", carriedRef).reason, "not_placed")
    -- Back on the floor, three tiles from the player.
    player:getInventory():Remove(item)
    M.onFloor(M.square(527, 500, 0), item)
    T.eq(ask(player, "gasifier.status", GZ.refFor(item)).reason, "no_access")
    T.eq(ask(player, "gasifier.status", { kind = "gasifier", id = 999999 }).reason, "unknown_target")
end)

-- A generator converted to gas at x,y (its project Commissioned, as the
-- gas commands' tests write it).
local function gasGenerator(x, y, step)
    local gen = M.square(x, y, 0):add(M.object("IsoGenerator", { fuel = 0, maxFuel = 10, step = step }))
    local md = gen:getModData()
    md.tlgDeviceId, md.tlgEngineId = "WGD-" .. x, "WGE-" .. x
    md.tlgConv = {
        v = 1, id = "WGC-" .. x, rev = 1, conversion = "gas_generator", state = "Commissioned", t = 0,
        snap = { targetConsumerProfile = "generator_gas", fuelStorageChanges = {}, cargoAndWeightImpact = {},
            visualConfiguration = {}, workStages = {}, requiredModules = {}, requiredTools = {},
            reversalAndSalvageRules = {} },
        hours = {}, delivered = {}, workers = {}, credit = {}, deviceKey = "gen:WGD-" .. x,
        chassis = "Base.Generator", deviceKind = "generator", engineId = "WGE-" .. x,
        originalProfile = "generator_si_stock", commissionedAt = 0,
    }
    return gen
end

T.case("gasifier: lighting it watches the gas generator beside it, which the minute pass then feeds", function()
    local gen = gasGenerator(540, 502, 0.015)
    local item, player, ref = gasifierAt(540, 500, { ["Base.Log"] = 4 })
    G.gasSquares["540,502,0"] = nil
    T.ok(ask(player, "gasifier.load", ref).ok)
    T.ok(ask(player, "gasifier.light", ref).ok)
    T.ok(G.gasSquares["540,502,0"], "watched")
    M.now = M.now + 1
    G.gasMinute()
    T.near(gen:getFuel(), 0.015 + GasFeed.MARGIN, 1e-9)
    T.ok(G.holdsGas(gen))
    local s = H.dispatch(player, "gas.status", { device = TLG.Authority.Resolver.refForObject(gen, "generator"),
        requestId = rid() })
    T.ok(s.ok, tostring(s.reason))
    T.near(s.woodgasNm3, (0.015 + GasFeed.MARGIN) * 32 / 5, 1e-9)
    T.eq(s.gasifiers, 1)
    T.eq(s.tankUses, nil)
    -- Put out: the generator gets nothing more.
    T.ok(ask(player, "gasifier.putOut", ref).ok)
    gen:setFuel(GasFeed.MARGIN)
    M.now = M.now + 1
    G.watchGas(gen)
    G.gasMinute()
    T.near(gen:getFuel(), GasFeed.MARGIN, 1e-12)
end)

T.case("audit V-01 fixed: a gasifier's record rewritten in its item's mod data is put back", function()
    local World = TLG.World
    local md = World.get()
    local saved = {}
    for _, f in ipairs(World.SERVER_FIELDS) do saved[f] = TLG.Tables.deepCopy(md[f]) end
    local wasServer = M.server
    M.server = true
    Vault.attach(World.attachServerStore({}), false)
    local ok, err = pcall(function()
        local item, player, ref = gasifierAt(550, 500, { ["Base.Log"] = 2 })
        T.ok(ask(player, "gasifier.load", ref).ok)
        local forged = TLG.Tables.deepCopy(item:getModData().tlgGasifier)
        forged.hopper = { charcoal = 120 }
        item:getModData().tlgGasifier = forged
        local s = ask(player, "gasifier.status", ref)
        T.near(s.hopperKg, 18, 1e-9, "the hopper as the server wrote it")
        T.near(item:getModData().tlgGasifier.hopper.firewood, 18, 1e-9)
        -- A record nobody wrote, on a gasifier without one, is dropped.
        local other = gasifierAt(552, 500)
        other:getModData().tlgGasifier = Gasifier.new({ id = "AUDIT-W", machine = "gasifier_stationary", t = 0 })
        other:getModData().tlgGasifier.hopper = { charcoal = 120 }
        T.eq(GZ.stored(other), nil, "a forged record is dropped")
    end)
    M.server = wasServer
    World.store = nil
    for _, f in ipairs(World.SERVER_FIELDS) do md[f] = saved[f] end
    if not ok then error(err, 0) end
end)
