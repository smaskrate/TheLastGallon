require "support/fixtures"

-- In multiplayer a client sends a timed action's fields named as its new's
-- parameters, read from the function itself (BC NetTimedAction.set), and
-- the server calls new with them. RT-MP run 156: the mod's constructors,
-- wrapped as function(self, ...), sent nothing, so the server built the
-- pump, refuelling and generator actions empty and no fuel moved; and the
-- pour's result callback, a function, is never sent (BC
-- PZNetKahluaTableImpl.canSave), so the player saw no result.

T.case("integration: the wrapped vanilla constructors keep vanilla's parameters", function()
    -- SRC ISTakeFuel.lua:97, ISRefuelFromGasPump.lua:108,
    -- ISAddGasolineToVehicle.lua:159, ISTakeGasolineFromVehicle.lua:158,
    -- ISAddFuel.lua:70.
    local expected = {
        ["TLG/Integration/Stations"] = { "ISTakeFuel.new = function(class, character, fuelStation, petrolCan)",
            "ISRefuelFromGasPump.new = function(class, character, part, fuelStation)" },
        ["TLG/Integration/Vehicles"] = { "A.new = function(class, character, part, item, otherItems)" },
        ["TLG/Integration/Generators"] = { "ISAddFuel.new = function(class, character, generator, petrol, maxTime)" },
    }
    for name, lines in pairs(expected) do
        local src = __TLG_SOURCES[name]
        T.ok(src ~= nil, name)
        for _, l in ipairs(lines) do T.ok(string.find(src, l, 1, true) ~= nil, name .. " declares " .. l) end
    end
    local _, adds = string.gsub(__TLG_SOURCES["TLG/Integration/Vehicles"],
        "A%.new = function%(class, character, part, item, otherItems%)", "")
    T.eq(adds, 2, "both the can -> tank and the siphon constructor")
    -- No mod source wraps a constructor through a vararg helper.
    for name, src in pairs(__TLG_SOURCES) do
        if string.find(name, "^TLG/") then
            T.ok(string.find(src, 'wrap%([%w_%.]+,%s*"new"') == nil, name .. " wraps a constructor with varargs")
        end
    end
end)

-- The pour as each side runs it: a client keeps onDone under the request id
-- it sends with the action; the server's copy (which has no onDone)
-- answers under that id; single player calls onDone itself.
T.case("integration: a multiplayer pour's result reaches the player's onDone", function()
    local names = { "ISBaseTimedAction", "ISTLGPourFuel", "isClient", "isServer", "getTimestampMs", "sendServerCommand" }
    local saved, savedNet, savedDispatch = {}, TLG.Net, TLG.Authority and TLG.Authority.Handlers and
        TLG.Authority.Handlers.dispatch
    for _, k in ipairs(names) do saved[k] = _G[k] end
    local ok, err = pcall(function()
        -- Vanilla's base action, as far as ISTLGPourFuel uses it.
        __TLG_SOURCES["TimedActions/ISBaseTimedAction"] = [[
            ISBaseTimedAction = {}
            ISBaseTimedAction.__index = ISBaseTimedAction
            function ISBaseTimedAction:derive(type)
                local o = setmetatable({}, self)
                self.__index = self
                o.Type = type
                return o
            end
            function ISBaseTimedAction.new(self, character)
                local o = setmetatable({}, self)
                self.__index = self
                o.character = character
                return o
            end
        ]]
        require "TLG/Actions/ISTLGPourFuel"
        getTimestampMs = function() return 1000 end
        local sent = {}
        sendServerCommand = function(player, module, command, args)
            sent[#sent + 1] = { player = player, module = module, command = command, args = args }
        end
        local dispatched
        TLG.Authority.Handlers.dispatch = function(player, command, args)
            dispatched = args
            return { ok = false, reason = "incompatible", requestId = args.requestId }
        end
        local fc = { getAmount = function() return 3 end, isEmpty = function() return false end }
        local item = { getID = function() return 42 end, getFluidContainer = function() return fc end }
        local dest, got = { kind = "generator", x = 1, y = 2, z = 0, index = 3 }, nil
        local player = { isTimedActionInstant = function() return false end }
        local function onDone(r) got = r end
        -- The client: onDone kept under the id it sends.
        isClient, isServer = function() return true end, function() return false end
        TLG.Net = { pending = {} }
        local mine = ISTLGPourFuel:new(player, item, dest, nil, false, onDone)
        T.eq(mine.requestId, "pour-42-1000"); T.ok(TLG.Net.pending["pour-42-1000"] == onDone, "kept for the reply")
        T.ok(mine.onDone == nil, "not on the action: a function is not sent, and the id after it would take its place")
        -- The server: its copy, made from the fields the client sent (no
        -- onDone), answers under the client's id.
        isClient, isServer = function() return false end, function() return true end
        TLG.Net = nil
        local copy = ISTLGPourFuel:new(player, item, dest, nil, false, nil, mine.requestId)
        T.eq(copy.requestId, "pour-42-1000", "the client's id")
        T.eq(copy:complete(), true)
        T.eq(dispatched.requestId, "pour-42-1000")
        T.eq(#sent, 1); T.ok(sent[1].player == player and sent[1].module == "TLG" and sent[1].command == "reply",
            "sent to the player as TLG.Net's replies are")
        T.eq(sent[1].args.requestId, "pour-42-1000"); T.eq(sent[1].args.reason, "incompatible")
        T.ok(got == nil, "the server has no onDone to call")
        -- Single player: onDone called at once, nothing sent.
        isClient, isServer = function() return false end, function() return false end
        local solo = ISTLGPourFuel:new(player, item, dest, nil, false, onDone)
        solo:complete()
        T.ok(got ~= nil and got.reason == "incompatible", "onDone called"); T.eq(#sent, 1, "nothing sent")
    end)
    for _, k in ipairs(names) do _G[k] = saved[k] end
    TLG.Net = savedNet
    if savedDispatch then TLG.Authority.Handlers.dispatch = savedDispatch end
    __TLG_SOURCES["TimedActions/ISBaseTimedAction"] = nil
    if not ok then error(err, 0) end
end)
