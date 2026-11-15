-- Inventory context menu for fuel containers. Every action is a request to
-- the authority (TLG.Net); the menu never changes fuel state itself.
require "TLG/Client/Net"
require "TLG/UI/Format"
require "TLG/Integration/Native"
require "TLG/Actions/ISTLGPourFuel"
require "TLG/UI/Clicked"
require "TLG/UI/Tip"
require "TLG/UI/Say"

TLG.UI = TLG.UI or {}
TLG.UI.FuelMenu = TLG.UI.FuelMenu or {}
local Menu = TLG.UI.FuelMenu
local Fmt, Native, Tip = TLG.UI.Format, TLG.Integration.Native, TLG.UI.Tip
local Containers, Resolver = TLG.Integration.Containers, TLG.Authority.Resolver

local Say = TLG.UI.Say

local function show(text) Say.window(text, 420, 260) end

-- A test's result: what it found; for a tank, the engine it feeds and,
-- from a kit, what the sample means for that engine.
function Menu.sampleText(reply)
    local parts = { getText("IGUI_TLG_InspectionTitle") }
    if reply.engine then parts[#parts + 1] = Fmt.engine(reply.engine) end
    parts[#parts + 1] = Fmt.observation(reply.observation)
    if reply.verdict then parts[#parts + 1] = Fmt.verdict(reply.verdict) end
    return table.concat(parts, " <LINE> <LINE> ")
end

-- What is read opens a window (What I know about it, a test's result);
-- what a treatment did, and a refusal, go over the character (TLG/UI/Say).
local function onReply(reply)
    if not reply.ok then
        Say.refusal(Fmt.failure(reply))
        return
    end
    if reply.command == "known" then
        show(Fmt.known(reply))
    elseif reply.observation then
        show(Menu.sampleText(reply))
    elseif reply.command == "status" and reply.evaluation then
        show(Fmt.evaluation(reply.evaluation))
    elseif reply.command == "treat" then
        Say.line(getText("IGUI_TLG_TreatDone_" .. tostring(reply.op)), true)
    end
end

local function itemRef(item) return Resolver.refForItem(item) end

local function request(command, args) TLG.Net.request(command, args, onReply) end

local function firstItem(entry)
    if instanceof(entry, "InventoryItem") then return entry end
    return entry.items and entry.items[1]
end

local function isFuelCan(item, kind)
    local fc = item and Containers.fluidOf(item, kind or "item")
    if fc == nil then return false end
    if kind ~= "object" and TLG.ContainerProfiles.items[item:getFullType()] then return true end
    local comp = Native.readComposition(fc)
    for id, amount in pairs(comp) do
        if amount > 0 and TLG.Registry.need("fuel", id).role == "fuel" then return true end
    end
    return false
end

local function addContainer(playerNum, context, item, kind, title, world)
    Say.from(playerNum)
    local player = getSpecificPlayer(playerNum)
    if item == nil or player == nil then return end
    local fc = Containers.fluidOf(item, kind)
    local root = context:addOption(title or getText("ContextMenu_TLG_Fuel"), nil, nil)
    local sub = ISContextMenu:getNew(context)
    context:addSubMenu(root, sub)
    local ref = kind == "item" and itemRef(item) or Resolver.refForObject(item, "object")
    local side = item:getModData().tlg
    -- Asked of the authority, which keeps the knowledge (in multiplayer the
    -- client's own copy of the player never had it).
    sub:addOption(getText("ContextMenu_TLG_ShowKnown"), nil, function() request("known", { target = ref }) end)
    sub:addOption(getText("ContextMenu_TLG_Look"), nil, function() request("sample", { target = ref, method = "visual" }) end)
    local kit = sub:addOption(getText("ContextMenu_TLG_SampleKit"), nil,
        function() request("sample", { target = ref, method = "kit" }) end)
    if not player:getInventory():getFirstTypeRecurse("TLG.FuelSampleKit") then
        Tip.grey(kit, getText("IGUI_TLG_Fail_NeedsKit"), world)
    end
    local stab = sub:addOption(getText("ContextMenu_TLG_Stabilize"), nil,
        function() request("treat", { target = ref, op = "stabilize" }) end)
    if not player:getInventory():getFirstTypeRecurse("TLG.FuelStabilizer") then
        Tip.grey(stab, getText("IGUI_TLG_Fail_NeedsStabilizer"), world)
    end
    local filt = sub:addOption(getText("ContextMenu_TLG_Filter"), nil,
        function() request("treat", { target = ref, op = "filter" }) end)
    if not player:getInventory():getFirstTypeRecurse("TLG.FuelFilter") then
        Tip.grey(filt, getText("IGUI_TLG_Fail_NeedsFilter"), world)
    end
    sub:addOption(getText("ContextMenu_TLG_DrainWater"), nil, function() request("treat", { target = ref, op = "separate" }) end)
    if side == nil or side.sealed ~= false then
        sub:addOption(getText("ContextMenu_TLG_Unseal"), nil, function() request("treat", { target = ref, op = "unseal" }) end)
    else
        sub:addOption(getText("ContextMenu_TLG_Seal"), nil, function() request("treat", { target = ref, op = "seal" }) end)
    end
    if fc:isEmpty() then
        sub:addOption(getText("ContextMenu_TLG_Clean"), nil, function() request("treat", { target = ref, op = "clean" }) end)
    elseif kind == "item" then
        Menu.addPourOptions(player, sub, item)
    end
    if kind == "item" then Menu.addDrainOptions(player, sub, item) end
end

function Menu.fill(playerNum, context, items)
    for _, entry in ipairs(items) do
        local item = firstItem(entry)
        if isFuelCan(item) then
            addContainer(playerNum, context, item, "item", nil, false)
            return
        end
    end
end

-- "This pump gives diesel.", from the pump's status (its main fuel), over
-- the character.
function Menu.askPump(pump)
    TLG.Net.request("status", { target = Resolver.refForObject(pump, "pump") }, function(reply)
        if not reply.ok then
            Say.refusal(Fmt.failure(reply))
        elseif reply.primary == nil or (reply.total or 0) <= 0 then
            Say.line(getText("IGUI_TLG_PumpEmpty"), false)
        else
            Say.line(getText("IGUI_TLG_PumpGives", Fmt.componentName(reply.primary)), true)
        end
    end)
end

-- The Fuel entry for what the click is on: a fixed object that holds fuel,
-- or a can on the ground under the click (TLG/UI/Clicked.lua; until 0.3.0
-- any can on the clicked tile, so that a click on the ground beside one
-- still offered it); and, under its own name, the tank of the vehicle or
-- the generator clicked (Menu.tankAt).
function Menu.fillWorld(playerNum, context, worldobjects, test)
    if getSpecificPlayer(playerNum) == nil then return end
    local found, seen, squares = {}, {}, {}
    local function collect(object)
        local owner, kind = object, "object"
        if instanceof(object, "IsoWorldInventoryObject") then owner, kind = object:getItem(), "item" end
        if owner and not seen[owner] and isFuelCan(owner, kind) then
            seen[owner] = true
            found[#found + 1] = { owner = owner, kind = kind }
        end
    end
    for _, object in ipairs(worldobjects) do
        if not instanceof(object, "IsoWorldInventoryObject") then collect(object) end
    end
    for _, object in ipairs(TLG.UI.Clicked.worldItems(playerNum, context, worldobjects)) do collect(object) end
    for _, square in ipairs(TLG.UI.Clicked.squares(worldobjects)) do squares[square] = true end
    -- A station pump: what it gives (D-036: some give diesel). Asked of the
    -- authority, which makes the pump's record at its first contact.
    local pump
    for _, object in ipairs(worldobjects) do
        if pump == nil and TLG.Integration.Stations.isPump(object) then pump = object end
    end
    if pump == nil then
        for square in pairs(squares) do
            local objects = square:getObjects()
            for i = 0, objects:size() - 1 do
                if pump == nil and TLG.Integration.Stations.isPump(objects:get(i)) then pump = objects:get(i) end
            end
        end
    end
    local tank = Menu.tankAt(playerNum, worldobjects)
    if #found == 0 and pump == nil and tank == nil then return end
    if test then return ISWorldObjectContextMenu.setTest() end
    Say.from(playerNum)
    if pump then
        context:addOption(getText("ContextMenu_TLG_PumpProduct"), nil, function() Menu.askPump(pump) end)
    end
    for _, entry in ipairs(found) do
        local title = getText("ContextMenu_TLG_Fuel")
        if #found > 1 then
            local name = entry.kind == "item" and entry.owner:getDisplayName()
                or Containers.fluidOf(entry.owner, entry.kind):getUiName()
            title = title .. " - " .. name
        end
        addContainer(playerNum, context, entry.owner, entry.kind, title, true)
    end
    if tank then Menu.addTank(playerNum, context, tank) end
end

-- Pouring into engines goes through the authoritative transfer so that any
-- fuel (not only Petrol) and its condition reach the tank, and incompatible
-- blends need an explicit experimental confirmation.
local function queuePour(player, item, destination, face, experimental, source)
    local world = item:getWorldItem()
    if world then
        ISWorldObjectContextMenu.onGrabWItem({}, world, player:getPlayerNum())
    else
        ISInventoryPaneContextMenu.transferIfNeeded(player, item)
    end
    if luautils and luautils.equipItems then luautils.equipItems(player, item, nil) end
    ISTimedActionQueue.add(ISTLGPourFuel:new(player, item, destination, face, experimental, function(reply)
        if reply.ok then return end
        if reply.reason == "incompatible" and not experimental then
            local text = getText("IGUI_TLG_Fail_Incompatible") .. " <LINE> <LINE> " .. Fmt.evaluation(reply.evaluation)
            local w, h = 440, 260
            local dlg = ISModalDialog:new(getCore():getScreenWidth() / 2 - w / 2, getCore():getScreenHeight() / 2 - h / 2,
                w, h, text, true, nil, function(_, button)
                    if button.internal == "YES" then queuePour(player, item, destination, face, true, source) end
                end)
            dlg:initialise()
            dlg:addToUIManager()
        else
            Say.refusal(Fmt.failure(reply))
        end
    end, nil, source))
end

local function nearbyVehicleTank(player)
    -- getVehicles() is a java.util.HashSet on 42.21 (see Integration/Vehicles.lua).
    for _, v in ipairs(getCell():getVehicles():toArray()) do
        local tank = v:getPartById("GasTank")
        if tank and v:isInArea(tank:getArea(), player) then return v end
    end
    return nil
end

local function nearbyGenerator(player)
    local sq = player:getSquare()
    if sq == nil then return nil end
    for dx = -2, 2 do
        for dy = -2, 2 do
            local s = getCell():getGridSquare(sq:getX() + dx, sq:getY() + dy, sq:getZ())
            if s then
                local objs = s:getObjects()
                for i = 0, objs:size() - 1 do
                    if instanceof(objs:get(i), "IsoGenerator") then return objs:get(i) end
                end
            end
        end
    end
    return nil
end

local function nearbyPump(player)
    local sq = player:getSquare()
    if sq == nil then return nil end
    for dx = -2, 2 do
        for dy = -2, 2 do
            local s = getCell():getGridSquare(sq:getX() + dx, sq:getY() + dy, sq:getZ())
            if s then
                local objs = s:getObjects()
                for i = 0, objs:size() - 1 do
                    if TLG.Integration.Stations.isPump(objs:get(i)) then return objs:get(i) end
                end
            end
        end
    end
    return nil
end

-- Vanilla has no way to empty a generator; conversions require a drained
-- fuel system, so TLG offers an authoritative drain into a can.
-- A generator whose fuel is gas takes and gives no liquid (D-040).
local function holdsGas(g)
    local ok, gas = pcall(TLG.Integration.Generators.holdsGas, g)
    return ok and gas
end

-- A generator that has no liquid to inspect: its fuel is gas, or it is a
-- gas generator with an empty tank. One converted to gas that still holds
-- petrol from before the conversion keeps its Fuel entry.
local function gasOnly(g)
    if holdsGas(g) then return true end
    local ok, gas = pcall(TLG.Integration.Generators.isGas, g)
    return ok and gas == true and g:getFuel() <= 1e-6
end

-- The tank the click is on, when the character is where the authority lets
-- it be sampled from (Authority/Resolver): a vehicle's from its fuel cap, a
-- generator's within 2.5 tiles, and not one whose fuel is gas (D-040: Gas
-- is its entry). Seated in a vehicle, none.
function Menu.tankAt(playerNum, worldobjects)
    local player = getSpecificPlayer(playerNum)
    if player == nil or player:getVehicle() ~= nil then return nil end
    local v = TLG.UI.Clicked.vehicle(playerNum, worldobjects, function() return nearbyVehicleTank(player) end)
    local tank = v and v:getPartById("GasTank") or nil
    if tank and v:isInArea(tank:getArea(), player) then
        return { kind = "vehicle", owner = v, ref = { kind = "vehicle", id = v:getId() } }
    end
    local g = TLG.UI.Clicked.generator(playerNum, worldobjects, function() return nearbyGenerator(player) end)
    local here, there = player:getSquare(), g and g:getSquare() or nil
    if here and there and here:DistToProper(there) <= 2.5 and not gasOnly(g) then
        return { kind = "generator", owner = g, ref = Resolver.refForObject(g, "generator") }
    end
    return nil
end

-- The engine's profile where this process is the authority. A client's copy
-- of the world record is not known to tell a diesel chassis from a petrol
-- one (Vehicles.baseProfile), so there the line is left out and the
-- authority's replies name the engine (Format.known, onReply).
function Menu.engineOf(tank)
    if not TLG.World.isAuthority() then return nil end
    local ok, profile = pcall(function()
        if tank.kind == "vehicle" then return TLG.Integration.Vehicles.profile(tank.owner) end
        return TLG.Integration.Generators.profile(tank.owner)
    end)
    return ok and profile or nil
end

-- The Fuel entry of a vehicle's or a generator's tank: the engine's type,
-- then what a can's entry has to learn about the fuel. The tank is read
-- through the same tests as a can and tells no more; a kit sample comes
-- back with what it means for this engine. RT-SP launch 419 on an ambulance and a
-- Diesel Generator; a real right-click on a vehicle NOT RUN (offline:
-- tests/integration/test_tank_menu.lua).
function Menu.addTank(playerNum, context, tank)
    Say.from(playerNum)
    local player = getSpecificPlayer(playerNum)
    local root = context:addOption(getText(tank.kind == "vehicle" and "ContextMenu_TLG_FuelVehicle"
        or "ContextMenu_TLG_FuelGenerator"), nil, nil)
    local sub = ISContextMenu:getNew(context)
    context:addSubMenu(root, sub)
    local engine = Fmt.engine(Menu.engineOf(tank))
    if engine then sub:addOption(engine, nil, nil) end
    local ref = tank.ref
    sub:addOption(getText("ContextMenu_TLG_ShowKnown"), nil, function() request("known", { target = ref }) end)
    sub:addOption(getText("ContextMenu_TLG_Look"), nil, function() request("sample", { target = ref, method = "visual" }) end)
    local kit = sub:addOption(getText("ContextMenu_TLG_SampleKit"), nil,
        function() request("sample", { target = ref, method = "kit" }) end)
    if not player:getInventory():getFirstTypeRecurse("TLG.FuelSampleKit") then
        Tip.grey(kit, getText("IGUI_TLG_Fail_NeedsKit"), true)
    end
end

function Menu.addDrainOptions(player, sub, item)
    local free = Containers.fluidOf(item, "item"):getFreeCapacity()
    local g = nearbyGenerator(player)
    if g and free > 0.05 and g:getFuel() > 0 and not holdsGas(g) then
        -- A timed action, as the pours are (R13): the can in hand, the
        -- generator faced, as long a litre as a pour.
        sub:addOption(getText("ContextMenu_TLG_DrainGenerator"), nil, function()
            queuePour(player, item, nil, g, false, TLG.Authority.Resolver.refForObject(g, "generator"))
        end)
    end
end

function Menu.addPourOptions(player, sub, item)
    local pump = nearbyPump(player)
    if pump then
        -- Restored station: the reservoir becomes player-run storage.
        -- A timed action, as the pours into engines are (R13).
        sub:addOption(getText("ContextMenu_TLG_PourStation"), nil, function()
            queuePour(player, item, TLG.Authority.Resolver.refForObject(pump, "pump"), pump, false)
        end)
    end
    local v = nearbyVehicleTank(player)
    if v then
        sub:addOption(getText("ContextMenu_TLG_PourVehicle"), nil, function()
            queuePour(player, item, { kind = "vehicle", id = v:getId() }, v, false)
        end)
    end
    local g = nearbyGenerator(player)
    if g and not holdsGas(g) then
        sub:addOption(getText("ContextMenu_TLG_PourGenerator"), nil, function()
            queuePour(player, item, TLG.Authority.Resolver.refForObject(g, "generator"), g, false)
        end)
    end
end

Events.OnFillInventoryObjectContextMenu.Add(Menu.fill)
Events.OnFillWorldObjectContextMenu.Add(Menu.fillWorld)

return Menu
