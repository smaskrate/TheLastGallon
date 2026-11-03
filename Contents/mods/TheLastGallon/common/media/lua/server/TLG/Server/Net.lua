-- Server transport: client requests -> authoritative handlers -> reply.
-- Verified on a dedicated server: the fuel, machine and conversion requests
-- (RT-MP runs 139-171, engine-capabilities G07).
require "TLG/Authority/Handlers"
require "TLG/Authority/MachineHandlers"
require "TLG/Authority/ConversionHandlers"

local Handlers = TLG.Authority.Handlers

local function onClientCommand(module, command, player, args)
    if module ~= "TLG" then return end
    local ok, res = pcall(Handlers.dispatch, player, command, args)
    if not ok then
        TLG.Log.error("command %s from %s failed: %s", tostring(command), Handlers.actorKey(player), tostring(res))
        res = { ok = false, reason = "server_error", requestId = type(args) == "table" and args.requestId or nil,
            command = command }
    end
    sendServerCommand(player, "TLG", "reply", res)
end

Events.OnClientCommand.Add(onClientCommand)
