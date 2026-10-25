-- DevClassMenu.lua — 主菜单职业切换排版截图
local Config = require "Config"
local Save = require "Save"
local UI = require "UI"
local S = require "State"
local Menu = require "Menu"
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
    Save.SetClass(S.data, "spearman")
    Save.SetClassLevel(S.data, 10)
    S.selectedLevel = 1
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
    Menu.Draw()
    UI.EndDesign()
    nvgEndFrame(S.ctx)
end
