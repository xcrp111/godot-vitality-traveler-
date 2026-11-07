-- DevClass.lua — 剑客专属强化冒烟测试：全量授予 + 连续施法/击杀/格挡
local Config = require "Config"
local Save = require "Save"
local S = require "State"
local Run = require "Run"
local Combat = require "Combat"
local VirtualControls = require "urhox-libs.UI.VirtualControls"

local frame = 0

local function GrantAll(run)
    local p = run.player
    local saved = run.loadout
    -- 测试用：临时视为携带全部 6 个技能，才能拿到所有技能专属强化
    run.loadout = { 1, 2, 3, 4, 5, 6 }
    local order = { "white", "blue", "purple", "gold", "color" }
    local granted = 0
    for _, rarity in ipairs(order) do
        while true do
            local buff = Run.RollClassBuff(p, rarity)
            if not buff then break end
            Run.GrantBuff(p, buff)
            granted = granted + 1
        end
    end
    run.loadout = saved
    -- 通用强化也塞一些，验证互不冲突
    for _, rarity in ipairs({ "white", "blue", "purple", "gold" }) do
        Run.GrantBuff(p, Run.RollBuff(rarity))
        Run.GrantBuff(p, Run.RollBuff(rarity))
    end
    print("[ClassTest] granted class buffs = " .. granted .. ", total buffs = " .. #p.buffs)
end

function Start()
    local dpr = graphics:GetDPR()
    if not dpr or dpr <= 0 then dpr = 1 end
    S.dpr = dpr
    S.W = graphics:GetWidth() / dpr
    S.H = graphics:GetHeight() / dpr
    S.scale = math.min(S.W / Config.DESIGN_W, S.H / Config.DESIGN_H)
    S.offX = (S.W - Config.DESIGN_W * S.scale) / 2
    S.offY = (S.H - Config.DESIGN_H * S.scale) / 2
    VirtualControls.Initialize(Config.DESIGN_W, Config.DESIGN_H)
    math.randomseed(11)
    S.data = Save.Load()
    Save.SetClass(S.data, "swordsman")
    Save.SetClassLevel(S.data, 10)
    do local lo = Save.Loadout(S.data); lo[1], lo[2], lo[3] = 1, 2, 4 end

    -- 奖励池：统计 40 次三选一里有多少专属
    Run.Start(1)
    local classCount, total = 0, 0
    for _ = 1, 40 do
        Run.OpenCombatReward("elite")
        local reward = S.reward
        if reward then
            for _, o in ipairs(reward.options) do
                total = total + 1
                if o.classBuff then classCount = classCount + 1 end
            end
        end
        S.reward = false
    end
    print(string.format("[ClassTest] reward roll: %d/%d class options", classCount, total))

    -- 重开一局并全量授予专属
    Run.Start(1)
    local run = S.run
    GrantAll(run)

    local cs = Combat.Start(run, "standard", 3)
    cs.enemies = {}
    cs.waveIndex = #cs.waves
    Combat.SpawnWave(cs, { minion = 5 })
    for _, e in ipairs(cs.enemies) do e.hp = 26 e.maxHp = 26 end
    cs.player.maxHp = 99999
    cs.player.hp = 99999
    S.screen = "combat"

    print("[ClassTest] combat started, flags=" .. tostring(p_flags(run.player)))
    SubscribeToEvent("Update", "HandleUpdate")
end

function p_flags(p)
    local n = 0
    for _ in pairs(p.flags) do n = n + 1 end
    return n
end

function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    frame = frame + 1
    local cs = S.combat
    if not cs then return end

    -- 防止房间被判清空，保持长跑
    cs.cleared = false
    cs.clearTimer = 0

    -- 轮换携带技能，六个技能都覆盖到
    if frame == 260 then cs.run.loadout = { 3, 5, 6 } end
    if frame == 520 then cs.run.loadout = { 1, 4, 2 } end

    -- 圆形走位
    S.input.x = math.cos(frame * 0.05)
    S.input.y = math.sin(frame * 0.05)

    -- 高频施法：各种技能都过一遍
    if frame % 12 == 0 then Combat.CastSkill(1) end
    if frame % 24 == 0 then Combat.CastSkill(2) end
    if frame % 40 == 0 then Combat.CastSkill(3) end
    if frame % 18 == 0 then Combat.CastSkill(1) end
    if frame % 55 == 0 then Combat.CastSkill(1) end
    if frame % 30 == 0 then Combat.CastSkill(2) end
    if frame % 33 == 0 then Combat.CastSkill(3) end

    -- 普攻
    if frame % 8 == 0 then Combat.ManualAttack() end

    -- 保证有目标可打
    if #cs.enemies == 0 or (frame % 25 == 0 and #cs.enemies < 6) then
        Combat.SpawnWave(cs, { minion = 3 })
        for _, e in ipairs(cs.enemies) do
            if e.hp > 40 then e.hp = 30 e.maxHp = 30 end
        end
    end

    -- 把敌人拉到身边，确保命中/连携/击杀路径都被踩到
    if frame % 20 == 0 then
        local i = 1
        for _, e in ipairs(cs.enemies) do
            local a = i * 1.3 + frame * 0.02
            e.x = cs.player.x + math.cos(a) * 45
            e.y = cs.player.y + math.sin(a) * 45
            i = i + 1
        end
    end

    Combat.Update(dt)

    -- 狂剑士会持续扣血，这里补回来保证长跑
    if cs.player then
        cs.player.hp = math.min(cs.player.maxHp, cs.player.hp + 60000)
    end

    if frame % 120 == 0 then
        local p = cs.player
        print(string.format(
            "[ClassTest] frame=%d enemies=%d hp=%d intent=%d/%d charges2=%s charges4=%s combo=%s stored=%s combos=%s bleed=%s",
            frame, #cs.enemies, math.floor(p.hp), p.intent,
            math.floor(5 + (p.flags.intentCapDelta or 0)),
            tostring(p.charges[2]), tostring(p.charges[4]),
            tostring(cs.lastHitSrc), tostring(cs.storedDebuffs), tostring(cs.comboCount or 0),
            tostring(cs.windWaves and #cs.windWaves or 0)))
    end
end
