-- DevHealthDay.lua — 健康任务跨日不复位 / 失效的回归
local Save = require "Save"
local S = require "State"

local fails = 0
local function check(name, cond, detail)
    if cond then
        print("[HealthDay] OK   " .. name)
    else
        fails = fails + 1
        print("[HealthDay] FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
    end
end

function Start()
    local d = Save.Fresh()
    S.data = d

    -- 模拟「昨天」：满水、已早睡、已领步数、步数 12000
    d.dayKey = "2000-01-01"
    d.todaySteps = 12000
    d.claimed = true
    d.waterMl = Save.WaterGoal()
    d.sleptEarly = true
    d.earlySleepPending = true

    -- 跨天：RollDay 应把当日任务全部复位，但早睡奖励要留到下次领取
    Save.RollDay(d)
    check("跨天后 dayKey 是今天", d.dayKey == Save.TodayKey(d), d.dayKey)
    check("跨天后饮水清零", (d.waterMl or 0) == 0, d.waterMl)
    check("跨天后早睡复位", d.sleptEarly == false, tostring(d.sleptEarly))
    check("跨天后可再次领取", d.claimed == false, tostring(d.claimed))
    check("早睡待领奖励保留", d.earlySleepPending == true, tostring(d.earlySleepPending))

    -- 再次跨天（中间没领取）：早睡奖励不能丢
    Save.NextDay(d)
    check("第二日早睡奖励仍在", d.earlySleepPending == true, tostring(d.earlySleepPending))

    -- 跨天后饮水任务可用
    local before = d.waterMl or 0
    Save.AddWater(d)
    check("跨天后可以继续记录饮水", (d.waterMl or 0) > before, d.waterMl)
    check("跨天后饮水不满不达标", Save.WaterMet(d) == false)

    -- 跨天后早睡任务可用
    local okSleep = Save.CheckSleep(d)
    check("跨天后可以记录早睡", okSleep == true)
    check("重复记录返回 false", Save.CheckSleep(d) == false)

    -- 跨天后领步数：早睡奖励生效，且步数来自本次输入
    Save.NextDay(d)
    local gain, _, streak = Save.Claim(d, 12000)
    check("跨天后领取有生息", gain > 0, gain)
    check("领取后标记已领", d.claimed == true)
    check("早睡奖励已结算", d.earlySleepPending == false, tostring(d.earlySleepPending))
    check("经验含早睡加成", d.exp >= gain + math.floor(gain * 0.30), d.exp)

    -- 同一天重复领取不再发奖励
    local gain2 = Save.Claim(d, 12000)
    check("同日重复领取无收益", gain2 == 0, gain2)

    -- 白天跨过 0 点（不点任何按钮）：反复调用 RollDay 不能把今天的记录又清掉
    d.waterMl = 750
    d.sleptEarly = true
    Save.RollDay(d)
    check("同日 RollDay 不清饮水", (d.waterMl or 0) == 750, d.waterMl)
    check("同日 RollDay 不清早睡", d.sleptEarly == true, tostring(d.sleptEarly))

    print(string.format("[HealthDay] done, failures = %d", fails))
end
