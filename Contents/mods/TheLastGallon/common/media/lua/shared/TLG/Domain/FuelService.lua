-- FuelService: the contract named in the specification (§4). Calculation
-- functions return proposed records and diagnostics; only the authority layer
-- commits them. UI previews call the same functions as the server.
require "TLG/Domain/Fuel/Aging"
require "TLG/Domain/Fuel/Mixing"
require "TLG/Domain/Fuel/Treatment"
require "TLG/Domain/Fuel/Inspection"
require "TLG/Domain/Consumers"

TLG.FuelService = TLG.FuelService or {}
local FuelService = TLG.FuelService
local D = TLG.Domain

-- FuelService.advance(batch, timeInterval, environmentSegments)
function FuelService.advance(supply, toTime, env)
    return D.Aging.advance(supply, toTime, env)
end

function FuelService.previewTransfer(source, destination, amount, opts)
    return D.Mixing.previewTransfer(source, destination, amount, opts)
end

-- inputs = { { supply = s, amount = litres }, ... }
function FuelService.previewBlend(inputs, consumerProfile, storageId)
    local blend = D.Mixing.previewBlend(inputs, storageId)
    local eval = consumerProfile and D.Consumers.evaluate(consumerProfile, blend) or nil
    return { supply = blend, evaluation = eval }
end

FuelService.evaluate = function(profileId, supply, state)
    return D.Consumers.evaluate(profileId, supply, state)
end

return FuelService
