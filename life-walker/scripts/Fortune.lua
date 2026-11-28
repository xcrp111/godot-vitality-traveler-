-- Fortune.lua — 每日一卦（叙事彩蛋，零数值产出）
--
-- 定位：不谈预言，只谈心情。它不给银币/经验/强化/提示，只给一句"今天该做什么"的话。
-- 三条硬规则（写在文案里就要守住，dev/DevFortune.lua 会断言）：
--   ① 禁止断言未来（不出现"会""将要"这类预测）
--   ② 禁止涉及具体人（不谈"某人会联系你"）
--   ③ 零数值产出（本模块不 require 任何东西，也不调用任何 hook）
--
-- 摇卦：三枚硬币 × 6 爻，从初爻摇到上爻。
--   0 阳 = 老阴（动，阴变阳）
--   1 阳 = 少阳（静，阳）
--   2 阳 = 少阴（静，阴）
--   3 阳 = 老阳（动，阳变阴）
-- 概率与三钱法一致：老阴/老阳各 1/8，少阳/少阴各 3/8。

local Fortune = {}

-- ---------------------------------------------------------------- 八卦
-- key 是"初爻、中爻、上爻"三位，1 = 阳，0 = 阴
Fortune.TRIGRAMS = {
    ["111"] = { name = "乾", symbol = "天" },
    ["110"] = { name = "兑", symbol = "泽" },
    ["101"] = { name = "离", symbol = "火" },
    ["100"] = { name = "震", symbol = "雷" },
    ["011"] = { name = "巽", symbol = "风" },
    ["010"] = { name = "坎", symbol = "水" },
    ["001"] = { name = "艮", symbol = "山" },
    ["000"] = { name = "坤", symbol = "地" },
}

-- ---------------------------------------------------------------- 卦表
-- 先上 12 卦（够轮着出两个月），其余用通用文案兜底。
-- 每条四段：name（卦名）/ state（一句状态）/ good（宜）/ bad（忌）
Fortune.HEXAGRAMS = {
    ["111111"] = { name = "乾为天", state = "力气很足的一天。", good = "把最想推进的那件事推一步。", bad = "一次开三摊。" },
    ["000000"] = { name = "坤为地", state = "适合承接，不适合起头。", good = "把手头的事做扎实。", bad = "今天做重大决定。" },
    ["010100"] = { name = "水雷屯", state = "刚起步，处处滞涩。", good = "先把最小的那一步走完。", bad = "急着要结果。" },
    ["001010"] = { name = "山水蒙", state = "雾还没散，看不清就先别急着断定。", good = "把要做的事写成一句话。", bad = "反复问同一个问题。" },
    ["000111"] = { name = "地天泰", state = "今天是顺的，顺着走就行。", good = "把那件一直拖着的小事推一步。", bad = "因为顺就跳过检查。" },
    ["111000"] = { name = "天地否", state = "气不顺的时候，守住已经确定的东西。", good = "把今天的范围缩小一半。", bad = "在这种日子里做决定。" },
    ["001110"] = { name = "山泽损", state = "先减掉一件事，路才走得动。", good = "删一个计划外的任务。", bad = "一边累一边加码。" },
    ["011001"] = { name = "风山渐", state = "不是慢，是稳。", good = "按自己的节奏来。", bad = "拿别人的进度当刻度。" },
    ["101010"] = { name = "火水未济", state = "收尾比开头难。", good = "把一件旧的做完。", bad = "同时开三个新头。" },
    ["010101"] = { name = "水火既济", state = "事情到了一个刚好的位置。", good = "把已经完成的记下来。", bad = "刚顺就想加量。" },
    ["111101"] = { name = "天火同人", state = "适合和人一起做点什么。", good = "把关系放到一件共同的事上。", bad = "在私底下反复猜别人的意思。" },
    ["101111"] = { name = "火天大有", state = "手上东西不少，别乱花。", good = "清点一下已有的资源。", bad = "因为富余就做多余的消耗。" },
}

-- 通用兜底（不在表里的卦）：只描述状态，不给预测
Fortune.GENERIC = {
    state = "今天没有特别的卦象。",
    good = "按自己的节奏走。",
    bad = "为了等一个征兆而停下来。",
}

-- ---------------------------------------------------------------- 摇卦
-- rand 需返回 [0,1) 的小数；不传就用 math.random
local function DefaultRand()
    return math.random()
end

--- 摇一卦
---@param rand fun():number|nil
---@return table lines  1..6，每项 { yang=bool, moving=bool, value=6/7/8/9 }
function Fortune.Cast(rand)
    rand = rand or DefaultRand
    local lines = {}
    for i = 1, 6 do
        local heads = 0
        for _ = 1, 3 do
            if rand() < 0.5 then heads = heads + 1 end
        end
        local yang, moving, value
        if heads == 0 then yang, moving, value = false, true, 6      -- 老阴
        elseif heads == 1 then yang, moving, value = true, false, 7  -- 少阳
        elseif heads == 2 then yang, moving, value = false, false, 8 -- 少阴
        else yang, moving, value = true, true, 9                     -- 老阳
        end
        lines[i] = { yang = yang, moving = moving, value = value }
    end
    return lines
end

-- 取三位 key：初/中/上（对下卦是 1,2,3；对上卦是 4,5,6）
local function TriKey(lines, from)
    local s = ""
    for i = from, from + 2 do
        s = s .. (lines[i].yang and "1" or "0")
    end
    return s
end

--- 由六爻算出上下卦与卦名
---@param lines table
---@return table { lowerKey, upperKey, lower, upper, hexKey, hex }
function Fortune.Read(lines)
    local lowerKey = TriKey(lines, 1)
    local upperKey = TriKey(lines, 4)
    local hexKey = upperKey .. lowerKey   -- 上卦在前，和下卦区分开
    local hex = Fortune.HEXAGRAMS[hexKey]
    return {
        lowerKey = lowerKey, upperKey = upperKey,
        lower = Fortune.TRIGRAMS[lowerKey], upper = Fortune.TRIGRAMS[upperKey],
        hexKey = hexKey, hex = hex,
    }
end

--- 有动爻时算出变卦（老阳变阴、老阴变阳）
---@return table|nil changed  nil 表示六爻全静
function Fortune.Changed(lines)
    local any = false
    for i = 1, 6 do if lines[i].moving then any = true end end
    if not any then return nil end
    local flipped = {}
    for i = 1, 6 do
        local yang = lines[i].yang
        if lines[i].moving then yang = not yang end
        flipped[i] = { yang = yang, moving = false, value = yang and 7 or 8 }
    end
    return Fortune.Read(flipped)
end

--- 摇一卦并取出要说的话（四段）
---@return table { name, state, good, bad, movingCount, changedName }
function Fortune.Draw(rand)
    local lines = Fortune.Cast(rand)
    local g = Fortune.Read(lines)
    local hex = g.hex or Fortune.GENERIC
    local movingCount = 0
    for i = 1, 6 do if lines[i].moving then movingCount = movingCount + 1 end end
    local changed = Fortune.Changed(lines)
    local changedName = nil
    if changed then
        changedName = changed.hex and changed.hex.name
            or (changed.upper.name .. "上" .. changed.lower.name .. "下（变卦）")
    end
    local name = hex.name or (g.upper.name .. "上" .. g.lower.name .. "下")
    return {
        name = name,
        state = hex.state, good = hex.good, bad = hex.bad,
        movingCount = movingCount,
        changedName = changedName,
        lines = lines,
    }
end

--- 每日一次：把日期折成种子，同一天结果稳定
---@param year integer
---@param month integer
---@param day integer
---@return integer
function Fortune.SeedOf(year, month, day)
    return (year * 372 + month * 31 + day) % 2147483647
end

-- 简易可复现随机（线性同余），避免动 math.random 的全局种子
local function SeededRand(seed)
    local s = math.floor(seed) % 2147483647
    if s <= 0 then s = s + 2147483646 end
    return function()
        s = (s * 16807) % 2147483647
        return s / 2147483647
    end
end

--- 按日期取今日一卦（同一天永远一样）
function Fortune.DailyText(year, month, day)
    return Fortune.Draw(SeededRand(Fortune.SeedOf(year, month, day)))
end

return Fortune
