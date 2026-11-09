-- TitleUI.lua — 初始界面（开场标题）
-- 背景与角色素材来自 game-health 项目（assets/art/）

local Config = require "Config"
local Save = require "Save"
local UI = require "UI"
local S = require "State"
local Art = require "Art"
local Economy = require "Economy"

local TitleUI = {}

local HERO = {
    path = "art/hero_idle.png",
    frames = 6,
    frameH = 561,
    drawH = 300,
    fps = 5,
}
local t = 0

function TitleUI.Update(dt)
    if S.screen ~= "title" then return end
    t = t + dt
end

--- 进入游戏（标题 → 场景）
function TitleUI.StartGame()
    if S.screen ~= "title" then return false end
    S.screen = "menu"
    S.panelMode = nil
    UI.SetToast("欢迎回来，生命行者", 2.0)
    return true
end

function TitleUI.Draw()
    -- 背景按整个物理屏幕（含 letterbox）cover 铺满，上下/左右都不会留出灰边
    local vx, vy, vw, vh = UI.ViewRect()
    if not Art.DrawCover("art/title_bg.jpg", vx, vy, vw, vh, 1) then
        UI.FillScreen(S.col.bg)
    end

    -- 底部压暗，给按钮与存档信息留可读背景
    nvgBeginPath(S.ctx)
    nvgRect(S.ctx, 0, Config.DESIGN_H - 260, Config.DESIGN_W, 260)
    nvgFillColor(S.ctx, nvgRGBA(8, 6, 14, 150))
    nvgFill(S.ctx)

    -- 开始按钮（居中，标题下方）
    local pulse = 0.5 + 0.5 * math.sin(t * 2.4)
    UI.Button("title_start", 470, 512, 340, 72, "开始游戏", function()
        TitleUI.StartGame()
    end, { fontSize = 26, fill = { 46, 118, 82, 255 },
        stroke = { 140 + pulse * 60, 240, 160 + pulse * 40, 255 }, strokeW = 2 })
    UI.Text(640, 596, 12, "点这里开始　·　键盘 Enter / 空格 也可以", S.col.dim,
        NVG_ALIGN_CENTER + NVG_ALIGN_TOP)

    -- 左下：存档概览
    local data = S.data
    if data then
        local lv = Save.ClassLevel(data)
        UI.Text(40, 646, 13, string.format("%s Lv.%d　·　已通关 %d 关　·　账号 Lv.%d",
            Config.Class().name, lv, math.min(20, data.stageCleared or 0),
            Economy.AccountLevel(data)), S.col.dim)
    end

    -- 右上：版本
    UI.Text(1196, 22, 12, "v" .. Config.VERSION, S.col.dim, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
end

return TitleUI
