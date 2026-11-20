-- DevFarmStage.lua — 测试按钮「下一阶段」逻辑
local Save = require "Save"
local S = require "State"
local Farm = require "Farm"

local fails = 0
local function check(name, cond, detail)
    if cond then print("[Stage] OK   " .. name)
    else fails = fails + 1; print("[Stage] FAIL " .. name .. (detail and (" — " .. tostring(detail)) or "")) end
end

function Start()
    S.data = Save.Fresh()
    local d = S.data
    d.stageCleared = 5
    local f = Farm.Ensure(d)
    f.seeds.ice = 5
    check("种下冰晶草", Farm.Plant(d, 1, "ice") == true)
    local i1 = Farm.PlotInfo(d, 1)
    check("初始为发芽期", i1.stage == 1, i1.stageName)

    check("推进一次", Farm.DebugNextStage(d, 1) == 1)
    local i2 = Farm.PlotInfo(d, 1)
    check("进入生长期", i2.stage == 2, i2.stageName)

    check("再推进一次", Farm.DebugNextStage(d, 1) == 1)
    check("进入成熟期（第三段）", Farm.PlotInfo(d, 1).stage == 3)
    check("再推进一次直接可收获", Farm.DebugNextStage(d, 1) == 1)
    local i3 = Farm.PlotInfo(d, 1)
    check("状态为可收获", i3.status == "mature", i3.status)

    check("成熟后不再推进", Farm.DebugNextStage(d, 1) == 0)

    -- 不选中时推进所有生长中的地
    Farm.Plant(d, 2, "ice")
    Farm.Plant(d, 3, "ice")
    check("全部推进 = 2 块", Farm.DebugNextStage(d, nil) == 2)
    check("只影响生长中的", Farm.PlotInfo(d, 2).stage == 2 and Farm.PlotInfo(d, 3).stage == 2)

    print(string.format("[Stage] done, failures = %d", fails))
end
