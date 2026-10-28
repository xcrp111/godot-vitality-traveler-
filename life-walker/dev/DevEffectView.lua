-- DevEffectView.lua — 剑气波 / 剑影的可见效果截图
local Config = require "Config"
local Save = require "Save"
local S = require "State"
local UI = require "UI"
local Run = require "Run"
local Combat = require "Combat"
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
    math.randomseed(4)
    S.data = Save.Load()
    Save.SetClassLevel(S.data, 10)
    Run.Start(1)
    S.run.loadout = { 1, 2, 4 }
    local p = S.run.player
    Run.GrantBuff(p, { id = "t_oni", name = "鬼剑术", desc = "", rarity = "color",
        classBuff = true, mod = {}, flag = { oni = 1 } })
    Run.GrantBuff(p, { id = "t_vision", name = "虚影回响", desc = "", rarity = "purple",
        classBuff = true, mod = {}, flag = { illusionChance = 1.0 } })
    Run.GrantBuff(p, { id = "t_after", name = "残影留存", desc = "", rarity = "purple",
        classBuff = true, mod = {}, flag = { phantomPct = 0.9 } })
    local cs = Combat.Start(S.run, "standard", 3)
    cs.enemies = {}
    cs.waveIndex = #cs.waves
    Combat.SpawnWave(cs, { minion = 3 })
    S.screen = "combat"
    p.intent = 5
    for i, e in ipairs(cs.enemies) do
        local a = -0.3 + i * 0.3
        e.x = p.x + math.cos(a) * (170 + i * 30)
        e.y = p.y + math.sin(a) * (170 + i * 30)
    end
    SubscribeToEvent(S.ctx, "NanoVGRender", "HandleRender")
    SubscribeToEvent("Update", "HandleUpdate")
end

function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    frame = frame + 1
    local cs = S.combat
    if not cs then return end
    if frame == 30 then
        cs.facing = 0
        Combat.BasicAttack(cs)
        Combat.CastSkill(1)
    end
    if frame > 30 then
        cs.cleared = false
        cs.clearTimer = 0
        for _, e in ipairs(cs.enemies) do
            local a = math.atan(e.y - cs.player.y, e.x - cs.player.x)
            local d = math.max(120, math.sqrt((e.x - cs.player.x) ^ 2 + (e.y - cs.player.y) ^ 2))
            e.x = cs.player.x + math.cos(a) * d
            e.y = cs.player.y + math.sin(a) * d
        end
        Combat.Update(dt)
        -- 保持剑气方向，不被自动锁敌改掉
        cs.facing = 0
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
