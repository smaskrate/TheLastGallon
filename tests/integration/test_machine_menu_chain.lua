require "support/fixtures"
-- The machine menu's entries for the biodiesel chain (D-036). The menu is
-- loaded by tests/integration/test_machine_menu.lua, which runs first and
-- keeps the callbacks the menu registers.
require "integration/test_machine_menu"
local Menu = TLG.UI.MachineMenu

-- Builds the menu of a placed machine of `fullType` and hands `check` its
-- entries by name and the list of requests they send.
local function menuFor(fullType, check)
    local saved = { instanceof = instanceof, getSpecificPlayer = getSpecificPlayer, getText = getText,
        ISContextMenu = ISContextMenu, request = TLG.Net.request }
    local function context()
        local c = { options = {} }
        function c:addOption(name, target, fn)
            local option = { name = name, onSelect = fn }
            self.options[#self.options + 1] = option
            return option
        end
        function c:addSubMenu(option, sub) option.sub = sub end
        return c
    end
    local square = { getX = function() return 10 end, getY = function() return 20 end, getZ = function() return 0 end }
    local item = { class = "InventoryItem", getFullType = function() return fullType end,
        getID = function() return 5 end, getModData = function() return {} end }
    item.getWorldItem = function() return { getSquare = function() return square end } end
    local sent = {}
    instanceof = function(value, class) return value.class == class end
    getText = function(key) return key end
    getSpecificPlayer = function() return { getInventory = function() return {
        getAllEvalRecurse = function() return { size = function() return 0 end } end,
    } end } end
    ISContextMenu = { getNew = context }
    TLG.Net.request = function(command, args) sent[#sent + 1] = { command = command, args = args } end
    local c = context()
    local ok, err = pcall(function()
        Menu.fill(0, c, { item })
        local byName = {}
        for _, o in ipairs(c.options[1].sub.options) do byName[o.name] = o end
        check(byName, sent)
    end)
    instanceof, getSpecificPlayer, getText = saved.instanceof, saved.getSpecificPlayer, saved.getText
    ISContextMenu, TLG.Net.request = saved.ISContextMenu, saved.request
    if not ok then error(err, 0) end
end

T.case("integration: the chain's machines offer one load each, a firebox where they have one", function()
    local expect = {
        ["TLG.WoodRetort"] = { load = "retort", firebox = true },
        ["TLG.AshBarrel"] = { load = "fire_pit", firebox = false },
        ["TLG.LyeLeacher"] = { load = "leacher", firebox = true },
        ["TLG.BiodieselReactor"] = { load = "reactor", firebox = true },
        ["TLG.BiodieselWashTank"] = { load = "settler", firebox = true },
    }
    for fullType, want in pairs(expect) do
        menuFor(fullType, function(menu, sent)
        local load = menu["ContextMenu_TLG_Load_" .. want.load]
        T.ok(load ~= nil, fullType .. " has its load")
        load.onSelect()
        T.eq(sent[1].command, "machine.load")
        T.eq(sent[1].args.target.id, 5)
        T.eq(menu.ContextMenu_TLG_AddFirewood ~= nil, want.firebox, fullType .. " firebox")
        T.ok(menu.ContextMenu_TLG_MachineStatus ~= nil)
        T.eq(menu.ContextMenu_TLG_CollectEthanol, nil, fullType .. " collects no ethanol")
        local collect = menu.ContextMenu_TLG_CollectBiodiesel
        if fullType == "TLG.BiodieselWashTank" then
            T.ok(collect ~= nil and collect.notAvailable == true, "collect is greyed with no can carried")
        else
            T.eq(collect, nil, fullType .. " hands its output to the next machine")
        end
        end)
    end
end)

T.case("integration: the ethanol machines keep their own entries", function()
    menuFor("TLG.PotStill", function(menu)
        T.ok(menu.ContextMenu_TLG_LoadWash ~= nil)
        T.ok(menu.ContextMenu_TLG_CollectEthanol ~= nil)
        T.eq(menu.ContextMenu_TLG_Load_retort, nil)
        T.eq(menu.ContextMenu_TLG_CollectBiodiesel, nil)
    end)
end)
