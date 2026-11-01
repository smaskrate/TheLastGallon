require "support/fixtures"
-- The machine menu's Status text (client UI). The menu registers game events
-- when it loads; a stand-in event list takes them.
local savedEvents = Events
Events = setmetatable({}, { __index = function(t, k)
    local e = { Add = function() end }
    rawset(t, k, e)
    return e
end })
require "TLG/UI/MachineContextMenu"
Events = savedEvents
local Menu = TLG.UI.MachineMenu

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
