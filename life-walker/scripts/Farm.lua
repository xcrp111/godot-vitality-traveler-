-- Farm.lua — 农场系统（单机版）：种植 / 浇水 / 收获 / 果实 Buff / 声望商店
-- 设计文档：农场系统设计.docx（好友访问、偷菜、赠送等社交部分暂未接入）
-- 纯逻辑模块：只依赖 Config，状态全部落在 data.farm，UI 由 FarmUI.lua 负责。

local Config = require "Config"

local Farm = {}

-- ---------------------------------------------------------------- 常量
Farm.FRUIT_CAP = 30          -- 每种果实最多存 30 个
Farm.EQUIP_MAX = 3           -- 战斗前最多携带 3 种果实
Farm.WATER_SEC = 15 * 60     -- 每次浇水减少当前阶段 15 分钟
Farm.WATER_CD = 2 * 3600     -- 默认浇水冷却 2 小时
Farm.WATER_CD_REP1 = 90 * 60 -- 声望 Lv.1 后冷却 1.5 小时
Farm.WATER_DAILY = 20        -- 每日浇水次数上限
Farm.REP_DAILY_CAP = 50      -- 每日声望上限

-- 声望等级（替代文档里的好友友好度，单人农场用浇水 / 收获积累）
Farm.REP_LEVELS = {
    { level = 0, need = 0,    name = "陌生人" },
    { level = 1, need = 30,   name = "点头之交" },
    { level = 2, need = 100,  name = "普通好友" },
    { level = 3, need = 300,  name = "亲密好友" },
    { level = 4, need = 600,  name = "最佳搭档" },
    { level = 5, need = 1200, name = "莫逆之交" },
    { level = 6, need = 1800, name = "灵魂羁绊" },
}

-- 作物（生长时间单位：小时；stages = 发芽 / 生长 / 成熟 的时长，合计 = total）
---@class FarmCrop
---@field id string
---@field name string
---@field seedType string
---@field total number
---@field stages number[]
---@field yield integer
---@field fruitName string
---@field effect string
---@field color number[]
---@field unlock table
---@type FarmCrop[]
Farm.Crops = {
    {
        id = "fire", name = "火灵果", seedType = "basic", total = 4,
        stages = { 1, 1.5, 1.5 }, yield = 3,
        fruitName = "火灵果", effect = "攻击力 +10%（本关）",
        color = { 235, 110, 80 }, unlock = {},
    },
    {
        id = "ice", name = "冰晶草", seedType = "basic", total = 6,
        stages = { 1.5, 2.5, 2 }, yield = 3,
        fruitName = "冰晶草", effect = "护盾上限 +15%（本关）",
        color = { 120, 200, 255 }, unlock = {},
    },
    {
        id = "thunder", name = "雷击木", seedType = "basic", total = 8,
        stages = { 2, 3, 3 }, yield = 4,
        fruitName = "雷击木", effect = "技能冷却 -10%（本关）",
        color = { 200, 180, 90 }, unlock = { stage = 3 },
    },
    {
        id = "gold", name = "生息花", seedType = "basic", total = 6,
        stages = { 1.5, 2.5, 2 }, yield = 5,
        fruitName = "生息花", effect = "本关开局额外 +50 血尘",
        color = { 245, 200, 80 }, unlock = { stage = 5 },
    },
    {
        id = "life", name = "生命之花", seedType = "rare", total = 12,
        stages = { 3, 5, 4 }, yield = 3,
        fruitName = "生命之花", effect = "生命上限 +20%（本关）",
        color = { 120, 230, 140 }, unlock = { stage = 10 },
    },
    {
        id = "mushroom", name = "彩虹蘑菇", seedType = "rare", total = 8,
        stages = { 2, 3, 3 }, yield = 3,
        fruitName = "彩虹蘑菇", effect = "随机获得 1 个白色强化（本关）",
        color = { 230, 140, 220 }, unlock = { repLevel = 3 },
    },
    {
        id = "timevine", name = "时空藤", seedType = "epic", total = 16,
        stages = { 4, 7, 5 }, yield = 3,
        fruitName = "时空藤", effect = "本关额外获得 3 次奖励重随",
        color = { 150, 120, 240 }, unlock = { stage = 12 },
    },
    {
        id = "chaos", name = "混沌花", seedType = "epic", total = 14,
        stages = { 3.5, 6, 4.5 }, yield = 3,
        fruitName = "混沌花", effect = "随机获得 1 个蓝色或紫色强化（本关）",
        color = { 210, 110, 190 }, unlock = { repSpent = 2000 },
    },
    {
        id = "phoenix", name = "凤凰花", seedType = "legendary", total = 24,
        stages = { 6, 10, 8 }, yield = 2,
        fruitName = "凤凰花", effect = "本关死亡时自动复活一次，恢复 50% 生命",
        color = { 255, 120, 90 }, unlock = { stage = 15 },
    },
}

-- 生息商店（每日限购）
Farm.GoldShop = {
    { id = "basic", name = "基础种子（随机）", price = 50, daily = 3 },
    { id = "rare",  name = "稀有种子（随机）", price = 200, daily = 3 },
}

-- 声望商店
Farm.RepShop = {
    { id = "basic",     name = "基础种子（随机）", cost = 10,  limit = 5, period = "day",  seedType = "basic" },
    { id = "rare",      name = "稀有种子（随机）", cost = 50,  limit = 2, period = "day",  seedType = "rare" },
    { id = "epic",      name = "史诗种子（随机）", cost = 100, limit = 5, period = "week", seedType = "epic" },
    { id = "legendary", name = "传说种子（随机）", cost = 150, limit = 3, period = "week", seedType = "legendary" },
    { id = "can",       name = "超级浇水水壶",     cost = 80,  limit = 5, period = "week" },
    { id = "land",      name = "土地解锁券",       cost = 200, limit = 5, period = "total" },
}

-- ---------------------------------------------------------------- 工具
function Farm.Now(data)
    return os.time() + ((data and data.dayOffset) or 0) * 86400
end

function Farm.Day(data)
    return os.date("%Y-%m-%d", Farm.Now(data))
end

function Farm.Week(data)
    local t = Farm.Now(data)
    local dt = os.date("*t", t)
    local wday = type(dt) == "table" and dt.wday or nil
    local back
    if type(wday) == "number" and wday >= 1 and wday <= 7 then
        back = (wday + 5) % 7
    else
        back = (math.floor(t / 86400) + 3) % 7
    end
    return os.date("%Y-%m-%d", t - back * 86400)
end

function Farm.CropByID(id)
    for _, c in ipairs(Farm.Crops) do
        if c.id == id then return c end
    end
    return nil
end

function Farm.FruitByID(id)
    return Farm.CropByID(id)
end

local function defaultFarm()
    local plots = {}
    for i = 1, 9 do
        plots[i] = { crop = nil, plantedAt = 0, waterBonus = 0, waterAt = 0 }
    end
    return {
        plots = plots,
        landCount = 4,
        seeds = {},
        fruits = {},
        equipped = {},
        rep = 0,
        repSpent = 0,
        repDay = "",
        repToday = 0,
        day = "",
        week = "",
        dailyBattles = 0,
        battleDay = "",
        battleReward = false,
        weeklyLayers = 0,
        layerWeek = "",
        layerReward = false,
        waterToday = 0,
        shopDay = "",
        shopBasic = 0,
        shopRare = 0,
        repShopDay = "",
        repShopWeek = "",
        repDailyBasic = 0,
        repDailyRare = 0,
        repWeeklyEpic = 0,
        repWeeklyLegendary = 0,
        repWeeklyCan = 0,
        landTicketsBought = 0,
        cans = 0,
        harvestCount = 0,
        starterGiven = false,
    }
end

function Farm.Ensure(data)
    if type(data) ~= "table" then return nil end
    if type(data.farm) ~= "table" then
        data.farm = defaultFarm()
    end
    local f = data.farm
    local def = defaultFarm()
    for k, v in pairs(def) do
        if f[k] == nil then f[k] = v end
    end
    if type(f.plots) ~= "table" then f.plots = def.plots end
    for i = 1, 9 do
        if type(f.plots[i]) ~= "table" then
            f.plots[i] = { crop = nil, plantedAt = 0, waterBonus = 0, waterAt = 0 }
        end
    end
    if type(f.seeds) ~= "table" then f.seeds = {} end
    if type(f.fruits) ~= "table" then f.fruits = {} end
    if type(f.equipped) ~= "table" then f.equipped = {} end
    if type(f.landCount) ~= "number" then f.landCount = 4 end
    f.landCount = math.max(4, math.min(9, math.floor(f.landCount)))
    -- 首次解锁送一点起步种子（火灵果 / 冰晶草各 2 颗）
    if (data.stageCleared or 0) >= 2 and not f.starterGiven then
        f.starterGiven = true
        f.seeds.fire = (f.seeds.fire or 0) + 2
        f.seeds.ice = (f.seeds.ice or 0) + 2
    end
    return f
end

--- 跨天 / 跨周重置。任何时候调用都安全。
function Farm.Roll(data)
    local f = Farm.Ensure(data)
    if not f then return nil end
    local day, week = Farm.Day(data), Farm.Week(data)
    if f.day ~= day then
        f.day = day
        f.dailyBattles = 0
        f.battleDay = day
        f.battleReward = false
        f.waterToday = 0
        f.repToday = 0
        f.repDay = day
        f.shopBasic = 0
        f.shopRare = 0
        f.shopDay = day
        f.repDailyBasic = 0
        f.repDailyRare = 0
        f.repShopDay = day
    end
    if f.week ~= week then
        f.week = week
        f.weeklyLayers = 0
        f.layerWeek = week
        f.layerReward = false
        f.repWeeklyEpic = 0
        f.repWeeklyLegendary = 0
        f.repWeeklyCan = 0
        f.repShopWeek = week
    end
    return f
end

-- ---------------------------------------------------------------- 解锁 / 声望
function Farm.Unlocked(data)
    return data and (data.stageCleared or 0) >= 2
end

function Farm.RepLevel(data)
    local f = Farm.Ensure(data)
    -- 等级按「累计获得」算（当前余额 + 已消耗），避免在商店花声望后掉级、把已解锁内容重新锁上
    local rep = f and ((f.rep or 0) + (f.repSpent or 0)) or 0
    local lv = 0
    for i, row in ipairs(Farm.REP_LEVELS) do
        if rep >= row.need then lv = i - 1 end
    end
    return lv
end

function Farm.RepLevelName(data)
    local lv = Farm.RepLevel(data)
    local row = Farm.REP_LEVELS[lv + 1]
    return row and row.name or "陌生人"
end

function Farm.RepNextNeed(data)
    local lv = Farm.RepLevel(data)
    local row = Farm.REP_LEVELS[lv + 2]
    return row and row.need or nil
end

function Farm.CropUnlocked(data, crop)
    local u = crop.unlock or {}
    if u.stage and (data.stageCleared or 0) < u.stage then return false end
    if u.repLevel and Farm.RepLevel(data) < u.repLevel then return false end
    if u.repSpent then
        local f = Farm.Ensure(data)
        if (f.repSpent or 0) < u.repSpent then return false end
    end
    return true
end

function Farm.CropUnlockText(data, crop)
    local u = crop.unlock or {}
    if u.stage then return "通关第 " .. u.stage .. " 关解锁" end
    if u.repLevel then return "农场声望 Lv." .. u.repLevel .. " 解锁" end
    if u.repSpent then return "声望商店累计消耗 " .. u.repSpent .. " 解锁" end
    return "已解锁"
end

--- 该品级「怎么才能解锁」的短文案（商店按钮被禁用时显示，避免玩家以为买不了是 bug）
---@return string|nil
function Farm.TierUnlockText(data, seedType)
    if Farm.HasTier(data, seedType) then return nil end
    local parts, seen = {}, {}
    for _, c in ipairs(Farm.Crops) do
        if c.seedType == seedType then
            local t = Farm.CropUnlockText(data, c)
            if not seen[t] then
                seen[t] = true
                parts[#parts + 1] = t
            end
        end
    end
    if #parts == 0 then return "该品级还没有解锁作物" end
    return table.concat(parts, " 或 ")
end

function Farm.UnlockedCrops(data)
    local list = {}
    for _, c in ipairs(Farm.Crops) do
        if Farm.CropUnlocked(data, c) then list[#list + 1] = c end
    end
    return list
end

--- 指定品级是否有已解锁作物
function Farm.HasTier(data, seedType)
    for _, c in ipairs(Farm.Crops) do
        if c.seedType == seedType and Farm.CropUnlocked(data, c) then
            return true
        end
    end
    return false
end

--- 增加声望（受每日上限约束）
function Farm.AddRep(data, n)
    local f = Farm.Roll(data)
    if not f or n <= 0 then return 0 end
    local room = math.max(0, Farm.REP_DAILY_CAP - (f.repToday or 0))
    local added = math.min(room, math.floor(n))
    if added <= 0 then return 0 end
    f.rep = (f.rep or 0) + added
    f.repToday = (f.repToday or 0) + added
    return added
end

-- ---------------------------------------------------------------- 种子 / 果实
function Farm.SeedCount(data, cropId)
    local f = Farm.Ensure(data)
    return f and f.seeds[cropId] or 0
end

function Farm.AddSeed(data, cropId, n)
    local f = Farm.Ensure(data)
    if not f or not Farm.CropByID(cropId) then return false end
    f.seeds[cropId] = (f.seeds[cropId] or 0) + (n or 1)
    return true
end

function Farm.FruitCount(data, fruitId)
    local f = Farm.Ensure(data)
    return f and f.fruits[fruitId] or 0
end

function Farm.AddFruit(data, fruitId, n)
    local f = Farm.Ensure(data)
    if not f or not Farm.FruitByID(fruitId) then return false end
    f.fruits[fruitId] = (f.fruits[fruitId] or 0) + (n or 1)
    return true
end

--- 随机一颗已解锁的指定品级种子；本品质无可用作物时向下回退
function Farm.RollSeed(data, seedType)
    local order = { "legendary", "epic", "rare", "basic" }
    local start = 1
    for i, t in ipairs(order) do
        if t == seedType then start = i break end
    end
    for i = start, #order do
        local pool = {}
        for _, c in ipairs(Farm.Crops) do
            if c.seedType == order[i] and Farm.CropUnlocked(data, c) then
                pool[#pool + 1] = c.id
            end
        end
        if #pool > 0 then return pool[math.random(1, #pool)] end
    end
    return nil
end

--- 战斗掉落：精英 8% 基础种子，Boss 5% 稀有种子
function Farm.CombatDrop(data, kind, chance)
    if not Farm.Unlocked(data) then return nil end
    local p = chance or (kind == "elite" and 0.08 or (kind == "boss" and 0.05) or 0)
    if p <= 0 or math.random() >= p then return nil end
    local cropId = Farm.RollSeed(data, kind == "boss" and "rare" or "basic")
    if not cropId then return nil end
    Farm.AddSeed(data, cropId, 1)
    return cropId
end

--- 每日任务：完成 3 场战斗奖励基础种子（每天 1 次）
function Farm.OnBattleFinished(data)
    local f = Farm.Roll(data)
    if not f then return nil end
    f.dailyBattles = (f.dailyBattles or 0) + 1
    if not f.battleReward and f.dailyBattles >= 3 then
        f.battleReward = true
        local cropId = Farm.RollSeed(data, "basic")
        if cropId then
            Farm.AddSeed(data, cropId, 1)
            return cropId
        end
    end
    return nil
end

--- 周常任务：无尽模式通关 10 层奖励稀有种子（每周 1 次）
function Farm.OnEndlessLayer(data)
    local f = Farm.Roll(data)
    if not f then return nil end
    f.weeklyLayers = (f.weeklyLayers or 0) + 1
    if not f.layerReward and f.weeklyLayers >= 10 then
        f.layerReward = true
        local cropId = Farm.RollSeed(data, "rare")
        if cropId then
            Farm.AddSeed(data, cropId, 1)
            return cropId
        end
    end
    return nil
end

-- ---------------------------------------------------------------- 土地 / 种植
---@class FarmPlotInfo
---@field status string
---@field crop FarmCrop|nil
---@field stage integer|nil
---@field stageName string|nil
---@field remain number|nil
---@field stageRemain number|nil
---@field total number|nil
---@field waterCd number|nil
---@field waterReady boolean|nil

---@param data table
---@param index integer
---@return FarmPlotInfo
function Farm.PlotInfo(data, index)
    local f = Farm.Ensure(data)
    local plot = f and f.plots[index]
    if not plot then return { status = "locked" } end
    if index > (f.landCount or 4) then return { status = "locked" } end
    if not plot.crop then return { status = "empty" } end
    local crop = Farm.CropByID(plot.crop)
    if not crop then
        plot.crop = nil
        return { status = "empty" }
    end
    local now = Farm.Now(data)
    local elapsed = math.max(0, now - (plot.plantedAt or 0)) + (plot.waterBonus or 0)
    local total = crop.total * 3600
    local s1 = (crop.stages[1] or 0) * 3600
    local s2 = (crop.stages[2] or 0) * 3600
    local c1, c2 = s1, s1 + s2
    local stage = 1
    if elapsed >= c1 then stage = 2 end
    if elapsed >= c2 then stage = 3 end
    local mature = elapsed >= total
    local stageEnd = (stage == 1 and c1) or (stage == 2 and c2) or total
    local cd = Farm.RepLevel(data) >= 1 and Farm.WATER_CD_REP1 or Farm.WATER_CD
    local waterCd = math.max(0, cd - (now - (plot.waterAt or 0)))
    return {
        status = mature and "mature" or "growing",
        crop = crop,
        stage = stage,
        stageName = mature and "可收获" or ({ "发芽期", "生长期", "成熟期" })[stage],
        remain = math.max(0, total - elapsed),
        stageRemain = math.max(0, stageEnd - elapsed),
        total = total,
        waterCd = waterCd,
        waterReady = (not mature) and waterCd <= 0,
    }
end

function Farm.Plant(data, index, cropId)
    local f = Farm.Roll(data)
    if not f then return false, "农场数据不可用" end
    if index < 1 or index > (f.landCount or 4) then return false, "这块土地还没解锁" end
    local plot = f.plots[index]
    if plot.crop then return false, "这块地已经种了作物" end
    local crop = Farm.CropByID(cropId)
    if not crop then return false, "没有这种种子" end
    if not Farm.CropUnlocked(data, crop) then
        return false, Farm.CropUnlockText(data, crop)
    end
    if (f.seeds[cropId] or 0) <= 0 then return false, "没有" .. crop.name .. "种子" end
    f.seeds[cropId] = f.seeds[cropId] - 1
    if f.seeds[cropId] <= 0 then f.seeds[cropId] = nil end
    plot.crop = cropId
    plot.plantedAt = Farm.Now(data)
    plot.waterBonus = 0
    plot.waterAt = 0
    return true, "种下了" .. crop.name
end

function Farm.Water(data, index)
    local f = Farm.Roll(data)
    if not f then return false, "农场数据不可用" end
    local info = Farm.PlotInfo(data, index)
    if info.status ~= "growing" then return false, "只有生长中的作物能浇水" end
    if (f.waterToday or 0) >= Farm.WATER_DAILY then return false, "今日浇水次数已用完" end
    if not info.waterReady then
        return false, string.format("还要 %d 分钟才能再浇", math.ceil(info.waterCd / 60))
    end
    local plot = f.plots[index]
    local reduce = math.min(Farm.WATER_SEC, info.stageRemain or 0)
    if reduce <= 0 then return false, "当前阶段已经结束" end
    plot.waterBonus = (plot.waterBonus or 0) + reduce
    plot.waterAt = Farm.Now(data)
    f.waterToday = (f.waterToday or 0) + 1
    Farm.AddRep(data, 1)
    return true, string.format("浇水成功：当前阶段减少 %d 分钟", math.floor(reduce / 60 + 0.5))
end

--- 声望 Lv.2：一键给所有可浇水的土地浇水（消耗 1 次浇水次数总计）
function Farm.WaterAll(data)
    local f = Farm.Roll(data)
    if not f then return false, "农场数据不可用" end
    if Farm.RepLevel(data) < 2 then return false, "农场声望 Lv.2 解锁一键浇水" end
    if (f.waterToday or 0) >= Farm.WATER_DAILY then return false, "今日浇水次数已用完" end
    local count = 0
    for i = 1, f.landCount or 4 do
        local info = Farm.PlotInfo(data, i)
        if info.status == "growing" and info.waterReady then
            local plot = f.plots[i]
            local reduce = math.min(Farm.WATER_SEC, info.stageRemain or 0)
            if reduce > 0 then
                plot.waterBonus = (plot.waterBonus or 0) + reduce
                plot.waterAt = Farm.Now(data)
                count = count + 1
            end
        end
    end
    if count <= 0 then return false, "现在没有可浇水的作物" end
    f.waterToday = (f.waterToday or 0) + 1
    Farm.AddRep(data, 1)
    return true, string.format("一键浇水：%d 块土地，各减少 15 分钟", count)
end

--- 超级浇水水壶：立即完成当前阶段
function Farm.UseCan(data, index)
    local f = Farm.Roll(data)
    if not f then return false, "农场数据不可用" end
    if (f.cans or 0) <= 0 then return false, "没有超级浇水水壶" end
    local info = Farm.PlotInfo(data, index)
    if info.status ~= "growing" then return false, "只有生长中的作物能使用水壶" end
    if (info.stageRemain or 0) <= 0 then return false, "当前阶段已经结束" end
    local plot = f.plots[index]
    plot.waterBonus = (plot.waterBonus or 0) + info.stageRemain
    f.cans = f.cans - 1
    return true, "水壶使用成功：当前阶段立即完成"
end

function Farm.Harvest(data, index)
    local f = Farm.Roll(data)
    if not f then return false, "农场数据不可用" end
    local info = Farm.PlotInfo(data, index)
    if info.status ~= "mature" then return false, "作物还没成熟" end
    local crop = info.crop
    local yield = crop.yield
    if (f.fruits[crop.id] or 0) + yield > Farm.FRUIT_CAP then
        return false, string.format("仓库已满：%s最多存 %d 个", crop.fruitName, Farm.FRUIT_CAP)
    end
    local plot = f.plots[index]
    plot.crop = nil
    plot.plantedAt = 0
    plot.waterBonus = 0
    plot.waterAt = 0
    f.fruits[crop.id] = (f.fruits[crop.id] or 0) + yield
    f.harvestCount = (f.harvestCount or 0) + 1
    local rep = Farm.AddRep(data, 5)
    return true, string.format("收获 %s ×%d（声望 +%d）", crop.fruitName, yield, rep)
end

function Farm.MatureCount(data)
    local f = Farm.Ensure(data)
    if not f then return 0 end
    local n = 0
    for i = 1, f.landCount or 4 do
        if Farm.PlotInfo(data, i).status == "mature" then n = n + 1 end
    end
    return n
end

function Farm.HasMature(data)
    return Farm.MatureCount(data) > 0
end

-- ---------------------------------------------------------------- 果实携带 / 本关生效
function Farm.EquippedList(data)
    local f = Farm.Ensure(data)
    local list = {}
    for _, id in ipairs(f and f.equipped or {}) do
        if (f.fruits[id] or 0) > 0 then list[#list + 1] = id end
    end
    return list
end

function Farm.IsEquipped(data, fruitId)
    local f = Farm.Ensure(data)
    for _, id in ipairs(f and f.equipped or {}) do
        if id == fruitId then return true end
    end
    return false
end

function Farm.ToggleEquip(data, fruitId)
    local f = Farm.Roll(data)
    if not f then return false, "农场数据不可用" end
    if (f.fruits[fruitId] or 0) <= 0 then return false, "没有这个果实" end
    for i, id in ipairs(f.equipped) do
        if id == fruitId then
            table.remove(f.equipped, i)
            return true, "已取消携带" .. (Farm.FruitByID(fruitId).fruitName)
        end
    end
    if #f.equipped >= Farm.EQUIP_MAX then
        return false, "最多携带 " .. Farm.EQUIP_MAX .. " 种果实"
    end
    f.equipped[#f.equipped + 1] = fruitId
    return true, "已携带" .. (Farm.FruitByID(fruitId).fruitName)
end

--- 开局结算：消耗携带的果实，把效果写进玩家；返回需要随机强化的品级列表
function Farm.ApplyRunBuffs(run, data)
    local f = Farm.Ensure(data)
    if not f or not run or not run.player then return {} end
    local p = run.player
    local randoms = {}
    local used = {}
    for _, id in ipairs(f.equipped or {}) do
        if (f.fruits[id] or 0) > 0 then
            local crop = Farm.FruitByID(id)
            if crop then
                f.fruits[id] = f.fruits[id] - 1
                if f.fruits[id] <= 0 then f.fruits[id] = nil end
                used[#used + 1] = crop.fruitName
                if id == "fire" then
                    p.mods.atkPct = (p.mods.atkPct or 0) + 0.10
                elseif id == "ice" then
                    p.mods.shieldPct = (p.mods.shieldPct or 0) + 0.15
                elseif id == "thunder" then
                    p.mods.cdrPct = (p.mods.cdrPct or 0) + 0.10
                elseif id == "gold" then
                    run.silver = (run.silver or 0) + 50
                elseif id == "life" then
                    p.mods.hpPct = (p.mods.hpPct or 0) + 0.20
                elseif id == "mushroom" then
                    randoms[#randoms + 1] = "white"
                elseif id == "timevine" then
                    run.guildRerolls = (run.guildRerolls or 0) + 3
                elseif id == "chaos" then
                    randoms[#randoms + 1] = math.random() < 0.5 and "blue" or "purple"
                elseif id == "phoenix" then
                    -- 必须走 mods：Run.Recompute 会用 mods 重算 p.revive，
                    -- 直接写 p.revive 会被随后的重算覆盖掉（之前凤凰花点了没用就是这个原因）
                    p.mods.revive = (p.mods.revive or 0) + 1
                    p.revivePct = 0.5
                    p.reviveUsed = false
                end
            end
        end
    end
    f.equipped = {}
    run.farmFruitNames = used
    return randoms
end

-- ---------------------------------------------------------------- 商店
function Farm.BuyGoldSeed(data, kind)
    local f = Farm.Roll(data)
    if not f then return false, "农场数据不可用" end
    local item
    for _, it in ipairs(Farm.GoldShop) do
        if it.id == kind then item = it break end
    end
    if not item then return false, "没有这件商品" end
    if not Farm.HasTier(data, kind) then
        return false, "该品级还没有解锁作物"
    end
    local bought = kind == "basic" and (f.shopBasic or 0) or (f.shopRare or 0)
    if bought >= item.daily then return false, "今日购买次数已用完" end
    if (data.gold or 0) < item.price then return false, "生息不足" end
    local cropId = Farm.RollSeed(data, kind)
    if not cropId then return false, "暂时没有可获得的种子（先推进关卡解锁作物）" end
    data.gold = data.gold - item.price
    Farm.AddSeed(data, cropId, 1)
    if kind == "basic" then f.shopBasic = bought + 1 else f.shopRare = bought + 1 end
    return true, "购买成功：" .. Farm.CropByID(cropId).name .. "种子 ×1"
end

local function repBoughtCount(f, id)
    if id == "basic" then return f.repDailyBasic or 0 end
    if id == "rare" then return f.repDailyRare or 0 end
    if id == "epic" then return f.repWeeklyEpic or 0 end
    if id == "legendary" then return f.repWeeklyLegendary or 0 end
    if id == "can" then return f.repWeeklyCan or 0 end
    if id == "land" then return f.landTicketsBought or 0 end
    return 0
end

local function addRepBought(f, id)
    if id == "basic" then f.repDailyBasic = (f.repDailyBasic or 0) + 1
    elseif id == "rare" then f.repDailyRare = (f.repDailyRare or 0) + 1
    elseif id == "epic" then f.repWeeklyEpic = (f.repWeeklyEpic or 0) + 1
    elseif id == "legendary" then f.repWeeklyLegendary = (f.repWeeklyLegendary or 0) + 1
    elseif id == "can" then f.repWeeklyCan = (f.repWeeklyCan or 0) + 1
    elseif id == "land" then f.landTicketsBought = (f.landTicketsBought or 0) + 1 end
end

function Farm.RepShopCost(data, id)
    if id == "land" then
        local f = Farm.Ensure(data)
        return 200 + 200 * (f.landTicketsBought or 0)
    end
    for _, it in ipairs(Farm.RepShop) do
        if it.id == id then return it.cost end
    end
    return 0
end

function Farm.BuyRep(data, id)
    local f = Farm.Roll(data)
    if not f then return false, "农场数据不可用" end
    local item
    for _, it in ipairs(Farm.RepShop) do
        if it.id == id then item = it break end
    end
    if not item then return false, "没有这件商品" end
    if id == "land" and (f.landCount or 4) >= 9 then return false, "土地已经全部解锁" end
    if item.seedType and not Farm.HasTier(data, item.seedType) then
        return false, "该品级还没有解锁作物"
    end
    local bought = repBoughtCount(f, id)
    if bought >= item.limit then
        return false, "购买次数已用完（" .. (item.period == "day" and "每日" or (item.period == "week" and "每周" or "全部")) .. "限购）"
    end
    local cost = Farm.RepShopCost(data, id)
    if (f.rep or 0) < cost then return false, "声望不足（需要 " .. cost .. "）" end
    local boughtCrop = nil
    if item.seedType then
        local cropId = Farm.RollSeed(data, item.seedType)
        if not cropId then return false, "暂时没有可获得的种子（先推进关卡解锁作物）" end
        Farm.AddSeed(data, cropId, 1)
        boughtCrop = Farm.CropByID(cropId)
    elseif id == "can" then
        f.cans = (f.cans or 0) + 1
    elseif id == "land" then
        f.landCount = math.min(9, (f.landCount or 4) + 1)
    end
    f.rep = f.rep - cost
    f.repSpent = (f.repSpent or 0) + cost
    addRepBought(f, id)
    local msg
    if boughtCrop then msg = "兑换成功：" .. boughtCrop.name .. "种子 ×1"
    elseif id == "can" then msg = "兑换成功：超级浇水水壶 ×1"
    elseif id == "land" then msg = "兑换成功：土地增加到 " .. f.landCount .. " 块"
    else msg = "兑换成功" end
    return true, msg
end

-- ---------------------------------------------------------------- 开发用
function Farm.DebugRipenAll(data)
    local f = Farm.Ensure(data)
    if not f then return end
    local now = Farm.Now(data)
    for i = 1, f.landCount or 4 do
        local plot = f.plots[i]
        if plot.crop then
            local crop = Farm.CropByID(plot.crop)
            if crop then
                plot.plantedAt = now - crop.total * 3600 - 1
                plot.waterBonus = 0
            end
        end
    end
end

--- 开发用：把指定地块推进到下一个阶段（不选则推进所有生长中的地）
---@param data table
---@param index integer|nil
---@return integer 推进了几块地
function Farm.DebugNextStage(data, index)
    local f = Farm.Ensure(data)
    if not f then return 0 end
    local list = {}
    if index then
        list[1] = index
    else
        for i = 1, f.landCount or 4 do list[#list + 1] = i end
    end
    local moved = 0
    local now = Farm.Now(data)
    for _, i in ipairs(list) do
        local info = Farm.PlotInfo(data, i)
        if info.status == "growing" then
            local plot = f.plots[i]
            local elapsed = info.total - info.remain
            -- 已经到最后一段（成熟期）时，再推一次就是直接可收获
            local target = (info.stage or 1) >= 3 and (info.total + 1)
                or (elapsed + info.stageRemain + 1)
            plot.plantedAt = now - target
            plot.waterBonus = 0
            plot.waterAt = 0
            moved = moved + 1
        end
    end
    return moved
end

function Farm.DebugAddRep(data, n)
    local f = Farm.Ensure(data)
    if not f then return end
    f.rep = (f.rep or 0) + (n or 0)
end

return Farm
