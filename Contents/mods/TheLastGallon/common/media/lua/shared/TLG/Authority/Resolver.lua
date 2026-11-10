-- Single owner of "reference -> adapter endpoint" resolution on the authority.
-- References are plain tables sent by clients; nothing in them is trusted
-- beyond identifying an object the server then validates:
--   { kind = "item", id = <InventoryItem:getID()>, x =, y =, z = }
--       Coordinates are optional for the actor's inventory, required for
--       nearby ground items or items inside furniture.
--   { kind = "vehicle", id = <BaseVehicle:getId()> }
--   { kind = "object", x =, y =, z =, index = }               (fluid object)
--   { kind = "pump", x =, y =, z =, index = }
--   { kind = "generator", x =, y =, z =, index = }
require "TLG/Integration/Containers"
require "TLG/Integration/Vehicles"
require "TLG/Integration/Generators"
require "TLG/Integration/Stations"

TLG.Authority = TLG.Authority or {}
TLG.Authority.Resolver = TLG.Authority.Resolver or {}
local Res = TLG.Authority.Resolver
local C, V, G, S = TLG.Integration.Containers, TLG.Integration.Vehicles, TLG.Integration.Generators,
    TLG.Integration.Stations

local function int(v) return type(v) == "number" and v == math.floor(v) end

local function objectAt(ref)
    if not (int(ref.x) and int(ref.y) and int(ref.z) and int(ref.index)) then return nil, "malformed_ref" end
    local sq = getCell() and getCell():getGridSquare(ref.x, ref.y, ref.z)
    if sq == nil then return nil, "not_loaded" end
    local objs = sq:getObjects()
    if ref.index < 0 or ref.index >= objs:size() then return nil, "no_object" end
    return objs:get(ref.index)
end

-- Generic adapter endpoint with a proximity check for world objects.
local function nearby(player, square, range)
    return player and square and player:getSquare() and player:getSquare():DistToProper(square) <= (range or 2.5)
end

local function nearbyItem(player, ref)
    if not (int(ref.x) and int(ref.y) and int(ref.z)) then return nil end
    local square = getCell() and getCell():getGridSquare(ref.x, ref.y, ref.z)
    if not nearby(player, square) or player:getSquare():getZ() ~= square:getZ() then return nil end
    local worldItems = square:getWorldObjects()
    for i = 0, worldItems:size() - 1 do
        local item = worldItems:get(i):getItem()
        if item and item:getID() == ref.id then return item end
    end
    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        local object = objects:get(i)
        for j = 0, object:getContainerCount() - 1 do
            local item = object:getContainerByIndex(j):getItemWithIDRecursiv(ref.id)
            if item then return item end
        end
    end
end

function Res.resolve(ref, ctx)
    if type(ref) ~= "table" then return nil, "malformed_ref" end
    local player = ctx.player
    if ref.kind == "item" then
        if not int(ref.id) or player == nil then return nil, "malformed_ref" end
        local item = player:getInventory():getItemWithIDRecursiv(ref.id)
        if item == nil then item = nearbyItem(player, ref) end
        if item == nil or C.fluidOf(item, "item") == nil then return nil, "no_item" end
        return C.endpoint(item, "item")
    elseif ref.kind == "vehicle" then
        if not int(ref.id) then return nil, "malformed_ref" end
        local v = getVehicleById(ref.id)
        if v == nil or V.tank(v) == nil then return nil, "no_vehicle" end
        return V.endpoint(v)
    elseif ref.kind == "object" then
        local obj, why = objectAt(ref)
        if obj == nil then return nil, why end
        if obj:getFluidContainer() == nil then return nil, "no_fluid_container" end
        return C.endpoint(obj, "object")
    elseif ref.kind == "pump" then
        local obj, why = objectAt(ref)
        if obj == nil then return nil, why end
        if not S.isPump(obj) then return nil, "not_a_pump" end
        local ep = { key = S.keyOf(obj) }
        function ep:canAccess(p)
            if nearby(p, obj:getSquare(), 3.5) then return true end
            return false, "out_of_reach"
        end
        function ep:read()
            local rec, status = S.read(obj, true)
            self.readStatus = status
            return rec
        end
        function ep:write(rec) S.write(obj, rec); return true end
        function ep:record(rec) S.writeSidecar(obj, rec); return true end
        return ep
    elseif ref.kind == "generator" then
        local obj, why = objectAt(ref)
        if obj == nil then return nil, why end
        if not instanceof(obj, "IsoGenerator") then return nil, "not_a_generator" end
        local ep = { key = G.keyOf(obj), consumer = G.profile(obj) }
        function ep:canAccess(p)
            if nearby(p, obj:getSquare(), 2.5) then return true end
            return false, "out_of_reach"
        end
        function ep:read()
            -- What burned since the record was written wears it first (D-031).
            pcall(G.chargeWear, obj)
            local rec, status = G.read(obj, true)
            self.readStatus = status
            return rec
        end
        function ep:write(rec)
            obj:setFuel(TLG.Domain.Supply.total(rec))
            G.writeSidecar(obj, rec)
            obj:sync()
            return true
        end
        function ep:record(rec) G.writeSidecar(obj, rec); return true end
        return ep
    end
    return nil, "unknown_kind"
end

-- Coordinates locate a dropped item or an item inside nearby furniture.
-- The authority still checks identity and reach, and keeps its item sidecar.
function Res.refForItem(item)
    local ref = { kind = "item", id = item:getID() }
    local world = item:getWorldItem()
    local outer = item:getOutermostContainer()
    local square = (world and world:getSquare()) or (outer and outer:getSourceGrid())
    if square then ref.x, ref.y, ref.z = square:getX(), square:getY(), square:getZ() end
    return ref
end

-- Builds a reference for an object the client is looking at.
function Res.refForObject(obj, kind)
    local sq = obj:getSquare()
    return { kind = kind, x = sq:getX(), y = sq:getY(), z = sq:getZ(), index = obj:getObjectIndex() }
end

return Res
