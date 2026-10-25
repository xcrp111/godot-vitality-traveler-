-- DevRanger.lua — 游侠基础数值 / 猎痕 / 六个技能
local Config = require "Config"
local Save = require "Save"
local S = require "State"
local Run = require "Run"
local Combat = require "Combat"
local VirtualControls = require "urhox-libs.UI.VirtualControls"

local fails = 0
local function check(name, cond, detail)
    if cond then
        print("[Ranger] OK   " .. name)
    else
        fails = fails + 1
        print("[Ranger] FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
    end
end

local function Step(cs, frames)
    for _ = 1, frames do
        Combat.Update(1 / 60)
        if S.screen ~= "combat" then return end
    end
end

local function Place(cs, dist)
    cs.enemies = {}
    Combat.SpawnWave(cs, { minion = 1 })
    local e = cs.enemies[1]
    e.hp = 3000
    e.maxHp = 3000
    e.x = cs.player.x + dist
    e.y = cs.player.y
    cs.facing = 0
    return e
end

function Start()
    VirtualControls.Initialize(Config.DESIGN_W, Config.DESIGN_H)
    S.data = Save.Load()
    Save.SetClass(S.data, "ranger")
    Save.SetClassLevel(S.data, 10)
    Config.SetClass("ranger")
    math.randomseed(21)
    Run.Start(1)
    S.run.loadout = { 1, 2, 3, 4, 5, 6 }
    local p = S.run.player
    check("生命 30", p.maxHp == 30, p.maxHp)
    check("护盾 20", p.maxShield == 20, p.maxShield)
    check("攻击 16", p.atk == 16, p.atk)
    check("远程职业", Config.Class().ranged == true)

    local cs = Combat.Start(S.run, "standard", 3)
    S.screen = "combat"
    cs.walls = {}
    cs.enemies = {}
    cs.waveIndex = #cs.waves

    -- 远程普攻 + 猎痕
    local e = Place(cs, 150)
    Combat.BasicAttack(cs)
    check("普攻生成箭矢", #cs.projs > 0, #cs.projs)
    Step(cs, 30)
    check("箭矢命中并挂猎痕", (e.hunt or 0) > 0 and e.hp < 3000,
        "hunt=" .. tostring(e.hunt) .. " hp=" .. e.hp)

    -- 疾退腾挪
    p.cooldowns[2] = 0
    local px = p.x
    Combat.CastSkill(2)
    check("疾退后撤", p.x < px)
    check("疾退获得狩猎冲动", p.intent >= 1, p.intent)
    check("疾退无敌", p.invulnTimer > 0)

    -- 精准速射
    p.cooldowns[1] = 0
    Combat.CastSkill(1)
    check("精准速射开启", (cs.rapidTimer or 0) > 0)
    e = Place(cs, 140)
    Combat.BasicAttack(cs)
    Step(cs, 30)
    check("速射层数", (cs.rapidStacks or 0) > 0, cs.rapidStacks)

    -- 穿魂狙击
    p.cooldowns[3] = 0
    e = Place(cs, 200)
    Combat.CastSkill(3)
    Step(cs, 60)
    check("狙击命中", e.hp < 3000, e.hp)
    check("狙击叠 2 层猎痕", (e.hunt or 0) >= 2, e.hunt)

    -- 猎影诱捕
    p.cooldowns[4] = 0
    e = Place(cs, 30)
    Combat.CastSkill(4)
    check("陷阱生成", #cs.rangerTraps > 0, #cs.rangerTraps)
    Step(cs, 10)
    check("陷阱触发猎痕", (e.hunt or 0) > 0 and (cs.rangerCrit or 0) > 0,
        "hunt=" .. tostring(e.hunt) .. " crit=" .. tostring(cs.rangerCrit))

    -- 箭影连射
    p.cooldowns[5] = 0
    cs.projs = {}
    Place(cs, 500)
    Combat.CastSkill(5)
    check("连射 4 支箭", #cs.projs == 4, #cs.projs)

    -- 掠袭换位
    p.cooldowns[6] = 0
    e = Place(cs, 260)
    e.hunt = 2
    local bx = p.x
    Combat.CastSkill(6)
    check("掠袭瞬移", math.abs(p.x - bx) > 20, p.x - bx)
    check("掠袭后普攻强化", (cs.rangerSwap or 0) > 0)

    print(string.format("[Ranger] done, failures = %d", fails))
end
