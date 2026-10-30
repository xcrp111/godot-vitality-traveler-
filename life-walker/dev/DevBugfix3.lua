-- DevBugfix3.lua — 2026-10-30 测试反馈（5 bug + 4 优化）回归
local Config = require "Config"
local Save = require "Save"
local S = require "State"
local Run = require "Run"
local Combat = require "Combat"

local fails = 0
local function check(name, cond, detail)
    if cond then
        print("[Fix3] OK   " .. name)
    else
        fails = fails + 1
        print("[FIX3] FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
    end
end

local function NewCombat(class, loadout)
    S.data = Save.Load()
    Save.SetClass(S.data, class)
    Save.SetClassLevel(S.data, 10)
    Config.SetClass(class)
    Run.Start(3, true)
    S.run.loadout = loadout or { 1, 2, 3 }
    local cs = Combat.Start(S.run, "standard", 1)
    S.screen = "combat"
    cs.enemies = {}
    cs.walls = {}
    cs.waves = { {} }
    cs.waveIndex = 1
    cs.player.x, cs.player.y = 640, 400
    cs.player.shield = 0
    cs.player.crit = 0
    return cs
end

function Start()
    -- ============ 1. 回马枪：后撤/前刺共用施法快照 ============
    local cs = NewCombat("spearman", { 1, 2, 5 })
    local p = cs.player
    p.x, p.y = 640, 400
    cs.facing = 0
    Combat.SpawnWave(cs, { minion = 1 })
    local front = cs.enemies[1]
    front.x, front.y = 820, 400
    front.hp, front.maxHp = 99999, 99999
    Combat.SpawnWave(cs, { minion = 1 })
    local side = cs.enemies[2]
    side.x, side.y = 380, 120   -- 超出 360 索敌范围，不会被 AimAt 抢走朝向
    side.hp, side.maxHp = 99999, 99999
    Combat.CastSkill(3)                      -- loadout[3] = 回马枪
    cs.facing = math.pi / 2                  -- 中途转向（模拟推摇杆）
    Combat.Update(0.16)
    check("1 中途转向不影响前刺方向（正前方命中）", front.hp < 99999, front.hp)
    check("1 转向后也不会打到侧面", side.hp == 99999, side.hp)

    -- ============ 2. 死亡：浮点残血也要判死 ============
    cs = NewCombat("swordsman")
    p = cs.player
    p.hp = 0.0001
    p.shield = 0
    Combat.DamagePlayer(cs, 0.2)             -- 小于 0.5 被抹平
    check("2 残血不足 1 点直接判死", cs.player.hp == 0 and S.screen == "gameover",
        tostring(cs.player.hp) .. " / " .. tostring(S.screen))

    cs = NewCombat("swordsman")
    p = cs.player
    p.hp = 0.4
    p.shield = 0
    Combat.DamagePlayer(cs, 0.1)
    check("2 0.4 血挨极小伤害也判死", S.screen == "gameover", S.screen)

    cs = NewCombat("swordsman")
    p = cs.player
    p.hp = 30
    p.shield = 0
    Combat.DamagePlayer(cs, 5)
    check("2 正常掉血不会误判死亡", S.screen == "combat" and cs.player.hp == 25,
        cs.player.hp)

    -- ============ 3. 吸血：单次上限改为 100%，普攻/技能分开 ============
    cs = NewCombat("swordsman")
    p = cs.player
    p.lifesteal = 1.5
    p.hp = 10
    Combat.SpawnWave(cs, { minion = 1 })
    local e = cs.enemies[1]
    e.hp, e.maxHp = 99999, 99999
    local hp0 = p.hp
    Combat.HitEnemy(cs, e, 10, false, true, true, "basic")
    check("3 单次回血不超过本次伤害（100% 上限）", math.abs((p.hp - hp0) - 10) < 0.01, p.hp - hp0)

    -- 多目标仍然各回各的
    cs = NewCombat("swordsman")
    p = cs.player
    p.lifesteal = 0.5
    p.hp = 10
    Combat.SpawnWave(cs, { minion = 2 })
    for _, en in ipairs(cs.enemies) do
        en.hp, en.maxHp = 99999, 99999
    end
    hp0 = p.hp
    for _, en in ipairs(cs.enemies) do
        Combat.HitEnemy(cs, en, 10, false, true, true, "basic")
    end
    check("3 多目标可以各回各的（续航）", (p.hp - hp0) > 8, p.hp - hp0)

    -- 普攻吸血 / 技能吸血分开
    cs = NewCombat("swordsman")
    p = cs.player
    p.lifesteal = 0
    p.flags.basicLifesteal = 0.5
    p.hp = 10
    Combat.SpawnWave(cs, { minion = 1 })
    e = cs.enemies[1]
    e.hp, e.maxHp = 99999, 99999
    hp0 = p.hp
    Combat.HitEnemy(cs, e, 10, false, true, true, "basic")
    local basicHeal = p.hp - hp0
    hp0 = p.hp
    Combat.HitEnemy(cs, e, 10, true, true, true, "skill")
    local skillHeal = p.hp - hp0
    check("3 普攻吸血只吃普攻", basicHeal > 4 and skillHeal < 0.01,
        string.format("basic=%.1f skill=%.1f", basicHeal, skillHeal))

    -- ============ 4. 鬼剑术：满层放剑气并清空剑意 ============
    cs = NewCombat("swordsman")
    p = cs.player
    Run.GrantBuff(p, { id = "sw_c_oni", name = "鬼剑术", desc = "", rarity = "color",
        classBuff = true, mod = {}, flag = { oni = 1 } })
    p.intent = 5
    cs.windWaves = {}
    Combat.BasicAttack(cs)
    check("4 满层普攻放剑气", #cs.windWaves == 1, #cs.windWaves)
    check("4 放完剑气清空剑意", p.intent == 0, p.intent)
    Combat.BasicAttack(cs)
    check("4 清空后不会连着放第二道", #cs.windWaves == 1, #cs.windWaves)

    -- ============ 5. 断势重击 + 小幅震荡 同时生效 ============
    cs = NewCombat("swordsman", { 1, 2, 3 })
    p = cs.player
    Run.GrantBuff(p, { id = "sw_b_break", name = "断势重击", desc = "", rarity = "blue",
        classBuff = true, mod = {}, flag = { triplePct = 0.13, tripleWind = 1 } })
    Run.GrantBuff(p, { id = "sw_b_quake", name = "小幅震荡", desc = "", rarity = "blue",
        classBuff = true, mod = {}, flag = { triplePct = 0.12, tripleKnock = 1 } })
    Combat.SpawnWave(cs, { minion = 1 })
    e = cs.enemies[1]
    e.x, e.y = p.x + 60, p.y
    e.hp, e.maxHp = 99999, 99999
    e.speed = 0                 -- 冻住 AI，只观察击退位移
    cs.windWaves = {}
    local ex = e.x
    local maxX = e.x
    Combat.CastSkill(1)
    for _ = 1, 45 do
        Combat.Update(1 / 60)
        if e.x > maxX then maxX = e.x end
    end
    check("5 剑气波仍然生成（断势重击）", #(cs.windWaves or {}) >= 1, #(cs.windWaves or {}))
    check("5 近战第三段也打到（不会只剩剑气）", e.hp < 99999, e.hp)
    check("5 击退生效（小幅震荡）", maxX > ex + 20, string.format("%.0f -> max %.0f", ex, maxX))

    -- ============ 6. 闪影突进：点按瞬发 + 拖动选向 ============
    cs = NewCombat("swordsman", { 2, 1, 3 })
    p = cs.player
    p.x, p.y = 640, 400
    cs.facing = 0
    local bx, by = Combat.CtrlPos("skill1", 1080, 624, 36)
    local down = Combat.AimPointer("down", bx, by, 61)
    check("6 闪影突进也能进入瞄准态", down and cs.aim ~= nil)
    Combat.AimPointer("up", bx, by, 61)          -- 轻点：不拖动
    check("6 轻点立即释放且不锁方向", cs.aim == nil and (p.cooldowns[2] or 0) > 0 and cs.aimLock == nil,
        tostring(p.cooldowns[2]))

    cs = NewCombat("swordsman", { 2, 1, 3 })
    p = cs.player
    p.x, p.y = 640, 400
    cs.facing = 0
    Combat.AimPointer("down", bx, by, 62)
    Combat.AimPointer("move", bx, by - 90, 62)   -- 往上拖：不用等 0.22 秒
    local aimAngle = cs.aim.angle
    Combat.AimPointer("up", bx, by - 90, 62)
    check("6 拖动即可选方向（无需长按）", math.abs(cs.facing - aimAngle) < 1e-6,
        string.format("%.2f vs %.2f", cs.facing, aimAngle))
    check("6 选的方向是向上", math.abs(cs.facing + math.pi / 2) < 0.05, cs.facing)

    -- ============ 7. 瞬影连斩：两段有区分 ============
    cs = NewCombat("swordsman", { 6, 1, 3 })
    p = cs.player
    p.x, p.y = 640, 400
    cs.facing = 0
    Combat.CastSkill(1)                          -- loadout[1] = 瞬影连斩
    check("7 第一段短促（0.10 秒）", cs.dash and math.abs(cs.dash.t - 0.10) < 1e-6,
        cs.dash and cs.dash.t)
    check("7 第一段不亮", cs.dash.bright ~= true, tostring(cs.dash.bright))
    for _ = 1, 20 do Combat.Update(1 / 60) end    -- 0.33 秒，触发第二段
    check("7 第二段更亮", cs.dash and cs.dash.bright == true, tostring(cs.dash and cs.dash.bright))
    check("7 第二段有停顿（第一段 0.10，第二段在 0.30 之后）", cs.dash and cs.dash.t > 0.10,
        cs.dash and cs.dash.t)

    -- ============ 8. 关卡解锁：步数档位不能每天累加 ============
    local d = Save.Fresh()
    check("8 新档只开第 1 关", d.unlocked == 1 and Save.MaxPlayable(d) == 1,
        tostring(d.unlocked))
    for _ = 1, 5 do
        d.claimed = false
        d.dayKey = ""
        d.todaySteps = 12000
        Save.Claim(d, 12000)
    end
    check("8 连续领取 5 天也不会涨到 20 关", d.unlocked == 4, d.unlocked)
    check("8 没通关就只能打第 1 关", Save.MaxPlayable(d) == 1, Save.MaxPlayable(d))
    -- 只有开发按钮能全解锁
    Save.DebugUnlockAll(d)
    check("8 开发按钮才全解锁", d.unlocked == 20 and Save.MaxPlayable(d) == 20,
        tostring(d.unlocked) .. "/" .. Save.MaxPlayable(d))

    -- ============ 9. 位移类技能：位移期间无敌 ============
    cs = NewCombat("spearman", { 2, 1, 5 })
    p = cs.player
    p.x, p.y = 640, 400
    cs.facing = 0
    p.hp = p.maxHp
    local hpDash = p.hp
    Combat.CastSkill(1)                       -- 突刺奔袭
    Combat.Update(1 / 60)
    Combat.DamagePlayer(cs, 50)
    check("9 突刺奔袭冲刺中免疫伤害", p.hp == hpDash, p.hp - hpDash)

    cs = NewCombat("spearman", { 1, 2, 5 })
    p = cs.player
    p.x, p.y = 640, 400
    cs.facing = 0
    p.hp = p.maxHp
    local hpBack = p.hp
    Combat.CastSkill(3)                       -- 回马枪
    Combat.Update(1 / 60)
    Combat.DamagePlayer(cs, 50)
    -- 回马枪不靠穿怪造成伤害，位移段不给无敌（设计如此）
    check("9 回马枪前冲不再无敌", p.hp < hpBack, p.hp - hpBack)

    cs = NewCombat("swordsman", { 2, 1, 3 })
    p = cs.player
    p.hp = p.maxHp
    local hpSw = p.hp
    Combat.CastSkill(1)                       -- 闪影突进
    Combat.Update(1 / 60)
    Combat.DamagePlayer(cs, 50)
    check("9 闪影突进免疫伤害", p.hp == hpSw, p.hp - hpSw)

    cs = NewCombat("ranger", { 6, 5, 3 })
    p = cs.player
    p.hp = p.maxHp
    Combat.SpawnWave(cs, { minion = 1 })
    local target = cs.enemies[1]
    target.x, target.y = p.x + 200, p.y
    p.cooldowns[6] = 0
    local hpSwap = p.hp
    Combat.CastSkill(1)                       -- 掠袭换位
    Combat.DamagePlayer(cs, 50)
    check("9 掠袭换位落地后短暂无敌", p.hp == hpSwap, p.hp - hpSwap)

    print("[Fix3] done, failures = " .. fails)
end
