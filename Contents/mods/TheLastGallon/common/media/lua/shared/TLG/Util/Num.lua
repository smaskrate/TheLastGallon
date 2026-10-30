-- Numeric helpers that are safe on the Kahlua VM.
-- Kahlua's `%` is Java's truncated remainder (-7 % 3 == -1), unlike Lua's
-- floored modulo, so modular arithmetic must go through Num.mod.
require "TLG/Core"

TLG.Num = TLG.Num or {}
local Num = TLG.Num

-- Conservation tolerance for liquid quantities in litres (docs/balance.md).
Num.EPS = 1e-9
-- Component amounts below this many litres are dropped as rounding dust.
-- Dropping can only destroy quantity, never create it.
Num.DUST = 1e-7

function Num.mod(a, b)
    return a - math.floor(a / b) * b
end

function Num.isFinite(x)
    return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

function Num.clamp(x, lo, hi)
    if x < lo then return lo end
    if x > hi then return hi end
    return x
end

function Num.near(a, b, tol)
    return math.abs(a - b) <= (tol or Num.EPS)
end

-- Rounds toward zero to a multiple of quantum (used when converting to
-- native units so that a conversion never manufactures quantity).
function Num.floorTo(x, quantum)
    return math.floor(x / quantum + 1e-9) * quantum
end

function Num.roundTo(x, quantum)
    return math.floor(x / quantum + 0.5) * quantum
end

-- Linear interpolation over a sorted list of {x, y} points (clamped ends).
function Num.interp(points, x)
    local n = #points
    if x <= points[1][1] then return points[1][2] end
    if x >= points[n][1] then return points[n][2] end
    for i = 2, n do
        local p1, p2 = points[i - 1], points[i]
        if x <= p2[1] then
            local t = (x - p1[1]) / (p2[1] - p1[1])
            return p1[2] + (p2[2] - p1[2]) * t
        end
    end
    return points[n][2]
end

-- Neumaier-compensated sum of the values of an array.
function Num.sum(values)
    local s, c = 0, 0
    for i = 1, #values do
        local v = values[i]
        local t = s + v
        if math.abs(s) >= math.abs(v) then
            c = c + ((s - t) + v)
        else
            c = c + ((v - t) + s)
        end
        s = t
    end
    return s + c
end

return Num
