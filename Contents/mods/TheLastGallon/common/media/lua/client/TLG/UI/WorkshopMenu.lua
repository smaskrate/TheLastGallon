-- World context menu: workshop conversions for the generator or the vehicle
-- the click is on (TLG/UI/Clicked.lua; until 0.3.0 for any within reach of
-- the character, whatever was clicked, so the entry also showed on bare
-- ground beside a car). All steps are authority requests (TLG.Net). "Work on it" walks to
-- the device and starts ISTLGConversionWork, which reports while the
-- character stays there; time away from the device is never credited.
-- Start, Hand over parts and Work on it used RT-SP 2026-10-31 (run 12) on a
-- Base.Generator and a Base.CarNormal; Project status, Cancel and Remove
-- are NOT RUN.
require "TLG/Client/Net"
require "TLG/Authority/Resolver"
require "TLG/Integration/ConversionDevices"
require "TLG/Actions/ISTLGConversionWork"
require "TLG/UI/Clicked"
require "TLG/UI/Format"
require "TLG/UI/Tip"
require "TLG/UI/Confirm"
require "TLG/UI/Say"

TLG.UI = TLG.UI or {}
TLG.UI.WorkshopMenu = TLG.UI.WorkshopMenu or {}
local Menu = TLG.UI.WorkshopMenu
local CD = TLG.Integration.ConversionDevices

local Say = TLG.UI.Say

local function show(text) Say.window(text, 440, 260) end

-- What is missing, in the player's words: items by display name (vanilla
-- getItemNameFromFullType), skills as "Mechanics 4", recipes as named.
function Menu.missingText(m)
    m = tostring(m)
    local skill, level = string.match(m, "^(%a+):(%d+)$")
    if skill then
        local name = getText("IGUI_perks_" .. skill)
        if name == "IGUI_perks_" .. skill then name = skill end
        return name .. " " .. level
    end
    if string.find(m, ".", 1, true) then
        local ok, name = pcall(getItemNameFromFullType, m)
        if ok and name and name ~= "" then return name end
    end
    return m
end

-- "4 Screws, 1 Rubber Hose": parts by display name with their counts, from
-- a table { fullType = count }; nil when it is empty or missing.
function Menu.partsText(t)
    if type(t) ~= "table" or TLG.Tables.isEmpty(t) then return nil end
    local parts = {}
    for _, id in ipairs(TLG.Tables.sortedKeys(t)) do
        parts[#parts + 1] = tostring(t[id]) .. " " .. Menu.missingText(id)
    end
    return table.concat(parts, ", ")
end

-- A refusal's text: the workshop's own wording, else the shared one
-- (TLG/UI/Format.lua).
local function reasonText(reason)
    local key = "IGUI_TLG_ConvReason_" .. tostring(reason)
    local text = getText(key)
    if text == key then return TLG.UI.Format.failure({ reason = reason }) end
    return text
end

-- The text of a workshop reply. After the state it lists what the step
-- moved, from the reply (TLG/Authority/ConversionHandlers.lua): the parts
-- handed over and those still needed, the parts a cancel or a removal gave
-- back and lost, and the hours of work done. The hours were read in a
-- dialog in RT-SP launch 413; the lists of parts are NOT RUN in game.
function Menu.describe(reply)
    if not reply.ok then
        local lines = { reasonText(reply.reason) }
        for _, m in ipairs(reply.missing or {}) do lines[#lines + 1] = "- " .. Menu.missingText(m) end
        return table.concat(lines, " <LINE> ")
    end
    local lines = { getText("IGUI_TLG_ConvState_" .. tostring(reply.state)) }
    if reply.conversion then lines[#lines + 1] = getText("IGUI_TLG_Conversion_" .. reply.conversion) end
    if reply.stage then lines[#lines + 1] = getText("IGUI_TLG_ConvStage", getText("IGUI_TLG_ConvStage_" .. reply.stage)) end
    if type(reply.doneHours) == "number" and type(reply.totalHours) == "number" and reply.totalHours > 0 then
        lines[#lines + 1] = getText("IGUI_TLG_ConvHours", string.format("%.1f", reply.doneHours),
            string.format("%.1f", reply.totalHours))
    end
    for _, row in ipairs({ { "consumed", "IGUI_TLG_ConvConsumed" }, { "outstanding", "IGUI_TLG_ConvOutstanding" },
        { "returned", "IGUI_TLG_ConvReturned" }, { "lost", "IGUI_TLG_ConvLost" } }) do
        local parts = Menu.partsText(reply[row[1]])
        if parts then lines[#lines + 1] = getText(row[2], parts) end
    end
    if reply.blocked then
        lines[#lines + 1] = reasonText(reply.blocked.reason)
        for _, m in ipairs(reply.blocked.missing or {}) do lines[#lines + 1] = "- " .. Menu.missingText(m) end
    end
    if reply.profile then lines[#lines + 1] = getText("IGUI_TLG_ConvProfile", getText("IGUI_TLG_Profile_" .. reply.profile)) end
    return table.concat(lines, " <LINE> ")
end

-- A workshop reply: every step's answer lists parts or hours and is read
-- in a window; a refusal that names nothing missing is one sentence over
-- the character.
local function tell(r)
    if not r.ok and #(r.missing or {}) == 0 then
        Say.refusal(Menu.describe(r))
    else
        show(Menu.describe(r))
    end
end

local function req(command, args) TLG.Net.request(command, args, tell) end

local function nearbyGenerator(player)
    local sq = player:getSquare()
    for dx = -2, 2 do
        for dy = -2, 2 do
            local s = sq and getCell():getGridSquare(sq:getX() + dx, sq:getY() + dy, sq:getZ())
            if s then
                local objs = s:getObjects()
                for i = 0, objs:size() - 1 do
                    if instanceof(objs:get(i), "IsoGenerator") then return objs:get(i) end
                end
            end
        end
    end
end

local function nearbyVehicle(player)
    local best, bestD
    -- getVehicles() is a java.util.HashSet on 42.21 (see Integration/Vehicles.lua).
    for _, v in ipairs(getCell():getVehicles():toArray()) do
        local d = player:DistTo(v:getX(), v:getY())
        if d <= 4 and (bestD == nil or d < bestD) then best, bestD = v, d end
    end
    return best
end

-- Walks to the engine area (vehicle) or next to the generator, then works.
function Menu.work(player, deviceRef, device)
    local action = ISTLGConversionWork:new(player, deviceRef, device, tell)
    if deviceRef.kind == "vehicle" then
        local engine = device:getPartById("Engine")
        if engine then ISTimedActionQueue.add(ISPathFindAction:pathToVehicleArea(player, device, engine:getArea())) end
        ISTimedActionQueue.add(action)
    elseif luautils.walkAdj(player, device:getSquare()) then
        ISTimedActionQueue.add(action)
    end
end

-- The project's state on this client's copy of the device ("none" without
-- one): a generator's mod data, a vehicle's Engine part's
-- (ConversionDevices.store sends both to the clients). Read as stored, with
-- no schema check or vault: the menu only chooses its entries from it, and
-- the authority judges every request. On a server the copy of a vehicle's
-- part is NOT RUN.
function Menu.projectState(device, kind)
    local ok, md = pcall(function()
        if kind == "vehicle" then return (CD.vehicleStore(device)) end
        return device:getModData()
    end)
    local project = ok and type(md) == "table" and md[CD.KEY] or nil
    if type(project) ~= "table" or type(project.state) ~= "string" then return "none" end
    return project.state
end

-- Which entries apply in a project's state; every one for a state this
-- build does not know, as the menu offered before.
function Menu.entriesFor(state)
    -- Planned: a project made and not begun, which only Start takes further
    -- (conversion.begin makes a new one).
    if state == "none" or state == "Planned" or TLG.Domain.ConversionService.TERMINAL[state] then return { start = true } end
    if state == "InProgress" then return { work = true, deliver = true, cancel = true } end
    if state == "Commissioned" then return { remove = true } end
    return { start = true, work = true, deliver = true, cancel = true, remove = true }
end

local function itemName(fullType)
    local ok, name = pcall(getItemNameFromFullType, fullType)
    if ok and name and name ~= "" then return name end
    return fullType
end

-- What a conversion asks for, as the lines of its Start entry's tooltip:
-- skills, know-how, tools, parts, the hours of work and the empty tank.
-- With `actor` (ConversionDevices.actor) what the character lacks is
-- marked. NOT RUN in game.
function Menu.requirements(def, actor)
    local lines = {}
    local function mark(text, has)
        if actor ~= nil and not has then return getText("IGUI_TLG_ConvReq_Missing", text) end
        return text
    end
    local know = def.requiredKnowledge or {}
    local skills = {}
    for _, perk in ipairs(TLG.Tables.sortedKeys(know.skills or {})) do
        local need = know.skills[perk]
        local have = actor and actor.skills and actor.skills[perk] or 0
        local text = Menu.missingText(perk .. ":" .. tostring(need))
        if actor ~= nil and have < need then text = getText("IGUI_TLG_ConvReq_SkillLow", text, tostring(have)) end
        skills[#skills + 1] = text
    end
    if #skills > 0 then lines[#lines + 1] = getText("IGUI_TLG_ConvReq_Skills", table.concat(skills, ", ")) end
    -- Known as the authority counts it (Project.lua, recipeSet): a name as a
    -- key with a true value, or as a value.
    local recipes, known = {}, {}
    for k, v in pairs(actor and actor.recipes or {}) do
        if type(k) == "string" and v then known[k] = true end
        if type(v) == "string" then known[v] = true end
    end
    for _, name in ipairs(know.recipes or {}) do
        recipes[#recipes + 1] = mark(name, known[name] == true)
    end
    if #recipes > 0 then lines[#lines + 1] = getText("IGUI_TLG_ConvReq_Knows", table.concat(recipes, ", ")) end
    -- Tools of every stage, each once; parts of every stage, summed.
    local tools, parts = {}, {}
    for _, stage in ipairs(TLG.Tables.sortedKeys(def.requiredTools or {})) do
        for _, tool in ipairs(def.requiredTools[stage]) do tools[tool] = true end
    end
    for _, stage in ipairs(TLG.Tables.sortedKeys(def.requiredModules or {})) do
        for _, part in ipairs(TLG.Tables.sortedKeys(def.requiredModules[stage])) do
            parts[part] = (parts[part] or 0) + def.requiredModules[stage][part]
        end
    end
    local inv = actor and actor.inventory or {}
    local list = {}
    for _, tool in ipairs(TLG.Tables.sortedKeys(tools)) do
        list[#list + 1] = mark(itemName(tool), (inv[tool] or 0) >= 1)
    end
    if #list > 0 then lines[#lines + 1] = getText("IGUI_TLG_ConvReq_Tools", table.concat(list, ", ")) end
    list = {}
    for _, part in ipairs(TLG.Tables.sortedKeys(parts)) do
        list[#list + 1] = mark(tostring(parts[part]) .. " " .. itemName(part), (inv[part] or 0) >= parts[part])
    end
    if #list > 0 then lines[#lines + 1] = getText("IGUI_TLG_ConvReq_Parts", table.concat(list, ", ")) end
    local hours = 0
    for _, stage in ipairs(def.workStages or {}) do hours = hours + (stage.hours or 0) end
    lines[#lines + 1] = getText("IGUI_TLG_ConvReq_Hours", string.format("%.1f", hours))
    if def.fuelStorageChanges and def.fuelStorageChanges.drainRequired then
        lines[#lines + 1] = getText("IGUI_TLG_ConvReq_Drain")
    end
    return table.concat(lines, " <LINE> ")
end

-- The Workshop entry of a device: Project status always, then what applies
-- to the project's state (Menu.entriesFor). Cancel and Remove ask first:
-- both lose parts.
local function addDeviceMenu(context, player, playerNum, titleKey, deviceRef, device, kind, chassis)
    Say.from(playerNum)
    local root = context:addOption(getText(titleKey), nil, nil)
    local sub = ISContextMenu:getNew(context)
    context:addSubMenu(root, sub)
    sub:addOption(getText("ContextMenu_TLG_ConvStatus"), nil, function()
        TLG.Net.request("conversion.status", { device = deviceRef }, function(r)
            show(Menu.describe(r))
        end)
    end)
    local offer = Menu.entriesFor(Menu.projectState(device, kind))
    if offer.start then
        for _, row in ipairs(TLG.Domain.ConversionService.matrix()) do
            if row.deviceKind == kind and row.chassis == chassis and CD.offered(row.conversion) then
                local o = sub:addOption(getText("ContextMenu_TLG_ConvBegin", getText("IGUI_TLG_Conversion_" .. row.conversion)),
                    nil, function() req("conversion.begin", { device = deviceRef, conversion = row.conversion }) end)
                local ok, text = pcall(function()
                    local known, actor = pcall(CD.actor, player, nil, row.conversion)
                    return Menu.requirements(TLG.Registry.need("conversion", row.conversion), known and actor or nil)
                end)
                if ok then TLG.UI.Tip.set(o, text, true) else TLG.Log.error("workshop requirements: %s", tostring(text)) end
            end
        end
    end
    if offer.deliver then
        sub:addOption(getText("ContextMenu_TLG_ConvDeliver"), nil, function() req("conversion.deliver", { device = deviceRef }) end)
    end
    if offer.work then
        sub:addOption(getText("ContextMenu_TLG_ConvJoin"), nil, function() Menu.work(player, deviceRef, device) end)
    end
    if offer.cancel then
        sub:addOption(getText("ContextMenu_TLG_ConvCancel"), nil, function()
            TLG.UI.Confirm.ask(getText("IGUI_TLG_Confirm_ConvCancel"), function()
                req("conversion.cancel", { device = deviceRef })
            end, playerNum)
        end)
    end
    if offer.remove then
        sub:addOption(getText("ContextMenu_TLG_ConvRemove"), nil, function()
            TLG.UI.Confirm.ask(getText("IGUI_TLG_Confirm_ConvRemove"), function()
                req("conversion.remove", { device = deviceRef })
            end, playerNum)
        end)
    end
end

function Menu.fill(playerNum, context, worldobjects, test)
    if test then return end
    local player = getSpecificPlayer(playerNum)
    if player == nil or player:getVehicle() ~= nil then return end
    -- With a controller there is no cursor: the nearest in reach, as before.
    local gen = TLG.UI.Clicked.generator(playerNum, worldobjects, function() return nearbyGenerator(player) end)
    if gen then
        addDeviceMenu(context, player, playerNum, "ContextMenu_TLG_ConvGenerator",
            TLG.Authority.Resolver.refForObject(gen, "generator"), gen, "generator", gen:getGeneratorItemType())
    end
    local v = TLG.UI.Clicked.vehicle(playerNum, worldobjects, function() return nearbyVehicle(player) end)
    if v then
        addDeviceMenu(context, player, playerNum, "ContextMenu_TLG_ConvVehicle", { kind = "vehicle", id = v:getId() }, v,
            "vehicle", v:getScriptName())
    end
end

Events.OnFillWorldObjectContextMenu.Add(Menu.fill)

return Menu
