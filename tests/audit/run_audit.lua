-- Entry point for the security audit tests (tools\run-tests.ps1 -Entry tests/audit/run_audit.lua).
-- Kept apart from run_all.lua: these tests define game-object mocks that the
-- domain suite must never see.
loadstring(__TLG_SOURCES["support/prelude"], "support/prelude")()
loadstring(__TLG_SOURCES["support/testlib"], "support/testlib")()

local filter = __TLG_ARGS[1]
if filter == "" or filter == "all" then filter = nil end
TEST_SEED = tonumber(__TLG_ARGS[2] or "") or 20261030

require("audit/test_audit")
require("audit/test_gas_handlers")

local ok = T.run(filter)
print(string.format("audit cases=%d passed=%d failed=%d assertions=%d", T.passed + T.failed, T.passed, T.failed,
    T.assertions))
if not ok then __TLG_EXIT_CODE = 1 end
