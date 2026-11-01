-- Authoritative machine commands (M3 ethanol chain). Inputs are taken from
-- the requesting player's inventory on the authority; clients only name the
-- machine and the requested amounts, which are bounded server-side.
require "TLG/Authority/Handlers"
require "TLG/Integration/Machines"
require "TLG/Content/Feedstocks"

local H = TLG.Authority.Handlers
local Machines, Process, World = TLG.Integration.Machines, TLG.Domain.Process, TLG.World
local C, Native = TLG.Integration.Containers, TLG.Integration.Native
local Supply, Mixing, Aging, Tables = TLG.Domain.Supply, TLG.Domain.Mixing, TLG.Domain.Aging, TLG.Tables
local Feed = TLG.Feedstocks

local function fail(reason, extra)
    local r = { ok = false, reason = reason }
    for k, v in pairs(extra or {}) do r[k] = v end
    return r
end

local function sortedItems(player, pred)
    local list = player:getInventory():getAllEvalRecurse(pred)
    local out = {}
    for i = 0, list:size() - 1 do out[#out + 1] = list:get(i) end
    return Tables.sort(out, function(a, b) return a:getID() < b:getID() end)
end

local function removeItem(item)
    local container = item:getContainer()
    container:Remove(item)
    if isServer() and sendRemoveItemFromContainer then sendRemoveItemFromContainer(container, item) end
end

-- Consumes whole feedstock items until `need` units of `field` are reached
-- (never more than `max`). Returns the amount consumed. With `dryRun` nothing
-- is removed, so callers can validate a batch before taking anything.
local function takeFeedstock(player, field, need, max, dryRun)
    local got = 0
    for _, item in ipairs(sortedItems(player, function(it)
        local c = Feed.contribution(it:getFullType())
        return c ~= nil and (c[field] or 0) > 0
    end)) do
        if got >= need then break end
        local c = Feed.contribution(item:getFullType())[field]
        if got + c <= max + 1e-9 then
            if not dryRun then removeItem(item) end
            got = got + c
        end
    end
    return got
end

-- Drains up to `litres` of clean water from the player's containers.
local function takeWater(player, litres, dryRun)
    local got = 0
    for _, item in ipairs(sortedItems(player, function(it)
        local fc = it:getFluidContainer()
        return fc ~= nil and not fc:isEmpty() and fc:isPureFluid(Fluid.Water)
    end)) do
        if got >= litres - 1e-9 then break end
        local fc = item:getFluidContainer()
        local take = math.min(fc:getAmount(), litres - got)
        if not dryRun then
            fc:adjustAmount(fc:getAmount() - take)
            item:syncItemFields()
        end
        got = got + take
    end
    return got
end

local function machineState(player, args)
    local bad = TLG.Authority.Transactions.validateRequest(args, { "target" })
    if bad then return nil, bad end
    local seen = H.ledger:lookup(H.actorKey(player), args.requestId)
    if seen then
        local copy = Tables.deepCopy(seen)
        copy.duplicate = true
        return nil, copy
    end
    local item = Machines.find(player, args.target)
    if item == nil then return nil, fail("unknown_target") end
    local sq = Machines.square(item)
    if sq and player:getSquare() and player:getSquare():DistToProper(sq) > 2.5 then
        return nil, fail("no_access")
    end
    local rec, why = Machines.read(item, true)
    if rec == nil then return nil, fail(why) end
    rec = Machines.advance(item, rec, World.now(), World.env())
    Machines.index(item, rec)
    if args.expectedRevision ~= nil and args.expectedRevision ~= rec.rev then
        return nil, fail("stale", { rev = rec.rev })
    end
    return { item = item, rec = rec }
end

local function commit(player, args, st, rec, extra)
    rec.rev = (st.rec.rev or 0) + 1
    Machines.write(st.item, rec)
    local r = { ok = true, requestId = args.requestId, state = rec.state, pause = rec.pause, rev = rec.rev,
        outputs = rec.outputs, firebox = rec.firebox, machine = rec.machine, stoppedEarly = rec.stoppedEarly }
    for k, v in pairs(extra or {}) do r[k] = v end
    H.ledger:record(H.actorKey(player), args.requestId, r)
    return r
end

function H.machineStatus(player, args)
    local st, err = machineState(player, args)
    if not st then return err end
    -- Status persists the catch-up so repeated views are cheap.
    Machines.write(st.item, st.rec)
    local s = Process.status(st.rec)
    local siteC, siteNow, site = Machines.siteTemp(st.item, st.rec, World.now(), World.env())
    return { ok = true, requestId = args.requestId, state = s.state, pause = s.reason, stage = s.stage,
        outputs = st.rec.outputs, firebox = st.rec.firebox, cond = st.rec.cond, rev = st.rec.rev,
        machine = st.rec.machine, inputs = st.rec.inputs, stageDone = st.rec.stageDone,
        siteC = siteC, siteNow = siteNow, site = site, stoppedEarly = st.rec.stoppedEarly }
end

function H.machineLoadFerment(player, args)
    local st, err = machineState(player, args)
    if not st then return err end
    if Machines.machineFor(st.item) ~= "fermenter_barrel" then return fail("wrong_machine") end
    if not Machines.isPlaced(st.item) then return fail("not_placed") end
    local recipe = TLG.Registry.need("recipe", "ethanol_ferment")
    local sugarWanted = TLG.Num.clamp(tonumber(args.sugarKg) or recipe.inputs.sugar_eq.max, 0, recipe.inputs.sugar_eq.max)
    local yeast = player:getInventory():getFirstTypeRecurse("Base.Yeast")
        or player:getInventory():getFirstTypeRecurse("TLG.YeastStarter")
    if yeast == nil then return fail("needs_yeast") end
    -- Validate with what is actually available before taking anything.
    local sugarAvail = takeFeedstock(player, "sugar_eq", sugarWanted, recipe.inputs.sugar_eq.max, true)
    -- Without an amount (the menu sends none) the water follows the sugar
    -- actually there, 5 L per kg; it used to follow the 30 kg maximum, so up
    -- to 130 L went into a 6 kg mash (found 2026-10-31).
    local waterWanted = TLG.Num.clamp(tonumber(args.waterL) or sugarAvail * 5, 0, recipe.inputs.water.max)
    local waterAvail = takeWater(player, waterWanted, true)
    local plan = Process.plan("ethanol_ferment", { sugar_eq = sugarAvail, water = waterAvail }, st.rec)
    if not plan.ok then return fail(plan.reason, { sugarAvailableKg = sugarAvail, waterAvailableL = waterAvail }) end
    local sugar = takeFeedstock(player, "sugar_eq", sugarWanted, recipe.inputs.sugar_eq.max)
    local water = takeWater(player, waterWanted)
    local loaded = Process.load(st.rec, "ethanol_ferment", { sugar_eq = sugar, water = water },
        player:getPerkLevel(Perks.Cooking))
    if not loaded.ok then
        TLG.Log.error("ferment load failed after validation: %s", tostring(loaded.reason))
        return fail(loaded.reason)
    end
    removeItem(yeast)
    local started = Process.start(loaded.proc, World.now())
    return commit(player, args, st, started.proc, { sugarKg = sugar, waterL = water })
end

function H.machineLoadWash(player, args)
    local st, err = machineState(player, args)
    if not st then return err end
    local mid = Machines.machineFor(st.item)
    if mid ~= "pot_still" and mid ~= "reflux_still" then return fail("wrong_machine") end
    if not Machines.isPlaced(st.item) then return fail("not_placed") end
    local fermenterItem
    for _, it in ipairs(Machines.nearbyMachines(Machines.square(st.item), 2, "fermenter")) do
        local r = Machines.advance(it, (Machines.read(it, true)), World.now(), World.env())
        if r.state == "OutputReady" then fermenterItem = it; break end
    end
    if fermenterItem == nil then return fail("no_ready_fermenter") end
    local frec = Machines.advance(fermenterItem, (Machines.read(fermenterItem, true)), World.now(), World.env())
    local still = TLG.Registry.need("machine", mid)
    local collected = Process.collect(frec, still.capacity)
    if not collected.ok then return fail(collected.reason) end
    local parcel = collected.parcel
    local loaded = Process.load(st.rec, "ethanol_distill",
        { ethanol = parcel.ethanol or 0, water = parcel.water or 0, sugar_eq = parcel.sugar_eq },
        player:getPerkLevel(Perks.Cooking))
    if not loaded.ok then return fail(loaded.reason) end
    collected.proc.rev = (frec.rev or 0) + 1
    Machines.write(fermenterItem, collected.proc)
    local started = Process.start(loaded.proc, World.now())
    local byproducts = collected.byproducts
    if byproducts and byproducts.yeast_starter then
        player:getInventory():AddItem("TLG.YeastStarter")
    end
    return commit(player, args, st, started.proc, { washL = (parcel.ethanol or 0) + (parcel.water or 0) })
end

function H.machineAddFuel(player, args)
    local st, err = machineState(player, args)
    if not st then return err end
    local m = TLG.Registry.need("machine", st.rec.machine)
    if not m.firebox then return fail("no_firebox") end
    local room = m.firebox.capacityKg - st.rec.firebox
    local wanted = TLG.Num.clamp(tonumber(args.kg) or room, 0, room)
    local kg = takeFeedstock(player, "wood", wanted, room)
    if kg <= 0 then return fail("needs_wood") end
    local r = Process.addFirebox(st.rec, kg)
    if not r.ok then return fail(r.reason) end
    return commit(player, args, st, r.proc, { addedKg = r.used })
end

local function simple(fn)
    return function(player, args)
        local st, err = machineState(player, args)
        if not st then return err end
        local r = fn(st.rec)
        if not r.ok then return fail(r.reason) end
        return commit(player, args, st, r.proc)
    end
end

-- Dries hydrous ethanol from a can in the player's inventory with quicklime
-- (drying column, recipe ethanol_dry). The ethanol and water move into the
-- column; machine.collect bottles the result, which keeps the source's
-- degradation (quicklime removes water, not ageing products).
function H.machineLoadDry(player, args)
    local st, err = machineState(player, args)
    if not st then return err end
    if Machines.machineFor(st.item) ~= "drying_column" then return fail("wrong_machine") end
    if not Machines.isPlaced(st.item) then return fail("not_placed") end
    if type(args.source) ~= "table" then return fail("malformed_source") end
    local can = player:getInventory():getItemWithIDRecursiv(args.source.id or -1)
    if can == nil or can:getFluidContainer() == nil then return fail("no_source") end
    local now, env = World.now(), World.env()
    local src = C.read(can, "item", true)
    if src == nil then return fail("source_not_fuel") end
    src = Aging.advance(src, now, env)
    for _, id in ipairs(Tables.sortedKeys(src.q)) do
        if id ~= "ethanol" and id ~= "water" and src.q[id] > 1e-6 then return fail("not_hydrous_ethanol") end
    end
    local recipe = TLG.Registry.need("recipe", "ethanol_dry")
    local column = TLG.Registry.need("machine", "drying_column")
    local p = recipe.params
    local eth, water = src.q.ethanol or 0, src.q.water or 0
    if eth < recipe.inputs.ethanol.min then return fail("not_hydrous_ethanol") end
    if water <= eth * p.targetWater + 1e-9 then return fail("already_dry") end
    local limeMax = recipe.inputs.quicklime_kg.max
    -- Share of the can that fits the recipe bounds and the column (lime counts
    -- towards the column's capacity).
    local scale = math.min(1, recipe.inputs.ethanol.max / eth, recipe.inputs.water.max / water,
        (column.capacity - limeMax) / (eth + water))
    local limeNeed = (water - eth * p.targetWater) * scale / p.waterPerKgLime
    local lime = takeFeedstock(player, "lime", limeNeed, limeMax, true)
    if lime < recipe.inputs.quicklime_kg.min then return fail("needs_lime") end
    local remaining, parcel = Mixing.removeProportional(src, (eth + water) * scale)
    local inputs = { ethanol = parcel.ethanol or 0, water = parcel.water or 0, quicklime_kg = lime }
    local plan = Process.plan("ethanol_dry", inputs, st.rec)
    if not plan.ok then return fail(plan.reason) end
    takeFeedstock(player, "lime", limeNeed, limeMax)
    local ok, why = Native.writeComposition(can:getFluidContainer(), remaining.q)
    if not ok then return fail("commit_failed", { detail = why }) end
    remaining.rev = (src.rev or 0) + 1
    C.writeSidecar(can, "item", remaining)
    local loaded = Process.load(st.rec, "ethanol_dry", inputs, player:getPerkLevel(Perks.Cooking))
    if not loaded.ok then
        TLG.Log.error("dry load failed after validation: %s", tostring(loaded.reason))
        return fail(loaded.reason)
    end
    local started = Process.start(loaded.proc, now)
    started.proc.carryDeg = Tables.deepCopy(src.deg)
    return commit(player, args, st, started.proc, { ethanolL = inputs.ethanol, waterL = inputs.water, limeKg = lime })
end

H.machinePause = simple(Process.pauseCmd)
H.machineResume = simple(Process.resumeCmd)

-- Aborting keeps what the batch made in the machine, to collect, and throws
-- the rest away; the reply lists both (Process.abort). It also empties a
-- spoiled batch and the output an earlier abort kept. Until run 31 the
-- partial result was only reported, and lost.
function H.machineAbort(player, args)
    local st, err = machineState(player, args)
    if not st then return err end
    local r = Process.abort(st.rec)
    if not r.ok then return fail(r.reason) end
    return commit(player, args, st, r.proc, { aborted = true, kept = r.kept, discarded = r.discarded, spoiled = r.spoiled })
end

-- Collect still output (hydrous ethanol) into a fuel container in inventory.
function H.machineCollect(player, args)
    local st, err = machineState(player, args)
    if not st then return err end
    local mid = Machines.machineFor(st.item)
    if mid == "fermenter_barrel" then return fail("use_still") end
    if type(args.destination) ~= "table" then return fail("malformed_destination") end
    local can = player:getInventory():getItemWithIDRecursiv(args.destination.id or -1)
    if can == nil or can:getFluidContainer() == nil then return fail("no_destination") end
    local now, env = World.now(), World.env()
    local dst = C.read(can, "item", true)
    if dst == nil then return fail("destination_not_fuel") end
    dst = Aging.advance(dst, now, env)
    local collected = Process.collect(st.rec, Supply.free(dst))
    if not collected.ok then return fail(collected.reason) end
    -- Distillate is fresh (distillation leaves ageing products in the
    -- stillage); dried ethanol keeps the degradation it went in with.
    local deg = (collected.props and collected.props.deg) or {}
    if st.rec.carryDeg then deg = Tables.deepCopy(st.rec.carryDeg) end
    if collected.proc.state == "Ready" then collected.proc.carryDeg = nil end
    local parcel = Supply.new({ storage = dst.storage, cap = 1e9, q = collected.parcel, t = now, deg = deg })
    local merged = Mixing.previewBlend({ { supply = dst, amount = Supply.total(dst) },
        { supply = parcel, amount = Supply.total(parcel) } }, dst.storage, dst.cap)
    merged.id, merged.rev, merged.cap, merged.sealed, merged.cond = dst.id, (dst.rev or 0) + 1, dst.cap, dst.sealed,
        dst.cond
    Supply.addProvenance(merged, { k = "made", from = st.rec.id, t = now, n = Supply.total(parcel) })
    local ok, why = Native.writeComposition(can:getFluidContainer(), merged.q)
    if not ok then return fail("commit_failed", { detail = why }) end
    C.writeSidecar(can, "item", merged)
    return commit(player, args, st, collected.proc, { collected = collected.parcel,
        discarded = collected.byproducts })
end

H.commands["machine.status"] = H.machineStatus
H.commands["machine.loadFerment"] = H.machineLoadFerment
H.commands["machine.loadWash"] = H.machineLoadWash
H.commands["machine.loadDry"] = H.machineLoadDry
H.commands["machine.addFuel"] = H.machineAddFuel
H.commands["machine.pause"] = H.machinePause
H.commands["machine.resume"] = H.machineResume
H.commands["machine.abort"] = H.machineAbort
H.commands["machine.collect"] = H.machineCollect

return H
