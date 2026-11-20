-- DevClick.lua — 点击系统回归（PointerDown/Up + 区域命中 + 取消）
local Config = require "Config"
local UI = require "UI"
local S = require "State"

local fails = 0
local function check(name, cond, detail)
    if cond then print("[Click] OK   " .. name)
    else fails = fails + 1
        print("[Click] FAIL " .. name .. (detail and (" — " .. tostring(detail)) or "")) end
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
    S.font = nvgCreateFont(S.ctx, "sans", "Fonts/MiSans-Regular.ttf")

    -- 画一帧把区域登记进 S.regions
    S.regions = {}
    UI.BeginDesign()
    local fired = false
    UI.Button("t_btn", 100, 100, 120, 40, "测试", function() fired = true end)
    UI.EndDesign()
    check("按钮登记了点击区域", #S.regions == 1, #S.regions)

    local hit = UI.Hit(150, 120)
    check("命中判定正确", hit == true, hit)
    check("空白处不命中", UI.Hit(500, 500) == false)

    local down = UI.PointerDown(150, 120, 0)
    check("按下被区域吃掉", down == true)
    UI.PointerUp(150, 120)
    check("原地抬手触发点击", fired == true)

    -- 移出后抬手不触发
    fired = false
    UI.PointerDown(150, 120, 0)
    UI.PointerUp(600, 600)
    check("移出后抬手不触发", fired == false)

    -- 取消后不触发
    UI.PointerDown(150, 120, 0)
    UI.PointerCancel()
    UI.PointerUp(150, 120)
    check("取消后不触发", fired == false)

    print(string.format("[Click] done, failures = %d", fails))
end
