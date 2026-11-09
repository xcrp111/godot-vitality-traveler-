-- DevCodex.lua — 图鉴「剑客专属」页排版检查（截图用）
local Config = require "Config"
local Save = require "Save"
local S = require "State"
local UI = require "UI"
local Menu = require "Menu"
local VirtualControls = require "urhox-libs.UI.VirtualControls"

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
    VirtualControls.Initialize(Config.DESIGN_W, Config.DESIGN_H)
    S.ctx = nvgCreate(1)
    S.font = nvgCreateFont(S.ctx, "sans", "Fonts/MiSans-Regular.ttf")
    S.data = Save.Load()
    S.screen = "menu"
    S.compendium = true
    S.compendiumTab = 3
    S.codexPage = tonumber(DEV_PAGE or "1") or 1
    SubscribeToEvent(S.ctx, "NanoVGRender", "HandleRender")
    SubscribeToEvent("Update", "HandleUpdate")
end

function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    frame = frame + 1
    UI.UpdateToast(dt)
end

function HandleRender(eventType, eventData)
    if not S.ctx then return end
    nvgBeginFrame(S.ctx, graphics:GetWidth(), graphics:GetHeight(), S.dpr)
    S.regions = {}
    UI.BeginDesign()
    Menu.Draw()
    UI.DrawToast()
    UI.EndDesign()
    nvgEndFrame(S.ctx)
end
