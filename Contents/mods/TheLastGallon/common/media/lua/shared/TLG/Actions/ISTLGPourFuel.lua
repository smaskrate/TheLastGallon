-- Timed action: pour a fuel can into a vehicle tank or generator through the
-- authoritative TLG transfer (needed for non-petrol fuels, which vanilla menus
-- do not offer). The transfer runs once in complete() on the authority
-- (single-player: locally; B42 multiplayer: server-side complete, NOT RUN).
require "TimedActions/ISBaseTimedAction"
require "TLG/Authority/Handlers"

ISTLGPourFuel = ISBaseTimedAction:derive("ISTLGPourFuel")

function ISTLGPourFuel:isValid()
    return self.item ~= nil and self.item:getFluidContainer() ~= nil and not self.item:getFluidContainer():isEmpty()
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
    return true
end

function ISTLGPourFuel:getDuration()
    if self.character:isTimedActionInstant() then return 1 end
    return math.max(50, math.floor(self.amount * 25))
end

-- destination: { kind = "vehicle", id = n } or { kind = "generator", x, y, z, index }
function ISTLGPourFuel:new(character, item, destination, faceObject, experimental, onDone)
    local o = ISBaseTimedAction.new(self, character)
    o.item = item
    o.destination = destination
    o.faceObject = faceObject
    o.experimental = experimental and true or false
    o.onDone = onDone
    o.amount = item:getFluidContainer():getAmount()
    o.requestId = string.format("pour-%d-%d", item:getID(), getTimestampMs())
    o.maxTime = o:getDuration()
    return o
end
