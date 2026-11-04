require "support/fixtures"
require "TLG/Content/Production"
require "TLG/Util/Rng"
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

T.case("sites: segments sort the notes' hours once and give every day exactly its own mean", function()
    local r = TLG.Rng.new(TEST_SEED or 20261030)
    local e = env(coldLog(-5, 9.1, 7.2))
    local days = 0
    for trial = 1, 40 do
        local site = { room = r:int(0, 1) == 1, z = r:int(0, 1), temps = {}, fires = {}, from = r:int(0, 40) }
        for h = 0, 24 * 12 do
            local roll = r:next()
            if roll < 0.5 then site.temps[h] = -5 + 30 * r:next() end
            if roll > 0.3 and r:next() < 0.5 then
                local kind = r:int(1, 4)
                if kind == 1 then
                    site.fires[h] = false
                elseif kind == 2 then
                    site.fires[h] = { t = h + r:next(), f = r:int(0, 600), x = r:int(-6, 6), y = r:int(-6, 6),
                        r = r:int(0, 1) == 1, c = 35 }
                elseif kind == 3 then
                    site.fires[h] = { t = h + r:next(), f = r:int(1, 200), x = r:int(-3, 3), y = r:int(-3, 3), r = false,
                        c = 25, rad = 3 }
                else
                    site.fires[h] = { t = h + r:next(), f = r:int(30, 400), x = r:int(-9, 9), y = r:int(-9, 9), r = false,
                        c = 35, k = "campfire", rmax = 10 }
                end
            end
        end
        if trial % 5 == 0 then site.fires = nil end
        local t0, t1 = r:int(0, 100) + r:next(), 24 * 12 - r:int(0, 50) + r:next()
        for _, seg in ipairs(e:segments(t0, t1, "sheltered", site)) do
            local day = e:dayIndex(seg.t0)
            local alone = { room = site.room, z = site.z, temps = site.temps, fires = site.fires, from = site.from }
            T.eq(seg.tempC, (e:siteDayMean(day, alone, t1)), string.format("trial %d, day %d", trial, day))
            days = days + 1
        end
    end
    T.ok(days > 300, "days compared: " .. days)
end)

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

-- D-022: a fire noted warming the machine keeps doing so while it is away.
local function fire(t, f, rad) return { t = t, f = f, x = 1, y = 2, r = true, c = rad and 25 or 35, rad = rad } end

T.case("fires: a fireplace's radius follows its fuel, its warmth the game's formula", function()
    T.eq(Climate.fireRadius(0), 1); T.eq(Climate.fireRadius(5), 1); T.eq(Climate.fireRadius(20), 3)
    T.eq(Climate.fireRadius(40), 5); T.eq(Climate.fireRadius(59), 7); T.eq(Climate.fireRadius(60), 8)
    T.eq(Climate.fireRadius(480), 8); T.eq(Climate.fireRadius(-3), 1)
    T.near(Climate.warmed(8, 1, 0, 8, true, 35), 8 + 0.875 * 20, 1e-9, "a cold room: 35 - 7 at the source")
    T.near(Climate.warmed(8, 0, 2, 8, false, 35), 8 + 0.75 * 12, 1e-9, "a source outdoors: 35 - 15")
    T.near(Climate.warmed(8, 1, 2, 8, true, 35), 8 + (1 - math.sqrt(5) / 8) * 20, 1e-9)
    T.eq(Climate.warmed(8, 8, 0, 8, true, 35), 8, "from the radius on: nothing")
    T.near(Climate.warmed(8, 1, 0, 3, true, 25), 8 + (2 / 3) * 10, 1e-9, "a barbecue: 25 C, radius 3")
    T.eq(Climate.warmed(45, 1, 0, 8, true, 35), 45, "never below the air")
    T.eq(Climate.noteRadius(fire(0, 10, 3), 10), 3, "a barbecue's radius does not follow its fuel")
    T.eq(Climate.noteRadius(fire(0, 10), 10), 2, "a fireplace's does: 1 + 7 x 10 / 60")
end)

T.case("fires: unread hours after a note keep the fire's warmth while its fuel lasts", function()
    local e = env(coldLog(-3, 7.7))
    local temps = {}
    for s = 0, 9 do temps[s] = 22 end
    local w8, w4 = Climate.warmed(7.7, 1, 2, 8, true, 35), Climate.warmed(7.7, 1, 2, 4, true, 35)
    -- Left at 10.5 with 330 min: warm from the noted hour's start to 16.0.
    local left = { room = true, z = 0, temps = temps, fires = { [9] = fire(9.5, 360), [10] = fire(10.5, 330) } }
    T.near(e:siteDayMean(0, left, 24), (10 * 22 + 6 * w8 + 8 * 7.7) / 24, 1e-9)
    -- 90 min at 10.0: hour 10 at radius 8; hour 11 starts with 30 min left, radius 4, for half an hour.
    local low = { room = true, z = 0, temps = temps, fires = { [10] = fire(10, 90) } }
    T.near(e:siteDayMean(0, low, 24), (10 * 22 + w8 + 0.5 * w4 + 12.5 * 7.7) / 24, 1e-9)
    -- A later note without a fire ends the credit; a reading wins over it.
    local out = { room = true, z = 0, temps = { [11] = 15 }, fires = { [10] = fire(10.2, 480), [12] = false } }
    for s = 0, 9 do out.temps[s] = 22 end
    T.near(e:siteDayMean(0, out, 24), (10 * 22 + w8 + 15 + 12 * 7.7) / 24, 1e-9)
    local none = { room = true, z = 0, temps = temps }
    T.near(e:siteDayMean(0, none, 24), (10 * 22 + 14 * 7.7) / 24, 1e-9, "no notes: the base")
    local bbq = { room = true, z = 0, temps = temps, fires = { [10] = fire(10, 120, 3) } }
    T.near(e:siteDayMean(0, bbq, 24), (10 * 22 + 2 * Climate.warmed(7.7, 1, 2, 3, true, 25) + 12 * 7.7) / 24, 1e-9)
    local unread = { room = true, z = 0, fires = { [0] = fire(0, 120) } }
    T.near(e:siteDayMean(0, unread, 24), (2 * w8 + 22 * 7.7) / 24, 1e-9, "left before the first reading was filed")
end)

T.case("fires: the credit runs across midnight; the hour in progress keeps its stand-in", function()
    local e = env(coldLog(-3, 7.7))
    local temps = {}
    for s = 0, 21 do temps[s] = 22 end
    local w8, w4 = Climate.warmed(7.7, 1, 2, 8, true, 35), Climate.warmed(7.7, 1, 2, 4, true, 35)
    local site = { room = true, z = 0, temps = temps, fires = { [22] = fire(22.5, 240) } }
    T.near(e:siteDayMean(0, site, 24), (22 * 22 + 2 * w8) / 24, 1e-9, "hours 22-23 warm")
    T.near(e:siteDayMean(1, site, 48), (2 * w8 + 0.5 * w4 + 21.5 * 7.7) / 24, 1e-9, "until 26.5 next day")
    local stand = { room = true, z = 0, temps = { [23] = 28 }, fires = { [24] = fire(24.1, 480) } }
    T.near(e:siteDayMean(1, stand, 24.5), 28, 1e-9, "the hour just ended stands in for the hour in progress")
    local notes = { [3] = fire(3, 60), [5] = false, [8] = fire(8, 60) }
    Climate.pruneNotes(notes, 6)
    T.ok(notes[3] == nil and notes[5] == false and notes[8] ~= nil, "the latest note before the cut stays")
end)

T.case("fires: the credit can carry a January batch at full rate through an absence", function()
    local e = env(coldLog(-3, 7.7))
    local temps = {}
    for s = 0, 11 do temps[s] = 22 end
    local warm = batch({ room = true, z = 0 }, temps)
    warm.fires = { [12] = fire(12.5, 450) }
    T.eq(Process.site(warm).fires[12].f, 450)
    local w = Process.advance(warm, 24, e)
    T.eq(w.state, "Processing")
    T.near(w.stageDone, 23, 1e-9, "12 h read and 8 h credited at 22 C: full rate after the preparation")
    local cold = Process.advance(batch({ room = true, z = 0 }, temps), 24, e)
    T.near(cold.stageDone, 23 * 0.4, 1e-9, "without the note the day mean is 14.9 C")
end)

T.case("fires: a campfire's radius follows its fuel, truncated, up to 10 tiles outdoors and 18 inside", function()
    T.eq(Climate.campfireRadius(361.5, 10), 10); T.eq(Climate.campfireRadius(360, 10), 10)
    T.eq(Climate.campfireRadius(359, 10), 9, "9.97 truncated")
    T.eq(Climate.campfireRadius(199, 10), 5, "RT-SP run 34: 5 at 199 minutes")
    T.eq(Climate.campfireRadius(108, 10), 3); T.eq(Climate.campfireRadius(107, 10), 2)
    T.eq(Climate.campfireRadius(100, 10), 2, "run 34: 2 at 100 minutes"); T.eq(Climate.campfireRadius(30, 10), 2)
    T.eq(Climate.campfireRadius(0, 10), 2); T.eq(Climate.campfireRadius(-4, 10), 2)
    T.eq(Climate.campfireRadius(480, 18), 18); T.eq(Climate.campfireRadius(200, 18), 10)
    T.eq(Climate.campfireRadius(200), 5, "outdoors unless told otherwise")
    local camp = { t = 0, f = 199, x = -1, y = 0, r = false, c = 35, k = "campfire", rmax = 10 }
    T.eq(Climate.noteRadius(camp, 199), 5)
    camp.rmax = 18
    T.eq(Climate.noteRadius(camp, 199), 9, "inside: 18 x 199 / 360 = 9.95")
end)

T.case("fires: a campfire's credit shrinks with its fuel, hour by hour", function()
    local e = env(coldLog(-3, 7.7))
    local temps = {}
    for s = 0, 9 do temps[s] = 18 end
    -- Outdoors, the base is the day's -3 C. Noted at 10.0 with 300 minutes:
    -- warm until 15.0, each hour at the radius of the fuel left at its start
    -- (300, 240, 180, 120 and 60 minutes: 8, 6, 5, 3 and 2 tiles).
    local note = { t = 10, f = 300, x = -1, y = 0, r = false, c = 35, k = "campfire", rmax = 10 }
    local site = { room = false, z = 0, temps = temps, fires = { [10] = note } }
    local function w(radius) return Climate.warmed(-3, -1, 0, radius, false, 35) end
    T.near(e:siteDayMean(0, site, 24), (10 * 18 + w(8) + w(6) + w(5) + w(3) + w(2) + 9 * -3) / 24, 1e-9)
    T.ok(w(2) < w(8), "a low fire warms the tile beside it less")
end)
