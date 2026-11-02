require "support/fixtures"
require "TLG/Integration/Machines"
local Machines, World, Process = TLG.Integration.Machines, TLG.World, TLG.Domain.Process

-- Stand-ins for the game calls the machine site adapter makes: global ModData,
-- the clock, the cell's squares, the air temperature per square and outdoors,
-- the daylight, grid power and the fire objects' classes. Installed for one
-- case and removed again (the domain suite runs without them).
local GLOBALS = { "ModData", "getGameTime", "getCell", "getClimateManager", "isServer", "isClient", "getWorld",
    "instanceof" }

local function fakeGame(now)
    local saved = {}
    for _, k in ipairs(GLOBALS) do saved[k] = _G[k] end
    local g = { now = now, squares = {}, store = {}, outC = -3, dl = 0.5, power = false }
    ModData = { getOrCreate = function(k)
        g.store[k] = g.store[k] or {}
        return g.store[k]
    end }
    local clock = {}
    function clock:getWorldAgeHours() return g.now end
    getGameTime = function() return clock end
    local cell = {}
    function cell:getGridSquare(x, y, z) return g.squares[x .. "," .. y .. "," .. z] end
    getCell = function() return cell end
    local cm, values, world = {}, {}, {}
    function cm:getAirTemperatureForSquare(sq) return sq.air end
    function cm:getTemperature() return g.outC end
    function values:getDayLightLagged() return g.dl end
    function cm:getClimateValuesCopy() return values end
    getClimateManager = function() return cm end
    function world:isHydroPowerOn() return g.power end
    getWorld = function() return world end
    instanceof = function(o, class) return type(o) == "table" and o.class == class end
    isServer = function() return false end
    isClient = function() return false end
    local md = World.get()
    md.v, md.calendar, md.climateLog = 1, { dayOfYear = 15, hourOfDay = 0 }, { [0] = { t = -3, rh = 0.7 } }
    function g.restore()
        for _, k in ipairs(GLOBALS) do _G[k] = saved[k] end
    end
    return g
end

-- A square with world objects (machines are items on it, D-015) and other
-- objects (fires).
local function square(g, x, y, z, room, air)
    local sq = { x = x, y = y, z = z, room = room, air = air, objs = {}, fires = {} }
    function sq:getX() return self.x end
    function sq:getY() return self.y end
    function sq:getZ() return self.z end
    function sq:isInARoom() return self.room end
    local list, others = {}, {}
    function list:size() return #sq.objs end
    function list:get(i) return sq.objs[i + 1] end
    function sq:getWorldObjects() return list end
    function sq:transmitRemoveItemFromSquare(o) self.transmitted = (self.transmitted or 0) + 1 end
    function sq:removeWorldObject(o)
        for i = #self.objs, 1, -1 do
            if self.objs[i] == o then table.remove(self.objs, i) end
        end
    end
    function others:size() return #sq.fires end
    function others:get(i) return sq.fires[i + 1] end
    function sq:getObjects() return others end
    g.squares[x .. "," .. y .. "," .. z] = sq
    return sq
end

-- A fire on a square as the notes see it: IsoFireplace or IsoBarbecue.
local function fireOn(sq, class, lit, fuel)
    local o = { class = class, lit = lit, fuel = fuel }
    function o:isLit() return self.lit end
    function o:getFuelAmount() return self.fuel end
    sq.fires[#sq.fires + 1] = o
    return o
end

-- A campfire a player built (SCampfireSystem): the object named "Campfire"
-- holding its fuel in mod data, and the permanent IsoFire it keeps lit,
-- whose light radius is its heat radius.
local function campfireOn(sq, fuel, exterior, radius)
    local camp, md = { class = "IsoObject" }, { fuelAmt = fuel, isLit = true, exterior = exterior }
    function camp:getName() return "Campfire" end
    function camp:getModData() return md end
    local flame = { class = "IsoFire", radius = radius }
    function flame:isPermanent() return true end
    function flame:getLightRadius() return self.radius end
    sq.fires[#sq.fires + 1] = camp
    sq.fires[#sq.fires + 1] = flame
    return md
end

local function machine(sq, rec)
    local item, wi, md = {}, {}, { tlgProc = rec }
    function wi:getSquare() return item.on end
    function wi:getItem() return item end
    function item:getFullType() return "TLG.FermenterVessel" end
    function item:getModData() return md end
    function item:getWorldItem() return item.on and wi or nil end
    function item:setWorldItem(w) if w == nil then item.on = nil end end
    function item:getID() return 7 end
    item.on, item.wi = sq, wi
    if sq then sq.objs[#sq.objs + 1] = wi end
    return item
end

-- Moves as the game makes them: off the ground into a container, or onto a
-- square (the same item, its world object on the square's list).
local function lift(item)
    local sq = item.on
    for i = #(sq and sq.objs or {}), 1, -1 do
        if sq.objs[i] == item.wi then table.remove(sq.objs, i) end
    end
    item.on = nil
end

local function place(item, sq)
    lift(item)
    item.on = sq
    sq.objs[#sq.objs + 1] = item.wi
end

-- Stage hours done on the batch (ethanol_ferment: preparing 1 h, then 96 h).
local function work(rec)
    local done = 0
    for i, st in ipairs(rec.recipe.params.stages) do
        if i < rec.stage then done = done + st.hours elseif i == rec.stage then done = done + rec.stageDone end
    end
    return done
end

-- A warm day 0 (22 C outdoors, no readings needed): every placed hour is a
-- full stage hour.
local function warmDay(g)
    g.outC = 22
    World.get().climateLog = { [0] = { t = 22, rh = 0.7 } }
    return World.env()
end

local function running(id, t)
    local f = Process.new({ id = id, machine = "fermenter_barrel", t = t })
    f = Process.load(f, "ethanol_ferment", { sugar_eq = 6, water = 30 }).proc
    return Process.start(f, t).proc
end

-- A batch started at 2 on `sq`, accessed once (site, seen, hourly list).
local function startedOn(sq, id, env)
    local item = machine(sq, running(id, 2))
    local rec = Machines.advance(item, Machines.read(item, false), 2, env)
    Machines.write(item, rec)
    Machines.index(item, rec)
    return item
end

T.case("integration: the hourly reading files the air at each loaded, placed, running machine", function()
    local g = fakeGame(2)
    local ok, err = pcall(function()
        local warm = square(g, 1, 1, 0, true, 21.5)
        local item = machine(warm, running("P1", 2))
        local idle = machine(square(g, 2, 1, 0, false, -4), Process.new({ id = "P2", machine = "fermenter_barrel", t = 2 }))
        Machines.index(item, Machines.read(item, false))
        Machines.index(idle, Machines.read(idle, false))
        g.now = 10.02
        Machines.sampleSites()
        local rec = item:getModData().tlgProc
        T.eq(rec.temps[9], 21.5, "filed under the hour that just ended")
        T.eq(rec.site.room, true); T.eq(rec.site.z, 0)
        T.ok(idle:getModData().tlgProc.temps == nil, "no batch, no reading")
        -- Unloaded square: skipped, still listed. Machine gone: dropped.
        g.squares["1,1,0"] = nil
        g.now = 11.01
        Machines.sampleSites()
        T.ok(rec.temps[10] == nil and World.get().machineSites.P1 ~= nil)
        g.squares["1,1,0"] = warm
        warm.objs = {}
        Machines.sampleSites()
        T.ok(World.get().machineSites.P1 == nil, "a loaded square without the machine drops it")
        T.ok(World.get().machineSites.P2 ~= nil)
    end)
    g.restore()
    if not ok then error(err, 0) end
end)

T.case("integration: an access records the site and keeps only the readings still needed", function()
    local g = fakeGame(30)
    local ok, err = pcall(function()
        local sq = square(g, 5, 5, 1, true, 12)
        local rec = running("P3", 2)
        rec.temps = { [3] = 20, [22] = 21, [23] = 19, [26] = 18, [29] = 17 }
        local item = machine(sq, rec)
        local env = World.env()
        local out = Machines.advance(item, Machines.read(item, false), 30, env)
        T.eq(out.site.room, true); T.eq(out.site.z, 1)
        T.ok(out.temps[3] == nil and out.temps[22] == nil, "day 0 is behind the batch")
        T.eq(out.temps[23], 19, "kept: it stands in for the first hour of day 1 (run 18)")
        T.eq(out.temps[26], 18); T.eq(out.temps[29], 17)
        local early = Machines.advance(item, Machines.read(item, false), 24.5, env)
        T.eq(early.temps[23], 19)
        T.near((Machines.siteTemp(item, early, 24.5, env)), 19, 1e-9, "just after midnight: yesterday's last hour")
        local c, now, kind = Machines.siteTemp(item, out, 30, env)
        T.near(c, (18 + 17 + 4 * env:siteBase(1, out.site)) / 6, 1e-9, "today so far: two readings, four hours at the base")
        T.eq(now, false); T.eq(kind, "room_upper")
        out.state, out.temps = "Ready", nil
        local air, isNow = Machines.siteTemp(item, out, 30, env)
        T.eq(air, 12); T.eq(isNow, true)
        item.on = nil
        T.ok(Machines.siteTemp(item, out, 30, env) == nil, "not placed: no site temperature")
        local done = Machines.advance(item, rec, 30, env)
        T.eq(done.pause, "not_placed")
    end)
    g.restore()
    if not ok then error(err, 0) end
end)

T.case("integration: every ten minutes the fire warming a machine is noted with its fuel", function()
    local g = fakeGame(2)
    local ok, err = pcall(function()
        local Climate = TLG.Domain.Climate
        local t0 = Climate.roomAir(-3, false, 0.5, false)
        local sq = square(g, 10, 10, 0, true, t0)
        local item = machine(sq, running("P4", 2))
        Machines.index(item, Machines.read(item, false))
        local hearth = fireOn(square(g, 11, 12, 0, true, 0), "IsoFireplace", true, 365)
        fireOn(square(g, 10, 13, 0, true, 0), "IsoFireplace", false, 480)
        local bbq = fireOn(square(g, 8, 10, 0, false, 0), "IsoBarbecue", true, 100)
        sq.air = Climate.warmed(t0, 1, 2, 8, true, 35)
        g.now = 10.83
        Machines.observeFires()
        local note = item:getModData().tlgProc.fires[10]
        T.eq(note.f, 365); T.eq(note.x, 1); T.eq(note.y, 2); T.eq(note.r, true); T.eq(note.c, 35)
        T.near(note.t, 10.83, 1e-12); T.ok(note.rad == nil, "a fireplace's radius follows its fuel")
        T.eq(item:getModData().tlgProc.site.room, true)
        -- The hearth out, the barbecue gives the air: its note has a fixed radius.
        hearth.lit = false
        sq.air = Climate.warmed(t0, -2, 0, 3, false, 25)
        g.now = 11.0
        Machines.observeFires()
        note = item:getModData().tlgProc.fires[11]
        T.eq(note.c, 25); T.eq(note.rad, 3); T.eq(note.f, 100); T.eq(note.r, false); T.eq(note.x, -2)
        -- Nothing warms it: false, the hour's last note wins, noted once an
        -- hour; the time it was found placed is kept every ten minutes.
        bbq.lit = false
        sq.air = t0
        g.now = 11.17
        Machines.observeFires()
        T.eq(item:getModData().tlgProc.fires[11], false)
        local writes, quiet, write = 0, nil, Machines.write
        Machines.write = function(it, r, q)
            writes, quiet = writes + 1, q
            return write(it, r, q)
        end
        g.now = 11.33
        Machines.observeFires()
        Machines.write = write
        T.eq(writes, 1); T.eq(quiet, true, "kept on the authority, not sent")
        T.eq(item:getModData().tlgProc.fires[11], false, "the hour's note as it was")
        T.eq(item:getModData().tlgProc.seen, 11.33, "found placed at 11.33")
        -- Warmer than the room by a heat source that is no fire it knows: false.
        sq.air = t0 + 5
        g.now = 12.0
        Machines.observeFires()
        T.eq(item:getModData().tlgProc.fires[12], false)
        -- Not loaded: skipped.
        g.squares["10,10,0"] = nil
        g.now = 13.5
        Machines.observeFires()
        T.ok(item:getModData().tlgProc.fires[13] == nil)
        -- The status credits the last note before an absence: hour 10's, had it stood last.
        local rec = Machines.read(item, false)
        rec.fires = { [10] = { t = 10.83, f = 365, x = 1, y = 2, r = true, c = 35 } }
        rec.temps = { [9] = 20 }
        local env = World.env()
        local base = env:siteBase(0, rec.site)
        local w8, w7 = Climate.warmed(base, 1, 2, 8, true, 35), Climate.warmed(base, 1, 2, 7, true, 35)
        local stop = 10.83 + 365 / 60
        local c = Machines.siteTemp(item, rec, 23, env)
        T.near(c, (7 * base + 20 + 6 * w8 + (stop - 16) * w7 + (23 - stop) * base) / 21, 1e-9,
            "from the batch start at 2: hours 2-8 at the base, 9 read, warm from 10 to 16.9 (radius 7 in its last hour)")
        -- An access keeps the latest note before its day; a finished batch drops them.
        rec.fires[3] = false
        local out = Machines.advance(item, rec, 30, env)
        T.ok(out.fires[3] == nil and out.fires[10] ~= nil, "the latest note before day 1 stays")
        out.state = "Ready"
        Machines.trimTemps(out, env)
        T.ok(out.fires == nil and out.temps == nil)
    end)
    g.restore()
    if not ok then error(err, 0) end
end)

T.case("integration: a campfire a player built is noted with its fuel and largest radius", function()
    local g = fakeGame(2)
    local ok, err = pcall(function()
        local Climate = TLG.Domain.Climate
        local sq = square(g, 10, 10, 0, false, -3)
        local item = machine(sq, running("P5", 2))
        Machines.index(item, Machines.read(item, false))
        -- Nine tiles away, past a fireplace's reach, with 397 minutes of fuel
        -- (radius 10; RT-SP run 34's last note before its trip).
        local cs = square(g, 19, 10, 0, false, 0)
        local md = campfireOn(cs, 397, true, 10)
        sq.air = Climate.warmed(-3, 9, 0, 10, false, 35)
        g.now = 10.5
        Machines.observeFires()
        local note = item:getModData().tlgProc.fires[10]
        T.eq(note.k, "campfire"); T.eq(note.rmax, 10); T.eq(note.f, 397); T.eq(note.c, 35)
        T.eq(note.x, 9); T.eq(note.y, 0); T.eq(note.r, false)
        T.ok(note.rad == nil, "its radius follows its fuel"); T.near(note.t, 10.5, 1e-12)
        -- Built inside: up to 18 tiles.
        md.exterior = false
        g.now = 11.0
        Machines.observeFires()
        T.eq(item:getModData().tlgProc.fires[11].rmax, 18)
        -- The flame without its campfire (another open fire): no fuel to count.
        table.remove(cs.fires, 1)
        g.now = 12.0
        Machines.observeFires()
        T.eq(item:getModData().tlgProc.fires[12], false)
    end)
    g.restore()
    if not ok then error(err, 0) end
end)

T.case("integration: a machine picked up counts up to that moment, waits while carried, starts again where put down", function()
    local g = fakeGame(2)
    local ok, err = pcall(function()
        local env = warmDay(g)
        local a, b = square(g, 1, 1, 0, false, 22), square(g, 4, 1, 0, false, 22)
        local item = startedOn(a, "P5", env)
        local rec = item:getModData().tlgProc
        T.eq(rec.site.x, 1); T.eq(rec.site.y, 1); T.eq(rec.seen, 2)
        lift(item)
        Machines.pickedUp(item, 5)
        rec = item:getModData().tlgProc
        T.near(work(rec), 3, 1e-9, "the 3 h it stood there count")
        T.eq(rec.state, "Paused"); T.eq(rec.pause, "not_placed"); T.eq(rec.t, 5); T.eq(rec.seen, 5)
        T.ok(World.get().machineSites.P5 == nil, "off the hourly list at once")
        local carried = Machines.advance(item, Machines.read(item, false), 7, env)
        T.near(work(carried), 3, 1e-9, "nothing while carried"); T.eq(carried.pause, "not_placed"); T.eq(carried.t, 7)
        Machines.write(item, carried)
        place(item, b)
        Machines.putDown(item, 8)
        rec = item:getModData().tlgProc
        T.eq(rec.state, "Processing"); T.ok(rec.pause == nil); T.eq(rec.t, 8); T.eq(rec.site.x, 4); T.eq(rec.seen, 8)
        T.eq(World.get().machineSites.P5.x, 4, "listed at the new tile at once")
        local later = Machines.advance(item, Machines.read(item, false), 10, env)
        T.near(work(later), 5, 1e-9, "3 h before the pickup and 2 h since, none of the 3 h carried")
        -- Picked up again, then a second pickup event while carried: no change.
        lift(item)
        Machines.write(item, later)
        Machines.pickedUp(item, 11)
        Machines.pickedUp(item, 12)
        rec = item:getModData().tlgProc
        T.near(work(rec), 6, 1e-9); T.eq(rec.t, 11, "the second pickup finds it carried")
    end)
    g.restore()
    if not ok then error(err, 0) end
end)

T.case("integration: a move no Lua saw counts only up to the last time the machine was found placed", function()
    local g = fakeGame(2)
    local ok, err = pcall(function()
        local env = warmDay(g)
        local a, b = square(g, 1, 1, 0, false, 22), square(g, 4, 1, 0, false, 22)
        -- Found placed at 4.5 (the ten-minute note); lifted unseen; read while carried.
        local c = startedOn(a, "P6", env)
        g.now = 4.5
        Machines.observeFires()
        T.eq(c:getModData().tlgProc.seen, 4.5, "stamped by the note")
        lift(c)
        local r = Machines.advance(c, Machines.read(c, false), 6, env)
        T.near(work(r), 2.5, 1e-9, "up to 4.5"); T.eq(r.state, "Paused"); T.eq(r.pause, "not_placed"); T.eq(r.t, 6)
        -- Lifted unseen, put down where the game's Lua sees it (the multiplayer case).
        local d = startedOn(a, "P7", env)
        g.now = 4.5
        Machines.observeFires()
        lift(d); place(d, b)
        Machines.putDown(d, 7)
        r = d:getModData().tlgProc
        T.near(work(r), 2.5, 1e-9); T.eq(r.state, "Processing"); T.eq(r.t, 7); T.eq(r.site.x, 4)
        T.eq(World.get().machineSites.P7.x, 4)
        -- Neither move seen: found on another tile at the next access.
        local e = startedOn(a, "P8", env)
        g.now = 4.5
        Machines.sampleSites()
        T.eq(e:getModData().tlgProc.seen, 4.5, "stamped by the hourly reading")
        lift(e); place(e, b)
        r = Machines.advance(e, Machines.read(e, false), 8, env)
        T.near(work(r), 2.5, 1e-9, "nothing after 4.5"); T.eq(r.t, 8); T.eq(r.site.x, 4); T.eq(r.seen, 8)
        -- Carried after a seen pickup, put down unseen: from the next access.
        local f = startedOn(a, "P9", env)
        lift(f)
        Machines.pickedUp(f, 3)
        place(f, b)
        r = Machines.advance(f, Machines.read(f, false), 9, env)
        T.near(work(r), 1, 1e-9); T.eq(r.state, "Processing"); T.eq(r.t, 9); T.eq(r.site.x, 4)
    end)
    g.restore()
    if not ok then error(err, 0) end
end)

T.case("integration: older records, finished batches and paused ones around a pickup", function()
    local g = fakeGame(2)
    local ok, err = pcall(function()
        local env = warmDay(g)
        local a, b = square(g, 1, 1, 0, false, 22), square(g, 4, 1, 0, false, 22)
        -- No seen time: nothing beyond the last access (the old rule).
        local old = machine(a, running("P10", 2))
        lift(old)
        local r = Machines.advance(old, Machines.read(old, false), 6, env)
        T.near(work(r), 0, 1e-9); T.eq(r.pause, "not_placed")
        -- A site without its tile cannot tell a move: counted as before.
        local tileless = machine(b, running("P11", 2))
        tileless:getModData().tlgProc.site = { room = false, z = 0 }
        r = Machines.advance(tileless, Machines.read(tileless, false), 6, env)
        T.near(work(r), 4, 1e-9); T.eq(r.site.x, 4)
        -- A batch that finishes before the pickup is not marked carried.
        local done = startedOn(a, "P12", env)
        local rec = done:getModData().tlgProc
        rec.stage, rec.stageDone = 2, 95.5
        lift(done)
        Machines.pickedUp(done, 3)
        rec = done:getModData().tlgProc
        T.eq(rec.state, "OutputReady"); T.ok(rec.pause == nil)
        -- Paused by the player: still paused once put down again.
        local held = startedOn(a, "P13", env)
        rec = held:getModData().tlgProc
        rec.state, rec.pause, rec.manualPause = "Paused", "paused_by_player", true
        lift(held)
        Machines.pickedUp(held, 4)
        T.eq(held:getModData().tlgProc.pause, "not_placed")
        place(held, b)
        Machines.putDown(held, 5)
        r = Machines.advance(held, Machines.read(held, false), 6, env)
        T.eq(r.state, "Paused"); T.eq(r.pause, "paused_by_player"); T.near(work(r), 0, 1e-9)
    end)
    g.restore()
    if not ok then error(err, 0) end
end)

T.case("integration: the game's Grab, floor transfers and place action account a machine's moves", function()
    local g = fakeGame(2)
    local names = { "ISGrabItemAction", "ISTransferAction", "ISDropWorldItemAction" }
    local saved = {}
    for _, k in ipairs(names) do saved[k] = _G[k] end
    local ok, err = pcall(function()
        local env = warmDay(g)
        local a, b = square(g, 1, 1, 0, false, 22), square(g, 4, 1, 0, false, 22)
        -- What the vanilla methods do to the item (SRC 42.21), with their
        -- signatures: Grab gets the world object, the transfer is called on
        -- the class with the character, the place action keeps item and square.
        ISGrabItemAction = { transferItem = function(self, witem) lift(witem:getItem()) end }
        ISTransferAction = { transferItem = function(self, character, item, src, dest, dropSquare)
            if dropSquare then place(item, dropSquare) else lift(item) end
            return item
        end }
        ISDropWorldItemAction = { complete = function(self)
            place(self.item, self.sq)
            return true
        end }
        Machines.install()
        local item = startedOn(a, "P14", env)
        g.now = 4
        local grab = setmetatable({}, { __index = ISGrabItemAction })
        grab:transferItem(item:getWorldItem())
        local rec = item:getModData().tlgProc
        T.near(work(rec), 2, 1e-9, "Grab: counted to the pickup"); T.eq(rec.pause, "not_placed")
        g.now = 6
        local drop = setmetatable({ item = item, sq = b }, { __index = ISDropWorldItemAction })
        T.eq(drop:complete(), true)
        rec = item:getModData().tlgProc
        T.eq(rec.state, "Processing"); T.eq(rec.t, 6); T.eq(rec.site.x, 4)
        g.now = 7
        T.eq(ISTransferAction:transferItem({}, item, "floor", "inventory", nil), item)
        rec = item:getModData().tlgProc
        T.near(work(rec), 3, 1e-9, "floor -> inventory: counted to the pickup"); T.eq(rec.pause, "not_placed")
        g.now = 9
        ISTransferAction:transferItem({}, item, "inventory", "floor", a)
        rec = item:getModData().tlgProc
        T.eq(rec.state, "Processing"); T.eq(rec.t, 9); T.eq(rec.site.x, 1)
        T.eq(World.get().machineSites.P14.x, 1)
        -- A machine without a record passes untouched.
        local bare = machine(b, nil)
        ISTransferAction:transferItem({}, bare, "floor", "inventory", nil)
        T.ok(bare:getModData().tlgProc == nil, "no record created")
        -- A failing account never breaks the move.
        local pickedUp, log, logged = Machines.pickedUp, TLG.Log.error, nil
        Machines.pickedUp = function() error("boom") end
        TLG.Log.error = function(fmt, ...) logged = string.format(fmt, ...) end
        ISTransferAction:transferItem({}, item, "floor", "inventory", nil)
        Machines.pickedUp, TLG.Log.error = pickedUp, log
        T.ok(item.on == nil, "moved anyway"); T.ok(logged ~= nil and string.find(logged, "boom", 1, true) ~= nil)
    end)
    for _, k in ipairs(names) do _G[k] = saved[k] end
    g.restore()
    if not ok then error(err, 0) end
end)

T.case("integration: a machine carried in both hands is accounted when taken and when dropped", function()
    local g = fakeGame(2)
    local names = { "ISGrabItemAction", "ISTransferAction", "ISDropWorldItemAction", "ISEquipHeavyItem", "ISUnequipAction",
        "forceDropHeavyItems" }
    local saved = {}
    for _, k in ipairs(names) do saved[k] = _G[k] end
    local ok, err = pcall(function()
        local env = warmDay(g)
        local a, b = square(g, 1, 1, 0, false, 22), square(g, 4, 1, 0, false, 22)
        -- What the vanilla functions do (42.21): ISEquipHeavyItem takes the
        -- item into the inventory and both hands but, off the floor, leaves
        -- its world object on the square (RT-SP runs 77-78); ISUnequipAction
        -- puts a heavy hand item at the character's feet unless it is
        -- unequipped to be dropped or placed; forceDropHeavyItems puts a
        -- heavy hand item at the character's feet.
        local hands, carried = { square = b }, {}
        local inventory = { contains = function(self, it) return carried[it] == true end }
        local character = {
            getPrimaryHandItem = function() return hands.primary end,
            getSecondaryHandItem = function() return hands.secondary end,
            getCurrentSquare = function() return hands.square end,
            getInventory = function() return inventory end,
        }
        ISGrabItemAction, ISTransferAction, ISDropWorldItemAction = {}, {}, {}
        ISEquipHeavyItem = { complete = function(self)
            carried[self.item] = true
            hands.primary, hands.secondary = self.item, self.item
            return true
        end }
        ISUnequipAction = { complete = function(self)
            hands.primary, hands.secondary = nil, nil
            if self.reason ~= "drop" and self.reason ~= "place" then
                place(self.item, self.character:getCurrentSquare())
                carried[self.item] = nil
            end
            return true
        end }
        forceDropHeavyItems = function(chr)
            local held = chr:getPrimaryHandItem()
            if held then
                place(held, chr:getCurrentSquare())
                carried[held] = nil
            end
            hands.primary, hands.secondary = nil, nil
        end
        Machines.install()
        local item = startedOn(a, "P15", env)
        g.now = 4
        local take = setmetatable({ item = item, character = character }, { __index = ISEquipHeavyItem })
        T.eq(take:complete(), true)
        T.ok(item:getWorldItem() == nil and #a.objs == 0 and a.transmitted == 1,
            "the world object vanilla left on the square is taken off as the floor transfer does")
        local rec = item:getModData().tlgProc
        T.near(work(rec), 2, 1e-9, "taken into both hands: counted to the pickup"); T.eq(rec.pause, "not_placed")
        g.now = 6
        forceDropHeavyItems(character)
        rec = item:getModData().tlgProc
        T.eq(rec.state, "Processing"); T.eq(rec.t, 6); T.eq(rec.site.x, 4, "dropped at the character's feet")
        T.eq(World.get().machineSites.P15.x, 4, "listed at the new tile at once")
        local later = Machines.advance(item, Machines.read(item, false), 8, env)
        T.near(work(later), 4, 1e-9, "2 h before the pickup and 2 h since the drop, none of the 2 h carried")
        -- Nothing in hand: the drop changes nothing.
        g.now = 9
        forceDropHeavyItems(character)
        T.eq(item:getModData().tlgProc.t, 6)
        -- Taken from the inventory (the machine was not standing): no pickup.
        lift(item)
        Machines.pickedUp(item, 9)
        g.now = 10
        setmetatable({ item = item, character = character }, { __index = ISEquipHeavyItem }):complete()
        T.eq(item:getModData().tlgProc.t, 9, "already carried")
        -- Unequipped to be dropped, it stays in the inventory (the floor
        -- transfer that follows puts it down): nothing yet.
        g.now = 11
        setmetatable({ item = item, character = character, reason = "drop" }, { __index = ISUnequipAction }):complete()
        T.eq(item:getModData().tlgProc.pause, "not_placed", "not put down by the drop's unequip")
        -- Unequipped for anything else (the menus unequip the hands before
        -- another heavy item is taken or a weapon equipped): at the
        -- character's feet, resumed from then.
        setmetatable({ item = item, character = character }, { __index = ISEquipHeavyItem }):complete()
        hands.square = a
        g.now = 12
        setmetatable({ item = item, character = character }, { __index = ISUnequipAction }):complete()
        rec = item:getModData().tlgProc
        T.eq(rec.state, "Processing"); T.eq(rec.t, 12); T.eq(rec.site.x, 1, "unequipped at the character's feet")
        T.eq(World.get().machineSites.P15.x, 1, "listed at the new tile at once")
        later = Machines.advance(item, Machines.read(item, false), 14, env)
        T.near(work(later), 7, 1e-9, "5 h placed before the pickup at 9 and 2 h since the drop, none of the 3 h carried")
        -- A machine without a record yet is taken off the ground too, and no
        -- record is created; a vanilla heavy item is left as vanilla leaves it.
        local bare = machine(b, nil)
        setmetatable({ item = bare, character = character }, { __index = ISEquipHeavyItem }):complete()
        T.ok(bare:getWorldItem() == nil, "lifted"); T.ok(bare:getModData().tlgProc == nil, "no record created")
        setmetatable({ item = bare, character = character }, { __index = ISUnequipAction }):complete()
        T.ok(bare:getWorldItem() ~= nil and bare:getModData().tlgProc == nil, "unequipped at the feet, still no record")
        local rock = machine(b, nil)
        function rock:getFullType() return "Base.LargeMeteorite" end
        setmetatable({ item = rock, character = character }, { __index = ISEquipHeavyItem }):complete()
        T.ok(rock:getWorldItem() ~= nil, "not the mod's item: untouched")
    end)
    for _, k in ipairs(names) do _G[k] = saved[k] end
    g.restore()
    if not ok then error(err, 0) end
end)
