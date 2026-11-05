-- The server store: the world record's fields only the authority uses (seed,
-- next id, placed machines' squares, today's climate sums; World.SERVER_FIELDS),
-- kept out of global ModData, which the server sends to any client asking
-- for a key (GlobalModData.receiveRequest, 42.21; audit 2026-11-05, V-03).
--
-- A global object system with no objects: the engine saves the keys named in
-- setModDataKeys to gos_tlgworld.bin in the save and, unlike global ModData,
-- sends a client only what getInitialStateForClient returns (nothing here).
-- Systems load after OnInitGlobalModData (GameServer.main and
-- GameLoadingState: IsoWorld.init, then SGlobalObjects.initSystems), so the
-- world record is created first and its server fields move here on attach.
-- Server and single-player only (the vanilla base class is not defined on
-- multiplayer clients).
if isClient() then return end

require "Map/SGlobalObjectSystem"
require "TLG/Integration/World"

if SGlobalObjectSystem == nil then return end

STLGWorldStore = SGlobalObjectSystem:derive("STLGWorldStore")
STLGWorldStore.NAME = "tlgworld"

function STLGWorldStore:new()
    return SGlobalObjectSystem.new(self, STLGWorldStore.NAME)
end

function STLGWorldStore:initSystem()
    SGlobalObjectSystem.initSystem(self)
    self.system:setModDataKeys({ "tlg" })
    self.system:setObjectModDataKeys({})
    if type(self.tlg) ~= "table" then self.tlg = {} end
    TLG.World.attachServerStore(self.tlg)
end

-- Clients get nothing of this system (the base class's default, kept explicit).
function STLGWorldStore:getInitialStateForClient()
    return nil
end

function STLGWorldStore:isValidIsoObject(isoObject)
    return false
end

function STLGWorldStore:newLuaObject(globalObject)
    error("the TLG world store has no objects")
end

-- Commands for this system from clients are ignored.
function STLGWorldStore:OnClientCommand(command, playerObj, args)
end

Events.OnSGlobalObjectSystemInit.Add(function()
    local ok, err = pcall(function() STLGWorldStore.instance = STLGWorldStore:new() end)
    if not ok then
        TLG.Log.error("world record: server store failed (%s); its fields stay in global ModData", tostring(err))
    end
end)

if Events.OnServerStarted then
    Events.OnServerStarted.Add(function()
        if TLG.World.store == nil then
            TLG.Log.warn("world record: no server store; seed and machine squares stay readable by clients")
        end
    end)
end
