-- DevCharArt.lua — 角色序列帧接入回归（状态机 / 行映射 / 图集可加载）
local Config = require "Config"
local Save = require "Save"
local S = require "State"
local Run = require "Run"
local UI = require "UI"
local Combat = require "Combat"
local CharArt = require "CharArt"

local fails = 0
local function check(name, cond, detail)
    if cond then
        print("[Char] OK   " .. name)
    else
        fails = fails + 1
        print("[Char] FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
    end
end

local function NewCombat(class, loadout)
    S.data = Save.Load()
    Save.SetClass(S.data, class)
    Save.SetClassLevel(S.data, 10)
    Config.SetClass(class)
    Run.Start(3, true)
    if loadout then S.run.loadout = loadout end
    local cs = Combat.Start(S.run, "standard", 1)
    S.screen = "combat"
    cs.enemies = {}
    cs.walls = {}
    cs.waves = { {} }
    cs.waveIndex = 1
    cs.anim = nil
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

    -- 图集能加载
    for _, cls in ipairs({ "swordsman", "spearman", "ranger", "mage" }) do
        local img = UI.ImageHandle("image/char/" .. cls .. ".png")
        local w, h = 0, 0
        if img then w, h = nvgImageSize(S.ctx, img) end
        check("图集可加载 " .. cls, w == 1280 and h > 0, w .. "x" .. h)
    end

    -- 行映射
    check("剑客 普攻行", CharArt.RowOf("swordsman", "attack") == 5)
    check("剑客 技能3 行", CharArt.RowOf("swordsman", "skill", 3) == 8)
    check("法师 技能1 行", CharArt.RowOf("mage", "skill", 1) == 6)
    check("法师 技能9 行", CharArt.RowOf("mage", "skill", 9) == 11)
    check("法师 闪避行", CharArt.RowOf("mage", "dodge") == 15)
    check("法师 胜利行", CharArt.RowOf("mage", "victory") == 16)

    -- 状态机：待机 / 行走自动切换
    local cs = NewCombat("swordsman", { 1, 2, 3 })
    S.input.x, S.input.y = 0, 0
    CharArt.Update(cs, 1 / 60)
    check("默认待机", cs.anim and cs.anim.action == "idle", cs.anim and cs.anim.action)
    S.input.x = 1
    CharArt.Update(cs, 1 / 60)
    check("移动切行走", cs.anim and cs.anim.action == "walk", cs.anim and cs.anim.action)
    S.input.x, S.input.y = 0, 0

    -- 普攻 / 技能 / 受击 会覆盖，并在时长后回落
    Combat.BasicAttack(cs)
    check("普攻覆盖为 attack", cs.anim and cs.anim.action == "attack", cs.anim and cs.anim.action)
    for _ = 1, 50 do CharArt.Update(cs, 1 / 60) end   -- 普攻现在 0.6 秒
    check("普攻播完回落到待机", cs.anim == nil or cs.anim.action == "idle",
        cs.anim and cs.anim.action)

    cs.player.cooldowns = {}
    Combat.CastSkill(3)   -- 剑心护体
    check("技能覆盖并取对应行", cs.anim and cs.anim.row == 8, cs.anim and cs.anim.row)

    cs.anim = nil
    cs.player.shield = 0
    Combat.DamagePlayer(cs, 10)
    check("受击播受击", cs.anim and cs.anim.action == "hurt", cs.anim and cs.anim.action)

    -- 画一帧不报错
    local p = cs.player
    local ok = CharArt.Draw("swordsman", 1, 1, p.x, p.y + p.radius, false, 1)
    check("绘制成功", ok == true, ok)
    local okFlip = CharArt.Draw("swordsman", 1, 1, p.x, p.y + p.radius, true, 1)
    check("镜像绘制成功", okFlip == true, okFlip)


    -- 行走 fps 跟着移速（以前固定 10）
    cs = NewCombat("swordsman", { 1, 2, 3 })
    cs.player.moveSpeed = 128
    S.input.x, S.input.y = 1, 0
    CharArt.Update(cs, 1 / 60)
    check("行走 fps 跟移速同步", cs.anim and cs.anim.action == "walk" and (cs.anim.fps or 0) > 12,
        cs.anim and cs.anim.fps)
    S.input.x, S.input.y = 0, 0

    -- hitstop：命中会冻结一段时间，且期间 cs.time 不再推进
    cs = NewCombat("swordsman", { 1, 2, 3 })
    Combat.SpawnWave(cs, { minion = 1 })
    local en = cs.enemies[1]
    en.x, en.y = cs.player.x + 40, cs.player.y
    en.hp, en.maxHp = 9999, 9999
    cs.hitstop = 0
    Combat.HitEnemy(cs, en, 10, false, true, false, "basic")
    check("命中触发 hitstop", (cs.hitstop or 0) > 0, cs.hitstop)
    check("命中带方向性震屏", (cs.shakeDirX or 0) ~= 0 or (cs.shakeDirY or 0) ~= 0,
        tostring(cs.shakeDirX) .. "," .. tostring(cs.shakeDirY))
    local t0 = cs.time
    Combat.Update(1 / 60)
    check("hitstop 期间时间冻结", math.abs(cs.time - t0) < 1e-6, cs.time - t0)
    check("hitstop 计时在走", (cs.hitstop or 0) < 0.09, cs.hitstop)

    print(string.format("[Char] done, failures = %d", fails))
end
