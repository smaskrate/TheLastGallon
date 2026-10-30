-- World state adapter: fuel-history epoch, policy, calendar origin, recorded
-- climate and balance-profile history, persisted once in global ModData
-- "TLG_World" by the authority (server or single-player host).
require "TLG/Domain/WorldInit"
require "TLG/Domain/Climate"
require "TLG/Domain/Balance"
require "TLG/Util/Rng"

TLG.Integration = TLG.Integration or {}
TLG.World = TLG.World or {}
local World = TLG.World
local WorldInit, Climate, Balance, Rng = TLG.Domain.WorldInit, TLG.Domain.Climate, TLG.Domain.Balance, TLG.Rng

World.KEY = "TLG_World"
World.CLIMATE_KEEP_DAYS = 450
local CUMULATIVE = { 0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334 }

function World.isAuthority()
    return isServer() or not isClient()
end

function World.now()
    return getGameTime():getWorldAgeHours()
end

-- Calendar origin of world hour 0, derived from the current calendar so it
-- does not depend on how the start date was configured.
local function calendarOrigin()
    local gt = getGameTime()
    local doy = CUMULATIVE[gt:getMonth() + 1] + gt:getDay() + 1
    local hourOfYear = (doy - 1) * 24 + gt:getTimeOfDay() - gt:getWorldAgeHours()
    local d = TLG.Num.mod(hourOfYear, 365 * 24)
    return { dayOfYear = math.floor(d / 24) + 1, hourOfDay = TLG.Num.mod(d, 24) }
end

local function sandboxPolicy()
    local opt = SandboxVars and SandboxVars.TheLastGallon and SandboxVars.TheLastGallon.ExistingSavePolicy
    local map = { [1] = "transition", [2] = "world_age", [3] = "install_now" }
    return map[opt or 1] or "transition"
end

local function sandboxProfile()
    local opt = SandboxVars and SandboxVars.TheLastGallon and SandboxVars.TheLastGallon.CampaignSpeed
    local map = { [1] = "default", [2] = "slow", [3] = "fast", [4] = "off" }
    return Balance.profile(map[opt or 1] or "default")
end

local function sandboxTransitionHours()
    local days = SandboxVars and SandboxVars.TheLastGallon and SandboxVars.TheLastGallon.TransitionDays
    return (days or 30) * 24
end

-- Creates the world record exactly once (authority only). `isNewGame` comes
-- from OnInitGlobalModData; new worlds report world age 2.0 h at first boot
-- (RT-DS), so world age alone cannot tell a new world from an old one.
function World.ensure(isNewGame)
    local md = ModData.getOrCreate(World.KEY)
    if md.v ~= nil then return md end
    if not World.isAuthority() then return md end
    local now = World.now()
    local newGame = isNewGame
    if newGame == nil then newGame = getGameTime():getHoursSurvived() < 0.5 end
    local policy = newGame and "new_world" or sandboxPolicy()
    local profile = sandboxProfile()
    local rec = WorldInit.create({
        seed = Rng.hash(tostring(getWorld():getWorld()) .. ":" .. tostring(getTimestamp())),
        policy = policy, now = now, transitionHours = sandboxTransitionHours(),
        balanceHistory = { { from = -1e12, id = profile.id, agingMul = profile.agingMul,
            breathingMul = profile.breathingMul, microbialMul = profile.microbialMul } },
    })
    for k, v in pairs(rec) do md[k] = v end
    md.calendar = calendarOrigin()
    md.climateLog = {}
    md.modVersion = TLG.VERSION
    md.createdAsNewGame = newGame and true or false
    TLG.Log.info("world fuel history created: policy=%s seed=%d epoch=%.2f installedAt=%.2f newGame=%s", md.policy,
        md.seed, md.epoch, md.installedAt, tostring(isNewGame))
    World.transmit()
    return md
end

-- Multiplayer: the server owns the record; clients receive a copy for UI
-- previews (replication NOT RUN, engine-capabilities G07/G08).
function World.transmit()
    if isServer() then ModData.transmit(World.KEY) end
end

function World.requestFromServer()
    if isClient() then ModData.request(World.KEY) end
end

function World.onReceive(key, data)
    if key == World.KEY and isClient() and type(data) == "table" then
        ModData.add(World.KEY, data)
    end
end

function World.get()
    return ModData.getOrCreate(World.KEY)
end

-- Climate instance used for every advance on this world.
function World.env()
    local md = World.get()
    return Climate.new(md.calendar, md.climateLog or {}, md.balanceHistory)
end

-- Records today's mean temperature/humidity (server, once per hour is fine).
function World.recordClimate()
    if not World.isAuthority() then return end
    local md = World.get()
    if md.v == nil then return end
    local env = World.env()
    local day = env:dayIndex(World.now())
    local cm = getClimateManager()
    local t = cm:getDayMeanTemperature()
    local rh = cm:getHumidity()
    if rh > 1 then rh = rh / 100 end
    Climate.record(md.climateLog, day, t, rh, World.CLIMATE_KEEP_DAYS)
end

-- A changed campaign speed applies from now on; the past keeps its profile.
function World.applyProfileChange()
    if not World.isAuthority() then return end
    local md = World.get()
    if md.v == nil then return end
    local profile = sandboxProfile()
    local last = md.balanceHistory[#md.balanceHistory]
    if last.id ~= profile.id then
        md.balanceHistory[#md.balanceHistory + 1] = { from = World.now(), id = profile.id, agingMul = profile.agingMul,
            breathingMul = profile.breathingMul, microbialMul = profile.microbialMul }
        TLG.Log.info("campaign profile %s -> %s from %.2f", last.id, profile.id, World.now())
    end
end

function World.newId(prefix)
    return WorldInit.newId(World.get(), prefix)
end

-- Baseline condition for fuel discovered without TLG state.
function World.baseline(key, spec)
    return WorldInit.baseline(World.get(), World.env(), key, spec, World.now())
end

return World
