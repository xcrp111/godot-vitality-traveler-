-- DevSceneView.lua — 主界面场景截图（走路 / 待机 / 悬停 / 子面板 / letterbox）
-- 时间线固定，配合引擎自带 -screenshot 使用：
--   cd .cli
--   UrhoXRuntime.exe DevSceneView.lua "-tapcode_dir=<项目根>" -tool_mode \
--       "-screenshot=../.tmp/sv1-idle.png" -screenshot-frame=15 -x 1280 -y 720
-- 帧号表：
--   15 待机 / 40 55 75 走路中的三帧 / 110 停下（回待机）/ 125 悬停顶部入口
--   140 角色面板 / 160 今日运动面板 / 175 选关面板 / 190 走近生命之书
local Config = require "Config"
local Save = require "Save"
local UI = require "UI"
local S = require "State"
local Art = require "Art"
local SceneUI = require "SceneUI"
local Menu = require "Menu"

local frame = 0
local dt = 1 / 60

local function Layout()
    local dpr = graphics:GetDPR()
    if not dpr or dpr <= 0 then dpr = 1 end
    S.dpr = dpr
    S.W = graphics:GetWidth() / dpr
    S.H = graphics:GetHeight() / dpr
    S.scale = math.min(S.W / Config.DESIGN_W, S.H / Config.DESIGN_H)
    S.offX = (S.W - Config.DESIGN_W * S.scale) / 2
    S.offY = (S.H - Config.DESIGN_H * S.scale) / 2
end

function Start()
    -- 临时：用一个非 16:9 的窗口验证上下/左右是否会有未绘制的空档
    if os.getenv("SV_MODE") then
        local w, h = string.match(os.getenv("SV_MODE"), "^(%d+)x(%d+)$")
        if w then pcall(function() graphics:SetMode(tonumber(w), tonumber(h), false, true) end) end
    end
    S.ctx = nvgCreate(1)
    S.font = nvgCreateFont(S.ctx, "sans", "Fonts/MiSans-Regular.ttf")
    S.data = Save.Load() or Save.Fresh()
    S.data.todaySteps = 8260
    S.data.claimed = false
    Config.SetClass(Save.ActiveClass(S.data))
    S.screen = "menu"
    S.panelMode = nil
    Layout()
    SceneUI.Init()
    SceneUI.debugBoxes = false
    local sc = S.scene
    sc.grid = false
    sc.wx, sc.wy = 1120, 700
    sc.facing = 1
    S.input.x, S.input.y = 0, 0
    S.hover.x, S.hover.y = -1, -1
    S.hoverIsMouse = true
    SubscribeToEvent(S.ctx, "NanoVGRender", "HandleRender")
    SubscribeToEvent("Update", "HandleUpdate")
    print(string.format("[DevSceneView] canvas %.0fx%.0f scale %.3f off %.1f,%.1f",
        S.W, S.H, S.scale, S.offX, S.offY))
end

local function Step()
    frame = frame + 1
    S.time = S.time + dt
    UI.UpdateToast(dt)

    if frame < 30 then
        S.input.x, S.input.y = 0, 0
    elseif frame < 100 then
        S.input.x, S.input.y = 1, 0
    elseif frame < 115 then
        S.input.x, S.input.y = 0, 0
    elseif frame < 130 then
        -- 顶部 HUD「背包」按钮中心（7 个入口 540 宽，startX = 370）
        S.hover.x, S.hover.y = 484, 39
    elseif frame < 150 then
        S.hover.x, S.hover.y = 378, 189          -- 角色面板：职业按钮
        S.panelMode = "char"
    elseif frame < 170 then
        S.hover.x, S.hover.y = 507, 344          -- 今日运动面板：+1000
        S.panelMode = "sports"
    elseif frame < 185 then
        S.hover.x, S.hover.y = 610, 311          -- 选关面板：开始按钮
        S.panelMode = "levels"
    else
        S.hover.x, S.hover.y = -1, -1
        S.panelMode = nil
        local sc = S.scene
        sc.wx, sc.wy = 300, 640                   -- 生命之书旁边
    end

    SceneUI.Update(dt)
end

function HandleUpdate()
    -- 窗口尺寸变化（或上面 SetMode 之后）重算设计画布
    local dpr = graphics:GetDPR()
    if not dpr or dpr <= 0 then dpr = 1 end
    if math.abs(graphics:GetWidth() / dpr - S.W) > 0.5 or math.abs(graphics:GetHeight() / dpr - S.H) > 0.5 then
        Layout()
        print(string.format("[DevSceneView] relayout %.0fx%.0f scale %.3f off %.1f,%.1f",
            S.W, S.H, S.scale, S.offX, S.offY))
    end
    Step()
end

function HandleRender()
    nvgBeginFrame(S.ctx, graphics:GetWidth(), graphics:GetHeight(), S.dpr)
    S.regions = {}
    UI.BeginDesign()
    nvgBeginPath(S.ctx)
    nvgRect(S.ctx, 0, 0, Config.DESIGN_W, Config.DESIGN_H)
    nvgFillColor(S.ctx, nvgRGBA(S.col.bg[1], S.col.bg[2], S.col.bg[3], 255))
    nvgFill(S.ctx)
    if S.panelMode == "char" then
        SceneUI.DrawPanelBg()
        Menu.DrawCharacter()
        SceneUI.DrawPanelBack()
    elseif S.panelMode == "sports" then
        SceneUI.DrawPanelBg()
        Menu.DrawSports()
        SceneUI.DrawPanelBack()
    elseif S.panelMode == "levels" then
        SceneUI.DrawPanelBg()
        Menu.DrawLevels()
        SceneUI.DrawPanelBack()
    else
        SceneUI.Draw()
    end
    UI.DrawPress()
    UI.DrawHover()
    UI.DrawToast()
    UI.EndDesign()
    nvgEndFrame(S.ctx)
    if frame >= 200 then engine:Exit() end
end
