-- DevClassDetailView.lua — 角色数值/形象面板渲染检查（截图用）
local Config = require "Config"
local Save = require "Save"
local S = require "State"
local UI = require "UI"
local Menu = require "Menu"

local frame = 0

function Start()
    local dpr = graphics:GetDPR()
    if not dpr or dpr <= 0 then dpr = 1 end
    S.dpr = dpr
    S.W = graphics:GetWidth() / dpr
    S.H = graphics:GetHeight() / dpr
    S.scale = math.min(S.W / Config.DESIGN_W, S.H / Config.DESIGN_H)
    S.offX = (S.W - Config.DESIGN_W * S.scale) / 2
    S.offY = (S.H - Config.DESIGN_H * S.scale) / 2
    S.ctx = nvgCreate(1)
    S.font = nvgCreateFont(S.ctx, "sans", "Fonts/MiSans-Game.ttf")
    S.data = Save.Load()
    Save.SetClass(S.data, "mage")
    Save.SetClassLevel(S.data, 12)
    S.data.levels.mage = 12
    Config.SetClass("mage")
    S.screen = "menu"
    S.panelMode = "char"
    S.classDetail = true
    S.classDetailView = "mage"
    S.classDetailSkill = 1
    SubscribeToEvent(S.ctx, "NanoVGRender", "HandleRender")
    SubscribeToEvent("Update", "HandleUpdate")
end

function HandleUpdate(eventType, eventData)
    frame = frame + 1
    S.time = S.time + eventData["TimeStep"]:GetFloat()
end

function HandleRender(eventType, eventData)
    if not S.ctx then return end
    nvgBeginFrame(S.ctx, graphics:GetWidth(), graphics:GetHeight(), S.dpr)
    S.regions = {}
    UI.BeginDesign()
    Menu.DrawClassDetail()
    UI.DrawToast()
    UI.EndDesign()
    nvgEndFrame(S.ctx)
end
