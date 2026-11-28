-- DevFx.lua — 技能特效（序列帧）接入回归：火球 / 冰锥 / 闪电链
local Config = require "Config"
local Save = require "Save"
local S = require "State"
local Run = require "Run"
local Combat = require "Combat"
local EffectArt = require "EffectArt"

local fails = 0
local function check(name, cond, detail)
    if cond then
        print("[Fx] OK   " .. name)
    else
        fails = fails + 1
        print("[Fx] FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
    end
end

local function NewCombat(loadout)
    S.data = Save.Load()
    Save.SetClass(S.data, "mage")
    Save.SetClassLevel(S.data, 10)
    Config.SetClass("mage")
    Run.Start(3, true)
    S.run.loadout = loadout
    local cs = Combat.Start(S.run, "standard", 1)
    S.screen = "combat"
    cs.enemies = {}
    cs.walls = {}
    cs.waves = { {} }
    cs.waveIndex = 1
    cs.anim = nil
    cs.player.cooldowns = {}
    return cs
end

local function Enemy(cs, dx, dy)
    Combat.SpawnWave(cs, { minion = 1 })
    local e = cs.enemies[#cs.enemies]
    e.hp, e.maxHp = 99999, 99999
    e.x, e.y = cs.player.x + (dx or 160), cs.player.y + (dy or 0)
    return e
end

local function CountFx(cs, id)
    local n = 0
    for _, f in ipairs(cs.fx or {}) do
        if f.id == id then n = n + 1 end
    end
    return n
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
    S.font = nvgCreateFont(S.ctx, "sans", "Fonts/MiSans-Game.ttf")

    -- 0) 图集能加载、帧号/时长正常
    for _, id in ipairs({ "fire_proj", "fire_impact", "ice_proj", "ice_impact", "chain" }) do
        local def = EffectArt.Def(id)
        check("特效已登记：" .. id, def ~= nil)
        check("时长合理：" .. id, EffectArt.Duration(id) > 0.2 and EffectArt.Duration(id) < 1.0,
            EffectArt.Duration(id))
        local ok = EffectArt.Draw(id, 0, 400, 300, { scale = 0.5 })
        check("能画出来：" .. id, ok == true)
    end

    -- 1) 火球：弹道带 fx，命中出命中特效
    local cs = NewCombat({ 1, 4, 5 })
    local e = Enemy(cs, 120, 0)
    e.x, e.y = cs.player.x + 60, cs.player.y
    Combat.CastSkill(1)
    local proj
    for _, pr in ipairs(cs.projs or {}) do
        if pr.fx then proj = pr end
    end
    check("火球弹道带序列帧", proj and proj.fx == "fire_proj", proj and proj.fx)
    check("火球带命中特效配置", proj and proj.fxImpact == "fire_impact",
        proj and proj.fxImpact)
    -- 去掉顿帧后命中更早，跑太久特效已经播完，这里只推进一小段
    for _ = 1, 10 do Combat.Update(1 / 60) end
    check("命中后生成火球爆炸特效", CountFx(cs, "fire_impact") >= 1, CountFx(cs, "fire_impact"))
    for _ = 1, 90 do Combat.Update(1 / 60) end
    check("命中特效会自己消失", CountFx(cs, "fire_impact") == 0, CountFx(cs, "fire_impact"))

    -- 2) 冰锥
    cs = NewCombat({ 1, 4, 5 })
    Enemy(cs, 60, 0)
    Combat.CastSkill(2)
    local ip
    for _, pr in ipairs(cs.projs or {}) do
        if pr.fx then ip = pr end
    end
    check("冰锥弹道带序列帧", ip and ip.fx == "ice_proj", ip and ip.fx)
    local seenIce = false
    for _ = 1, 40 do
        Combat.Update(1 / 60)
        if CountFx(cs, "ice_impact") >= 1 then seenIce = true end
    end
    check("冰锥命中出特效", seenIce == true, CountFx(cs, "ice_impact"))

    -- 3) 闪电链：每次链到目标都有一条电弧特效
    cs = NewCombat({ 1, 4, 5 })
    Enemy(cs, 60, 0)
    Combat.CastSkill(3)
    check("闪电链生成电弧特效", CountFx(cs, "chain") >= 1, CountFx(cs, "chain"))

    -- 4) 别的职业不受影响（游侠普攻仍是老画法）
    S.data = Save.Load()
    Save.SetClass(S.data, "ranger")
    Config.SetClass("ranger")
    Run.Start(3, true)
    S.run.loadout = { 1, 2, 3 }
    local cs2 = Combat.Start(S.run, "standard", 1)
    S.combat = cs2
    S.screen = "combat"
    cs2.enemies, cs2.walls, cs2.waves, cs2.waveIndex = {}, {}, { {} }, 1
    Combat.BasicAttack(cs2)
    local hasFx = false
    for _, pr in ipairs(cs2.projs or {}) do if pr.fx then hasFx = true end end
    check("游侠普攻不套法师特效", hasFx == false)

    print(string.format("[Fx] done, failures = %d", fails))
end
