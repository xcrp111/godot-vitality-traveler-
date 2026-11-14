-- Opportunity.lua — 机遇系统：遗弃村落 / 不期而遇 / 得偿所愿 / 命运岔口
--
-- 纯逻辑模块：不 require 任何其它脚本，所有对外部世界的改动都通过 ctx.hooks 回调注入，
-- 这样 dev/DevActMap.lua 可以用桩函数把整张表跑一遍，不需要启动运行时。
--
-- ---------------------------------------------------------------- 数值依据
-- 全部换算都从 Config.lua 的现有价格表反推，不拍脑袋（详见 dev/ACT_MAP.md）：
--   1 单位 = 一次标准战斗房 ≈ 12 血尘 + 1 次三选一
--   1% 最大生命 ≈ 0.36 血尘        （小药 12 血尘/33%，大药 24 血尘/66%）
--   1 个强化品质档 ≈ 22 血尘        （白 24 / 蓝 40 / 紫 64 / 金 115）
--   局外 1 生息 ≈ 1 经验            （12000 步 = 533 生息 + 533 经验）
--
-- ---------------------------------------------------------------- 地图上只放两个节点
-- 原来四种机遇房（村 / 遇 / 愿 / 机）挤在 4×4 的地图上太占格子，也把「选择」稀释了。
-- 现在地图上只留两种，各自承担一种明确的决策：
--   不期而遇 有选择 有代价 → 决策
--   得偿所愿 有选择 无风险 → 保底
-- 另外两种不再占地图格子，但玩法一点没丢：
--   遗弃村落 → 清完战斗房后 12% 概率「路过」，白拿一份小惊喜（RollVillageDrop）
--   命运岔口 → 得偿所愿的第五个方向「搏」，把赌局收进玩家自己按下的按钮里
--
-- 预算上限（CAP）仍按四种分开记：村落和命运虽然不占地图，但产出量级不一样，
-- dev/DevActMap.lua 会逐条断言，改数值时改这里就够。

local Opportunity = {}

-- ---------------------------------------------------------------- 节点类型
Opportunity.KINDS = {
    encounter = {
        name = "不期而遇", icon = "遇", color = { 255, 209, 102, 255 }, mapNode = true,
        desc = "二选一：一边先付代价，一边稳当收下。",
    },
    wish = {
        name = "得偿所愿", icon = "愿", color = { 76, 201, 240, 255 }, mapNode = true,
        desc = "选方向，不选具体：永远拿得到你想要的类别；也可以赌一把。",
    },
    village = {
        name = "遗弃村落", icon = "村", color = { 126, 231, 135, 255 }, mapNode = false,
        desc = "清完战斗房后路过，白拿一份，不占地图格子。",
    },
    chance = {
        name = "命运岔口", icon = "机", color = { 190, 140, 255, 255 }, mapNode = false,
        desc = "得偿所愿里那个「搏」背后的牌桌。",
    },
}

Opportunity.KIND_ORDER = { "encounter", "wish", "village", "chance" }
-- 会出现在地图上的节点类型（ActMap.CheckLayer 与渲染以此为准）
Opportunity.MAP_KINDS = { "encounter", "wish" }
Opportunity.MAP_KIND_SET = { encounter = true, wish = true }

-- ---------------------------------------------------------------- 预算上限
-- 每条都是「单次结算」的上限，不是总和。
Opportunity.CAP = {
    village = {
        silver = 20, buff = 0, gold = 20, exp = 10,
        healPct = 0.25, shieldPct = 0.30, item = 1, intel = 1,
    },
    encounter = {
        silver = 50, buff = 1, gold = 25, exp = 15,
        healPct = 0.45, shieldPct = 0.30, item = 1, intel = 1,
    },
    wish = {
        silver = 40, buff = 1, gold = 30, exp = 30,
        healPct = 0.50, shieldPct = 0.30, item = 1, intel = 0,
    },
    chance = {
        silver = 60, buff = 1, gold = 30, exp = 20,
        healPct = 0.35, shieldPct = 0.30, item = 1, intel = 0,
    },
}

-- 代价上限：不管哪个节点，单次最多让你吐这么多
Opportunity.CAP_COST = {
    silver = 80,
    hpPct = 0.35,
    item = 1,
    stepRisk = 1,
}

-- 命运岔口的「大凶」地板：生命低于这个比例时，大凶自动降级成小凶
Opportunity.LOSS_HP_FLOOR = 0.25
-- 血尘不够赔时改成扣血，但扣血上限就是这个比例
Opportunity.LOSS_HP_CAP = 0.15
-- 前几关不刷命运岔口（新手期不给赌）
Opportunity.CHANCE_MIN_LEVEL = 6

-- ---------------------------------------------------------------- 机遇池
-- 每条：{ id, kind, weight, minLevel?, cond?, title, text, options = { {label, desc?, cost?, gain?, minLevel?, enabled?} } }
--   cost / gain 的字段：silver 血尘、gold 局外生息、exp 局外经验、healPct 回血、
--   hpPct 按最大生命扣血、shieldPct 按护盾上限加盾、buff 品质（"white"/"blue"/"purple"/"gold"）、
--   item 道具数、intel 揭示地图、reroll 免费重随次数、stepRisk 本层后续强度 +1 档
Opportunity.DEFS = {
    -- ============================================================ 遗弃村落（无代价）
    {
        id = "v_coin", kind = "village", weight = 28, minLevel = 1,
        title = "遗弃的补给箱",
        text = "路边的箱子上还挂着褪色的标签，一直没人来取。",
        options = {
            { label = "打开箱子", gain = { silver = 15 } },
        },
    },
    {
        id = "v_heal", kind = "village", weight = 24, minLevel = 1,
        title = "尚有余温的营火",
        text = "有人刚走，灰烬底下还压着炭火。",
        cond = function(ctx) return ctx.state.hp <= ctx.state.maxHp * 0.70 end,
        options = {
            { label = "坐下来烤一会", gain = { healPct = 0.20 } },
        },
    },
    {
        id = "v_shield", kind = "village", weight = 16, minLevel = 1,
        title = "墙缝里的菌丝",
        text = "菌丝在墙缝里织成一层膜，摸上去像冷的皮革。",
        options = {
            { label = "撕一层裹在身上", gain = { shieldPct = 0.30 } },
        },
    },
    {
        id = "v_exp", kind = "village", weight = 14, minLevel = 1,
        title = "旅行者的笔记",
        text = "十几页潦草的字，最后一行只写了半句。",
        options = {
            { label = "收进背包", gain = { exp = 8 } },
        },
    },
    {
        id = "v_item", kind = "village", weight = 10, minLevel = 1,
        title = "没锁的药柜",
        text = "柜门半开，里面还剩一支没摔碎的针剂。",
        cond = function(ctx) return ctx.hooks.addItem ~= nil end,
        options = {
            { label = "拿走它", gain = { item = 1 } },
        },
    },
    {
        id = "v_intel", kind = "village", weight = 10, minLevel = 1,
        title = "看门人的登记册",
        text = "纸页上记着每个房间什么时候熄灯。",
        options = {
            { label = "抄下来", gain = { intel = 1, silver = 5 } },
        },
    },

    -- ============================================================ 不期而遇（有选择、有代价）
    {
        id = "e_blood", kind = "encounter", weight = 18, minLevel = 1,
        title = "血与利的岔路",
        text = "一株会说话的菌丝缠在断剑上：「给我点热的，我给你点好的。」",
        options = {
            {
                label = "割开手掌", desc = "失去 30% 生命，换一个金色强化",
                cost = { hpPct = 0.30 }, gain = { buff = "gold" },
                enabled = function(ctx) return ctx.state.hp > ctx.state.maxHp * 0.50 end,
            },
            {
                label = "绕开它", desc = "恢复 40% 生命",
                gain = { healPct = 0.40 },
            },
        },
    },
    {
        id = "e_march", kind = "encounter", weight = 16, minLevel = 1,
        title = "绕远的路",
        text = "前面塌了半边，两边各有一条能走的路。",
        options = {
            {
                label = "翻过废墟", desc = "+45 血尘，但本层后面所有房间更硬",
                gain = { silver = 45, stepRisk = 1 },
            },
            {
                label = "沿着排水沟走", desc = "+15 血尘",
                gain = { silver = 15 },
            },
        },
    },
    {
        id = "e_peddler", kind = "encounter", weight = 16, minLevel = 3,
        title = "半张脸的商人",
        text = "他把货摊开在路灯下，价签是用血写的。",
        options = {
            {
                label = "付 60 血尘", desc = "换一个保底紫色的强化",
                cost = { silver = 60 }, gain = { buff = "purple" },
                enabled = function(ctx) return ctx.state.silver >= 60 end,
            },
            {
                label = "只要他递来的碎银", desc = "+12 血尘",
                gain = { silver = 12 },
            },
        },
    },
    {
        id = "e_rumor", kind = "encounter", weight = 14, minLevel = 1,
        title = "墙上的刻痕",
        text = "有人在这里数过房间，一道刻痕一间。刻痕尽头的暗巷里似乎还反着光。",
        options = {
            {
                label = "循着刻痕走进暗巷", desc = "+30 血尘，但失去 15% 生命",
                gain = { silver = 30 }, cost = { hpPct = 0.15 },
                enabled = function(ctx) return ctx.state.hp > ctx.state.maxHp * 0.30 end,
            },
            {
                label = "把刻痕抄下来", desc = "揭示本层所有房间 + 1 次免费重随",
                gain = { intel = 1, reroll = 1 },
            },
        },
    },
    {
        id = "e_potion", kind = "encounter", weight = 14, minLevel = 2,
        title = "摔碎的药箱",
        text = "药水淌了一地，只有底下一层还是好的。",
        options = {
            {
                label = "交出 1 个道具", desc = "换一个蓝色强化",
                cost = { item = 1 }, gain = { buff = "blue" },
                enabled = function(ctx) return ctx.state.items > 0 end,
            },
            {
                label = "把剩下的刮起来", desc = "+18 血尘",
                gain = { silver = 18 },
            },
        },
    },
    {
        id = "e_debt", kind = "encounter", weight = 12, minLevel = 4,
        title = "写着你名字的欠条",
        text = "借据上的笔迹和你一模一样，可你没来过这。",
        options = {
            {
                label = "还债", desc = "付 70 血尘，换一个金色强化",
                cost = { silver = 70 }, gain = { buff = "gold" },
                enabled = function(ctx) return ctx.state.silver >= 70 end,
            },
            {
                label = "撕掉它", desc = "+10 血尘",
                gain = { silver = 10 },
            },
        },
    },

    -- ============================================================ 得偿所愿（选方向）
    -- 只给「方向」不给「具体物品」：所以不会出现「抽到没用的金色」这种挫败
    {
        id = "w_wish", kind = "wish", weight = 100, minLevel = 1,
        title = "得偿所愿",
        text = "井底浮起一枚旧钱币，水面上映出你想要的东西。",
        options = {
            {
                label = "财", desc = "+35 血尘",
                gain = { silver = 35 }, minLevel = 8,
            },
            {
                label = "生", desc = "恢复 45% 生命，并 +5 血尘",
                gain = { healPct = 0.45, silver = 5 },
            },
            {
                label = "力", desc = "一次保底蓝色的三选一",
                gain = { buff = "blue" },
            },
            {
                label = "悟", desc = "+25 精粹",
                gain = { exp = 25 },
            },
            {
                -- 原来独立的「命运岔口」节点压缩成了这一项：想赌的人自己按，不想赌的人看不见它
                label = "搏", desc = "赌一把：掷一次命运牌桌（期望约 20 血尘，最高 +60 还送一次紫保底）",
                rollId = "c_fate", minLevel = Opportunity.CHANCE_MIN_LEVEL,
            },
        },
    },

    -- ============================================================ 命运牌桌（不再是地图节点）
    -- 期望血尘 = -2.5 -2 +2.5 +6.25 +12 = +16.25，再加约 3.8 的紫保底期望 ≈ 20
    -- 比「财」的稳定 35 低是故意的：赌买的是方差和爽点，不是收益。
    {
        id = "c_fate", kind = "chance", weight = 100, minLevel = Opportunity.CHANCE_MIN_LEVEL,
        title = "命运岔口",
        text = "三张牌在风里翻了个面，牌背上的图案全都一样。",
        roll = {
            -- 大凶只写一个血尘代价：血尘不够时 ApplySilverLoss 会自动改成扣血（最多 15%），
            -- 所以不需要再写 lossHpPct，否则会一份惩罚扣两次
            { id = "great_bad", p = 0.10, label = "大凶", cost = { silver = 25 } },
            { id = "bad", p = 0.20, label = "小凶", cost = { silver = 10 } },
            { id = "calm", p = 0.25, label = "平静", gain = { silver = 10 } },
            { id = "good", p = 0.25, label = "小吉", gain = { silver = 25 } },
            { id = "great_good", p = 0.20, label = "大吉", gain = { silver = 60 }, bonusBuffChance = 0.30, bonusBuff = "purple" },
        },
    },
}

-- ---------------------------------------------------------------- 索引
local function BuildIndex()
    local byKind = {}
    for _, kind in ipairs(Opportunity.KIND_ORDER) do byKind[kind] = {} end
    for _, def in ipairs(Opportunity.DEFS) do
        local list = byKind[def.kind]
        assert(list, "未知的机遇类型: " .. tostring(def.kind) .. " (" .. tostring(def.id) .. ")")
        list[#list + 1] = def
    end
    Opportunity.ByKind = byKind
end
BuildIndex()

function Opportunity.DefByID(id)
    for _, def in ipairs(Opportunity.DEFS) do
        if def.id == id then return def end
    end
    return nil
end

-- ---------------------------------------------------------------- 上下文
-- ctx = {
--   level = 7,                  -- 当前关卡（或无尽模式的等效关卡）
--   rand  = function(a, b) end, -- 可注入，默认 math.random
--   state = { silver, hp, maxHp, shield, maxShield, items },
--   hooks = {
--     grantBuff = function(rarity) -> { name, desc } end
--     addGold   = function(n) end
--     addExp    = function(n) end
--     addItem   = function(amount) end
--     useItem   = function(n) -> boolean end
--     reveal    = function() end
--     reroll    = function(n) end
--   }
-- }
function Opportunity.MakeContext(opts)
    opts = opts or {}
    local state = opts.state or {}
    local hooks = opts.hooks or {}
    local gainLog = { silver = 0, gold = 0, exp = 0, buffs = {}, items = 0, intel = 0, reroll = 0, stepRisk = 0 }
    local stubHooks = {
        grantBuff = hooks.grantBuff or function(rarity)
            gainLog.buffs[#gainLog.buffs + 1] = rarity
            return { name = "强化(" .. tostring(rarity) .. ")", desc = "测试桩" }
        end,
        addGold = hooks.addGold or function(n) gainLog.gold = gainLog.gold + n end,
        addExp = hooks.addExp or function(n) gainLog.exp = gainLog.exp + n end,
        addItem = hooks.addItem or function(n) gainLog.items = gainLog.items + (n or 1) end,
        useItem = hooks.useItem or function(n)
            if (state.items or 0) < (n or 1) then return false end
            state.items = (state.items or 0) - (n or 1)
            return true
        end,
        reveal = hooks.reveal or function() gainLog.intel = gainLog.intel + 1 end,
        reroll = hooks.reroll or function(n) gainLog.reroll = gainLog.reroll + (n or 1) end,
    }
    return {
        level = opts.level or 1,
        rand = opts.rand or math.random,
        state = {
            silver = state.silver or 0,
            hp = state.hp or 50,
            maxHp = state.maxHp or 50,
            shield = state.shield or 0,
            maxShield = state.maxShield or 0,
            items = state.items or 0,
        },
        hooks = stubHooks,
        log = gainLog,
    }
end

-- ---------------------------------------------------------------- 预算核算
local GAIN_AXES = { "silver", "gold", "exp", "healPct", "shieldPct", "buff", "item", "intel" }

-- 把 gain 折算成可比较的预算表（buff / item 记成「次数」，不看品质，品质另算）
---@return table
function Opportunity.ValueOf(gain)
    local v = {
        silver = 0, gold = 0, exp = 0, healPct = 0, shieldPct = 0,
        buff = 0, item = 0, intel = 0, reroll = 0, stepRisk = 0, hpPct = 0,
    }
    if not gain then return v end
    v.hpPct = (gain.hpPct or 0)
    v.silver = (gain.silver or 0)
    v.gold = (gain.gold or 0)
    v.exp = (gain.exp or 0)
    v.healPct = (gain.healPct or 0)
    v.shieldPct = (gain.shieldPct or 0)
    v.item = (gain.item or 0)
    v.intel = (gain.intel or 0)
    v.reroll = (gain.reroll or 0)
    v.stepRisk = (gain.stepRisk or 0)
    if gain.buff then v.buff = 1 end
    return v
end

-- 折算成「血尘等值」，只用于跨类比较和界面上的收益预告，不参与判定
function Opportunity.SilverEquivalent(gain, cost)
    local v = Opportunity.ValueOf(gain)
    local c = Opportunity.ValueOf(cost)
    local BUFF_PRICE = { white = 24, blue = 40, purple = 64, gold = 115, color = 200 }
    local eq = (v.silver - c.silver)
        + (v.gold - c.gold) * 0.4          -- 局外资源跨局、但额度小，折价算
        + (v.exp - c.exp) * 1.0
        + (v.healPct - c.healPct) * 36     -- 1% 生命 = 0.36 血尘
        + (v.shieldPct - c.shieldPct) * 20
        + (v.item - c.item) * 12
        + (v.intel) * 8
        + (v.reroll) * 12
        + (v.stepRisk) * 0
    if gain and gain.buff then eq = eq + (BUFF_PRICE[gain.buff] or 24) end
    return eq
end

-- 单条目项是否在预算内
---@return boolean, string|nil
function Opportunity.WithinCap(kind, gain, cost)
    local cap = Opportunity.CAP[kind]
    if not cap then return false, "未知类型 " .. tostring(kind) end
    local v = Opportunity.ValueOf(gain)
    for _, axis in ipairs(GAIN_AXES) do
        local limit = cap[axis]
        if limit and v[axis] > limit + 1e-9 then
            return false, string.format("%s 超出上限：%s=%s > %s", kind, axis, tostring(v[axis]), tostring(limit))
        end
    end
    -- 得偿所愿不允许揭示地图（它只给「方向」）
    if v.intel > (cap.intel or 0) + 1e-9 then
        return false, string.format("%s 不允许给情报", kind)
    end
    local c = Opportunity.ValueOf(cost)
    for axis, limit in pairs(Opportunity.CAP_COST) do
        if c[axis] > limit + 1e-9 then
            return false, string.format("%s 代价超出上限：%s=%s > %s", kind, axis, tostring(c[axis]), tostring(limit))
        end
    end
    return true, nil
end

-- ---------------------------------------------------------------- 抽取
local function WeightedPick(list, rand, weightOf)
    local total = 0
    for i, item in ipairs(list) do total = total + (weightOf(item, i) or 0) end
    if total <= 0 then return nil end
    local x = rand() * total
    for i, item in ipairs(list) do
        x = x - (weightOf(item, i) or 0)
        if x <= 0 then return item end
    end
    return list[#list]
end
Opportunity.WeightedPick = WeightedPick

local function DefUsable(def, ctx)
    if (def.minLevel or 1) > (ctx.level or 1) then return false end
    if def.cond and not def.cond(ctx) then return false end
    return true
end

---@param kind string
---@return table|nil  offer = { id, kind, title, text, options = { {label, desc, enabled, cost, gain} }, roll = {...} }
function Opportunity.Offer(ctx, kind, depth)
    depth = depth or 0
    if depth > 8 then return nil end   -- 极端情况（所有条目都被条件挡掉）时不要递归到天荒地老
    local pool = Opportunity.ByKind[kind] or {}
    local usable = {}
    for _, def in ipairs(pool) do
        if DefUsable(def, ctx) then usable[#usable + 1] = def end
    end
    if #usable == 0 then return nil end
    local def = WeightedPick(usable, ctx.rand or math.random, function(d) return d.weight or 1 end)
    if not def then return nil end

    local offer = {
        id = def.id, kind = def.kind, title = def.title, text = def.text,
        options = {}, roll = def.roll,
    }
    if def.options then
        for _, opt in ipairs(def.options) do
            if (opt.minLevel or 1) <= (ctx.level or 1) then
                local enabled = true
                if opt.enabled then
                    local ok, res = pcall(opt.enabled, ctx)
                    enabled = ok and res or false
                end
                offer.options[#offer.options + 1] = {
                    label = opt.label, desc = opt.desc,
                    cost = opt.cost, gain = opt.gain, rollId = opt.rollId, enabled = enabled,
                }
            end
        end
        if #offer.options == 0 then return Opportunity.Offer(ctx, kind, depth + 1) end
    end
    return offer
end

-- ---------------------------------------------------------------- 结算
local function ApplyHeal(ctx, pct)
    if not pct or pct <= 0 then return 0 end
    local before = ctx.state.hp
    ctx.state.hp = math.min(ctx.state.maxHp, ctx.state.hp + ctx.state.maxHp * pct)
    return ctx.state.hp - before
end

local function ApplyShield(ctx, pct)
    if not pct or pct <= 0 then return 0 end
    local add = ctx.state.maxShield * pct
    ctx.state.shield = math.min(ctx.state.maxShield * 1.5, ctx.state.shield + add)
    return add
end

-- 扣血尘；不够就改成扣血（有地板，避免一次赌输直接结束本局）
local function ApplySilverLoss(ctx, amount)
    local have = ctx.state.silver or 0
    if have >= amount then
        ctx.state.silver = have - amount
        return string.format("失去 %d 血尘。", amount)
    end
    ctx.state.silver = 0
    local short = amount - have
    local hpLoss = math.min(ctx.state.hp * 0.9, math.max(short, 1) * 0.6)
    local cap = ctx.state.maxHp * Opportunity.LOSS_HP_CAP
    hpLoss = math.min(hpLoss, cap)
    ctx.state.hp = math.max(1, ctx.state.hp - hpLoss)
    return string.format("血尘不够，失去 %d 点生命。", math.floor(hpLoss + 0.5))
end

-- 应用一份 cost / gain，返回若干行文案
---@return table lines, boolean ok, table effects
function Opportunity.ApplySpec(ctx, spec, label)
    local lines = {}
    local effects = { stepRisk = 0 }
    local prefix = label and (label .. "：") or ""

    -- 先付代价
    if spec and spec.cost then
        local c = spec.cost
        if c.silver and c.silver > 0 then
            local have = ctx.state.silver or 0
            if have < c.silver then return { prefix .. "血尘不足，什么也没发生。" }, false, effects end
            ctx.state.silver = have - c.silver
            lines[#lines + 1] = string.format("%s支付 %d 血尘。", prefix, c.silver)
        end
        if c.hpPct and c.hpPct > 0 then
            local loss = ctx.state.maxHp * c.hpPct
            ctx.state.hp = math.max(1, ctx.state.hp - loss)
            lines[#lines + 1] = string.format("%s失去 %d 点生命。", prefix, math.floor(loss + 0.5))
        end
        if c.item and c.item > 0 then
            local ok = ctx.hooks.useItem and ctx.hooks.useItem(c.item)
            if not ok then return { prefix .. "没有可交出的道具。" }, false, effects end
            lines[#lines + 1] = string.format("%s交出 %d 个道具。", prefix, c.item)
        end
        if c.stepRisk and c.stepRisk > 0 then
            -- 代价型难度提升：由调用方（Run）读 effects.stepRisk 叠进本层 step
            effects.stepRisk = effects.stepRisk + c.stepRisk
            lines[#lines + 1] = prefix .. "这条路更难走（本层后续强度上升）。"
        end
    end

    -- 再拿收益
    local g = spec and spec.gain
    if g then
        if g.silver and g.silver ~= 0 then
            ctx.state.silver = (ctx.state.silver or 0) + g.silver
            lines[#lines + 1] = string.format("%s+%d 血尘。", prefix, g.silver)
        end
        if g.gold and g.gold ~= 0 and ctx.hooks.addGold then
            ctx.hooks.addGold(g.gold)
            lines[#lines + 1] = string.format("%s+%d 生息（局外）。", prefix, g.gold)
        end
        if g.exp and g.exp ~= 0 and ctx.hooks.addExp then
            ctx.hooks.addExp(g.exp)
            lines[#lines + 1] = string.format("%s+%d 精粹。", prefix, g.exp)
        end
        if g.healPct and g.healPct > 0 then
            local healed = ApplyHeal(ctx, g.healPct)
            lines[#lines + 1] = string.format("%s回复 %d 点生命。", prefix, math.floor(healed + 0.5))
        end
        if g.shieldPct and g.shieldPct > 0 then
            local add = ApplyShield(ctx, g.shieldPct)
            lines[#lines + 1] = string.format("%s护盾 +%d。", prefix, math.floor(add + 0.5))
        end
        if g.buff and ctx.hooks.grantBuff then
            local bf = ctx.hooks.grantBuff(g.buff)
            if bf then
                lines[#lines + 1] = string.format("%s获得「%s」：%s", prefix, tostring(bf.name), tostring(bf.desc))
            end
        end
        if g.item and g.item > 0 and ctx.hooks.addItem then
            ctx.hooks.addItem(g.item)
            lines[#lines + 1] = string.format("%s获得 %d 个道具。", prefix, g.item)
        end
        if g.intel and g.intel > 0 and ctx.hooks.reveal then
            ctx.hooks.reveal()
            lines[#lines + 1] = prefix .. "本层所有房间已标记。"
        end
        if g.reroll and g.reroll > 0 and ctx.hooks.reroll then
            ctx.hooks.reroll(g.reroll)
            lines[#lines + 1] = string.format("%s获得 %d 次免费重随。", prefix, g.reroll)
        end
        if g.stepRisk and g.stepRisk > 0 then
            effects.stepRisk = effects.stepRisk + g.stepRisk
            lines[#lines + 1] = prefix .. "这条路更难走（本层后续强度上升）。"
        end
    end

    if #lines == 0 then lines[#lines + 1] = prefix .. "什么也没发生。" end
    return lines, true, effects
end

-- 命运牌桌：按概率掷一次，含「大凶地板」规则
---@param ctx table
---@param roll table|nil  不传就默认 c_fate 那张表
---@return table|nil tier
function Opportunity.RollChance(ctx, roll)
    local def = roll
    if not def then
        local d = Opportunity.DefByID("c_fate")
        def = d and d.roll
    end
    if not def then return nil end
    local rand = ctx.rand or math.random
    local total = 0
    for _, t in ipairs(def) do total = total + t.p end
    local x = rand() * total
    local tier = def[#def]
    for _, t in ipairs(def) do
        x = x - t.p
        if x <= 0 then tier = t; break end
    end
    -- 大凶地板：血太少时降级成小凶，避免「赌一把直接结束本局」
    if tier.id == "great_bad" and ctx.state.hp <= ctx.state.maxHp * Opportunity.LOSS_HP_FLOOR then
        for _, t in ipairs(def) do
            if t.id == "bad" then tier = t; break end
        end
    end
    return tier
end

-- 掷一次命运牌桌并结算
---@return table lines, boolean ok, table effects
function Opportunity.ResolveRoll(ctx, roll)
    local tier = Opportunity.RollChance(ctx, roll)
    if not tier then return { "命运没有回应。" }, false, { stepRisk = 0 } end
    local lines = { "掷出「" .. tier.label .. "」。" }
    local effects = { stepRisk = 0 }
    if tier.cost then
        if tier.cost.silver and (ctx.state.silver or 0) < tier.cost.silver then
            lines[#lines + 1] = ApplySilverLoss(ctx, tier.cost.silver)
        else
            local sub, ok, subEffects = Opportunity.ApplySpec(ctx, { cost = tier.cost })
            for _, l in ipairs(sub) do lines[#lines + 1] = l end
            if not ok then return lines, false, effects end
            effects.stepRisk = effects.stepRisk + (subEffects and subEffects.stepRisk or 0)
        end
    end
    if tier.gain then
        local sub, _, subEffects = Opportunity.ApplySpec(ctx, { gain = tier.gain })
        for _, l in ipairs(sub) do lines[#lines + 1] = l end
        effects.stepRisk = effects.stepRisk + (subEffects and subEffects.stepRisk or 0)
    end
    if tier.bonusBuff and tier.bonusBuffChance then
        local rand = ctx.rand or math.random
        if rand() < tier.bonusBuffChance and ctx.hooks.grantBuff then
            local bf = ctx.hooks.grantBuff(tier.bonusBuff)
            if bf then
                lines[#lines + 1] = string.format("牌面又亮了一下，获得「%s」：%s", bf.name, bf.desc)
            end
        end
    end
    return lines, true, effects
end

-- 结算一个 offer 的第 index 个选项
---@return table lines, boolean ok, table effects
function Opportunity.Resolve(ctx, offer, index)
    if not offer then return { "没有可结算的机遇。" }, false, { stepRisk = 0 } end
    if offer.roll then return Opportunity.ResolveRoll(ctx, offer.roll) end

    local opt = offer.options and offer.options[index]
    if not opt then return { "这个选项不存在。" }, false, { stepRisk = 0 } end
    if opt.enabled == false then return { "现在还不能选这个。" }, false, { stepRisk = 0 } end
    -- 「搏」：这个选项本身就是一次掷骰，不读 gain
    if opt.rollId then
        local def = Opportunity.DefByID(opt.rollId)
        if not def or not def.roll then return { "牌桌上什么也没有。" }, false, { stepRisk = 0 } end
        return Opportunity.ResolveRoll(ctx, def.roll)
    end
    return Opportunity.ApplySpec(ctx, opt)
end

-- ---------------------------------------------------------------- 战斗后随机村落
-- 村落不再占地图节点：清完一间战斗房后有机会「路过」，白拿一份，纯惊喜
Opportunity.VILLAGE_DROP_CHANCE = 0.12

---@return table|nil offer
function Opportunity.RollVillageDrop(ctx)
    if not ctx then return nil end
    local rand = ctx.rand or math.random
    if rand() > Opportunity.VILLAGE_DROP_CHANCE then return nil end
    return Opportunity.Offer(ctx, "village")
end

return Opportunity
