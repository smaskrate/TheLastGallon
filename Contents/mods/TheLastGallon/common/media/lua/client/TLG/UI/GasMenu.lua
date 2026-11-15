-- World menu for a generator converted to gas (D-040): its propane tank goes
-- in and comes out, as with the game's propane barbecue, and its gas can be
-- read. Every action is a request to the authority (TLG.Net,
-- TLG/Authority/GasHandlers.lua); the menu only reads what it shows.
require "TLG/Client/Net"
require "TLG/UI/Format"
require "TLG/UI/Clicked"
require "TLG/Integration/Generators"
require "TLG/UI/Tip"
require "TLG/UI/Say"

TLG.UI = TLG.UI or {}
TLG.UI.GasMenu = TLG.UI.GasMenu or {}
local Menu = TLG.UI.GasMenu
local G, Fmt = TLG.Integration.Generators, TLG.UI.Format

local Say = TLG.UI.Say

local function show(text) Say.window(text, 420, 220) end

-- How long the gas lasts, to the hour and no finer: the game burns once an
-- hour and a generator stops at the step that empties it, so the hours left
-- are good to within one (launch 358: 0.006 L at 0.005 L an hour, stopped
-- 1.97 h later). Under an hour it says so; from two days on, days and hours.
function Menu.span(hours)
    local whole = math.floor(math.max(0, tonumber(hours) or 0))
    if whole < 1 then return getText("IGUI_TLG_GasSpanUnderHour") end
    if whole < 48 then return getText("IGUI_TLG_GasSpanAbout", getText("IGUI_TLG_Dur_Hours", tostring(whole))) end
    return getText("IGUI_TLG_GasSpanAbout", getText("IGUI_TLG_Dur_Days", tostring(math.floor(whole / 24)),
        tostring(whole - math.floor(whole / 24) * 24)))
end

-- The text of a gas.status reply.
function Menu.describe(r)
    -- How long the gas lasts at the load the generator has now (R11), in
    -- place of the buffer's litres of petrol: with no tank and a gasifier
    -- lit, the generator holds about an hour's gas and is refilled as it
    -- runs, and the line says so. A generator that never ran has no load to
    -- reckon with.
    local lines = { getText("IGUI_TLG_GasTitle") }
    local holds = r.holdsGas or (r.tankUses or 0) >= 1
    if not holds then
        lines[2] = getText("IGUI_TLG_GasEmpty")
    elseif r.hoursLeft == nil then
        lines[2] = getText("IGUI_TLG_GasLeftUnknown")
    elseif (r.gasifiers or 0) > 0 and not ((r.tankUses or 0) >= 1) then
        lines[2] = getText("IGUI_TLG_GasLeftFed", Menu.span(r.hoursLeft))
    else
        lines[2] = getText("IGUI_TLG_GasLeft", Menu.span(r.hoursLeft))
    end
    if r.tankUses then
        lines[#lines + 1] = getText("IGUI_TLG_GasTank", tostring(r.tankUses), string.format("%.2f", r.tankKg or 0))
    else
        lines[#lines + 1] = getText("IGUI_TLG_GasNoTank")
    end
    lines[#lines + 1] = getText("IGUI_TLG_GasGasifiers", tostring(r.gasifiers or 0))
    return table.concat(lines, " <LINE> ")
end

local function onReply(reply)
    if not reply.ok then
        Say.refusal(Fmt.failure(reply))
    elseif reply.command == "gas.status" then
        show(Menu.describe(reply))
    elseif reply.command == "gas.connect" then
        Say.line(getText("IGUI_TLG_GasConnected", tostring(reply.uses)), true)
    elseif reply.command == "gas.remove" then
        Say.line(getText("IGUI_TLG_GasRemoved", tostring(reply.uses)), true)
    end
end

local function tankUses(item)
    return math.floor(item:getCurrentUsesFloat() / item:getUseDelta() + 0.5)
end

-- A propane tank with gas left where the authority looks for one: the
-- inventory, or the floor within a square of the generator.
function Menu.tankNear(player, gen)
    local list = player:getInventory():getAllTypeRecurse("Base.PropaneTank")
    for i = 0, (list and list:size() or 0) - 1 do
        if tankUses(list:get(i)) >= 1 then return true end
    end
    local sq = gen:getSquare()
    for dx = -1, 1 do
        for dy = -1, 1 do
            local s = sq and getCell():getGridSquare(sq:getX() + dx, sq:getY() + dy, sq:getZ())
            local objs = s and s:getWorldObjects()
            for i = 0, (objs and objs:size() or 0) - 1 do
                local it = objs:get(i):getItem()
                if it and it:getFullType() == "Base.PropaneTank" and tankUses(it) >= 1 then return true end
            end
        end
    end
    return false
end

function Menu.fill(playerNum, context, worldobjects, test)
    if test then return end
    local player = getSpecificPlayer(playerNum)
    if player == nil or player:getVehicle() ~= nil then return end
    local gen = TLG.UI.Clicked.generator(playerNum, worldobjects, nil)
    if gen == nil then return end
    local ok, gas = pcall(G.isGas, gen)
    if not (ok and gas) then return end
    local ref = TLG.Authority.Resolver.refForObject(gen, "generator")
    Say.from(playerNum)
    local root = context:addOption(getText("ContextMenu_TLG_Gas"), nil, nil)
    local sub = ISContextMenu:getNew(context)
    context:addSubMenu(root, sub)
    local rec = gen:getModData()[G.GAS_KEY]
    if type(rec) == "table" and rec.tank then
        sub:addOption(getText("ContextMenu_TLG_GasRemoveTank"), nil, function()
            TLG.Net.request("gas.remove", { device = ref }, onReply)
        end)
    else
        local opt = sub:addOption(getText("ContextMenu_TLG_GasConnectTank"), nil, function()
            TLG.Net.request("gas.connect", { device = ref }, onReply)
        end)
        if not Menu.tankNear(player, gen) then
            TLG.UI.Tip.grey(opt, getText("IGUI_TLG_Fail_NoPropaneTank"), true)
        end
    end
    sub:addOption(getText("ContextMenu_TLG_GasStatus"), nil, function()
        TLG.Net.request("gas.status", { device = ref }, onReply)
    end)
end

Events.OnFillWorldObjectContextMenu.Add(Menu.fill)

return Menu
