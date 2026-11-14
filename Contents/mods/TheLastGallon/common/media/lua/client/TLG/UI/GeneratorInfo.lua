-- The game's Generator Info window says how much fuel and never which. A
-- line is added above its text with the fuel this generator takes ("Runs
-- on: ...", as the game's own first line is "Fuel: 40%"), by its
-- profile (Integration/Generators.profile: a diesel one, a converted one).
--
-- The window asks for its text at every frame (SRC
-- client/ISUI/ISGeneratorInfoWindow.lua, update -> getRichText(object,
-- true)), so the line of the last generator asked about is kept for
-- REFRESH_MS. The profile is read from this client's copy of the
-- generator's mod data; on a server's client that copy is NOT RUN. On any
-- error the game's text is returned as it is.
-- RT-SP launch 419: the text for the Diesel Generator and the red one, read
-- through getRichText. The window on screen NOT RUN.
require "ISUI/ISGeneratorInfoWindow"
require "TLG/Integration/Generators"

TLG.UI = TLG.UI or {}
TLG.UI.GeneratorInfo = TLG.UI.GeneratorInfo or {}
local Info = TLG.UI.GeneratorInfo

Info.REFRESH_MS = 2000

-- "Runs on: diesel or biodiesel", nil for a profile without a text.
function Info.line(generator)
    local profile = TLG.Integration.Generators.profile(generator)
    local key = "IGUI_TLG_GenFuel_" .. tostring(profile)
    local what = getText(key)
    if what == key then return nil end
    return getText("IGUI_TLG_GenFuel", what)
end

local function now()
    return getTimestampMs and getTimestampMs() or 0
end

function Info.cached(generator)
    local at = now()
    if Info.last == nil or Info.last.generator ~= generator or at - Info.last.at >= Info.REFRESH_MS
        or at < Info.last.at then
        local ok, line = pcall(Info.line, generator)
        Info.last = { generator = generator, at = at, line = ok and line or nil }
    end
    return Info.last.line
end

-- The game's text with the line above it; `displayStats` false is the short
-- text of the generator's tooltip, left as it is.
function Info.text(original, generator, displayStats)
    local text = original(generator, displayStats)
    if not displayStats or generator == nil then return text end
    local line = Info.cached(generator)
    if line == nil then return text end
    return line .. " <LINE> " .. text
end

function Info.install()
    if Info.original ~= nil or ISGeneratorInfoWindow == nil or ISGeneratorInfoWindow.getRichText == nil then return end
    Info.original = ISGeneratorInfoWindow.getRichText
    ISGeneratorInfoWindow.getRichText = function(object, displayStats)
        return Info.text(Info.original, object, displayStats)
    end
end

Info.install()

return Info
