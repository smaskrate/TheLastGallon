-- World state adapter: fuel-history epoch, policy, calendar origin, recorded
-- climate and balance-profile history, persisted once in global ModData
-- "TLG_World" by the authority (server or single-player host).
--
-- What only the authority uses (the seed, the next id, the placed machines'
-- squares, today's climate sums) is kept apart, in the server store: the
-- modData of a server-side global object system (server/TLG/Server/
-- WorldStore.lua), saved with the world and never sent to clients. Global
-- ModData is not private: the server answers ModData.request for any key
-- with the whole table (GlobalModData.receiveRequest, 42.21), so "TLG_World"
-- gave every client the squares of every running machine (audit 2026-11-05,
-- V-03). Until the store is attached (it loads after OnInitGlobalModData),
-- and wherever it is missing, those fields stay in "TLG_World" as before.
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
-- Fields of the world record kept in the server store.
World.SERVER_FIELDS = { "seed", "nextId", "machineSites", "climateAcc" }
local SERVER_FIELD = {}
for _, f in ipairs(World.SERVER_FIELDS) do SERVER_FIELD[f] = true end
World.SERVER_STORE_SCHEMA = 1
local CUMULATIVE = { 0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334 }

-- The table holding the server fields: the attached server store, else the
-- world record itself (before the store loads, in tests, and on clients,
-- whose copy no longer carries them).
function World.server()
    return World.store or ModData.getOrCreate(World.KEY)
end

-- Attaches the server store's table and moves the server fields out of the
-- world record (a world created this session, or a save from before the
-- store). The store's own values win; the next id never goes back. Also
-- returns whether the store was lost (a new seed was drawn).
function World.attachServerStore(tbl)
    local md = ModData.getOrCreate(World.KEY)
    if tbl.v == nil then tbl.v = World.SERVER_STORE_SCHEMA end
    local moved = {}
    for _, f in ipairs(World.SERVER_FIELDS) do
        local old = md[f]
        if old ~= nil then
            if tbl[f] == nil then
                tbl[f] = old
            elseif f == "nextId" and type(old) == "number" and old > tbl[f] then
                tbl[f] = old
            end
            md[f] = nil
            moved[#moved + 1] = f
        end
    end
    World.store = tbl
    -- A world whose store was lost: a new seed keeps new ids distinct.
    local regenerated = md.v ~= nil and tbl.seed == nil
    if regenerated then
        tbl.seed = Rng.hash(tostring(getWorld():getWorld()) .. ":" .. tostring(getTimestamp()))
        tbl.nextId = tbl.nextId or 1
        TLG.Log.warn("world record: server store had no seed; new seed %d", tbl.seed)
    end
    if #moved > 0 then
        TLG.Log.info("world record: %s moved to the server store", table.concat(moved, ","))
        World.transmit()
    end
    return tbl, regenerated
end

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
    local srv = World.server()
    for k, v in pairs(rec) do
        if SERVER_FIELD[k] then srv[k] = v else md[k] = v end
    end
    md.calendar = calendarOrigin()
    md.climateLog = {}
    md.modVersion = TLG.VERSION
    md.createdAsNewGame = newGame and true or false
    -- Diesel chassis (Vehicles.DIESEL_FAMILIES) exist from the start of a
    -- new game only: a save that had the mod or the game before keeps its
    -- vehicles on petrol (D-036). Never set afterwards.
    md.dieselVehicles = newGame and true or false
    TLG.Log.info("world fuel history created: policy=%s seed=%d epoch=%.2f installedAt=%.2f newGame=%s", md.policy,
        srv.seed, md.epoch, md.installedAt, tostring(isNewGame))
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

-- Records today's mean temperature/humidity as the running mean of the hourly
-- readings (called every game hour on the authority). getDayMeanTemperature()
-- is the season curve (BC: currentDay.season.getDayMeanTemperature), so cold
-- snaps and heat waves never reached machines or fuel ageing (RT-SP run 15);
-- getTemperature() is the air temperature with the weather.
-- The same readings give the day means of the game's room air without heat
-- sources (Climate.roomAir from the hour's air, lagged daylight and grid
-- power), which machines in rooms use while their area is not loaded (D-021).
function World.recordClimate()
    if not World.isAuthority() then return end
    local md = World.get()
    if md.v == nil then return end
    local env = World.env()
    local day = env:dayIndex(World.now())
    local cm = getClimateManager()
    local t = cm:getTemperature()
    local rh = cm:getHumidity()
    if rh > 1 then rh = rh / 100 end
    local dl, power = nil, nil
    pcall(function() dl = cm:getClimateValuesCopy():getDayLightLagged() end)
    pcall(function() power = getWorld():isHydroPowerOn() end)
    if (type(dl) ~= "number" or power == nil) and not World.roomWarned then
        World.roomWarned = true
        TLG.Log.warn("room air: daylight=%s power=%s unreadable; using daylight 0.5, no power", tostring(dl),
            tostring(power))
    end
    if type(dl) ~= "number" then dl = Climate.ROOM_DAYLIGHT end
    local srv = World.server()
    local acc = srv.climateAcc
    if acc == nil or acc.day ~= day then acc = { day = day, n = 0, t = 0, rh = 0 } end
    acc.n, acc.t, acc.rh = acc.n + 1, acc.t + t, acc.rh + rh
    -- Counted apart: an accumulator from before D-021 has no room sums yet.
    acc.rn = (acc.rn or 0) + 1
    acc.r0 = (acc.r0 or 0) + Climate.roomAir(t, false, dl, power == true)
    acc.r1 = (acc.r1 or 0) + Climate.roomAir(t, true, dl, power == true)
    srv.climateAcc = acc
    Climate.record(md.climateLog, day, acc.t / acc.n, acc.rh / acc.n, World.CLIMATE_KEEP_DAYS, acc.r0 / acc.rn,
        acc.r1 / acc.rn)
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

-- Authority only (allocates from the server store's next id).
function World.newId(prefix)
    return WorldInit.newId(World.server(), prefix)
end

-- The world's seed (server store) with its public policy fields, as
-- WorldInit's seeding reads them from one table.
function World.facts()
    local md, srv = World.get(), World.server()
    if srv == md and md.seed ~= nil then return md end
    return { seed = srv.seed or 1, epoch = md.epoch, policy = md.policy, installedAt = md.installedAt,
        transitionHours = md.transitionHours }
end

-- Baseline condition for fuel discovered without TLG state.
function World.baseline(key, spec)
    return WorldInit.baseline(World.facts(), World.env(), key, spec, World.now())
end

return World
