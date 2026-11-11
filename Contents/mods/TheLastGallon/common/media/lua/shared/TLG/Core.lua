-- Root namespace, versions and logging for The Last Gallon.
-- Every TLG module registers itself under the global TLG table and also
-- returns its table, so callers work whether or not `require` returns values.
TLG = TLG or {}

TLG.MOD_ID = "TheLastGallon"
TLG.VERSION = "0.3.0"

-- Persistent/versioned contracts (see docs/migrations.md).
TLG.SCHEMA = {
    supply = 1,     -- liquid/gas supply records
    world = 1,      -- world fuel-history epoch and init policy
    process = 1,    -- production processes
    project = 1,    -- workshop conversion projects
    network = 1,    -- energy networks
    adapter = 1,    -- adapter definition set
}

-- The only build this package has been tested on (docs/environment.md).
TLG.TESTED_GAME_VERSION = "42.22.2"
TLG.TESTED_GAME_REVISION = "3d39148846"

TLG.Log = TLG.Log or {}
local Log = TLG.Log
Log.debugEnabled = false

local function emit(level, fmt, ...)
    local ok, msg = pcall(string.format, fmt, ...)
    if not ok then
        msg = tostring(fmt)
    end
    print("[TLG][" .. level .. "] " .. msg)
end

function Log.info(fmt, ...) emit("INFO", fmt, ...) end
function Log.warn(fmt, ...) emit("WARN", fmt, ...) end
function Log.error(fmt, ...) emit("ERROR", fmt, ...) end
function Log.debug(fmt, ...)
    if Log.debugEnabled then emit("DEBUG", fmt, ...) end
end

return TLG
