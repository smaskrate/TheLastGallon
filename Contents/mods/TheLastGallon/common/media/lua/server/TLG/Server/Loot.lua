-- The field manual's place in the loot lists. The world fires
-- OnPreDistributionMerge, then parses the lists (BC IsoWorld.init:
-- ItemPickerJava.Parse), so the manual is added on that event.
require "TLG/Core"
require "TLG/Integration/Manual"

Events.OnPreDistributionMerge.Add(function()
    local lists = ProceduralDistributions and ProceduralDistributions.list
    local ok, res = pcall(TLG.Integration.Manual.addToLoot, lists)
    if ok then
        TLG.Log.info("field manual added to %d loot lists: %s", #res, table.concat(res, ", "))
    else
        TLG.Log.error("field manual loot: %s", tostring(res))
    end
end)
