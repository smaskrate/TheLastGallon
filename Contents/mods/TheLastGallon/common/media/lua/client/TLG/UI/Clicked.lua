-- What a right-click in the world is on.
--
-- The game hands the menus the object under the cursor, which for an item
-- lying on the ground is the floor tile, never the item (run 0.1.1 found
-- that). Until 0.3.0 the mod's menus therefore took every item on the
-- clicked tile, so a click on bare ground beside a can still offered the
-- can's menu. The game's own Grab entry has a rule for this (BC
-- ISWorldObjectContextMenuLogic.getWorldObjectsInRadius): an item on the
-- ground is under the click when its position on screen is within 48 pixels,
-- divided by the zoom, of the click. The same rule is used here, over the
-- clicked squares and the squares around them, so that the mod's entry for
-- an item shows where the game's Grab entry for it does.
TLG.UI = TLG.UI or {}
TLG.UI.Clicked = TLG.UI.Clicked or {}
local Clicked = TLG.UI.Clicked

Clicked.ITEM_RADIUS = 48

function Clicked.usesController(playerNum)
    return JoypadState ~= nil and JoypadState.players ~= nil and JoypadState.players[playerNum + 1] ~= nil
end

-- Where the click was on screen: the position the menu was asked for (SRC
-- ISContextMenu.get keeps it; ISWorldObjectContextMenu.createMenu passes the
-- click's). nil with a controller, which has no cursor, and for a menu
-- built without a position.
function Clicked.position(playerNum, context)
    if Clicked.usesController(playerNum) then return nil end
    local x, y = context and context.requestX, context and context.requestY
    if type(x) ~= "number" or type(y) ~= "number" then return nil end
    return x, y
end

-- The squares of the clicked objects, each once, in the order clicked.
function Clicked.squares(worldobjects)
    local out, seen = {}, {}
    for _, object in ipairs(worldobjects) do
        local square = object.getSquare and object:getSquare() or nil
        if square and not seen[square] then
            seen[square] = true
            out[#out + 1] = square
        end
    end
    return out
end

-- The items on the ground the click is on (IsoWorldInventoryObject): those
-- handed over as clicked objects, and those near the click on the clicked
-- squares and the squares around them. Without a click position (a
-- controller), every item on the clicked squares, as before.
function Clicked.worldItems(playerNum, context, worldobjects)
    local out, seen = {}, {}
    local function add(object)
        if object ~= nil and not seen[object] then
            seen[object] = true
            out[#out + 1] = object
        end
    end
    for _, object in ipairs(worldobjects) do
        if instanceof(object, "IsoWorldInventoryObject") then add(object) end
    end
    local squares = Clicked.squares(worldobjects)
    local x, y = Clicked.position(playerNum, context)
    if x == nil then
        for _, square in ipairs(squares) do
            local items = square:getWorldObjects()
            for i = 0, items:size() - 1 do add(items:get(i)) end
        end
        return out
    end
    local radius = Clicked.ITEM_RADIUS / getCore():getZoom(playerNum)
    local visited = {}
    local function visit(square)
        if square == nil or visited[square] then return end
        visited[square] = true
        local items = square:getWorldObjects()
        for i = 0, items:size() - 1 do
            local item = items:get(i)
            local dx, dy = item:getScreenPosX(playerNum) - x, item:getScreenPosY(playerNum) - y
            if dx * dx + dy * dy <= radius * radius then add(item) end
        end
    end
    for _, square in ipairs(squares) do
        visit(square)
        for dx = -1, 1 do
            for dy = -1, 1 do
                if dx ~= 0 or dy ~= 0 then
                    visit(getCell():getGridSquare(square:getX() + dx, square:getY() + dy, square:getZ()))
                end
            end
        end
    end
    return out
end

-- The vehicle the click is on: one handed over as a clicked object, else the
-- one under the cursor, as the game's own vehicle menu finds it (SRC
-- ISVehicleMenu.OnFillWorldObjectContextMenu). With a controller there is no
-- cursor: `fallback()` then says which.
function Clicked.vehicle(playerNum, worldobjects, fallback)
    for _, object in ipairs(worldobjects) do
        if instanceof(object, "BaseVehicle") then return object end
    end
    if Clicked.usesController(playerNum) then return fallback and fallback() or nil end
    local ok, vehicle = pcall(function()
        return IsoObjectPicker.Instance:PickVehicle(getMouseXScaled(), getMouseYScaled())
    end)
    return ok and vehicle or nil
end

-- The generator the click is on: among the clicked objects or standing on
-- one of their squares, as the game's own generator entries find it (they
-- look at everything on the clicked square, BC
-- ISWorldObjectContextMenuLogic.fetch).
function Clicked.generator(playerNum, worldobjects, fallback)
    for _, object in ipairs(worldobjects) do
        if instanceof(object, "IsoGenerator") then return object end
    end
    for _, square in ipairs(Clicked.squares(worldobjects)) do
        local objects = square:getObjects()
        for i = 0, objects:size() - 1 do
            if instanceof(objects:get(i), "IsoGenerator") then return objects:get(i) end
        end
    end
    if Clicked.usesController(playerNum) then return fallback and fallback() or nil end
    return nil
end

return Clicked