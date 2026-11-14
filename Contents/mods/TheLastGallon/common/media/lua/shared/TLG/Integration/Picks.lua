-- Which of a character's items a load takes. One selection for the
-- authority, which then removes them (TLG/Authority/MachineHandlers.lua,
-- GasifierHandlers.lua), and for the menus, which show it beside the entry
-- before the click (spec §16: a preview uses the calculation the action
-- uses). Nothing here changes an item.
--
-- An item the player marked as a favourite is never picked: it is the
-- game's own mark for "leave this alone" (its menus check isFavorite before
-- they drop or unequip). On a server the mark is read on the server's copy
-- of the item; that the game sends it there is NOT RUN.
require "TLG/Util/Tables"
require "TLG/Util/Num"
require "TLG/Content/Feedstocks"

TLG.Integration = TLG.Integration or {}
TLG.Integration.Picks = TLG.Integration.Picks or {}
local Picks = TLG.Integration.Picks
local Feed, Tables = TLG.Feedstocks, TLG.Tables

-- Planks are building material first: the firebox takes them only when
-- asked (machine.addFuel with `planks`).
Picks.PLANKS = { ["Base.Plank"] = true }

function Picks.kept(item)
    return item.isFavorite ~= nil and item:isFavorite() == true
end

-- The inventory's items that pass `pred` and are not kept, in the order of
-- their ids.
local function candidates(player, pred)
    local list = player:getInventory():getAllEvalRecurse(function(it) return not Picks.kept(it) and pred(it) end)
    local out = {}
    for i = 0, list:size() - 1 do out[#out + 1] = list:get(i) end
    return Tables.sort(out, function(a, b) return a:getID() < b:getID() end)
end

-- Whole feedstock items until `need` units of `field` are reached, never
-- more than `max`; `skip` is a set of item types left out. Returns the
-- amount and the items.
function Picks.feedstock(player, field, need, max, skip)
    local got, items = 0, {}
    for _, item in ipairs(candidates(player, function(it)
        local c = Feed.contribution(it:getFullType())
        return c ~= nil and (c[field] or 0) > 0 and not (skip and skip[it:getFullType()])
    end)) do
        if got >= need then break end
        local c = Feed.contribution(item:getFullType())[field]
        if got + c <= max + 1e-9 then
            got = got + c
            items[#items + 1] = item
        end
    end
    return got, items
end

-- Up to `litres` of clean water from the containers carried. Returns the
-- amount and what each container gives: { { item, litres } }.
function Picks.water(player, litres)
    local got, takes = 0, {}
    for _, item in ipairs(candidates(player, function(it)
        local fc = it:getFluidContainer()
        return fc ~= nil and not fc:isEmpty() and fc:isPureFluid(Fluid.Water)
    end)) do
        if got >= litres - 1e-9 then break end
        local take = math.min(item:getFluidContainer():getAmount(), litres - got)
        got = got + take
        takes[#takes + 1] = { item = item, litres = take }
    end
    return got, takes
end

-- Whole items giving `field` by what is left in them (Feed.amount: a
-- part-used bottle of oil counts for its rest) while they fit under `max`.
-- Returns the amount and the items.
function Picks.amounts(player, field, max)
    local got, items = 0, {}
    for _, item in ipairs(candidates(player, function(it) return Feed.amount(it, field) > 0 end)) do
        local c = Feed.amount(item, field)
        if got + c <= max + 1e-9 then
            got = got + c
            items[#items + 1] = item
        end
    end
    return got, items
end

-- The yeast a mash takes: bought yeast first, then a starter culture.
function Picks.yeast(player)
    for _, fullType in ipairs({ "Base.Yeast", "TLG.YeastStarter" }) do
        local found = candidates(player, function(it) return it:getFullType() == fullType end)
        if found[1] then return found[1] end
    end
    return nil
end

-- A mash for the fermentation vessel: sugar and crops up to `sugarKg` (the
-- recipe's most when nil), clean water up to `waterL` (5 L for each kg of
-- the sugar found when nil) and the yeast. Returns { sugarWanted, sugar,
-- sugarItems, waterWanted, water, waterTakes, yeast }.
function Picks.mash(player, sugarKg, waterL)
    local recipe = TLG.Registry.need("recipe", "ethanol_ferment")
    local sugarMax = recipe.inputs.sugar_eq.max
    local p = { sugarWanted = TLG.Num.clamp(tonumber(sugarKg) or sugarMax, 0, sugarMax) }
    p.sugar, p.sugarItems = Picks.feedstock(player, "sugar_eq", p.sugarWanted, sugarMax)
    p.waterWanted = TLG.Num.clamp(tonumber(waterL) or p.sugar * 5, 0, recipe.inputs.water.max)
    p.water, p.waterTakes = Picks.water(player, p.waterWanted)
    p.yeast = Picks.yeast(player)
    return p
end

-- Wood and charcoal for a gasifier's hopper, by the recipe input each
-- fills: whole items while they fit in `room` kg. Returns the load
-- { firewood, charcoal }, its kg and the items.
local HOPPER_INPUT = { wood = "firewood", charcoal = "charcoal" }

local function hopperField(item)
    local c = Feed.contribution(item:getFullType())
    if c == nil then return nil end
    if (c.wood or 0) > 0 then return "wood", c.wood end
    if (c.charcoal or 0) > 0 then return "charcoal", c.charcoal end
    return nil
end

function Picks.hopper(player, room)
    local load, got, items = {}, 0, {}
    for _, item in ipairs(candidates(player, function(it) return hopperField(it) ~= nil end)) do
        local field, kg = hopperField(item)
        if got + kg <= room + 1e-9 then
            got = got + kg
            items[#items + 1] = item
            load[HOPPER_INPUT[field]] = (load[HOPPER_INPUT[field]] or 0) + kg
        end
    end
    return load, got, items
end

-- A repair (UX review R8; the owner's choice of 2026-11-14: a simple
-- material, no skill). Each gives back REPAIR_STEP of the condition and
-- takes one piece of what the machine is made of, with the tool held and
-- kept: the wooden fermenter a plank and two nails with a hammer, every
-- other machine a metal pipe with a screwdriver. Four repairs cost about
-- what a new machine does; they keep its place. Game values.
Picks.REPAIR_STEP = 0.25
Picks.REPAIRS = {
    wood = { tools = { "Base.Hammer", "Base.BallPeenHammer", "Base.ClubHammer", "Base.HammerStone", "Base.WoodenMallet" },
        parts = { ["Base.Plank"] = 1, ["Base.Nails"] = 2 } },
    metal = { tools = { "Base.Screwdriver", "Base.Screwdriver_Old", "Base.Screwdriver_Improvised" },
        parts = { ["Base.MetalPipe"] = 1 } },
}
Picks.REPAIR_KIND = { fermenter_barrel = "wood" }

-- Whether a repair is offered and accepted at condition `cond`: only when
-- the whole step fits, so that a repair always gives back what it says and
-- no part is spent on a machine a few batches old.
function Picks.repairable(cond)
    return type(cond) == "number" and cond <= 1 - Picks.REPAIR_STEP + 1e-9
end

-- What repairing machine `machineId` asks for.
function Picks.repairSpec(machineId)
    return Picks.REPAIRS[Picks.REPAIR_KIND[machineId] or "metal"]
end

-- What a repair of `machineId` would take from the character: the tool
-- (kept; a favourite one serves, it is not used up), the parts' items
-- (favourites never), and what is missing: the first tool's type when no
-- tool is carried, and each part's type once for every piece short.
function Picks.repair(player, machineId)
    local spec = Picks.repairSpec(machineId)
    local inv, tool = player:getInventory(), nil
    for _, t in ipairs(spec.tools) do
        tool = tool or inv:getFirstTypeRecurse(t)
    end
    local items, missing = {}, {}
    if tool == nil then missing[#missing + 1] = spec.tools[1] end
    for _, fullType in ipairs(Tables.sortedKeys(spec.parts)) do
        local found = candidates(player, function(it) return it:getFullType() == fullType end)
        for i = 1, spec.parts[fullType] do
            if found[i] then items[#items + 1] = found[i] else missing[#missing + 1] = fullType end
        end
    end
    return { ok = #missing == 0, tool = tool, items = items, missing = missing }
end

return Picks
