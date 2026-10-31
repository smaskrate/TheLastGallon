-- Environment segments for aging and unloaded simulation.
--
-- Time is world hours (getWorldAgeHours). Segments are aligned to world day
-- boundaries so that any split of an interval yields the same per-day values;
-- together with closed-form aging this makes one large advance equal to many
-- small ones while the log does not change between them. Recorded daily
-- climate (written by the server while the world runs) overrides the
-- deterministic seasonal model; a reading is never applied to an earlier day.
-- Today's record is the running mean of today's readings so far
-- (World.recordClimate, D-020) and changes until midnight, so an advance made
-- during the day uses the mean so far for today's hours and is not redone
-- later: a machine read through the day and one caught up after midnight can
-- differ slightly for that day.
--
-- Machine sites (D-021): a placed machine's day temperature is the mean air
-- temperature at its tile over the day's hours of the batch, the game's own
-- hourly reading where one was taken there (rooms, grid power, fires) and the
-- day's unheated value for its site elsewhere.
require "TLG/Util/Num"
require "TLG/Util/Tables"

TLG.Domain = TLG.Domain or {}
TLG.Domain.Climate = TLG.Domain.Climate or {}
local Climate = TLG.Domain.Climate
local Num = TLG.Num

-- Monthly mean outdoor temperatures (C) and relative humidity for the
-- default Kentucky setting; game-design approximation (docs/balance.md).
Climate.MONTH_TEMP = { 1, 3, 8, 14, 19, 24, 26, 25, 21, 14, 8, 3 }
Climate.MONTH_RH = { 0.70, 0.68, 0.64, 0.62, 0.68, 0.70, 0.72, 0.72, 0.72, 0.68, 0.70, 0.72 }
Climate.GROUND_MEAN = 13
Climate.GROUND_AMPLITUDE = 3
Climate.SHELTER_TARGET = 16
Climate.DAYS_IN_MONTH = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
-- The game's room air (BC 42.21 ClimateManager.getAirTemperatureForSquare):
-- rooms tend to 22 C; the grid holds them there while it is on.
Climate.ROOM_TARGET = 22
-- Lagged daylight (0..1) assumed for days recorded without room means.
Climate.ROOM_DAYLIGHT = 0.5

Climate.__index = Climate

-- origin = { dayOfYear = 1..365 at world hour 0, hourOfDay = 0..24 }.
-- log    = optional { [dayIndex] = { t = tempC, rh = humidity, r0, r1 } } recorded
--          days (r0/r1: room air means, see Climate.record).
-- history = optional ordered list of balance-profile changes:
--           { { from = hour, agingMul =, breathingMul =, microbialMul =, id = } }
function Climate.new(origin, log, history)
    local o = setmetatable({}, Climate)
    o.origin = origin or { dayOfYear = 190, hourOfDay = 9 }
    o.log = log or {}
    o.history = history or { { from = -math.huge, id = "default", agingMul = 1, breathingMul = 1, microbialMul = 1 } }
    return o
end

-- World day index containing world hour t, counted from the calendar midnight
-- before world start.
function Climate:dayIndex(t)
    return math.floor((t + self.origin.hourOfDay) / 24)
end

function Climate:dayStart(day)
    return day * 24 - self.origin.hourOfDay
end

function Climate:dayOfYear(day)
    return Num.mod(self.origin.dayOfYear - 1 + day, 365) + 1
end

-- Linear interpolation between mid-month values, wrapping around the year.
local function seasonal(doy, table12)
    local mids, acc = {}, 0
    for m = 1, 12 do
        mids[m] = acc + Climate.DAYS_IN_MONTH[m] / 2
        acc = acc + Climate.DAYS_IN_MONTH[m]
    end
    local points = { { mids[12] - 365, table12[12] } }
    for m = 1, 12 do points[#points + 1] = { mids[m], table12[m] } end
    points[#points + 1] = { mids[1] + 365, table12[1] }
    return Num.interp(points, doy - 0.5)
end

function Climate:outdoor(day)
    local rec = self.log[day]
    if rec ~= nil then
        return rec.t, rec.rh
    end
    local doy = self:dayOfYear(day)
    return seasonal(doy, Climate.MONTH_TEMP), seasonal(doy, Climate.MONTH_RH)
end

-- Storage temperature from outdoor temperature and the profile's exposure.
function Climate:storageTemp(day, thermal)
    local out, rh = self:outdoor(day)
    if thermal == "ground" then
        local doy = self:dayOfYear(day)
        local phase = math.cos((doy - 200) / 365 * 2 * math.pi)
        return Climate.GROUND_MEAN + Climate.GROUND_AMPLITUDE * phase, rh * 0.8
    elseif thermal == "sheltered" then
        return (out + Climate.SHELTER_TARGET) / 2, rh * 0.9
    end
    return out, rh
end

-- Air in a room with no heat source, as the game computes it for a tile
-- (BC 42.21 ClimateManager.getAirTemperatureForSquare, square in a room, no
-- vehicle): grid power holds 22 C; otherwise the room moves the outdoor air a
-- share k = 0.4 + 0.2 x lagged daylight towards 22 C, 0.85 k above the
-- ground floor. Above 22 C the ground floor takes 0.85 k and upper floors
-- k + 0.2 x the lagged night, which 42.21 sets to the same daylight value.
function Climate.roomAir(outC, upper, dayLight, power)
    local target = Climate.ROOM_TARGET
    if power then return target end
    local k = 0.4 + 0.2 * dayLight
    if outC <= target then
        local diff = target - outC
        if upper then diff = diff * 0.85 end
        return outC + diff * k
    end
    local diff = outC - target
    if upper then return outC - diff * (k + 0.2 * dayLight) end
    return outC - diff * 0.85 * k
end

-- A site's day temperature without heat sources: outdoors the recorded mean;
-- in a room the day's recorded room mean for its floor, or for days recorded
-- without one the room formula on the day mean (daylight 0.5, no power).
-- site = { room = bool, z = floor }.
function Climate:siteBase(day, site)
    local out, rh = self:outdoor(day)
    if not site.room then return out, rh end
    local upper = (site.z or 0) >= 1
    local rec = self.log[day]
    local recorded = rec and (upper and rec.r1 or rec.r0)
    if recorded ~= nil then return recorded, rh * 0.9 end
    return Climate.roomAir(out, upper, Climate.ROOM_DAYLIGHT, false), rh * 0.9
end

-- Mean air temperature at a site over the day's hours of the batch, up to
-- `upto`: readings where the site was sampled (site.temps[s] covers world hours
-- [s, s + 1)), the site's base elsewhere. site.from is the batch start; hours
-- before it do not count, so a batch started late in the day is not diluted.
function Climate:siteDayMean(day, site, upto)
    local base, rh = self:siteBase(day, site)
    local from = math.max(self:dayStart(day), site.from or -math.huge)
    local to = math.min(self:dayStart(day + 1), upto or math.huge)
    local span = to - from
    local temps = site.temps
    if temps == nil or span <= 1e-9 then return base, rh end
    local sum, covered = 0, 0
    for s = math.floor(from), math.ceil(to) - 1 do
        local v = temps[s]
        if v ~= nil then
            local overlap = math.min(to, s + 1) - math.max(from, s)
            if overlap > 0 then sum, covered = sum + overlap * v, covered + overlap end
        end
    end
    return (sum + (span - covered) * base) / span, rh
end

-- Drops readings for hours before `before` (already advanced past).
function Climate.pruneSlots(temps, before)
    if temps == nil then return end
    local old = {}
    for s in pairs(temps) do
        if s < before then old[#old + 1] = s end
    end
    for _, s in ipairs(old) do temps[s] = nil end
end

function Climate:profileAt(t)
    local current = self.history[1]
    for i = 2, #self.history do
        if self.history[i].from <= t then current = self.history[i] else break end
    end
    return current
end

-- Contiguous segments covering [t0, t1] split at day and profile boundaries.
-- With a site (see siteDayMean) its day temperature replaces the thermal
-- exposure; every segment of a day gets the same value.
function Climate:segments(t0, t1, thermal, site)
    local out = {}
    if t1 <= t0 then return out end
    local siteDays = {}
    local cuts = {}
    for i = 2, #self.history do
        local f = self.history[i].from
        if f > t0 and f < t1 then cuts[#cuts + 1] = f end
    end
    local t = t0
    local ci = 1
    while t < t1 do
        local day = self:dayIndex(t)
        local stop = math.min(self:dayStart(day + 1), t1)
        while ci <= #cuts and cuts[ci] <= t do ci = ci + 1 end
        if ci <= #cuts and cuts[ci] < stop then stop = cuts[ci] end
        if stop <= t then stop = math.min(t + 1e-9, t1) end
        local temp, rh
        if site ~= nil then
            local d = siteDays[day]
            if d == nil then
                d = { self:siteDayMean(day, site, t1) }
                siteDays[day] = d
            end
            temp, rh = d[1], d[2]
        else
            temp, rh = self:storageTemp(day, thermal)
        end
        out[#out + 1] = { t0 = t, t1 = stop, dt = stop - t, tempC = temp, rh = rh, profile = self:profileAt(t) }
        t = stop
    end
    return out
end

-- Daily record helper for the server's climate logger (bounded ring).
-- room0/room1: optional day means of the game's room air without heat
-- sources on the ground and upper floors (Climate.roomAir, hourly inputs).
function Climate.record(log, day, tempC, rh, keepDays, room0, room1)
    log[day] = { t = tempC, rh = rh, r0 = room0, r1 = room1 }
    local cutoff = day - (keepDays or 450)
    for _, k in ipairs(TLG.Tables.sortedKeys(log)) do
        if k < cutoff then log[k] = nil else break end
    end
end

return Climate
