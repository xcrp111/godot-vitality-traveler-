-- DevSceneJoy.lua — 主界面触屏方向摇杆回归
-- 校验：显示条件 / 按下吞掉输入 / 拖动产生移动 / 松手归零 / 面板打开时解锁
local Config = require "Config"
local Save = require "Save"
local S = require "State"
local SceneUI = require "SceneUI"

local fails = 0
local function check(name, cond, detail)
    if cond then
        print("[Joy] OK   " .. name)
    else
        fails = fails + 1
        print("[Joy] FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
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
    S.panelMode = nil
    S.scene = nil
    SceneUI.Init()

    local J = SceneUI.JOY

    -- 1) 显示条件
    S.touchMode = nil
    check("PC（未触屏）默认不显示摇杆", SceneUI.JoyVisible() == false)
    S.touchMode = true
    check("触屏后显示摇杆", SceneUI.JoyVisible() == true)
    S.data.sceneJoyDisabled = true
    check("设置里关掉后不显示", SceneUI.JoyVisible() == false)
    S.data.sceneJoyDisabled = nil

    -- 2) 摇杆外点击不吞
    check("摇杆外按下不消费", SceneUI.Pointer("down", 900, 300, 1) == false)
    -- 3) 按下 / 拖动 / 移动
    check("摇杆内按下被吞", SceneUI.Pointer("down", J.x, J.y, 1) == true)
    SceneUI.Pointer("move", J.x + 50, J.y, 1)
    SceneUI.Update(1 / 60)
    check("拖动后 S.input 指向右", (S.input.x or 0) > 0.5 and math.abs(S.input.y or 0) < 0.05,
        tostring(S.input.x) .. "," .. tostring(S.input.y))

    local wx0, wy0 = S.scene.wx, S.scene.wy
    for _ = 1, 30 do SceneUI.Update(1 / 60) end
    check("按住摇杆人物往右走", S.scene.wx > wx0 + 30,
        string.format("%.1f → %.1f", wx0, S.scene.wx))
    check("不会被顺带往上下走", math.abs(S.scene.wy - wy0) < 12,
        string.format("%.1f → %.1f", wy0, S.scene.wy))

    -- 往上拖：纵向移动（先找个上方有空地的点，避免正好顶着建筑）
    local openX, openY
    for x = 200, 1200, 20 do
        if not SceneUI.Blocked(x, 900) and not SceneUI.Blocked(x, 830) then
            openX, openY = x, 900
            break
        end
    end
    check("找到纵向空地", openX ~= nil)
    if openX then S.scene.wx, S.scene.wy = openX, openY end
    SceneUI.Pointer("move", J.x, J.y - 50, 1)
    SceneUI.Update(1 / 60)
    check("往上拖后 S.input 指向上", (S.input.y or 0) < -0.5, tostring(S.input.y))
    local wy1 = S.scene.wy
    for _ = 1, 20 do SceneUI.Update(1 / 60) end
    check("按住摇杆人物往上走", S.scene.wy < wy1 - 20,
        string.format("%.1f → %.1f", wy1, S.scene.wy))

    -- 4) 松手归零
    check("松手被吞", SceneUI.Pointer("up", 0, 0, 1) == true)
    SceneUI.Update(1 / 60)
    local wx2 = S.scene.wx
    check("松手后输入归零", (S.input.x or 0) == 0 and (S.input.y or 0) == 0,
        tostring(S.input.x) .. "," .. tostring(S.input.y))
    for _ = 1, 10 do SceneUI.Update(1 / 60) end
    check("松手后人物停下", math.abs(S.scene.wx - wx2) < 1,
        string.format("%.1f → %.1f", wx2, S.scene.wx))

    -- 5) 面板打开时输入解锁（不能带着摇杆开面板，人物继续走）
    SceneUI.Pointer("down", J.x, J.y, 2)
    SceneUI.Pointer("move", J.x + 50, J.y, 2)
    S.panelMode = "levels"
    SceneUI.Pointer("down", J.x, J.y, 3)   -- 面板下不再接管
    check("面板打开时摇杆不接管", false == SceneUI.Pointer("down", J.x, J.y, 4))
    SceneUI.Update(1 / 60)
    check("面板打开后输入清零", (S.input.x or 0) == 0, tostring(S.input.x))
    S.panelMode = nil

    -- 6) 画一帧不报错
    local ok, err = pcall(function()
        S.touchMode = true
        SceneUI.Pointer("down", J.x, J.y, 5)
        SceneUI.Pointer("move", J.x - 40, J.y + 30, 5)
        SceneUI.Draw()
        SceneUI.Pointer("up", 0, 0, 5)
    end)
    check("绘制一帧不报错", ok, err)

    print(string.format("[Joy] done, failures = %d", fails))
end
