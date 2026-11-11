-- A line shown over the player's head for something the mod did to an
-- engine (D-037: a start that damaged it, an engine that failed). The
-- authority sends; the player's own client shows. In single player both are
-- this process.
TLG.Notify = TLG.Notify or {}
local N = TLG.Notify

-- Client side. `fuel` is a fuel id, shown by its translated name.
function N.show(key, fuel)
    local ok, text = pcall(function()
        if fuel then return getText(key, getText("IGUI_TLG_Fuel_" .. tostring(fuel))) end
        return getText(key)
    end)
    if not ok then return nil end
    N.last = { key = key, fuel = fuel, text = text }
    pcall(function()
        local player = getPlayer()
        if player and HaloTextHelper and HaloTextHelper.addBadText then HaloTextHelper.addBadText(player, text) end
    end)
    return text
end

-- Authority side: to `player`'s client on a server, here otherwise.
function N.send(player, key, fuel)
    if isServer and isServer() then
        if player then sendServerCommand(player, "TLG", "note", { key = key, fuel = fuel }) end
        return
    end
    N.show(key, fuel)
end

return N