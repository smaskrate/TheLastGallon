-- Deterministic pseudo-random numbers and stable string hashing.
-- math.random is absent in the Kahlua J2SE environment and ZombRand is not
-- reproducible, so world seeding and tests use this Park-Miller generator.
-- All products stay below 2^53, so double arithmetic is exact.
require "TLG/Util/Num"

TLG.Rng = TLG.Rng or {}
local Rng = TLG.Rng
local Num = TLG.Num

local MOD = 2147483647
local MUL = 48271

Rng.__index = Rng

function Rng.new(seed)
    local s = Num.mod(math.floor(seed or 1), MOD)
    if s == 0 then s = 1 end
    return setmetatable({ state = s }, Rng)
end

-- Uniform in [0, 1).
function Rng:next()
    self.state = Num.mod(self.state * MUL, MOD)
    return (self.state - 1) / (MOD - 1)
end

-- Integer in [lo, hi].
function Rng:int(lo, hi)
    return lo + math.floor(self:next() * (hi - lo + 1))
end

function Rng:range(lo, hi)
    return lo + (hi - lo) * self:next()
end

-- Approximately normal (Irwin-Hall, n = 6), mean 0, sd 1.
function Rng:normal()
    local s = 0
    for _ = 1, 6 do s = s + self:next() end
    return (s - 3) * math.sqrt(2)
end

function Rng:pick(list)
    return list[self:int(1, #list)]
end

-- Stable 31-bit hash of a string (polynomial, exact in doubles).
function Rng.hash(str, salt)
    local h = Num.mod(salt or 5381, MOD)
    for i = 1, #str do
        h = Num.mod(h * 33 + string.byte(str, i), MOD)
    end
    return h
end

-- Deterministic value in [0, 1) for a (seed, key) pair, e.g. station variation
-- seeded by world seed and stable site id.
function Rng.unit(seed, key)
    local r = Rng.new(Rng.hash(key, seed))
    r:next()
    return r:next()
end

return Rng
