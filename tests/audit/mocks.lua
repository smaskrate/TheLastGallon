-- Mocks of the game objects the authority layer touches, for the security
-- audit tests (tests/audit). They stand in for the engine: a result here
-- shows what the mod's own code does with a request, never what the engine
-- or the protocol does (see docs/security-audit-2026-11-05.md).
require "support/fixtures"

AUD = AUD or {}
local M = AUD

-- A native FluidContainer: fluids by type string, capacity, owner.
local FC = {}
FC.__index = FC
function M.fluidContainer(owner, capacity, fluids)
    local fc = setmetatable({ owner = owner, capacity = capacity, fluids = {} }, FC)
    for name, amount in pairs(fluids or {}) do fc.fluids[name] = amount end
    return fc
end
function FC:getOwner() return self.owner end
function FC:getCapacity() return self.capacity end
function FC:getAmount()
    local s = 0
    for _, a in pairs(self.fluids) do s = s + a end
    return s
end
function FC:getFreeCapacity() return self.capacity - self:getAmount() end
function FC:isEmpty() return self:getAmount() <= 0 end
function FC:isPureFluid(f)
    local n = 0
    for name, a in pairs(self.fluids) do if a > 0 then n = n + 1; if name ~= f.name then return false end end end
    return n == 1
end
function FC:createFluidSample()
    local list = {}
    for name, a in pairs(self.fluids) do if a > 0 then list[#list + 1] = { name = name } end end
    table.sort(list, function(a, b) return a.name < b.name end)
    local sample = { list = list }
    function sample:size() return #self.list end
    function sample:getFluid(i)
        local f = self.list[i + 1]
        return { getFluidTypeString = function() return f.name end, name = f.name }
    end
    function sample:release() end
    return sample
end
function FC:getSpecificFluidAmount(f) return self.fluids[f.name] or 0 end
function FC:adjustSpecificFluidAmount(f, amount)
    if amount <= 0 then self.fluids[f.name] = nil else self.fluids[f.name] = amount end
end
function FC:addFluid(f, amount) self.fluids[f.name] = (self.fluids[f.name] or 0) + amount end
function FC:adjustAmount(total)
    local have = self:getAmount()
    if have <= 0 then return end
    for name, a in pairs(self.fluids) do self.fluids[name] = a * total / have end
end
function FC:Empty() self.fluids = {} end

-- Fluid.Get(name) -> a fluid handle whose type string is the name.
Fluid = Fluid or {}
Fluid.Get = function(name) return { name = name, getFluidTypeString = function() return name end } end
Fluid.Petrol = Fluid.Get("Petrol")
Fluid.Water = Fluid.Get("Water")

-- Java-ish instanceof over a `class` field (and its ancestors list).
function instanceof(o, cls)
    if type(o) ~= "table" then return false end
    if o.class == cls then return true end
    for _, c in ipairs(o.classes or {}) do if c == cls then return true end end
    return false
end

-- Squares: a world of squares by "x,y,z", each with an object list.
local world = { squares = {}, vehicles = {} }
M.world = world
local Square = {}
Square.__index = Square
function M.square(x, y, z)
    local key = x .. "," .. y .. "," .. (z or 0)
    local sq = world.squares[key]
    if sq == nil then
        sq = setmetatable({ x = x, y = y, z = z or 0, objects = {}, worldObjects = {} }, Square)
        world.squares[key] = sq
    end
    return sq
end
function Square:getX() return self.x end
function Square:getY() return self.y end
function Square:getZ() return self.z end
function Square:DistToProper(other)
    local dx, dy = self.x - other:getX(), self.y - other:getY()
    return math.sqrt(dx * dx + dy * dy)
end
local function list(t)
    return { size = function() return #t end, get = function(_, i) return t[i + 1] end }
end
function Square:getObjects() return list(self.objects) end
function Square:getWorldObjects() return list(self.worldObjects) end
function Square:transmitRemoveItemFromSquare(wi) self.transmittedRemovals = (self.transmittedRemovals or 0) + 1 end
function Square:removeWorldObject(wi)
    for i, x in ipairs(self.worldObjects) do if x == wi then table.remove(self.worldObjects, i); return end end
end
function Square:getGenerator()
    for _, o in ipairs(self.objects) do if o.class == "IsoGenerator" then return o end end
    return nil
end
function Square:isInARoom() return false end
function Square:add(o)
    self.objects[#self.objects + 1] = o
    o.square = self
    o.index = #self.objects - 1
    return o
end

getCell = function()
    return { getGridSquare = function(_, x, y, z) return world.squares[x .. "," .. y .. "," .. (z or 0)] end,
        getVehicles = function() return { toArray = function() return world.vehicles end } end }
end
getVehicleById = function(id)
    for _, v in ipairs(world.vehicles) do if v.id == id then return v end end
    return nil
end

-- A world object with mod data; `class` picks what instanceof says.
local Obj = {}
Obj.__index = Obj
function M.object(class, fields)
    local o = setmetatable({ class = class, md = {}, transmitted = 0 }, Obj)
    for k, v in pairs(fields or {}) do o[k] = v end
    return o
end
function Obj:getModData() return self.md end
function Obj:hasModData() return not TLG.Tables.isEmpty(self.md) end
function Obj:transmitModData() self.transmitted = self.transmitted + 1 end
function Obj:getSquare() return self.square end
function Obj:getObjectIndex() return self.index or -1 end
function Obj:getFluidContainer() return self.fc end
function Obj:getPipedFuelAmount() return self.piped or 0 end
function Obj:setPipedFuelAmount(n) self.piped = n end
-- Generators.
function Obj:getFuel() return self.fuel or 0 end
function Obj:setFuel(f) self.fuel = f end
function Obj:getMaxFuel() return self.maxFuel or 10 end
function Obj:sync() self.synced = (self.synced or 0) + 1 end
function Obj:getCondition() return self.condition or 100 end
function Obj:setCondition(c) self.condition = c end
function Obj:isActivated() return self.activated == true end
function Obj:getGeneratorItemType() return self.itemType or "Base.Generator" end
function Obj:getName() return self.name end

-- An inventory item with a fluid container, inside a player's inventory.
local Item = {}
Item.__index = Item
local nextItemId = 1000
function M.item(fullType, capacity, fluids)
    local it = setmetatable({ fullType = fullType, id = nextItemId, md = {}, synced = 0 }, Item)
    nextItemId = nextItemId + 1
    if capacity then it.fc = M.fluidContainer(it, capacity, fluids) end
    return it
end
function Item:getID() return self.id end
function Item:getFullType() return self.fullType end
function Item:getModData() return self.md end
function Item:getFluidContainer() return self.fc end
function Item:getFluidContainerFromSelfOrWorldItem() return self.fc end
function Item:syncItemFields() self.synced = self.synced + 1 end
function Item:getContainer() return self.container end
function Item:getOutermostContainer() return self.container end
function Item:getWorldItem() return self.worldItem end
function Item:setWorldItem(wi) self.worldItem = wi end
function Item:getStaticModel() return nil end
-- Drainables (a propane tank: 5000 uses, BC/RT launch 342).
function Item:getUseDelta() return self.useDelta or 0.0002 end
function Item:getCurrentUsesFloat() return self.usedDelta or 1 end
function Item:setUsedDelta(f) self.usedDelta = f end

-- A propane tank item with `uses` left.
function M.tank(uses)
    local it = M.item("Base.PropaneTank")
    it.usedDelta = uses * it:getUseDelta()
    return it
end
instanceItem = function(fullType)
    if fullType == "Base.PropaneTank" then return M.tank(0) end
    return M.item(fullType)
end
sendAddItemToContainer = function() end

-- An item lying on a square, as an IsoWorldInventoryObject holds it.
function M.onFloor(sq, item)
    local wi = { class = "IsoWorldInventoryObject", item = item, square = sq }
    function wi:getItem() return self.item end
    function wi:getSquare() return self.square end
    item.worldItem = wi
    sq.worldObjects[#sq.worldObjects + 1] = wi
    return wi
end

-- A container (a player's inventory).
local Inv = {}
Inv.__index = Inv
function M.inventory(owner)
    return setmetatable({ items = {}, owner = owner }, Inv)
end
function Inv:AddItem(x)
    local it = type(x) == "string" and M.item(x) or x
    it.container = self
    self.items[#self.items + 1] = it
    return it
end
function Inv:Remove(it)
    for i, x in ipairs(self.items) do if x == it then table.remove(self.items, i); it.container = nil; return end end
end
function Inv:getItemWithIDRecursiv(id)
    for _, x in ipairs(self.items) do if x.id == id then return x end end
    return nil
end
function Inv:getItemWithID(id) return self:getItemWithIDRecursiv(id) end
function Inv:getFirstTypeRecurse(t)
    for _, x in ipairs(self.items) do if x.fullType == t then return x end end
    return nil
end
function Inv:getAllTypeRecurse(t)
    local out = {}
    for _, x in ipairs(self.items) do if x.fullType == t then out[#out + 1] = x end end
    return list(out)
end
function Inv:getCountTypeRecurse(t)
    local n = 0
    for _, x in ipairs(self.items) do if x.fullType == t then n = n + 1 end end
    return n
end
function Inv:getAllEvalRecurse(pred)
    local out = {}
    for _, x in ipairs(self.items) do if pred(x) then out[#out + 1] = x end end
    return list(out)
end
function Inv:getSourceGrid() return nil end
function Inv:contains(it) for _, x in ipairs(self.items) do if x == it then return true end end return false end

-- A player at a square, with an inventory and a name.
local Player = {}
Player.__index = Player
function M.player(name, square)
    local p = setmetatable({ name = name, square = square, num = 0 }, Player)
    p.inv = M.inventory(p)
    return p
end
function Player:getUsername() return self.name end
function Player:getPlayerNum() return self.num end
function Player:getSquare() return self.square end
function Player:getInventory() return self.inv end
function Player:getModData() self.md = self.md or {}; return self.md end
function Player:getPerkLevel() return 0 end
function Player:DistTo(x, y)
    local dx, dy = self.square.x - x, self.square.y - y
    return math.sqrt(dx * dx + dy * dy)
end
function Player:getKnownRecipes() return { size = function() return 0 end } end
function Player:getVehicle() return nil end

-- A vehicle with a gas tank part and an engine part.
local Part = {}
Part.__index = Part
local Vehicle = {}
Vehicle.__index = Vehicle
function M.vehicle(id, x, y, capacity, litres, script)
    local v = setmetatable({ id = id, x = x, y = y, script = script or "Base.CarNormal", parts = {} }, Vehicle)
    v.parts.GasTank = setmetatable({ vehicle = v, amount = litres or 0, capacity = capacity or 40, md = {},
        area = "GasTank" }, Part)
    v.parts.Engine = setmetatable({ vehicle = v, md = {}, condition = 100 }, Part)
    world.vehicles[#world.vehicles + 1] = v
    return v
end
function Vehicle:getId() return self.id end
function Vehicle:getSqlId() return self.id end
function Vehicle:getScriptName() return self.script end
function Vehicle:getX() return self.x end
function Vehicle:getY() return self.y end
function Vehicle:getPartById(id) return self.parts[id] end
function Vehicle:transmitPartModData(part) self.transmitted = (self.transmitted or 0) + 1 end
function Vehicle:isEngineRunning() return false end
-- A player is at the filler cap when standing within 1.5 tiles of the car.
function Vehicle:isInArea(area, player)
    return player:DistTo(self.x, self.y) <= 1.5
end
function Part:getContainerContentAmount() return self.amount end
function Part:setContainerContentAmount(a) self.amount = a end
function Part:getContainerCapacity() return self.capacity end
function Part:getModData() return self.md end
function Part:getVehicle() return self.vehicle end
function Part:getArea() return self.area end

-- Game globals the adapters read on the authority.
M.now = 100
getGameTime = function()
    return { getWorldAgeHours = function() return M.now end, getHoursSurvived = function() return M.now end,
        getMonth = function() return 6 end, getDay = function() return 8 end, getTimeOfDay = function() return 9 end }
end
getClimateManager = function()
    return { getTemperature = function() return 20 end, getHumidity = function() return 0.6 end }
end
getWorld = function() return { getWorld = function() return "audit" end, isHydroPowerOn = function() return false end } end
getTimestamp = function() return 1 end
getTimestampMs = function() return 1 end
isServer = function() return M.server == true end
isClient = function() return false end
SandboxVars = SandboxVars or { TheLastGallon = {} }
Perks = Perks or { Mechanics = "Mechanics", Cooking = "Cooking", Electricity = "Electricity",
    MetalWelding = "MetalWelding", Woodwork = "Woodwork" }
Events = Events or {}
local function ev() return { Add = function() end, Remove = function() end } end
for _, e in ipairs({ "OnInitGlobalModData", "OnGameStart", "OnReceiveGlobalModData", "OnServerStarted", "EveryHours",
    "EveryTenMinutes", "EveryOneMinute", "OnClientCommand", "OnServerCommand", "OnPreDistributionMerge",
    "OnFillInventoryObjectContextMenu", "OnFillWorldObjectContextMenu" }) do
    Events[e] = Events[e] or ev()
end
local globalMd = {}
ModData = ModData or {
    getOrCreate = function(key) globalMd[key] = globalMd[key] or {}; return globalMd[key] end,
    transmit = function() end, request = function() end, add = function(key, t) globalMd[key] = t end,
}
getCore = function() return { getVersion = function() return TLG.TESTED_GAME_VERSION end } end
sendRemoveItemFromContainer = function() end

-- The world record, created as the authority creates it.
function M.ensureWorld()
    require "TLG/Integration/World"
    TLG.World.ensure(true)
    return TLG.World.get()
end

return M
