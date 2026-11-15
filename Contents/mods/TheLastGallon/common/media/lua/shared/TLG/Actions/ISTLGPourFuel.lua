-- Timed action: pour a fuel can into a vehicle tank or generator through the
-- authoritative TLG transfer (needed for non-petrol fuels, which vanilla menus
-- do not offer). The transfer runs once in complete() on the authority
-- (single player: locally; multiplayer: the server's copy of the action,
-- RT-MP run 156). In multiplayer the reply reaches onDone through TLG.Net:
-- a function is not sent with the action (BC PZNetKahluaTableImpl.canSave),
-- so the server's copy has no onDone and answers under the request id the
-- client sent with it (run 156 saw no result on the client before this).
--
-- The same action pours a can into a station's reservoir (the destination a
-- pump) and, with `source`, runs the other way: Drain the generator into
-- this can moves the source's fuel into the can (UX review R13: both were
-- instant requests while every other pour took time).
require "TimedActions/ISBaseTimedAction"
require "TLG/Authority/Handlers"

ISTLGPourFuel = ISBaseTimedAction:derive("ISTLGPourFuel")

function ISTLGPourFuel:isValid()
    local fc = self.item and TLG.Integration.Containers.fluidOf(self.item, "item")
    if fc == nil then return false end
    if self.source then return fc:getFreeCapacity() > 0.05 end
    return not fc:isEmpty()
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
    self.item:setJobType(getText(self.source and "ContextMenu_TLG_DrainGenerator" or "ContextMenu_TLG_PourInto"))
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
        source = self.source or { kind = "item", id = self.item:getID() },
        destination = self.source and { kind = "item", id = self.item:getID() } or self.destination,
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
    return math.max(50, math.floor((self.litres or self.amount) * 25))
end

-- The litres a drain will move, for its duration: the can's room, or what
-- the generator faced holds when that is less. The transfer itself is asked
-- for the can's room and moves what the source has.
local function drainLitres(room, faceObject)
    local ok, held = pcall(function() return faceObject:getFuel() end)
    if ok and type(held) == "number" and held >= 0 and held < room then return held end
    return room
end

-- destination: { kind = "vehicle", id = n } or { kind = "generator", x, y, z, index }
-- requestId: none from the menus. A multiplayer client sends the action's
-- fields named as new's parameters (BC NetTimedAction.set), so the server's
-- copy gets the client's id, and a client keeps onDone under it for the
-- server's reply, not on the action: the server passes the fields it gets
-- in order, a function is not sent (BC PZNetKahluaTableImpl.save), and the
-- id after it then took onDone's place (RT-MP run 157). A nil goes as a
-- placeholder.
-- source: nil for a pour; for a drain, the reference of what is emptied
-- into the can (a generator), and `destination` is nil. It comes last so
-- that the fields before it stay where a pour sends them.
function ISTLGPourFuel:new(character, item, destination, faceObject, experimental, onDone, requestId, source)
    local o = ISBaseTimedAction.new(self, character)
    o.item = item
    o.destination = destination
    o.faceObject = faceObject
    o.experimental = experimental and true or false
    o.onDone = onDone
    o.source = source
    local fc = TLG.Integration.Containers.fluidOf(item, "item")
    if source then
        o.amount = fc:getFreeCapacity()
        o.litres = drainLitres(o.amount, faceObject)
    else
        o.amount = fc:getAmount()
    end
    o.requestId = requestId or string.format("pour-%d-%d", item:getID(), getTimestampMs())
    if onDone and isClient() and TLG.Net then
        TLG.Net.pending[o.requestId] = onDone
        o.onDone = nil
    end
    o.maxTime = o:getDuration()
    return o
end
