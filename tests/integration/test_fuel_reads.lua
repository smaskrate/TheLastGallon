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
        rec.q.ethanol, rec.q.water = 4 - 1.5e-4, 1.5e-4
        I.Containers.endpoint(can, "item"):record(rec)
        T.ok(can.md.tlg.q.water == nil, "no water under the game's minimum in the record")
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
