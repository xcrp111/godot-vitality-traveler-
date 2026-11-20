-- PetUI.lua — 宠物系统界面（口径：《宠物系统（最新）.docx》）
-- 五个页签：孵蛋匣 / 仓库 / 图鉴 / 家园 / 商店。纯收集，没有任何战力加成。

local Config = require "Config"
local Save = require "Save"
local UI = require "UI"
local S = require "State"
local Economy = require "Economy"
local PetData = require "PetData"
local Pet = require "Pet"

local PetUI = {}

local TABS = {
    { id = 1, name = "孵蛋匣" },
    { id = 2, name = "仓库" },
    { id = 3, name = "图鉴" },
    { id = 4, name = "家园" },
    { id = 5, name = "商店" },
}

local function FmtLeft(sec)
    sec = math.max(0, math.floor(sec or 0))
    if sec <= 0 then return "已孵化" end
    local h = math.floor(sec / 3600)
    local m = math.floor((sec % 3600) / 60)
    if h > 0 then return string.format("%d 小时 %d 分", h, m) end
    return string.format("%d 分", m)
end

local function TierColor(tier)
    local t = PetData.TierInfo(tier)
    return t.color or S.col.text
end

local function AttrColor(attr)
    return PetData.AttrInfo(attr).color
end

-- ---------------------------------------------------------------- 孵蛋匣
local function DrawGacha(data)
    local p = Pet.Ensure(data)
    local g = PetData.Gacha

    UI.Panel(64, 122, 520, 400, 14, S.col.panel, S.col.cyan, 1)
    UI.Text(84, 138, 20, "灵宠孵蛋匣", S.col.gold)
    UI.TextBox(84, 170, 480, 12,
        "单抽 / 十连都可以，十连不改变基础概率，只是省操作。重复宠物蛋会自动折算宠物代币，蛋不会进仓库。",
        S.col.dim)

    local y = 214
    UI.Text(84, y, 14, "基础概率", S.col.text)
    local odds = { { "低阶", g.odds.low, "low" }, { "高阶", g.odds.high, "high" }, { "究极", g.odds.ultra, "ultra" } }
    for i, o in ipairs(odds) do
        UI.Text(104, y + 26 + (i - 1) * 22, 13, string.format("%s宠物蛋", o[1]), TierColor(o[3]))
        UI.Text(320, y + 26 + (i - 1) * 22, 13, o[2] .. "%", S.col.dim, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
    end

    -- 保底进度
    local py = 320
    UI.Text(84, py, 14, "保底进度", S.col.text)
    local p10 = p.pity10 % g.pity10
    UI.Bar(104, py + 24, 300, 10, p10 / g.pity10, S.col.cyan, { 26, 22, 42, 255 }, S.col.line)
    UI.Text(414, py + 20, 12, string.format("十连保底 %d/%d", p10, g.pity10), S.col.dim)
    UI.Bar(104, py + 44, 300, 10, p.pity90 / g.pity90, S.col.purple, { 26, 22, 42, 255 }, S.col.line)
    UI.Text(414, py + 40, 12, string.format("究极大保底 %d/%d", p.pity90, g.pity90), S.col.dim)

    -- 抽蛋按钮
    local canOnce = p.coins >= g.priceOnce
    local canTen = p.coins >= g.priceTen
    local full = #p.eggs >= Pet.EggCap(data)
    UI.Button("pet_draw1", 84, 392, 220, 44,
        string.format("抽一次 · %d 代币", g.priceOnce), function()
            local ok, msg = Pet.Draw(S.data, 1)
            UI.SetToast(msg, 2.8)
            if ok then
                S.petLastDraw = nil
                Save.Write(S.data)
            end
        end, { fontSize = 16, enabled = canOnce and not full,
            fill = { 40, 116, 74, 255 }, stroke = S.col.green })

    UI.Button("pet_draw10", 320, 392, 244, 44,
        string.format("十连 · %d 代币", g.priceTen), function()
            local ok, msg, results = Pet.Draw(S.data, 10)
            UI.SetToast(msg, 3.0)
            if ok then
                S.petLastDraw = results
                Save.Write(S.data)
            end
        end, { fontSize = 16, enabled = canTen and not full,
            fill = { 96, 62, 148, 255 }, stroke = S.col.purple })

    -- 精粹兑换宠物代币（价格沿用旧版抽卡：5 精粹 = 20 代币）
    local ess = Economy.Essence(data)
    for i, pack in ipairs(PetData.CoinPacks) do
        local x = 84 + (i - 1) * 244
        local w = (i == 1) and 220 or 244
        UI.Button("pet_buycoin_" .. i, x, 444, w, 32,
            string.format("精粹 %d → %d 代币", pack.essence, pack.coins), function()
                local ok, msg = Pet.BuyCoinsWithEssence(S.data, i)
                UI.SetToast(msg, 2.4)
                if ok then Save.Write(S.data) end
            end, { fontSize = 13, enabled = ess >= pack.essence,
                fill = { 132, 100, 44, 255 }, stroke = S.col.gold })
    end

    UI.Text(84, 488, 12, string.format("宠物蛋仓库 %d / %d　·　宠物仓库 %d / %d　·　孵化槽 %d / %d",
        #p.eggs, Pet.EggCap(data), #p.pets, Pet.PetCap(data), Pet.SlotsUsed(data), Pet.Slots(data)), S.col.dim)

    -- 右：最近一次抽蛋结果
    UI.Panel(608, 122, 608, 400, 14, S.col.panel, S.col.cyan, 1)
    UI.Text(628, 138, 20, "最近一次结果", S.col.gold)
    local results = S.petLastDraw
    if not results or #results == 0 then
        UI.Text(912, 270, 14, "还没有抽过，点左边按钮开始", S.col.dim, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    else
        for i, r in ipairs(results) do
            if i > 10 then break end
            local col = (i - 1) % 2
            local row = math.floor((i - 1) / 2)
            local x = 628 + col * 292
            local y = 172 + row * 52
            local pet = r.pet
            UI.Panel(x, y, 280, 44, 8, { 88, 72, 126, 255 }, TierColor(r.tier), 1)
            UI.Text(x + 12, y + 6, 13, pet and PetData.Name(pet) or "?", TierColor(r.tier))
            UI.Text(x + 12, y + 24, 11, PetData.TierInfo(r.tier).name .. " · " ..
                PetData.AttrInfo(pet and pet.attr or "").name, S.col.dim)
            if r.coins then
                UI.Text(x + 268, y + 14, 12, "+" .. r.coins .. " 代币", S.col.gold,
                    NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
            elseif r.hatching then
                UI.Text(x + 268, y + 14, 12, "已入仓库", S.col.green,
                    NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
            else
                UI.Text(x + 268, y + 14, 12, "仓库满→折币", S.col.orange,
                    NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
            end
        end
    end
end

-- ---------------------------------------------------------------- 仓库
-- 宠物蛋列表可视区域：每行 44 高，一次显示 10 行，可上下滚动
local LIST = { x = 76, y = 178, w = 1000, rowH = 44, visible = 10 }

local function EggListMaxScroll(count)
    return math.max(0, count - LIST.visible)
end

local function EggClampedScroll(count)
    local maxS = EggListMaxScroll(count)
    local s = math.floor(S.petEggScroll or 0)
    if s < 0 then s = 0 end
    if s > maxS then s = maxS end
    S.petEggScroll = s
    return s, maxS
end

local function EggListVisible()
    return S.pet and (S.petTab or 1) == 2 and (S.petBagTab or 1) == 1
end

local function DrawStorage(data)
    local p = Pet.Ensure(data)
    Pet.Sweep(data)
    local isPetTab = (S.petBagTab or 1) == 2

    UI.Button("pet_bag_egg", 64, 122, 140, 34, "宠物蛋", function()
        S.petBagTab = 1
    end, { fontSize = 15, fill = not isPetTab and { 40, 132, 176, 255 } or { 74, 60, 106, 255 },
        stroke = not isPetTab and S.col.cyan or S.col.line })
    UI.Button("pet_bag_pet", 212, 122, 140, 34, "宠物", function()
        S.petBagTab = 2
    end, { fontSize = 15, fill = isPetTab and { 40, 132, 176, 255 } or { 74, 60, 106, 255 },
        stroke = isPetTab and S.col.cyan or S.col.line })

    local capText = isPetTab
        and string.format("宠物 %d / %d 格", #p.pets, Pet.PetCap(data))
        or string.format("宠物蛋 %d / %d 格", #p.eggs, Pet.EggCap(data))
    UI.Text(984, 130, 13, capText, S.col.dim, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
    UI.Button("pet_cap_buy", 1000, 122, 200, 34,
        string.format("扩容 +%d 格 · %d 代币", PetData.CapStep, Pet.CapPrice(data)), function()
            local ok, msg = Pet.Buy(S.data, "cap")
            UI.SetToast(msg, 2.4)
            if ok then Save.Write(S.data) end
        end, { fontSize = 13, enabled = p.coins >= Pet.CapPrice(data),
            fill = { 96, 62, 148, 255 }, stroke = S.col.purple })

    if isPetTab then
        if #p.pets == 0 then
            UI.Text(640, 380, 16, "还没有孵出宠物：去「孵蛋匣」抽蛋", S.col.dim,
                NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
            return
        end
        for i, id in ipairs(p.pets) do
            if i > 24 then break end
            local pet = PetData.Get(id)
            local col = (i - 1) % 4
            local row = math.floor((i - 1) / 4)
            local x = 76 + col * 292
            local y = 176 + row * 96
            UI.Panel(x, y, 276, 84, 10, { 88, 72, 126, 255 }, TierColor(pet.tier), 2)
            UI.Text(x + 12, y + 8, 15, PetData.Name(pet), TierColor(pet.tier))
            UI.Text(x + 264, y + 10, 11, PetData.TierInfo(pet.tier).name,
                S.col.dim, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
            UI.Text(x + 12, y + 30, 11, PetData.AttrInfo(pet.attr).name .. "属性",
                AttrColor(pet.attr))
            UI.TextBox(x + 12, y + 48, 250, 10, PetData.ChainText(pet), S.col.dim)
        end
    else
        if #p.eggs == 0 then
            UI.Text(640, 380, 16, "宠物蛋仓库是空的", S.col.dim, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
            return
        end

        local scroll, maxScroll = EggClampedScroll(#p.eggs)
        local from = scroll + 1
        local to = math.min(#p.eggs, scroll + LIST.visible)

        -- 孵化槽占用
        UI.Text(LIST.x, 158, 12, string.format("孵化槽 %d / %d（同时最多孵这么多颗，其余排队）",
            Pet.SlotsUsed(data), Pet.Slots(data)), S.col.cyan)

        -- 滚动区域在上面先登记，保证列表行内的按钮能正常点击
        for i = from, to do
            local egg = p.eggs[i]
            local pet = PetData.Get(egg.id)
            local left = Pet.EggLeft(egg)
            local waiting = egg.state == "waiting"
            local ready = (not waiting) and left <= 0
            local y = LIST.y + (i - from) * LIST.rowH
            local fill = waiting and { 74, 66, 96, 255 }
                or (ready and { 40, 108, 68, 255 } or { 88, 72, 126, 255 })
            UI.Panel(LIST.x, y, LIST.w, 38, 8, fill,
                ready and S.col.green or (waiting and S.col.line or S.col.cyan), 1)
            UI.Text(LIST.x + 16, y + 10, 14, PetData.Name(pet), TierColor(pet.tier))
            UI.Text(LIST.x + 224, y + 12, 11, PetData.TierInfo(pet.tier).name .. " · " ..
                PetData.AttrInfo(pet.attr).name, S.col.dim)
            local stateText
            if waiting then
                stateText = "排队中（等孵化槽）"
            elseif ready then
                stateText = "已孵化，去「宠物」页领取"
            else
                stateText = FmtLeft(left)
            end
            UI.Text(LIST.x + 484, y + 12, 12, stateText,
                ready and S.col.green or (waiting and S.col.dim or S.col.cyan))
            UI.Button("pet_speed_" .. i, LIST.x + 824, y + 5, 160, 28,
                "加速卡 · 4h", function()
                    local ok, msg = Pet.Buy(S.data, "speed", i)
                    UI.SetToast(msg, 2.4)
                    if ok then Save.Write(S.data) end
                end, { fontSize = 12,
                    enabled = PetData.ShopItem("speed").price <= p.coins and not waiting and not ready,
                    fill = { 96, 62, 148, 255 }, stroke = S.col.purple })
        end

        -- 滚动条 + 上下按钮
        local trackX, trackY, trackW, trackH = 1088, LIST.y, 8, LIST.visible * LIST.rowH - 6
        UI.Panel(trackX, trackY, trackW, trackH, 4, { 40, 34, 56, 255 }, S.col.line, 1)
        if maxScroll > 0 then
            local ratio = LIST.visible / #p.eggs
            local thumbH = math.max(24, math.floor(trackH * ratio))
            local thumbY = trackY + math.floor((trackH - thumbH) * (scroll / maxScroll))
            UI.Panel(trackX, thumbY, trackW, thumbH, 4, S.col.cyan)
        end
        UI.Button("pet_egg_up", 1102, LIST.y, 44, 30, "▲", function()
            S.petEggScroll = math.max(0, EggClampedScroll(#p.eggs) - 1)
        end, { fontSize = 14, enabled = scroll > 0 })
        UI.Button("pet_egg_down", 1102, LIST.y + LIST.visible * LIST.rowH - 36, 44, 30, "▼", function()
            local s, maxS = EggClampedScroll(#p.eggs)
            S.petEggScroll = math.min(maxS, s + 1)
        end, { fontSize = 14, enabled = scroll < maxScroll })

        UI.Text(LIST.x, LIST.y + LIST.visible * LIST.rowH + 4, 12,
            string.format("显示第 %d~%d 颗 / 共 %d 颗（滚轮或拖拽列表上下滚动）", from, to, #p.eggs), S.col.dim)
    end
end

-- ---------------------------------------------------------------- 滚动输入（仅宠物蛋列表）
local DRAG = { x = 76, x2 = 890, y = 178, y2 = 618 }

--- 滚轮：返回 true 表示吃掉这次输入
function PetUI.Wheel(delta)
    if not EggListVisible() then return false end
    local data = S.data
    local p = Pet.Ensure(data)
    local s = EggClampedScroll(#p.eggs)
    S.petEggScroll = s - delta
    EggClampedScroll(#p.eggs)
    return true
end

--- 拖拽滚动：只在列表左侧空白区（避开加速按钮列）接管
function PetUI.Pointer(phase, x, y)
    if not EggListVisible() then
        if phase == "up" then S.petEggDrag = nil end
        return false
    end
    local drag = S.petEggDrag
    if phase == "down" then
        if x >= DRAG.x and x <= DRAG.x2 and y >= DRAG.y and y <= DRAG.y2 then
            local p = Pet.Ensure(S.data)
            S.petEggDrag = { y0 = y, s0 = EggClampedScroll(#p.eggs) }
            return true
        end
        return false
    elseif phase == "move" then
        if not drag then return false end
        local p = Pet.Ensure(S.data)
        local rowDelta = math.floor((y - drag.y0) / LIST.rowH)
        S.petEggScroll = drag.s0 - rowDelta
        EggClampedScroll(#p.eggs)
        return true
    elseif phase == "up" then
        if drag then
            S.petEggDrag = nil
            return true
        end
        return false
    end
    return false
end

-- ---------------------------------------------------------------- 图鉴
local function DrawCodex(data)
    local p = Pet.Ensure(data)
    local attr = S.petAttr or "fire"

    UI.Text(84, 130, 13, string.format("已点亮 %d / %d　·　称号 %d 个",
        Pet.Unlocked(data), PetData.TotalCount(), Pet.TitleCount(data)), S.col.dim)

    -- 属性分页
    for i, a in ipairs(PetData.Attrs) do
        local active = attr == a.id
        UI.Button("pet_attr_" .. a.id, 64 + (i - 1) * 104, 152, 96, 30, a.name, function()
            S.petAttr = a.id
        end, { fontSize = 14, fill = active and { 40, 132, 176, 255 } or { 74, 60, 106, 255 },
            stroke = active and a.color or S.col.line })
    end

    -- 该属性宠物列表
    local y = 196
    local n = 0
    for _, pet in ipairs(PetData.List) do
        if pet.attr == attr then
            n = n + 1
            local seen = Pet.IsSeen(data, pet.id)
            local col = (n - 1) % 2
            local row = math.floor((n - 1) / 2)
            local x = 76 + col * 452
            local yy = y + row * 74
            UI.Panel(x, yy, 436, 64, 10, seen and { 88, 72, 126, 255 } or { 52, 48, 70, 255 },
                seen and TierColor(pet.tier) or S.col.line, seen and 2 or 1)
            if seen then
                UI.Text(x + 14, yy + 8, 16, PetData.Name(pet), TierColor(pet.tier))
                UI.Text(x + 422, yy + 10, 11, PetData.TierInfo(pet.tier).name, S.col.dim,
                    NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
                UI.TextBox(x + 14, yy + 34, 400, 11, PetData.ChainText(pet), S.col.dim)
            else
                UI.Text(x + 14, yy + 8, 16, "？？？", S.col.line)
                UI.Text(x + 422, yy + 10, 11, PetData.TierInfo(pet.tier).name, S.col.dim,
                    NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
                UI.TextBox(x + 14, yy + 34, 400, 11, "进化路线：" .. PetData.ChainText(pet), S.col.dim)
            end
        end
    end

    -- 阶段奖励
    local ry = 502
    UI.Text(76, ry, 14, "图鉴阶段奖励", S.col.gold)
    for i, r in ipairs(PetData.Rewards) do
        local progress, need, done, claimed = Pet.RewardState(data, r)
        local col = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        local x = 76 + col * 590
        local yy = ry + 26 + row * 22 + row * 12
        UI.Panel(x, yy, 574, 32, 8, claimed and { 40, 100, 62, 255 } or { 74, 60, 106, 255 },
            claimed and S.col.green or S.col.line, 1)
        UI.Text(x + 12, yy + 7, 13, r.desc, claimed and S.col.green or S.col.text)
        UI.Text(x + 400, yy + 8, 11, string.format("%d/%d", math.min(progress, need), need), S.col.dim)
        if claimed then
            UI.Text(x + 470, yy + 8, 11, "已领取", S.col.green)
        elseif done then
            UI.Button("pet_claim_" .. r.id, x + 470, yy + 3, 90, 26, "领取", function()
                local ok, msg = Pet.ClaimReward(S.data, r.id)
                UI.SetToast(msg, 2.8)
                if ok then Save.Write(S.data) end
            end, { fontSize = 12, fill = { 40, 116, 74, 255 }, stroke = S.col.green })
        else
            UI.Text(x + 470, yy + 8, 11, r.coins .. " 代币", S.col.dim)
        end
    end
end

-- ---------------------------------------------------------------- 家园
local function DrawHome(data)
    local p = Pet.Ensure(data)
    local plots = Pet.Plots(data)
    local today = Pet.FeedToday(data)

    UI.Text(84, 130, 13, string.format("家园互动 +%d 代币 / 次　·　今日 %d / %d　·　摆件 %d 件",
        PetData.Feed.coins, today, PetData.Feed.dailyCap, p.decor or 0), S.col.dim)

    for i, plot in ipairs(plots) do
        local col = (i - 1) % 4
        local row = math.floor((i - 1) / 4)
        local x = 76 + col * 292
        local y = 168 + row * 200
        local w, h = 276, 186
        local def = plot.def
        UI.Panel(x, y, w, h, 12, plot.locked and { 46, 42, 58, 255 } or { 74, 60, 106, 255 },
            plot.locked and S.col.line or (def.attr and AttrColor(def.attr) or S.col.green), 1)
        UI.Text(x + 14, y + 10, 15, def.name, plot.locked and S.col.dim or S.col.text)

        if plot.locked then
            UI.Text(x + w / 2, y + 80, 12,
                string.format("收集 1 只%s属性宠物解锁", PetData.AttrInfo(def.attr).name),
                S.col.dim, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        elseif plot.petId then
            local pet = PetData.Get(plot.petId)
            UI.Text(x + w / 2, y + 46, 18, PetData.Name(pet), TierColor(pet.tier),
                NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
            UI.Text(x + w / 2, y + 74, 11, PetData.ChainText(pet), S.col.dim,
                NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
            UI.Button("pet_feed_" .. def.id, x + 14, y + h - 76, 120, 30, "互动 +3",
                function()
                    local ok, msg = Pet.Feed(S.data, def.id)
                    UI.SetToast(msg, 2.2)
                    if ok then Save.Write(S.data) end
                end, { fontSize = 13, fill = { 40, 116, 74, 255 }, stroke = S.col.green })
            UI.Button("pet_unplace_" .. def.id, x + 142, y + h - 76, 120, 30, "收回",
                function()
                    Pet.RemoveFromPlot(S.data, def.id)
                    Save.Write(S.data)
                    UI.SetToast("已收回", 1.6)
                end, { fontSize = 13, fill = { 96, 62, 148, 255 }, stroke = S.col.purple })
        else
            UI.Text(x + w / 2, y + 60, 12, "空地（点下面选择要展示的宠物）", S.col.dim,
                NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
            -- 简单选择器：把拥有的宠物前 4 只做成按钮
            for j = 1, math.min(4, #p.pets) do
                local id = p.pets[j]
                local pet = PetData.Get(id)
                UI.Button("pet_place_" .. def.id .. "_" .. j,
                    x + 14 + ((j - 1) % 2) * 130, y + 96 + math.floor((j - 1) / 2) * 40,
                    120, 34, PetData.Name(pet), function()
                        Pet.Place(S.data, id, def.id)
                        Save.Write(S.data)
                        UI.SetToast("已放置 " .. PetData.Name(pet), 1.8)
                    end, { fontSize = 12, fill = { 62, 78, 138, 255 }, stroke = S.col.cyan })
            end
            if #p.pets == 0 then
                UI.Text(x + w / 2, y + 120, 11, "还没有宠物", S.col.dim,
                    NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
            end
        end
    end

    UI.Text(76, 596, 12, "家园只用于展示与互动，宠物、摆件、地块都不提供任何属性或战力加成。", S.col.dim)
end

-- ---------------------------------------------------------------- 商店
local function DrawShop(data)
    local p = Pet.Ensure(data)
    UI.Text(84, 130, 13, string.format("只收宠物代币　·　当前 %s　·　商店不出售究极蛋",
        UI.FormatNumber(p.coins)), S.col.dim)

    for i, item in ipairs(PetData.Shop) do
        local price = item.price
        if item.id == "cap" then price = Pet.CapPrice(data) end
        if item.id == "slot" then price = Pet.SlotPrice(data) or 0 end
        local col = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        local x = 76 + col * 578
        local y = 168 + row * 108
        local can = p.coins >= price
        local soldOut = (item.id == "bg" and p.bgOwned) or (item.id == "slot" and Pet.SlotPrice(data) == nil)
        UI.Panel(x, y, 562, 96, 12, soldOut and { 40, 100, 62, 255 } or S.col.panel,
            soldOut and S.col.green or S.col.line, 1)
        UI.Text(x + 16, y + 10, 17, item.name, S.col.text)
        UI.Text(x + 546, y + 8, 18, price .. " 代币", can and S.col.gold or S.col.red,
            NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
        UI.TextBox(x + 16, y + 38, 400, 11,
            item.id == "slot" and string.format("同时孵化上限 +1（现在 %d / %d 个）",
                Pet.Slots(data), PetData.SlotMax) or item.desc, S.col.dim)
        if soldOut then
            UI.Text(x + 546, y + 62, 12, "已拥有", S.col.green, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
        elseif item.id == "egg_low" then
            UI.Button("pet_buy_" .. item.id, x + 430, y + 54, 116, 30, "选一只", function()
                S.petPickLow = true
            end, { fontSize = 13, enabled = can,
                fill = { 40, 116, 74, 255 }, stroke = S.col.green })
        elseif item.id == "speed" then
            UI.Button("pet_buy_" .. item.id, x + 430, y + 54, 116, 30, "去仓库用", function()
                S.petTab = 2
                S.petBagTab = 1
            end, { fontSize = 13, enabled = can,
                fill = { 62, 78, 138, 255 }, stroke = S.col.cyan })
        else
            UI.Button("pet_buy_" .. item.id, x + 430, y + 54, 116, 30, "购买", function()
                local ok, msg = Pet.Buy(S.data, item.id)
                UI.SetToast(msg, 2.4)
                if ok then Save.Write(S.data) end
            end, { fontSize = 13, enabled = can,
                fill = { 40, 116, 74, 255 }, stroke = S.col.green })
        end
    end

    -- 自选低阶蛋：弹出 10 只
    if S.petPickLow then
        UI.Panel(180, 200, 920, 340, 16, { 24, 20, 36, 250 }, S.col.cyan, 2)
        UI.Text(900, 216, 18, "选一只低阶宠物（60 代币）", S.col.gold,
            NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        local lows = PetData.Pool("low")
        for i, pet in ipairs(lows) do
            local col = (i - 1) % 5
            local row = math.floor((i - 1) / 5)
            local x = 212 + col * 172
            local y = 262 + row * 80
            UI.Button("pet_picklow_" .. pet.id, x, y, 160, 60,
                PetData.Name(pet) .. "\n" .. PetData.AttrInfo(pet.attr).name, function()
                    local ok, msg = Pet.Buy(S.data, "egg_low", pet.id)
                    UI.SetToast(msg, 2.6)
                    if ok then
                        S.petPickLow = false
                        Save.Write(S.data)
                    end
                end, { fontSize = 12, fill = { 62, 78, 138, 255 }, stroke = S.col.cyan })
        end
        UI.Button("pet_picklow_cancel", 560, 470, 160, 40, "取消", function()
            S.petPickLow = false
        end, { fontSize = 15 })
    end
end

-- ---------------------------------------------------------------- 主绘制
function PetUI.Draw()
    local data = S.data
    local p = Pet.Ensure(data)

    nvgBeginPath(S.ctx)
    nvgRect(S.ctx, 0, 0, Config.DESIGN_W, Config.DESIGN_H)
    nvgFillColor(S.ctx, nvgRGBA(S.col.bg[1], S.col.bg[2], S.col.bg[3], 246))
    nvgFill(S.ctx)

    UI.Text(64, 36, 32, "宠物", S.col.text)
    UI.Text(140, 48, 14, "纯收集系统：抽蛋 → 孵化 → 仓库 / 图鉴 / 家园，全程不加任何战力", S.col.dim)

    UI.Text(1104, 40, 18, "宠物代币 " .. UI.FormatNumber(p.coins), S.col.gold,
        NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
    UI.Text(1104, 64, 12, "精粹 " .. UI.FormatNumber(Economy.Essence(data)), S.col.dim,
        NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
    UI.Button("pet_close", 1136, 26, 88, 34, "关闭", function()
        S.pet = false
        S.petPickLow = false
    end, { fontSize = 15, fill = { 122, 52, 60, 255 }, stroke = S.col.red })

    for _, tab in ipairs(TABS) do
        local x = 64 + (tab.id - 1) * 112
        local active = (S.petTab or 1) == tab.id
        UI.Button("pet_tab_" .. tab.id, x, 82, 104, 34, tab.name, function()
            S.petTab = tab.id
            S.petPickLow = false
        end, { fontSize = 15,
            fill = active and { 40, 132, 176, 255 } or { 74, 60, 106, 255 },
            stroke = active and S.col.cyan or S.col.line, strokeW = active and 2 or 1 })
    end

    Pet.Sweep(data)

    if (S.petTab or 1) == 1 then
        DrawGacha(data)
    elseif S.petTab == 2 then
        DrawStorage(data)
    elseif S.petTab == 3 then
        DrawCodex(data)
    elseif S.petTab == 4 then
        DrawHome(data)
    else
        DrawShop(data)
    end
end

return PetUI
