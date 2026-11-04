require "TLG/Util/Num"
require "TLG/Util/Tables"
require "TLG/Util/Rng"
local Num, Tables, Rng = TLG.Num, TLG.Tables, TLG.Rng

T.case("util: floored modulo matches Lua semantics on Kahlua", function()
    T.eq(Num.mod(-7, 3), 2)
    T.eq(Num.mod(7, 3), 1)
    T.eq(Num.mod(-0.5, 24), 23.5)
end)

T.case("util: merge sort is stable and handles sorted/reversed input", function()
    local list = {}
    for i = 1, 5000 do list[i] = { k = math.floor(i / 10), i = i } end
    Tables.sort(list, function(a, b) return a.k < b.k end)
    for i = 2, #list do
        T.ok(list[i - 1].k < list[i].k or (list[i - 1].k == list[i].k and list[i - 1].i < list[i].i), "stable order")
    end
    local rev = {}
    for i = 1, 5000 do rev[i] = 5001 - i end
    Tables.sort(rev)
    T.eq(rev[1], 1); T.eq(rev[5000], 5000)
end)

T.case("util: sortedKeys orders numbers before strings deterministically", function()
    local keys = Tables.sortedKeys({ b = 1, a = 2, [3] = 0, [1] = 0 })
    T.eq(table.concat({ tostring(keys[1]), tostring(keys[2]), keys[3], keys[4] }, ","), "1,3,a,b")
end)

T.case("util: kthKey gives the k-th of the sorted keys without sorting", function()
    local r = Rng.new(TEST_SEED or 20261030)
    for trial = 1, 300 do
        local t = {}
        for _ = 1, r:int(0, 40) do
            local kind, key = r:int(1, 4), nil
            if kind == 1 then key = r:int(-50, 50)
            elseif kind == 2 then key = r:int(0, 1000) + r:next()
            elseif kind == 3 then key = "k" .. r:int(1, 30)
            else key = r:int(100, 200) end
            t[key] = true
        end
        local keys = Tables.sortedKeys(t)
        for k = 0, #keys + 2 do
            T.eq(Tables.kthKey(t, k), keys[k], string.format("trial %d: key %d of %d", trial, k, #keys))
        end
    end
end)

T.case("util: isEmpty works without next()", function()
    T.ok(Tables.isEmpty({}))
    T.ok(not Tables.isEmpty({ x = false }))
end)

T.case("util: rng is deterministic and in range", function()
    local a, b = Rng.new(42), Rng.new(42)
    for _ = 1, 1000 do
        local x = a:next()
        T.eq(x, b:next())
        T.ok(x >= 0 and x < 1, "unit interval")
    end
    local r = Rng.new(7)
    for _ = 1, 500 do
        local v = r:int(3, 5)
        T.ok(v >= 3 and v <= 5 and v == math.floor(v), "int range")
    end
    T.eq(Rng.hash("station:Muldraugh:1"), Rng.hash("station:Muldraugh:1"))
    T.ok(Rng.hash("a") ~= Rng.hash("b"), "hash differs")
end)

T.case("util: compensated sum", function()
    local v = {}
    for i = 1, 10000 do v[i] = 0.1 end
    T.near(Num.sum(v), 1000, 1e-9)
end)
