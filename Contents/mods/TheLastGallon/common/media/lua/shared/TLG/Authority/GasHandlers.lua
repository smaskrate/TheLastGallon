-- Authoritative gas-feed commands (D-040, propane). A propane tank goes into
-- a gas generator, as into the game's propane barbecue, and comes out again;
-- the generator's gas can be read. The client names the generator only: the
-- tank, its uses, the generator's profile, its fuel and the reach are read
-- on the authority.
--   gas.connect  a Base.PropaneTank with uses left, from the inventory or else
--                the floor beside the generator, goes in (the item is
--                removed, its uses kept in the record) and the buffer is
--                filled at once. Refused while a tank is in, on a generator
--                that is not converted to gas, and on one that holds liquid
--                fuel (drain it first).
--   gas.remove   the tank comes out with the propane the buffer has not
--                burned, in whole uses (GasFeed.disconnect).
--   gas.status   the buffer's litres and propane, the tank's uses.
require "TLG/Authority/Handlers"
require "TLG/Integration/Generators"

local H = TLG.Authority.Handlers
local G, GasFeed, Gas, World, Tables = TLG.Integration.Generators, TLG.Domain.GasFeed, TLG.Domain.Gas, TLG.World,
    TLG.Tables
local Res = TLG.Authority.Resolver

H.PROPANE_TANK = "Base.PropaneTank"

local function fail(reason, extra)
    local r = { ok = false, reason = reason }
    for k, v in pairs(extra or {}) do r[k] = v end
    return r
end

-- The generator the request names, within the reach of the workshop's.
local function openGenerator(player, ref)
    if type(ref) ~= "table" or ref.kind ~= "generator" then return nil, fail("malformed_device") end
    local ep, why = Res.resolve(ref, H.context(player))
    if ep == nil then return nil, fail(why or "no_generator") end
    if not ep:canAccess(player) then return nil, fail("no_access") end
    local sq = getCell():getGridSquare(ref.x, ref.y, ref.z)
    local gen = sq and sq:getObjects():get(ref.index)
    if gen == nil or not instanceof(gen, "IsoGenerator") then return nil, fail("no_generator") end
    return gen
end

-- A tank's whole uses (the game keeps whole uses, launches 342 and 345).
function H.tankUses(item)
    return math.floor(item:getCurrentUsesFloat() / item:getUseDelta() + 0.5)
end

-- A propane tank with uses left: the first in the inventory, else the first
-- on the floor within a square of the generator. Returns it and "inventory"
-- or "floor".
local function findTank(player, gen)
    local list = player:getInventory():getAllTypeRecurse(H.PROPANE_TANK)
    for i = 0, (list and list:size() or 0) - 1 do
        local it = list:get(i)
        if H.tankUses(it) >= 1 then return it, "inventory" end
    end
    local sq = gen:getSquare()
    for dx = -1, 1 do
        for dy = -1, 1 do
            local s = sq and getCell():getGridSquare(sq:getX() + dx, sq:getY() + dy, sq:getZ())
            local objs = s and s:getWorldObjects()
            for i = 0, (objs and objs:size() or 0) - 1 do
                local it = objs:get(i):getItem()
                if it and it:getFullType() == H.PROPANE_TANK and H.tankUses(it) >= 1 then return it, "floor" end
            end
        end
    end
    return nil
end

-- Takes the tank item out of the world: off the floor as the game's floor
-- transfer does (as Machines.liftFromGround), or out of its container.
local function takeTank(item, where)
    if where == "floor" then
        local wi = item:getWorldItem()
        local sq = wi and wi:getSquare()
        if sq then
            sq:transmitRemoveItemFromSquare(wi)
            sq:removeWorldObject(wi)
        end
        item:setWorldItem(nil)
        return
    end
    local c = item:getContainer()
    c:Remove(item)
    if isServer() and sendRemoveItemFromContainer then sendRemoveItemFromContainer(c, item) end
end

-- The tank comes out with the propane the buffer has not burned, in whole
-- uses, into `player`'s inventory; the record is written without it.
-- Shared with conversion.remove. Returns the uses given, or nil and why.
function H.gasTakeTank(player, gen, rec)
    pcall(G.chargeWear, gen)
    local d = GasFeed.disconnect(rec, gen:getFuel(), World.now())
    if not d.ok then return nil, d.reason end
    gen:setFuel(d.fuel)
    d.rec.fuel = gen:getFuel()
    G.writeGas(gen, d.rec)
    local item = instanceItem(H.PROPANE_TANK)
    item:setUsedDelta(d.uses * item:getUseDelta())
    local inv = player:getInventory()
    inv:AddItem(item)
    if isServer() and sendAddItemToContainer then sendAddItemToContainer(inv, item) end
    return d.uses
end

-- Same request id answered from the ledger.
local function seenBefore(player, args)
    local seen = H.ledger:lookup(H.actorKey(player), args.requestId)
    if not seen then return nil end
    local copy = Tables.deepCopy(seen)
    copy.duplicate = true
    return copy
end

local function answer(player, args, reply)
    reply.requestId = args.requestId
    H.ledger:record(H.actorKey(player), args.requestId, reply)
    return reply
end

H.commands["gas.connect"] = function(player, args)
    local bad = TLG.Authority.Transactions.validateRequest(args, { "device" })
    if bad then return bad end
    local seen = seenBefore(player, args)
    if seen then return seen end
    local gen, err = openGenerator(player, args.device)
    if gen == nil then return err end
    if not G.isGas(gen) then return fail("not_gas_generator") end
    local md, rec = gen:getModData(), G.gasRecord(gen)
    if md[G.GAS_KEY] ~= nil and rec == nil then return fail("future_schema") end
    if rec and rec.tank then return fail("tank_connected") end
    local fuel = gen:getFuel()
    if fuel > GasFeed.TOLERANCE and not GasFeed.holdsGas(rec, fuel) then return fail("not_drained", { fuel = fuel }) end
    local tank, where = findTank(player, gen)
    if tank == nil then return fail("no_propane_tank") end
    local uses = H.tankUses(tank)
    pcall(G.chargeWear, gen)
    -- The record re-based on the litres held now (the gas left, if any).
    rec = rec or GasFeed.new({ id = World.newId("GS"), t = World.now() })
    local base = Tables.deepCopy(rec)
    base.buf, base.fuel = GasFeed.current(rec, fuel), fuel
    local c = GasFeed.connect(base, uses, World.now())
    if not c.ok then return fail(c.reason) end
    takeTank(tank, where)
    G.writeGas(gen, c.rec)
    local moved = G.gasRefill(gen)
    return answer(player, args, { ok = true, uses = uses, moved = moved, fuel = gen:getFuel(), from = where })
end

H.commands["gas.remove"] = function(player, args)
    local bad = TLG.Authority.Transactions.validateRequest(args, { "device" })
    if bad then return bad end
    local seen = seenBefore(player, args)
    if seen then return seen end
    local gen, err = openGenerator(player, args.device)
    if gen == nil then return err end
    local md, rec = gen:getModData(), G.gasRecord(gen)
    if md[G.GAS_KEY] ~= nil and rec == nil then return fail("future_schema") end
    if rec == nil or rec.tank == nil then return fail("no_tank") end
    local uses, why = H.gasTakeTank(player, gen, rec)
    if uses == nil then return fail(why) end
    return answer(player, args, { ok = true, uses = uses, fuel = gen:getFuel() })
end

-- Read-only (no ledger), within the same reach.
H.commands["gas.status"] = function(player, args)
    local bad = TLG.Authority.Transactions.validateRequest(args, { "device" })
    if bad then return bad end
    local gen, err = openGenerator(player, args.device)
    if gen == nil then return err end
    local rec, fuel = G.gasRecord(gen), gen:getFuel()
    local held = GasFeed.holdsGas(rec, fuel)
    local cur = held and GasFeed.current(rec, fuel) or {}
    local tank = rec and rec.tank
    return { ok = true, requestId = args.requestId, gas = G.isGas(gen), holdsGas = held, fuel = fuel,
        cap = G.gasCap(gen), propaneKg = Gas.toKg("propane", cur.propane or 0), tankUses = tank and tank.uses,
        tankKg = tank and Gas.toKg("propane", Gas.usesToNm3(tank.uses)) }
end

return H
