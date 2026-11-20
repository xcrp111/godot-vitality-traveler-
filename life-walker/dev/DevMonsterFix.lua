-- DevMonsterFix.lua — 畸变疫病派系：持续伤害强度 / 可读性 / 巨像疫域改周期
local Config = require "Config"
local Save = require "Save"
local S = require "State"
local Run = require "Run"
local Combat = require "Combat"

local fails = 0
local function check(name, cond, detail)
    if cond then
        print("[Mon] OK   " .. name)
    else
        fails = fails + 1
        print("[MON] FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
    end
end

local function NewCombat(class)
    S.data = Save.Load()
    Save.SetClass(S.data, class or "swordsman")
    Save.SetClassLevel(S.data, 10)
    Config.SetClass(class or "swordsman")
    Run.Start(3, true)
    S.run.loadout = { 1, 2, 3 }
    local cs = Combat.Start(S.run, "standard", 1)
    S.screen = "combat"
    cs.enemies = {}
    cs.walls = {}
    cs.waves = { {} }
    cs.waveIndex = 1
    cs.player.x, cs.player.y = 640, 400
    cs.player.shield = 0
    S.data.autoAttack = false   -- 测试里别让自动普攻把 Boss 打到 30% 触发爆炸疫域
    return cs
end

function Start()
    -- ===== 脓肿岩行者：脓水与感染的伤害下调 =====
    local cs = NewCombat()
    local p = cs.player
    Combat.SpawnTestEnemy(cs, "minion", "abscess")
    local ab = cs.enemies[1]
    ab.x, ab.y = p.x + 200, p.y
    ab.hp = ab.maxHp * 0.3
    Combat.Update(1 / 60)
    local hz = cs.hazardFields and cs.hazardFields[1]
    check("脓肿行者会在残血时留脓水", hz ~= nil)
    check("脓水单跳伤害下调（0.22 倍攻击）", hz and math.abs(hz.dps - ab.atk * 0.22) < 0.01,
        hz and string.format("%.2f vs %.2f", hz.dps, ab.atk * 0.22))
    check("脓水带类型标记（用于上色）", hz and hz.kind == "pus", hz and hz.kind)

    -- 感染：被脓肿行者近战命中后，DPS 应为 0.45 倍攻击
    cs = NewCombat()
    p = cs.player
    Combat.SpawnTestEnemy(cs, "minion", "abscess")
    ab = cs.enemies[1]
    ab.x, ab.y = p.x + 30, p.y
    ab.attackCd = 0
    for _ = 1, 10 do Combat.Update(1 / 60) end
    check("感染 DPS 下调（0.45 倍攻击）",
        (p.infectDps or 0) > 0 and math.abs(p.infectDps - ab.atk * 0.45) < 0.01,
        string.format("%.2f vs %.2f", p.infectDps or 0, ab.atk * 0.45))

    -- ===== 疫蚀石魔：腐液类型与伤害 =====
    cs = NewCombat()
    p = cs.player
    Combat.SpawnTestEnemy(cs, "elite", "golem")
    local golem = cs.enemies[1]
    golem.x, golem.y = p.x + 260, p.y
    golem.stompCd = 0
    cs.hazardFields = {}
    Combat.Update(1 / 60)
    local rot = cs.hazardFields[1]
    check("疫蚀石魔跺脚留下腐液", rot ~= nil)
    check("腐液带类型标记", rot and rot.kind == "rot", rot and rot.kind)
    check("腐液伤害略微下调（0.42 倍攻击）", rot and math.abs(rot.dps - golem.atk * 0.42) < 0.01,
        rot and string.format("%.2f", rot.dps))

    -- ===== 瘟衰巨像：衰竭疫域改成周期性技能 =====
    cs = NewCombat()
    p = cs.player
    Combat.SpawnTestEnemy(cs, "boss", "colossus")
    local boss = cs.enemies[1]
    boss.x, boss.y = p.x + 120, p.y
    boss.bossSkillCd = 9999          -- 屏蔽冲击波，单看疫域
    boss.speed = 0
    p.hp = p.maxHp
    local hp0 = p.hp

    for _ = 1, 210 do Combat.Update(1 / 60) end   -- 3.5 秒
    check("疫域不是常驻（开局 3.5 秒内没开）", (boss.auraOn or 0) <= 0, boss.auraOn)
    check("疫域关闭时贴脸不掉血", p.hp == hp0, hp0 - p.hp)

    for _ = 1, 60 do Combat.Update(1 / 60) end    -- 到 4.5 秒
    check("疫域会周期开启", (boss.auraOn or 0) > 0, boss.auraOn)
    check("疫域开启时站里面会掉血", p.hp < hp0, hp0 - p.hp)

    for _ = 1, 240 do Combat.Update(1 / 60) end   -- 再等 4 秒（开启 3 秒后关闭）
    check("疫域会关闭，给近战输出窗口", (boss.auraOn or 0) <= 0, boss.auraOn)
    local hp1 = p.hp
    for _ = 1, 120 do Combat.Update(1 / 60) end   -- 关闭期间 2 秒
    check("关闭期间不掉血", p.hp == hp1, hp1 - p.hp)

    print("[Mon] done, failures = " .. fails)
end
