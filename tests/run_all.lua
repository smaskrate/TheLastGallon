-- Entry point for the domain test suite (run through tools/run-tests.ps1).
-- __TLG_ARGS[1] = optional case-name filter, __TLG_ARGS[2] = optional seed.
loadstring(__TLG_SOURCES["support/prelude"], "support/prelude")()
loadstring(__TLG_SOURCES["support/testlib"], "support/testlib")()

local filter = __TLG_ARGS[1]
if filter == "" or filter == "all" then
    filter = nil
end
TEST_SEED = tonumber(__TLG_ARGS[2] or "") or 20261030

local modules = {}
for name in pairs(__TLG_SOURCES) do
    if string.find(name, "^domain/test_") or string.find(name, "^authority/test_") or
        string.find(name, "^integration/test_") then
        modules[#modules + 1] = name
    end
end
table.sort(modules)

for _, name in ipairs(modules) do
    require(name)
end

local ok = T.run(filter)
print(string.format("modules=%d cases=%d passed=%d failed=%d assertions=%d seed=%d",
    #modules, T.passed + T.failed, T.passed, T.failed, T.assertions, TEST_SEED))
if not ok then
    __TLG_EXIT_CODE = 1
end
