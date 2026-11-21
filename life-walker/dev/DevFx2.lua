-- DevFx2.lua — 其余法师技能特效 + 状态特效回归
local Config = require "Config"
local Save = require "Save"
local S = require "State"
local Run = require "Run"
local Combat = require "Combat"
local EffectArt = require "EffectArt"

local fails = 0
local function check(name, cond, detail)
    if cond then
        print("[Fx2] OK   " .. name)
    else
        fails = fails + 1
        print("[Fx2] FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
    end
end

local function NewCombat(loadout)
    S.data = Save.Load()
    Save.SetClass(S.data, "mage")
    Save.SetClassLevel(S.data, 12)
    Config.SetClass("mage")
    Run.Start(5, true)
    S.run.loadout = loadout
    local cs = Combat.Start(S.run, "standard", 1)
    S.screen = "combat"
    S.combat = cs
    cs.enemies, cs.walls, cs.waves, cs.waveIndex = {}, {}, { {} }, 1
    cs.anim = nil
    cs.player.cooldowns = {}
    return cs
end

local function Enemy(cs, dx, dy)
    Combat.SpawnWave(cs, { minion = 1 })
    local e = cs.enemies[#cs.enemies]
    e.hp, e.maxHp = 99999, 99999
    e.x, e.y = cs.player.x + (dx or 120), cs.player.y + (dy or 0)
    return e
end

local function HasFx(cs, id)
    for _, f in ipairs(cs.fx or {}) do
        if f.id == id then return true end
    end
    return false
end

local function FieldFx(cs)
    for _, f in ipairs(cs.mageFields or {}) do
        if f.fx then return f.fx end
    end
    return nil
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

    -- 0) 新增特效都能加载并画出来
    for _, id in ipairs({ "frost", "flame", "meteor", "meteor_hit", "static", "blizzard",
        "thunder", "burn", "freeze", "slow" }) do
        check("已登记：" .. id, EffectArt.Def(id) ~= nil)
        check("能画：" .. id, EffectArt.Draw(id, 0.1, 400, 300, { scale = 0.4 }) == true)
    end

    -- 1) 冰冻波（slot1 换成技能2）
    local cs = NewCombat({ 2, 6, 8 })
    Enemy(cs, 100, 0)
    Combat.CastSkill(1)
    check("冰冻波出特效", HasFx(cs, "frost"))

    -- 2) 烈焰冲击
    cs = NewCombat({ 6, 2, 8 })
    Enemy(cs, 90, 0)
    Combat.CastSkill(1)
    check("烈焰冲击出特效", HasFx(cs, "flame"))

    -- 3) 流星陨落：陨石 + 延后的落地冲击
    cs = NewCombat({ 8, 2, 6 })
    Enemy(cs, 120, 0)
    Combat.CastSkill(1)
    check("流星出陨石特效", HasFx(cs, "meteor"))
    check("流星出落地冲击特效", HasFx(cs, "meteor_hit"))
    local delay = 0
    for _, f in ipairs(cs.fx or {}) do
        if f.id == "meteor_hit" then delay = f.delay or 0 end
    end
    check("落地冲击是延后的", delay > 0, delay)

    -- 4) 雷击术
    cs = NewCombat({ 3, 2, 6 })
    Enemy(cs, 80, 0)
    Combat.CastSkill(1)
    check("雷击术出特效", HasFx(cs, "thunder"))

    -- 5) 静电力场 / 暴风雪：地面范围带循环特效
    cs = NewCombat({ 7, 2, 6 })
    Enemy(cs, 60, 0)
    Combat.CastSkill(1)
    check("静电力场带循环特效", FieldFx(cs) == "static", FieldFx(cs))

    cs = NewCombat({ 9, 2, 6 })
    Enemy(cs, 60, 0)
    Combat.CastSkill(1)
    check("暴风雪带循环特效", FieldFx(cs) == "blizzard", FieldFx(cs))

    -- 6) 状态特效：打上火/冰/减速后敌人身上有状态
    cs = NewCombat({ 1, 2, 6 })
    local e = Enemy(cs, 60, 0)
    Combat.HitEnemy(cs, e, 10, true, true, false, "skill")
    check("能画一帧战斗（含敌人状态特效）", pcall(function() Combat.Draw() end))

    print(string.format("[Fx2] done, failures = %d", fails))
end
