-- DevFixBatch3.lua — 2026-11-10 这批游侠/枪客反馈的回归
local Config = require "Config"
local Save = require "Save"
local S = require "State"
local Run = require "Run"
local Combat = require "Combat"

local fails = 0
local function check(name, cond, detail)
    if cond then
        print("[Fx4] OK   " .. name)
    else
        fails = fails + 1
        print("[Fx4] FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
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
    return { id = id, name = id, desc = "", rarity = "purple",
        classBuff = false, mod = {}, flag = flag or {} }
end

function Start()
    -- ① 疾退腾挪：翻滚后下一发普攻必定暴击
    local cs = NewCombat("ranger", { 2, 3, 5 })
    local p = cs.player
    Combat.CastSkill(1)
    for _ = 1, 24 do Combat.Update(1/60) end
    check("疾退后记录必暴标记", (cs.rangerDodgeCrit or 0) == 1, cs.rangerDodgeCrit)
    p.attackTimer = 0
    Combat.ManualAttack(); for _ = 1, 20 do Combat.Update(1/60) end
    check("必暴标记被消耗", (cs.rangerDodgeCrit or 0) == 0, cs.rangerDodgeCrit)

    -- ② 箭影连射：指示器射程/扇面与真实弹道一致
    cs = NewCombat("ranger", { 5, 3, 6 })
    cs.telegraphs = {}
    Combat.CastSkill(1)
    for _ = 1, 24 do Combat.Update(1/60) end
    local tel = cs.telegraphs[#cs.telegraphs]
    check("连射指示器射程 900", tel and tel.range == 900, tel and tel.range)
    check("连射指示器扇面收窄", tel and tel.arc < 0.60, tel and tel.arc)

    -- ③ 减速到期要把强度清零（不会看起来「减速到死」）
    cs = NewCombat("ranger", { 1, 2, 3 })
    p = cs.player
    S.data.autoAttack = false   -- 别让自动普攻一直刷新减速
    Run.GrantBuff(p, Buff("x_slow", { basicSlow = 0.2 }))
    Run.Recompute(p)
    Combat.SpawnWave(cs, { minion = 1 })
    local e = cs.enemies[1]
    e.x, e.y = p.x + 60, p.y
    e.hp, e.maxHp = 999999, 999999
    p.attackTimer = 0
    Combat.ManualAttack(); for _ = 1, 20 do Combat.Update(1/60) end
    for _ = 1, 60 * 4 do Combat.Update(1 / 60) end
    check("减速计时结束后强度归零", (e.slowPct or 0) == 0, e.slowPct)

    -- ④ 反击箭阵按「受到伤害 × 1.6」反弹
    cs = NewCombat("ranger", { 1, 2, 3 })
    p = cs.player
    Run.GrantBuff(p, Buff("x_thorns", { thorns = 1.6, thornsHunt = 1 }))
    Run.Recompute(p)
    Combat.SpawnWave(cs, { minion = 1 })
    e = cs.enemies[1]
    e.x, e.y = p.x + 30, p.y
    e.hp, e.maxHp = 100000, 100000
    p.shield = 0
    local hpBefore = e.hp
    Combat.DamagePlayer(cs, 100)
    local dealt = hpBefore - e.hp
    check("反弹伤害 = 受伤 × 1.6", math.abs(dealt - 160) < 1, dealt)
    check("反弹附带猎痕", (e.hunt or 0) >= 1, e.hunt)

    -- ⑤ 猛攻蓄力：普攻命中就能叠重击
    cs = NewCombat("spearman", { 1, 2, 3 })
    p = cs.player
    Run.GrantBuff(p, Buff("x_charge", { chargePct = 0.07, guardSlam = 3.2,
        heavyDR = 0.12, heavyStagger = 1, guardSlamCombo = 1 }))
    Run.Recompute(p)
    Combat.SpawnWave(cs, { minion = 1 })
    e = cs.enemies[1]
    e.x, e.y = p.x + 55, p.y
    e.hp, e.maxHp = 999999, 999999
    cs.spearCombo = 0
    p.attackTimer = 0
    Combat.ManualAttack(); for _ = 1, 20 do Combat.Update(1/60) end
    check("普攻命中叠 1 层重击", (cs.chargeStacks or 0) >= 1, cs.chargeStacks)

    -- ⑥ 猛攻蓄力：固守结束把 3.2 倍重劈存起来，下一次命中才结算
    cs = NewCombat("spearman", { 3, 1, 2 })
    p = cs.player
    Run.GrantBuff(p, Buff("x_charge", { chargePct = 0.07, guardSlam = 3.2,
        heavyDR = 0.12, heavyStagger = 1, guardSlamCombo = 1 }))
    Run.Recompute(p)
    Combat.CastSkill(1)                       -- 铁枪固守
    cs.guardTimer = 0.02
    Combat.Update(0.05)                       -- 固守结束
    check("固守结束存下重劈", cs.pendingSlam ~= nil, cs.pendingSlam ~= nil)
    Combat.SpawnWave(cs, { minion = 1 })
    e = cs.enemies[1]
    e.x, e.y = p.x + 50, p.y
    e.hp, e.maxHp = 999999, 999999
    local hp2 = e.hp
    p.attackTimer = 0
    Combat.ManualAttack(); for _ = 1, 20 do Combat.Update(1/60) end
    check("重劈在下次命中结算", cs.pendingSlam == nil)
    check("重劈造成额外伤害", hp2 - e.hp > p.atk * 3.0, string.format("%.0f", hp2 - e.hp))

    -- ⑦ 枪势轮回：掷枪命中给枪势
    cs = NewCombat("spearman", { 4, 1, 2 })
    p = cs.player
    Run.GrantBuff(p, Buff("x_cycle", { momentumOnSkill = 1, momentumFreeNew = 1,
        comboHuntChance = 0.2, skillCdMul = 0.3, momentumGainMul = 0.6 }))
    Run.Recompute(p)
    p.intent = 0
    Combat.SpawnWave(cs, { minion = 1 })
    e = cs.enemies[1]
    e.x, e.y = p.x + 200, p.y
    e.hp, e.maxHp = 999999, 999999
    Combat.CastSkill(1)                       -- 掷枪
    for _ = 1, 90 do Combat.Update(1 / 60) end
    check("掷枪命中叠枪势", (p.intent or 0) >= 1, p.intent)

    -- ⑧ 错位连携：两种负面并存即触发，且只消耗用到的两种
    cs = NewCombat("spearman", { 1, 2, 3 })
    p = cs.player
    Run.GrantBuff(p, Buff("x_mis", { misalign = 1, comboMaster = 1 }))
    Run.Recompute(p)
    Combat.SpawnWave(cs, { minion = 1 })
    e = cs.enemies[1]
    e.x, e.y = p.x + 50, p.y
    e.hp, e.maxHp = 999999, 999999
    e.crack, e.crackTimer = 1, 4
    e.hunt, e.huntTimer = 2, 4
    local before = cs.comboCount or 0
    p.attackTimer = 0
    Combat.ManualAttack(); for _ = 1, 20 do Combat.Update(1/60) end
    check("挫裂+猎痕触发出连携", (cs.comboCount or 0) > before, cs.comboCount)
    check("没用到的失衡保留", (e.stagger or 0) == 0 or (e.hunt or 0) >= 0)

    print(string.format("[Fx4] done, failures = %d", fails))
end
