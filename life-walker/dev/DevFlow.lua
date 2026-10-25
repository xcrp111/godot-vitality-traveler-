-- DevFlow.lua — 全流程冒烟：地图 → 各类房间 → Boss → 通关

local Config = require "Config"
local Save = require "Save"
local UI = require "UI"
local S = require "State"
local Run = require "Run"
local Combat = require "Combat"
local Screens = require "Screens"
local VirtualControls = require "urhox-libs.UI.VirtualControls"

local path = {
    { 4, 2 }, { 3, 2 }, { 3, 3 }, { 2, 3 }, { 2, 4 }, { 1, 4 },
}
local idx = 1
local frame = 0
local done = false

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
    VirtualControls.Initialize(Config.DESIGN_W, Config.DESIGN_H)
    math.randomseed(1)
    S.data = Save.Load()
    Save.SetClass(S.data, "swordsman")
    Save.SetClassLevel(S.data, 5)
    Run.Start(1)
    print("[DevFlow] start unlocked=" .. S.data.unlocked)
    SubscribeToEvent(S.ctx, "NanoVGRender", "HandleRender")
    SubscribeToEvent("Update", "HandleUpdate")
end

function Stop()
    VirtualControls.Shutdown()
    if S.ctx then nvgDelete(S.ctx) end
end

function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    S.time = S.time + dt
    UI.UpdateToast(dt)
    if done then return end
    frame = frame + 1
    if frame > 3000 then
        print("[DevFlow] TIMEOUT screen=" .. S.screen .. " idx=" .. idx)
        done = true
        return
    end

    if S.screen == "combat" and S.combat then
        local cs = S.combat
        for i = #cs.enemies, 1, -1 do
            Combat.KillEnemy(cs, cs.enemies[i])
        end
        cs.waveIndex = #cs.waves
        Combat.Update(dt)
    elseif S.screen == "reward" then
        print("[DevFlow] reward @ frame " .. frame)
        Run.ChooseReward(1)
    elseif S.screen == "shop" then
        print("[DevFlow] shop @ frame " .. frame)
        Run.CloseShop()
    elseif S.screen == "event" then
        print("[DevFlow] event @ frame " .. frame)
        Run.CloseEvent()
    elseif S.screen == "map" then
        if idx <= #path then
            local cell = path[idx]
            print("[DevFlow] move to " .. cell[1] .. "," .. cell[2])
            Run.Move(cell[1], cell[2])
            idx = idx + 1
        end
    elseif S.screen == "levelclear" then
        print("[DevFlow] LEVEL CLEAR unlocked=" .. S.data.unlocked .. " frame=" .. frame)
        done = true
    elseif S.screen == "gameover" then
        print("[DevFlow] GAME OVER")
        done = true
    end
end

function HandleRender()
    nvgBeginFrame(S.ctx, graphics:GetWidth(), graphics:GetHeight(), S.dpr)
    S.regions = {}
    UI.BeginDesign()
    if S.screen == "combat" then
        Combat.Draw()
    elseif S.screen == "shop" then
        Screens.DrawShop()
    elseif S.screen == "event" then
        Screens.DrawEvent()
    elseif S.screen == "levelclear" then
        Screens.DrawLevelClear()
    else
        Screens.DrawMap()
    end
    UI.EndDesign()
    nvgEndFrame(S.ctx)
end
