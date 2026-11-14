-- FarmUI.lua — 农场界面（主菜单覆盖层）：农场 / 果实 / 商店
local Config = require "Config"
local Save = require "Save"
local UI = require "UI"
local S = require "State"
local Farm = require "Farm"
local FarmArt = require "FarmArt"
local FarmWalk = require "FarmWalk"

local FarmUI = {}

local TABS = { "农场", "果实", "商店" }

local function toast(msg, sec)
    UI.SetToast(msg, sec or 2.2)
end

local function commit(ok, msg)
    Save.Write(S.data)
    toast(msg)
    return ok
end

local function FormatRemain(sec)
    sec = math.max(0, math.floor(sec or 0))
    if sec >= 3600 then
        return string.format("%d 小时 %d 分", math.floor(sec / 3600), math.floor(sec % 3600 / 60))
    end
    if sec >= 60 then
        return string.format("%d 分 %d 秒", math.floor(sec / 60), sec % 60)
    end
    return string.format("%d 秒", sec)
end

local function FormatRep(data)
    local f = Farm.Roll(data)
    local lv = Farm.RepLevel(data)
    local nextNeed = Farm.RepNextNeed(data)
    local txt = string.format("农场声望 Lv.%d %s · %d 点", lv, Farm.RepLevelName(data), f.rep or 0)
    if nextNeed then
        txt = txt .. string.format("（下阶段 %d）", nextNeed)
    end
    return txt
end

local function drawHeader()
    local f = Farm.Roll(S.data)
    UI.Panel(200, 60, 880, 600, 18, { 24, 27, 22, 252 }, S.col.line, 1)
    UI.Text(232, 78, 28, "农场", { 180, 225, 170 })
    UI.Text(330, 88, 13, FormatRep(S.data), S.col.dim)

    UI.Text(232, 116, 13, "生息 " .. UI.FormatNumber(S.data.gold or 0), S.col.gold)
    local seedTotal, fruitTotal = 0, 0
    for _, v in pairs(f.seeds or {}) do seedTotal = seedTotal + v end
    for _, v in pairs(f.fruits or {}) do fruitTotal = fruitTotal + v end
    UI.Text(430, 116, 13, "种子 " .. seedTotal .. " · 果实 " .. fruitTotal
        .. " · 土地 " .. (f.landCount or 4) .. "/9", S.col.dim)

    for i, name in ipairs(TABS) do
        local x = 640 + (i - 1) * 92
        local active = (S.farmTab or 1) == i
        UI.Button("farm_tab_" .. i, x, 100, 84, 32, name, function()
            S.farmTab = i
        end, {
            fontSize = 14,
            fill = active and { 46, 76, 52, 255 } or { 34, 31, 40, 255 },
            stroke = active and { 120, 200, 140, 255 } or S.col.line,
        })
    end

    UI.Button("farm_close", 960, 72, 100, 36, "关闭 Esc", function()
        S.farm = false
    end, { fontSize = 14 })
end

-- ---------------------------------------------------------------- 农场页
local function drawPlot(index, x, y, w, h)
    local info = Farm.PlotInfo(S.data, index)
    local selected = (S.farmPlot == index)
    local fill = { 34, 37, 30, 255 }
    local stroke = S.col.line
    if info.status == "locked" then
        fill = { 26, 26, 24, 255 }
        stroke = { 50, 50, 46, 255 }
    elseif selected then
        fill = { 46, 56, 42, 255 }
        stroke = { 130, 210, 150, 255 }
    elseif info.status == "mature" then
        fill = { 44, 52, 34, 255 }
        stroke = { 210, 190, 90, 255 }
    end
    UI.Panel(x, y, w, h, 12, fill, stroke, selected and 3 or 1)

    if info.status == "locked" then
        UI.Text(x + w / 2, y + h / 2, 14, "未解锁", S.col.dim,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        return
    end
    if info.status == "empty" then
        UI.Text(x + w / 2, y + h / 2 - 8, 16, "空地", S.col.dim,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        UI.Text(x + w / 2, y + h / 2 + 16, 11, "点一下选中", S.col.dim,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    else
        local c = info.crop.color
        UI.Circle(x + w / 2, y + 38, 24, { c[1], c[2], c[3], 70 },
            { c[1], c[2], c[3], 235 }, 2)
        UI.Text(x + w / 2, y + 38, 16, string.sub(info.crop.name, 1, 1),
            { 30, 28, 24, 255 }, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        UI.Text(x + w / 2, y + 74, 14, info.crop.name, S.col.text,
            NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        if info.status == "mature" then
            UI.Text(x + w / 2, y + 96, 13, "可收获", { 230, 210, 110, 255 },
                NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        else
            UI.Text(x + w / 2, y + 96, 12,
                info.stageName .. " · " .. FormatRemain(info.stageRemain), S.col.dim,
                NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
            UI.Text(x + w / 2, y + 114, 11, "总剩余 " .. FormatRemain(info.remain), S.col.dim,
                NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        end
    end
    UI.Region("farm_plot_" .. index, x, y, w, h, function()
        local cur = Farm.PlotInfo(S.data, index)
        if cur.status == "mature" then
            local ok, msg = Farm.Harvest(S.data, index)
            commit(ok, msg)
        else
            S.farmPlot = index
        end
    end, true)
end

local function drawFarmTab()
    UI.Panel(220, 150, 530, 480, 14, S.col.panel, S.col.line, 1)
    local cell, gap, x0, y0 = 140, 14, 240, 180
    for i = 1, 9 do
        local col = (i - 1) % 3
        local row = math.floor((i - 1) / 3)
        drawPlot(i, x0 + col * (cell + gap), y0 + row * (cell + gap), cell, cell)
    end

    -- 右：选中土地 / 种子 / 操作
    UI.Panel(770, 150, 290, 480, 14, S.col.panel, S.col.line, 1)
    local idx = S.farmPlot
    local info = idx and Farm.PlotInfo(S.data, idx) or nil
    local f = Farm.Roll(S.data)

    if not idx then
        UI.Text(790, 170, 16, "选择一块土地", S.col.text)
        UI.Text(790, 200, 12, "空地：点一下后选种子种下", S.col.dim)
        UI.Text(790, 220, 12, "生长中：可以浇水 / 用水壶", S.col.dim)
        UI.Text(790, 240, 12, "成熟：点土地直接收获", S.col.dim)
        UI.Text(790, 280, 12,
            string.format("今日战斗 %d/3 · 本周无尽 %d/10", f.dailyBattles or 0, f.weeklyLayers or 0),
            S.col.dim)
    elseif info.status == "locked" then
        UI.Text(790, 170, 16, "土地未解锁", S.col.dim)
    elseif info.status == "empty" then
        UI.Text(790, 170, 16, "第 " .. idx .. " 块地 · 选择种子", S.col.text)
        local y = 202
        local any = false
        for _, crop in ipairs(Farm.Crops) do
            if Farm.CropUnlocked(S.data, crop) then
                any = true
                local count = f.seeds[crop.id] or 0
                UI.Button("farm_seed_" .. crop.id, 786, y, 258, 34,
                    string.format("%s种子 ×%d", crop.name, count), function()
                        local ok, msg = Farm.Plant(S.data, idx, crop.id)
                        commit(ok, msg)
                    end, { fontSize = 13, enabled = count > 0,
                        fill = count > 0 and { 40, 52, 40, 255 } or { 32, 30, 36, 255 } })
                y = y + 40
                if y > 560 then break end
            end
        end
        if not any then
            UI.Text(790, 210, 13, "还没有解锁任何作物", S.col.dim)
        elseif y <= 210 then
            UI.Text(790, 210, 13, "没有种子：战斗掉落 / 商店购买", S.col.dim)
        end
    elseif info.status == "growing" then
        local crop = info.crop
        UI.Text(790, 168, 15, "第 " .. idx .. " 块地 · " .. crop.name, S.col.text)
        UI.Text(790, 196, 13, "阶段：" .. info.stageName, S.col.dim)
        UI.Text(790, 218, 13, "当前阶段剩余：" .. FormatRemain(info.stageRemain), S.col.dim)
        UI.Text(790, 240, 13, "成熟还需：" .. FormatRemain(info.remain), S.col.dim)
        UI.Text(790, 262, 12, "浇水冷却：" .. (info.waterReady and "可浇水" or FormatRemain(info.waterCd)),
            info.waterReady and S.col.green or S.col.dim)
        UI.Button("farm_water", 786, 292, 258, 40, "浇水（-15 分钟）", function()
            local ok, msg = Farm.Water(S.data, idx)
            commit(ok, msg)
        end, { fontSize = 14, enabled = info.waterReady and (f.waterToday or 0) < Farm.WATER_DAILY })
        UI.Button("farm_can", 786, 340, 258, 40, "超级水壶（剩 " .. (f.cans or 0) .. "）", function()
            local ok, msg = Farm.UseCan(S.data, idx)
            commit(ok, msg)
        end, { fontSize = 14, enabled = (f.cans or 0) > 0 })
        UI.Button("farm_water_all", 786, 388, 258, 40, "一键浇水（声望 Lv.2）", function()
            local ok, msg = Farm.WaterAll(S.data)
            commit(ok, msg)
        end, { fontSize = 13, enabled = Farm.RepLevel(S.data) >= 2 })
        UI.Text(790, 438, 11, string.format("今日浇水 %d / %d", f.waterToday or 0, Farm.WATER_DAILY),
            S.col.dim)
    elseif info.status == "mature" then
        UI.Text(790, 168, 15, "第 " .. idx .. " 块地 · " .. info.crop.name, { 230, 210, 110, 255 })
        UI.Text(790, 196, 13, "已经成熟，可以收获", S.col.dim)
        UI.Text(790, 226, 12, "预计产出 " .. info.crop.yield .. " 个" .. info.crop.fruitName, S.col.dim)
        UI.Button("farm_harvest", 786, 262, 258, 44, "收获", function()
            local ok, msg = Farm.Harvest(S.data, idx)
            commit(ok, msg)
        end, { fontSize = 16, fill = { 56, 66, 36, 255 }, stroke = { 170, 170, 90, 255 } })
    end

    if S.dev then
        UI.Button("farm_dev_ripe", 786, 570, 124, 30, "全部成熟", function()
            Farm.DebugRipenAll(S.data)
            Save.Write(S.data)
            toast("测试：所有作物已成熟")
        end, { fontSize = 12 })
        UI.Button("farm_dev_rep", 920, 570, 124, 30, "声望 +100", function()
            Farm.DebugAddRep(S.data, 100)
            Save.Write(S.data)
            toast("测试：声望 +100")
        end, { fontSize = 12 })
    end
end

-- ---------------------------------------------------------------- 果实页
local function drawFruitTab()
    UI.Panel(220, 150, 840, 480, 14, S.col.panel, S.col.line, 1)
    UI.Text(240, 166, 16, "果实背包", S.col.text)
    local equipped = Farm.EquippedList(S.data)
    UI.Text(360, 170, 12,
        string.format("已携带 %d / %d 种 · 开局消耗 1 个，效果持续本关；同类不叠加",
            #equipped, Farm.EQUIP_MAX), S.col.dim)

    local f = Farm.Roll(S.data)
    local cols = 3
    local w, h, gap = 260, 128, 14
    local x0, y0 = 240, 200
    for i, crop in ipairs(Farm.Crops) do
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        local x = x0 + col * (w + gap)
        local y = y0 + row * (h + gap)
        local count = f.fruits[crop.id] or 0
        local on = Farm.IsEquipped(S.data, crop.id)
        UI.Panel(x, y, w, h, 10, on and { 46, 56, 40, 255 } or { 34, 32, 40, 255 },
            on and { 140, 210, 150, 255 } or S.col.line, on and 2 or 1)
        -- 果实图标（序列帧第 4 列）
        FarmArt.DrawCrop(crop.id, 4, x + 4, y + 6, 64, 64)
        UI.Text(x + 74, y + 10, 16, crop.fruitName, S.col.text)
        UI.Text(x + w - 12, y + 10, 16, "×" .. count, S.col.gold,
            NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
        UI.TextBox(x + 74, y + 36, w - 88, 12, crop.effect, S.col.dim)
        UI.Button("farm_equip_" .. crop.id, x + 12, y + h - 44, w - 24, 34,
            on and "取消携带" or "携带", function()
                local ok, msg = Farm.ToggleEquip(S.data, crop.id)
                commit(ok, msg)
            end, { fontSize = 14, enabled = count > 0,
                fill = on and { 50, 66, 44, 255 } or { 40, 48, 44, 255 },
                stroke = on and { 140, 210, 150, 255 } or S.col.line })
    end
    UI.Text(240, 640, 12,
        "果实通过农场的作物收获获得；最多携带 3 种，不同类型可以同时生效。", S.col.dim)
end

-- ---------------------------------------------------------------- 商店页
local function drawShopTab()
    local f = Farm.Roll(S.data)
    -- 生息商店
    UI.Panel(220, 150, 390, 470, 14, S.col.panel, S.col.line, 1)
    UI.Text(240, 168, 18, "生息商店（每日限购）", S.col.gold)
    local y = 204
    for _, item in ipairs(Farm.GoldShop) do
        local bought = item.id == "basic" and (f.shopBasic or 0) or (f.shopRare or 0)
        UI.Panel(238, y, 354, 74, 10, S.col.panel2, S.col.line, 1)
        UI.Text(252, y + 8, 15, item.name, S.col.text)
        UI.Text(252, y + 30, 12, "价格 " .. item.price .. " 生息 · 今日 " .. bought .. "/" .. item.daily,
            S.col.dim)
        -- 买不了的时候把原因写在按钮下面，别让玩家对着灰按钮猜
        local why
        if bought >= item.daily then why = "今日已买完"
        elseif (S.data.gold or 0) < item.price then why = "生息不足"
        elseif not Farm.HasTier(S.data, item.id) then
            why = Farm.TierUnlockText(S.data, item.id) or "该品级还没有解锁作物"
        end
        if why then
            UI.Text(252, y + 50, 10, why, { 220, 150, 140 }, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        end
        UI.Button("farm_buy_gold_" .. item.id, 500, y + 18, 76, 38, "购买", function()
            local ok, msg = Farm.BuyGoldSeed(S.data, item.id)
            commit(ok, msg)
        end, { fontSize = 14, enabled = why == nil })
        y = y + 84
    end
    UI.Text(240, 390, 12, "生息从每日步数 / 战斗获得；种子种类按已解锁作物随机", S.col.dim)

    -- 声望商店
    UI.Panel(630, 150, 430, 470, 14, S.col.panel, S.col.line, 1)
    UI.Text(650, 168, 18, "声望商店", S.col.cyan)
    UI.Text(650, 192, 12, FormatRep(S.data), S.col.dim)
    local ry = 216
    for _, item in ipairs(Farm.RepShop) do
        local bought
        if item.id == "basic" then bought = f.repDailyBasic or 0
        elseif item.id == "rare" then bought = f.repDailyRare or 0
        elseif item.id == "epic" then bought = f.repWeeklyEpic or 0
        elseif item.id == "legendary" then bought = f.repWeeklyLegendary or 0
        elseif item.id == "can" then bought = f.repWeeklyCan or 0
        else bought = f.landTicketsBought or 0 end
        local cost = Farm.RepShopCost(S.data, item.id)
        local period = item.period == "day" and "每日" or (item.period == "week" and "每周" or "共")
        -- 禁用原因要写出来：史诗 / 传说种子锁在作物解锁条件后面，
        -- 只给个灰按钮的话玩家会以为是 bug
        local why
        if item.id == "land" and (f.landCount or 4) >= 9 then
            why = "土地已全部解锁"
        elseif bought >= item.limit then
            why = period .. "限购已用完"
        elseif item.seedType then
            why = Farm.TierUnlockText(S.data, item.seedType)
        end
        if not why and (f.rep or 0) < cost then why = "声望不足" end
        UI.Panel(648, ry, 394, 56, 10, S.col.panel2, S.col.line, 1)
        UI.Text(662, ry + 7, 14, item.name, S.col.text)
        if why then
            UI.Text(662, ry + 27, 10, why, S.col.orange)
        else
            UI.Text(662, ry + 27, 11,
                string.format("%d 声望 · %s限 %d/%d", cost, period, bought, item.limit), S.col.dim)
        end
        UI.Button("farm_buy_rep_" .. item.id, 950, ry + 9, 78, 38, "兑换", function()
            local ok, msg = Farm.BuyRep(S.data, item.id)
            commit(ok, msg)
        end, { fontSize = 13, enabled = not why })
        ry = ry + 64
    end
    UI.Text(648, 600, 11, "声望通过浇水 / 收获获得，每日最多 +50", S.col.dim)
end

-- ---------------------------------------------------------------- 实景地图模式
-- 有底图时：整张农场图铺底，9 块地按量出来的坐标叠状态，操作放在底部浮层
local function drawSlimHeader()
    UI.Panel(0, 0, Config.DESIGN_W, 58, 0, { 10, 12, 10, 210 }, nil, 0)
    UI.Text(24, 12, 26, "农场", { 180, 225, 170 })
    UI.Text(96, 20, 12, FormatRep(S.data), S.col.dim)
    local f = Farm.Roll(S.data)
    local seedTotal, fruitTotal = 0, 0
    for _, v in pairs(f.seeds or {}) do seedTotal = seedTotal + v end
    for _, v in pairs(f.fruits or {}) do fruitTotal = fruitTotal + v end
    UI.Text(24, 40, 11, string.format("生息 %s · 种子 %d · 果实 %d · 土地 %d/9",
        UI.FormatNumber(S.data.gold or 0), seedTotal, fruitTotal, f.landCount or 4), S.col.dim)

    for i, name in ipairs(TABS) do
        local x = 700 + (i - 1) * 96
        local active = (S.farmTab or 1) == i
        UI.Button("farm_tab_" .. i, x, 12, 88, 32, name, function()
            S.farmTab = i
            S.farmPlot = nil
        end, {
            fontSize = 14,
            fill = active and { 46, 76, 52, 240 } or { 28, 30, 28, 200 },
            stroke = active and { 120, 200, 140, 255 } or S.col.line,
        })
    end
    UI.Button("farm_close", 1170, 12, 92, 32, "关闭 Esc", function()
        S.farm = false
    end, { fontSize = 13 })
end

--- 单块地在底图上的状态叠加
local function drawArtPlot(index)
    local x, y, w, h = FarmArt.PlotRect(index)
    local info = Farm.PlotInfo(S.data, index)
    local selected = (S.farmPlot == index)
    local cx, cy = x + w / 2, y + h / 2

    if info.status == "locked" then
        -- 未开垦：压暗
        UI.Panel(x, y, w, h, 6, { 8, 10, 8, 165 }, { 55, 55, 48, 150 }, 1)
        UI.Text(cx, cy - 6, 12, "未开垦", { 150, 150, 140, 220 }, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        UI.Text(cx, cy + 12, 10, "商店解锁", { 120, 120, 110, 200 },
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    elseif info.status == "empty" then
        FarmArt.DrawPlotTile(x, y, w, h)
        if selected then
            UI.Panel(x, y, w, h, 6, { 120, 210, 150, 45 }, { 140, 225, 165, 235 }, 2)
        else
            UI.Panel(x, y, w, h, 6, { 255, 255, 240, 12 }, { 200, 220, 180, 70 }, 1)
        end
    else
        FarmArt.DrawPlotTile(x, y, w, h)
        local c = info.crop.color
        if info.status == "mature" then
            UI.Panel(x, y, w, h, 6, { 240, 200, 90, 40 }, { 240, 200, 90, 235 }, 2)
        elseif selected then
            UI.Panel(x, y, w, h, 6, { 120, 210, 150, 35 }, { 140, 225, 165, 220 }, 2)
        end
        -- 作物贴图：成熟用第 3 列，其余用对应阶段列；没有图时回退成色块占位
        local col = info.status == "mature" and 3 or (info.stage or 1)
        -- 序列帧里作物贴着画布底部（下方留 10% 空），
        -- 所以让「内容底边」落在格子高度的 88% 处，植物才会站在地块中间偏下
        local spriteH = h * 1.55
        local spriteW = spriteH
        local sx = cx - spriteW / 2
        local sy = y + h * 0.88 - spriteH * 0.898
        local drawn = FarmArt.DrawCrop(info.crop.id, col, sx, sy, spriteW, spriteH)
        if not drawn then
            local cr = math.min(w, h) * 0.26
            UI.Circle(cx, cy - h * 0.10, cr, { c[1], c[2], c[3], 90 },
                { c[1], c[2], c[3], 235 }, 2)
            UI.Text(cx, cy - h * 0.10, cr * 0.95, string.sub(info.crop.name, 1, 1),
                { 28, 26, 22, 255 }, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        end
        local label = info.status == "mature" and "可收获"
            or (info.stageName .. " · " .. FormatRemain(info.stageRemain))
        -- 成熟作物现在会占满格子，文字压上去看不清，先垫一条半透明底
        UI.Panel(cx - w * 0.40, y + h * 0.03, w * 0.80, 15, 5, { 8, 10, 8, 120 })
        UI.Text(cx, y + h * 0.12, 10, label,
            info.status == "mature" and { 245, 215, 120, 255 } or S.col.dim,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    end

    if selected and info.status ~= "empty" then
        UI.Panel(x - 3, y - 3, w + 6, h + 6, 8, nil, { 140, 225, 165, 235 }, 2)
    end

    UI.Region("farm_plot_" .. index, x, y, w, h, function()
        local cur = Farm.PlotInfo(S.data, index)
        if cur.status == "mature" then
            local ok, msg = Farm.Harvest(S.data, index)
            commit(ok, msg)
        else
            S.farmPlot = (S.farmPlot == index) and nil or index
        end
    end, true)
end

--- 底部操作浮层
local function drawPlotCard()
    local idx = S.farmPlot
    if not idx then
        UI.Text(640, 700, 13, "点一块地：空地选种子 · 生长中浇水 · 成熟直接收获",
            { 220, 220, 205, 210 }, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        return
    end
    local info = Farm.PlotInfo(S.data, idx)
    local f = Farm.Roll(S.data)
    local w, h = 900, 96
    local x, y = (Config.DESIGN_W - w) / 2, 616
    UI.Panel(x, y, w, h, 14, { 16, 18, 14, 242 }, { 90, 110, 90, 220 }, 1)

    if info.status == "locked" then
        UI.Text(x + 24, y + 20, 14, "这块地还没开垦", S.col.text)
        UI.Text(x + 24, y + 46, 12, "「商店 → 土地解锁券」可以把 4 块地扩到 9 块", S.col.dim)
        UI.Button("plot_close", x + w - 96, y + 30, 80, 36, "关闭", function()
            S.farmPlot = nil
        end, { fontSize = 13 })
    elseif info.status == "empty" then
        UI.Text(x + 24, y + 14, 13, "第 " .. idx .. " 块地 · 选种子", S.col.text)
        local bx = x + 24
        local shown = 0
        for _, crop in ipairs(Farm.Crops) do
            local count = f.seeds[crop.id] or 0
            if count > 0 and Farm.CropUnlocked(S.data, crop) then
                shown = shown + 1
                UI.Button("art_seed_" .. crop.id, bx, y + 40, 150, 40,
                    string.format("%s ×%d", crop.name, count), function()
                        local ok, msg = Farm.Plant(S.data, idx, crop.id)
                        S.farmPlot = nil
                        commit(ok, msg)
                    end, { fontSize = 12, fill = { 40, 56, 40, 255 },
                          stroke = { 110, 180, 120, 220 } })
                bx = bx + 158
                if shown >= 5 then break end
            end
        end
        if shown == 0 then
            UI.Text(x + 24, y + 46, 12, "没有可用的种子：打精英 / Boss 会掉落，也可以在商店购买", S.col.dim)
        end
        UI.Button("plot_close", x + w - 96, y + 30, 80, 36, "关闭", function()
            S.farmPlot = nil
        end, { fontSize = 13 })
    elseif info.status == "growing" then
        UI.Text(x + 24, y + 14, 13, string.format("第 %d 块地 · %s · %s（还剩 %s）", idx,
            info.crop.name, info.stageName, FormatRemain(info.remain)), S.col.text)
        UI.Button("art_water", x + 24, y + 40, 180, 40, "浇水（-15 分钟）", function()
            local ok, msg = Farm.Water(S.data, idx)
            commit(ok, msg)
        end, { fontSize = 13, enabled = info.waterReady and (f.waterToday or 0) < Farm.WATER_DAILY })
        UI.Button("art_can", x + 214, y + 40, 180, 40,
            "超级水壶（剩 " .. (f.cans or 0) .. "）", function()
                local ok, msg = Farm.UseCan(S.data, idx)
                commit(ok, msg)
            end, { fontSize = 13, enabled = (f.cans or 0) > 0 })
        UI.Button("art_water_all", x + 404, y + 40, 180, 40, "一键浇水（Lv.2）", function()
            local ok, msg = Farm.WaterAll(S.data)
            commit(ok, msg)
        end, { fontSize = 13, enabled = Farm.RepLevel(S.data) >= 2 })
        UI.Button("plot_close", x + w - 96, y + 30, 80, 36, "关闭", function()
            S.farmPlot = nil
        end, { fontSize = 13 })
    elseif info.status == "mature" then
        UI.Text(x + 24, y + 14, 13,
            string.format("第 %d 块地 · %s 已成熟，收获可得 %d 个%s", idx,
                info.crop.name, info.crop.yield, info.crop.fruitName), S.col.text)
        UI.Button("art_harvest", x + 24, y + 40, 220, 40, "收获", function()
            local ok, msg = Farm.Harvest(S.data, idx)
            S.farmPlot = nil
            commit(ok, msg)
        end, { fontSize = 15, fill = { 58, 70, 38, 255 }, stroke = { 190, 190, 100, 255 } })
        UI.Button("plot_close", x + w - 96, y + 30, 80, 36, "关闭", function()
            S.farmPlot = nil
        end, { fontSize = 13 })
    end
end

local function drawFarmTabArt()
    -- 先注册整张地图的点击区（点一下走过去），地块区后注册，优先级更高
    UI.Region("farm_walk_area", 0, 58, Config.DESIGN_W, 560, function()
        FarmWalk.WalkToDesign(S.clickDX or 0, S.clickDY or 0)
    end, true)
    for i = 1, 9 do drawArtPlot(i) end
    drawPlotCard()
    FarmWalk.Draw()
    if FarmWalk.nearest then
        UI.Button("farm_interact", 1130, 600, 130, 46, "交互 E", function()
            FarmWalk.Interact()
        end, { fontSize = 15, fill = { 46, 78, 54, 255 }, stroke = { 130, 210, 150, 255 } })
    end
    if S.dev then
        UI.Button("farm_dev_next", 24, 664, 132, 30, "下一阶段（选中）", function()
            local n = Farm.DebugNextStage(S.data, S.farmPlot)
            Save.Write(S.data)
            if n > 0 then
                toast("测试：推进了 " .. n .. " 块地")
            else
                toast("选一块生长中的地再点", 1.8)
            end
        end, { fontSize = 11 })
        UI.Button("farm_dev_ripe", 164, 664, 110, 30, "全部成熟", function()
            Farm.DebugRipenAll(S.data)
            Save.Write(S.data)
            toast("测试：所有作物已成熟")
        end, { fontSize = 12 })
        UI.Button("farm_dev_rep", 282, 664, 110, 30, "声望 +100", function()
            Farm.DebugAddRep(S.data, 100)
            Save.Write(S.data)
            toast("测试：声望 +100")
        end, { fontSize = 12 })
    end
end

-- ---------------------------------------------------------------- 主入口
function FarmUI.Draw()
    Farm.Roll(S.data)
    nvgBeginPath(S.ctx)
    nvgRect(S.ctx, 0, 0, Config.DESIGN_W, Config.DESIGN_H)
    nvgFillColor(S.ctx, nvgRGBA(9, 11, 9, 255))
    nvgFill(S.ctx)

    -- 有底图就走实景地图模式；底图没加载出来时回退到原来的矢量面板
    local artOK = FarmArt.DrawMap()
    if artOK then
        drawSlimHeader()
        local tab = S.farmTab or 1
        if tab == 2 then
            drawFruitTab()
        elseif tab == 3 then
            drawShopTab()
        else
            drawFarmTabArt()
        end
        return
    end

    nvgBeginPath(S.ctx)
    nvgRect(S.ctx, 0, 0, Config.DESIGN_W, Config.DESIGN_H)
    nvgFillColor(S.ctx, nvgRGBA(10, 12, 10, 215))
    nvgFill(S.ctx)

    drawHeader()
    local tab = S.farmTab or 1
    if tab == 2 then
        drawFruitTab()
    elseif tab == 3 then
        drawShopTab()
    else
        drawFarmTab()
    end
end

return FarmUI
