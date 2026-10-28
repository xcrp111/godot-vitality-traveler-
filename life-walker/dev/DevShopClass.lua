-- DevShopClass.lua — 商店里剑客专属强化的排版
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
    math.randomseed(7)
    Run.Start(1)
    S.run.silver = 300
    Run.OpenShop()
    local n = 0
    for _, slot in ipairs(S.run.shop.slots) do
        if slot.classBuff then n = n + 1 end
    end
    print("[ShopClass] class slots = " .. n)
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
    Screens.DrawShop()
    UI.DrawToast()
    UI.EndDesign()
    nvgEndFrame(S.ctx)
end
