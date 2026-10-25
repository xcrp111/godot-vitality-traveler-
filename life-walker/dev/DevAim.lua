-- DevAim.lua — 截图用：把敌人固定在正右方，检查扇形与小刀方向是否一致
local Config = require "Config"
local Save = require "Save"
local UI = require "UI"
local S = require "State"
local Run = require "Run"
local Combat = require "Combat"
local VirtualControls = require "urhox-libs.UI.VirtualControls"

function Start()
    S.ctx = nvgCreate(1)
    S.font = nvgCreateFont(S.ctx, "sans", "Fonts/MiSans-Regular.ttf")
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
    p.maxHp = 99999
    p.hp = 99999
    for i = #cs.enemies, 2, -1 do
        table.remove(cs.enemies, i)
    end
    local e = cs.enemies[1]
    if e then
        e.x = p.x + 60
        e.y = p.y
        e.hp = 999999
        e.maxHp = 999999
        e.speed = 0
        e.behavior = "chase"
    end
    SubscribeToEvent(S.ctx, "NanoVGRender", "HandleRender")
    SubscribeToEvent("Update", "HandleUpdate")
end

function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    S.time = S.time + dt
    Combat.Update(dt)
end

function HandleRender()
    nvgBeginFrame(S.ctx, graphics:GetWidth(), graphics:GetHeight(), S.dpr)
    S.regions = {}
    UI.BeginDesign()
    nvgBeginPath(S.ctx)
    nvgRect(S.ctx, 0, 0, Config.DESIGN_W, Config.DESIGN_H)
    nvgFillColor(S.ctx, nvgRGBA(16, 14, 22, 255))
    nvgFill(S.ctx)
    Combat.Draw()
    UI.EndDesign()
    nvgEndFrame(S.ctx)
end
