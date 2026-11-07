-- DevCombatTest.lua — 攻击 / 受伤 / 掉落冒烟测试（不参与正式构建）
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
    math.randomseed(1)
    S.data = Save.Load()
    Save.SetClassLevel(S.data, 5)
    Run.Start(1)
    Run.Move(4, 2)
    local cs = S.combat
    local p = cs.player
    p.maxHp = 1000
    p.hp = 1000
    p.shield = 0
    for i = #cs.enemies, 2, -1 do
        table.remove(cs.enemies, i)
    end
    local e = cs.enemies[1]
    if e then
        e.x = p.x + 45
        e.y = p.y
        e.hp = 18
        e.maxHp = 18
        e.atk = 6
        e.speed = 0
    end
    print("[CombatTest] enemies=" .. #cs.enemies .. " hp=" .. p.hp)
    SubscribeToEvent("Update", "HandleUpdate")
end

function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    frame = frame + 1
    Combat.Update(dt)
    if frame == 120 or frame == 300 then
        local cs = S.combat
        if cs then
            local p = cs.player
            print(string.format("[CombatTest] frame=%d enemies=%d silver=%d hp=%.1f shield=%.1f screen=%s",
                frame, #cs.enemies, cs.run.silver, p.hp, p.shield, S.screen))
        end
    end
    if frame >= 360 then
        print("[CombatTest] DONE")
        frame = -99999
    end
end
