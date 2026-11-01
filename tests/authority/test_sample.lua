require "support/fixtures"
-- The handlers' adapters register game events when they load (TLG/Boot); a
-- stand-in event list takes them (as tests/integration/test_machine_menu.lua).
local savedEvents = Events
Events = setmetatable({}, { __index = function(t, k)
    local e = { Add = function() end }
    rawset(t, k, e)
    return e
end })
require "TLG/Authority/Handlers"
Events = savedEvents
local H, Res = TLG.Authority.Handlers, TLG.Authority.Resolver

-- The sample command against a stand-in endpoint: the game clock and global
-- ModData stubbed, the resolver replaced, a player with mod data. Installed
-- for one case and removed again.
local GLOBALS = { "ModData", "getGameTime", "isServer", "isClient" }

local function stage(status, rec)
    local saved, resolve = {}, Res.resolve
    for _, k in ipairs(GLOBALS) do saved[k] = _G[k] end
    local store = {}
    ModData = { getOrCreate = function(k)
        store[k] = store[k] or {}
        return store[k]
    end }
    local clock = {}
    function clock:getWorldAgeHours() return 100 end
    getGameTime = function() return clock end
    isServer = function() return false end
    isClient = function() return false end
    local s = { writes = 0, recorded = nil, md = {} }
    local ep = { key = rec.id }
    function ep:canAccess() return true end
    function ep:read()
        self.readStatus = status
        return TLG.Domain.Supply.copy(rec)
    end
    function ep:write() s.writes = s.writes + 1; return true end
    function ep:record(r) s.recorded = r; return true end
    Res.resolve = function() return ep end
    s.player = {}
    function s.player:getModData() return s.md end
    function s.player:getUsername() return "tester" end
    function s.player:getInventory() return { getFirstTypeRecurse = function() return nil end } end
    function s.restore()
        Res.resolve = resolve
        for _, k in ipairs(GLOBALS) do _G[k] = saved[k] end
    end
    return s
end

local function petrol(id)
    return F.supply({ id = id, storage = "jerrycan_steel", q = { gasoline = 10 }, t = 100 })
end

local function staged(status, rec, fn)
    local s = stage(status, rec)
    local ok, err = pcall(fn, s)
    s.restore()
    if not ok then error(err, 0) end
end

T.case("authority: a first look records the fuel it looks at, without touching it", function()
    staged("initialized", petrol("S9-1"), function(s)
        local r = H.sample(s.player, { requestId = "look-1", target = { kind = "item", id = 1 }, method = "visual" })
        T.eq(r.ok, true)
        T.ok(s.recorded ~= nil, "the record is written")
        T.eq(s.recorded.id, "S9-1", "under the id the observation is filed under")
        T.near(s.recorded.q.gasoline, 10, 1e-12, "the fuel as found")
        T.eq(s.writes, 0, "the fuel itself is not written")
        T.ok(s.md.tlgKnowledge["S9-1"] == r.observation, "What I know about it finds the look by that id")
    end)
end)

T.case("authority: a look at recorded fuel, or a refused one, writes nothing", function()
    staged("ok", petrol("S9-2"), function(s)
        local r = H.sample(s.player, { requestId = "look-2", target = { kind = "item", id = 2 }, method = "visual" })
        T.eq(r.ok, true)
        T.ok(s.recorded == nil, "already recorded: nothing written")
        T.ok(s.md.tlgKnowledge["S9-2"] ~= nil, "filed under its id")
    end)
    staged("initialized", petrol("S9-3"), function(s)
        local r = H.sample(s.player, { requestId = "look-3", target = { kind = "item", id = 3 }, method = "kit" })
        T.eq(r.ok, false); T.eq(r.reason, "needs_sample_kit")
        T.ok(s.recorded == nil and s.md.tlgKnowledge == nil, "no kit: no record, no observation")
    end)
end)
