require "support/fixtures"
local savedEvents = Events
Events = setmetatable({}, { __index = function() return { Add = function() end } end })
require "TLG/Authority/Resolver"
Events = savedEvents

T.case("integration: fuel references find placed containers and reject stale or distant targets", function()
    local savedCell = getCell
    local Res = TLG.Authority.Resolver
    local function list(items)
        return { size = function() return #items end, get = function(_, i) return items[i + 1] end }
    end
    local distance, height, carried, stored = 1, 0, false, false
    local fluid = {}
    local item, world, square
    local inventory = { getItemWithIDRecursiv = function(_, id)
        if carried and id == 17 then return item end
    end }
    local cupboard = { getItemWithIDRecursiv = function(_, id)
        if stored and id == 17 then return item end
    end, getSourceGrid = function() return square end }
    local furniture = { getContainerCount = function() return 1 end,
        getContainerByIndex = function() return cupboard end }
    square = { getX = function() return 4 end, getY = function() return 5 end, getZ = function() return 0 end,
        getWorldObjects = function() return list((carried or stored) and {} or { world }) end,
        getObjects = function() return list({ furniture }) end }
    world = { getItem = function() return item end, getSquare = function() return square end }
    item = { getID = function() return 17 end, getFluidContainer = function() return nil end,
        getFluidContainerFromSelfOrWorldItem = function() return fluid end,
        getWorldItem = function() if not carried and not stored then return world end end,
        getOutermostContainer = function()
            if carried then return inventory end
            if stored then return cupboard end
        end }
    local player = { getInventory = function() return inventory end, getSquare = function() return {
        DistToProper = function() return distance end, getZ = function() return height end,
    } end }
    getCell = function() return { getGridSquare = function(_, x, y, z)
        if x == 4 and y == 5 and z == 0 then return square end
    end } end
    local ok, err = pcall(function()
        local ref = Res.refForItem(item)
        T.eq(ref.kind, "item")
        T.eq(ref.x, 4)
        local ep = Res.resolve(ref, { player = player })
        T.eq(ep.owner, item, "world fluids keep the inventory item's sidecar")
        T.ok(ep:canAccess(player))
        distance = 20
        T.eq(Res.resolve(ref, { player = player }), nil, "out of reach")
        distance, height = 1, 1
        T.eq(Res.resolve(ref, { player = player }), nil, "another floor")
        height = 0
        ref.id = 99
        T.eq(Res.resolve(ref, { player = player }), nil, "replaced item")
        ref.id, ref.x = 17, 4.5
        T.eq(Res.resolve(ref, { player = player }), nil, "malformed coordinates")
        ref.x, carried = 4, true
        T.eq(Res.resolve(ref, { player = player }).owner, item, "picked up since menu opened")
        carried, stored = false, true
        local storedRef = Res.refForItem(item)
        T.eq(storedRef.x, 4)
        local storedEndpoint = Res.resolve(storedRef, { player = player })
        T.eq(storedEndpoint.owner, item, "inside nearby furniture")
        T.ok(storedEndpoint:canAccess(player))
    end)
    getCell = savedCell
    if not ok then error(err, 0) end
end)
