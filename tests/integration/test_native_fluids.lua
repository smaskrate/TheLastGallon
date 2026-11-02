require "support/fixtures"
require "TLG/Integration/Native"
local Native = TLG.Integration.Native

-- Stand-ins for the game's fluids and FluidContainer, with the rules that
-- matter here as BC 42.21 has them:
-- * the amount reads as the capacity within 0.001 L of it (recalculateCaches);
-- * isFull() is the amount within 1e-4 L of capacity (PZMath.equal);
-- * addFluid refuses a full container and clips to the room left;
-- * adjustSpecificFluidAmount sets a fluid already there (nothing when the
--   container is empty) and drops it under 1e-4 L (removeFluidInstanceIfEmpty).
local function fakeFluids()
    local saved, byName = Fluid, {}
    Fluid = { Get = function(name)
        if byName[name] == nil then
            local f = { name = name }
            function f:getFluidTypeString() return self.name end
            byName[name] = f
        end
        return byName[name]
    end }
    return function() Fluid = saved end
end

local function container(capacity, fills)
    local fc = { cap = capacity, list = {} }
    local function sum()
        local s = 0
        for _, e in ipairs(fc.list) do s = s + e.amount end
        return s
    end
    function fc:getCapacity() return self.cap end
    function fc:getAmount()
        local s = sum()
        if self.cap - s < 0.001 then return self.cap end
        return s
    end
    function fc:isFull() return math.abs(self.cap - self:getAmount()) < 1e-4 end
    function fc:isEmpty() return self:getAmount() == 0 end
    function fc:addFluid(fluid, amount)
        amount = math.max(0, amount)
        if amount <= 0 or self:isFull() then return end
        amount = math.min(amount, self.cap - self:getAmount())
        for _, e in ipairs(self.list) do
            if e.fluid == fluid then
                e.amount = e.amount + amount
                return
            end
        end
        self.list[#self.list + 1] = { fluid = fluid, amount = amount }
    end
    function fc:adjustSpecificFluidAmount(fluid, amount)
        if self:isEmpty() then return end
        amount = math.max(0, math.min(amount, self.cap))
        for i = #self.list, 1, -1 do
            if self.list[i].fluid == fluid then
                self.list[i].amount = amount
                if math.abs(amount) < 1e-4 then table.remove(self.list, i) end
            end
        end
    end
    function fc:getSpecificFluidAmount(fluid)
        for _, e in ipairs(self.list) do
            if e.fluid == fluid then return e.amount end
        end
        return 0
    end
    function fc:createFluidSample()
        local s, fluids = {}, {}
        for i, e in ipairs(self.list) do fluids[i] = e.fluid end
        function s:size() return #fluids end
        function s:getFluid(i) return fluids[i + 1] end
        function s:release() end
        return s
    end
    for _, f in ipairs(fills or {}) do fc:addFluid(Fluid.Get(f[1]), f[2]) end
    return fc
end

local function holds(fc, want, label)
    local comp = Native.readComposition(fc)
    for id, v in pairs(want) do T.near(comp[id] or 0, v, 1e-9, label .. ": " .. id) end
    for id, v in pairs(comp) do T.near(want[id] or 0, v, 1e-9, label .. ": " .. id) end
end

T.case("native: a full can takes the water its record gained, the litres kept", function()
    local restore = fakeFluids()
    local ok, err = pcall(function()
        -- RT-SP run 57: the petrol lowered first, the full can refused the water.
        local fc = container(10, { { "Petrol", 10 } })
        T.ok(Native.writeComposition(fc, { gasoline = 10 - 1.117e-4, water = 1.117e-4 }))
        holds(fc, { gasoline = 10 - 1.117e-4, water = 1.117e-4 }, "full can")
    end)
    restore()
    if not ok then error(err, 0) end
end)

T.case("native: a can filled to the brim at a pump keeps the station's water and sediment", function()
    local restore = fakeFluids()
    local ok, err = pcall(function()
        -- The game put 10 L of Petrol in; the parcel was a clean station's
        -- fuel, whose traces bring the can within 0.001 L of full one by one.
        local fc = container(10, { { "Petrol", 10 } })
        T.ok(Native.writeComposition(fc, { gasoline = 9.9987, sediment = 0.0005, water = 0.0008 }))
        holds(fc, { gasoline = 9.9987, sediment = 0.0005, water = 0.0008 }, "pump fill")
    end)
    restore()
    if not ok then error(err, 0) end
end)

T.case("native: a fluid replaced by another, and fluids set without new ones", function()
    local restore = fakeFluids()
    local ok, err = pcall(function()
        local fc = container(10, { { "Petrol", 5 } })
        T.ok(Native.writeComposition(fc, { ethanol = 5 }))
        holds(fc, { ethanol = 5 }, "replaced")
        local mixed = container(20, { { "TLG_Ethanol", 8 }, { "TLG_FuelWater", 0.5 } })
        T.ok(Native.writeComposition(mixed, { ethanol = 7.9, water = 0.6 }))
        holds(mixed, { ethanol = 7.9, water = 0.6 }, "set")
        local ok2, why = Native.writeComposition(mixed, { propane = 1 })
        T.ok(ok2 == false and why == "no_native_fluid_propane", "a gas has no native fluid: " .. tostring(why))
        holds(mixed, { ethanol = 7.9, water = 0.6 }, "untouched after the refusal")
    end)
    restore()
    if not ok then error(err, 0) end
end)

T.case("native: what a container can hold keeps the litres", function()
    local held = Native.holdable({ gasoline = 9.9998, water = 1.5e-4, sediment = 5e-5, ethanol = 1e-12 })
    T.near(held.gasoline, 10, 1e-12, "the small ones went to the largest")
    T.ok(held.water == nil and held.sediment == nil and held.ethanol == nil, "nothing under the game's minimum left")
    local big = Native.holdable({ gasoline = 9, water = 0.5 })
    T.near(big.gasoline, 9, 0); T.near(big.water, 0.5, 0)
end)
