-- DevHealth.lua — 健康行为（维度二）：喝水 / 早睡 / 久坐提醒 / 冥想
local Config = require "Config"
local Save = require "Save"
local S = require "State"
local Run = require "Run"
local Menu = require "Menu"
local UI = require "UI"

local fails = 0
local function check(name, cond, detail)
    if cond then
        print("[H] OK   " .. name)
    else
        fails = fails + 1
        print("[H] FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
    end
end

function Start()
    S.data = Save.Fresh()
    Save.SetClass(S.data, "swordsman")
    Config.SetClass("swordsman")
    S.screen = "menu"

    -- ============ ① 饮水 → 全局基础生命 +10% ============
    local baseHp = Config.ClassStats(10)
    check("初始没喝水", Save.WaterMl(S.data) == 0)
    Save.AddWater(S.data)
    check("打卡一杯 +250ml", Save.WaterMl(S.data) == Config.Health.waterStepMl, Save.WaterMl(S.data))
    check("没达标", Save.WaterMet(S.data) == false)
    local p0 = Run.NewPlayer(10)
    check("没达标时生命不变", p0.maxHp == baseHp, p0.maxHp .. " vs " .. baseHp)

    for _ = 1, 10 do Save.AddWater(S.data) end
    check("喝满达标", Save.WaterMet(S.data), Save.WaterMl(S.data))
    local p1 = Run.NewPlayer(10)
    local expect = math.floor(baseHp * (1 + Config.Health.waterHpPct) + 0.5)
    check("达标后基础生命 +10%", p1.maxHp == expect, p1.maxHp .. " vs " .. expect)

    -- ============ ② 早睡 → 次日领取经验加成 ============
    check("记录早睡", Save.CheckSleep(S.data) == true)
    check("同一天不能重复记录", Save.CheckSleep(S.data) == false)
    S.data.claimed = false
    local g, _u, _st, _rg, _rsp, extra = Save.Claim(S.data, 12000)
    check("次日领取多给经验", (extra or 0) > 0, extra)
    check("奖励只结算一次", (S.data.earlySleepPending or false) == false)
    S.data.claimed = false
    local _g2, _u2, _s2, _r2, _p2, extra2 = Save.Claim(S.data, 12000)
    check("再领不会重复给", (extra2 or 0) == 0, extra2)

    -- ============ ③ 久坐提醒 → 移速 +10%（10 分钟） ============
    S.screen = "combat"
    S.restPrompt = nil
    S.data.playSeconds = 0
    Menu.UpdateOverlays(Config.Health.playReminder)
    check("玩满 30 分钟弹提醒", S.restPrompt ~= nil)
    check("弹层吃掉其他输入", Menu.OverlayPointer("down", 5, 5) == true)
    check("弹层期间计时在走", (function()
        local t0 = S.restPrompt.t
        Menu.UpdateOverlays(1)
        return S.restPrompt and S.restPrompt.t > t0
    end)())
    Menu.OverlayPointer("down", 500, 420)      -- 「我起来活动了」
    check("活动后拿到移速加成", Save.BuffLeft(S.data, "moveBuffUntil") > 0, S.restPrompt)
    local p2 = Run.NewPlayer(10)
    check("新局移速 +10%", math.abs(p2.moveSpeed - Config.Class().speed * (1 + Config.Health.restMovePct)) < 0.01,
        p2.moveSpeed)

    -- 跳过则没有加成
    S.data.moveBuffUntil = 0
    S.restPrompt = { t = 0 }
    Menu.OverlayPointer("down", 660, 420)      -- 「继续游戏」
    check("跳过不给加成", Save.BuffLeft(S.data, "moveBuffUntil") == 0)

    -- ============ ④ 冥想 → 冷却缩减 -10%（30 分钟） ============
    S.meditate = { t = 0, dur = 60 }
    check("冥想弹层吃输入", Menu.OverlayPointer("down", 5, 5) == true)
    Menu.UpdateOverlays(30)
    check("没到时间不能领", (S.meditate.t or 0) < 60)
    Menu.OverlayPointer("down", 500, 470)      -- 完成按钮（未到时间）
    check("时间没到不会给加成", Save.BuffLeft(S.data, "cdrBuffUntil") == 0)
    Menu.UpdateOverlays(31)
    Menu.OverlayPointer("down", 500, 470)
    check("冥想完成拿到冷却缩减", Save.BuffLeft(S.data, "cdrBuffUntil") > 0, S.meditate)
    local p3 = Run.NewPlayer(10)
    check("新局冷却缩减 +10%", math.abs(p3.cdr - Config.Health.meditateCdrPct) < 1e-6, p3.cdr)

    -- 放弃冥想不给加成
    S.data.cdrBuffUntil = 0
    S.meditate = { t = 0, dur = 60 }
    Menu.OverlayPointer("down", 760, 470)      -- 「结束（无加成）」
    check("放弃冥想无加成", Save.BuffLeft(S.data, "cdrBuffUntil") == 0 and S.meditate == nil)

    -- ============ ⑤ 加成是跨局/全局的 ============
    check("移速与冷却加成写在存档里（跨局）",
        type(S.data.moveBuffUntil) == "number" and type(S.data.cdrBuffUntil) == "number")

    -- ============ ⑥ 健康任务界面能画、按钮能点 ============
    local okUi, errUi = pcall(function()
        S.ctx = nvgCreate(1)
        S.font = nvgCreateFont(S.ctx, "sans", "Fonts/MiSans-Regular.ttf")
        S.data = Save.Fresh()
        Save.SetClass(S.data, "swordsman")
        Config.SetClass("swordsman")
        S.screen = "menu"
        S.settings = false
        S.healthTasks = true
        Menu.Draw()
        check("健康任务界面能正常绘制", true)
        local before = Save.WaterMl(S.data)
        UI.Click(914, 254)   -- 「喝水 +250ml」
        check("点喝水按钮能打卡", Save.WaterMl(S.data) > before,
            before .. " -> " .. Save.WaterMl(S.data))
        Menu.Draw()
        UI.Click(914, 316)   -- 「记录今天早睡」
        check("点早睡按钮能打卡", S.data.sleptEarly == true)
        Menu.Draw()
        UI.Click(778, 448)   -- 「60 秒」冥想按钮
        check("点冥想能开弹层", S.meditate ~= nil)
        S.meditate = nil
        S.healthTasks = false
    end)
    if not okUi then check("健康任务界面能正常绘制", false, tostring(errUi)) end

    print("[H] done, failures = " .. fails)
end
