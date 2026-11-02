require "support/fixtures"
require "TLG/Integration/Containers"
-- Generators registers its installer through Boot, which hooks the game's
-- Events as it loads: a stand-in for this require only (see Boot.lua).
local savedEvents = Events
Events = setmetatable({}, { __index = function() return { Add = function() end } end })
require "TLG/Integration/Generators"
Events = savedEvents
local G = TLG.Integration.Generators

-- Stand-ins for the game calls a generator put down makes: global ModData,
-- the clock, the cell's squares and the object classes, and the vanilla
-- class the adapter wraps. Installed for one case and removed again.
local GLOBALS = { "ModData", "getGameTime", "getCell", "isServer", "isClient", "instanceof", "ISUnequipAction" }

local function fakeGame()
    local saved = {}
    for _, k in ipairs(GLOBALS) do saved[k] = _G[k] end
    local g = { squares = {}, store = {} }
    ModData = { getOrCreate = function(k)
        g.store[k] = g.store[k] or {}
        return g.store[k]
    end }
    local clock = {}
    function clock:getWorldAgeHours() return 10 end
    getGameTime = function() return clock end
    local cell = {}
    function cell:getGridSquare(x, y, z) return g.squares[x .. "," .. y .. "," .. z] end
    getCell = function() return cell end
    instanceof = function(o, class) return type(o) == "table" and o.class == class end
    isServer = function() return false end
    isClient = function() return false end
    function g.restore()
        for _, k in ipairs(GLOBALS) do _G[k] = saved[k] end
    end
    return g
end

local function list(t)
    return { size = function() return #t end, get = function(_, i) return t[i + 1] end }
end

local function square(g, x, y)
    local s = { objs = {} }
    function s:getX() return x end
    function s:getY() return y end
    function s:getZ() return 0 end
    function s:getObjects() return list(self.objs) end
    g.squares[x .. "," .. y .. ",0"] = s
    return s
end

-- What IsoGridSquare.AddWorldInventoryItem makes of a generator item (BC
-- setInfoFromItem): an IsoGenerator with the item's fuel and type, and none
-- of the mod's record.
local function generatorOn(sq, fuel, fullType)
    local o = { class = "IsoGenerator", md = { fuel = fuel, generatorFullType = fullType }, fuel = fuel }
    function o:getModData() return self.md end
    function o:getFuel() return self.fuel end
    function o:transmitModData() end
    sq.objs[#sq.objs + 1] = o
    return o
end

T.case("integration: a generator the menus' unequip puts down keeps its record and conversion", function()
    local g = fakeGame()
    local ok, err = pcall(function()
        local here, east = square(g, 5, 5), square(g, 6, 5)
        local inventory = {}
        local character = {
            getCurrentSquare = function() return here end,
            getInventory = function() return { contains = function(_, it) return inventory[it] == true end } end,
        }
        -- ISUnequipAction.complete drops a heavy hand item at the feet unless
        -- it is unequipped to be dropped or placed (SRC ISUnequipAction.lua:134).
        ISUnequipAction = { complete = function(self)
            if self.reason ~= "drop" and self.reason ~= "place" then
                inventory[self.item] = nil
                generatorOn(self.character:getCurrentSquare(), self.item:getModData().fuel, self.item:getFullType())
            end
            return true
        end }
        G.install()
        local item, md = {}, { fuel = 6, tlg = { kind = "generator", id = "G9", q = { gasoline = 6 }, tlgConv = { state = "Commissioned" } } }
        function item:getFullType() return "Base.Generator" end
        function item:getModData() return md end
        function item:getID() return 9 end
        inventory[item] = true
        -- A generator without a record and with the same fuel lies a tile away.
        local other = generatorOn(east, 6, "Base.Generator")
        -- Unequipped to be dropped, the item stays in the inventory (the floor
        -- transfer that follows has its own hook): nothing is attached.
        setmetatable({ item = item, character = character, reason = "drop" }, { __index = ISUnequipAction }):complete()
        T.ok(other.md.tlg == nil, "nothing attached while the generator is still carried")
        -- Unequipped for anything else: put down at the feet, record and
        -- conversion on the object it became.
        setmetatable({ item = item, character = character }, { __index = ISUnequipAction }):complete()
        local dropped = here.objs[1]
        T.ok(dropped ~= nil and dropped.md.tlg ~= nil and dropped.md.tlg.id == "G9", "the record on the new object")
        T.eq(dropped.md.tlgConv and dropped.md.tlgConv.state, "Commissioned", "the conversion on the new object")
        T.ok(other.md.tlg == nil, "the other generator untouched")
    end)
    g.restore()
    if not ok then error(err, 0) end
end)
