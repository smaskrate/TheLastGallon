-- A gas generator's feed (D-040). The generator's own fuel holds gas already
-- taken from its source, as the petrol litres of the same energy, and the
-- game burns that fuel in its hourly steps (launches 342, 345-349). The
-- record (object mod data "tlgGas", kind "gas") keeps the gas in that
-- buffer, in Nm3 by gas, as of the litres the generator held when it was
-- written, and the propane tank inserted into the generator, in whole uses
-- (the game keeps whole uses on a tank item, launches 342 and 345):
--
--   { v = 1, id, buf = { propane = Nm3, ... }, fuel = litres when written,
--     tank = nil | { uses = n }, t = hours }
--
-- The game burns the mix in proportion, so the gas left is buf scaled by
-- the litres held now over `fuel`. A refill tops the litres up to the cap
-- with whole uses from the tank, and the uses taken are the propane added:
-- nothing is made or lost. The buffer stays less than one use below the
-- cap; the next refill's room includes the rest. Without a tank with uses
-- left, wood gas drawn from a gasifier beside the generator fills the
-- buffer the same way (F.feed), to a lower cap: one hourly step and a margin
-- (D-040). Pure functions; the adapter is TLG/Integration/Generators.
require "TLG/Domain/Gas"

TLG.Domain = TLG.Domain or {}
TLG.Domain.GasFeed = TLG.Domain.GasFeed or {}
local F = TLG.Domain.GasFeed
local Gas, Supply = TLG.Domain.Gas, TLG.Domain.Supply
local Registry, Tables = TLG.Registry, TLG.Tables

F.SCHEMA = 1
-- Litres taken as equal, as TLG.Integration.Generators.read takes them.
F.TOLERANCE = 1e-4
-- What a wood-gas buffer holds above one hourly step, so that a step
-- leaves fuel and the generator runs on (D-040: one step plus 1e-4 L ran on,
-- launch 346). Ten times TOLERANCE, so that the litres a step leaves still
-- read as gas.
F.MARGIN = 1e-3

local function fail(reason) return { ok = false, reason = reason } end

local function litreMJ() return Registry.need("fuel", "gasoline").energyMJ end
local function propaneMJ() return Registry.need("fuel", "propane").energyMJ end

-- Litres of petrol with the energy of `buf` (Nm3 by gas).
function F.litresOf(buf)
    return Gas.energyMJ(buf or {}) / litreMJ()
end

-- Litres of petrol with the energy of `nm3` of propane.
function F.propaneLitres(nm3)
    return nm3 * propaneMJ() / litreMJ()
end

function F.new(o)
    o = o or {}
    return { v = F.SCHEMA, id = o.id, buf = {}, fuel = 0, t = o.t or 0 }
end

-- The gas left in the buffer when the generator holds `fuelNow` litres. A
-- rise past the litres written is not gas the mod gave: it is not counted.
function F.current(rec, fuelNow)
    local out, held = {}, rec.fuel or 0
    local k = 0
    if held > 0 then k = math.min(1, math.max(0, fuelNow or 0) / held) end
    for _, id in ipairs(Tables.sortedKeys(rec.buf or {})) do
        local left = rec.buf[id] * k
        if left > 0 then out[id] = left end
    end
    return out
end

-- Whether the buffer holds gas. Only then are the generator's liquid paths
-- refused: a converted generator that still holds petrol (a save from
-- before the feed) is drained as any other.
function F.holdsGas(rec, fuelNow)
    return rec ~= nil and (rec.fuel or 0) > F.TOLERANCE and (fuelNow or 0) > F.TOLERANCE
end

-- Inserts a tank with `uses` left. One tank at a time.
function F.connect(rec, uses, now)
    if rec.tank ~= nil then return fail("tank_connected") end
    if type(uses) ~= "number" or uses ~= uses or uses < 1 then return fail("tank_empty") end
    local out = Tables.deepCopy(rec)
    out.tank = { uses = math.min(Gas.TANK_USES, math.floor(uses + Gas.USE_TOLERANCE)) }
    out.t = now or out.t
    return { ok = true, rec = out }
end

-- The whole tank uses a room of `litres` takes, energy for energy: what a
-- refill moves at most (0 when less than one use fits, or for a malformed
-- room).
function F.usesFor(litres)
    return (Gas.nm3ToUses(litres * litreMJ() / propaneMJ())) or 0
end

-- Tops the buffer up to `cap` litres with whole uses from the tank. Returns
-- the record, the litres to set and the uses moved (0: nothing to write).
function F.refill(rec, fuelNow, cap, now)
    local tank, room = rec.tank, cap - fuelNow
    if tank == nil or tank.uses < 1 or room <= F.TOLERANCE then
        return { ok = true, moved = 0, rec = rec, fuel = fuelNow }
    end
    local uses = math.min(F.usesFor(room), tank.uses)
    if uses < 1 then return { ok = true, moved = 0, rec = rec, fuel = fuelNow } end
    local add = Gas.usesToNm3(uses)
    local out = Tables.deepCopy(rec)
    out.buf = F.current(rec, fuelNow)
    out.buf.propane = (out.buf.propane or 0) + add
    out.tank.uses = tank.uses - uses
    out.fuel = fuelNow + F.propaneLitres(add)
    out.t = now or out.t
    return { ok = true, moved = uses, rec = out, fuel = out.fuel }
end

-- Tops the buffer up towards `cap` litres with up to `nm3` of gas `id`
-- drawn from a producer (D-040, wood gas from a gasifier), energy for
-- energy, never past the cap. Returns the record, the litres to set and the
-- Nm3 taken (0: nothing to write).
function F.feed(rec, fuelNow, cap, id, nm3, now)
    local room = cap - fuelNow
    if room <= 0 or not (type(nm3) == "number" and nm3 > 0) then
        return { ok = true, taken = 0, rec = rec, fuel = fuelNow }
    end
    local mj = Registry.need("fuel", id).energyMJ
    local take = math.min(nm3, room * litreMJ() / mj)
    local out = Tables.deepCopy(rec)
    out.buf = F.current(rec, fuelNow)
    out.buf[id] = (out.buf[id] or 0) + take
    out.fuel = math.min(cap, fuelNow + take * mj / litreMJ())
    out.t = now or out.t
    return { ok = true, taken = take, rec = out, fuel = out.fuel }
end

-- Nm3 of gas `id` with the energy of `litres` of petrol.
function F.nm3For(id, litres)
    return litres * litreMJ() / Registry.need("fuel", id).energyMJ
end

-- Takes the tank out. The propane the buffer has not burned goes back into
-- it in whole uses, up to a full tank; the rest stays in the buffer, so a
-- tank taken back straight after connecting is as full as it went in, less
-- at most a use. Returns the record, the litres to set and the tank's uses.
function F.disconnect(rec, fuelNow, now)
    if rec.tank == nil then return fail("no_tank") end
    local out = Tables.deepCopy(rec)
    out.buf = F.current(rec, fuelNow)
    local held = out.buf.propane or 0
    local back = math.min(Gas.TANK_USES - rec.tank.uses, Gas.nm3ToUses(held) or 0)
    local taken = Gas.usesToNm3(back)
    if held - taken > 0 then out.buf.propane = held - taken else out.buf.propane = nil end
    out.tank = nil
    out.fuel = math.max(0, fuelNow - F.propaneLitres(taken))
    out.t = now or out.t
    return { ok = true, rec = out, uses = rec.tank.uses + back, fuel = out.fuel }
end

-- Removing the conversion lets out what the buffer holds.
function F.vent(rec, now)
    local out = Tables.deepCopy(rec)
    out.buf, out.fuel, out.t = {}, 0, now or out.t
    return out
end

-- The buffer as a gas supply, for Consumers.evaluate (it reads shares).
function F.supply(rec, fuelNow)
    return Supply.new({ id = rec.id, storage = "gas_buffer", q = F.current(rec, fuelNow), t = rec.t })
end

return F
