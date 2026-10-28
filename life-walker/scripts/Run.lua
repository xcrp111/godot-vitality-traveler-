-- Run.lua — 单关流程：4x4 地图 / 房间 / 银币 / 商店 / 事件

local Config = require "Config"
local Save = require "Save"
local UI = require "UI"
local S = require "State"
local Guild = require "Guild"

-- 释放摇杆输入（原来是 VirtualControls.Clear 负责，现在摇杆是自绘的）
local function ReleaseInput()
    S.input.x = 0
    S.input.y = 0
    local cs = S.combat
    if cs and cs.joystick then
        cs.joystick.active = false
        cs.joystick.kx = cs.joystick.baseX
        cs.joystick.ky = cs.joystick.baseY
    end
end

---@class Mods
---@field hpPct number
---@field shieldPct number
---@field atkPct number
---@field asPct number
---@field msPct number
---@field cdrPct number
---@field crit number
---@field critDmg number
---@field lifesteal number
---@field dodge number
---@field basicPct number
---@field skillPct number
---@field regen number
---@field revive number
---@field rangePct number
---@field hurtHeal number
---@field critHeal number

---@class PlayerState
---@field x number
---@field y number
---@field radius number
---@field classLevel integer
---@field baseHp number
---@field baseShield number
---@field baseAtk number
---@field maxHp number
---@field maxShield number
---@field atk number
---@field hp number
---@field shield number
---@field attackSpeed number
---@field moveSpeed number
---@field crit number
---@field critDmg number
---@field lifesteal number
---@field dodge number
---@field cdr number
---@field basicPct number
---@field skillPct number
---@field regen number
---@field rangePct number
---@field hurtHeal number
---@field critHeal number
---@field revive number
---@field reviveUsed boolean
---@field mods Mods
---@field flags table<string, number>
---@field classBuffs table<string, boolean>
---@field colorPity integer
---@field charges table<number, integer>
---@field buffs table[]
---@field intent integer
---@field intentTimer number
---@field attackTimer number
---@field attackQueued boolean
---@field cooldowns table<number, number>
---@field rageTimer number
---@field parryTimer number
---@field invulnTimer number
---@field noDamageTimer number
---@field hurtHealTimer number
---@field hurtHealAmount number

---@class RunState
---@field level integer
---@field silver integer
---@field step integer
---@field posR integer
---@field posC integer
---@field visited table<string, boolean>
---@field cleared table<string, boolean>
---@field player PlayerState
---@field loadout integer[]
---@field shop any
---@field event any
---@field items table[]
---@field roomType string

local Run = {}

local WORLD_W = 1280
local WORLD_H = 720
Run.WORLD_W = WORLD_W
Run.WORLD_H = WORLD_H

local function Key(r, c)
    return tostring(r) .. "," .. tostring(c)
end
Run.Key = Key

local function NewMods()
    return {
        hpPct = 0, shieldPct = 0, atkPct = 0, asPct = 0, msPct = 0,
        cdrPct = 0, crit = 0, critDmg = 0, lifesteal = 0, dodge = 0,
        basicPct = 0, skillPct = 0, regen = 0, revive = 0,
        rangePct = 0, hurtHeal = 0, critHeal = 0,
    }
end

---@param classLevel integer
---@return PlayerState
function Run.NewPlayer(classLevel)
    local c = Config.Class()
    local hp, sh, atk = Config.ClassStats(classLevel)
    return {
        x = WORLD_W / 2, y = WORLD_H / 2, radius = c.radius or 15,
        classLevel = classLevel,
        baseHp = hp, baseShield = sh, baseAtk = atk,
        maxHp = hp, maxShield = sh, atk = atk,
        hp = hp, shield = math.floor(sh * Config.StartShieldRatio + 0.5),
        attackSpeed = c.attackSpeed or 1.0,
        moveSpeed = c.speed,
        crit = 0, critDmg = 1.5, lifesteal = 0, dodge = 0,
        cdr = 0, basicPct = 0, skillPct = 0, regen = 0,
        rangePct = 0, hurtHeal = 0, critHeal = 0, revive = 0,
        reviveUsed = false,
        mods = NewMods(),
        flags = {},
        classBuffs = {},
        colorPity = 0,
        charges = {},
        buffs = {},
        intent = 0,
        intentTimer = 0,
        attackTimer = 0,
        attackQueued = false,
        cooldowns = {},
        rageTimer = 0,
        parryTimer = 0,
        invulnTimer = 0,
        noDamageTimer = 99,
        hurtHealTimer = 0,
        hurtHealAmount = 0,
    }
end

---@param p PlayerState
function Run.Recompute(p)
    local m = p.mods
    local oldMaxHp = p.maxHp
    local oldMaxShield = p.maxShield
    p.maxHp = math.floor(p.baseHp * (1 + m.hpPct) + 0.5)
    p.maxShield = math.floor(p.baseShield * (1 + m.shieldPct) + 0.5)
    p.atk = p.baseAtk * (1 + m.atkPct)
    p.attackSpeed = (Config.Class().attackSpeed or 1.0) * (1 + m.asPct)
    p.moveSpeed = Config.Class().speed * (1 + m.msPct)
    p.crit = m.crit
    p.critDmg = 1.5 + m.critDmg
    p.lifesteal = m.lifesteal
    p.dodge = m.dodge
    p.cdr = math.min(0.60, m.cdrPct)
    p.basicPct = m.basicPct
    p.skillPct = m.skillPct
    p.regen = m.regen
    p.rangePct = m.rangePct
    p.hurtHeal = m.hurtHeal
    p.critHeal = m.critHeal
    p.revive = m.revive

    local delta = p.maxHp - oldMaxHp
    if delta > 0 then p.hp = p.hp + delta end
    local sdelta = p.maxShield - oldMaxShield
    if sdelta > 0 then p.shield = p.shield + sdelta end
    if p.hp > p.maxHp then p.hp = p.maxHp end
    if p.shield > p.maxShield * 1.5 then p.shield = p.maxShield * 1.5 end
end

function Run.Start(level, bypassGate)
    -- 关卡门槛：步数解锁 + 上一关已通关（测试模式传 bypassGate=true 跳过）
    level = math.max(1, math.min(20, math.floor(level or 1)))
    if not bypassGate then
        local maxPlayable = Save.MaxPlayable(S.data)
        if level > maxPlayable then
            print(string.format("[Run] level %d 未解锁（当前最高 %d），已自动降到 %d",
                level, maxPlayable, maxPlayable))
            level = maxPlayable
        end
    end
    Config.SetClass(Save.ActiveClass(S.data))
    local classLevel = Save.ClassLevel(S.data)
    local p = Run.NewPlayer(classLevel)
    -- 公会科技：初始护盾 / 技能冷却 / 暴伤
    Guild.ApplyRunMods(p, S.data)
    Run.Recompute(p)
    local unlocked = Save.UnlockedSkills(classLevel)
    local saved = Save.Loadout(S.data)
    local used = {}
    local loadout = {}
    for i = 1, 3 do
        local id = saved[i]
        if id and id > 0 and Save.IsSkillUnlocked(classLevel, id) and not used[id] then
            loadout[#loadout + 1] = id
            used[id] = true
        end
    end
    for _, id in ipairs(unlocked) do
        if #loadout >= 3 then break end
        if not used[id] then
            loadout[#loadout + 1] = id
            used[id] = true
        end
    end
    ---@type RunState
    local run = {
        level = level,
        silver = 0,
        step = 0,
        posR = 4,
        posC = 1,
        visited = {},
        cleared = {},
        player = p,
        loadout = loadout,
        shop = nil,
        event = nil,
        items = {},
        roomType = "start",
    }
    run.visited[Key(4, 1)] = true
    run.cleared[Key(4, 1)] = true
    -- 公会局内特权：初始资金 / 保险 / 预警 / 重随券 / 钥匙
    Guild.StartRun(run, S.data)
    Save.Write(S.data)
    S.run = run
    S.screen = "map"
    S.combat = nil
    print("[Run] start level " .. level .. ", class level " .. classLevel)
end

-- 公会团本：单独的一局 Boss 战，不占地图形进度
function Run.StartRaid()
    local Combat = require "Combat"
    -- 团本数值先按第 1 关关底（step 9）计算，不跟角色进度走
    local level = 1
    Config.SetClass(Save.ActiveClass(S.data))
    local classLevel = Save.ClassLevel(S.data)
    local p = Run.NewPlayer(classLevel)
    Guild.ApplyRunMods(p, S.data)
    Run.Recompute(p)

    -- 技能跟随主界面的技能选择（与普通开局一致）
    local unlocked = Save.UnlockedSkills(classLevel)
    local saved = Save.Loadout(S.data)
    local used, loadout = {}, {}
    for i = 1, 3 do
        local id = saved[i]
        if id and id > 0 and Save.IsSkillUnlocked(classLevel, id) and not used[id] then
            loadout[#loadout + 1] = id
            used[id] = true
        end
    end
    for _, id in ipairs(unlocked) do
        if #loadout >= 3 then break end
        if not used[id] then
            loadout[#loadout + 1] = id
            used[id] = true
        end
    end

    local run = {
        level = level,
        silver = 0,
        step = 9,
        posR = 4,
        posC = 1,
        visited = {},
        cleared = {},
        player = p,
        loadout = loadout,
        shop = nil,
        event = nil,
        items = {},
        roomType = "raid",
        guildRaid = true,
        raidDamage = 0,
        raidTier = Guild.RaidTier(S.data),
    }
    Guild.StartRun(run, S.data)
    S.run = run
    S.combat = nil
    S.guild = false
    Combat.Start(run, "raid", 9)
    S.screen = "combat"
    print("[Raid] start guild raid, level " .. level)
end

-- 奖励房重随（消耗公会重随券）
function Run.RerollReward()
    local reward = S.reward
    local run = S.run
    if not reward or not run then return false end
    if (run.guildRerolls or 0) <= 0 then return false end
    run.guildRerolls = run.guildRerolls - 1
    local p = run.player
    local weights = Config.RewardWeights[reward.roomType] or Config.RewardWeights.standard
    local used, options = {}, {}
    for i = 1, 3 do
        local rarity = WeightedFrom(weights)
        local buff = Run.RollAnyBuff(p, rarity)
        local tries = 0
        while used[buff.id] and tries < 12 do
            buff = Run.RollAnyBuff(p, WeightedFrom(weights))
            tries = tries + 1
        end
        used[buff.id] = true
        options[i] = buff
    end
    S.reward = { options = options, roomType = reward.roomType }
    return true
end

function Run.Abort()
    ReleaseInput()
    S.reward = false
    S.run = nil
    S.combat = nil
    S.screen = "menu"
    UI.SetToast("已撤退，本关进度丢失")
end

function Run.CellType(r, c)
    if r < 1 or r > 4 or c < 1 or c > 4 then return nil end
    return Config.MapLayout[r][c]
end

function Run.IsFinal(r, c)
    return r == 1 and c == 4
end

-- 只能向右 / 上 / 下
function Run.CanMove(r, c)
    local run = S.run
    if not run then return false end
    local dr = r - run.posR
    local dc = c - run.posC
    if math.abs(dr) + math.abs(dc) ~= 1 then return false end
    if r < 1 or r > 4 or c < 1 or c > 4 then return false end
    -- 回到走过的房间：允许（空房间可以穿行）
    if run.visited[Key(r, c)] then return true end
    -- 进入新房间：仍然只能向右 / 上 / 下
    if dc < 0 then return false end
    return true
end

---@param r integer
---@param c integer
function Run.Move(r, c)
    local run = S.run
    if not run or not Run.CanMove(r, c) then return end
    local key = Key(r, c)
    local wasVisited = run.visited[key] == true
    run.posR = r
    run.posC = c
    run.visited[key] = true
    run.roomType = Run.CellType(r, c) or "standard"
    if wasVisited then
        S.screen = "map"
        UI.SetToast("回到已清空的房间")
        return
    end
    run.step = run.step + 1
    Run.EnterRoom(run.roomType)
end

function Run.EnterRoom(roomType)
    local run = S.run
    if roomType == "shop" then
        Run.OpenShop()
        S.screen = "shop"
    elseif roomType == "event" then
        Run.OpenEvent()
        S.screen = "event"
    else
        local Combat = require "Combat"
        S.combat = Combat.Start(run, roomType, run.step)
        S.screen = "combat"
    end
end

function Run.OnRoomCleared()
    local run = S.run
    if not run then return end
    run.cleared[Key(run.posR, run.posC)] = true
    if run.roomType == "boss" then
        local data = S.data
        -- 通关记录：下一关要「步数解锁 + 上一关已通关」两个条件都满足才开放
        Save.MarkCleared(data, run.level)
        S.screen = "levelclear"
        S.combat = nil
    else
        S.screen = "map"
        S.combat = nil
    end
end

-- ---------------------------------------------------------------- Buff
local function WeightedRarity()
    local order = { "white", "blue", "purple", "gold" }
    local total = 0
    for _, k in ipairs(order) do total = total + Config.Rarity[k].weight end
    local x = math.random() * total
    for _, k in ipairs(order) do
        x = x - Config.Rarity[k].weight
        if x <= 0 then return k end
    end
    return "white"
end

local function WeightedFrom(weights)
    local order = { "white", "blue", "purple", "gold" }
    local total = 0
    for _, k in ipairs(order) do total = total + (weights[k] or 0) end
    if total <= 0 then return "white" end
    local x = math.random() * total
    for _, k in ipairs(order) do
        x = x - (weights[k] or 0)
        if x <= 0 then return k end
    end
    return "white"
end

function Run.RollBuff(rarity)
    rarity = rarity or WeightedRarity()
    local pool = Config.Buffs[rarity]
    if not pool or #pool == 0 then
        rarity = "white"
        pool = Config.Buffs[rarity]
    end
    local base = pool[math.random(1, #pool)]
    return {
        id = base.id, name = base.name, desc = base.desc,
        mod = base.mod, rarity = rarity,
        price = Config.Rarity[rarity].price,
        color = Config.Rarity[rarity].color,
    }
end

-- ---------------------------------------------------------------- 角色专属 Buff
-- 当前局是否携带了某个技能
function Run.HasSkill(id)
    local run = S.run
    if not run then return true end
    for _, s in ipairs(run.loadout or {}) do
        if s == id then return true end
    end
    return false
end

-- 专属强化要求的技能是否全部携带
function Run.ClassBuffUsable(buff)
    local need = Config.ClassBuffNeed(buff)
    if need then
        for _, id in ipairs(need) do
            if not Run.HasSkill(id) then return false end
        end
    end
    -- 元素类强化：必须携带对应元素的技能（法师：没带冰系就抽不到冰系强化）
    local needEl = Config.ClassBuffElementNeed(buff)
    if needEl then
        local carried = {}
        local loadout = (S.run and S.run.loadout) or {}
        for _, sid in ipairs(loadout) do
            local sk = Config.SkillByID(sid)
            if sk and sk.element then carried[sk.element] = true end
        end
        for el in pairs(needEl) do
            if not carried[el] then return false end
        end
    end
    return true
end

-- 彩色只存在于专属池，出现概率额外压低
function Run.RollClassBuff(p, rarity)
    local group = Config.ClassBuffs[Config.PlayerClass]
    if not group then return nil end
    if not rarity then
        rarity = WeightedRarity()
        local pity = p.colorPity or 0
        if math.random() < 0.06 + 0.03 * pity then rarity = "color" end
    end
    local pool = group[rarity]
    if not pool then return nil end

    local avail = {}
    for _, b in ipairs(pool) do
        if not p.classBuffs[b.id] and Run.ClassBuffUsable(b) then avail[#avail + 1] = b end
    end
    if #avail == 0 and rarity == "color" then
        -- 彩色拿完了就退回到金色，避免重复获取
        rarity = "gold"
        pool = group[rarity] or {}
        avail = {}
        for _, b in ipairs(pool) do
            if not p.classBuffs[b.id] and Run.ClassBuffUsable(b) then avail[#avail + 1] = b end
        end
    end
    if #avail == 0 then return nil end
    local base = avail[math.random(1, #avail)]
    return {
        id = base.id, name = base.name, desc = base.desc,
        mod = base.mod or {}, flag = base.flag or {},
        rarity = rarity, classBuff = true,
        price = Config.Rarity[rarity].price,
        color = Config.Rarity[rarity].color,
    }
end

---@param p PlayerState
---@param rarity string|nil
---@param weights table|nil
function Run.RollAnyBuff(p, rarity, weights)
    rarity = rarity or (weights and WeightedFrom(weights)) or WeightedRarity()
    if math.random() < 0.55 then
        -- 金色专属有小概率升级成彩色；连续没出彩色会把概率推高，第 5 次保底
        local classRarity = rarity
        if rarity == "gold" then
            local pity = (p.colorPity or 0) + 1
            p.colorPity = pity
            local chance = 0.18 + 0.07 * (pity - 1)
            if pity >= 5 or math.random() < chance then classRarity = "color" end
        end
        local cb = Run.RollClassBuff(p, classRarity)
        if cb then return cb end
        if classRarity ~= rarity then
            cb = Run.RollClassBuff(p, rarity)
            if cb then return cb end
        end
    end
    if rarity == "color" then rarity = "gold" end
    return Run.RollBuff(rarity)
end

---@param p PlayerState
function Run.GrantBuff(p, buff)
    if buff.classBuff and p.classBuffs[buff.id] then
        -- 专属强化不重复获取
        return buff
    end
    for k, v in pairs(buff.mod or {}) do
        p.mods[k] = (p.mods[k] or 0) + v
    end
    for k, v in pairs(buff.flag or {}) do
        p.flags[k] = (p.flags[k] or 0) + v
    end
    if buff.classBuff then p.classBuffs[buff.id] = true end
    p.buffs[#p.buffs + 1] = buff
    if buff.rarity == "color" then p.colorPity = 0 end   -- 拿到彩色就重置保底计数
    Run.Recompute(p)
    return buff
end

---@param p PlayerState
---@param rarity string|nil
function Run.GrantRandomBuff(p, rarity)
    local buff = Run.RollAnyBuff(p, rarity)
    Run.GrantBuff(p, buff)
    return buff
end

-- ---------------------------------------------------------------- 战斗房奖励
function Run.OpenCombatReward(roomType)
    ReleaseInput()
    local weights = Config.RewardWeights[roomType] or Config.RewardWeights.standard
    local p = S.run and S.run.player
    if not p then p = { classBuffs = {} } end
    local options = {}
    local used = {}
    local classCount = 0

    for i = 1, 3 do
        local rarity = WeightedFrom(weights)
        local buff = Run.RollAnyBuff(p, rarity)
        local tries = 0
        while used[buff.id] and tries < 12 do
            buff = Run.RollAnyBuff(p, WeightedFrom(weights))
            tries = tries + 1
        end
        used[buff.id] = true
        if buff.classBuff then classCount = classCount + 1 end
        options[i] = buff
    end

    -- 至少保证一张剑客专属
    if classCount == 0 then
        local cb = Run.RollClassBuff(p)
        if cb and cb.rarity ~= "color" then
            local idx = math.random(1, 3)
            used[options[idx].id] = nil
            options[idx] = cb
        end
    end

    -- 三个选项品质完全相同时，抬高一档，避免三张同色
    if options[1].rarity == options[2].rarity and options[2].rarity == options[3].rarity then
        local order = { "white", "blue", "purple", "gold" }
        local idx = 1
        for i, r in ipairs(order) do
            if r == options[1].rarity then idx = i end
        end
        local nextRarity = order[math.min(#order, idx + 1)]
        options[math.random(1, 3)] = Run.RollAnyBuff(p, nextRarity)
    end

    S.reward = { options = options, roomType = roomType }
    S.combat = nil
    S.screen = "reward"
end

function Run.FinishRoom()
    local run = S.run
    if not run then return end
    run.cleared[Key(run.posR, run.posC)] = true
    S.screen = "map"
end

function Run.ChooseReward(index)
    local reward = S.reward
    if not reward then return end
    local buff = reward.options[index]
    if not buff then return end
    Run.GrantBuff(S.run.player, buff)
    S.reward = false
    Run.FinishRoom()
end

function Run.SkipReward()
    if not S.reward then return end
    S.run.silver = S.run.silver + 15
    S.reward = false
    Run.FinishRoom()
end

function Run.OnCombatCleared(roomType)
    if roomType == "raid" then return end   -- 团本结算由 Combat.FinishRaid 负责
    if roomType == "boss" then
        Run.OnRoomCleared()
    else
        Run.OpenCombatReward(roomType)
    end
end

---@param p PlayerState
function Run.Heal(p, pct)
    local amount = p.maxHp * pct
    if (p.necrosisTimer or 0) > 0 then amount = amount * 0.5 end
    p.hp = math.min(p.maxHp, p.hp + amount)
    return amount
end

-- ---------------------------------------------------------------- 商店
function Run.OpenShop()
    ReleaseInput()
    local run = S.run
    run.shop = { freeRefreshUsed = false, paidRefresh = 0, slots = {} }
    Run.RefreshShop()
end

function Run.RefreshShop()
    local run = S.run
    local shop = run.shop
    if not shop then return end
    local old = shop.slots
    local slots = {}

    -- 恢复品固定 1 小 1 大
    slots[1] = { kind = "potion", item = "small", name = Config.Shop.PotionSmall.name,
        desc = Config.Shop.PotionSmall.desc, price = Config.Shop.PotionSmall.price, sold = false }
    slots[2] = { kind = "potion", item = "large", name = Config.Shop.PotionLarge.name,
        desc = Config.Shop.PotionLarge.desc, price = Config.Shop.PotionLarge.price, sold = false }

    -- 药水 2 格
    local cons = Config.Shop.Consumables
    local a = math.random(1, #cons)
    local b = a
    while b == a do b = math.random(1, #cons) end
    slots[3] = { kind = "consumable", item = cons[a].id, name = cons[a].name,
        desc = cons[a].desc, price = cons[a].price, sold = false }
    slots[4] = { kind = "consumable", item = cons[b].id, name = cons[b].name,
        desc = cons[b].desc, price = cons[b].price, sold = false }

    -- 6 个 Buff + 保底（含剑客专属）
    local buffs = {}
    for i = 1, 6 do buffs[i] = Run.RollAnyBuff(run.player) end
    local hasPurple, hasGold = false, false
    for _, bf in ipairs(buffs) do
        if bf.rarity == "purple" then hasPurple = true end
        if bf.rarity == "gold" then hasGold = true end
    end
    if not hasPurple then
        local idx = 1
        for i = 1, 6 do
            if buffs[i].rarity ~= "gold" then idx = i break end
        end
        buffs[idx] = Run.RollAnyBuff(run.player, "purple")
    end
    hasGold = false
    for _, bf in ipairs(buffs) do
        if bf.rarity == "gold" then hasGold = true end
    end
    if not hasGold then
        local idx = 1
        for i = 1, 6 do
            if buffs[i].rarity ~= "purple" then idx = i break end
        end
        buffs[idx] = Run.RollAnyBuff(run.player, "gold")
    end
    for i = 1, 6 do
        local bf = buffs[i]
        slots[4 + i] = { kind = "buff", buff = bf, name = bf.name, desc = bf.desc,
            price = bf.price, sold = false, rarity = bf.rarity, classBuff = bf.classBuff }
    end

    -- 保留已售罄格
    if old then
        for i, oldSlot in ipairs(old) do
            if oldSlot.sold and slots[i] then
                slots[i] = { kind = "empty", sold = true, price = 0, name = "", desc = "" }
            end
        end
    end

    shop.slots = slots
end

local ITEM_SHORT = {
    potion_small = "小药",
    potion_large = "大药",
    shield = "盾",
    rage = "狂",
}

function Run.ItemInfo(id)
    if id == "potion_small" then
        local d = Config.Shop.PotionSmall
        return { id = id, name = d.name, short = ITEM_SHORT[id], desc = d.desc, kind = "potion", heal = d.heal }
    elseif id == "potion_large" then
        local d = Config.Shop.PotionLarge
        return { id = id, name = d.name, short = ITEM_SHORT[id], desc = d.desc, kind = "potion", heal = d.heal }
    end
    for _, c in ipairs(Config.Shop.Consumables) do
        if c.id == id then
            return { id = id, name = c.name, short = ITEM_SHORT[id] or "", desc = c.desc, kind = "consumable" }
        end
    end
    return nil
end

function Run.AddItem(id)
    local run = S.run
    if not run then return end
    for _, it in ipairs(run.items) do
        if it.id == id then
            it.count = it.count + 1
            return
        end
    end
    run.items[#run.items + 1] = { id = id, count = 1 }
end

-- 使用道具栏第一件道具，返回 id, info
function Run.UseItemAt(index)
    local run = S.run
    if not run then return nil, nil end
    local it = run.items[index]
    if not it then return nil, nil end
    local info = Run.ItemInfo(it.id)
    it.count = it.count - 1
    if it.count <= 0 then
        table.remove(run.items, index)
    end
    return it.id, info
end

function Run.UseFirstItem()
    return Run.UseItemAt(1)
end

function Run.BuySlot(index)
    local run = S.run
    local shop = run and run.shop
    if not shop then return end
    local slot = shop.slots[index]
    if not slot or slot.sold or slot.kind == "empty" then return end
    if run.silver < slot.price then
        UI.SetToast("银币不足")
        return
    end
    run.silver = run.silver - slot.price
    slot.sold = true

    local p = run.player
    if slot.kind == "potion" then
        local id = slot.item == "small" and "potion_small" or "potion_large"
        Run.AddItem(id)
        UI.SetToast("已放入道具栏，战斗中按 E 或点道具按钮")
    elseif slot.kind == "consumable" then
        Run.AddItem(slot.item)
        UI.SetToast("已放入道具栏，战斗中按 E 或点道具按钮")
    elseif slot.kind == "buff" then
        Run.GrantBuff(p, slot.buff)
        UI.SetToast("获得 " .. slot.name)
    end
end

function Run.Refresh()
    local shop = S.run and S.run.shop
    if not shop then return end
    if not shop.freeRefreshUsed then
        shop.freeRefreshUsed = true
        Run.RefreshShop()
        return
    end
    Run.PaidRefresh()
end

function Run.PaidRefresh()
    local shop = S.run and S.run.shop
    if not shop then return end
    if shop.paidRefresh >= Config.Shop.RefreshLimit then
        UI.SetToast("本商店刷新次数已用完")
        return
    end
    if S.run.silver < Config.Shop.RefreshPrice then
        UI.SetToast("银币不足")
        return
    end
    S.run.silver = S.run.silver - Config.Shop.RefreshPrice
    shop.paidRefresh = shop.paidRefresh + 1
    Run.RefreshShop()
end

function Run.CloseShop()
    S.run.shop = nil
    S.run.cleared[Key(S.run.posR, S.run.posC)] = true
    S.screen = "map"
end

-- ---------------------------------------------------------------- 事件
local function PickEventDef()
    local roll = math.random(1, 3)
    return roll
end

function Run.OpenEvent()
    ReleaseInput()
    local run = S.run
    local p = run.player
    local id = PickEventDef()
    local ev

    if id == 1 then
        local bet = math.floor(run.silver * 0.3)
        ev = {
            title = "流浪商人的骰子赌局",
            text = "商人晃了晃骰盅：「押上你三成银币，掷出 4 点以上，我双倍还你。」",
            options = {},
        }
        ev.options[1] = {
            label = "押注 " .. bet .. " 银币",
            enabled = bet >= 5,
            action = function()
                local roll = math.random(1, 6)
                if roll >= 4 then
                    run.silver = run.silver + bet
                    return string.format("掷出 %d 点，赢得 %d 银币。", roll, bet)
                else
                    run.silver = run.silver - bet
                    return string.format("掷出 %d 点，输掉 %d 银币。", roll, bet)
                end
            end,
        }
        ev.options[2] = {
            label = "花 10 银币买一张随机 Buff",
            enabled = run.silver >= 10,
            action = function()
                run.silver = run.silver - 10
                local bf = Run.GrantRandomBuff(p)
                return "商人塞给你一张「" .. bf.name .. "」：" .. bf.desc
            end,
        }
    elseif id == 2 then
        ev = {
            title = "遗忘的藏宝洞",
            text = "洞里摆着三张背面朝上的卡牌，最里面还压着一小袋银币。",
            options = {},
        }
        for i = 1, 3 do
            ev.options[i] = {
                label = "翻开第 " .. i .. " 张卡",
                enabled = true,
                action = function()
                    local rarity = ({ "white", "blue", "purple" })[math.random(1, 3)]
                    local bf = Run.GrantRandomBuff(p, rarity)
                    return "卡牌化作「" .. bf.name .. "」：" .. bf.desc
                end,
            }
        end
        ev.options[4] = {
            label = "不翻牌，拿走 30 银币",
            enabled = true,
            action = function()
                run.silver = run.silver + 30
                return "你拿走钱袋，获得 30 银币。"
            end,
        }
    else
        local cost = math.floor(p.maxHp * 0.3)
        ev = {
            title = "篝火旁的陌生人",
            text = "陌生人往火里添了根柴：「用一点血，换一点运气，公平交易。」",
            options = {},
        }
        ev.options[1] = {
            label = "献出 " .. cost .. " 生命，换 1 个金色 Buff",
            enabled = p.hp > cost,
            action = function()
                p.hp = math.max(1, p.hp - cost)
                local bf = Run.GrantRandomBuff(p, "gold")
                return "火光一闪，你获得「" .. bf.name .. "」：" .. bf.desc
            end,
        }
        ev.options[2] = {
            label = "只烤火，恢复 50% 生命",
            enabled = true,
            action = function()
                local amount = Run.Heal(p, 0.5)
                return string.format("你恢复 %d 点生命。", math.floor(amount))
            end,
        }
    end

    ev.result = nil
    run.event = ev
end

function Run.ChooseEvent(index)
    local run = S.run
    local ev = run and run.event
    if not ev or ev.result then return end
    local opt = ev.options[index]
    if not opt or opt.enabled == false then return end
    ev.result = opt.action()
end

function Run.CloseEvent()
    local run = S.run
    run.event = nil
    run.cleared[Key(run.posR, run.posC)] = true
    S.screen = "map"
end

-- ---------------------------------------------------------------- 关卡结束
function Run.ReturnToMenu()
    S.showStatus = false
    ReleaseInput()
    S.input.x = 0
    S.input.y = 0
    S.reward = false
    S.run = nil
    S.combat = nil
    S.screen = "menu"
end

return Run
