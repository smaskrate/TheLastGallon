-- Offline profile of a machine record's hourly and ten-minute work and its
-- catch-up (docs/performance.md), on the game's Kahlua VM:
--   tools/run-tests.ps1 -Entry tests/support/bench_machine_records.lua
-- os.time gives seconds with a millisecond fraction here, so each piece is
-- repeated for about a second. Stand-ins for the game calls as in
-- tests/integration/test_machine_sites.lua. Not part of the suite.
loadstring(__TLG_SOURCES["support/prelude"], "support/prelude")()
loadstring(__TLG_SOURCES["support/testlib"], "support/testlib")()
require "support/fixtures"
require "TLG/Integration/Machines"
local Machines, World, Process, Tables = TLG.Integration.Machines, TLG.World, TLG.Domain.Process, TLG.Tables

local g = { now = 600, squares = {}, store = {} }
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
function cm:getTemperature() return 22 end
function values:getDayLightLagged() return 0.5 end
function cm:getClimateValuesCopy() return values end
getClimateManager = function() return cm end
function world:isHydroPowerOn() return false end
getWorld = function() return world end
instanceof = function(o, class) return type(o) == "table" and o.class == class end
isServer = function() return false end
isClient = function() return false end
local md = World.get()
md.v, md.calendar, md.climateLog = 1, { dayOfYear = 190, hourOfDay = 0 }, {}
for d = 0, 40 do md.climateLog[d] = { t = 22, rh = 0.7 } end

local function square(x, y, air)
    local sq = { x = x, y = y, z = 0, air = air, objs = {} }
    function sq:getX() return self.x end
    function sq:getY() return self.y end
    function sq:getZ() return self.z end
    function sq:isInARoom() return false end
    local list, none = {}, {}
    function list:size() return #sq.objs end
    function list:get(i) return sq.objs[i + 1] end
    function sq:getWorldObjects() return list end
    function none:size() return 0 end
    function sq:getObjects() return none end
    g.squares[x .. "," .. y .. ",0"] = sq
    return sq
end

local function machine(sq, rec)
    local item, wi, imd = {}, {}, { tlgProc = rec }
    function wi:getSquare() return sq end
    function wi:getItem() return item end
    function item:getFullType() return "TLG.FermenterVessel" end
    function item:getModData() return imd end
    function item:getWorldItem() return wi end
    function item:getID() return 7 end
    sq.objs[#sq.objs + 1] = wi
    return item
end

-- A fermenter started 480 hours ago and not opened since, with a reading and
-- a "no fire" note for every hour (Machines.MAX_READINGS).
local hours = Machines.MAX_READINGS
local t0 = g.now - hours
local rec = Process.new({ id = "P1", machine = "fermenter_barrel", t = t0 })
rec = Process.load(rec, "ethanol_ferment", { sugar_eq = 6, water = 30 }).proc
rec = Process.start(rec, t0).proc
rec.site, rec.seen, rec.temps, rec.fires = { room = false, z = 0, x = 1, y = 1 }, t0, {}, {}
for h = math.floor(t0), math.floor(t0) + hours - 1 do rec.temps[h], rec.fires[h] = 22, false end
local sq = square(1, 1, 22)
local item = machine(sq, rec)
md.machineSites = { P1 = { x = 1, y = 1, z = 0 } }
local env = World.env()

local function time(label, fn)
    local s = os.time()
    local n = 0
    repeat
        fn()
        n = n + 1
    until os.time() - s >= 1
    print(string.format("%-46s %9.4f ms per call (%d calls)", label, (os.time() - s) * 1000 / n, n))
end

print(string.format("record: %d readings, %d notes, opened %d hours ago", Tables.count(rec.temps),
    Tables.count(rec.fires), hours))
time("Tables.deepCopy(record)", function() Tables.deepCopy(rec) end)
time("Machines.read(item)", function() Machines.read(item, false) end)
time("Tables.sortedKeys(readings)", function() Tables.sortedKeys(rec.temps) end)
local copy = Machines.read(item, false)
time("Machines.trimTemps(record)", function() Machines.trimTemps(copy, env) end)
time("World.env()", function() World.env() end)
time("Machines.airAt + warmingFire (no fire)", function() Machines.warmingFire(sq, Machines.airAt(sq), g.now) end)
time("Machines.sampleSites (this machine)", function() Machines.sampleSites() end)
time("Machines.observeFires (this machine)", function() Machines.observeFires() end)
local site = Process.site(Machines.read(item, false))
time("env:segments over its 20 days", function() env:segments(t0, g.now, "sheltered", site) end)
time("env:siteDayMean, one day", function() env:siteDayMean(env:dayIndex(t0) + 5, site, g.now) end)
local fresh = Machines.read(item, false)
time("Machines.advance through the 20 days", function() Machines.advance(item, fresh, g.now, env) end)
