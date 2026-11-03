-- Shared by the multiplayer harness's client and server sides
-- (MPHarness.lua, MPServer.lua): the same text for the same record on
-- either side, so the two can be compared.
TLGH = TLGH or {}
TLGH.MPShared = TLGH.MPShared or {}
local S = TLGH.MPShared

-- A value as text: tables with their keys sorted, numbers to 4 places.
local function text(v)
    if type(v) == "number" then return string.format("%.4f", v) end
    if type(v) ~= "table" then return tostring(v) end
    local entries = {}
    for k, val in pairs(v) do entries[#entries + 1] = { tostring(k), val } end
    table.sort(entries, function(a, b) return a[1] < b[1] end)
    local parts = {}
    for _, e in ipairs(entries) do parts[#parts + 1] = e[1] .. "=" .. text(e[2]) end
    return "{" .. table.concat(parts, ",") .. "}"
end
S.text = text

-- An item's TLG sidecar (its mod data's tlg table) as text.
function S.sidecar(item)
    local md = item and item:getModData()
    if md == nil or md.tlg == nil then return "no-sidecar" end
    return text(md.tlg)
end

-- The square a row step k stands on, from the spawn point (as SPHarness's
-- RT.MI.spot): one step of k is one tile across the screen.
S.CX, S.CY = 10660, 10645
function S.spot(k) return S.CX + k, S.CY - k end
-- The row behind it, further from the camera (RT.MI.behind).
function S.behind(k) return S.CX + k - 1, S.CY - k - 1 end

-- The full types of the items lying on a square.
function S.floorTypes(x, y)
    local sq = getCell():getGridSquare(x, y, 0)
    local objs = sq and sq:getWorldObjects()
    local types = {}
    for i = 0, (objs and objs:size() or 0) - 1 do
        local item = objs:get(i):getItem()
        if item then types[#types + 1] = item:getFullType() end
    end
    table.sort(types)
    return types
end

-- Every item lying within `r` squares of the spawn point, as "x,y:type"
-- entries sorted, so a client's view and the server's can be compared.
S.R = 5
function S.floorAround()
    local out = {}
    for x = S.CX - S.R, S.CX + S.R do
        for y = S.CY - S.R, S.CY + S.R do
            for _, t in ipairs(S.floorTypes(x, y)) do out[#out + 1] = x .. "," .. y .. ":" .. t end
        end
    end
    table.sort(out)
    return table.concat(out, ";")
end

return S
