-- DevInvuln.lua — 突进无敌帧冒烟
local Config = require "Config"
local Save = require "Save"
local S = require "State"
local Run = require "Run"
local Combat = require "Combat"
local VirtualControls = require "urhox-libs.UI.VirtualControls"

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
    Save.SetClassLevel(S.data, 6)
    Run.Start(1)
    Run.Move(4, 2)
    local cs = S.combat
    local p = cs.player
    p.hp = 100
    p.shield = 0

    p.invulnTimer = 0.3
    Combat.DamagePlayer(cs, 50)
    print("[InvulnTest] during dash hp=" .. p.hp)

    p.invulnTimer = 0
    Combat.DamagePlayer(cs, 50)
    print("[InvulnTest] after dash hp=" .. p.hp)

    S.run.loadout = { 2, 6, 1 }
    p.cooldowns[2] = 0
    p.cooldowns[6] = 0
    Combat.CastSkill(1)
    print("[InvulnTest] skill2 invuln=" .. string.format("%.2f", p.invulnTimer))
    p.invulnTimer = 0
    Combat.CastSkill(2)
    print("[InvulnTest] skill6 invuln=" .. string.format("%.2f", p.invulnTimer))
end
