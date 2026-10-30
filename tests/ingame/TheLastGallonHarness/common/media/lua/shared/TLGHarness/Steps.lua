-- Tick-driven step runner for in-game experiments. Each step is
-- { name, fn(ctx, ticks, H), timeout }; fn returns true when finished and nil
-- to keep waiting. Errors and timeouts are logged and the runner moves on,
-- so one launch yields evidence even when some steps fail.
TLGH = TLGH or {}
TLGH.Steps = {}

function TLGH.Steps.run(report, steps, shared, onDone)
    local i, started, ticks, ctx = 1, false, 0, nil
    local function tick()
        local step = steps[i]
        if not step then
            Events.OnTick.Remove(tick)
            if onDone then onDone() end
            return
        end
        if not started then
            report:line("STEP %s begin", step.name)
            started, ticks, ctx = true, 0, {}
        end
        ticks = ticks + 1
        local ok, res = pcall(step.fn, ctx, ticks, shared)
        if not ok then
            report:line("STEPERR %s :: %s", step.name, tostring(res))
            res = true
        end
        if res == true then
            i, started = i + 1, false
        elseif ticks > (step.timeout or 900) then
            report:line("TIMEOUT %s after %d ticks", step.name, ticks)
            i, started = i + 1, false
        end
    end
    Events.OnTick.Add(tick)
end

function TLGH.Steps.actionsIdle(player)
    local q = ISTimedActionQueue.getTimedActionQueue(player)
    local queueEmpty = (q == nil) or (q.queue == nil) or (#q.queue == 0)
    return queueEmpty and player:getCharacterActions():isEmpty()
end

function TLGH.readRequest()
    local r = getFileReader("TLG_harness_request.txt", false)
    if not r then return nil end
    local line = r:readLine()
    r:close()
    return line
end

function TLGH.writeFile(name, lines)
    local w = getFileWriter(name, true, false)
    for _, l in ipairs(lines) do w:write(l .. "\n") end
    w:close()
end

function TLGH.readKeyValues(name)
    local out = {}
    local r = getFileReader(name, false)
    if not r then return out end
    local l = r:readLine()
    while l do
        local k, v = string.match(l, "^([^=]+)=(.*)$")
        if k then out[k] = v end
        l = r:readLine()
    end
    r:close()
    return out
end

function TLGH.fluidSummary(fc)
    if not fc then return "nofc" end
    local s = fc:createFluidSample()
    local parts = {}
    for i = 0, s:size() - 1 do
        local f = s:getFluid(i)
        parts[#parts + 1] = string.format("%s=%.4f", f:getFluidTypeString(), fc:getSpecificFluidAmount(f))
    end
    s:release()
    return string.format("total=%.4f [%s]", fc:getAmount(), table.concat(parts, ","))
end
