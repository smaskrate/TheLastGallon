-- Minimal test framework for the Kahlua runner.
-- Kahlua turns table-valued errors into strings, so failures are plain strings.
T = {
    cases = {},
    failures = {},
    passed = 0,
    failed = 0,
    assertions = 0,
}

local function fmt(v)
    if type(v) == "string" then
        return string.format("%q", v)
    end
    return tostring(v)
end

function T.case(name, fn)
    T.cases[#T.cases + 1] = { name = name, fn = fn }
end

function T.fail(msg)
    error("ASSERT: " .. tostring(msg), 2)
end

function T.ok(cond, msg)
    T.assertions = T.assertions + 1
    if not cond then
        error("ASSERT: " .. tostring(msg or "expected truthy value"), 2)
    end
end

function T.eq(actual, expected, msg)
    T.assertions = T.assertions + 1
    if actual ~= expected then
        error("ASSERT: " .. tostring(msg or "values differ") .. ": expected " .. fmt(expected) .. ", got " .. fmt(actual), 2)
    end
end

function T.near(actual, expected, tol, msg)
    T.assertions = T.assertions + 1
    tol = tol or 1e-9
    if type(actual) ~= "number" or type(expected) ~= "number" or math.abs(actual - expected) > tol then
        error("ASSERT: " .. tostring(msg or "numbers differ") .. ": expected " .. fmt(expected) ..
            " +/- " .. tostring(tol) .. ", got " .. fmt(actual), 2)
    end
end

function T.le(a, b, msg)
    T.assertions = T.assertions + 1
    if not (a <= b) then
        error("ASSERT: " .. tostring(msg or "expected a <= b") .. ": " .. fmt(a) .. " > " .. fmt(b), 2)
    end
end

-- Asserts that fn raises an error whose message contains `fragment` (if given).
function T.raises(fn, fragment, msg)
    T.assertions = T.assertions + 1
    local ok, err = pcall(fn)
    if ok then
        error("ASSERT: " .. tostring(msg or "expected an error"), 2)
    end
    if fragment and not string.find(tostring(err), fragment, 1, true) then
        error("ASSERT: " .. tostring(msg or "error message mismatch") .. ": wanted '" .. fragment ..
            "' in " .. tostring(err), 2)
    end
end

function T.run(filter)
    for _, c in ipairs(T.cases) do
        if not filter or string.find(c.name, filter, 1, true) then
            local ok, err = pcall(c.fn)
            if ok then
                T.passed = T.passed + 1
            else
                T.failed = T.failed + 1
                T.failures[#T.failures + 1] = c.name .. "\n      " .. tostring(err)
                print("FAIL " .. c.name)
                print("      " .. tostring(err))
            end
        end
    end
    return T.failed == 0
end
