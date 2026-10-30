-- Producer models (spec §12 "Generation models").
--
-- Pure functions of explicit inputs: the caller (adapter) supplies clock,
-- weather and site values; the dispatch receives the resulting available
-- power per interval and never recomputes it, so a split interval sees the
-- same inputs as the whole one. Generation.steps provides a fixed time grid
-- for callers that need time-varying inputs (solar) to stay split-invariant.
--
-- Definitions are MachineDefinitions with energy = solar | wind | hydro |
-- fueled (TLG/Content/Energy). Producer nodes carry installation values:
--   cond      0..1 equipment condition (dirt, damage, wear)
--   exposure  0..1 site factor: shading/orientation (solar), shelter (wind
--             speed multiplier)
--   flowM3s, headM   authored hydro site (default: definition values)
--
-- solar   ratedKW (STC, 1 kW/m2) x derate x clear-sky plane-of-array
--         irradiance x cloud factor x (1 - snow) x exposure x cond.
--         Sun position from day of year, clock hour and latitude (Cooper
--         declination); panel tilted at the latitude facing south, so
--         cos(incidence) = cos(declination) cos(hour angle); Meinel air-mass
--         attenuation 1.353 x 0.7^(AM^0.678) kW/m2 plus 10% diffuse; cloud
--         factor 1 - 0.75 c^3.4 (Kasten-Czeplak). Day length and season follow
--         from the sun position.
-- wind    cubic power curve between cut-in and rated speed, rated output up
--         to cut-out, zero above (furled); always within [0, ratedKW x cond].
-- hydro   9.81 kW per (m3/s x m) x efficiency x authored flow x head
--         (optional monthly flow multipliers), capped at ratedKW, x cond.
-- fueled  affine fuel curve F(P) = idle + slope x P (kW of fuel energy) with
--         F(rated) = rated / efficiency and F(0) = idleFraction x F(rated).
--         Recovered heat = heatRecovery x (F - P); the rest is loss, so
--         electric + recovered heat + loss = fuel energy by construction.
--         Fuel units = fuel kWh x 3.6 / energyMJ (L, Nm3 or kg).
require "TLG/Registry/Registry"
require "TLG/Util/Num"
require "TLG/Util/Tables"
require "TLG/Domain/Climate"

TLG.Domain = TLG.Domain or {}
TLG.Domain.Energy = TLG.Domain.Energy or {}
TLG.Domain.Energy.Generation = TLG.Domain.Energy.Generation or {}
local Gen = TLG.Domain.Energy.Generation
local Registry, Num, Climate = TLG.Registry, TLG.Num, TLG.Domain.Climate

Gen.TYPES = { solar = true, wind = true, hydro = true, fueled = true }
Gen.OWNERS = { tlg = true, native = true }
-- Muldraugh / Louisville area, degrees north (design value).
Gen.LATITUDE = 37.9
-- Clock hour of solar noon. Kentucky summer time puts it near 13:30; the
-- adapter may pass ctx.solarNoon from the game's own dawn/dusk instead.
Gen.SOLAR_NOON = 13.0
Gen.MJ_PER_KWH = 3.6
-- Hydraulic power of water: rho g = 1000 kg/m3 x 9.81 m/s2 -> 9.81 kW per
-- (m3/s of flow x m of head).
Gen.WATER_KW = 9.81

local function positive(v) return Num.isFinite(v) and v > 0 end
local function nonneg(v) return Num.isFinite(v) and v >= 0 end
local function unit(v) return Num.isFinite(v) and v >= 0 and v <= 1 end

function Gen.problems(def)
    local out = {}
    local function bad(msg) out[#out + 1] = msg end
    if not positive(def.ratedKW) then bad("producer needs positive ratedKW") end
    if def.energy == "solar" then
        if not (positive(def.derate) and def.derate <= 1) then bad("solar derate must be in (0,1]") end
    elseif def.energy == "wind" then
        if not (nonneg(def.cutInMS) and positive(def.ratedMS) and positive(def.cutOutMS) and
            def.cutInMS < def.ratedMS and def.ratedMS < def.cutOutMS) then
            bad("wind needs 0 <= cutInMS < ratedMS < cutOutMS")
        end
    elseif def.energy == "hydro" then
        if not nonneg(def.flowM3s) or not nonneg(def.headM) then bad("hydro needs flowM3s and headM >= 0") end
        if not (positive(def.efficiency) and def.efficiency <= 1) then bad("hydro efficiency must be in (0,1]") end
        if def.monthly ~= nil then
            local ok = type(def.monthly) == "table" and #def.monthly == 12
            for m = 1, 12 do
                if ok and not nonneg(def.monthly[m]) then ok = false end
            end
            if not ok then bad("hydro monthly needs 12 non-negative multipliers") end
        end
    elseif def.energy == "fueled" then
        if not (positive(def.efficiency) and def.efficiency <= 0.6) then bad("fueled efficiency must be in (0,0.6]") end
        if def.idleFraction ~= nil and not (nonneg(def.idleFraction) and def.idleFraction < 1) then
            bad("idleFraction must be in [0,1)")
        end
        if def.heatRecovery ~= nil and not (nonneg(def.heatRecovery) and def.heatRecovery < 1) then
            bad("heatRecovery must be in [0,1)")
        end
        if def.consumer ~= nil and Registry.get("consumer", def.consumer) == nil then
            bad("unknown consumer profile " .. tostring(def.consumer))
        end
        if def.owner ~= nil and not Gen.OWNERS[def.owner] then bad("owner must be tlg or native") end
    end
    return out
end

Registry.addValidator("machine", function(def, problem)
    if not Gen.TYPES[def.energy] then return end
    for _, msg in ipairs(Gen.problems(def)) do problem(msg) end
end)

function Gen.def(id)
    local def = Registry.get("machine", id)
    if def ~= nil and Gen.TYPES[def.energy] then return def end
    return nil
end

-- Producer node helper.
function Gen.producer(o)
    return {
        kind = "producer", id = o.id, def = o.def, cond = o.cond, exposure = o.exposure,
        mode = o.mode, running = o.running, runFor = o.runFor, policy = o.policy,
        flowM3s = o.flowM3s, headM = o.headM,
    }
end

------------------------------------------------------------------------------
-- Solar
------------------------------------------------------------------------------

-- Sun position: sine of the altitude, cosine of the incidence angle on a
-- south-facing panel tilted at the latitude, declination (radians).
function Gen.sun(dayOfYear, hourOfDay, latitude, noon)
    local decl = math.rad(23.44) * math.sin(2 * math.pi * (284 + dayOfYear) / 365)
    local h = math.rad(15 * (hourOfDay - (noon or Gen.SOLAR_NOON)))
    local lat = math.rad(latitude or Gen.LATITUDE)
    local sinAlt = math.sin(lat) * math.sin(decl) + math.cos(lat) * math.cos(decl) * math.cos(h)
    local cosInc = math.cos(decl) * math.cos(h)
    return sinAlt, cosInc, decl
end

-- Hours of daylight (sun above the horizon).
function Gen.dayLength(dayOfYear, latitude)
    local _, _, decl = Gen.sun(dayOfYear, 12, latitude, 12)
    local x = -math.tan(math.rad(latitude or Gen.LATITUDE)) * math.tan(decl)
    return 2 * math.deg(math.acos(Num.clamp(x, -1, 1))) / 15
end

-- Clear-sky plane-of-array irradiance relative to 1 kW/m2, within [0, 1].
function Gen.clearSky(sinAlt, cosInc)
    if sinAlt <= 0 then return 0 end
    local airMass = 1 / math.max(sinAlt, 0.03)
    local beam = 1.353 * 0.7 ^ (airMass ^ 0.678)
    return Num.clamp(beam * math.max(0, cosInc) + 0.1 * beam * sinAlt, 0, 1)
end

-- Kasten-Czeplak cloud attenuation; cloud cover 0..1.
function Gen.cloudFactor(cloud)
    return 1 - 0.75 * (cloud ^ 3.4)
end

local function siteFactor(node, key)
    local v = node[key]
    if v == nil then return 1 end
    return v
end

function Gen.solarKW(def, node, ctx)
    local sinAlt, cosInc = Gen.sun(ctx.dayOfYear, ctx.hourOfDay, ctx.latitude, ctx.solarNoon)
    local poa = Gen.clearSky(sinAlt, cosInc)
    local kw = def.ratedKW * def.derate * poa * Gen.cloudFactor(ctx.cloud or 0) * (1 - (ctx.snow or 0))
    return Num.clamp(kw * siteFactor(node, "exposure") * siteFactor(node, "cond"), 0, def.ratedKW)
end

------------------------------------------------------------------------------
-- Wind and hydro
------------------------------------------------------------------------------

function Gen.windKW(def, node, ctx)
    local v = ctx.windMS * siteFactor(node, "exposure")
    local c = siteFactor(node, "cond")
    if v < def.cutInMS or v >= def.cutOutMS then return 0 end
    if v >= def.ratedMS then return def.ratedKW * c end
    local a3, b3 = def.cutInMS ^ 3, def.ratedMS ^ 3
    return Num.clamp(def.ratedKW * (v ^ 3 - a3) / (b3 - a3), 0, def.ratedKW) * c
end

function Gen.hydroKW(def, node, ctx)
    local q = node.flowM3s == nil and def.flowM3s or node.flowM3s
    local h = node.headM == nil and def.headM or node.headM
    local mult = 1
    if def.monthly ~= nil and ctx.month ~= nil then mult = def.monthly[ctx.month] end
    local kw = Gen.WATER_KW * q * mult * h * def.efficiency
    return math.min(def.ratedKW, kw) * siteFactor(node, "cond")
end

-- Available power of a renewable producer for one interval.
-- ctx = { dayOfYear, hourOfDay, month, cloud, snow, windMS, latitude, solarNoon }
-- Returns kW or nil, reason.
function Gen.availableKW(def, node, ctx)
    if def == nil or not Gen.TYPES[def.energy] or def.energy == "fueled" then return nil, "not_renewable" end
    node, ctx = node or {}, ctx or {}
    for _, key in ipairs({ "cond", "exposure" }) do
        if node[key] ~= nil and not unit(node[key]) then return nil, "invalid_producer" end
    end
    if def.energy == "solar" then
        if not (Num.isFinite(ctx.dayOfYear) and ctx.dayOfYear >= 1 and ctx.dayOfYear <= 366) then return nil, "invalid_time" end
        if not (Num.isFinite(ctx.hourOfDay) and ctx.hourOfDay >= 0 and ctx.hourOfDay <= 24) then return nil, "invalid_time" end
        if ctx.latitude ~= nil and not (Num.isFinite(ctx.latitude) and math.abs(ctx.latitude) <= 90) then return nil, "invalid_site" end
        if ctx.solarNoon ~= nil and not (Num.isFinite(ctx.solarNoon) and ctx.solarNoon >= 0 and ctx.solarNoon <= 24) then
            return nil, "invalid_time"
        end
        if ctx.cloud ~= nil and not unit(ctx.cloud) then return nil, "invalid_weather" end
        if ctx.snow ~= nil and not unit(ctx.snow) then return nil, "invalid_weather" end
        return Gen.solarKW(def, node, ctx)
    elseif def.energy == "wind" then
        if not nonneg(ctx.windMS) then return nil, "invalid_weather" end
        return Gen.windKW(def, node, ctx)
    end
    if node.flowM3s ~= nil and not nonneg(node.flowM3s) then return nil, "invalid_site" end
    if node.headM ~= nil and not nonneg(node.headM) then return nil, "invalid_site" end
    if ctx.month ~= nil and not (Num.isFinite(ctx.month) and ctx.month == math.floor(ctx.month) and
        ctx.month >= 1 and ctx.month <= 12) then
        return nil, "invalid_time"
    end
    return Gen.hydroKW(def, node, ctx)
end

------------------------------------------------------------------------------
-- Fueled generation
------------------------------------------------------------------------------

-- Fuel curve: returns idle fuel power (kW) and slope (kW fuel per kW out).
function Gen.curve(def)
    local full = def.ratedKW / def.efficiency
    local idle = (def.idleFraction or 0) * full
    return idle, (full - idle) / def.ratedKW
end

function Gen.fuelKW(def, outputKW)
    local idle, slope = Gen.curve(def)
    return idle + slope * outputKW
end

-- Recoverable heat (kW) for electrical output p at fuel power f.
function Gen.recoverableKW(def, p, f)
    return (def.heatRecovery or 0) * (f - p)
end

function Gen.units(fuelKWh, energyMJ)
    return fuelKWh * Gen.MJ_PER_KWH / energyMJ
end

function Gen.fuelEnergyKWh(units, energyMJ)
    return units * energyMJ / Gen.MJ_PER_KWH
end

-- Steady-state budget of a fueled producer at output p kW for `hours`.
-- electricKWh + heatKWh + lossKWh = fuelKWh = fuelUnits x energyMJ / 3.6.
function Gen.budget(def, p, hours, energyMJ)
    if def == nil or def.energy ~= "fueled" then return { ok = false, reason = "not_fueled" } end
    if not (nonneg(p) and p <= def.ratedKW) then return { ok = false, reason = "invalid_power" } end
    if not nonneg(hours) then return { ok = false, reason = "invalid_interval" } end
    if not positive(energyMJ) then return { ok = false, reason = "invalid_energy" } end
    local f = Gen.fuelKW(def, p)
    local heat = Gen.recoverableKW(def, p, f)
    local fuelKWh = f * hours
    return {
        ok = true, fuelKWh = fuelKWh, fuelMJ = fuelKWh * Gen.MJ_PER_KWH, fuelUnits = Gen.units(fuelKWh, energyMJ),
        electricKWh = p * hours, heatKWh = heat * hours, lossKWh = (f - p - heat) * hours,
    }
end

------------------------------------------------------------------------------
-- Time grid for piecewise-constant inputs
------------------------------------------------------------------------------

local function monthOf(doy)
    local acc = 0
    for m = 1, 12 do
        acc = acc + Climate.DAYS_IN_MONTH[m]
        if doy <= acc then return m end
    end
    return 12
end

-- Number of grid cells touched by [t0, t1] (for bounding catch-up work).
function Gen.stepCount(t0, t1, stepHours)
    if not (t1 > t0) then return 0 end
    return math.ceil(t1 / stepHours) - math.floor(t0 / stepHours)
end

-- Cells are [k*step, (k+1)*step) in world hours. Each returned piece is
-- clipped to [t0, t1] and carries the calendar values of its cell midpoint,
-- so splitting an interval anywhere yields the same inputs per cell.
-- origin = { dayOfYear, hourOfDay } at world hour 0 (TLG.Domain.Climate).
function Gen.steps(t0, t1, origin, stepHours)
    origin = origin or { dayOfYear = 190, hourOfDay = 9 }
    stepHours = stepHours or 1
    local clock = Climate.new(origin)
    local out = {}
    if not (t1 > t0) then return out end
    local k = math.floor(t0 / stepHours)
    local t = t0
    while t < t1 do
        local c0, c1 = k * stepHours, (k + 1) * stepHours
        if c1 > t then
            local e = math.min(c1, t1)
            local mid = (c0 + c1) / 2
            local day = clock:dayIndex(mid)
            local doy = clock:dayOfYear(day)
            out[#out + 1] = {
                t0 = t, t1 = e, c0 = c0, c1 = c1, mid = mid, day = day, dayOfYear = doy, month = monthOf(doy),
                hourOfDay = Num.mod(mid + origin.hourOfDay, 24),
            }
            t = e
        end
        k = k + 1
    end
    return out
end

return Gen
