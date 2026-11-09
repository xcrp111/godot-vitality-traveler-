-- DevAttack.lua — 平A边缘命中 / 输入缓存冒烟
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
    Save.SetClassLevel(S.data, 5)
    Run.Start(1)
    Run.Move(4, 2)
    local cs = S.combat
    local p = cs.player
    p.maxHp = 9999
    p.hp = 9999

    for i = #cs.enemies, 2, -1 do table.remove(cs.enemies, i) end
    local e = cs.enemies[1]
    e.x = p.x + math.cos(math.rad(65)) * 70
    e.y = p.y + math.sin(math.rad(65)) * 70
    e.hp = 100
    e.maxHp = 100
    e.speed = 0
    p.facing = 0

    print("[AttackTest] before hp=" .. e.hp)
    Combat.BasicAttack(cs)
    print("[AttackTest] after edge attack hp=" .. e.hp)

    p.attackTimer = 0.3
    p.attackQueued = false
    Combat.ManualAttack()
    print("[AttackTest] queued=" .. tostring(p.attackQueued) .. " timer=" .. string.format("%.2f", p.attackTimer))
    Combat.Update(0.35)
    print("[AttackTest] after update queued=" .. tostring(p.attackQueued) .. " hp=" .. string.format("%.1f", e.hp))
end
