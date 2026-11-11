-- Multiplayer harness, further cases (tools/run-mp-harness.ps1 -Only
-- machines|fuel|conversion|carconv|stills|effects|timers|biodiesel), built from
-- MPHarness.lua's helpers (MP.h).
-- machines: a running vessel moved where no Lua sees it (the world menu's
-- Grab and the inventory's Drop are item transactions on a client, D-015),
-- and two players loading one fermenter at once. effects and timers: the
-- engine effects (D-031) and the machines' timers (D-032) with the server
-- applying them (each described where its steps are built).
-- Results: <cachedir>/Lua/TLG_harness_mp.txt, as MPHarness.lua's.
require "TLGHarness/MPHarness"

local MP = TLGH.MP
if not MP or not MP.h then return end
local S = TLGH.MPShared
local h = MP.h
local report, player, check, send, call, once, wait = h.report, h.player, h.check, h.send, h.call, h.once, h.wait
local waitFrom, nextFrom, request, brief, walkTo, idle = h.waitFrom, h.nextFrom, h.request, h.brief, h.walkTo, h.idle
local floorItem, inventoryItem, countType, ids = h.floorItem, h.inventoryItem, h.countType, h.ids

------------------------------------------------------------------------------
-- gensprite (2026-11-11, one client, -Only gensprite -ModAway): the server
-- played with the mod, then without it, then with it again; A joins each
-- time. Session 1: the server puts a Diesel Generator down and A sees its
-- sprite. Session 2, no mod on the server or on A: the game loads the
-- generator without its tile sheet and saves it. Session 3: the mod's
-- LoadGridsquare handler on the server must have given the sprite back
-- (0.3.2), and A must see it with its picture. The session is kept in the
-- snap file, which outlives the Lua; this block runs before the others and
-- uses nothing of the mod in session 2.
------------------------------------------------------------------------------
if MP.only == "gensprite" then
    local SNAP = "TLG_harness_mpsnap.txt"
    local snap = TLGH.readKeyValues(SNAP)
    local function generator()
        local e = TLGH.readKeyValues(SNAP)
        local sq = getCell():getGridSquare(tonumber(e.gx) or -1, tonumber(e.gy) or -1, 0)
        local objs = sq and sq:getObjects()
        for i = 0, (objs and objs:size() or 0) - 1 do
            if instanceof(objs:get(i), "IsoGenerator") then return objs:get(i) end
        end
        return nil
    end
    local function seen()
        local g = generator()
        local name, tex = "none", nil
        pcall(function()
            local s = g:getSprite()
            name = s and tostring(s:getName()) or "none"
        end)
        pcall(function() tex = g:getSprite():getTextureForCurrentFrame(g:getDir()) end)
        return g, name, tex
    end
    local function leaveAs(session)
        return { name = "mp_gs_leave_" .. session, timeout = 600, fn = function(ctx, ticks)
            if ticks < 60 then return nil end
            local e = TLGH.readKeyValues(SNAP)
            TLGH.writeFile(SNAP, { "gx=" .. tostring(e.gx), "gy=" .. tostring(e.gy), "session=" .. tostring(session) })
            h.setPhase("restart_wait")
            report():line("OBS  MP.leaving to the main menu for the server's restart (after session %d)", session)
            setGameSpeed(1)
            getCore():quit()
            return true
        end }
    end
    MP.stepsA = { MP.waitWorld,
        call("gs_setup", "setup_gensprite", {}, "setup_gensprite", function(m)
            TLGH.writeFile(SNAP, { "gx=" .. tostring(m.gx), "gy=" .. tostring(m.gy), "session=0" })
        end),
        wait("mp_gs_generator_arrives", 240),
        once("mp_gs_seen_with_the_mod", function()
            local g, name, tex = seen()
            check("gs_generator_drawn_before_the_mod_goes", function()
                return g ~= nil and name == "tlg_generators_01_0" and tex ~= nil, string.format(
                    "generator %s, sprite %s, picture %s", tostring(g ~= nil), name, tostring(tex ~= nil))
            end)
        end),
        leaveAs(1) }
    if snap.session == "1" then
        MP.stepsRejoined = { MP.waitWorld, wait("mp_gs_settle_without_the_mod", 300),
            once("mp_gs_seen_without_the_mod", function()
                local g, name, tex = seen()
                check("gs_no_mod_in_this_session", function()
                    return TLG == nil or TLG.Integration == nil, "the mod's table on this client: " .. tostring(TLG ~= nil
                        and TLG.Integration ~= nil)
                end)
                check("gs_generator_kept_without_its_sprite", function()
                    return g ~= nil and name ~= "tlg_generators_01_0", string.format(
                        "generator %s, generatorFullType %s, sprite %s, picture %s", tostring(g ~= nil),
                        tostring(g and g:getModData().generatorFullType), name, tostring(tex ~= nil))
                end)
            end),
            leaveAs(2) }
    elseif snap.session == "2" then
        MP.stepsRejoined = { MP.waitWorld, wait("mp_gs_settle_with_the_mod_back", 300),
            call("gs_probe", "probe_gensprite", function()
                local e = TLGH.readKeyValues(SNAP)
                return { gx = e.gx, gy = e.gy }
            end, "probe_gensprite", function(m)
                check("gs_server_has_the_sprite_back", function()
                    return m.found == "true" and m.sprite == "tlg_generators_01_0" and m.profile == "generator_ci_bio",
                        string.format("server: generator %s, type %s, sprite %s, profile %s", tostring(m.found),
                            tostring(m.fullType), tostring(m.sprite), tostring(m.profile))
                end)
            end),
            once("mp_gs_seen_with_the_mod_back", function()
                local g, name, tex = seen()
                check("gs_client_sees_the_sprite_back", function()
                    return g ~= nil and name == "tlg_generators_01_0" and tex ~= nil, string.format(
                        "generator %s, sprite %s, picture %s", tostring(g ~= nil), name, tostring(tex ~= nil))
                end)
            end),
            once("mp_finish_b", function() send("finish", {}) end), MP.finish }
    end
    return
end

------------------------------------------------------------------------------
-- handbook (2026-11-11, one client, D-038): the biodiesel recipes on a
-- server, in a client without -debug. The Ash Barrel (a metal drum, two
-- steel rods, a hammer; Welding 2) is tried in the game's crafting window
-- three times with its materials in the inventory: with the recipe not
-- learned, with the handbook read and Welding 0, and with Welding 2. The
-- window must offer Craft only the last time, and the barrel must then be
-- made on the server. The server also rolls its loot lists for the
-- handbook (MPServer.lua roll_handbook).
------------------------------------------------------------------------------
-- handbook3 (2026-11-11, one client): the same window for the three other
-- welded machines, with the materials for all three. Welding 3 and the
-- handbook read: each refused, below its level. Welding 4: the Wood Retort
-- and the Wash Tank made, the Reactor (Welding 5) refused. Welding 5: the
-- Reactor made. handbook3u: Welding 5 (below the level that teaches any of
-- them) and nothing read: each refused, not learned. The Lye Leacher is
-- not tried: it is made on a surface, and the harness's ground has none.
------------------------------------------------------------------------------
if MP.only == "handbook" or MP.only == "handbook3" or MP.only == "handbook3u" or MP.only == "onebelow"
    or MP.only == "onebelow2" or MP.only == "onebelow3" or MP.only == "onebelow4" then
    local HB = { recipe = "TLG_MakeAshBarrel" }
    local function recipes()
        local out = {}
        local list = CraftRecipeManager.queryRecipes("InHandCraft;AnySurfaceCraft")
        for i = 0, list:size() - 1 do
            local r = list:get(i)
            out[string.match(r:getName(), "([^%.]+)$")] = r
        end
        return out
    end
    local function knownSet()
        local all, learned, actual = recipes(), "", ""
        for _, n in ipairs(TLG.Integration.Manual.HANDBOOK_RECIPES) do
            local r = all[n]
            learned = learned .. ((r and CraftRecipeManager.hasPlayerLearnedRecipe(r, player())) and "1" or "0")
            actual = actual .. ((r and player():isRecipeActuallyKnown(r)) and "1" or "0")
        end
        return learned, actual
    end
    local function panel()
        local w = ISEntityUI.GetWindowInstance(0, "HandcraftWindow")
        return w, w and w.handCraftPanel
    end
    -- Opens the crafting window with its button, picks the Ash Barrel's row
    -- as a click does, and reports what the window offers; with `press` it
    -- presses Craft and waits for the action to end.
    -- A product in the inventory or lying within two squares: a heavy one
    -- made by an overloaded character falls to the floor.
    local function have(product)
        local n, p = countType(product), player()
        for x = math.floor(p:getX()) - 2, math.floor(p:getX()) + 2 do
            for y = math.floor(p:getY()) - 2, math.floor(p:getY()) + 2 do
                local sq = getCell():getGridSquare(x, y, 0)
                local objs = sq and sq:getWorldObjects()
                for i = 0, (objs and objs:size() or 0) - 1 do
                    local it = objs:get(i):getItem()
                    if it and it:getFullType() == product then n = n + 1 end
                end
            end
        end
        return n
    end
    local function tryCraft(name, wantOffered, recipeName, product)
        recipeName, product = recipeName or HB.recipe, product or "TLG.AshBarrel"
        return { name = "mp_hb_try_" .. name, timeout = 9000, fn = function(ctx, ticks)
            local p = player()
            if ticks == 1 then
                ctx.base = have(product)
                triggerEvent("OnContainerUpdate")
                local pd = getPlayerData(0)
                local btn = pd and pd.equipped and pd.equipped.craftingBtn
                if btn then btn:forceClick() end
                return nil
            end
            if ticks < 90 then return nil end
            local w, hp = panel()
            if not ctx.picked then
                ctx.picked = true
                if hp and not hp.recipesPanel.recipeListMode then hp.recipesPanel.recipeFilterPanel.viewModeButton:forceClick() end
                local lb = hp and hp.recipesPanel and hp.recipesPanel.recipeListPanel and hp.recipesPanel.recipeListPanel.recipeListPanel
                local recipe = recipes()[recipeName]
                for i, it in ipairs(lb and lb.items or {}) do
                    if it.item ~= nil and it.item == recipe then ctx.row = i end
                end
                if ctx.row then
                    lb.selected = ctx.row
                    lb.onmousedown(lb.target, lb.items[ctx.row].item)
                end
                ctx.at = ticks
                return nil
            end
            if ticks - ctx.at < 90 then return nil end
            local c = hp and hp.recipePanel and hp.recipePanel.craftControl
            if not ctx.judged then
                ctx.judged = true
                local can
                pcall(function() can = hp.logic:canPerformCurrentRecipe() end)
                local inputs = "?"
                pcall(function() inputs = tostring(hp.logic:getRecipeData():areAllInputItemsSatisfied()) end)
                ctx.offered = ctx.row ~= nil and c ~= nil and c.buttonCraft.enable == true
                local learned, actual = knownSet()
                -- What the recipe asks as the game holds it, and the game's
                -- own answer for this character (launches 325-331: the
                -- window offered Welding 4 recipes at Welding 3).
                local asks = "?"
                pcall(function()
                    local r, parts = recipes()[recipeName], {}
                    for i = 0, r:getRequiredSkillCount() - 1 do
                        local s = r:getRequiredSkill(i)
                        parts[#parts + 1] = string.format("%s:%s hasPlayerRequiredSkill=%s level here %s xp %s", tostring(s:getPerk():getId()),
                            tostring(s:getLevel()), tostring(CraftRecipeManager.hasPlayerRequiredSkill(s, p)),
                            tostring(p:getPerkLevel(s:getPerk())), tostring(p:getXp():getXP(s:getPerk())))
                    end
                    asks = table.concat(parts, "; ")
                end)
                ctx.asks = asks
                ctx.text = string.format("window open=%s, row listed=%s, Craft enabled=%s, canPerform=%s, inputs satisfied=%s;"
                    .. " Welding %d; hasPlayerLearnedRecipe %s, actually known %s; debug=%s; dark=%s", tostring(w ~= nil),
                    tostring(ctx.row ~= nil), tostring(c and c.buttonCraft.enable), tostring(can), inputs,
                    p:getPerkLevel(Perks.MetalWelding), learned, actual, tostring(getDebug()), tostring(p:tooDarkToRead()))
                if ctx.offered and wantOffered and c then c.buttonCraft:forceClick() end
                -- Craft pressed where it must not be offered, as a click on a
                -- disabled button: nothing may start. With nothing expected
                -- (nil) it is pressed too.
                if not wantOffered and c then c.buttonCraft:forceClick() end
                ctx.at = ticks
                return nil
            end
            if ticks - ctx.at < 60 then return nil end
            local busy = #(ISTimedActionQueue.getTimedActionQueue(p).queue or {}) > 0
            if busy and ticks - ctx.at < 8000 then return nil end
            local made = have(product) - ctx.base
            if wantOffered == nil then
                -- Nothing expected: what the window did is kept (onebelow).
                HB.seen = HB.seen or {}
                HB.seen[name] = { offered = ctx.offered, made = made }
                report():line("OBS  MP.hb_%s offered=%s made=%d: %s; asks %s", name, tostring(ctx.offered), made, ctx.text,
                    tostring(ctx.asks))
            else
                check("hb_" .. name, function()
                    return ctx.offered == wantOffered and made == (wantOffered and 1 or 0), string.format(
                        "%s; asks %s; %s made %d", ctx.text, tostring(ctx.asks), product, made)
                end)
            end
            if w then w:close() end
            return true
        end }
    end
    local function serverView(name, judge)
        return call("hb_probe_" .. name, "probe_handbook", {}, "probe_handbook", function(m)
            report():line("OBS  MP.hb_%s server: known %s, Welding %s, Ash Barrels %s, handbook read %s", name, tostring(m.known),
                tostring(m.level), tostring(m.barrels), tostring(m.read))
            judge(m)
        end)
    end
    HB.read = { name = "mp_hb_read", timeout = 9000, fn = function(ctx, ticks)
        local p = player()
        if not ctx.started then
            local book = p:getInventory():getFirstTypeRecurse("TLG.BiodieselHandbook")
            if not book and ticks < 600 then return nil end
            ctx.started, ctx.at = true, ticks
            if book then ISInventoryPaneContextMenu.readItem(book, 0) end
            return nil
        end
        if ticks - ctx.at < 60 then return nil end
        local busy = #(ISTimedActionQueue.getTimedActionQueue(p).queue or {}) > 0
        if busy and ticks - ctx.at < 8000 then return nil end
        local learned, actual = knownSet()
        check("hb_handbook_read_teaches_all_five_here", function()
            return actual == "11111", string.format("after %d ticks: hasPlayerLearnedRecipe %s, actually known %s",
                ticks - ctx.at, learned, actual)
        end)
        return true
    end }
    -- onebelow (2026-11-11, one client): is a recipe craftable one level
    -- below its SkillRequired by the game's rule, or only the mod's? A
    -- recipe of the game's own, Make Bone Spoon (Carving 2, nothing to
    -- learn; a file, a hunting knife, a sharp bone fragment), is tried at
    -- Carving 0, 1 and 2, then the Ash Barrel (Welding 2), the handbook
    -- read, at Welding 0, 1 and 2. Two below must be refused and the level
    -- itself must make it; what the window does one below is written down,
    -- and the two recipes must have got the same answer.
    -- onebelow2: the game's own Make Metal Sheet, a recipe of the mod's kind
    -- (MetalWelding 4, must be learned, learned without the book at 6; four
    -- small metal sheets, a blowtorch, a mask), taught on the server and
    -- here with learnRecipe, tried at Welding 2, 3 and 4.
    -- onebelow4: the game's own Make Metal Sheet again, now learned as a
    -- player learns it: its magazine (Base.MetalworkMag4) read with the
    -- inventory menu's Read. Tried at Welding 2, 3 and 4.
    if MP.only == "onebelow4" then
        local function level(name, n)
            return call("hb_level_" .. name, "handbook_level", { level = n, rise = "1" }, "handbook_level", function(m)
                local p, guard = player(), 0
                while p:getPerkLevel(Perks.MetalWelding) < n and guard < 12 do
                    p:LevelPerk(Perks.MetalWelding)
                    guard = guard + 1
                end
                report():line("OBS  MP.hb_level Welding on the server %s, here %d", tostring(m.level), p:getPerkLevel(Perks.MetalWelding))
            end)
        end
        local R4, P4, MAG = "MakeMetalSheet", "Base.SheetMetal", "Base.MetalworkMag4"
        MP.stepsA = { MP.waitWorld,
            call("hb_give", "give", { items = "Base.SmallSheetMetal;Base.SmallSheetMetal;Base.SmallSheetMetal;Base.SmallSheetMetal;"
                .. "Base.SmallSheetMetal;Base.SmallSheetMetal;Base.SmallSheetMetal;Base.SmallSheetMetal;Base.BlowTorch;Base.WeldingMask;"
                .. MAG .. ";Base.HandTorch" }, "given", function(m) report():line("OBS  MP.hb_given %s", tostring(m.ids)) end),
            wait("mp_hb_items_arrive", 240),
            once("mp_hb_light", function()
                local torch = player():getInventory():getFirstTypeRecurse("Base.HandTorch")
                if torch and player():tooDarkToRead() then
                    torch:setActivated(true)
                    player():setSecondaryHandItem(torch)
                end
            end),
            level("welding_2", 2), wait("mp_ob_settle_1", 120),
            tryCraft("metal_sheet_refused_not_learned_at_welding_2", false, R4, P4),
            { name = "mp_ob_read_the_games_magazine", timeout = 9000, fn = function(ctx, ticks)
                local p = player()
                if not ctx.started then
                    local book = p:getInventory():getFirstTypeRecurse(MAG)
                    if not book and ticks < 600 then return nil end
                    ctx.started, ctx.at = true, ticks
                    if book then ISInventoryPaneContextMenu.readItem(book, 0) end
                    return nil
                end
                if ticks - ctx.at < 60 then return nil end
                local busy = #(ISTimedActionQueue.getTimedActionQueue(p).queue or {}) > 0
                if busy and ticks - ctx.at < 8000 then return nil end
                local r = recipes()[R4]
                check("ob_the_games_magazine_read_teaches_its_recipe", function()
                    return r ~= nil and p:isRecipeActuallyKnown(r) == true and p:getAlreadyReadBook():contains(MAG), string.format(
                        "after %d ticks: Make Metal Sheet actually known=%s, the magazine recorded as read=%s", ticks - ctx.at,
                        tostring(r and p:isRecipeActuallyKnown(r)), tostring(p:getAlreadyReadBook():contains(MAG)))
                end)
                return true
            end },
            tryCraft("metal_sheet_refused_at_welding_2", false, R4, P4),
            level("welding_3", 3), wait("mp_ob_settle_2", 120),
            tryCraft("metal_sheet_from_the_magazine_at_welding_3", nil, R4, P4),
            level("welding_4", 4), wait("mp_ob_settle_3", 120),
            tryCraft("metal_sheet_at_welding_4", nil, R4, P4),
            once("mp_ob_verdict", function()
                local s = (HB.seen or {}).metal_sheet_from_the_magazine_at_welding_3 or {}
                local t = (HB.seen or {}).metal_sheet_at_welding_4 or {}
                check("ob_the_games_magazine_recipe_one_level_below", function()
                    return s.offered ~= nil, string.format(
                        "Make Metal Sheet (Welding 4), its magazine read: at Welding 3 offered=%s made=%s; at Welding 4 offered=%s made=%s",
                        tostring(s.offered), tostring(s.made), tostring(t.offered), tostring(t.made))
                end)
            end),
            once("mp_finish_b", function() send("finish", {}) end), MP.finish }
        return
    end
    -- onebelow3: the Ash Barrel taught with learnRecipe, the handbook never
    -- carried or read, at Welding 1 and 2.
    if MP.only == "onebelow3" then
        local function level(name, n)
            return call("hb_level_" .. name, "handbook_level", { level = n, rise = "1" }, "handbook_level", function(m)
                local p, guard = player(), 0
                while p:getPerkLevel(Perks.MetalWelding) < n and guard < 12 do
                    p:LevelPerk(Perks.MetalWelding)
                    guard = guard + 1
                end
                report():line("OBS  MP.hb_level Welding on the server %s, here %d", tostring(m.level), p:getPerkLevel(Perks.MetalWelding))
            end)
        end
        MP.stepsA = { MP.waitWorld,
            call("hb_give", "give", { items = "Base.MetalDrum;Base.MetalDrum;Base.MetalBar;Base.MetalBar;Base.MetalBar;Base.MetalBar;Base.Hammer" },
                "given", function(m) report():line("OBS  MP.hb_given %s", tostring(m.ids)) end),
            wait("mp_hb_items_arrive", 240),
            call("ob_learn", "learn_recipe", { recipe = HB.recipe }, "learn_recipe", function(m)
                player():learnRecipe(HB.recipe)
                local r = recipes()[HB.recipe]
                check("ob_ash_barrel_learned_without_the_handbook", function()
                    return m.known == "true" and r ~= nil and player():isRecipeActuallyKnown(r) == true
                        and not player():getAlreadyReadBook():contains("TLG.BiodieselHandbook"),
                        string.format("server knows it=%s; here actually known=%s; handbook read=%s", tostring(m.known),
                            tostring(r and player():isRecipeActuallyKnown(r)),
                            tostring(player():getAlreadyReadBook():contains("TLG.BiodieselHandbook")))
                end)
            end),
            wait("mp_ob_settle_1", 120),
            tryCraft("ash_barrel_refused_at_welding_0", false),
            level("welding_1", 1), wait("mp_ob_settle_2", 120),
            tryCraft("ash_barrel_taught_at_welding_1", nil),
            level("welding_2", 2), wait("mp_ob_settle_3", 120),
            tryCraft("ash_barrel_made_at_welding_2", true),
            once("mp_ob_verdict", function()
                local s = (HB.seen or {}).ash_barrel_taught_at_welding_1 or {}
                check("ob_the_ash_barrel_taught_one_level_below", function()
                    return s.offered ~= nil, string.format("the Ash Barrel (Welding 2), taught with learnRecipe, at Welding 1: offered=%s made=%s",
                        tostring(s.offered), tostring(s.made))
                end)
            end),
            once("mp_finish_b", function() send("finish", {}) end), MP.finish }
        return
    end
    if MP.only == "onebelow2" then
        local function level(name, n)
            return call("hb_level_" .. name, "handbook_level", { level = n, rise = "1" }, "handbook_level", function(m)
                local p, guard = player(), 0
                while p:getPerkLevel(Perks.MetalWelding) < n and guard < 12 do
                    p:LevelPerk(Perks.MetalWelding)
                    guard = guard + 1
                end
                report():line("OBS  MP.hb_level Welding on the server %s, here %d", tostring(m.level), p:getPerkLevel(Perks.MetalWelding))
            end)
        end
        local R2, P2 = "MakeMetalSheet", "Base.SheetMetal"
        MP.stepsA = { MP.waitWorld,
            call("hb_give", "give", { items = "Base.SmallSheetMetal;Base.SmallSheetMetal;Base.SmallSheetMetal;Base.SmallSheetMetal;"
                .. "Base.SmallSheetMetal;Base.SmallSheetMetal;Base.SmallSheetMetal;Base.SmallSheetMetal;Base.BlowTorch;Base.WeldingMask" },
                "given", function(m) report():line("OBS  MP.hb_given %s", tostring(m.ids)) end),
            wait("mp_hb_items_arrive", 240),
            level("welding_2", 2), wait("mp_ob_settle_1", 120),
            tryCraft("metal_sheet_refused_not_learned_at_welding_2", false, R2, P2),
            call("ob_learn", "learn_recipe", { recipe = R2 }, "learn_recipe", function(m)
                player():learnRecipe(R2)
                local r = recipes()[R2]
                check("ob_the_games_recipe_learned_on_both_sides", function()
                    return m.known == "true" and r ~= nil and player():isRecipeActuallyKnown(r) == true and r:needToBeLearn() == true,
                        string.format("server knows %s=%s; here actually known=%s, must be learned=%s", tostring(m.recipe), tostring(m.known),
                            tostring(r and player():isRecipeActuallyKnown(r)), tostring(r and r:needToBeLearn()))
                end)
            end),
            wait("mp_ob_settle_2", 120),
            tryCraft("metal_sheet_refused_at_welding_2", false, R2, P2),
            level("welding_3", 3), wait("mp_ob_settle_3", 120),
            tryCraft("metal_sheet_at_welding_3", nil, R2, P2),
            level("welding_4", 4), wait("mp_ob_settle_4", 120),
            tryCraft("metal_sheet_made_at_welding_4", true, R2, P2),
            once("mp_ob_verdict", function()
                local s = (HB.seen or {}).metal_sheet_at_welding_3 or {}
                check("ob_the_games_learned_welding_recipe_one_level_below", function()
                    return s.offered ~= nil, string.format("Make Metal Sheet (Welding 4, learned) at Welding 3: offered=%s made=%s",
                        tostring(s.offered), tostring(s.made))
                end)
            end),
            once("mp_finish_b", function() send("finish", {}) end), MP.finish }
        return
    end
    if MP.only == "onebelow" then
        local function level(name, perk, n)
            return call("hb_level_" .. name, "handbook_level", { level = n, rise = "1", perk = perk }, "handbook_level", function(m)
                local p, guard = player(), 0
                while p:getPerkLevel(Perks[perk]) < n and guard < 12 do
                    p:LevelPerk(Perks[perk])
                    guard = guard + 1
                end
                report():line("OBS  MP.hb_level %s on the server %s, here %d", perk, tostring(m.level), p:getPerkLevel(Perks[perk]))
            end)
        end
        MP.stepsA = { MP.waitWorld,
            call("hb_give", "give", { items = "Base.File;Base.HuntingKnife;Base.SharpBoneFragment;Base.SharpBoneFragment;"
                .. "Base.SharpBoneFragment;Base.MetalDrum;Base.MetalDrum;Base.MetalBar;Base.MetalBar;Base.MetalBar;Base.MetalBar;"
                .. "Base.Hammer;TLG.BiodieselHandbook;Base.HandTorch" }, "given",
                function(m) report():line("OBS  MP.hb_given %s", tostring(m.ids)) end),
            wait("mp_hb_items_arrive", 240),
            once("mp_hb_light", function()
                local torch = player():getInventory():getFirstTypeRecurse("Base.HandTorch")
                if torch and player():tooDarkToRead() then
                    torch:setActivated(true)
                    player():setSecondaryHandItem(torch)
                end
                check("ob_starts_at_level_0_without_debug", function()
                    local p = player()
                    return getDebug() == false and p:getPerkLevel(Perks.Carving) == 0 and p:getPerkLevel(Perks.MetalWelding) == 0,
                        string.format("debug=%s Carving %d Welding %d role %s", tostring(getDebug()), p:getPerkLevel(Perks.Carving),
                            p:getPerkLevel(Perks.MetalWelding), tostring(select(2, pcall(function() return p:getRole():getName() end))))
                end)
            end),
            tryCraft("bone_spoon_refused_at_carving_0", false, "MakeBoneSpoon", "Base.Spoon_Bone"),
            level("carving_1", "Carving", 1), wait("mp_ob_settle_1", 120),
            tryCraft("bone_spoon_at_carving_1", nil, "MakeBoneSpoon", "Base.Spoon_Bone"),
            level("carving_2", "Carving", 2), wait("mp_ob_settle_2", 120),
            tryCraft("bone_spoon_made_at_carving_2", true, "MakeBoneSpoon", "Base.Spoon_Bone"),
            HB.read,
            tryCraft("ash_barrel_refused_at_welding_0", false),
            level("welding_1", "MetalWelding", 1), wait("mp_ob_settle_3", 120),
            tryCraft("ash_barrel_at_welding_1", nil),
            level("welding_2", "MetalWelding", 2), wait("mp_ob_settle_4", 120),
            tryCraft("ash_barrel_made_at_welding_2", true),
            once("mp_ob_verdict", function()
                local s = HB.seen or {}
                local spoon, barrel = s.bone_spoon_at_carving_1 or {}, s.ash_barrel_at_welding_1 or {}
                check("ob_one_level_below_the_mods_recipe_gets_the_games_answer", function()
                    return spoon.offered ~= nil and spoon.offered == barrel.offered and (spoon.made == 1) == (barrel.made == 1),
                        string.format("the game's Make Bone Spoon (Carving 2) at Carving 1: offered=%s made=%s; the Ash Barrel (Welding 2) at Welding 1: offered=%s made=%s",
                            tostring(spoon.offered), tostring(spoon.made), tostring(barrel.offered), tostring(barrel.made))
                end)
            end),
            once("mp_finish_b", function() send("finish", {}) end), MP.finish }
        return
    end
    if MP.only == "handbook3" or MP.only == "handbook3u" then
        -- Gained a level at a time with LevelPerk, here and on the server
        -- (MPServer.lua handbook_level says why).
        local function level(name, n)
            return call("hb_level_" .. name, "handbook_level", { level = n, rise = "1" }, "handbook_level", function(m)
                local p, guard = player(), 0
                while p:getPerkLevel(Perks.MetalWelding) < n and guard < 12 do
                    p:LevelPerk(Perks.MetalWelding)
                    guard = guard + 1
                end
                report():line("OBS  MP.hb_level Welding on the server %s (%s XP), here %d (%s XP)", tostring(m.level),
                    tostring(m.xp), p:getPerkLevel(Perks.MetalWelding), tostring(p:getXp():getXP(Perks.MetalWelding)))
            end)
        end
        local M3 = { { "wood_retort", "TLG_MakeWoodRetort", "TLG.WoodRetort" },
            { "wash_tank", "TLG_MakeBiodieselWashTank", "TLG.BiodieselWashTank" },
            { "reactor", "TLG_MakeBiodieselReactor", "TLG.BiodieselReactor" } }
        local function all(suffix, want)
            local out = {}
            for _, m in ipairs(M3) do out[#out + 1] = tryCraft(m[1] .. "_" .. suffix, want, m[2], m[3]) end
            return out
        end
        local steps = { MP.waitWorld,
            once("mp_hb_start", function()
                local learned, actual = knownSet()
                check("hb_nothing_known_at_the_start", function()
                    return actual == "00000" and getDebug() == false, string.format(
                        "debug=%s; hasPlayerLearnedRecipe %s, actually known %s; Welding %d; role %s", tostring(getDebug()), learned,
                        actual, player():getPerkLevel(Perks.MetalWelding),
                        tostring(select(2, pcall(function() return player():getRole():getName() end))))
                end)
            end),
            -- For the three: 3 drums, 5 sheets, 4 pipes, 5 rods, a bucket; a
            -- blowtorch (2 uses each) and a mask.
            call("hb_give", "give", { items = "Base.MetalDrum;Base.MetalDrum;Base.MetalDrum;Base.SheetMetal;Base.SheetMetal;"
                .. "Base.SheetMetal;Base.SheetMetal;Base.SheetMetal;Base.MetalPipe;Base.MetalPipe;Base.MetalPipe;Base.MetalPipe;"
                .. "Base.MetalBar;Base.MetalBar;Base.MetalBar;Base.MetalBar;Base.MetalBar;Base.BucketEmpty;Base.BlowTorch;"
                .. "Base.WeldingMask;TLG.BiodieselHandbook;Base.HandTorch" }, "given",
                function(m) report():line("OBS  MP.hb_given %s", tostring(m.ids)) end),
            wait("mp_hb_items_arrive", 240),
            once("mp_hb_light", function()
                local torch = player():getInventory():getFirstTypeRecurse("Base.HandTorch")
                if torch and player():tooDarkToRead() then
                    torch:setActivated(true)
                    player():setSecondaryHandItem(torch)
                end
            end) }
        -- handbook3u: only the refusals of recipes not learned, at Welding 5.
        -- The level only ever rises in a launch: launch 325 set it to 5 and
        -- then down to 3 (setPerkLevelDebug), and the window then offered
        -- the two Welding 4 recipes at 3.
        if MP.only == "handbook3u" then
            steps[#steps + 1] = level("5_not_learned", 5)
            steps[#steps + 1] = wait("mp_hb_level_settles_1", 120)
            for _, s in ipairs(all("refused_not_learned_at_welding_5", false)) do steps[#steps + 1] = s end
            steps[#steps + 1] = once("mp_finish_b", function() send("finish", {}) end)
            steps[#steps + 1] = MP.finish
            MP.stepsA = steps
            return
        end
        for _, s in ipairs({ level("3", 3), wait("mp_hb_level_settles_2", 120), HB.read,
            serverView("after_reading", function(m)
                check("hb_server_knows_the_five_after_the_read", function()
                    return m.known == "11111" and m.read == "true" and tonumber(m.level) == 3, string.format(
                        "known %s, read %s, Welding %s", tostring(m.known), tostring(m.read), tostring(m.level))
                end)
            end) }) do steps[#steps + 1] = s end
        for _, s in ipairs(all("refused_at_welding_3", false)) do steps[#steps + 1] = s end
        for _, s in ipairs({ level("4", 4), wait("mp_hb_level_settles_3", 120),
            tryCraft("wood_retort_made_at_welding_4", true, M3[1][2], M3[1][3]),
            tryCraft("wash_tank_made_at_welding_4", true, M3[2][2], M3[2][3]),
            tryCraft("reactor_refused_at_welding_4", false, M3[3][2], M3[3][3]),
            level("5", 5), wait("mp_hb_level_settles_4", 120),
            tryCraft("reactor_made_at_welding_5", true, M3[3][2], M3[3][3]),
            once("mp_finish_b", function() send("finish", {}) end), MP.finish }) do steps[#steps + 1] = s end
        MP.stepsA = steps
        return
    end
    MP.stepsA = { MP.waitWorld,
        once("mp_hb_start", function()
            local learned, actual = knownSet()
            check("hb_nothing_known_at_the_start", function()
                -- Launch 311: CraftRecipeManager.hasPlayerLearnedRecipe said
                -- every recipe learned here too, without -debug (the account
                -- is an admin), while the window refused; it is logged only.
                return actual == "00000" and getDebug() == false, string.format(
                    "debug=%s; hasPlayerLearnedRecipe %s, actually known %s; Welding %d", tostring(getDebug()), learned,
                    actual, player():getPerkLevel(Perks.MetalWelding))
            end)
        end),
        call("hb_give", "give", { items = "Base.MetalDrum;Base.MetalBar;Base.MetalBar;Base.Hammer;TLG.BiodieselHandbook;Base.HandTorch" },
            "given", function(m) report():line("OBS  MP.hb_given %s", tostring(m.ids)) end),
        wait("mp_hb_items_arrive", 180),
        once("mp_hb_light", function()
            local torch = player():getInventory():getFirstTypeRecurse("Base.HandTorch")
            if torch and player():tooDarkToRead() then
                torch:setActivated(true)
                player():setSecondaryHandItem(torch)
            end
        end),
        tryCraft("refused_recipe_not_learned", false),
        HB.read,
        serverView("after_reading", function(m)
            check("hb_server_knows_the_five_after_the_read", function()
                return m.known == "11111" and m.read == "true", string.format("known %s, read %s", tostring(m.known), tostring(m.read))
            end)
        end),
        tryCraft("refused_below_welding_2", false),
        call("hb_level", "handbook_level", { level = 2 }, "handbook_level", function(m)
            player():setPerkLevelDebug(Perks.MetalWelding, 2)
            report():line("OBS  MP.hb_level Welding on the server %s, here %d", tostring(m.level),
                player():getPerkLevel(Perks.MetalWelding))
        end),
        wait("mp_hb_level_settles", 120),
        tryCraft("made_with_the_recipe_and_welding_2", true),
        serverView("after_crafting", function(m)
            check("hb_server_holds_the_ash_barrel", function()
                return tonumber(m.barrels) == 1 and tonumber(m.level) == 2, string.format("Ash Barrels %s, Welding %s",
                    tostring(m.barrels), tostring(m.level))
            end)
        end),
        call("hb_roll", "roll_handbook", {}, "roll_handbook", function(m)
            check("hb_handbook_rolled_from_loot_on_the_server", function()
                return (tonumber(m.total) or 0) > 0, string.format("%s handbooks in %s fills: %s", tostring(m.total),
                    tostring(m.fills), tostring(m.lists))
            end)
        end),
        once("mp_finish_b", function() send("finish", {}) end), MP.finish }
    return
end

local V = "TLG.FermenterVessel"
local C = {}
MP.C = C

-- The server's view of vessel `idFn()` (MPServer.lua probe_vessel), logged,
-- then judged.
local function probe(name, idFn, judge)
    return call(name, "probe_vessel", function() return { id = idFn() } end, "probe_vessel", function(m)
        report():line("OBS  MP.%s server: where=%s state=%s pause=%s site=%s listed=%s t=%.4f seen=%.4f done=%.4f"
            .. " now=%.4f inputs=%s takes=%s", name, tostring(m.where), tostring(m.state), tostring(m.pause),
            tostring(m.site), tostring(m.listed), tonumber(m.t) or -1, tonumber(m.seen) or -1, tonumber(m.done) or -1,
            tonumber(m.now) or -1, tostring(m.inputs), tostring(m.takes))
        judge(m)
    end)
end

-- Vessel `id` as this client sees it: in the inventory, or lying within
-- S.R squares of the spawn point.
local function findVessel(id)
    local item = inventoryItem(id)
    for x = S.CX - S.R, S.CX + S.R do
        for y = S.CY - S.R, S.CY + S.R do
            local sq = item == nil and getCell():getGridSquare(x, y, 0)
            local objs = sq and sq:getWorldObjects()
            for i = 0, (objs and objs:size() or 0) - 1 do
                local it = objs:get(i):getItem()
                if it and it:getID() == id then item = it end
            end
        end
    end
    return item
end

-- machine.status for vessel `idFn()` as the mod's menu asks it, from where
-- this client sees the vessel. A record moves on only when it is accessed.
local function status(name, idFn, judge)
    return request(name, "machine.status", function()
        local item = findVessel(idFn())
        return item and { target = TLG.Integration.Machines.refFor(item) }
    end, function(r)
        report():line("OBS  MP.%s reply: %s pause=%s stage=%s rev=%s", name, brief(r), tostring(r.pause),
            tostring(r.stage), tostring(r.rev))
        judge(r)
    end)
end

------------------------------------------------------------------------------
-- machines, A: a running vessel grabbed through the world menu, asked about
-- while carried, dropped through the inventory and asked about again.
------------------------------------------------------------------------------
local function gId() return C.grabId end

C.spawnGrab = call("spawn_grab_vessel", "spawn", function()
    local x, y = S.spot(3)
    return { item = V, x = x, y = y, batch = "1" }
end, "spawned", function(m) C.grabId = tonumber(m.id) end)

C.grabBefore = probe("grab_before", gId, function(m)
    C.takesBefore = m.takes or ""
    local x, y = S.spot(3)
    check("grab_vessel_running_on_the_floor", function()
        return m.where == "floor " .. x .. "," .. y and m.state == "Processing", "see the server's line above"
    end)
end)

-- The world menu's Grab (ISWorldObjectContextMenu.onGrabWItem): on a
-- client it queues an inventory transfer, which the server runs as an item
-- transaction.
C.grab = { name = "mp_grab_vessel", timeout = 2400, fn = function(ctx, ticks)
    local p = player()
    if not ctx.queued then
        local x, y = S.spot(3)
        local item = floorItem(x, y, V)
        local wi = item and item:getWorldItem()
        if not wi then
            report():line("FAIL MP.grab_queued_%s :: no vessel on %d,%d", MP.role, x, y)
            return true
        end
        ISWorldObjectContextMenu.onGrabWItem(nil, wi, 0)
        ctx.queued = ticks
        report():line("OBS  MP.grab queued: %s", h.actionNames(p))
        return nil
    end
    if ticks - ctx.queued < 60 or not TLGH.Steps.actionsIdle(p) then return nil end
    ctx.idle = ctx.idle or ticks
    if ticks - ctx.idle < 120 then return nil end
    check("grab_in_the_inventory", function()
        local item = inventoryItem(C.grabId)
        return item ~= nil and not h.inBothHands(p, V), string.format("in the inventory=%s, in both hands=%s",
            tostring(item ~= nil), tostring(h.inBothHands(p, V)))
    end)
    return true
end }

C.grabbed = probe("grab_after", gId, function(m)
    local since = string.sub(m.takes or "", #(C.takesBefore or "") + 1)
    report():line("OBS  MP.grab the record right after the grab: state=%s pause=%s (a move no Lua sees leaves it as"
        .. " it was until the next access)", tostring(m.state), tostring(m.pause))
    check("grab_on_the_server_no_take", function()
        return m.where == "inventory tlga" and since == "", "where=" .. tostring(m.where) .. " takes since:" .. since
    end)
end)

C.statusCarried = status("grab_status_carried", gId, function(r)
    check("grab_status_carried_paused", function()
        return r.ok == true and r.state == "Paused" and r.pause == "not_placed", "see the reply above"
    end)
end)

C.carried1 = probe("grab_carried_1", gId, function(m) C.done1 = tonumber(m.done) end)
C.statusCarried2 = status("grab_status_carried_again", gId, function() end)
C.carried2 = probe("grab_carried_2", gId, function(m)
    check("grab_nothing_counted_while_carried", function()
        return m.state == "Paused" and tonumber(m.done) == C.done1, string.format("done %.4f then %.4f",
            C.done1 or -1, tonumber(m.done) or -1)
    end)
end)

C.drop = { name = "mp_drop_grabbed_vessel", timeout = 2400, fn = function(ctx, ticks)
    local p = player()
    if not ctx.queued then
        local item = inventoryItem(C.grabId)
        if not item then
            report():line("FAIL MP.grab_dropped_%s :: not in the inventory", MP.role)
            return true
        end
        ISInventoryPaneContextMenu.dropItem(item, 0)
        ctx.queued = ticks
        return nil
    end
    if ticks - ctx.queued < 60 or not TLGH.Steps.actionsIdle(p) then return nil end
    ctx.idle = ctx.idle or ticks
    return ticks - ctx.idle >= 120 or nil
end }

C.dropped = probe("grab_dropped", gId, function(m)
    C.dropSite = string.match(m.where or "", "^floor (.+)$")
    report():line("OBS  MP.grab the record right after the drop: state=%s pause=%s", tostring(m.state), tostring(m.pause))
    check("grab_dropped_on_the_floor", function() return C.dropSite ~= nil, "where=" .. tostring(m.where) end)
end)

C.statusDropped = status("grab_status_dropped", gId, function(r)
    check("grab_status_dropped_processing", function()
        return r.ok == true and r.state == "Processing", "see the reply above"
    end)
end)

C.placed1 = probe("grab_placed_1", gId, function(m)
    C.done3 = tonumber(m.done)
    check("grab_listed_where_it_lies", function()
        return m.state == "Processing" and m.site == C.dropSite and m.listed == C.dropSite, "see the server's line above"
    end)
end)
C.statusPlaced2 = status("grab_status_placed_again", gId, function() end)
C.placed2 = probe("grab_placed_2", gId, function(m)
    check("grab_runs_again_after_the_drop", function()
        return m.state == "Processing" and (tonumber(m.done) or 0) > (C.done3 or 0), string.format("done %.4f then %.4f",
            C.done3 or -1, tonumber(m.done) or -1)
    end)
end)

------------------------------------------------------------------------------
-- machines, A and B: one empty fermenter, both players loading it at once
-- as the mod's menu does (machine.loadFerment with the target alone). Each
-- carries 2 kg of sugar, a yeast and 10 L of water in a bucket.
------------------------------------------------------------------------------
local function fId() return C.loadId end
local LOAD = { items = "Base.Sugar;Base.Sugar;Base.Yeast;Base.BucketEmpty", water = "10" }

local function water()
    local litres, list = 0, player():getInventory():getItemsFromFullType("Base.BucketEmpty")
    for i = 0, (list and list:size() or 0) - 1 do
        local fc = list:get(i):getFluidContainer()
        if fc then litres = litres + fc:getAmount() end
    end
    return litres
end

local function carried() return string.format("sugar=%d yeast=%d water=%.1f", countType("Base.Sugar"),
    countType("Base.Yeast"), water()) end

C.spawnLoad = call("spawn_load_vessel", "spawn", function()
    local x, y = S.spot(-2)
    return { item = V, x = x, y = y }
end, "spawned", function(m) C.loadId = tonumber(m.id) end)

C.give = call("give_feedstock", "give", LOAD, "given", function() end)

C.haveFeed = { name = "mp_have_feedstock", timeout = 900, fn = function(ctx, ticks)
    if ticks < 60 then return nil end
    if countType("Base.Sugar") < 2 and ticks < 600 then return nil end
    C.before = carried()
    report():line("OBS  MP.load %s carries %s", MP.role, C.before)
    return true
end }

-- Sends the load as soon as `go` says so; the reply and the carried items
-- after it are kept for the check.
local function loadNow(first)
    return { name = "mp_load_now", timeout = 3600, fn = function(ctx, ticks)
        if not ctx.sent then
            if first then
                send("load_now", {})
            elseif not nextFrom("load_now") then
                return nil
            end
            local x, y = S.spot(-2)
            local item = floorItem(x, y, V)
            if not item then
                report():line("FAIL MP.load_sent_%s :: no vessel on %d,%d", MP.role, x, y)
                return true
            end
            ctx.sent = ticks
            TLG.Net.request("machine.loadFerment", { target = TLG.Integration.Machines.refFor(item) },
                function(r) ctx.reply = r end)
            report():line("OBS  MP.load %s sent at tick %d", MP.role, ticks)
            return nil
        end
        if not ctx.reply or ticks - ctx.sent < 120 then return nil end
        local r = ctx.reply
        C.reply, C.after = r, carried()
        report():line("OBS  MP.load %s reply: %s sugarKg=%s waterL=%s; carries %s", MP.role, brief(r),
            tostring(r.sugarKg), tostring(r.waterL), C.after)
        check("load_items_follow_the_reply", function()
            local all = C.after == "sugar=0 yeast=0 water=0.0"
            return (r.ok == true and all) or (r.ok ~= true and C.after == C.before),
                string.format("ok=%s; before %s, after %s", tostring(r.ok), tostring(C.before), C.after)
        end)
        send("load_result", { ok = tostring(r.ok), reason = tostring(r.reason) })
        return true
    end }
end

C.loadBoth = waitFrom("mp_wait_load_result", "load_result", function(m)
    local mine = C.reply or {}
    local okA, okB = mine.ok == true, m.ok == "true"
    report():line("OBS  MP.load A ok=%s reason=%s; B ok=%s reason=%s", tostring(okA), tostring(mine.reason),
        tostring(okB), tostring(m.reason))
    check("load_one_of_two_players", function()
        local busy = okA and m.reason or mine.reason
        return okA ~= okB and busy == "machine_busy", string.format("A ok=%s, B ok=%s, the other's reason %s",
            tostring(okA), tostring(okB), tostring(busy))
    end)
end)

------------------------------------------------------------------------------
-- machines, A: a vessel taken out of a crate (the container nearest the
-- spawn point; MPServer.lua crate_vessel) as a double-click in the loot
-- window takes it (equipHeavyItem, which walks to the container). From a
-- container the game's own complete works on a server, and the mod's take
-- leaves it to it (D-030).
------------------------------------------------------------------------------
local function crateId() return C.crateSite and tonumber(C.crateSite.id) end

C.crate = call("crate_vessel", "crate_vessel", {}, "crated", function(m)
    C.crateSite = m
    report():line("OBS  MP.crate vessel %s put in a %s at %s,%s %s", tostring(m.id), tostring(m.type), tostring(m.x),
        tostring(m.y), tostring(m.error or ""))
end)

C.takeFromCrate = { name = "mp_take_from_crate", timeout = 3600, fn = function(ctx, ticks)
    local p = player()
    if not ctx.queued then
        local s = C.crateSite
        local sq = s and s.x and getCell():getGridSquare(tonumber(s.x), tonumber(s.y), 0)
        local objs = sq and sq:getObjects()
        local item
        for i = 0, (objs and objs:size() or 0) - 1 do
            local c = objs:get(i):getContainer()
            item = item or (c and c:getItemWithID(crateId()))
        end
        if not item then
            if ticks < 600 then return nil end
            report():line("FAIL MP.crate_vessel_listed_%s :: this client does not see the vessel in the container", MP.role)
            return true
        end
        ISInventoryPaneContextMenu.equipHeavyItem(p, item)
        ctx.queued = ticks
        report():line("OBS  MP.crate take queued: %s", h.actionNames(p))
        return nil
    end
    if ticks - ctx.queued < 60 or not TLGH.Steps.actionsIdle(p) then return nil end
    ctx.idle = ctx.idle or ticks
    if ticks - ctx.idle < 120 then return nil end
    local held = p:getPrimaryHandItem()
    check("crate_vessel_in_both_hands", function()
        return h.inBothHands(p, V) and held:getID() == crateId(), string.format("primary=%s id=%s",
            tostring(held and held:getFullType()), tostring(held and held:getID()))
    end)
    return true
end }

C.crateSeen = probe("crate_after", crateId, function(m)
    -- Trimmed: the first take of a run has no space before it (run 166).
    local since = string.match(string.sub(m.takes or "", #(C.takesBeforeCrate or "") + 1), "^%s*(.-)%s*$")
    report():line("OBS  MP.crate the server's takes since: %s", since)
    check("crate_vessel_left_to_the_game_on_server", function()
        return m.where == "inventory tlga both hands" and since == "tlga:nil", "where=" .. tostring(m.where)
            .. " takes since: " .. since
    end)
end)

C.loaded = probe("load_server", fId, function(m)
    C.takesBeforeCrate = m.takes or ""
    check("load_server_batch_from_one", function()
        return m.state == "Processing" and m.inputs == "{sugar_eq=2.0000,water=10.0000}", "see the server's line above"
    end)
end)

------------------------------------------------------------------------------
-- fuel, A: the single-player chain's hops at the Gas2Go pumps, each queued
-- through the game's own menu functions (which walk and equip as a click
-- does), with the server's view after each (MPServer.lua setup_fuel,
-- probe_fuel). The mod's pour is queued as its menu queues it, with the
-- harness's own result callback.
------------------------------------------------------------------------------
local FU = { ids = {} }
MP.FU = FU

local function site(k) return FU.site and tonumber(FU.site[k]) end

local function fuelArgs()
    local s = FU.site or {}
    return { px = s.px, py = s.py, car = s.car, g1x = s.g1x, g1y = s.g1y, g2x = s.g2x, g2y = s.g2y,
        ids = table.concat(FU.ids, ";") }
end

local function pumpObj()
    local sq = FU.site and getCell():getGridSquare(site("px"), site("py"), 0)
    local objs = sq and sq:getObjects()
    for i = 0, (objs and objs:size() or 0) - 1 do
        if objs:get(i):getPipedFuelAmount() > 0 then return objs:get(i) end
    end
    return nil
end

local function car() return FU.site and getVehicleById(site("car")) end

local function tank()
    local v = car()
    return v and v:getPartById("GasTank")
end

local function gen(k)
    local sq = FU.site and getCell():getGridSquare(site("g" .. k .. "x"), site("g" .. k .. "y"), 0)
    local objs = sq and sq:getObjects()
    for i = 0, (objs and objs:size() or 0) - 1 do
        if instanceof(objs:get(i), "IsoGenerator") then return objs:get(i) end
    end
    return nil
end

local function canL(key)
    local it = inventoryItem(FU[key])
    local fc = it and it:getFluidContainer()
    return fc and fc:getAmount() or -1
end

local function near(a, b, tol) return a ~= nil and b ~= nil and math.abs(a - b) <= (tol or 1e-3) end

local function probeFuel(name, judge)
    return call(name, "probe_fuel", fuelArgs, "probe_fuel", function(m)
        report():line("OBS  MP.%s server: pump units=%s %s", name, tostring(m.pumpUnits), tostring(m.pumpSide))
        report():line("OBS  MP.%s server: tank %.4f L, record %.4f L, engine running=%s %s", name,
            tonumber(m.tankL) or -1, tonumber(m.tankRecL) or -1, tostring(m.engine), tostring(m.tankSide))
        for _, k in ipairs({ "g1", "g2" }) do
            report():line("OBS  MP.%s server: %s fuel %.4f L, record %.4f L, on=%s %s", name, k,
                tonumber(m[k .. "Fuel"]) or -1, tonumber(m[k .. "RecL"]) or -1, tostring(m[k .. "On"]),
                tostring(m[k .. "Side"]))
        end
        report():line("OBS  MP.%s server: carried generator record %.4f L %s; items %s", name,
            tonumber(m.genItemRecL) or -1, tostring(m.genItemSide), tostring(m.items))
        judge(m)
    end)
end

-- A step that queues `queue(ctx, player)` once and waits until the player's
-- actions are done and `settle` ticks more have passed.
local function act(name, queue, settle)
    return { name = "mp_" .. name, timeout = 7200, fn = function(ctx, ticks)
        local p = player()
        if not ctx.queued then
            local ok, err = pcall(queue, ctx, p)
            if not ok then
                report():line("FAIL MP.%s_queued_%s :: %s", name, MP.role, tostring(err))
                return true
            end
            ctx.queued = ticks
            report():line("OBS  MP.%s queued: %s", name, h.actionNames(p))
            return nil
        end
        if ticks - ctx.queued < 60 or not TLGH.Steps.actionsIdle(p) then return nil end
        ctx.idle = ctx.idle or ticks
        return ticks - ctx.idle >= (settle or 120) or nil
    end }
end

local function giveCan(name, args, key)
    local a = { items = "Base.PetrolCan" }
    for k, v in pairs(args) do a[k] = v end
    return call(name, "give", a, "given", function(m)
        local got = ids(m.ids)["Base.PetrolCan"]
        FU[key] = got and got[1]
        FU.ids[#FU.ids + 1] = tostring(FU[key])
    end)
end

local function arrived(key)
    return { name = "mp_" .. key .. "_arrives", timeout = 900, fn = function(ctx, ticks)
        if inventoryItem(FU[key]) == nil and ticks < 600 then return nil end
        report():line("OBS  MP.%s in the inventory=%s, %.4f L", key, tostring(inventoryItem(FU[key]) ~= nil), canL(key))
        return true
    end }
end

-- This client's line for item `key` as probe_fuel writes it.
local function itemText(key)
    local it = inventoryItem(FU[key])
    local fc = it and it:getFluidContainer()
    return tostring(FU[key]) .. "=" .. (fc and string.format("%.4f", fc:getAmount()) or "nil") .. " " .. S.sidecar(it)
end

FU.setup = call("fuel_site", "setup_fuel", {}, "fuel_site", function(m)
    FU.site = m
    report():line("OBS  MP.fuel site: pump %s,%s (%s units), car %s, generators %s,%s and %s,%s %s", tostring(m.px),
        tostring(m.py), tostring(m.units), tostring(m.car), tostring(m.g1x), tostring(m.g1y), tostring(m.g2x),
        tostring(m.g2y), tostring(m.error or ""))
end)

FU.seen = once("mp_fuel_site_seen", function()
    local t = tank()
    check("fuel_site_seen", function()
        return pumpObj() ~= nil and car() ~= nil and t ~= nil and near(t:getContainerContentAmount(), 0) and gen(1) ~= nil
            and gen(2) ~= nil and near(gen(1):getFuel(), 0) and near(gen(2):getFuel(), 0),
            string.format("pump=%s car=%s tank=%s g1=%s g2=%s", tostring(pumpObj() ~= nil), tostring(car() ~= nil),
                tostring(t and t:getContainerContentAmount()), tostring(gen(1) and gen(1):getFuel()),
                tostring(gen(2) and gen(2):getFuel()))
    end)
end)

FU.pumpToCan = act("pump_to_can", function(ctx, p)
    FU.units0 = pumpObj():getPipedFuelAmount()
    ISWorldObjectContextMenu.onTakeFuelNew(nil, pumpObj(), nil, inventoryItem(FU.can1), 0)
end, 180)

FU.afterPumpToCan = probeFuel("after_pump_to_can", function(m)
    FU.can1L = canL("can1")
    check("pump_to_can", function()
        return FU.can1L > 0 and string.find(m.items or "", itemText("can1"), 1, true) ~= nil and m.pumpSide ~= "nil"
            and tonumber(m.pumpUnits) < (FU.units0 or 0), string.format("can %.4f L; this client %s", FU.can1L,
            itemText("can1"))
    end)
end)

FU.canToCar = act("can_to_car", function(ctx, p) ISVehiclePartMenu.onAddGasoline(p, tank()) end, 180)

FU.afterCanToCar = probeFuel("after_can_to_car", function(m)
    FU.tank1 = tonumber(m.tankL)
    check("can_to_car", function()
        return (FU.can1L or 0) > 0 and near(FU.tank1, FU.can1L, 2e-3) and near(tonumber(m.tankRecL), FU.tank1, 2e-3)
            and near(tank():getContainerContentAmount(), FU.tank1, 2e-3), string.format("can had %.4f L; server tank"
            .. " %.4f L, record %.4f L; this client's tank %.4f L", FU.can1L or -1, FU.tank1 or -1,
            tonumber(m.tankRecL) or -1, tank():getContainerContentAmount())
    end)
end)

-- The two actions ISVehiclePartMenu.onPumpGasoline queues, with the
-- station's pump: its own search looks two squares round the filler, and
-- the car stands where the single-player chain parks it.
FU.pumpToCar = act("pump_to_car", function(ctx, p)
    FU.units1 = pumpObj():getPipedFuelAmount()
    local part = tank()
    ISTimedActionQueue.add(ISPathFindAction:pathToVehicleArea(p, part:getVehicle(), part:getArea()))
    ISTimedActionQueue.add(ISRefuelFromGasPump:new(p, part, pumpObj()))
end, 180)

FU.afterPumpToCar = probeFuel("after_pump_to_car", function(m)
    FU.tank2 = tonumber(m.tankL)
    FU.tank2b = FU.tank2
    check("pump_to_car", function()
        return FU.tank2 > (FU.tank1 or 0) + 1 and near(tonumber(m.tankRecL), FU.tank2, 2e-3)
            and tonumber(m.pumpUnits) < (FU.units1 or 0), string.format("tank %.4f -> %.4f L, record %.4f L",
            FU.tank1 or -1, FU.tank2 or -1, tonumber(m.tankRecL) or -1)
    end)
end)

-- Siphoning (the game's own menu: ISVehiclePartMenu.onTakeGasoline, with a
-- rubber hose, the item tagged base:siphongas) back into the can poured
-- into the car, which the menu prefers while it is still in hand.
FU.giveHose = call("give_hose", "give", { items = "Base.RubberHose" }, "given", function() end)

FU.siphon = act("siphon", function(ctx, p) ISVehiclePartMenu.onTakeGasoline(p, tank()) end, 180)

FU.afterSiphon = probeFuel("after_siphon", function(m)
    local can, rec = canL("can1"), tonumber(m["recL" .. tostring(FU.can1)])
    FU.tank2 = tonumber(m.tankL)
    check("siphon_car_to_can", function()
        return can > 0 and near(FU.tank2 + can, FU.tank2b, 2e-3) and near(tonumber(m.tankRecL), FU.tank2, 2e-3)
            and near(rec, can, 2e-3), string.format("tank %.4f -> %.4f L, record %.4f L; can %.4f L, record %.4f L",
            FU.tank2b or -1, FU.tank2 or -1, tonumber(m.tankRecL) or -1, can, rec or -1)
    end)
end)

FU.canToGen = act("can_to_generator", function(ctx, p)
    ISWorldObjectContextMenu.doAddFuelGenerator(nil, gen(1), nil, inventoryItem(FU.can2), 0)
end, 180)

FU.afterCanToGen = probeFuel("after_can_to_generator", function(m)
    FU.g1a = tonumber(m.g1Fuel)
    check("can_to_generator", function()
        return near(FU.g1a, 5, 2e-3) and near(tonumber(m.g1RecL), FU.g1a, 2e-3) and near(canL("can2"), 0),
            string.format("generator %.4f L, record %.4f L; can %.4f L", FU.g1a or -1, tonumber(m.g1RecL) or -1,
            canL("can2"))
    end)
end)

-- The mod's pour, queued as its menu queues it (FuelContextMenu.queuePour)
-- with the harness's own callback in place of the menu's messages.
local function pour(name, canKey, k, experimental)
    return act(name, function(ctx, p)
        FU[name] = nil
        local g = gen(k)
        ISTimedActionQueue.add(ISTLGPourFuel:new(p, inventoryItem(FU[canKey]),
            TLG.Authority.Resolver.refForObject(g, "generator"), g, experimental, function(r) FU[name] = r end))
    end, 180)
end

local function pourReached(name)
    return once("mp_" .. name .. "_result", function()
        local r = FU[name]
        report():line("OBS  MP.%s result on the player's client: %s", name, r and brief(r) or "none")
        check(name .. "_result_reaches_the_player", function()
            return r ~= nil, r and brief(r) or "the pour's callback never ran on the client"
        end)
    end)
end

FU.afterPourPetrol = probeFuel("after_pour_petrol", function(m)
    FU.g1b = tonumber(m.g1Fuel)
    check("pour_petrol_into_generator", function()
        return near(FU.g1b, (FU.g1a or 0) + 3, 2e-3) and near(tonumber(m.g1RecL), FU.g1b, 2e-3) and near(canL("can3"), 0),
            string.format("generator %.4f -> %.4f L, record %.4f L; can %.4f L", FU.g1a or -1, FU.g1b or -1,
            tonumber(m.g1RecL) or -1, canL("can3"))
    end)
end)

-- Can 4 holds diesel since 0.3.0 (ethanol before: it now runs a stock
-- generator lean, D-037); the step names keep "ethanol".
FU.afterPourEthanol = probeFuel("after_pour_ethanol", function(m)
    check("pour_diesel_refused_nothing_moved", function()
        return near(tonumber(m.g1Fuel), FU.g1b, 1e-6) and near(canL("can4"), 3, 1e-6), string.format(
            "generator %.4f L (was %.4f); can %.4f L", tonumber(m.g1Fuel) or -1, FU.g1b or -1, canL("can4"))
    end)
end)

FU.afterPourConfirmed = probeFuel("after_pour_ethanol_confirmed", function(m)
    check("pour_diesel_confirmed_into_empty_generator", function()
        return near(tonumber(m.g2Fuel), 3, 2e-3) and near(tonumber(m.g2RecL), 3, 2e-3) and near(canL("can4"), 0),
            string.format("generator 2 %.4f L, record %.4f L; can %.4f L", tonumber(m.g2Fuel) or -1,
            tonumber(m.g2RecL) or -1, canL("can4"))
    end)
end)

local function switch(name, k, on)
    return act(name, function(ctx, p) ISWorldObjectContextMenu.onActivateGenerator(nil, on, gen(k), 0) end, 180)
end

FU.afterStarts = probeFuel("after_generator_starts", function(m)
    FU.g1c = tonumber(m.g1Fuel)
    check("generator_on_petrol_starts", function() return m.g1On == "true", "g1 on=" .. tostring(m.g1On) end)
    check("generator_on_diesel_refused", function() return m.g2On == "false", "g2 on=" .. tostring(m.g2On) end)
    -- The refused start damaged it, and the server told this player's client
    -- (D-037, TLG/Notify.lua).
    local note = TLG.Notify and TLG.Notify.last
    check("refused_start_told_to_the_player_by_the_server", function()
        return note ~= nil and note.key == "IGUI_TLG_Note_StartDamage" and note.fuel == "diesel",
            note and tostring(note.text) or "no line reached the client"
    end)
end)

-- The generator's record is reconciled with the game's burn when it is
-- read: the mod's status request reads it as a player looking at it does.
-- The reply gives the record as reconciled then (status writes nothing; the
-- next write keeps it: the take below carries the burned amount).
FU.genStatus = request("generator_status", "status", function()
    local g = gen(1)
    return g and { target = TLG.Authority.Resolver.refForObject(g, "generator") }
end, function(r)
    FU.genTotal = tonumber(r.total)
    report():line("OBS  MP.generator_status reply: %s total=%s", brief(r), tostring(r.total))
end)

FU.afterBurn = probeFuel("after_generator_burn", function(m)
    check("generator_burn_followed", function()
        return tonumber(m.g1Fuel) < (FU.g1c or 0) and near(FU.genTotal, tonumber(m.g1Fuel), 2e-3),
            string.format("fuel %.4f -> %.4f L; the status's record %.4f L", FU.g1c or -1, tonumber(m.g1Fuel) or -1,
            FU.genTotal or -1)
    end)
    FU.g1d = tonumber(m.g1Fuel)
end)

-- Taken as a player takes it: unplugged first (ISTakeGenerator.isValid
-- refuses a connected one; run 156 took nothing).
FU.unplug = act("unplug_generator", function(ctx, p)
    ISWorldObjectContextMenu.onPlugGenerator(nil, gen(1), 0, false)
end, 120)

FU.take = act("take_generator", function(ctx, p) ISWorldObjectContextMenu.onTakeGenerator(nil, gen(1), 0) end, 180)

FU.afterTake = probeFuel("after_take_generator", function(m)
    FU.taken = m.g1Fuel == -1 and m.genItemSide ~= "nil"
    check("generator_record_on_the_item", function()
        return m.g1Fuel == -1 and m.genItemSide ~= "nil" and near(tonumber(m.genItemRecL), FU.g1d, 2e-3),
            string.format("object fuel %s; item record %.4f L (generator had %.4f L)", tostring(m.g1Fuel),
            tonumber(m.genItemRecL) or -1, FU.g1d or -1)
    end)
end)

FU.place = act("place_generator", function(ctx, p)
    local it = p:getInventory():getFirstTypeRecurse("Base.Generator")
    ISTimedActionQueue.add(ISDropWorldItemAction:new(p, it, getCell():getGridSquare(site("g1x"), site("g1y"), 0),
        0.5, 0.5, 0, 0, false))
end, 180)

FU.afterPlace = probeFuel("after_place_generator", function(m)
    check("generator_record_back_on_the_object", function()
        return FU.taken and near(tonumber(m.g1Fuel), FU.g1d, 2e-3) and near(tonumber(m.g1RecL), FU.g1d, 2e-3),
            string.format("object fuel %.4f L, record %.4f L (carried %.4f L)", tonumber(m.g1Fuel) or -1,
            tonumber(m.g1RecL) or -1, FU.g1d or -1)
    end)
end)

FU.enter = act("enter_car", function(ctx, p) ISVehicleMenu.onEnter(p, car(), 0) end, 120)

-- Up to three tries, as the single-player gate step's (a start can fail by
-- chance: the mod's gate weighs the fuel's quality, run 159 failed once).
FU.start = { name = "mp_start_car", timeout = 7200, fn = function(ctx, ticks)
    local p = player()
    if not ctx.t then
        ctx.attempts, ctx.t = 1, ticks
        ISVehicleMenu.onStartEngine(p)
        return nil
    end
    if ticks - ctx.t < 300 or not TLGH.Steps.actionsIdle(p) then return nil end
    local v = car()
    if (v and v:isEngineRunning()) or ctx.attempts >= 3 then
        report():line("OBS  MP.start_car running=%s after %d attempt(s)", tostring(v and v:isEngineRunning()), ctx.attempts)
        return true
    end
    ctx.attempts, ctx.t = ctx.attempts + 1, ticks
    ISVehicleMenu.onStartEngine(p)
    return nil
end }

FU.afterStart = probeFuel("after_car_start", function(m)
    FU.tank3 = tonumber(m.tankL)
    check("car_starts_on_station_fuel", function()
        return m.engine == "true", string.format("engine running=%s; driver=%s", tostring(m.engine),
            tostring(car() and car():isDriver(player())))
    end)
end)

-- As the generator's: the tank's record is reconciled with the game's burn
-- when it is read (Vehicles.read; the per-minute pass only decides stalls).
FU.carStatus = request("car_status", "status", function()
    return FU.site and { target = { kind = "vehicle", id = site("car") } }
end, function(r)
    FU.carTotal = tonumber(r.total)
    report():line("OBS  MP.car_status reply: %s total=%s", brief(r), tostring(r.total))
end)

FU.afterIdle = probeFuel("after_car_idle", function(m)
    check("car_idle_burn_followed", function()
        return tonumber(m.tankL) < (FU.tank3 or 0) and near(FU.carTotal, tonumber(m.tankL), 2e-3),
            string.format("tank %.4f -> %.4f L; the status's record %.4f L", FU.tank3 or -1, tonumber(m.tankL) or -1,
            FU.carTotal or -1)
    end)
end)

------------------------------------------------------------------------------
-- conversion, A: a generator converted at the workshop as its menu does it
-- (WorkshopMenu: conversion.begin, conversion.deliver, then Menu.work's
-- ISTLGConversionWork, which reports as world time passes), on the shortest
-- day (the launcher's DayLength 1); then ethanol poured into it without a
-- confirmation, and the generator started on it.
------------------------------------------------------------------------------
local CV = {}
MP.CV = CV

local function cvGen()
    local sq = CV.site and getCell():getGridSquare(tonumber(CV.site.x), tonumber(CV.site.y), 0)
    local objs = sq and sq:getObjects()
    for i = 0, (objs and objs:size() or 0) - 1 do
        if instanceof(objs:get(i), "IsoGenerator") then return objs:get(i) end
    end
    return nil
end

local function cvRef()
    local g = cvGen()
    return g and TLG.Authority.Resolver.refForObject(g, "generator")
end

CV.setup = call("conversion_site", "setup_conversion", {}, "conversion_site", function(m)
    CV.site = m
    report():line("OBS  MP.conversion generator at %s,%s; the server's player: Mechanics %s, Electricity %s",
        tostring(m.x), tostring(m.y), tostring(m.mechanics), tostring(m.electricity))
end)

-- The same skills and recipe on this client, as the single-player loop sets
-- them.
CV.train = once("mp_train", function()
    local p = player()
    p:setPerkLevelDebug(Perks.Mechanics, 4)
    p:setPerkLevelDebug(Perks.Electricity, 2)
    p:getKnownRecipes():add("Generator")
end)

local function convRequest(name, command, extra, judge)
    return request(name, command, function()
        local ref = cvRef()
        if not ref then return nil end
        local a = { device = ref }
        for k, v in pairs(extra or {}) do a[k] = v end
        return a
    end, function(r)
        report():line("OBS  MP.%s reply: %s stage=%s missing=%s consumed=%s done=%s/%s", name, brief(r), tostring(r.stage),
            S.text(r.missing), S.text(r.consumed), tostring(r.doneHours), tostring(r.totalHours))
        judge(r)
    end)
end

CV.begin = convRequest("conversion_begin", "conversion.begin", { conversion = "flex_generator" }, function(r)
    check("conversion_begun", function() return r.ok == true and r.state == "InProgress", brief(r) end)
end)

CV.deliver = convRequest("conversion_deliver", "conversion.deliver", nil, function(r)
    check("conversion_parts_handed_over", function() return r.ok == true, brief(r) end)
end)

-- "Work on it" (WorkshopMenu.work), until the action ends by itself.
CV.work = { name = "mp_conversion_work", timeout = 60000, fn = function(ctx, ticks)
    local p = player()
    if not ctx.queued then
        local g = cvGen()
        if not g then
            report():line("FAIL MP.conversion_work_%s :: no generator", MP.role)
            return true
        end
        TLG.UI.WorkshopMenu.work(p, cvRef(), g)
        ctx.queued = ticks
        report():line("OBS  MP.conversion work queued: %s", h.actionNames(p))
        return nil
    end
    if ticks - ctx.queued < 120 or not TLGH.Steps.actionsIdle(p) then return nil end
    report():line("OBS  MP.conversion work ended after %d ticks, %d replies, the last: %s", ticks - ctx.queued,
        CV.replies or 0, CV.last and brief(CV.last) or "none")
    return true
end }

CV.status = convRequest("conversion_status", "conversion.status", nil, function(r)
    check("conversion_commissioned", function() return r.ok == true and r.state == "Commissioned", brief(r) end)
end)

local function probeGen(name, judge)
    return call(name, "probe_generator", function() return { x = CV.site and CV.site.x, y = CV.site and CV.site.y } end,
        "probe_generator", function(m)
            report():line("OBS  MP.%s server: profile=%s fuel=%.4f on=%s %s", name, tostring(m.profile),
                tonumber(m.fuel) or -1, tostring(m.on), tostring(m.side))
            judge(m)
        end)
end

CV.profile = probeGen("converted_generator", function(m)
    check("generator_converted_to_flex", function() return m.profile == "generator_si_flex", "profile=" .. tostring(m.profile) end)
end)

CV.pour = act("pour_ethanol_into_flex", function(ctx, p)
    local g = cvGen()
    ISTimedActionQueue.add(ISTLGPourFuel:new(p, inventoryItem(FU.cvCan), TLG.Authority.Resolver.refForObject(g, "generator"),
        g, false, function(r) CV.pourReply = r end))
end, 180)

CV.afterPour = probeGen("flex_after_pour", function(m)
    report():line("OBS  MP.pour_ethanol_into_flex result on the player's client: %s",
        CV.pourReply and brief(CV.pourReply) or "none")
    check("flex_generator_takes_ethanol_unconfirmed", function()
        return near(tonumber(m.fuel), 3, 2e-3) and near(canL("cvCan"), 0), string.format("generator %.4f L; can %.4f L",
            tonumber(m.fuel) or -1, canL("cvCan"))
    end)
end)

CV.start = act("start_flex_generator", function(ctx, p)
    ISWorldObjectContextMenu.onActivateGenerator(nil, true, cvGen(), 0)
end, 180)

CV.afterStart = probeGen("flex_after_start", function(m)
    check("flex_generator_starts_on_ethanol", function() return m.on == "true", "on=" .. tostring(m.on) end)
end)

------------------------------------------------------------------------------
-- carconv, A: a Base.CarNormal converted to flex fuel as the workshop menu
-- does it (begin, hand over parts, Menu.work, which paths to the engine
-- area first), on the shortest day; then ethanol poured into it without a
-- confirmation, and the car started on it with its key.
------------------------------------------------------------------------------
local CC = {}
MP.CC = CC

local function ccCar() return CC.site and getVehicleById(tonumber(CC.site.car)) end
local function ccRef() return CC.site and { kind = "vehicle", id = tonumber(CC.site.car) } end

CC.setup = call("carconv_site", "setup_carconv", {}, "carconv_site", function(m)
    CC.site = m
    report():line("OBS  MP.carconv car %s; the server's player: Mechanics %s", tostring(m.car), tostring(m.mechanics))
end)

CC.train = once("mp_train_mechanics", function()
    player():setPerkLevelDebug(Perks.Mechanics, 4)
    player():getKnownRecipes():add("Basic Mechanics")
end)

local function ccRequest(name, command, extra, judge)
    return request(name, command, function()
        local a = { device = ccRef() }
        for k, v in pairs(extra or {}) do a[k] = v end
        return a.device and a
    end, function(r)
        report():line("OBS  MP.%s reply: %s stage=%s missing=%s consumed=%s done=%s/%s", name, brief(r), tostring(r.stage),
            S.text(r.missing), S.text(r.consumed), tostring(r.doneHours), tostring(r.totalHours))
        judge(r)
    end)
end

CC.begin = ccRequest("carconv_begin", "conversion.begin", { conversion = "flex_car_normal" }, function(r)
    check("carconv_begun", function() return r.ok == true and r.state == "InProgress", brief(r) end)
end)

CC.deliver = ccRequest("carconv_deliver", "conversion.deliver", nil, function(r)
    check("carconv_parts_handed_over", function() return r.ok == true, brief(r) end)
end)

CC.work = { name = "mp_carconv_work", timeout = 72000, fn = function(ctx, ticks)
    local p = player()
    if not ctx.queued then
        if not ccCar() then
            report():line("FAIL MP.carconv_work_%s :: no car", MP.role)
            return true
        end
        TLG.UI.WorkshopMenu.work(p, ccRef(), ccCar())
        ctx.queued = ticks
        report():line("OBS  MP.carconv work queued: %s", h.actionNames(p))
        return nil
    end
    if ticks - ctx.queued < 120 or not TLGH.Steps.actionsIdle(p) then return nil end
    report():line("OBS  MP.carconv work ended after %d ticks, %d replies, the last: %s", ticks - ctx.queued,
        CV.replies or 0, CV.last and brief(CV.last) or "none")
    return true
end }

CC.status = ccRequest("carconv_status", "conversion.status", nil, function(r)
    check("carconv_commissioned", function() return r.ok == true and r.state == "Commissioned", brief(r) end)
end)

local function probeCar(name, judge)
    return call(name, "probe_vehicle", function() return { car = CC.site and CC.site.car } end, "probe_vehicle",
        function(m)
            report():line("OBS  MP.%s server: profile=%s tank %.4f L, record %.4f L, engine running=%s %s", name,
                tostring(m.profile), tonumber(m.tankL) or -1, tonumber(m.recL) or -1, tostring(m.engine), tostring(m.side))
            judge(m)
        end)
end

CC.profile = probeCar("converted_car", function(m)
    check("car_converted_to_flex", function() return m.profile == "engine_si_flex", "profile=" .. tostring(m.profile) end)
end)

-- From the filler, where the mod's menu offers the pour (FuelContextMenu:
-- the player in the tank's area) and the server takes it (run 168 poured
-- from the engine, where the work had left A: not_at_fuel_cap).
CC.pour = act("pour_ethanol_into_flex_car", function(ctx, p)
    local car = ccCar()
    ISTimedActionQueue.add(ISPathFindAction:pathToVehicleArea(p, car, car:getPartById("GasTank"):getArea()))
    ISTimedActionQueue.add(ISTLGPourFuel:new(p, inventoryItem(FU.ccCan), ccRef(), car, false,
        function(r) CC.pourReply = r end))
end, 180)

CC.afterPour = probeCar("flex_car_after_pour", function(m)
    report():line("OBS  MP.pour_ethanol_into_flex_car result on the player's client: %s",
        CC.pourReply and brief(CC.pourReply) or "none")
    check("flex_car_takes_ethanol_unconfirmed", function()
        return CC.pourReply ~= nil and CC.pourReply.ok == true and near(tonumber(m.tankL), 3, 2e-3)
            and near(tonumber(m.recL), 3, 2e-3), string.format("tank %.4f L, record %.4f L; result %s",
            tonumber(m.tankL) or -1, tonumber(m.recL) or -1, CC.pourReply and brief(CC.pourReply) or "none")
    end)
end)

-- Started as FU.start does it, up to three tries.
local function startCar(name, getCar)
    return { name = "mp_" .. name, timeout = 7200, fn = function(ctx, ticks)
        local p = player()
        if not ctx.t then
            ctx.attempts, ctx.t = 1, ticks
            ISVehicleMenu.onStartEngine(p)
            return nil
        end
        if ticks - ctx.t < 300 or not TLGH.Steps.actionsIdle(p) then return nil end
        local v = getCar()
        if (v and v:isEngineRunning()) or ctx.attempts >= 3 then
            report():line("OBS  MP.%s running=%s after %d attempt(s)", name, tostring(v and v:isEngineRunning()),
                ctx.attempts)
            return true
        end
        ctx.attempts, ctx.t = ctx.attempts + 1, ticks
        ISVehicleMenu.onStartEngine(p)
        return nil
    end }
end

CC.enter = act("enter_flex_car", function(ctx, p) ISVehicleMenu.onEnter(p, ccCar(), 0) end, 120)
CC.start = startCar("start_flex_car", ccCar)

CC.afterStart = probeCar("flex_car_after_start", function(m)
    check("flex_car_starts_on_ethanol", function() return m.engine == "true", "engine running=" .. tostring(m.engine) end)
end)

------------------------------------------------------------------------------
-- stills, A: both stills and the drying column, run through the mod's
-- machine requests as their menu sends them, around a fermenter the server
-- made done (MPServer.lua setup_production), on the shortest day: firewood
-- and the wash into each still, distilled, collected into a can each, the
-- reflux still's run dried with quicklime and collected again.
------------------------------------------------------------------------------
local PR = {}
MP.PR = PR

local function machineRef(key)
    local it = PR.site and findVessel(tonumber(PR.site[key]))
    return it and TLG.Integration.Machines.refFor(it)
end

-- The player's empty jerry cans by id, the first for the pot still's run,
-- the second for the reflux still's, the third for the dried ethanol.
local function jerry(n)
    local list = player():getInventory():getItemsFromFullType("Base.JerryCan")
    local cans = {}
    for i = 0, (list and list:size() or 0) - 1 do cans[#cans + 1] = list:get(i) end
    table.sort(cans, function(a, b) return a:getID() < b:getID() end)
    return cans[n]
end

local function mreq(name, command, key, extra, judge)
    return request(name, command, function()
        local ref = machineRef(key)
        if not ref then return nil end
        local a = { target = ref }
        for k, v in pairs(type(extra) == "function" and extra() or extra or {}) do a[k] = v end
        return a
    end, function(r)
        report():line("OBS  MP.%s reply: %s pause=%s stage=%s outputs=%s firebox=%s washL=%s", name, brief(r),
            tostring(r.pause), tostring(r.stage), S.text(r.outputs), tostring(r.firebox), tostring(r.washL))
        judge(r)
    end)
end

PR.setup = call("production_site", "setup_production", {}, "production_site", function(m)
    PR.site = m
    report():line("OBS  MP.production fermenter %s (%s after %s h, outputs %s), pot still %s, reflux still %s,"
        .. " drying column %s", tostring(m.fermenter), tostring(m.state), tostring(m.hours), tostring(m.outputs),
        tostring(m.pot), tostring(m.reflux), tostring(m.dryer))
end)

PR.fermenter = mreq("fermenter_status", "machine.status", "fermenter", nil, function(r)
    check("fermenter_done", function() return r.ok == true and r.state == "OutputReady", brief(r) end)
end)

local function logs(name) return call(name, "give", { items = "Base.Log;Base.Log" }, "given", function() end) end

local function fed(name, key)
    return mreq(name, "machine.addFuel", key, nil, function(r)
        check(name, function() return r.ok == true and (tonumber(r.firebox) or 0) > 0, brief(r) end)
    end)
end

local function washed(name, key)
    return mreq(name, "machine.loadWash", key, nil, function(r)
        check(name, function() return r.ok == true and r.state == "Processing" and (tonumber(r.washL) or 0) > 0,
            brief(r) .. " washL=" .. tostring(r.washL) end)
    end)
end

-- Asks each machine's status every 5 s (an access is what moves a record
-- on) until all are OutputReady. A still that stops for heat (its firebox
-- burned out, pause no_heat) is fed again as a player tends it: two more
-- logs, then its firewood (run 170: 60 L of wash in the pot still need 51
-- kWh; two logs give it 34, and it waited).
local function ready(name, keys)
    return { name = "mp_" .. name, timeout = 72000, fn = function(ctx, ticks)
        if ctx.pending then return nil end
        ctx.answers = ctx.answers or {}
        if ctx.feed then
            if ticks < ctx.feed.at then return nil end
            ctx.pending = 1
            local k = ctx.feed.key
            TLG.Net.request("machine.addFuel", { target = machineRef(k) }, function(r)
                report():line("OBS  MP.%s %s fed again: %s firebox=%s", name, k, brief(r), tostring(r.firebox))
                ctx.feed, ctx.pending, ctx.answers = nil, nil, {}
            end)
            return nil
        end
        local all = true
        for _, k in ipairs(keys) do
            if ctx.answers[k] ~= "OutputReady" then all = false end
            if ctx.answers[k] == "no_heat" then
                send("give", { items = "Base.Log;Base.Log", tag = "refeed_" .. k })
                report():line("OBS  MP.%s %s stopped for heat after %d ticks: two more logs", name, k, ticks)
                ctx.feed = { key = k, at = ticks + 120 }
                return nil
            end
        end
        if all then
            report():line("OBS  MP.%s all done after %d ticks", name, ticks)
            return true
        end
        if ctx.next and ticks < ctx.next then return nil end
        ctx.pending, ctx.next = #keys, ticks + 300
        for _, k in ipairs(keys) do
            TLG.Net.request("machine.status", { target = machineRef(k) }, function(r)
                ctx.answers[k] = r.pause == "no_heat" and "no_heat" or r.state
                ctx.pending = ctx.pending - 1
                if ctx.pending <= 0 then ctx.pending = nil end
            end)
        end
        return nil
    end }
end

local function collected(name, key, n)
    return mreq(name, "machine.collect", key, function()
        local can = jerry(n)
        return { destination = { kind = "item", id = can and can:getID() } }
    end, function(r)
        check(name, function() return r.ok == true, brief(r) end)
    end)
end

-- What this client holds of a can's fuel: its litres and its TLG record's
-- ethanol and water (the server writes it and sends it with the item).
local function canFuel(n)
    local can = jerry(n)
    local q = can and can:getModData().tlg and can:getModData().tlg.q or {}
    return can and can:getFluidContainer():getAmount() or -1, q.ethanol or 0, q.water or 0
end

-- The reflux still's run to the single-player loop's purity (under 7 %
-- water, LOOP.distill_completed); the pot still makes weaker spirit.
PR.cans = once("mp_stills_cans", function()
    for n, still in ipairs({ "pot", "reflux" }) do
        local litres, eth, water = canFuel(n)
        report():line("OBS  MP.%s still's run in can %s: %.4f L, ethanol %.4f, water %.4f", still,
            tostring(jerry(n) and jerry(n):getID()), litres, eth, water)
        check(still .. "_still_run_bottled", function()
            local pure = still == "pot" or water / math.max(1e-9, eth + water) < 0.07
            return eth > 0.5 and pure and near(eth + water, litres, 2e-3),
                string.format("%.4f L: ethanol %.4f, water %.4f", litres, eth, water)
        end)
    end
end)

PR.dry = mreq("dry_load", "machine.loadDry", "dryer", function()
    local can = jerry(2)
    return { source = { kind = "item", id = can and can:getID() } }
end, function(r)
    check("dry_loaded", function() return r.ok == true and r.state == "Processing", brief(r) end)
end)

PR.dried = once("mp_dried_can", function()
    local litres, eth, water = canFuel(3)
    report():line("OBS  MP.dried ethanol in can %s: %.4f L, ethanol %.4f, water %.4f",
        tostring(jerry(3) and jerry(3):getID()), litres, eth, water)
    check("dried_ethanol_bottled", function()
        return eth > 0.5 and water <= eth * 0.005 + 1e-4 and near(eth + water, litres, 2e-3),
            string.format("%.4f L: ethanol %.4f, water %.4f", litres, eth, water)
    end)
end)

-- Each reply the work action gets from the server, logged (the first few
-- and any that is not plain progress).
if (MP.only == "conversion" or MP.only == "carconv") and ISTLGConversionWork then
    local onReply = ISTLGConversionWork.onReply
    ISTLGConversionWork.onReply = function(self, r)
        CV.replies, CV.last = (CV.replies or 0) + 1, r
        if CV.replies <= 3 or r.state ~= "InProgress" or not r.ok then
            report():line("OBS  MP.work reply %d: %s stage=%s done=%s/%s credited=%s", CV.replies, brief(r),
                tostring(r.stage), tostring(r.doneHours), tostring(r.totalHours), tostring(r.credited))
        end
        return onReply(self, r)
    end
end

local function standNear(name, dx, dy)
    return walkTo(name, function()
        local x, y = S.spot(-2)
        return x + dx, y + dy
    end)
end

------------------------------------------------------------------------------
-- effects (D-031 with a server applying it), A drives and B watches, on the
-- shortest day. The server holds the fixtures and watches the engine every
-- game minute (MPServer.lua, the effects case). A pours 10 L of petrol into
-- the car from a can, the server ages the tank's record to 2.6 (power factor
-- 0.851, wear factor 1.743) and scales the car wear rate by 1000: idling
-- burns about 0.0005 L a game minute (RT-MP run 160), so at the
-- single-player mode's 100 no whole point would come off. Stalls are off for
-- that leg. A starts the engine and idles; the server must lower the power
-- within two minute passes of seeing it run and hold it, keep quality and
-- loudness, charge the wear of the litres counted and give the power back
-- within two minute passes of the stop. Then a blend no stock engine takes
-- (written over the record, petrol and ethanol 5 to 3): with stalls on, the
-- start is refused; with stalls off, it runs at half power (the floor);
-- stalls on again, it stalls within two minute passes. Last, a generator:
-- 8 L poured in from a can, its record aged to 3.0, switched on by the server
-- for 6 game hours, then a 2 L refuel, whose ISAddFuel.new on the server
-- charges the wear at 100 times the rate, once.
-- Both clients follow the car every tick and log each change. At each mark A
-- takes the server's engine and compares its own; B is sent the server's
-- values and compares its own. A client applies a received engine through
-- setEngineFeature, which stores the loudness times 0.37037036 (BC
-- VehicleEngine.parse), so a client's loudness is not the server's: it is
-- watched for any change after the client first saw the engine run.
------------------------------------------------------------------------------
local EF = { scale = 1000, genScale = 100, staleDeg = 2.6, genDeg = 3.0, genHours = 6, W = {} }
MP.EF = EF

local function efCar() return EF.carId and getVehicleById(EF.carId) or nil end

local function efEngine(v)
    local e = v and v:getPartById("Engine")
    return e and e:getCondition() or -1
end

local function efWatch()
    local ok, err = pcall(function()
        local v = efCar()
        if v == nil then return end
        local W = EF.W
        local p, q, l, run, c = v:getEnginePower(), v:getEngineQuality(), v:getEngineLoudness(), v:isEngineRunning(),
            efEngine(v)
        EF.ticks = (EF.ticks or 0) + 1
        if W.p ~= p or W.q ~= q or W.l ~= l or W.run ~= run or W.c ~= c then
            report():line("OBS  MP.effects tick %d on %s's client: power %d quality %d loudness %d running %s engine %d",
                EF.ticks, MP.role, p, q, l, tostring(run), c)
            W.p, W.q, W.l, W.run, W.c = p, q, l, run, c
        end
        if W.lFirst == nil then W.lFirst = l end
        if run and W.lBase == nil then W.lBase = l end
        if W.lBase ~= nil and l ~= W.lBase and W.lChanged == nil then
            W.lChanged = string.format("%d at tick %d (was %d)", l, EF.ticks, W.lBase)
        end
    end)
    if not ok and not EF.watchFailed then
        EF.watchFailed = true
        report():line("STEPERR MP.effects_watch_%s :: %s", MP.role, tostring(err))
    end
end

-- This client's view of the engine against the server's values `m`.
local function efSeen(name, m, cond)
    local v = efCar()
    local p, q, l = v and v:getEnginePower(), v and v:getEngineQuality(), v and v:getEngineLoudness()
    local run, c = v and tostring(v:isEngineRunning()), efEngine(v)
    EF.serverL = tonumber(m.loudness)
    report():line("OBS  MP.effects %s on %s's client: power %s quality %s loudness %s running %s engine %s; the server's"
        .. " power %s quality %s loudness %s running %s engine %s", name, MP.role, tostring(p), tostring(q), tostring(l),
        tostring(run), tostring(c), tostring(m.power), tostring(m.quality), tostring(m.loudness), tostring(m.running),
        tostring(m.cond))
    check("effects_" .. name .. "_engine_seen", function()
        return v ~= nil and p == tonumber(m.power) and q == tonumber(m.quality) and run == tostring(m.running),
            string.format("power %s (server %s) quality %s (server %s) running %s (server %s)", tostring(p),
                tostring(m.power), tostring(q), tostring(m.quality), tostring(run), tostring(m.running))
    end)
    if cond then
        check("effects_" .. name .. "_engine_condition_seen", function()
            return c == tonumber(m.cond), string.format("%s (server %s)", tostring(c), tostring(m.cond))
        end)
    end
end

-- After the last mark, on each client: the loudness since the client first
-- saw the engine run.
local function efLoudness()
    local W = EF.W
    local scaled = EF.serverL and math.floor(EF.serverL * 0.37037036)
    report():line("OBS  MP.effects loudness on %s's client: %s before the engine first ran, %s at its first running tick,"
        .. " changed since: %s; the server's %s (x0.37037036 = %s)", MP.role, tostring(W.lFirst), tostring(W.lBase),
        tostring(W.lChanged or "no"), tostring(EF.serverL), tostring(scaled))
    check("effects_loudness_kept_after_the_engine_first_ran", function()
        return W.lBase ~= nil and W.lChanged == nil, W.lChanged or ("held at " .. tostring(W.lBase))
    end)
end

local function efNum(m, k) return tonumber(m[k]) or -1 end

-- A takes the server's engine (MPServer effects_probe), judges it, compares
-- its own view, and sends the server's values to B, which compares its own.
local function efMark(name, judge, cond)
    return call("effects_" .. name, "effects_probe", {}, "effects_probe", function(m)
        report():line("OBS  MP.effects %s server: running %s %s power %s (own %s, factor %.6f, target %s, reached after"
            .. " %s minute pass(es)%s; ran %s, stopped %s pass(es) after the last option change, own power back after"
            .. " %s) quality %s loudness %s engine %s carry %.6f; minute %s, runs %s; wear counted %s minute(s) %.6f L"
            .. " %.6f points from engine %s carry %.6f; %s; the mod's pass %s call(s) %s ms, max %s ms",
            name, tostring(m.running), tostring(m.state), tostring(m.power), tostring(m.base), efNum(m, "factor"),
            tostring(m.target), tostring(m.reachedAt), m.strayed ~= "" and (", strayed " .. tostring(m.strayed)) or "",
            tostring(m.ranFor), tostring(m.stoppedAfter), tostring(m.backAt), tostring(m.quality), tostring(m.loudness),
            tostring(m.cond), efNum(m, "carry"), tostring(m.minute), tostring(m.runs), tostring(m.calls),
            efNum(m, "litres"), efNum(m, "accrual"), tostring(m.cond0), efNum(m, "carry0"),
            m.featuresChanged ~= "" and ("features changed: " .. tostring(m.featuresChanged)) or "quality and loudness as armed",
            tostring(m.costN), tostring(m.costMs), tostring(m.costMax))
        judge(m)
        efSeen(name, m, cond)
        send("ef_mark", { name = name, power = m.power, quality = m.quality, loudness = m.loudness, cond = m.cond,
            running = m.running, condCheck = cond and "1" or "0" })
        EF.lastRuns = tonumber(m.runs)
    end)
end

local function efSeenByB(name) return waitFrom("mp_effects_seen_" .. name, "ef_seen") end

EF.setup = call("effects_site", "setup_effects", {}, "effects_site", function(m)
    EF.site, EF.carId = m, tonumber(m.car)
    FU.site = { car = m.car, g1x = m.g1x, g1y = m.g1y }
    report():line("OBS  MP.effects site: car %s, generator %s,%s (condition %s, one in %s); engine power %s quality %s"
        .. " loudness %s condition %s", tostring(m.car), tostring(m.g1x), tostring(m.g1y), tostring(m.genCond),
        tostring(m.oneIn), tostring(m.power), tostring(m.quality), tostring(m.loudness), tostring(m.cond))
    send("ef_site", { car = m.car })
end)

EF.seeCar = { name = "mp_effects_see_car", timeout = 1800, fn = function(ctx, ticks)
    local v = efCar()
    if v == nil then return nil end
    if not EF.watching then
        Events.OnTick.Add(efWatch)
        EF.watching = true
    end
    report():line("OBS  MP.effects car %s on %s's client: power %d quality %d loudness %d engine %d", tostring(EF.carId),
        MP.role, v:getEnginePower(), v:getEngineQuality(), v:getEngineLoudness(), efEngine(v))
    return true
end }

EF.age = call("effects_age", "effects_age", { deg = tostring(EF.staleDeg) }, "effects_age", function(m)
    report():line("OBS  MP.effects stale tank %.4f L %s; compatible=%s grade=%s powerFactor=%.6f wearFactor=%.6f",
        efNum(m, "tankL"), tostring(m.tank), tostring(m.compatible), tostring(m.grade), efNum(m, "powerFactor"),
        efNum(m, "wearFactor"))
    check("effects_stale_fuel_costs_power_and_wear", function()
        return m.compatible == "true" and efNum(m, "powerFactor") < 1 and efNum(m, "wearFactor") > 1
            and efNum(m, "tankL") > 9.9, string.format("%.4f L, compatible=%s power %.6f wear %.6f", efNum(m, "tankL"),
            tostring(m.compatible), efNum(m, "powerFactor"), efNum(m, "wearFactor"))
    end)
end)

local function efArm(name, stalls, scale)
    return call("effects_arm_" .. name, "effects_arm", { stalls = stalls, scale = tostring(scale) }, "effects_arm",
        function(m)
            report():line("OBS  MP.effects armed %s: stalls %s, car wear %.4f a litre at factor 2 (x%d fixture); engine %s"
                .. " quality %s loudness %s power %s running %s", name, stalls, efNum(m, "rate"), scale,
                tostring(m.cond), tostring(m.quality), tostring(m.loudness), tostring(m.power), tostring(m.running))
        end)
end

local function efStalls(name, on)
    return call("effects_stalls_" .. name, "effects_stalls", { on = on }, "effects_stalls", function(m)
        report():line("OBS  MP.effects stalls %s on the server at minute %s", tostring(m.on), tostring(m.minute))
    end)
end

EF.staleRunning = efMark("stale_running", function(m)
    check("effects_stale_power_lowered_on_the_server", function()
        local r = efNum(m, "reachedAt")
        return m.running == "true" and efNum(m, "factor") < 1 and efNum(m, "target") < efNum(m, "base")
            and efNum(m, "power") == efNum(m, "target") and r >= 0 and r <= 2 and m.strayed == "",
            string.format("%s -> %s (factor %.6f) after %s minute pass(es)%s, now %s", tostring(m.base),
                tostring(m.target), efNum(m, "factor"), tostring(m.reachedAt),
                m.strayed ~= "" and (", strayed " .. tostring(m.strayed)) or ", held", tostring(m.power))
    end)
    check("effects_stale_quality_and_loudness_kept_on_the_server", function()
        return m.featuresChanged == "" and efNum(m, "quality") == efNum(m, "q0") and efNum(m, "loudness") == efNum(m, "l0"),
            m.featuresChanged ~= "" and tostring(m.featuresChanged) or string.format("quality %s loudness %s",
                tostring(m.quality), tostring(m.loudness))
    end)
end, false)

EF.shutOff = act("effects_shut_off", function(ctx, p) ISVehicleMenu.onShutOff(p) end, 600)

EF.staleStopped = efMark("stale_stopped", function(m)
    check("effects_stale_power_back_after_the_stop", function()
        local b = efNum(m, "backAt")
        return m.running == "false" and efNum(m, "power") == efNum(m, "base") and m.powerState == "nil" and b >= 0
            and b <= 2, string.format("power %s (own %s) %s minute pass(es) after the stop; state %s", tostring(m.power),
            tostring(m.base), tostring(m.backAt), tostring(m.powerState))
    end)
    check("effects_stale_engine_worn_by_the_litres_burned", function()
        local taken = efNum(m, "cond0") - efNum(m, "cond")
        local due = efNum(m, "carry0") + efNum(m, "accrual")
        return efNum(m, "calls") > 0 and taken >= 1 and taken == math.floor(due + 1e-9)
            and math.abs(taken + efNum(m, "carry") - due) <= 1e-6,
            string.format("%d points taken + %.6f carried = %.6f; due %.6f (%s minute(s), %.6f L)", taken,
                efNum(m, "carry"), taken + efNum(m, "carry"), due, tostring(m.calls), efNum(m, "litres"))
    end)
end, true)

EF.blend = call("effects_blend", "effects_blend", {}, "effects_blend", function(m)
    report():line("OBS  MP.effects unfit blend %s; compatible=%s powerFactor=%.6f reasons %s", tostring(m.tank),
        tostring(m.compatible), efNum(m, "powerFactor"), tostring(m.reasons))
    check("effects_blend_unfit_for_the_engine", function()
        return m.compatible == "false", string.format("compatible=%s %s", tostring(m.compatible), tostring(m.reasons))
    end)
end)

-- One start through the menu, expected refused by the server's gate.
EF.tryStart = { name = "mp_effects_start_refused", timeout = 2400, fn = function(ctx, ticks)
    local p = player()
    if not ctx.t then
        ctx.t = ticks
        ISVehicleMenu.onStartEngine(p)
        report():line("OBS  MP.effects start queued: %s", h.actionNames(p))
        return nil
    end
    if ticks - ctx.t < 600 or not TLGH.Steps.actionsIdle(p) then return nil end
    local v = efCar()
    report():line("OBS  MP.effects start on the unfit blend: running=%s state=%s on A's client", tostring(v and v:isEngineRunning()),
        tostring(v and v:getEngineState()))
    return true
end }

EF.unfitRefused = efMark("unfit_refused", function(m)
    check("effects_start_refused_on_the_unfit_blend", function()
        return m.running == "false" and efNum(m, "runs") == (EF.lastRuns or -1),
            string.format("running %s, runs %s (before %s)", tostring(m.running), tostring(m.runs), tostring(EF.lastRuns))
    end)
end, false)

EF.unfitRunning = efMark("unfit_running", function(m)
    check("effects_unfit_runs_at_the_floor_with_stalls_off", function()
        local r, base = efNum(m, "reachedAt"), efNum(m, "base")
        return m.running == "true" and efNum(m, "runs") == (EF.lastRuns or -1) + 1
            and efNum(m, "target") == math.floor(base * 0.5 + 0.5) and efNum(m, "power") == efNum(m, "target")
            and r >= 0 and r <= 2 and m.strayed == "" and efNum(m, "ranFor") >= 10,
            string.format("power %s (own %s, target %s) after %s pass(es)%s; ran %s minute(s) without a stall",
                tostring(m.power), tostring(m.base), tostring(m.target), tostring(m.reachedAt),
                m.strayed ~= "" and (", strayed " .. tostring(m.strayed)) or "", tostring(m.ranFor))
    end)
end, false)

-- Stalls on with the engine running: A's client must see it stop.
EF.waitStall = { name = "mp_effects_wait_stall", timeout = 2400, fn = function(ctx, ticks)
    local v = efCar()
    if v and v:isEngineRunning() and ticks < 1800 then return nil end
    ctx.stopped = ctx.stopped or ticks
    if ticks - ctx.stopped < 600 then return nil end
    report():line("OBS  MP.effects A's client: running=%s %d ticks after stalls went on", tostring(v and v:isEngineRunning()),
        ctx.stopped)
    return true
end }

EF.unfitStalled = efMark("unfit_stalled", function(m)
    check("effects_unfit_stalls_with_the_option_on", function()
        local s, b = efNum(m, "stoppedAfter"), efNum(m, "backAt")
        return m.running == "false" and s >= 0 and s <= 2 and efNum(m, "power") == efNum(m, "base") and b >= 0 and b <= 2,
            string.format("stopped %s minute pass(es) after stalls went on; power %s (own %s) %s pass(es) later",
                tostring(m.stoppedAfter), tostring(m.power), tostring(m.base), tostring(m.backAt))
    end)
end, true)

EF.exit = act("effects_exit", function(ctx, p) ISVehicleMenu.onExit(p) end, 120)

local function efFuelGen(name, key)
    return act(name, function(ctx, p)
        ISWorldObjectContextMenu.doAddFuelGenerator(nil, gen(1), nil, inventoryItem(FU[key]), 0)
    end, 180)
end

EF.genAge = call("effects_gen_age", "effects_gen_age", { deg = tostring(EF.genDeg) }, "effects_gen_age", function(m)
    EF.genH0 = tonumber(m.hours)
    report():line("OBS  MP.effects generator %.4f L, condition %s, on %s, record %s; compatible=%s wearFactor=%.6f",
        efNum(m, "fuel"), tostring(m.cond), tostring(m.on), tostring(m.side), tostring(m.compatible), efNum(m, "wearFactor"))
    check("effects_gen_fuel_wears", function()
        return m.on == "true" and m.compatible == "true" and efNum(m, "wearFactor") > 1 and math.abs(efNum(m, "fuel") - 8) < 2e-3,
            string.format("on %s, %.4f L, wear %.6f", tostring(m.on), efNum(m, "fuel"), efNum(m, "wearFactor"))
    end)
end)

EF.genRun = { name = "mp_effects_generator_runs", timeout = 30000, fn = function(ctx, ticks)
    local hrs = getGameTime():getWorldAgeHours()
    if EF.genH0 and hrs - EF.genH0 < EF.genHours and ticks < 28000 then return nil end
    local g = gen(1)
    report():line("OBS  MP.effects generator ran %.2f game h: fuel %.4f L, condition %s on A's client", hrs - (EF.genH0 or hrs),
        g and g:getFuel() or -1, tostring(g and g:getCondition()))
    return true
end }

EF.genArm = call("effects_gen_arm", "effects_gen_arm", { scale = tostring(EF.genScale) }, "effects_gen_arm", function(m)
    report():line("OBS  MP.effects generator armed (wear x%d fixture): %.4f L, condition %s, record %s", EF.genScale,
        efNum(m, "fuel"), tostring(m.cond), tostring(m.side))
end)

EF.genProbe = call("effects_gen_probe", "effects_gen_probe", {}, "effects_gen_probe", function(m)
    local g = gen(1)
    report():line("OBS  MP.effects generator charge (call %s of %s): %.6f L burned at factor %.6f, %.4f points a litre at"
        .. " factor 2: %.6f due; condition %s -> %s, carry %.6f -> %.6f; charged again: %s (condition %s -> %s), later"
        .. " calls %s; now %.4f L, condition %s; A's client %s", tostring(m.firstIndex), tostring(m.charges),
        efNum(m, "burned"), efNum(m, "wear"), efNum(m, "perLitre"), efNum(m, "due"), tostring(m.cond), tostring(m.cond1),
        efNum(m, "carry"), efNum(m, "carry1"), tostring(m.again), tostring(m.againFrom), tostring(m.againCond),
        tostring(m.later), efNum(m, "fuelNow"), tostring(m.condNow), tostring(g and g:getCondition()))
    check("effects_gen_worn_by_the_litres_burned", function()
        local taken, due = efNum(m, "cond") - efNum(m, "cond1"), efNum(m, "due")
        return m.firstIndex ~= nil and taken >= 1 and taken == math.floor(due + 1e-9)
            and math.abs(taken + efNum(m, "carry1") - due) <= 1e-6,
            string.format("%d points taken + %.6f carried; due %.6f", taken, efNum(m, "carry1"), due)
    end)
    check("effects_gen_not_charged_twice", function()
        return efNum(m, "again") == 0 and efNum(m, "againCond") == efNum(m, "againFrom") and efNum(m, "later") == 0,
            string.format("again %s, later calls %s", tostring(m.again), tostring(m.later))
    end)
    check("effects_gen_condition_seen", function()
        return g ~= nil and g:getCondition() == efNum(m, "condNow"),
            string.format("%s (server %s)", tostring(g and g:getCondition()), tostring(m.condNow))
    end)
end)

EF.cleanup = call("effects_cleanup", "effects_cleanup", {}, "effects_cleanup", function(m)
    report():line("OBS  MP.effects fixtures undone; stalls %s", tostring(m.stalls))
end)

-- B: the marks A sends, until A finishes.
EF.watchB = { name = "mp_effects_watch_marks", timeout = 120000, fn = function(ctx, ticks)
    local m = nextFrom("ef_mark")
    if m then
        efSeen(m.name, m, m.condCheck == "1")
        send("ef_seen", { name = m.name })
    end
    if nextFrom("finish") then
        efLoudness()
        return true
    end
    return nil
end }

------------------------------------------------------------------------------
-- timers (D-032 with a server running them), A only, on the shortest day.
-- The server builds, fuels and lights a campfire, puts four running
-- fermenters beside it and 28 out of its reach, and checks every reading and
-- note its timers write against its own read of the air and the campfire
-- (MPServer.lua, the timers case). After three game hours A takes the
-- results, asks the status of a machine by the fire and one away from it as
-- the menu does (the catch-up from those notes and readings runs on the
-- server), and has the server time the timers' bodies.
------------------------------------------------------------------------------
local TM = { hours = 3 }
MP.TM = TM

TM.setup = call("timers_site", "setup_timers", { fuel = "480", far = "28" }, "timers_site", function(m)
    TM.site = m
    report():line("OBS  MP.timers site: campfire %s,%s built=%s lit=%s fuel %s; %s machines (%s out of reach); by the fire"
        .. " %s at %s,%s, away %s at %s,%s %s", tostring(m.fx), tostring(m.fy), tostring(m.built), tostring(m.lit),
        tostring(m.fuel), tostring(m.machines), tostring(m.far), tostring(m.nearId), tostring(m.nearX), tostring(m.nearY),
        tostring(m.farId), tostring(m.farX), tostring(m.farY), tostring(m.error or ""))
    check("timers_campfire_and_machines_on_the_server", function()
        return m.lit == "true" and tonumber(m.machines) == 32,
            string.format("lit %s, %s machines", tostring(m.lit), tostring(m.machines))
    end)
end)

TM.wait = { name = "mp_timers_hours", timeout = 12000, fn = function(ctx, ticks)
    local hrs = getGameTime():getWorldAgeHours()
    ctx.h0 = ctx.h0 or hrs
    if hrs - ctx.h0 < TM.hours and ticks < 11000 then return nil end
    report():line("OBS  MP.timers %.2f game hours passed", hrs - ctx.h0)
    return true
end }

TM.probe = call("timers_probe", "probe_timers", {}, "probe_timers", function(m)
    report():line("OBS  MP.timers server: %s hour(s), %s ten-minute pass(es), %s machines; readings matched %s, not %s;"
        .. " notes matched %s, not %s; warmed by the fire: %s beside it, %s away; campfire notes by the fire %s; fewest"
        .. " readings on a record %s; campfire fuel %s lit %s", tostring(m.hours), tostring(m.tens), tostring(m.machines),
        tostring(m.readings), tostring(m.badReadings), tostring(m.goodNotes), tostring(m.badNotes), tostring(m.warmNear),
        tostring(m.warmFar), tostring(m.nearCampfireHours), tostring(m.slotsMin), tostring(m.fuel), tostring(m.lit))
    for _, k in ipairs({ "hour_climate", "hour_readings", "ten_minute_notes", "machine_status" }) do
        report():line("OBS  MP.timers cost on the server: %s", tostring(m["cost_" .. k]))
    end
    local hours, tens, n = efNum(m, "hours"), efNum(m, "tens"), efNum(m, "machines")
    check("timers_hourly_readings_on_the_server", function()
        return hours >= TM.hours and efNum(m, "badReadings") == 0 and efNum(m, "readings") == hours * n,
            string.format("%s of %d readings matched the air (%s hours, %s machines)", tostring(m.readings), hours * n,
                tostring(m.hours), tostring(m.machines))
    end)
    check("timers_fire_notes_on_the_server", function()
        return tens >= 6 * TM.hours and efNum(m, "badNotes") == 0 and efNum(m, "goodNotes") == tens * n
            and efNum(m, "warmNear") == 4 and efNum(m, "warmFar") == 0,
            string.format("%s of %d notes as the air and the campfire give them; warmed %s beside the fire, %s away",
                tostring(m.goodNotes), tens * n, tostring(m.warmNear), tostring(m.warmFar))
    end)
end)

local function tmStatus(name, which)
    return request("timers_status_" .. name, "machine.status", function()
        local s = TM.site
        local x, y = tonumber(s[which .. "X"]), tonumber(s[which .. "Y"])
        local item = h.floorItem(x, y, "TLG.FermenterVessel")
        return item and { target = TLG.Integration.Machines.refFor(item) }
    end, function(r)
        report():line("OBS  MP.timers status %s: %s stage=%s siteC=%s siteNow=%s", name, brief(r), tostring(r.stage),
            tostring(r.siteC), tostring(r.siteNow))
        check("timers_status_" .. name, function()
            return r.ok == true and r.state == "Processing", brief(r)
        end)
    end)
end

local function tmWalk(name, which)
    return walkTo("mp_walk_to_" .. name, function()
        return tonumber(TM.site[which .. "X"]), tonumber(TM.site[which .. "Y"])
    end)
end

TM.bench = call("timers_bench", "bench_timers", {}, "bench_timers", function(m)
    for _, k in ipairs({ "hour", "ten", "status" }) do
        report():line("OBS  MP.timers bench on the server %s: %s", k, tostring(m[k .. "Text"]))
    end
end)

TM.costs = call("timers_costs", "probe_timers", {}, "probe_timers", function(m)
    for _, k in ipairs({ "hour_climate", "hour_readings", "ten_minute_notes", "machine_status" }) do
        report():line("OBS  MP.timers cost on the server at the end: %s", tostring(m["cost_" .. k]))
    end
end)

------------------------------------------------------------------------------
-- wrongfuel (2026-11-11, one client; D-037 with a server applying it). The
-- server puts a petrol car, an ambulance, a petrol generator and a Diesel
-- Generator by the spawn point (MPServer.lua, the wrong-fuel case). A pours
-- 10 L of petrol into each vehicle with the game's own action; the server
-- then rewrites a tank's record in shares (a fixture) and answers with the
-- verdict, which is checked against docs/balance.md's table.
-- What must cross the wire, each seen on the server and on A's client:
-- - a start the fuel refuses (the car on 40 % diesel, three tries): the
--   engine loses the 1 or 2 points the server drew and the battery 2 %, and
--   the driver is told;
-- - starts on fuel that harms (the car on a fifth diesel, the ambulance on
--   petrol alone), tried until the engine runs: each refused when the
--   server's draw is above the start factor, and the driver told on a pass;
-- - the car's power lowered while it runs; 4 L taken from its tank by the
--   server: the engine's and the exhaust's condition for those litres;
-- - the ambulance failing on petrol (1 L taken, the failure draw held at 0):
--   condition 0, stopped, the driver told, no start afterwards;
-- - the petrol generator refused on 40 % diesel (three tries) and the Diesel
--   Generator switched on on petrol, then failed by the server (a litre
--   gone, the draw held at 0);
-- - the mod's pour of petrol into the ambulance, refused until confirmed;
-- - the sandbox option off on the server: the same tank blocks the start.
-- The stall draw is held on the server while an engine must keep running.
------------------------------------------------------------------------------
local WFC = (function()
    local W = {}
    local function veh(k) return W.site and getVehicleById(tonumber(W.site[k])) or nil end
    local function num(m, k) return tonumber(m[k]) or -1 end
    -- "start=0.1234;refused;roll=2.0000" as { { "start", 0.1234 }, ... }.
    local function draws(m)
        local out = {}
        for part in string.gmatch(m.draws or "", "[^;]+") do
            local k, v = string.match(part, "^([^=]+)=(.*)$")
            out[#out + 1] = { k or part, tonumber(v) }
        end
        return out
    end
    local function drawOf(list, key)
        for _, d in ipairs(list) do
            if d[1] == key then return d[2] or true end
        end
        return nil
    end
    local function partCondition(k, id)
        local v = veh(k)
        local p = v and v:getPartById(id)
        if p == nil or (id ~= "Engine" and p:getInventoryItem() == nil) then return -1 end
        return p:getCondition()
    end
    local function noteIs(key, fuel)
        local n = TLG.Notify and TLG.Notify.last
        return n ~= nil and n.key == key and n.fuel == fuel
    end
    local function noteText()
        local n = TLG.Notify and TLG.Notify.last
        return n and tostring(n.text) or "no line reached the client"
    end
    local function clearNote()
        if TLG.Notify then TLG.Notify.last = nil end
    end
    local function facts(m)
        return string.format("compatible=%s harmful=%s level=%s of %s start %s power %s wear %s failure %s exhaust %s attempt %s (%s)",
            tostring(m.compatible), tostring(m.harmful), tostring(m.level), tostring(m.wrong), tostring(m.start), tostring(m.pf),
            tostring(m.wear), tostring(m.failure), tostring(m.exhaust), tostring(m.attempt), tostring(m.reasons))
    end

    local function set(name, k, q, want)
        return call("wf_set_" .. name, "wf_set", { k = k, q = q }, "wf_set", function(m)
            W[k] = m
            report():line("OBS  MP.wf_set %s on the server: %s; condition %s, tank %s L", name, facts(m), tostring(m.cond),
                tostring(m.tankL or m.fuel))
            check("wf_verdict_" .. name, function()
                return m.compatible == tostring(want.compatible) and m.level == tostring(want.level)
                    and m.wrong == tostring(want.wrong) and math.abs(num(m, "start") - want.start) < 1e-6
                    and math.abs(num(m, "pf") - want.power) < 1e-6 and math.abs(num(m, "wear") - want.wear) < 1e-6
                    and m.failure == tostring(want.failure) and m.exhaust == tostring(want.exhaust)
                    and m.attempt == (want.attempt or "nil"), facts(m)
            end)
        end)
    end

    local function probe(name, k, judge, release)
        return call("wf_probe_" .. name, "wf_probe", { k = k, release = release and "1" or "0" }, "wf_probe", function(m)
            report():line("OBS  MP.wf_probe %s on the server: %s; engine %s carry %s exhaust %s carry %s battery %s running %s power %s (%s) tank %s; generator on %s fuel %s; draws %s",
                name, facts(m), tostring(m.cond), tostring(m.carry), tostring(m.muffler), tostring(m.mcarry), tostring(m.charge),
                tostring(m.running), tostring(m.power), tostring(m.powerState), tostring(m.tankL), tostring(m.on), tostring(m.fuel),
                tostring(m.draws))
            judge(m)
            W[k] = m
        end)
    end

    -- Asks the server from inside a step: sent once, then the answer or nil.
    local function ask(ctx, k)
        if not ctx.asked then
            ctx.asked = "wf_ask_" .. tostring(ctx.name) .. "_" .. tostring(ctx.tries)
            ctx.n = #(MP.inbox.wf_probe or {})
            send("wf_probe", { k = k, tag = ctx.asked })
            return nil
        end
        local got = MP.inbox.wf_probe or {}
        for i = ctx.n + 1, #got do
            if got[i].role == MP.role and got[i].tag == ctx.asked then
                ctx.asked = nil
                return got[i]
            end
        end
        return nil
    end

    -- Tries through the game's own menu until `stop(m)` or `most` tries:
    -- `go(p)` queues one, `judge(m, d)` gives ok and a text for it.
    local function tries(name, k, most, go, judge, stop, after)
        return { name = "mp_wf_" .. name, timeout = 40000, fn = function(ctx, ticks)
            local p = player()
            if not ctx.phase then ctx.phase, ctx.tries, ctx.texts, ctx.name = "try", 0, {}, name end
            if ctx.phase == "try" then
                clearNote()
                ctx.tries = ctx.tries + 1
                go(p)
                ctx.phase, ctx.t = "wait", ticks
                return nil
            end
            if ctx.phase == "wait" then
                if ticks - ctx.t < 300 or not TLGH.Steps.actionsIdle(p) then return nil end
                ctx.phase = "ask"
            end
            local m = ask(ctx, k)
            if not m then return nil end
            local ok, text = judge(m, draws(m), W[k] or {})
            ctx.texts[#ctx.texts + 1] = text
            if not ok and not ctx.bad then ctx.bad = string.format("try %d: %s", ctx.tries, text) end
            W[k] = m
            if not stop(m) and ctx.tries < most then
                ctx.phase = "try"
                return nil
            end
            report():line("OBS  MP.wf_%s tries: %s", name, table.concat(ctx.texts, " | "))
            check("wf_" .. name .. "_every_try_as_the_servers_draw_gives", function()
                return ctx.bad == nil, ctx.bad or string.format("%d tries, each as drawn", ctx.tries)
            end)
            if after then after(m, ctx) end
            return true
        end }
    end

    -- A start the fuel refuses: the points the server drew, the battery, the line.
    local function refusedJudge(k, fuel, generator)
        return function(m, d, before)
            local roll = drawOf(d, generator and "groll" or "roll")
            local refused = drawOf(d, generator and "grefused" or "refused") ~= nil
            local taken = num(before, "cond") - num(m, "cond")
            local used = num(before, "charge") - num(m, "charge")
            local here = generator and (W.gen(generator) and W.gen(generator):getCondition() or -1) or partCondition(k, "Engine")
            local ok = refused and (roll == 1 or roll == 2) and taken == roll and here == num(m, "cond")
                and noteIs("IGUI_TLG_Note_StartDamage", fuel)
                and (generator and m.on == "false" or (not generator and m.running == "false" and used > 0.0199 and used < 0.0201))
            return ok, string.format("the server drew %s, condition %s -> %s there and %s here%s; line: %s", tostring(roll),
                tostring(before.cond), tostring(m.cond), tostring(here),
                generator and "" or string.format(", battery -%.4f", used), noteText())
        end
    end

    -- A start on fuel that harms: refused when the server's draw is above the factor.
    local function harmJudge(k, sf, fuel, generator)
        return function(m, d, before)
            local x = drawOf(d, generator and "gstart" or "start")
            local refused = drawOf(d, generator and "grefused" or "refused") ~= nil
            local on = generator and m.on or m.running
            local ok = type(x) == "number" and refused == (x > sf) and num(m, "cond") == num(before, "cond")
                and (not refused or on == "false") and (refused or noteIs("IGUI_TLG_Note_WrongFuel", fuel))
            return ok, string.format("drew %s against %s: %s by the server, on %s%s", tostring(x), tostring(sf),
                refused and "refused" or "passed", tostring(on), refused and "" or ("; line: " .. noteText()))
        end
    end

    W.gen = function(n)
        local sq = W.site and getCell():getGridSquare(tonumber(W.site["g" .. n .. "x"]), tonumber(W.site["g" .. n .. "y"]), 0)
        local objs = sq and sq:getObjects()
        for i = 0, (objs and objs:size() or 0) - 1 do
            if instanceof(objs:get(i), "IsoGenerator") then return objs:get(i) end
        end
        return nil
    end

    W.setup = call("wf_site", "setup_wrongfuel", {}, "wrongfuel_site", function(m)
        W.site = m
        FU.site = { car = m.car, g1x = m.g1x, g1y = m.g1y, g2x = m.g2x, g2y = m.g2y }
        check("wf_site_ready_on_the_server", function()
            return m.carProfile == "engine_si_stock" and m.ambProfile == "engine_ci_stock" and m.g1Profile == "generator_si_stock"
                and m.g2Profile == "generator_ci_bio" and m.diesel == "true" and m.damage == "true" and m.stalls == "true",
                string.format("car %s, ambulance %s, generators %s and %s; dieselVehicles=%s WrongFuelDamage=%s VehicleStalls=%s; CarGasConsumption %s; the mod there is %s",
                    tostring(m.carProfile), tostring(m.ambProfile), tostring(m.g1Profile), tostring(m.g2Profile), tostring(m.diesel),
                    tostring(m.damage), tostring(m.stalls), tostring(m.consumption), tostring(m.version))
        end)
    end)

    W.seen = once("mp_wf_site_seen", function()
        check("wf_site_seen", function()
            return veh("car") ~= nil and veh("amb") ~= nil and W.gen(1) ~= nil and W.gen(2) ~= nil and getDebug() == false,
                string.format("car=%s ambulance=%s generators=%s,%s debug=%s role=%s", tostring(veh("car") ~= nil),
                    tostring(veh("amb") ~= nil), tostring(W.gen(1) ~= nil), tostring(W.gen(2) ~= nil), tostring(getDebug()),
                    tostring(select(2, pcall(function() return player():getRole():getName() end))))
        end)
    end)

    W.canToAmb = act("wf_can_to_ambulance", function(ctx, p)
        ISVehiclePartMenu.onAddGasoline(p, veh("amb"):getPartById("GasTank"))
    end, 180)

    local function enter(name, k)
        return act("wf_enter_" .. name, function(ctx, p) ISVehicleMenu.onEnter(p, veh(k), 0) end, 120)
    end
    local function startEngine(p) ISVehicleMenu.onStartEngine(p) end
    local function switchOn(n)
        return function(p) ISWorldObjectContextMenu.onActivateGenerator(nil, true, W.gen(n), 0) end
    end
    local function hold(name, on)
        return call("wf_hold_" .. name, "wf_hold", { stall = on and "1" or "0" }, "wf_hold", function(m)
            report():line("OBS  MP.wf stall draw held on the server: %s", tostring(m.stall))
        end)
    end
    local function consumption()
        local c = W.site and tonumber(W.site.consumption)
        return (c and c > 0) and c or 1
    end

    -- The mod's pour into a vehicle, queued as its menu queues it.
    local function pourInto(name, canKey, k, experimental)
        return act("wf_" .. name, function(ctx, p)
            W[name] = nil
            local v = veh(k)
            local part = v:getPartById("GasTank")
            local can = inventoryItem(FU[canKey])
            ISTimedActionQueue.add(ISPathFindAction:pathToVehicleArea(p, v, part:getArea()))
            if luautils and luautils.equipItems then luautils.equipItems(p, can, nil) end
            ISTimedActionQueue.add(ISTLGPourFuel:new(p, can, { kind = "vehicle", id = v:getId() }, v, experimental,
                function(r) W[name] = r end))
        end, 180)
    end
    -- A generator fuelled with the game's own Add Fuel.
    local function fuelGen(name, n, canKey)
        return act("wf_" .. name, function(ctx, p)
            ISWorldObjectContextMenu.doAddFuelGenerator(nil, W.gen(n), nil, inventoryItem(FU[canKey]), 0)
        end, 180)
    end

    W.steps = {
        MP.waitWorld, W.setup, wait("mp_wf_site_arrives", 300), W.seen,
        giveCan("wf_give_can_car", { petrol = "10" }, "wfCan1"), arrived("wfCan1"), FU.canToCar,
        giveCan("wf_give_can_ambulance", { petrol = "10" }, "wfCan2"), arrived("wfCan2"), W.canToAmb,
        -- The verdicts.
        set("car_on_a_fifth_diesel", "car", "gasoline=0.8;diesel=0.2",
            { compatible = true, level = 2, wrong = "diesel", start = 0.4, power = 0.6, wear = 6, exhaust = 0.5 }),
        set("ambulance_on_30pc_petrol", "amb", "diesel=0.7;gasoline=0.3",
            { compatible = true, level = 2, wrong = "gasoline", start = 0.5, power = 0.7, wear = 8 }),
        set("ambulance_on_petrol", "amb", "gasoline=1",
            { compatible = true, level = 3, wrong = "gasoline", start = 0.25, power = 0.5, wear = 15, failure = 0.02 }),
        set("car_on_40pc_diesel", "car", "gasoline=0.6;diesel=0.4",
            { compatible = false, level = 4, wrong = "diesel", start = 0, power = 0, wear = 10, exhaust = 1, attempt = "1-2" }),
        -- The car: refused, then started on a fifth diesel.
        enter("car", "car"),
        tries("car_refused_on_40pc_diesel", "car", 3, startEngine, refusedJudge("car", "diesel"), function() return false end),
        set("car_back_on_a_fifth_diesel", "car", "gasoline=0.8;diesel=0.2",
            { compatible = true, level = 2, wrong = "diesel", start = 0.4, power = 0.6, wear = 6, exhaust = 0.5 }),
        hold("for_the_car", true),
        tries("car_starts_on_a_fifth_diesel", "car", 14, startEngine, harmJudge("car", 0.4, "diesel"),
            function(m) return m.running == "true" end, function(m)
                check("wf_car_running_on_a_fifth_diesel", function()
                    local v = veh("car")
                    return m.running == "true" and v ~= nil and v:isEngineRunning(), string.format("server %s, here %s",
                        tostring(m.running), tostring(v and v:isEngineRunning()))
                end)
            end),
        wait("mp_wf_car_idles", 420),
        probe("car_power", "car", function(m)
            check("wf_power_lowered_on_the_server_and_seen_here", function()
                local base = num(W.site, "carPower")
                local target = TLG.Domain.EngineEffects.targetPower(base, 0.6)
                local v = veh("car")
                return m.running == "true" and num(m, "power") == target and target < base and v ~= nil
                    and v:getEnginePower() == target, string.format("own %s, x 0.6: %s; the server's %s, here %s; running %s",
                    tostring(base), tostring(target), tostring(m.power), tostring(v and v:getEnginePower()), tostring(m.running))
            end)
        end),
        call("wf_burn_car", "wf_burn", { k = "car", litres = "4" }, "wf_burn", function(m)
            W.b0 = m
            report():line("OBS  MP.wf_burn car: engine %s carry %s exhaust %s carry %s tank %s -> %s L", tostring(m.cond),
                tostring(m.carry), tostring(m.muffler), tostring(m.mcarry), tostring(m.tankL), tostring(m.tankAfter))
        end),
        wait("mp_wf_car_burns", 450),
        probe("car_wear", "car", function(m)
            local b, c = W.b0 or {}, consumption()
            local burned = num(b, "tankL") - num(m, "tankL")
            check("wf_engine_and_exhaust_worn_by_the_litre_on_the_server", function()
                local taken = num(b, "cond") - num(m, "cond")
                local due = num(b, "carry") + burned * (6 - 1) * 0.15 / c
                local exhaust = (num(b, "muffler") - num(m, "muffler")) + num(m, "mcarry")
                local exhaustDue = num(b, "mcarry") + burned / c * 0.5
                return m.running == "true" and burned > 3.9 and taken >= 2 and math.abs(taken + num(m, "carry") - due) <= 0.06
                    and num(b, "muffler") >= 0 and math.abs(exhaust - exhaustDue) <= 0.06, string.format(
                    "%.4f L at wear x 6: engine %d taken + %.4f carried, %.4f due; exhaust %s -> %s + %.4f carried, %.4f due",
                    burned, taken, num(m, "carry"), due, tostring(b.muffler), tostring(m.muffler), num(m, "mcarry"), exhaustDue)
            end)
            check("wf_worn_engine_and_exhaust_seen_here", function()
                return partCondition("car", "Engine") == num(m, "cond") and partCondition("car", "Muffler") == num(m, "muffler"),
                    string.format("engine %s here, %s there; exhaust %s here, %s there", tostring(partCondition("car", "Engine")),
                        tostring(m.cond), tostring(partCondition("car", "Muffler")), tostring(m.muffler))
            end)
        end, true),
        act("wf_shut_off_car", function(ctx, p) ISVehicleMenu.onShutOff(p) end, 300),
        act("wf_exit_car", function(ctx, p) ISVehicleMenu.onExit(p) end, 120),
        -- The ambulance on petrol alone: started, then failed.
        enter("ambulance", "amb"),
        hold("for_the_ambulance", true),
        tries("ambulance_starts_on_petrol", "amb", 20, startEngine, harmJudge("amb", 0.25, "gasoline"),
            function(m) return m.running == "true" end, function(m)
                check("wf_ambulance_running_on_petrol", function()
                    local v = veh("amb")
                    return m.running == "true" and v ~= nil and v:isEngineRunning(), string.format("server %s, here %s",
                        tostring(m.running), tostring(v and v:isEngineRunning()))
                end)
            end),
        wait("mp_wf_ambulance_idles", 300),
        once("mp_wf_clear_line", clearNote),
        call("wf_burn_ambulance", "wf_burn", { k = "amb", litres = "1", fail = "1" }, "wf_burn", function(m)
            W.b0 = m
            report():line("OBS  MP.wf_burn ambulance: engine %s tank %s -> %s L, the failure draw held at 0", tostring(m.cond),
                tostring(m.tankL), tostring(m.tankAfter))
        end),
        wait("mp_wf_ambulance_burns", 450),
        probe("ambulance_failed", "amb", function(m)
            check("wf_engine_failed_on_the_server_and_seen_here", function()
                local v = veh("amb")
                return num(W.b0 or {}, "cond") > 0 and num(m, "cond") == 0 and m.running == "false"
                    and drawOf(draws(m), "failheld") ~= nil and partCondition("amb", "Engine") == 0 and v ~= nil
                    and not v:isEngineRunning() and noteIs("IGUI_TLG_Note_EngineFailed", "gasoline"), string.format(
                    "engine %s -> %s on the server, running %s; here engine %s, running %s; line: %s", tostring(W.b0 and W.b0.cond),
                    tostring(m.cond), tostring(m.running), tostring(partCondition("amb", "Engine")),
                    tostring(v and v:isEngineRunning()), noteText())
            end)
        end, true),
        tries("failed_ambulance_does_not_start", "amb", 1, startEngine, function(m)
            return m.running == "false" and num(m, "cond") == 0, string.format("running %s, engine %s on the server",
                tostring(m.running), tostring(m.cond))
        end, function() return true end),
        act("wf_exit_ambulance", function(ctx, p) ISVehicleMenu.onExit(p) end, 120),
        -- The generators, each fuelled with 5 L of petrol by the game's Add Fuel.
        giveCan("wf_give_can_generator_1", { petrol = "5" }, "wfCan4"), arrived("wfCan4"),
        fuelGen("fuel_the_petrol_generator", 1, "wfCan4"),
        giveCan("wf_give_can_generator_2", { petrol = "5" }, "wfCan5"), arrived("wfCan5"),
        fuelGen("fuel_the_diesel_generator", 2, "wfCan5"),
        set("petrol_generator_on_40pc_diesel", "g1", "gasoline=0.6;diesel=0.4",
            { compatible = false, level = 4, wrong = "diesel", start = 0, power = 0, wear = 10, exhaust = 1, attempt = "1-2" }),
        tries("petrol_generator_refused", "g1", 3, switchOn(1), refusedJudge("g1", "diesel", 1), function() return false end),
        set("diesel_generator_on_petrol", "g2", "gasoline=1",
            { compatible = true, level = 3, wrong = "gasoline", start = 0.25, power = 0.5, wear = 15, failure = 0.02 }),
        tries("diesel_generator_starts_on_petrol", "g2", 20, switchOn(2), harmJudge("g2", 0.25, "gasoline", 2),
            function(m) return m.on == "true" end, function(m)
                check("wf_diesel_generator_running_on_petrol", function()
                    local g = W.gen(2)
                    return m.on == "true" and g ~= nil and g:isActivated(), string.format("server %s, here %s", tostring(m.on),
                        tostring(g and g:isActivated()))
                end)
            end),
        call("wf_generator_fails", "wf_gen_fail", {}, "wf_gen_fail", function(m)
            W.gf = m
            check("wf_diesel_generator_failed_on_the_server", function()
                return m.on0 == "true" and num(m, "cond") == 0 and m.on == "false" and drawOf(draws(m), "gfailheld") ~= nil,
                    string.format("running before %s; condition %s -> %s, on %s; draws %s", tostring(m.on0), tostring(m.cond0),
                        tostring(m.cond), tostring(m.on), tostring(m.draws))
            end)
        end),
        wait("mp_wf_generator_failure_arrives", 180),
        once("mp_wf_generator_failure_seen", function()
            check("wf_failed_generator_seen_here", function()
                local g = W.gen(2)
                return g ~= nil and g:getCondition() == 0 and not g:isActivated(), string.format("condition %s, on %s",
                    tostring(g and g:getCondition()), tostring(g and g:isActivated()))
            end)
        end),
        -- The mod's pour: petrol into the ambulance's diesel.
        set("ambulance_on_diesel", "amb", "diesel=1", { compatible = true, start = 1, power = 1, wear = 1 }),
        giveCan("wf_give_pour_can", { petrol = "5" }, "wfCan3"), arrived("wfCan3"),
        pourInto("pour_petrol_into_the_ambulance", "wfCan3", "amb", false),
        probe("after_the_refused_pour", "amb", function(m)
            local r = W.pour_petrol_into_the_ambulance
            check("wf_pour_of_petrol_into_a_diesel_refused_by_the_server", function()
                return r ~= nil and r.ok == false and r.reason == "incompatible" and math.abs(num(m, "tankL") - num(W.amb, "tankL")) < 1e-6
                    and math.abs(canL("wfCan3") - 5) < 1e-6, string.format("reply %s; tank %s L (was %s); can %.4f L",
                    r and brief(r) or "none", tostring(m.tankL), tostring(W.amb and W.amb.tankL), canL("wfCan3"))
            end)
        end),
        pourInto("pour_petrol_into_the_ambulance_confirmed", "wfCan3", "amb", true),
        probe("after_the_confirmed_pour", "amb", function(m)
            local r = W.pour_petrol_into_the_ambulance_confirmed
            check("wf_confirmed_pour_goes_in_and_the_tank_harms", function()
                return r ~= nil and r.ok == true and math.abs(num(m, "tankL") - num(W.amb, "tankL") - 5) < 2e-3
                    and m.harmful == "true" and m.level == "2" and m.wrong == "gasoline", string.format(
                    "reply %s; tank %s L (was %s); %s", r and brief(r) or "none", tostring(m.tankL),
                    tostring(W.amb and W.amb.tankL), facts(m))
            end)
        end),
        -- The option off, then on again.
        call("wf_option_off", "wf_option", { on = "false" }, "wf_option", function(m)
            check("wf_option_off_blocks_without_damage_on_the_server", function()
                return m.on == "false" and m.compatible == "false" and m.harmful == "false" and m.attempt == "nil"
                    and num(m, "wear") == 1, "option " .. tostring(m.on) .. ": " .. facts(m)
            end)
        end),
        call("wf_option_on", "wf_option", { on = "true" }, "wf_option", function(m)
            check("wf_option_on_again", function()
                return m.on == "true" and m.compatible == "true" and m.harmful == "true", "option " .. tostring(m.on) .. ": " .. facts(m)
            end)
        end),
        call("wf_cleanup", "wf_cleanup", {}, "wf_cleanup", function(m)
            report():line("OBS  MP.wf fixtures undone; WrongFuelDamage %s", tostring(m.damage))
        end),
        once("mp_finish_b", function() send("finish", {}) end), MP.finish,
    }
    return W
end)()
MP.WFC = WFC

------------------------------------------------------------------------------
-- menus (2026-11-11, one client; 0.3.1 on a server): the mod's world menu
-- entries follow the click, as the single-player modes context-menus and
-- context-menus-zoom check it. The server puts down the wrong-fuel case's
-- car and generators, a full petrol can and a fermentation vessel. On A's
-- client each menu is built by the game's own right-click builder at a
-- chosen point: around the can and the vessel 77 clicks each, the mod's
-- entry exactly where the game's Grab shows (48 pixels over the zoom; a
-- click within 1.5 pixels of that reach is not judged); bare ground; the
-- generator's tile; the car with the cursor on it and away from it. At zoom
-- 1, 0.5 and 1.5. The client runs without -debug.
------------------------------------------------------------------------------
local MNC = (function()
    local M = { canAt = { S.CX - 3, S.CY }, vesselAt = { S.CX - 3, S.CY - 4 }, bareAt = { S.CX - 6, S.CY + 1 } }
    local function entry(menu, text)
        for i, o in pairs(menu.options or {}) do
            if type(i) == "number" and i < (menu.numOptions or 1e9) and type(o) == "table" and o.name ~= nil
                and string.sub(tostring(o.name), 1, #text) == text then
                return true
            end
        end
        return false
    end
    -- The game's menu for a click at (x, y) on `objects`, the cursor at (mx, my).
    local function menuAt(objects, x, y, mx, my)
        local realX, realY = getMouseXScaled, getMouseYScaled
        getMouseXScaled, getMouseYScaled = function() return mx or -5000 end, function() return my or -5000 end
        local ok, err = pcall(ISWorldObjectContextMenu.createMenu, 0, objects, x, y)
        getMouseXScaled, getMouseYScaled = realX, realY
        local menu = getPlayerContextMenu(0)
        local r = { ok = ok, err = err, fuel = entry(menu, getText("ContextMenu_TLG_Fuel")),
            machine = entry(menu, getText("ContextMenu_TLG_Machine")), grab = entry(menu, getText("ContextMenu_Grab")),
            gen = entry(menu, getText("ContextMenu_TLG_ConvGenerator")), car = entry(menu, getText("ContextMenu_TLG_ConvVehicle")) }
        pcall(function() menu:hideAndChildren() end)
        return r
    end
    local function text(r)
        return string.format("Fuel=%s Machine=%s Grab=%s Workshop generator=%s car=%s%s", tostring(r.fuel), tostring(r.machine),
            tostring(r.grab), tostring(r.gen), tostring(r.car), r.ok and "" or (" (builder error: " .. tostring(r.err) .. ")"))
    end
    local function floorOf(x, y)
        local sq = getCell():getGridSquare(x, y, 0)
        return sq and sq:getFloor(), sq
    end
    local function spawn(name, item, at, petrol)
        return call("mn_spawn_" .. name, "spawn", { item = item, x = at[1], y = at[2], petrol = petrol }, "spawned", function(m)
            report():line("OBS  MP.mn %s %s put down at %s,%s by the server", name, tostring(m.item), tostring(m.x), tostring(m.y))
        end)
    end
    local function at(tag)
        return { name = "mp_mn_at_" .. tag, timeout = 900, fn = function(ctx, ticks)
            if ticks < 120 then return nil end
            local zoom = getCore():getZoom(0)
            local can = floorItem(M.canAt[1], M.canAt[2], "Base.PetrolCan")
            local vessel = floorItem(M.vesselAt[1], M.vesselAt[2], "TLG.FermenterVessel")
            local site = WFC.site or {}
            local car = getVehicleById(tonumber(site.car) or -1)
            local gx, gy = tonumber(site.g1x), tonumber(site.g1y)
            if not (can and vessel and car and gx and can:getWorldItem() and vessel:getWorldItem()) then
                check("mn_" .. tag .. "_everything_here", function()
                    return false, string.format("can=%s vessel=%s car=%s generator tile=%s", tostring(can ~= nil), tostring(vessel ~= nil),
                        tostring(car ~= nil), tostring(gx))
                end)
                return true
            end
            report():line("OBS  MP.mn %s zoom %.2f debug=%s", tag, zoom, tostring(getDebug()))
            local items = { { "can", can, "fuel" }, { "vessel", vessel, "machine" } }
            local pos, reach = {}, 48 / zoom
            for i, spec in ipairs(items) do
                local w = spec[2]:getWorldItem()
                pos[i] = { x = w:getScreenPosX(0), y = w:getScreenPosY(0) }
            end
            for i, spec in ipairs(items) do
                local sx, sy = pos[i].x, pos[i].y
                local shown, hidden, n, edge, bad = 0, 0, 0, 0, {}
                for _, dx in ipairs({ -120, -80, -50, -30, -15, 0, 15, 30, 50, 80, 120 }) do
                    for _, dy in ipairs({ -80, -40, -15, 0, 15, 40, 80 }) do
                        local x, y = sx + dx, sy + dy
                        local wx, wy = ISCoordConversion.ToWorld(x * zoom, y * zoom, 0)
                        local floor, under = floorOf(math.floor(wx), math.floor(wy))
                        if floor then
                            local r = menuAt({ floor }, x, y)
                            n = n + 1
                            local want, onEdge = {}, false
                            for j, other in ipairs(items) do
                                local d = math.sqrt((pos[j].x - x) * (pos[j].x - x) + (pos[j].y - y) * (pos[j].y - y))
                                want[other[3]] = d <= reach
                                if math.abs(d - reach) <= 1.5 then onEdge = true end
                            end
                            local onGen = under:getX() == gx and under:getY() == gy
                            if onEdge then
                                edge = edge + 1
                            elseif r.ok and r.fuel == want.fuel and r.machine == want.machine
                                and r.grab == (want.fuel or want.machine) and r.gen == onGen and not r.car then
                                if r[spec[3]] then shown = shown + 1 else hidden = hidden + 1 end
                            elseif #bad < 6 then
                                bad[#bad + 1] = string.format("%d,%d: %s", dx, dy, text(r))
                            end
                        end
                    end
                end
                check("mn_" .. tag .. "_" .. spec[1] .. "_entry_shows_exactly_where_the_games_grab_shows", function()
                    return #bad == 0 and shown > 0 and hidden > 0, string.format(
                        "%d clicks around the item at %.0f,%.0f, reach %.1f pixels: its entry and Grab %d, without it %d, on the reach's edge and not judged %d%s",
                        n, sx, sy, reach, shown, hidden, edge, #bad > 0 and ("; differing: " .. table.concat(bad, " | ")) or "")
                end)
            end
            local bare = floorOf(M.bareAt[1], M.bareAt[2])
            local bx, by = isoToScreenX(0, M.bareAt[1] + 0.5, M.bareAt[2] + 0.5, 0), isoToScreenY(0, M.bareAt[1] + 0.5, M.bareAt[2] + 0.5, 0)
            local cx, cy = isoToScreenX(0, car:getX(), car:getY(), car:getZ()), isoToScreenY(0, car:getX(), car:getY(), car:getZ())
            local r = menuAt({ bare }, bx, by, bx * zoom, by * zoom)
            check("mn_" .. tag .. "_bare_ground_has_no_entry", function()
                return r.ok and not r.gen and not r.car and not r.fuel and not r.machine, text(r)
            end)
            r = menuAt({ (floorOf(gx, gy)) }, bx, by, bx * zoom, by * zoom)
            check("mn_" .. tag .. "_generator_tile_has_the_generator_entry", function() return r.ok and r.gen and not r.car, text(r) end)
            local under = floorOf(math.floor(car:getX()), math.floor(car:getY())) or bare
            r = menuAt({ under }, cx, cy, cx * zoom, cy * zoom)
            check("mn_" .. tag .. "_car_under_the_cursor_has_the_car_entry", function()
                return r.ok and r.car and not r.gen, string.format("the car on screen at %.0f,%.0f: %s", cx, cy, text(r))
            end)
            r = menuAt({ under }, bx, by, bx * zoom, by * zoom)
            check("mn_" .. tag .. "_car_not_under_the_cursor_has_no_entry", function() return r.ok and not r.car, text(r) end)
            return true
        end }
    end
    M.steps = { MP.waitWorld, WFC.setup, spawn("can", "Base.PetrolCan", M.canAt, "5"),
        spawn("vessel", "TLG.FermenterVessel", M.vesselAt), wait("mp_mn_site_arrives", 300),
        h.zoomTo("mp_mn_zoom_100", 1.0), at("zoom_100"),
        h.zoomTo("mp_mn_zoom_050", 0.5), at("zoom_050"),
        h.zoomTo("mp_mn_zoom_150", 1.5), at("zoom_150"),
        h.zoomTo("mp_mn_zoom_back", 1.0),
        call("mn_cleanup", "wf_cleanup", {}, "wf_cleanup", function() end),
        once("mp_finish_b", function() send("finish", {}) end), MP.finish }
    return M
end)()

if MP.only == "menus" then
    MP.stepsA = MNC.steps
    MP.stepsB = { MP.waitWorld, waitFrom("mp_wait_finish", "finish"), MP.finish }
elseif MP.only == "wrongfuel" then
    MP.stepsA = WFC.steps
    MP.stepsB = { MP.waitWorld, waitFrom("mp_wait_finish", "finish"), MP.finish }
elseif MP.only == "machines" then
    local bx0, by0, vx, vy = h.bx0, h.by0, h.vx, h.vy
    MP.stepsA = {
        MP.waitWorld, h.zoomTo("mp_zoom", 0.5), h.stand("mp_stand", bx0, by0),
        waitFrom("mp_wait_b", "hello", function() send("start", {}) end),
        C.spawnGrab, wait("mp_grab_vessel_lands", 120), C.grabBefore,
        walkTo("mp_walk_to_grab", S.spot(2)), C.grab, C.grabbed, C.statusCarried, C.carried1,
        wait("mp_carried_a_while", 900), C.statusCarried2, C.carried2, C.drop, C.dropped, C.statusDropped,
        C.placed1, wait("mp_placed_a_while", 900), C.statusPlaced2, C.placed2,
        C.spawnLoad, C.give, C.haveFeed, standNear("mp_walk_to_load", 1, -1),
        once("mp_load_setup", function() send("load_setup", {}) end), waitFrom("mp_wait_load_ready", "load_ready"),
        loadNow(true), C.loadBoth, C.loaded,
        C.crate, wait("mp_crate_vessel_arrives", 120), C.takeFromCrate, C.crateSeen,
        once("mp_finish_b", function() send("finish", {}) end), MP.finish,
    }
    MP.stepsB = {
        MP.waitWorld, h.zoomTo("mp_zoom", 0.5), h.stand("mp_stand", vx, vy, 1),
        once("mp_hello", function() send("hello", {}) end), waitFrom("mp_wait_start", "start"),
        waitFrom("mp_wait_load_setup", "load_setup"), C.give, C.haveFeed, standNear("mp_walk_to_load", 1, 1),
        once("mp_load_ready", function() send("load_ready", {}) end), loadNow(false),
        waitFrom("mp_wait_finish", "finish"), MP.finish,
    }
elseif MP.only == "fuel" then
    MP.stepsA = {
        MP.waitWorld, FU.setup, wait("mp_fuel_site_arrives", 300), FU.seen,
        giveCan("give_empty_can", { petrol = "0" }, "can1"), arrived("can1"), FU.pumpToCan, FU.afterPumpToCan,
        FU.canToCar, FU.afterCanToCar, FU.pumpToCar, FU.afterPumpToCar,
        FU.giveHose, wait("mp_hose_arrives", 120), FU.siphon, FU.afterSiphon,
        giveCan("give_petrol_can", { petrol = "5" }, "can2"), arrived("can2"), FU.canToGen, FU.afterCanToGen,
        giveCan("give_pour_can", { petrol = "3" }, "can3"), arrived("can3"),
        walkTo("mp_walk_to_generator_1", function() return site("g1x") + 1, site("g1y") end),
        pour("pour_petrol", "can3", 1, false), pourReached("pour_petrol"), FU.afterPourPetrol,
        giveCan("give_ethanol_can", { fill = "TLG_Diesel", litres = "3" }, "can4"), arrived("can4"),
        pour("pour_ethanol", "can4", 1, false), pourReached("pour_ethanol"), FU.afterPourEthanol,
        walkTo("mp_walk_to_generator_2", function() return site("g2x") + 1, site("g2y") end),
        pour("pour_ethanol_confirmed", "can4", 2, true), pourReached("pour_ethanol_confirmed"), FU.afterPourConfirmed,
        switch("start_generator_1", 1, true), switch("start_generator_2", 2, true), FU.afterStarts,
        wait("mp_generator_runs", 1800), FU.genStatus, FU.afterBurn,
        switch("stop_generator_1", 1, false), FU.unplug, FU.take, FU.afterTake, FU.place, FU.afterPlace,
        FU.enter, FU.start, FU.afterStart, wait("mp_car_idles", 1800), FU.carStatus, FU.afterIdle,
        once("mp_finish_b", function() send("finish", {}) end), MP.finish,
    }
    MP.stepsB = { MP.waitWorld, waitFrom("mp_wait_finish", "finish"), MP.finish }
elseif MP.only == "conversion" then
    MP.stepsA = {
        MP.waitWorld, CV.setup, CV.train, wait("mp_conversion_items_arrive", 300),
        walkTo("mp_walk_to_conversion", S.spot(2)),
        CV.begin, CV.deliver, CV.work, CV.status, CV.profile,
        giveCan("give_conversion_ethanol", { fill = "TLG_Ethanol", litres = "3" }, "cvCan"), arrived("cvCan"),
        CV.pour, CV.afterPour, CV.start, CV.afterStart,
        once("mp_finish_b", function() send("finish", {}) end), MP.finish,
    }
    MP.stepsB = { MP.waitWorld, waitFrom("mp_wait_finish", "finish"), MP.finish }
elseif MP.only == "carconv" then
    MP.stepsA = {
        MP.waitWorld, CC.setup, CC.train, wait("mp_carconv_items_arrive", 300),
        walkTo("mp_walk_to_car", S.CX + 1, S.CY + 1),
        CC.begin, CC.deliver, CC.work, CC.status, CC.profile,
        giveCan("give_carconv_ethanol", { fill = "TLG_Ethanol", litres = "3" }, "ccCan"), arrived("ccCan"),
        CC.pour, CC.afterPour, CC.enter, CC.start, CC.afterStart,
        once("mp_finish_b", function() send("finish", {}) end), MP.finish,
    }
    MP.stepsB = { MP.waitWorld, waitFrom("mp_wait_finish", "finish"), MP.finish }
elseif MP.only == "stills" then
    MP.stepsA = {
        MP.waitWorld, PR.setup, wait("mp_production_site_arrives", 300), PR.fermenter,
        logs("give_logs_pot"), wait("mp_logs_pot_arrive", 120), fed("pot_firewood", "pot"), washed("pot_wash", "pot"),
        logs("give_logs_reflux"), wait("mp_logs_reflux_arrive", 120), fed("reflux_firewood", "reflux"),
        washed("reflux_wash", "reflux"), ready("stills_distil", { "pot", "reflux" }),
        collected("pot_collect", "pot", 1), collected("reflux_collect", "reflux", 2), wait("mp_runs_arrive", 120),
        PR.cans, PR.dry, ready("drying", { "dryer" }), collected("dry_collect", "dryer", 3),
        wait("mp_dried_arrives", 120), PR.dried,
        once("mp_finish_b", function() send("finish", {}) end), MP.finish,
    }
    MP.stepsB = { MP.waitWorld, waitFrom("mp_wait_finish", "finish"), MP.finish }
elseif MP.only == "effects" then
    -- B says hello once in the world: a message sent before it joined
    -- would never reach it.
    MP.stepsA = {
        MP.waitWorld, waitFrom("mp_wait_b", "hello"), EF.setup, EF.seeCar, waitFrom("mp_wait_b_sees_car", "ef_ready"),
        giveCan("give_effects_can", { petrol = "10" }, "efCan"), arrived("efCan"), FU.canToCar,
        EF.age, efArm("stale", "false", EF.scale), FU.enter, FU.start, wait("mp_effects_idle", 3600),
        EF.staleRunning, efSeenByB("stale_running"),
        EF.shutOff, EF.staleStopped, efSeenByB("stale_stopped"),
        EF.blend, efArm("unfit", "true", 1), EF.tryStart, EF.unfitRefused, efSeenByB("unfit_refused"),
        efStalls("off", "false"), FU.start, wait("mp_effects_unfit_idle", 900),
        EF.unfitRunning, efSeenByB("unfit_running"),
        efStalls("on", "true"), EF.waitStall, EF.unfitStalled, efSeenByB("unfit_stalled"),
        once("mp_effects_loudness", efLoudness), EF.exit,
        giveCan("give_generator_can", { petrol = "8" }, "genCan1"), arrived("genCan1"),
        efFuelGen("effects_gen_fuel", "genCan1"), EF.genAge, EF.genRun, EF.genArm,
        giveCan("give_generator_can_2", { petrol = "2" }, "genCan2"), arrived("genCan2"),
        efFuelGen("effects_gen_charge", "genCan2"), EF.genProbe, EF.cleanup,
        once("mp_finish_b", function() send("finish", {}) end), MP.finish,
    }
    MP.stepsB = {
        MP.waitWorld, walkTo("mp_walk_to_watch", S.CX - 2, S.CY + 4), once("mp_hello", function() send("hello", {}) end),
        waitFrom("mp_wait_effects_site", "ef_site", function(m) EF.carId = tonumber(m.car) end), EF.seeCar,
        once("mp_effects_ready", function() send("ef_ready", {}) end), EF.watchB, MP.finish,
    }
elseif MP.only == "timers" then
    MP.stepsA = {
        MP.waitWorld, TM.setup, TM.wait, TM.probe,
        tmWalk("machine_by_the_fire", "near"), tmStatus("by_the_fire", "near"),
        tmWalk("machine_away", "far"), tmStatus("away", "far"),
        TM.bench, TM.costs, MP.finish,
    }
    MP.stepsB = { MP.waitWorld, waitFrom("mp_wait_finish", "finish"), MP.finish }
elseif MP.only == "knowledge" then
    -- What I know about it on a server (2026-11-06). A tests a petrol can
    -- with the sampling kit and with a look (both answered by the server,
    -- which keeps the knowledge in its player object), then opens What I
    -- know about it from the Fuel menu as a player does: the dialog's text
    -- is what the player reads. Then the can is opened (the unseal
    -- treatment) and the menu read again. Before the fix the menu read the
    -- client's own copy of the player's mod data, which nothing filled.
    local KN = {}
    local function has(text, part) return text ~= nil and string.find(text, part, 1, true) ~= nil end
    local function fuelMenuOption(key)
        local context = ISContextMenu.get(0, 100, 100)
        TLG.UI.FuelMenu.fill(0, context, { KN.can })
        local root = context:getOptionFromName(getText("ContextMenu_TLG_Fuel"))
        local sub = root and root.subOption and context:getSubMenu(root.subOption)
        local opt = sub and sub:getOptionFromName(getText(key))
        context:setVisible(false)
        return opt
    end
    -- Fuel > What I know about it, the dialog it opens (ISModalRichText) caught.
    local function knownDialog(name, judge)
        return { name = "mp_kn_" .. name, timeout = 1200, fn = function(ctx, ticks)
            if ticks == 1 then
                ctx.orig = ISModalRichText.new
                ISModalRichText.new = function(self, x, y, w, hh, text, ...)
                    local o = ctx.orig(self, x, y, w, hh, text, ...)
                    ctx.text, ctx.dialog = tostring(text), o
                    return o
                end
                local opt = fuelMenuOption("ContextMenu_TLG_ShowKnown")
                if opt then opt.onSelect(opt.target, opt.param1, opt.param2) end
                ctx.clicked = opt ~= nil
                return nil
            end
            if not ctx.text and ticks < 900 then return nil end
            ISModalRichText.new = ctx.orig
            if ctx.dialog then pcall(function() ctx.dialog:removeFromUIManager() end) end
            report():line("OBS  MP.kn_%s_%s menu entry=%s; dialog: %s", name, MP.role, tostring(ctx.clicked), tostring(ctx.text))
            judge(ctx.text or "")
            return true
        end }
    end
    KN.give = call("give_knowledge_items", "give", { items = "Base.PetrolCan;TLG.FuelSampleKit", petrol = "5" }, "given",
        function(m) KN.ids = ids(m.ids) end)
    KN.have = { name = "mp_kn_have", timeout = 900, fn = function(ctx, ticks)
        KN.can = inventoryItem(KN.ids and KN.ids["Base.PetrolCan"] and KN.ids["Base.PetrolCan"][1])
        if not (KN.can and countType("TLG.FuelSampleKit") >= 1) and ticks < 600 then return nil end
        check("kn_items", function()
            return KN.can ~= nil and countType("TLG.FuelSampleKit") >= 1, string.format("can %s, kits %d",
                tostring(KN.can and KN.can:getID()), countType("TLG.FuelSampleKit"))
        end)
        return true
    end }
    local function canRef() return KN.can and { target = { kind = "item", id = KN.can:getID() } } end
    KN.kit = request("kn_kit", "sample", function()
        local a = canRef(); if a then a.method = "kit" end; return a
    end, function(r)
        check("kn_kit", function() return r.ok == true and r.observation ~= nil and r.observation.method == "kit", brief(r) end)
    end)
    KN.look = request("kn_look", "sample", function()
        local a = canRef(); if a then a.method = "visual" end; return a
    end, function(r)
        check("kn_look", function() return r.ok == true and r.observation ~= nil, brief(r) end)
        local know = player():getModData().tlgKnowledge
        local side = KN.can:getModData().tlg
        report():line("OBS  MP.kn_client_copy_%s the client's own player mod data: knowledge %s; the can's record id %s",
            MP.role, know == nil and "none" or "present", tostring(side and side.id))
    end)
    KN.known = knownDialog("known", function(text)
        check("kn_known_lists_both_tests", function()
            return has(text, getText("IGUI_TLG_KnownTitle")) and has(text, getText("IGUI_TLG_TestName_kit"))
                and has(text, getText("IGUI_TLG_TestName_visual")) and has(text, getText("IGUI_TLG_Ago_Now")), text
        end)
        check("kn_known_sealed_no_note", function() return not has(text, getText("IGUI_TLG_KnownOpen")), text end)
    end)
    KN.unseal = request("kn_unseal", "treat", function()
        local a = canRef(); if a then a.op = "unseal" end; return a
    end, function(r)
        check("kn_unseal", function() return r.ok == true, brief(r) end)
    end)
    KN.knownOpen = knownDialog("known_open", function(text)
        check("kn_known_open_note", function() return has(text, getText("IGUI_TLG_KnownOpen")), text end)
    end)
    MP.stepsA = { MP.waitWorld, KN.give, KN.have, KN.kit, KN.look, KN.known, KN.unseal, wait("mp_kn_unseal_settles", 60),
        KN.knownOpen, MP.finish }
    MP.stepsB = { MP.waitWorld, waitFrom("mp_wait_finish", "finish"), MP.finish }

    -- With -Restart: the can stays sealed; after both tests A notes the
    -- can's id, its record id and the kit's composition line (the file
    -- outlives the Lua), leaves, the server is saved, stopped and started
    -- again, and A joins again. What the server knows of the player must
    -- come back: both tests, neither changed, the can sealed; and the
    -- dialog as a player reads it.
    if MP.restart then
        local SNAP = "TLG_harness_mpsnap.txt"
        local function kitLine(text)
            local label = string.gsub(getText("IGUI_TLG_Composition", ""), "%s+$", "")
            local s, i = text or "", 1
            while i <= #s do
                local a, b = string.find(s, " <LINE> ", i, true)
                local part = string.sub(s, i, (a or #s + 1) - 1)
                if has(part, label) then return part end
                if not a then break end
                i = b + 1
            end
            return ""
        end
        KN.snap = knownDialog("known_before_restart", function(text)
            local side = KN.can:getModData().tlg
            KN.line = kitLine(text)
            TLGH.writeFile(SNAP, { "canId=" .. tostring(KN.can:getID()), "rec=" .. tostring(side and side.id),
                "kitLine=" .. KN.line })
            report():line("OBS  MP.kn_before_restart can %s, record %s, the kit's line '%s'", tostring(KN.can:getID()),
                tostring(side and side.id), KN.line)
            check("kn_before_restart_both_tests", function()
                return has(text, getText("IGUI_TLG_TestName_kit")) and has(text, getText("IGUI_TLG_TestName_visual"))
                    and KN.line ~= "", text
            end)
        end)
        KN.leave = { name = "mp_kn_leave", timeout = 600, fn = function(ctx, ticks)
            if ticks < 60 then return nil end
            h.setPhase("restart_wait")
            report():line("OBS  MP.leaving to the main menu for the server's restart")
            setGameSpeed(1)
            getCore():quit()
            return true
        end }
        KN.back = { name = "mp_kn_can_back", timeout = 1200, fn = function(ctx, ticks)
            local e = TLGH.readKeyValues(SNAP)
            KN.can = inventoryItem(tonumber(e.canId))
            if not KN.can and ticks < 600 then return nil end
            KN.line = e.kitLine or ""
            local side = KN.can and KN.can:getModData().tlg
            check("kn_can_back_after_restart", function()
                return KN.can ~= nil and side ~= nil and tostring(side.id) == e.rec, string.format("can %s found=%s, record %s"
                    .. " (before %s)", tostring(e.canId), tostring(KN.can ~= nil), tostring(side and side.id), tostring(e.rec))
            end)
            return true
        end }
        KN.direct = request("kn_known_after_restart", "known", function() return canRef() end, function(r)
            local parts = {}
            for _, t in ipairs(r.tests or {}) do
                parts[#parts + 1] = string.format("%s age=%.3f changed=%s", tostring(t.method), tonumber(t.ageHours) or -1,
                    tostring(t.changed))
            end
            report():line("OBS  MP.kn_known_after_restart reply ok=%s sealed=%s tests: %s", tostring(r.ok), tostring(r.sealed),
                table.concat(parts, "; "))
            check("kn_server_knows_both_tests_after_restart", function()
                local t = r.tests or {}
                return r.ok == true and #t == 2 and t[1].method == "kit" and t[2].method == "visual"
                    and t[1].changed == false and t[2].changed == false and r.sealed == true, "see the reply above"
            end)
        end)
        KN.dialogAfter = knownDialog("known_after_restart", function(text)
            check("kn_dialog_after_restart", function()
                return has(text, getText("IGUI_TLG_TestName_kit")) and has(text, getText("IGUI_TLG_TestName_visual"))
                    and KN.line ~= "" and has(text, KN.line) and not has(text, getText("IGUI_TLG_KnownChanged"))
                    and not has(text, getText("IGUI_TLG_KnownOpen")), text
            end)
        end)
        MP.stepsA = { MP.waitWorld, KN.give, KN.have, KN.kit, KN.look, KN.known, KN.snap, KN.leave }
        MP.stepsRejoined = { MP.waitWorld, wait("mp_kn_settle", 120), KN.back, KN.direct, KN.dialogAfter, MP.finish }
    end
end

------------------------------------------------------------------------------
-- death (2026-11-06, two clients): a carrier dies on a server. A takes a
-- running vessel off the floor into both hands (the mod's take on the
-- server, D-030), carries it two squares and dies. B, alive, asks the server
-- where the vessel is and what its record says right before the death and
-- once it has landed: put down where it fell from the moment of the death
-- (the D-015 amendment), or still carried until someone next reads it.
-- Then B walks to it, the record is read after a while (machine.status, as
-- the menu asks) and its work since the put-down is compared with the game
-- time since. The server's harness logs whether OnPlayerDeath and
-- OnCharacterDeath fire there (MPServer.lua).
------------------------------------------------------------------------------
if MP.only == "biodiesel" then
    -- The biodiesel pathway on a server (D-036), A alone. The server sets
    -- the site up (MPServer.lua setup_biodiesel). A loads each of the five
    -- machines through the mod's requests as their menu sends them (the
    -- leacher, the reactor and the wash tank from the finished machine
    -- beside them), collects a finished wash tank's biodiesel into a can
    -- and is refused a retort's methanol; pours biodiesel into the diesel
    -- generator, starts it, and takes it; starts the ambulance on the
    -- diesel it was found with; reads a diesel pump's label and fills a
    -- can at it through the game's own menu function. After each part the
    -- server's view is asked (probe_biodiesel) and this client's own view
    -- of the can, the generator's sprite and the item is checked.
    local BM = { keys = "retort;barrel;leacher;reactor;wash;barrelDone;retortDone;leacherDone;reactorDone;washDone" }
    MP.BM = BM
    local function bsite(k) return BM.site and tonumber(BM.site[k]) end
    local function machineItem(key)
        local id = bsite(key)
        local item = inventoryItem(id)
        for x = S.CX - 8, S.CX + 11 do
            for y = S.CY - 5, S.CY do
                local sq = item == nil and getCell():getGridSquare(x, y, 0)
                local objs = sq and sq:getWorldObjects()
                for i = 0, (objs and objs:size() or 0) - 1 do
                    local it = objs:get(i):getItem()
                    if it and it:getID() == id then item = it end
                end
            end
        end
        return item
    end
    local function objectAt(x, y, pred)
        local sq = x and getCell():getGridSquare(x, y, 0)
        local objs = sq and sq:getObjects()
        for i = 0, (objs and objs:size() or 0) - 1 do
            if pred(objs:get(i)) then return objs:get(i) end
        end
        return nil
    end
    local function bgen() return objectAt(bsite("gx"), bsite("gy"), function(o) return instanceof(o, "IsoGenerator") end) end
    local function bpump() return objectAt(bsite("px"), bsite("py"), function(o) return o:getPipedFuelAmount() > 0 end) end
    local function van() return BM.site and getVehicleById(bsite("van")) end
    local function fluids(item)
        local fc = item and item:getFluidContainer()
        if not fc then return {}, "no container" end
        local comp = TLG.Integration.Native.readComposition(fc)
        return comp, S.text(comp) .. " petrol=" .. tostring(fc:contains(Fluid.Petrol))
    end
    local function breq(name, command, key, extra, judge)
        return request(name, command, function()
            local it = machineItem(key)
            if not it then return nil end
            local a = { target = TLG.Integration.Machines.refFor(it) }
            for k, v in pairs(type(extra) == "function" and extra() or extra or {}) do a[k] = v end
            return a
        end, function(r)
            report():line("OBS  MP.%s reply: %s wood=%s ash=%s water=%s oil=%s methanol=%s lye=%s crude=%s wash=%s firebox=%s"
                .. " collected=%s", name, brief(r), tostring(r.woodKg), tostring(r.ashKg), tostring(r.waterL), tostring(r.oilL),
                tostring(r.methanolL), tostring(r.lyeKg), tostring(r.crudeL), tostring(r.washWaterL), tostring(r.firebox),
                S.text(r.collected))
            judge(r)
        end)
    end
    local function give(name, items, extra)
        local a = { items = items }
        for k, v in pairs(extra or {}) do a[k] = v end
        return call(name, "give", a, "given", function() end)
    end
    local function toMachine(key)
        return walkTo("mp_walk_to_" .. key, function() return bsite(key .. "X"), (bsite(key .. "Y") or bsite("y")) + 1 end)
    end
    local function probeB(name, judge)
        return call(name, "probe_biodiesel", function()
            local s = BM.site or {}
            local have = {}
            for _, id in ipairs({ tonumber(s.jerry) or false, FU.bdCan or false, FU.dCan or false }) do
                if id then have[#have + 1] = tostring(id) end
            end
            local a = { keys = BM.keys, gx = s.gx, gy = s.gy, van = s.van, px = s.px, py = s.py, ids = table.concat(have, ";") }
            for key in string.gmatch(BM.keys, "[^;]+") do a[key] = s[key] end
            return a
        end, "probe_biodiesel", function(m)
            local parts = {}
            for key in string.gmatch(BM.keys, "[^;]+") do parts[#parts + 1] = key .. "=" .. tostring(m[key]) .. " " .. tostring(m[key .. "Out"]) end
            report():line("OBS  MP.%s server machines: %s", name, table.concat(parts, "; "))
            report():line("OBS  MP.%s server: generator found=%s type=%s profile=%s fuel=%s on=%s %s; carried %s %s", name,
                tostring(m.gFound), tostring(m.gType), tostring(m.gProfile), tostring(m.gFuel), tostring(m.gOn), tostring(m.gSide),
                tostring(m.carriedType), tostring(m.carriedSide))
            report():line("OBS  MP.%s server: van profile=%s tank=%s L engine=%s %s; pump units=%s %s; cans %s", name,
                tostring(m.vanProfile), tostring(m.vanL), tostring(m.vanEngine), tostring(m.vanSide), tostring(m.pumpUnits),
                tostring(m.pumpSide), tostring(m.cans))
            judge(m)
        end)
    end
    local function has(text, part) return text ~= nil and string.find(text, part, 1, true) ~= nil end
    local loaded = function(name, more)
        return function(r) check(name, function() return r.ok == true and r.state == "Processing" and more(r), brief(r) end) end
    end

    BM.setup = call("biodiesel_site", "setup_biodiesel", {}, "biodiesel_site", function(m)
        BM.site = m
        report():line("OBS  MP.biodiesel site: blocked squares [%s]; finished machines: %s; generator %s,%s; van %s; pump %s,%s"
            .. " (%s units, gives %s); world has diesel=%s", tostring(m.blocked), tostring(m.states), tostring(m.gx), tostring(m.gy),
            tostring(m.van), tostring(m.px), tostring(m.py), tostring(m.pumpUnits), tostring(m.pumpProduct), tostring(m.dieselWorld))
        check("biodiesel_site_made", function()
            return m.blocked == "" and has(m.states, "washDone=OutputReady") and has(m.states, "reactorDone=OutputReady")
                and has(m.states, "retortDone=OutputReady") and has(m.states, "leacherDone=OutputReady")
                and has(m.states, "barrelDone=OutputReady") and m.pumpProduct == "diesel" and m.dieselWorld == "true",
                tostring(m.states)
        end)
    end)

    -- What this client holds of the site: the ten machines, the generator
    -- with its own sprite and picture, the van, and the world's record.
    BM.seen = once("mp_biodiesel_site_seen", function()
        local missing = {}
        for key in string.gmatch(BM.keys, "[^;]+") do
            if machineItem(key) == nil then missing[#missing + 1] = key end
        end
        local g = bgen()
        local name, tex, itemType = "?", nil, "?"
        pcall(function() name = g:getSprite():getName() end)
        pcall(function() tex = g:getSprite():getTextureForCurrentFrame(g:getDir()) end)
        pcall(function() itemType = g:getGeneratorItemType() end)
        local world = TLG.World.get()
        local v = van()
        check("biodiesel_site_seen", function()
            return #missing == 0 and g ~= nil and v ~= nil, string.format("machines missing: %s; generator %s; van %s",
                table.concat(missing, ","), tostring(g ~= nil), tostring(v ~= nil))
        end)
        check("diesel_generator_drawn_on_the_client", function()
            return name == "tlg_generators_01_0" and tex ~= nil and itemType == "TLG.DieselGenerator",
                string.format("sprite %s, picture %s, item type %s", tostring(name), tostring(tex ~= nil), tostring(itemType))
        end)
        check("client_knows_the_van_is_diesel", function()
            local profile = v and TLG.Integration.Vehicles.baseProfile(v)
            return world.dieselVehicles == true and profile == "engine_ci_stock", string.format(
                "client's world record dieselVehicles=%s; profile here %s", tostring(world.dieselVehicles), tostring(profile))
        end)
    end)

    BM.collect = breq("biodiesel_collect", "machine.collect", "washDone", function()
        return { destination = { kind = "item", id = bsite("jerry") } }
    end, function(r) check("biodiesel_collect", function() return r.ok == true, brief(r) end) end)

    BM.can = once("mp_biodiesel_can", function()
        local can = inventoryItem(bsite("jerry"))
        local comp, text = fluids(can)
        local q = can and can:getModData().tlg and can:getModData().tlg.q or {}
        check("biodiesel_in_the_client_can", function()
            return (comp.biodiesel or 0) > 16 and (comp.methanol or 0) > 0.01 and (comp.plant_oil or 0) > 0.1
                and (q.biodiesel or 0) > 16, string.format("fluids %s; record %s", text, S.text(q))
        end)
    end)

    BM.refused = breq("retort_collect", "machine.collect", "retortDone", function()
        return { destination = { kind = "item", id = bsite("jerry") } }
    end, function(r)
        check("retort_gives_nothing_to_a_can", function() return r.ok == false and r.reason == "use_next_machine", brief(r) end)
    end)

    BM.afterChain = probeB("after_chain", function(m)
        check("chain_states_on_the_server", function()
            return m.retort == "Processing" and m.barrel == "Processing" and m.leacher == "Processing" and m.reactor == "Processing"
                and m.wash == "Processing" and m.barrelDone == "Ready" and m.reactorDone == "Ready" and m.washDone == "Ready"
                and m.retortDone == "OutputReady" and m.leacherDone == "OutputReady",
                string.format("retort %s barrel %s leacher %s reactor %s wash %s; finished barrel %s retort %s leacher %s reactor %s"
                    .. " wash tank %s", tostring(m.retort), tostring(m.barrel), tostring(m.leacher), tostring(m.reactor),
                    tostring(m.wash), tostring(m.barrelDone), tostring(m.retortDone), tostring(m.leacherDone),
                    tostring(m.reactorDone), tostring(m.washDone))
        end)
    end)

    BM.pour = act("pour_biodiesel", function(ctx, p)
        local g = bgen()
        ISTimedActionQueue.add(ISTLGPourFuel:new(p, inventoryItem(FU.bdCan), TLG.Authority.Resolver.refForObject(g, "generator"),
            g, false, function(r) BM.pourReply = r end))
    end, 180)
    BM.on = act("start_diesel_generator", function() ISWorldObjectContextMenu.onActivateGenerator(nil, true, bgen(), 0) end, 180)
    BM.afterOn = probeB("after_generator_start", function(m)
        local r = BM.pourReply
        check("biodiesel_poured_into_the_generator", function()
            return r ~= nil and r.ok == true and near(tonumber(m.gFuel), 5, 0.01) and has(m.gSide, "biodiesel"),
                string.format("pour %s; server fuel %s %s", r and brief(r) or "no reply", tostring(m.gFuel), tostring(m.gSide))
        end)
        check("diesel_generator_runs_on_the_server", function()
            return m.gOn == "true" and m.gProfile == "generator_ci_bio" and m.gType == "TLG.DieselGenerator",
                string.format("on=%s profile=%s type=%s", tostring(m.gOn), tostring(m.gProfile), tostring(m.gType))
        end)
    end)
    BM.off = act("stop_diesel_generator", function() ISWorldObjectContextMenu.onActivateGenerator(nil, false, bgen(), 0) end, 120)
    BM.unplug = act("unplug_diesel_generator", function() ISWorldObjectContextMenu.onPlugGenerator(nil, bgen(), 0, false) end, 120)
    BM.take = act("take_diesel_generator", function() ISWorldObjectContextMenu.onTakeGenerator(nil, bgen(), 0) end, 180)
    BM.afterTake = probeB("after_generator_take", function(m)
        local held = player():getPrimaryHandItem()
        check("diesel_generator_taken_as_itself", function()
            return m.gFound == "false" and m.carriedType == "TLG.DieselGenerator" and has(m.carriedSide, "biodiesel")
                and held ~= nil and held:getFullType() == "TLG.DieselGenerator", string.format(
                "server: object left=%s, carried %s %s; in this client's hands %s", tostring(m.gFound), tostring(m.carriedType),
                tostring(m.carriedSide), tostring(held and held:getFullType()))
        end)
    end)
    BM.drop = act("put_generator_down", function(ctx, p)
        local it = p:getPrimaryHandItem()
        ISTimedActionQueue.add(ISDropWorldItemAction:new(p, it, getCell():getGridSquare(bsite("gx"), bsite("gy"), 0), 0.5, 0.5,
            0, 0, false))
    end, 180)
    BM.afterDrop = probeB("after_generator_put_down", function(m)
        check("diesel_generator_put_down_as_itself", function()
            return m.gFound == "true" and m.gType == "TLG.DieselGenerator" and m.gProfile == "generator_ci_bio"
                and has(m.gSide, "biodiesel"), string.format("found=%s type=%s profile=%s %s", tostring(m.gFound),
                tostring(m.gType), tostring(m.gProfile), tostring(m.gSide))
        end)
    end)

    -- The repair of a generator that lost its sprite (0.3.2), on the server
    -- with this client connected: the server takes the sprite away and
    -- runs the mod's LoadGridsquare handler on the generator's square.
    local function clientSprite()
        local g = bgen()
        local name, tex = "none", nil
        pcall(function() name = tostring(g:getSprite():getName()) end)
        pcall(function() tex = g:getSprite():getTextureForCurrentFrame(g:getDir()) end)
        return name, tex
    end
    local function spriteCall(step, onAnswer)
        return call("generator_sprite_" .. step, "sprite_repair", function()
            return { gx = bsite("gx"), gy = bsite("gy"), step = step }
        end, "sprite_repair", onAnswer)
    end
    BM.strip = spriteCall("strip", function(m)
        BM.stripped = m
        report():line("OBS  MP.generator_sprite_strip server: found=%s by %s ok=%s sent=%s sprite %s -> %s", tostring(m.found),
            tostring(m.how), tostring(m.ok), tostring(m.sent), tostring(m.before), tostring(m.after))
    end)
    BM.stripSeen = once("mp_generator_sprite_stripped_here", function()
        local name, tex = clientSprite()
        BM.strippedHere = name
        report():line("OBS  MP.generator_sprite_strip this client then sees sprite %s, picture %s", name, tostring(tex ~= nil))
    end)
    BM.repair = spriteCall("repair", function(m)
        check("server_gives_the_generator_its_sprite_back", function()
            local s = BM.stripped or {}
            return s.after ~= "tlg_generators_01_0" and m.ok == "true" and m.after == "tlg_generators_01_0",
                string.format("server: stripped to %s (%s); the handler ok=%s err=%s, sprite %s -> %s", tostring(s.after),
                    tostring(s.how), tostring(m.ok), tostring(m.err), tostring(m.before), tostring(m.after))
        end)
    end)
    BM.repairSeen = once("mp_generator_sprite_back_here", function()
        local name, tex = clientSprite()
        check("client_sees_the_generator_sprite_back", function()
            return name == "tlg_generators_01_0" and tex ~= nil, string.format(
                "this client saw %s after the strip and sees %s now, picture %s", tostring(BM.strippedHere), name,
                tostring(tex ~= nil))
        end)
    end)

    BM.enter = act("enter_van", function(ctx, p) ISVehicleMenu.onEnter(p, van(), 0) end, 120)
    BM.start = startCar("start_van", van)
    BM.status = request("van_status", "status", function()
        return BM.site and { target = { kind = "vehicle", id = bsite("van") } }
    end, function(r)
        report():line("OBS  MP.van_status reply: %s primary=%s total=%s compatible=%s", brief(r), tostring(r.primary),
            tostring(r.total), tostring(r.evaluation and r.evaluation.compatible))
        check("van_holds_diesel", function()
            return r.ok == true and r.primary == "diesel" and r.evaluation ~= nil and r.evaluation.compatible == true, brief(r)
        end)
    end)
    BM.afterStart = probeB("after_van_start", function(m)
        check("van_starts_on_diesel", function()
            -- The tank has no record on the server yet: nothing has written
            -- one (launch 247 asked for it here); the status above read it.
            return m.vanEngine == "true" and m.vanProfile == "engine_ci_stock",
                string.format("engine=%s profile=%s %s", tostring(m.vanEngine), tostring(m.vanProfile), tostring(m.vanSide))
        end)
    end)
    BM.exit = act("leave_van", function(ctx, p) ISVehicleMenu.onExit(p) end, 180)

    BM.label = request("pump_label", "status", function()
        local p = bpump()
        return p and { target = TLG.Authority.Resolver.refForObject(p, "pump") }
    end, function(r)
        local context = ISContextMenu.get(0, 100, 100)
        TLG.UI.FuelMenu.fillWorld(0, context, { bpump() }, false)
        local opt = context:getOptionFromName(getText("ContextMenu_TLG_PumpProduct"))
        context:setVisible(false)
        report():line("OBS  MP.pump_label reply: %s primary=%s total=%s; menu entry=%s", brief(r), tostring(r.primary),
            tostring(r.total), tostring(opt ~= nil))
        check("pump_label_reads_diesel", function() return r.ok == true and r.primary == "diesel" and opt ~= nil, brief(r) end)
    end)
    BM.pumpToCan = act("diesel_pump_to_can", function(ctx, p)
        BM.units0 = bpump():getPipedFuelAmount()
        ISWorldObjectContextMenu.onTakeFuelNew(nil, bpump(), nil, inventoryItem(FU.dCan), 0)
    end, 180)
    BM.afterPump = probeB("after_diesel_pump", function(m)
        local can = inventoryItem(FU.dCan)
        local comp, text = fluids(can)
        check("diesel_from_the_pump_in_the_client_can", function()
            return (comp.diesel or 0) > 1 and (comp.gasoline or 0) == 0 and not can:getFluidContainer():contains(Fluid.Petrol)
                and tonumber(m.pumpUnits) < (BM.units0 or 0) and has(m.cans, "diesel"), string.format(
                "this client's can: %s; server pump units %s (were %s); server cans %s", text, tostring(m.pumpUnits),
                tostring(BM.units0), tostring(m.cans))
        end)
    end)

    MP.stepsA = {
        MP.waitWorld, BM.setup, wait("mp_biodiesel_site_arrives", 300), BM.seen,
        give("give_logs_retort", "Base.Log;Base.Log"), wait("mp_logs_retort_arrive", 120), toMachine("retort"),
        breq("retort_load", "machine.load", "retort", nil, loaded("retort_load", function(r) return near(r.woodKg, 18) end)),
        give("give_logs_barrel", "Base.Log;Base.Log"), wait("mp_logs_barrel_arrive", 120), toMachine("barrel"),
        breq("barrel_load", "machine.load", "barrel", nil, loaded("barrel_load", function(r) return near(r.woodKg, 18) end)),
        give("give_water", "Base.BucketEmpty", { water = "10" }), wait("mp_water_arrives", 120), toMachine("leacher"),
        breq("leacher_load", "machine.load", "leacher", nil, loaded("leacher_load", function(r)
            return near(r.ashKg, 1.485, 1e-6) and near(r.waterL, 2.97, 1e-6)
        end)),
        give("give_oil", string.rep("Base.OilVegetable;", 7)), wait("mp_oil_arrives", 120), toMachine("reactor"),
        breq("reactor_load", "machine.load", "reactor", nil, loaded("reactor_load", function(r)
            return near(r.oilL, 6.3, 1e-6) and near(r.methanolL, 0.945, 1e-6) and near(r.lyeKg, 0.07875, 1e-6)
        end)),
        give("give_log_reactor", "Base.Log"), wait("mp_log_reactor_arrives", 120),
        breq("reactor_firewood", "machine.addFuel", "reactor", nil, function(r)
            check("reactor_firewood", function() return r.ok == true and near(tonumber(r.firebox), 9), brief(r) end)
        end),
        toMachine("wash"),
        breq("wash_load", "machine.load", "wash", nil, loaded("wash_load", function(r)
            return (tonumber(r.crudeL) or 0) > 17 and (tonumber(r.washWaterL) or 0) > 5
        end)),
        toMachine("washDone"), BM.collect, wait("mp_biodiesel_arrives", 180), BM.can,
        toMachine("retortDone"), BM.refused, BM.afterChain,
        giveCan("give_biodiesel_can", { fill = "TLG_Biodiesel", litres = "5" }, "bdCan"), arrived("bdCan"),
        walkTo("mp_walk_to_diesel_generator", function() return bsite("gx") + 1, bsite("gy") end),
        BM.pour, BM.on, BM.afterOn, BM.off, BM.unplug, BM.take, BM.afterTake, BM.drop, BM.afterDrop,
        BM.strip, wait("mp_generator_sprite_strip_arrives", 180), BM.stripSeen,
        BM.repair, wait("mp_generator_sprite_repair_arrives", 180), BM.repairSeen,
        BM.enter, BM.start, BM.status, BM.afterStart, BM.exit,
        giveCan("give_can_for_diesel", { petrol = "0" }, "dCan"), arrived("dCan"),
        walkTo("mp_walk_to_diesel_pump", function() return bsite("px") + 1, bsite("py") end),
        BM.label, BM.pumpToCan, BM.afterPump,
        once("mp_finish_b", function() send("finish", {}) end), MP.finish,
    }
    MP.stepsB = { MP.waitWorld, waitFrom("mp_wait_finish", "finish"), MP.finish }
end

if MP.only == "death" then
    local DE = {}
    local function dId() return DE.id end
    local function line(name, m)
        report():line("OBS  MP.%s server: where=%s state=%s pause=%s site=%s listed=%s t=%.4f done=%.4f now=%.4f vessels=%s held=%s landing=%s",
            name, tostring(m.where), tostring(m.state), tostring(m.pause), tostring(m.site), tostring(m.listed),
            tonumber(m.t) or -1, tonumber(m.done) or -1, tonumber(m.now) or -1, tostring(m.vessels), tostring(m.held),
            tostring(m.landing))
    end
    local function probeDeath(name, judge)
        return call(name, "probe_vessel", function() return { id = DE.id, pid = DE.pid } end, "probe_vessel", function(m)
            line(name, m)
            judge(m)
        end)
    end
    DE.spawn = call("spawn_death_vessel", "spawn", function()
        local x, y = S.spot(3)
        return { item = V, x = x, y = y, batch = "1" }
    end, "spawned", function(m)
        DE.id = tonumber(m.id)
        report():line("OBS  MP.death vessel %s spawned with its batch %s", tostring(m.id), tostring(m.batch))
    end)
    -- Taken off the floor as a double-click in the loot window takes it
    -- (MPHarness.lua takeHeavy): A stands on its square.
    DE.take = { name = "mp_death_take", timeout = 2400, fn = function(ctx, ticks)
        local p = player()
        if ticks == 1 then
            pcall(function() getPlayerLoot(0):refreshBackpacks() end)
            return nil
        end
        if ticks == 60 then
            pcall(function() getPlayerLoot(0):refreshBackpacks() end)
            local x, y = S.spot(3)
            local _, listed = h.floorListing(V)
            local item = listed or floorItem(x, y, V)
            if not item then
                report():line("FAIL MP.death_take_%s :: no vessel on its square", MP.role)
                return true
            end
            ISInventoryPaneContextMenu.equipHeavyItem(p, item)
            ctx.queued = ticks
            return nil
        end
        if not ctx.queued then return nil end
        if ticks - ctx.queued < 60 or not TLGH.Steps.actionsIdle(p) then return nil end
        ctx.idle = ctx.idle or ticks
        if ticks - ctx.idle < 120 then return nil end
        local held = p:getPrimaryHandItem()
        DE.pid = held and held:getModData().tlgProc and held:getModData().tlgProc.id
        check("death_vessel_in_both_hands", function()
            return h.inBothHands(p, V), string.format("primary=%s record %s", tostring(held and held:getFullType()),
                tostring(DE.pid))
        end)
        return true
    end }
    DE.carried = probeDeath("death_carried", function(m)
        check("death_vessel_carried_on_server", function()
            return m.where == "inventory tlga both hands" and m.state == "Paused" and m.pause == "not_placed",
                "see the server's line above"
        end)
        -- The server's equip events told the mod (Machines.onHands).
        check("death_mod_knows_the_vessel_in_hand", function() return m.held == "tlga", "held=" .. tostring(m.held) end)
    end)
    -- A tells B where it stands, then dies (Kill, as the single-player
    -- successor run; the server kills it if the client's kill does not take).
    DE.die = { name = "mp_death_die", timeout = 3600, fn = function(ctx, ticks)
        local p = player()
        if ticks == 1 then
            local sq = p:getSquare()
            DE.x, DE.y = sq:getX(), sq:getY()
            send("dying", { id = DE.id, pid = DE.pid, x = DE.x, y = DE.y })
            return nil
        end
        if ticks == 120 then
            local held = p:getPrimaryHandItem()
            report():line("OBS  MP.death A dies at %d,%d carrying %s", DE.x, DE.y, tostring(held and held:getFullType()))
            p:setGodMod(false)
            local ok, err = pcall(function() p:Kill(nil) end)
            if not ok then
                report():line("OBS  MP.death Kill(nil) failed (%s); health set to 0", tostring(err))
                p:setHealth(0)
            end
            ctx.killed = ticks
            return nil
        end
        if not ctx.killed then return nil end
        if not p:isDead() and ticks - ctx.killed == 600 then
            report():line("OBS  MP.death not dead 600 ticks after the client's kill: the server is asked")
            send("kill", { tag = "kill" })
        end
        if not p:isDead() and ticks - ctx.killed < 1800 then return nil end
        report():line("OBS  MP.death A dead=%s %d ticks after the kill; post-death screen=%s", tostring(p:isDead()),
            ticks - ctx.killed, tostring(ISPostDeathUI.instance ~= nil and ISPostDeathUI.instance[0] ~= nil))
        check("death_a_died", function() return p:isDead(), "dead=" .. tostring(p:isDead()) end)
        return true
    end }
    MP.stepsA = {
        MP.waitWorld, waitFrom("mp_wait_b", "hello"), DE.spawn, wait("mp_death_vessel_lands", 120),
        walkTo("mp_walk_onto_vessel", S.spot(3)), DE.take, DE.carried, walkTo("mp_walk_carrying", S.spot(1)),
        wait("mp_carried_a_while", 300), DE.die, waitFrom("mp_wait_finish", "finish", nil, 36000), MP.finish,
    }

    -- B: watches from three squares off the row.
    DE.atDeath = probeDeath("death_right_before", function(m)
        DE.now0 = tonumber(m.now)
        check("death_carried_before_the_death", function()
            return m.state == "Paused" and m.pause == "not_placed", "see the server's line above"
        end)
    end)
    DE.landed = probeDeath("death_landed", function(m)
        DE.site, DE.t1, DE.done1 = m.site, tonumber(m.t), tonumber(m.done)
        local since = (DE.t1 or -1) - (DE.now0 or 0)
        report():line("OBS  MP.death the record's time %.4f game h after the probe right before the death", since)
        -- Run 209 compared the floor with the record's site, which the
        -- put-down moves: a vessel on the floor with a carried record failed
        -- both checks. The site belongs to the put-down's.
        check("death_vessel_on_the_floor", function()
            return string.find(m.where or "", "^floor ") ~= nil, "where=" .. tostring(m.where)
        end)
        check("death_put_down_from_the_death", function()
            return m.state == "Processing" and m.pause == "none" and m.where == "floor " .. tostring(m.site)
                and m.listed == m.site and since >= 0 and since <= 0.25,
                string.format("state=%s pause=%s site=%s listed=%s; record time %.4f h after the probe before the death",
                    tostring(m.state), tostring(m.pause), tostring(m.site), tostring(m.listed), since)
        end)
    end)
    DE.status = status("death_status", dId, function(r)
        check("death_status_processing", function() return r.ok == true and r.state == "Processing", "see the reply above" end)
    end)
    -- Work since the death (the probe right before it), against the game
    -- time from the death to this read.
    DE.worked = probeDeath("death_worked", function(m)
        local dt = (tonumber(m.t) or 0) - (DE.now0 or 0)
        local dw = (tonumber(m.done) or 0) - (DE.done1 or 0)
        check("death_batch_works_from_the_death", function()
            return m.state == "Processing" and dt > 0.2 and dw >= 0.5 * dt and dw <= dt + 0.002,
                string.format("%.4f h of work over the %.4f game h from the death to this read", dw, dt)
        end)
    end)
    MP.stepsB = {
        MP.waitWorld, walkTo("mp_walk_to_watch", S.CX - 2, S.CY + 3), once("mp_hello", function() send("hello", {}) end),
        waitFrom("mp_wait_dying", "dying", function(m)
            DE.id, DE.pid, DE.x, DE.y = tonumber(m.id), m.pid, tonumber(m.x), tonumber(m.y)
        end),
        DE.atDeath, wait("mp_death_lands", 900), DE.landed,
        walkTo("mp_walk_to_vessel", function()
            local x, y = string.match(DE.site or "", "^(%-?%d+),(%-?%d+)$")
            x, y = tonumber(x) or DE.x, tonumber(y) or DE.y
            return x - 1, y + 1
        end),
        wait("mp_death_vessel_works", 1800), DE.status, DE.worked,
        once("mp_finish_a", function() send("finish", {}) end), MP.finish,
    }
end
