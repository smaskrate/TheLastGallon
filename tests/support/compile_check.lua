-- Compiles (without running) every Lua file exposed by the runner roots with
-- the game's own Kahlua compiler; reports syntax errors.
local names = {}
for name in pairs(__TLG_SOURCES) do names[#names + 1] = name end
table.sort(names)
local bad = 0
for _, name in ipairs(names) do
    -- A UTF-8 byte-order mark makes the Kahlua compiler fail (seen in tests).
    local first = string.byte(__TLG_SOURCES[name], 1)
    if first == 65279 or first == 239 then
        bad = bad + 1
        print("BOM " .. name)
    end
    local fn, err = loadstring(__TLG_SOURCES[name], name)
    if not fn then
        bad = bad + 1
        print("SYNTAX " .. name .. ": " .. tostring(err))
    end
end
print(string.format("compiled=%d errors=%d", #names, bad))
if bad > 0 then __TLG_EXIT_CODE = 1 end
