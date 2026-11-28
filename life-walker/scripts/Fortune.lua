-- Fortune.lua — 每日一卦（叙事彩蛋，零数值产出）
--
-- 定位：不谈预言，只谈心情。它不给银币/经验/强化/提示，只给一句"今天该做什么"的话。
-- 三条硬规则（dev/DevFortune.lua 会断言）：
--   ① 禁止断言未来（不出现"会回来""将会"这类预测）
--   ② 禁止涉及具体人（不谈"某人会联系你"）
--   ③ 零数值产出（本模块不 require 任何东西，也不调用任何 hook）
--
-- 摇卦：三枚硬币 × 6 爻，从初爻摇到上爻。
--   0 阳 = 老阴（动，阴变阳）　1 阳 = 少阳（静，阳）
--   2 阳 = 少阴（静，阴）　　3 阳 = 老阳（动，阳变阴）
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

-- ---------------------------------------------------------------- 六十四卦
-- key = 上卦三位 .. 下卦三位。每条四段：name / state（状态一句）/ good（宜）/ bad（忌）
-- 写法约定：state 只描述"当下是什么样"，good/bad 只给行为建议；不写预测、不写具体人。
Fortune.HEXAGRAMS = {
    -- 上乾
    ["111111"] = { name = "乾为天", state = "力气很足的一天。", good = "把最想推进的那件事推一步。", bad = "一次开三摊。" },
    ["111110"] = { name = "天泽履", state = "脚下有薄冰，走路要看着。", good = "按规矩来，别抄近道。", bad = "逞能。" },
    ["111101"] = { name = "天火同人", state = "适合和人一起做点什么。", good = "把关系放到一件共同的事上。", bad = "私下反复猜别人的意思。" },
    ["111100"] = { name = "天雷无妄", state = "别耍小聪明的一天。", good = "按本分做事。", bad = "投机。" },
    ["111011"] = { name = "天风姤", state = "突然遇到什么，来得快。", good = "看清楚再靠近。", bad = "一时兴起就做决定。" },
    ["111010"] = { name = "天水讼", state = "有分歧，容易越说越僵。", good = "先把事实摆清楚再开口。", bad = "争输赢。" },
    ["111001"] = { name = "天山遁", state = "该退一步的时候。", good = "把范围缩小，先守住自己。", bad = "硬顶。" },
    ["111000"] = { name = "天地否", state = "气不顺，守住已经确定的东西。", good = "把今天的范围缩小一半。", bad = "在这种日子里做决定。" },
    -- 上兑
    ["110111"] = { name = "泽天夬", state = "该做个了断。", good = "把话说清楚，一次说完。", bad = "拖着不表态。" },
    ["110110"] = { name = "兑为泽", state = "说话顺，气氛好。", good = "把该说的话说了。", bad = "话说得太满。" },
    ["110101"] = { name = "泽火革", state = "该换了。", good = "把一个旧做法换掉。", bad = "为了变化而变化。" },
    ["110100"] = { name = "泽雷随", state = "跟着走比自己开路省力。", good = "顺着已有的节奏来。", bad = "为了不同而不同。" },
    ["110011"] = { name = "泽风大过", state = "担子太重，快压弯了。", good = "先卸掉一样东西。", bad = "再添一件。" },
    ["110010"] = { name = "泽水困", state = "资源紧，别硬撑。", good = "能省就省，先保住底线。", bad = "硬撑门面。" },
    ["110001"] = { name = "泽山咸", state = "有感应，容易被打动。", good = "认真回应一次。", bad = "被情绪推着走。" },
    ["110000"] = { name = "泽地萃", state = "人和事聚在一起。", good = "把该约的人约上。", bad = "聚了却没有议题。" },
    -- 上离
    ["101111"] = { name = "火天大有", state = "手上东西不少，别乱花。", good = "清点一下已有的资源。", bad = "因为富余就做多余的消耗。" },
    ["101110"] = { name = "火泽睽", state = "彼此看法不一样。", good = "先把共同点找出来。", bad = "非要统一口径。" },
    ["101101"] = { name = "离为火", state = "亮，但也烧得快。", good = "趁状态好把难的那件做了。", bad = "连轴转。" },
    ["101100"] = { name = "火雷噬嗑", state = "有硬骨头要咬。", good = "直接处理那个最卡的地方。", bad = "绕过去。" },
    ["101011"] = { name = "火风鼎", state = "在铸一件新东西。", good = "把一件事从头做扎实。", bad = "只搭架子。" },
    ["101010"] = { name = "火水未济", state = "收尾比开头难。", good = "把一件旧的做完。", bad = "同时开三个新头。" },
    ["101001"] = { name = "火山旅", state = "在外漂泊，没有根基。", good = "把临时的东西简单化。", bad = "这时候做大投入。" },
    ["101000"] = { name = "火地晋", state = "在往上走，节奏稳。", good = "把正在做的事推进一步。", bad = "为了快而省略步骤。" },
    -- 上震
    ["100111"] = { name = "雷天大壮", state = "力气大，容易用力过猛。", good = "把力气用在刀刃上。", bad = "跟人较劲。" },
    ["100110"] = { name = "雷泽归妹", state = "关系里位置不对等。", good = "先把边界说清楚。", bad = "委屈自己去迁就。" },
    ["100101"] = { name = "雷火丰", state = "到了最盛的时候。", good = "把成果记下来。", bad = "以为会一直这样。" },
    ["100100"] = { name = "震为雷", state = "动静大，容易被吓到。", good = "先稳住，再看清。", bad = "被第一反应带着跑。" },
    ["100011"] = { name = "雷风恒", state = "靠的是长期，不是一时。", good = "把习惯续上。", bad = "今天拼命明天躺平。" },
    ["100010"] = { name = "雷水解", state = "结开了，松一口气。", good = "把还没收尾的收掉。", bad = "刚松就松到底。" },
    ["100001"] = { name = "雷山小过", state = "小事可做，大事别碰。", good = "做小而具体的事。", bad = "这时候下大注。" },
    ["100000"] = { name = "雷地豫", state = "有点兴奋，容易上头。", good = "把兴奋写成一个具体计划。", bad = "通宵冲一件事。" },
    -- 上巽
    ["011111"] = { name = "风天小畜", state = "力气还小，先攒着。", good = "做小而确定的事。", bad = "硬推大项目。" },
    ["011110"] = { name = "风泽中孚", state = "心里有底，就别多解释。", good = "做一件说到做到的小事。", bad = "反复承诺。" },
    ["011101"] = { name = "风火家人", state = "内部的事要紧。", good = "把身边的秩序整理一下。", bad = "对亲近的人敷衍。" },
    ["011100"] = { name = "风雷益", state = "加进来的是好东西，别贪。", good = "挑一件真正需要的加进来。", bad = "什么都想要。" },
    ["011011"] = { name = "巽为风", state = "轻轻地推进，别硬来。", good = "用商量代替命令。", bad = "反复试探。" },
    ["011010"] = { name = "风水涣", state = "散了，需要重新聚。", good = "把注意力收回一件事上。", bad = "同时追好几件。" },
    ["011001"] = { name = "风山渐", state = "不是慢，是稳。", good = "按自己的节奏来。", bad = "拿别人的进度当刻度。" },
    ["011000"] = { name = "风地观", state = "适合看，不适合动手。", good = "把局面先看清楚。", bad = "边看边评价。" },
    -- 上坎
    ["010111"] = { name = "水天需", state = "在等一个时机。", good = "把等待的时间用在一件小事上。", bad = "空等。" },
    ["010110"] = { name = "水泽节", state = "要有节制。", good = "给自己定一条线。", bad = "因为一次顺就破例。" },
    ["010101"] = { name = "水火既济", state = "事情到了一个刚好的位置。", good = "把已经完成的记下来。", bad = "刚顺就想加量。" },
    ["010100"] = { name = "水雷屯", state = "刚起步，处处滞涩。", good = "先把最小的那一步走完。", bad = "急着要结果。" },
    ["010011"] = { name = "水风井", state = "有用的东西在下面，得去打。", good = "回头看看已有的积累。", bad = "到处找新的。" },
    ["010010"] = { name = "坎为水", state = "反复的坎，一个接一个。", good = "一件事一件事过。", bad = "同时处理所有问题。" },
    ["010001"] = { name = "水山蹇", state = "前面堵着，绕比撞快。", good = "换一条路试试。", bad = "硬闯。" },
    ["010000"] = { name = "水地比", state = "适合靠近，不适合独行。", good = "找一个人一起做点什么。", bad = "把自己关起来。" },
    -- 上艮
    ["001111"] = { name = "山天大畜", state = "攒着的力气该用了。", good = "把储备拿出来用一点。", bad = "继续囤着不动。" },
    ["001110"] = { name = "山泽损", state = "先减掉一件事，路才走得动。", good = "删一个计划外的任务。", bad = "一边累一边加码。" },
    ["001101"] = { name = "山火贲", state = "表面好看，里面还欠一口气。", good = "把细节收拾干净。", bad = "只做表面功夫。" },
    ["001100"] = { name = "山雷颐", state = "该养一养了。", good = "吃好睡好。", bad = "用消耗换进度。" },
    ["001011"] = { name = "山风蛊", state = "有旧账要清。", good = "挑一件拖了很久的事收尾。", bad = "又开新坑。" },
    ["001010"] = { name = "山水蒙", state = "雾还没散，看不清就先别急着断定。", good = "把要做的事写成一句话。", bad = "反复问同一个问题。" },
    ["001001"] = { name = "艮为山", state = "该停的时候要停。", good = "让自己停半天。", bad = "停不下来。" },
    ["001000"] = { name = "山地剥", state = "在往下掉，止住比救回来重要。", good = "先止损。", bad = "加仓。" },
    -- 上坤
    ["000111"] = { name = "地天泰", state = "今天是顺的，顺着走就行。", good = "把那件一直拖着的小事推一步。", bad = "因为顺就跳过检查。" },
    ["000110"] = { name = "地泽临", state = "有人来了，或者事近了。", good = "把要紧的话说清楚。", bad = "含糊应付。" },
    ["000101"] = { name = "地火明夷", state = "光被挡住了。", good = "低调做事，别急着表态。", bad = "这时候出头。" },
    ["000100"] = { name = "地雷复", state = "回来了，从最小的地方开始。", good = "做一个很小的开始。", bad = "一回来就加满。" },
    ["000011"] = { name = "地风升", state = "慢慢往上长。", good = "每天做一点。", bad = "想一步到位。" },
    ["000010"] = { name = "地水师", state = "需要有人拿主意。", good = "把分工写下来。", bad = "局面没看清就动。" },
    ["000001"] = { name = "地山谦", state = "低一点，反而走得远。", good = "把功劳分出去一点。", bad = "这时候讲排场。" },
    ["000000"] = { name = "坤为地", state = "适合承接，不适合起头。", good = "把手头的事做扎实。", bad = "今天做重大决定。" },
}

-- 通用兜底（理论上不该用到：64 卦已全覆盖；留着防表缺口）
Fortune.GENERIC = {
    state = "今天没有特别的卦象。",
    good = "按自己的节奏走。",
    bad = "为了等一个征兆而停下来。",
}

-- ---------------------------------------------------------------- 摇卦
local function DefaultRand()
    return math.random()
end

--- 摇一卦
---@param rand fun():number|nil
---@return table lines 1..6，每项 { yang=bool, moving=bool, value=6/7/8/9 }
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

-- 取三位 key：初/中/上（下卦是 1,2,3；上卦是 4,5,6）
local function TriKey(lines, from)
    local s = ""
    for i = from, from + 2 do
        s = s .. (lines[i].yang and "1" or "0")
    end
    return s
end

--- 由六爻算出上下卦与卦名
function Fortune.Read(lines)
    local lowerKey = TriKey(lines, 1)
    local upperKey = TriKey(lines, 4)
    local hexKey = upperKey .. lowerKey
    return {
        lowerKey = lowerKey, upperKey = upperKey,
        lower = Fortune.TRIGRAMS[lowerKey], upper = Fortune.TRIGRAMS[upperKey],
        hexKey = hexKey, hex = Fortune.HEXAGRAMS[hexKey],
    }
end

--- 有动爻时算出变卦（老阳变阴、老阴变阳）
---@return table|nil  nil 表示六爻全静
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
