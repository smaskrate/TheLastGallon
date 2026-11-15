-- A machine's Status as a card that stays open (UX review, section 5):
-- Status is the entry asked most, on five machines over three days, and
-- each answer was a window to close. The card is the same text, kept up to
-- date by asking machine.status again every ten game minutes while it is
-- shown, and gone by itself when the machine is picked up, is out of reach
-- or is no longer there. It has no buttons: the actions stay in the menu.
--
-- Only a machine on the ground, and only without a controller, gets a
-- card; a carried machine's Status and a controller's stay the window
-- (TLG/UI/MachineContextMenu.lua). The gasifier's Status and Gas status are
-- windows still.
--
-- Each refresh is a machine.status request: the authority brings the record
-- to now and writes it (Authority/MachineHandlers.lua), which on a server
-- sends it to the clients. Hence the pace: ten game minutes, and never
-- less than MIN_MS of real time, so that a fast-forwarded game does not ask
-- at every frame. The cost with several cards open is NOT MEASURED.
require "TLG/Client/Net"
require "TLG/Integration/Machines"
require "TLG/UI/Format"
require "TLG/UI/Say"

TLG.UI = TLG.UI or {}
TLG.UI.MachineCard = TLG.UI.MachineCard or {}
local Card = TLG.UI.MachineCard
local Machines, Say = TLG.Integration.Machines, TLG.UI.Say

Card.REFRESH_HOURS = 10 / 60
Card.MIN_MS = 3000
-- The open cards' states, by key: { item, ref, title, playerNum, atHours,
-- atMs, asked }.
Card.open = Card.open or {}

local function gameHours()
    local ok, h = pcall(function() return getGameTime():getWorldAgeHours() end)
    return ok and type(h) == "number" and h or 0
end

local function realMs()
    return getTimestampMs and getTimestampMs() or 0
end

function Card.keyOf(item)
    return "machine:" .. tostring(item:getID())
end

-- Whether Status of `item` for player `playerNum` is a card: the machine on
-- the ground, no controller.
function Card.wanted(playerNum, item)
    if not Machines.isPlaced(item) then return false end
    if JoypadState ~= nil and JoypadState.players ~= nil and JoypadState.players[(playerNum or 0) + 1] then
        return false
    end
    return true
end

-- Whether a card last filled at `atHours` (game) and `atMs` (real) asks
-- again now: ten game minutes on, and MIN_MS of real time; a clock that
-- went back asks again.
function Card.due(atHours, atMs, nowHours, nowMs)
    if nowMs < atMs or nowHours < atHours then return true end
    return nowHours - atHours >= Card.REFRESH_HOURS and nowMs - atMs >= Card.MIN_MS
end

-- Whether a refresh's reply keeps the card: only a status of a machine
-- still on the ground. Out of reach, gone, or any other refusal closes it.
function Card.keeps(reply)
    return type(reply) == "table" and reply.ok == true and reply.placed ~= false
end

-- A source machine's name in this client's language, from its item type.
function Card.nameOf(source)
    local ok, name = pcall(getItemNameFromFullType, source.type)
    if ok and type(name) == "string" and name ~= "" then return name end
    return tostring(source.machine)
end

-- The machines this one takes from, as the authority found them within two
-- tiles, nearest first: "Takes from: Lye Leacher, 1 tile away. Finished: lye
-- ready for a reactor". Machines of one type in one state share a line,
-- with their number and the nearest one's distance: "Takes from: 3 x
-- Fermentation Vessel, nearest 1 tile away. Working" (the owner's choice,
-- 2026-11-15, after RT-SP launch 442 showed four lines for four vessels).
-- The number stands before the name as it is, since an item's name has no
-- plural to ask the game for.
function Card.sourceLines(reply)
    local lines = {}
    if type(reply.sources) ~= "table" then return lines end
    local groups, byKey = {}, {}
    for _, s in ipairs(reply.sources) do
        local id = tostring(s.type) .. "|" .. tostring(s.state)
        local tiles = math.floor((tonumber(s.tiles) or 0) + 0.5)
        local g = byKey[id]
        if g == nil then
            g = { first = s, count = 0, tiles = tiles }
            byKey[id] = g
            groups[#groups + 1] = g
        end
        g.count = g.count + 1
        if tiles < g.tiles then g.tiles = tiles end
    end
    for _, g in ipairs(groups) do
        local s = g.first
        local def = TLG.Registry.get("machine", s.machine)
        local kind = def and def.kind
        local key = "IGUI_TLG_MachineState_" .. tostring(s.state)
        local own = getText(key .. "_" .. tostring(kind))
        local state = own ~= key .. "_" .. tostring(kind) and own or getText(key)
        if g.count == 1 then
            lines[#lines + 1] = getText(g.tiles == 1 and "IGUI_TLG_Card_Source1" or "IGUI_TLG_Card_Source",
                Card.nameOf(s), tostring(g.tiles), state)
        else
            lines[#lines + 1] = getText(g.tiles == 1 and "IGUI_TLG_Card_Sources1" or "IGUI_TLG_Card_Sources",
                tostring(g.count), Card.nameOf(s), tostring(g.tiles), state)
        end
    end
    if #lines == 0 and reply.takesFrom then lines[1] = getText("IGUI_TLG_Card_NoSource") end
    return lines
end

-- The card's text: Status, then the machines it takes from.
function Card.text(reply)
    local text = TLG.UI.MachineMenu.describe(reply)
    for _, line in ipairs(Card.sourceLines(reply)) do text = text .. " <LINE> " .. line end
    return text
end

-- The reach the authority gives a machine's commands (MachineHandlers,
-- machineState).
Card.REACH = 2.5

-- Whether the card's player is still within reach of its machine, as this
-- client sees both. False only when both squares are known and too far
-- apart: where one cannot be read, the authority's answer decides at the
-- next refresh.
function Card.inReach(st)
    local ok, far = pcall(function()
        local here = getSpecificPlayer(st.playerNum or 0):getSquare()
        local there = Machines.square(st.item)
        return here ~= nil and there ~= nil and here:DistToProper(there) > Card.REACH
    end)
    return not (ok and far == true)
end

local function forget(key) Card.open[key] = nil end

-- At each frame a card is shown: when it is due, ask again. A machine no
-- longer on the ground closes its card without asking.
function Card.onUpdate(key)
    local st = Card.open[key]
    if st == nil then return Say.closeCard(key) end
    if not Card.inReach(st) then return Say.closeCard(key) end
    local placed = false
    pcall(function() placed = Machines.isPlaced(st.item) end)
    if not placed then return Say.closeCard(key) end
    if st.asked or not Card.due(st.atHours, st.atMs, gameHours(), realMs()) then return end
    st.asked = true
    -- Its own answer: a refusal closes the card and says nothing.
    TLG.Net.request("machine.status", { target = st.ref }, function(reply)
        local now = Card.open[key]
        if now == nil then return end
        now.asked = false
        if not Card.keeps(reply) then return Say.closeCard(key) end
        Card.fill(key, reply, true)
    end)
end

function Card.fill(key, reply, behind)
    local st = Card.open[key]
    if st == nil then return end
    st.atHours, st.atMs = gameHours(), realMs()
    return Say.card(key, st.title, Card.text(reply), Card.onUpdate, forget, behind)
end

-- Shows the Status `reply` of `item` as its card, a new one or the one
-- already open. Returns "card", or "window" where the game has no card.
function Card.show(item, ref, reply, playerNum)
    local key = Card.keyOf(item)
    Card.open[key] = Card.open[key] or {}
    local st = Card.open[key]
    st.item, st.ref, st.title, st.asked, st.playerNum = item, ref, item:getDisplayName(), false, playerNum or 0
    local how = Card.fill(key, reply)
    if how ~= "card" then Card.open[key] = nil end
    return how
end

return Card
