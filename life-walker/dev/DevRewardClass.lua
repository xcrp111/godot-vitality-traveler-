-- DevRewardClass.lua — 奖励界面显示剑客专属标签
local Config = require "Config"
local Save = require "Save"
local S = require "State"
local UI = require "UI"
local Run = require "Run"
local Screens = require "Screens"
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
    S.ctx = nvgCreate(1)
    S.font = nvgCreateFont(S.ctx, "sans", "Fonts/MiSans-Regular.ttf")
    S.data = Save.Load()
    Save.SetClassLevel(S.data, 10)
    math.randomseed(11)
    Run.Start(1)
    for _ = 1, 30 do
        Run.OpenCombatReward("elite")
        local n = 0
        for _, o in ipairs(S.reward.options) do
            if o.classBuff then n = n + 1 end
        end
        if n >= 2 then break end
    end
    S.run.silver = 120
    S.screen = "reward"
    S.combat = nil
    for _, o in ipairs(S.reward.options) do
        print(string.format("[Reward] %s %s class=%s", o.rarity, o.name, tostring(o.classBuff)))
    end
    SubscribeToEvent(S.ctx, "NanoVGRender", "HandleRender")
    SubscribeToEvent("Update", "HandleUpdate")
end

function HandleUpdate(eventType, eventData)
    UI.UpdateToast(eventData["TimeStep"]:GetFloat())
end

function HandleRender(eventType, eventData)
    if not S.ctx then return end
    nvgBeginFrame(S.ctx, graphics:GetWidth(), graphics:GetHeight(), S.dpr)
    S.regions = {}
    UI.BeginDesign()
    Screens.DrawReward()
    UI.DrawToast()
    UI.EndDesign()
    nvgEndFrame(S.ctx)
end
