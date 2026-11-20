-- Camp.lua — 营地（局外）系统：局外商店 / 农场 / 窝
-- 口径：《描述表格_经济系统优化版》3 表（局外商店）、1 表（种子→果实、建材盖窝）
--
-- 宠物不在这里：宠物是独立收集系统（见 PetData.lua / Pet.lua / PetUI.lua），
-- 用自己的「宠物代币」，与精粹、金币都不互通。
-- 金币（局内）也不进入这里：局外只收精粹。

local Config = require "Config"
local Economy = require "Economy"

local Camp = {}

-- ---------------------------------------------------------------- 局外商店（只收精粹）
Camp.ShopItems = {
    { id = "key",       name = "钥匙",       group = "门票", price = 10, qty = 1,  unit = "把",
      limit = { kind = "daily", key = "keyBought", n = 3 },  desc = "开局带入 1 把钥匙，可在地图上额外开一次奖励房" },
    { id = "streakcard", name = "间断卡",    group = "门票", price = 30, qty = 1,  unit = "张",
      limit = { kind = "every3days" },                        desc = "补一次健康断签（限 1 天），断签当天领取时自动续上" },
    { id = "mat_basic", name = "基础建材",   group = "养成", price = 50, qty = 10, unit = "个",
      limit = { kind = "none" },                              desc = "盖窝用（每次 10 个）" },
    { id = "mat_mid",   name = "中级建材",   group = "养成", price = 100, qty = 5, unit = "个",
      limit = { kind = "none" },                              desc = "盖窝用（每次 5 个）" },
    { id = "seed_basic", name = "基础种子",  group = "农场", price = 50, qty = 1,  unit = "颗",
      limit = { kind = "daily", key = "seedBasicBought", n = 3 }, desc = "种出白色/蓝色果实（30 分钟成熟）" },
    { id = "seed_rare", name = "稀有种子",   group = "农场", price = 200, qty = 1, unit = "颗",
      limit = { kind = "daily", key = "seedRareBought", n = 1 },  desc = "种出紫色/金色果实（120 分钟成熟）" },
}

-- 种子 → 果实（1 表：种植 → 果实 → 局内 Buff）
Camp.Seeds = {
    basic = { name = "基础种子", minutes = 30, outcomes = { { rarity = "white", w = 75 }, { rarity = "blue", w = 25 } } },
    rare  = { name = "稀有种子", minutes = 120, outcomes = { { rarity = "purple", w = 80 }, { rarity = "gold", w = 20 } } },
}

-- 窝升级（建材 → 盖窝；等级只影响农场地块数）
Camp.NestLevels = {
    { level = 2, basic = 20, mid = 5 },
    { level = 3, basic = 40, mid = 12 },
    { level = 4, basic = 70, mid = 25 },
    { level = 5, basic = 110, mid = 45 },
}

-- ---------------------------------------------------------------- 存档结构
local function defaultCamp()
    return {
        keys = 0,
        streakCards = 0,
        mats = { basic = 0, mid = 0 },
        seeds = { basic = 0, rare = 0 },
        fruits = { white = 0, blue = 0, purple = 0, gold = 0 },
        equippedFruit = nil,
        plots = {},
        nestLevel = 1,
        day = { key = "", keyBought = 0, seedBasicBought = 0, seedRareBought = 0, cardDay = -999 },
    }
end

local function num(v, d)
    if type(v) ~= "number" then return d end
    return v
end

--- 补齐/修复营地存档结构，返回 data.camp
---@param data table
---@return table
function Camp.Ensure(data)
    if type(data) ~= "table" then return defaultCamp() end
    local def = defaultCamp()
    local c = data.camp
    if type(c) ~= "table" then
        data.camp = defaultCamp()
        c = data.camp
    end
    -- 旧版营地里养宠物的字段已废弃（宠物已独立成系统）
    c.pets = nil
    c.eggs = nil
    c.gacha = nil
    c.speed50 = nil
    c.speed20 = nil
    c.slots = nil
    for k, v in pairs(def) do
        if c[k] == nil then c[k] = v end
    end
    for _, k in ipairs({ "keys", "streakCards", "nestLevel" }) do
        c[k] = math.max(0, math.floor(num(c[k], 0)))
    end
    c.nestLevel = math.max(1, math.min(#Camp.NestLevels + 1, c.nestLevel))
    if type(c.mats) ~= "table" then c.mats = { basic = 0, mid = 0 } end
    c.mats.basic = math.max(0, math.floor(num(c.mats.basic, 0)))
    c.mats.mid = math.max(0, math.floor(num(c.mats.mid, 0)))
    if type(c.seeds) ~= "table" then c.seeds = { basic = 0, rare = 0 } end
    for _, k in ipairs({ "basic", "rare" }) do c.seeds[k] = math.max(0, math.floor(num(c.seeds[k], 0))) end
    if type(c.fruits) ~= "table" then c.fruits = { white = 0, blue = 0, purple = 0, gold = 0 } end
    for _, k in ipairs({ "white", "blue", "purple", "gold" }) do
        c.fruits[k] = math.max(0, math.floor(num(c.fruits[k], 0)))
    end
    if type(c.plots) ~= "table" then c.plots = {} end
    if type(c.day) ~= "table" then c.day = def.day end
    c.day.cardDay = num(c.day.cardDay, -999)
    return c
end

local function dayNum(data)
    return math.floor(os.time() / 86400) + ((data and data.dayOffset) or 0)
end

--- 跨天：清空每日限购（由 Save.RollDay 调用，dayKey 已更新）
---@param data table
function Camp.RollDay(data)
    local c = Camp.Ensure(data)
    local key = (data and data.dayKey) or ""
    if c.day.key ~= key then
        c.day.key = key
        c.day.keyBought = 0
        c.day.seedBasicBought = 0
        c.day.seedRareBought = 0
    end
end

-- ---------------------------------------------------------------- 窝
--- 当前地块数
function Camp.Plots(data)
    local c = Camp.Ensure(data)
    return math.min(6, 1 + c.nestLevel)
end

--- 下一个窝等级的升级费用（满级返回 nil）
function Camp.NextNest(data)
    local c = Camp.Ensure(data)
    return Camp.NestLevels[c.nestLevel]
end

--- 盖窝：花基础 / 中级建材升级
---@return boolean, string
function Camp.UpgradeNest(data)
    local c = Camp.Ensure(data)
    local next = Camp.NextNest(data)
    if not next then return false, "窝已经满级" end
    if c.mats.basic < next.basic then
        return false, string.format("基础建材不足，还差 %d", next.basic - c.mats.basic)
    end
    if c.mats.mid < next.mid then
        return false, string.format("中级建材不足，还差 %d", next.mid - c.mats.mid)
    end
    c.mats.basic = c.mats.basic - next.basic
    c.mats.mid = c.mats.mid - next.mid
    c.nestLevel = c.nestLevel + 1
    return true, string.format("窝升到 Lv.%d：农场地块 %d 块", c.nestLevel, Camp.Plots(data))
end

-- ---------------------------------------------------------------- 局外商店
function Camp.Item(id)
    for _, it in ipairs(Camp.ShopItems) do
        if it.id == id then return it end
    end
    return nil
end

--- 当前售价（这里都是固定价，宠物相关商品已不在营地）
function Camp.Price(data, item)
    return item.price
end

--- 今日剩余可买次数（-1 表示不限）
function Camp.RemainToday(data, item)
    local c = Camp.Ensure(data)
    local kind = item.limit.kind
    if kind == "none" then return -1 end
    if kind == "daily" then
        return math.max(0, item.limit.n - num(c.day[item.limit.key], 0))
    end
    if kind == "every3days" then
        if dayNum(data) - num(c.day.cardDay, -999) >= 3 then return 1 end
        return 0
    end
    return -1
end

local function markBought(data, item)
    local c = Camp.Ensure(data)
    local kind = item.limit.kind
    if kind == "daily" then
        c.day[item.limit.key] = num(c.day[item.limit.key], 0) + 1
    elseif kind == "every3days" then
        c.day.cardDay = dayNum(data)
    end
end

--- 购买一件局外商品（只收精粹）
---@return boolean, string
function Camp.Buy(data, itemId)
    local c = Camp.Ensure(data)
    local item = Camp.Item(itemId)
    if not item then return false, "没有这个商品" end
    if Camp.RemainToday(data, item) == 0 then
        return false, "限购已用完（每日 5:00 刷新）"
    end
    local price = Camp.Price(data, item)
    if not Economy.SpendEssence(data, price) then
        return false, string.format("精粹不足，还差 %d", price - Economy.Essence(data))
    end

    if item.id == "key" then
        c.keys = c.keys + 1
    elseif item.id == "streakcard" then
        c.streakCards = c.streakCards + 1
    elseif item.id == "mat_basic" then
        c.mats.basic = c.mats.basic + item.qty
    elseif item.id == "mat_mid" then
        c.mats.mid = c.mats.mid + item.qty
    elseif item.id == "seed_basic" then
        c.seeds.basic = c.seeds.basic + 1
    elseif item.id == "seed_rare" then
        c.seeds.rare = c.seeds.rare + 1
    end
    markBought(data, item)
    return true, string.format("已购买 %s（-%d 精粹）", item.name, price)
end

-- ---------------------------------------------------------------- 农场
function Camp.Plot(data, index)
    return Camp.Ensure(data).plots[index]
end

function Camp.PlotBusy(data, index)
    local plot = Camp.Plot(data, index)
    return plot ~= nil and plot.seed ~= nil
end

--- 播种
---@return boolean, string
function Camp.Plant(data, index, kind)
    local c = Camp.Ensure(data)
    local def = Camp.Seeds[kind]
    if not def then return false, "没有这种种子" end
    if index < 1 or index > Camp.Plots(data) then return false, "这块地还没开垦" end
    if Camp.PlotBusy(data, index) then return false, "这块地已经种了东西" end
    if (c.seeds[kind] or 0) <= 0 then return false, "没有" .. def.name end
    c.seeds[kind] = c.seeds[kind] - 1
    c.plots[index] = { seed = kind, readyAt = os.time() + def.minutes * 60 }
    return true, string.format("已种下 %s（%d 分钟成熟）", def.name, def.minutes)
end

--- 剩余成熟秒数（0 = 可收获）
function Camp.PlotLeft(plot)
    if not plot or not plot.seed then return 0 end
    return math.max(0, math.floor((plot.readyAt or 0) - os.time()))
end

--- 收获：产出一颗果实
---@return boolean, string
function Camp.Harvest(data, index)
    local c = Camp.Ensure(data)
    local plot = c.plots[index]
    if not plot or not plot.seed then return false, "这块地没有作物" end
    if Camp.PlotLeft(plot) > 0 then return false, "还没成熟" end
    local def = Camp.Seeds[plot.seed]
    local total = 0
    for _, o in ipairs(def.outcomes) do total = total + o.w end
    local r = math.random() * total
    local rarity = def.outcomes[1].rarity
    for _, o in ipairs(def.outcomes) do
        r = r - o.w
        if r <= 0 then rarity = o.rarity break end
    end
    c.plots[index] = nil
    c.fruits[rarity] = (c.fruits[rarity] or 0) + 1
    return true, string.format("收获 %s果实 +1", Config.Rarity[rarity].name)
end

--- 把一颗果实装进背包（开局消耗，给一个该品质随机 Buff）
---@return boolean, string
function Camp.EquipFruit(data, rarity)
    local c = Camp.Ensure(data)
    if (c.fruits[rarity] or 0) <= 0 then return false, "没有这种果实" end
    if c.equippedFruit then return false, "背包里已经装了一颗果实（先取下）" end
    c.fruits[rarity] = c.fruits[rarity] - 1
    c.equippedFruit = rarity
    return true, string.format("已装入 %s果实：下一局开局获得一个该品质 Buff", Config.Rarity[rarity].name)
end

function Camp.UnequipFruit(data)
    local c = Camp.Ensure(data)
    if not c.equippedFruit then return false end
    c.fruits[c.equippedFruit] = (c.fruits[c.equippedFruit] or 0) + 1
    c.equippedFruit = nil
    return true
end

-- ---------------------------------------------------------------- 背包（局外物品总览）
---@return table[] list { group, name, count, unit, desc, rarity }
function Camp.Inventory(data)
    local c = Camp.Ensure(data)
    local list = {}
    local function add(group, name, count, unit, desc, rarity)
        count = math.floor(count or 0)
        if count > 0 then
            list[#list + 1] = { group = group, name = name, count = count, unit = unit or "个",
                desc = desc or "", rarity = rarity }
        end
    end

    add("门票", "钥匙", c.keys, "把", "开局带入，地图上额外开一次奖励房")
    add("门票", "间断卡", c.streakCards, "张", "断签当天领取时自动续上连续天数（限 1 天）")
    add("材料", "基础建材", c.mats.basic, "个", "盖窝用（窝升级要基础 + 中级建材）")
    add("材料", "中级建材", c.mats.mid, "个", "盖窝用（窝升级要基础 + 中级建材）")
    add("农场", "基础种子", c.seeds.basic, "颗", "30 分钟成熟，产白/蓝果实")
    add("农场", "稀有种子", c.seeds.rare, "颗", "120 分钟成熟，产紫/金果实")
    for _, r in ipairs({ "white", "blue", "purple", "gold" }) do
        add("果实", Config.Rarity[r].name .. "果实", c.fruits[r] or 0, "颗",
            "装背包后，下一局开局获得一个该品质随机 Buff", r)
    end
    if c.equippedFruit then
        add("果实", "已装备：「" .. Config.Rarity[c.equippedFruit].name .. "果实」", 1, "颗",
            "下一局开局就会消耗掉", c.equippedFruit)
    end
    return list
end

-- ---------------------------------------------------------------- 开局结算
--- 开局：带入钥匙、消耗果实换 Buff
---@return table info { keys, fruitRarity, buffName }
function Camp.StartRun(run, data, grantFruitBuff)
    local c = Camp.Ensure(data)
    local info = { keys = 0, fruitRarity = nil, buffName = nil }

    if (c.keys or 0) > 0 then
        run.guildKeys = (run.guildKeys or 0) + c.keys
        info.keys = c.keys
        c.keys = 0
    end

    if c.equippedFruit and grantFruitBuff then
        local rarity = c.equippedFruit
        local buff = grantFruitBuff(rarity)
        if buff then
            info.fruitRarity = rarity
            info.buffName = buff.name
            c.equippedFruit = nil
        end
    end
    return info
end

return Camp
