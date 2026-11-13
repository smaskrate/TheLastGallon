-- Adapter: the gasifier (D-040, wood gas), a machine item placed within two
-- tiles of a gas generator, as the biodiesel machines hand their products
-- on (D-036).
--
--   state store   item mod data "tlgGasifier": a TLG.Domain.Gas.Gasifier
--                 record (record kind "gasifier") and `site`, the tile it was
--                 lit on; checked against the vault on a server (holder the
--                 item, audit V-01). On a server each write of a gasifier no
--                 character carries is also sent to the clients
--                 (WorldItemRecords), whose menus read their own copy
--   advance       lazy, on every authority read, with no draw: a generator's
--                 refill draws the gas it takes in a lump (Gasifier.draw),
--                 once an hour while the generator runs, which keeps it lit;
--                 with nobody drawing it waits with its buffer full and goes
--                 out after its hold (3 h). One large advance equals many
--                 small ones, so nothing advances it on a timer.
--   moves         it burns only where it was lit: a record that says lit
--                 whose item is carried, or lies on another tile, is put out
--                 at its next read, its hopper kept. No move hooks.
--   the generator TLG/Integration/Generators draws from it on the minute pass
--                 (GZ.drawNear) when no propane tank with uses is in.
require "TLG/Domain/Gas"
require "TLG/Persistence/Migrations"
require "TLG/Integration/World"
require "TLG/Content/WoodGas"
require "TLG/Authority/Vault"
require "TLG/Integration/WorldItemRecords"

TLG.Integration = TLG.Integration or {}
TLG.Integration.Gasifiers = TLG.Integration.Gasifiers or {}
local GZ = TLG.Integration.Gasifiers
local Gasifier, World, Tables, Vault = TLG.Domain.Gas.Gasifier, TLG.World, TLG.Tables, TLG.Authority.Vault

GZ.KEY = "tlgGasifier"
GZ.ITEMS = { ["TLG.Gasifier"] = "gasifier_stationary" }
-- How far from a gas generator a gasifier feeds it, in tiles on its floor.
GZ.RADIUS = 2

function GZ.machineFor(item)
    return item and GZ.ITEMS[item:getFullType()] or nil
end

function GZ.isPlaced(item)
    return item:getWorldItem() ~= nil
end

function GZ.square(item)
    local wi = item:getWorldItem()
    return wi and wi:getSquare() or nil
end

local function send(item)
    if item.syncItemFields then item:syncItemFields() end
    local wi = item:getWorldItem()
    if wi and wi.transmitModData then pcall(function() wi:transmitModData() end) end
end

-- The record as stored, checked against the vault on a server.
function GZ.stored(item)
    return Vault.guard("gasifier", Vault.itemHolder(item), item:getModData(), GZ.KEY, function() send(item) end)
end

-- A copy of the record, a new cold one when the item has none (an id only
-- when `persist`), or nil and why: not a gasifier, or a newer build's
-- record (left as it is).
function GZ.read(item, persist)
    local machine = GZ.machineFor(item)
    if machine == nil then return nil, "not_a_gasifier" end
    local raw = GZ.stored(item)
    local rec, status = TLG.Persistence.Migrations.sidecar("gasifier", raw)
    if raw ~= nil and rec == nil then return nil, status end
    if rec == nil then
        rec = Gasifier.new({ id = persist and World.newId("W") or nil, machine = machine, t = World.now() })
    end
    return Tables.deepCopy(rec), "ok"
end

-- Lit: burning, or paused and still hot.
function GZ.lit(st)
    return st.state == "Processing" or st.state == "Paused"
end

function GZ.siteOf(sq)
    return { x = sq:getX(), y = sq:getY(), z = sq:getZ() }
end

local function onSite(st, sq)
    local s = st.site
    return s ~= nil and sq ~= nil and s.x == sq:getX() and s.y == sq:getY() and (s.z or 0) == sq:getZ()
end

-- Brings a gasifier to `now` with no draw. One lit that is carried or lies
-- on another tile than its site is put out there, its hopper kept.
function GZ.advance(item, st, now)
    local out = st
    if now > st.t then out = (Gasifier.advance(st, now, 0)) end
    if GZ.lit(out) and not onSite(out, GZ.square(item)) then
        local p = Gasifier.putOut(out, out.t, "moved")
        if p.ok then out = p.st end
    end
    return out
end

-- On a server, the record written for a gasifier no character carries also
-- goes to the clients, whose menus read their own copy
-- (TLG/Integration/WorldItemRecords.lua, D-041).
function GZ.write(item, st)
    item:getModData()[GZ.KEY] = st
    Vault.put("gasifier", Vault.itemHolder(item), st)
    send(item)
    TLG.Integration.WorldItemRecords.send(item, GZ.KEY, st)
end

-- Gasifier items lying within `radius` tiles of `sq` on its floor, in the
-- order of their ids.
function GZ.near(sq, radius)
    local out = {}
    if sq == nil then return out end
    local cell = getCell()
    for dx = -radius, radius do
        for dy = -radius, radius do
            local s = cell:getGridSquare(sq:getX() + dx, sq:getY() + dy, sq:getZ())
            local wobjs = s and s:getWorldObjects()
            for i = 0, (wobjs and wobjs:size() or 0) - 1 do
                local it = wobjs:get(i):getItem()
                if GZ.machineFor(it) then out[#out + 1] = it end
            end
        end
    end
    return Tables.sort(out, function(a, b) return a:getID() < b:getID() end)
end

-- On the authority: up to `nm3` of wood gas for a generator on `sq`, drawn
-- from the gasifiers within RADIUS in the order of their ids. Each one drawn
-- from, or put out because it moved, is written. Returns the Nm3 taken.
function GZ.drawNear(sq, nm3, now)
    local got = 0
    for _, item in ipairs(GZ.near(sq, GZ.RADIUS)) do
        if got >= nm3 then break end
        if item:getModData()[GZ.KEY] ~= nil then
            local st = GZ.read(item, false)
            if st ~= nil then
                local before = st.state
                st = GZ.advance(item, st, now)
                local d = Gasifier.draw(st, nm3 - got, now)
                if d.ok and d.taken > 0 then
                    got = got + d.taken
                    GZ.write(item, d.st)
                elseif st.state ~= before then
                    GZ.write(item, st)
                end
            end
        end
    end
    return got
end

-- A gasifier item by id, on the square the reference names or in the
-- player's inventory.
function GZ.find(player, ref)
    if type(ref) ~= "table" or type(ref.id) ~= "number" then return nil end
    if ref.x and ref.y and ref.z then
        local sq = getCell():getGridSquare(ref.x, ref.y, ref.z)
        local wobjs = sq and sq:getWorldObjects()
        for i = 0, (wobjs and wobjs:size() or 0) - 1 do
            local it = wobjs:get(i):getItem()
            if it and it:getID() == ref.id and GZ.machineFor(it) then return it end
        end
    end
    local it = player and player:getInventory():getItemWithIDRecursiv(ref.id) or nil
    return GZ.machineFor(it) and it or nil
end

function GZ.refFor(item)
    local sq = GZ.square(item)
    if sq then return { kind = "gasifier", id = item:getID(), x = sq:getX(), y = sq:getY(), z = sq:getZ() } end
    return { kind = "gasifier", id = item:getID() }
end

-- The gas generators within RADIUS of a gasifier join the refills' list,
-- and look for its gas at their next refill (an action on the gasifier:
-- the generator may have stopped looking, Generators.woodgasRefill).
function GZ.watchGenerators(item)
    local G, sq = TLG.Integration.Generators, GZ.square(item)
    if G == nil or sq == nil then return 0 end
    local n, cell = 0, getCell()
    for dx = -GZ.RADIUS, GZ.RADIUS do
        for dy = -GZ.RADIUS, GZ.RADIUS do
            local s = cell:getGridSquare(sq:getX() + dx, sq:getY() + dy, sq:getZ())
            local gen = s and s:getGenerator()
            if gen ~= nil then
                G.watchGas(gen)
                n = n + 1
            end
        end
    end
    return n
end

return GZ
