-- ActMap.lua — 层间地图（幕 → 层卡 → 局内节点图）
--
-- 三层结构：
--   幕（Act）   —— 主线 20 关切成 4 幕，幕是「进度可视化 + 幕末奖励」的单位
--   层卡（Card）—— 每次进入下一关 / 下一层时三选一：地形模板 × 层词条
--   局内节点图  —— 一层的房间网格 + 显式边表 + 机遇族节点 + 死胡同
--
-- 为什么是「层卡三选一」而不是明日方舟那种树状节点图：
--   设计画布 1280×720、手机竖屏、NanoVG 立即模式、房间格子已经 120~140px。
--   20 个带标签的分叉节点会挤成一团，所以把「选择」压缩成三张大卡，
--   信息密度相同、点击目标够大、还能塞下完整的收益预告。
--
-- 之所以能这么便宜地做出来：Config.MapTemplates 里那 7 张手工模板本来就是
-- 「地图变体」，只是现在被 Config.PickMainMap 随机抽掉了，玩家没有选择权。
-- 本模块把它们变成「看得见、选得动」的卡，不需要新造任何地形。
--
-- 数值依据（与 Config.lua 对齐，不另立一套）：
--   Config.RoomWaves + Config.SilverDrop → 每类房间的期望银币
--   Config.RoomCost / Config.MapTargetCost → 难度预算

local Config = require "Config"

local ActMap = {}

local COMBAT_SET = { light = true, standard = true, mixed = true, elite = true, double = true }
ActMap.COMBAT_SET = COMBAT_SET
local ELITE_SET = { elite = true, double = true }
-- 会出现在地图上的机遇房只有两种：不期而遇 / 得偿所愿
-- （遗弃村落和命运牌桌已经不在看地图上了，见 Opportunity.lua 头部注释）
local SPECIAL_KINDS = { encounter = true, wish = true }
ActMap.SPECIAL_KINDS = SPECIAL_KINDS
-- 兼容旧代码：这个名字以前包含四种，现在跟着缩减
ActMap.MAP_SPECIAL_KINDS = SPECIAL_KINDS

-- ---------------------------------------------------------------- 幕
-- 幕边界直接对齐仓库里已有的两个锚点：
--   · 第 7 关起小兵池混入「畸变疫病」派系
--   · Config.Endless.unlockStage = 10（通关第 10 关解锁无尽）
-- 所以 4 幕 × 5 关不是硬加的结构，而是既有数值本来就这么长的。
ActMap.ACTS = {
    {
        id = 1, name = "初旅", from = 1, to = 5,
        faction = "游移病菌 / 病毒孢子囊",
        desc = "第一次出门。只有三种小兵，一个 Boss，地图上不会有命运岔口。",
        reward = { gold = 30, exp = 25 },
    },
    {
        id = 2, name = "蔓延", from = 6, to = 10,
        faction = "潮热沙蠕 / 畸变疫病（前置）",
        desc = "第 7 关起畸变疫病进场。打完这一幕的关底就解锁无尽模式。",
        reward = { gold = 40, exp = 30 },
    },
    {
        id = 3, name = "畸变", from = 11, to = 15,
        faction = "脓肿岩行者 / 疫蚀石魔 / 瘟衰巨像",
        desc = "地面开始留东西：脓水、腐液、衰竭疫域。精英会成对出现。",
        reward = { gold = 50, exp = 40 },
    },
    {
        id = 4, name = "瘟衰", from = 16, to = 20,
        faction = "瘟衰巨像（狂暴）",
        desc = "最后四层。关底 Boss 带层词条，强度按 RoomMul 的 9 段上限锁死。",
        reward = { gold = 60, exp = 50 },
    },
}
ActMap.MAX_LEVEL = 20

---@return table|nil
function ActMap.ActOfLevel(level)
    level = math.max(1, math.floor(level or 1))
    for _, act in ipairs(ActMap.ACTS) do
        if level >= act.from and level <= act.to then return act end
    end
    return nil
end

function ActMap.IsActEnd(level)
    local act = ActMap.ActOfLevel(level)
    return act ~= nil and level == act.to
end

-- 幕内进度：第几关 / 共几关
function ActMap.ActProgress(level)
    local act = ActMap.ActOfLevel(level)
    if not act then return 0, 5 end
    return (math.max(1, math.min(level, act.to)) - act.from) + 1, (act.to - act.from) + 1
end

-- ---------------------------------------------------------------- 层词条
-- risk = 相对 MapTargetCost 的强度偏移（会被 NormalizeMap 吸收掉一部分）
-- 硬约束：三张卡里至少一张 risk <= 0，否则玩家没得选，选择等于不存在
ActMap.MODS = {
    {
        id = "plain", name = "荒径", icon = "径", risk = 0.00, silverMul = 1.00,
        desc = "什么也没有。地图保持模板原样。",
    },
    {
        id = "market", name = "商路通畅", icon = "商", risk = -0.15, silverMul = 0.90,
        desc = "多一间商店、少一间战斗房。强化来得更多，银币少一点。",
        grid = { combatTo = "shop", count = 1 },
    },
    {
        id = "nest", name = "病巢密布", icon = "巢", risk = 0.35, silverMul = 1.25,
        desc = "多一间精英房。银币 +25%，强化品质权重上移一档。",
        grid = { promoteElite = 1 },
        qualityBonus = 1,
    },
    {
        id = "shallow", name = "浅滩缓行", icon = "滩", risk = -0.30, silverMul = 0.80,
        desc = "少两间战斗房，本层房间倍率按低 2 档算。稳但穷。",
        grid = { demote = 2 },
        stepPenalty = 2,
    },
    {
        id = "plague", name = "疫风过境", icon = "疫", risk = 0.20, silverMul = 1.00,
        desc = "清掉 Boss 房额外 +40 银币。整层更硬，但回报看得见。",
        clearSilver = 40,
    },
    {
        id = "fog", name = "迷雾", icon = "雾", risk = 0.00, silverMul = 1.00,
        desc = "地图上不显示精英与 Boss 的位置，但这一层必定有一个不期而遇。",
        hideIntel = true,
        forceEncounter = true,
    },
}

function ActMap.ModByID(id)
    for _, m in ipairs(ActMap.MODS) do
        if m.id == id then return m end
    end
    return ActMap.MODS[1]
end

-- ---------------------------------------------------------------- 房间产出（从 Config 反推）
-- 用 Config.RoomWaves 的波次 + Config.SilverDrop 的中位值算，避免手写数字和配置漂移
local SILVER_CACHE = {}
---@return number 期望银币（全清）
function ActMap.RoomSilver(kind)
    if SILVER_CACHE[kind] then return SILVER_CACHE[kind] end
    local waves = Config.RoomWaves and Config.RoomWaves[kind]
    local drop = Config.SilverDrop or {}
    local function Mid(t)
        if not t then return 0 end
        return ((t[1] or 0) + (t[2] or 0)) / 2
    end
    local minion, elite, boss = Mid(drop.minion), Mid(drop.elite), Mid(drop.boss)
    local total = 0
    if waves then
        for _, w in ipairs(waves) do
            total = total + (w.minion or 0) * minion + (w.elite or 0) * elite + (w.boss or 0) * boss
        end
    end
    SILVER_CACHE[kind] = math.floor(total + 0.5)
    return SILVER_CACHE[kind]
end

-- 一层的房间统计 + 期望收益
---@param grid string[][]
---@param mod table|nil
---@return table preview
function ActMap.PreviewOf(grid, mod)
    local p = { combat = 0, elite = 0, shop = 0, event = 0, special = 0, boss = 0, silver = 0 }
    local rows = #grid
    for r = 1, rows do
        for c = 1, #grid[r] do
            local t = grid[r][c]
            if t == "boss" then
                p.boss = p.boss + 1
                p.silver = p.silver + ActMap.RoomSilver(t)
            elseif t == "shop" then
                p.shop = p.shop + 1
            elseif t == "event" then
                -- 模板里的 event 格会在 GenerateLayer 里就地改造成机遇房，所以预告里算进「机遇」
                p.event = p.event + 1
                p.special = p.special + 1
            elseif SPECIAL_KINDS[t] then
                p.special = p.special + 1
            elseif COMBAT_SET[t] then
                p.combat = p.combat + 1
                if ELITE_SET[t] then p.elite = p.elite + 1 end
                p.silver = p.silver + ActMap.RoomSilver(t)
            end
        end
    end
    local mul = (mod and mod.silverMul) or 1
    p.silver = math.floor(p.silver * mul + 0.5) + ((mod and mod.clearSilver) or 0)
    return p
end

-- 相对目标强度的偏移
-- 注意：词条的 risk 只作为 NormalizeGrid 的目标偏移，已经沉到网格组成里了，
-- 这里不能再加一次，否则会重复计算（病巢实际 +0.35，算出来会变成 +0.70）
function ActMap.RiskOf(grid, level)
    return Config.AvgCombatCost(grid) - Config.MapTargetCost(level)
end

function ActMap.RiskLabel(risk)
    if risk <= -0.20 then return "轻松" end
    if risk <= 0.10 then return "常规" end
    if risk <= 0.32 then return "吃紧" end
    return "险恶"
end

-- ---------------------------------------------------------------- 网格工具
local function CloneGrid(grid)
    local out = {}
    for r = 1, #grid do
        out[r] = {}
        for c = 1, #grid[r] do out[r][c] = grid[r][c] end
    end
    return out
end
ActMap.CloneGrid = CloneGrid

-- 「起点右边第一间」和 Boss 房是不能动的锚点（Config.CheckMap 会校验）
local function IsAnchor(grid, r, c)
    local rows = #grid
    local cols = #grid[1]
    if grid[r][c] == "start" or grid[r][c] == "boss" then return true end
    if r == rows and c == 2 then return true end
    if r == 1 and c == cols then return true end
    return false
end

local function ApplyMod(grid, mod)
    if not mod or not mod.grid then return grid end
    local rows, cols = #grid, #grid[1]

    -- 把一间战斗房改成商店（同时满足 combat-1 / shop+1）
    if mod.grid.combatTo == "shop" then
        local pick
        for c = cols - 1, 2, -1 do
            for r = 1, rows do
                if COMBAT_SET[grid[r][c]] and not IsAnchor(grid, r, c) then
                    pick = { r, c }
                    break
                end
            end
            if pick then break end
        end
        if pick then grid[pick[1]][pick[2]] = "shop" end
    end

    -- 升一间精英房
    if mod.grid.promoteElite then
        local pick
        for r = 2, rows do
            for c = 3, cols - 1 do
                local t = grid[r][c]
                if (t == "standard" or t == "mixed" or t == "light") and not IsAnchor(grid, r, c) then
                    pick = { r, c }
                    break
                end
            end
            if pick then break end
        end
        if pick then grid[pick[1]][pick[2]] = "elite" end
    end

    -- 降级战斗房（double → elite → mixed → standard → light）
    if mod.grid.demote then
        local DOWN = { double = "elite", elite = "mixed", mixed = "standard", standard = "light" }
        local done = 0
        for c = cols, 1, -1 do
            for r = 1, rows do
                if done >= mod.grid.demote then break end
                local t = grid[r][c]
                if DOWN[t] and not IsAnchor(grid, r, c) then
                    grid[r][c] = DOWN[t]
                    done = done + 1
                end
            end
        end
    end
    return grid
end
ActMap.ApplyMod = ApplyMod

-- ---------------------------------------------------------------- 难度归一
-- 和 Config.lua 里 MapTemplates 那套同一个思路，但目标值带上词条的 risk 偏移：
-- 词条说要难 0.35，就把这张卡的平均强度往 MapTargetCost+0.35 上拉。
-- 不这么做的话「精英重压」模板自己就 +0.33，叠上病巢直接爆表，
-- 玩家看到的会是「三张卡全都打不过」——那选择等于不存在。
local DOWN = { double = "elite", elite = "mixed", mixed = "standard", standard = "light" }
-- 阶梯：DOWN 逐级降、UP 逐级升。
-- mixed → elite 这一档是 2026-11-10 补的：没有它，第 20 关（目标 1.75）的卡
-- 最多只能归一到混战房（1.4），risk 恒为负，三张卡全变成「轻松」——
-- 玩家看到的不是「选难的那个」，而是「三张一样」。
local UP = { light = "standard", standard = "mixed", mixed = "elite" }

local function NormalizeGrid(grid, level, mod)
    local target = Config.MapTargetCost(level) + ((mod and mod.risk) or 0)
    for _ = 1, 16 do
        local avg = Config.AvgCombatCost(grid)
        local pick, pickCost = nil, nil
        if avg > target + 0.22 then
            for r = 1, #grid do
                for c = 1, #grid[r] do
                    local t = grid[r][c]
                    if DOWN[t] and not IsAnchor(grid, r, c) then
                        local cost = Config.RoomCost[t] or 0
                        if not pickCost or cost > pickCost then pick, pickCost = { r, c }, cost end
                    end
                end
            end
            if not pick then break end
            grid[pick[1]][pick[2]] = DOWN[grid[pick[1]][pick[2]]]
        elseif avg < target - 0.24 then
            for r = 1, #grid do
                for c = 1, #grid[r] do
                    local t = grid[r][c]
                    if UP[t] and not IsAnchor(grid, r, c) then
                        local cost = Config.RoomCost[t] or 0
                        if not pickCost or cost < pickCost then pick, pickCost = { r, c }, cost end
                    end
                end
            end
            if not pick then break end
            grid[pick[1]][pick[2]] = UP[grid[pick[1]][pick[2]]]
        else
            break
        end
    end
    -- 前 5 关不出双精房（和 Config.NormalizeMap 保持一致）
    if level < 6 then
        for r = 1, #grid do
            for c = 1, #grid[r] do
                if grid[r][c] == "double" then grid[r][c] = "elite" end
            end
        end
    end
    return grid
end

-- 一层只放几个机遇房。改成 2 就能恢复到「两个机遇房」的版本，其余代码不用动。
ActMap.SPECIAL_ROOM_COUNT = 1

-- 一层最多只留同样数量的「事件格」（journey 模板有 3 个）。
-- 多出来的降级成轻战：保持房间总数不变，同时给后面 PlaceSpecials 留出上限
local function ClampEvents(grid, maxCount)
    maxCount = maxCount or ActMap.SPECIAL_ROOM_COUNT
    local events = {}
    for r = 1, #grid do
        for c = 1, #grid[r] do
            if grid[r][c] == "event" then events[#events + 1] = { r, c } end
        end
    end
    for i = maxCount + 1, #events do
        local e = events[i]
        if not IsAnchor(grid, e[1], e[2]) then grid[e[1]][e[2]] = "light" end
    end
    return grid
end
ActMap.ClampEvents = ClampEvents

-- ---------------------------------------------------------------- 层卡
local SAFE_MODS = { "plain", "shallow" }
local RISK_MODS = { "nest", "plague" }
local FILLER_MODS = { "market", "fog", "plain" }

local function PickFrom(list, rand, used)
    local pool = {}
    for _, id in ipairs(list) do
        if not (used and used[id]) then pool[#pool + 1] = id end
    end
    if #pool == 0 then
        for _, id in ipairs(list) do pool[#pool + 1] = id end
    end
    return pool[rand(1, #pool)]
end

local function PickTemplate(list, level, rand, used)
    local pool = {}
    for _, t in ipairs(list) do
        if not (used and used[t.id]) then pool[#pool + 1] = t end
    end
    if #pool == 0 then pool = list end
    -- 关卡越早，越倾向「轻战起步」这类模板
    local weights = {}
    local total = 0
    for i, t in ipairs(pool) do
        local w = 1
        if level < (t.minLevel or 1) then w = 0.15 end
        weights[i] = w
        total = total + w
    end
    local x = rand(1, 1000) / 1000 * total
    for i, t in ipairs(pool) do
        x = x - weights[i]
        if x <= 0 then return t end
    end
    return pool[#pool]
end

-- 三选一：地形模板 × 层词条
-- 硬约束（dev/DevActMap.lua 会跑 200 次）：
--   · 正好 3 张卡，模板与词条都不重复
--   · 至少一张 risk <= 0（给一条不冒险的路）
--   · 每张卡的 risk 在 [-0.45, +0.45]
--   · 每张卡都通过 Config.CheckMap
-- ---------------------------------------------------------------- 三张卡的整体修复
-- 支配卡：一张卡既更难（或同难度）、又给得更少。这种卡在三选一里永远没有选它的理由，
-- 玩家只是多了一个废选项。实测（2026-11-11）200 次抽卡里有 55 次（27.5%）存在这种卡。
-- 「轻松 = 房间战斗弱」已是定稿语义，所以修复方向是**把银币补上去**，不是改标签。
local DOM_EPS = 1e-9

--- a 是否被 b 支配（b 至少一样好，且有一项严格更好）
function ActMap.IsDominated(a, b)
    if a == nil or b == nil or a == b then return false end
    local harsher = a.risk > b.risk + DOM_EPS
    local sameRisk = math.abs(a.risk - b.risk) <= DOM_EPS
    if harsher then return a.preview.silver <= b.preview.silver end
    if sameRisk then return a.preview.silver < b.preview.silver end
    return false
end

-- 战斗房升/降一级。只改类型不改数量，所以 CheckMap 的「首房为战斗房 / 商店事件各 ≥1」
-- 不受影响（IsAnchor 会保护起点、首领、首房）。
local BUMP_UP = { light = "standard", standard = "mixed", mixed = "elite" }
local BUMP_DOWN = { elite = "mixed", mixed = "standard", standard = "light" }

local function ChangeOneRoom(card, level, order)
    local grid = card.grid
    for r = 1, #grid do
        for c = 1, #grid[r] do
            local from = grid[r][c]
            local to = order[from]
            if to and not IsAnchor(grid, r, c) then
                grid[r][c] = to
                if Config.CheckMap(grid) then
                    card.preview = ActMap.PreviewOf(grid, card.mod)
                    card.risk = ActMap.RiskOf(grid, level)
                    card.riskLabel = ActMap.RiskLabel(card.risk)
                    card.baseSilver = card.preview.silver
                    card.silverFix = 0
                    return true
                end
                grid[r][c] = from
            end
        end
    end
    return false
end

-- 把被支配的卡修到「不再被支配」。
-- 只补银币是不够的：两张卡**强度完全一样**时，无论怎么调银币，穷的那张都会被富的支配
-- （同强度、更少钱）——所以得先把「强度撞车」拆开，给其中一张升/降一个战斗房。
function ActMap.RepairPareto(cards, level, cap)
    cap = cap or 1.00
    local fixes, added, bumped = 0, 0, 0
    for _ = 1, 4 do
        -- ① 拆强度撞车：同强度且给得不更多的那张，升一个战斗房（升不了就把另一张降一个）
        for i = 1, #cards do
            for j = 1, #cards do
                local a, b = cards[i], cards[j]
                if i ~= j and math.abs(a.risk - b.risk) <= DOM_EPS
                    and a.preview.silver <= b.preview.silver then
                    if ChangeOneRoom(a, level, BUMP_UP) then
                        bumped = bumped + 1
                    elseif ChangeOneRoom(b, level, BUMP_DOWN) then
                        bumped = bumped + 1
                    end
                end
            end
        end

        -- ② 补银币：更难（或同难度）却给得更少的那张，补到严格多于对方
        for i = 1, #cards do
            local a = cards[i]
            for j = 1, #cards do
                local b = cards[j]
                if ActMap.IsDominated(a, b) then
                    local base = a.baseSilver or a.preview.silver
                    local harsher = a.risk > b.risk + DOM_EPS
                    -- 同难度要求银币严格更多，否则会被反向支配；更难则至少持平
                    local target = harsher and (b.preview.silver + 1) or b.preview.silver
                    -- 封顶 +1：卡在封顶线时也要保证「严格多于对方」，否则会留下 1 银币的残留支配
                    local limit = math.floor(base * (1 + cap) + 0.5) + 1
                    if target > limit then target = limit end
                    if target > limit then
                        -- 差距大到补不起（>cap）：把这张「又难又穷」的卡降一级，让它不再更难。
                        -- 降不下来（已经全是浅滩房）就只能留着，下一轮再说。
                        ChangeOneRoom(a, level, BUMP_DOWN)
                    elseif target > a.preview.silver then
                        local d = target - a.preview.silver
                        a.silverFix = (a.silverFix or 0) + d
                        a.preview.silver = target
                        fixes = fixes + 1
                        added = added + d
                    end
                end
            end
        end
    end
    return fixes, added, bumped
end

-- M2：收益分档（三张卡相对排名，不引入新的绝对阈值）
-- 标签只表达战斗强度，所以「选哪张」这个决策只能靠收益分档承担。
function ActMap.AssignSilverTiers(cards)
    -- 三张卡 → 1/2/3 星，卡片数变了也能用（星数 = 相对排名）
    local STAR = { [1] = "★☆☆", [2] = "★★☆", [3] = "★★★" }
    local LABEL = { [1] = "偏少", [2] = "一般", [3] = "偏多" }
    for i = 1, #cards do
        local c = cards[i]
        local n = 0
        for j = 1, #cards do
            if cards[j].preview.silver < c.preview.silver - DOM_EPS then n = n + 1 end
        end
        c.silverTier = math.min(3, n + 1)   -- 1 = 最穷 … 3 = 最富
        c.silverStars = STAR[c.silverTier]
        c.silverLabel = LABEL[c.silverTier]
    end
end

---@param level integer
---@param opts table|nil  { rand, needShop, templates }
---@return table[] cards
function ActMap.RollCards(level, opts)
    opts = opts or {}
    local rand = opts.rand or function(a, b) return math.random(a, b) end
    local list = opts.templates or Config.MapTemplates
    local usedTpl, usedMod = {}, {}
    local cards = {}

    local plan = {
        { pool = SAFE_MODS },   -- 一张稳的
        { pool = RISK_MODS },   -- 一张有代价的
        { pool = FILLER_MODS }, -- 一张补位
    }

    for i = 1, 3 do
        local modId = PickFrom(plan[i].pool, rand, usedMod)
        local mod = ActMap.ModByID(modId)
        local card = nil
        for _ = 1, 8 do
            local tpl = PickTemplate(list, level, rand, usedTpl)
            local grid = NormalizeGrid(ClampEvents(ApplyMod(CloneGrid(tpl.grid), mod)), level, mod)
            local ok = Config.CheckMap(grid, { shop = opts.needShop == nil or opts.needShop })
            if ok then
                card = {
                    id = tpl.id .. "/" .. mod.id,
                    templateId = tpl.id, templateName = tpl.name,
                    modId = mod.id, modName = mod.name, mod = mod,
                    grid = grid,
                }
                usedTpl[tpl.id] = true
                break
            end
        end
        if not card then
            -- 词条把地图改坏了：退回荒径，保证永远有牌出
            local mod2 = ActMap.ModByID("plain")
            local tpl = PickTemplate(list, level, rand, usedTpl)
            card = {
                id = tpl.id .. "/plain", templateId = tpl.id, templateName = tpl.name,
                modId = "plain", modName = mod2.name, mod = mod2,
                grid = NormalizeGrid(ClampEvents(CloneGrid(tpl.grid)), level, mod2),
            }
            usedTpl[tpl.id] = true
            mod = mod2
        end
        usedMod[mod.id] = true
        card.preview = ActMap.PreviewOf(card.grid, mod)
        card.risk = ActMap.RiskOf(card.grid, level)
        card.riskLabel = ActMap.RiskLabel(card.risk)
        card.stepPenalty = mod.stepPenalty or 0
        card.silverMul = mod.silverMul or 1
        card.qualityBonus = mod.qualityBonus or 0
        card.clearSilver = mod.clearSilver or 0
        card.hideIntel = mod.hideIntel or false
        card.forceEncounter = mod.forceEncounter or false
        cards[#cards + 1] = card
    end

    -- 兜底：万一三张全是险的（模板本身就重），把最后一张换成浅滩
    local hasSafe = false
    for _, card in ipairs(cards) do
        if card.risk <= 0.02 then hasSafe = true; break end
    end
    if not hasSafe then
        local mod = ActMap.ModByID("shallow")
        -- 必须把 already-used 的模板传进去，否则兜底牌会和另一张卡撞模板
        local tpl = PickTemplate(list, level, rand, usedTpl)
        local grid = NormalizeGrid(ClampEvents(ApplyMod(CloneGrid(tpl.grid), mod)), level, mod)
        cards[3] = {
            id = tpl.id .. "/shallow", templateId = tpl.id, templateName = tpl.name,
            modId = mod.id, modName = mod.name, mod = mod, grid = grid,
            preview = ActMap.PreviewOf(grid, mod),
            risk = ActMap.RiskOf(grid, level),
            riskLabel = ActMap.RiskLabel(ActMap.RiskOf(grid, level)),
            stepPenalty = mod.stepPenalty or 0,
            silverMul = mod.silverMul or 1,
            qualityBonus = 0,
            clearSilver = 0,
            hideIntel = false,
            forceEncounter = false,
        }
    end

    -- 三张卡都齐了才做整体修复：先记基准收益（用于封顶和统计），再修帕累托，最后分档
    for _, c in ipairs(cards) do c.baseSilver = c.preview.silver end
    ActMap.RepairPareto(cards, level)
    ActMap.AssignSilverTiers(cards)
    return cards
end

-- ---------------------------------------------------------------- 边表
local DIRS = { { 0, 1 }, { -1, 0 }, { 1, 0 } }   -- 右 / 上 / 下：和现在 Run.CanMove 一致

local function EKey(r, c) return tostring(r) .. "," .. tostring(c) end
ActMap.EKey = EKey

local function Adjacent(grid, r, c)
    local rows, cols = #grid, #grid[1]
    local list = {}
    for _, d in ipairs(DIRS) do
        local nr, nc = r + d[1], c + d[2]
        if nr >= 1 and nr <= rows and nc >= 1 and nc <= cols then
            list[#list + 1] = { nr, nc }
        end
    end
    return list
end

-- 从 start 出发能不能到 boss；avoid = { elite = true } 表示绕开精英房
---@return boolean
function ActMap.HasPath(grid, edges, avoid)
    local rows = #grid
    local startR, startC = rows, 1
    local seen = { [EKey(startR, startC)] = true }
    local queue = { { startR, startC } }
    local head = 1
    while head <= #queue do
        local cur = queue[head]; head = head + 1
        local r, c = cur[1], cur[2]
        local t = grid[r][c]
        if t == "boss" then return true end
        if t == "start" or not (avoid and avoid[grid[r][c]]) then
            local list = (edges and edges[EKey(r, c)]) or Adjacent(grid, r, c)
            for _, nb in ipairs(list) do
                local k = EKey(nb[1], nb[2])
                if not seen[k] then
                    seen[k] = true
                    -- 目标格是精英房时不进（但 Boss / 商店可以进）
                    if not (avoid and avoid[grid[nb[1]][nb[2]]]) then
                        queue[#queue + 1] = nb
                    end
                end
            end
        end
    end
    return false
end

function ActMap.RoomCount(grid)
    local n = 0
    for r = 1, #grid do n = n + #grid[r] end
    return n
end

-- 基础边表 = 网格四邻接（只往右 / 上 / 下）
local function BaseEdges(grid)
    local edges = {}
    for r = 1, #grid do
        for c = 1, #grid[r] do
            edges[EKey(r, c)] = Adjacent(grid, r, c)
        end
    end
    return edges
end

-- ---------------------------------------------------------------- 局内节点图
-- 机遇族：每层 1~2 个，只有「不期而遇」和「得偿所愿」两种
ActMap.SPECIAL_WEIGHTS = { encounter = 58, wish = 42 }
-- 地图上会出现哪些机遇房：只有这两类
local MAP_KINDS = { "encounter", "wish" }

local function PickSpecialKind(level, rand)
    local pool, total = {}, 0
    for _, kind in ipairs(MAP_KINDS) do
        local w = ActMap.SPECIAL_WEIGHTS[kind] or 0
        if w > 0 then
            pool[#pool + 1] = { kind = kind, w = w }
            total = total + w
        end
    end
    if total <= 0 or #pool == 0 then return "encounter" end
    local x = (rand(1, 1000) / 1000) * total
    for _, entry in ipairs(pool) do
        x = x - entry.w
        if x <= 0 then return entry.kind end
    end
    return pool[#pool].kind
end

local function SpecialCandidates(grid)
    local rows, cols = #grid, #grid[1]
    local list = {}
    for r = 1, rows do
        for c = 2, cols do
            if COMBAT_SET[grid[r][c]] and not IsAnchor(grid, r, c) then
                list[#list + 1] = { r, c }
            end
        end
    end
    return list
end

local function PlaceSpecials(grid, level, rand, mod)
    local specials = {}

    -- ① 模板里的 event 房 == 老的三个硬编码事件（骰子赌局 / 藏宝洞 / 篝火陌生人），
    --    跟新的机遇房功能完全重叠（赌 = 命运、藏宝 = 得偿所愿、篝火 = 不期而遇）。
    --    所以就地改造成 encounter / wish，不再额外占格子 —— 这是本轮减节点的主要收益。
    for r = 1, #grid do
        for c = 1, #grid[r] do
            if grid[r][c] == "event" then
                local kind = PickSpecialKind(level, rand)
                grid[r][c] = kind
                specials[#specials + 1] = { r = r, c = c, kind = kind, wasEvent = true }
            end
        end
    end

    -- ② 迷雾：必定有一个不期而遇
    if mod and mod.forceEncounter then
        local hasEncounter = false
        for _, s in ipairs(specials) do
            if s.kind == "encounter" then hasEncounter = true end
        end
        if not hasEncounter and #specials > 0 then
            local s = specials[1]
            grid[s.r][s.c] = "encounter"
            s.kind = "encounter"
        elseif not hasEncounter then
            local cands = SpecialCandidates(grid)
            if #cands > 0 then
                local pick = cands[rand(1, #cands)]
                grid[pick[1]][pick[2]] = "encounter"
                specials[#specials + 1] = { r = pick[1], c = pick[2], kind = "encounter" }
            end
        end
    end

    -- ③ 数量不够就从战斗房里补；总数受 ActMap.SPECIAL_ROOM_COUNT 控制
    local want = ActMap.SPECIAL_ROOM_COUNT
    while #specials < want do
        local cands = SpecialCandidates(grid)
        if #cands == 0 then break end
        local pick = cands[rand(1, #cands)]
        local kind = PickSpecialKind(level, rand)
        grid[pick[1]][pick[2]] = kind
        specials[#specials + 1] = { r = pick[1], c = pick[2], kind = kind }
    end
    return specials
end

-- 把某个机遇房改成「死胡同」：只能从左边进来，没有出口
-- 绕路 = 房间数变多 = step 变大 = 后面所有房间更硬，这是天然的平衡杠杆
local function MakeDeadEnd(grid, edges, specials, rand)
    if #specials == 0 then return nil end
    local target = specials[rand(1, #specials)]
    local key = EKey(target.r, target.c)
    local saved = edges[key]
    edges[key] = {}
    if not ActMap.HasPath(grid, edges, nil) then
        edges[key] = saved
        return nil
    end
    target.deadEnd = true
    return target
end

-- 生成一层的节点图：{ grid, edges, specials, card, risk }
---@param level integer
---@param card table  ActMap.RollCards 返回的其中一张
---@param opts table|nil  { rand, maxTries }
---@return table layer
function ActMap.GenerateLayer(level, card, opts)
    opts = opts or {}
    local rand = opts.rand or function(a, b) return math.random(a, b) end
    local maxTries = opts.maxTries or 40
    local last = nil

    for _ = 1, maxTries do
        local grid = CloneGrid(card.grid)
        local specials = PlaceSpecials(grid, level, rand, card.mod)
        local edges = BaseEdges(grid)
        MakeDeadEnd(grid, edges, specials, rand)
        local layer = {
            level = level, card = card, grid = grid, edges = edges,
            specials = specials, rows = #grid, cols = #grid[1],
        }
        local ok, reason = ActMap.CheckLayer(layer)
        if ok then return layer end
        last = { layer = layer, reason = reason }
    end

    -- 兜底：把精英房全降成混战，保证一定有绕过路线
    local grid = CloneGrid(card.grid)
    for r = 1, #grid do
        for c = 1, #grid[r] do
            if ELITE_SET[grid[r][c]] and not IsAnchor(grid, r, c) then
                grid[r][c] = "mixed"
            end
        end
    end
    local specials = PlaceSpecials(grid, level, rand, card.mod)
    local edges = BaseEdges(grid)
    return {
        level = level, card = card, grid = grid, edges = edges,
        specials = specials, rows = #grid, cols = #grid[1],
        fallback = true,
        lastReason = last and last.reason or nil,
    }
end

-- 结构硬约束
---@return boolean, string|nil
function ActMap.CheckLayer(layer)
    local grid = layer.grid
    local edges = layer.edges
    if not grid or #grid == 0 then return false, "空地图" end
    local rows, cols = #grid, #grid[1]
    if grid[rows][1] ~= "start" then return false, "起点不在左下" end
    if grid[1][cols] ~= "boss" then return false, "Boss 不在右上" end
    if not ActMap.HasPath(grid, edges, nil) then return false, "走不到 Boss" end
    if not ActMap.HasPath(grid, edges, ELITE_SET) then
        return false, "没有绕过精英房的路线"
    end
    local specialCount = 0
    for r = 1, rows do
        for c = 1, cols do
            local t = grid[r][c]
            if SPECIAL_KINDS[t] then specialCount = specialCount + 1 end
            -- 机遇房改造完之后不该再有 event 格
            if t == "event" then return false, "还有未改造的 event 房" end
        end
    end
    if specialCount < 1 then return false, "没有机遇族节点" end
    if specialCount > ActMap.SPECIAL_ROOM_COUNT then
        return false, string.format("机遇房超过 %d 个：%d", ActMap.SPECIAL_ROOM_COUNT, specialCount)
    end
    return true, nil
end

-- ---------------------------------------------------------------- 幕末奖励
-- 主线过完一幕给一次「幕间机遇」：村庄式、无风险、不给战斗
function ActMap.ActEndReward(level)
    local act = ActMap.ActOfLevel(level)
    if not act or level ~= act.to then return nil end
    return {
        actId = act.id, actName = act.name,
        gold = act.reward.gold, exp = act.reward.exp,
        text = string.format("「%s」幕完成：+%d 生息、+%d 精粹。", act.name, act.reward.gold, act.reward.exp),
    }
end

return ActMap
