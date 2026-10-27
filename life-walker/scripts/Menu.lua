-- Menu.lua — 主菜单 / 运动结算 / 角色升级 / 技能配置

local Config = require "Config"
local Save = require "Save"
local UI = require "UI"
local S = require "State"
local Run = require "Run"
local Combat = require "Combat"
local Audio = require "Audio"
local KbLayout = require "KbLayout"

local Menu = {}

local function DrawStat(x, y, label, value)
    UI.Text(x, y, 18, label, S.col.dim)
    UI.Text(x + 150, y, 22, value, S.col.text)
end

local function FixLoadout()
    local data = S.data
    Config.SetClass(Save.ActiveClass(data))
    local loadout = Save.Loadout(data)
    local classLevel = Save.ClassLevel(data)
    local unlocked = Save.UnlockedSkills(classLevel)
    local used = {}
    local changed = false
    for i = 1, 3 do
        local id = loadout[i]
        if not Save.IsSkillUnlocked(classLevel, id) then
            if loadout[i] ~= 0 then changed = true end
            loadout[i] = 0
        else
            used[id] = true
        end
    end
    for i = 1, 3 do
        if loadout[i] == 0 then
            for _, id in ipairs(unlocked) do
                if not used[id] then
                    loadout[i] = id
                    used[id] = true
                    changed = true
                    break
                end
            end
        end
    end
    if changed then
        Save.Write(data)
    end
end
Menu.FixLoadout = FixLoadout

local function StartLevel()
    Run.Start(S.selectedLevel)
end

local function ClassStatusLines()
    local class = Config.PlayerClass
    if class == "spearman" then
        return {
            "枪势：打满一套三段普攻获得 1 层（最多 3 层）；持有枪势时普攻范围 +1 格并施加失衡。",
            "失衡：最多 2 层、3 秒，敌人移速 -12%；消耗枪势的技能命中带挫裂目标触发震荡。",
            "三段枪式：5 秒内强化 3 次普攻，1A +40% 攻击、2A 吸血 25%、3A 强制击飞。",
        }
    elseif class == "ranger" then
        return {
            "猎痕：普攻命中施加，每层使目标受到的普攻伤害 +14%，最多 5 层。",
            "狩猎冲动：疾退腾挪获得 1 层（最多 3 层），每层攻速 +8%。",
            "追猎：失衡 + 猎痕触发，短时间提升自身攻速与移速。",
        }
    elseif class == "mage" then
        return {
            "元素亲和：出战 3 个同系技能触发专精（火：伤害 +25%；冰：控制 +50%；电：冷却 -20%），1 火 1 冰 1 电触发元素共鸣（全元素 +10%）。",
            "燃烧 / 冰冻：火技能挂燃烧，冰技能挂冰冻；火打冰冻触发融化，冰打燃烧触发蒸发。",
            "过载：电系技能命中燃烧/冰冻目标时，每个状态额外 +30% 伤害。",
        }
    end
    return {
        "剑意：普攻命中叠 1 层（最多 5 层），每层普攻伤害 +6%；5 层触发剑气爆发（1.5 倍范围伤害 + 1 层挫裂）。",
        "挫裂：每层使目标受到的全部物理伤害 +12%，最多 5 层，持续 4 秒、每秒掉 1 层；剑意 ≥3 层时普攻叠加挫裂。",
        "无敌：突进期间免疫伤害。格挡：1 秒内完全免伤（可连挡多次），格挡成功反击剑气、获得剑意并返还冷却。",
    }
end

function Menu.DrawSkillPicker()
    local slot = S.skillPicker or 1
    local data = S.data
    Config.SetClass(Save.ActiveClass(data))
    local loadout = Save.Loadout(data)
    local classLevel = Save.ClassLevel(data)

    nvgBeginPath(S.ctx)
    nvgRect(S.ctx, 0, 0, Config.DESIGN_W, Config.DESIGN_H)
    nvgFillColor(S.ctx, nvgRGBA(0, 0, 0, 195))
    nvgFill(S.ctx)

    UI.Panel(220, 36, 840, 648, 18, { 28, 24, 38, 250 }, S.col.line, 1)
    UI.Text(260, 62, 28, "选择出战技能 · 第 " .. slot .. " 格", S.col.text)
    UI.Text(260, 100, 15, "已解锁的技能可以自由搭配，同一技能不能重复装备", S.col.dim)

    for idx, sk in ipairs(Config.Skills) do
        local col = (idx - 1) % 3
        local row = math.floor((idx - 1) / 3)
        local x = 240 + col * 260
        local y = 132 + row * 150
        local w, h = 245, 132

        local unlocked = Save.IsSkillUnlocked(classLevel, sk.id)
        local equippedSlot = 0
        for j = 1, 3 do
            if loadout[j] == sk.id then equippedSlot = j end
        end
        local isCurrent = equippedSlot == slot

        local fill = { 40, 36, 52, 255 }
        local stroke = S.col.line
        local nameColor = S.col.text
        if not unlocked then
            fill = { 32, 30, 40, 255 }
            nameColor = { 110, 106, 120, 255 }
        elseif isCurrent then
            fill = { 38, 62, 72, 255 }
            stroke = S.col.cyan
        elseif equippedSlot > 0 then
            stroke = { 90, 120, 150, 255 }
        end

        UI.Panel(x, y, w, h, 12, fill, stroke, isCurrent and 3 or 1)
        UI.Text(x + 14, y + 10, 17, sk.name, nameColor)
        UI.TextBox(x + 14, y + 34, w - 28, 10.5, sk.desc or "", S.col.dim)
        UI.Text(x + 14, y + 112, 10, string.format("冷却 %.1f 秒", sk.cd), S.col.dim)

        if not unlocked then
            UI.Text(x + w - 14, y + 10, 12, "Lv." .. sk.unlockLevel .. " 解锁",
                { 120, 110, 130, 255 }, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
        elseif isCurrent then
            UI.Text(x + w - 14, y + 10, 12, "当前装备", S.col.cyan,
                NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
        elseif equippedSlot > 0 then
            UI.Text(x + w - 14, y + 10, 11, "第 " .. equippedSlot .. " 格 · 交换", S.col.dim,
                NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
        end

        if unlocked and not isCurrent then
            UI.Region("pick_" .. idx, x, y, w, h, function()
                local prev = loadout[slot]
                loadout[slot] = sk.id
                if equippedSlot > 0 then
                    loadout[equippedSlot] = prev
                end
                Save.Write(S.data)
                S.skillPicker = false
            end, true)
        end
    end

    UI.Text(260, 580, 14, "状态说明", S.col.gold)
    local lines = ClassStatusLines()
    for i, line in ipairs(lines) do
        UI.Text(260, 602 + (i - 1) * 18, 10.5, line, S.col.dim)
    end

    UI.Button("picker_close", 850, 612, 170, 40, "关闭", function()
        S.skillPicker = false
    end, { fontSize = 16 })
end

local KIND_NAMES = { minion = "小兵", elite = "精英", boss = "Boss" }

local function CompendiumMonsters()
    UI.Text(130, 196, 12,
        "小兵 HP = 25 × (1 + (N - 1) × 0.2)^1.4，ATK = 5 + (N - 1) × 0.9；精英 ×3.5 HP / ×1.8 ATK；Boss ×8 HP / ×2.5 ATK。带「第 7 关起」标记的怪物从第 7 关开始进入正常房间，也可以在测试模式直接选择。",
        S.col.dim)
    for i, m in ipairs(Config.Monsters) do
        local col = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        local x = 130 + col * 520
        local y = 224 + row * 110
        UI.Circle(x + 12, y + 12, 8, m.color)
        UI.Text(x + 32, y, 18, m.name, S.col.text)
        local kindText = KIND_NAMES[m.kind] or m.kind
        if m.lateGame then kindText = kindText .. " · 第 7 关起" end
        UI.Text(x + 180, y + 3, 13, kindText, m.lateGame and S.col.orange or S.col.dim)
        UI.TextBox(x + 32, y + 28, 450, 12, m.codex or m.desc, S.col.dim)
    end
end

local function CompendiumBuffs()
    UI.Text(130, 196, 12,
        "通用强化池。出现权重：白 35% / 蓝 30% / 紫 22% / 金 10%；" ..
        Config.Class().name .. "专属强化见「" .. Config.Class().name .. "专属」页。",
        S.col.dim)

    ---@type string[][]
    local columns = {
        { "white", "blue" },
        { "purple", "gold" },
    }
    ---@type number[]
    local colX = { 140, 670 }
    for ci = 1, 2 do
        local x = colX[ci] or 140
        local y = 228
        for _, rarity in ipairs(columns[ci] or {}) do
            local rc = Config.Rarity[rarity]
            UI.Text(x, y, 14, rc.name .. " · " .. rc.price .. " 银币", rc.color)
            y = y + 26
            for _, b in ipairs(Config.Buffs[rarity]) do
                UI.Text(x + 8, y, 12, b.name, rc.color)
                UI.Text(x + 138, y, 12, b.desc, S.col.dim)
                y = y + 22
            end
            y = y + 6
        end
    end
end

local function CompendiumSkills()
    local class = Config.Class()
    UI.Text(130, 196, 12,
        class.name .. " · " .. #Config.Skills .. " 个技能，出战携带 3 个；按等级解锁，10 级前全部解锁。",
        S.col.dim)
    for i, sk in ipairs(Config.Skills) do
        local col = (i - 1) % 3
        local row = math.floor((i - 1) / 3)
        local x = 130 + col * 330
        local y = 226 + row * 146
        local w, h = 320, 132
        UI.Panel(x, y, w, h, 12, { 38, 34, 50, 255 }, S.col.line, 1)
        UI.Text(x + 16, y + 12, 17, sk.name, S.col.text)
        UI.Text(x + w - 16, y + 14, 11, "Lv." .. sk.unlockLevel .. " 解锁", S.col.dim,
            NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
        UI.TextBox(x + 16, y + 38, w - 32, 10.5, sk.desc or "", S.col.dim)
        UI.Text(x + 16, y + 108, 10, string.format("冷却 %.1f 秒", sk.cd), S.col.cyan)
    end
end

local function CompendiumStatusSpear()
    UI.Text(130, 196, 14, "状态与机制", S.col.gold)
    local statuses = {
        { "枪势", "打满一套三段普攻获得 1 层，最多 3 层；持有枪势时普攻范围 +1 格并施加失衡。" },
        { "失衡", "最多 2 层、持续 3 秒；敌人移速 -12%，与挫裂 / 猎痕组成物理连携。" },
        { "挫裂", "每层使目标受到的物理伤害 +12%，最多 5 层，持续 4 秒、每秒掉 1 层。" },
        { "猎痕", "每层使目标受到的普攻伤害 +14%，最多 5 层；只加成普攻。" },
        { "震荡", "挫裂 + 猎痕触发，扩散挫裂到周围敌人；消耗枪势的技能命中带挫裂目标可直接触发。" },
        { "粉碎 / 追猎", "失衡 + 挫裂 / 失衡 + 猎痕触发，分别造成爆发伤害与攻速移速增益，由专属强化解锁。" },
        { "三段枪式", "5 秒内强化接下来 3 次普攻：1A +40% 攻击、2A 吸血 25%、3A 强制击飞；每次命中全技能 -1 秒。" },
        { "铁枪固守", "架枪 2.5 秒弹开子弹并减伤，收尾震地造成范围伤害并施加挫裂。" },
    }
    local y = 224
    for _, st in ipairs(statuses) do
        UI.Text(130, y, 15, st[1], S.col.orange)
        UI.TextBox(130, y + 19, 480, 11, st[2], S.col.dim)
        y = y + 50
    end

    UI.Text(680, 196, 14, "道具", S.col.gold)
    local items = {
        { "小型生命药剂", "恢复 33% 生命，战斗中使用。" },
        { "大型生命药剂", "恢复 66% 生命，战斗中使用。" },
        { "护盾发生器", "获得护盾上限 50% 的护盾，可暂时超过上限（最多 150%）。" },
        { "狂暴药剂", "10 秒内攻速 +30%、移速 +20%。" },
    }
    local iy = 226
    for _, it in ipairs(items) do
        UI.Text(680, iy, 15, it[1], S.col.green)
        UI.TextBox(680, iy + 20, 440, 12, it[2], S.col.dim)
        iy = iy + 48
    end

    UI.Text(680, 430, 14, "专属强化", S.col.gold)
    UI.TextBox(680, 454, 440, 12,
        "枪客专属强化只会出现在枪客的奖励、商店与事件里，同名限一次；彩色品质只存在于专属池。完整清单见「枪客专属」页。",
        S.col.dim)
end

local function CompendiumStatusRanger()
    UI.Text(130, 196, 14, "状态与机制", S.col.gold)
    local statuses = {
        { "猎痕", "普攻命中施加，每层使目标受到的普攻伤害 +14%，最多 5 层、持续 4 秒。" },
        { "狩猎冲动", "疾退腾挪获得 1 层（最多 3 层），每层攻速 +8%；5 秒不刷新会清空。" },
        { "追猎", "失衡 + 猎痕触发，短时间提升自身攻速与移速，并返还部分技能冷却。" },
        { "精准速射", "5 秒内普攻命中叠层，每层攻速 +6%（最多 5 层）。" },
        { "猎影诱捕", "长按拖放夹子，敌人踩中被束缚 1.2 秒、减速 40%、叠 1 层猎痕，触发后下一次普攻必定暴击。" },
        { "掠袭换位", "瞬移到带猎痕的敌人身后，下一次普攻伤害 +25% 并额外叠 2 层猎痕。" },
    }
    local y = 224
    for _, st in ipairs(statuses) do
        UI.Text(130, y, 15, st[1], S.col.green)
        UI.TextBox(130, y + 19, 480, 11, st[2], S.col.dim)
        y = y + 50
    end
    UI.Text(680, 196, 14, "道具", S.col.gold)
    local items = {
        { "小型生命药剂", "恢复 33% 生命。" },
        { "大型生命药剂", "恢复 66% 生命。" },
        { "护盾发生器", "获得护盾上限 50% 的护盾，可暂时超过上限。" },
        { "狂暴药剂", "10 秒内攻速 +30%、移速 +20%。" },
    }
    local iy = 226
    for _, it in ipairs(items) do
        UI.Text(680, iy, 15, it[1], S.col.green)
        UI.TextBox(680, iy + 20, 440, 12, it[2], S.col.dim)
        iy = iy + 48
    end
    UI.Text(680, 430, 14, "专属强化", S.col.gold)
    UI.TextBox(680, 454, 440, 12,
        "游侠专属强化只会出现在游侠的奖励、商店与事件里，同名限一次；完整清单见「游侠专属」页。",
        S.col.dim)
end

local function CompendiumStatusMage()
    UI.Text(130, 196, 14, "元素与机制", S.col.gold)
    local statuses = {
        { "元素亲和", "按出战技能配比：3 火=火系伤害 +25%；3 冰=控制 +50%；3 电=冷却 -20%；火冰电各 1=全元素 +10%。" },
        { "燃烧", "火系技能施加，持续掉血；被冰系命中触发蒸发。" },
        { "冰冻", "冰系技能施加，目标几乎无法移动；被火系命中触发融化。" },
        { "融化", "火系命中冰冻目标：额外 1.2 倍攻击伤害，并转为燃烧。" },
        { "蒸发", "冰系命中燃烧目标：冰冻 3 秒并把燃烧扩散到周围。" },
        { "过载", "电系命中燃烧/冰冻目标：每个状态额外 +30% 伤害。" },
    }
    local y = 224
    for _, st in ipairs(statuses) do
        UI.Text(130, y, 15, st[1], S.col.purple)
        UI.TextBox(130, y + 19, 480, 11, st[2], S.col.dim)
        y = y + 50
    end
    UI.Text(680, 196, 14, "道具", S.col.gold)
    local items = {
        { "小型生命药剂", "恢复 33% 生命。" },
        { "大型生命药剂", "恢复 66% 生命。" },
        { "护盾发生器", "获得护盾上限 50% 的护盾，可暂时超过上限。" },
        { "狂暴药剂", "10 秒内攻速 +30%、移速 +20%。" },
    }
    local iy = 226
    for _, it in ipairs(items) do
        UI.Text(680, iy, 15, it[1], S.col.green)
        UI.TextBox(680, iy + 20, 440, 12, it[2], S.col.dim)
        iy = iy + 48
    end
    UI.Text(680, 430, 14, "专属强化", S.col.gold)
    UI.TextBox(680, 454, 440, 12,
        "法师专属强化只会出现在法师的奖励、商店与事件里，同名限一次；完整清单见「法师专属」页。",
        S.col.dim)
end

local function CompendiumStatus()
    if Config.PlayerClass == "spearman" then
        return CompendiumStatusSpear()
    elseif Config.PlayerClass == "ranger" then
        return CompendiumStatusRanger()
    elseif Config.PlayerClass == "mage" then
        return CompendiumStatusMage()
    end
    UI.Text(130, 196, 14, "状态与机制", S.col.gold)
    local statuses = {
        { "剑意", "普攻命中叠 1 层，默认上限 5 层；每层普攻伤害 +6%；满层触发剑气爆发并清空。" },
        { "挫裂", "每层使目标受到的物理伤害 +12%，最多 5 层，持续 4 秒、每秒掉 1 层；剑意 ≥3 层时普攻叠加。" },
        { "失衡", "仅由专属强化产出的物理负面，与挫裂同时存在时触发粉碎连携。" },
        { "猎痕", "仅由专属强化产出的物理负面，与挫裂同时存在时触发震荡连携。" },
        { "物理连携", "粉碎：额外爆发伤害；震荡：对周围敌人溅射；追猎：返还技能冷却。专属强化可解锁。" },
        { "剑气爆发", "剑意满层触发，对周围造成 1.5 倍攻击伤害，并施加 1 层挫裂。" },
        { "无敌", "闪影突进 0.22 秒、瞬影连斩约 0.45 秒，期间免疫全部伤害。" },
        { "格挡", "卸势格挡 1 秒内完全免伤，可连挡多次；格挡成功反击剑气、获得剑意并返还 0.8 秒冷却。" },
        { "护盾", "每房开局满盾；战斗中脱战 5 秒后每秒回复 10% 护盾上限。" },
    }
    local y = 224
    for _, st in ipairs(statuses) do
        UI.Text(130, y, 15, st[1], S.col.cyan)
        UI.TextBox(130, y + 19, 480, 11, st[2], S.col.dim)
        y = y + 50
    end

    UI.Text(680, 196, 14, "道具", S.col.gold)
    local items = {
        { "小型生命药剂", "恢复 33% 生命，战斗中使用。" },
        { "大型生命药剂", "恢复 66% 生命，战斗中使用。" },
        { "护盾发生器", "获得护盾上限 50% 的护盾，可暂时超过上限（最多 150%）。" },
        { "狂暴药剂", "10 秒内攻速 +30%、移速 +20%。" },
    }
    local iy = 226
    for _, it in ipairs(items) do
        UI.Text(680, iy, 15, it[1], S.col.green)
        UI.TextBox(680, iy + 20, 440, 12, it[2], S.col.dim)
        iy = iy + 48
    end

    UI.Text(680, 430, 14, "专属强化", S.col.gold)
    UI.TextBox(680, 454, 440, 12,
        Config.Class().name .. "专属强化只会出现在" .. Config.Class().name ..
        "的奖励、商店与事件里，同名限一次；彩色品质只存在于专属池。完整清单见「" ..
        Config.Class().name .. "专属」页。",
        S.col.dim)
end

local function CompendiumClassBuffs()
    local order = { "white", "blue", "purple", "gold", "color" }
    ---@type table[]
    local list = {}
    local classGroup = Config.ClassBuffs[Config.PlayerClass] or {}
    for _, rarity in ipairs(order) do
        for _, b in ipairs(classGroup[rarity] or {}) do
            list[#list + 1] = { base = b, rarity = rarity }
        end
    end

    local perPage = 15
    local pages = math.max(1, math.ceil(#list / perPage))
    if S.codexPage > pages then S.codexPage = pages end
    if S.codexPage < 1 then S.codexPage = 1 end
    local page = S.codexPage

    local className = Config.Class().name
    UI.Text(130, 196, 12,
        string.format("%s专属强化（共 %d 条）：只会出现在%s的奖励 / 商店 / 事件中，同名只能拿一次。每页 15 条。",
            className, #list, className),
        S.col.dim)

    UI.Button("codex_prev", 760, 76, 44, 40, "<", function()
        S.codexPage = math.max(1, S.codexPage - 1)
    end, { fontSize = 18 })
    UI.Text(848, 96, 16, string.format("%d / %d", page, pages), S.col.text,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    UI.Button("codex_next", 892, 76, 44, 40, ">", function()
        S.codexPage = math.min(pages, S.codexPage + 1)
    end, { fontSize = 18 })

    local start = (page - 1) * perPage + 1
    for i = start, math.min(#list, start + perPage - 1) do
        local entry = list[i]
        local idx = i - start
        local col = idx % 3
        local row = math.floor(idx / 3)
        local x = 130 + col * 335
        local y = 214 + row * 92
        local w, h = 325, 84
        local rc = Config.Rarity[entry.rarity]
        UI.Panel(x, y, w, h, 10, { 38, 34, 50, 255 }, rc.color, 2)
        UI.Text(x + 14, y + 8, 16, entry.base.name, rc.color)
        UI.Text(x + w - 14, y + 10, 11, rc.name, S.col.dim,
            NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
        UI.TextBox(x + 14, y + 32, w - 28, 10.5, entry.base.desc, S.col.dim)
        local need = Config.ClassBuffNeedText(entry.base)
        if need then
            UI.Text(x + 14, y + h - 17, 10, "需要携带：" .. need, S.col.orange)
        end
    end
end

function Menu.DrawCompendium()
    nvgBeginPath(S.ctx)
    nvgRect(S.ctx, 0, 0, Config.DESIGN_W, Config.DESIGN_H)
    nvgFillColor(S.ctx, nvgRGBA(0, 0, 0, 200))
    nvgFill(S.ctx)

    UI.Panel(90, 48, 1100, 624, 18, { 28, 24, 38, 252 }, S.col.line, 1)
    UI.Text(130, 68, 30, "生命行者 · 图鉴", S.col.gold)
    UI.Text(130, 108, 14, "怪物 / 强化 / " .. Config.Class().name .. "专属 / 技能 / 状态与道具", S.col.dim)

    UI.Button("codex_close", 1010, 76, 150, 40, "关闭", function()
        S.compendium = false
    end, { fontSize = 16 })

    local tabs = { "怪物", "通用强化", Config.Class().name .. "专属", "技能", "状态 / 道具" }
    for i, label in ipairs(tabs) do
        local active = S.compendiumTab == i
        UI.Button("codex_tab_" .. i, 130 + (i - 1) * 148, 140, 136, 40, label, function()
            S.compendiumTab = i
            S.codexPage = 1
        end, {
            fontSize = 15,
            fill = active and { 48, 70, 92, 255 } or { 36, 32, 48, 255 },
            stroke = active and S.col.cyan or S.col.line,
        })
    end

    if S.compendiumTab == 1 then
        CompendiumMonsters()
    elseif S.compendiumTab == 2 then
        CompendiumBuffs()
    elseif S.compendiumTab == 3 then
        CompendiumClassBuffs()
    elseif S.compendiumTab == 4 then
        CompendiumSkills()
    else
        CompendiumStatus()
    end
end

-- ---------------------------------------------------------------- 测试模式
local TEST_GENERAL = {
    { "w_atk", "攻击 +15%" },
    { "w_as", "攻速 +12%" },
    { "b_crit", "暴击 +10%" },
    { "b_cdr", "冷却 -12%" },
    { "p_ls", "吸血 +18%" },
    { "w_sh", "护盾 +15%" },
}

local TEST_MONSTERS = {
    { "germ", "病菌" },
    { "spore", "孢子" },
    { "worm", "沙蠕" },
    { "mycel", "菌丝怪" },
    { "plague", "疫魔" },
    { "abscess", "脓肿" },
    { "golem", "石魔" },
    { "colossus", "巨像" },
}

local function TestToggle(id, x, y, w, h, label, active, fn, fontSize)
    UI.Button(id, x, y, w, h, label, fn, {
        fontSize = fontSize or 14,
        fill = active and { 48, 82, 70, 255 } or { 38, 34, 50, 255 },
        stroke = active and S.col.green or S.col.line,
    })
end

local function StartTestRun()
    local data = S.data
    local savedLevel = Save.ClassLevel(data)
    local loadout = Save.Loadout(data)
    local savedLoadout = { loadout[1], loadout[2], loadout[3] }
    Save.SetClassLevel(data, math.max(10, savedLevel))

    local skills = {}
    for _, sk in ipairs(Config.Skills) do
        if S.testSkills[sk.id] then skills[#skills + 1] = sk.id end
    end
    if #skills > 0 then
        for i = 1, 3 do loadout[i] = skills[i] or 0 end
    end

    Run.Start(math.max(1, math.min(20, S.testLevel or 1)), true)
    Save.SetClassLevel(data, savedLevel)
    for i = 1, 3 do loadout[i] = savedLoadout[i] end

    local p = S.run.player
    for id in pairs(S.testBuffs) do
        local b = Config.ClassBuffByID(id)
        local rarity = Config.ClassBuffRarity(id)
        if b and rarity then
            Run.GrantBuff(p, {
                id = b.id, name = b.name, desc = b.desc,
                mod = b.mod or {}, flag = b.flag or {},
                rarity = rarity, classBuff = true,
                price = Config.Rarity[rarity].price, color = Config.Rarity[rarity].color,
            })
        end
    end
    for id in pairs(S.testGeneral) do
        local b, rarity = Config.GeneralBuffByID(id)
        if b and rarity then
            Run.GrantBuff(p, {
                id = b.id, name = b.name, desc = b.desc, mod = b.mod,
                rarity = rarity, price = Config.Rarity[rarity].price,
                color = Config.Rarity[rarity].color,
            })
        end
    end

    local cs = Combat.Start(S.run, "standard", 1)
    cs.testMode = true
    cs.waves = {}
    cs.waveIndex = 0
    cs.enemies = {}

    local spawned = 0
    for id, n in pairs(S.testMonsterCount) do
        if n and n > 0 then
            local kind = "minion"
            if id == "mycel" or id == "golem" then kind = "elite"
            elseif id == "plague" or id == "colossus" then kind = "boss" end
            for _ = 1, n do
                Combat.SpawnTestEnemy(cs, kind, id)
                spawned = spawned + 1
            end
        end
    end
    if spawned == 0 then
        for _ = 1, 3 do Combat.SpawnTestEnemy(cs, "minion", "germ") end
        spawned = 3
    end

    S.screen = "combat"
    S.test = false
    UI.SetToast(string.format("测试战斗：%d 条专属 / %d 条通用 / %d 只怪",
        (function() local n = 0 for _ in pairs(S.testBuffs) do n = n + 1 end return n end)(),
        (function() local n = 0 for _ in pairs(S.testGeneral) do n = n + 1 end return n end)(),
        spawned), 2.4)
end
Menu.StartTestRun = StartTestRun

function Menu.DrawTestLab()
    local group = Config.ClassBuffs[Config.PlayerClass] or {}
    local rarities = { "white", "blue", "purple", "gold", "color" }
    ---@type table[]
    local list = {}
    for _, r in ipairs(rarities) do
        for _, b in ipairs(group[r] or {}) do
            list[#list + 1] = { b = b, rarity = r }
        end
    end
    local perPage = 28
    local pages = math.max(1, math.ceil(#list / perPage))
    S.testPage = math.min(pages, math.max(1, S.testPage))

    nvgBeginPath(S.ctx)
    nvgRect(S.ctx, 0, 0, Config.DESIGN_W, Config.DESIGN_H)
    nvgFillColor(S.ctx, nvgRGBA(0, 0, 0, 200))
    nvgFill(S.ctx)

    UI.Panel(90, 48, 1100, 624, 18, { 28, 24, 38, 252 }, S.col.line, 1)
    UI.Text(120, 66, 28, "测试模式", S.col.gold)
    UI.Text(120, 104, 13, "仅本地开发用：自选专属 / 通用强化、携带技能和怪物，直接进战斗。选择不会被存档记录。", S.col.dim)
    UI.Button("test_close", 1040, 74, 120, 40, "关闭", function()
        S.test = false
    end, { fontSize = 16 })

    -- 分页
    local page = S.testPage
    UI.Button("test_prev", 830, 70, 40, 32, "<", function()
        S.testPage = math.max(1, S.testPage - 1)
    end, { fontSize = 16 })
    UI.Text(880, 86, 14, page .. " / " .. pages, S.col.text,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    UI.Button("test_next", 930, 70, 40, 32, ">", function()
        S.testPage = math.min(pages, S.testPage + 1)
    end, { fontSize = 16 })

    -- 专属强化 4 列 x 7 行（右侧留出详情面板）
    local start = (page - 1) * perPage + 1
    for i = start, math.min(#list, start + perPage - 1) do
        local entry = list[i]
        local idx = i - start
        local col = idx % 4
        local row = math.floor(idx / 4)
        local x = 120 + col * 162
        local y = 140 + row * 30
        local active = S.testBuffs[entry.b.id] == true
        TestToggle("tb_" .. entry.b.id, x, y, 152, 26,
            (active and "[x] " or "") .. entry.b.name, active, function()
                S.testBuffs[entry.b.id] = (not active) or nil
                S.testDetail = { kind = "class", id = entry.b.id }
            end, 13)
    end

    -- 右侧：效果详情
    UI.Panel(800, 140, 360, 400, 14, { 26, 22, 34, 255 }, S.col.line, 1)
    UI.Text(820, 156, 17, "效果详情", S.col.gold)
    local det = S.testDetail
    local detailShown = false
    if det and det.kind == "class" then
        local b = Config.ClassBuffByID(det.id)
        local rarityKey = Config.ClassBuffRarity(det.id)
        if b and rarityKey then
            local rc = Config.Rarity[rarityKey]
            UI.Text(820, 192, 20, b.name, rc.color)
            UI.Text(820, 222, 12, rc.name .. " · " .. Config.Class().name .. "专属", S.col.dim)
            local need = Config.ClassBuffNeedText(b)
            UI.TextBox(820, 246, 320, 11,
                need and ("需要携带：" .. need) or "通用效果，不受携带技能限制",
                need and S.col.orange or S.col.dim)
            UI.TextBox(820, 276, 320, 12.5, b.desc or "", S.col.text)
            UI.Text(820, 366, 12,
                S.testBuffs[b.id] and "已勾选（再点一次取消）" or "未勾选",
                S.testBuffs[b.id] and S.col.green or S.col.dim)
            detailShown = true
        end
    elseif det and det.kind == "general" then
        local b, rarityKey = Config.GeneralBuffByID(det.id)
        if b and rarityKey then
            local rc = Config.Rarity[rarityKey]
            UI.Text(820, 192, 20, b.name, rc.color)
            UI.Text(820, 222, 12, rc.name .. " · 通用强化", S.col.dim)
            UI.TextBox(820, 252, 320, 12.5, b.desc or "", S.col.text)
            UI.Text(820, 366, 12,
                S.testGeneral[b.id] and "已勾选（再点一次取消）" or "未勾选",
                S.testGeneral[b.id] and S.col.green or S.col.dim)
            detailShown = true
        end
    end
    if not detailShown then
        UI.Text(820, 192, 13, "点击任意强化查看完整效果。", S.col.dim)
        UI.TextBox(820, 218, 320, 12,
            "状态：强化会立即写进角色属性；专属强化里的技能类条目需要携带对应技能才会生效。",
            S.col.dim)
    end
    local classN, generalN, monsterN = 0, 0, 0
    for _ in pairs(S.testBuffs) do classN = classN + 1 end
    for _ in pairs(S.testGeneral) do generalN = generalN + 1 end
    for _, n in pairs(S.testMonsterCount) do
        if n and n > 0 then monsterN = monsterN + n end
    end
    UI.Text(820, 478, 12, string.format("已选：专属 %d · 通用 %d · 怪物 %d", classN, generalN, monsterN),
        S.col.cyan)

    -- 通用强化
    UI.Text(120, 372, 15, "通用强化", S.col.cyan)
    for i, g in ipairs(TEST_GENERAL) do
        local x = 120 + (i - 1) * 112
        local active = S.testGeneral[g[1]] == true
        TestToggle("tg_" .. g[1], x, 366, 106, 30,
            (active and "[x] " or "") .. g[2]:gsub(" ", ""), active, function()
                S.testGeneral[g[1]] = (not active) or nil
                S.testDetail = { kind = "general", id = g[1] }
            end, 12)
    end

    -- 怪物：名称开关 + 数量步进
    UI.Text(120, 396, 15, "怪物（点名称开关，- / + 调数量）", S.col.cyan)
    for i, m in ipairs(TEST_MONSTERS) do
        local col = (i - 1) % 4
        local row = math.floor((i - 1) / 4)
        local x = 120 + col * 165
        local y = 416 + row * 66
        local count = S.testMonsterCount[m[1]] or 0
        local active = count > 0
        TestToggle("tm_" .. m[1], x, y, 150, 28,
            (active and "[x] " or "") .. m[2], active, function()
                if active then
                    S.testMonsterCount[m[1]] = 0
                else
                    S.testMonsterCount[m[1]] =
                        (m[1] == "mycel" or m[1] == "plague" or m[1] == "golem" or m[1] == "colossus") and 1 or 3
                end
            end, 13)
        UI.Button("tmm_" .. m[1], x, y + 32, 34, 26, "-", function()
            local v = S.testMonsterCount[m[1]] or 0
            S.testMonsterCount[m[1]] = math.max(0, v - 1)
        end, { fontSize = 16 })
        UI.Text(x + 75, y + 45, 15, tostring(count), active and S.col.text or S.col.dim,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        UI.Button("tmp_" .. m[1], x + 116, y + 32, 34, 26, "+", function()
            local v = S.testMonsterCount[m[1]] or 0
            S.testMonsterCount[m[1]] = math.min(10, v + 1)
        end, { fontSize = 16 })
    end

    -- 携带技能（最多 3 个）
    UI.Text(120, 548, 15, "携带技能（最多 3 个，不选则用当前配置）", S.col.cyan)
    local selectedSkills = 0
    for _ in pairs(S.testSkills) do selectedSkills = selectedSkills + 1 end
    for i, sk in ipairs(Config.Skills) do
        local col = (i - 1) % 5
        local row = math.floor((i - 1) / 5)
        local x = 120 + col * 132
        local y = 570 + row * 34
        local active = S.testSkills[sk.id] == true
        TestToggle("ts_" .. sk.id, x, y, 124, 30,
            (active and "[x] " or "") .. sk.short, active, function()
                if active then
                    S.testSkills[sk.id] = nil
                elseif selectedSkills < 3 then
                    S.testSkills[sk.id] = true
                else
                    UI.SetToast("最多携带 3 个技能", 1.6)
                end
            end, 13)
    end

    -- 右下：批量操作 / 关卡等级 / 进入
    UI.Button("test_allpage", 800, 552, 170, 34, "全选本页", function()
        local last = math.min(#list, start + perPage - 1)
        for i = start, last do S.testBuffs[list[i].b.id] = true end
    end, { fontSize = 13 })
    UI.Button("test_clear", 980, 552, 170, 34, "清空选择", function()
        S.testBuffs = {}
        S.testGeneral = {}
        S.testSkills = {}
        S.testMonsterCount = {
            germ = 0, spore = 0, worm = 0, mycel = 0, plague = 0,
            abscess = 0, golem = 0, colossus = 0,
        }
        S.testDetail = nil
    end, { fontSize = 13 })
    UI.Text(800, 604, 13, "怪物等级", S.col.dim)
    UI.Button("test_lv_minus", 880, 594, 36, 34, "-", function()
        S.testLevel = math.max(1, (S.testLevel or 1) - 1)
    end, { fontSize = 16 })
    UI.Panel(922, 594, 64, 34, 8, S.col.panel2, S.col.line, 1)
    UI.Text(954, 611, 15, "Lv." .. (S.testLevel or 1), S.col.text,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    UI.Button("test_lv_plus", 990, 594, 36, 34, "+", function()
        S.testLevel = math.min(20, (S.testLevel or 1) + 1)
    end, { fontSize = 16 })
    local tl = math.max(1, math.min(20, S.testLevel or 1))
    local mhp, matk = Config.MonsterStats(tl, 1, "minion")
    UI.Text(1036, 594, 11, string.format("第 %d 关数值", tl), S.col.dim)
    UI.Text(1036, 610, 11, string.format("小兵 %d血/%d攻", mhp, matk), S.col.cyan)
    UI.Button("test_start", 800, 632, 350, 34, "进入测试战斗", StartTestRun, {
        fontSize = 16, accent = S.col.green,
        fill = { 40, 74, 52, 255 }, stroke = { 90, 150, 105, 255 },
    })
end

function Menu.DrawResetConfirm()
    nvgBeginPath(S.ctx)
    nvgRect(S.ctx, 0, 0, Config.DESIGN_W, Config.DESIGN_H)
    nvgFillColor(S.ctx, nvgRGBA(0, 0, 0, 205))
    nvgFill(S.ctx)
    UI.Panel(420, 250, 440, 210, 16, { 32, 26, 36, 255 }, S.col.red, 2)
    UI.Text(640, 274, 24, "重置存档？", S.col.red, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    UI.Text(640, 314, 13, "职业等级、经验、金币、解锁关卡、", S.col.dim,
        NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    UI.Text(640, 334, 13, "连续健康天数和技能配置都会恢复到初始状态。", S.col.dim,
        NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    UI.Text(640, 372, 13, "此操作不可撤销。", S.col.dim, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    UI.Button("reset_yes", 460, 394, 170, 44, "确认重置", function()
        Save.Reset(S.data)
        S.selectedLevel = 1
        S.confirmReset = false
        UI.SetToast("存档已重置：等级 1 / 金币 0 / 关卡 1", 2.6)
    end, { fontSize = 16, fill = { 76, 38, 42, 255 }, stroke = { 150, 80, 86, 255 } })
    UI.Button("reset_no", 650, 394, 170, 44, "取消", function()
        S.confirmReset = false
    end, { fontSize = 16 })
end

-- ---------------------------------------------------------------- 设置（左侧分类 + 右侧列表）
local SETTINGS_TABS = {
    { id = "visual",  label = "画面与性能" },
    { id = "control", label = "操作手感" },
    { id = "combat",  label = "战斗显示" },
    { id = "data",    label = "数据与帮助" },
}

local function ApplyFps(data)
    data.fpsCap = data.fpsCap or 60
    if engine then engine.maxFps = data.fpsCap end
end
Menu.ApplyFps = ApplyFps

-- 单行：左标题（可带说明），右侧控件区从 x=790 开始
local function SetRow(y, title, hint)
    UI.Text(404, y + 6, 16, title, S.col.text)
    if hint then UI.Text(404, y + 28, 11, hint, S.col.dim) end
end

local function SetToggle(y, id, on, cb, onText, offText)
    UI.Button(id, 790, y, 120, 36, on and (onText or "开启") or (offText or "关闭"), function()
        cb(not on)
        Save.Write(S.data)
    end, {
        fontSize = 14,
        fill = on and { 40, 70, 52, 255 } or { 52, 34, 38, 255 },
        stroke = on and S.col.green or S.col.red,
    })
end

local function SetSeg(y, id, options, cur, cb)
    local x = 790
    for _, o in ipairs(options) do
        local active = (o[1] == cur)
        local val = o[1]
        UI.Button(id .. "_" .. tostring(val), x, y, 92, 36, o[2], function()
            cb(val)
            Save.Write(S.data)
        end, {
            fontSize = 14,
            fill = active and { 40, 70, 52, 255 } or { 36, 32, 48, 255 },
            stroke = active and S.col.green or S.col.line,
        })
        x = x + 98
    end
end

function Menu.DrawSettings()
    local data = S.data
    local tab = S.settingsTab or "control"

    nvgBeginPath(S.ctx)
    nvgRect(S.ctx, 0, 0, Config.DESIGN_W, Config.DESIGN_H)
    nvgFillColor(S.ctx, nvgRGBA(0, 0, 0, 210))
    nvgFill(S.ctx)

    UI.Panel(200, 76, 880, 568, 18, { 28, 24, 38, 252 }, S.col.line, 1)
    UI.Text(232, 96, 26, "设置", S.col.gold)
    UI.Text(232, 128, 12, "本地保存，改动立即生效", S.col.dim)

    -- 左侧分类
    for i, t in ipairs(SETTINGS_TABS) do
        local y = 168 + (i - 1) * 58
        local active = (tab == t.id)
        UI.Button("set_tab_" .. t.id, 224, y, 160, 46, t.label, function()
            S.settingsTab = t.id
        end, {
            fontSize = 15,
            fill = active and { 42, 62, 84, 255 } or { 34, 30, 44, 255 },
            stroke = active and S.col.cyan or S.col.line,
            accent = active and S.col.cyan or nil,
        })
    end

    -- 分隔线
    UI.Panel(400, 150, 2, 462, 1, { 60, 56, 78, 255 })

    local y0 = 158
    local rowH = 62

    if tab == "visual" then
        local r = 1
        SetRow(y0 + (r - 1) * rowH, "帧率上限", "省电就选 30，流畅选 60/120")
        SetSeg(y0 + (r - 1) * rowH, "set_fps", { { 30, "30" }, { 60, "60" }, { 120, "120" } },
            data.fpsCap or 60, function(v)
                data.fpsCap = v
                ApplyFps(data)
            end)
        r = r + 1
        SetRow(y0 + (r - 1) * rowH, "低画质模式", "粒子、拖尾、残影减量，弱机更稳")
        SetToggle(y0 + (r - 1) * rowH, "set_lowq", data.lowQuality == true, function(v)
            data.lowQuality = v
        end)
        r = r + 1
        SetRow(y0 + (r - 1) * rowH, "屏幕震动", "受击/爆发时的镜头抖动")
        SetToggle(y0 + (r - 1) * rowH, "set_shake", data.screenShake ~= false, function(v)
            data.screenShake = v
        end)
        r = r + 1
        SetRow(y0 + (r - 1) * rowH, "伤害数字", "简化 = 更小更淡，减少画面干扰")
        SetSeg(y0 + (r - 1) * rowH, "set_dmg",
            { { "full", "完整" }, { "simple", "简化" }, { "off", "关闭" } },
            data.damageText or "full", function(v)
                data.damageText = v
            end)
        r = r + 1
        SetRow(y0 + (r - 1) * rowH, "背景音乐", "当前版本音频未启用，开关先保留")
        SetToggle(y0 + (r - 1) * rowH, "set_music", data.musicOn ~= false, function(v)
            Audio.SetEnabled(data, v)
        end, "开启", "关闭")
        r = r + 1
        local volume = data.musicVolume or 0.32
        SetRow(y0 + (r - 1) * rowH, "音量", string.format("当前 %d%%（0%% 等同静音）",
            math.floor(volume * 100 + 0.5)))
        UI.Button("vol_minus", 790, y0 + (r - 1) * rowH, 44, 36, "-", function()
            Audio.SetVolume(data, (data.musicVolume or 0.32) - 0.1)
            Save.Write(data)
        end, { fontSize = 20 })
        UI.Button("vol_plus", 842, y0 + (r - 1) * rowH, 44, 36, "+", function()
            Audio.SetVolume(data, (data.musicVolume or 0.32) + 0.1)
            Save.Write(data)
        end, { fontSize = 20 })
        for i = 1, 6 do
            local x = 896 + (i - 1) * 24
            local on = i <= math.floor(volume * 6 + 0.5)
            UI.Panel(x, y0 + (r - 1) * rowH, 20, 36, 5,
                on and { 48, 96, 110, 255 } or { 36, 32, 48, 255 },
                on and S.col.cyan or S.col.line, 1)
            local lv = i
            UI.Region("vol_seg_" .. i, x, y0 + (r - 1) * rowH, 20, 36, function()
                Audio.SetVolume(data, lv / 6)
                Save.Write(data)
            end, true)
        end
    elseif tab == "control" then
        local r = 1
        SetRow(y0 + (r - 1) * rowH, "摇杆模式", "浮动 = 按在哪里就在哪里出现")
        SetSeg(y0 + (r - 1) * rowH, "set_joymode",
            { { "float", "浮动" }, { "fixed", "固定" } },
            data.joyMode == "fixed" and "fixed" or "float", function(v)
                data.joyMode = v
            end)
        r = r + 1
        SetRow(y0 + (r - 1) * rowH, "摇杆灵敏度", "高 = 轻推就走，低 = 更稳不容易飘")
        SetSeg(y0 + (r - 1) * rowH, "set_joysens",
            { { "low", "低" }, { "mid", "中" }, { "high", "高" } },
            data.joySensitivity or "mid", function(v)
                data.joySensitivity = v
            end)
        r = r + 1
        SetRow(y0 + (r - 1) * rowH, "拖尾跟随", "手指拖出圈子时摇杆基座跟着走")
        SetToggle(y0 + (r - 1) * rowH, "set_follow", data.joyFollow ~= false, function(v)
            data.joyFollow = v
        end)
        r = r + 1
        SetRow(y0 + (r - 1) * rowH, "长按施法阈值", "按住多久进入瞄准；越短越容易触发")
        SetSeg(y0 + (r - 1) * rowH, "set_aimhold",
            { { 0.15, "0.15s" }, { 0.22, "0.22s" }, { 0.30, "0.30s" } },
            data.aimHold or 0.22, function(v)
                data.aimHold = v
            end)
        r = r + 1
        SetRow(y0 + (r - 1) * rowH, "选位施法", "夹子/流星这类技能怎么定落点")
        SetSeg(y0 + (r - 1) * rowH, "set_aimmode",
            { { "button", "按键摇杆" }, { "screen", "屏幕位置" } },
            data.aimMode == "screen" and "screen" or "button", function(v)
                data.aimMode = v
            end)
        r = r + 1
        SetRow(y0 + (r - 1) * rowH, "瞄准指示", "长按技能时显示按键到手指的指示线")
        SetToggle(y0 + (r - 1) * rowH, "set_aimind", data.aimIndicator ~= false, function(v)
            data.aimIndicator = v
        end)
        r = r + 1
        SetRow(y0 + (r - 1) * rowH, "自动攻击", "进入普攻范围后自动出刀；关掉只能手动点普攻")
        SetToggle(y0 + (r - 1) * rowH, "set_auto", data.autoAttack ~= false, function(v)
            data.autoAttack = v
        end)
        r = r + 1
        SetRow(y0 + (r - 1) * rowH, "按键布局", "摇杆/技能键/取消施法框的位置和大小")
        UI.Button("set_layout", 790, y0 + (r - 1) * rowH, 190, 36, "打开编辑器", function()
            KbLayout.Open()
        end, { fontSize = 15 })
    elseif tab == "combat" then
        local r = 1
        SetRow(y0 + (r - 1) * rowH, "普攻范围预览", "常驻显示普攻的扇形/射线")
        SetToggle(y0 + (r - 1) * rowH, "set_range", data.showSkillRange ~= false, function(v)
            data.showSkillRange = v
        end)
        r = r + 1
        SetRow(y0 + (r - 1) * rowH, "怪物血条", "关掉可以更看清弹幕")
        SetToggle(y0 + (r - 1) * rowH, "set_hpbar", data.enemyHpBar ~= false, function(v)
            data.enemyHpBar = v
        end)
        r = r + 1
        SetRow(y0 + (r - 1) * rowH, "敌方预警加强", "Boss/精英的红圈更亮更粗")
        SetToggle(y0 + (r - 1) * rowH, "set_warn", data.bossWarn ~= false, function(v)
            data.bossWarn = v
        end)
        r = r + 1
        SetRow(y0 + (r - 1) * rowH, "命中反馈", "攻击命中时的闪白与火花（固定开启）")
        UI.Text(790, y0 + (r - 1) * rowH + 10, 14, "已开启", S.col.dim)
        r = r + 1
        SetRow(y0 + (r - 1) * rowH, "战斗内暂停", "屏幕右上角「暂停」按钮 / Esc")
        UI.Text(790, y0 + (r - 1) * rowH + 10, 14, "始终可用", S.col.dim)
    else
        local r = 1
        SetRow(y0 + (r - 1) * rowH, "按键布局", "调整摇杆、技能键、取消施法框")
        UI.Button("set_layout2", 790, y0 + (r - 1) * rowH, 190, 36, "打开编辑器", function()
            KbLayout.Open()
        end, { fontSize = 15 })
        r = r + 1
        SetRow(y0 + (r - 1) * rowH, "图鉴", "怪物 / 强化 / 技能 / 状态与道具")
        UI.Button("set_codex", 790, y0 + (r - 1) * rowH, 190, 36, "打开图鉴", function()
            S.settings = false
            S.compendium = true
        end, { fontSize = 15 })
        r = r + 1
        SetRow(y0 + (r - 1) * rowH, "恢复默认设置", "只重置画面/操作/战斗开关，不动存档")
        UI.Button("set_defaults", 790, y0 + (r - 1) * rowH, 190, 36, "恢复默认", function()
            local def = Save.Defaults()
            for _, k in ipairs({ "fpsCap", "lowQuality", "screenShake", "damageText",
                "joySensitivity", "aimHold", "autoAttack", "aimIndicator",
                "showSkillRange", "enemyHpBar", "bossWarn", "aimMode", "joyMode", "joyFollow" }) do
                data[k] = def[k]
            end
            ApplyFps(data)
            Save.Write(data)
            UI.SetToast("设置已恢复默认", 1.6)
        end, { fontSize = 15 })
        r = r + 1
        SetRow(y0 + (r - 1) * rowH, "清空存档", "等级、金币、关卡进度全部重置，不可恢复")
        if S.settingsWipeConfirm then
            UI.Button("set_wipe_yes", 790, y0 + (r - 1) * rowH, 92, 36, "确认清空", function()
                S.settingsWipeConfirm = false
                local fresh = Save.Fresh()
                Save.Write(fresh)
                S.data = fresh
                ApplyFps(S.data)
                UI.SetToast("存档已清空", 1.6)
            end, { fontSize = 14, fill = { 96, 34, 40, 255 }, stroke = S.col.red })
            UI.Button("set_wipe_no", 890, y0 + (r - 1) * rowH, 92, 36, "取消", function()
                S.settingsWipeConfirm = false
            end, { fontSize = 14 })
        else
            UI.Button("set_wipe", 790, y0 + (r - 1) * rowH, 190, 36, "清空存档", function()
                S.settingsWipeConfirm = true
            end, { fontSize = 15, fill = { 52, 34, 38, 255 }, stroke = S.col.red })
        end
        r = r + 1
        UI.Text(404, y0 + (r - 1) * rowH + 4, 12,
            string.format("版本 v%s · 职业 %s Lv.%d · 金币 %s · 关卡 1~%d",
                Config.VERSION, Config.Class().name, Save.ClassLevel(data),
                UI.FormatNumber(data.gold), data.unlocked), S.col.dim)
    end

    -- 底部：说明 + 关闭
    UI.Text(224, 600, 12,
        "Esc / 点「关闭」返回；设置改动会立刻写进本地存档", S.col.dim)
    UI.Button("set_close", 920, 588, 140, 38, "关闭 (Esc)", function()
        S.settings = false
        S.settingsWipeConfirm = false
    end, { fontSize = 15, fill = { 44, 92, 62, 255 } })
end

function Menu.Draw()
    local data = S.data
    FixLoadout()
    if S.compendium then
        Menu.DrawCompendium()
        return
    end
    if S.settings then
        Menu.DrawSettings()
        return
    end
    if S.test then
        Menu.DrawTestLab()
        return
    end
    if S.skillPicker then
        Menu.DrawSkillPicker()
        return
    end

    -- 标题
    UI.Text(64, 42, 46, Config.GAME_TITLE, S.col.text)
    UI.Text(66, 100, 18, "把每一步，走成力量。", S.col.dim)
    UI.Text(1216, 46, 14, "v" .. Config.VERSION, S.col.dim, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
    UI.Button("codex", 1030, 34, 130, 40, "图鉴", function()
        S.compendium = true
        S.compendiumTab = 1
        S.codexPage = 1
    end, { fontSize = 16 })
    UI.Button("settings", 890, 34, 120, 40, "设置", function()
        S.settings = true
    end, { fontSize = 16 })

    -- 左：角色
    UI.Panel(64, 138, 560, 402, 16, S.col.panel, S.col.line, 1)
    UI.Text(88, 160, 22, "角色", S.col.gold)
    local classBtnX = 296
    for _, cid in ipairs({ "swordsman", "spearman", "ranger", "mage" }) do
        local c = Config.Classes[cid]
        if c then
            local active = Save.ActiveClass(data) == cid
            UI.Button("class_" .. cid, classBtnX, 154, 76, 34, c.name, function()
                if Save.ActiveClass(data) == cid then return end
                Save.SetClass(data, cid)
                FixLoadout()
                S.testBuffs = {}
                S.testSkills = {}
                S.testDetail = nil
                S.selectedLevel = math.min(data.unlocked, math.max(1, S.selectedLevel))
                UI.SetToast("已切换到 " .. c.name, 2.0)
            end, {
                fontSize = 14,
                fill = active and { 48, 70, 92, 255 } or { 36, 32, 48, 255 },
                stroke = active and S.col.cyan or S.col.line,
            })
            classBtnX = classBtnX + 80
        end
    end
    local classLevel = Save.ClassLevel(data)
    local cost = Save.NextCost(data)
    DrawStat(88, 204, "金币", UI.FormatNumber(data.gold))
    DrawStat(88, 236, "可分配经验", UI.FormatNumber(data.exp))
    DrawStat(88, 268, Config.Class().name .. "等级", "Lv." .. classLevel)
    DrawStat(88, 300, "升级需要", cost and UI.FormatNumber(cost) or "已满级")
    DrawStat(88, 332, "连续健康", data.streak .. " 天")
    DrawStat(88, 364, "技能点", tostring(data.skillPoints))

    local costText
    local canLevel = false
    if cost then
        local needGate, gateName = Config.LevelGate(classLevel + 1)
        if needGate > 0 and data.streak < needGate then
            costText = "需连续 " .. needGate .. " 天（" .. gateName .. "）"
        elseif data.exp < cost then
            costText = string.format("升级到 Lv.%d · 需 %d 经验（还差 %d）",
                classLevel + 1, cost, math.ceil(cost - data.exp))
        else
            costText = string.format("升级到 Lv.%d · 消耗 %d 经验", classLevel + 1, cost)
            canLevel = true
        end
    else
        costText = Config.Class().name .. "已满级"
    end
    UI.Button("levelup", 88, 392, 512, 42, costText, function()
        local ok, msg = Save.LevelUp(S.data)
        UI.SetToast(msg, 2.4)
        if ok then FixLoadout() end
    end, { enabled = canLevel, accent = S.col.green, fontSize = 15 })

    UI.Text(88, 440, 12, "点上面的职业按钮决定给谁升级；升级直接从「可分配经验」里扣掉这一级需要的量", S.col.dim)

    UI.Text(88, 462, 18, "出战技能（点一下切换）", S.col.dim)
    local loadout = Save.Loadout(data)
    for i = 1, 3 do
        local x = 88 + (i - 1) * 168
        local id = loadout[i]
        local sk = Config.SkillByID(id)
        local label
        local enabled = true
        if sk and Save.IsSkillUnlocked(classLevel, id) then
            label = sk.short .. " · " .. sk.name
        else
            label = "空位"
        end
        UI.Button("slot" .. i, x, 492, 152, 44, label, function()
            S.skillPicker = i
        end, { fontSize = 16, enabled = enabled, accent = S.col.cyan })
    end

    -- 右：今日运动
    UI.Panel(656, 138, 560, 402, 16, S.col.panel, S.col.line, 1)
    UI.Text(680, 160, 22, "今日运动", S.col.gold)

    local steps = data.todaySteps
    UI.Text(680, 200, 54, UI.FormatNumber(steps), S.col.text)
    UI.Text(680 + 220, 228, 18, "步", S.col.dim)

    local gain, pct = Config.StepGold(steps)
    UI.Text(680, 272, 19, string.format("超静息消耗 %.1f%%  ·  预计 +%d 金币 / +%d 经验", pct, gain, gain),
        S.col.cyan)

    UI.Button("step_minus", 680, 312, 120, 48, "-1000", function()
        if S.data.claimed then return end
        S.data.todaySteps = math.max(0, S.data.todaySteps - 1000)
        Save.Write(S.data)
    end, { fontSize = 20, enabled = not data.claimed })
    UI.Button("step_plus", 812, 312, 120, 48, "+1000", function()
        if S.data.claimed then return end
        S.data.todaySteps = math.min(50000, S.data.todaySteps + 1000)
        Save.Write(S.data)
    end, { fontSize = 20, enabled = not data.claimed })

    local claimLabel = data.claimed and "今日已领取" or "记录步数并领取"
    UI.Button("claim", 680, 378, 420, 54, claimLabel, function()
        local g, unlocks, streak, rg, rsp = Save.Claim(S.data, S.data.todaySteps)
        S.selectedLevel = S.data.unlocked
        if g > 0 or unlocks > 0 or rg > 0 then
            local msg = string.format("获得 %d 金币，可分配经验 +%d，解锁 %d 关，连续 %d 天",
                g, g, unlocks, streak)
            if rg > 0 then msg = msg .. string.format("；连续奖励 +%d 金币 +%d 技能点", rg, rsp) end
            UI.SetToast(msg, 3.2)
        else
            UI.SetToast("今天已经领取过了", 2.0)
        end
    end, { fontSize = 20, enabled = not data.claimed, accent = S.col.gold })

    local unlockCount = 0
    for _, need in ipairs(Config.StepUnlockThresholds) do
        if steps >= need then unlockCount = unlockCount + 1 end
    end
    UI.Text(680, 448, 17,
        string.format("步数解锁：2000 / 8000 / 12000（今日可解锁 %d 关）", unlockCount), S.col.dim)
    local maxPlayable = Save.MaxPlayable(data)
    local clearedCount = math.min(20, data.stageCleared or 0)
    UI.Text(680, 476, 17,
        string.format("关卡进度：已通关 %d 关 · 可挑战 1 ~ %d", clearedCount, maxPlayable), S.col.dim)
    if maxPlayable < data.unlocked then
        UI.Text(680, 504, 15,
            string.format("通关第 %d 关后才会开放新关卡（步数已够 %d 关）", maxPlayable, data.unlocked), S.col.orange)
    end

    -- 底部：关卡选择 + 开始
    local maxLv = Save.MaxPlayable(data)
    UI.Button("lv_minus", 330, 580, 56, 56, "-", function()
        S.selectedLevel = math.max(1, S.selectedLevel - 1)
    end, { fontSize = 26 })
    UI.Panel(396, 580, 300, 56, 10, S.col.panel2, S.col.line, 1)
    UI.Text(546, 608, 24, "第 " .. S.selectedLevel .. " 关", S.col.text,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    UI.Button("lv_plus", 706, 580, 56, 56, "+", function()
        S.selectedLevel = math.min(maxLv, S.selectedLevel + 1)
    end, { fontSize = 26 })

    UI.Button("start", 790, 574, 300, 68, "开始第 " .. S.selectedLevel .. " 关",
        StartLevel, { fontSize = 24, accent = S.col.green, fill = { 40, 74, 52, 255 } })

    -- 开发模式（正式发布时把 State.lua 里的 S.dev 改成 false 即可整块隐藏）
    if S.dev then
        local dvx, dvy, dvw, dvh = 64, 648, 118, 32
        local function DevX(i) return dvx + (i - 1) * (dvw + 10) end
        UI.Button("devnextday", DevX(1), dvy, dvw, dvh, "下一天", function()
            Save.NextDay(S.data)
            UI.SetToast("已进入下一天，记得重新记录步数并领取", 2.4)
        end, { fontSize = 14, fill = { 40, 58, 48, 255 }, stroke = { 80, 130, 96, 255 } })
        UI.Button("devtest", DevX(2), dvy, dvw, dvh, "测试模式", function()
            S.test = true
            S.testPage = 1
        end, { fontSize = 14, fill = { 40, 52, 74, 255 }, stroke = { 80, 110, 160, 255 } })
        UI.Button("devunlock", DevX(3), dvy, dvw, dvh, "解锁关卡", function()
            Save.DebugUnlockAll(S.data)
            S.selectedLevel = Save.MaxPlayable(S.data)
            UI.SetToast("已解锁到第 20 关", 2.0)
        end, { fontSize = 14, fill = { 44, 56, 44, 255 }, stroke = { 96, 140, 96, 255 } })
        UI.Button("devexp", DevX(4), dvy, dvw, dvh, "经验 +1000", function()
            S.data.exp = (S.data.exp or 0) + 1000
            Save.Write(S.data)
            UI.SetToast("可分配经验 +1000", 1.8)
        end, { fontSize = 14, fill = { 44, 52, 70, 255 }, stroke = { 90, 110, 150, 255 } })
        UI.Button("devgold", DevX(5), dvy, dvw, dvh, "金币 +1000", function()
            S.data.gold = (S.data.gold or 0) + 1000
            Save.Write(S.data)
            UI.SetToast("金币 +1000", 1.8)
        end, { fontSize = 14, fill = { 58, 52, 36, 255 }, stroke = { 140, 120, 70, 255 } })
        UI.Button("devreset", DevX(6), dvy, dvw, dvh, "重置存档", function()
            S.confirmReset = true
        end, { fontSize = 14, fill = { 66, 40, 44, 255 }, stroke = { 130, 76, 82, 255 } })
        UI.Text(64, 686, 12,
            "开发模式：推进日期 / 自选强化与怪物测试 / 解锁关卡 / 加经验金币 / 清空存档（发布前把 State.lua 的 dev 改成 false）",
            S.col.dim)
    end

    UI.Text(64, 703, 12, "手机：左下摇杆 + 右下技能键　桌面：WASD 移动 / J K L 技能 / SPACE 平A / E 道具 / Tab 强化面板　普攻自动锁敌", S.col.dim)

    if S.confirmReset then
        Menu.DrawResetConfirm()
    end
end

return Menu
