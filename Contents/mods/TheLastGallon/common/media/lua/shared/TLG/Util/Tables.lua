-- Deterministic table helpers. `pairs` order is unspecified (and `next` is not
-- available in the game's Kahlua environment), so anything that affects state
-- or output iterates over Tables.sortedKeys.
require "TLG/Core"

TLG.Tables = TLG.Tables or {}
local Tables = TLG.Tables

local function keyLess(a, b)
    local ta, tb = type(a), type(b)
    if ta ~= tb then
        return ta < tb
    end
    return a < b
end

-- Stable, iterative merge sort. The game's table.sort is a recursive
-- left-pivot quicksort (stdlib.lua) that is unstable and degrades on sorted
-- input; this one is safe for any size.
function Tables.sort(list, less)
    less = less or keyLess
    local n = #list
    if n < 2 then return list end
    local src, dst = list, {}
    local width = 1
    while width < n do
        local i = 1
        while i <= n do
            local mid = math.min(i + width, n + 1)
            local hi = math.min(i + 2 * width, n + 1)
            local a, b, k = i, mid, i
            while a < mid and b < hi do
                if less(src[b], src[a]) then
                    dst[k] = src[b]; b = b + 1
                else
                    dst[k] = src[a]; a = a + 1
                end
                k = k + 1
            end
            while a < mid do dst[k] = src[a]; a = a + 1; k = k + 1 end
            while b < hi do dst[k] = src[b]; b = b + 1; k = k + 1 end
            i = i + 2 * width
        end
        src, dst = dst, src
        width = width * 2
    end
    if src ~= list then
        for i = 1, n do list[i] = src[i] end
    end
    return list
end

function Tables.sortedKeys(t)
    local keys = {}
    for k in pairs(t) do
        keys[#keys + 1] = k
    end
    return Tables.sort(keys)
end

function Tables.isEmpty(t)
    for _ in pairs(t) do
        return false
    end
    return true
end

function Tables.count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

function Tables.copy(t)
    local out = {}
    for k, v in pairs(t) do out[k] = v end
    return out
end

-- Deep copy of plain data (no metatables, no cycles). Used for snapshots of
-- persistent state so that previews never alias committed records.
function Tables.deepCopy(v)
    if type(v) ~= "table" then
        return v
    end
    local out = {}
    for k, x in pairs(v) do
        out[k] = Tables.deepCopy(x)
    end
    return out
end

-- Structural equality of plain data with a numeric tolerance.
function Tables.deepEqual(a, b, tol)
    if type(a) ~= type(b) then return false end
    if type(a) == "number" then
        return math.abs(a - b) <= (tol or 0)
    end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do
        if not Tables.deepEqual(v, b[k], tol) then return false end
    end
    for k in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
end

function Tables.contains(list, value)
    for i = 1, #list do
        if list[i] == value then return true end
    end
    return false
end

return Tables
