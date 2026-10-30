-- Environment segments for aging and unloaded simulation.
--
-- Time is world hours (getWorldAgeHours). Segments are aligned to world day
-- boundaries so that any split of an interval yields the same per-day values;
-- together with closed-form aging this makes one large advance equal to many
-- small ones. Recorded daily climate (written by the server while the world
-- runs) overrides the deterministic seasonal model; the current temperature is
-- never applied to the past.
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

Climate.__index = Climate

-- origin = { dayOfYear = 1..365 at world hour 0, hourOfDay = 0..24 }.
-- log    = optional { [dayIndex] = { t = tempC, rh = humidity } } recorded days.
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

function Climate:profileAt(t)
    local current = self.history[1]
    for i = 2, #self.history do
        if self.history[i].from <= t then current = self.history[i] else break end
    end
    return current
end

-- Contiguous segments covering [t0, t1] split at day and profile boundaries.
function Climate:segments(t0, t1, thermal)
    local out = {}
    if t1 <= t0 then return out end
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
        local temp, rh = self:storageTemp(day, thermal)
        out[#out + 1] = { t0 = t, t1 = stop, dt = stop - t, tempC = temp, rh = rh, profile = self:profileAt(t) }
        t = stop
    end
    return out
end

-- Daily record helper for the server's climate logger (bounded ring).
function Climate.record(log, day, tempC, rh, keepDays)
    log[day] = { t = tempC, rh = rh }
    local cutoff = day - (keepDays or 450)
    for _, k in ipairs(TLG.Tables.sortedKeys(log)) do
        if k < cutoff then log[k] = nil else break end
    end
end

return Climate
