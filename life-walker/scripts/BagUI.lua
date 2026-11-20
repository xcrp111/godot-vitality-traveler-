-- BagUI.lua — 背包（主菜单级入口，和营地 / 公会 / 设置 / 图鉴并列）
-- 只展示「局外物品」：钥匙、间断卡、加速卡、建材、抽卡次数、种子、果实、宠物蛋。

local Config = require "Config"
local UI = require "UI"
local S = require "State"
local Economy = require "Economy"
local Camp = require "Camp"

local BagUI = {}

local PAGE_SIZE = 12

local function RarityColor(rarity)
    local rc = Config.Rarity[rarity]
    return rc and rc.color or nil
end

-- 分组配色：让一眼能分出是门票 / 材料 / 抽卡 / 农场 / 果实 / 蛋
local GROUP_COLOR = {
    ["门票"] = "gold",
    ["养成"] = "cyan",
    ["材料"] = "orange",
    ["抽卡"] = "purple",
    ["农场"] = "green",
    ["果实"] = "gold",
    ["宠物蛋"] = "purple",
}

function BagUI.Draw()
    local data = S.data
    local c = Camp.Ensure(data)
    local list = Camp.Inventory(data)
    local pages = math.max(1, math.ceil(#list / PAGE_SIZE))
    local page = math.min(pages, math.max(1, S.bagPage or 1))
    S.bagPage = page

    -- 遮罩
    nvgBeginPath(S.ctx)
    nvgRect(S.ctx, 0, 0, Config.DESIGN_W, Config.DESIGN_H)
    nvgFillColor(S.ctx, nvgRGBA(S.col.bg[1], S.col.bg[2], S.col.bg[3], 245))
    nvgFill(S.ctx)

    UI.Text(64, 36, 32, "背包", S.col.text)
    UI.Text(158, 48, 14, string.format("局外物品 %d 类（宠物蛋 / 宠物在主菜单「宠物」里）", #list), S.col.dim)

    UI.Text(1004, 40, 18, "精粹 " .. UI.FormatNumber(Economy.Essence(data)), S.col.gold,
        NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
    UI.Text(1004, 64, 12, "金币是局内货币，只在关卡里显示",
        S.col.dim, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
    UI.Button("bag_close", 1136, 26, 88, 34, "关闭", function()
        S.bag = false
    end, { fontSize = 15, fill = { 122, 52, 60, 255 }, stroke = S.col.red })

    -- 翻页
    UI.Button("bag_prev", 1044, 80, 44, 26, "<", function()
        S.bagPage = math.max(1, page - 1)
    end, { fontSize = 15, enabled = page > 1 })
    UI.Text(1112, 86, 13, string.format("%d / %d", page, pages), S.col.dim,
        NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    UI.Button("bag_next", 1152, 80, 44, 26, ">", function()
        S.bagPage = math.min(pages, page + 1)
    end, { fontSize = 15, enabled = page < pages })

    -- 快捷入口提示
    UI.Text(64, 86, 12, "买新东西去「营地 · 局外商店」，孵化在「营地 · 宠物」，种植在「营地 · 农场」", S.col.dim)

    if #list == 0 then
        UI.Text(640, 360, 17, "背包是空的：先去「营地 · 局外商店」买点东西", S.col.dim,
            NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        return
    end

    local from = (page - 1) * PAGE_SIZE + 1
    local to = math.min(#list, from + PAGE_SIZE - 1)
    local cols = 3
    for idx = from, to do
        local item = list[idx]
        local i = idx - from
        local col = i % cols
        local row = math.floor(i / cols)
        local x = 76 + col * 392
        local y = 124 + row * 138
        local w, h = 376, 126
        local accent = (item.rarity and RarityColor(item.rarity))
            or S.col[GROUP_COLOR[item.group] or "cyan"] or S.col.cyan

        UI.Panel(x, y, w, h, 12, { 88, 72, 126, 255 }, accent, 2)
        UI.Text(x + 16, y + 10, 11, item.group, S.col.dim)
        UI.Text(x + 16, y + 28, 18, item.name, accent)
        UI.Text(x + w - 16, y + 24, 26, "×" .. UI.FormatNumber(item.count), S.col.gold,
            NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
        UI.TextBox(x + 16, y + 64, w - 32, 11, item.desc, S.col.dim)
        UI.Text(x + 16, y + h - 20, 11, "单位：" .. item.unit, S.col.dim)
    end

    if pages > 1 then
        UI.Text(640, 690, 12, "点右上角 < > 翻页", S.col.dim, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    end

    -- 已装备的果实提醒
    if c.equippedFruit then
        UI.Text(640, 74, 12, string.format("已装备：%s果实（下一局开局自动消耗）",
            Config.Rarity[c.equippedFruit].name), S.col.gold, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    end
end

return BagUI
