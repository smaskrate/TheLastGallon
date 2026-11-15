require "support/fixtures"
-- What the menus' dialogs say an action took and gave, why a load was
-- refused and why an entry is greyed (client UI). The menus are loaded by
-- tests/integration/test_clicked.lua (Workshop) and test_machine_menu.lua
-- (machines), which keep the stand-ins their loading needs.
require "integration/test_clicked"
require "integration/test_machine_menu"
require "TLG/UI/Format"
require "TLG/UI/Tip"
local Machine, Workshop, Fmt, Tip = TLG.UI.MachineMenu, TLG.UI.WorkshopMenu, TLG.UI.Format, TLG.UI.Tip

-- getText as the game's Translator, every key known: "[key:arg,arg]".
local function bracket(key, ...)
    local args = { ... }
    return "[" .. key .. (#args > 0 and (":" .. table.concat(args, ",")) or "") .. "]"
end

local function has(text, part) return string.find(text, part, 1, true) ~= nil end

-- Runs `fn` with getText and the Format module's translator as `tr`.
local function withText(tr, fn)
    local saved = { getText = getText, translate = Fmt.translate, name = getItemNameFromFullType }
    getText, Fmt.translate = tr, tr
    getItemNameFromFullType = function(fullType) return "<" .. fullType .. ">" end
    local ok, err = pcall(fn)
    getText, Fmt.translate, getItemNameFromFullType = saved.getText, saved.translate, saved.name
    if not ok then error(err, 0) end
end

T.case("integration: an amount carries its material's unit", function()
    withText(bracket, function()
        T.eq(Fmt.amount("ethanol", 12.346), "[IGUI_TLG_Amount_L:12.35]")
        T.eq(Fmt.amount("sugar_eq", 6), "[IGUI_TLG_Amount_kg:6.00]")
        T.eq(Fmt.amount("woodgas", 0.04), "[IGUI_TLG_Amount_m3:0.04]")
        T.eq(Fmt.amount("yeast_starter", 1), "1.00", "counted, no unit")
        T.eq(Fmt.amount("no_such_material", 2), "2.00", "unknown to the registry")
        T.eq(Fmt.amount("water", nil), "[IGUI_TLG_Amount_L:0.00]")
        T.eq(Fmt.amounts({ water = 29.67, spent_lime = 0.4 }),
            "[IGUI_TLG_Fuel_spent_lime] [IGUI_TLG_Amount_kg:0.40], [IGUI_TLG_Fuel_water] [IGUI_TLG_Amount_L:29.67]")
        T.eq(Fmt.amounts(nil), "")
    end)
end)

T.case("integration: a machine's dialog says what a load, a feed and a collect moved", function()
    withText(bracket, function()
        local function text(reply)
            reply.ok = true
            return Machine.describe(reply)
        end
        local t = text({ command = "machine.loadFerment", machine = "fermenter_barrel", state = "Processing",
            stage = "prepare", sugarKg = 6, waterL = 30 })
        T.ok(has(t, "[IGUI_TLG_Did_loadFerment:6.00,30.00]"), t)
        T.ok(has(t, "[IGUI_TLG_MachineState_Processing"), "the state follows: " .. t)
        t = text({ command = "machine.loadWash", machine = "pot_still", state = "Processing", washL = 36.5 })
        T.ok(has(t, "[IGUI_TLG_Did_loadWash:36.50]"), t)
        -- The firebox after a feed, with what it holds at most.
        local cap = TLG.Registry.need("machine", "pot_still").firebox.capacityKg
        t = text({ command = "machine.addFuel", machine = "pot_still", state = "Ready", addedKg = 9, firebox = 9 })
        T.ok(has(t, "[IGUI_TLG_Did_addFuel:9.00]"), t)
        T.ok(has(t, "[IGUI_TLG_FireboxOf:9.0," .. string.format("%.0f", cap) .. "]"), t)
        t = text({ command = "machine.loadDry", machine = "drying_column", state = "Processing", ethanolL = 8,
            waterL = 2, limeKg = 5.5 })
        T.ok(has(t, "[IGUI_TLG_Did_loadDry:8.00,2.00,5.50]"), t)
        -- Collect: what went into the can, what stays, what the emptied machine threw away.
        t = text({ command = "machine.collect", machine = "pot_still", state = "Ready", outputs = {},
            collected = { ethanol = 4, water = 1 }, discarded = { stillage = 20 } })
        T.ok(has(t, "[IGUI_TLG_Did_collect:[IGUI_TLG_Fuel_ethanol] [IGUI_TLG_Amount_L:4.00], "
            .. "[IGUI_TLG_Fuel_water] [IGUI_TLG_Amount_L:1.00]]"), t)
        T.ok(has(t, "[IGUI_TLG_Discarded:[IGUI_TLG_Fuel_stillage] [IGUI_TLG_Amount_kg:20.00]]"), t)
        -- The chain's one command, worded by the machine's kind.
        t = text({ command = "machine.load", machine = "wood_retort", state = "Processing", woodKg = 40 })
        T.ok(has(t, "[IGUI_TLG_Did_load_wood:40.00]"), t)
        t = text({ command = "machine.load", machine = "lye_leacher", state = "Processing", ashKg = 2, waterL = 4 })
        T.ok(has(t, "[IGUI_TLG_Did_load_leacher:2.00,4.00]"), t)
        t = text({ command = "machine.load", machine = "biodiesel_reactor", state = "Processing", oilL = 10,
            methanolL = 2, lyeKg = 0.05, charcoal = 3 })
        T.ok(has(t, "[IGUI_TLG_Did_load_reactor:10.00,2.00,0.05]") and has(t, "[IGUI_TLG_Did_charcoal:3]"), t)
        t = text({ command = "machine.load", machine = "biodiesel_reactor", state = "Processing", oilL = 10,
            methanolL = 2, lyeKg = 0.05, charcoal = 0 })
        T.ok(not has(t, "IGUI_TLG_Did_charcoal"), "the retort still holds methanol: " .. t)
        t = text({ command = "machine.load", machine = "biodiesel_wash_tank", state = "Processing", crudeL = 11,
            washWaterL = 3, discarded = { glycerin = 1.2 } })
        T.ok(has(t, "[IGUI_TLG_Did_load_settler:11.00,3.00]"), t)
        T.ok(has(t, "[IGUI_TLG_Discarded:[IGUI_TLG_Fuel_glycerin] [IGUI_TLG_Amount_L:1.20]]"), t)
        -- Status, Pause and a reply without its amounts say nothing about a move.
        t = text({ command = "machine.status", machine = "pot_still", state = "OutputReady", outputs = { ethanol = 12.3 } })
        T.ok(not has(t, "IGUI_TLG_Did_"), t)
        T.ok(has(t, "[IGUI_TLG_Fuel_ethanol]: [IGUI_TLG_Amount_L:12.30]"), "outputs carry their unit: " .. t)
        T.ok(not has(text({ command = "machine.pause", machine = "pot_still", state = "Paused" }), "IGUI_TLG_Did_"))
        T.ok(has(text({ command = "machine.loadWash", state = "Processing" }), "[IGUI_TLG_Did_loadWash:0.00]"))
        T.ok(not has(text({ command = "machine.load", state = "Processing" }), "IGUI_TLG_Did_"), "machine unknown")
    end)
end)

T.case("integration: every machine of the chain has its load's wording", function()
    withText(bracket, function()
        local kinds = { retort = true, fire_pit = true, leacher = true, reactor = true, settler = true }
        local seen = 0
        for _, id in ipairs(TLG.Registry.ids("machine")) do
            local def = TLG.Registry.need("machine", id)
            if kinds[def.kind] then
                seen = seen + 1
                T.ok(Machine.did({ command = "machine.load" }, def.kind) ~= nil, id)
            end
        end
        T.ok(seen >= 5, "chain machines found: " .. tostring(seen))
    end)
end)

T.case("integration: a refused load says what was found of the material it was short of", function()
    -- A translator that knows the machines' wording for two codes only.
    local known = { IGUI_TLG_MachineFail_not_enough_sugar_eq = true, IGUI_TLG_MachineFail_not_enough_plant_oil = true,
        IGUI_TLG_MachineFail_machine_busy = true }
    withText(function(key, ...)
        if string.find(key, "^IGUI_TLG_MachineFail_") and not known[key] then return key end
        return bracket(key, ...)
    end, function()
        local t = Machine.failureText({ ok = false, reason = "not_enough_sugar_eq", sugarAvailableKg = 1.25,
            waterAvailableL = 6.25 })
        T.eq(t, "[IGUI_TLG_MachineFail_not_enough_sugar_eq] <LINE> [IGUI_TLG_Found_sugar:1.25]",
            "the sugar only: the water is counted up to what the sugar takes")
        t = Machine.failureText({ ok = false, reason = "not_enough_plant_oil", oilAvailableL = 3, methanolAvailableL = 9,
            lyeAvailableKg = 1 })
        T.eq(t, "[IGUI_TLG_MachineFail_not_enough_plant_oil] <LINE> [IGUI_TLG_Found_oil:3.00]")
        -- No amount in the reply, or a refusal that is not a shortage: the reason alone.
        T.eq(Machine.failureText({ ok = false, reason = "not_enough_sugar_eq" }), "[IGUI_TLG_MachineFail_not_enough_sugar_eq]")
        T.eq(Machine.failureText({ ok = false, reason = "machine_busy", sugarAvailableKg = 6 }),
            "[IGUI_TLG_MachineFail_machine_busy]")
        -- Without the machines' wording: the shared one, then the code as it is.
        T.eq(Machine.failureText({ ok = false, reason = "unknown_target" }), "[IGUI_TLG_Fail_Gone]")
        T.eq(Machine.failureText({ ok = false, reason = "malformed_source" }), "[IGUI_TLG_Fail_Generic:malformed_source]")
    end)
end)

T.case("integration: the workshop's dialog lists parts and hours, and words its refusals", function()
    local known = { IGUI_TLG_ConvReason_missing_module = true, IGUI_TLG_ConvReason_malformed_project = true }
    withText(function(key, ...)
        if string.find(key, "^IGUI_TLG_ConvReason_") and not known[key] then return key end
        return bracket(key, ...)
    end, function()
        -- Hand over parts: what went in, what is still needed, the hours so far.
        local t = Workshop.describe({ ok = true, state = "InProgress", stage = "install", doneHours = 2.5, totalHours = 7.5,
            consumed = { ["Base.Screws"] = 4, ["Base.RubberHose"] = 1 }, outstanding = { ["Base.ElectricWire"] = 1 } })
        T.ok(has(t, "[IGUI_TLG_ConvHours:2.5,7.5]"), t)
        T.ok(has(t, "[IGUI_TLG_ConvConsumed:1 <Base.RubberHose>, 4 <Base.Screws>]"), t)
        T.ok(has(t, "[IGUI_TLG_ConvOutstanding:1 <Base.ElectricWire>]"), t)
        T.ok(not has(t, "IGUI_TLG_ConvReturned") and not has(t, "IGUI_TLG_ConvLost"), t)
        -- Cancel: what came back and what did not; a closed project has no hours.
        t = Workshop.describe({ ok = true, state = "Cancelled", returned = { ["Base.Screws"] = 3 },
            lost = { ["Base.Screws"] = 1, ["Base.RubberHose"] = 1 }, consumed = {}, outstanding = {} })
        T.ok(has(t, "[IGUI_TLG_ConvState_Cancelled]") and has(t, "[IGUI_TLG_ConvReturned:3 <Base.Screws>]"), t)
        T.ok(has(t, "[IGUI_TLG_ConvLost:1 <Base.RubberHose>, 1 <Base.Screws>]"), t)
        T.ok(not has(t, "IGUI_TLG_ConvHours") and not has(t, "IGUI_TLG_ConvConsumed"), t)
        -- Project status carries none of these.
        t = Workshop.describe({ ok = true, state = "none", profile = "generator_si_stock" })
        T.eq(t, "[IGUI_TLG_ConvState_none] <LINE> [IGUI_TLG_ConvProfile:[IGUI_TLG_Profile_generator_si_stock]]")
        -- Refusals: the workshop's wording, else the shared one, else the code.
        t = Workshop.describe({ ok = false, reason = "missing_module", missing = { "Base.Screws" } })
        T.eq(t, "[IGUI_TLG_ConvReason_missing_module] <LINE> - <Base.Screws>")
        T.eq(Workshop.describe({ ok = false, reason = "malformed_project" }), "[IGUI_TLG_ConvReason_malformed_project]")
        T.eq(Workshop.describe({ ok = false, reason = "no_engine" }), "[IGUI_TLG_Fail_NoEngine]")
        T.eq(Workshop.describe({ ok = false, reason = "wrong_device" }), "[IGUI_TLG_Fail_Generic:wrong_device]")
    end)
end)

T.case("integration: a greyed entry carries its reason in the menu it belongs to", function()
    local saved = { inv = ISInventoryPaneContextMenu, world = ISWorldObjectContextMenu }
    local made = { inv = 0, world = 0 }
    local ok, err = pcall(function()
        ISInventoryPaneContextMenu = { addToolTip = function() made.inv = made.inv + 1; return {} end }
        ISWorldObjectContextMenu = { addToolTip = function() made.world = made.world + 1; return {} end }
        local o = {}
        Tip.grey(o, "why", false)
        T.ok(o.notAvailable == true and o.toolTip.description == "why")
        T.eq(made.inv, 1); T.eq(made.world, 0)
        o = {}
        Tip.set(o, "into", true)
        T.ok(o.notAvailable == nil and o.toolTip.description == "into")
        T.eq(made.world, 1)
        -- No text: greyed, no tooltip taken from the menu.
        o = {}
        Tip.grey(o, nil, true)
        T.ok(o.notAvailable == true and o.toolTip == nil)
        T.eq(made.world, 1)
        -- A menu without tooltips (the tests' stand-ins, a failing call): the entry stays greyed.
        ISWorldObjectContextMenu = { addToolTip = function() error("no tooltip") end }
        o = {}
        Tip.grey(o, "why", true)
        T.ok(o.notAvailable == true and o.toolTip == nil)
        ISInventoryPaneContextMenu = nil
        o = {}
        Tip.grey(o, "why", false)
        T.ok(o.notAvailable == true and o.toolTip == nil)
    end)
    ISInventoryPaneContextMenu, ISWorldObjectContextMenu = saved.inv, saved.world
    if not ok then error(err, 0) end
end)

T.case("integration: a length of game time reads in minutes, hours, then days", function()
    withText(bracket, function()
        T.eq(Fmt.duration(0), "[IGUI_TLG_Dur_Min:1]")
        T.eq(Fmt.duration(0.5), "[IGUI_TLG_Dur_Min:30]")
        T.eq(Fmt.duration(1), "[IGUI_TLG_Dur_Hours:1.0]")
        T.eq(Fmt.duration(3.46), "[IGUI_TLG_Dur_Hours:3.5]")
        T.eq(Fmt.duration(10.4), "[IGUI_TLG_Dur_Hours:10]")
        T.eq(Fmt.duration(47.4), "[IGUI_TLG_Dur_Hours:47]")
        T.eq(Fmt.duration(47.6), "[IGUI_TLG_Dur_Days:2,0]")
        T.eq(Fmt.duration(58.2), "[IGUI_TLG_Dur_Days:2,10]")
        T.eq(Fmt.duration(nil), "[IGUI_TLG_Dur_Min:1]")
        T.eq(Fmt.duration(-3), "[IGUI_TLG_Dur_Min:1]")
    end)
end)

T.case("integration: a machine's Status says how far the batch is and how long it takes", function()
    withText(bracket, function()
        local function text(state, pause, progress)
            return Machine.describe({ ok = true, command = "machine.status", machine = "fermenter_barrel", state = state,
                pause = pause, stage = "ferment", progress = progress })
        end
        local stage = "[IGUI_TLG_StageDone:[IGUI_TLG_Stage_ferment],38%]"
        -- Working, slowed by the temperature.
        local t = text("Processing", nil, { stageDone = 36.5, stageHours = 96, workLeft = 59.5, etaHours = 148.75,
            tempBound = true, slowed = true })
        T.ok(has(t, stage), t)
        T.ok(has(t, "[IGUI_TLG_EtaSlowed:[IGUI_TLG_Dur_Days:6,5]]"), t)
        T.ok(not has(t, "IGUI_TLG_WorkLeft") and not has(t, "IGUI_TLG_StoodStill"), t)
        -- At full rate, bound to the temperature or not.
        t = text("Processing", nil, { stageDone = 36.5, stageHours = 96, workLeft = 59.5, etaHours = 59.5, tempBound = true })
        T.ok(has(t, "[IGUI_TLG_EtaTemp:[IGUI_TLG_Dur_Days:2,12]]"), t)
        t = text("Processing", nil, { stageDone = 1, stageHours = 4, workLeft = 3, etaHours = 3, woodShortKg = 2.26 })
        T.ok(has(t, "[IGUI_TLG_Eta:[IGUI_TLG_Dur_Hours:3.0]]") and has(t, "[IGUI_TLG_WoodShort:2.3]"), t)
        -- Paused: the work left, and the hours stood still against the limit.
        t = text("Paused", "too_cold", { stageDone = 36.5, stageHours = 96, workLeft = 59.5, tempBound = true,
            pausedFor = 30, maxPauseHours = 72 })
        T.ok(has(t, stage) and has(t, "[IGUI_TLG_WorkLeft:[IGUI_TLG_Dur_Days:2,12]]"), t)
        T.ok(has(t, "[IGUI_TLG_StoodStill:[IGUI_TLG_Dur_Hours:30],[IGUI_TLG_Dur_Days:3,0]]"), t)
        T.ok(not has(t, "IGUI_TLG_Eta"), "no estimate while it stands: " .. t)
        -- Paused with an estimate in the reply (a still out of wood): still the work left.
        t = text("Paused", "no_heat", { stageDone = 1, stageHours = 4, workLeft = 3, etaHours = 3, woodShortKg = 7 })
        T.ok(has(t, "[IGUI_TLG_WorkLeft:[IGUI_TLG_Dur_Hours:3.0]]") and not has(t, "IGUI_TLG_Eta"), t)
        -- Working, never stood still: no line about it. No estimate: the work left.
        t = text("Processing", nil, { stageDone = 0, stageHours = 96, workLeft = 96, tempBound = true, pausedFor = 0,
            maxPauseHours = 72 })
        T.ok(has(t, "[IGUI_TLG_StageDone:[IGUI_TLG_Stage_ferment],0%]") and has(t, "[IGUI_TLG_WorkLeftNow:"), t)
        T.ok(not has(t, "IGUI_TLG_StoodStill"), t)
        -- A reply without the estimate (an older server): the stage as before.
        t = text("Processing", nil, nil)
        T.ok(has(t, "[IGUI_TLG_Stage:[IGUI_TLG_Stage_ferment]]") and not has(t, "IGUI_TLG_StageDone"), t)
    end)
end)

-- A player carrying `items`: { { fullType, name, favourite, water } }.
local function carrying(list)
    local items = {}
    for i, o in ipairs(list) do
        local item = {}
        function item:getFullType() return o[1] end
        function item:getDisplayName() return o[2] end
        function item:getID() return i end
        function item:isFavorite() return o.favourite == true end
        function item:getFluidContainer()
            if not o.water then return nil end
            return { isEmpty = function() return false end, isPureFluid = function() return true end,
                getAmount = function() return o.water end }
        end
        items[#items + 1] = item
    end
    local inv = {}
    function inv:getAllEvalRecurse(pred)
        local found = {}
        for _, it in ipairs(items) do
            if pred(it) then found[#found + 1] = it end
        end
        return { size = function() return #found end, get = function(_, i) return found[i + 1] end }
    end
    return { getInventory = function() return inv end }
end

T.case("integration: a load's tooltip lists what it would take, or why it would be refused", function()
    require "TLG/UI/LoadPreview"
    local Preview = TLG.UI.LoadPreview
    local savedFluid = Fluid
    Fluid = Fluid or { Water = "water" }
    local ok, err = pcall(withText, bracket, function()
        -- A mash: sugar and crops by name with their sugar, the water, the yeast.
        local p = carrying({ { "Base.Sugar", "Sugar" }, { "Base.Sugar", "Sugar" }, { "Base.Potato", "Potato" },
            { "Base.Potato", "Potato", favourite = true }, { "Base.WaterBottle", "Bottle", water = 30 },
            { "Base.Yeast", "Yeast" } })
        T.eq(Preview.mash(p), "[IGUI_TLG_Tip_WillTake:1 Potato, 2 Sugar [IGUI_TLG_Tip_SugarEq:2.09], "
            .. "[IGUI_TLG_Tip_Water:10.45], 1 Yeast]")
        -- No yeast but a favourite one; too little sugar.
        T.eq(Preview.mash(carrying({ { "Base.Sugar", "Sugar" }, { "Base.Yeast", "Yeast", favourite = true } })),
            "[IGUI_TLG_MachineFail_needs_yeast]")
        T.eq(Preview.mash(carrying({ { "Base.Sugar", "Sugar" }, { "Base.Yeast", "Yeast" } })),
            "[IGUI_TLG_MachineFail_not_enough_sugar_eq] [IGUI_TLG_Found_sugar:1.00]")
        -- A firebox with 20 kg of room: a log and firewood; planks only when asked; whole items that fit.
        p = carrying({ { "Base.Log", "Log" }, { "Base.Log", "Log" }, { "Base.Log", "Log" }, { "Base.Firewood", "Firewood" },
            { "Base.Plank", "Plank" } })
        T.eq(Preview.firebox(p, 20, false), "[IGUI_TLG_Tip_WillTake:1 Firewood, 2 Log [IGUI_TLG_Tip_Kg:20.00]]")
        T.eq(Preview.firebox(p, 13, true), "[IGUI_TLG_Tip_WillTake:1 Firewood, 1 Log, 1 Plank [IGUI_TLG_Tip_Kg:12.50]]")
        T.eq(Preview.firebox(p, 0, false), "[IGUI_TLG_MachineFail_firebox_full]")
        T.eq(Preview.firebox(carrying({ { "Base.Plank", "Plank" } }), 20, false), "[IGUI_TLG_MachineFail_needs_wood]")
        -- A batch's wood, and too little of it.
        local min = TLG.Registry.need("recipe", "ash_burn").inputs.firewood.min
        T.ok(min > 0.3, "the ash barrel has a least load")
        T.eq(Preview.woodLoad(carrying({ { "Base.Twigs", "Twigs" } }), "ash_burn"),
            "[IGUI_TLG_MachineFail_not_enough_firewood] [IGUI_TLG_Found_wood:0.30]")
        T.ok(has(Preview.woodLoad(p, "ash_burn"), "[IGUI_TLG_Tip_WillTake:1 Firewood, 3 Log, 1 Plank [IGUI_TLG_Tip_Kg:30.50]]"),
            Preview.woodLoad(p, "ash_burn"))
        -- A gasifier's hopper takes charcoal too.
        T.eq(Preview.hopper(carrying({ { "Base.Log", "Log" }, { "Base.Charcoal", "Charcoal" } }), 50),
            "[IGUI_TLG_Tip_WillTake:1 Charcoal, 1 Log [IGUI_TLG_Tip_Kg:10.00]]")
        T.eq(Preview.hopper(carrying({ { "Base.Log", "Log", favourite = true } }), 50), "[IGUI_TLG_GasifierFail_needs_wood]")
        -- A preview that fails leaves the entry without a tooltip.
        local option = {}
        Preview.attach(option, false, function() error("no inventory") end)
        T.eq(option.toolTip, nil)
    end)
    Fluid = savedFluid
    if not ok then error(err, 0) end
end)

T.case("integration: a load's tooltip gives the machine's refusal before what it would take", function()
    require "TLG/UI/LoadPreview"
    local Preview = TLG.UI.LoadPreview
    withText(bracket, function()
        T.eq(Preview.refusal(nil), nil, "no record yet")
        T.eq(Preview.refusal({}), nil)
        T.eq(Preview.refusal({ state = "Ready", cond = 1 }), nil)
        T.eq(Preview.refusal({ state = "Processing" }), "[IGUI_TLG_MachineFail_machine_busy]")
        T.eq(Preview.refusal({ state = "OutputReady" }), "[IGUI_TLG_MachineFail_machine_busy]")
        T.eq(Preview.refusal({ state = "Faulted", pause = "batch_spoiled" }), "[IGUI_TLG_MachineFail_batch_spoiled]")
        T.eq(Preview.refusal({ state = "Ready", cond = 0 }), "[IGUI_TLG_MachineFail_needs_repair]")
        -- A busy vessel or barrel: the refusal, whatever is carried.
        local p = carrying({ { "Base.Sugar", "Sugar" }, { "Base.Sugar", "Sugar" }, { "Base.Log", "Log" },
            { "Base.Yeast", "Yeast" } })
        T.eq(Preview.mash(p, { state = "Processing" }), "[IGUI_TLG_MachineFail_machine_busy]")
        T.eq(Preview.woodLoad(p, "ash_burn", { state = "OutputReady" }), "[IGUI_TLG_MachineFail_machine_busy]")
        T.ok(has(Preview.woodLoad(p, "ash_burn", { state = "Ready", cond = 1 }), "IGUI_TLG_Tip_WillTake"))
    end)
end)

T.case("integration: the firebox's second entry shows with a plank carried that is not a favourite", function()
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
    local still = { class = "InventoryItem", getFullType = function() return "TLG.PotStill" end,
        getID = function() return 5 end, getModData = function() return {} end,
        getDisplayName = function() return "Pot Still" end }
    still.getWorldItem = function() return { getSquare = function() return square end } end
    local sent, carried = {}, nil
    instanceof = function(value, class) return value.class == class end
    getText = function(key) return key end
    getSpecificPlayer = function() return carried end
    ISContextMenu = { getNew = context }
    TLG.Net.request = function(command, args) sent[#sent + 1] = { command = command, args = args } end
    local function entries(list)
        carried = carrying(list)
        local c = context()
        Machine.fill(0, c, { still })
        local byName = {}
        for _, o in ipairs(c.options[1].sub.options) do byName[o.name] = o end
        return byName
    end
    local ok, err = pcall(function()
        local e = entries({ { "Base.Log", "Log" } })
        T.ok(e.ContextMenu_TLG_AddFirewood ~= nil)
        T.eq(e.ContextMenu_TLG_AddFirewoodPlanks, nil, "no plank carried")
        e = entries({ { "Base.Plank", "Plank", favourite = true } })
        T.eq(e.ContextMenu_TLG_AddFirewoodPlanks, nil, "only a favourite plank")
        e = entries({ { "Base.Log", "Log" }, { "Base.Plank", "Plank" } })
        T.ok(e.ContextMenu_TLG_AddFirewoodPlanks ~= nil, "a plank carried")
        e.ContextMenu_TLG_AddFirewood.onSelect()
        T.eq(sent[#sent].command, "machine.addFuel"); T.eq(sent[#sent].args.planks, nil)
        e.ContextMenu_TLG_AddFirewoodPlanks.onSelect()
        T.eq(sent[#sent].command, "machine.addFuel"); T.eq(sent[#sent].args.planks, true)
    end)
    instanceof, getSpecificPlayer, getText = saved.instanceof, saved.getSpecificPlayer, saved.getText
    ISContextMenu, TLG.Net.request = saved.ISContextMenu, saved.request
    if not ok then error(err, 0) end
end)

T.case("integration: the workshop menu offers what applies to the project's state", function()
    local function offered(state)
        local e = Workshop.entriesFor(state)
        local out = {}
        for _, k in ipairs({ "start", "deliver", "work", "cancel", "remove" }) do
            if e[k] then out[#out + 1] = k end
        end
        return table.concat(out, ",")
    end
    T.eq(offered("none"), "start")
    T.eq(offered("InProgress"), "deliver,work,cancel")
    T.eq(offered("Planned"), "start", "made and not begun: only Start takes it further")
    T.eq(offered("Commissioned"), "remove")
    for _, state in ipairs({ "Cancelled", "Removed", "Reverted", "Invalidated" }) do
        T.eq(offered(state), "start", state .. ": a new project can start")
    end
    T.eq(offered("SomethingNewer"), "start,deliver,work,cancel,remove", "a state this build does not know: everything")
    -- The state on the client's copy: a generator's mod data, a vehicle's Engine part's.
    local function generator(md) return { getModData = function() return md end } end
    local function vehicle(md)
        return { getPartById = function(_, id) return id == "Engine" and { getModData = function() return md end } or nil end }
    end
    T.eq(Workshop.projectState(generator({}), "generator"), "none")
    T.eq(Workshop.projectState(generator({ tlgConv = { state = "InProgress" } }), "generator"), "InProgress")
    T.eq(Workshop.projectState(vehicle({ tlgConv = { state = "Commissioned" } }), "vehicle"), "Commissioned")
    T.eq(Workshop.projectState(vehicle({}), "vehicle"), "none")
    T.eq(Workshop.projectState({ getPartById = function() return nil end }, "vehicle"), "none", "no engine")
    T.eq(Workshop.projectState({}, "generator"), "none", "a device that cannot be read")
    T.eq(Workshop.projectState(generator({ tlgConv = "broken" }), "generator"), "none")
end)

T.case("integration: Start's tooltip lists what the conversion asks for and marks what is missing", function()
    withText(bracket, function()
        local def = TLG.Registry.need("conversion", "flex_generator")
        -- Without the character's own numbers: the list alone.
        local t = Workshop.requirements(def, nil)
        T.ok(has(t, "[IGUI_TLG_ConvReq_Skills:[IGUI_perks_Electricity] 2, [IGUI_perks_Mechanics] 2]"), t)
        T.ok(has(t, "[IGUI_TLG_ConvReq_Knows:Generator]"), t)
        T.ok(has(t, "[IGUI_TLG_ConvReq_Tools:<Base.Pliers>, <Base.Screwdriver>, <Base.Wrench>]"), t)
        T.ok(has(t, "[IGUI_TLG_ConvReq_Parts:1 <Base.ElectricWire>, 1 <Base.RubberHose>, 4 <Base.Screws>]"), t)
        T.ok(has(t, "[IGUI_TLG_ConvReq_Hours:7.5]") and has(t, "[IGUI_TLG_ConvReq_Drain]"), t)
        T.ok(not has(t, "IGUI_TLG_ConvReq_Missing") and not has(t, "IGUI_TLG_ConvReq_SkillLow"), t)
        -- A character short of a skill, the magazine, a tool and some screws.
        t = Workshop.requirements(def, { skills = { Mechanics = 2, Electricity = 1 }, recipes = {},
            inventory = { ["Base.Wrench"] = 1, ["Base.Screwdriver"] = 1, ["Base.Screws"] = 3, ["Base.RubberHose"] = 1,
                ["Base.ElectricWire"] = 2 } })
        T.ok(has(t, "[IGUI_TLG_ConvReq_SkillLow:[IGUI_perks_Electricity] 2,1], [IGUI_perks_Mechanics] 2]"), t)
        T.ok(has(t, "[IGUI_TLG_ConvReq_Knows:[IGUI_TLG_ConvReq_Missing:Generator]]"), t)
        T.ok(has(t, "[IGUI_TLG_ConvReq_Tools:[IGUI_TLG_ConvReq_Missing:<Base.Pliers>], <Base.Screwdriver>, <Base.Wrench>]"), t)
        T.ok(has(t, "[IGUI_TLG_ConvReq_Parts:1 <Base.ElectricWire>, 1 <Base.RubberHose>, "
            .. "[IGUI_TLG_ConvReq_Missing:4 <Base.Screws>]]"), t)
        -- With everything: nothing marked.
        t = Workshop.requirements(def, { skills = { Mechanics = 5, Electricity = 5 }, recipes = { Generator = true },
            inventory = { ["Base.Wrench"] = 1, ["Base.Screwdriver"] = 1, ["Base.Pliers"] = 1, ["Base.Screws"] = 4,
                ["Base.RubberHose"] = 1, ["Base.ElectricWire"] = 1 } })
        T.ok(not has(t, "IGUI_TLG_ConvReq_Missing") and not has(t, "IGUI_TLG_ConvReq_SkillLow"), t)
        -- Every conversion's requirements can be listed.
        for _, id in ipairs(TLG.Registry.ids("conversion")) do
            T.ok(has(Workshop.requirements(TLG.Registry.need("conversion", id), nil), "IGUI_TLG_ConvReq_Hours"), id)
        end
    end)
end)

T.case("integration: Cancel and Remove ask first, and the menu follows the device's project", function()
    local saved = { instanceof = instanceof, getSpecificPlayer = getSpecificPlayer, getText = getText,
        ISContextMenu = ISContextMenu, request = TLG.Net.request, ask = TLG.UI.Confirm.ask, getCell = getCell,
        JoypadState = JoypadState }
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
    local md, sent, asked, answer = {}, {}, {}, false
    local square = { getX = function() return 11 end, getY = function() return 10 end, getZ = function() return 0 end }
    local gen = { class = "IsoGenerator", getSquare = function() return square end, getObjectIndex = function() return 1 end,
        getGeneratorItemType = function() return "Base.Generator" end, getModData = function() return md end }
    instanceof = function(o, class) return type(o) == "table" and o.class == class end
    getText = function(key, a) if a ~= nil then return key .. ":" .. tostring(a) end return key end
    getSpecificPlayer = function() return { getVehicle = function() return nil end, getSquare = function() return square end } end
    getCell = function() return { getVehicles = function() return { toArray = function() return {} end } end } end
    JoypadState = nil
    ISContextMenu = { getNew = context }
    TLG.Net.request = function(command, args) sent[#sent + 1] = command end
    TLG.UI.Confirm.ask = function(text, onYes)
        asked[#asked + 1] = text
        if answer then onYes() end
    end
    local function entries()
        local c = context()
        Workshop.fill(0, c, { gen }, false)
        local byName, names = {}, {}
        for _, o in ipairs(c.options[1].sub.options) do
            byName[o.name] = o
            names[#names + 1] = (string.gsub(o.name, ":.*", ""))
        end
        return byName, table.concat(names, ",")
    end
    local ok, err = pcall(function()
        local e, names = entries()
        T.eq(names, "ContextMenu_TLG_ConvStatus,ContextMenu_TLG_ConvBegin,ContextMenu_TLG_ConvBegin", "no project")
        md.tlgConv = { state = "InProgress" }
        e, names = entries()
        T.eq(names, "ContextMenu_TLG_ConvStatus,ContextMenu_TLG_ConvDeliver,ContextMenu_TLG_ConvJoin,ContextMenu_TLG_ConvCancel")
        -- Cancel: asked, nothing sent on No, the request on Yes.
        e.ContextMenu_TLG_ConvCancel.onSelect()
        T.eq(asked[#asked], "IGUI_TLG_Confirm_ConvCancel"); T.eq(#sent, 0, "No: nothing sent")
        answer = true
        e.ContextMenu_TLG_ConvCancel.onSelect()
        T.eq(sent[#sent], "conversion.cancel")
        -- Hand over parts needs no question.
        local before = #asked
        e.ContextMenu_TLG_ConvDeliver.onSelect()
        T.eq(sent[#sent], "conversion.deliver"); T.eq(#asked, before)
        md.tlgConv = { state = "Commissioned" }
        e, names = entries()
        T.eq(names, "ContextMenu_TLG_ConvStatus,ContextMenu_TLG_ConvRemove")
        answer = false
        local n = #sent
        e.ContextMenu_TLG_ConvRemove.onSelect()
        T.eq(asked[#asked], "IGUI_TLG_Confirm_ConvRemove"); T.eq(#sent, n)
        answer = true
        e.ContextMenu_TLG_ConvRemove.onSelect()
        T.eq(sent[#sent], "conversion.remove")
        md.tlgConv = { state = "Cancelled" }
        e, names = entries()
        T.eq(names, "ContextMenu_TLG_ConvStatus,ContextMenu_TLG_ConvBegin,ContextMenu_TLG_ConvBegin", "a new project can start")
    end)
    instanceof, getSpecificPlayer, getText, getCell = saved.instanceof, saved.getSpecificPlayer, saved.getText, saved.getCell
    ISContextMenu, TLG.Net.request, TLG.UI.Confirm.ask, JoypadState = saved.ISContextMenu, saved.request, saved.ask,
        saved.JoypadState
    if not ok then error(err, 0) end
end)

T.case("integration: Abort batch on what an abort kept asks before throwing it away", function()
    local saved = { instanceof = instanceof, getSpecificPlayer = getSpecificPlayer, getText = getText,
        ISContextMenu = ISContextMenu, request = TLG.Net.request, ask = TLG.UI.Confirm.ask, isClient = isClient }
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
    local md, sent, asked = {}, {}, {}
    local square = { getX = function() return 10 end, getY = function() return 20 end, getZ = function() return 0 end }
    local still = { class = "InventoryItem", getFullType = function() return "TLG.PotStill" end,
        getID = function() return 5 end, getModData = function() return md end,
        getDisplayName = function() return "Pot Still" end }
    still.getWorldItem = function() return { getSquare = function() return square end } end
    instanceof = function(value, class) return value.class == class end
    getText = function(key) return key end
    getSpecificPlayer = function() return carrying({}) end
    -- As a multiplayer client: the record as sent, not brought forward.
    isClient = function() return true end
    ISContextMenu = { getNew = context }
    TLG.Net.request = function(command) sent[#sent + 1] = command end
    TLG.UI.Confirm.ask = function(text, onYes)
        asked[#asked + 1] = text
        onYes()
    end
    local function abort()
        local c = context()
        Machine.fill(0, c, { still })
        for _, o in ipairs(c.options[1].sub.options) do
            if o.name == "ContextMenu_TLG_Abort" then return o end
        end
    end
    local ok, err = pcall(function()
        md.tlgProc = { state = "Processing", machine = "pot_still" }
        abort().onSelect()
        T.eq(sent[#sent], "machine.abort"); T.eq(#asked, 0, "a running batch: no question, its product is kept")
        md.tlgProc = { state = "OutputReady", stoppedEarly = true, machine = "pot_still" }
        abort().onSelect()
        T.eq(asked[#asked], "IGUI_TLG_Confirm_AbortAgain"); T.eq(#sent, 2)
        md.tlgProc = { state = "Faulted", pause = "batch_spoiled", machine = "pot_still" }
        abort().onSelect()
        T.eq(#asked, 1, "a spoiled batch: nothing left worth asking about"); T.eq(#sent, 3)
    end)
    instanceof, getSpecificPlayer, getText, isClient = saved.instanceof, saved.getSpecificPlayer, saved.getText, saved.isClient
    ISContextMenu, TLG.Net.request, TLG.UI.Confirm.ask = saved.ISContextMenu, saved.request, saved.ask
    if not ok then error(err, 0) end
end)
