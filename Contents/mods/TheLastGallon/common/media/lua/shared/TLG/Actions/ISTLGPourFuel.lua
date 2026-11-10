-- Timed action: pour a fuel can into a vehicle tank or generator through the
-- authoritative TLG transfer (needed for non-petrol fuels, which vanilla menus
-- do not offer). The transfer runs once in complete() on the authority
-- (single player: locally; multiplayer: the server's copy of the action,
-- RT-MP run 156). In multiplayer the reply reaches onDone through TLG.Net:
-- a function is not sent with the action (BC PZNetKahluaTableImpl.canSave),
-- so the server's copy has no onDone and answers under the request id the
-- client sent with it (run 156 saw no result on the client before this).
require "TimedActions/ISBaseTimedAction"
require "TLG/Authority/Handlers"

ISTLGPourFuel = ISBaseTimedAction:derive("ISTLGPourFuel")

function ISTLGPourFuel:isValid()
    local fc = self.item and TLG.Integration.Containers.fluidOf(self.item, "item")
    return fc ~= nil and not fc:isEmpty()
end

function ISTLGPourFuel:waitToStart()
    if self.faceObject then self.character:faceThisObject(self.faceObject) end
    return self.character:shouldBeTurning()
end

function ISTLGPourFuel:update()
    self.item:setJobDelta(self:getJobDelta())
    self.character:setMetabolicTarget(Metabolics.HeavyDomestic)
end

function ISTLGPourFuel:start()
    self.item:setJobType(getText("ContextMenu_TLG_PourInto"))
    self:setActionAnim("refuelgascan")
    self:setOverrideHandModels(self.item:getStaticModel(), nil)
    self.sound = self.character:playSound("VehicleAddFuelFromCanister")
end

function ISTLGPourFuel:stop()
    if self.sound then self.character:stopOrTriggerSound(self.sound) end
    self.item:setJobDelta(0)
    ISBaseTimedAction.stop(self)
end

function ISTLGPourFuel:perform()
    if self.sound then self.character:stopOrTriggerSound(self.sound) end
    self.item:setJobDelta(0)
    ISBaseTimedAction.perform(self)
end

function ISTLGPourFuel:complete()
    if not TLG.World.isAuthority() then return true end
    local reply = TLG.Authority.Handlers.dispatch(self.character, "transfer", {
        requestId = self.requestId,
        source = { kind = "item", id = self.item:getID() },
        destination = self.destination,
        amount = self.amount,
        experimental = self.experimental,
    })
    self.reply = reply
    if self.onDone then pcall(self.onDone, reply) end
    if isServer() then sendServerCommand(self.character, "TLG", "reply", reply) end
    return true
end

function ISTLGPourFuel:getDuration()
    if self.character:isTimedActionInstant() then return 1 end
    return math.max(50, math.floor(self.amount * 25))
end

-- destination: { kind = "vehicle", id = n } or { kind = "generator", x, y, z, index }
-- requestId: none from the menus. A multiplayer client sends the action's
-- fields named as new's parameters (BC NetTimedAction.set), so the server's
-- copy gets the client's id, and a client keeps onDone under it for the
-- server's reply, not on the action: the server passes the fields it gets
-- in order, a function is not sent (BC PZNetKahluaTableImpl.save), and the
-- id after it then took onDone's place (RT-MP run 157). A nil goes as a
-- placeholder.
function ISTLGPourFuel:new(character, item, destination, faceObject, experimental, onDone, requestId)
    local o = ISBaseTimedAction.new(self, character)
    o.item = item
    o.destination = destination
    o.faceObject = faceObject
    o.experimental = experimental and true or false
    o.onDone = onDone
    o.amount = TLG.Integration.Containers.fluidOf(item, "item"):getAmount()
    o.requestId = requestId or string.format("pour-%d-%d", item:getID(), getTimestampMs())
    if onDone and isClient() and TLG.Net then
        TLG.Net.pending[o.requestId] = onDone
        o.onDone = nil
    end
    o.maxTime = o:getDuration()
    return o
end
