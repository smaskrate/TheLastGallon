require "support/fixtures"
require "TLG/Integration/Manual"
local Manual = TLG.Integration.Manual

-- A created manual as the game hands it to the item script's OnCreate.
local function newItem()
    local item, md = {}, {}
    function item:getModData() return md end
    return item
end

T.case("integration: a new field manual carries the game's print media fields", function()
    local item = newItem()
    Manual.onCreate(item)
    local pm = item:getModData().printMedia
    T.ok(pm ~= nil, "printMedia set")
    T.eq(pm.id, "TLG_ManualFuelSystems")
    T.eq(pm.title, "IGUI_TLG_Manual_Title")
    T.eq(pm.info, "IGUI_TLG_Manual_Page")
    T.eq(pm.text, "IGUI_TLG_Manual_Text")
    T.eq(item:getModData().literatureTitle, "IGUI_TLG_Manual_Title", "read once, as the game's print media")
end)

T.case("integration: the field manual joins the loot lists this build has, once", function()
    local function list(...) return { rolls = 2, items = { ... } } end
    local lists = {
        GasStorageMechanics = list("MechanicMag1", 1),
        CrateMechanics = list("MechanicMag1", 1, "Wrench", 4),
        CrateGenerator = list("ElectronicsMag4", 6),
        LibraryMagazines = list("ElectronicsMag4", 1),
        KitchenBook = list("FarmingMag1", 0.1),
    }
    local added = Manual.addToLoot(lists)
    T.eq(table.concat(added, ","), "CrateGenerator,CrateMechanics,GasStorageMechanics,LibraryMagazines",
        "only the listed lists this build has")
    local items = lists.CrateMechanics.items
    T.eq(#items, 6); T.eq(items[5], "TLG.ManualFuelSystems"); T.eq(items[6], 1)
    T.eq(lists.CrateGenerator.items[4], 2, "a third of the generator magazine's 6")
    T.eq(#lists.KitchenBook.items, 2, "a list not chosen is left alone")
    -- Added again (the event fired twice): nothing changes.
    T.eq(#Manual.addToLoot(lists), 0)
    T.eq(#lists.CrateMechanics.items, 6)
    -- No lists at all, or a list without items, is not an error.
    T.eq(#Manual.addToLoot(nil), 0)
    T.eq(#Manual.addToLoot({ FarmerTools = { rolls = 1 } }), 0)
end)

T.case("integration: every chosen weight is a plain positive number", function()
    local n = 0
    for name, weight in pairs(Manual.LOOT) do
        n = n + 1
        T.ok(type(weight) == "number" and weight > 0 and weight <= 6, name)
    end
    T.eq(n, 11)
end)
