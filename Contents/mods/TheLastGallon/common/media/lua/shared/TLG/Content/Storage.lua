-- StorageProfile content (docs/balance.md).
--   capacity   default capacity in canonical units (adapters may override)
--   agingMul   multiplier on fuel aging (permeation, venting, heat cycles)
--   vented     true when the vessel always breathes (no seal state)
--   sealable   player can seal/unseal it
--   breathing  moisture exchange per hour at humidity 1.0 when unsealed
--   thermal    outdoor | sheltered | ground (see TLG/Domain/Climate)
--   leakPerHour  fraction of gas lost per hour at condition 1.0 (gases)
require "TLG/Domain/Fuel/Defs"
local R = TLG.Registry

R.define("storage", { id = "jerrycan_steel", phase = "liquid", capacity = 20, agingMul = 1.0, sealable = true,
    breathing = 2e-6, thermal = "sheltered" })
R.define("storage", { id = "gascan_plastic", phase = "liquid", capacity = 10, agingMul = 1.15, sealable = true,
    breathing = 4e-6, thermal = "sheltered" })
R.define("storage", { id = "bottle", phase = "liquid", capacity = 1, agingMul = 1.0, sealable = true,
    breathing = 1e-6, thermal = "sheltered" })
R.define("storage", { id = "drum_steel", phase = "liquid", capacity = 200, agingMul = 0.95, sealable = true,
    breathing = 1.5e-6, thermal = "sheltered" })
R.define("storage", { id = "open_vessel", phase = "liquid", agingMul = 1.0, sealable = false,
    breathing = 2e-5, thermal = "sheltered" })
R.define("storage", { id = "vehicle_tank", phase = "liquid", agingMul = 1.25, vented = true,
    breathing = 3e-6, thermal = "outdoor" })
R.define("storage", { id = "generator_tank", phase = "liquid", agingMul = 1.3, vented = true,
    breathing = 3e-6, thermal = "outdoor" })
R.define("storage", { id = "station_ust", phase = "liquid", capacity = 10000, agingMul = 0.9, vented = true,
    breathing = 1e-6, thermal = "ground" })
R.define("storage", { id = "tank_ibc", phase = "liquid", capacity = 1000, agingMul = 1.0, sealable = true,
    breathing = 2e-6, thermal = "sheltered" })
-- Unknown native container discovered without TLG state (pessimistic).
R.define("storage", { id = "unknown", phase = "liquid", agingMul = 1.3, vented = true,
    breathing = 5e-6, thermal = "outdoor" })

R.define("storage", { id = "propane_cylinder", phase = "gas", capacity = 4.48, agingMul = 1.0, sealable = false,
    breathing = 0, thermal = "sheltered", leakPerHour = 0 })
R.define("storage", { id = "gas_holder", phase = "gas", capacity = 20, agingMul = 1.0, sealable = false,
    breathing = 0, thermal = "outdoor", leakPerHour = 0.0005 })
-- A gas generator's buffer (D-040, TLG/Domain/GasFeed): the gas its own
-- fuel stands for, read for its shares. The capacity bounds nothing there.
R.define("storage", { id = "gas_buffer", phase = "gas", capacity = 100, agingMul = 1.0, sealable = false,
    breathing = 0, thermal = "sheltered", leakPerHour = 0 })

return true
