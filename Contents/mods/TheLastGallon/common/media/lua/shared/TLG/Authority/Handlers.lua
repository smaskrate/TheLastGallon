-- Authoritative command handlers. On a dedicated/hosted server they are called
-- from OnClientCommand (server/TLG/Server/Net.lua); in single-player the client
-- calls them directly (client/TLG/Client/Net.lua). Clients never mutate state.
require "TLG/Authority/Transactions"
require "TLG/Authority/Resolver"
require "TLG/Domain/Fuel/Treatment"
require "TLG/Domain/Fuel/Inspection"

TLG.Authority.Handlers = TLG.Authority.Handlers or {}
local H = TLG.Authority.Handlers
local Tx, Res = TLG.Authority.Transactions, TLG.Authority.Resolver
local World, Supply, Aging, Treatment, Inspection = TLG.World, TLG.Domain.Supply, TLG.Domain.Aging,
    TLG.Domain.Treatment, TLG.Domain.Inspection
local Rng = TLG.Rng

H.ledger = H.ledger or TLG.Authority.Ledger.new(64)
H.reservations = H.reservations or TLG.Authority.Reservations.new()

function H.actorKey(player)
    local name = player and player:getUsername()
    if name and name ~= "" then return name end
    return "player" .. tostring(player and player:getPlayerNum() or "?")
end

function H.context(player)
    local ambient
    pcall(function() ambient = getClimateManager():getTemperature() end)
    H.reservations:expire(World.now())
    return { now = World.now(), env = World.env(), ledger = H.ledger, reservations = H.reservations,
        resolve = Res.resolve, player = player, ambientC = ambient }
end

local function protectPours()
    local o = SandboxVars and SandboxVars.TheLastGallon and SandboxVars.TheLastGallon.ProtectIncompatiblePours
    return o ~= false
end

function H.transfer(player, args)
    local ctx = H.context(player)
    if not protectPours() then args.experimental = true end
    return Tx.transfer(ctx, H.actorKey(player), args)
end

-- Opens, validates and advances one endpoint; shared by single-target commands.
local function openTarget(player, args)
    local bad = Tx.validateRequest(args, { "target" })
    if bad then return nil, bad end
    local ctx = H.context(player)
    local seen = ctx.ledger:lookup(H.actorKey(player), args.requestId)
    if seen then
        local copy = TLG.Tables.deepCopy(seen)
        copy.duplicate = true
        return nil, copy
    end
    local ep, why = ctx.resolve(args.target, ctx)
    if ep == nil then return nil, { ok = false, reason = "unknown_target", detail = why } end
    local ok, reason = ep:canAccess(player)
    if not ok then return nil, { ok = false, reason = "no_access", detail = reason } end
    local stored, readError = ep:read()
    if stored == nil then return nil, { ok = false, reason = readError } end
    local rec = Aging.advance(stored, ctx.now, ctx.env)
    if args.expectedRevision ~= nil and args.expectedRevision ~= rec.rev then
        return nil, { ok = false, reason = "stale", rev = rec.rev }
    end
    return { ctx = ctx, ep = ep, rec = rec }
end

local function remember(state, player, args, response)
    state.ctx.ledger:record(H.actorKey(player), args.requestId, response)
    return response
end

local function findItem(player, fullType)
    return player:getInventory():getFirstTypeRecurse(fullType)
end

local function consume(player, item)
    local container = item:getContainer()
    container:Remove(item)
    if isServer() and sendRemoveItemFromContainer then sendRemoveItemFromContainer(container, item) end
end

-- Sampling never moves fuel; the observation is stored per player, under
-- the id the fuel carries. Fuel the mod had not recorded is recorded as
-- found (D-024): before, the observation was filed under an id the fuel
-- never got, and What I know about it stayed "unknown" (RT-SP runs 39-40).
-- A can's fluids are set to that record's composition, the litres the same
-- (D-024 amendment: the water it took up before it was found).
function H.sample(player, args)
    local state, err = openTarget(player, args)
    if not state then return err end
    local method = args.method == "kit" and "kit" or "visual"
    if method == "kit" and not findItem(player, "TLG.FuelSampleKit") then
        return { ok = false, reason = "needs_sample_kit" }
    end
    if state.ep.readStatus == "initialized" and state.ep.record then state.ep:record(state.rec) end
    local skill = 0
    pcall(function() skill = player:getPerkLevel(Perks.Mechanics) / 10 end)
    local seed = Rng.hash(args.requestId .. ":" .. tostring(state.rec.id), World.server().seed or 1)
    local obs = Inspection.sample(state.rec, method, skill, Rng.new(seed))
    obs.supplyId = state.rec.id
    local know = player:getModData().tlgKnowledge or {}
    -- The latest result of each test (a look keeps what a kit found).
    know[tostring(state.rec.id)] = Inspection.remember(know[tostring(state.rec.id)], obs)
    player:getModData().tlgKnowledge = know
    return remember(state, player, args, { ok = true, requestId = args.requestId, observation = obs })
end

local TREATMENTS = {
    stabilize = function(rec, player)
        local bottle = findItem(player, "TLG.FuelStabilizer")
        if not bottle then return { ok = false, reason = "needs_stabilizer" } end
        local r = Treatment.stabilize(rec, 1)
        if r.ok then r.consume = { bottle } end
        return r
    end,
    filter = function(rec, player)
        local filter = findItem(player, "TLG.FuelFilter")
        if not filter then return { ok = false, reason = "needs_filter" } end
        local r = Treatment.filter(rec, { sedimentEff = 0.95, waterCapacity = 0.15, holdup = 0.05, micReduction = 0.3 })
        if r.ok then r.consume = { filter } end
        return r
    end,
    separate = function(rec) return Treatment.separateWater(rec, 1.0) end,
    seal = function(rec) return Treatment.setSealed(rec, true) end,
    unseal = function(rec) return Treatment.setSealed(rec, false) end,
    clean = function(rec) return Treatment.clean(rec) end,
}

function H.treat(player, args)
    local fn = TREATMENTS[args and args.op]
    if fn == nil then return { ok = false, reason = "unknown_operation", requestId = args and args.requestId } end
    local state, err = openTarget(player, args)
    if not state then return err end
    local r = fn(state.rec, player)
    if not r.ok then return { ok = false, reason = r.reason, requestId = args.requestId } end
    local rec = r.supply
    rec.rev = state.rec.rev + 1
    local ok, why = state.ep:write(rec, { kind = "treat", op = args.op, removed = r.removed })
    if not ok then return { ok = false, reason = "commit_failed", detail = why } end
    for _, item in ipairs(r.consume or {}) do consume(player, item) end
    return remember(state, player, args, { ok = true, requestId = args.requestId, op = args.op, removed = r.removed,
        rev = rec.rev, total = Supply.total(rec) })
end

-- Read-only status for UI (no ledger; current authoritative view). Only for
-- what the player could look at: within reach as for sample and treat, or,
-- for a vehicle, from a seat in it (the dashboard). Before, any loaded
-- vehicle, pump or generator answered from anywhere (audit 2026-11-05, V-02).
function H.status(player, args)
    local bad = Tx.validateRequest(args, { "target" })
    if bad then return bad end
    local ctx = H.context(player)
    local ep, why = ctx.resolve(args.target, ctx)
    if ep == nil then return { ok = false, reason = "unknown_target", detail = why, requestId = args.requestId } end
    local ok, reason = (ep.canObserve or ep.canAccess)(ep, player)
    if not ok then return { ok = false, reason = "no_access", detail = reason, requestId = args.requestId } end
    local stored, readError = ep:read()
    if stored == nil then return { ok = false, reason = readError, requestId = args.requestId } end
    local rec = Aging.advance(stored, ctx.now, ctx.env)
    local eval
    if ep.consumer then eval = TLG.Domain.Consumers.evaluate(ep.consumer, rec, { ambientC = ctx.ambientC }) end
    return { ok = true, requestId = args.requestId, rev = rec.rev, total = Supply.total(rec), cap = rec.cap,
        sealed = rec.sealed, primary = Supply.primary(rec), evaluation = eval }
end

-- What the asking player knows about a fuel (read-only, no ledger): each
-- test's latest result, how long ago it was made and whether the fuel
-- changed since, and whether the container is open. Answered by the
-- authority, which keeps the knowledge in its own player object: before,
-- the menu read the player's mod data where it stood, and a multiplayer
-- client's copy never received what the server wrote (audit 2026-11-05,
-- open item). Same reach as status.
function H.known(player, args)
    local bad = Tx.validateRequest(args, { "target" })
    if bad then return bad end
    local ctx = H.context(player)
    local ep, why = ctx.resolve(args.target, ctx)
    if ep == nil then return { ok = false, reason = "unknown_target", detail = why, requestId = args.requestId } end
    local ok, reason = (ep.canObserve or ep.canAccess)(ep, player)
    if not ok then return { ok = false, reason = "no_access", detail = reason, requestId = args.requestId } end
    local stored, readError = ep:read()
    if stored == nil then return { ok = false, reason = readError, requestId = args.requestId } end
    local rec = Aging.advance(stored, ctx.now, ctx.env)
    local know = player:getModData().tlgKnowledge or {}
    local entry = rec.id ~= nil and know[tostring(rec.id)] or nil
    return { ok = true, requestId = args.requestId, tests = Inspection.known(rec, entry), sealed = rec.sealed == true }
end

H.commands = { transfer = H.transfer, sample = H.sample, treat = H.treat, status = H.status, known = H.known }

function H.dispatch(player, command, args)
    local fn = H.commands[command]
    if fn == nil then return { ok = false, reason = "unknown_command", requestId = args and args.requestId } end
    if not World.isAuthority() then return { ok = false, reason = "not_authority" } end
    local r = fn(player, args or {})
    r.requestId = r.requestId or (args and args.requestId)
    r.command = command
    return r
end

return H
