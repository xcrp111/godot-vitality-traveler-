-- DevSmoke.lua — 本地冒烟测试入口（不参与正式构建）
-- 按帧推进：战斗 → 商店 → 事件 → 事件结果 → 通关 → 地图

local Config = require "Config"
local Save = require "Save"
local UI = require "UI"
local S = require "State"
local Run = require "Run"
local Combat = require "Combat"
local Screens = require "Screens"
local VirtualControls = require "urhox-libs.UI.VirtualControls"

local stage = "combat"
local castTimer = 0
local frame = 0

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
    math.randomseed(os.time())
    S.data = Save.Load()
    Save.SetClassLevel(S.data, 5)
    Run.Start(1)
    Run.Move(4, 2)
    S.screen = "combat"
    stage = "combat"
    if S.run then
        S.run.player.maxHp = 99999
        S.run.player.hp = 99999
    end
    print("[DevSmoke] started, screen=" .. S.screen)
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
    frame = frame + 1

    if stage == "combat" then
        S.input.x = math.cos(S.time * 1.3) * 0.6
        S.input.y = math.sin(S.time * 1.3) * 0.6
        castTimer = castTimer + dt
        if castTimer > 0.8 then
            castTimer = 0
            Combat.CastSkill(math.random(1, 3))
        end
        if S.screen == "combat" then
            Combat.Update(dt)
        end
        if frame > 300 then
            print("[DevSmoke] frame " .. frame .. " -> shop")
            Run.OpenShop()
            S.screen = "shop"
            stage = "shop"
        end
    elseif stage == "shop" then
        if frame > 420 then
            print("[DevSmoke] frame " .. frame .. " -> event")
            Run.CloseShop()
            Run.OpenEvent()
            S.screen = "event"
            stage = "event"
        end
    elseif stage == "event" then
        if frame > 520 then
            print("[DevSmoke] frame " .. frame .. " -> choose event")
            Run.ChooseEvent(1)
            stage = "event_done"
        end
    elseif stage == "event_done" then
        if frame > 580 then
            print("[DevSmoke] frame " .. frame .. " -> levelclear")
            Run.CloseEvent()
            S.screen = "levelclear"
            stage = "clear"
        end
    elseif stage == "clear" then
        if frame > 640 then
            S.screen = "map"
            stage = "map"
        end
    end
end

function HandleRender()
    nvgBeginFrame(S.ctx, graphics:GetWidth(), graphics:GetHeight(), S.dpr)
    S.regions = {}
    UI.BeginDesign()
    nvgBeginPath(S.ctx)
    nvgRect(S.ctx, 0, 0, Config.DESIGN_W, Config.DESIGN_H)
    nvgFillColor(S.ctx, nvgRGBA(16, 14, 22, 255))
    nvgFill(S.ctx)

    if S.screen == "combat" then
        Combat.Draw()
    elseif S.screen == "shop" then
        Screens.DrawShop()
    elseif S.screen == "event" then
        Screens.DrawEvent()
    elseif S.screen == "levelclear" then
        Screens.DrawLevelClear()
    elseif S.screen == "map" then
        Screens.DrawMap()
    end
    UI.DrawToast()
    UI.EndDesign()
    nvgEndFrame(S.ctx)
end
