-- The fuel systems field manual (TLG.ManualFuelSystems). It is read the way
-- the game reads its newspapers and fliers: an item whose mod data holds
-- `printMedia` is offered "Inspect", and reading it shows that page in the
-- game's print media window and records it read (SRC ISReadABook.lua
-- perform and complete; ISInventoryPaneContextMenu.doPrintMediaMenu). The
-- page explains start-up, fuel compatibility and troubleshooting of the
-- ethanol loop; the manual teaches no recipe and gates nothing (spec: other
-- ways to learn must stay open). It is found in the loot lists below.
TLG = TLG or {}
TLG.Integration = TLG.Integration or {}
TLG.Integration.Manual = TLG.Integration.Manual or {}
local Manual = TLG.Integration.Manual

Manual.ITEM = "TLG.ManualFuelSystems"
-- The print media id the game records as read (IsoGameCharacter
-- addReadPrintMedia); vanilla ids are flier and newspaper names.
Manual.MEDIA_ID = "TLG_ManualFuelSystems"
Manual.TITLE = "IGUI_TLG_Manual_Title"
Manual.PAGE = "IGUI_TLG_Manual_Page"
Manual.TEXT = "IGUI_TLG_Manual_Text"

-- Vanilla procedural lists (42.21 ProceduralDistributions.lua) that hold
-- the game's own mechanics, farming or generator magazines, each with that
-- magazine's weight there: gas station storage, garages and mechanics,
-- farms and homesteads, generator crates, blue-collar bookstores, tool
-- stores and libraries. The generator crate holds the generator magazine
-- at 6; the manual is a third as likely there.
Manual.LOOT = {
    GasStorageMechanics = 1,
    CrateMechanics = 1,
    MechanicShelfBooks = 2,
    StoreShelfMechanics = 1,
    FarmerTools = 2,
    CrateFarming = 2,
    Homesteading = 2,
    CrateGenerator = 2,
    BookstoreBlueCollar = 2,
    ToolStoreBooks = 2,
    LibraryMagazines = 1,
}

-- The item script's OnCreate (TLG_items.txt), run for every new manual,
-- loot included (BC InventoryItem.initialiseItem): the fields the game sets
-- on its own print media (BC RecipeCodeHelper.setPrintMediaInfo).
function Manual.onCreate(item)
    local md = item:getModData()
    md.printMedia = { id = Manual.MEDIA_ID, title = Manual.TITLE, info = Manual.PAGE, text = Manual.TEXT }
    md.literatureTitle = Manual.TITLE
end

-- The biodiesel handbook (TLG_items.txt): a recipe magazine of the game's
-- kind, which teaches the five biodiesel machines' recipes. It goes into
-- the same lists as the manual, at the same weights.
Manual.HANDBOOK = "TLG.BiodieselHandbook"
Manual.HANDBOOK_RECIPES = { "TLG_MakeWoodRetort", "TLG_MakeAshBarrel", "TLG_MakeLyeLeacher",
    "TLG_MakeBiodieselReactor", "TLG_MakeBiodieselWashTank" }
-- The wood gas handbook (D-040): the gasifier's recipe, in the same lists
-- at the same weights.
Manual.WOODGAS_HANDBOOK = "TLG.WoodGasHandbook"
Manual.WOODGAS_RECIPES = { "TLG_MakeGasifier" }

-- Adds `itemType` (the manual when nil) to `lists`
-- (ProceduralDistributions.list) before the game parses them. A list this
-- build lacks is skipped and one that has the item already is left as it
-- is. Returns the names it was added to.
function Manual.addToLoot(lists, itemType)
    itemType = itemType or Manual.ITEM
    local added = {}
    for name, weight in pairs(Manual.LOOT) do
        local list = type(lists) == "table" and lists[name] or nil
        local items = type(list) == "table" and list.items or nil
        if type(items) == "table" then
            local present = false
            for i = 1, #items, 2 do
                if items[i] == itemType then present = true end
            end
            if not present then
                items[#items + 1] = itemType
                items[#items + 1] = weight
                added[#added + 1] = name
            end
        end
    end
    table.sort(added)
    return added
end

return Manual
