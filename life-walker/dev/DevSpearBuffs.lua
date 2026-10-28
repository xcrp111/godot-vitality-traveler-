-- DevSpearBuffs.lua — 枪客专属强化全量冒烟
local Config = require "Config"
local Save = require "Save"
local S = require "State"
local Run = require "Run"
local Combat = require "Combat"
local VirtualControls = require "urhox-libs.UI.VirtualControls"

local frame = 0

function Start()
    VirtualControls.Initialize(Config.DESIGN_W, Config.DESIGN_H)
    S.data = Save.Load()
    Save.SetClass(S.data, "spearman")
    Save.SetClassLevel(S.data, 10)
    Config.SetClass("spearman")
    math.randomseed(13)

    Run.Start(1)
    S.run.loadout = { 1, 2, 3, 4, 5, 6 }
    local p = S.run.player
    local group = Config.ClassBuffs.spearman
    local granted = 0
    for _, rarity in ipairs({ "white", "blue", "purple", "gold", "color" }) do
        while true do
            local buff = Run.RollClassBuff(p, rarity)
            if not buff then break end
            Run.GrantBuff(p, buff)
            granted = granted + 1
        end
    end
    for _, rarity in ipairs({ "white", "blue", "purple", "gold" }) do
        Run.GrantBuff(p, Run.RollBuff(rarity))
    end
    print("[SpearBuff] granted=" .. granted .. " total=" .. #p.buffs)

    -- 抽卡过滤：只带 1/2 技能时不该出现 3~6 的技能专属
    S.run.loadout = { 1, 2 }
    local bad = 0
    for _ = 1, 30 do
        Run.OpenCombatReward("elite")
        for _, opt in ipairs(S.reward.options) do
            if opt.classBuff then
                local need = Config.ClassBuffNeed(opt)
                if need then
                    for _, id in ipairs(need) do
                        if id > 2 then bad = bad + 1 end
                    end
                end
            end
        end
        S.reward = false
    end
    print("[SpearBuff] illegal offers=" .. bad)

    S.run.loadout = { 1, 2, 3, 4, 5, 6 }
    local cs = Combat.Start(S.run, "standard", 3)
    cs.enemies = {}
    cs.waveIndex = #cs.waves
    Combat.SpawnWave(cs, { minion = 4 })
    S.screen = "combat"
    p.maxHp = 99999
    p.hp = 99999
    SubscribeToEvent("Update", "HandleUpdate")
end

function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    frame = frame + 1
    local cs = S.combat
    if not cs then return end
    cs.cleared = false
    cs.clearTimer = 0

    S.input.x = math.cos(frame * 0.07)
    S.input.y = math.sin(frame * 0.07)

    cs.facing = 0
    if frame % 9 == 0 then Combat.ManualAttack() end
    if frame % 20 == 0 then Combat.CastSkill(1) end
    if frame % 26 == 0 then Combat.CastSkill(2) end
    if frame % 60 == 0 then Combat.CastSkill(3) end
    if frame % 30 == 0 then Combat.CastSkill(4) end
    if frame % 40 == 0 then Combat.CastSkill(5) end
    if frame % 50 == 0 then Combat.CastSkill(6) end

    if #cs.enemies == 0 or (frame % 30 == 0 and #cs.enemies < 5) then
        Combat.SpawnWave(cs, { minion = 3 })
        for _, e in ipairs(cs.enemies) do
            if e.hp > 600 then e.hp = 500 e.maxHp = 500 end
        end
    end
    if frame % 15 == 0 then
        local i = 1
        for _, e in ipairs(cs.enemies) do
            local a = i * 1.2
            e.x = cs.player.x + math.cos(a) * (45 + i * 10)
            e.y = cs.player.y + math.sin(a) * (45 + i * 10)
            i = i + 1
        end
    end

    Combat.Update(dt)
    if cs.player then
        cs.player.hp = math.min(cs.player.maxHp, cs.player.hp + 60000)
    end

    if frame % 150 == 0 then
        print(string.format("[SpearBuff] frame=%d enemies=%d momentum=%d/%d combos=%d phantoms=%d charges2=%s charges5=%s",
            frame, #cs.enemies, cs.player.intent, 3, cs.comboCount or 0,
            cs.phantomCount or 0, tostring(cs.player.charges[2]), tostring(cs.player.charges[5])))
    end
end
