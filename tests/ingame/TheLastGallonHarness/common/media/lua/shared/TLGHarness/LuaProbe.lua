-- In-game counterpart of tests/support/runtime_probe.lua: records which Lua
-- features the game's Kahlua environment exposes (with PZ globals loaded).
TLGH = TLGH or {}

function TLGH.runLuaProbe(report)
    report:line("## Lua runtime (in-game environment)")
    local function obs(name, fn) report:observe("lua." .. name, fn) end
    obs("_VERSION", function() return _VERSION end)
    obs("type(next)", function() return type(next) end)
    obs("type(math.random)", function() return type(math.random) end)
    obs("type(table.unpack)", function() return type(table.unpack) end)
    obs("type(unpack)", function() return type(unpack) end)
    obs("type(require)", function() return type(require) end)
    obs("type(loadstring)", function() return type(loadstring) end)
    obs("type(getfenv)", function() return type(getfenv) end)
    obs("type(os)", function() return type(os) end)
    obs("type(os.time)", function() return type(os and os.time) end)
    obs("type(io)", function() return type(io) end)
    obs("-7 % 3", function() return -7 % 3 end)
    obs("error(table) type", function()
        local _, e = pcall(error, { code = 1 })
        return type(e)
    end)
    obs("string.format('%s', nil)", function()
        local ok = pcall(string.format, "%s", nil)
        return ok and "accepted" or "rejected"
    end)
    obs("require returns module table", function()
        local r = require "TLGHarness/Report"
        return tostring(r == TLGH.Report) .. " (" .. type(r) .. ")"
    end)
    obs("tostring(1e20)", function() return tostring(1e20) end)
    obs("deep recursion 3000", function()
        local function r(n) if n == 0 then return 0 end; return 1 + r(n - 1) end
        return r(3000)
    end)
end
