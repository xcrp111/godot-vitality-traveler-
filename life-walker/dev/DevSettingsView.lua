-- DevSettingsView.lua — 设置面板截图
local Config = require "Config"
local Save = require "Save"
local UI = require "UI"
local S = require "State"
local Menu = require "Menu"
local Audio = require "Audio"
local VirtualControls = require "urhox-libs.UI.VirtualControls"
function Start()
    local dpr = graphics:GetDPR(); if not dpr or dpr <= 0 then dpr = 1 end
    S.dpr = dpr; S.W = graphics:GetWidth() / dpr; S.H = graphics:GetHeight() / dpr
    S.scale = math.min(S.W / Config.DESIGN_W, S.H / Config.DESIGN_H)
    S.offX = (S.W - Config.DESIGN_W * S.scale) / 2
    S.offY = (S.H - Config.DESIGN_H * S.scale) / 2
    VirtualControls.Initialize(Config.DESIGN_W, Config.DESIGN_H)
    S.ctx = nvgCreate(1); S.font = nvgCreateFont(S.ctx, "sans", "Fonts/MiSans-Regular.ttf")
    S.data = Save.Load()
    Save.SetClass(S.data, "ranger")
    Save.SetClassLevel(S.data, 8)
    S.data.gold = 1280
    S.data.exp = 640
    S.data.unlocked = 4
    S.data.streak = 5
    S.data.classExp.ranger = 110
    S.data.musicOn = true
    S.data.musicVolume = 0.4
    S.settings = true
    Audio.Init(S.data)
    SubscribeToEvent(S.ctx, "NanoVGRender", "HandleRender")
    SubscribeToEvent("Update", "HandleUpdate")
end
function HandleUpdate(eventType, eventData)
    Audio.Update(eventData["TimeStep"]:GetFloat())
    UI.UpdateToast(eventData["TimeStep"]:GetFloat())
end
function HandleRender()
    nvgBeginFrame(S.ctx, graphics:GetWidth(), graphics:GetHeight(), S.dpr)
    S.regions = {}; UI.BeginDesign(); Menu.Draw(); UI.DrawToast(); UI.EndDesign(); nvgEndFrame(S.ctx)
end
