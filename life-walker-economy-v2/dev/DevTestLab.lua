-- DevTestLab.lua — 测试模式：自选强化 / 技能 / 怪物后直接进战斗
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
        print("[Lab] OK   " .. name)
    else
        fails = fails + 1
        print("[Lab] FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
    end
end

function Start()
    VirtualControls.Initialize(Config.DESIGN_W, Config.DESIGN_H)
    S.data = Save.Load()
    Save.SetClass(S.data, "swordsman")
    Save.SetClassLevel(S.data, 14)
    math.randomseed(5)

    S.testMonsterCount = { germ = 2, mycel = 1 }
    S.testBuffs = { sw_b_break = true, sw_p_reset = true, sw_c_oni = true }
    S.testGeneral = { w_atk = true }
    S.testSkills = { [1] = true, [4] = true }
    S.testLevel = 3

    Menu.StartTestRun()
    check("进入战斗", S.screen == "combat" and S.combat ~= nil)
    local cs = S.combat
    local p = cs and cs.player
    check("测试标记", cs and cs.testMode == true)
    check("怪物数量", cs and #cs.enemies == 3, cs and #cs.enemies)
    check("关卡等级", cs and cs.run.level == 3, cs and cs.run.level)
    check("专属生效 断势重击", p and (p.flags.tripleWind or 0) == 1)
    check("专属生效 瞬斩重置", p and (p.flags.tripleReset or 0) == 1)
    check("专属生效 鬼剑术", p and (p.flags.oni or 0) == 1)
    check("通用生效 攻击+15%", p and p.atk > p.baseAtk, p and (p.atk - p.baseAtk))
    check("技能携带", cs and #cs.run.loadout >= 2 and cs.run.loadout[1] == 1,
        cs and table.concat(cs.run.loadout, ","))
    check("存档等级未被改动", Save.ClassLevel(S.data) == 14, Save.ClassLevel(S.data))

    for _ = 1, 120 do
        cs.cleared = false
        cs.clearTimer = 0
        Combat.Update(1 / 60)
        if S.screen ~= "combat" then break end
    end
    check("长跑后仍在战斗", S.screen == "combat", S.screen)

    print(string.format("[Lab] done, failures = %d", fails))
end
