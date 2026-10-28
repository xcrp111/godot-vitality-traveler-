-- DevClassView.lua — 全专属强化下的战斗 HUD / 强化面板渲染检查
local Config = require "Config"
local Save = require "Save"
local S = require "State"
local UI = require "UI"
local Run = require "Run"
local Combat = require "Combat"
local VirtualControls = require "urhox-libs.UI.VirtualControls"

local frame = 0

local function GrantAll(run)
    local p = run.player
    local saved = run.loadout
    run.loadout = { 1, 2, 3, 4, 5, 6 }
    for _, rarity in ipairs({ "white", "blue", "purple", "gold", "color" }) do
        while true do
            local buff = Run.RollClassBuff(p, rarity)
            if not buff then break end
            Run.GrantBuff(p, buff)
        end
    end
    run.loadout = saved
    for _, rarity in ipairs({ "white", "blue", "purple", "gold" }) do
        Run.GrantBuff(p, Run.RollBuff(rarity))
    end
end

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
    math.randomseed(3)
    S.data = Save.Load()
    Save.SetClassLevel(S.data, 10)
    Run.Start(2)
    GrantAll(S.run)
    local cs = Combat.Start(S.run, "standard", 5)
    S.screen = "combat"
    for i = 1, 4 do
        cs.enemies = cs.enemies or {}
    end
    Combat.SpawnWave(cs, { minion = 4 })
    for _, e in ipairs(cs.enemies) do
        e.x = cs.player.x + math.random(-160, 160)
        e.y = cs.player.y + math.random(-120, 120)
    end
    cs.player.intent = 3
    cs.player.hp = cs.player.maxHp
    SubscribeToEvent(S.ctx, "NanoVGRender", "HandleRender")
    SubscribeToEvent("Update", "HandleUpdate")
end

function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    frame = frame + 1
    local cs = S.combat
    if not cs then return end
    Combat.Update(dt)
    if frame == 40 then
        Combat.CastSkill(1)
    end
    if frame >= 70 then
        cs.showBuffs = true
    end
end

function HandleRender(eventType, eventData)
    if not S.ctx then return end
    nvgBeginFrame(S.ctx, graphics:GetWidth(), graphics:GetHeight(), S.dpr)
    S.regions = {}
    UI.BeginDesign()
    Combat.Draw()
    UI.DrawToast()
    UI.EndDesign()
    nvgEndFrame(S.ctx)
end
