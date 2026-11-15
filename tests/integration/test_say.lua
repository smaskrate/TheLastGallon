require "support/fixtures"
-- How a reply reaches the player (client UI, TLG/UI/Say.lua; UX review R6,
-- D-016 as amended): over the character for what an action did and for a
-- refusal of one sentence, in a window for what is read and for a refusal
-- with a list. The menus are loaded by test_machine_menu.lua and
-- test_gasifier_menu.lua, which keep the stand-ins their loading needs.
require "integration/test_machine_menu"
require "integration/test_gasifier_menu"
require "TLG/UI/Say"
local Say, Machine, Gasifier, Fmt = TLG.UI.Say, TLG.UI.MachineMenu, TLG.UI.GasifierMenu, TLG.UI.Format

local function bracket(key, ...)
    local args = { ... }
    return "[" .. key .. (#args > 0 and (":" .. table.concat(args, ",")) or "") .. "]"
end

local GLOBALS = { "getText", "getSpecificPlayer", "HaloTextHelper", "ISModalRichText", "getCore" }

-- The game's two ways to show a text, recorded: s.lines over a character
-- ({ player, text, good }) and s.windows ({ text, w, h, playerNum }).
local function stage(fn)
    local saved = { translate = Fmt.translate, playerNum = Say.playerNum }
    for _, k in ipairs(GLOBALS) do saved[k] = _G[k] end
    local s = { lines = {}, windows = {}, players = { [0] = "first", [1] = "second" } }
    getText, Fmt.translate = bracket, bracket
    getSpecificPlayer = function(n) return s.players[n] end
    HaloTextHelper = {
        addGoodText = function(player, text) s.lines[#s.lines + 1] = { player = player, text = text, good = true } end,
        addBadText = function(player, text) s.lines[#s.lines + 1] = { player = player, text = text, good = false } end,
    }
    getCore = function() return { getScreenWidth = function() return 1920 end, getScreenHeight = function() return 1080 end } end
    ISModalRichText = { new = function(_, x, y, w, h, text, _, _, _, playerNum)
        local o = { text = text, w = w, h = h, x = x, playerNum = playerNum }
        function o:initialise() self.initialised = true end
        function o:addToUIManager() s.windows[#s.windows + 1] = self end
        return o
    end }
    Say.playerNum = 0
    local ok, err = pcall(fn, s)
    for _, k in ipairs(GLOBALS) do _G[k] = saved[k] end
    Fmt.translate, Say.playerNum = saved.translate, saved.playerNum
    if not ok then error(err, 0) end
end

T.case("integration: a sentence goes over the character, a text with lines or without a character opens a window", function()
    stage(function(s)
        T.eq(Say.line("Stabilizer added.", true), "line")
        T.eq(#s.lines, 1); T.eq(#s.windows, 0)
        T.ok(s.lines[1].good == true and s.lines[1].text == "Stabilizer added." and s.lines[1].player == "first")
        T.eq(Say.refusal("You need a fuel filter."), "line")
        T.ok(s.lines[2].good == false, "a refusal in the bad colour")
        -- The player whose menu was opened last.
        Say.from(1)
        Say.line("Paused", true)
        T.eq(s.lines[3].player, "second")
        Say.from(nil)
        T.eq(Say.playerNum, 1, "no number: the last one stays")
        -- A list stays a window, whoever asks for a line.
        T.eq(Say.refusal("Not enough wood. <LINE> Found: 2.00 kg"), "window")
        T.eq(#s.lines, 3); T.eq(#s.windows, 1)
        T.ok(s.windows[1].initialised and s.windows[1].text == "Not enough wood. <LINE> Found: 2.00 kg")
        T.eq(s.windows[1].playerNum, 1, "the window is that player's")
        -- No character, or a game without the text over the head: the
        -- window, so that a reply is never dropped.
        s.players[1] = nil
        T.eq(Say.line("Filtered.", true), "window")
        s.players[1] = "second"
        HaloTextHelper = nil
        T.eq(Say.refusal("You need a kit."), "window")
        HaloTextHelper = { addGoodText = function() error("java") end }
        T.eq(Say.line("Sealed.", true), "window")
        T.eq(#s.windows, 4); T.eq(#s.lines, 3)
        T.eq(Say.line("", true), "window", "nothing to say over a character")
        -- A window's size is the menu's own.
        Say.window("Status", 440, 260)
        T.ok(s.windows[6].w == 440 and s.windows[6].h == 260)
        T.eq(s.windows[6].x, 1920 / 2 - 220)
    end)
end)

T.case("integration: a machine's action is said in one sentence; Status, an abort and what was thrown away are windows", function()
    stage(function()
        local function line(reply)
            reply.ok = true
            return Machine.line(reply)
        end
        T.eq(line({ command = "machine.loadFerment", machine = "fermenter_barrel", state = "Processing", stage = "prepare",
            sugarKg = 6, waterL = 30 }), "[IGUI_TLG_Did_loadFerment:6.00,30.00]")
        T.eq(line({ command = "machine.loadWash", machine = "pot_still", state = "Processing", washL = 36.5 }),
            "[IGUI_TLG_Did_loadWash:36.50]")
        -- The feed, repeated most often: with what the firebox now holds.
        local cap = string.format("%.0f", TLG.Registry.need("machine", "pot_still").firebox.capacityKg)
        T.eq(line({ command = "machine.addFuel", machine = "pot_still", state = "Ready", addedKg = 9, firebox = 9 }),
            "[IGUI_TLG_Did_addFuel:9.00] [IGUI_TLG_FireboxOf:9.0," .. cap .. "]")
        T.eq(line({ command = "machine.collect", machine = "pot_still", state = "Ready", outputs = {},
            collected = { ethanol = 4 } }), "[IGUI_TLG_Did_collect:[IGUI_TLG_Fuel_ethanol] [IGUI_TLG_Amount_L:4.00]]")
        T.eq(line({ command = "machine.load", machine = "wood_retort", state = "Processing", woodKg = 40 }),
            "[IGUI_TLG_Did_load_wood:40.00]")
        -- Pause and Resume move nothing: the state, and why it stands.
        local paused = line({ command = "machine.pause", machine = "pot_still", state = "Paused", pause = "paused_by_player" })
        T.ok(string.find(paused, "[IGUI_TLG_MachineState_Paused", 1, true) == 1
            and string.find(paused, "IGUI_TLG_Pause_paused_by_player", 1, true) ~= nil, paused)
        T.ok(not string.find(paused, "<LINE>", 1, true), "one sentence")
        T.ok(string.find(line({ command = "machine.resume", machine = "pot_still", state = "Processing", stage = "distil" }),
            "IGUI_TLG_MachineState_Processing", 1, true) ~= nil)
        -- Windows.
        T.ok(line({ command = "machine.status", machine = "pot_still", state = "Processing", stage = "distil" }) == nil,
            "Status is read")
        T.ok(line({ command = "machine.abort", machine = "pot_still", state = "Ready", aborted = true }) == nil, "an abort")
        T.ok(line({ machine = "pot_still", state = "Processing", stage = "distil" }) == nil, "a reply that names no command")
        T.ok(line({ command = "machine.collect", machine = "pot_still", state = "Ready", outputs = {},
            collected = { ethanol = 4 }, discarded = { stillage = 20 } }) == nil, "the collect that threw the stillage away")
        T.ok(line({ command = "machine.load", machine = "biodiesel_reactor", state = "Processing", oilL = 10, methanolL = 2,
            lyeKg = 0.1, charcoal = 3 }) == nil, "the load that also emptied the retort")
        T.ok(line({ command = "machine.load", machine = "biodiesel_reactor", state = "Processing", oilL = 10, methanolL = 2,
            lyeKg = 0.1 }) ~= nil)
        T.ok(line({ command = "machine.collect", machine = "pot_still", state = "Ready", collected = { ethanol = 4 },
            discarded = {} }) ~= nil, "nothing thrown away")
    end)
end)

T.case("integration: a gasifier's action is said in one sentence, its Status is a window", function()
    stage(function()
        T.ok(Gasifier.line({ command = "gasifier.status", state = "Processing", mode = "running" }) == nil)
        T.ok(Gasifier.line({ state = "Ready" }) == nil, "a reply that names no command")
        T.eq(Gasifier.line({ command = "gasifier.load", state = "Ready", loadedKg = 12.5, items = 5, hopperKg = 12.5 }),
            "[IGUI_TLG_GasifierLoaded:12.5,5]")
        T.eq(Gasifier.line({ command = "gasifier.putOut", state = "Ready", vented = 0.25 }), "[IGUI_TLG_GasifierVented:0.25]")
        T.eq(Gasifier.line({ command = "gasifier.service", state = "Ready",
            thrownAway = { wood_tar = 1, wood_ash = 2, water = 0.5 } }), "[IGUI_TLG_GasifierServiced:1.00,2.00,0.50]")
        T.eq(Gasifier.line({ command = "gasifier.light", state = "Processing", mode = "warming" }),
            "[IGUI_TLG_GasifierState_warming]")
    end)
end)

T.case("integration: Status says how worn a machine is and what that costs in yield", function()
    stage(function()
        local Process = TLG.Domain.Process
        T.near(Process.yieldAt(1), 1, 1e-12); T.near(Process.yieldAt(0), 0.7, 1e-12); T.near(Process.yieldAt(0.5), 0.85, 1e-12)
        T.near(Process.yieldAt(nil), 1, 1e-12); T.near(Process.yieldAt(7), 1, 1e-12)
        T.ok(Fmt.condition(nil) == nil, "a reply without a condition")
        T.eq(Fmt.condition(1), "[IGUI_TLG_MachineCond:100%]", "a new machine: no cost named")
        T.eq(Fmt.condition(0.86), "[IGUI_TLG_MachineCond:86%] <LINE> [IGUI_TLG_MachineCondYield:96%]")
        T.eq(Fmt.condition(0), "[IGUI_TLG_MachineCond:0%] <LINE> [IGUI_TLG_MachineCondWornOut]")
        local function has(text, part) return string.find(text, part, 1, true) ~= nil end
        local status = Machine.describe({ ok = true, command = "machine.status", machine = "pot_still", state = "Ready",
            cond = 0.5 })
        T.ok(has(status, "[IGUI_TLG_MachineCond:50%] <LINE> [IGUI_TLG_MachineCondYield:85%]"), status)
        -- An action's window (an abort) does not repeat it.
        T.ok(not has(Machine.describe({ ok = true, command = "machine.abort", machine = "pot_still", state = "Ready",
            aborted = true, cond = 0.5 }), "MachineCond"))
        T.ok(has(Gasifier.describe({ command = "gasifier.status", state = "Ready", hopperKg = 0, filter = 0.2, cond = 0.9 }),
            "[IGUI_TLG_MachineCond:90%] <LINE> [IGUI_TLG_MachineCondYield:97%]"))
    end)
end)

T.case("integration: the Repair entry shows on a worn machine, with what it takes or what is missing", function()
    stage(function()
        local Repair, Picks = TLG.UI.Repair, TLG.Integration.Picks
        local saved = { name = getItemNameFromFullType, world = ISWorldObjectContextMenu, pick = Picks.repair }
        getItemNameFromFullType = function(t) return "<" .. t .. ">" end
        ISWorldObjectContextMenu = { addToolTip = function() return {} end }
        local ok, err = pcall(function()
            local function menu()
                local c = { options = {} }
                function c:addOption(name, _, fn) local o = { name = name, fn = fn }; self.options[#self.options + 1] = o; return o end
                return c
            end
            local needs = "[IGUI_TLG_Tip_Repair:25%,1 <Base.MetalPipe>,<Base.Screwdriver>]"
            T.eq(Repair.needs("pot_still"), needs)
            T.eq(Repair.needs("fermenter_barrel"), "[IGUI_TLG_Tip_Repair:25%,2 <Base.Nails>, 1 <Base.Plank>,<Base.Hammer>]")
            -- Not worn enough, or no condition known: no entry.
            local c = menu()
            T.ok(Repair.add(c, {}, "pot_still", 1, nil, true, nil) == nil and Repair.add(c, {}, "pot_still", nil, nil, true, nil) == nil)
            T.ok(Repair.add(c, {}, "pot_still", 0.8, nil, true, nil) == nil, "a whole quarter does not fit yet")
            T.eq(#c.options, 0)
            -- Worn, with what it takes.
            Picks.repair = function() return { ok = true, items = {}, missing = {} } end
            local clicked = false
            local o = Repair.add(c, {}, "pot_still", 0.6, nil, true, function() clicked = true end)
            T.eq(o.name, "[ContextMenu_TLG_Repair]")
            T.ok(o.notAvailable == nil and o.toolTip.description == needs)
            o.fn()
            T.ok(clicked)
            -- Something missing: greyed, naming it once, then what it takes.
            Picks.repair = function() return { ok = false, items = {}, missing = { "Base.Nails", "Base.Nails", "Base.Hammer" } } end
            o = Repair.add(c, {}, "pot_still", 0.6, nil, true, nil)
            T.ok(o.notAvailable == true)
            T.eq(o.toolTip.description, "[IGUI_TLG_Tip_RepairMissing:<Base.Nails>, <Base.Hammer>] <LINE> " .. needs)
            -- Busy: greyed with that reason, the inventory not looked at.
            Picks.repair = function() error("not asked") end
            o = Repair.add(c, {}, "pot_still", 0.6, "busy now", true, nil)
            T.ok(o.notAvailable == true and o.toolTip.description == "busy now")
            -- The replies: a line when done, a window with the list when refused.
            T.eq(Machine.line({ ok = true, command = "machine.repair", machine = "pot_still", state = "Ready", cond = 0.65 }),
                "[IGUI_TLG_Did_repair:65%]")
            T.eq(Gasifier.line({ command = "gasifier.repair", state = "Ready", repaired = true, cond = 0.25 }),
                "[IGUI_TLG_Did_repair:25%]")
            T.eq(Machine.failureText({ ok = false, reason = "needs_repair_parts", missing = { "Base.MetalPipe", "Base.MetalPipe" } }),
                "[IGUI_TLG_MachineFail_needs_repair_parts] <LINE> - <Base.MetalPipe>", "the list, each part once (the stand-in translator knows every key)")
            T.eq(Fmt.failure({ reason = "not_worn" }), "[IGUI_TLG_Fail_NotWorn]")
            T.eq(Fmt.failure({ reason = "needs_repair_parts" }), "[IGUI_TLG_Fail_RepairParts]")
        end)
        getItemNameFromFullType, ISWorldObjectContextMenu, Picks.repair = saved.name, saved.world, saved.pick
        if not ok then error(err, 0) end
    end)
end)

-- The game's window sets the game's speed to 1 when it closes; the mod's
-- windows give the speed back (UX review R14).
T.case("integration: closing a window leaves the game's speed as it was", function()
    stage(function(s)
        local savedUI = UIManager
        local ok, err = pcall(function()
            local speed, sets, destroyed = 3, 0, 0
            local controls = { getCurrentGameSpeed = function() return speed end,
                SetCurrentGameSpeed = function(_, v) speed = v; sets = sets + 1 end }
            UIManager = { getSpeedControls = function() return controls end }
            -- The game's destroy, as far as the speed goes.
            ISModalRichText.destroy = function(self)
                destroyed = destroyed + 1
                self.closed = true
                UIManager.getSpeedControls():SetCurrentGameSpeed(1)
            end
            local modal = Say.window("Status")
            T.ok(modal.destroy == Say.close, "the window closes through Say.close")
            modal:destroy()
            T.ok(modal.closed, "closed as the game closes it"); T.eq(destroyed, 1)
            T.eq(speed, 3, "the faster speed is back")
            -- At normal speed nothing is set again.
            speed, sets = 1, 0
            Say.window("Status"):destroy()
            T.eq(speed, 1); T.eq(sets, 1, "only the game's own set")
            -- Paused when it was opened and closed: paused after.
            speed = 0
            Say.window("Status"):destroy()
            T.eq(speed, 0)
            -- No speed controls (a server's client): closed, nothing else.
            UIManager = { getSpeedControls = function() return nil end }
            ISModalRichText.destroy = function(self) self.closed = true end
            modal = Say.window("Status")
            modal:destroy()
            T.ok(modal.closed)
            UIManager = nil
            modal = Say.window("Status")
            modal:destroy()
            T.ok(modal.closed)
        end)
        UIManager = savedUI
        if not ok then error(err, 0) end
    end)
end)

T.case("integration: a yes/no question of the game's keeps the speed when it is answered", function()
    local savedUI, savedDialog = UIManager, ISModalDialog
    local ok, err = pcall(function()
        local speed = 2
        local controls = { getCurrentGameSpeed = function() return speed end,
            SetCurrentGameSpeed = function(_, v) speed = v end }
        UIManager = { getSpeedControls = function() return controls end }
        ISModalDialog = { destroy = function(self)
            self.closed = true
            UIManager.getSpeedControls():SetCurrentGameSpeed(1)
        end }
        local dialog = {}
        T.ok(Say.keepSpeed(dialog) == dialog, "returns the dialog")
        dialog:destroy()
        T.ok(dialog.closed, "closed as the game closes it"); T.eq(speed, 2)
    end)
    UIManager, ISModalDialog = savedUI, savedDialog
    if not ok then error(err, 0) end
end)
