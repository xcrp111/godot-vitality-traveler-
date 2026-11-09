-- DevItems.lua — 道具栏购买/使用逻辑冒烟
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
    S.data = Save.Load()
    Save.SetClassLevel(S.data, 5)
    Run.Start(1)
    Run.Move(4, 2)

    local p = S.run.player
    p.hp = 10
    Run.AddItem("potion_small")
    Combat.UseItem()
    print(string.format("[ItemTest] potion hp=%.0f items=%d", p.hp, #S.run.items))

    Run.AddItem("shield")
    Run.AddItem("shield")
    p.shield = 0
    Combat.UseItemAt(1)
    print(string.format("[ItemTest] shield=%.0f items=%d", p.shield, #S.run.items))

    Run.AddItem("rage")
    Combat.UseItemAt(2)
    print(string.format("[ItemTest] rage=%.1f items=%d", p.rageTimer, #S.run.items))
end
