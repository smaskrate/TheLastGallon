-- Mapping between B42 native fluids and TLG components, and helpers to read
-- and write a native FluidContainer's composition.
-- Evidence: RT-DS (engine-capabilities G02): mod fluids register under their
-- bare names (Fluid.Get("TLG_Ethanol")); transfers and adjustAmount scale all
-- fluids proportionally.
require "TLG/Domain/Fuel/Defs"
require "TLG/Util/Tables"

TLG.Integration = TLG.Integration or {}
TLG.Integration.Native = TLG.Integration.Native or {}
local Native = TLG.Integration.Native
local Registry, Tables = TLG.Registry, TLG.Tables

local byFluid = nil

local function buildIndex()
    byFluid = {}
    for _, def in ipairs(Registry.all("fuel")) do
        if def.nativeFluid then byFluid[def.nativeFluid] = def.id end
    end
end

-- Component id for a native fluid type string, or nil when TLG does not track it.
function Native.componentForFluidName(name)
    if byFluid == nil then buildIndex() end
    return byFluid[name]
end

function Native.fluidForComponent(id)
    local def = Registry.get("fuel", id)
    if def == nil or def.nativeFluid == nil then return nil end
    return Fluid.Get(def.nativeFluid)
end

-- Reads { component = litres } and the litres of untracked fluids.
function Native.readComposition(fc)
    local comp, foreign, foreignNames = {}, 0, {}
    local sample = fc:createFluidSample()
    for i = 0, sample:size() - 1 do
        local f = sample:getFluid(i)
        local name = f:getFluidTypeString()
        local amount = fc:getSpecificFluidAmount(f)
        local id = Native.componentForFluidName(name)
        if id then
            comp[id] = (comp[id] or 0) + amount
        else
            foreign = foreign + amount
            foreignNames[#foreignNames + 1] = name
        end
    end
    sample:release()
    return comp, foreign, foreignNames
end

-- True when the container holds only TLG-tracked fuel fluids (or nothing).
function Native.isFuelContainer(fc)
    if fc == nil then return false end
    local comp, foreign = Native.readComposition(fc)
    if foreign > 1e-6 then return false end
    return not Tables.isEmpty(comp)
end

-- What a container can hold (BC 42.21 FluidContainer):
-- * a fluid under 1e-4 L is dropped as empty (removeFluidInstanceIfEmpty);
-- * within 0.001 L of capacity the amount reads as the capacity
--   (recalculateCaches), so isFull() holds and addFluid refuses a new fluid,
--   while adjustSpecificFluidAmount sets one already there without that check.
-- RT-SP run 57: a full petrol can, its petrol lowered for 1.1e-4 L of water,
-- refused the water and lost those litres.
Native.MIN_FLUID = 2e-4 -- a component under this goes to the largest (twice the game's 1e-4)
Native.ROOM = 0.005 -- room kept while new fluids go in (the game's 0.001, with margin)

-- The composition a container can hold: a component under Native.MIN_FLUID
-- goes to the largest, so the litres are kept.
function Native.holdable(comp)
    local out, largest = {}, nil
    for _, id in ipairs(Tables.sortedKeys(comp)) do
        if comp[id] > 1e-9 then
            out[id] = comp[id]
            if largest == nil or comp[id] > comp[largest] then largest = id end
        end
    end
    for _, id in ipairs(Tables.sortedKeys(out)) do
        if id ~= largest and out[id] < Native.MIN_FLUID then
            out[largest] = out[largest] + out[id]
            out[id] = nil
        end
    end
    return out
end

-- Sets the container's fluids to `comp` (litres per component). Used only
-- when TLG itself moved or corrected quantities (decision D-006) or wrote a
-- record (Containers.commit, which passes Native.holdable compositions).
-- New fluids go in smallest first while the largest one already there is
-- held low, so a full container takes them. Returns false when a component
-- has no native fluid.
function Native.writeComposition(fc, comp)
    local target = {}
    for _, id in ipairs(Tables.sortedKeys(comp)) do
        if comp[id] > 1e-9 then
            if Native.fluidForComponent(id) == nil then return false, "no_native_fluid_" .. id end
            target[id] = comp[id]
        end
    end
    local current = Native.readComposition(fc)
    local adds, total, kept = {}, 0, nil
    for _, id in ipairs(Tables.sortedKeys(target)) do
        total = total + target[id]
        if (current[id] or 0) > 0 then
            if kept == nil or target[id] > target[kept] then kept = id end
        else
            adds[#adds + 1] = id
        end
    end
    local low
    if kept and #adds > 0 then
        local need = total - (fc:getCapacity() - Native.ROOM)
        if need > 0 and target[kept] - need >= 10 * Native.MIN_FLUID then low = target[kept] - need end
    end
    for _, id in ipairs(Tables.sortedKeys(current)) do
        local fluid = Native.fluidForComponent(id)
        if target[id] == nil then
            fc:adjustSpecificFluidAmount(fluid, 0)
        elseif id == kept and low then
            fc:adjustSpecificFluidAmount(fluid, low)
        else
            fc:adjustSpecificFluidAmount(fluid, target[id])
        end
    end
    adds = Tables.sort(adds, function(a, b) return target[a] < target[b] end)
    for _, id in ipairs(adds) do fc:addFluid(Native.fluidForComponent(id), target[id]) end
    if low then fc:adjustSpecificFluidAmount(Native.fluidForComponent(kept), target[kept]) end
    return true
end

return Native
