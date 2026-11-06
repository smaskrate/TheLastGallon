-- Bootstrap: content, world record, adapter hooks, climate logging.
require "TLG/Core"
require "TLG/Content/Fuels"
require "TLG/Content/Storage"
require "TLG/Content/Consumers"
require "TLG/Content/Production"
require "TLG/Content/Feedstocks"
require "TLG/Content/Conversions"
require "TLG/Content/Energy"
require "TLG/Content/Biodiesel"
require "TLG/Content/Biogas"
require "TLG/Content/WoodGas"
require "TLG/Content/Propane"
require "TLG/Integration/ConversionDevices"
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
-- Machine pickup and put-down (D-015). Registered here: the domain tests load
-- Machines.lua without the game's Events, so it cannot require Boot. It is
-- loaded by the time the game starts, as the hourly readings below rely on
-- (RT-SP runs 17-26).
Boot.addInstaller("machines", function()
    if TLG.Integration.Machines then TLG.Integration.Machines.install() end
end)

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

Events.OnInitGlobalModData.Add(function(isNewGame)
    TLG.World.ensure(isNewGame)
    TLG.World.applyProfileChange()
end)
Events.OnGameStart.Add(Boot.install)
Events.OnGameStart.Add(TLG.World.requestFromServer)
if Events.OnReceiveGlobalModData then Events.OnReceiveGlobalModData.Add(TLG.World.onReceive) end
if Events.OnServerStarted then Events.OnServerStarted.Add(Boot.install) end
Events.EveryHours.Add(function()
    local ok, err = pcall(TLG.World.recordClimate)
    if not ok then TLG.Log.error("climate log: %s", tostring(err)) end
    -- After the climate record: the machines' hourly air readings (D-021).
    local machines = TLG.Integration.Machines
    if machines then
        ok, err = pcall(machines.sampleSites)
        if not ok then TLG.Log.error("machine air readings: %s", tostring(err)) end
    end
end)
-- The fire warming each machine, noted every ten minutes (D-022).
Events.EveryTenMinutes.Add(function()
    local machines = TLG.Integration.Machines
    if machines then
        local ok, err = pcall(machines.observeFires)
        if not ok then TLG.Log.error("machine fire notes: %s", tostring(err)) end
        -- The machines in characters' hands (Machines.censusHands).
        ok, err = pcall(machines.censusHands)
        if not ok then TLG.Log.error("machine hands: %s", tostring(err)) end
    end
end)

return Boot
