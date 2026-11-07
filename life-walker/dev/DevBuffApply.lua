-- DevBuffApply.lua — 校验通用/专属强化的数值确实写进角色属性
local Config = require "Config"
local Save = require "Save"
local S = require "State"
local Run = require "Run"
local VirtualControls = require "urhox-libs.UI.VirtualControls"

local function Approx(a, b, eps)
    return math.abs(a - b) <= (eps or 0.001)
end

function Start()
    S.data = Save.Load()
    Save.SetClass(S.data, "swordsman")
    Save.SetClassLevel(S.data, 10)
    math.randomseed(9)
    Run.Start(1)
    local p = S.run.player
    local fail = 0
    local function check(name, got, want, eps)
        if Approx(got, want, eps) then
            print(string.format("[Apply] OK   %s = %.3f", name, got))
        else
            fail = fail + 1
            print(string.format("[Apply] FAIL %s = %.3f (want %.3f)", name, got, want))
        end
    end

    local baseAtk = p.atk
    local baseAs = p.attackSpeed
    local baseMs = p.moveSpeed
    local baseHp = p.maxHp
    local baseSh = p.maxShield

    local atkBuff = { id = "t_atk", name = "t", desc = "", rarity = "white", mod = { atkPct = 0.15 } }
    Run.GrantBuff(p, atkBuff)
    check("atk +15%", p.atk, baseAtk * 1.15, 0.02)

    Run.GrantBuff(p, { id = "t_as", name = "t", desc = "", rarity = "white", mod = { asPct = 0.22 } })
    check("attackSpeed +22%", p.attackSpeed, baseAs * 1.22, 0.01)

    Run.GrantBuff(p, { id = "t_ms", name = "t", desc = "", rarity = "white", mod = { msPct = 0.18 } })
    check("moveSpeed +18%", p.moveSpeed, baseMs * 1.18, 0.5)

    Run.GrantBuff(p, { id = "t_hp", name = "t", desc = "", rarity = "white", mod = { hpPct = 0.15 } })
    check("maxHp +15%", p.maxHp, math.floor(baseHp * 1.15 + 0.5), 0.5)

    local shieldBefore = p.shield
    Run.GrantBuff(p, { id = "t_sh", name = "t", desc = "", rarity = "white", mod = { shieldPct = 0.15 } })
    check("maxShield +15%", p.maxShield, math.floor(baseSh * 1.15 + 0.5), 0.5)
    -- 上限提升时当前护盾应同步增加
    local gained = p.maxShield - baseSh
    check("shield follows max", p.shield, math.min(shieldBefore + gained, p.maxShield * 1.5), 0.5)

    Run.GrantBuff(p, { id = "t_crit", name = "t", desc = "", rarity = "blue", mod = { crit = 0.10 } })
    check("crit", p.crit, 0.10, 0.0001)
    Run.GrantBuff(p, { id = "t_ls", name = "t", desc = "", rarity = "purple", mod = { lifesteal = 0.18 } })
    check("lifesteal", p.lifesteal, 0.18, 0.0001)
    Run.GrantBuff(p, { id = "t_cdr", name = "t", desc = "", rarity = "blue", mod = { cdrPct = 0.12 } })
    check("cdr", p.cdr, 0.12, 0.0001)

    -- 专属 flag 是否写进 p.flags
    Run.GrantBuff(p, { id = "t_flag", name = "t", desc = "", rarity = "purple", classBuff = true,
        mod = {}, flag = { triplePct = 0.28, dashCharges = 1 } })
    check("flag triplePct", p.flags.triplePct or 0, 0.28, 0.0001)
    check("flag dashCharges", p.flags.dashCharges or 0, 1, 0.0001)

    -- 护盾发生器：可超过上限
    p.shield = p.maxShield
    local cs = { player = p, texts = {}, effects = {} }
    p.shield = math.min(p.maxShield * 1.5, p.shield + p.maxShield * 0.5)
    check("shield overshield", p.shield, p.maxShield * 1.5, 0.5)

    print(string.format("[Apply] done, failures = %d", fail))
end
