-- Storage profiles for native containers (item full types and world-object
-- entity/sprite families). Unknown containers use the pessimistic "unknown"
-- profile until mapped here (docs/support-matrix.md).
TLG.ContainerProfiles = TLG.ContainerProfiles or {}
local P = TLG.ContainerProfiles

P.items = {
    ["Base.PetrolCan"] = "gascan_plastic",
    ["Base.JerryCan"] = "jerrycan_steel",
}

function P.forItem(item)
    local id = P.items[item:getFullType()]
    if id then return id end
    local fc = item:getFluidContainer()
    if fc and fc:getCapacity() <= 2 then return "bottle" end
    return "unknown"
end

function P.forObject(obj)
    return "drum_steel"
end

return P
