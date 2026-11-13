-- Records the authority writes into the mod data of an item no character
-- carries, sent to the clients on a server: an item lying on the floor, or
-- in the container of an object on a square (a crate, a bin, a cupboard).
-- The game sends an item's mod data only to the client whose inventory
-- holds it: syncItemFields sends a floor item's stats and nothing for an
-- item in an object's container, and transmitModData on a floor item's
-- world object sends that object's own mod data (engine-capabilities,
-- RT-MP; launches 362, 365). The client menus decide entries from their own
-- copy: a machine's Pause, Resume and Abort batch (`tlgProc`, D-023), a
-- can's Seal or Unseal (`tlg`). A client joining, loading the item's chunk
-- again or opening the container for the first time gets the item with its
-- record as the server holds it then.
require "TLG/Core"

TLG.Integration = TLG.Integration or {}
TLG.Integration.WorldItemRecords = TLG.Integration.WorldItemRecords or {}
local WR = TLG.Integration.WorldItemRecords

-- The mod data keys sent and taken, each with the fields left out: a
-- machine's hourly readings and fire notes (up to 480 entries each; no
-- menu reads them).
WR.KEYS = { tlg = {}, tlgProc = { temps = true, fires = true } }

-- The square a client finds the item on: the one it lies on, or the one of
-- the object whose container holds it, where Resolver.nearbyItem finds it
-- too. nil for an item a character carries (the game sends the holder its
-- item's fields), in a vehicle, or nowhere.
function WR.squareOf(item)
    local wi = item:getWorldItem()
    if wi then return wi:getSquare() end
    local outer = item:getOutermostContainer()
    local parent = outer and outer:getParent()
    if parent == nil or instanceof(parent, "IsoGameCharacter") or instanceof(parent, "BaseVehicle") then
        return nil
    end
    return parent:getSquare()
end

-- On a server: `rec`, just written under `key` into `item`, goes to the
-- clients when no character carries the item. Returns whether it was sent.
function WR.send(item, key, rec)
    if not (isServer and isServer()) or sendServerCommand == nil or WR.KEYS[key] == nil or type(rec) ~= "table" then
        return false
    end
    local sq = WR.squareOf(item)
    if sq == nil then return false end
    local drop, view = WR.KEYS[key], {}
    for k, v in pairs(rec) do
        if not drop[k] then view[k] = v end
    end
    sendServerCommand("TLG", "item", { id = item:getID(), x = sq:getX(), y = sq:getY(), z = sq:getZ(), key = key,
        rec = view })
    return true
end

-- This client's copy of item `id` on `sq`: on the floor, or in a container
-- of an object there.
local function itemOn(sq, id)
    local wobjs = sq:getWorldObjects()
    for i = 0, wobjs:size() - 1 do
        local it = wobjs:get(i):getItem()
        if it and it:getID() == id then return it end
    end
    local objs = sq:getObjects()
    for i = 0, objs:size() - 1 do
        local o = objs:get(i)
        for j = 0, o:getContainerCount() - 1 do
            local it = o:getContainerByIndex(j):getItemWithIDRecursiv(id)
            if it then return it end
        end
    end
    return nil
end

-- On a client: a record the server sent, put in this client's copy of the
-- item. Returns whether the item was found: this client may not have it,
-- on a square it has not loaded or in a container whose items it was not
-- sent.
function WR.received(args)
    if type(args) ~= "table" or type(args.rec) ~= "table" or WR.KEYS[args.key] == nil or type(args.id) ~= "number"
        or getCell() == nil then
        return false
    end
    local sq = getCell():getGridSquare(args.x, args.y, args.z)
    local it = sq and itemOn(sq, args.id)
    if it == nil then return false end
    it:getModData()[args.key] = args.rec
    return true
end

return WR
