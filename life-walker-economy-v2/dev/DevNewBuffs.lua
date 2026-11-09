-- DevNewBuffs.lua — 游侠 / 法师专属强化全量冒烟
local Config = require "Config"
local Save = require "Save"
local S = require "State"
local Run = require "Run"
local Combat = require "Combat"
local VirtualControls = require "urhox-libs.UI.VirtualControls"

local function Smoke(classId, maxSkill)
    Save.SetClass(S.data, classId)
    Save.SetClassLevel(S.data, 10)
    Config.SetClass(classId)
    Run.Start(1)
    local all = {}
    for id = 1, maxSkill do all[id] = id end
    S.run.loadout = all
    local p = S.run.player
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

    -- 抽卡过滤
    S.run.loadout = { 1, 2 }
    local bad = 0
    for _ = 1, 30 do
        Run.OpenCombatReward("elite")
        for _, opt in ipairs(S.reward.options) do
            if opt.classBuff then
                local need = Config.ClassBuffNeed(opt)
                if need then
                    for _, id in ipairs(need) do if id > 2 then bad = bad + 1 end end
                end
            end
        end
        S.reward = false
    end

    S.run.loadout = all
    local cs = Combat.Start(S.run, "standard", 3)
    cs.enemies = {}
    cs.waveIndex = #cs.waves
    Combat.SpawnWave(cs, { minion = 4 })
    S.screen = "combat"
    p.maxHp = 99999
    p.hp = 99999
    local frames = 600
    for f = 1, frames do
        cs.cleared = false
        cs.clearTimer = 0
        S.input.x = math.cos(f * 0.07)
        S.input.y = math.sin(f * 0.07)
        if f % 8 == 0 then Combat.ManualAttack() end
        for slot = 1, maxSkill do
            if f % (10 + slot * 3) == 0 then Combat.CastSkill(slot) end
        end
        if #cs.enemies == 0 or (f % 30 == 0 and #cs.enemies < 4) then
            Combat.SpawnWave(cs, { minion = 3 })
            for _, e in ipairs(cs.enemies) do
                if e.hp > 800 then e.hp = 600 e.maxHp = 600 end
            end
        end
        if f % 20 == 0 then
            local i = 1
            for _, e in ipairs(cs.enemies) do
                local a = i * 1.1
                e.x = cs.player.x + math.cos(a) * (60 + i * 8)
                e.y = cs.player.y + math.sin(a) * (60 + i * 8)
                i = i + 1
            end
        end
        Combat.Update(1 / 60)
        if cs.player then cs.player.hp = math.min(cs.player.maxHp, cs.player.hp + 50000) end
    end
    print(string.format("[NewBuff] %s granted=%d illegal=%d screen=%s enemies=%d projs=%d fields=%d",
        classId, granted, bad, S.screen, #cs.enemies, #(cs.projs or {}), #(cs.mageFields or {})))
end

function Start()
    VirtualControls.Initialize(Config.DESIGN_W, Config.DESIGN_H)
    S.data = Save.Load()
    math.randomseed(17)
    Smoke("ranger", 6)
    Smoke("mage", 9)
    print("[NewBuff] done")
end
