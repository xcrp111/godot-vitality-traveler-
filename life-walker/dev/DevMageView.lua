-- DevMageView.lua — 法师战斗截图
local Config = require "Config"
local Save = require "Save"
local S = require "State"
local UI = require "UI"
local Run = require "Run"
local Combat = require "Combat"
local VirtualControls = require "urhox-libs.UI.VirtualControls"
local frame = 0
function Start()
    local dpr = graphics:GetDPR(); if not dpr or dpr <= 0 then dpr = 1 end
    S.dpr = dpr; S.W = graphics:GetWidth() / dpr; S.H = graphics:GetHeight() / dpr
    S.scale = math.min(S.W / Config.DESIGN_W, S.H / Config.DESIGN_H)
    S.offX = (S.W - Config.DESIGN_W * S.scale) / 2
    S.offY = (S.H - Config.DESIGN_H * S.scale) / 2
    VirtualControls.Initialize(Config.DESIGN_W, Config.DESIGN_H)
    S.ctx = nvgCreate(1); S.font = nvgCreateFont(S.ctx, "sans", "Fonts/MiSans-Regular.ttf")
    math.randomseed(9)
    S.data = Save.Load(); Save.SetClass(S.data, "mage"); Save.SetClassLevel(S.data, 10)
    Config.SetClass("mage"); Run.Start(1); S.run.loadout = { 1, 2, 3 }
    local cs = Combat.Start(S.run, "standard", 3)
    cs.enemies = {}; cs.waveIndex = #cs.waves
    Combat.SpawnWave(cs, { minion = 4 }); S.screen = "combat"
    local p = cs.player
    for i, e in ipairs(cs.enemies) do
        e.x = p.x + 120 + i * 26; e.y = p.y - 60 + i * 32
    end
    SubscribeToEvent(S.ctx, "NanoVGRender", "HandleRender")
    SubscribeToEvent("Update", "HandleUpdate")
end
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat(); frame = frame + 1
    local cs = S.combat; if not cs then return end
    if frame == 30 then cs.facing = 0; Combat.CastSkill(1); Combat.CastSkill(2); Combat.CastSkill(3) end
    if frame > 30 then
        cs.cleared = false; cs.clearTimer = 0
        Combat.Update(dt); cs.facing = 0
        for _, e in ipairs(cs.enemies) do
            e.x = cs.player.x + 140 + 20 * math.sin(frame * 0.05)
        end
    end
end
function HandleRender()
    nvgBeginFrame(S.ctx, graphics:GetWidth(), graphics:GetHeight(), S.dpr)
    S.regions = {}; UI.BeginDesign(); Combat.Draw(); UI.DrawToast(); UI.EndDesign(); nvgEndFrame(S.ctx)
end
