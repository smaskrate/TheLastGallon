require "support/fixtures"
require "TLG/Integration/ConversionDevices"
local CD = TLG.Integration.ConversionDevices

-- Stand-in for the IsoPlayer calls CD.actor makes (inventory counts, known
-- recipes); perks are read under pcall and stay empty here.
local function fakePlayer(counts, recipes)
    local inv, list, known = {}, {}, recipes or {}
    function inv:getCountTypeRecurse(id) return counts[id] or 0 end
    function list:size() return #known end
    function list:get(i) return known[i + 1] end
    local p = {}
    function p:getInventory() return inv end
    function p:getKnownRecipes() return list end
    function p:getUsername() return "tester" end
    return p
end

T.case("integration: conversion.begin's actor counts the requested conversion's tools", function()
    local p = fakePlayer({ ["Base.Screwdriver"] = 1, ["Base.Wrench"] = 2, ["Base.RubberHose"] = 3 }, { "Generator" })
    local a = CD.actor(p, nil, "flex_generator")
    T.eq(a.inventory["Base.Screwdriver"], 1)
    T.eq(a.inventory["Base.Wrench"], 2)
    T.eq(a.inventory["Base.RubberHose"], 3)
    T.eq(a.inventory["Base.Pliers"], 0, "named by the definition but not carried")
    T.ok(a.recipes["Generator"], "known recipe")
    -- RT-SP run 7: built from the absent project alone, nothing was counted.
    T.ok(TLG.Tables.isEmpty(CD.actor(p, nil).inventory))
    T.ok(TLG.Tables.isEmpty(CD.actor(p, nil, "no_such_conversion").inventory))
end)

T.case("integration: a project's actor also counts its removal tools", function()
    local p = fakePlayer({ ["Base.Hammer"] = 1 })
    local project = { conversion = "flex_generator",
        snap = { requiredTools = { inspect = {} }, reversalAndSalvageRules = { tools = { "Base.Hammer" } } } }
    T.eq(CD.actor(p, project).inventory["Base.Hammer"], 1)
end)
