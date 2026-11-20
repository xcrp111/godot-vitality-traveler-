-- LevelCards.lua — 进入关卡前的「层卡三选一」（ActMap）
-- 每关进入时从 ActMap 抽三张卡：地形模板 × 层词条，选完直接开打。
local Config = require "Config"
local UI = require "UI"
local S = require "State"
local Run = require "Run"
local ActMap = require "ActMap"

local LevelCards = {}

function LevelCards.Open(level)
    level = math.max(1, math.min(20, math.floor(level or 1)))
    S.levelCards = { level = level, cards = ActMap.RollCards(level, {}) }
end

function LevelCards.Close() S.levelCards = nil end
function LevelCards.Active() return S.levelCards ~= nil end

function LevelCards.Choose(i)
    local st = S.levelCards
    if not st then return end
    local card = st.cards[i]
    if not card then return end
    local layer = ActMap.GenerateLayer(st.level, card)
    S.levelCards = nil
    if layer then
        Run.StartWithLayer(st.level, layer)
    else
        Run.Start(st.level)
    end
end

local RISK_COLOR = {
    ["轻松"] = { 126, 231, 135, 255 },
    ["常规"] = { 236, 232, 242, 255 },
    ["吃紧"] = { 255, 209, 102, 255 },
    ["险恶"] = { 255, 107, 107, 255 },
}

function LevelCards.Draw()
    local st = S.levelCards
    if not st then return end
    nvgBeginPath(S.ctx)
    nvgRect(S.ctx, 0, 0, Config.DESIGN_W, Config.DESIGN_H)
    nvgFillColor(S.ctx, nvgRGBA(8, 10, 14, 228))
    nvgFill(S.ctx)

    UI.Text(640, 54, 28, string.format("第 %d 关 · 选择本层地形", st.level), S.col.gold,
        NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    UI.Text(640, 94, 14, "三张层卡 = 地形模板 × 层词条，选完直接开打", S.col.dim,
        NVG_ALIGN_CENTER + NVG_ALIGN_TOP)

    local w, h, gap = 340, 424, 30
    local total = #st.cards * w + (#st.cards - 1) * gap
    local x0 = (Config.DESIGN_W - total) / 2
    for i, card in ipairs(st.cards) do
        local x = x0 + (i - 1) * (w + gap)
        local y = 140
        local label = ActMap.RiskLabel(ActMap.RiskOf(card.grid, st.level))
        local col = RISK_COLOR[label] or S.col.text
        UI.Panel(x, y, w, h, 14, { 30, 28, 44, 245 }, S.col.line, 2)
        UI.Text(x + 20, y + 16, 13, (card.mod and card.mod.icon or "径"), S.col.dim)
        UI.Text(x + 20, y + 36, 24, card.templateName or card.templateId or "", S.col.text)
        UI.Text(x + 20, y + 72, 18, "词条 · " .. (card.modName or ""), col)
        UI.TextBox(x + 20, y + 100, w - 40, 13, (card.mod and card.mod.desc) or "", S.col.dim)

        local pv = card.preview or {}
        local yy = y + 170
        for _, r in ipairs({
            { "战斗房", pv.combat or 0 }, { "精英房", pv.elite or 0 },
            { "商店", pv.shop or 0 }, { "机遇", pv.special or 0 },
            { "Boss", pv.boss or 0 },
        }) do
            UI.Text(x + 24, yy, 14, r[1], S.col.dim)
            UI.Text(x + w - 24, yy, 14, tostring(r[2]), S.col.text,
                NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
            yy = yy + 24
        end
        UI.Text(x + 24, yy + 10, 14, "预期血尘", S.col.dim)
        UI.Text(x + w - 24, yy + 8, 17, tostring(pv.silver or 0), S.col.gold,
            NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
        UI.Text(x + 24, yy + 42, 15, "难度：" .. label, col)

        UI.Button("levelcard_" .. i, x + 24, y + h - 64, w - 48, 46, "选这张",
            function() LevelCards.Choose(i) end,
            { fontSize = 18, accent = col, fill = { 40, 52, 46, 255 } })
    end

    UI.Button("levelcard_close", 560, 596, 160, 42, "返回 (Esc)", function()
        LevelCards.Close()
        S.panelMode = "levels"
    end, { fontSize = 15 })
end

return LevelCards
