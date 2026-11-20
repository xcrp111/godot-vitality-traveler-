-- DevMonsters.lua — 新怪物（脓肿岩行者 / 疫蚀石魔 / 瘟衰巨像）与测试模式投放
local Config = require "Config"
local Save = require "Save"
local S = require "State"
local Run = require "Run"
local Combat = require "Combat"
local Menu = require "Menu"
local VirtualControls = require "urhox-libs.UI.VirtualControls"

local fails = 0
local function check(name, cond, detail)
    if cond then
        print("[Mob] OK   " .. name)
    else
        fails = fails + 1
        print("[Mob] FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
    end
end

local function Setup()
    Save.SetClass(S.data, "swordsman")
    Save.SetClassLevel(S.data, 10)
    Config.SetClass("swordsman")
    Run.Start(1)
    local cs = Combat.Start(S.run, "standard", 3)
    cs.enemies = {}
    cs.walls = {}
    cs.waveIndex = #cs.waves
    S.screen = "combat"
    cs.player.maxHp = 9999
    cs.player.hp = 9999
    cs.player.shield = 0
    return cs
end

local function Step(cs, frames)
    for _ = 1, frames do Combat.Update(1 / 60) end
end

function Start()
    VirtualControls.Initialize(Config.DESIGN_W, Config.DESIGN_H)
    S.data = Save.Load()
    math.randomseed(41)

    -- 脓肿岩行者：感染 + 残血脓水
    local cs = Setup()
    Combat.SpawnTestEnemy(cs, "minion", "abscess")
    local e = cs.enemies[1]
    e.attackCd = 0
    e.x = cs.player.x + 20
    e.y = cs.player.y
    Step(cs, 10)
    check("脓肿岩行者命中附加感染", (cs.player.infectTimer or 0) > 0, cs.player.infectTimer)
    e.hp = e.maxHp * 0.2
    Step(cs, 5)
    check("脓肿岩行者残血留下脓水", #cs.hazardFields > 0, #cs.hazardFields)

    -- 疫蚀石魔：坏死 + 跺脚腐液
    cs = Setup()
    Combat.SpawnTestEnemy(cs, "elite", "golem")
    e = cs.enemies[1]
    e.attackCd = 0
    e.x = cs.player.x + 20
    e.y = cs.player.y
    e.stompCd = 0.05
    Step(cs, 12)
    check("石魔命中附加坏死", (cs.player.necrosisTimer or 0) > 0, cs.player.necrosisTimer)
    check("石魔跺脚生成腐液", #cs.hazardFields > 0, #cs.hazardFields)

    -- 瘟衰巨像：衰弱 + 疫域 + 腐化冲击波
    cs = Setup()
    Combat.SpawnTestEnemy(cs, "boss", "colossus")
    e = cs.enemies[1]
    e.attackCd = 0
    e.x = cs.player.x + 20
    e.y = cs.player.y
    e.bossSkillCd = 0.05
    Step(cs, 12)
    check("巨像命中附加衰弱", (cs.player.weakenTimer or 0) > 0, cs.player.weakenTimer)
    local shock = false
    for _, b in ipairs(cs.bullets) do if b.shock then shock = true end end
    check("巨像释放腐化冲击波", shock)
    e.hp = e.maxHp * 0.45
    Step(cs, 5)
    check("巨像半血狂暴", e.enraged == true, e.enraged)

    -- 测试模式：三种新怪同时投放
    cs = Setup()
    S.testMonsterCount = { abscess = 1, golem = 1, colossus = 1 }
    S.testBuffs = {}
    S.testGeneral = {}
    S.testSkills = {}
    S.testLevel = 5
    Menu.StartTestRun()
    cs = S.combat
    local ids = {}
    for _, en in ipairs(cs.enemies) do ids[en.id] = (ids[en.id] or 0) + 1 end
    check("测试模式投放脓肿岩行者", (ids.abscess or 0) == 1, ids.abscess)
    check("测试模式投放疫蚀石魔", (ids.golem or 0) == 1, ids.golem)
    check("测试模式投放瘟衰巨像", (ids.colossus or 0) == 1, ids.colossus)
    check("测试模式怪物总数", #cs.enemies == 3, #cs.enemies)

    -- 第 7 关起：新怪物进入正常房间
    local function LateSetup(level)
        Save.SetClassLevel(S.data, 10)
        Run.Start(level, true)   -- 关卡门槛会夹到已解锁进度，测试直接绕过
        local c = Combat.Start(S.run, "standard", 1)
        c.enemies = {}
        c.walls = {}
        c.waveIndex = #c.waves
        S.screen = "combat"
        return c
    end
    local c7 = LateSetup(7)
    Combat.SpawnWave(c7, { boss = 1 })
    check("第 7 关 Boss 为瘟衰巨像", c7.enemies[1] and c7.enemies[1].id == "colossus",
        c7.enemies[1] and c7.enemies[1].id)
    c7.enemies = {}
    local eliteIds = {}
    for _ = 1, 40 do Combat.SpawnWave(c7, { elite = 1 }) end
    for _, e in ipairs(c7.enemies) do eliteIds[e.id] = (eliteIds[e.id] or 0) + 1 end
    check("第 7 关精英混入疫蚀石魔", (eliteIds.golem or 0) > 0, eliteIds.golem)
    check("第 7 关仍会刷菌丝怪", (eliteIds.mycel or 0) > 0, eliteIds.mycel)
    c7.enemies = {}
    local minionAbscess = 0
    for _ = 1, 60 do Combat.SpawnWave(c7, { minion = 1 }) end
    for _, e in ipairs(c7.enemies) do
        if e.id == "abscess" then minionAbscess = minionAbscess + 1 end
    end
    check("第 7 关小兵混入脓肿岩行者", minionAbscess > 0, minionAbscess)

    local c6 = LateSetup(6)
    Combat.SpawnWave(c6, { boss = 1 })
    check("第 6 关 Boss 仍是高热疫魔", c6.enemies[1] and c6.enemies[1].id == "plague",
        c6.enemies[1] and c6.enemies[1].id)
    c6.enemies = {}
    local earlyNew = 0
    for _ = 1, 40 do Combat.SpawnWave(c6, { minion = 1 }) end
    for _, e in ipairs(c6.enemies) do
        if e.id == "abscess" then earlyNew = earlyNew + 1 end
    end
    check("第 6 关不出现新小兵", earlyNew == 0, earlyNew)

    print(string.format("[Mob] done, failures = %d", fails))
end
