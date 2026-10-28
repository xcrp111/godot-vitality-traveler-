-- DevSpear.lua — 枪客基础数值 / 枪势 / 六个技能冒烟测试
local Config = require "Config"
local Save = require "Save"
local S = require "State"
local Run = require "Run"
local Combat = require "Combat"
local VirtualControls = require "urhox-libs.UI.VirtualControls"

local fails = 0
local function check(name, cond, detail)
    if cond then
        print("[Spear] OK   " .. name)
    else
        fails = fails + 1
        print("[Spear] FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
    end
end

local function Step(cs, frames)
    for _ = 1, frames do
        Combat.Update(1 / 60)
        if S.screen ~= "combat" then return end
    end
end

local function PlaceEnemy(cs, dist)
    cs.enemies = {}
    Combat.SpawnWave(cs, { minion = 1 })
    local e = cs.enemies[1]
    e.hp = 2000
    e.maxHp = 2000
    e.x = cs.player.x + dist
    e.y = cs.player.y
    cs.facing = 0
    return e
end

function Start()
    VirtualControls.Initialize(Config.DESIGN_W, Config.DESIGN_H)
    S.data = Save.Load()
    Save.SetClass(S.data, "spearman")
    Save.SetClassLevel(S.data, 10)
    math.randomseed(8)

    Config.SetClass("spearman")
    Run.Start(1)
    S.run.loadout = { 1, 2, 3, 4, 5, 6 }
    local p = S.run.player
    check("基础生命 50", p.maxHp == 50, p.maxHp)
    check("基础护盾 25", p.maxShield == 25, p.maxShield)
    check("基础攻击 16", p.atk == 16, p.atk)
    check("移速 128", math.floor(p.moveSpeed) == 128, p.moveSpeed)
    check("技能池是枪客", Config.Skills[1].name == "三段枪式", Config.Skills[1] and Config.Skills[1].name)

    local cs = Combat.Start(S.run, "standard", 3)
    S.screen = "combat"
    cs.enemies = {}
    cs.walls = {}
    cs.waveIndex = #cs.waves
    local e = PlaceEnemy(cs, 50)

    -- 三段普攻
    p.attackTimer = 0
    Combat.BasicAttack(cs)
    check("1A 连击段数", cs.spearCombo == 1, cs.spearCombo)
    Combat.BasicAttack(cs)
    check("2A 连击段数", cs.spearCombo == 2, cs.spearCombo)
    Combat.BasicAttack(cs)
    check("3A 后回到 0 段", cs.spearCombo == 0, cs.spearCombo)
    check("打满一套获得枪势", p.intent >= 1, p.intent)

    -- 持有枪势普攻施加减速失衡
    e.stagger = 0
    e.staggerTimer = 0
    Combat.BasicAttack(cs)
    check("持有枪势普攻挂失衡", (e.stagger or 0) > 0, e.stagger)

    -- 三段枪式
    p.intent = 1
    p.cooldowns = {}
    Combat.CastSkill(1)
    check("三段枪式进入强化", (cs.spearBuffHits or 0) == 3, cs.spearBuffHits)
    p.cooldowns[2] = 5
    Combat.BasicAttack(cs)
    check("强化普攻减技能 CD", (p.cooldowns[2] or 0) < 5, p.cooldowns[2])

    -- 突刺奔袭：消耗枪势时触发震荡
    p.intent = 1
    p.cooldowns[2] = 0
    e = PlaceEnemy(cs, 60)
    local combos = cs.comboCount or 0
    Combat.CastSkill(2)
    check("突刺进入冲刺", cs.dash ~= nil)
    check("突刺消耗枪势", p.intent == 0, p.intent)
    Step(cs, 20)
    check("突刺消耗枪势触发震荡", (cs.comboCount or 0) > combos, cs.comboCount)
    -- 不消耗枪势时保留挫裂
    p.intent = 0
    p.cooldowns[2] = 0
    e = PlaceEnemy(cs, 60)
    Combat.CastSkill(2)
    Step(cs, 20)
    check("突刺命中挂挫裂", (e.crack or 0) > 0, e.crack)

    -- 铁枪固守
    p.cooldowns[3] = 0
    p.intent = 1
    Combat.CastSkill(3)
    check("铁枪固守持续", (cs.guardTimer or 0) > 2.0, cs.guardTimer)
    e = PlaceEnemy(cs, 60)
    local hpBefore = e.hp
    Step(cs, 170)
    check("固守结束震地", e.hp < hpBefore, e.hp)

    -- 掷枪
    p.cooldowns[4] = 0
    p.intent = 1
    e = PlaceEnemy(cs, 160)
    Combat.CastSkill(4)
    check("掷枪生成投掷物", #cs.spearShots > 0, #cs.spearShots)
    Step(cs, 40)
    check("掷枪命中并失衡", (e.stagger or 0) > 0, e.stagger)

    -- 回马枪
    p.cooldowns[5] = 0
    p.intent = 1
    e = PlaceEnemy(cs, 60)
    local px = p.x
    Combat.CastSkill(5)
    check("回马枪后撤", p.x < px, p.x - px)
    Step(cs, 30)
    check("回马枪命中", e.hp < 2000, e.hp)

    -- 枪阵震地
    p.cooldowns[6] = 0
    p.intent = 1
    e = PlaceEnemy(cs, 60)
    local shockHp = e.hp
    Combat.CastSkill(6)
    check("枪阵震地伤害", e.hp < shockHp, e.hp)
    check("枪阵震地失衡", (e.stagger or 0) > 0, e.stagger)

    print(string.format("[Spear] done, failures = %d", fails))
end
