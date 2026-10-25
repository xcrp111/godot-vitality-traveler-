-- DevTestLabView.lua — 测试模式面板截图
local Config = require "Config"
local Save = require "Save"
local S = require "State"
local UI = require "UI"
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
    Save.SetClass(S.data, "swordsman")
    Save.SetClassLevel(S.data, 14)
    S.screen = "menu"
    S.test = true
    S.testPage = 1
    S.testBuffs = { sw_b_break = true, sw_p_reset = true, sw_c_oni = true }
    S.testGeneral = { w_atk = true }
    S.testMonsterCount = { germ = 3, mycel = 1 }
    S.testSkills = { [1] = true, [4] = true }
    S.testLevel = 5
    S.testDetail = { kind = "class", id = "sw_b_break" }
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
    Menu.Draw()
    UI.DrawToast()
    UI.EndDesign()
    nvgEndFrame(S.ctx)
end
