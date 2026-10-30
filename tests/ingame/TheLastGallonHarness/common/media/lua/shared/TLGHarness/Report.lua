-- Result writer for in-game experiments. Results go to <cachedir>/Lua/<file>
-- through getFileWriter and are also echoed to the console log. The file is
-- rewritten after every line so a crash or hang still leaves evidence.
TLGH = TLGH or {}
TLGH.Report = {}
local Report = TLGH.Report
Report.__index = Report

function Report.new(fileName, title, append)
    local o = setmetatable({}, Report)
    o.fileName = fileName
    o.lines = {}
    o.pass = 0
    o.fail = 0
    if append then
        local r = getFileReader(fileName, false)
        if r then
            local l = r:readLine()
            while l do
                o.lines[#o.lines + 1] = l
                l = r:readLine()
            end
            r:close()
        end
    end
    o:line("# %s", title)
    o:line("game=%s", tostring(getCore and getCore():getVersion() or "?"))
    o:line("isServer=%s isClient=%s", tostring(isServer()), tostring(isClient()))
    return o
end

function Report:flush()
    local w = getFileWriter(self.fileName, true, false)
    for _, l in ipairs(self.lines) do
        w:write(l .. "\n")
    end
    w:close()
end

function Report:line(fmt, ...)
    local ok, msg = pcall(string.format, fmt, ...)
    if not ok then msg = tostring(fmt) end
    self.lines[#self.lines + 1] = msg
    print("[TLGH] " .. msg)
    self:flush()
end

-- Records a named check. `fn` returns ok, detail; errors count as failures.
function Report:check(name, fn)
    local ok, a, b = pcall(fn)
    local passed, detail
    if not ok then
        passed, detail = false, "ERROR " .. tostring(a)
    else
        passed, detail = (a and true or false), b
    end
    if passed then self.pass = self.pass + 1 else self.fail = self.fail + 1 end
    self:line("%s %s :: %s", passed and "PASS" or "FAIL", name, tostring(detail))
    return passed
end

-- Records an observation that is not pass/fail.
function Report:observe(name, fn)
    local ok, v = pcall(fn)
    self:line("OBS  %s :: %s", name, ok and tostring(v) or ("ERROR " .. tostring(v)))
    return ok and v or nil
end

function Report:finish(final)
    self:line("SUMMARY pass=%d fail=%d", self.pass, self.fail)
    if final ~= false then self:line("DONE") end
end

return Report
