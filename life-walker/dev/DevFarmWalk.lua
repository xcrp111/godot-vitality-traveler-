-- DevFarmWalk.lua — 农场行走与走近交互
local Config = require "Config"
local Save = require "Save"
local S = require "State"
local Farm = require "Farm"
local FarmArt = require "FarmArt"
local FarmWalk = require "FarmWalk"

local fails = 0
local function check(name, cond, detail)
    if cond then print("[Walk] OK   " .. name)
    else fails = fails + 1; print("[Walk] FAIL " .. name .. (detail and (" — " .. tostring(detail)) or "") ) end
end

function Start()
    S.data = Save.Fresh()
    local d = S.data
    d.stageCleared = 5
    local f = Farm.Ensure(d)
    f.landCount = 9
    f.seeds.ice = 5
    Farm.Plant(d, 1, "ice")

    FarmArt.Layout(720)
    FarmWalk.Reset()
    S.input.x, S.input.y = 0, 0
    check("出生在木门附近", math.abs(FarmWalk.x - 700) < 1 and math.abs(FarmWalk.y - 840) < 1)

    -- 走到水井
    FarmWalk.WalkToDesign(FarmWalk.ToDesign(152, 352))
    for _ = 1, 200 do FarmWalk.Update(1 / 60) end
    check("走到了水井", FarmWalk.nearest and FarmWalk.nearest.id == "well",
        FarmWalk.nearest and FarmWalk.nearest.id)

    -- 井边浇水：第 1 块地处于生长期，浇水后阶段剩余时间变短
    local before = Farm.PlotInfo(d, 1).remain
    FarmWalk.Interact()
    local after = Farm.PlotInfo(d, 1).remain
    check("水井浇水生效", after < before, string.format("%.0f -> %.0f", before, after))

    -- 走到摊位
    FarmWalk.WalkToDesign(FarmWalk.ToDesign(1150, 380))
    for _ = 1, 260 do FarmWalk.Update(1 / 60) end
    check("走到了摊位", FarmWalk.nearest and FarmWalk.nearest.id == "stall",
        FarmWalk.nearest and FarmWalk.nearest.id)
    S.farmTab = 1
    FarmWalk.Interact()
    check("摊位打开商店页", S.farmTab == 3, S.farmTab)

    -- 走到地块旁：空地播种
    FarmWalk.WalkToDesign(FarmWalk.ToDesign(608, 474))
    for _ = 1, 260 do FarmWalk.Update(1 / 60) end
    check("走到了第 5 块地", FarmWalk.nearest and FarmWalk.nearest.id == "plot")
    FarmWalk.Interact()
    check("空地交互打开播种面板", S.farmPlot == 5, S.farmPlot)

    -- 木门退出
    FarmWalk.WalkToDesign(FarmWalk.ToDesign(700, 880))
    for _ = 1, 300 do FarmWalk.Update(1 / 60) end
    check("走到了木门", FarmWalk.nearest and FarmWalk.nearest.id == "gate",
        FarmWalk.nearest and FarmWalk.nearest.id)
    S.farm = true
    FarmWalk.Interact()
    check("木门离开农场", S.farm == false, S.farm)

    print(string.format("[Walk] done, failures = %d", fails))
end
