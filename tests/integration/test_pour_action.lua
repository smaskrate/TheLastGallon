require "support/fixtures"
require "TLG/Integration/Containers"
local I, D, World = TLG.Integration, TLG.Domain, TLG.World

-- The game's pour action (ISFluidTransferAction, behind the Transfer Liquid
-- window) pours a slice per update and the rest when it completes. RT-SP
-- run 213: followed slice by slice, the water and sediment of aged petrol
-- did not reach the target. These cases run a stand-in of the action on
-- stand-ins of the game's fluids, through the mod's real hook.

-- Stand-ins for the game: the clock (World.now, World.env), global ModData,
-- the fluids, inventory items with one fluid container each, and
-- FluidContainer.Transfer. A container keeps its fluids in a list, as the
-- game does; the transfer moves the amount out of the source in its
-- proportions, and a fluid under 1e-4 L is then dropped with its litres
-- (removeFluidInstanceIfEmpty, BC 42.21), the strictest the game can be
-- with the traces of one slice.
local GLOBALS = { "ModData", "getGameTime", "isServer", "isClient", "instanceof", "Fluid", "FluidContainer",
    "ISFluidTransferAction" }

local function fluidOf(name, byName)
    if byName[name] == nil then
        local f = { name = name }
        function f:getFluidTypeString() return self.name end
        byName[name] = f
    end
    return byName[name]
end

local function container(owner, capacity)
    local fc = { owner = owner, cap = capacity, list = {} }
    function fc:getOwner() return self.owner end
    function fc:getCapacity() return self.cap end
    function fc:getAmount()
        local s = 0
        for _, e in ipairs(self.list) do s = s + e.amount end
        return s
    end
    function fc:isEmpty() return #self.list == 0 end
    function fc:addFluid(fluid, amount)
        if amount <= 0 then return end
        for _, e in ipairs(self.list) do
            if e.fluid == fluid then
                e.amount = e.amount + amount
                return
            end
        end
        self.list[#self.list + 1] = { fluid = fluid, amount = amount }
    end
    function fc:adjustSpecificFluidAmount(fluid, amount)
        for i = #self.list, 1, -1 do
            if self.list[i].fluid == fluid then
                self.list[i].amount = amount
                if amount < 1e-4 then table.remove(self.list, i) end
            end
        end
    end
    function fc:getSpecificFluidAmount(fluid)
        for _, e in ipairs(self.list) do
            if e.fluid == fluid then return e.amount end
        end
        return 0
    end
    function fc:createFluidSample()
        local s, fluids = {}, {}
        for i, e in ipairs(self.list) do fluids[i] = e.fluid end
        function s:size() return #fluids end
        function s:getFluid(i) return fluids[i + 1] end
        function s:release() end
        return s
    end
    return fc
end

local function gameTransfer(a, b, amount)
    local total = a:getAmount()
    if total <= 0 or amount <= 0 then return end
    local share = math.min(amount, total) / total
    for _, e in ipairs(a.list) do
        local d = e.amount * share
        e.amount = e.amount - d
        b:addFluid(e.fluid, d)
    end
    for _, fc in ipairs({ a, b }) do
        for i = #fc.list, 1, -1 do
            if fc.list[i].amount < 1e-4 then table.remove(fc.list, i) end
        end
    end
end

-- The action as the game has it (SRC ISFluidTransferAction.lua): each
-- update takes the source down to where the pour's progress says, complete
-- pours what is left of the amount, stop leaves the rest.
local Pour = {}
Pour.__index = Pour
local function holder(fc) return { getFluidContainer = function() return fc end } end
function Pour.new(src, dst, amount, ticks)
    local o = setmetatable({ source = holder(src.fc), target = holder(dst.fc), amount = amount, maxTime = ticks,
        tick = 0 }, Pour)
    o.sourceStartAmount = src.fc:getAmount()
    return o
end
function Pour:update()
    self.tick = self.tick + 1
    local left = self.sourceStartAmount - self.amount * math.min(1, self.tick / self.maxTime)
    local fc = self.source:getFluidContainer()
    FluidContainer.Transfer(fc, self.target:getFluidContainer(), math.max(0, fc:getAmount() - left))
end
function Pour:complete()
    local fc = self.source:getFluidContainer()
    FluidContainer.Transfer(fc, self.target:getFluidContainer(),
        math.max(0, fc:getAmount() - (self.sourceStartAmount - self.amount)))
    return true
end
function Pour:stop() self.stopped = true end

-- The hook is installed once per Lua state (Containers.install); the
-- stand-in FluidContainer and action stay the ones it wrapped.
local Transfer = { Transfer = function(a, b, amount) return gameTransfer(a, b, amount) end }
local installed = false

local function fakeGame(now)
    local saved = {}
    for _, k in ipairs(GLOBALS) do saved[k] = _G[k] end
    local g = { now = now, store = {}, writes = {}, warnings = {}, byName = {} }
    ModData = { getOrCreate = function(k)
        g.store[k] = g.store[k] or {}
        return g.store[k]
    end }
    local clock = {}
    function clock:getWorldAgeHours() return g.now end
    getGameTime = function() return clock end
    isServer, isClient = function() return false end, function() return false end
    instanceof = function(o, cls) return type(o) == "table" and o.class == cls end
    Fluid = { Get = function(name) return fluidOf(name, g.byName) end }
    FluidContainer, ISFluidTransferAction = Transfer, Pour
    if not installed then
        I.Containers.install()
        installed = true
    end
    local md = World.get()
    md.v, md.calendar, md.climateLog = 1, { dayOfYear = 190, hourOfDay = 9 }, {}
    local srv = World.server()
    srv.seed, srv.nextId = srv.seed or 7, srv.nextId or 1
    local writeSidecar, warn = I.Containers.writeSidecar, TLG.Log.warn
    I.Containers.writeSidecar = function(owner, kind, rec)
        g.writes[owner.id] = (g.writes[owner.id] or 0) + 1
        return writeSidecar(owner, kind, rec)
    end
    TLG.Log.warn = function(fmt, ...) g.warnings[#g.warnings + 1] = string.format(fmt, ...) end
    function g.restore()
        for _, k in ipairs(GLOBALS) do _G[k] = saved[k] end
        I.Containers.writeSidecar, TLG.Log.warn = writeSidecar, warn
    end
    return g
end

local function run(fn)
    local g = fakeGame(100)
    local ok, err = pcall(fn, g)
    g.restore()
    if not ok then error(err, 0) end
end

-- An inventory can holding `fills` ({ native fluid name, litres }) and,
-- when given, the record the mod wrote for it.
local function can(g, id, fills, record)
    local it = { class = "InventoryItem", id = id, md = { tlg = record } }
    it.fc = container(it, 10)
    for _, f in ipairs(fills) do it.fc:addFluid(fluidOf(f[1], g.byName), f[2]) end
    function it:getModData() return self.md end
    function it:getFluidContainerFromSelfOrWorldItem() return self.fc end
    function it:getFluidContainer() return self.fc end
    function it:getFullType() return "Base.PetrolCan" end
    function it:getID() return self.id end
    function it:syncItemFields() end
    return it
end

-- Can A of run 213: petrol with the mod's ethanol, water and sediment,
-- aged and stabilized, recorded at world hour 100.
local A_FLUIDS = { { "Petrol", 6 }, { "TLG_Ethanol", 1.5 }, { "TLG_FuelWater", 0.06 }, { "TLG_FuelSediment", 0.02 } }
local function canA(g)
    return can(g, 1, A_FLUIDS, { v = 1, id = "S1", rev = 1, t = 100,
        q = { gasoline = 6, ethanol = 1.5, water = 0.06, sediment = 0.02 }, deg = { gasoline = 0.3, ethanol = 0.15 },
        stab = 0.6, mic = 0.02, cond = 1, sealed = false, storage = "jerrycan_steel", prov = {} })
end

local A_Q = { gasoline = 6, ethanol = 1.5, water = 0.06, sediment = 0.02 }
local A_TOTAL = 7.58

-- The can's fluids hold what its record says, component by component.
local function fluidsMatchRecord(x, label)
    local q, comp = x.md.tlg.q, I.Native.readComposition(x.fc)
    for id, v in pairs(q) do T.near(comp[id] or 0, v, 1e-9, label .. " fluids: " .. id) end
    for id, v in pairs(comp) do T.near(q[id] or 0, v, 1e-9, label .. " fluids: " .. id) end
end

-- `x` holds `litres` of can A's fuel, in A's condition.
local function holdsFuelOfA(x, litres, label)
    local rec = x.md.tlg
    for id, v in pairs(A_Q) do T.near(rec.q[id] or 0, v / A_TOTAL * litres, 1e-9, label .. ": " .. id) end
    T.near(rec.deg.gasoline, 0.3, 1e-9, label .. ": petrol's ageing")
    T.near(rec.deg.ethanol, 0.15, 1e-9, label .. ": ethanol's ageing")
    T.near(rec.stab, 0.6, 1e-9, label .. ": stabilizer")
    T.near(rec.mic, 0.02, 1e-9, label .. ": microbial growth")
    fluidsMatchRecord(x, label)
end

T.case("integration: the game's pour action is followed once, the water and sediment of every slice kept", function()
    run(function(g)
        local a, b = canA(g), can(g, 2, {})
        -- Run 213: half of A, 3.79 L, in 190 slices.
        local act = Pour.new(a, b, A_TOTAL / 2, 190)
        for _ = 1, 189 do act:update() end
        T.ok(b.md.tlg == nil and (g.writes[1] or 0) == 0, "no record written while the slices go in")
        T.ok(act:complete(), "complete returns what the game's does")
        holdsFuelOfA(b, A_TOTAL / 2, "target")
        T.near(b.md.tlg.q.water, 0.03, 1e-9, "the water arrived")
        T.near(b.md.tlg.q.sediment, 0.01, 1e-9, "the sediment arrived")
        holdsFuelOfA(a, A_TOTAL / 2, "source")
        T.eq(g.writes[1], 1, "the source's record written once")
        T.eq(g.writes[2], 1, "the target's record written once")
        T.eq(#g.warnings, 0, table.concat(g.warnings, " | "))
        local again, status = I.Containers.read(b, "item", false)
        T.eq(status, "ok", "the next read finds the fluids as recorded")
        T.near(again.q.sediment, 0.01, 1e-9, "the next read keeps the sediment")
    end)
end)

T.case("integration: a pour stopped part-way is followed for the litres that left", function()
    run(function(g)
        local a, b = canA(g), can(g, 2, {})
        local act = Pour.new(a, b, A_TOTAL / 2, 190)
        for _ = 1, 60 do act:update() end
        act:stop()
        T.ok(act.stopped, "the game's stop ran")
        local moved = A_TOTAL / 2 * 60 / 190
        holdsFuelOfA(b, moved, "target")
        holdsFuelOfA(a, A_TOTAL - moved, "source")
        local _, status = I.Containers.read(b, "item", false)
        T.eq(status, "ok", "not left to be found as fuel of unknown origin")
        -- The game does not complete a stopped action; a second stop moves nothing.
        act:stop()
        T.eq(g.writes[2], 1, "followed once")
    end)
end)

T.case("integration: a pour outside the action is still followed call by call", function()
    run(function(g)
        local a, b = canA(g), can(g, 2, {})
        FluidContainer.Transfer(a.fc, b.fc, 1)
        holdsFuelOfA(b, 1, "target")
        holdsFuelOfA(a, A_TOTAL - 1, "source")
    end)
end)

T.case("integration: a pour of a fluid the mod does not track is left to the game", function()
    run(function(g)
        local a, b = can(g, 1, { { "Water", 5 } }), can(g, 2, {})
        local act = Pour.new(a, b, 2, 20)
        for _ = 1, 19 do act:update() end
        act:complete()
        T.near(b.fc:getAmount(), 2, 1e-9, "the game moved the water")
        T.ok(a.md.tlg == nil and b.md.tlg == nil, "no record written")
    end)
end)

T.case("integration: a pour during which a record was written is left to the next read", function()
    run(function(g)
        local a, b = canA(g), can(g, 2, {})
        local act = Pour.new(a, b, 2, 100)
        for _ = 1, 50 do act:update() end
        -- Another write to the source while it pours (another player, on a server).
        a.md.tlg.rev = a.md.tlg.rev + 1
        act:complete()
        T.near(a.fc:getAmount(), A_TOTAL - 2, 1e-9, "the game moved the litres")
        T.ok(b.md.tlg == nil, "the target's record not written from out-of-date records")
        T.eq(#g.warnings, 1, "one warning")
        T.ok(string.find(g.warnings[1] or "", "a record was written during it", 1, true) ~= nil, g.warnings[1])
    end)
end)
