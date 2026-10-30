-- Quantity reservations for long operations (pouring, dispensing, loading a
-- machine). A reservation lowers the quantity other requests may take from a
-- source until it is committed (possibly partially), cancelled or expires.
require "TLG/Util/Tables"

TLG.Authority = TLG.Authority or {}
TLG.Authority.Reservations = TLG.Authority.Reservations or {}
local Reservations = TLG.Authority.Reservations
local Tables = TLG.Tables
Reservations.__index = Reservations

function Reservations.new()
    return setmetatable({ bySource = {}, byId = {}, nextId = 1 }, Reservations)
end

function Reservations:expire(now)
    for _, id in ipairs(Tables.sortedKeys(self.byId)) do
        local r = self.byId[id]
        if r.expires <= now then self:release(id) end
    end
end

-- Total reserved on a source by anyone except `exceptOwner`.
function Reservations:reserved(sourceKey, exceptOwner)
    local list = self.bySource[sourceKey]
    if list == nil then return 0 end
    local sum = 0
    for _, id in ipairs(Tables.sortedKeys(list)) do
        local r = self.byId[id]
        if r and r.owner ~= exceptOwner then sum = sum + r.amount end
    end
    return sum
end

function Reservations:create(sourceKey, owner, amount, now, ttl)
    local id = self.nextId
    self.nextId = id + 1
    local r = { id = id, source = sourceKey, owner = owner, amount = amount, expires = now + (ttl or 1) }
    self.byId[id] = r
    self.bySource[sourceKey] = self.bySource[sourceKey] or {}
    self.bySource[sourceKey][id] = true
    return r
end

function Reservations:get(id)
    return self.byId[id]
end

function Reservations:release(id)
    local r = self.byId[id]
    if r == nil then return nil end
    self.byId[id] = nil
    local list = self.bySource[r.source]
    if list then
        list[id] = nil
        if Tables.isEmpty(list) then self.bySource[r.source] = nil end
    end
    return r
end

return Reservations
