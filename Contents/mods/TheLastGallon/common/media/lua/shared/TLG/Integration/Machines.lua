-- Adapter: production machines as placeable items (decision D-015).
-- Runtime status: SOURCE EVIDENCE ONLY (world-item modData persistence and
-- MP replication NOT RUN).
--
--   state store        machine item modData "tlgProc" (TLG.Domain.Process)
--   processing         only while the item lies on the ground; picking it up
--                      pauses the batch at the next access without crediting
--                      the unknown carried time (conservative)
--   unloaded           lazy, event-exact catch-up on access (Process.advance)
--   owner of           machine inputs, outputs, firebox fuel (all TLG-owned)
require "TLG/Domain/Production/Process"
require "TLG/Persistence/Migrations"
require "TLG/Integration/World"
require "TLG/Content/Production"

TLG.Integration.Machines = TLG.Integration.Machines or {}
local M = TLG.Integration.Machines
local Process, World, Tables = TLG.Domain.Process, TLG.World, TLG.Tables

M.SIDECAR = "tlgProc"
M.ITEMS = {
    ["TLG.FermenterVessel"] = "fermenter_barrel",
    ["TLG.PotStill"] = "pot_still",
    ["TLG.RefluxStill"] = "reflux_still",
    ["TLG.DryingColumn"] = "drying_column",
}

function M.machineFor(item)
    return item and M.ITEMS[item:getFullType()] or nil
end

function M.isPlaced(item)
    return item:getWorldItem() ~= nil
end

function M.square(item)
    local wi = item:getWorldItem()
    return wi and wi:getSquare() or nil
end

-- Committed process record for a machine item (nil for non-machines or
-- unknown future schemas, which stay untouched).
function M.read(item, persist)
    local machine = M.machineFor(item)
    if machine == nil then return nil, "not_a_machine" end
    local raw = item:getModData()[M.SIDECAR]
    local rec, status = TLG.Persistence.Migrations.sidecar("process", raw)
    if raw ~= nil and rec == nil then return nil, status end
    if rec == nil then
        rec = Process.new({ id = persist and World.newId("P") or nil, machine = machine, t = World.now() })
    end
    return Tables.deepCopy(rec), "ok"
end

-- Brings a machine to `now`: processing only counts while placed.
function M.advance(item, rec, now, env)
    if rec.state == "Processing" or rec.state == "Paused" then
        if not M.isPlaced(item) then
            local out = Tables.deepCopy(rec)
            if out.state == "Processing" then
                out.state, out.pause = "Paused", "not_placed"
            end
            out.t = now
            return out
        end
        if rec.pause == "not_placed" then
            local out = Tables.deepCopy(rec)
            out.state, out.pause, out.t = "Processing", nil, now
            return Process.advance(out, now, env)
        end
    end
    return (Process.advance(rec, now, env))
end

function M.write(item, rec)
    item:getModData()[M.SIDECAR] = rec
    if item.syncItemFields then item:syncItemFields() end
    local wi = item:getWorldItem()
    if wi and wi.transmitModData then pcall(function() wi:transmitModData() end) end
end

-- Machine items within reach of a square (for still <- fermenter loading).
function M.nearbyMachines(square, radius, kind)
    local out = {}
    if square == nil then return out end
    local cell = getCell()
    for dx = -radius, radius do
        for dy = -radius, radius do
            local sq = cell:getGridSquare(square:getX() + dx, square:getY() + dy, square:getZ())
            if sq then
                local wobjs = sq:getWorldObjects()
                for i = 0, wobjs:size() - 1 do
                    local it = wobjs:get(i):getItem()
                    local mid = M.machineFor(it)
                    if mid and (kind == nil or TLG.Registry.need("machine", mid).kind == kind) then
                        out[#out + 1] = it
                    end
                end
            end
        end
    end
    return out
end

-- Finds a machine item by id on a square or in the player's inventory.
function M.find(player, ref)
    if type(ref) ~= "table" or type(ref.id) ~= "number" then return nil end
    if ref.x and ref.y and ref.z then
        local sq = getCell():getGridSquare(ref.x, ref.y, ref.z)
        if sq then
            local wobjs = sq:getWorldObjects()
            for i = 0, wobjs:size() - 1 do
                local it = wobjs:get(i):getItem()
                if it and it:getID() == ref.id then return it end
            end
        end
    end
    return player and player:getInventory():getItemWithIDRecursiv(ref.id) or nil
end

function M.refFor(item)
    local sq = M.square(item)
    if sq then return { kind = "machine", id = item:getID(), x = sq:getX(), y = sq:getY(), z = sq:getZ() } end
    return { kind = "machine", id = item:getID() }
end

return M
