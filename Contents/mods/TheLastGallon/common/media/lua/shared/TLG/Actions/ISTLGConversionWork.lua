-- Timed action: work on a workshop conversion at the device. It runs until
-- the conversion is commissioned, the work is blocked (tool, parts, tank) or
-- the character leaves. Starting joins the project, which forfeits any time
-- since the last report; while the character stays in reach, the action
-- reports every ConversionDevices.REPORT_EVERY_HOURS of world time and the
-- authority credits only the time since the previous report (at most
-- WORKER_TIMEOUT_HOURS). Walking away stops it with a final report.
-- Reports go through TLG.Net (single player: locally; multiplayer: client
-- requests, NOT RUN); a server-side copy of the action never reports.
-- Verified RT-SP 2026-10-31 (run 9): reports, ending itself at
-- Commissioned, stop() when the character was moved out of reach, no credit
-- for time away. Queued by the harness: the menu's walk to the device, the
-- endings on a block or a refused join, and the progress bar's rendering
-- are NOT RUN.
require "TimedActions/ISBaseTimedAction"
require "TLG/Integration/ConversionDevices"

ISTLGConversionWork = ISBaseTimedAction:derive("ISTLGConversionWork")
local CD = TLG.Integration.ConversionDevices

-- Same reach as the authority: 4 tiles from a vehicle (ConversionHandlers),
-- 2.5 tiles from a generator's square (Resolver).
function ISTLGConversionWork:isValid()
    if self.character:getVehicle() ~= nil then return false end
    if self.deviceRef.kind == "vehicle" then
        local v = getVehicleById(self.deviceRef.id)
        return v ~= nil and self.character:DistTo(v:getX(), v:getY()) <= 4
    end
    local sq = self.character:getSquare()
    return self.device:getObjectIndex() ~= -1 and sq ~= nil and sq:DistToProper(self.device:getSquare()) <= 2.5
end

function ISTLGConversionWork:waitToStart()
    self.character:faceThisObject(self.device)
    return self.character:shouldBeTurning()
end

function ISTLGConversionWork:send(command, args, onReply)
    if isServer() or not TLG.Net then return end
    args.device = self.deviceRef
    TLG.Net.request(command, args, onReply)
end

function ISTLGConversionWork:onReply(r)
    if self.ended then return end
    if r.ok and r.state == "InProgress" and not r.released then
        self.joined = true
        if r.totalHours and r.totalHours > 0 then
            -- Progress bar on an open-ended action: not verified to render.
            local ok, err = pcall(self.setJobDelta, self, r.doneHours / r.totalHours)
            if not ok then TLG.Log.error("conversion work progress: %s", tostring(err)) end
        end
        return
    end
    self.ended, self.result = true, r
    if self.onEnd then pcall(self.onEnd, r) end
    self:forceComplete()
end

function ISTLGConversionWork:start()
    if self.deviceRef.kind == "vehicle" then
        self:setActionAnim("VehicleWorkOnMid")
    else
        self:setActionAnim("Loot")
        self.character:SetVariable("LootPosition", "Low")
    end
    self.lastReport = TLG.World.now()
    self:send("conversion.join", {}, function(r) self:onReply(r) end)
end

function ISTLGConversionWork:update()
    self.character:faceThisObject(self.device)
    self.character:setMetabolicTarget(Metabolics.UsingTools)
    if not self.joined or self.ended then return end
    local now = TLG.World.now()
    if now - self.lastReport >= CD.REPORT_EVERY_HOURS then
        self.lastReport = now
        self.reports = self.reports + 1
        self:send("conversion.work", {}, function(r) self:onReply(r) end)
    end
end

function ISTLGConversionWork:stop()
    if self.joined and not self.ended then
        -- Credits the time since the last report and leaves the project.
        self.ended, self.stopped = true, true
        self:send("conversion.work", { leave = true })
    end
    ISBaseTimedAction.stop(self)
end

function ISTLGConversionWork:perform()
    ISBaseTimedAction.perform(self)
end

function ISTLGConversionWork:complete()
    return true
end

function ISTLGConversionWork:getDuration()
    return -1
end

-- deviceRef: { kind = "vehicle", id = n } or a generator ref
-- (Resolver.refForObject); device: the BaseVehicle or IsoGenerator.
-- onEnd(reply) runs when the action ends by itself (done, blocked, refused).
function ISTLGConversionWork:new(character, deviceRef, device, onEnd)
    local o = ISBaseTimedAction.new(self, character)
    o.deviceRef, o.device, o.onEnd = deviceRef, device, onEnd
    o.reports = 0
    o.caloriesModifier = 4
    o.maxTime = o:getDuration()
    return o
end
