-- The records the mod keeps in mod data a client can rewrite, kept again on
-- the server (security audit 2026-11-05, V-01).
--
-- A multiplayer client can replace, on the server, the mod data of an item
-- (SyncItemFields, SyncItemModData) and of a world object (ObjectModData):
-- the engine applies those packets as they come (BC 42.21). The fuel records
-- of items, pumps, generators and world containers ("tlg"), the machines'
-- process records ("tlgProc"), and the generators' conversion projects
-- ("tlgConv") and wear ("tlgWear") live there. The vault keeps in the server
-- store (TLG.World.store, saved with the world in gos_tlgworld.bin and never
-- sent to clients) each record as the authority last wrote it, and the
-- holder it was written to. Every authority read goes through Vault.guard,
-- which puts the record back where the mod data differs.
--
-- The vault holds the very table the authority put in the mod data, not a
-- copy. A packet never changes that table: the engine loads one into the
-- mod data by wiping it and building new tables for every value
-- (KahluaTableImpl.load, BC 42.21), so a forged record is always another
-- table. A read that finds the vault's table is the record as written, at
-- no cost; another table is compared field by field: equal (after a load
-- from the save the two are separate tables), it becomes the vault's; not
-- equal, the vault's goes back in its place. Copying and comparing whole
-- records on every access cost up to 1.3 ms per machine with 480 readings.
--
-- A machine's process record also carries its hourly readings and ten-minute
-- fire notes ("temps", "fires": up to 480 hours of each, about 50 KB as
-- saved). The engine saves the whole store in one 10 MB buffer and, past it,
-- leaves the file empty (SGlobalObjectSystem.save, BC 42.21), and a
-- dedicated server saves it with no Lua event first (ServerMap.QueuedSaveAll).
-- So the vault saves such a record without them, about 1.2 KB, and for each
-- a digest under keys only the server store holds (Vault.DIGESTED). The table
-- written stays in this Lua state for the identity check. A record found with
-- other readings or notes than the authority wrote loses them: the batch
-- reads those hours at the site's unheated value. A record put back after a
-- restart, when this Lua state no longer has the table written, has none.
--
--   holder        who holds a record: "item:<item id>" (the engine keeps an
--                 item's id across saves, BC InventoryItem.save and load),
--                 "pump:x,y,z", "gen:x,y,z", "obj:x,y,z"
--   known id      same content: read as it is; other content: the server's
--                 record is put back. Found on another holder, it moves
--                 there (a move no Lua saw) when that holder never had one; a
--                 holder with a record of its own gets its own back, and one
--                 whose record moved away reads as untracked
--   no record     a holder that had one gets it back (a removed record)
--   unknown id    allocated before the vault existed: adopted as found
--                 (saves from before it) when no larger than ADOPT_BYTES;
--                 otherwise dropped, and the holder reads as untracked fuel
--                 or an idle machine
--
-- Only on a server (dedicated, or the server of a hosted game): in single
-- player no other client can write, and loading the world there drops the
-- vault (it would go stale). Without the server store (before it loads,
-- or if it failed) records are read as found, as before the vault. Vehicle
-- parts are not covered: their mod data reaches a server only from the
-- server (BaseVehicle.transmitPartModData acts only when GameServer.server).
require "TLG/Core"
require "TLG/Util/Tables"
require "TLG/Util/Rng"
require "TLG/Integration/World"

TLG.Authority = TLG.Authority or {}
TLG.Authority.Vault = TLG.Authority.Vault or {}
local Vault = TLG.Authority.Vault
local Tables = TLG.Tables

Vault.SCHEMA = 1
-- Numbers count as equal within this relative difference (both copies are
-- doubles saved as doubles; the margin only absorbs a conversion on the way).
Vault.TOLERANCE = 1e-9
-- A record taken as found from client-writable mod data (an id from before
-- the vault, a generator's wear) is kept only up to this size as saved.
Vault.ADOPT_BYTES = 8192
-- Entries a digested field may hold (the authority keeps at most 482).
Vault.MAX_ENTRIES = 1024
-- Record fields kept as a digest rather than as written, per kind: field ->
-- what one entry holds ("value": a reading; "note": false or a fire note).
Vault.DIGESTED = { process = { temps = "value", fires = "note" } }
-- The fields of a fire note (Machines.warmingFire). A note with another
-- field is not one the authority wrote.
Vault.NOTE_FIELDS = { "t", "f", "x", "y", "r", "c", "rad", "k", "rmax" }

local function onServer()
    return type(isServer) == "function" and isServer() == true
end

local function vault()
    local store = TLG.World.store
    local v = store and store.vault
    if type(v) ~= "table" or v.v ~= Vault.SCHEMA then return nil end
    return v
end

function Vault.active()
    return onServer() and vault() ~= nil
end

local function same(a, b)
    if a == b then return true end
    local ta = type(a)
    if ta ~= type(b) then return false end
    if ta == "number" then
        return math.abs(a - b) <= Vault.TOLERANCE * math.max(1, math.abs(a), math.abs(b))
    end
    if ta ~= "table" then return false end
    for k, x in pairs(a) do
        if not same(x, b[k]) then return false end
    end
    for k in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
end
Vault.same = same

-- `raw` against a saved form without the `skip` fields.
local function sameExcept(raw, saved, skip)
    if type(raw) ~= "table" or type(saved) ~= "table" then return false end
    for k, x in pairs(raw) do
        if not skip[k] and not same(x, saved[k]) then return false end
    end
    for k in pairs(saved) do
        if raw[k] == nil then return false end
    end
    return true
end

-- Size of x as KahluaTableImpl.save writes it (a count, then a type byte and
-- the payload of every key and value; a string with a short length), or nil
-- once over `budget`.
local function bytes(x, budget)
    local t = type(x)
    if t == "string" then return 3 + #x end
    if t == "number" then return 9 end
    if t == "boolean" then return 2 end
    if t ~= "table" then return 0 end
    local n = 5
    for k, y in pairs(x) do
        local a = bytes(k, budget - n)
        if a == nil then return nil end
        n = n + a
        local b = bytes(y, budget - n)
        if b == nil then return nil end
        n = n + b
        if n > budget then return nil end
    end
    return n
end
Vault.bytes = bytes

-- Digests. One of a field is the sum, mod P, over its entries (hour h, entry
-- x) of enc(x) / (h + w), where w and the bases and weights enc uses are
-- secret and live only in the server store. A reading is its value folded
-- with a base; a note, the sum over its fields of a weight per field name
-- times the value folded. For keys drawn at random, two different fields
-- give the same sum with probability about (entries that differ + 20) / P
-- (a nonzero rational function of the keys vanishing at them;
-- Schwartz-Zippel). A sum does not depend on the order pairs gives the
-- entries or a note's fields in, which a load does not keep. P is a prime
-- below 2^26: a product of two residues, under 2^52, is exact in a double.
-- Kahlua's % takes a - int(a / b) * b, the quotient cast to a 32-bit int
-- (1e15 % 1 is not 0 there): every % here is of non-negative operands with
-- a quotient below 2^26, where that is the exact modulo.
local P = 67108859
local HOURS = 1048576             -- hours a digested field may be keyed by: [0, 2^20)
local LIMB = 33554432             -- 2^25
local OFFSET = 1125899906842624   -- 2^50

-- A scalar folded with base k: a number to 1e-5 within +-1e9, a boolean, a
-- string of up to 64 characters; nil for anything else.
local function scalar(k, x)
    local t = type(x)
    if t == "number" then
        if x ~= x or x >= 1e9 or x <= -1e9 then return nil end
        local q = math.floor(x * 100000 + 0.5) + OFFSET
        local lo = q % LIMB
        return (((k + (q - lo) / LIMB) % P) * k + lo) % P
    end
    if t == "boolean" then return (2 * k + (x and 1 or 0)) % P end
    if t == "string" then
        local n = #x
        if n > 64 then return nil end
        local acc = (3 * k + n) % P
        for i = 1, n do acc = (acc * k + string.byte(x, i)) % P end
        return acc
    end
    return nil
end

-- Entry encoders: (entry, keys of the vault, base of the field).
local ENCODERS = {
    value = function(x, keys, k) return scalar(k, x) end,
    note = function(x, keys, k)
        if type(x) ~= "table" then
            local s = scalar(k, x)
            return s and (s * k + 5) % P
        end
        local acc, nf = 7, keys.nf
        for f, y in pairs(x) do
            local wf = nf[f]
            local s = wf and scalar(k, y)
            if s == nil then return nil end
            acc = (acc + s * wf) % P
        end
        return acc
    end,
}

-- The encoder of each digested field, by name.
local encoderOf = {}
for _, split in pairs(Vault.DIGESTED) do
    for field, how in pairs(split) do encoderOf[field] = ENCODERS[how] end
end

local function inverse(a)
    local t, nt, r, nr = 0, 1, P, a
    while nr ~= 0 do
        local q = math.floor(r / nr)
        t, nt = nt, t - q * nt
        r, nr = nr, r - q * nr
    end
    if t < 0 then t = t + P end
    return t
end

-- 1 / (h + w) mod P, kept per hour (all machines share the recent hours).
local weights, weightsOf, weightsCount = {}, nil, 0
local function weight(w, h)
    if weightsOf ~= w or weightsCount >= 8192 then weights, weightsOf, weightsCount = {}, w, 0 end
    local x = weights[h]
    if x == nil then
        x = inverse(h + w)
        weights[h] = x
        weightsCount = weightsCount + 1
    end
    return x
end

-- This Lua state only, never saved: per record key, the table the authority
-- last wrote (live) and, per digested field, its entries and their terms
-- (memo), so a write that adds a reading costs only the entries that
-- changed. A note is never changed in place (Machines: notes are assigned or
-- pruned), so an entry still holding the same note keeps its term.
local live, memo = {}, {}

-- The digest of `map` (a record's field `field`), -1 without one, nil when
-- it holds what the authority never writes.
local function digestOf(keys, rk, field, map)
    local slot = memo[rk]
    if slot == nil then
        slot = {}
        memo[rk] = slot
    end
    if map == nil then
        slot[field] = nil
        return -1
    end
    if type(map) ~= "table" then
        slot[field] = nil
        return nil
    end
    local enc, base, w = encoderOf[field], keys[field], keys.w
    local m = slot[field]
    if m == nil or not rawequal(m.map, map) then
        m = { map = map, vals = {}, cs = {}, n = 0, d = 0 }
        slot[field] = m
    end
    local seen, vals = 0, m.vals
    for h, x in pairs(map) do
        seen = seen + 1
        local old = vals[h]
        if old == nil or old ~= x then
            local e = seen <= Vault.MAX_ENTRIES and type(h) == "number" and h >= 0 and h < HOURS
                and h % 1 == 0 and enc(x, keys, base) or nil
            if e == nil then
                slot[field] = nil
                return nil
            end
            local c = (e * weight(w, h)) % P
            if old == nil then m.n = m.n + 1 else m.d = (m.d + P - m.cs[h]) % P end
            vals[h], m.cs[h], m.d = x, c, (m.d + c) % P
        end
    end
    if seen ~= m.n then
        local gone = {}
        for h in pairs(m.vals) do
            if map[h] == nil then gone[#gone + 1] = h end
        end
        for _, h in ipairs(gone) do
            m.d = (m.d + P - m.cs[h]) % P
            m.vals[h], m.cs[h], m.n = nil, nil, m.n - 1
        end
    end
    return m.d
end

local warnedDigest = {}

-- What the vault saves of `rec`: the record without its digested fields,
-- and their digests (false: one the authority wrote but cannot digest).
local function compact(v, kind, rk, rec)
    local saved, d = Tables.copy(rec), {}
    for field in pairs(Vault.DIGESTED[kind]) do
        saved[field] = nil
        local x = digestOf(v.dk, rk, field, rec[field])
        if x == nil then
            x = false
            if not warnedDigest[field] then
                warnedDigest[field] = true
                TLG.Log.warn("vault: %s of %s cannot be digested; after a restart it is dropped", field, rk)
            end
        end
        d[field] = x
    end
    return saved, d
end

local rng
local function secret(lo, hi)
    if type(ZombRand) == "function" then return lo + math.floor(ZombRand(hi - lo)) end
    rng = rng or TLG.Rng.new(math.floor((os.time() * 1000) % 2147483647))
    return rng:int(lo, hi - 1)
end

-- The digest keys, drawn once per vault; a vault saved without them (or a
-- digested field without its key) gets them now and its records compacted.
local function prepare(v)
    if type(v.recs) ~= "table" then v.recs = {} end
    if type(v.holders) ~= "table" then v.holders = {} end
    if type(v.dk) ~= "table" then v.dk = {} end
    if type(v.dk.w) ~= "number" then v.dk.w = secret(HOURS, P - HOURS) end
    for field in pairs(encoderOf) do
        if type(v.dk[field]) ~= "number" then v.dk[field] = secret(2, P - 1) end
    end
    if type(v.dk.nf) ~= "table" then v.dk.nf = {} end
    for _, f in ipairs(Vault.NOTE_FIELDS) do
        if type(v.dk.nf[f]) ~= "number" then v.dk.nf[f] = secret(1, P - 1) end
    end
    local n = 0
    for rk, e in pairs(v.recs) do
        local kind = string.match(rk, "^(%a+):")
        if kind and Vault.DIGESTED[kind] and type(e) == "table" and type(e.r) == "table" and type(e.d) ~= "table" then
            e.r, e.d = compact(v, kind, rk, e.r)
            memo[rk] = nil
            n = n + 1
        end
    end
    if n > 0 then TLG.Log.info("vault: %d records saved in full now kept compact", n) end
end

-- Called when the server store is attached (server/TLG/Server/WorldStore.lua).
-- `regenerated`: the store was lost and the world got a new seed, so the ids
-- already given out carry another one; those are adopted as found.
function Vault.attach(store, regenerated)
    live, memo = {}, {}
    if not onServer() then
        if store.vault ~= nil then
            store.vault = nil
            TLG.Log.info("vault: dropped (the world is loaded without a server)")
        end
        return
    end
    local v = store.vault
    if type(v) == "table" then
        if type(v.v) == "number" and v.v > Vault.SCHEMA then
            TLG.Log.warn("vault: written by a newer version (schema %s); records are read as found", tostring(v.v))
        elseif v.v == Vault.SCHEMA then
            prepare(v)
        end
        return
    end
    store.vault = {
        v = Vault.SCHEMA,
        from = store.nextId or 1,
        tag = string.format("%d", store.seed or 0),
        foreign = regenerated == true or nil,
        recs = {},
        holders = {},
    }
    prepare(store.vault)
    TLG.Log.info("vault: started; records with ids before %d are adopted as found", store.vault.from)
end

-- Ids are "<letter><tag>-<n>" (WorldInit.newId). One given out before the
-- vault existed (same tag, n below `from`), or under a seed the world lost
-- with its store, is adopted the first time it is found.
local function legacy(v, id)
    local tag, n = string.match(id, "^%a+(%-?%d+)%-(%d+)$")
    if tag == nil then return false end
    if tag == v.tag then return tonumber(n) < v.from end
    return v.foreign == true
end

-- Holders may be given as a function, called only when the vault is in use
-- (computing one can need what a test double or a client lacks).
local function resolve(holder)
    if type(holder) == "function" then return holder() end
    return holder
end

local function key(kind, id) return kind .. ":" .. id end
local function slot(kind, holder) return holder .. "|" .. kind end

-- Records `rec` (a table with a string id) as `holder`'s, moving it from the
-- holder it had: that one keeps a mark that its record left.
local function put(v, kind, holder, rec)
    local k = key(kind, rec.id)
    local e = v.recs[k]
    if e and e.h ~= holder and v.holders[slot(kind, e.h)] == rec.id then
        v.holders[slot(kind, e.h)] = false
    end
    if e == nil then
        e = {}
        v.recs[k] = e
    end
    e.h = holder
    if Vault.DIGESTED[kind] then
        e.r, e.d = compact(v, kind, k, rec)
        live[k] = rec
    else
        e.r = rec
    end
    v.holders[slot(kind, holder)] = rec.id
end

-- The record to give a holder back: for a kind with digested fields, the
-- table last written while this Lua state has it, else the saved form
-- (without those fields).
local function recordOf(kind, k, e)
    if not Vault.DIGESTED[kind] then return e.r end
    local t = live[k]
    if t == nil then
        t = Tables.copy(e.r)
        live[k] = t
    end
    return t
end

-- A record from client-writable mod data the vault may take as found. The
-- size first, then the digested fields (whose terms stay only if it is).
local function admissible(v, kind, k, raw)
    local body, split = raw, Vault.DIGESTED[kind]
    if split then
        body = Tables.copy(raw)
        for field in pairs(split) do body[field] = nil end
    end
    if bytes(body, Vault.ADOPT_BYTES) == nil then return false, "larger than " .. Vault.ADOPT_BYTES .. " bytes" end
    for field in pairs(split or {}) do
        if digestOf(v.dk, k, field, raw[field]) == nil then
            memo[k] = nil
            return false, field .. " not as the mod writes it"
        end
    end
    return true
end

-- `raw`, found with the id of entry e, against what the authority wrote.
local function verify(v, kind, k, e, raw, status)
    local split = Vault.DIGESTED[kind]
    if split == nil then
        if rawequal(raw, e.r) then return raw, status end
        if same(raw, e.r) then
            e.r = raw
            return raw, status
        end
        return e.r, "restored", "content differs"
    end
    if rawequal(raw, live[k]) then return raw, status end
    local fields = sameExcept(raw, e.r, split)
    local kept, lost = {}, nil
    for field in pairs(split) do
        local d = digestOf(v.dk, k, field, raw[field])
        if d ~= nil and type(e.d) == "table" and d == e.d[field] then
            kept[field] = true
        else
            lost = lost and (lost .. ", " .. field) or field
        end
    end
    if fields and lost == nil then
        live[k] = raw
        return raw, status
    end
    local out = Tables.copy(e.r)
    for field in pairs(kept) do out[field] = raw[field] end
    live[k] = out
    if not fields then
        return out, "restored", "content differs" .. (lost and ("; " .. lost .. " dropped") or "")
    end
    return out, "cleared", lost .. " differ; dropped"
end

-- What the checks did since this Lua state started (for logs and the
-- harness; not saved). cleared: a record read without readings or notes
-- that differ from the ones written.
Vault.stats = { moved = 0, adopted = 0, restored = 0, cleared = 0, dropped = 0 }
local function count(status)
    if Vault.stats[status] ~= nil then Vault.stats[status] = Vault.stats[status] + 1 end
end

local warnedNoId = {}

-- After the authority wrote `rec` to `holder`'s mod data.
function Vault.put(kind, holder, rec)
    if not Vault.active() or type(rec) ~= "table" then return end
    holder = resolve(holder)
    if holder == nil then return end
    if type(rec.id) ~= "string" then
        if not warnedNoId[kind] then
            warnedNoId[kind] = true
            TLG.Log.warn("vault: a %s record without an id was written to %s; not kept", kind, tostring(holder))
        end
        return
    end
    put(vault(), kind, holder, rec)
end

-- The holder no longer has a record of this kind (taken by the authority).
function Vault.release(kind, holder)
    local v = Vault.active() and vault()
    if not v then return end
    holder = resolve(holder)
    if holder == nil then return end
    if type(v.holders[slot(kind, holder)]) == "string" then v.holders[slot(kind, holder)] = false end
end

-- The record to read for `holder` given what its mod data holds (`raw`),
-- and what was done: "ok", "moved", "adopted" (raw is used), "restored"
-- (the server's record, to put in the mod data), "cleared" (raw without the
-- digested fields that differ, to put in the mod data), "dropped" (nil:
-- untracked).
function Vault.check(kind, holder, raw)
    local v = vault()
    if v == nil or not onServer() or holder == nil then return raw, "ok" end
    local mine = v.holders[slot(kind, holder)]
    local ownKey = type(mine) == "string" and key(kind, mine) or nil
    local own = ownKey and v.recs[ownKey] or nil
    local id = type(raw) == "table" and type(raw.id) == "string" and raw.id or nil
    local k = id and key(kind, id)
    local e = k and v.recs[k]
    if e then
        local status = "ok"
        if e.h ~= holder then
            if own then return recordOf(kind, ownKey, own), "restored", "a record of " .. tostring(e.h) end
            if mine ~= nil then return nil, "dropped", "a record of " .. tostring(e.h) end
            -- The holder never had a record: this one moved here unseen.
            if e.h ~= nil and v.holders[slot(kind, e.h)] == id then v.holders[slot(kind, e.h)] = false end
            TLG.Log.info("vault: %s %s moved from %s to %s", kind, id, tostring(e.h), holder)
            e.h = holder
            v.holders[slot(kind, holder)] = id
            status = "moved"
        end
        return verify(v, kind, k, e, raw, status)
    end
    if own then return recordOf(kind, ownKey, own), "restored", raw == nil and "record removed" or "unknown id" end
    if raw == nil then return nil, "ok" end
    if id and mine == nil and legacy(v, id) then
        local ok, why = admissible(v, kind, k, raw)
        if not ok then return nil, "dropped", why end
        put(v, kind, holder, raw)
        TLG.Log.info("vault: %s %s on %s adopted (given out before the vault)", kind, id, holder)
        return raw, "adopted"
    end
    return nil, "dropped", id and "unknown id" or "no id"
end

-- Reads md[field] for `holder` through the vault. A record put back,
-- cleared or dropped is written to the mod data at once and sent with
-- `sync`, so the clients' copies follow.
function Vault.guard(kind, holder, md, field, sync)
    local raw = md[field]
    if not Vault.active() then return raw end
    holder = resolve(holder)
    local out, status, why = Vault.check(kind, holder, raw)
    count(status)
    if status == "restored" or status == "cleared" or status == "dropped" then
        md[field] = out
        if sync then
            local ok, err = pcall(sync)
            if not ok then TLG.Log.error("vault: sync of %s failed: %s", tostring(holder), tostring(err)) end
        end
        TLG.Log.warn("vault: %s on %s %s (%s)", kind, tostring(holder), status, tostring(why))
    end
    return out
end

-- Records keyed by another record's id rather than by their own (a
-- generator's wear, keyed by its fuel record): same checks, no holder.
-- An unknown one is adopted as found up to ADOPT_BYTES; its use bounds it
-- (G.chargeWear).
function Vault.guardKeyed(kind, id, md, field, sync)
    local raw = md[field]
    if not Vault.active() or type(id) ~= "string" then return raw end
    local v = vault()
    local e = v.recs[key(kind, id)]
    if e == nil then
        if raw ~= nil and bytes(raw, Vault.ADOPT_BYTES) == nil then
            md[field] = nil
            if sync then pcall(sync) end
            count("dropped")
            TLG.Log.warn("vault: %s of %s dropped (larger than %d bytes)", kind, id, Vault.ADOPT_BYTES)
            return nil
        end
        if raw ~= nil then v.recs[key(kind, id)] = { r = raw } end
        return raw
    end
    if rawequal(raw, e.r) then return raw end
    if same(raw, e.r) then
        e.r = raw
        return raw
    end
    md[field] = e.r
    if sync then pcall(sync) end
    TLG.Log.warn("vault: %s of %s restored (content differs)", kind, id)
    return md[field]
end

function Vault.putKeyed(kind, id, rec)
    if not Vault.active() or type(id) ~= "string" then return end
    local e = vault().recs[key(kind, id)]
    if e then e.r = rec else vault().recs[key(kind, id)] = { r = rec } end
end

function Vault.itemHolder(item)
    return "item:" .. tostring(item:getID())
end

return Vault
