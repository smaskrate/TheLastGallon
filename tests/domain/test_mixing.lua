require "support/fixtures"
local Mixing, Supply, Aging = TLG.Domain.Mixing, TLG.Domain.Supply, TLG.Domain.Aging

local function can(q, deg, o)
    o = o or {}
    return F.supply({ id = o.id, storage = o.storage or "jerrycan_steel", cap = o.cap or 20, q = q, deg = deg,
        stab = o.stab, mic = o.mic, t = o.t or 100 })
end

T.case("mixing: transfer conserves every component", function()
    local a = can({ gasoline = 15, ethanol = 3, water = 0.1 }, { gasoline = 1.2, ethanol = 0.2 }, { id = "A" })
    local b = can({ gasoline = 4 }, { gasoline = 0.1 }, { id = "B" })
    local r = Mixing.previewTransfer(a, b, 7.5)
    T.ok(r.ok)
    T.near(r.moved, 7.5, 1e-12)
    for _, id in ipairs({ "gasoline", "ethanol", "water" }) do
        T.near(Supply.amount(r.src, id) + Supply.amount(r.dst, id), Supply.amount(a, id) + Supply.amount(b, id), 1e-9, id)
    end
    F.noViolations(r.src, "src"); F.noViolations(r.dst, "dst")
    -- Inputs untouched (preview is pure).
    T.near(Supply.total(a), 18.1, 1e-12)
end)

T.case("mixing: bounded by source, destination room and request", function()
    local a = can({ gasoline = 5 }, nil, { id = "A" })
    local b = can({ gasoline = 18 }, nil, { id = "B" })
    T.near(Mixing.previewTransfer(a, b, 10).moved, 2, 1e-12, "room")
    local empty = can({}, nil, { id = "E" })
    T.near(Mixing.previewTransfer(a, empty, 10).moved, 5, 1e-12, "source")
    local full = can({ gasoline = 20 }, nil, { id = "F" })
    local r = Mixing.previewTransfer(a, full, 1)
    T.eq(r.moved, 0); T.eq(r.reason, "destination_full")
    T.eq(Mixing.previewTransfer(a, b, -1).reason, "invalid_amount")
    T.eq(Mixing.previewTransfer(a, b, 0 / 0).reason, "invalid_amount")
end)

T.case("mixing: participants must be at the same time and phase", function()
    local a = can({ gasoline = 5 }, nil, { id = "A", t = 100 })
    local b = can({ gasoline = 5 }, nil, { id = "B", t = 101 })
    T.eq(Mixing.previewTransfer(a, b, 1).reason, "time_mismatch")
    local gas = F.supply({ id = "G", storage = "propane_cylinder", q = { propane = 1 }, t = 100 })
    T.eq(Mixing.previewTransfer(a, gas, 1).reason, "phase_mismatch")
    T.eq(Mixing.previewTransfer(a, a, 1).reason, "same_supply")
end)

T.case("mixing: split and recombine preserves properties", function()
    local orig = can({ gasoline = 12, ethanol = 2, water = 0.05 }, { gasoline = 1.7, ethanol = 0.3 },
        { id = "O", stab = 0.5, mic = 0.1 })
    local half = can({}, nil, { id = "H" })
    local r1 = Mixing.previewTransfer(orig, half, 6.37)
    local r2 = Mixing.previewTransfer(r1.dst, r1.src, 100)
    F.assertSupplyClose(r2.dst, orig, 1e-12, "recombined")
    T.ok(Supply.isEmpty(r2.src), "split vessel empty")
end)

T.case("mixing: new containers and labels never rejuvenate fuel", function()
    local old = can({ gasoline = 10 }, { gasoline = 2.6 }, { id = "OLD" })
    local fresh = can({}, nil, { id = "NEW" })
    fresh.label = "brand new!"
    local r = Mixing.previewTransfer(old, fresh, 10)
    T.near(r.dst.deg.gasoline, 2.6, 1e-12)
end)

T.case("mixing: a small fresh addition cannot reset a large degraded reserve", function()
    local big = can({ gasoline = 990 }, { gasoline = 3.0 }, { id = "BIG", cap = 1000, storage = "tank_ibc" })
    local small = can({ gasoline = 10 }, { gasoline = 0 }, { id = "S" })
    local r = Mixing.previewTransfer(small, big, 10)
    T.near(r.dst.deg.gasoline, 2.97, 1e-9)
end)

T.case("mixing: repeated tiny transfers never manufacture quantity", function()
    local rng = TLG.Rng.new(TEST_SEED)
    local a = can({ gasoline = 10, ethanol = 1.3, water = 0.01 }, { gasoline = 0.5, ethanol = 0.1 }, { id = "A" })
    local b = can({ gasoline = 3 }, { gasoline = 1.1 }, { id = "B" })
    local initial = Supply.total(a) + Supply.total(b)
    local destroyed = 0
    for i = 1, 20000 do
        local amt = rng:range(1e-7, 2e-4)
        local r
        if i % 2 == 0 then r = Mixing.previewTransfer(a, b, amt) else r = Mixing.previewTransfer(b, a, amt) end
        if i % 2 == 0 then a, b = r.src, r.dst else b, a = r.src, r.dst end
        destroyed = destroyed + (r.dust or 0)
        T.le(Supply.total(a) + Supply.total(b), initial + 1e-9, "no creation at step " .. i)
    end
    T.near(Supply.total(a) + Supply.total(b) + destroyed, initial, 1e-9, "conserved including dust")
end)

T.case("mixing: unknown native inflow uses the baseline, never fresh fuel", function()
    local s = can({ gasoline = 5 }, { gasoline = 0.5 }, { id = "S" })
    local out = Mixing.addUntracked(s, "gasoline", 5, { deg = 2.0 })
    T.near(out.deg.gasoline, 1.25, 1e-12)
    T.eq(out.prov[#out.prov].k, "untracked")
end)

T.case("mixing: proportional removal for observed native consumption", function()
    local s = can({ gasoline = 9, ethanol = 1, water = 0.02 }, { gasoline = 1, ethanol = 0.2 }, { id = "S" })
    local out, parcel = Mixing.removeProportional(s, 5)
    T.near(Supply.total(out), 5.02, 1e-9)
    T.near(parcel.gasoline / parcel.ethanol, 9, 1e-9)
    T.near(out.deg.gasoline, 1, 1e-12, "condition unchanged by proportional draw")
end)

T.case("mixing: blend preview uses the same rules as transfers", function()
    local a = can({ gasoline = 10 }, { gasoline = 2 }, { id = "A" })
    local b = can({ ethanol = 10 }, { ethanol = 0 }, { id = "B" })
    local res = TLG.FuelService.previewBlend({ { supply = a, amount = 9 }, { supply = b, amount = 1 } }, "engine_si_stock")
    T.near(Supply.fraction(res.supply, "ethanol"), 0.1, 1e-12)
    T.ok(res.evaluation.compatible, "E10 accepted by stock engine")
    local viaTransfer = Mixing.previewTransfer(b, Mixing.previewTransfer(a, can({}, nil, { id = "C" }), 9).dst, 1).dst
    T.near(Supply.blendDeg(viaTransfer), Supply.blendDeg(res.supply), 1e-12)
end)
