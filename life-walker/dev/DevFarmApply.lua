-- DevFarmApply.lua — 果实效果在「真实开局流程」里是否真的生效
-- 之前凤凰花只是在 Farm.ApplyRunBuffs 里加了 p.revive，
-- 紧接着 Run.Recompute 用 mods 重算，把 p.revive 覆盖回 0，等于没生效。
local Config = require "Config"
local Save = require "Save"
local S = require "State"
local Farm = require "Farm"
local Run = require "Run"

local fails = 0
local function check(name, cond, detail)
    if cond then
        print("[FarmApply] OK   " .. name)
    else
        fails = fails + 1
        print("[FarmApply] FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
    end
end

local function freshFarm()
    S.data = Save.Fresh()
    local d = S.data
    d.stageCleared = 5
    Farm.Ensure(d)
    return d
end

local function giveFruit(d, id, n)
    local f = Farm.Ensure(d)
    f.fruits[id] = (f.fruits[id] or 0) + (n or 5)
end

local function equipAll(d, ids)
    local f = Farm.Ensure(d)
    f.equipped = {}
    for _, id in ipairs(ids) do
        giveFruit(d, id, 3)
        f.equipped[#f.equipped + 1] = id
    end
end

function Start()
    -- 1) 凤凰花：走完整 Run.Start 后仍然有复活次数
    local d = freshFarm()
    equipAll(d, { "phoenix" })
    Run.Start(1, true)
    check("凤凰花：开局后有复活次数", (S.run.player.revive or 0) >= 1, S.run.player.revive)
    check("凤凰花：复活比例 50%", math.abs((S.run.player.revivePct or 0) - 0.5) < 0.001,
        S.run.player.revivePct)
    check("凤凰花：果实已被消耗", (Farm.Ensure(d).fruits.phoenix or 0) < 3,
        Farm.Ensure(d).fruits.phoenix)

    -- 2) 火灵果：攻击 +10%
    d = freshFarm()
    equipAll(d, { "fire" })
    local baseAtk = Run.NewPlayer(Save.ClassLevel(d)).baseAtk
    Run.Start(1, true)
    local atk = S.run.player.atk
    check("火灵果：攻击 +10%", atk > baseAtk * 1.09, string.format("%.1f -> %.1f", baseAtk, atk))

    -- 3) 冰晶草：护盾上限 +15%
    d = freshFarm()
    equipAll(d, { "ice" })
    local baseShield = Run.NewPlayer(Save.ClassLevel(d)).baseShield
    Run.Start(1, true)
    check("冰晶草：护盾上限 +15%", S.run.player.maxShield > baseShield,
        string.format("%d -> %d", baseShield, S.run.player.maxShield))

    -- 4) 雷击木：冷却 -10%
    d = freshFarm()
    equipAll(d, { "thunder" })
    Run.Start(1, true)
    check("雷击木：CDR +10%", (S.run.player.mods.cdrPct or 0) >= 0.099, S.run.player.mods.cdrPct)

    -- 5) 生命之花：生命上限 +20%
    d = freshFarm()
    equipAll(d, { "life" })
    local baseHp = Run.NewPlayer(Save.ClassLevel(d)).baseHp
    Run.Start(1, true)
    check("生命之花：生命 +20%", S.run.player.maxHp > baseHp * 1.19,
        string.format("%d -> %d", baseHp, S.run.player.maxHp))

    -- 6) 生息花：开局 +50 血尘
    d = freshFarm()
    equipAll(d, { "gold" })
    Run.Start(1, true)
    check("生息花：开局 +50 血尘", (S.run.silver or 0) >= 50, S.run.silver)

    -- 7) 时空藤：奖励重随 +3
    d = freshFarm()
    equipAll(d, { "timevine" })
    Run.Start(1, true)
    check("时空藤：重随 +3", (S.run.guildRerolls or 0) >= 3, S.run.guildRerolls)

    -- 8) 早睡：次日领取经验 +30%
    d = freshFarm()
    d.exp = 0
    d.claimed = false
    d.dayKey = "2000-01-01"
    d.todaySteps = 10000
    Save.CheckSleep(d)
    check("早睡打卡成功", d.earlySleepPending == true)
    local exp0 = d.exp
    local g, _, _, _, _, extra = Save.Claim(d, 10000)
    local gained = d.exp - exp0
    check("早睡：领取时经验有加成", (extra or 0) > 0, extra)
    check("早睡：加成 = 基础经验 30%",
        math.floor(g * Config.Health.earlySleepExpPct + 0.5) == (extra or -1),
        string.format("extra=%s g=%s", tostring(extra), tostring(g)))
    check("早睡：总经验 = 基础 + 加成", gained == g + (extra or 0),
        string.format("gained=%d g=%d extra=%s", gained, g, tostring(extra)))
    check("早睡：奖励只结算一次", d.earlySleepPending == false)

    print(string.format("[FarmApply] done, failures = %d", fails))
end
