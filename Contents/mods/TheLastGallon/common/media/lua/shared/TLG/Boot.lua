-- Bootstrap: content, world record, adapter hooks, climate logging.
require "TLG/Core"
require "TLG/Content/Fuels"
require "TLG/Content/Storage"
require "TLG/Content/Consumers"
require "TLG/Content/Production"
require "TLG/Content/Feedstocks"
require "TLG/Integration/World"
require "TLG/Integration/Containers"

TLG.Boot = TLG.Boot or {}
local Boot = TLG.Boot
Boot.installers = Boot.installers or {}

-- Adapters register an installer; all run once per Lua state.
function Boot.addInstaller(name, fn)
    Boot.installers[#Boot.installers + 1] = { name = name, fn = fn }
end

Boot.addInstaller("containers", TLG.Integration.Containers.install)

local installed = false
function Boot.install()
    if installed then return end
    installed = true
    local problems = TLG.Registry.validate()
    if #problems > 0 then
        for _, p in ipairs(problems) do TLG.Log.error("content: %s", p) end
    end
    for _, inst in ipairs(Boot.installers) do
        local ok, err = pcall(inst.fn)
        if not ok then TLG.Log.error("installer %s failed: %s", inst.name, tostring(err)) end
    end
    local version = getCore():getVersion()
    if string.sub(version, 1, #TLG.TESTED_GAME_VERSION) ~= TLG.TESTED_GAME_VERSION then
        TLG.Log.warn("untested game version %s (tested: %s %s)", version, TLG.TESTED_GAME_VERSION,
            TLG.TESTED_GAME_REVISION)
        TLG.untestedVersion = version
    end
    TLG.Log.info("The Last Gallon %s ready (server=%s client=%s)", TLG.VERSION, tostring(isServer()), tostring(isClient()))
end

Events.OnInitGlobalModData.Add(function()
    TLG.World.ensure()
    TLG.World.applyProfileChange()
end)
Events.OnGameStart.Add(Boot.install)
if Events.OnServerStarted then Events.OnServerStarted.Add(Boot.install) end
Events.EveryHours.Add(function()
    local ok, err = pcall(TLG.World.recordClimate)
    if not ok then TLG.Log.error("climate log: %s", tostring(err)) end
end)

return Boot
