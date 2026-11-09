-- DevMage.lua — 法师元素机制 / 九个技能
local Config = require "Config"
local Save = require "Save"
local S = require "State"
local Run = require "Run"
local Combat = require "Combat"
local VirtualControls = require "urhox-libs.UI.VirtualControls"

local fails = 0
local function check(name, cond, detail)
    if cond then
        print("[Mage] OK   " .. name)
    else
        fails = fails + 1
        print("[Mage] FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
    end
end

local function Step(cs, frames)
    for _ = 1, frames do
        Combat.Update(1 / 60)
        if S.screen ~= "combat" then return end
    end
end

local function Place(cs, dist, count)
    cs.enemies = {}
    Combat.SpawnWave(cs, { minion = count or 1 })
    local first = nil
    for i, e in ipairs(cs.enemies) do
        e.hp = 4000
        e.maxHp = 4000
        e.x = cs.player.x + dist + (i - 1) * 40
        e.y = cs.player.y
        first = first or e
    end
    cs.facing = 0
    return first
end

function Start()
    VirtualControls.Initialize(Config.DESIGN_W, Config.DESIGN_H)
    S.data = Save.Load()
    Save.SetClass(S.data, "mage")
    Save.SetClassLevel(S.data, 10)
    Config.SetClass("mage")
    math.randomseed(31)
    Run.Start(1)
    S.run.loadout = { 1, 2, 3 }
    local p = S.run.player
    check("生命 40", p.maxHp == 40, p.maxHp)
    check("护盾 25", p.maxShield == 25, p.maxShield)
    check("攻击 17", p.atk == 17, p.atk)
    check("远程职业", Config.Class().ranged == true)

    local cs = Combat.Start(S.run, "standard", 3)
    S.screen = "combat"
    cs.walls = {}
    cs.enemies = {}
    cs.waveIndex = #cs.waves
    check("元素共鸣（1 火 1 冰 1 电）", cs.mageSpec == "resonance", cs.mageSpec)

    -- 普攻
    local e = Place(cs, 150)
    Combat.BasicAttack(cs)
    check("普攻生成法弹", #cs.projs > 0, #cs.projs)
    Step(cs, 30)
    check("法弹命中", e.hp < 4000, e.hp)

    -- 火球：燃烧
    p.cooldowns[1] = 0
    e = Place(cs, 150)
    Combat.CastSkill(1)
    Step(cs, 40)
    check("火球命中并燃烧", (e.burnTimer or 0) > 0 and e.hp < 4000,
        "burn=" .. tostring(e.burnTimer))

    -- 雷击：对燃烧目标过载
    p.cooldowns[3] = 0
    local hpBefore = e.hp
    Combat.CastSkill(3)
    check("雷击命中燃烧目标", e.hp < hpBefore, e.hp)

    -- 冰冻波：冰冻
    p.cooldowns[2] = 0
    e = Place(cs, 90)
    Combat.CastSkill(2)
    check("冰冻波施加冰冻", (e.freezeTimer or 0) > 0, e.freezeTimer)

    -- 融化：冰冻目标吃火
    p.cooldowns[1] = 0
    local meltHp = e.hp
    Combat.CastSkill(1)
    Step(cs, 40)
    check("冰冻目标触发融化伤害", e.hp < meltHp, e.hp)

    -- 冰锥减速
    S.run.loadout = { 4, 5, 6 }
    p.cooldowns[4] = 0
    e = Place(cs, 150)
    Combat.CastSkill(1) -- slot1 = 技能 4
    Step(cs, 40)
    check("冰锥命中减速", (e.slowTimer or 0) > 0 and e.hp < 4000, e.slowTimer)

    -- 闪电链连锁
    p.cooldowns[5] = 0
    Place(cs, 80, 4)
    Combat.CastSkill(2) -- slot2 = 技能 5
    local hurt = 0
    for _, en in ipairs(cs.enemies) do if en.hp < 4000 then hurt = hurt + 1 end end
    check("闪电链命中多个目标", hurt >= 2, hurt)

    -- 烈焰 + 静电力场 + 流星 + 暴风雪
    p.cooldowns[6] = 0
    e = Place(cs, 80)
    Combat.CastSkill(3) -- 技能 6
    check("烈焰造成伤害", e.hp < 4000, e.hp)

    S.run.loadout = { 7, 8, 9 }
    p.cooldowns[7] = 0
    Combat.CastSkill(1) -- 技能 7
    check("静电力场生成", #cs.mageFields > 0, #cs.mageFields)
    p.cooldowns[8] = 0
    e = Place(cs, 150)
    Combat.CastSkill(2) -- 技能 8
    check("流星命中", e.hp < 4000, e.hp)
    p.cooldowns[9] = 0
    Combat.CastSkill(3) -- 技能 9
    check("暴风雪生成", #cs.mageFields > 0, #cs.mageFields)

    -- 三火专精
    S.run.loadout = { 1, 6, 8 }
    local cs2 = Combat.Start(S.run, "standard", 3)
    check("三火专精", cs2.mageSpec == "fire", cs2.mageSpec)

    print(string.format("[Mage] done, failures = %d", fails))
end
