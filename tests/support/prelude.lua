-- Test-only environment shim for the Kahlua runner.
-- Implements PZ-style `require "TLG/Domain/Fuel"` over __TLG_SOURCES, which the
-- runner fills from the runtime package roots (shared, client, server) and tests/.
local loaded = {}

function require(name)
    name = string.gsub(name, "\\", "/")
    name = string.gsub(name, "%.lua$", "")
    local cached = loaded[name]
    if cached ~= nil then
        return cached
    end
    local src = __TLG_SOURCES[name]
    if src == nil then
        error("module not found: " .. name)
    end
    local fn, err = loadstring(src, name)
    if not fn then
        error("compile error in " .. name .. ": " .. tostring(err))
    end
    loaded[name] = true
    local result = fn()
    if result ~= nil then
        loaded[name] = result
    end
    return loaded[name]
end

-- Mirrors in-game globals the domain must never depend on. Adapters may; the
-- domain test suite runs without them to prove the domain stays pure.
isServer = nil
isClient = nil
getGameTime = nil
