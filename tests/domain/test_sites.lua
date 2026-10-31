require "support/fixtures"
require "TLG/Content/Production"
local Climate, Process = TLG.Domain.Climate, TLG.Domain.Process

-- Origin at midnight so day d covers world hours [24 d, 24 d + 24).
local function env(log) return Climate.new({ dayOfYear = 15, hourOfDay = 0 }, log or {}) end

local function coldLog(tempC, room0, room1)
    local log = {}
    for d = -2, 40 do log[d] = { t = tempC, rh = 0.7, r0 = room0, r1 = room1 } end
    return log
end

local function batch(site, temps)
    local f = Process.new({ id = "F1", machine = "fermenter_barrel", t = 0 })
    f = Process.load(f, "ethanol_ferment", { sugar_eq = 6, water = 30 }).proc
    f = Process.start(f, 0).proc
    f.site, f.temps = site, temps
    return f
end

T.case("sites: room air follows the game's formula", function()
    T.eq(Climate.roomAir(-5, false, 0.5, true), 22, "grid power holds 22 C")
    T.eq(Climate.roomAir(30, true, 0.5, true), 22)
    T.near(Climate.roomAir(-5, false, 0.5, false), 8.5, 1e-9)
    T.near(Climate.roomAir(-5, false, 0, false), 5.8, 1e-9, "night: k = 0.4")
    T.near(Climate.roomAir(-5, false, 1, false), 11.2, 1e-9, "day: k = 0.6")
    T.near(Climate.roomAir(-5, true, 0.5, false), 6.475, 1e-9, "upper floors: 0.85 of the pull")
    T.near(Climate.roomAir(30, false, 0.5, false), 26.6, 1e-9)
    T.near(Climate.roomAir(30, true, 0.5, false), 25.2, 1e-9)
    T.near(Climate.roomAir(22, false, 0.5, false), 22, 1e-9)
end)

T.case("sites: outdoors takes the day mean, a room its recorded room mean or the formula", function()
    local e = env(coldLog(-5))
    local t, rh = e:siteBase(3, { room = false, z = 0 })
    T.near(t, -5, 1e-12); T.near(rh, 0.7, 1e-12)
    t, rh = e:siteBase(3, { room = true, z = 0 })
    T.near(t, 8.5, 1e-9, "no room mean recorded: daylight 0.5, no power"); T.near(rh, 0.63, 1e-12)
    T.near(e:siteBase(3, { room = true, z = 1 }), 6.475, 1e-9)
    local r = env(coldLog(-5, 9.1, 7.2))
    T.near(r:siteBase(3, { room = true, z = 0 }), 9.1, 1e-12)
    T.near(r:siteBase(3, { room = true, z = 2 }), 7.2, 1e-12)
    T.near(r:siteBase(3, { room = false, z = 2 }), -5, 1e-12, "outdoors ignores the floor")
end)

T.case("sites: readings cover their hour, the base fills the rest, hours before the batch do not count", function()
    local e = env(coldLog(-5))
    local out = { room = false, z = 0, temps = {} }
    for s = 0, 11 do out.temps[s] = 25 end
    T.near(e:siteDayMean(0, out, 24), 10, 1e-9, "12 warm hours, 12 at the base")
    T.near(e:siteDayMean(0, out, 6), 25, 1e-9, "so far today: only warm hours")
    local late = { room = false, z = 0, temps = {}, from = 12 }
    for s = 12, 23 do late.temps[s] = 25 end
    T.near(e:siteDayMean(0, late, 24), 25, 1e-9, "a batch started at noon is not diluted")
    T.near(e:siteDayMean(1, late, 48), -5, 1e-9, "no readings next day: the base")
    local part = { room = false, z = 0, temps = { [12] = 20, [13] = 30 }, from = 12.5 }
    T.near(e:siteDayMean(0, part, 14), 40 / 1.5, 1e-9, "partial hours weigh by overlap")
    T.near(e:siteDayMean(0, { room = false, z = 0, from = 30 }, 24), -5, 1e-9, "batch not started that day")
end)

T.case("sites: the hour in progress takes the previous hour's reading", function()
    local e = env(coldLog(-5))
    local warm = { room = true, z = 0, temps = { [22] = 28, [23] = 28 } }
    T.near(e:siteDayMean(1, warm, 24.5), 28, 1e-9, "just after midnight: yesterday's last hour stands in")
    T.near(e:siteDayMean(0, warm, 24), 28 * 2 / 24 + 8.5 * 22 / 24, 1e-9, "a whole day: no stand-in")
    local gap = { room = true, z = 0, temps = { [22] = 28 } }
    T.near(e:siteDayMean(1, gap, 24.5), 8.5, 1e-9, "only the hour just ended stands in")
    local filed = { room = true, z = 0, temps = { [23] = 28, [24] = 10 } }
    T.near(e:siteDayMean(1, filed, 24.5), 10, 1e-9, "a reading for the hour itself wins")
    local started = { room = true, z = 0, temps = {}, from = 24.25 }
    T.near(e:siteDayMean(1, started, 24.5), 8.5, 1e-9, "no reading before the batch: the base")
end)

T.case("sites: a January fermenter outdoors stops while the same batch in a room runs slowly", function()
    local e = env(coldLog(-3))
    local outside = Process.advance(batch({ room = false, z = 0 }), 48, e)
    T.eq(outside.state, "Paused"); T.eq(outside.pause, "too_cold")
    T.near(outside.pausedFor, 47, 1e-9, "after the 1 h preparation")
    local room = Process.advance(batch({ room = true, z = 0 }), 48, e)
    T.eq(room.state, "Processing", "room: -3 + 25 x 0.5 = 9.5 C")
    T.near(room.stageDone, 47 * 0.4, 1e-9)
    local nosite = Process.advance(batch(nil), 48, e)
    T.ok(Process.site(nosite) == nil)
    T.eq(nosite.pause, "too_cold", "no site: the definition's sheltered exposure, (-3 + 16) / 2")
end)

T.case("sites: readings taken by a fire make the day warm enough to run at full rate", function()
    local e = env(coldLog(-3))
    local temps = {}
    for s = 24, 47 do temps[s] = 26 end
    local f = Process.advance(batch({ room = true, z = 0 }, temps), 48, e)
    T.eq(f.state, "Processing")
    T.near(f.stageDone, 23 * 0.4 + 24, 1e-9, "day 0 at the room base (0.4), day 1 warmed (full rate)")
end)

T.case("sites: advancing in day steps equals one advance over the same days", function()
    local e = env(coldLog(-3))
    local temps = {}
    for s = 0, 95 do temps[s] = (s % 24 < 10) and 30 or ((s % 7 == 0) and 5 or 12) end
    local whole = Process.advance(batch({ room = true, z = 0 }, temps), 96, e)
    local stepped = batch({ room = true, z = 0 }, temps)
    for t = 24, 96, 24 do stepped = Process.advance(stepped, t, e) end
    T.eq(whole.state, stepped.state)
    T.near(whole.stageDone, stepped.stageDone, 1e-9)
    T.near(whole.pausedFor, stepped.pausedFor, 1e-9)
end)

T.case("sites: the batch start is kept, consumed readings can be dropped, room means are recorded", function()
    local f = batch({ room = true, z = 0 }, { [1] = 3, [5] = 4, [30] = 5 })
    f.startedAt = 2
    local site = Process.site(f)
    T.eq(site.from, 2); T.eq(site.room, true); T.eq(site.z, 0)
    Climate.pruneSlots(f.temps, 5)
    T.ok(f.temps[1] == nil and f.temps[5] == 4 and f.temps[30] == 5)
    T.eq(Process.start(Process.load(Process.new({ id = "F2", machine = "fermenter_barrel", t = 7 }), "ethanol_ferment",
        { sugar_eq = 6, water = 30 }).proc, 7).proc.startedAt, 7)
    local log = {}
    Climate.record(log, 10, -2, 0.7, 450, 9.6, 7.9)
    T.eq(log[10].r0, 9.6); T.eq(log[10].r1, 7.9)
    Climate.record(log, 11, -2, 0.7, 450)
    T.ok(log[11].r0 == nil, "room means are optional")
end)
