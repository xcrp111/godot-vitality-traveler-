-- CampUI.lua — 营地界面：局外商店 / 农场 / 窝
-- 宠物已独立成系统（主菜单「宠物」入口），不在营地页签里。

local Config = require "Config"
local Save = require "Save"
local UI = require "UI"
local S = require "State"
local Economy = require "Economy"
local Camp = require "Camp"

local CampUI = {}

local TABS = {
    { id = 1, name = "局外商店" },
    { id = 2, name = "农场" },
    { id = 3, name = "窝" },
}

local function FmtTime(sec)
    sec = math.max(0, math.floor(sec or 0))
    if sec <= 0 then return "可领取" end
    local m = math.floor(sec / 60)
    if m >= 60 then
        return string.format("%d 小时 %d 分", math.floor(m / 60), m % 60)
    end
    return string.format("%d 分 %02d 秒", m, sec % 60)
end

local function RarityColor(rarity)
    local rc = Config.Rarity[rarity]
    return rc and rc.color or S.col.text
end

local function RarityName(rarity)
    local rc = Config.Rarity[rarity]
    return rc and rc.name or tostring(rarity)
end

-- ---------------------------------------------------------------- 商店
local function DrawShop(data, c)
    local y0 = 150
    UI.Text(96, 128, 15, "局外商店全部收精粹；每日 5:00 刷新限购，未买次数不累积。", S.col.dim)

    for i, item in ipairs(Camp.ShopItems) do
        local col = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        local x = 76 + col * 566
        local y = y0 + row * 104
        local w, h = 542, 94

        local price = Camp.Price(data, item)
        local remain = Camp.RemainToday(data, item)
        local soldOut = remain == 0
        local affordable = Economy.Essence(data) >= price
        local enabled = not soldOut and affordable

        UI.Panel(x, y, w, h, 12, soldOut and { 40, 36, 54, 255 } or S.col.panel,
            soldOut and S.col.line or S.col.cyan, 1)
        UI.Text(x + 18, y + 12, 18, item.name, soldOut and S.col.dim or S.col.text)
        UI.Text(x + w - 18, y + 10, 20, price .. " 精粹", affordable and S.col.gold or S.col.red,
            NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
        UI.Text(x + 18, y + 38, 12, item.desc, S.col.dim)

        local limitText = "不限"
        if item.limit.kind == "daily" then
            limitText = string.format("今日还剩 %d / %d", remain, item.limit.n)
        elseif item.limit.kind == "every3days" then
            limitText = remain > 0 and "每 3 天可买 1 张（现在可买）" or "每 3 天可买 1 张（冷却中）"
        end
        UI.Text(x + 18, y + 62, 12, string.format("%s　每次 %d %s　·　%s",
            item.group, item.qty, item.unit, limitText), soldOut and S.col.orange or S.col.cyan)

        UI.Button("camp_buy_" .. item.id, x + w - 116, y + 56, 96, 28,
            soldOut and "已限购" or (affordable and "购买" or "精粹不足"),
            function()
                local ok, msg = Camp.Buy(S.data, item.id)
                UI.SetToast(msg, 2.4)
                if ok then Save.Write(S.data) end
            end, { fontSize = 14, enabled = enabled,
                fill = enabled and { 40, 116, 74, 255 } or { 56, 50, 74, 255 },
                stroke = enabled and S.col.green or S.col.line })
    end

    UI.Text(96, 620, 13, string.format(
        "当前精粹 %s　·　两条货币线不换算：金币只来自局内房间掉落、只用于局内商店",
        UI.FormatNumber(Economy.Essence(data))), S.col.dim)
    UI.Text(96, 644, 12, "宠物相关（孵蛋 / 仓库 / 图鉴 / 家园 / 代币商店）在主菜单「宠物」里，用独立的宠物代币。",
        S.col.dim)
end

-- ---------------------------------------------------------------- 农场
local function DrawFarm(data, c)
    local plots = Camp.Plots(data)
    UI.Panel(64, 122, 700, 540, 14, S.col.panel, S.col.cyan, 1)
    UI.Text(84, 138, 20, string.format("农场地块（%d / %d，盖窝可加）", plots, 6), S.col.gold)
    UI.Text(84, 168, 12, string.format("种子：基础 ×%d（30 分 · 白/蓝）　稀有 ×%d（120 分 · 紫/金）",
        c.seeds.basic, c.seeds.rare), S.col.dim)

    local perRow = 3
    for i = 1, 6 do
        local col = (i - 1) % perRow
        local row = math.floor((i - 1) / perRow)
        local x = 84 + col * 224
        local y = 196 + row * 226
        local w, h = 208, 208
        local unlocked = i <= plots
        local plot = c.plots[i]
        local busy = plot and plot.seed
        local left = busy and Camp.PlotLeft(plot) or 0
        local ready = busy and left <= 0

        UI.Panel(x, y, w, h, 12,
            not unlocked and { 44, 38, 60, 255 } or (ready and { 40, 108, 68, 255 } or { 88, 72, 126, 255 }),
            ready and S.col.green or S.col.line, 1)

        if not unlocked then
            UI.Text(x + w / 2, y + h / 2, 13, "未开垦\n（升级窝解锁）", S.col.dim,
                NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        elseif not busy then
            UI.Text(x + w / 2, y + 26, 14, "空地", S.col.dim, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
            UI.Button("camp_plant_basic_" .. i, x + 20, y + 62, w - 40, 32, "种基础种子",
                function()
                    local ok, msg = Camp.Plant(S.data, i, "basic")
                    UI.SetToast(msg, 2.4)
                    if ok then Save.Write(S.data) end
                end, { fontSize = 13, enabled = c.seeds.basic > 0,
                    fill = { 40, 116, 74, 255 }, stroke = S.col.green })
            UI.Button("camp_plant_rare_" .. i, x + 20, y + 104, w - 40, 32, "种稀有种子",
                function()
                    local ok, msg = Camp.Plant(S.data, i, "rare")
                    UI.SetToast(msg, 2.4)
                    if ok then Save.Write(S.data) end
                end, { fontSize = 13, enabled = c.seeds.rare > 0,
                    fill = { 96, 62, 148, 255 }, stroke = S.col.purple })
            UI.Text(x + w / 2, y + 154, 11, "收获 → 果实 → 开局 Buff", S.col.cyan,
                NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        else
            local def = Camp.Seeds[plot.seed]
            UI.Text(x + w / 2, y + 26, 14, def and def.name or "作物", S.col.text,
                NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
            UI.Text(x + w / 2, y + 56, 12, ready and "已成熟" or FmtTime(left),
                ready and S.col.green or S.col.cyan, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
            local total = math.max(1, def and def.minutes * 60 or 1)
            UI.Bar(x + 20, y + 88, w - 40, 12, 1 - math.min(1, left / total), S.col.green,
                { 40, 34, 56, 255 }, S.col.line)
            UI.Button("camp_harvest_" .. i, x + 20, y + 118, w - 40, 36, ready and "收获" or "还没熟",
                function()
                    local ok, msg = Camp.Harvest(S.data, i)
                    UI.SetToast(msg, 2.4)
                    if ok then Save.Write(S.data) end
                end, { fontSize = 15, enabled = ready,
                    fill = { 40, 116, 74, 255 }, stroke = S.col.green })
        end
    end

    -- 右：果实库存
    UI.Panel(788, 122, 428, 540, 14, S.col.panel, S.col.cyan, 1)
    UI.Text(808, 138, 20, "果实（局内 Buff 券）", S.col.gold)
    UI.Text(808, 168, 12, "装一颗进背包，下一局开局自动换成一个该品质的随机 Buff", S.col.dim)

    local equipped = c.equippedFruit
    UI.Panel(808, 192, 388, 56, 10, equipped and { 96, 82, 40, 255 } or { 88, 72, 126, 255 },
        equipped and S.col.gold or S.col.line, 1)
    if equipped then
        UI.Text(824, 210, 16, "背包里：" .. RarityName(equipped) .. "果实", RarityColor(equipped))
        UI.Button("camp_unequip", 1080, 206, 100, 30, "取下", function()
            Camp.UnequipFruit(S.data)
            Save.Write(S.data)
            UI.SetToast("已取下果实", 1.8)
        end, { fontSize = 13 })
    else
        UI.Text(824, 212, 14, "背包是空的", S.col.dim)
    end

    for i, rarity in ipairs({ "white", "blue", "purple", "gold" }) do
        local y = 264 + (i - 1) * 74
        local n = c.fruits[rarity] or 0
        UI.Panel(808, y, 388, 64, 10, { 88, 72, 126, 255 }, RarityColor(rarity), 2)
        UI.Text(824, y + 10, 16, RarityName(rarity) .. "果实 ×" .. n, RarityColor(rarity))
        UI.Text(824, y + 36, 11, "开局随机获得一个" .. RarityName(rarity) .. "品质 Buff", S.col.dim)
        UI.Button("camp_equip_" .. rarity, 1080, y + 18, 100, 30, "装背包", function()
            local ok, msg = Camp.EquipFruit(S.data, rarity)
            UI.SetToast(msg, 2.4)
            if ok then Save.Write(S.data) end
        end, { fontSize = 13, enabled = n > 0 and equipped == nil,
            fill = { 40, 116, 74, 255 }, stroke = S.col.green })
    end
end

-- ---------------------------------------------------------------- 窝
local function DrawNest(data, c)
    UI.Panel(64, 122, 560, 300, 14, S.col.panel, S.col.cyan, 1)
    UI.Text(84, 138, 20, string.format("窝 Lv.%d", c.nestLevel), S.col.gold)
    UI.Text(84, 170, 13, string.format("农场地块 %d / 6", Camp.Plots(data)), S.col.cyan)

    local nextLv = Camp.NextNest(data)
    if nextLv then
        UI.Text(84, 208, 13, string.format("升级到 Lv.%d 需要：基础建材 %d、中级建材 %d", nextLv.level,
            nextLv.basic, nextLv.mid), S.col.text)
        UI.Text(84, 234, 12, string.format("你现有：基础 %d、中级 %d", c.mats.basic, c.mats.mid), S.col.dim)
        local can = c.mats.basic >= nextLv.basic and c.mats.mid >= nextLv.mid
        UI.Button("camp_nest_up", 84, 262, 240, 40, "盖窝升级", function()
            local ok, msg = Camp.UpgradeNest(S.data)
            UI.SetToast(msg, 2.6)
            if ok then Save.Write(S.data) end
        end, { fontSize = 16, enabled = can, accent = S.col.gold,
            fill = can and { 132, 100, 44, 255 } or { 56, 50, 74, 255 },
            stroke = can and S.col.gold or S.col.line })
    else
        UI.Text(84, 208, 14, "窝已经满级（Lv.5）", S.col.green)
    end

    UI.Text(84, 320, 12, "建材只能从局外商店买（基础 50 精粹 / 10 个，中级 100 精粹 / 5 个）", S.col.dim)
    UI.Text(84, 344, 12, "窝等级决定农场地块数：+1/级，上限 6 块", S.col.dim)

    UI.Panel(648, 122, 568, 300, 14, S.col.panel, S.col.cyan, 1)
    UI.Text(668, 138, 20, "局外一览", S.col.gold)
    local rows = {
        { "精粹", UI.FormatNumber(Economy.Essence(data)) },
        { "累计获得精粹", UI.FormatNumber(data.essenceEarned or 0) },
        { "账号等级", "Lv." .. Economy.AccountLevel(data) },
        { "钥匙 / 间断卡", c.keys .. " 把 / " .. c.streakCards .. " 张" },
        { "种子", "基础 " .. c.seeds.basic .. " · 稀有 " .. c.seeds.rare },
        { "建材", "基础 " .. c.mats.basic .. " · 中级 " .. c.mats.mid },
    }
    for i, row in ipairs(rows) do
        local y = 176 + (i - 1) * 32
        UI.Text(668, y, 14, row[1], S.col.dim)
        UI.Text(1200, y, 15, row[2], S.col.text, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
    end

    if S.dev then
        UI.Button("camp_devskip", 668, 386, 220, 30, "开发：跳过所有等待", function()
            local now = os.time()
            for _, plot in pairs(c.plots) do
                if plot then plot.readyAt = now end
            end
            Save.Write(S.data)
            UI.SetToast("已跳过成熟等待", 2.0)
        end, { fontSize = 12, fill = { 40, 116, 74, 255 }, stroke = S.col.green })
    end
end

-- ---------------------------------------------------------------- 主绘制
function CampUI.Draw()
    local data = S.data
    local c = Camp.Ensure(data)

    nvgBeginPath(S.ctx)
    nvgRect(S.ctx, 0, 0, Config.DESIGN_W, Config.DESIGN_H)
    nvgFillColor(S.ctx, nvgRGBA(S.col.bg[1], S.col.bg[2], S.col.bg[3], 245))
    nvgFill(S.ctx)

    UI.Text(64, 36, 32, "营地", S.col.text)
    UI.Text(158, 48, 14, "局外养成：只花精粹，不碰局内金币", S.col.dim)

    UI.Text(1104, 40, 18, "精粹 " .. UI.FormatNumber(Economy.Essence(data)), S.col.gold,
        NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
    UI.Button("camp_close", 1136, 26, 88, 34, "关闭", function()
        S.camp = false
    end, { fontSize = 15, fill = { 122, 52, 60, 255 }, stroke = S.col.red })

    for _, tab in ipairs(TABS) do
        local x = 64 + (tab.id - 1) * 112
        local active = (S.campTab or 1) == tab.id
        UI.Button("camp_tab_" .. tab.id, x, 82, 104, 34, tab.name, function()
            S.campTab = tab.id
        end, { fontSize = 15,
            fill = active and { 40, 132, 176, 255 } or { 74, 60, 106, 255 },
            stroke = active and S.col.cyan or S.col.line, strokeW = active and 2 or 1 })
    end

    if (S.campTab or 1) == 1 then
        DrawShop(data, c)
    elseif S.campTab == 2 then
        DrawFarm(data, c)
    else
        DrawNest(data, c)
    end
end

return CampUI
