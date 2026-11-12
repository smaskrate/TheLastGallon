-- Authoritative gasifier commands (D-040, wood gas). The client names the
-- gasifier; the wood taken, the hopper's room, the state and the reach are
-- read on the authority.
--   gasifier.load     logs, firewood, planks, twigs and charcoal from the
--                     inventory (TLG/Content/Feedstocks), whole items while
--                     they fit in the hopper
--   gasifier.light    a cold gasifier is lit: it warms up, then makes gas
--   gasifier.putOut   the fire out now; the gas in it is let out and the
--                     wood stays in the hopper
--   gasifier.service  the filter's tar, the grate's ash and the trap's water
--                     taken out and thrown away; not while it burns
--   gasifier.status   its state, read-only; also while carried
-- A carried gasifier answers Status only, as the machines do (D-015). Each
-- action on one lying on the floor watches the gas generators beside it:
-- they look for its gas at their next refill.
require "TLG/Authority/Handlers"
require "TLG/Integration/Gasifiers"
require "TLG/Content/Feedstocks"

local H = TLG.Authority.Handlers
local GZ, Gasifier, World, Tables = TLG.Integration.Gasifiers, TLG.Domain.Gas.Gasifier, TLG.World, TLG.Tables
local Feed = TLG.Feedstocks

-- The machines' reach (MachineHandlers).
H.GASIFIER_REACH = 2.5

local function fail(reason, extra)
    local r = { ok = false, reason = reason }
    for k, v in pairs(extra or {}) do r[k] = v end
    return r
end

-- Wood and charcoal items, by the recipe input each fills.
local INPUT = { wood = "firewood", charcoal = "charcoal" }

local function feedField(item)
    local c = Feed.contribution(item:getFullType())
    if c == nil then return nil end
    if (c.wood or 0) > 0 then return "wood", c.wood end
    if (c.charcoal or 0) > 0 then return "charcoal", c.charcoal end
    return nil
end

-- Whole wood and charcoal items from the inventory, in the order of their
-- ids, while they fit in `room` kg. Returns the load by recipe input, its
-- kg and the items; with `dryRun` nothing is taken.
local function takeFeed(player, room, dryRun)
    local list = player:getInventory():getAllEvalRecurse(function(it) return feedField(it) ~= nil end)
    local items = {}
    for i = 0, list:size() - 1 do items[#items + 1] = list:get(i) end
    items = Tables.sort(items, function(a, b) return a:getID() < b:getID() end)
    local load, got, n = {}, 0, 0
    for _, item in ipairs(items) do
        local field, kg = feedField(item)
        if got + kg <= room + 1e-9 then
            if not dryRun then
                local c = item:getContainer()
                c:Remove(item)
                if isServer() and sendRemoveItemFromContainer then sendRemoveItemFromContainer(c, item) end
            end
            got, n = got + kg, n + 1
            load[INPUT[field]] = (load[INPUT[field]] or 0) + kg
        end
    end
    return load, got, n
end

-- What a reply tells of a gasifier.
local function describe(item, st)
    local s = Gasifier.status(st)
    return { state = s.state, pause = s.reason, mode = s.mode, hopperKg = s.hopperKg, warm = s.warm,
        buffer = s.buffer, bufferCap = s.bufferCap, filter = s.filter, holdLeft = s.holdLeft, held = s.held,
        cond = s.cond, rev = st.rev, placed = GZ.isPlaced(item) }
end

-- The gasifier the request names, within reach, its record brought to now.
-- An action needs it on the floor, and gives a new record its id.
local function open(player, args, placed)
    local item = GZ.find(player, args.target)
    if item == nil then return nil, fail("unknown_target") end
    local sq = GZ.square(item)
    if sq and player:getSquare() and player:getSquare():DistToProper(sq) > H.GASIFIER_REACH then
        return nil, fail("no_access")
    end
    if placed and sq == nil then return nil, fail("not_placed") end
    local st, why = GZ.read(item, placed)
    if st == nil then return nil, fail(why) end
    st = GZ.advance(item, st, World.now())
    if args.expectedRevision ~= nil and args.expectedRevision ~= st.rev then
        return nil, fail("stale", { rev = st.rev })
    end
    return { item = item, st = st }
end

local function commit(player, args, o, st, extra)
    st.rev = (o.st.rev or 0) + 1
    GZ.write(o.item, st)
    GZ.watchGenerators(o.item)
    local r = describe(o.item, st)
    r.ok, r.requestId = true, args.requestId
    for k, v in pairs(extra or {}) do r[k] = v end
    H.ledger:record(H.actorKey(player), args.requestId, r)
    return r
end

-- A command on a gasifier lying on the floor: the same request id is
-- answered from the ledger.
local function action(fn)
    return function(player, args)
        local bad = TLG.Authority.Transactions.validateRequest(args, { "target" })
        if bad then return bad end
        local seen = H.ledger:lookup(H.actorKey(player), args.requestId)
        if seen then
            local copy = Tables.deepCopy(seen)
            copy.duplicate = true
            return copy
        end
        local o, err = open(player, args, true)
        if o == nil then return err end
        return fn(player, args, o)
    end
end

H.commands["gasifier.load"] = action(function(player, args, o)
    local m = TLG.Registry.need("machine", o.st.machine)
    local room = m.capacity - Gasifier.status(o.st).hopperKg
    if room <= 1e-9 then return fail("hopper_full") end
    local load, kg = takeFeed(player, room, true)
    if kg <= 0 then return fail("needs_wood") end
    local r = Gasifier.load(o.st, load, World.now())
    if not r.ok then return fail(r.reason) end
    local _, taken, n = takeFeed(player, room, false)
    return commit(player, args, o, r.st, { loadedKg = taken, items = n })
end)

H.commands["gasifier.light"] = action(function(player, args, o)
    local r = Gasifier.start(o.st, World.now())
    if not r.ok then return fail(r.reason) end
    r.st.site = GZ.siteOf(GZ.square(o.item))
    return commit(player, args, o, r.st)
end)

H.commands["gasifier.putOut"] = action(function(player, args, o)
    local r = Gasifier.putOut(o.st, World.now())
    if not r.ok then return fail(r.reason) end
    return commit(player, args, o, r.st, { vented = r.vented })
end)

H.commands["gasifier.service"] = action(function(player, args, o)
    local r = Gasifier.service(o.st, World.now())
    if not r.ok then return fail(r.reason) end
    return commit(player, args, o, r.st, { thrownAway = r.returned })
end)

-- Read-only (no ledger); the catch-up is kept, as machine.status keeps it.
H.commands["gasifier.status"] = function(player, args)
    local bad = TLG.Authority.Transactions.validateRequest(args, { "target" })
    if bad then return bad end
    local o, err = open(player, args, false)
    if o == nil then return err end
    if o.item:getModData()[GZ.KEY] ~= nil then GZ.write(o.item, o.st) end
    local r = describe(o.item, o.st)
    r.ok, r.requestId = true, args.requestId
    return r
end

return H
