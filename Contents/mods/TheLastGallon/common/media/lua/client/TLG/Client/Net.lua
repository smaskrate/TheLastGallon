-- Client request API. Every mutation is a request; the reply carries the
-- authoritative result. Single-player calls the same handlers locally.
require "TLG/Authority/Handlers"
require "TLG/Authority/MachineHandlers"
require "TLG/Authority/ConversionHandlers"

TLG.Net = TLG.Net or { pending = {}, counter = 0 }
local Net = TLG.Net

local function deliver(reply)
    local id = reply and reply.requestId
    local cb = id and Net.pending[id]
    Net.pending[id or ""] = nil
    if cb then
        local ok, err = pcall(cb, reply)
        if not ok then TLG.Log.error("reply handler %s: %s", tostring(reply.command), tostring(err)) end
    end
end

function Net.request(command, args, onReply)
    local player = getPlayer()
    Net.counter = Net.counter + 1
    args.requestId = string.format("%s-%d-%d", tostring(player:getPlayerNum()), getTimestampMs(), Net.counter)
    if onReply then Net.pending[args.requestId] = onReply end
    if isClient() then
        sendClientCommand(player, "TLG", command, args)
    else
        deliver(TLG.Authority.Handlers.dispatch(player, command, args))
    end
    return args.requestId
end

Events.OnServerCommand.Add(function(module, command, args)
    if module == "TLG" and command == "reply" then deliver(args) end
end)

return Net
