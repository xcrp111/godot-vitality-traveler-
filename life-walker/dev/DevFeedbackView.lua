-- DevFeedbackView.lua — 截图验收：长按瞄准预览 / 夹子模型 / 格挡横剑
local Config = require "Config"
local Save = require "Save"
local S = require "State"
local UI = require "UI"
local Run = require "Run"
local Combat = require "Combat"

local frame = 0

local function Setup(class, loadout)
    S.data = Save.Load()
    Save.SetClass(S.data, class)
    Save.SetClassLevel(S.data, 10)
    Config.SetClass(class)
    Run.Start(3, true)
    S.run.loadout = loadout
    local cs = Combat.Start(S.run, "standard", 2)
    cs.enemies = {}
    cs.waveIndex = #cs.waves
    Combat.SpawnWave(cs, { minion = 4, elite = 1 })
    S.screen = "combat"
    local p = cs.player
    p.x, p.y = 640, 380
    for i, e in ipairs(cs.enemies) do
        e.x = p.x + 150 + i * 40
        e.y = p.y - 90 + i * 45
        e.hp = e.maxHp
    end
    cs.walls = {}
    return cs
end

function Start()
    local dpr = graphics:GetDPR(); if not dpr or dpr <= 0 then dpr = 1 end
    S.dpr = dpr
    S.W = graphics:GetWidth() / dpr
    S.H = graphics:GetHeight() / dpr
    S.scale = math.min(S.W / Config.DESIGN_W, S.H / Config.DESIGN_H)
    S.offX = (S.W - Config.DESIGN_W * S.scale) / 2
    S.offY = (S.H - Config.DESIGN_H * S.scale) / 2
    S.ctx = nvgCreate(1)
    S.font = nvgCreateFont(S.ctx, "sans", "Fonts/MiSans-Regular.ttf")
    math.randomseed(11)

    local cs = Setup("mage", { 1, 3, 8 })
    cs.facing = 0
    cs.aim = {
        slot = 1, id = 1, spec = Config.SkillAimOf(1), tid = 1,
        t = 0.4, sx = 0, sy = 0, moved = true, angle = -0.55,
        point = { x = cs.player.x, y = cs.player.y },
    }

    SubscribeToEvent(S.ctx, "NanoVGRender", "HandleRender")
    SubscribeToEvent("Update", "HandleUpdate")
end

function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    frame = frame + 1
    local cs = S.combat
    if not cs then return end

    if frame == 55 then
        -- 游侠：夹子模型 + 落点瞄准
        cs = Setup("ranger", { 4, 3, 5 })
        cs.facing = 0
        cs.player.cooldowns[4] = 0
        cs.aimPoint = { x = cs.player.x + 150, y = cs.player.y - 60 }
        cs.aimLock = true
        Combat.CastSkill(1)
        cs.aimLock = nil
        cs.aimPoint = nil
        cs.aim = {
            slot = 1, id = 4, spec = Config.SkillAimOf(4), tid = 1,
            t = 0.4, sx = 0, sy = 0, moved = true, angle = -0.4,
            point = { x = cs.player.x + 170, y = cs.player.y - 80 },
        }
    elseif frame == 105 then
        -- 剑客：格挡横剑 + 成功闪光
        cs = Setup("swordsman", { 1, 2, 3 })
        cs.facing = 0.2
        cs.player.parryTimer = 1.0
        cs.player.parryLeft = 99
        cs.parryFlash = 0.28
    end

    if cs then
        Combat.Update(dt)
        cs.player.hp = cs.player.maxHp
        cs.player.shield = cs.player.maxShield
        if cs.aim then cs.aim.t = 0.4 end
    end
end

function HandleRender(eventType, eventData)
    if not S.ctx then return end
    local W, H = graphics:GetWidth(), graphics:GetHeight()
    nvgBeginFrame(S.ctx, W, H, S.dpr)
    UI.BeginDesign()
    if S.combat then Combat.Draw() end
    UI.EndDesign()
    nvgEndFrame(S.ctx)
end
