-- Propane content (spec §10): a finite scavenged gas. It is a transitional
-- supply and emergency reserve, never a renewable route (TLG/Domain/Routes).
-- Numbers are design values (docs/balance.md).
--
-- Vanilla Base.PropaneTank is a drainable with 5000 uses and no
-- FluidContainer (RT-DS, decision D-014); TLG.Domain.Gas maps uses <-> Nm3
-- (one full tank = 4.48 Nm3 = 9.0 kg). Propane has no aging parameters, so it
-- never degrades in storage; vessel condition belongs to the container only
-- (fill refusal below the vessel's minimum condition, leaks through the
-- storage profile's leakPerHour).
require "TLG/Content/Fuels"
require "TLG/Content/Storage"
require "TLG/Domain/Gas"
local R, Gas, Supply = TLG.Registry, TLG.Domain.Gas, TLG.Domain.Supply

TLG.Content = TLG.Content or {}
TLG.Content.Propane = TLG.Content.Propane or {}
local Propane = TLG.Content.Propane

-- Residential bulk tank (about 1.9 m3 water capacity filled to 80 %):
-- 380 Nm3 = 764 kg. Farms and rural houses; never refilled by the world.
R.define("storage", { id = "propane_bulk", phase = "gas", capacity = 380, agingMul = 1.0, sealable = false,
    breathing = 0, thermal = "outdoor", leakPerHour = 0 })
Gas.VESSELS.propane_bulk = { accepts = { propane = true }, minFillCond = 0.5 }

-- Vanilla items that hold propane. Only runtime-verified items are listed.
Propane.items = {
    ["Base.PropaneTank"] = { storage = "propane_cylinder", uses = Gas.TANK_USES, nm3 = Gas.TANK_NM3 },
}

-- Gas supply for a vanilla item with `uses` remaining (nil when unknown).
function Propane.supplyFromItem(fullType, uses, o)
    local spec = Propane.items[fullType]
    if spec == nil then return nil end
    o = o or {}
    return Gas.cylinderFromUses(uses, { id = o.id, storage = spec.storage, cond = o.cond, t = o.t })
end

-- Display mass in kg (propane is shown in kg at Gas.PROPANE_KG_PER_NM3).
function Propane.kg(nm3)
    return nm3 * Gas.PROPANE_KG_PER_NM3
end

-- New bulk tank found in the world with `fraction` of its capacity left.
function Propane.bulkTank(fraction, o)
    o = o or {}
    local cap = R.need("storage", "propane_bulk").capacity
    local f = math.max(0, math.min(1, fraction or 0))
    return Supply.new({ id = o.id, storage = "propane_bulk", q = { propane = cap * f }, cond = o.cond, t = o.t })
end

return Propane
