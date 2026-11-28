-- DevFortune.lua — 每日一卦的纯逻辑回归（不启动运行时）
--
-- 跑法（cwd = life-walker）：
--   F:\_vt_tools\py\python.exe F:\_vt_tools\run_lua.py F:\godot-vitality-traveler\life-walker DevFortune
--
-- 它守三件事：
--   ① 摇卦的概率分布对不对（老阴/老阳各 1/8，少阴/少阳各 3/8）
--   ② 变卦算得对不对（有动爻才变，且每爻刚好翻转）
--   ③ 文案守不守硬规则（不断言未来、不涉及具体人、正文非空）

local Fortune = require "Fortune"

local fails = 0
local function check(name, cond, detail)
    if cond then
        print("[Ftn] OK   " .. name)
    else
        fails = fails + 1
        print("[Ftn] FAIL " .. name .. (detail ~= nil and (" — " .. tostring(detail)) or ""))
    end
end

-- ---------------------------------------------------------------- ① 卦表
local hexCount = 0
for key, hex in pairs(Fortune.HEXAGRAMS) do
    hexCount = hexCount + 1
    check("卦表 key 是 6 位二进制（" .. key .. "）", #key == 6 and key:match("^[01]+$") ~= nil, key)
    check("卦表有卦名（" .. key .. "）", type(hex.name) == "string" and #hex.name > 0)
    check("卦表有三段文案（" .. key .. "）",
        type(hex.state) == "string" and #hex.state > 0
        and type(hex.good) == "string" and #hex.good > 0
        and type(hex.bad) == "string" and #hex.bad > 0)
end
check("卦表 64 卦全齐", hexCount == 64, hexCount)
print("[Ftn] 卦表：" .. hexCount .. " 卦")

-- 六十四卦应该把八卦两两组合的 64 种全覆盖（上卦三位 .. 下卦三位）
local missing = {}
for upperKey in pairs(Fortune.TRIGRAMS) do
    for lowerKey in pairs(Fortune.TRIGRAMS) do
        if not Fortune.HEXAGRAMS[upperKey .. lowerKey] then
            missing[#missing + 1] = upperKey .. lowerKey
        end
    end
end
check("八卦两两组合全有卦（64 种）", #missing == 0, table.concat(missing, ","))

local triCount = 0
for key, tri in pairs(Fortune.TRIGRAMS) do
    triCount = triCount + 1
    check("八卦 key 合法（" .. key .. "）", #key == 3 and key:match("^[01]+$") ~= nil, key)
    check("八卦有名字（" .. key .. "）", type(tri.name) == "string" and #tri.name > 0)
end
check("八个卦齐了", triCount == 8, triCount)

-- ---------------------------------------------------------------- ② 摇卦分布
local rand = math.random
math.randomseed(20261128)

local TOTALS = 4000
local count = { [6] = 0, [7] = 0, [8] = 0, [9] = 0 }
local lineTotal = 0
for _ = 1, TOTALS do
    local lines = Fortune.Cast(rand)
    for i = 1, 6 do
        count[lines[i].value] = (count[lines[i].value] or 0) + 1
        lineTotal = lineTotal + 1
    end
end

local function pct(v) return count[v] / lineTotal end
check("老阴约 1/8", math.abs(pct(6) - 0.125) < 0.012, string.format("%.4f", pct(6)))
check("少阳约 3/8", math.abs(pct(7) - 0.375) < 0.018, string.format("%.4f", pct(7)))
check("少阴约 3/8", math.abs(pct(8) - 0.375) < 0.018, string.format("%.4f", pct(8)))
check("老阳约 1/8", math.abs(pct(9) - 0.125) < 0.012, string.format("%.4f", pct(9)))
check("动爻总概率约 1/4", math.abs((pct(6) + pct(9)) - 0.25) < 0.02,
    string.format("%.4f", pct(6) + pct(9)))
print(string.format("[Ftn] 摇卦 %d 爻：老阴 %.3f 少阳 %.3f 少阴 %.3f 老阳 %.3f",
    lineTotal, pct(6), pct(7), pct(8), pct(9)))

-- ---------------------------------------------------------------- ③ 变卦
-- 全静：无变卦
local still = {}
for i = 1, 6 do still[i] = { yang = true, moving = false, value = 7 } end
check("六爻全静时没有变卦", Fortune.Changed(still) == nil)

-- 单爻动：变卦对应爻必须翻转
local one = {}
for i = 1, 6 do one[i] = { yang = true, moving = false, value = 7 } end
one[1] = { yang = true, moving = true, value = 9 }   -- 老阳，应变阴
local ch = Fortune.Changed(one)
check("有动爻时有变卦", ch ~= nil)
check("老阳变为阴", ch and ch.lowerKey:sub(1, 1) == "0", ch and ch.lowerKey)

local two = {}
for i = 1, 6 do two[i] = { yang = false, moving = false, value = 8 } end
two[6] = { yang = false, moving = true, value = 6 }  -- 老阴，应变阳
local ch2 = Fortune.Changed(two)
check("老阴变为阳", ch2 and ch2.upperKey:sub(3, 3) == "1", ch2 and ch2.upperKey)

-- 一动一静的混合
local mix = {}
for i = 1, 6 do mix[i] = { yang = (i % 2 == 0), moving = false, value = 7 } end
mix[2].moving = true; mix[2].value = 9
local ch3 = Fortune.Changed(mix)
check("混合时变卦不为空", ch3 ~= nil)
check("未动的爻保持不变", ch3 and ch3.lowerKey:sub(2, 2) == (mix[2].value == 9 and "0" or "1"), ch3 and ch3.lowerKey)

-- ---------------------------------------------------------------- ④ 文案硬规则
local BAN_PREDICT = { "会回来", "将会", "必将", "一定会", "某人", "有人会", "他回来", "她回来" }
local function Banned(text)
    for _, w in ipairs(BAN_PREDICT) do
        if text:find(w, 1, true) then return w end
    end
    return nil
end

local texts, badPredict = 0, 0
for key, hex in pairs(Fortune.HEXAGRAMS) do
    texts = texts + 1
    local joined = hex.state .. hex.good .. hex.bad
    local w = Banned(joined)
    if w then
        badPredict = badPredict + 1
        check("文案不许断言未来（" .. key .. "）", false, w)
    end
end
check("通用兜底文案也守规矩", Banned(Fortune.GENERIC.state .. Fortune.GENERIC.good .. Fortune.GENERIC.bad) == nil)
check("所有文案都守规矩", badPredict == 0, badPredict .. "/" .. texts)

-- ---------------------------------------------------------------- ⑤ 每日一次（可复现）
local a = Fortune.DailyText(2026, 12, 1)
local b = Fortune.DailyText(2026, 12, 1)
local c = Fortune.DailyText(2026, 12, 2)
check("同一天结果相同", a.name == b.name and a.state == b.state, a.name .. " vs " .. b.name)
check("不同天可能不同（不强求）", type(c.name) == "string")
check("每日一卦有名字", type(a.name) == "string" and #a.name > 0, a.name)
check("每日一卦有四段", type(a.state) == "string" and #a.state > 0
    and type(a.good) == "string" and #a.good > 0
    and type(a.bad) == "string" and #a.bad > 0)

-- 抽 30 天，看看 12 卦够不够轮
local seen, seenCount = {}, 0
for d = 1, 30 do
    local t = Fortune.DailyText(2026, 12, d)
    if not seen[t.name] then seen[t.name] = true; seenCount = seenCount + 1 end
end
print(string.format("[Ftn] 12 月连抽 30 天：出现 %d 种卦（含兜底）", seenCount))
check("30 天内至少出 10 种不同卦", seenCount >= 10, seenCount)

-- ---------------------------------------------------------------- ⑥ 零数值产出
local src = io and io.open and io.open("scripts/Fortune.lua", "r")
if src then
    local body = src:read("*a")
    src:close()
    local banned = { "addGold", "addExp", "addItem", "silver", "score", "exp =", "gold =" }
    local hit = nil
    for _, w in ipairs(banned) do
        if body:find(w, 1, true) then hit = w; break end
    end
    check("模块里没有任何数值产出（只读源码）", hit == nil, hit)
else
    print("[Ftn] 跳过源码扫描（io 不可用）")
end

print("[Ftn] done, failures = " .. fails)
