-- Guild.lua — 公会系统：贡献币经济 / 周限购 / 科技树 / 局内特权 / 团本 / 互助
-- 纯逻辑模块：不 require 任何其它脚本，避免与 Save / Run 形成循环依赖。
-- 所有状态都落在存档的 data.guild 上，UI 由 GuildUI.lua 负责。

local Guild = {}

-- ---------------------------------------------------------------- 常量
Guild.COIN_CAP = 3500          -- 每周贡献币软上限

Guild.EARN = {
    sign      = { coins = 20,  limit = 1,  label = "每日签到/捐赠" },
    rescue    = { coins = 80,  limit = 3,  label = "灵魂摆渡（救援）" },
    bounty    = { coins = 50,  limit = 2,  label = "悬赏拓印（寄 Buff）" },
    like      = { coins = 5,   limit = 5,  label = "战报点赞" },
}

-- 团本评级：按对 Boss 的输出量（占 Boss 血量百分比）评级，击杀 = 100% 以上
Guild.RAID_GRADES = {
    { grade = "S", min = 100, coins = 1000 },
    { grade = "A", min = 75,  coins = 875 },
    { grade = "B", min = 50,  coins = 750 },
    { grade = "C", min = 30,  coins = 625 },
    { grade = "D", min = 0,   coins = 500 },
}

-- 团本 Boss：沿用关底模型（瘟衰巨像）
Guild.RAID_BOSS_ID = "colossus"

-- 团本难度档位：由公会等级解锁，atkMul 直接乘在 Boss 伤害上
Guild.RAID_TIERS = {
    { tier = 1, name = "普通", atkMul = 1.00, coinMul = 1.00 },
    { tier = 2, name = "困难", atkMul = 1.35, coinMul = 1.15 },
    { tier = 3, name = "噩梦", atkMul = 1.80, coinMul = 1.30 },
    { tier = 4, name = "炼狱", atkMul = 2.40, coinMul = 1.50 },
    { tier = 5, name = "灭世", atkMul = 3.20, coinMul = 1.75 },
}

-- 公会等级：1~5 级；全员累计公会经验达标后，手动点按钮升级
Guild.MAX_LEVEL = 5
Guild.LEVEL_EXP = { [2] = 2000, [3] = 8000, [4] = 20000, [5] = 40000 }   -- 升到该级所需的「公会总经验」

-- 每周限购·硬通货（minLevel = 公会等级解锁，rarity = 稀有度）
Guild.WeeklyItems = {
    {
        id = "stone", name = "技能突破石（小）", price = 250, limit = 3, minLevel = 1, rarity = "普通",
        desc = "特殊货币，直接 +1 技能点（天赋技能升级用）",
    },
    {
        id = "key", name = "钥匙房钥匙", price = 200, limit = 2, minLevel = 1, rarity = "普通",
        desc = "局内宝箱钥匙：跑图时在地图上开一次额外三选一奖励房",
    },
    {
        id = "crystal", name = "角色经验结晶（大）", price = 150, limit = 5, minLevel = 2, rarity = "稀有",
        desc = "特殊货币，+300 可分配经验（加速局外角色等级）",
    },
    {
        id = "reset", name = "经验重置券", price = 300, limit = 1, minLevel = 3, rarity = "史诗",
        desc = "当前职业等级回到 Lv.1，已投入的升级经验全额退回经验池",
    },
    {
        id = "relic", name = "星辉结晶（巨）", price = 500, limit = 1, minLevel = 4, rarity = "传说",
        desc = "+1500 可分配经验，并额外 +1 技能点",
    },
    {
        id = "sigil", name = "公会秘银钥匙", price = 450, limit = 1, minLevel = 5, rarity = "传说",
        desc = "+1 钥匙房钥匙，并赠送 1 张 Buff 重随券",
    },
}

-- 局内战斗特权（按局付费，买完在下一次开局时消耗）
Guild.Perks = {
    { id = "reroll",   name = "Buff 重随券", price = 80,  minLevel = 1, rarity = "普通",
      desc = "本局奖励房可免费重随 1 次（可叠加）" },
    { id = "silver",   name = "初始资金加注", price = 60, minLevel = 1, rarity = "普通",
      desc = "本局开局额外携带 +50 银币（可叠加）" },
    { id = "insurance", name = "濒死护盾保险", price = 150, minLevel = 2, rarity = "稀有",
      desc = "本局第一次致命伤保留 1 血（每日限购 3 次）" },
    { id = "warn",     name = "精英怪预警", price = 40,  minLevel = 3, rarity = "史诗",
      desc = "本局地图上提前标出精英 / Boss 房间" },
}

-- 科技树：3 条支线 × 10 级，单级 300 起、每级 +100，单线满级 7500
Guild.Tech = {
    {
        id = "survival", name = "生存线（护盾）", color = "cyan",
        effectText = "全角色局内初始护盾 +1.5%/级，脱战回复延迟 -0.1 秒/级",
        maxText = "满级：初始护盾 +15%，脱战回复延迟 -1 秒",
    },
    {
        id = "economy", name = "经济线（掉落）", color = "gold",
        effectText = "局内银币掉落 +2%/级，局外通用币收益 +1%/级",
        maxText = "满级：银币掉落 +20%，通用币收益 +10%",
    },
    {
        id = "offense", name = "输出线（冷却）", color = "orange",
        effectText = "技能冷却 -1%/级，暴击伤害 +1%/级",
        maxText = "满级：技能冷却 -10%，暴击伤害 +10%",
    },
}
Guild.TECH_MAX = 10

-- 纪念物与外观（美术待接入，二期开放）
Guild.Cosmetics = {
    { id = "medal_bronze", name = "公会勋章·铜", price = 1000, desc = "加载界面展示青铜徽章" },
    { id = "medal_silver", name = "公会勋章·银", price = 3000, desc = "加载界面展示白银徽章" },
    { id = "medal_gold",   name = "公会勋章·金", price = 6000, desc = "加载界面展示黄金徽章" },
    { id = "trail",        name = "专属子弹拖尾", price = 4000, desc = "改变平A / 技能弹道颜色轨迹" },
    { id = "pet",          name = "公会守护兽", price = 8000, desc = "局内跟随萌宠，带公会旗帜" },
    { id = "statue",       name = "纪念雕像", price = 5000, desc = "公会大厅立起个人金像，刻 ID 与最高纪录" },
}
Guild.COSMETIC_UNLOCKED = false   -- 二期：素材就绪后改 true

-- 公会成员（离线模拟的社交对象）
Guild.Members = {
    { name = "夜行灯",   class = "swordsman", title = "副会长" },
    { name = "拾荒者K",  class = "spearman",  title = "精英" },
    { name = "白露未晞", class = "ranger",    title = "精英" },
    { name = "炉心",     class = "mage",      title = "精英" },
    { name = "半盏茶",   class = "swordsman", title = "成员" },
    { name = "雾隐",     class = "ranger",    title = "成员" },
    { name = "阿岚",     class = "mage",      title = "成员" },
    { name = "老陈",     class = "spearman",  title = "成员" },
    { name = "小满",     class = "ranger",    title = "成员" },
    { name = "橘猫不睡", class = "swordsman", title = "成员" },
}

local FEED_TEXTS = {
    "刚用 %%s 打穿了第 %d 关，血条只剩一丝，手还在抖。",
    "今天步数达标，领了 %d 金币，公会仓库又满了一点。",
    "求购 %%s，谁有多的私我，贡献币好商量。",
    "团本这周打得稀碎，只拿了个 %%s，下周再战。",
    "第一次把 %%s 叠到 5 层，伤害直接翻倍，爽。",
    "新人报到，求带第 %d 关，我可以打工换 Buff。",
    "灵魂摆渡救了三个兄弟，这周的贡献币算是稳了。",
    "第六关那个精英怪贴脸太狠，建议先买濒死保险。",
}

local BUFF_POOL = { "剑意", "枪势", "元素亲和", "猎痕", "失衡", "暴击强化", "荆棘护甲", "吸血" }
local GRADE_POOL = { "S", "A", "B", "C" }

-- ---------------------------------------------------------------- 工具
local function dayIndex(data)
    return math.floor(os.time() / 86400) + ((data and data.dayOffset) or 0)
end

function Guild.Day(data)
    local offset = (data and data.dayOffset) or 0
    return os.date("%Y-%m-%d", os.time() + offset * 86400)
end

function Guild.Week(data)
    local offset = (data and data.dayOffset) or 0
    local t = os.time() + offset * 86400
    -- 以周一为周界线（每周一更新周上限与商店）
    local wd = tonumber(os.date("%w", t)) or 0     -- 0=周日
    local back = (wd + 6) % 7                      -- 距离最近一个周一的天数
    local weekStart = t - back * 86400
    return os.date("%Y-%m-%d", weekStart)
end

-- 稳定的伪随机：同一 seed 每天结果一致，离线也能"刷新"但不闪
local function hash(seed, salt)
    local h = (seed or 0) * 1103515245 + (salt or 0) * 12345 + 20260101
    h = h % 2147483647
    if h < 0 then h = -h end
    return h
end

local function pick(tbl, seed, salt)
    if #tbl == 0 then return nil end
    return tbl[(hash(seed, salt) % #tbl) + 1]
end

-- ---------------------------------------------------------------- 初始化 / 重置
local function defaultGuild()
    return {
        coins = 0,
        thanks = 0,
        exp = 0,               -- 个人累计公会经验（每获得 1 贡献币 +1）
        level = 1,             -- 公会等级 1~5（达标后手动升级）
        raidTier = 1,          -- 当前选择的团本难度档位
        total = 0,             -- 累计贡献
        week = "",
        weekEarned = 0,
        day = "",
        sign = false,
        rescue = 0,
        bounty = 0,
        likes = 0,
        liked = {},
        tech = { survival = 0, economy = 0, offense = 0 },
        shop = { week = "", bought = {} },
        perks = { reroll = 0, silver = 0, insurance = 0, warn = 0, insuranceDay = "" },
        keys = 0,
        cosmetic = {},
        raid = { week = "", done = false, grade = "", percent = 0, coins = 0 },
    }
end

function Guild.Ensure(data)
    local g = data.guild
    if type(g) ~= "table" then
        data.guild = defaultGuild()
        return data.guild
    end
    local def = defaultGuild()
    for k, v in pairs(def) do
        if g[k] == nil then
            g[k] = v
        elseif type(v) == "table" and type(g[k]) ~= "table" then
            g[k] = v
        end
    end
    for k, v in pairs(def.tech) do
        if type(g.tech[k]) ~= "number" then g.tech[k] = v end
    end
    for k, v in pairs(def.perks) do
        if type(g.perks[k]) ~= "number" and type(v) == "number" then g.perks[k] = v end
    end
    if type(g.shop.bought) ~= "table" then g.shop.bought = {} end
    if type(g.cosmetic) ~= "table" then g.cosmetic = {} end
    if type(g.liked) ~= "table" then g.liked = {} end
    if type(g.raid) ~= "table" then g.raid = def.raid end
    return g
end

--- 跨天 / 跨周重置。任何时候调用都安全。
function Guild.Roll(data)
    local g = Guild.Ensure(data)
    local day, week = Guild.Day(data), Guild.Week(data)
    if g.day ~= day then
        g.day = day
        g.sign = false
        g.rescue = 0
        g.bounty = 0
        g.likes = 0
        g.liked = {}
        if g.perks.insuranceDay ~= day then
            g.perks.insuranceDay = day
            g.perks.insuranceBought = 0
        end
    end
    if g.week ~= week then
        g.week = week
        g.weekEarned = 0
        g.shop.week = week
        g.shop.bought = {}
        g.raid = { week = week, done = false, grade = "", percent = 0, coins = 0 }
    end
    return g
end

-- ---------------------------------------------------------------- 贡献币产出
--- 记入贡献币，受周上限约束。溢出部分按 100:1 折算感谢信。
function Guild.AddCoins(data, amount)
    local g = Guild.Roll(data)
    if amount <= 0 then return 0 end
    local room = math.max(0, Guild.COIN_CAP - g.weekEarned)
    local added = math.min(room, amount)
    local overflow = amount - added
    g.coins = g.coins + added
    g.weekEarned = g.weekEarned + added
    g.total = g.total + added
    -- 个人获得 1 贡献币 = 个人公会经验 +1（全员合计由 Guild.TotalExp 折算）
    g.exp = (g.exp or 0) + added
    if overflow > 0 then
        g.thanks = g.thanks + math.floor(overflow / 100)
    end
    return added, overflow
end

local function earnOnce(data, kind, limitKey)
    local g = Guild.Roll(data)
    local cfg = Guild.EARN[kind]
    if (g[limitKey] or 0) >= cfg.limit then return 0 end
    g[limitKey] = (g[limitKey] or 0) + 1
    return Guild.AddCoins(data, cfg.coins)
end

function Guild.Sign(data)
    local g = Guild.Roll(data)
    if g.sign then return false, "今天已经签到过了" end
    g.sign = true
    local added = Guild.AddCoins(data, Guild.EARN.sign.coins)
    return true, "签到成功：+" .. added .. " 贡献币（捐赠材料已自动放入公会仓库）"
end

-- 每日可救援名单（离线模拟：每天 4 位成员里 3 位"倒下"）
function Guild.RescueList(data)
    local seed, list = dayIndex(data), {}
    for i, m in ipairs(Guild.Members) do
        if (hash(seed, i) % 4) ~= 0 then
            list[#list + 1] = { idx = i, name = m.name, class = m.class, title = m.title }
        end
    end
    return list
end

function Guild.Rescue(data, idx)
    local g = Guild.Roll(data)
    if g.rescue >= Guild.EARN.rescue.limit then
        return false, "今天救援次数已用完（3/3）"
    end
    local member = Guild.Members[idx]
    if not member then return false, "找不到该成员" end
    local usedKey = "rescue_" .. idx
    if g.liked[usedKey] then return false, "今天已经救过这位成员了" end
    g.liked[usedKey] = true
    local added, overflow = Guild.AddCoins(data, Guild.EARN.rescue.coins)
    local msg = "摆渡成功：" .. member.name .. " 重新站了起来，+" .. added .. " 贡献币"
    if overflow > 0 then msg = msg .. "（本周已达上限，" .. overflow .. " 溢出折算感谢信）" end
    return true, msg
end

-- 每日悬赏：2 位求购者，寄出对应稀有 Buff
function Guild.BountyList(data)
    local seed, list = dayIndex(data), {}
    for i = 1, 2 do
        list[#list + 1] = {
            idx = i,
            name = Guild.Members[(hash(seed, 20 + i) % #Guild.Members) + 1].name,
            buff = pick(BUFF_POOL, seed, 40 + i),
            rarity = pick({ "紫", "金" }, seed, 60 + i),
        }
    end
    return list
end

function Guild.SendBounty(data, idx)
    local g = Guild.Roll(data)
    if g.bounty >= Guild.EARN.bounty.limit then
        return false, "今天拓印次数已用完（2/2）"
    end
    local key = "bounty_" .. idx
    if g.liked[key] then return false, "这条悬赏已经交付过了" end
    g.liked[key] = true
    g.bounty = g.bounty + 1
    local added, overflow = Guild.AddCoins(data, Guild.EARN.bounty.coins)
    local msg = "拓印已寄出，+" .. added .. " 贡献币"
    if overflow > 0 then msg = msg .. "（达到周上限，溢出折算感谢信）" end
    return true, msg
end

-- 战报（公会频道）：每天 4~5 条
function Guild.Feed(data)
    local seed, list = dayIndex(data), {}
    local n = 4 + (hash(seed, 7) % 2)
    for i = 1, n do
        local m = Guild.Members[(hash(seed, 100 + i) % #Guild.Members) + 1]
        local tpl = FEED_TEXTS[(hash(seed, 200 + i) % #FEED_TEXTS) + 1]
        local text = tpl
        local ok, formatted = pcall(string.format, tpl, pick(BUFF_POOL, seed, 300 + i),
            (hash(seed, 400 + i) % 18) + 2, pick(GRADE_POOL, seed, 500 + i))
        if ok then text = formatted end
        list[#list + 1] = {
            idx = i, author = m.name, title = m.title,
            text = text, liked = (Guild.Roll(data).liked["feed_" .. i] == true),
        }
    end
    return list
end

function Guild.Like(data, idx)
    local g = Guild.Roll(data)
    if g.likes >= Guild.EARN.like.limit then
        return false, "今天点赞次数已用完（5/5）"
    end
    local key = "feed_" .. idx
    if g.liked[key] then return false, "这条战报已经点过赞了" end
    g.liked[key] = true
    g.likes = g.likes + 1
    local added = Guild.AddCoins(data, Guild.EARN.like.coins)
    return true, "已点赞，+" .. added .. " 贡献币"
end

-- ---------------------------------------------------------------- 每周限购商店
function Guild.WeeklyBought(data, id)
    local g = Guild.Roll(data)
    return g.shop.bought[id] or 0
end

function Guild.BuyWeekly(data, id)
    local g = Guild.Roll(data)
    local item
    for _, it in ipairs(Guild.WeeklyItems) do
        if it.id == id then item = it break end
    end
    if not item then return false, "没有这件商品" end
    local lv = Guild.Level(data)
    if lv < (item.minLevel or 1) then
        return false, "公会等级不足：需要 Lv." .. (item.minLevel or 1) .. "（当前 Lv." .. lv .. "）"
    end
    local bought = g.shop.bought[id] or 0
    if bought >= item.limit then return false, "本周已买满 " .. item.limit .. " 个" end
    if g.coins < item.price then return false, "贡献币不足（需要 " .. item.price .. "）" end

    g.coins = g.coins - item.price
    g.shop.bought[id] = bought + 1

    if id == "stone" then
        data.skillPoints = (data.skillPoints or 0) + 1
        return true, "兑换成功：技能点 +1（当前 " .. data.skillPoints .. "）"
    elseif id == "key" then
        g.keys = (g.keys or 0) + 1
        return true, "兑换成功：钥匙 +1（当前 " .. g.keys .. " 把）"
    elseif id == "crystal" then
        data.exp = (data.exp or 0) + 300
        return true, "兑换成功：可分配经验 +300（当前 " .. data.exp .. "）"
    elseif id == "relic" then
        data.exp = (data.exp or 0) + 1500
        data.skillPoints = (data.skillPoints or 0) + 1
        return true, "兑换成功：可分配经验 +1500，技能点 +1"
    elseif id == "sigil" then
        g.keys = (g.keys or 0) + 1
        g.perks.reroll = (g.perks.reroll or 0) + 1
        return true, "兑换成功：钥匙 +1，Buff 重随券 +1"
    elseif id == "reset" then
        local Save = require "Save"
        local Config = require "Config"
        local class = Save.ActiveClass(data)
        local lv = Save.ClassLevel(data)
        if lv <= 1 then
            g.shop.bought[id] = bought          -- 退回购买记录
            g.coins = g.coins + item.price
            return false, "当前职业已经是 Lv.1，没有可重置的等级"
        end
        local refund = 0
        for i = 1, lv - 1 do
            refund = refund + (Config.LevelCost[i] or 0)
        end
        data.levels[class] = 1
        data.exp = (data.exp or 0) + refund
        Save.Write(data)
        return true, "已重置 " .. Config.Classes[class].name .. " 到 Lv.1，退回 " .. refund .. " 经验"
    end
    return true, "兑换成功"
end

--- 金币兑换通道：满级后的兜底出口，10 贡献币 = 1 金币
function Guild.ConvertToGold(data)
    local g = Guild.Roll(data)
    if g.coins < 10 then return false, "至少需要 10 贡献币" end
    local units = math.floor(g.coins / 10)
    g.coins = g.coins - units * 10
    data.gold = (data.gold or 0) + units
    return true, "兑换完成：+" .. units .. " 金币"
end

-- ---------------------------------------------------------------- 局内特权
function Guild.BuyPerk(data, id)
    local g = Guild.Roll(data)
    local perk
    for _, p in ipairs(Guild.Perks) do
        if p.id == id then perk = p break end
    end
    if not perk then return false, "没有这个特权" end
    local lv = Guild.Level(data)
    if lv < (perk.minLevel or 1) then
        return false, "公会等级不足：需要 Lv." .. (perk.minLevel or 1) .. "（当前 Lv." .. lv .. "）"
    end
    if id == "insurance" then
        local day = Guild.Day(data)
        if g.perks.insuranceDay ~= day then
            g.perks.insuranceDay = day
            g.perks.insuranceBought = 0
        end
        if (g.perks.insuranceBought or 0) >= 3 then
            return false, "濒死保险每日限购 3 次"
        end
    end
    if g.coins < perk.price then
        return false, "贡献币不足（需要 " .. perk.price .. "）"
    end
    g.coins = g.coins - perk.price
    if id == "insurance" then
        g.perks.insuranceBought = (g.perks.insuranceBought or 0) + 1
        g.perks.insurance = g.perks.insurance + 1
    else
        g.perks[id] = (g.perks[id] or 0) + 1
    end
    return true, "已购买：" .. perk.name
end

-- ---------------------------------------------------------------- 科技树
function Guild.TechCost(branch, level)
    -- level 是「即将升到的那一级」：1..10 → 300,400,...,1200
    return 300 + (math.max(1, math.min(Guild.TECH_MAX, level)) - 1) * 100
end

function Guild.TechSpent(branch, level)
    local sum = 0
    for i = 1, (level or 0) do sum = sum + Guild.TechCost(branch, i) end
    return sum
end

--- 科技等级上限：公会 1 级 2 级科技，每升 1 级公会 +2 级上限（5 级公会 → 10 级）
function Guild.TechCap(data)
    return math.min(Guild.TECH_MAX, Guild.Level(data) * 2)
end

function Guild.UpgradeTech(data, branch)
    local g = Guild.Roll(data)
    local lv = g.tech[branch] or 0
    local cap = Guild.TechCap(data)
    if lv >= cap then
        if cap >= Guild.TECH_MAX then
            return false, "该支线已满级"
        end
        return false, "公会等级不足：Lv." .. Guild.Level(data) .. " 的科技上限是 " .. cap .. " 级"
    end
    local cost = Guild.TechCost(branch, lv + 1)
    if g.coins < cost then return false, "贡献币不足（需要 " .. cost .. "）" end
    g.coins = g.coins - cost
    g.tech[branch] = lv + 1
    return true, "科技升级：Lv." .. (lv + 1) .. "（-" .. cost .. " 贡献币）"
end

-- ---------------------------------------------------------------- 局外 / 局内加成
function Guild.Bonus(data)
    local g = data and data.guild or nil
    local tech = (g and g.tech) or {}
    local sv, eco, off = tech.survival or 0, tech.economy or 0, tech.offense or 0
    return {
        shieldPct   = 0.015 * sv,   -- 初始护盾
        regenDelay  = 0.1 * sv,     -- 脱战回复延迟（秒）
        silverMul   = 1 + 0.02 * eco,
        goldMul     = 1 + 0.01 * eco,
        cdrPct      = 0.01 * off,
        critDmg     = 0.01 * off,
    }
end

function Guild.SilverMul(data)
    return Guild.Bonus(data).silverMul
end

function Guild.GoldMul(data)
    return Guild.Bonus(data).goldMul
end

--- 把公会科技与已购特权写进玩家状态（在 Run.NewPlayer 之后、Recompute 之前调用）
function Guild.ApplyRunMods(p, data)
    local b = Guild.Bonus(data)
    p.mods = p.mods or {}
    p.mods.shieldPct = (p.mods.shieldPct or 0) + b.shieldPct
    p.mods.cdrPct = (p.mods.cdrPct or 0) + b.cdrPct
    p.mods.critDmg = (p.mods.critDmg or 0) + b.critDmg
    p.guildRegenDelay = b.regenDelay
end

--- 开局结算：消耗已购特权、发放钥匙 / 重随次数 / 保险 / 预警
function Guild.StartRun(run, data)
    local g = Guild.Roll(data)
    local perks = g.perks
    run.guildRerolls = perks.reroll or 0
    run.guildInsurance = (perks.insurance or 0) > 0
    run.guildEliteWarn = (perks.warn or 0) > 0
    run.guildKeys = g.keys or 0
    local silverBoost = (perks.silver or 0) * 50
    run.silver = (run.silver or 0) + silverBoost
    if run.player then
        run.player.guildInsurance = run.guildInsurance
        run.player.guildInsuranceUsed = false
    end
    perks.reroll, perks.silver, perks.warn = 0, 0, 0
    if run.guildInsurance then perks.insurance = math.max(0, (perks.insurance or 0) - 1) end
    return run
end

function Guild.UseKey(run, data)
    local g = Guild.Roll(data)
    if (g.keys or 0) <= 0 then return false, "没有钥匙" end
    g.keys = g.keys - 1
    run.guildKeys = g.keys
    return true, "消耗 1 把钥匙，开启额外奖励房"
end

-- ---------------------------------------------------------------- 团本
--- 已解锁的最高难度档位 = 公会等级（1~5）
function Guild.RaidTierMax(data)
    return math.max(1, math.min(#Guild.RAID_TIERS, Guild.Level(data)))
end

function Guild.RaidTierInfo(tier)
    tier = math.max(1, math.min(#Guild.RAID_TIERS, math.floor(tier or 1)))
    return Guild.RAID_TIERS[tier]
end

--- 当前选择的档位（超出解锁范围时自动夹到上限）
function Guild.RaidTier(data)
    local g = Guild.Ensure(data)
    return math.max(1, math.min(Guild.RaidTierMax(data), g.raidTier or 1))
end

function Guild.SetRaidTier(data, tier)
    local g = Guild.Ensure(data)
    local maxTier = Guild.RaidTierMax(data)
    tier = math.max(1, math.min(maxTier, math.floor(tier or 1)))
    g.raidTier = tier
    local info = Guild.RaidTierInfo(tier)
    return true, "团本难度：" .. info.name .. "（Boss 伤害 x" .. info.atkMul .. "）"
end

--- Boss 伤害倍率（Combat 刷 Boss 时使用）
function Guild.RaidAtkMul(tier)
    return Guild.RaidTierInfo(tier).atkMul
end

--- 测试用：一键清空周限购 + 团本次数
function Guild.ResetWeeklyForTest(data)
    local g = Guild.Roll(data)
    g.shop.bought = {}
    g.shop.week = g.week
    g.raid = { week = g.week, done = false, grade = "", percent = 0, coins = 0 }
    return true, "已重置：周限购次数、团本次数与评级"
end

function Guild.RaidReady(data, force)
    local g = Guild.Roll(data)
    if force then return true end
    return not g.raid.done
end

function Guild.RaidGrade(percent)
    for _, row in ipairs(Guild.RAID_GRADES) do
        if percent >= row.min then return row.grade, row.coins end
    end
    return "D", 500
end

--- 团本结算：percent = 对 Boss 造成的伤害百分比（击杀即 100）
--- force = 测试模式：忽略「本周已结算」限制，可反复体验
function Guild.CompleteRaid(data, percent, force, damage)
    local g = Guild.Roll(data)
    if g.raid.done and not force then
        return g.raid.grade, 0, "本周团本已结算（" .. tostring(g.raid.grade) .. "）"
    end
    percent = math.max(0, math.min(120, math.floor(percent or 0)))
    local grade, baseCoins = Guild.RaidGrade(percent)
    local tier = Guild.RaidTier(data)
    local coins = math.floor(baseCoins * Guild.RaidTierInfo(tier).coinMul + 0.5)
    g.raid.done = true
    g.raid.grade = grade
    g.raid.percent = percent
    g.raid.tier = tier
    g.raid.damage = math.floor(damage or 0)
    g.raid.coins = coins
    local added = Guild.AddCoins(data, coins)
    g.raid.coins = added
    return grade, added, string.format("团本 %s 难度 · 评级 %s（输出 %d%%），+%d 贡献币",
        Guild.RaidTierInfo(tier).name, grade, percent, added)
end

-- ---------------------------------------------------------------- 公会等级（感谢信）
function Guild.Level(data)
    local g = Guild.Ensure(data)
    return math.max(1, math.min(Guild.MAX_LEVEL, math.floor(g.level or 1)))
end

--- 公会总经验 = 个人公会经验 x 成员数（离线模拟：全员的合计）
function Guild.TotalExp(data)
    local g = Guild.Ensure(data)
    return (g.exp or 0) * #Guild.Members
end

--- 升到下一级所需的公会总经验
function Guild.LevelNeed(data)
    local lv = Guild.Level(data)
    return Guild.LEVEL_EXP[lv + 1]
end

function Guild.LevelProgress(data)
    local lv = Guild.Level(data)
    local need = Guild.LevelNeed(data)
    if not need then return 1, 0 end
    return math.min(1, Guild.TotalExp(data) / need), need
end

function Guild.CanLevelUp(data)
    local need = Guild.LevelNeed(data)
    if not need then return false end
    return Guild.TotalExp(data) >= need
end

--- 手动升级公会等级（经验累计不消耗，达标即可点）
function Guild.LevelUpGuild(data)
    local g = Guild.Ensure(data)
    local lv = Guild.Level(data)
    if lv >= Guild.MAX_LEVEL then return false, "公会已经满级" end
    local need = Guild.LevelNeed(data)
    if Guild.TotalExp(data) < need then
        return false, "公会总经验不足：还差 " .. (need - Guild.TotalExp(data))
    end
    g.level = lv + 1
    local cap = Guild.TechCap(data)
    local tier = Guild.RaidTierMax(data)
    local msg = "公会升到 Lv." .. g.level .. "：科技上限 " .. cap .. " 级，团本解锁 "
        .. Guild.RaidTierInfo(tier).name .. " 难度"
    return true, msg
end

function Guild.SubmitThanks(data)
    local g = Guild.Ensure(data)
    if (g.thanks or 0) <= 0 then return false, "没有感谢信" end
    g.thanks = g.thanks - 1
    g.exp = (g.exp or 0) + 10
    return true, "上交 1 封感谢信，公会经验 +10"
end

function Guild.CapProgress(data)
    local g = Guild.Ensure(data)
    return math.min(1, g.weekEarned / Guild.COIN_CAP), g.weekEarned, Guild.COIN_CAP
end

return Guild
