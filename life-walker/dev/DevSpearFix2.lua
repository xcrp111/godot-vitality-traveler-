-- DevSpearFix2.lua — 本轮枪客修复回归（嗜血裁决 / 破军追猎 / 固阵壁垒 / 飞枪轮回 / 逐影千旋 / 奔突回锋）
local Config = require "Config"
local Save = require "Save"
local S = require "State"
local Run = require "Run"
local Combat = require "Combat"

local fails = 0
local function check(name, cond, detail)
    if cond then
        print("[Fx3] OK   " .. name)
    else
        fails = fails + 1
        print("[Fx3] FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
    end
end

local function NewCombat(class, loadout)
    S.data = Save.Load()
    Save.SetClass(S.data, class)
    Save.SetClassLevel(S.data, 10)
    Config.SetClass(class)
    Run.Start(3, true)
    if loadout then S.run.loadout = loadout end
    local cs = Combat.Start(S.run, "standard", 1)
    S.screen = "combat"
    cs.enemies = {}
    cs.walls = {}
    cs.waves = { {} }
    cs.waveIndex = 1
    cs.player.x, cs.player.y = 640, 400
    cs.facing = 0
    cs.player.attackTimer = 0
    return cs
end

local function Buff(id, flag)
    return { id = id, name = id, desc = "", rarity = "gold",
        classBuff = false, mod = {}, flag = flag }
end

function Start()
    -- ① 嗜血裁决：真伤是固定数值，不吃暴击 / 物理加成，能击杀
    local cs = NewCombat("spearman", { 1, 2, 3 })
    Combat.SpawnWave(cs, { minion = 1 })
    local e = cs.enemies[1]
    e.hp, e.maxHp = 1000, 1000
    Combat.TrueDamage(cs, e, 80, "真伤")
    check("真伤按固定值扣血", math.abs(e.hp - 920) < 0.01, e.hp)
    Combat.TrueDamage(cs, e, 5000)
    check("真伤可以击杀目标", #cs.enemies == 0, #cs.enemies)

    -- ② 连段必须命中才推进（空挥不再攒出 3A）
    cs = NewCombat("spearman", { 1, 2, 3 })
    cs.player.attackTimer = 0
    Combat.ManualAttack(); for _ = 1, 20 do Combat.Update(1/60) end
    check("空挥不推进连段", (cs.spearCombo or 0) == 0, cs.spearCombo)
    Combat.SpawnWave(cs, { minion = 1 })
    local e2 = cs.enemies[1]
    e2.x, e2.y = cs.player.x + 60, cs.player.y
    e2.hp, e2.maxHp = 999999, 999999
    cs.facing = 0
    cs.player.attackTimer = 0
    Combat.ManualAttack(); for _ = 1, 20 do Combat.Update(1/60) end
    check("命中推进到 1A", cs.spearCombo == 1, cs.spearCombo)
    cs.player.attackTimer = 0
    Combat.ManualAttack(); for _ = 1, 20 do Combat.Update(1/60) end
    check("再命中推进到 2A", cs.spearCombo == 2, cs.spearCombo)
    cs.player.attackTimer = 0
    Combat.ManualAttack(); for _ = 1, 20 do Combat.Update(1/60) end
    check("第三段后回到 0", cs.spearCombo == 0, cs.spearCombo)

    -- ③ 飞枪轮回：折返的枪飞回手上，接住返还 2 秒冷却
    cs = NewCombat("spearman", { 4, 1, 2 })
    local p = cs.player
    Run.GrantBuff(p, Buff("x_return", { throwReturn = 1, throwStagger = 1, throwCd = 2 }))
    Run.Recompute(p)
    cs.facing = 0
    Combat.CastSkill(1)
    for _ = 1, 24 do Combat.Update(1/60) end
    check("掷枪已飞出", #cs.spearShots == 1, #cs.spearShots)
    p.cooldowns[4] = 60
    local t = 0
    while #cs.spearShots > 0 and t < 6 do
        S.screen = "combat"
        S.combat = cs
        cs.cleared, cs.clearTimer = false, 0   -- 空房间会被判成通关，Update 会提前返回
        Combat.Update(1 / 60)
        t = t + 1 / 60
    end
    check("枪会折返并被接住", #cs.spearShots == 0, #cs.spearShots)
    check("接枪返还 2 秒冷却", (p.cooldowns[4] or 0) <= 60 - t - 1.8,
        string.format("cd=%.2f t=%.2f", p.cooldowns[4] or 0, t))

    -- ④ 固阵壁垒：子弹不掉血，沿原弹道反弹，反弹带失衡
    cs = NewCombat("spearman", { 3, 1, 2 })
    p = cs.player
    Run.GrantBuff(p, Buff("x_bastion", { guardDur = 0.7, guardDR = 0.15,
        guardReflect = 2.5, reflectStagger = 1 }))
    Run.Recompute(p)
    Combat.CastSkill(1)
    for _ = 1, 24 do Combat.Update(1/60) end
    check("固守已开启", (cs.guardTimer or 0) > 0, cs.guardTimer)
    cs.projs = {}
    cs.bullets = {
        { x = p.x - 5, y = p.y, vx = 300, vy = 0, r = 8, life = 1, dmg = 30,
          color = { 200, 200, 255 } },
    }
    local hpBefore = p.hp
    Combat.UpdateBullets(cs, 1 / 60)
    check("固守期间子弹不掉血", p.hp == hpBefore, p.hp)
    check("敌方子弹被移除", #cs.bullets == 0, #cs.bullets)
    local rp = cs.projs[1]
    check("反弹弹体已生成", rp ~= nil, #cs.projs)
    check("沿原弹道反向飞回", rp and rp.vx < 0, rp and rp.vx)
    check("反弹附带失衡", rp and (rp.stagger or 0) >= 1, rp and rp.stagger)

    -- ⑤ 逐影千旋：位移技能的残影跟着人走
    cs = NewCombat("spearman", { 2, 1, 3 })
    p = cs.player
    p.flags = p.flags or {}
    p.flags.phantomPct = 0.55
    Combat.CastSkill(1)
    for _ = 1, 24 do Combat.Update(1/60) end
    check("位移技能生成残影", #cs.phantoms >= 1, #cs.phantoms)
    local ph = cs.phantoms[1]
    p.x = p.x + 180
    Combat.Update(1 / 60)
    check("残影跟随位移", ph and math.abs(ph.x - p.x) < 1,
        ph and string.format("ph=%.1f p=%.1f", ph.x, p.x))

    -- ⑥ 技能 1（三段枪式）的残影不再凭空打出 3.4 倍技能伤害
    cs = NewCombat("spearman", { 1, 2, 3 })
    p = cs.player
    p.flags = p.flags or {}
    p.flags.phantomPct = 0.55
    cs.pendingHits = {}
    Combat.CastSkill(1)
    for _ = 1, 24 do Combat.Update(1/60) end
    local scheduled = #cs.pendingHits
    check("增益技能的残影只结算一段", scheduled <= 1, scheduled)

    print(string.format("[Fx3] done, failures = %d", fails))
end
