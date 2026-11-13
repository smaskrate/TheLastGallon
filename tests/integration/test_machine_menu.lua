require "support/fixtures"
-- The machine menu's Status text (client UI). The menu registers game events
-- when it loads; a stand-in event list takes them.
local savedEvents = Events
local callbacks = {}
Events = setmetatable({}, { __index = function(t, k)
    local e = { Add = function(fn) callbacks[k] = fn end }
    rawset(t, k, e)
    return e
end })
require "TLG/UI/MachineContextMenu"
Events = savedEvents
local Menu = TLG.UI.MachineMenu

T.case("integration: registered machine menus handle floor inventory and world picking", function()
    local saved = { instanceof = instanceof, getSpecificPlayer = getSpecificPlayer, getText = getText,
        ISContextMenu = ISContextMenu, ISWorldObjectContextMenu = ISWorldObjectContextMenu,
        request = TLG.Net.request }
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
    local objects = {}
    local square = {
        getX = function() return 10 end, getY = function() return 20 end, getZ = function() return 1 end,
        getWorldObjects = function() return {
            size = function() return #objects end, get = function(_, i) return objects[i + 1] end,
        } end,
    }
    local floor = { getSquare = function() return square end }
    local requested, tested
    instanceof = function(value, class) return value.class == class end
    getText = function(key) return key end
    getSpecificPlayer = function() return { getInventory = function() return {
        getAllEvalRecurse = function() return { size = function() return 0 end } end,
    } end } end
    ISContextMenu = { getNew = context }
    ISWorldObjectContextMenu = { setTest = function() tested = true; return true end }
    TLG.Net.request = function(command, args) requested = { command = command, args = args } end
    local ok, err = pcall(function()
        T.eq(callbacks.OnFillInventoryObjectContextMenu, Menu.fill)
        T.eq(callbacks.OnFillWorldObjectContextMenu, Menu.fillWorld)
        for fullType in pairs(TLG.Integration.Machines.ITEMS) do
            local item = { class = "InventoryItem", getFullType = function() return fullType end,
                getID = function() return 123 end, getModData = function() return {} end,
                getDisplayName = function() return fullType end }
            local world = { class = "IsoWorldInventoryObject", getItem = function() return item end,
                getSquare = function() return square end }
            item.getWorldItem = function() return world end
            objects = { world }
            for _, entry in ipairs({ item, { items = { item, item } } }) do
                local c = context()
                callbacks.OnFillInventoryObjectContextMenu(0, c, { entry })
                T.eq(#c.options, 1, fullType .. " floor inventory")
                c.options[1].sub.options[1].onSelect()
                T.eq(requested.command, "machine.status")
                T.eq(requested.args.target.id, 123)
                T.eq(requested.args.target.x, 10)
                T.eq(requested.args.target.z, 1)
            end
            local c = context()
            callbacks.OnFillWorldObjectContextMenu(0, c, { floor, world, floor }, false)
            T.eq(#c.options, 1, "one entry per machine")
            c.options[1].sub.options[1].onSelect()
            T.eq(requested.args.target.y, 20)
            tested = false
            c = context()
            callbacks.OnFillWorldObjectContextMenu(0, c, { floor }, true)
            T.ok(tested, "controller probe detects the menu")
            T.eq(#c.options, 0, "probe does not build a menu")
        end
        objects = {}
        tested = false
        local c = context()
        callbacks.OnFillWorldObjectContextMenu(0, c, { floor }, true)
        T.ok(not tested, "empty floor has no machine menu")
    end)
    instanceof, getSpecificPlayer, getText = saved.instanceof, saved.getSpecificPlayer, saved.getText
    ISContextMenu, ISWorldObjectContextMenu = saved.ISContextMenu, saved.ISWorldObjectContextMenu
    TLG.Net.request = saved.request
    if not ok then error(err, 0) end
end)

-- getText as the game's Translator: a key it knows comes back as "[key]"
-- (arguments appended), one it does not as the key itself.
local function lookup(known)
    return function(key, ...)
        if not known[key] then return key end
        local args = { ... }
        return "[" .. key .. (#args > 0 and (":" .. table.concat(args, ",")) or "") .. "]"
    end
end

local function has(text, part) return string.find(text, part, 1, true) ~= nil end

T.case("integration: a finished machine's Status says what waits and where it goes", function()
    local saved = getText
    getText = lookup({
        IGUI_TLG_MachineState_OutputReady = true, IGUI_TLG_MachineState_OutputReady_fermenter = true,
        IGUI_TLG_MachineState_OutputReady_still = true, IGUI_TLG_MachineState_Processing = true,
        IGUI_TLG_Pause_output_full = true, IGUI_TLG_Pause_output_full_fermenter = true, IGUI_TLG_Pause_no_heat = true,
        IGUI_TLG_Stage = true, IGUI_TLG_Stage_distill = true,
    })
    local ok, err = pcall(function()
        -- The fermenter after the pot still took 60 L of 66.6 (RT-SP run 28).
        local text = Menu.describe({ state = "OutputReady", pause = "output_full", machine = "fermenter_barrel",
            outputs = { ethanol = 0.654, water = 5.946 } })
        T.ok(has(text, "[IGUI_TLG_MachineState_OutputReady_fermenter]"), text)
        T.ok(has(text, "[IGUI_TLG_Pause_output_full_fermenter]"), text)
        T.ok(not has(text, "IGUI_TLG_Stage"), "no stage once finished: " .. text)
        -- A still whose can was too small: its own state, the shared pause.
        text = Menu.describe({ state = "OutputReady", pause = "output_full", machine = "pot_still", outputs = { ethanol = 1 } })
        T.ok(has(text, "[IGUI_TLG_MachineState_OutputReady_still]"), text)
        T.ok(has(text, "[IGUI_TLG_Pause_output_full]"), text)
        -- Running: the shared state, the pause and the stage.
        text = Menu.describe({ state = "Processing", pause = "no_heat", stage = "distill", machine = "pot_still" })
        T.ok(has(text, "[IGUI_TLG_MachineState_Processing]") and has(text, "[IGUI_TLG_Pause_no_heat]"), text)
        T.ok(has(text, "[IGUI_TLG_Stage:[IGUI_TLG_Stage_distill]]"), text)
        -- No machine in the reply, or a kind without its own wording: the shared one.
        T.ok(has(Menu.describe({ state = "OutputReady" }), "[IGUI_TLG_MachineState_OutputReady]"))
        T.ok(has(Menu.describe({ state = "OutputReady", machine = "drying_column" }), "[IGUI_TLG_MachineState_OutputReady]"))
    end)
    getText = saved
    if not ok then error(err, 0) end
end)

T.case("integration: an abort's dialog says what was kept and what was thrown away", function()
    local saved = getText
    getText = lookup({
        IGUI_TLG_Aborted = true, IGUI_TLG_AbortedSpoiled = true, IGUI_TLG_AbortAgain = true, IGUI_TLG_Discarded = true,
        IGUI_TLG_MachineState_Ready = true, IGUI_TLG_MachineState_OutputReady_stopped = true,
        IGUI_TLG_MachineState_OutputReady_stopped_fermenter = true, IGUI_TLG_Fuel_ethanol = true, IGUI_TLG_Fuel_water = true,
        IGUI_TLG_Fuel_sugar_eq = true, IGUI_TLG_Fuel_spent_lime = true,
    })
    local ok, err = pcall(function()
        -- Fermenter: the wash so far stays for a still; a second Abort throws it away.
        local text = Menu.describe({ ok = true, aborted = true, state = "OutputReady", stoppedEarly = true,
            machine = "fermenter_barrel", outputs = { ethanol = 0.17, water = 30, sugar_eq = 5.69 }, kept = {}, discarded = {} })
        T.ok(has(text, "[IGUI_TLG_Aborted]") and has(text, "[IGUI_TLG_MachineState_OutputReady_stopped_fermenter]"), text)
        T.ok(has(text, "[IGUI_TLG_Fuel_sugar_eq]: 5.69") and has(text, "[IGUI_TLG_AbortAgain]"), text)
        T.ok(not has(text, "IGUI_TLG_Discarded"), "nothing thrown away: " .. text)
        -- Drying column: the shared stopped wording and the spent lime listed.
        text = Menu.describe({ ok = true, aborted = true, state = "OutputReady", stoppedEarly = true, machine = "drying_column",
            outputs = { ethanol = 4, water = 0.51 }, discarded = { spent_lime = 4.49 } })
        T.ok(has(text, "[IGUI_TLG_MachineState_OutputReady_stopped]"), text)
        T.ok(has(text, "[IGUI_TLG_Discarded:[IGUI_TLG_Fuel_spent_lime] 4.49]"), text)
        -- A spoiled batch thrown away.
        text = Menu.describe({ ok = true, aborted = true, spoiled = true, state = "Ready", machine = "fermenter_barrel",
            outputs = {}, discarded = { sugar_eq = 6, water = 30 } })
        T.ok(has(text, "[IGUI_TLG_AbortedSpoiled]") and has(text, "[IGUI_TLG_MachineState_Ready]"), text)
        T.ok(has(text, "[IGUI_TLG_Fuel_sugar_eq] 6.00") and not has(text, "IGUI_TLG_AbortAgain"), text)
        -- A later Status of the kept output: stopped, not finished; no abort lines.
        text = Menu.describe({ ok = true, state = "OutputReady", stoppedEarly = true, machine = "drying_column", outputs = { ethanol = 4 } })
        T.ok(has(text, "[IGUI_TLG_MachineState_OutputReady_stopped]") and not has(text, "IGUI_TLG_Abort"), text)
    end)
    getText = saved
    if not ok then error(err, 0) end
end)

T.case("integration: Pause, Resume and Abort batch are offered only where they apply", function()
    local function item(rec)
        local md = { tlgProc = rec }
        local it = {}
        function it:getModData() return md end
        return it
    end
    -- Without the game the preview falls back to the stored record.
    local function offered(rec)
        local c = Menu.controls(item(rec))
        return string.format("%s,%s,%s", tostring(c.pause == true), tostring(c.resume == true), tostring(c.abort == true))
    end
    T.eq(offered({ state = "Processing" }), "true,false,true", "working")
    T.eq(offered({ state = "Paused", pause = "paused_by_player", manualPause = true }), "false,true,true", "paused by hand")
    T.eq(offered({ state = "Paused", pause = "too_cold" }), "false,false,true", "paused by the cold: Resume would not help")
    T.eq(offered({ state = "Faulted", pause = "batch_spoiled" }), "false,false,true", "spoiled: Abort empties it")
    T.eq(offered({ state = "OutputReady", stoppedEarly = true }), "false,false,true", "kept by an abort")
    T.eq(offered({ state = "OutputReady" }), "false,false,false", "finished: collect it")
    T.eq(offered({ state = "Ready" }), "false,false,false")
    T.eq(offered(nil), "false,false,false", "no record yet")
end)

T.case("integration: a multiplayer client judges Pause, Resume and Abort batch on the record as the server sent it", function()
    local Machines = TLG.Integration.Machines
    local World = TLG.World
    local savedAdvance, savedClient, savedRead = Machines.advance, isClient, Machines.read
    local savedNow, savedEnv = World.now, World.env
    Machines.read = function(item) return TLG.Tables.deepCopy(item:getModData().tlgProc) end
    World.now, World.env = function() return 5 end, function() return {} end
    local calls = 0
    -- Brought forward, this batch would read finished; as sent, it works.
    Machines.advance = function(item, rec)
        calls = calls + 1
        local out = TLG.Tables.deepCopy(rec)
        out.state = "OutputReady"
        return out
    end
    local ok, err = pcall(function()
        local md = { tlgProc = { v = 1, id = "P-mp", machine = "fermenter_barrel", state = "Processing", t = 0 } }
        local it = {}
        function it:getModData() return md end
        function it:getFullType() return "TLG.FermenterVessel" end
        isClient = function() return true end
        local c = Menu.controls(it)
        T.eq(calls, 0, "not brought forward on a client")
        T.ok(c.pause == true and c.abort == true, "as sent: working")
        isClient = function() return false end
        c = Menu.controls(it)
        T.eq(calls, 1, "brought forward in single player")
        T.ok(c.pause == false and c.abort == false, "brought forward: finished")
    end)
    Machines.advance, isClient, Machines.read = savedAdvance, savedClient, savedRead
    World.now, World.env = savedNow, savedEnv
    if not ok then error(err, 0) end
end)
