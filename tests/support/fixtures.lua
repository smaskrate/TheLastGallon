-- Shared fixtures for domain tests.
require "TLG/Content/Fuels"
require "TLG/Content/Storage"
require "TLG/Content/Consumers"
require "TLG/Domain/FuelService"
require "TLG/Domain/WorldInit"

F = F or {}

-- July 9 start (day 190), 09:00, like the default B42 start.
function F.env(history)
    return TLG.Domain.Climate.new({ dayOfYear = 190, hourOfDay = 9 }, {}, history)
end

function F.supply(o)
    return TLG.Domain.Supply.new(o)
end

-- Relative/absolute closeness for state comparisons.
function F.close(a, b, rel)
    rel = rel or 1e-9
    return math.abs(a - b) <= rel * math.max(1, math.abs(a), math.abs(b))
end

function F.assertSupplyClose(a, b, rel, label)
    label = label or "supply"
    local keys = {}
    for k in pairs(a.q) do keys[k] = true end
    for k in pairs(b.q) do keys[k] = true end
    for k in pairs(keys) do
        T.ok(F.close(a.q[k] or 0, b.q[k] or 0, rel), label .. ": q." .. k .. " " .. tostring(a.q[k]) .. " vs " .. tostring(b.q[k]))
    end
    for k in pairs(keys) do
        if a.deg[k] or b.deg[k] then
            T.ok(F.close(a.deg[k] or 0, b.deg[k] or 0, rel), label .. ": deg." .. k .. " " .. tostring(a.deg[k]) .. " vs " .. tostring(b.deg[k]))
        end
    end
    T.ok(F.close(a.mic, b.mic, rel), label .. ": mic " .. a.mic .. " vs " .. b.mic)
    T.ok(F.close(a.stab, b.stab, rel), label .. ": stab")
end

function F.noViolations(s, label)
    local bad = TLG.Domain.Supply.check(s)
    T.ok(#bad == 0, (label or "supply") .. " invariants: " .. table.concat(bad, ", "))
end
