-- DevMageBalance.lua — 法师平衡调整回归：跟随力场 / 龙息射程 / 冰冻波射程 / 冷却
local Config = require "Config"
local Save = require "Save"
local S = require "State"
local Run = require "Run"
local Combat = require "Combat"

local fails = 0
local function check(name, cond, detail)
    if cond then
        print("[MageBal] OK   " .. name)
    else
        fails = fails + 1
        print("[MageBal] FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
    end
end

local function NewCombat(loadout, mods, flags)
    S.data = Save.Load()
    Save.SetClass(S.data, "mage")
    Save.SetClassLevel(S.data, 12)
    Config.SetClass("mage")
    Run.Start(3, true)
    S.run.loadout = loadout
    local cs = Combat.Start(S.run, "standard", 1)
    S.combat = cs
    S.screen = "combat"
    cs.enemies, cs.walls, cs.waves, cs.waveIndex = {}, {}, { {} }, 1
    cs.player.cooldowns = {}
    for k, v in pairs(mods or {}) do cs.player.mods[k] = (cs.player.mods[k] or 0) + v end
    for k, v in pairs(flags or {}) do cs.player.flags[k] = (cs.player.flags[k] or 0) + v end
    Run.Recompute(cs.player)
    return cs
end

local function PutEnemy(cs, dx, dy)
    Combat.SpawnWave(cs, { minion = 1 })
    local e = cs.enemies[#cs.enemies]
    e.x, e.y = cs.player.x + dx, cs.player.y + dy
    e.hp, e.maxHp = 99999, 99999
    e.speed = 0
    return e
end

local function DamageIn(func)
    local cs = NewCombat({ 1, 2, 3 })
    -- 先固定一个木桩在正前方
    local e = PutEnemy(cs, 200, 0)
    local before = e.hp
    func(cs, e)
    return before - e.hp
end

-- 1) 冷却：小技能整体下调
local cds = {}
for _, sk in ipairs(Config.ClassSkills.mage) do cds[sk.id] = sk.cd end
check("火球冷却 1.6", cds[1] == 1.6, cds[1])
check("冰冻波冷却 4.0", cds[2] == 4.0, cds[2])
check("雷击冷却 3.4", cds[3] == 3.4, cds[3])
check("冰锥冷却 2.4", cds[4] == 2.4, cds[4])
check("闪电链冷却 5.0", cds[5] == 5.0, cds[5])
check("烈焰冷却 5.0", cds[6] == 5.0, cds[6])
check("静电力场冷却 6.5", cds[7] == 6.5, cds[7])
check("流星冷却 8.5", cds[8] == 8.5, cds[8])
check("暴风雪冷却 10.0", cds[9] == 10.0, cds[9])

-- 2) 普攻系数上调（0.6 -> 0.8）
check("法师普攻系数 0.80", Config.Classes.mage.basicCoef == 0.8, Config.Classes.mage.basicCoef)

-- 3) 静电力场跟随玩家
local cs = NewCombat({ 7, 0, 0 })
Combat.MageCastSkill(1)
local f = cs.mageFields[1]
check("静电力场已生成", f ~= nil)
if f then
    local fx0, fy0 = f.x, f.y
    cs.player.x = cs.player.x + 120
    cs.player.y = cs.player.y + 60
    Combat.Update(1 / 60)
    check("力场跟随玩家（x）", math.abs(f.x - cs.player.x) < 1, f.x - cs.player.x)
    check("力场跟随玩家（y）", math.abs(f.y - cs.player.y) < 1, f.y - cs.player.y)
    check("力场确实移动过", math.abs(f.x - fx0) > 50 and math.abs(f.y - fy0) > 20)
    check("静电力场半径 >= 160（原 96 太小）", (f.r or 0) >= 160, f.r)
end

-- 4) 龙息：烈焰冲击的强化形态（不再替换火球）
cs = NewCombat({ 6, 0, 0 }, nil, { dragonBreath = 1 })
local far = PutEnemy(cs, 280, 0)
local hp0 = far.hp
Combat.MageCastSkill(1)
local breathField = nil
for _, f in ipairs(cs.mageFields or {}) do if f.breath then breathField = f end end
check("龙息生成持续喷射场地", breathField ~= nil)
if breathField then
    check("龙息持续时间 >= 2 秒", (breathField.life or 0) >= 2.0, breathField.life)
    check("龙息扇形 <= 90°", (breathField.arc or 0) <= math.rad(90.5),
        math.deg(breathField.arc or 0))
    -- 总量 = 每跳伤害 × 每秒跳数 × 时长；秒伤要低于上一版（0.35/0.15 ≈ 2.33 倍/秒）
    local dps = ((breathField.dmg or 0) / 0.15)
    check("龙息秒伤低于 2.0 倍/秒", dps < 2.0, dps)
    local total = dps * (breathField.life or 0)
    check("龙息总伤害高于 2.8 倍", total > 2.8, total)
end
for _ = 1, 240 do Combat.Update(1 / 60) end
check("龙息持续灼烧 280px 的目标", far.hp < hp0, hp0 - far.hp)
check("龙息是持续伤害（不只打一下）", (hp0 - far.hp) > 0 and breathField ~= nil and (breathField.dmg or 0) < 2.0)
check("龙息场地到时消失", #(cs.mageFields or {}) == 0, #(cs.mageFields or {}))

cs = NewCombat({ 6, 0, 0 }, nil, { dragonBreath = 1 })
local tooFar = PutEnemy(cs, 360, 0)
local hp1 = tooFar.hp
Combat.MageCastSkill(1)
for _ = 1, 200 do Combat.Update(1 / 60) end
check("龙息有射程上限（360px 打不到）", tooFar.hp == hp1, hp1 - tooFar.hp)

-- 5) 冰冻波：射程 128 -> 240，伤害 0.8 -> 1.0
cs = NewCombat({ 2, 0, 0 })
local e230 = PutEnemy(cs, 230, 0)
local hp2 = e230.hp
Combat.MageCastSkill(1)
check("冰冻波能打到 230px 的目标", e230.hp < hp2, hp2 - e230.hp)

cs = NewCombat({ 2, 0, 0 })
local e260 = PutEnemy(cs, 260, 0)
local hp2b = e260.hp
Combat.MageCastSkill(1)
check("冰冻波射程上限（260px 打不到）", e260.hp == hp2b, hp2b - e260.hp)

-- 6) 冰锥伤害 1.2 -> 1.4
cs = NewCombat({ 4, 0, 0 })
local e = PutEnemy(cs, 200, 0)
local hp3 = e.hp
Combat.MageCastSkill(1)
for _ = 1, 60 do Combat.Update(1 / 60) end
check("冰锥能命中远处目标", e.hp < hp3, hp3 - e.hp)

-- 7) 静电力场伤害 0.2 -> 0.25
cs = NewCombat({ 7, 0, 0 })
local near = PutEnemy(cs, 40, 0)
local hp4 = near.hp
Combat.MageCastSkill(1)
for _ = 1, 40 do Combat.Update(1 / 60) end
check("静电力场持续造成伤害", near.hp < hp4, hp4 - near.hp)

-- 9) 烈焰冲击范围 120 -> 220
cs = NewCombat({ 6, 0, 0 })
local eFlame = PutEnemy(cs, 210, 0)
local hpF = eFlame.hp
Combat.MageCastSkill(1)
check("烈焰冲击能打到 210px 的目标", eFlame.hp < hpF, hpF - eFlame.hp)

-- 10) 暴风雪可以指定落点
check("暴风雪是选位技能",
    Config.SkillAimOf(9) ~= nil and Config.SkillAimOf(9).mode == "point",
    Config.SkillAimOf(9) and Config.SkillAimOf(9).mode)
cs = NewCombat({ 9, 0, 0 })
PutEnemy(cs, 600, 0)
local px, py = cs.player.x, cs.player.y
cs.aimPoint = { x = px + 300, y = py }
Combat.MageCastSkill(1)
local bf = cs.mageFields[1]
check("暴风雪落在拖拽指定的位置",
    bf ~= nil and math.abs(bf.x - (px + 300)) < 2 and math.abs(bf.y - py) < 2,
    bf and (bf.x - px))
cs.aimPoint = nil

-- 11) 龙息是烈焰冲击的强化，不再挂在火球上
check("龙息依赖烈焰冲击", (function()
    local need = Config.ClassBuffSkills.mage.ma_p_dragon
    return need and need[1] == 6
end)())

-- 8) 新数值有说明文案同步（避免面板显示旧数字）
for _, sk in ipairs(Config.ClassSkills.mage) do
    if sk.id == 2 then check("冰冻波描述已更新为 1.0 倍", sk.desc:find("1.0 倍", 1, true) ~= nil, sk.desc) end
    if sk.id == 4 then check("冰锥描述已更新为 1.4 倍", sk.desc:find("1.4 倍", 1, true) ~= nil, sk.desc) end
    if sk.id == 7 then check("静电力场描述写了跟随", sk.desc:find("跟随", 1, true) ~= nil, sk.desc) end
end

print(string.format("[MageBal] done, failures = %d", fails))
