-- DevReward.lua — 截图用：战斗奖励三选一
local Config = require "Config"
local Save = require "Save"
local UI = require "UI"
local S = require "State"
local Run = require "Run"
local Screens = require "Screens"

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
    math.randomseed(7)
    S.data = Save.Load()
    Save.SetClassLevel(S.data, 5)
    Run.Start(1)
    Run.OpenCombatReward("elite")
    SubscribeToEvent(S.ctx, "NanoVGRender", "HandleRender")
end

function HandleRender()
    nvgBeginFrame(S.ctx, graphics:GetWidth(), graphics:GetHeight(), S.dpr)
    S.regions = {}
    UI.BeginDesign()
    nvgBeginPath(S.ctx)
    nvgRect(S.ctx, 0, 0, Config.DESIGN_W, Config.DESIGN_H)
    nvgFillColor(S.ctx, nvgRGBA(16, 14, 22, 255))
    nvgFill(S.ctx)
    Screens.DrawReward()
    UI.EndDesign()
    nvgEndFrame(S.ctx)
end
