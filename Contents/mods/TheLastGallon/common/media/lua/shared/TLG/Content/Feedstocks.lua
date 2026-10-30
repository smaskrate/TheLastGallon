-- Vanilla items accepted as production feedstock, with the canonical quantity
-- each contributes. Item ids were checked against the 42.21 item scripts
-- (media/scripts/generated/items); the item adapter re-checks them at load
-- and disables missing entries with a logged warning.
--   sugar_eq  kg of fermentable sugar equivalent per item (starch counted after cooking)
--   oil       litres of oil per item (biodiesel)
--   manure    kg of digestible manure per item (biogas)
--   wood      kg of dry wood per item (gasifier / firebox)
--   lime      kg of quicklime per item (drying)
TLG.Feedstocks = TLG.Feedstocks or {}
local Feed = TLG.Feedstocks

Feed.items = {
    ["Base.Sugar"] = { sugar_eq = 1.0 },
    ["Base.SugarBrown"] = { sugar_eq = 0.9 },
    ["Base.SugarBeet"] = { sugar_eq = 0.16, cook = false },
    ["Base.Corn"] = { sugar_eq = 0.12, cook = true },
    ["Base.Potato"] = { sugar_eq = 0.09, cook = true },
    ["Base.Pumpkin"] = { sugar_eq = 0.15, cook = true },
    ["Base.Apple"] = { sugar_eq = 0.02 },
    ["Base.Grapes"] = { sugar_eq = 0.03 },
    ["Base.Watermelon"] = { sugar_eq = 0.25 },
    ["Base.OilVegetable"] = { oil = 0.9 },
    ["Base.OilOlive"] = { oil = 0.9 },
    ["Base.Lard"] = { oil = 0.4 },
    ["Base.SunflowerSeeds"] = { oilseed = 0.25 },
    ["Base.SunflowerHeadDried"] = { oilseed = 0.4 },
    ["Base.Soybeans"] = { oilseed = 0.2 },
    ["Base.Dung_Cow"] = { manure = 2.0 },
    ["Base.Dung_Pig"] = { manure = 1.5 },
    ["Base.Dung_Sheep"] = { manure = 0.8 },
    ["Base.Dung_Chicken"] = { manure = 0.3 },
    ["Base.Dung_Turkey"] = { manure = 0.4 },
    ["Base.Firewood"] = { wood = 2.0 },
    ["Base.Log"] = { wood = 9.0 },
    ["Base.Plank"] = { wood = 1.5 },
    ["Base.Twigs"] = { wood = 0.3 },
    ["Base.Charcoal"] = { charcoal = 1.0 },
    ["Base.Quicklime"] = { lime = 1.0 },
    ["Base.Yeast"] = { yeast = 1 },
}

function Feed.contribution(fullType)
    return Feed.items[fullType]
end

return Feed
