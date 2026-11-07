-- DevFarmView.lua — 农场实景地图截图验收
local Config = require "Config"
local Save = require "Save"
local S = require "State"
local UI = require "UI"
local Farm = require "Farm"
local FarmUI = require "FarmUI"

local frame = 0

function Start()
    local dpr = graphics:GetDPR(); if not dpr or dpr <= 0 then dpr = 1 end
    S.dpr = dpr
    S.W = graphics:GetWidth() / dpr
    S.H = graphics:GetHeight() / dpr
    S.scale = math.min(S.W / Config.DESIGN_W, S.H / Config.DESIGN_H)
    S.offX = (S.W - Config.DESIGN_W * S.scale) / 2
    S.offY = (S.H - Config.DESIGN_H * S.scale) / 2
    S.ctx = nvgCreate(1)
    S.font = nvgCreateFont(S.ctx, "sans", "Fonts/MiSans-Regular.ttf")
    math.randomseed(3)

    S.data = Save.Load()
    S.data.stageCleared = 6
    local d = S.data
    local f = Farm.Ensure(d)
    f.landCount = 6
    f.seeds.fire = 3
    f.seeds.ice = 2
    Farm.Plant(d, 1, "fire")
    Farm.Water(d, 1)
    Farm.DebugRipenAll(d)
    S.farm = true
    S.farmTab = 1

    local iw, ih = UI.ImageSize("image/farm/farm_map.jpg")
    print(string.format("[FarmView] 底图尺寸 %g x %g", iw, ih))
    SubscribeToEvent(S.ctx, "NanoVGRender", "HandleRender")
    SubscribeToEvent("Update", "HandleUpdate")
end

function HandleUpdate(eventType, eventData) frame = frame + 1 end

function HandleRender(eventType, eventData)
    if not S.ctx then return end
    nvgBeginFrame(S.ctx, graphics:GetWidth(), graphics:GetHeight(), S.dpr)
    UI.BeginDesign()
    FarmUI.Draw()
    UI.EndDesign()
    nvgEndFrame(S.ctx)
end
