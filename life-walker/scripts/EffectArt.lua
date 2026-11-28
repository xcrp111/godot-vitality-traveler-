-- EffectArt.lua — 技能特效图集（像素序列帧）
-- 素材来自「法师迭代素材包」，由 dev/make_fx_sheets.js 整理成横条：
--   每张 assets/image/fx/<ID>.png = 8 帧横向排列，单帧 CELL×CELL，帧内内容居中
--   （原始素材单帧 256×256，导入时按整体等比缩到 CELL，保留像素风格）
local UI = require "UI"
local S = require "State"

local EffectArt = {}

EffectArt.CELL = 128

-- 特效定义：file 相对资源根；fps 决定播放速度；loop 决定播完循环还是消失
EffectArt.Defs = {
    -- 火球（法师技能 1）
    fire_proj   = { file = "image/fx/E03_fireball_projectile_L1.png", fps = 16, loop = true,  scale = 0.38 },
    fire_impact = { file = "image/fx/E04_fireball_impact_L1.png",     fps = 18, loop = false, scale = 0.75 },
    -- 冰锥（法师技能 4）
    ice_proj    = { file = "image/fx/E09_ice_spike_projectile_L1.png", fps = 16, loop = true,  scale = 0.38 },
    ice_impact  = { file = "image/fx/E10_ice_spike_impact_L1.png",     fps = 18, loop = false, scale = 0.75 },
    -- 闪电链（法师技能 5）
    chain       = { file = "image/fx/E12_chain_lightning_L1.png",      fps = 18, loop = false, scale = 0.85 },
    -- 冰冻波（法师技能 2）
    frost       = { file = "image/fx/E08_frost_wave_L1.png",           fps = 16, loop = false, scale = 0.9 },
    -- 烈焰冲击（法师技能 6）
    flame       = { file = "image/fx/E05_flame_burst_L1.png",          fps = 16, loop = false, scale = 0.9 },
    -- 流星陨落（法师技能 8）：落下的陨石 + 落地冲击
    meteor      = { file = "image/fx/E06_meteor_projectile_L1.png",    fps = 12, loop = true,  scale = 0.7 },
    meteor_hit  = { file = "image/fx/E07_meteor_impact_L1.png",        fps = 16, loop = false, scale = 1.0 },
    -- 静电力场（法师技能 7）/ 暴风雪（法师技能 9）：跟着地面范围的循环特效
    static      = { file = "image/fx/E14_static_field_L1.png",         fps = 8,  loop = true,  scale = 0.9 },
    blizzard    = { file = "image/fx/E11_blizzard_L1.png",             fps = 10, loop = true,  scale = 1.0 },
    -- 雷击术（法师技能 3）
    thunder     = { file = "image/fx/E13_thunder_strike_L1.png",       fps = 16, loop = false, scale = 0.85 },
    -- 敌人身上的状态特效（循环）
    burn        = { file = "image/fx/S01_burn_loop.png",               fps = 10, loop = true,  scale = 0.5 },
    freeze      = { file = "image/fx/S03_freeze_loop.png",             fps = 10, loop = true,  scale = 0.55 },
    slow        = { file = "image/fx/S05_slow_loop.png",               fps = 8,  loop = true,  scale = 0.55 },

    -- 剑客（swordswoman 素材包）
    sw_stab     = { file = "image/fx/sw_stab.png",      fps = 18, loop = false, scale = 1.0 },
    sw_dash     = { file = "image/fx/sw_dash.png",      fps = 20, loop = false, scale = 0.9 },
    sw_guardaura= { file = "image/fx/sw_guardaura.png", fps = 10, loop = true,  scale = 0.9 },
    sw_spin     = { file = "image/fx/sw_spin.png",      fps = 18, loop = false, scale = 1.1 },
    sw_shadow   = { file = "image/fx/sw_shadow.png",    fps = 20, loop = false, scale = 0.9 },
    sw_parry    = { file = "image/fx/sw_parry.png",     fps = 22, loop = false, scale = 0.8 },
}

-- 剑客素材包的全部特效（由 dev/make_sword_fx_all.js 生成的表，启动时并进来）
do
    local ok, SwordFx = pcall(require, "SwordFxDefs")
    if ok and type(SwordFx) == "table" then
        for id, def in pairs(SwordFx) do
            if EffectArt.Defs[id] == nil then EffectArt.Defs[id] = def end
        end
    end
end

local failed = {}

---@return table|nil
function EffectArt.Def(id)
    return id and EffectArt.Defs[id] or nil
end

--- 播完一整套需要多少秒
function EffectArt.Duration(id)
    local def = EffectArt.Def(id)
    if not def then return 0 end
    return 8 / (def.fps or 16)
end

--- 当前帧号（1..8）
function EffectArt.Frame(id, t)
    local def = EffectArt.Def(id)
    if not def then return 1 end
    local fps = def.fps or 16
    local n = math.floor((t or 0) * fps) + 1
    if def.loop then
        return (n - 1) % 8 + 1
    end
    return math.min(8, n)
end

--- 画一帧特效；x,y 是中心点
---@param id string 特效 id
---@param t number 已播放秒数
---@param x number 中心 x
---@param y number 中心 y
---@param opts table|nil { rot=弧度, scale=倍数, alpha=0~1 }
function EffectArt.Draw(id, t, x, y, opts)
    local def = EffectArt.Def(id)
    if not def or failed[id] then return false end
    local img = UI.ImageHandle(def.file)
    if not img then failed[id] = true; return false end
    local iw, ih = nvgImageSize(S.ctx, img)
    if not iw or iw <= 0 or not ih or ih <= 0 then
        failed[id] = true
        return false
    end
    opts = opts or {}
    local cell = EffectArt.CELL
    local k = opts.scale or def.scale or 1
    local frame = EffectArt.Frame(id, t)
    local alpha = opts.alpha or 1

    nvgSave(S.ctx)
    nvgTranslate(S.ctx, x, y)
    if opts.rot then nvgRotate(S.ctx, opts.rot) end
    nvgTranslate(S.ctx, -cell * k / 2, -cell * k / 2)
    nvgScale(S.ctx, (cell * k) / cell, (cell * k) / cell)

    local paint = nvgImagePattern(S.ctx, -(frame - 1) * cell, 0, iw, ih, 0, img, alpha)
    nvgBeginPath(S.ctx)
    nvgRect(S.ctx, 0, 0, cell, cell)
    nvgFillPaint(S.ctx, paint)
    nvgFill(S.ctx)
    nvgRestore(S.ctx)
    return true
end

return EffectArt
