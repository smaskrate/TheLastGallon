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

-- Sets the container's fluids to exactly `comp` (litres per component).
-- Used only when TLG itself moved or corrected quantities (decision D-006).
-- Returns false when a component has no native fluid.
function Native.writeComposition(fc, comp)
    local current = Native.readComposition(fc)
    for _, id in ipairs(Tables.sortedKeys(comp)) do
        if Native.fluidForComponent(id) == nil and comp[id] > 1e-9 then return false, "no_native_fluid_" .. id end
    end
    for _, id in ipairs(Tables.sortedKeys(current)) do
        if (comp[id] or 0) <= 1e-9 then
            fc:adjustSpecificFluidAmount(Native.fluidForComponent(id), 0)
        end
    end
    for _, id in ipairs(Tables.sortedKeys(comp)) do
        local want = comp[id]
        if want > 1e-9 then
            local fluid = Native.fluidForComponent(id)
            if (current[id] or 0) > 0 then
                fc:adjustSpecificFluidAmount(fluid, want)
            else
                fc:addFluid(fluid, want)
            end
        end
    end
    return true
end

return Native
