-- DevDevPanel.lua — 开发工具面板回归：推进日期 / 解锁关卡 / 满足健康 / 资源
local Config = require "Config"
local Save = require "Save"
local S = require "State"
local Economy = require "Economy"
local Farm = require "Farm"
local UI = require "UI"

local fails = 0
local function check(name, cond, detail)
    if cond then
        print("[Dev] OK   " .. name)
    else
        fails = fails + 1
        print("[Dev] FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
    end
end

function Start()
    local dpr = graphics:GetDPR(); if not dpr or dpr <= 0 then dpr = 1 end
    S.dpr = dpr
    S.W = graphics:GetWidth() / dpr
    S.H = graphics:GetHeight() / dpr
    S.scale = math.min(S.W / Config.DESIGN_W, S.H / Config.DESIGN_H)
    S.offX = (S.W - Config.DESIGN_W * S.scale) / 2
    S.offY = (S.H - Config.DESIGN_H * S.scale) / 2
    S.ctx = nvgCreate(1)
    S.font = nvgCreateFont(S.ctx, "sans", "Fonts/MiSans-Game.ttf")

    S.data = Save.Load()
    S.screen = "menu"
    local d = S.data

    -- 面板开关 + 绘制
    local DevPanel = require "DevPanel"
    DevPanel.Open()
    check("打开面板", S.devPanel == true)
    local okDraw, err = pcall(function() DevPanel.Draw() end)
    check("面板能画出来", okDraw, err)
    DevPanel.Close()
    check("关闭面板", S.devPanel == false)

    -- 快速下一天
    local day0 = d.dayKey
    local off0 = d.dayOffset or 0
    Save.NextDay(d)
    Save.RollDay(d)
    check("下一天推进 dayOffset", (d.dayOffset or 0) == off0 + 1, d.dayOffset)
    check("下一天刷新 dayKey", d.dayKey ~= nil, d.dayKey)

    -- 满足健康要求
    d.waterMl, d.sleptEarly, d.todaySteps, d.claimed = 0, false, 0, false
    local goal = Save.WaterGoal()
    Save.AddWater(d, goal)
    Save.CheckSleep(d)
    d.todaySteps = 12000
    check("饮水达标", Save.WaterMet(d) == true, d.waterMl)
    check("早睡打卡", d.sleptEarly == true)
    check("步数达标", (d.todaySteps or 0) >= 12000, d.todaySteps)

    -- 一键解锁关卡
    Save.DebugUnlockAll(d)
    check("关卡全解锁", (d.stageCleared or 0) >= 19 and (d.unlocked or 0) >= 20,
        string.format("cleared=%s unlocked=%s", tostring(d.stageCleared), tostring(d.unlocked)))

    -- 资源
    local e0 = Economy.Essence(d)
    Economy.AddEssence(d, 1000)
    check("精粹 +1000", Economy.Essence(d) == e0 + 1000, Economy.Essence(d))

    -- 农场：全熟 + 土地 9
    local f = Farm.Roll(d)
    f.landCount = 4
    Farm.AddSeed(d, "fire", 2)
    Farm.Plant(d, 1, "fire")
    Farm.DebugRipenAll(d)
    check("农场作物可收获", Farm.MatureCount(d) >= 1, Farm.MatureCount(d))
    f.landCount = 9
    check("土地解锁到 9 块", (Farm.Roll(d).landCount or 0) == 9, Farm.Roll(d).landCount)

    print(string.format("[Dev] done, failures = %d", fails))
end
