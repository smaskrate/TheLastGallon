-- What a load would take from the inventory, as a line for the entry's
-- tooltip (TLG/UI/Tip.lua). The items are chosen by the functions the
-- authority takes them with (TLG/Integration/Picks.lua), on this client's
-- copy of the inventory; when nothing would be taken the line is the
-- refusal the click would get. NOT RUN in game.
require "TLG/Integration/Picks"
require "TLG/UI/Format"
require "TLG/UI/Tip"

TLG.UI = TLG.UI or {}
TLG.UI.LoadPreview = TLG.UI.LoadPreview or {}
local P = TLG.UI.LoadPreview
local Picks = TLG.Integration.Picks

local function num(x) return string.format("%.2f", tonumber(x) or 0) end

-- "3 Log, 12 Potato": items counted by display name, in the names' order.
function P.names(items)
    local counts = {}
    for _, item in ipairs(items) do
        local name = tostring(item:getDisplayName())
        counts[name] = (counts[name] or 0) + 1
    end
    local parts = {}
    for _, name in ipairs(TLG.Tables.sortedKeys(counts)) do
        parts[#parts + 1] = tostring(counts[name]) .. " " .. name
    end
    return table.concat(parts, ", ")
end

local function willTake(parts)
    return getText("IGUI_TLG_Tip_WillTake", table.concat(parts, ", "))
end

-- A refusal's text with what was found, as the dialog would give it.
local function short(reasonKey, foundKey, amount)
    return getText(reasonKey) .. " " .. getText(foundKey, num(amount))
end

-- Why a machine with the record `rec` takes no batch now, in the order
-- Process.plan refuses: a spoiled batch in it, another batch, worn out.
-- Nil when it would take one, or has no record yet.
function P.refusal(rec)
    if type(rec) ~= "table" or rec.state == nil then return nil end
    if rec.state == "Faulted" and rec.pause == "batch_spoiled" then return getText("IGUI_TLG_MachineFail_batch_spoiled") end
    if rec.state ~= "Ready" then return getText("IGUI_TLG_MachineFail_machine_busy") end
    if (tonumber(rec.cond) or 1) <= 0 then return getText("IGUI_TLG_MachineFail_needs_repair") end
    return nil
end

-- Load mash and start fermenting.
function P.mash(player, rec)
    local refused = P.refusal(rec)
    if refused then return refused end
    local inputs = TLG.Registry.need("recipe", "ethanol_ferment").inputs
    local mash = Picks.mash(player)
    if mash.yeast == nil then return getText("IGUI_TLG_MachineFail_needs_yeast") end
    if mash.sugar < (inputs.sugar_eq.min or 0) - 1e-9 then
        return short("IGUI_TLG_MachineFail_not_enough_sugar_eq", "IGUI_TLG_Found_sugar", mash.sugar)
    end
    if mash.water < (inputs.water.min or 0) - 1e-9 then
        return short("IGUI_TLG_MachineFail_not_enough_water", "IGUI_TLG_Found_water", mash.water)
    end
    return willTake({ P.names(mash.sugarItems) .. " " .. getText("IGUI_TLG_Tip_SugarEq", num(mash.sugar)),
        getText("IGUI_TLG_Tip_Water", num(mash.water)), P.names({ mash.yeast }) })
end

-- Wood for a firebox with `room` kg free; planks only with `planks`.
function P.firebox(player, room, planks)
    if room <= 1e-9 then return getText("IGUI_TLG_MachineFail_firebox_full") end
    local kg, items = Picks.feedstock(player, "wood", room, room, not planks and Picks.PLANKS or nil)
    if kg <= 0 then return getText("IGUI_TLG_MachineFail_needs_wood") end
    return willTake({ P.names(items) .. " " .. getText("IGUI_TLG_Tip_Kg", num(kg)) })
end

-- Wood for a batch of `recipeId` (the wood retort, the ash barrel).
function P.woodLoad(player, recipeId, rec)
    local refused = P.refusal(rec)
    if refused then return refused end
    local bounds = TLG.Registry.need("recipe", recipeId).inputs.firewood
    local kg, items = Picks.feedstock(player, "wood", bounds.max, bounds.max)
    if kg < (bounds.min or 0) - 1e-9 then
        return short("IGUI_TLG_MachineFail_not_enough_firewood", "IGUI_TLG_Found_wood", kg)
    end
    return willTake({ P.names(items) .. " " .. getText("IGUI_TLG_Tip_Kg", num(kg)) })
end

-- Wood and charcoal for a gasifier's hopper with `room` kg free.
function P.hopper(player, room)
    local _, kg, items = Picks.hopper(player, room)
    if kg <= 0 then return getText("IGUI_TLG_GasifierFail_needs_wood") end
    return willTake({ P.names(items) .. " " .. getText("IGUI_TLG_Tip_Kg", num(kg)) })
end

-- Sets the preview `fn(...)` gives as the tooltip of `option`. A preview
-- that fails leaves the entry as it is: the click still works.
function P.attach(option, world, fn, ...)
    local ok, text = pcall(fn, ...)
    if ok and type(text) == "string" then
        TLG.UI.Tip.set(option, text, world)
    elseif not ok then
        TLG.Log.error("load preview: %s", tostring(text))
    end
end

return P
