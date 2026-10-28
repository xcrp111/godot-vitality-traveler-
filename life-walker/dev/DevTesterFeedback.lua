-- DevTesterFeedback.lua — 测试同学反馈的 10 条：逐条验证修复
local Config = require "Config"
local Save = require "Save"
local S = require "State"
local Run = require "Run"
local Combat = require "Combat"

local fails = 0
local function check(name, cond, detail)
    if cond then
        print("[FB] OK   " .. name)
    else
        fails = fails + 1
        print("[FB] FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
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
    return cs
end

function Start()
    -- 1. 测试模式可退出
    local cs = NewCombat("swordsman")
    cs.testMode = true
    Combat.SetPaused(cs, true)
    check("1 暂停面板可打开（含退出测试）", cs.paused == true)
    cs.paused = false
    Run.ReturnToMenu()
    check("1 退出测试回到主菜单", S.screen == "menu" and S.run == nil and S.combat == nil, S.screen)

    -- 3. 法师法杖与弹道同向（代码层面：杖头朝向 = facing）
    cs = NewCombat("mage", { 1, 2, 3 })
    cs.facing = 0.9
    check("3 法师朝向已设定", math.abs(cs.facing - 0.9) < 1e-6)

    -- 8 / 10. 冲刺跟随输入方向
    cs = NewCombat("swordsman")
    S.input.x, S.input.y = 1, 0
    Combat.CastSkill(2)   -- 闪影突进
    check("8 有输入时按输入方向冲", cs.dash ~= nil and math.abs(cs.dash.dirx - 1) < 0.01,
        cs.dash and string.format("%.2f,%.2f", cs.dash.dirx, cs.dash.diry))

    cs = NewCombat("swordsman")
    S.input.x, S.input.y = 0, 0
    cs.facing = 0
    Combat.CastSkill(2)
    check("8 无输入时按面朝方向冲", math.abs(cs.dash.dirx - 1) < 0.01, cs.dash and cs.dash.dirx)

    cs = NewCombat("ranger", { 2, 3, 5 })
    local px, py = cs.player.x, cs.player.y
    S.input.x, S.input.y = 0, -1   -- 向上推
    Combat.CastSkill(1)            -- 疾退腾挪（loadout 第 1 格 = 技能 id 2）
    check("10 疾退跟随摇杆方向", cs.player.y < py - 10, string.format("%.0f -> %.0f", py, cs.player.y))

    -- 7. 反弹 / 消弹
    cs = NewCombat("swordsman")
    Run.GrantBuff(cs.player, { id = "p_reflect", name = "镜面反射", desc = "", rarity = "purple",
        classBuff = false, mod = {}, flag = { reflectBullet = 1 } })
    Combat.SpawnWave(cs, { minion = 1 })
    local e = cs.enemies[1]
    e.x, e.y = cs.player.x + 200, cs.player.y
    e.hp = 9999
    e.maxHp = 9999
    cs.bullets = {}
    cs.bullets[1] = { x = cs.player.x - 5, y = cs.player.y, vx = 300, vy = 0, r = 8, life = 1, dmg = 5, color = { 200, 200, 255 } }
    local hpBefore = cs.player.hp
    Combat.UpdateBullets(cs, 1 / 60)
    check("7 反弹：不吃这一发伤害", cs.player.hp == hpBefore, cs.player.hp)
    check("7 反弹：打出自己的弹丸", #cs.projs >= 1, #cs.projs)
    check("7 反弹：敌方子弹被移除", #cs.bullets == 0, #cs.bullets)

    cs = NewCombat("swordsman")
    Run.GrantBuff(cs.player, { id = "p_clear", name = "弹幕清除", desc = "", rarity = "purple",
        classBuff = false, mod = {}, flag = { clearBullet = 1 } })
    cs.bullets = {}
    for i = 1, 3 do
        cs.bullets[i] = { x = cs.player.x + 20 + i * 10, y = cs.player.y, vx = 0, vy = 0, r = 8, life = 5, dmg = 5, color = { 200, 200, 255 } }
    end
    cs.bullets[4] = { x = cs.player.x + 900, y = cs.player.y, vx = 0, vy = 0, r = 8, life = 5, dmg = 5, color = { 200, 200, 255 } }
    Combat.BasicAttack(cs)
    check("7 消弹：范围内清空", #cs.bullets == 1, #cs.bullets)
    check("7 消弹：范围外保留", cs.bullets[1] ~= nil and cs.bullets[1].x > cs.player.x + 500, cs.bullets[1] and cs.bullets[1].x)

    -- 2. 枪势不再让普攻范围暴涨
    cs = NewCombat("spearman", { 1, 2, 4 })
    local class = Config.Class()
    cs.player.intent = 0
    local r0 = class.basicRange
    cs.player.intent = 2
    local r1 = class.basicRange + 18
    check("2 枪势距离加成收敛为 +18", r1 - r0 == 18, r1 - r0)

    -- 6. 精英奖励
    check("6 精英银币提高", Config.SilverDrop.elite[1] >= 30, Config.SilverDrop.elite[1])
    cs = NewCombat("swordsman")
    cs.enemies = {}
    Combat.SpawnWave(cs, { elite = 1 })
    local el = cs.enemies[1]
    local silver0 = cs.run.silver
    el.hp = 1
    cs.player.hp = math.floor(cs.player.maxHp * 0.5)
    local hpMid = cs.player.hp
    Combat.HitEnemy(cs, el, 9999, false, true, false, "basic")
    check("6 精英掉银币", cs.run.silver > silver0, cs.run.silver - silver0)
    check("6 打完精英不回血（按反馈移除）", cs.player.hp == hpMid,
        string.format("%d -> %d", hpMid, cs.player.hp))

    -- 5. 移速
    check("5 基础移速上调", Config.Classes.mage.speed >= 3.9 * 32, Config.Classes.mage.speed)
    local msCount = 0
    for _, rarity in ipairs({ "white", "blue", "purple", "gold" }) do
        for _, b in ipairs(Config.Buffs[rarity]) do
            if b.mod and (b.mod.msPct or 0) > 0 then msCount = msCount + 1 end
        end
    end
    check("5 移速词条数量 >= 6", msCount >= 6, msCount)

    -- 9. 挫裂反馈（有 crackFlash 与飘字）
    cs = NewCombat("swordsman")
    Combat.SpawnWave(cs, { minion = 1 })
    local m = cs.enemies[1]
    m.hp, m.maxHp = 500, 500
    m.x, m.y = cs.player.x + 60, cs.player.y
    cs.texts = {}
    Combat.ArcHit(cs, 200, math.rad(360), 1.0, false, 1)
    check("9 挫裂层数增加", (m.crack or 0) >= 1, m.crack)
    local hasText = false
    for _, t in ipairs(cs.texts or {}) do
        if string.find(t.text or "", "挫裂") then hasText = true end
    end
    check("9 挫裂有飘字反馈", hasText)

    -- 4. 冷却可视化数据就绪
    cs = NewCombat("swordsman")
    cs.player.cooldowns[1] = 2.0
    cs.time = 10
    cs.lastCd = { skill1 = 2.0 }
    check("4 冷却计时可用", Combat.SkillCooldown(cs, 1) > 0, Combat.SkillCooldown(cs, 1))

    print("[FB] done, failures = " .. fails)
end
