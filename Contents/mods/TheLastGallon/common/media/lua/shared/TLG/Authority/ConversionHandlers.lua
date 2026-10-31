-- Authoritative workshop-conversion commands. The client names the device
-- and the conversion; skills, tools, parts, tank contents and elapsed work
-- time are always read on the authority (never client-reported).
require "TLG/Authority/Handlers"
require "TLG/Integration/ConversionDevices"

local H = TLG.Authority.Handlers
local CD, CS, World, Tables = TLG.Integration.ConversionDevices, TLG.Domain.ConversionService, TLG.World, TLG.Tables
local Res = TLG.Authority.Resolver

local function fail(reason, extra)
    local r = { ok = false, reason = reason }
    for k, v in pairs(extra or {}) do r[k] = v end
    return r
end

-- Resolves the device; returns descriptor, modData store, holder (for sync).
local function openDevice(player, ref)
    if type(ref) ~= "table" then return nil, fail("malformed_device") end
    if ref.kind == "vehicle" then
        if type(ref.id) ~= "number" then return nil, fail("malformed_device") end
        local v = getVehicleById(ref.id)
        if v == nil then return nil, fail("no_vehicle") end
        if player:DistTo(v:getX(), v:getY()) > 4 then return nil, fail("no_access") end
        local device, md, engine = CD.describeVehicle(v, true)
        if device == nil then return nil, fail("no_engine") end
        return { device = device, md = md, holder = engine }
    elseif ref.kind == "generator" then
        local ctx = H.context(player)
        local ep, why = Res.resolve(ref, ctx)
        if ep == nil then return nil, fail(why or "no_generator") end
        local ok = ep:canAccess(player)
        if not ok then return nil, fail("no_access") end
        local sq = getCell():getGridSquare(ref.x, ref.y, ref.z)
        local gen = sq:getObjects():get(ref.index)
        local device, md = CD.describeGenerator(gen, true)
        return { device = device, md = md, holder = gen }
    end
    return nil, fail("malformed_device")
end

local function giveItems(player, list)
    for _, id in ipairs(Tables.sortedKeys(list or {})) do
        for _ = 1, list[id] do player:getInventory():AddItem(id) end
    end
end

local function takeItems(player, list)
    for _, id in ipairs(Tables.sortedKeys(list or {})) do
        for _ = 1, list[id] do
            local it = player:getInventory():getFirstTypeRecurse(id)
            if it then
                local c = it:getContainer()
                c:Remove(it)
                if isServer() and sendRemoveItemFromContainer then sendRemoveItemFromContainer(c, it) end
            end
        end
    end
end

-- Runs one ConversionService call and commits the resulting project.
local function run(player, args, fn)
    local bad = TLG.Authority.Transactions.validateRequest(args, { "device" })
    if bad then return bad end
    local seen = H.ledger:lookup(H.actorKey(player), args.requestId)
    if seen then
        local copy = Tables.deepCopy(seen)
        copy.duplicate = true
        return copy
    end
    local d, err = openDevice(player, args.device)
    if d == nil then return err end
    -- Never overwrite a project written by a newer build.
    local project, status = CD.project(d.md)
    if d.md[CD.KEY] ~= nil and project == nil then return fail(status) end
    local actor = CD.actor(player, project, args.conversion)
    local req = { now = World.now(), expectedRev = args.expectedRevision, leave = args.leave,
        workerTimeoutHours = CD.WORKER_TIMEOUT_HOURS }
    local r = fn(project, actor, d.device, req, d)
    if not r.ok then return fail(r.reason, { missing = r.missing, rev = r.rev, state = r.state }) end
    if not r.unchanged then CD.store(d.md, d.holder, r.project) end
    takeItems(player, r.consumed)
    giveItems(player, r.returned)
    local s = CS.status(r.project, actor, d.device)
    local reply = { ok = true, requestId = args.requestId, state = r.project.state, rev = r.project.rev,
        stage = s and s.stage, blocked = r.project.blocked, consumed = r.consumed, returned = r.returned,
        lost = r.lost, outstanding = r.outstanding, credited = r.credited, released = r.released,
        expired = r.expired, doneHours = s and s.doneHours, totalHours = s and s.totalHours }
    H.ledger:record(H.actorKey(player), args.requestId, reply)
    return reply
end

H.commands["conversion.begin"] = function(player, args)
    if type(args.conversion) ~= "string" then return fail("malformed_request") end
    return run(player, args, function(project, actor, device, req)
        if project == nil or project.state ~= "InProgress" and project.state ~= "Commissioned" then
            project = CS.new({ id = World.newId("C"), conversion = args.conversion, t = req.now })
        end
        local b = CS.begin(project, actor, device, req)
        if not b.ok then return b end
        local j = CS.join(b.project, actor, device, { now = req.now })
        if j.ok then return j end
        return b
    end)
end

H.commands["conversion.join"] = function(player, args)
    return run(player, args, function(p, a, d, req) return CS.join(p, a, d, req) end)
end

H.commands["conversion.work"] = function(player, args)
    return run(player, args, function(p, a, d, req) return CS.work(p, a, d, req) end)
end

H.commands["conversion.deliver"] = function(player, args)
    return run(player, args, function(p, a, d, req) return CS.deliver(p, a, d, req) end)
end

H.commands["conversion.cancel"] = function(player, args)
    return run(player, args, function(p, a, d, req) return CS.cancel(p, a, d, req) end)
end

H.commands["conversion.remove"] = function(player, args)
    return run(player, args, function(p, a, d, req) return CS.remove(p, a, d, req) end)
end

H.commands["conversion.status"] = function(player, args)
    local bad = TLG.Authority.Transactions.validateRequest(args, { "device" })
    if bad then return bad end
    local d, err = openDevice(player, args.device)
    if d == nil then return err end
    local project, status = CD.project(d.md)
    if d.md[CD.KEY] ~= nil and project == nil then return fail(status) end
    local options = {}
    for _, row in ipairs(CS.matrix()) do
        if row.chassis == d.device.chassis then options[#options + 1] = row.conversion end
    end
    local s = project and CS.status(project, CD.actor(player, project), d.device) or nil
    return { ok = true, requestId = args.requestId, state = project and project.state or "none",
        conversion = project and project.conversion, stage = s and s.stage, blocked = project and project.blocked,
        options = options, profile = (d.device.kind == "vehicle") and TLG.Integration.Vehicles.profile(getVehicleById(args.device.id))
            or TLG.Integration.Generators.profile(d.holder) }
end

return H
