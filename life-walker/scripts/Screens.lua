-- Screens.lua — 地图 / 商店 / 事件 / 通关 / 失败

local Save = require "Save"
local Config = require "Config"
local Run = require "Run"
local UI = require "UI"
local S = require "State"
local Combat = require "Combat"

local Screens = {}

-- ---------------------------------------------------------------- 地图
function Screens.DrawMap()
    local run = S.run
    if not run then return end
    local p = run.player

    -- 选关时也能查看状态/强化面板
    if S.showStatus then
        S.statusPanel = S.statusPanel or { page = 1, detail = nil }
        Combat.DrawStatusPanel(p, run, S.statusPanel,
            "选关界面 · 点击强化名字查看效果 · Esc 返回",
            function()
                S.showStatus = false
                S.statusPanel.detail = nil
            end)
        return
    end

    UI.Text(64, 36, 38, "第 " .. run.level .. " 关", S.col.text)
    UI.Text(64, 88, 16, "选择一个相邻房间前进", S.col.dim)

    UI.Panel(980, 34, 236, 72, 12, S.col.panel, S.col.line, 1)
    UI.Text(998, 48, 15, "银币", S.col.dim)
    UI.Text(1056, 44, 22, tostring(run.silver), S.col.gold)
    UI.Text(998, 76, 15, "生命", S.col.dim)
    UI.Text(1056, 72, 18, math.floor(p.hp) .. " / " .. p.maxHp, S.col.text)
    UI.Button("map_status", 980, 114, 236, 34, "状态面板", function()
        S.showStatus = true
        S.statusPanel = S.statusPanel or { page = 1, detail = nil }
    end, { fontSize = 14 })

    local cell = 120
    local gap = 16
    local x0 = (Config.DESIGN_W - (4 * cell + 3 * gap)) / 2
    local y0 = 140

    for r = 1, 4 do
        for c = 1, 4 do
            local x = x0 + (c - 1) * (cell + gap)
            local y = y0 + (r - 1) * (cell + gap)
            local key = Run.Key(r, c)
            local visited = run.visited[key]
            local isCurrent = (r == run.posR and c == run.posC)
            local canMove = Run.CanMove(r, c)
            local roomType = Run.CellType(r, c)
            local label = Config.RoomIcons[roomType] or "?"
            if not visited and not canMove then label = "?" end

            local fill = { 40, 36, 52, 255 }
            local stroke = S.col.line
            local textColor = S.col.dim
            if visited then
                fill = { 34, 54, 46, 255 }
                stroke = { 80, 140, 110, 255 }
                textColor = S.col.text
            end
            if canMove then
                if not visited then
                    fill = { 50, 46, 72, 255 }
                end
                stroke = S.col.cyan
                textColor = S.col.text
            end
            if isCurrent then
                fill = { 42, 78, 90, 255 }
                stroke = S.col.cyan
                textColor = S.col.text
            end

            UI.Panel(x, y, cell, cell, 14, fill, stroke, isCurrent and 3 or 1)
            UI.Text(x + cell / 2, y + cell / 2 - 6, 34, label, textColor,
                NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            if visited or canMove or isCurrent then
                local name = isCurrent and "当前位置" or (Config.RoomNames[roomType] or "")
                UI.Text(x + cell / 2, y + cell - 24, 14, name, S.col.dim,
                    NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
            end

            if canMove then
                UI.Region("cell_" .. r .. "_" .. c, x, y, cell, cell, function()
                    Run.Move(r, c)
                end, true)
            end
        end
    end

    -- 连线
    for r = 1, 4 do
        for c = 1, 4 do
            local x = x0 + (c - 1) * (cell + gap)
            local y = y0 + (r - 1) * (cell + gap)
            if c < 4 then
                UI.Line(x + cell, y + cell / 2, x + cell + gap, y + cell / 2, { 60, 54, 78, 160 }, 2)
            end
            if r < 4 then
                UI.Line(x + cell / 2, y + cell, x + cell / 2, y + cell + gap, { 60, 54, 78, 160 }, 2)
            end
        end
    end

    UI.Text(64, 108, 15, "白框 = 新房间（向右 / 上 / 下）；绿色 = 已清空，可以回头穿行。", S.col.dim)

    UI.Button("retreat", 1100, 640, 120, 44, "撤退", function()
        Run.Abort()
    end, { fontSize = 18, fill = { 52, 34, 38, 255 }, stroke = { 120, 60, 66, 255 } })
end

-- ---------------------------------------------------------------- 商店
function Screens.DrawShop()
    local run = S.run
    local shop = run and run.shop
    if not shop then return end

    UI.Text(64, 34, 34, "商店", S.col.text)
    UI.Text(180, 46, 16, "本关银币，离开关卡不保留", S.col.dim)
    UI.Text(1116, 36, 22, "银币 " .. tostring(run.silver), S.col.gold, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)

    for i = 1, 10 do
        local slot = shop.slots[i]
        local col = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        local x = 64 + col * 590
        local y = 116 + row * 98
        local w, h = 560, 86

        local fill = { 38, 34, 50, 255 }
        local stroke = S.col.line
        if slot.kind == "buff" then
            local c = Config.Rarity[slot.rarity].color
            stroke = c
        end
        if slot.sold then
            fill = { 30, 28, 38, 255 }
            stroke = { 56, 52, 66, 255 }
        end
        UI.Panel(x, y, w, h, 12, fill, stroke, 1)

        if slot.kind == "empty" or slot.sold then
            UI.Text(x + w / 2, y + h / 2, 18, "已售出", S.col.dim,
                NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        else
            local nameColor = S.col.text
            if slot.kind == "buff" then
                nameColor = Config.Rarity[slot.rarity].color
            elseif slot.kind == "potion" then
                nameColor = S.col.red
            elseif slot.kind == "consumable" then
                nameColor = S.col.cyan
            end
            UI.Text(x + 20, y + 14, 20, slot.name, nameColor)
            if slot.classBuff then
                UI.Text(x + w - 150, y + 18, 13, Config.Class().name .. "专属", S.col.orange,
                    NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
            end
            UI.TextBox(x + 20, y + 43, w - 165, 10.5, slot.desc, S.col.dim)
            UI.Text(x + w - 20, y + 20, 22, tostring(slot.price) .. " 银币", S.col.gold,
                NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
            local affordable = run.silver >= slot.price
            UI.Button("buy_" .. i, x + w - 130, y + h - 40, 110, 30,
                affordable and "购买" or "银币不足", function()
                    Run.BuySlot(i)
                end, { fontSize = 16, enabled = affordable,
                    fill = { 44, 64, 52, 255 }, stroke = { 80, 130, 96, 255 } })
        end
    end

    UI.Text(64, 628, 15, "药水 / 道具购买后进入道具栏，战斗中按 E 或点道具按钮；每店 1 次免费刷新，付费 12 银币 / 次，最多 3 次。",
        S.col.dim)
    local refreshLabel = shop.freeRefreshUsed and ("刷新 (" .. shop.paidRefresh .. "/3)") or "免费刷新"
    UI.Button("refresh", 920, 648, 150, 44, refreshLabel, function()
        Run.Refresh()
    end, { fontSize = 17 })
    UI.Button("leave_shop", 1088, 648, 130, 44, "离开", function()
        Run.CloseShop()
    end, { fontSize = 18, fill = { 40, 62, 48, 255 }, stroke = { 80, 130, 96, 255 } })
end

-- ---------------------------------------------------------------- 事件
function Screens.DrawEvent()
    local run = S.run
    local ev = run and run.event
    if not ev then return end

    UI.Panel(180, 96, 920, 528, 18, { 28, 24, 38, 245 }, S.col.line, 1)
    UI.Text(220, 124, 30, ev.title, S.col.gold)
    UI.TextBox(220, 174, 840, 19, ev.text, S.col.text)

    if not ev.result then
        local y = 270
        for i, opt in ipairs(ev.options) do
            local enabled = opt.enabled ~= false
            UI.Button("event_opt_" .. i, 260, y, 760, 54, opt.label, function()
                Run.ChooseEvent(i)
            end, { fontSize = 19, enabled = enabled,
                fill = enabled and { 44, 48, 66, 255 } or { 38, 36, 46, 255 } })
            y = y + 66
        end
    else
        UI.Panel(240, 300, 800, 130, 12, { 34, 40, 50, 255 }, S.col.cyan, 1)
        UI.TextBox(264, 322, 752, 20, ev.result, S.col.text)
        UI.Button("event_leave", 500, 470, 280, 56, "离开事件房", function()
            Run.CloseEvent()
        end, { fontSize = 20, fill = { 40, 62, 48, 255 }, stroke = { 80, 130, 96, 255 } })
    end
end

-- ---------------------------------------------------------------- 战斗奖励
function Screens.DrawReward()
    local reward = S.reward
    local run = S.run
    if not reward or not run then return end

    UI.Text(640, 54, 36, "战斗胜利 · 选择一项强化", S.col.gold,
        NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    UI.Text(640, 108, 16, "房间难度越高，高品质 Buff 的出现概率越大", S.col.dim,
        NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    UI.Text(640, 136, 14, "当前银币 " .. tostring(run.silver), S.col.dim,
        NVG_ALIGN_CENTER + NVG_ALIGN_TOP)

    for i, buff in ipairs(reward.options) do
        local x = 100 + (i - 1) * 370
        local y = 176
        local w, h = 340, 330
        local rarity = Config.Rarity[buff.rarity]
        local rc = rarity.color

        UI.Panel(x, y, w, h, 16, { 34, 30, 46, 255 }, rc, 3)
        UI.Text(x + 20, y + 18, 16, rarity.name, rc)
        if buff.classBuff then
            UI.Text(x + w - 20, y + 18, 14, Config.Class().name .. "专属", S.col.orange,
                NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
        end
        UI.Text(x + 20, y + 52, 26, buff.name, S.col.text)
        UI.TextBox(x + 20, y + 98, w - 40, 16, buff.desc, S.col.dim)
        UI.Button("reward_btn_" .. i, x + 20, y + h - 62, w - 40, 44, "选择", function()
            Run.ChooseReward(i)
        end, { fontSize = 18, fill = { 42, 58, 48, 255 }, stroke = { 80, 120, 90, 255 } })
        UI.Region("reward_card_" .. i, x, y, w, h, function()
            Run.ChooseReward(i)
        end, true)
    end

    UI.Button("skip_reward", 490, 550, 300, 52, "跳过，拿 15 银币", function()
        Run.SkipReward()
    end, { fontSize = 18 })
end

-- ---------------------------------------------------------------- 结算
function Screens.DrawLevelClear()
    local run = S.run
    UI.Text(640, 150, 54, "第 " .. (run and run.level or 0) .. " 关 通关", S.col.gold,
        NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    UI.Text(640, 230, 20, "疾病派系被击退，主线又前进了一步。", S.col.dim,
        NVG_ALIGN_CENTER + NVG_ALIGN_TOP)

    if run then
        UI.Panel(440, 296, 400, 150, 14, S.col.panel, S.col.line, 1)
        UI.Text(466, 318, 18, "本关银币", S.col.dim)
        UI.Text(814, 318, 20, tostring(run.silver), S.col.gold, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
        UI.Text(466, 356, 18, "获得 Buff", S.col.dim)
        UI.Text(814, 356, 20, tostring(#run.player.buffs), S.col.text, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
        UI.Text(466, 394, 18, Config.Class().name .. "等级", S.col.dim)
        UI.Text(814, 394, 20, "Lv." .. Save.ClassLevel(S.data), S.col.text, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
    end

    UI.Button("clear_menu", 490, 500, 300, 64, "返回主菜单", function()
        Run.ReturnToMenu()
    end, { fontSize = 22, fill = { 40, 62, 48, 255 }, stroke = { 80, 130, 96, 255 } })
end

function Screens.DrawGameOver()
    UI.Text(640, 160, 56, "倒下了", S.col.red, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    UI.Text(640, 240, 20, "本关进度丢失，调整构筑再来一次。", S.col.dim,
        NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    UI.Button("over_menu", 490, 340, 300, 64, "返回主菜单", function()
        Run.ReturnToMenu()
    end, { fontSize = 22, fill = { 52, 34, 38, 255 }, stroke = { 120, 60, 66, 255 } })
end

return Screens
