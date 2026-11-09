-- DevEffectCheck.lua — 逐个验证专属强化的可见效果是否真的触发
local Config = require "Config"
local Save = require "Save"
local S = require "State"
local Run = require "Run"
local Combat = require "Combat"
local VirtualControls = require "urhox-libs.UI.VirtualControls"

local fails = 0

local function check(name, cond, detail)
    if cond then
        print("[Effect] OK   " .. name)
    else
        fails = fails + 1
        print("[Effect] FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
    end
end

local function Step(cs, frames)
    for _ = 1, frames do
        if #cs.enemies == 0 then
            Combat.SpawnWave(cs, { minion = 2 })
        end
        local fx, fy = math.cos(cs.facing), math.sin(cs.facing)
        for _, e in ipairs(cs.enemies) do
            if e.hp > 500 then e.hp = 500 end
            e.maxHp = 500
            e.x = cs.player.x + fx * 45
            e.y = cs.player.y + fy * 45
        end
        cs.cleared = false
        cs.clearTimer = 0
        Combat.Update(1 / 60)
    end
end

local function Grant(id, mod, flag)
    Run.GrantBuff(S.run.player, {
        id = id, name = id, desc = "", rarity = "purple",
        classBuff = true, mod = mod or {}, flag = flag or {},
    })
end

function Start()
    S.data = Save.Load()
    Save.SetClass(S.data, "swordsman")
    Save.SetClassLevel(S.data, 10)
    math.randomseed(4)
    Run.Start(1)
    S.run.loadout = { 1, 2, 4 }
    local cs = Combat.Start(S.run, "standard", 3)
    cs.enemies = {}
    cs.waveIndex = #cs.waves
    Combat.SpawnWave(cs, { minion = 3 })
    S.screen = "combat"
    local p = cs.player
    p.maxHp = 9999
    p.hp = 9999

    -- 1. 鬼剑术：剑意满 -> 远程剑气
    Grant("t_oni", { skillPct = 0.35 }, { oni = 1 })
    p.intent = 0
    p.cooldowns = {}
    local waveBefore = cs.waveCount or 0
    Combat.BasicAttack(cs)
    check("鬼剑术 剑意不满时仍是近战", (cs.waveCount or 0) == waveBefore,
        "waveCount=" .. tostring(cs.waveCount))
    -- 重新放一个 120 像素外的靶子，专门验证剑气伤害
    cs.enemies = {}
    Combat.SpawnWave(cs, { minion = 1 })
    local target = cs.enemies[1]
    target.hp = 500
    target.maxHp = 500
    target.x = p.x + 120
    target.y = p.y
    cs.facing = 0
    p.intent = 5 + math.floor(p.flags.intentCapDelta or 0)
    local hpBefore = target.hp
    Combat.BasicAttack(cs)
    check("鬼剑术 满剑意发射剑气", (cs.waveCount or 0) == waveBefore + 1
        and #cs.windWaves == 1, "waveCount=" .. tostring(cs.waveCount) .. " waves=" .. #cs.windWaves)
    for _ = 1, 15 do Combat.Update(1 / 60) end
    check("剑气命中并造成伤害", target.hp < hpBefore,
        "hp " .. tostring(hpBefore) .. " -> " .. tostring(target.hp))

    -- 2. 断势重击：三段第三段变剑气
    Grant("t_wind", {}, { triplePct = 0.13, tripleWind = 1 })
    local beforeWind = cs.waveCount or 0
    p.cooldowns[1] = 0
    Combat.CastSkill(1)
    Step(cs, 60)
    check("断势重击 第三段剑气", (cs.waveCount or 0) > beforeWind,
        "waveCount=" .. tostring(cs.waveCount))

    -- 3. 虚影回响：复刻刚释放的技能（概率拉到 100%）
    Grant("t_illusion", {}, { illusionChance = 1.0 })
    local beforeIll = cs.phantomCount or 0
    p.cooldowns[1] = 0
    Combat.CastSkill(1)
    check("虚影回响 立即登记剑影", (cs.phantomCount or 0) == beforeIll + 1,
        "phantoms=" .. tostring(cs.phantomCount))
    check("虚影回响 有可见剑影对象", #cs.phantoms >= 1, "list=" .. #cs.phantoms)
    local illPh = nil
    for i = #cs.phantoms, 1, -1 do
        if cs.phantoms[i].kind == "illusion" then illPh = cs.phantoms[i] break end
    end
    check("虚影回响 复刻三段斩", illPh and illPh.skill == 1,
        illPh and illPh.skill or "none")
    local beforeHits = cs.phantomHits or 0
    Step(cs, 40)
    check("虚影回响 复刻攻击执行", (cs.phantomHits or 0) > beforeHits,
        tostring(cs.phantomHits))

    -- 4. 残影留存：复刻刚释放的技能（旋刃横斩）
    Grant("t_phantom", {}, { phantomPct = 0.9 })
    local beforePh = cs.phantomCount or 0
    p.cooldowns[4] = 0
    Combat.CastSkill(3) -- loadout 第 3 格是旋刃横斩
    check("残影留存 登记剑影", (cs.phantomCount or 0) >= beforePh + 1,
        "phantoms=" .. tostring(cs.phantomCount))
    local phPh = nil
    for i = #cs.phantoms, 1, -1 do
        if cs.phantoms[i].kind == "phantom" then phPh = cs.phantoms[i] break end
    end
    check("残影留存 复刻旋刃横斩", phPh and phPh.skill == 4,
        phPh and phPh.skill or "none")
    local beforePhHits = cs.phantomHits or 0
    Step(cs, 40)
    check("残影留存 复刻攻击执行", (cs.phantomHits or 0) > beforePhHits,
        tostring(cs.phantomHits))

    -- 5. 瞬斩重置：三段全中返还冷却
    Grant("t_reset", {}, { triplePct = 0.28, tripleReset = 1, tripleFullIntent = 2 })
    p.cooldowns[1] = 0
    p.intent = 0
    Combat.CastSkill(1)
    Step(cs, 60)
    check("瞬斩重置 冷却清空", (p.cooldowns[1] or 0) <= 0.001,
        "cd=" .. tostring(p.cooldowns[1]))

    -- 6. 双重闪击：冷却中也能靠充能再放一次
    Grant("t_charge", {}, { dashCharges = 1, dashPct = 0.27, dashCrack = 1 })
    p.cooldowns[2] = 3
    p.charges[2] = 1
    cs.dash = nil
    Combat.CastSkill(2)
    check("双重闪击 充能可用", cs.dash ~= nil)

    -- 7. 剑舞流转：格挡成功刷新旋刃 / 瞬影
    Grant("t_dance", {}, { danceFlow = 1, spinCdMul = 0.25, blinkCdMul = 0.25 })
    p.cooldowns[4] = 5
    p.cooldowns[6] = 5
    p.parryTimer = 1
    p.parryLeft = 1
    p.invulnTimer = 0
    cs.dash = nil
    local hpBeforeParry = p.hp
    Combat.DamagePlayer(cs, 10)
    check("剑舞流转 格挡刷新技能", (p.cooldowns[4] or 0) == 0 and (p.cooldowns[6] or 0) == 0,
        string.format("cd4=%s cd6=%s", tostring(p.cooldowns[4]), tostring(p.cooldowns[6])))
    check("格挡成功不掉血", p.hp >= hpBeforeParry)

    -- 8. 震波反击：剑心结束触发冲击波
    Grant("t_shock", {}, { stanceShock = 1.2 })
    cs.swordHeartTimer = 0.02
    cs.enemies = {}
    Combat.SpawnWave(cs, { minion = 1 })
    local shockTarget = cs.enemies[1]
    shockTarget.hp = 500
    shockTarget.maxHp = 500
    shockTarget.x = p.x + 40
    shockTarget.y = p.y
    local shockHp = shockTarget.hp
    Combat.Update(0.05)
    check("震波反击 结束触发", shockTarget.hp < shockHp,
        "hp " .. tostring(shockHp) .. " -> " .. tostring(shockTarget.hp))

    -- 9. 不动明王：减伤 + 受击叠盾
    Grant("t_immovable", {}, { stanceDur = 0.6, stanceDR = 0.30,
        stanceShieldOnHit = 0.25, stanceCrackCap = 1 })
    cs.swordHeartTimer = 5
    p.shield = 0
    p.parryTimer = 0
    p.parryLeft = 0
    p.invulnTimer = 0
    cs.dash = nil
    local hpBeforeHit = p.hp
    Combat.DamagePlayer(cs, 100)
    check("不动明王 减伤并叠盾", p.shield > 0 and (hpBeforeHit - p.hp) < 100,
        string.format("dmg=%.0f shield=%.0f", hpBeforeHit - p.hp, p.shield))

    -- 10. 护盾发生器：可以超过上限
    S.run.items = { { id = "shield", count = 1 } }
    p.shield = p.maxShield
    local shieldBefore = p.shield
    Combat.UseItemAt(1)
    check("护盾发生器 超过上限", p.shield > shieldBefore and p.shield <= p.maxShield * 1.5,
        string.format("shield=%.0f max=%.0f", p.shield, p.maxShield))

    print(string.format("[Effect] done, failures = %d", fails))
end
