-- Bounded per-actor request ledger: a retried request returns the stored
-- response instead of executing again (spec §14). Oldest entries are evicted
-- first; eviction only forgets very old retries.
require "TLG/Core"

TLG.Authority = TLG.Authority or {}
TLG.Authority.Ledger = TLG.Authority.Ledger or {}
local Ledger = TLG.Authority.Ledger
Ledger.__index = Ledger

Ledger.DEFAULT_CAPACITY = 64

function Ledger.new(capacity)
    return setmetatable({ capacity = capacity or Ledger.DEFAULT_CAPACITY, actors = {} }, Ledger)
end

local function bucket(self, actor)
    local b = self.actors[actor]
    if b == nil then
        b = { order = {}, results = {} }
        self.actors[actor] = b
    end
    return b
end

function Ledger:lookup(actor, requestId)
    local b = self.actors[actor]
    if b == nil then return nil end
    return b.results[requestId]
end

function Ledger:record(actor, requestId, response)
    local b = bucket(self, actor)
    if b.results[requestId] == nil then
        b.order[#b.order + 1] = requestId
    end
    b.results[requestId] = response
    while #b.order > self.capacity do
        local old = table.remove(b.order, 1)
        b.results[old] = nil
    end
end

return Ledger
