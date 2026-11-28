-- DevPanel.lua — 开发/测试工具面板（只有 S.dev = true 时入口才显示）
-- 把以前散落在旧菜单里的测试功能收进一个按钮：推进日期、解锁关卡、满足健康要求、
-- 加货币、农场全熟、测试战斗、测试关卡跳转、重置存档。
local Config = require "Config"
local Save = require "Save"
local UI = require "UI"
local S = require "State"
local Economy = require "Economy"
local Farm = require "Farm"

local DevPanel = {}

local PANEL = { x = 110, y = 44, w = 1060, h = 632 }

local function Line(y, label, value, color)
    UI.Text(PANEL.x + 32, y, 13, label, S.col.dim)
    UI.Text(PANEL.x + 210, y, 13, tostring(value), color or S.col.text)
end

local function Btn(id, x, y, w, h, label, onClick, color)
    UI.Button(id, x, y, w, h, label, onClick, {
        fontSize = 14,
        fill = color or { 42, 48, 60, 255 },
        stroke = S.col.line,
    })
end

--- 打开面板
function DevPanel.Open()
    S.devPanel = true
end

function DevPanel.Close()
    S.devPanel = false
end

function DevPanel.Draw()
    local d = S.data
    if not d then return end

    nvgBeginPath(S.ctx)
    nvgRect(S.ctx, 0, 0, Config.DESIGN_W, Config.DESIGN_H)
    nvgFillColor(S.ctx, nvgRGBA(0, 0, 0, 205))
    nvgFill(S.ctx)
    UI.Panel(PANEL.x, PANEL.y, PANEL.w, PANEL.h, 16, { 26, 24, 34, 252 }, S.col.line, 1)

    UI.Text(PANEL.x + 32, PANEL.y + 20, 26, "开发 / 测试工具", S.col.gold)
    UI.Text(PANEL.x + 32, PANEL.y + 56, 12, "只在开发模式下出现。所有操作会直接改存档，正式发布前把 State.lua 里的 dev 改成 false。", S.col.dim)
    UI.Button("dev_close", PANEL.x + PANEL.w - 120, PANEL.y + 18, 90, 34, "关闭", function()
        DevPanel.Close()
    end, { fontSize = 15 })

    -- 当前状态
    local y = PANEL.y + 92
    UI.Text(PANEL.x + 32, y, 14, "当前状态", S.col.cyan)
    y = y + 26
    Line(y, "日期", tostring(d.dayKey) .. string.format("（dayOffset %d）", d.dayOffset or 0)); y = y + 24
    Line(y, "关卡进度", string.format("已通关 %d / 解锁 %d", d.stageCleared or 0, d.unlocked or 1)); y = y + 24
    Line(y, "职业等级", string.format("%s Lv.%d", Config.Class().name, Save.ClassLevel(d))); y = y + 24
    Line(y, "货币", string.format("生息 %s · 精粹 %s", UI.FormatNumber(d.gold or 0),
        UI.FormatNumber(Economy.Essence(d)))); y = y + 24
    Line(y, "健康", string.format("饮水 %d/%d　步数 %d　早睡 %s　今日已领 %s",
        d.waterMl or 0, Save.WaterGoal(), d.todaySteps or 0,
        d.sleptEarly and "是" or "否", d.claimed and "是" or "否")); y = y + 24
    local f = Farm.Roll(d)
    Line(y, "农场", string.format("土地 %d/9　成熟 %d 块　声望 Lv.%d",
        f and f.landCount or 4, Farm.MatureCount(d), Farm.RepLevel(d)))

    -- 左列：时间与健康
    local colW = 250
    local colX, colY = PANEL.x + 32, PANEL.y + 330   -- 状态区占上半部分，按钮从下半部分开始
    UI.Text(colX, colY, 14, "时间 / 健康任务", S.col.cyan)
    colY = colY + 30
    Btn("dev_nextday", colX, colY, colW, 38, "快速下一天", function()
        Save.NextDay(S.data)
        Save.RollDay(S.data)
        UI.SetToast("已进入下一天：" .. S.data.dayKey, 2.2)
    end, { 40, 58, 48, 255 })
    Btn("dev_health", colX, colY + 48, colW, 38, "满足健康要求", function()
        local goal = Save.WaterGoal()
        if (d.waterMl or 0) < goal then Save.AddWater(d, goal - (d.waterMl or 0)) end
        Save.CheckSleep(d)
        d.todaySteps = math.max(d.todaySteps or 0, 12000)
        d.claimed = false
        Save.Write(d)
        UI.SetToast("饮水/早睡/步数已达标，可以去「运动」页领取", 2.6)
    end, { 40, 60, 52, 255 })
    Btn("dev_resettoday", colX, colY + 96, colW, 38, "重置今日任务", function()
        Save.ResetToday(d)
        UI.SetToast("今日任务已重置", 1.8)
    end)

    -- 中列：关卡与内容
    local midX = colX + colW + 123
    local midY = colY
    UI.Text(midX, midY - 30, 14, "关卡 / 内容", S.col.cyan)
    Btn("dev_unlock", midX, midY, 200, 38, "一键解锁全部关卡", function()
        Save.DebugUnlockAll(d)
        S.selectedLevel = Save.MaxPlayable(d)
        UI.SetToast("已解锁到第 20 关", 2.0)
    end, { 44, 56, 44, 255 })
    Btn("dev_testrun", midX, midY + 48, 200, 38, "测试战斗面板", function()
        DevPanel.Close()
        S.test = true
        S.testPage = 1
    end, { 40, 52, 74, 255 })
    Btn("dev_testlevel", midX, midY + 96, 200, 38, "测试关卡（选关）", function()
        DevPanel.Close()
        S.panelMode = "levels"
    end, { 40, 52, 74, 255 })

    -- 右列：资源与杂项
    local rightX = midX + colW + 123
    local rightY = colY
    UI.Text(rightX, rightY - 30, 14, "资源 / 其他", S.col.cyan)
    Btn("dev_essence", rightX, rightY, 200, 38, "精粹 +1000", function()
        Economy.AddEssence(d, 1000)
        Save.Write(d)
        UI.SetToast("精粹 +1000", 1.6)
    end, { 44, 52, 70, 255 })
    Btn("dev_gold", rightX, rightY + 48, 200, 38, "生息 +1000", function()
        local got = Economy.AddGold(d, 1000)
        Save.Write(d)
        UI.SetToast("生息 +" .. got .. "（上限 " .. Economy.GoldCap(d) .. "）", 1.8)
    end, { 58, 52, 36, 255 })
    Btn("dev_farmripen", rightX, rightY + 96, 200, 38, "农场全部成熟", function()
        Farm.DebugRipenAll(d)
        UI.SetToast("农场作物已全部成熟", 1.8)
    end, { 44, 62, 48, 255 })
    Btn("dev_farmland", rightX, rightY + 144, 200, 38, "农场土地解锁到 9 块", function()
        local ff = Farm.Roll(d)
        ff.landCount = 9
        Save.Write(d)
        UI.SetToast("农场土地已解锁到 9 块", 1.8)
    end, { 44, 62, 48, 255 })

    -- 底部独立一行：无尽解锁 + 重置存档（原来挤在右列，会顶出面板）
    local bottomY = PANEL.y + PANEL.h - 76
    Btn("dev_unlockendless", colX, bottomY, colW, 38, "强制解锁无尽模式", function()
        local on = not Save.EndlessUnlocked(d)
        Save.SetDevEndlessUnlock(d, on)
        UI.SetToast(on and "无尽模式已解锁（测试）" or "已取消强制解锁", 1.8)
    end, { 52, 42, 66, 255 })

    Btn("dev_reset", colX + colW + 123, bottomY, colW, 38, "重置存档", function()
        DevPanel.Close()
        S.confirmReset = true
    end, { 66, 40, 44, 255 })

    -- 底部第三格：音效自检（排查手机上没声音）
    local Sfx = require "Sfx"
    Btn("dev_sfxdiag", colX + (colW + 123) * 2, bottomY, colW, 38, "音效自检", function()
        local out = Sfx.Diag()
        UI.SetToast(out, 4.0)
    end, { 44, 52, 80, 255 })
    -- 音频通路排查：分别在「卡农那条已知能出声的路径」里放 WAV 和 OGG
    local Audio = require "Audio"
    Btn("dev_wavtest", colX, bottomY - 46, 120, 38, "试听A: WAV", function()
        local ok = Audio.PlayTemp("audio/mage/states/D04_freeze_break.wav", 0.9, 1.0)
        UI.SetToast(ok and "正在播 A（WAV 音效）—— 听到请告诉我" or "A 播放失败", 3.0)
    end, { 44, 60, 80, 255 })
    Btn("dev_oggtest", colX + 130, bottomY - 46, 120, 38, "试听B: OGG", function()
        local ok = Audio.PlayTemp("audio/mage/music/M04_boss.ogg", 0.35, 2.0)
        UI.SetToast(ok and "正在播 B（OGG 音乐片段）—— 听到请告诉我" or "B 播放失败", 3.0)
    end, { 60, 52, 84, 255 })

    -- 剧情 / 昵称
    Btn("dev_storyreset", colX + 260, bottomY - 46, 200, 38, "重置剧情进度（可重看）", function()
        S.data.storySeen = {}
        Save.Write(S.data)
        UI.SetToast("剧情进度已重置：第 1~6 关各对应一段剧情", 3.0)
    end, { 52, 46, 70, 255 })
    Btn("dev_name", colX + 470, bottomY - 46, 160, 38, "改昵称", function()
        local NameEntry = require "NameEntry"
        NameEntry.Open(function(name)
            S.data.playerName = name
            Save.Write(S.data)
            UI.SetToast("昵称已改为 " .. name, 2.2)
        end)
    end, { 44, 52, 80, 255 })

    -- 底部说明：入口 + 已有的测试面板
    UI.Text(colX + (colW + 123) * 2, bottomY + 46, 11,
        "「测试战斗面板」自选强化/技能/怪物直接进战斗；「测试关卡」走正常选关流程。", S.col.dim)
end

return DevPanel
