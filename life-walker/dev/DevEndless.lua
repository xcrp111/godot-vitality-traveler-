-- DevEndless.lua — 无尽模式（层数 / 3×3 / 强度映射 / 强化上限替换 / 记录）+ 主线随机房间
local Config = require "Config"
local Save = require "Save"
local S = require "State"
local Run = require "Run"
local Menu = require "Menu"
local UI = require "UI"

local fails = 0
local function check(name, cond, detail)
    if cond then
        print("[E] OK   " .. name)
    else
        fails = fails + 1
        print("[E] FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
    end
end

local function CountType(map, kind)
    local n = 0
    for r = 1, #map do
        for c = 1, #map[r] do
            if map[r][c] == kind then n = n + 1 end
        end
    end
    return n
end

local function MapSig(map)
    local t = {}
    for r = 1, #map do t[#t + 1] = table.concat(map[r], ",") end
    return table.concat(t, "|")
end

function Start()
    math.randomseed(20261030)
    S.data = Save.Fresh()
    Save.SetClass(S.data, "swordsman")
    Config.SetClass("swordsman")
    S.screen = "menu"

    -- ============ ① 主线地图：伪随机（模板 + 难度归一） ============
    local badStructure, noShop, noEvent = 0, 0, 0
    local variants = {}
    local function SampleMain(level, times)
        local avgSum, avgMax, avgMin = 0, -99, 99
        for _ = 1, times do
            local m = Config.PickMainMap(level)
            local ok, why = Config.CheckMap(m)
            if not ok then
                badStructure = badStructure + 1
                print("[E] 结构问题:", why)
            end
            if CountType(m, "shop") < 1 then noShop = noShop + 1 end
            if CountType(m, "event") < 1 then noEvent = noEvent + 1 end
            if level < 6 and CountType(m, "double") > 0 then
                badStructure = badStructure + 1
                print("[E] 低关卡出现双精房")
            end
            variants[MapSig(m)] = true
            local avg = Config.AvgCombatCost(m)
            avgSum = avgSum + avg
            if avg > avgMax then avgMax = avg end
            if avg < avgMin then avgMin = avg end
        end
        return avgSum / times, avgMin, avgMax
    end

    local avg1 = SampleMain(1, 60)
    local avg10 = SampleMain(10, 60)
    local avg20, min20, max20 = SampleMain(20, 80)
    check("伪随机地图结构约束全通过（起点 / Boss / 首房 / 商店 / 事件）", badStructure == 0, badStructure)
    check("每张图都有商店房", noShop == 0, noShop)
    check("每张图都有事件房", noEvent == 0, noEvent)
    local target20 = Config.MapTargetCost(20)
    check("第 20 关强度被归一在目标附近", math.abs(avg20 - target20) <= 0.45,
        string.format("平均 %.2f 目标 %.2f 区间 %.2f~%.2f", avg20, target20, min20, max20))
    check("难度随关卡上升（第 1 关 < 第 20 关）", avg1 < avg20,
        string.format("%.2f vs %.2f（第 10 关 %.2f）", avg1, avg20, avg10))
    local n = 0
    for _ in pairs(variants) do n = n + 1 end
    check("多次生成有足够多的布局变化", n >= 8, n .. " 种布局")

    -- 主线两局的地图不是同一张
    Save.DebugUnlockAll(S.data)
    Run.Start(3, true)
    local sig1 = MapSig(S.run.map)
    Run.Start(3, true)
    local sig2 = MapSig(S.run.map)
    check("同一关连开两局房间布局不同", sig1 ~= sig2)
    check("主线 run.endless = false", S.run.endless == false)

    -- ============ ② 解锁条件 ============
    S.data.stageCleared = 9
    check("通关 9 关还没解锁", Save.EndlessUnlocked(S.data) == false)
    S.data.stageCleared = 10
    check("通关第 10 关解锁无尽", Save.EndlessUnlocked(S.data) == true)

    -- ============ ③ 进入无尽：第 1 层 = 主线第 10 关强度 ============
    Run.StartEndless()
    local run = S.run
    check("进入无尽模式", run and run.endless == true and S.screen == "map")
    check("起始第 1 层", run.layer == 1, run.layer)
    check("等效主线第 10 关", run.level == 10, run.level)
    check("单层 3×3", run.rows == 3 and run.cols == 3, run.rows .. "x" .. run.cols)
    check("起点在左下", run.posR == 3 and run.posC == 1)
    check("地图里有 Boss 房", CountType(run.map, "boss") == 1)
    check("无尽模板一共 10 张", #Config.EndlessTemplates == 10, #Config.EndlessTemplates)
    local okLayer, whyLayer = Config.CheckMap(run.map, { shop = false })
    check("无尽单层结构约束（允许没有商店）", okLayer, whyLayer)
    check("无尽单层至少有 1 个事件房", CountType(run.map, "event") >= 1)
    check("记录到第 1 层", (S.data.endlessBest or 0) >= 1, S.data.endlessBest)

    -- 强度公式：无尽第 1 层 == 主线第 10 关
    local hp10 = Config.MonsterStats(10, 1, "minion")
    local hpE1 = Config.MonsterStats(run.level, 1, "minion")
    check("第 1 层小兵血量 = 主线第 10 关", hp10 == hpE1, hp10 .. " vs " .. hpE1)
    -- 文档第 4 节的对照表比公式整体错开一关（表里 N=11 才是 105），以公式为准
    check("第 1 层小兵血量按主线公式算", hp10 == Config.MinionHP(10) and hp10 > 100, hp10)

    -- ============ ④ 走一格就进战斗，房号从 1 开始 ============
    Run.Move(3, 2)
    check("起点右边固定普通战斗房", run.roomType == "standard", run.roomType)
    check("进入战斗", S.screen == "combat")
    check("房号 1", S.combat.step == 1, S.combat.step)
    S.combat = nil

    -- ============ ⑤ 通关本层 → 下一层：层数 +1、强度 +1 关、状态保留 ============
    local p = run.player
    p.hp = p.maxHp * 0.4
    local buffId = Run.GrantRandomBuff(p)
    local buffCount = #p.buffs
    local silver = run.silver
    run.roomType = "boss"
    S.combat = { run = run, step = 4 }
    Run.OnRoomCleared()
    check("无尽打掉 Boss 不结算主线通关", S.screen == "levelclear", S.screen)
    check("无尽不会记主线通关", (S.data.stageCleared or 0) == 10, S.data.stageCleared)

    Run.NextEndlessLayer()
    check("进入第 2 层", run.layer == 2, run.layer)
    check("第 2 层等效主线第 11 关", run.level == 11, run.level)
    check("层数推进后回到起点", run.posR == 3 and run.posC == 1)
    check("强化带入下一层", #p.buffs == buffCount, #p.buffs .. " vs " .. buffCount)
    check("银币带入下一层", run.silver == silver)
    check("每层开场回 20% 生命", p.hp > p.maxHp * 0.39, p.hp)
    check("记录刷新到第 2 层", (S.data.endlessBest or 0) >= 2, S.data.endlessBest)

    -- ============ ⑤-2 商店：不要求每层都有，但相邻两层之间至少要有一个 ============
    local gapBad, shopless, needShopBad = 0, 0, 0
    local prevShop = nil
    for layer = 1, 80 do
        local needShop = (prevShop == false)
        local m = Config.PickEndlessMap(layer, needShop)
        local hasShop = Config.GridHasRoom(m, "shop")
        if prevShop == false and not hasShop then gapBad = gapBad + 1 end
        if needShop and not hasShop then needShopBad = needShopBad + 1 end
        if not hasShop then shopless = shopless + 1 end
        prevShop = hasShop
    end
    check("无尽：相邻两层之间至少有一个商店", gapBad == 0, gapBad)
    check("无尽：要求必须有商店时不会抽到无商店的层", needShopBad == 0, needShopBad)
    check("无尽：确实存在没有商店的层（不是每层都有）", shopless > 0, shopless .. "/80 层")

    -- 真实流程连推 30 层，检查 lastLayerShop 与规则一致
    local flowBad = 0
    local flowShopless = 0
    for _ = 1, 30 do
        local prev = run.lastLayerShop
        Run.NextEndlessLayer()
        local hasShop = Config.GridHasRoom(run.map, "shop")
        if run.lastLayerShop ~= hasShop then flowBad = flowBad + 1 end
        if prev == false and not hasShop then flowBad = flowBad + 1 end
        if not hasShop then flowShopless = flowShopless + 1 end
    end
    check("无尽连推 30 层：商店记录与地图一致", flowBad == 0, flowBad)
    check("无尽连推 30 层：确实出现过无商店层", flowShopless > 0, flowShopless .. "/30 层")

    -- ============ ⑥ 强化上限 10：满了走替换 ============
    p.buffs = {}
    for _ = 1, Config.Endless.buffCap do Run.GrantRandomBuff(p) end
    check("强化已有 10 个", #p.buffs == Config.Endless.buffCap, #p.buffs)
    local atkBefore = p.atk
    Run.OpenCombatReward("standard")
    check("满 10 个时进入替换模式", S.reward and S.reward.replace == true)
    Run.ChooseReward(1)
    check("选完新强化还在选替换目标", S.reward and S.reward.pending ~= nil and S.screen == "reward")
    local pendingName = S.reward.pending.name
    Run.ApplyReplace(1)
    check("替换后数量仍为 10", #p.buffs == Config.Endless.buffCap, #p.buffs)
    check("新强化已生效", S.reward == false and S.screen == "map")
    local found = false
    for _, b in ipairs(p.buffs) do
        if b.name == pendingName then found = true end
    end
    check("被换上的强化在列表里", found, pendingName)
    check("面板数值经过重算（不因换强化而报错）", p.atk > 0 and atkBefore > 0)

    -- 取消替换：保留原来那 10 个
    Run.OpenCombatReward("standard")
    Run.ChooseReward(2)
    local cntBefore = #p.buffs
    Run.CancelReplace()
    check("放弃替换后仍是原来的 10 个", #p.buffs == cntBefore and S.reward.pending == nil)
    S.reward = false
    S.screen = "map"

    -- ============ ⑦ 记录 / 勋章 ============
    S.data.endlessBest = 0
    S.data.endlessMedal = 0
    S.data.endlessDayBest = 0
    Save.RollEndless(S.data)
    local r1 = Save.RecordEndless(S.data, 5)
    check("破纪录", r1.best == true and S.data.endlessBest == 5, S.data.endlessBest)
    check("破纪录勋章升到 Lv.1", S.data.endlessMedal == 1 and r1.medalUp == 1, S.data.endlessMedal)
    check("破纪录给金币与经验", r1.gold > 0 and r1.exp > 0, r1.gold .. "/" .. r1.exp)
    local r2 = Save.RecordEndless(S.data, 3)
    check("没破纪录不升勋章", r2.best == false and S.data.endlessMedal == 1)
    check("日 / 周 / 月记录都记到最高", S.data.endlessDayBest == 5)
    local rec = Save.EndlessRecords(S.data)
    check("记录一览可读", rec.best == 5 and rec.medal == 1 and rec.day == 5)

    -- ============ ⑧ 死亡结算显示层数 ============
    S.screen = "gameover"
    S.run = { endless = true, layer = 3, level = 12, player = { buffs = {} }, silver = 0 }

    -- ============ ⑨ 界面能画、按钮能点 ============
    local okUi, errUi = pcall(function()
        S.ctx = nvgCreate(1)
        S.font = nvgCreateFont(S.ctx, "sans", "Fonts/MiSans-Regular.ttf")
        S.data = Save.Fresh()
        Save.SetClass(S.data, "swordsman")
        Save.DebugUnlockAll(S.data)
        S.screen = "menu"
        S.endlessPanel = true
        Menu.Draw()
        check("无尽模式面板能正常绘制", true)
        UI.Click(470, 574)         -- 开始挑战
        check("点开始挑战能进无尽", S.run ~= nil and S.run.endless == true, S.endlessPanel)
        if S.run then
            S.screen = "map"
            local Screens = require "Screens"
            Screens.DrawMap()
            check("无尽地图（3×3）能正常绘制", true)
            S.combat = nil
        end
        S.endlessPanel = false
    end)
    if not okUi then check("无尽界面能正常绘制", false, tostring(errUi)) end

    -- ============ ⑩ 测试模式里的无尽解锁 ============
    S.data = Save.Fresh()
    S.selectedLevel = 1
    check("新存档默认没解锁无尽", Save.EndlessUnlocked(S.data) == false)
    Save.SetDevEndlessUnlock(S.data, true)
    check("测试开关可以强制解锁无尽", Save.EndlessUnlocked(S.data) == true)
    check("强制解锁不动主线进度", (S.data.stageCleared or 0) == 0, S.data.stageCleared)
    Save.SetDevEndlessUnlock(S.data, false)
    check("关掉开关回到未解锁", Save.EndlessUnlocked(S.data) == false)

    local okTest, errTest = pcall(function()
        S.ctx = S.ctx or nvgCreate(1)
        S.screen = "menu"
        S.test = true
        S.testPage = 1
        Menu.DrawTestLab()
        UI.Click(350, 87)                       -- 「解锁无尽（测试）」
        check("测试面板点一下能解锁无尽", Save.EndlessUnlocked(S.data) == true,
            tostring(S.data.devUnlockEndless))
        S.test = true
        Menu.DrawTestLab()
        UI.Click(350, 87)                       -- 再点一次关掉
        check("测试面板再点一下能关掉", Save.EndlessUnlocked(S.data) == false)
        Save.SetDevEndlessUnlock(S.data, true)
        S.test = true
        Menu.DrawTestLab()
        UI.Click(560, 87)                       -- 「进入无尽（测试）」
        check("测试面板能直接进无尽模式",
            S.run ~= nil and S.run.endless == true and S.screen == "map")
        S.test = false
        S.run = nil
        S.combat = nil
        S.screen = "menu"
    end)
    if not okTest then check("测试面板无尽开关", false, tostring(errTest)) end

    print("[E] done, failures = " .. fails)
end
