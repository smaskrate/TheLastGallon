-- The mod's items in the loot lists: the field manual, the biodiesel
-- handbook and the diesel
-- generator. The world fires OnPreDistributionMerge, then parses the lists
-- (BC IsoWorld.init: ItemPickerJava.Parse), so both are added on that
-- event.
require "TLG/Core"
require "TLG/Integration/Manual"
require "TLG/Integration/Generators"

Events.OnPreDistributionMerge.Add(function()
    local lists = ProceduralDistributions and ProceduralDistributions.list
    local ok, res = pcall(TLG.Integration.Manual.addToLoot, lists)
    if ok then
        TLG.Log.info("field manual added to %d loot lists: %s", #res, table.concat(res, ", "))
    else
        TLG.Log.error("field manual loot: %s", tostring(res))
    end
    local hok, hres = pcall(TLG.Integration.Manual.addToLoot, lists, TLG.Integration.Manual.HANDBOOK)
    if hok then
        TLG.Log.info("biodiesel handbook added to %d loot lists: %s", #hres, table.concat(hres, ", "))
    else
        TLG.Log.error("biodiesel handbook loot: %s", tostring(hres))
    end
    -- The diesel generator (D-036): beside vanilla's, in the crate lists
    -- and in the vehicles' (VehicleDistributions).
    local G = TLG.Integration.Generators
    for _, t in ipairs({ { "loot", lists }, { "vehicle", VehicleDistributions } }) do
        local done, names = pcall(G.addToLoot, t[2])
        if done then
            TLG.Log.info("diesel generator added to %d %s lists: %s", #names, t[1], table.concat(names, ", "))
        else
            TLG.Log.error("diesel generator %s lists: %s", t[1], tostring(names))
        end
    end
end)
