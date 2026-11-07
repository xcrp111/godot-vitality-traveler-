-- DevDeathProbe.lua — 复核测试同学报的 5 个 bug，先摸清实际行为
local Config = require "Config"
local Save = require "Save"
local S = require "State"
local Run = require "Run"
local Combat = require "Combat"

local function NewCombat(class, loadout)
    S.data = Save.Load()
    Save.SetClass(S.data, class)
    Save.SetClassLevel(S.data, 10)
    Config.SetClass(class)
    Run.Start(3, true)
    S.run.loadout = loadout or { 1, 2, 3 }
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
    -- ===== 1. 死亡判定 =====
    local cs = NewCombat("swordsman")
    cs.player.hp = 5
    cs.player.shield = 0
    Combat.DamagePlayer(cs, 100)
    print("[Probe] 裸伤致死 -> hp=" .. tostring(cs.player.hp) .. " screen=" .. tostring(S.screen))

    cs = NewCombat("swordsman")
    cs.player.hp = 5
    cs.player.shield = 0
    cs.player.hp = 0.0001
    Combat.DamagePlayer(cs, 0)
    print("[Probe] hp≈0 但伤害为 0 -> hp=" .. tostring(cs.player.hp) .. " screen=" .. tostring(S.screen))

    -- 满减伤叠满：看伤害会不会被吃到 0（那样就永远死不了）
    cs = NewCombat("swordsman")
    local p = cs.player
    p.hp = 5
    p.shield = 0
    p.flags.hurtReduction = 0.6
    p.flags.stanceDR = 0.5
    p.flags.berserk = 1
    p.hp = p.maxHp * 0.001
    cs.swordHeartTimer = 5
    Combat.DamagePlayer(cs, 100)
    print("[Probe] 减伤叠满后 -> hp=" .. tostring(cs.player.hp) .. " screen=" .. tostring(S.screen))

    -- 护盾吸收后 hp 归零
    cs = NewCombat("swordsman")
    cs.player.hp = 5
    cs.player.shield = 50
    Combat.DamagePlayer(cs, 100)
    print("[Probe] 护盾+致命伤 -> hp=" .. tostring(cs.player.hp) .. " screen=" .. tostring(S.screen))

    -- 复活
    cs = NewCombat("swordsman")
    cs.player.hp = 5
    cs.player.revive = 1
    cs.player.reviveUsed = false
    Combat.DamagePlayer(cs, 100)
    print("[Probe] 带复活 -> hp=" .. tostring(cs.player.hp) .. " screen=" .. tostring(S.screen))

    -- ===== 2. 吸血上限 =====
    cs = NewCombat("swordsman")
    p = cs.player
    p.lifesteal = 1.5     -- 多来源叠加后超过 100%
    p.hp = 10
    cs.enemies = {}
    Combat.SpawnWave(cs, { minion = 1 })
    local e = cs.enemies[1]
    e.hp, e.maxHp = 99999, 99999
    local hp0 = p.hp
    Combat.HitEnemy(cs, e, 10, false, true, true, "basic")
    print(string.format("[Probe] 吸血 150%% 打 10 点 -> 回血 %.2f（上限应为 5）", p.hp - hp0))

    -- ===== 3. 鬼剑术 =====
    cs = NewCombat("swordsman")
    p = cs.player
    Run.GrantBuff(p, { id = "sw_c_oni", name = "鬼剑术", desc = "", rarity = "color",
        classBuff = true, mod = { skillPct = 0.35 }, flag = { oni = 1 } })
    Combat.SpawnWave(cs, { minion = 1 })
    cs.enemies[1].x, cs.enemies[1].y = p.x + 40, p.y
    cs.enemies[1].hp, cs.enemies[1].maxHp = 99999, 99999
    p.intent = 5
    cs.windWaves = {}
    Combat.BasicAttack(cs)
    print("[Probe] 鬼剑术满层普攻 -> 剑气数=" .. #(cs.windWaves or {}) .. " 剑意=" .. tostring(p.intent))
    Combat.BasicAttack(cs)
    Combat.BasicAttack(cs)
    print("[Probe] 连按三次后 -> 剑气数=" .. #(cs.windWaves or {}) .. " 剑意=" .. tostring(p.intent))

    -- 贴近敌人时会不会走剑气爆发
    cs = NewCombat("swordsman")
    p = cs.player
    Run.GrantBuff(p, { id = "sw_c_oni", name = "鬼剑术", desc = "", rarity = "color",
        classBuff = true, mod = { skillPct = 0.35 }, flag = { oni = 1 } })
    Combat.SpawnWave(cs, { minion = 1 })
    cs.enemies[1].x, cs.enemies[1].y = p.x + 30, p.y
    cs.enemies[1].hp, cs.enemies[1].maxHp = 99999, 99999
    p.intent = 4        -- 未满
    cs.windWaves = {}
    Combat.BasicAttack(cs)   -- 近战补满 5 层 -> 触发爆发清层？
    print("[Probe] 未满→近战补满 -> 剑气=" .. #(cs.windWaves or {}) .. " 剑意=" .. tostring(p.intent))

    -- ===== 4. 断势重击 + 小幅震荡 =====
    cs = NewCombat("swordsman", { 1, 2, 3 })
    p = cs.player
    Run.GrantBuff(p, { id = "sw_b_break", name = "断势重击", desc = "", rarity = "blue",
        classBuff = true, mod = {}, flag = { triplePct = 0.13, tripleWind = 1 } })
    Run.GrantBuff(p, { id = "sw_b_quake", name = "小幅震荡", desc = "", rarity = "blue",
        classBuff = true, mod = {}, flag = { triplePct = 0.12, tripleKnock = 1 } })
    Combat.SpawnWave(cs, { minion = 1 })
    e = cs.enemies[1]
    e.x, e.y = p.x + 60, p.y
    e.hp, e.maxHp = 99999, 99999
    cs.windWaves = {}
    local ex, ey = e.x, e.y
    local hpB = e.hp
    Combat.CastSkill(1)
    for _ = 1, 40 do Combat.Update(1 / 60) end
    print(string.format("[Probe] 两个强化同时带 -> 剑气=%d 敌人位移=%.1f 掉了=%.0f 挫裂=%d",
        #(cs.windWaves or {}), math.abs(e.x - ex) + math.abs(e.y - ey), hpB - e.hp, e.crack or 0))

    print("[Probe] done")
end
