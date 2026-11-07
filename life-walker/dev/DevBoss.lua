-- DevBoss.lua — 单独跑 Boss，检查新增攻击 / 冲击波 / 召唤不报错
local Config = require "Config"
local Save = require "Save"
local S = require "State"
local Run = require "Run"
local Combat = require "Combat"
local VirtualControls = require "urhox-libs.UI.VirtualControls"

local frame = 0

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
    math.randomseed(5)
    S.data = Save.Load()
    Save.SetClassLevel(S.data, 10)
    Run.Start(1)
    local cs = Combat.Start(S.run, "boss", 9)
    cs.enemies = {}
    cs.waveIndex = #cs.waves
    Combat.SpawnWave(cs, { boss = 1 })
    cs.player.maxHp = 99999
    cs.player.hp = 99999
    S.screen = "combat"
    print("[BossTest] boss spawned, walls=" .. #cs.walls)
    SubscribeToEvent("Update", "HandleUpdate")
end

function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    frame = frame + 1
    Combat.Update(dt)
    if frame % 120 == 0 then
        local cs = S.combat
        if cs then
            local boss = nil
            for _, e in ipairs(cs.enemies) do
                if e.kind == "boss" then boss = e end
            end
            print(string.format("[BossTest] frame=%d enemies=%d bossHp=%s charge=%s",
                frame, #cs.enemies, boss and string.format("%.0f", boss.hp) or "none",
                boss and tostring(boss.chargeState) or "-"))
        end
    end
    if frame >= 1200 then frame = -99999 end
end
