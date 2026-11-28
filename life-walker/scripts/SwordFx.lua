-- SwordFx.lua — 剑客素材包特效的「事件 → 特效」映射表
--
-- 108 个序列帧全部在这里登记。战斗代码只按事件名调用：
--     SwordFx.Spawn(cs, "combo_crush", x, y)
--     SwordFx.SpawnAll(cs, "combo_shock", x, y)   -- 一组同时播（源 + 波）
--
-- 每个事件都带最小间隔（gap），避免多目标时一张帧刷屏。
local EffectArt = require "EffectArt"

local SwordFx = {}

-- 事件 → 候选特效（随机挑一个；SpawnAll 会全播）
SwordFx.EVENTS = {
    -- 出场 / 角色状态
    spawn              = { "swfx_A01_spawn_fx" },
    shield_hit         = { "swfx_A10_shield_hit" },
    shield_break       = { "swfx_A11_shield_break" },
    shield_restore     = { "swfx_A12_shield_restore", "swfx_V13_shield" },
    armor_shield       = { "swfx_V13_armor" },
    heal               = { "swfx_A15h_heal" },
    drain              = { "swfx_A15v_drain" },
    mana_return        = { "swfx_A15m_mana" },
    revive             = { "swfx_A14_revive_fx" },
    dodge              = { "swfx_GG03_evade" },
    hp_cost            = { "swfx_GR02_cost", "swfx_V18_cost" },
    rage_on            = { "swfx_V18_rage" },
    rage_end           = { "swfx_V18_end" },
    invul              = { "swfx_V06_invul" },
    control_immune     = { "swfx_SP05_controlimmune" },
    freed              = { "swfx_V12_free" },
    charge             = { "swfx_V09_chargefx" },
    cd_reset           = { "swfx_V25_reset" },
    free_charge        = { "swfx_V25_free" },

    -- 剑意（资源）
    intent_gain        = { "swfx_P01_gain" },
    intent_burst1      = { "swfx_P01_burst1" },
    intent_burst2      = { "swfx_P01_burst2" },
    intent_burst3      = { "swfx_P01_burst3", "swfx_P01_full", "swfx_V29_cap_change" },
    intent_double      = { "swfx_P01_double", "swfx_S03_extra_gain" },
    intent_fade        = { "swfx_P01_fade" },
    skills_ready       = { "swfx_V28_flow" },

    -- 三种物理负面
    crack              = { "swfx_E01_apply" },
    crack_cap          = { "swfx_V28_full", "swfx_V26_area" },
    crack_spread       = { "swfx_V23_spread", "swfx_V23_extra" },
    crack_refresh      = { "swfx_E01_refresh" },
    crack_decay        = { "swfx_E01_decay" },
    crack_clear        = { "swfx_E01_clear" },
    stagger            = { "swfx_E02_apply" },
    stagger_cap        = { "swfx_V11_imbalance" },
    stagger_clear      = { "swfx_E02_clear" },
    hunt               = { "swfx_E03_apply" },
    hunt_mark          = { "swfx_V11_huntmark" },
    hunt_refresh       = { "swfx_E03_refresh" },
    hunt_decay         = { "swfx_E03_decay" },
    hunt_clear         = { "swfx_E03_clear" },
    debuff_all         = { "swfx_V19_multi" },
    lock               = { "swfx_V10_lock" },
    bleed              = { "swfx_V10_bleed" },

    -- 连携
    combo_crush        = { "swfx_CMB01_crush", "swfx_CMB01_impact", "swfx_V21_crush" },
    combo_shock        = { "swfx_CMB02_receive" },
    combo_hunt         = { "swfx_CMB03_start" },
    combo_hunt_hold    = { "swfx_CMB03_buff" },
    combo_hunt_end     = { "swfx_CMB03_end" },
    combo_misalign     = { "swfx_V21_swap" },
    combo_shock_source = { "swfx_CMB02_source" },
    combo_shock_wave   = { "swfx_CMB02_wave", "swfx_V21_wave" },
    combo_shock_slow   = { "swfx_CMB02_slow" },
    combo_hunt_pair    = { "swfx_V21_hunt" },

    -- 普攻 / 剑气
    basic_hit          = { "swfx_S00_hit" },
    basic_trail        = { "swfx_S00_trail" },
    windblade          = { "swfx_V02_windblade", "swfx_V07_wave" },
    oni_area           = { "swfx_V17_area", "swfx_V17_hit", "swfx_V17_wave" },
    pierce             = { "swfx_V04_pierce" },
    knockback          = { "swfx_V03_push" },
    extra_hit          = { "swfx_V23_extra" },

    -- 技能
    sk_stab_spawn      = { "swfx_S01_spawn", "swfx_S01_ready" },
    sk_stab_fly        = { "swfx_S01_fly" },
    sk_stab_hit        = { "swfx_S01_impact", "swfx_S01_air" },
    sk_stab_end        = { "swfx_S01_dissipate" },
    sk_stab_stack      = { "swfx_S01_stackgain" },
    sk_dash            = { "swfx_S02_swordpath" },
    sk_dash_after      = { "swfx_S02_after" },
    sk_dash_hit        = { "swfx_S02_hit" },
    sk_guard_start     = { "swfx_S03_flare", "swfx_S03_aura" },
    sk_guard_end       = { "swfx_S03_end" },
    sk_guard_edge      = { "swfx_S03_edge" },
    sk_spin_hit        = { "swfx_S04_hit" },
    sk_spin_orbit      = { "swfx_S04_orbit", "swfx_V22_orbit1" },
    sk_spin_orbit2     = { "swfx_V22_orbit2" },
    sk_blink_trail     = { "swfx_S06_trail" },
    sk_blink_hit       = { "swfx_S06_impact" },
    sk_blink_after     = { "swfx_S06_after" },
    guard_contact      = { "swfx_S05_contact_fx" },
    guard_aoe          = { "swfx_S05_lv3" },
    guard_hold         = { "swfx_V24_guard" },
    guard_second       = { "swfx_V24_second" },
    deflect            = { "swfx_V02_deflect" },
    reflect            = { "swfx_SP06_reflect" },
    guard_break        = { "swfx_V07_wave" },

    -- 虚影 / 代偿
    phantom_spawn      = { "swfx_V11_summon" },
    phantom_hunt       = { "swfx_V11_huntmark" },
    phantom_stagger    = { "swfx_V11_imbalance" },
    phantom_fade       = { "swfx_V11_fade" },
    compensate_store   = { "swfx_V20_store" },
    compensate_extract = { "swfx_V20_extract" },
    compensate_fly     = { "swfx_V20_inflight" },
    compensate_move    = { "swfx_V20_transfer" },
    compensate_clear   = { "swfx_V20_clear" },

    -- 击杀 / 区域
    kill_reset         = { "swfx_V29_reset" },
    area_edge          = { "swfx_V26_edge" },
    cast_ready         = { "swfx_S01_ready" },
}

local last_ = {}

local function Duration(id)
    local def = EffectArt.Def(id)
    return def and EffectArt.Duration(id) or 0.3
end

--- 播一个事件（随机取一个候选）
---@param cs table 战斗状态
---@param key string 事件名（SwordFx.EVENTS 的键）
---@param x number
---@param y number
---@param opts? { scale?: number, rot?: number, gap?: number, alpha?: number }
function SwordFx.Spawn(cs, key, x, y, opts)
    local list = SwordFx.EVENTS[key]
    if not cs or not list or #list == 0 then return end
    opts = opts or {}
    local now = cs.time or 0
    local gap = opts.gap or 0.1
    if now - (last_[key] or -999) < gap then return end
    last_[key] = now
    local id = list[math.random(#list)]
    if not EffectArt.Def(id) then return end
    cs.fx = cs.fx or {}
    cs.fx[#cs.fx + 1] = {
        id = id, x = x, y = y, t = 0,
        dur = opts.life or Duration(id),
        delay = 0, rot = opts.rot, scale = opts.scale, alpha = opts.alpha,
    }
end

--- 播一个事件的整组（源 + 波这种需要同时出现的）
function SwordFx.SpawnAll(cs, key, x, y, opts)
    local list = SwordFx.EVENTS[key]
    if not cs or not list then return end
    opts = opts or {}
    for _, id in ipairs(list) do
        if EffectArt.Def(id) then
            cs.fx = cs.fx or {}
            cs.fx[#cs.fx + 1] = {
                id = id, x = x, y = y, t = 0,
                dur = opts.life or Duration(id),
                delay = 0, rot = opts.rot, scale = opts.scale, alpha = opts.alpha,
            }
        end
    end
end

--- 战斗开始时清掉节流记录
function SwordFx.Reset()
    last_ = {}
end

--- 当前映射覆盖了多少个特效 id（回归测试用）
function SwordFx.CoveredIds()
    local set = {}
    for _, list in pairs(SwordFx.EVENTS) do
        for _, id in ipairs(list) do set[id] = true end
    end
    return set
end

return SwordFx
