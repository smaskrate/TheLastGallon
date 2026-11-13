require "support/fixtures"
require "TLG/Integration/Containers"
-- Generators, Vehicles and Stations register their installers through Boot,
-- which hooks the game's Events as it loads. A stand-in for these requires
-- only: the suite runs without Events (see Boot.lua).
local savedEvents = Events
Events = setmetatable({}, { __index = function() return { Add = function() end } end })
require "TLG/Integration/Generators"
require "TLG/Integration/Vehicles"
require "TLG/Integration/Stations"
Events = savedEvents
local I, D, World = TLG.Integration, TLG.Domain, TLG.World

-- Stand-ins for the game calls the fuel reads and writes make: global
-- ModData and the clock (World.now, World.env), and a can's native fluids
-- (each fake container's `fluids`; writes counted in g.writes). The
-- untracked baseline is fixed, since what matters here is when the inflow
-- mixes in. Installed for one case and removed again.
local GLOBALS = { "ModData", "getGameTime" }
local BASE = 0.07

local function fakeGame(now)
    local saved = {}
    for _, k in ipairs(GLOBALS) do saved[k] = _G[k] end
    local g = { now = now, store = {}, writes = 0 }
    ModData = { getOrCreate = function(k)
        g.store[k] = g.store[k] or {}
        return g.store[k]
    end }
    local clock = {}
    function clock:getWorldAgeHours() return g.now end
    getGameTime = function() return clock end
    local md = World.get()
    md.v, md.calendar, md.climateLog = 1, { dayOfYear = 190, hourOfDay = 9 }, {}
    local untracked, readComposition, writeComposition = I.Containers.untrackedDeg, I.Native.readComposition,
        I.Native.writeComposition
    I.Containers.untrackedDeg = function() return BASE end
    I.Native.readComposition = function(fc) return fc:fluids(), 0, {} end
    I.Native.writeComposition = function(fc, comp)
        g.writes = g.writes + 1
        fc.comp = TLG.Tables.copy(comp)
        return true
    end
    function g.restore()
        for _, k in ipairs(GLOBALS) do _G[k] = saved[k] end
        I.Containers.untrackedDeg, I.Native.readComposition, I.Native.writeComposition = untracked, readComposition,
            writeComposition
    end
    return g
end

-- A record of 4 L of petrol last written at world hour 100.
local function sidecar()
    return { v = 1, id = "S1", rev = 2, t = 100, q = { gasoline = 4 }, deg = { gasoline = 0.3 }, stab = 0, mic = 0,
        cond = 1, prov = {} }
end

-- One stand-in per adapter; `x.litres` is what the native owner holds.
local function can()
    local x = { md = { tlg = sidecar() }, litres = 4 }
    local fc = {}
    function fc:getCapacity() return 10 end
    function fc:fluids() return { gasoline = x.litres } end
    function x:getModData() return self.md end
    function x:getFluidContainerFromSelfOrWorldItem() return fc end
    function x:getFullType() return "Base.PetrolCan" end
    function x:getID() return 7 end
    return x
end

local function vehicle()
    local x = { md = { tlg = sidecar() }, litres = 4 }
    local part = {}
    function part:getContainerContentAmount() return x.litres end
    function part:getContainerCapacity() return 50 end
    function part:getModData() return x.md end
    function x:getPartById(id) return id == "GasTank" and part or nil end
    return x
end

local function generator()
    local x = { md = { tlg = sidecar() }, litres = 4 }
    function x:getFuel() return self.litres end
    function x:getMaxFuel() return 10 end
    function x:getModData() return self.md end
    return x
end

local function pump()
    local x = { md = { tlg = sidecar() }, litres = 4 }
    function x:getPipedFuelAmount() return self.litres end
    function x:getModData() return self.md end
    return x
end

local READS = {
    { "a can", can, function(x) return I.Containers.read(x, "item", false) end },
    { "a vehicle tank", vehicle, function(x) return I.Vehicles.read(x, false) end },
    { "a generator", generator, function(x) return I.Generators.read(x, false) end },
    { "a pump", pump, function(x) return I.Stations.read(x, false) end },
}

for _, r in ipairs(READS) do
    local name, make, read = r[1], r[2], r[3]
    T.case("integration: petrol put into " .. name .. " unseen mixes in when found, aged once", function()
        local g = fakeGame(100)
        local ok, err = pcall(function()
            local x = make()
            local before, status = read(x)
            T.eq(status, "ok", "nothing changed yet")
            -- A month later 3 L more are in it, put there by nothing the mod saw.
            g.now, x.litres = 100 + 24 * 30, 7
            local env, base = World.env(), { deg = BASE, mic = 0 }
            local after, status2 = read(x)
            T.eq(status2, "reconciled")
            T.eq(after.t, g.now, "advanced to the moment it was found")
            F.assertSupplyClose(after, D.Mixing.addUntracked(D.Aging.advance(before, g.now, env), "gasoline", 3, base),
                1e-12, name)
            -- RT-SP run 54: mixed in at the last write, then aged with the rest.
            local twice = D.Aging.advance(D.Mixing.addUntracked(before, "gasoline", 3, base), g.now, env)
            T.ok(twice.deg.gasoline > after.deg.gasoline + 1e-3,
                string.format("aged twice %.6f, once %.6f", twice.deg.gasoline, after.deg.gasoline))
            -- A loss alone leaves from the record as written; callers advance it.
            x.litres = 2
            T.eq(read(x).t, before.t, "a loss alone is not advanced")
        end)
        g.restore()
        if not ok then error(err, 0) end
    end)
end

-- An opened jerry can of the mod's ethanol recorded at world hour 100, or
-- an empty one never recorded; its fluids are a table the stand-ins read
-- and write.
local function ethanolCan(id, litres)
    local x = { id = id, md = {} }
    if litres > 0 then
        x.md.tlg = { v = 1, id = "S" .. id, rev = 1, t = 100, q = { ethanol = litres }, deg = { ethanol = 0.1 }, stab = 0,
            mic = 0, cond = 1, sealed = false, storage = "jerrycan_steel", prov = {} }
    end
    local fc = { comp = litres > 0 and { ethanol = litres } or {} }
    function fc:getCapacity() return 20 end
    function fc:fluids() return TLG.Tables.copy(self.comp) end
    function x:getModData() return self.md end
    function x:getFluidContainerFromSelfOrWorldItem() return fc end
    function x:getFullType() return "Base.JerryCan" end
    function x:getID() return self.id end
    x.fc = fc
    return x
end

-- The can's fluids hold what its record says, component by component.
local function fluidsMatchRecord(x, label)
    local q, comp = x.md.tlg.q, x.fc.comp
    for id, v in pairs(q) do T.near(comp[id] or 0, v, 1e-9, label .. ": " .. id) end
    for id, v in pairs(comp) do T.near(q[id] or 0, v, 1e-9, label .. ": " .. id) end
end

-- Water an opened can takes up while it ages: written to the record alone,
-- the next read took the fluids as they were and dropped it (2026-11-02).
local LATER = 100 + 24 * 60

T.case("integration: a pour the mod follows leaves the water an opened can took up in its fluids", function()
    local g = fakeGame(100)
    local ok, err = pcall(function()
        local src, dst = ethanolCan(1, 4), ethanolCan(2, 0)
        g.now = LATER
        local a, b = I.Containers.read(src, "item", false), I.Containers.read(dst, "item", false)
        -- The game moves 1 L of ethanol, the only fluid it knows the can holds.
        src.fc.comp.ethanol, dst.fc.comp.ethanol = 3, 1
        I.Containers.followNativeTransfer(src, "item", a, dst, "item", b, { ethanol = 1 })
        local water = src.md.tlg.q.water or 0
        T.ok(water > 1e-3, string.format("the can took up %.6f L of water in 60 days", water))
        fluidsMatchRecord(src, "source")
        fluidsMatchRecord(dst, "destination")
        T.near(D.Supply.total(src.md.tlg), 3, 1e-9, "the litres the game left")
        T.eq(g.writes, 1, "only the source's fluids differed from its record")
        local again, status = I.Containers.read(src, "item", false)
        T.eq(status, "ok")
        T.near(again.q.water or 0, water, 1e-12, "the next read keeps the water")
    end)
    g.restore()
    if not ok then error(err, 0) end
end)

T.case("integration: a look's record sets the can's fluids to it, the litres unchanged", function()
    local g = fakeGame(100)
    local ok, err = pcall(function()
        local can = ethanolCan(3, 4)
        g.now = LATER
        local rec = D.Aging.advance((I.Containers.read(can, "item", false)), g.now, World.env())
        I.Containers.endpoint(can, "item"):record(rec)
        local water = can.md.tlg.q.water or 0
        T.ok(water > 1e-3, string.format("%.6f L of water", water))
        fluidsMatchRecord(can, "looked at")
        T.near(D.Supply.total(can.md.tlg), 4, 1e-9, "no litres moved")
        local again, status = I.Containers.read(can, "item", false)
        T.eq(status, "ok")
        T.near(again.q.water or 0, water, 1e-12, "the next read keeps the water")
    end)
    g.restore()
    if not ok then error(err, 0) end
end)

T.case("integration: water too little for the game to hold stays fuel in the record and the fluids", function()
    local g = fakeGame(100)
    local ok, err = pcall(function()
        local can = ethanolCan(5, 4)
        g.now = LATER
        local rec = D.Aging.advance((I.Containers.read(can, "item", false)), g.now, World.env())
        rec.q.ethanol, rec.q.water, rec.q.gasoline, rec.deg.gasoline = 4 - 2.5e-4, 1.5e-4, 1e-4, 0.5
        I.Containers.endpoint(can, "item"):record(rec)
        T.ok(can.md.tlg.q.water == nil and can.md.tlg.q.gasoline == nil, "nothing under the game's minimum in the record")
        T.ok(can.md.tlg.deg.gasoline == nil, "no condition left for a fuel folded away")
        fluidsMatchRecord(can, "too little")
        T.near(D.Supply.total(can.md.tlg), 4, 1e-12, "the litres kept")
        T.near(rec.q.water, 1.5e-4, 0, "the caller's record left as it was")
    end)
    g.restore()
    if not ok then error(err, 0) end
end)

T.case("integration: a record write leaves the fluids alone below the commit tolerance", function()
    local g = fakeGame(100)
    local ok, err = pcall(function()
        local can = ethanolCan(4, 4)
        g.now = 100.25
        local rec = D.Aging.advance((I.Containers.read(can, "item", false)), g.now, World.env())
        local water = rec.q.water or 0
        T.ok(water > 0 and water < I.Containers.COMMIT_TOLERANCE,
            string.format("%.3e L of water in a quarter of an hour", water))
        I.Containers.endpoint(can, "item"):record(rec)
        T.eq(g.writes, 0, "the fluids not touched")
        T.eq(can.md.tlg.t, g.now, "the record written")
    end)
    g.restore()
    if not ok then error(err, 0) end
end)

-- The Fuel menu offers Seal or Unseal from the client's copy of the can's
-- record; on a server a can no character carries, on the floor or in a
-- crate, gets it from WorldItemRecords (an item's fields reach only the
-- client holding it).
T.case("integration: on a server a can's record goes to the clients while it lies on the floor or in a crate; a client puts it in its copy", function()
    local g = fakeGame(100)
    local names, sent, saved = { "sendServerCommand", "isServer", "getCell", "instanceof" }, {}, {}
    for _, k in ipairs(names) do saved[k] = _G[k] end
    sendServerCommand = function(module, command, args) sent[#sent + 1] = { module = module, command = command, args = args } end
    instanceof = function(o, class)
        return type(o) == "table" and (o.class == class or (class == "IsoGameCharacter" and o.class == "IsoPlayer"))
    end
    local function list(t) return { size = function() return #t end, get = function(_, i) return t[i + 1] end } end
    local ok, err = pcall(function()
        -- The floor at 10,20; a crate at 11,20.
        local floor, objects = {}, {}
        local sq = { getX = function() return 10 end, getY = function() return 20 end, getZ = function() return 0 end,
            getWorldObjects = function() return list(floor) end, getObjects = function() return list({}) end }
        local crateSq = { getX = function() return 11 end, getY = function() return 20 end, getZ = function() return 0 end,
            getWorldObjects = function() return list({}) end, getObjects = function() return list(objects) end }
        getCell = function() return { getGridSquare = function(_, x, y, z)
            if y == 20 and z == 0 then return (x == 10 and sq) or (x == 11 and crateSq) or nil end
        end } end
        local crate = { class = "IsoObject", getSquare = function() return crateSq end }
        local inCrate = { getParent = function() return crate end }
        local inHands = { getParent = function() return { class = "IsoPlayer" } end }
        local onFloor, outer = true, nil
        local x = can()
        function x:getWorldItem() return onFloor and { getSquare = function() return sq end } or nil end
        function x:getOutermostContainer() return outer end
        local rec = sidecar()
        rec.sealed = false
        isServer = function() return false end
        I.Containers.writeSidecar(x, "item", rec)
        T.eq(#sent, 0, "single player sends nothing")
        isServer = function() return true end
        I.Containers.writeSidecar(x, "item", rec)
        T.eq(#sent, 1)
        local m = sent[1]
        T.eq(m.module, "TLG"); T.eq(m.command, "item"); T.eq(m.args.key, "tlg")
        T.eq(m.args.id, 7); T.eq(m.args.x, 10); T.eq(m.args.y, 20); T.eq(m.args.z, 0)
        T.eq(m.args.rec.sealed, false); T.eq(m.args.rec.id, "S1")
        onFloor, outer = false, inHands
        I.Containers.writeSidecar(x, "item", rec)
        T.eq(#sent, 1, "carried: its holder gets it with the item's fields")
        outer = inCrate
        rec.sealed = true
        I.Containers.writeSidecar(x, "item", rec)
        T.eq(#sent, 2, "in a crate: sent")
        local c = sent[2]
        T.eq(c.args.x, 11); T.eq(c.args.y, 20); T.eq(c.args.rec.sealed, true)
        -- A client's copies, on the floor and in the crate, take the records
        -- sent.
        isServer = function() return false end
        local WR = TLG.Integration.WorldItemRecords
        local copy = can()
        copy.md = {}
        floor[1] = { getItem = function() return copy end }
        T.ok(WR.received(m.args))
        T.eq(copy.md.tlg.sealed, false, "the copy on the floor now says unsealed")
        local stored = can()
        stored.md = {}
        objects[1] = { getContainerCount = function() return 1 end, getContainerByIndex = function()
            return { getItemWithIDRecursiv = function(_, id) return id == 7 and stored or nil end }
        end }
        T.ok(WR.received(c.args))
        T.eq(stored.md.tlg.sealed, true, "the copy in the crate now says sealed")
        T.ok(not WR.received({ id = 8, x = 11, y = 20, z = 0, key = "tlg", rec = c.args.rec }), "another item")
        T.ok(not WR.received({ id = 7, x = 12, y = 20, z = 0, key = "tlg", rec = c.args.rec }), "a square not loaded")
    end)
    for _, k in ipairs(names) do _G[k] = saved[k] end
    g.restore()
    if not ok then error(err, 0) end
end)

-- Diesel chassis (D-036): a vehicle's stock profile and the fuel an
-- unrecorded tank is taken to hold.
local function chassis(script, litres, engineSide)
    local x = { litres = litres or 0 }
    local tank, engine, tmd, emd = {}, {}, {}, { tlg = engineSide }
    function tank:getContainerContentAmount() return x.litres end
    function tank:getContainerCapacity() return 60 end
    function tank:getModData() return tmd end
    function engine:getModData() return emd end
    function x:getPartById(id) return (id == "GasTank" and tank) or (id == "Engine" and engine) or nil end
    function x:getScriptName() return script end
    function x:getSqlId() return 5 end
    return x
end

T.case("integration: the chosen chassis families are diesel, each with its variants, and no other", function()
    local V = I.Vehicles
    for _, name in ipairs({ "Base.PickUpVan", "Base.PickUpVanLightsFire", "PickUpVan_Camo", "Base.VanRadio", "Base.VanRadio_3N",
        "Base.VanSeats", "Base.VanSeats_Prison", "Base.VanSeatsAirportShuttle", "Base.VanAmbulance" }) do
        T.ok(V.isDieselChassis(name), name)
    end
    for _, name in ipairs({ "Base.PickUpTruck", "Base.PickUpTruckLightsFire", "Base.StepVan", "Base.StepVanMail", "Base.Van",
        "Base.VanSpiffo", "Base.Van_Transit", "Base.SUV", "Base.OffRoad", "Base.CarNormal", "Base.SmallCar", "nil", "" }) do
        T.ok(not V.isDieselChassis(name), name .. " stays petrol")
    end
end)

T.case("integration: diesel chassis exist only in a world started as a new game with them", function()
    local V = I.Vehicles
    local g = fakeGame(200)
    local ok, err = pcall(function()
        local world = World.get()
        -- A save from before: the same van is a petrol van.
        T.eq(V.baseProfile(chassis("Base.VanAmbulance")), "engine_si_stock")
        T.eq(V.referenceFuel(chassis("Base.VanAmbulance")), "gasoline")
        world.dieselVehicles = true
        T.eq(V.baseProfile(chassis("Base.VanAmbulance")), "engine_ci_stock")
        T.eq(V.referenceFuel(chassis("Base.VanAmbulance")), "diesel")
        T.eq(V.baseProfile(chassis("Base.Van")), "engine_si_stock", "a trade van stays petrol")
        T.eq(V.baseProfile(chassis("Base.PickUpVan", 0, { profile = "engine_si_flex" })), "engine_si_flex",
            "an engine's own recorded profile comes first")
        -- Found with fuel and no record: diesel in the diesel van, petrol in the other.
        local rec = V.read(chassis("Base.VanAmbulance", 12), false)
        T.near(rec.q.diesel or 0, 12, 0.01, "the baseline gives a little of it to water"); T.eq(rec.q.gasoline, nil)
        rec = V.read(chassis("Base.Van", 12), false)
        T.near(rec.q.gasoline or 0, 12, 0.01); T.eq(rec.q.diesel, nil)
    end)
    g.restore()
    if not ok then error(err, 0) end
end)
-- Diesel at some pumps (D-036).
local function stationPump(x, litres, side)
    local o = { md = { tlg = side }, units = litres }
    local square = {}
    function square:getX() return x end
    function square:getY() return 20 end
    function square:getZ() return 0 end
    function o:getSquare() return square end
    function o:getPipedFuelAmount() return self.units end
    function o:setPipedFuelAmount(n) self.units = n end
    function o:hasModData() return true end
    function o:getModData() return self.md end
    function o:transmitModData() end
    return o
end

T.case("integration: a generator with a fuel record is not a pump", function()
    local S = I.Stations
    local saved = instanceof
    instanceof = function(o, class) return type(o) == "table" and o.class == class end
    local ok, err = pcall(function()
        -- A pump the mod has recorded and emptied is still a pump.
        local pump = stationPump(1, 0, { v = 1, q = {}, frac = 0 })
        T.eq(S.isPump(pump), true)
        -- A generator keeps its tank's record under the same mod data key.
        local generator = stationPump(2, 0, { v = 1, q = { gasoline = 5 } })
        generator.class = "IsoGenerator"
        T.eq(S.isPump(generator), false)
        -- An object with neither piped fuel nor a record is not one either.
        local other = stationPump(3, 0, nil)
        T.eq(S.isPump(other), false)
        -- A fixed fluid container the mod has recorded (a barrel) keeps its
        -- record under the same key, without a reservoir's `frac`.
        local barrel = stationPump(4, 0, { v = 1, id = "S7-3", storage = "drum_steel", q = { gasoline = 40 } })
        T.eq(S.isPump(barrel), false)
        -- A pump the mod wrote, run dry: its record has `frac`, as
        -- Stations.writeSidecar always gives it.
        local dry = stationPump(5, 0, { v = 1, id = "R7-1", cap = 10000, frac = 0, product = "diesel", q = {} })
        T.eq(S.isPump(dry), true)
        -- The game's own key for an exhausted pump still counts.
        local vanilla = stationPump(7, 0, nil)
        vanilla.md.fuelAmount = 0
        T.eq(S.isPump(vanilla), true)
    end)
    instanceof = saved
    if not ok then error(err, 0) end
end)

T.case("domain: about one pump in four holds diesel, the same pump every time", function()
    local W = D.WorldInit
    local world, diesel = { seed = 4242 }, 0
    for i = 1, 2000 do
        local key = "pump:" .. i .. ",20,0"
        local p = W.stationProduct(world, key)
        T.ok(p == "diesel" or p == "gasoline", p)
        T.eq(W.stationProduct(world, key), p, "the same draw again")
        if p == "diesel" then diesel = diesel + 1 end
    end
    T.ok(diesel > 2000 * 0.20 and diesel < 2000 * 0.30, "share " .. diesel / 2000)
    -- Another world draws its own pumps.
    local differs = 0
    for i = 1, 200 do
        local key = "pump:" .. i .. ",20,0"
        if W.stationProduct({ seed = 99 }, key) ~= W.stationProduct(world, key) then differs = differs + 1 end
    end
    T.ok(differs > 0, "another seed gives another set")
end)

T.case("integration: a pump's first record holds its draw's fuel, in a world with diesel vehicles only", function()
    local S, W = I.Stations, D.WorldInit
    local g = fakeGame(200)
    local share = W.STATION_DIESEL_SHARE
    local ok, err = pcall(function()
        local world = World.get()
        local srv = World.server()
        srv.seed, srv.nextId = 7, 1
        -- A save from before: every pump is petrol, whatever the draw.
        W.STATION_DIESEL_SHARE = 1
        local rec = S.read(stationPump(1, 500), false)
        T.ok((rec.q.gasoline or 0) > 490 and rec.q.diesel == nil, "petrol in an older save")
        T.eq(rec.product, "gasoline")
        world.dieselVehicles = true
        rec = S.read(stationPump(2, 500), false)
        T.ok((rec.q.diesel or 0) > 490 and rec.q.gasoline == nil, "diesel where the draw says so")
        T.eq(rec.product, "diesel")
        W.STATION_DIESEL_SHARE = 0
        rec = S.read(stationPump(3, 500), false)
        T.ok((rec.q.gasoline or 0) > 490 and rec.q.diesel == nil, "petrol where it does not")
        -- Written, the pump keeps what it gives: a later draw does not change it.
        W.STATION_DIESEL_SHARE = 1
        local pump = stationPump(4, 500)
        rec = S.read(pump, true)
        S.write(pump, rec)
        T.eq(pump.md.tlg.product, "diesel")
        W.STATION_DIESEL_SHARE = 0
        local again = S.read(pump, false)
        T.eq(again.product, "diesel"); T.ok((again.q.diesel or 0) > 490)
        T.eq(S.product(pump), "diesel")
        -- A record rebuilt without the field (a transfer's) is written with it.
        again.product = nil
        S.writeSidecar(pump, again)
        T.eq(pump.md.tlg.product, "diesel")
        -- A record from before the field existed is petrol.
        local old = stationPump(5, 4, sidecar())
        T.eq(S.product(old), "gasoline")
        T.eq(S.read(old, false).product, "gasoline")
    end)
    W.STATION_DIESEL_SHARE = share
    g.restore()
    if not ok then error(err, 0) end
end)
