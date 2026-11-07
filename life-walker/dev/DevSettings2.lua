-- DevSettings2.lua — 设置项接线验证（不改画面，只验逻辑）
local Config = require "Config"
local Save = require "Save"
local S = require "State"
local Run = require "Run"
local Combat = require "Combat"
local Menu = require "Menu"
local UI = require "UI"

local fails = 0
local function check(name, cond, detail)
    if cond then
        print("[Set2] OK   " .. name)
    else
        fails = fails + 1
        print("[SET2] FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
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
    cs.player.shield = 0
    return cs
end

function Start()
    -- 默认值齐全
    local def = Save.Defaults()
    check("默认帧率 60", def.fpsCap == 60, def.fpsCap)
    check("默认伤害数字完整", def.damageText == "full", def.damageText)
    check("默认灵敏中", def.joySensitivity == "mid", def.joySensitivity)
    check("默认长按 0.22", def.aimHold == 0.22, def.aimHold)
    check("默认自动攻击开", def.autoAttack == true, def.autoAttack)
    check("默认血条/预警开", def.enemyHpBar == true and def.bossWarn == true)

    -- 帧率上限真的写进引擎
    S.data = Save.Fresh()
    S.data.fpsCap = 30
    Menu.ApplyFps(S.data)
    check("帧率上限写入引擎", engine == nil or engine.maxFps == 30,
        engine and engine.maxFps)

    -- 伤害数字：关闭后不再产生飘字
    local cs = NewCombat("swordsman")
    S.data.damageText = "off"
    Combat.SpawnWave(cs, { minion = 1 })
    local e = cs.enemies[1]
    e.hp, e.maxHp = 99999, 99999
    cs.texts = {}
    Combat.HitEnemy(cs, e, 100, false, true, true, "basic")
    check("伤害数字关闭后无飘字", #cs.texts == 0, #cs.texts)

    cs = NewCombat("swordsman")
    S.data.damageText = "full"
    Combat.SpawnWave(cs, { minion = 1 })
    e = cs.enemies[1]
    e.hp, e.maxHp = 99999, 99999
    cs.texts = {}
    Combat.HitEnemy(cs, e, 100, false, true, true, "basic")
    check("伤害数字打开后有飘字", #cs.texts > 0, #cs.texts)

    -- 低画质：粒子数量减量
    cs = NewCombat("swordsman")
    S.data.lowQuality = false
    cs.effects = {}
    local csx = cs
    Combat.SpawnWave(csx, { minion = 1 })
    local e1 = csx.enemies[1]
    e1.x, e1.y = csx.player.x + 40, csx.player.y
    e1.hp, e1.maxHp = 1, 1
    Combat.HitEnemy(csx, e1, 999, false, true, true, "basic")
    local normalFx = #csx.effects

    cs = NewCombat("swordsman")
    S.data.lowQuality = true
    cs.effects = {}
    Combat.SpawnWave(cs, { minion = 1 })
    local e2 = cs.enemies[1]
    e2.x, e2.y = cs.player.x + 40, cs.player.y
    e2.hp, e2.maxHp = 1, 1
    Combat.HitEnemy(cs, e2, 999, false, true, true, "basic")
    local lowFx = #cs.effects
    check("低画质粒子减量", lowFx < normalFx, string.format("%d -> %d", normalFx, lowFx))

    -- 自动攻击开关
    cs = NewCombat("swordsman")
    S.data.autoAttack = true
    Combat.SpawnWave(cs, { minion = 1 })
    cs.enemies[1].x, cs.enemies[1].y = cs.player.x + 40, cs.player.y
    cs.enemies[1].hp, cs.enemies[1].maxHp = 99999, 99999
    cs.player.attackTimer = 0
    local hpA = cs.enemies[1].hp
    Combat.Update(0.05)
    check("自动攻击开启时会出手", cs.enemies[1].hp < hpA or cs.player.attackTimer > 0,
        cs.player.attackTimer)

    cs = NewCombat("swordsman")
    S.data.autoAttack = false
    Combat.SpawnWave(cs, { minion = 1 })
    cs.enemies[1].x, cs.enemies[1].y = cs.player.x + 40, cs.player.y
    cs.enemies[1].hp, cs.enemies[1].maxHp = 99999, 99999
    cs.player.attackTimer = 0
    cs.player.attackQueued = false
    local hpB = cs.enemies[1].hp
    Combat.Update(0.05)
    check("自动攻击关闭时不出手", cs.enemies[1].hp == hpB and cs.player.attackTimer <= 0,
        string.format("%d -> %d", hpB, cs.enemies[1].hp))
    S.data.autoAttack = true

    -- 长按阈值：0.30 秒时，按 0.25 秒松手不该锁定方向
    cs = NewCombat("mage", { 1, 3, 8 })
    cs.player.crit = 0
    S.data.aimHold = 0.30
    local bx, by = Combat.CtrlPos("skill1", 1080, 624, 36)
    Combat.AimPointer("down", bx, by, 41)
    Combat.AimPointer("move", bx, by - 100, 41)
    cs.aim.t = 0.25
    Combat.AimPointer("up", bx, by - 100, 41)
    check("阈值 0.30：按 0.25 秒松手不锁方向（走智能施法）",
        cs.aim == nil and cs.aimLock == nil, tostring(cs.aimLock))

    cs = NewCombat("mage", { 1, 3, 8 })
    S.data.aimHold = 0.15
    Combat.AimPointer("down", bx, by, 42)
    Combat.AimPointer("move", bx, by - 100, 42)
    cs.aim.t = 0.2
    local aimAngle = cs.aim.angle
    Combat.AimPointer("up", bx, by - 100, 42)
    check("阈值 0.15：按 0.2 秒松手按瞄准方向释放",
        math.abs(cs.facing - aimAngle) < 1e-6, string.format("%.3f vs %.3f", cs.facing, aimAngle))
    S.data.aimHold = 0.22

    -- 摇杆灵敏度：高灵敏轻推就走，低灵敏同幅度不动
    cs = NewCombat("swordsman")
    local js = cs.joystick
    S.data.joySensitivity = "high"
    Combat.JoystickPointer("down", js.anchorX, js.anchorY, 51)
    Combat.JoystickPointer("move", js.anchorX, js.anchorY - js.radius * 0.08, 51)
    local highInput = math.abs(S.input.y)
    Combat.JoystickPointer("up", js.anchorX, js.anchorY, 51)

    S.data.joySensitivity = "low"
    Combat.JoystickPointer("down", js.anchorX, js.anchorY, 52)
    Combat.JoystickPointer("move", js.anchorX, js.anchorY - js.radius * 0.08, 52)
    local lowInput = math.abs(S.input.y)
    Combat.JoystickPointer("up", js.anchorX, js.anchorY, 52)
    check("高灵敏轻推就有输入、低灵敏不死区外不动", highInput > 0 and lowInput == 0,
        string.format("high=%.3f low=%.3f", highInput, lowInput))
    S.data.joySensitivity = "mid"

    -- 清空存档走的是全新存档
    local fresh = Save.Fresh()
    check("全新存档字段完整", fresh.aimMode == "button" and fresh.fpsCap == 60 and fresh.exp == 0,
        tostring(fresh.fpsCap))

    -- ============ 设置界面本身：能画、按钮能点、改动能落到存档 ============
    local okUi, errUi = pcall(function()
        S.ctx = nvgCreate(1)
        S.font = nvgCreateFont(S.ctx, "sans", "Fonts/MiSans-Regular.ttf")
        S.data = Save.Load()
        S.screen = "menu"
        S.settings = true
        S.settingsTab = "control"
        Menu.Draw()                                  -- 注册所有按钮区域
        check("设置界面能正常绘制", true)

        UI.Click(304, 191)                           -- 左侧「画面与性能」
        Menu.Draw()
        check("点左侧分类能切页", S.settingsTab == "visual", S.settingsTab)

        UI.Click(1020, 176)                          -- 帧率 120
        check("点帧率按钮生效", S.data.fpsCap == 120, S.data.fpsCap)

        Menu.Draw()
        UI.Click(850, 238)                           -- 低画质开关
        check("点开关生效", S.data.lowQuality == true, S.data.lowQuality)

        UI.Click(304, 365)                           -- 左侧「数据与帮助」
        Menu.Draw()
        UI.Click(885, 300)                           -- 恢复默认设置（数据页第 3 行）
        check("恢复默认设置生效", S.data.fpsCap == 60 and S.data.lowQuality == false,
            string.format("fps=%s lowq=%s", tostring(S.data.fpsCap), tostring(S.data.lowQuality)))

        S.settings = false
    end)
    if not okUi then check("设置界面能正常绘制", false, tostring(errUi)) end

    print("[Set2] done, failures = " .. fails)
end
