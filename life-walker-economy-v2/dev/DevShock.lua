-- DevShock.lua — 截图用：冲击波被墙切掉一段
local Config = require "Config"
local Save = require "Save"
local UI = require "UI"
local S = require "State"
local Run = require "Run"
local Combat = require "Combat"
local VirtualControls = require "urhox-libs.UI.VirtualControls"

local frame = 0

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
    Save.SetClassLevel(S.data, 10)
    Run.Start(1)
    local cs = Combat.Start(S.run, "boss", 9)
    cs.enemies = {}
    cs.waves = {}
    cs.waveIndex = 0
    cs.cleared = false
    cs.player.x = 640
    cs.player.y = 360
    cs.player.maxHp = 9999
    cs.player.hp = 9999
    cs.walls = { { x = 520, y = 290, w = 80, h = 140 } }
    local segs = {}
    for i = 1, 72 do segs[i] = true end
    cs.bullets[#cs.bullets + 1] = {
        x = 380, y = 360, r = 200, maxR = 520, speed = 240,
        dmg = 20, hit = false, shock = true, segCount = 72, segments = segs,
    }
    S.screen = "combat"
    SubscribeToEvent(S.ctx, "NanoVGRender", "HandleRender")
    SubscribeToEvent("Update", "HandleUpdate")
end

function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    frame = frame + 1
    if S.combat then
        Combat.UpdateBullets(S.combat, dt)
    end
    if frame == 60 then
        print(string.format("[ShockTest] frame=60 playerHp=%.0f bullets=%d",
            S.combat.player.hp, #S.combat.bullets))
    end
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
