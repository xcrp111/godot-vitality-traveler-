-- Economy.lua — 经济系统核心（v2 · 双币线）
--
-- 口径来源：《描述表格_经济系统优化版》第 0/1/2/4/5/7 表
--   · 精粹（essence）：每日能量消耗结算产出。只用于局外养成（角色升级、局外商店、
--     宠物/农场/孵化）。每日 5:00 结算一次，峰值 = 累计精粹 × 连击倍率 + 每日固定项。
--   · 金币（gold）：局内房间掉落产出。只用于局内商店。跨关累积，上限 = 账号等级 × 300。
--   两条线互不换算、互不互通，任何地方都不要把两者相加。
--
-- 每日精粹公式（2 表定稿）：
--   累计精粹 = Σ 每个百分点按「它所在档位的单价」计费（正常范围 / 超重肥胖两条阶梯）
--   日总精粹 = 累计精粹 × 连击倍率 + 每日基础 3 +（活力满满额外 5，仅连续 >7 天且当日 ≥10%）
--   连击倍率只乘累计精粹：连续 3~7 天 ×2（健康），连续 >7 天 ×3（活力满满），未达标 ×1。

local Config = require "Config"

local Economy = {}

local E = Config.Economy

-- ---------------------------------------------------------------- 体脂率状态
---@param data table
---@return number
function Economy.BodyFat(data)
    local bf = data and data.bodyFat
    if type(bf) ~= "number" then bf = 0 end
    return math.max(0, math.min(60, bf))
end

--- 正常范围 / 超重肥胖：两条不同的单价阶梯
---@param data table
---@return string "normal"|"over"
function Economy.BodyState(data)
    return Economy.BodyFat(data) >= E.overweightFat and "over" or "normal"
end

---@param data table
---@return string
function Economy.BodyStateName(data)
    return Economy.BodyState(data) == "over" and "超重肥胖" or "正常范围"
end

---@param data table
---@param delta number
---@return number 调整后的体脂率
function Economy.AddBodyFat(data, delta)
    data.bodyFat = math.max(0, math.min(60, math.floor(Economy.BodyFat(data) + (delta or 0))))
    return data.bodyFat
end

-- ---------------------------------------------------------------- 体脂率 → 精粹阶梯
-- 每 1% 都按所在档单价计费并跨档累加（不是「末档单价 × 总百分比」）
---@param percent number 超静息消耗百分比
---@param state string|nil "normal"|"over"
---@return integer
function Economy.TierEssence(percent, state)
    percent = math.floor(math.max(0, percent or 0))
    local key = (state == "over") and "over" or "normal"
    local total, done = 0, 0
    for _, t in ipairs(E.tiers) do
        local up = t.upTo
        if up == math.huge or percent <= up then
            local n = percent - done
            if n > 0 then total = total + n * t[key] end
            break
        end
        local n = up - done
        if n > 0 then total = total + n * t[key] end
        done = up
    end
    return total
end

--- 连击倍率：只乘「累计精粹」，且当日必须达标（≥10%）
---@param streak integer
---@param percent number
---@return integer
function Economy.StreakMult(streak, percent)
    if (percent or 0) < E.streakGatePercent then return 1 end
    streak = math.floor(streak or 0)
    if streak >= E.vitalityDays then return E.vitalityMult end
    if streak >= E.healthyDays then return E.healthyMult end
    return 1
end

--- 每日固定项：基础 3 +（活力满满额外 5），不参与连击倍率
---@param streak integer
---@param percent number
---@return integer
function Economy.DailyFixed(streak, percent)
    local total = E.baseEssence
    if (percent or 0) >= E.streakGatePercent and math.floor(streak or 0) >= E.vitalityDays then
        total = total + E.vitalityBonus
    end
    return total
end

--- 连击档位名（给界面用）
---@param streak integer
---@param percent number
---@return string
function Economy.StreakName(streak, percent)
    if (percent or 0) < E.streakGatePercent then return "未达标" end
    if math.floor(streak or 0) >= E.vitalityDays then return "活力满满" end
    if math.floor(streak or 0) >= E.healthyDays then return "健康" end
    return "未达标"
end

--- 每日精粹结算（纯函数，不改存档）
---@param data table
---@param steps integer
---@param streak integer 结算后的连续天数
---@return integer total, table detail
function Economy.DailyEssence(data, steps, streak)
    local pct = Config.ActivityPercent(steps or 0)
    local state = Economy.BodyState(data)
    local tiered = Economy.TierEssence(pct, state)
    local mult = Economy.StreakMult(streak, pct)
    local fixed = Economy.DailyFixed(streak, pct)
    return tiered * mult + fixed, {
        percent = pct,
        state = state,
        tiered = tiered,
        mult = mult,
        fixed = fixed,
    }
end

--- 预览用：不结算，只算「如果现在领取能拿多少」
---@param data table
---@param steps integer
---@param nextStreak integer|nil
---@return integer total, table detail
function Economy.PreviewDaily(data, steps, nextStreak)
    return Economy.DailyEssence(data, steps, nextStreak or (data and data.streak) or 0)
end

-- ---------------------------------------------------------------- 账号等级（累计获得精粹 · 纯里程碑）
-- 表内 22 级；22 级之后不封顶：每级沿用 21→22 的增量（accountStepAfterMax）继续往上算
---@param data table
---@return integer
function Economy.AccountLevel(data)
    local earned = math.floor((data and data.essenceEarned) or 0)
    local lastIdx = #E.accountThresholds
    local last = E.accountThresholds[lastIdx] or 0
    local step = E.accountStepAfterMax or 2000
    if earned >= last then
        return lastIdx + math.floor((earned - last) / step)
    end
    local lv = 1
    for i = 2, lastIdx do
        if earned >= E.accountThresholds[i] then lv = i else break end
    end
    return lv
end

--- 账号等级表内级数（22）
---@return integer
function Economy.AccountMaxLevel()
    return #E.accountThresholds
end

--- 该等级对应的累计精粹基线（进度条用；22 级之后同样按 +2000 延伸）
---@param lv integer
---@return integer
function Economy.AccountBase(lv)
    local lastIdx = #E.accountThresholds
    lv = math.max(1, math.floor(lv or 1))
    if lv <= lastIdx then
        return lv > 1 and E.accountThresholds[lv] or 0
    end
    return E.accountThresholds[lastIdx] + (lv - lastIdx) * (E.accountStepAfterMax or 2000)
end

--- 下一级门槛与还差多少精粹（没有封顶）
---@param data table
---@return integer need, integer remain
function Economy.AccountNext(data)
    local lv = Economy.AccountLevel(data)
    local lastIdx = #E.accountThresholds
    local need
    if lv < lastIdx then
        need = E.accountThresholds[lv + 1]
    else
        need = E.accountThresholds[lastIdx] + (lv + 1 - lastIdx) * (E.accountStepAfterMax or 2000)
    end
    local earned = math.floor((data and data.essenceEarned) or 0)
    return need, math.max(0, need - earned)
end

-- ---------------------------------------------------------------- 金币（局内）
---@param data table
---@return integer
function Economy.Gold(data)
    return math.floor((data and data.gold) or 0)
end

--- 金币储存上限 = 账号等级 × 300 × 产出倍率
---@param data table
---@return integer
function Economy.GoldCap(data)
    return Economy.AccountLevel(data) * E.goldCapPerAccountLevel * Economy.GoldIncomeMul()
end

--- 关卡内金币产出倍率
---@return number
function Economy.GoldIncomeMul()
    return E.goldIncomeMul or 1
end

--- 把一次金币收入按倍率放大（掉落 / 事件奖励 / 跳过奖励都走这里）
---@param n number
---@return integer
function Economy.ScaleGoldIncome(n)
    return math.max(1, math.floor((n or 0) * Economy.GoldIncomeMul() + 0.5))
end

--- 加金币（受储存上限约束），返回实际入账数量
---@param data table
---@param n number
---@return integer gained
function Economy.AddGold(data, n)
    if not data then return 0 end
    n = math.floor((n or 0) + 0.5)
    if n <= 0 then return 0 end
    local cap = Economy.GoldCap(data)
    local cur = Economy.Gold(data)
    local after = math.min(cap, cur + n)
    data.gold = after
    return after - cur
end

--- 花金币，成功返回 true
---@param data table
---@param n number
---@return boolean
function Economy.SpendGold(data, n)
    if not data then return false end
    n = math.floor((n or 0) + 0.5)
    if n <= 0 then return true end
    local cur = Economy.Gold(data)
    if cur < n then return false end
    data.gold = cur - n
    return true
end

--- 金币是否已顶到储存上限
---@param data table
---@return boolean
function Economy.GoldFull(data)
    return Economy.Gold(data) >= Economy.GoldCap(data)
end

--- 清空金币（每次开新关卡时调用；无尽模式不调）
---@param data table
---@return integer 清掉的数量
function Economy.ResetGold(data)
    if not data then return 0 end
    local had = Economy.Gold(data)
    data.gold = 0
    return had
end

-- ---------------------------------------------------------------- 精粹（局外）
---@param data table
---@return integer
function Economy.Essence(data)
    return math.floor((data and data.essence) or 0)
end

--- 加精粹；默认同时计入「累计获得」（账号等级里程碑）
---@param data table
---@param n number
---@param countEarned boolean|nil 传 false 表示不计入累计获得（例如开发者补币）
---@return integer gained, integer levelsUp
function Economy.AddEssence(data, n, countEarned)
    if not data then return 0, 0 end
    n = math.floor((n or 0) + 0.5)
    if n <= 0 then return 0, 0 end
    data.essence = Economy.Essence(data) + n
    local levelsUp = 0
    if countEarned ~= false then
        data.essenceEarned = math.floor((data.essenceEarned or 0) + n)
        levelsUp = Economy.SyncAccountLevel(data)
    end
    return n, levelsUp
end

--- 花精粹，成功返回 true
---@param data table
---@param n number
---@return boolean
function Economy.SpendEssence(data, n)
    if not data then return false end
    n = math.floor((n or 0) + 0.5)
    if n <= 0 then return true end
    local cur = Economy.Essence(data)
    if cur < n then return false end
    data.essence = cur - n
    return true
end

--- 按「累计获得精粹」重算账号等级；每升 1 级发 1 技能点
---@param data table
---@return integer levelsUp
function Economy.SyncAccountLevel(data)
    if not data then return 0 end
    data.essenceEarned = math.floor(data.essenceEarned or 0)
    local lv = Economy.AccountLevel(data)
    local had = math.floor(data.accountLevel or 1)
    if had < 1 then had = 1 end
    data.accountLevel = lv
    if lv <= had then return 0 end
    local up = lv - had
    data.skillPoints = (data.skillPoints or 0) + up * E.skillPointPerLevel
    return up
end

return Economy
