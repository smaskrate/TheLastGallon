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

-- Stand-ins for the game calls the fuel reads make: global ModData and the
-- clock (World.now, World.env), and the native fluids of a can, petrol only.
-- The untracked baseline is fixed, since what matters here is when the
-- inflow mixes in. Installed for one case and removed again.
local GLOBALS = { "ModData", "getGameTime" }
local BASE = 0.07

local function fakeGame(now)
    local saved = {}
    for _, k in ipairs(GLOBALS) do saved[k] = _G[k] end
    local g = { now = now, store = {} }
    ModData = { getOrCreate = function(k)
        g.store[k] = g.store[k] or {}
        return g.store[k]
    end }
    local clock = {}
    function clock:getWorldAgeHours() return g.now end
    getGameTime = function() return clock end
    local md = World.get()
    md.v, md.calendar, md.climateLog = 1, { dayOfYear = 190, hourOfDay = 9 }, {}
    local untracked, readComposition = I.Containers.untrackedDeg, I.Native.readComposition
    I.Containers.untrackedDeg = function() return BASE end
    I.Native.readComposition = function(fc) return { gasoline = fc.owner.litres }, 0, {} end
    function g.restore()
        for _, k in ipairs(GLOBALS) do _G[k] = saved[k] end
        I.Containers.untrackedDeg, I.Native.readComposition = untracked, readComposition
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
    local fc = { owner = x }
    function fc:getCapacity() return 10 end
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
