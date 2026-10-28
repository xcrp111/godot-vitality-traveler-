-- DevPauseStatus.lua — 战斗暂停菜单 / 选关界面状态面板 / 测试模式怪物等级
local Config = require "Config"
local Save = require "Save"
local S = require "State"
local Run = require "Run"
local Combat = require "Combat"

local fails = 0
local function check(name, cond, detail)
    if cond then
        print("[Pause] OK   " .. name)
    else
        fails = fails + 1
        print("[Pause] FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
    end
end

local function NewCombat()
    S.data = Save.Load()
    Save.SetClass(S.data, "swordsman")
    Save.SetClassLevel(S.data, 8)
    Config.SetClass("swordsman")
    Run.Start(3)
    local cs = Combat.Start(S.run, "standard", 2)
    S.screen = "combat"
    cs.enemies = {}
    cs.walls = {}
    cs.waves = { {} }
    cs.waveIndex = 1
    return cs
end

function Start()
    -- ================= 暂停 =================
    local cs = NewCombat()
    check("初始未暂停", cs.paused == false, tostring(cs.paused))

    local hp0 = cs.player.hp
    Combat.SetPaused(cs, true)
    check("暂停已开启", cs.paused == true)
    check("暂停清空摇杆输入", S.input.x == 0 and S.input.y == 0)

    -- 暂停期间手动打技能不应生效
    local before = cs.player.attackTimer
    Combat.ManualAttack()
    check("暂停时普攻不生效", cs.player.attackTimer == before, cs.player.attackTimer)

    Combat.TogglePause()
    check("再按一次恢复", cs.paused == false)

    -- 暂停时开状态面板，先恢复再打开
    Combat.SetPaused(cs, true)
    cs.statusPanel = cs.statusPanel or { page = 1, detail = nil }
    Combat.SetPaused(cs, false)
    cs.showBuffs = true
    check("状态面板可打开", cs.showBuffs == true)

    -- ================= 选关界面状态面板 =================
    S.showStatus = false
    S.statusPanel = nil
    S.screen = "map"
    check("默认不显示选关面板", S.showStatus == false)
    S.showStatus = true
    S.statusPanel = S.statusPanel or { page = 1, detail = nil }
    check("选关面板状态表就绪", type(S.statusPanel) == "table" and S.statusPanel.page == 1)

    -- 面板用的是 run.player，确保选关时玩家数据在
    check("选关时玩家存在", S.run and S.run.player ~= nil)
    check("选关时玩家有 hp", S.run.player and S.run.player.maxHp > 0, S.run.player and S.run.player.maxHp)

    -- 返回主菜单时应自动收起
    Run.ReturnToMenu()
    check("回菜单收起选关面板", S.showStatus == false)

    -- ================= 测试模式怪物等级 =================
    local hp1 = Config.MonsterStats(1, 1, "minion")
    local hp5 = Config.MonsterStats(5, 1, "minion")
    local hp10 = Config.MonsterStats(10, 1, "minion")
    check("怪物血量随等级递增", hp1 < hp5 and hp5 < hp10,
        string.format("%d / %d / %d", hp1, hp5, hp10))

    local atk1 = Config.MonsterStats(1, 1, "minion")
    local boss10 = Config.MonsterStats(10, 1, "boss")
    check("Boss 明显高于小兵", boss10 > hp10 * 4, boss10 .. " vs " .. hp10)

    -- 测试模式确实按所选等级生成怪物
    S.testLevel = 7
    S.data = Save.Load()
    Save.SetClass(S.data, "swordsman")
    Save.SetClassLevel(S.data, 10)
    Config.SetClass("swordsman")
    Run.Start(math.max(1, math.min(20, S.testLevel)), true)
    local cs2 = Combat.Start(S.run, "standard", 1)
    cs2.testMode = true
    cs2.waves = {}
    cs2.enemies = {}
    S.screen = "combat"
    Combat.SpawnTestEnemy(cs2, "minion", "germ")
    local e = cs2.enemies[1]
    local expectHp = Config.MonsterStats(7, 1, "minion")
    check("测试模式按所选等级生成", e ~= nil and e.maxHp == expectHp,
        e and (e.maxHp .. " vs " .. expectHp))

    print("[Pause] done, failures = " .. fails)
end
