-- Config.lua
-- 全部数值与静态数据。改数值只改这里。

local Config = {}

Config.GAME_TITLE = "生命行者"
Config.VERSION = "0.1.0"
Config.DESIGN_W = 1280
Config.DESIGN_H = 720

-- 换算
Config.PPM = 32                 -- 1 米 = 32 像素（仅用于手感参考）
Config.STEP_KCAL = 0.04         -- 每步约消耗千卡
Config.REST_KCAL = 1800         -- 每日静息消耗

-- ---------------------------------------------------------------- 数学工具
local function Round(x)
    return math.floor(x + 0.5)
end
Config.Round = Round

function Config.Clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

function Config.Lerp(a, b, t)
    return a + (b - a) * t
end

-- ---------------------------------------------------------------- 怪物数值
-- 第 N 关 · 第 1 房基准
function Config.MinionHP(level)
    return Round(25 * (1 + (level - 1) * 0.2) ^ 1.4)
end

function Config.MinionATK(level)
    return Round(5 + (level - 1) * 0.9)
end

-- 房间倍率：M 从 1 开始，超过 9 按 9 锁
function Config.RoomMul(level, step)
    local m = math.min(step, 9)
    return (1.12 + (level - 1) * 0.0017) ^ (m - 1)
end

-- 返回 hp, atk
function Config.MonsterStats(level, step, kind)
    local hpBase = Config.MinionHP(level)
    local atkBase = Config.MinionATK(level)
    local mul = Config.RoomMul(level, step)
    local hpMul, atkMul = 1.0, 1.0
    if kind == "elite" then
        hpMul, atkMul = 3.5, 1.8
    elseif kind == "boss" then
        hpMul, atkMul = 8.0, 2.5
    end
    return Round(hpBase * mul * hpMul), Round(atkBase * atkMul)
end

-- ---------------------------------------------------------------- 怪物定义
-- behavior: chase 追击 / shooter 远程 / elite 精英 / boss
Config.Monsters = {
    {
        id = "germ", name = "游移病菌", kind = "minion", behavior = "chase",
        radius = 14, speed = 128, color = { 168, 120, 210 },
        desc = "高速游荡，碰到就咬一口",
        codex = "高速追击玩家，贴身时造成接触伤害。血量与攻击最低，适合用来叠剑意和攒银币。",
    },
    {
        id = "spore", name = "病毒孢子囊", kind = "minion", behavior = "shooter",
        radius = 17, speed = 34, color = { 120, 210, 160 },
        desc = "原地喷孢子，别站着不动",
        codex = "保持约 190~320 的距离，每 2.2 秒向玩家发射孢子弹。子弹会被墙体挡住，可以借墙卡视线。",
    },
    {
        id = "worm", name = "潮热沙蠕", kind = "minion", behavior = "chase",
        radius = 16, speed = 100, color = { 230, 150, 100 },
        desc = "贴地蠕行，撞人附带高热",
        codex = "高速冲撞型小兵，移动速度比游移病菌慢一点，但体型更大、接触判定更宽。",
    },
    {
        id = "mycel", name = "腐败菌丝怪", kind = "elite", behavior = "elite",
        radius = 26, speed = 86, color = { 140, 160, 90 },
        desc = "近战叠感染，定期喷一圈孢子",
        codex = "精英模板：3.5 倍小兵 HP、1.8 倍 ATK。近战接触伤害，每 4.5 秒向四周喷出 8 发孢子弹。",
    },
    {
        id = "plague", name = "高热疫魔", kind = "boss", behavior = "boss",
        radius = 46, speed = 72, color = { 235, 70, 70 },
        desc = "大范围震荡冲击，血量过半后狂暴",
        codex = "Boss 模板：8 倍小兵 HP、2.5 倍 ATK。技能：扩散冲击波（被墙挡住的部分会消失）；朝玩家发射 5 发扇形弹幕；0.7 秒红色预警后高速冲锋；血量 66% / 33% 时各召唤 2 只小兵；半血进入狂暴，攻速与冲击波频率提升。",
    },
    -- 以下为「畸变疫病」派系，暂时只在测试模式投放
    {
        id = "abscess", name = "脓肿岩行者", kind = "minion", behavior = "chase",
        radius = 18, speed = 88, color = { 190, 150, 100 }, lateGame = true,
        desc = "近战附带皮肤感染，残血滴落脓水",
        codex = "近战挥拳命中会附加「感染」，4 秒内持续掉血；生命低于 40% 时会在脚下留下腐蚀脓水，站进去会持续受伤。",
    },
    {
        id = "golem", name = "疫蚀石魔", kind = "elite", behavior = "golem",
        radius = 28, speed = 68, color = { 130, 120, 105 }, lateGame = true,
        desc = "重锤附带坏死，跺脚留下腐液",
        codex = "精英模板。重锤命中附加「坏死」，4 秒内受到的治疗减半；每 5 秒跺脚向四周喷溅腐蚀腐液，站在腐液上会持续掉血并减速。",
    },
    {
        id = "colossus", name = "瘟衰巨像", kind = "boss", behavior = "colossus",
        radius = 50, speed = 58, color = { 120, 95, 135 }, lateGame = true,
        desc = "衰弱疫域 + 腐化冲击波",
        codex = "Boss 模板。巨臂拍击附加「衰弱」，4 秒内攻击力 -20%；身边持续存在衰竭疫域（减速 + 掉血）；每 5 秒释放腐化冲击波；血量 50% 时进入狂暴，疫域扩大。",
    },
}

Config.MinionPool = { "germ", "spore", "worm" }

-- ---------------------------------------------------------------- 地图与房间
-- 4x4 固定布局：row 1 在上，col 1 在左；起点 (4,1)，终点 (1,4)
-- 类型：start / light / standard / mixed / elite / double / shop / event / boss
Config.MapLayout = {
    { "standard", "mixed", "elite", "boss" },
    { "standard", "shop", "event", "elite" },
    { "standard", "event", "mixed", "double" },
    { "start", "standard", "shop", "mixed" },
}

Config.RoomNames = {
    start = "起点", light = "轻战房", standard = "标战房", mixed = "混战房",
    elite = "精英房", double = "双精房", shop = "商店房", event = "事件房", boss = "Boss房",
    raid = "公会团本",
}

Config.RoomIcons = {
    start = "起", light = "战", standard = "战", mixed = "混",
    elite = "精", double = "精", shop = "商", event = "?", boss = "B",
    raid = "团",
}

-- 波次：每波是 { minion = n, elite = n, boss = n }
Config.RoomWaves = {
    light = {
        { minion = 3 },
    },
    standard = {
        { minion = 4 },
    },
    mixed = {
        { minion = 3 },
        { elite = 1 },
    },
    elite = {
        { elite = 1, minion = 1 },
        { minion = 1 },
    },
    double = {
        { elite = 1 },
        { elite = 1 },
    },
    boss = {
        { minion = 2 },
        { boss = 1 },
    },
    -- 公会团本：沿用关底 Boss「瘟衰巨像」的模型，先清一小波杂兵再进 Boss
    raid = {
        { minion = 2 },
        { boss = 1 },
    },
}

-- ---------------------------------------------------------------- 银币
Config.SilverDrop = {
    minion = { 2, 4 },
    elite = { 30, 45 },
    boss = { 0, 0 },
}

-- ---------------------------------------------------------------- 商店
Config.Shop = {
    BasePrices = { 12, 24, 24, 32, 24, 40, 64, 115, 12 },
    PotionSmall = { price = 12, heal = 0.33, name = "小型生命药剂", short = "小药", desc = "恢复 33% 生命" },
    PotionLarge = { price = 24, heal = 0.66, name = "大型生命药剂", short = "大药", desc = "恢复 66% 生命" },
    Consumables = {
        { id = "shield", name = "护盾发生器", short = "盾", price = 32, desc = "获得护盾上限 50% 的护盾，可暂时超过上限（最多 150%）" },
        { id = "rage", name = "狂暴药剂", short = "狂", price = 24, desc = "10 秒内攻速 +30%、移速 +20%" },
    },
    RefreshPrice = 12,
    RefreshLimit = 3,
    BuffSlots = 6,
}

-- 品质权重（彩色只出现在角色专属池）
Config.Rarity = {
    white = { name = "白色", weight = 35, price = 24, color = { 220, 220, 225 } },
    blue = { name = "蓝色", weight = 30, price = 40, color = { 96, 170, 255 } },
    purple = { name = "紫色", weight = 22, price = 64, color = { 190, 140, 255 } },
    gold = { name = "金色", weight = 10, price = 115, color = { 255, 200, 80 } },
    color = { name = "彩色", weight = 0, price = 200, color = { 255, 120, 210 } },
}

-- ---------------------------------------------------------------- 通用 Buff
-- 效果写入 mods（加法百分比 / 加法数值）
Config.Buffs = {
    white = {
        { id = "w_hp", name = "生命强化", desc = "生命上限 +15%", mod = { hpPct = 0.15 } },
        { id = "w_sh", name = "护盾强化", desc = "护盾上限 +15%", mod = { shieldPct = 0.15 } },
        { id = "w_atk", name = "攻击强化", desc = "攻击力 +15%", mod = { atkPct = 0.15 } },
        { id = "w_as", name = "急速", desc = "攻速 +12%", mod = { asPct = 0.12 } },
        { id = "w_ms", name = "迅捷", desc = "移速 +10%", mod = { msPct = 0.10 } },
        { id = "w_range", name = "普攻射程", desc = "普攻范围 +10%", mod = { rangePct = 0.10 } },
        { id = "w_ms2", name = "轻身", desc = "移速 +12%", mod = { msPct = 0.12 } },
    },
    blue = {
        { id = "b_ms", name = "移速强化", desc = "移速 +18%", mod = { msPct = 0.18 } },
        { id = "b_crit", name = "暴击率提升", desc = "暴击率 +10%", mod = { crit = 0.10 } },
        { id = "b_as", name = "急速强化", desc = "攻速 +22%", mod = { asPct = 0.22 } },
        { id = "b_cdr", name = "冷却缩减", desc = "技能冷却 -12%", mod = { cdrPct = 0.12 } },
        { id = "b_regen", name = "受创回复", desc = "受伤后 2 秒回复 10% 伤害", mod = { hurtHeal = 0.10 } },
        { id = "b_critls", name = "暴击吸血", desc = "暴击时回复 3 点生命", mod = { critHeal = 3 } },
        { id = "b_wind", name = "疾风", desc = "移速 +15%，攻速 +8%", mod = { msPct = 0.15, asPct = 0.08 } },
    },
    purple = {
        { id = "p_cdr", name = "冷却缩减强化", desc = "技能冷却 -22%", mod = { cdrPct = 0.22 } },
        { id = "p_basic", name = "平A专精", desc = "普通攻击伤害 +30%", mod = { basicPct = 0.30 } },
        { id = "p_skill", name = "技能专精", desc = "技能伤害 +30%", mod = { skillPct = 0.30 } },
        { id = "p_critdmg", name = "暴击伤害提升", desc = "暴击伤害 +30%", mod = { critDmg = 0.30 } },
        { id = "p_as", name = "急速强化", desc = "攻速 +35%", mod = { asPct = 0.35 } },
        { id = "p_ms", name = "移速强化", desc = "移速 +30%", mod = { msPct = 0.30 } },
        { id = "p_ls", name = "全局吸血", desc = "18% 吸血，单次不超过伤害 50%", mod = { lifesteal = 0.18 } },
        { id = "p_reflect", name = "镜面反射", desc = "被弹幕命中时 35% 概率反弹一发（1.5 倍攻击），完全免伤",
          mod = {}, flag = { reflectBullet = 0.35 } },
        { id = "p_clear", name = "弹幕清除", desc = "普通攻击会击碎范围内的敌人子弹",
          mod = {}, flag = { clearBullet = 1 } },
    },
    gold = {
        { id = "g_ls", name = "吸血", desc = "造成伤害的 5% 回复生命", mod = { lifesteal = 0.05 } },
        { id = "g_dodge", name = "闪避", desc = "10% 概率躲避伤害", mod = { dodge = 0.10 } },
        { id = "g_as", name = "急速强化", desc = "攻速 +50%", mod = { asPct = 0.50 } },
        { id = "g_ms", name = "移速强化", desc = "移速 +45%", mod = { msPct = 0.45 } },
        { id = "g_cdr", name = "冷却缩减强化", desc = "技能冷却 -35%", mod = { cdrPct = 0.35 } },
        { id = "g_pen", name = "破甲", desc = "普通攻击伤害 +40%，普攻命中使目标受到的物理伤害 +8%（4 秒）。",
          mod = { basicPct = 0.40 }, flag = { penVuln = 0.08 } },
        { id = "g_regen", name = "持续回复", desc = "每秒回复 3 点生命", mod = { regen = 3 } },
        { id = "g_revive", name = "复活", desc = "死亡时以 30% 生命复活一次", mod = { revive = 1 } },
    },
}

-- ---------------------------------------------------------------- 角色专属 Buff
-- 只有对应职业能在奖励/商店/事件中抽到，每个账号每局每种最多 1 份。
-- mod：数值加成（合并进 p.mods）；flag：行为参数（合并进 p.flags）。
Config.ClassBuffs = {
    swordsman = {
        white = {
            { id = "sw_w_sharpen", name = "利刃打磨", desc = "三段斩每段伤害 +8%；第三段命中 35% 概率额外施加 1 层挫裂。",
              mod = {}, flag = { triplePct = 0.08, triple3CrackChance = 0.35 } },
            { id = "sw_w_dashcd", name = "疾行突袭", desc = "闪影突进冷却 -1.5 秒。",
              mod = {}, flag = { dashCd = -1.5 } },
            { id = "sw_w_stancedur", name = "固守延持", desc = "剑心护体持续时间 +0.6 秒。",
              mod = {}, flag = { stanceDur = 0.6 } },
            { id = "sw_w_heavy", name = "重击增幅", desc = "三段斩第三段伤害 +6%；第三段命中使目标挫裂持续 +0.7 秒。",
              mod = {}, flag = { triple3Pct = 0.06, tripleCrackExtend = 0.7 } },
            { id = "sw_w_vamp", name = "吸血精进", desc = "剑心护体期间额外获得 4% 吸血。",
              mod = {}, flag = { stanceLifesteal = 0.04 } },
            { id = "sw_w_step", name = "身法轻盈", desc = "闪影突进距离 +25%。",
              mod = {}, flag = { dashDist = 0.25 } },
            { id = "sw_w_crit", name = "暴击潜能", desc = "暴击率 +5%。",
              mod = { crit = 0.05 }, flag = {} },
            { id = "sw_w_hp", name = "体魄坚韧", desc = "生命上限 +12%。",
              mod = { hpPct = 0.12 }, flag = {} },
            { id = "sw_w_spin", name = "环刃轻舞", desc = "旋刃横斩伤害 +8%，冷却 -0.4 秒。",
              mod = {}, flag = { spinPct = 0.08, spinCd = -0.4 } },
            { id = "sw_w_guard", name = "坚守姿态", desc = "卸势格挡持续 +0.15 秒；格挡成功回复 5% 生命。",
              mod = {}, flag = { parryDur = 0.15, parryHeal = 0.05 } },
            { id = "sw_w_blink", name = "疾影步", desc = "瞬影连斩冲刺距离 +15%，每段伤害 +7%。",
              mod = {}, flag = { blinkDist = 0.15, blinkPct = 0.07 } },
        },
        blue = {
            { id = "sw_b_break", name = "断势重击", desc = "三段斩伤害 +13%；第三段改为 1.4 倍剑气波，可清除路径上的弹幕并施加 1 层挫裂。",
              mod = {}, flag = { triplePct = 0.13, tripleWind = 1 } },
            { id = "sw_b_quake", name = "小幅震荡", desc = "三段斩伤害 +12%；第三段击退敌人并施加 1 层失衡。",
              mod = {}, flag = { triplePct = 0.12, tripleKnock = 1 } },
            { id = "sw_b_pierce", name = "穿刺斩击", desc = "闪影突进每命中一名新敌人施加 1 层挫裂；对第 2 名及之后的敌人额外造成 0.3 倍伤害。",
              mod = {}, flag = { dashCrack = 1, dashPierce = 0.3 } },
            { id = "sw_b_dashheal", name = "回血突袭", desc = "闪影突进伤害 +14%，每次命中回复 6% 生命。",
              mod = {}, flag = { dashPct = 0.14, dashHeal = 0.06 } },
            { id = "sw_b_shock", name = "震波反击", desc = "剑心护体结束时释放冲击波，造成 1.2 倍伤害并施加 1 层挫裂。",
              mod = {}, flag = { stanceShock = 1.2 } },
            { id = "sw_b_calm", name = "稳固心神", desc = "受到伤害降低 8%（本版本无控制效果，改为减伤）。",
              mod = {}, flag = { hurtReduction = 0.08 } },
            { id = "sw_b_flow", name = "速斩衔接", desc = "普攻伤害 +15%；释放技能后下一次普攻额外获得 1 层剑意。",
              mod = { basicPct = 0.15 }, flag = { skillIntent = 1 } },
            { id = "sw_b_chase", name = "追击本能", desc = "移速 +8%；附近有残血敌人时再 +12% 移速。",
              mod = { msPct = 0.08 }, flag = { executeMs = 0.12 } },
            { id = "sw_b_lowhp", name = "残血续航", desc = "普攻伤害 +11%；生命低于 40% 时额外获得 10% 吸血。",
              mod = { basicPct = 0.11 }, flag = { lowLifesteal = 0.10 } },
            { id = "sw_b_refund", name = "收剑减耗", desc = "技能未命中时返还 25% 冷却。",
              mod = {}, flag = { missRefund = 0.25 } },
            { id = "sw_b_whirl", name = "裂风回旋", desc = "旋刃横斩范围 +22%、伤害 +13%，额外 15% 概率再施加 1 层挫裂。",
              mod = {}, flag = { spinRange = 0.22, spinPct = 0.13, spinCrackChance = 0.15 } },
            { id = "sw_b_guardheal", name = "卸劲回生", desc = "格挡成功后 3 秒内吸血 +12%，并减少旋刃横斩 1.5 秒冷却。",
              mod = {}, flag = { parryLifesteal = 0.12, parrySpinCd = 1.5 } },
            { id = "sw_b_double", name = "双冲贯体", desc = "瞬影连斩每段伤害 +14%，命中使目标挫裂持续 +0.5 秒。",
              mod = {}, flag = { blinkPct = 0.14, blinkCrackExtend = 0.5 } },
        },
        purple = {
            { id = "sw_p_reset", name = "瞬斩重置", desc = "三段斩伤害 +28%；三段全部命中返还冷却并获得 2 层剑意。",
              mod = {}, flag = { triplePct = 0.28, tripleReset = 1, tripleFullIntent = 2 } },
            { id = "sw_p_soft", name = "柔化起步", desc = "普攻伤害 +25%，普攻间隔 -20%。",
              mod = { basicPct = 0.25 }, flag = { basicNoRecovery = 0.20 } },
            { id = "sw_p_charges", name = "双重闪击", desc = "闪影突进获得 2 层充能，伤害 +27%，命中施加 1 层挫裂。",
              mod = {}, flag = { dashCharges = 1, dashPct = 0.27, dashCrack = 1 } },
            { id = "sw_p_invuln", name = "瞬身无敌", desc = "闪影突进伤害 +30%，无敌时间覆盖整个突进并额外 +0.15 秒。",
              mod = {}, flag = { dashPct = 0.30, dashInvuln = 0.15 } },
            { id = "sw_p_control", name = "全域免控", desc = "剑心护体期间受到伤害 -18%（本版本无控制效果，改为减伤）。",
              mod = {}, flag = { stanceDR = 0.18 } },
            { id = "sw_p_thorns", name = "坚守反伤", desc = "受击时对 70 范围内的敌人反弹 0.8 倍攻击伤害，35% 概率施加 1 层挫裂。",
              mod = {}, flag = { thorns = 0.8, thornsCrack = 0.35 } },
            { id = "sw_p_phantom", name = "残影留存", desc = "释放技能后留下剑影，0.35 秒后复刻一次 0.9 倍范围攻击（可叠剑意、施挫裂）。",
              mod = {}, flag = { phantomPct = 0.9 } },
            { id = "sw_p_bleed", name = "持续蚀伤", desc = "普攻伤害 +32%；挫裂不再随时间衰减；攻击附带每秒 0.3 倍攻击的流血，持续 3 秒。",
              mod = { basicPct = 0.32 }, flag = { crackNoDecay = 1, bleedDps = 0.3 } },
            { id = "sw_p_charge", name = "蓄力斩击", desc = "三段斩第一段伤害 +33%，命中直接施加 2 层挫裂。",
              mod = {}, flag = { triple1Pct = 0.33, triple1Crack = 2 } },
            { id = "sw_p_harvest", name = "收割增益", desc = "所有伤害 +26%；击杀时全部技能冷却 -1.5 秒，并立刻获得 5 层剑意。",
              mod = {}, flag = { allDmgPct = 0.26, killCdr = 1.5, killIntent = 5 } },
            { id = "sw_p_stagger", name = "借势破斩", desc = "普攻、旋刃横斩 30% 概率施加 1 层失衡；挫裂 + 失衡可触发粉碎连携。代价：失衡持续减半，粉碎伤害 -20%。",
              mod = {}, flag = { staggerChance = 0.3, comboMaster = 1, comboDmg = -0.2, staggerShort = 1 } },
            { id = "sw_p_illusion", name = "虚影回响", desc = "释放技能时 35% 概率召唤虚影，0.4 秒后以 0.35 倍伤害攻击并施加随机物理负面。",
              mod = {}, flag = { illusionChance = 0.35 } },
            { id = "sw_p_spin", name = "旋刃风暴", desc = "旋刃横斩范围 +22%、额外 20% 概率施加挫裂，连携伤害 +22%。",
              mod = {}, flag = { spinRange = 0.22, spinCrackChance = 0.2, comboDmg = 0.22 } },
            { id = "sw_p_parry2", name = "铁壁卸锋", desc = "卸势格挡持续 +0.3 秒；格挡成功立刻获得 2 层剑意，额外返还 0.6 秒技能冷却，之后 4 秒挫裂叠加上限 +1。",
              mod = {}, flag = { parryDur = 0.3, parryIntent = 2, parryCdr = 0.6, parryCrackCap = 1 } },
            { id = "sw_p_blinkcd", name = "瞬影卸锋", desc = "瞬影连斩冷却 -1 秒；格挡成功时为瞬影连斩补充 1 次免费充能；每段命中延长挫裂 0.5 秒。",
              mod = {}, flag = { blinkCd = -1, parryBlinkCharge = 1, blinkCrackExtend = 0.5 } },
        },
        gold = {
            { id = "sw_g_exec", name = "瞬杀剑意", desc = "闪影突进伤害 +52%；突进击杀立刻重置冷却并触发一次免费剑气爆发。",
              mod = {}, flag = { dashPct = 0.52, dashKillReset = 1, dashKillBurst = 1 } },
            { id = "sw_g_endless", name = "无尽剑舞", desc = "三段斩伤害 +48%，三段间隔大幅缩短；每一段命中额外获得 1 层剑意。",
              mod = {}, flag = { triplePct = 0.48, tripleFast = 0.55, tripleIntentAll = 1 } },
            { id = "sw_g_immovable", name = "不动明王", desc = "剑心护体持续 +0.6 秒，期间受到伤害 -30%，受击获得护盾；期间施加的挫裂上限 +1。",
              mod = {}, flag = { stanceDur = 0.6, stanceDR = 0.30, stanceShieldOnHit = 0.25, stanceCrackCap = 1 } },
            { id = "sw_g_soul", name = "噬魂侵蚀", desc = "所有伤害 +45%；物理攻击附带每秒 0.4 倍攻击的流血（3 秒），流血伤害会刷新挫裂持续时间。",
              mod = {}, flag = { allDmgPct = 0.45, bleedDps = 0.4, bleedRefresh = 1 } },
            { id = "sw_g_insight", name = "三态洞悉", desc = "普攻命中带挫裂的敌人：45% 施加失衡、25% 施加猎痕；挫裂+失衡触发粉碎，挫裂+猎痕触发震荡。代价：剑意上限 -2，失衡/猎痕最多 2 层。",
              mod = {}, flag = { comboMaster = 1, insight = 1, intentCapDelta = -2 } },
            { id = "sw_g_echo", name = "Debuff回响", desc = "触发物理连携后向周围敌人施加 1 层随机负面。代价：连携后 5 秒内技能冷却 +20%。",
              mod = {}, flag = { comboEcho = 1 } },
            { id = "sw_g_whirl2", name = "轮转灭阵", desc = "旋刃横斩获得 2 层充能；命中带挫裂的敌人有 15% 概率把挫裂扩散给周围；粉碎连携额外造成 0.6 倍范围伤害。代价：旋刃横斩冷却 +25%。",
              mod = {}, flag = { spinCharges = 1, spinSpread = 0.15, comboDmg = 0.22, comboBurst = 0.6, spinCdMul = 0.25 } },
            { id = "sw_g_guard3", name = "不动卸甲", desc = "格挡成功对 140 范围内敌人施加 1 层挫裂；之后 4 秒斩击技能伤害 +30%。代价：卸势格挡冷却 +2 秒。",
              mod = {}, flag = { parryCrackAoE = 1, parryDmgBuff = 0.30, parryCd = 2 } },
            { id = "sw_g_three", name = "千影碎击", desc = "瞬影连斩变为三段冲刺，每段都判定粉碎连携；击杀重置该技能冷却。代价：瞬影连斩冷却 +1 秒。",
              mod = {}, flag = { blinkStages = 1, blinkCombo = 1, blinkKillReset = 1, blinkCd = 1 } },
        },
        color = {
            { id = "sw_c_oni", name = "鬼剑术", desc = "剑意满时普攻变为远程拔刀剑气（3.4 倍伤害、贯穿并清弹幕）；技能伤害 +35%；剑气命中施加 1 层挫裂。",
              mod = { skillPct = 0.35 }, flag = { oni = 1 } },
            { id = "sw_c_berserk", name = "狂剑士", desc = "技能伤害 +60%；造成伤害的 8% 回复生命；释放技能消耗当前生命 10%（不会低于 25% 最大生命）；每损失 10% 生命获得 +5% 攻击 / 攻速 / 减伤（最多 50%）。",
              mod = { skillPct = 0.6, lifesteal = 0.08 }, flag = { berserk = 1 } },
            { id = "sw_c_symbiosis", name = "武链共生", desc = "攻击 40% 概率额外施加另外两种物理负面；可触发全部三套连携。代价：原生剑意与技能不再施加挫裂，负面叠层上限减半。",
              mod = {}, flag = { chainSymbiosis = 1, debuffChance = 0.4, comboMaster = 1 } },
            { id = "sw_c_compensate", name = "代偿流转", desc = "击杀时抽取目标全部负面并储存；接下来 5 次攻击将其施加给新敌人。代价：储存负面触发的连携伤害 -35%。",
              mod = {}, flag = { compensate = 1 } },
            { id = "sw_c_misalign", name = "错位反应", desc = "解锁错位连携：挫裂+猎痕→粉碎、挫裂+失衡→追猎、失衡+猎痕→震荡。代价：错位连携强度只有 60%。",
              mod = {}, flag = { misalign = 1, comboMaster = 1 } },
            { id = "sw_c_dance", name = "剑舞流转", desc = "旋刃横斩、瞬影连斩命中缩短格挡冷却；格挡成功刷新这两个技能；两者命中直接将挫裂叠满。代价：这两个技能冷却 +25%。",
              mod = {}, flag = { danceFlow = 1, spinCdMul = 0.25, blinkCdMul = 0.25 } },
        },
    },
    spearman = {
        white = {
            { id = "sp_w_blade", name = "枪刃加固", desc = "普攻伤害 +8%。",
              mod = { basicPct = 0.08 }, flag = {} },
            { id = "sp_w_dashcd", name = "轻装突进", desc = "突刺奔袭冷却 -0.5 秒。",
              mod = {}, flag = { dashCd = -0.5 } },
            { id = "sp_w_guarddur", name = "固阵", desc = "铁枪固守持续时间 +0.2 秒。",
              mod = {}, flag = { guardDur = 0.2 } },
            { id = "sp_w_stance", name = "稳扎根基", desc = "普攻伤害 +5%，普攻额外 15% 概率施加 1 层失衡。",
              mod = { basicPct = 0.05 }, flag = { basicStaggerChance = 0.15 } },
            { id = "sp_w_lift", name = "轻巧挑刺", desc = "第三段普攻击退距离 +12。",
              mod = {}, flag = { comboKnock = 12 } },
            { id = "sp_w_damp", name = "减震护体", desc = "铁枪固守期间近战减伤 +4%。",
              mod = {}, flag = { guardDR = 0.04 } },
            { id = "sp_w_throww", name = "远投配重", desc = "掷枪伤害 +8%，飞行距离 +12%。",
              mod = {}, flag = { throwPct = 0.08, throwRange = 0.12 } },
            { id = "sp_w_back", name = "退击轻装", desc = "回马枪后撤距离 +12%，伤害 +7%。",
              mod = {}, flag = { backDist = 0.12, backPct = 0.07 } },
            { id = "sp_w_shock", name = "震地增幅", desc = "枪阵震地范围 +10%，伤害 +8%。",
              mod = {}, flag = { shockRange = 0.10, shockPct = 0.08 } },
        },
        blue = {
            { id = "sp_b_chain", name = "连环挑击", desc = "第三段普攻伤害 +12%，命中使技能 1 冷却 -1 秒，并额外施加 1 层失衡。",
              mod = {}, flag = { combo3Pct = 0.12, combo3Cdr = 1, combo3Stagger = 1 } },
            { id = "sp_b_dashheal", name = "破阵回血", desc = "突刺奔袭伤害 +13%，命中回复 5% 生命。",
              mod = {}, flag = { dashPct = 0.13, dashHeal = 0.05 } },
            { id = "sp_b_shock", name = "震地强化", desc = "枪阵震地伤害 +15%、范围 +10%、击退 +50%，命中施加 1 层失衡。",
              mod = {}, flag = { shockPct = 0.15, shockRange = 0.10, shockKnock = 0.5, shockStagger = 1 } },
            { id = "sp_b_reflect", name = "弹击反击", desc = "铁枪固守成功弹开子弹时获得 5% 护盾，下一次普攻直接获得 1 层枪势。",
              mod = {}, flag = { guardReflect = 1.2, guardShieldOnBlock = 0.05, guardNextMomentum = 1 } },
            { id = "sp_b_flow", name = "速攻衔接", desc = "普攻伤害 +14%；释放技能后 3 秒内攻速 +10%。",
              mod = { basicPct = 0.14 }, flag = { castAs = 0.10 } },
            { id = "sp_b_pierce", name = "穿刺冲击", desc = "突刺奔袭对第 2 名及之后的敌人额外 0.4 倍伤害，命中积累 1 层失衡。",
              mod = {}, flag = { dashPierce = 0.4, dashStagger = 1 } },
            { id = "sp_b_throw", name = "锐矛穿刺", desc = "掷枪伤害 +13%，贯穿 +1；命中 35% 概率额外施加 1 层失衡。",
              mod = {}, flag = { throwPct = 0.13, throwPierce = 1, throwStaggerChance = 0.35 } },
            { id = "sp_b_back", name = "进退连环", desc = "回马枪伤害 +12%，释放后 2 秒移速 +15%；命中 35% 概率返还 1 层枪势。",
              mod = {}, flag = { backPct = 0.12, backMs = 0.15, backMomentum = 0.35 } },
            { id = "sp_b_guard", name = "环震扩域", desc = "枪阵震地范围 +20%、击退 +40%、伤害 +14%。",
              mod = {}, flag = { shockRange = 0.20, shockKnock = 0.4, shockPct = 0.14 } },
        },
        purple = {
            { id = "sp_p_sweep", name = "横扫千军", desc = "第二段普攻范围 +25%、伤害 +28%，并给范围内敌人施加 1 层失衡。",
              mod = {}, flag = { sweepRange = 0.25, sweepPct = 0.28, sweepStagger = 1 } },
            { id = "sp_p_dash2", name = "双重突刺", desc = "突刺奔袭获得 2 层充能，伤害 +26%，命中积累 1 层失衡。",
              mod = {}, flag = { dashCharges = 1, dashPct = 0.26, dashStagger = 1 } },
            { id = "sp_p_guard", name = "不动如山", desc = "铁枪固守减伤 +10%，震地伤害 +30%，失衡持续时间 +1 秒。",
              mod = {}, flag = { guardDR = 0.10, shockPct = 0.30, staggerDur = 1 } },
            { id = "sp_p_combo", name = "三连循环", desc = "普攻伤害 +32%；打满三段返还技能 1 冷却并额外获得 1 层枪势。",
              mod = { basicPct = 0.32 }, flag = { comboFullRefund = 1, comboFullMomentum = 1 } },
            { id = "sp_p_break", name = "双重破军", desc = "突刺奔袭获得 2 层充能；对第 2 名及之后的敌人额外 0.33 倍伤害，命中积累失衡。",
              mod = {}, flag = { dashCharges = 1, dashPierce = 0.33, dashStagger = 1 } },
            { id = "sp_p_air", name = "破空突袭", desc = "突刺奔袭期间无敌，伤害 +25%。",
              mod = {}, flag = { dashInvuln = 1, dashPct = 0.25 } },
            { id = "sp_p_resonance", name = "印记共振", desc = "攻击带失衡目标 30% 概率施加 1 层猎痕；消耗枪势的技能命中带挫裂+猎痕目标触发震荡。代价：猎痕持续减半，震荡扩散层数减半。",
              mod = {}, flag = { huntOnStagger = 0.3, momentumCombo = 1, huntDurMul = 0.5, spreadMul = 0.5 } },
            { id = "sp_p_illusion", name = "虚影回响", desc = "释放技能时 35% 概率召唤虚影，复刻该技能 35% 伤害并施加随机物理负面。",
              mod = {}, flag = { illusionChance = 0.35 } },
            { id = "sp_p_throwpierce", name = "飞枪破阵", desc = "掷枪贯穿 +1，命中额外施加 1 层失衡；由枪势触发的震荡扩散 +0.7 格。",
              mod = {}, flag = { throwPierce = 1, throwStagger = 1, spreadAdd = 0.7 } },
            { id = "sp_p_backshock", name = "回马震阵", desc = "回马枪后撤 +20%，枪阵震地范围 +20%；震地 20% 概率施加 1 层猎痕。",
              mod = {}, flag = { backDist = 0.2, shockRange = 0.2, shockHunt = 0.2 } },
            { id = "sp_p_shockrefund", name = "震荡蓄势", desc = "枪阵震地命中 2 名以上敌人时 50% 概率返还 1 层枪势；震荡扩散 +0.5 格。",
              mod = {}, flag = { shockRefund = 0.5, spreadAdd = 0.5 } },
        },
        gold = {
            { id = "sp_g_blood", name = "嗜血裁决", desc = "1A 伤害 +40% 且吸血 8%；2A 伤害 +45% 并附加 8% 真实伤害；3A 必定暴击、伤害 +50%，暴击命中直接叠满失衡。",
              mod = {}, flag = { a1Pct = 0.4, a1Lifesteal = 0.08, a2Pct = 0.45,
                  a2True = 0.08, a3Pct = 0.5, a3Crit = 1, a3CritMaxStagger = 1 } },
            { id = "sp_g_chase", name = "破军追猎", desc = "突刺距离 +20%，之后 3 秒普攻 +55%；对 35% 生命以下敌人额外 +40% 伤害；击杀永久 +3% 攻击；3A 命中带挫裂目标触发震荡。",
              mod = {}, flag = { dashDist = 0.2, next3aPct = 0.55, executePct = 0.4,
                  killAtkPct = 0.03, a3Combo = 1 } },
            { id = "sp_g_bastion", name = "固阵壁垒", desc = "铁枪固守 +0.7 秒、减伤 +15%；成功弹开子弹时反击 2.5 倍并施加失衡；生命上限 +20%。",
              mod = { hpPct = 0.2 }, flag = { guardDur = 0.7, guardDR = 0.15,
                  guardReflect = 2.5, reflectStagger = 1 } },
            { id = "sp_g_wind", name = "枪风无尽", desc = "第二段普攻留下枪风领域（每 0.5 秒 0.4 倍伤害）；普攻范围 +15%、伤害 +48%，领域内敌人持续积累失衡。",
              mod = { basicPct = 0.48, rangePct = 0.15 }, flag = { a2Wind = 1, windStagger = 1 } },
            { id = "sp_g_allmomentum", name = "万象枪势", desc = "消耗枪势的技能 45% 挂挫裂、25% 挂猎痕；失衡+挫裂触发震荡，失衡+猎痕触发追猎。代价：枪势获取 -30%，异种负面上限 2 层。",
              mod = {}, flag = { momentumCrack = 0.45, momentumHunt = 0.25, comboAll = 1,
                  comboMaster = 1, momentumGainMul = 0.7, debuffCap2 = 1 } },
            { id = "sp_g_echo", name = "Debuff回响", desc = "触发物理连携后向周围敌人施加 1 层随机负面。代价：连携后 5 秒内技能冷却 +20%。",
              mod = {}, flag = { comboEcho = 1 } },
            { id = "sp_g_return", name = "飞枪轮回", desc = "掷枪会折返，往返两段伤害；每段施加失衡；震荡连携伤害 +40%。代价：掷枪冷却 +2 秒。",
              mod = {}, flag = { throwReturn = 1, throwStagger = 1, comboDmg = 0.4, throwCd = 2 } },
            { id = "sp_g_backcharge", name = "奔突回锋", desc = "回马枪获得 2 层充能；命中 35% 概率给周围敌人挂失衡；消耗枪势释放回马枪不消耗层数。代价：回马枪冷却 +1 秒。",
              mod = {}, flag = { backCharges = 1, backStaggerChance = 0.35,
                  momentumKeepBack = 1, backCd = 1 } },
            { id = "sp_g_quake", name = "万枪撼地", desc = "枪阵震地连续释放两段冲击波；每次命中叠高失衡；震荡时大范围扩散挫裂。代价：冷却 +2.5 秒。",
              mod = {}, flag = { shockWaves = 1, shockStaggerStack = 1,
                  shockSpreadCrack = 1, shockCd = 2.5 } },
        },
        color = {
            { id = "sp_c_shadow", name = "逐影千旋", desc = "残影复刻技能 55% 伤害，复刻命中也能积攒枪势、施加失衡；所有伤害 +30%。",
              mod = {}, flag = { phantomPct = 0.55, allDmgPct = 0.3,
                  phantomMomentum = 1, phantomStagger = 1 } },
            { id = "sp_c_charge", name = "猛攻蓄力", desc = "每次 3A 命中叠加 1 层重击（每层 3A 伤害 +7%，最多 10 层）；铁枪固守结束追加 3.2 倍重劈；重击自带 12% 减伤并大范围施加失衡。",
              mod = {}, flag = { chargePct = 0.07, guardSlam = 3.2, heavyDR = 0.12,
                  heavyStagger = 1, guardSlamCombo = 1 } },
            { id = "sp_c_symbiosis", name = "武链共生", desc = "攻击 40% 概率额外施加另外两种物理负面；可触发全部三套连携。代价：原生枪势不再施加失衡，负面叠层上限减半。",
              mod = {}, flag = { chainSymbiosis = 1, debuffChance = 0.4, comboMaster = 1 } },
            { id = "sp_c_compensate", name = "代偿流转", desc = "击杀时抽取目标全部负面并储存；接下来 5 次攻击将其施加给新敌人。代价：储存负面触发的连携伤害 -35%。",
              mod = {}, flag = { compensate = 1 } },
            { id = "sp_c_misalign", name = "错位反应", desc = "解锁错位连携：挫裂+猎痕→粉碎、挫裂+失衡→追猎、失衡+猎痕→震荡。代价：错位连携强度只有 60%。",
              mod = {}, flag = { misalign = 1, comboMaster = 1 } },
            { id = "sp_c_cycle", name = "枪势轮回", desc = "掷枪、回马枪、枪阵震地命中也能获得枪势；这三个技能不消耗枪势；震荡时 20% 概率挂猎痕。代价：三个技能冷却 +30%，枪势自然获取 -40%。",
              mod = {}, flag = { momentumOnSkill = 1, momentumFreeNew = 1,
                  comboHuntChance = 0.2, skillCdMul = 0.3, momentumGainMul = 0.6 } },
        },
    },
    ranger = {
        white = {
            { id = "ra_w_bow", name = "弓身加固", desc = "普攻伤害 +9%。",
              mod = { basicPct = 0.09 }, flag = {} },
            { id = "ra_w_step", name = "迅捷步法", desc = "移速 +12%。",
              mod = { msPct = 0.12 }, flag = {} },
            { id = "ra_w_range", name = "远射专精", desc = "普攻射程 +15%。",
              mod = { rangePct = 0.15 }, flag = {} },
            { id = "ra_w_vital", name = "精准要害", desc = "暴击伤害 +5%。",
              mod = { critDmg = 0.05 }, flag = {} },
            { id = "ra_w_back", name = "轻盈后撤", desc = "疾退腾挪冷却 -1 秒。",
              mod = {}, flag = { r2Cd = -1.0 } },
            { id = "ra_w_trap", name = "陷阱延展", desc = "陷阱持续 +0.4 秒，范围 +10%。",
              mod = {}, flag = { trapDur = 0.4, trapRadius = 0.10 } },
            { id = "ra_w_volley", name = "速射调校", desc = "箭影连射每支箭伤害 +8%。",
              mod = {}, flag = { volleyPct = 0.08 } },
            { id = "ra_w_swap", name = "掠影轻步", desc = "掠袭换位冷却 -0.6 秒，瞬移后移速 +10%。",
              mod = {}, flag = { swapCd = -0.6, swapMs = 0.10 } },
        },
        blue = {
            { id = "ra_b_pierce", name = "破甲箭矢", desc = "猎痕衰减变慢；强化普攻伤害 +14%。",
              mod = { basicPct = 0.14 }, flag = { huntDurMul = 0.5 } },
            { id = "ra_b_splash", name = "散射微调", desc = "普攻附带 1 个目标的溅射，溅射伤害 0.7 倍并叠加猎痕。",
              mod = {}, flag = { basicSplash = 1, basicSplashPct = 0.7 } },
            { id = "ra_b_dodge", name = "应急闪避", desc = "疾退腾挪无敌时间 +0.3 秒。",
              mod = {}, flag = { dodgeInvuln = 0.3 } },
            { id = "ra_b_rapid", name = "持续加速", desc = "精准速射持续时间 +1.5 秒。",
              mod = {}, flag = { rapidDur = 1.5 } },
            { id = "ra_b_snipe", name = "冲击爆裂", desc = "穿魂狙击命中后产生 1.3 倍范围爆炸并叠加猎痕。",
              mod = {}, flag = { snipeBoom = 1.3 } },
            { id = "ra_b_mark", name = "续能标记", desc = "普攻命中带猎痕目标时减少技能冷却 0.4 秒，对其普攻伤害额外 +12%。",
              mod = {}, flag = { huntCdr = 0.4, huntBasicPct = 0.12 } },
            { id = "ra_b_leech", name = "汲取箭矢", desc = "普攻伤害 +13%，命中回复 3% 生命。",
              mod = { basicPct = 0.13 }, flag = { basicLifesteal = 0.03 } },
            { id = "ra_b_mist", name = "迷雾隐匿", desc = "受到伤害降低 8%。",
              mod = {}, flag = { hurtReduction = 0.08 } },
            { id = "ra_b_rapid2", name = "急速续射", desc = "普攻伤害 +16%，精准速射每层攻速额外 +4%。",
              mod = { basicPct = 0.16 }, flag = { rapidPct = 0.04 } },
            { id = "ra_b_slow", name = "减速箭矢", desc = "普攻使目标减速 20%，普攻伤害 +11%。",
              mod = { basicPct = 0.11 }, flag = { basicSlow = 0.2 } },
            { id = "ra_b_trap", name = "迟滞罗网", desc = "陷阱减速 +20%、冷却 -0.5 秒，狩猎契机持续 +1 秒。",
              mod = {}, flag = { trapSlow = 0.2, trapCd = -0.5, trapCritDur = 1 } },
            { id = "ra_b_volley", name = "齐射增益", desc = "箭影连射 +1 支箭，伤害 +13%。",
              mod = {}, flag = { volleyArrows = 1, volleyPct = 0.13 } },
            { id = "ra_b_swap", name = "瞬跃增益", desc = "掠袭换位后该次普攻伤害额外 +8%，瞬移后移速 +10%，该次普攻 +12%。",
              mod = {}, flag = { swapAs = 0.08, swapMs = 0.10, swapBasicPct = 0.12 } },
        },
        purple = {
            { id = "ra_p_stacks", name = "多层烙印", desc = "普攻一次叠加 2 层猎痕。",
              mod = {}, flag = { huntPerHit = 1 } },
            { id = "ra_p_frost", name = "凝固寒箭", desc = "普攻使目标减速 30%，普攻伤害 +25%。",
              mod = { basicPct = 0.25 }, flag = { basicSlow = 0.3 } },
            { id = "ra_p_dodge2", name = "二段疾退", desc = "疾退腾挪额外获得 1 层狩猎冲动，冷却 -0.5 秒。",
              mod = {}, flag = { dodgeStacks = 1, r2Cd = -0.5 } },
            { id = "ra_p_air", name = "空中蓄力", desc = "穿魂狙击伤害 +30%。",
              mod = {}, flag = { snipePct = 0.3 } },
            { id = "ra_p_pierce", name = "贯穿之箭", desc = "普攻贯穿 2 名敌人，伤害 +32%；每贯穿一名敌人附加 1 层猎痕。",
              mod = { basicPct = 0.32 }, flag = { basicPierce = 2, huntOnPierce = 1 } },
            { id = "ra_p_instant", name = "瞬发狙击", desc = "穿魂狙击取消蓄力，但伤害 -30%。",
              mod = {}, flag = { snipeCharge = -1.0, snipePct = -0.3 } },
            { id = "ra_p_counter", name = "反击箭阵", desc = "受击反弹 1.6 倍伤害箭矢，并施加猎痕。",
              mod = {}, flag = { thorns = 1.6, thornsHunt = 0.4 } },
            { id = "ra_p_markdmg", name = "标记增伤", desc = "对带猎痕目标的普攻伤害额外提升（每层 +8%）。",
              mod = {}, flag = { huntBasicPct = 0.08 } },
            { id = "ra_p_store", name = "蓄力储能", desc = "穿魂狙击伤害 +28%。",
              mod = {}, flag = { snipePct = 0.28 } },
            { id = "ra_p_swapdmg", name = "位移增伤", desc = "掠袭换位后第一次普攻 +35%，并直接叠 2 层猎痕。",
              mod = {}, flag = { swapBasicPct = 0.35, swapHunt = 2 } },
            { id = "ra_p_stagger", name = "残响硬直", desc = "命中带猎痕目标 30% 概率施加 1 层失衡。",
              mod = {}, flag = { staggerOnHunt = 0.3, comboMaster = 1 } },
            { id = "ra_p_illusion", name = "虚影回响", desc = "释放技能时 35% 概率召唤虚影，复刻该技能 35% 伤害。",
              mod = {}, flag = { illusionChance = 0.35 } },
            { id = "ra_p_trap2", name = "诱捕烙印", desc = "陷阱触发时一次叠 2 层猎痕，狩猎契机持续 +2 秒。",
              mod = {}, flag = { trapHuntStacks = 2, trapCritDur = 2 } },
            { id = "ra_p_volley2", name = "掠影疾射", desc = "箭影连射 +2 支箭，掠袭换位冷却 -2 秒。",
              mod = {}, flag = { volleyArrows = 2, swapCd = -2 } },
            { id = "ra_p_swap2", name = "瞬猎奔袭", desc = "掠袭换位对周围施加猎痕，换位后第一次攻击 +20% 伤害。",
              mod = {}, flag = { swapAoeHunt = 1, swapBasicPct = 0.2 } },
        },
        gold = {
            { id = "ra_g_frost", name = "冰封刻印", desc = "普攻减速 35%，暴击时减速翻倍；普攻伤害 +42%，暴击额外叠 1 层猎痕。",
              mod = { basicPct = 0.42 }, flag = { basicSlow = 0.35, critSlow = 1, critHunt = 1 } },
            { id = "ra_g_leap", name = "跃动契约", desc = "普攻伤害 +50%；掠袭换位后第一次普攻额外叠 3 层猎痕。",
              mod = { basicPct = 0.5 }, flag = { swapHunt = 3 } },
            { id = "ra_g_hunt", name = "交织狩猎", desc = "普攻命中带猎痕目标：45% 施加失衡、25% 施加挫裂；可触发追猎 / 震荡。代价：狩猎冲动上限 -1，异种负面上限 2 层。",
              mod = {}, flag = { huntTargetStagger = 0.45, huntTargetCrack = 0.25,
                  comboMaster = 1, dodgeCap = -1, debuffCap2 = 1 } },
            { id = "ra_g_echo", name = "Debuff回响", desc = "触发物理连携后向周围敌人施加 1 层随机负面。代价：连携后 5 秒内技能冷却 +20%。",
              mod = {}, flag = { comboEcho = 1 } },
            { id = "ra_g_trap", name = "多重罗网", desc = "陷阱可存 2 个，触发保留 2 层狩猎契机，并给周围敌人挂猎痕。代价：陷阱冷却 +3 秒。",
              mod = {}, flag = { trapCount = 1, trapCritStacks = 1, trapHuntAoe = 1, trapCd = 3 } },
            { id = "ra_g_rain", name = "箭雨倾泻", desc = "箭影连射 +4 支箭，每支 40% 概率触发追猎，伤害 +35%。",
              mod = {}, flag = { volleyArrows = 4, volleyComboChance = 0.4, volleyPct = 0.35 } },
            { id = "ra_g_shuttle", name = "猎影穿梭", desc = "掠袭换位 +1 层充能，换位后首次攻击必定暴击；触发追猎时返还 1 层充能。代价：冷却 +2.5 秒。",
              mod = {}, flag = { swapCharge = 1, swapCrit = 1, swapComboReset = 1, swapCd = 2.5 } },
        },
        color = {
            { id = "ra_c_fate", name = "命运箭矢", desc = "普攻随机附带溅射 / 吸血 / 范围伤害之一；总伤害 +35%，所有效果都能叠加猎痕。",
              mod = {}, flag = { fateArrow = 1, basicPct = 0.35, allDmgPct = 0.1 } },
            { id = "ra_c_twin", name = "双生妖影", desc = "普攻与技能总伤害 +45%；普攻额外叠 1 层猎痕，掠袭换位后首次攻击触发追猎。",
              mod = {}, flag = { twinForm = 1, allDmgPct = 0.45, huntPerHit = 1, swapCombo = 1 } },
            { id = "ra_c_sky", name = "飞空猎袭", desc = "穿魂狙击 +40% 伤害，箭影连射 +2 支；命中失衡目标时追猎增益拉满。",
              mod = {}, flag = { snipePct = 0.4, volleyArrows = 2, huntExecute = 1 } },
            { id = "ra_c_symbiosis", name = "武链共生", desc = "攻击 40% 概率额外施加另外两种物理负面；可触发全部三套连携。代价：原生猎痕不再生成，负面叠层上限减半。",
              mod = {}, flag = { chainSymbiosis = 1, debuffChance = 0.4, comboMaster = 1 } },
            { id = "ra_c_compensate", name = "代偿流转", desc = "击杀时抽取目标全部负面并储存；接下来 5 次攻击将其施加给新敌人。代价：储存负面触发的连携伤害 -35%。",
              mod = {}, flag = { compensate = 1 } },
            { id = "ra_c_misalign", name = "错位反应", desc = "解锁错位连携：挫裂+猎痕→粉碎、挫裂+失衡→追猎、失衡+猎痕→震荡。代价：错位连携强度只有 60%。",
              mod = {}, flag = { misalign = 1, comboMaster = 1 } },
            { id = "ra_c_cycle", name = "狩命轮转", desc = "陷阱触发刷新箭影连射、掠袭换位；箭影连射/掠袭命中减少陷阱冷却；三者命中都可触发追猎。",
              mod = {}, flag = { huntCycle = 1, comboHuntChance = 0.2, trapCd = -2 } },
        },
    },
    mage = {
        white = {
            { id = "ma_w_fire", name = "火焰亲和", desc = "火系伤害 +8%。",
              mod = {}, flag = { firePct = 0.08 } },
            { id = "ma_w_ice", name = "冰霜亲和", desc = "冰系伤害 +8%。",
              mod = {}, flag = { icePct = 0.08 } },
            { id = "ma_w_bolt", name = "雷电亲和", desc = "电系伤害 +8%。",
              mod = {}, flag = { boltPct = 0.08 } },
            { id = "ma_w_siphon", name = "能量虹吸", desc = "击杀时全部技能冷却 -0.3 秒。",
              mod = {}, flag = { killCdr = 0.3 } },
            { id = "ma_w_spread", name = "灼烧蔓延", desc = "燃烧扩散范围 +0.5 格。",
              mod = {}, flag = { burnSpread = 0.5 } },
            { id = "ma_w_frostarc", name = "冰冻蔓延", desc = "冰冻波扇形 +10°。",
              mod = {}, flag = { freezeArc = math.rad(10) } },
            { id = "ma_w_chain", name = "闪电延伸", desc = "闪电链 / 雷击范围 +0.5 格。",
              mod = {}, flag = { boltRange = 0.5 } },
            { id = "ma_w_fireball", name = "火球增效", desc = "火球术伤害 +10%。",
              mod = {}, flag = { m1Pct = 0.10 } },
            { id = "ma_w_icewave", name = "冰冻增效", desc = "冰冻波伤害 +10%。",
              mod = {}, flag = { m2Pct = 0.10 } },
            { id = "ma_w_boltstrike", name = "雷击增效", desc = "雷击术伤害 +10%。",
              mod = {}, flag = { m3Pct = 0.10 } },
            { id = "ma_w_blizzard", name = "暴风雪强化", desc = "暴风雪持续时间 +1 秒。",
              mod = {}, flag = { blizzardDur = 1 } },
            { id = "ma_w_static", name = "静电增幅", desc = "静电力场伤害 +15%。",
              mod = {}, flag = { m7Pct = 0.15 } },
        },
        blue = {
            { id = "ma_b_flame", name = "烈焰延伸", desc = "烈焰冲击的燃烧持续 +3 秒。",
              mod = {}, flag = { m6Burn = 3 } },
            { id = "ma_b_pierceice", name = "寒冰刺骨", desc = "冰冻波扇形 +25°，冰冻时间 +0.5 秒。",
              mod = {}, flag = { freezeArc = math.rad(25), freezeDur = 0.5 } },
            { id = "ma_b_chain", name = "连锁反应", desc = "闪电链连锁目标 +2。",
              mod = {}, flag = { boltChain = 2 } },
            { id = "ma_b_ember", name = "余烬蔓延", desc = "余烬地面范围 +0.35 格。",
              mod = {}, flag = { emberRadius = 0.35 } },
            { id = "ma_b_iceshield", name = "冰晶护盾", desc = "冰冻波冷却 -2 秒。",
              mod = {}, flag = { m2Cd = -2 } },
            { id = "ma_b_recover", name = "电能回收", desc = "电系技能命中时全部技能冷却 -0.3 秒。",
              mod = {}, flag = { boltSkillCdr = 0.3 } },
            { id = "ma_b_meteor", name = "流星增效", desc = "流星陨落伤害 +20%。",
              mod = {}, flag = { m8Pct = 0.20 } },
            { id = "ma_b_icespike", name = "冰锥强效", desc = "冰锥术减速 +15%，伤害 +15%。",
              mod = {}, flag = { slowBonus = 0.15, m4Pct = 0.15 } },
            { id = "ma_b_static", name = "静电领域", desc = "静电力场范围 +0.35 格。",
              mod = {}, flag = { staticRadius = 0.35 } },
            { id = "ma_b_emberslow", name = "余烬焚毁", desc = "余烬地面上的敌人移速 -15%。",
              mod = {}, flag = { emberSlow = 0.15 } },
            { id = "ma_b_frostfield", name = "寒霜领域", desc = "暴风雪范围内冰系伤害 +10%。",
              mod = {}, flag = { blizzardIce = 0.10 } },
            { id = "ma_b_charge", name = "过载充能", desc = "闪电链每连锁一个目标回复 0.3 秒技能冷却。",
              mod = {}, flag = { boltKillCdr = 0.3 } },
        },
        purple = {
            { id = "ma_p_lava", name = "熔岩之心", desc = "火系技能命中时额外生成一片余烬地面，持续 2 秒并造成持续灼烧；最多同时存在 6 片，可叠加。",
              mod = {}, flag = { emberOnFire = 1 } },
            { id = "ma_p_frozen", name = "永冻领域", desc = "暴风雪减速提升至 50%，范围内冰系伤害 +20%。",
              mod = {}, flag = { blizzardSlow = 0.5, blizzardIce = 0.2 } },
            { id = "ma_p_thunder", name = "雷暴导体", desc = "静电力场范围内电系伤害 +30%。",
              mod = {}, flag = { staticBolt = 0.3 } },
            { id = "ma_p_resonance", name = "元素协调", desc = "火/冰/电各带一个时，元素连携伤害额外 +35%。",
              mod = {}, flag = { elemComboPct = 0.35 } },
            { id = "ma_p_dragon", name = "龙息术", desc = "火球术变为扇形火焰喷射：射程 5 格、宽 120°、穿透。",
              mod = {}, flag = { dragonBreath = 1 } },
            { id = "ma_p_nova", name = "冰霜新星", desc = "冰冻波变为以自身为中心的圆形扩散（半径 4 格），冰冻 +0.5 秒。",
              mod = {}, flag = { iceNova = 1, freezeDur = 0.5 } },
            { id = "ma_p_storm", name = "闪电风暴", desc = "闪电链变为对半径 4 格内所有敌人造成 1.0 倍伤害。",
              mod = {}, flag = { lightningStorm = 1 } },
            { id = "ma_p_emberstorm", name = "余烬风暴", desc = "烈焰冲击对燃烧敌人的增伤 +50%（额外）。",
              mod = {}, flag = { burnBonus = 0.5 } },
            { id = "ma_p_zero", name = "绝对零度", desc = "冰冻波对已冰冻敌人额外造成 1.0 倍攻击伤害。",
              mod = {}, flag = { absoluteZero = 1 } },
            { id = "ma_p_thundergod", name = "雷神之怒", desc = "雷击术暴击倍率提升至 2.5。",
              mod = {}, flag = { thunderCrit = 2.5 } },
        },
        gold = {
            { id = "ma_g_phoenix", name = "凤凰余烬", desc = "火系击杀时自动释放一次火球术（不耗冷却），并留下余烬。",
              mod = {}, flag = { phoenix = 1 } },
            { id = "ma_g_winter", name = "永恒寒冬", desc = "暴风雪范围内敌人减速 50%，每秒受 0.15 倍攻击伤害。",
              mod = {}, flag = { eternalWinter = 1 } },
            { id = "ma_g_thunder", name = "雷霆万钧", desc = "闪电链对生命低于 50% 的敌人伤害翻倍。",
              mod = {}, flag = { thunderExecute = 1 } },
            { id = "ma_g_ultimate", name = "元素共鸣·极", desc = "每释放一个技能，全元素伤害 +5%（最多 5 层，持续 8 秒）。",
              mod = {}, flag = { elemResonance = 1 } },
            { id = "ma_g_burnshield", name = "灼烧转化", desc = "火系伤害的 20% 转化为护盾（不超过上限 50%）。",
              mod = {}, flag = { burnShield = 0.2 } },
            { id = "ma_g_icearmor", name = "冰甲术", desc = "护盾存在时冰系伤害 +25%。",
              mod = {}, flag = { iceArmor = 0.25 } },
            { id = "ma_g_overload", name = "电能暴走", desc = "连续释放 3 个电系技能后，下一个电系技能冷却立即重置。",
              mod = {}, flag = { overloadCharge = 1 } },
            { id = "ma_g_elemoverload", name = "元素过载", desc = "释放任意技能时 20% 概率冷却归零且伤害 +40%。",
              mod = {}, flag = { elemOverload = 1 } },
        },
        color = {
            { id = "ma_c_bake", name = "炙烤大师", desc = "火系伤害 -50%，但火焰命中会叠加灼烧层数（最多 5 层），每层提升燃烧伤害。",
              mod = {}, flag = { bakeMaster = 1 } },
            { id = "ma_c_melt", name = "冰火两重天", desc = "融化伤害翻倍；冰打燃烧、火打冰冻额外 +20%。",
              mod = {}, flag = { meltDouble = 1 } },
            { id = "ma_c_time", name = "时空法师", desc = "每释放一个技能，其他技能冷却 -0.25 秒；移速 -10%。",
              mod = { msPct = -0.10 }, flag = { timeMage = 1 } },
            { id = "ma_c_chaos", name = "混沌法术", desc = "20% 概率本次技能伤害 +30% 并额外触发一次元素效果。",
              mod = {}, flag = { chaos = 1 } },
            { id = "ma_c_quiz", name = "答题大师", desc = "释放技能后获得同系考题层数，下次同系技能伤害 +20%（最多 5 层）。",
              mod = {}, flag = { quiz = 1 } },
            { id = "ma_c_echo", name = "奥术回响", desc = "释放技能后留下回响，再次释放同系技能时回响复制 40% 伤害。",
              mod = {}, flag = { arcaneEcho = 1 } },
        },
    },
}

-- 当前使用的职业（后续接入多职业时改这里 / 改成存档字段）
Config.PlayerClass = "swordsman"

-- 专属强化依赖携带的技能：没带对应技能就不会出现在奖励/商店里
-- 结构按职业分组，后续角色只需追加自己的映射
Config.ClassBuffSkills = {
    swordsman = {
        sw_w_sharpen = { 1 }, sw_w_heavy = { 1 }, sw_b_break = { 1 }, sw_b_quake = { 1 },
        sw_p_reset = { 1 }, sw_p_charge = { 1 }, sw_g_endless = { 1 },
        sw_w_dashcd = { 2 }, sw_w_step = { 2 }, sw_b_pierce = { 2 }, sw_b_dashheal = { 2 },
        sw_p_charges = { 2 }, sw_p_invuln = { 2 }, sw_g_exec = { 2 },
        sw_w_stancedur = { 3 }, sw_w_vamp = { 3 }, sw_b_shock = { 3 }, sw_p_control = { 3 },
        sw_g_immovable = { 3 },
        sw_w_spin = { 4 }, sw_b_whirl = { 4 }, sw_p_spin = { 4 }, sw_g_whirl2 = { 4 },
        sw_w_guard = { 5 }, sw_b_guardheal = { 5 }, sw_p_parry2 = { 5 }, sw_g_guard3 = { 5 },
        sw_w_blink = { 6 }, sw_b_double = { 6 }, sw_p_blinkcd = { 6 }, sw_g_three = { 6 },
        sw_c_dance = { 4, 6 },
    },
    spearman = {
        sp_w_dashcd = { 2 }, sp_b_dashheal = { 2 }, sp_b_pierce = { 2 },
        sp_p_dash2 = { 2 }, sp_p_break = { 2 }, sp_p_air = { 2 }, sp_g_chase = { 2 },
        sp_w_guarddur = { 3 }, sp_w_damp = { 3 }, sp_b_reflect = { 3 },
        sp_p_guard = { 3 }, sp_g_bastion = { 3 }, sp_c_charge = { 3 },
        sp_w_throww = { 4 }, sp_b_throw = { 4 }, sp_p_throwpierce = { 4 },
        sp_g_return = { 4 },
        sp_w_back = { 5 }, sp_b_back = { 5 }, sp_p_backshock = { 5 },
        sp_g_backcharge = { 5 },
        sp_w_shock = { 6 }, sp_b_shock = { 6 }, sp_b_guard = { 6 },
        sp_p_shockrefund = { 6 }, sp_g_quake = { 6 },
        sp_c_cycle = { 4, 5, 6 },
    },
    ranger = {
        ra_b_rapid = { 1 }, ra_b_rapid2 = { 1 },
        ra_w_back = { 2 }, ra_b_dodge = { 2 }, ra_p_dodge2 = { 2 },
        ra_b_snipe = { 3 }, ra_p_air = { 3 }, ra_p_store = { 3 }, ra_c_sky = { 3 },
        ra_p_instant = { 3 },
        ra_w_trap = { 4 }, ra_b_trap = { 4 }, ra_p_trap2 = { 4 }, ra_g_trap = { 4 },
        ra_w_volley = { 5 }, ra_b_volley = { 5 }, ra_p_volley2 = { 5 }, ra_g_rain = { 5 },
        ra_w_swap = { 6 }, ra_b_swap = { 6 }, ra_p_swap2 = { 6 }, ra_p_swapdmg = { 6 },
        ra_g_leap = { 6 }, ra_g_shuttle = { 6 },
        ra_c_cycle = { 4, 5, 6 },
    },
    mage = {
        ma_w_fireball = { 1 }, ma_w_icewave = { 2 }, ma_w_boltstrike = { 3 },
        ma_w_blizzard = { 9 }, ma_w_static = { 7 },
        ma_b_flame = { 6 }, ma_b_pierceice = { 2 }, ma_b_chain = { 5 },
        ma_b_meteor = { 8 }, ma_b_icespike = { 4 }, ma_b_static = { 7 },
        ma_p_lava = { 1, 6, 8 }, ma_p_frozen = { 9 }, ma_p_thunder = { 7 },
        ma_p_dragon = { 1 }, ma_p_nova = { 2 }, ma_p_storm = { 5 },
        ma_p_emberstorm = { 6 }, ma_p_zero = { 2 }, ma_p_thundergod = { 3 },
        ma_g_phoenix = { 1, 6, 8 }, ma_g_winter = { 9 },
    },
}

function Config.ClassBuffNeed(buff)
    local group = Config.ClassBuffSkills[Config.PlayerClass]
    return group and group[buff.id] or nil
end

-- 元素类强化：只有携带了对应元素的技能，才可能抽到这条强化。
-- 没写进来的 = 通用条目，任何配装都能出。
-- 同时写多个元素（如元素协调）= 必须这几系都带着。
Config.ClassBuffElements = {
    mage = {
        -- 火
        ma_w_fire = { fire = true },
        ma_w_spread = { fire = true },
        ma_w_fireball = { fire = true },
        ma_b_flame = { fire = true },
        ma_b_ember = { fire = true },
        ma_b_emberslow = { fire = true },
        ma_b_meteor = { fire = true },
        ma_p_lava = { fire = true },
        ma_p_dragon = { fire = true },
        ma_p_emberstorm = { fire = true },
        ma_g_phoenix = { fire = true },
        ma_g_burnshield = { fire = true },
        ma_c_bake = { fire = true },
        -- 冰
        ma_w_ice = { ice = true },
        ma_w_frostarc = { ice = true },
        ma_w_icewave = { ice = true },
        ma_w_blizzard = { ice = true },
        ma_b_pierceice = { ice = true },
        ma_b_iceshield = { ice = true },
        ma_b_icespike = { ice = true },
        ma_b_frostfield = { ice = true },
        ma_p_frozen = { ice = true },
        ma_p_nova = { ice = true },
        ma_p_zero = { ice = true },
        ma_g_winter = { ice = true },
        ma_g_icearmor = { ice = true },
        -- 电
        ma_w_bolt = { bolt = true },
        ma_w_chain = { bolt = true },
        ma_w_boltstrike = { bolt = true },
        ma_w_static = { bolt = true },
        ma_b_chain = { bolt = true },
        ma_b_recover = { bolt = true },
        ma_b_static = { bolt = true },
        ma_b_charge = { bolt = true },
        ma_p_thunder = { bolt = true },
        ma_p_storm = { bolt = true },
        ma_p_thundergod = { bolt = true },
        ma_g_thunder = { bolt = true },
        ma_g_overload = { bolt = true },
        -- 需要多系同时存在
        ma_p_resonance = { fire = true, ice = true, bolt = true },
        ma_c_melt = { fire = true, ice = true },
    },
}

local ELEMENT_NAMES = { fire = "火系", ice = "冰系", bolt = "电系" }
local ELEMENT_ORDER = { "fire", "ice", "bolt" }

function Config.ClassBuffElementNeed(buff)
    local group = Config.ClassBuffElements[Config.PlayerClass]
    return group and group[buff.id] or nil
end

-- 返回「需要：xxx」文本；技能要求和元素要求会合并
function Config.ClassBuffNeedText(buff)
    local parts = {}
    local need = Config.ClassBuffNeed(buff)
    if need then
        local names = {}
        for _, id in ipairs(need) do
            local sk = Config.SkillByID(id)
            if sk then names[#names + 1] = sk.name end
        end
        if #names > 0 then parts[#parts + 1] = table.concat(names, " + ") end
    end
    local els = Config.ClassBuffElementNeed(buff)
    if els then
        local names = {}
        for _, el in ipairs(ELEMENT_ORDER) do
            if els[el] then names[#names + 1] = ELEMENT_NAMES[el] end
        end
        if #names > 0 then parts[#parts + 1] = table.concat(names, " + ") .. "技能" end
    end
    if #parts == 0 then return nil end
    return table.concat(parts, " + ")
end

function Config.ClassBuffByID(id)
    for _, group in pairs(Config.ClassBuffs) do
        for _, list in pairs(group) do
            for _, b in ipairs(list) do
                if b.id == id then return b end
            end
        end
    end
    return nil
end

function Config.ClassBuffRarity(id)
    for _, group in pairs(Config.ClassBuffs) do
        for rarity, list in pairs(group) do
            for _, b in ipairs(list) do
                if b.id == id then return rarity end
            end
        end
    end
    return nil
end

function Config.GeneralBuffByID(id)
    for rarity, list in pairs(Config.Buffs) do
        for _, b in ipairs(list) do
            if b.id == id then return b, rarity end
        end
    end
    return nil, nil
end

-- 角色 ---------------------------------------------------------------------
Config.Classes = {
    swordsman = {
        id = "swordsman", name = "剑客", role = "重装战士",
        hp = { 43, 70, 100 },      -- Lv.1 / 10 / 20
        shield = { 22, 40, 60 },
        atk = { 8, 17, 27 },
        speed = 4.7 * 32,           -- 像素/秒（4.7 米/秒）
        attackSpeed = 1.0,          -- 次/秒
        attackCdMul = 1.0,
        basicCoef = 1.0,
        basicRange = 74,
        basicArc = math.rad(110),
        radius = 15,
        color = { 120, 200, 255 },
        resourceName = "剑意",
        resourceMax = 5,
    },
    spearman = {
        id = "spearman", name = "枪客", role = "均衡连击手",
        hp = { 32, 50, 70 },
        shield = { 16, 25, 35 },
        atk = { 7, 16, 26 },
        speed = 4.0 * 32,
        attackSpeed = 1.0,
        attackCdMul = 0.55,         -- 三段普攻每段之间的间隔
        basicCoef = 1.2,            -- 三段均值（0.9 / 0.9 / 1.8）
        basicRange = 82,
        basicArc = math.rad(95),
        radius = 15,
        color = { 255, 186, 120 },
        resourceName = "枪势",
        resourceMax = 3,
    },
    ranger = {
        id = "ranger", name = "游侠", role = "远程风筝手",
        hp = { 21, 30, 40 },
        shield = { 11, 20, 30 },
        atk = { 7, 16, 26 },
        speed = 4.0 * 32,
        attackSpeed = 1.0,
        attackCdMul = 1.0,
        basicCoef = 1.0,
        basicRange = 360,
        basicArc = math.rad(20),
        radius = 15,
        color = { 140, 230, 170 },
        resourceName = "狩猎冲动",
        resourceMax = 3,
        ranged = true,
    },
    mage = {
        id = "mage", name = "法师", role = "元素爆发型",
        hp = { 22, 40, 60 },
        shield = { 16, 25, 35 },
        atk = { 8, 17, 27 },
        speed = 3.9 * 32,
        attackSpeed = 1.0,
        attackCdMul = 1.0,
        basicCoef = 0.6,
        basicRange = 380,
        basicArc = math.rad(12),
        radius = 15,
        color = { 190, 150, 255 },
        resourceName = "能量",
        resourceMax = 0,
        showResource = false,
        ranged = true,
    },
}

function Config.Class()
    return Config.Classes[Config.PlayerClass] or Config.Classes.swordsman
end

-- 等级经验消耗（Lv.N -> N+1）
Config.LevelCost = {
    6, 9, 14, 22, 33, 48, 68, 94, 128, 172,
    228, 298, 386, 496, 632, 800, 1006, 1258, 1562,
}

-- 升级门槛：目标等级 -> 需要的连续健康天数
function Config.LevelGate(targetLevel)
    if targetLevel >= 16 then
        return 8, "活力满满"
    elseif targetLevel >= 11 then
        return 3, "健康"
    end
    return 0, nil
end

function Config.ClassStats(level)
    local c = Config.Class()
    local hp, sh, atk
    if level <= 10 then
        local t = (level - 1) / 9
        hp = Config.Lerp(c.hp[1], c.hp[2], t)
        sh = Config.Lerp(c.shield[1], c.shield[2], t)
        atk = Config.Lerp(c.atk[1], c.atk[2], t)
    else
        local t = (level - 10) / 10
        hp = Config.Lerp(c.hp[2], c.hp[3], t)
        sh = Config.Lerp(c.shield[2], c.shield[3], t)
        atk = Config.Lerp(c.atk[2], c.atk[3], t)
    end
    return Round(hp), Round(sh), Round(atk)
end

-- ---------------------------------------------------------------- 技能池
-- unlockLevel 按最终节奏：Lv1 两个，之后 3/5/7/9 各一个
Config.ClassSkills = {
    swordsman = {
        {
            id = 1, name = "三段斩", short = "斩", unlockLevel = 1,
            cd = 3.0,
            desc = "向前三段斩击，每段 1.0 / 1.1 / 1.3 倍攻击。每命中一次获得 1 层剑意（最多 5 层），剑意每层使普攻伤害 +6%。",
        },
        {
            id = 2, name = "闪影突进", short = "突", unlockLevel = 1,
            cd = 6.0,
            desc = "向前突进并造成 1.7 倍伤害，命中后该技能冷却 -0.8 秒。突进期间无敌（0.22 秒），可以穿怪。",
        },
        {
            id = 3, name = "剑心护体", short = "护", unlockLevel = 3,
            cd = 10.0,
            desc = "1.8 秒内移速 +25%、攻速 +20%、吸血 +6%。期间普攻每次额外获得 1 层剑意，更快叠满 5 层触发剑气爆发。",
        },
        {
            id = 4, name = "旋刃横斩", short = "旋", unlockLevel = 5,
            cd = 6.0,
            desc = "原地 360° 斩击，造成 1.5 倍伤害并施加 1 层挫裂。挫裂每层使目标受到的物理伤害 +12%，最多 5 层，持续 4 秒且每秒掉 1 层。",
        },
        {
            id = 5, name = "卸势格挡", short = "格", unlockLevel = 7,
            cd = 8.0,
            desc = "横剑架起 1 秒，期间完全免伤（可连挡多次攻击）。格挡成功立刻反击一道剑气（0.9 倍范围伤害）、获得 1 层剑意，并让其他技能冷却 -0.8 秒。",
        },
        {
            id = 6, name = "瞬影连斩", short = "瞬", unlockLevel = 9,
            cd = 7.0,
            desc = "两段短冲刺，每段 1.2 倍伤害，每段命中获得 1 层剑意。突进期间无敌（约 0.45 秒，覆盖两段之间的间隙）。",
        },
    },
    spearman = {
        {
            id = 1, name = "三段枪式", short = "式", unlockLevel = 1,
            cd = 7.0,
            desc = "开启后 5 秒内强化接下来 3 次普攻：1A 额外 40% 攻击、2A 吸血 25%、3A 强制击飞；每次命中使全部技能冷却 -1 秒。",
        },
        {
            id = 2, name = "突刺奔袭", short = "突", unlockLevel = 1,
            cd = 6.0,
            desc = "向前突刺（距离更远），1.6 倍伤害，突进期间减伤 10%；命中施加 1 层挫裂，收尾震开周围敌人并叠失衡。消耗 1 层枪势时，命中带挫裂目标触发震荡连携。",
        },
        {
            id = 3, name = "铁枪固守", short = "守", unlockLevel = 3,
            cd = 9.0,
            desc = "架枪 2.5 秒：弹开子弹、近战减伤 12%；收尾震地 1.8 倍伤害并施加 1 层挫裂。消耗枪势时，震地命中带挫裂目标触发震荡。",
        },
        {
            id = 4, name = "掷枪", short = "掷", unlockLevel = 5,
            cd = 7.0,
            desc = "投掷长枪贯穿敌人，造成 1.7 倍伤害并施加 1 层失衡。消耗枪势时，命中带挫裂目标触发震荡连携。",
        },
        {
            id = 5, name = "回马枪", short = "回", unlockLevel = 7,
            cd = 6.5,
            desc = "后撤一步再向前突刺：突刺距离与范围都更大，1.75 倍伤害并施加 1 层失衡。消耗枪势时，命中带挫裂目标触发震荡连携。",
        },
        {
            id = 6, name = "枪阵震地", short = "震", unlockLevel = 9,
            cd = 9.0,
            desc = "长枪砸地，环形冲击波造成 1.8 倍伤害并施加 1 层失衡。消耗枪势时，命中带挫裂目标触发震荡连携。",
        },
    },
    ranger = {
        {
            id = 1, name = "精准速射", short = "速", unlockLevel = 1,
            cd = 6.0,
            desc = "5 秒内普攻命中叠加速射层数（每层攻速 +6%，最多 5 层），期间普攻额外叠加 1 层猎痕。",
        },
        {
            id = 2, name = "疾退腾挪", short = "退", unlockLevel = 1,
            cd = 7.0,
            desc = "向后翻滚并短暂无敌 0.3 秒，获得 1 层狩猎冲动；翻滚期间碰到敌人子弹会额外补充 1 层。",
        },
        {
            id = 3, name = "穿魂狙击", short = "狙", unlockLevel = 3,
            cd = 8.0,
            desc = "蓄力 0.6 秒后射出穿透箭，造成 2.6 倍伤害并施加 2 层猎痕；命中带失衡目标触发追猎连携。",
        },
        {
            id = 4, name = "猎影诱捕", short = "陷", unlockLevel = 5,
            cd = 11.0,
            desc = "长按拖到指定位置放下夹子（3 秒）：敌人踩中会被束缚 1.2 秒、减速 40%、施加 1 层猎痕，并使你下一次普攻必定暴击。",
        },
        {
            id = 5, name = "箭影连射", short = "连", unlockLevel = 7,
            cd = 5.5,
            desc = "向面前扇形射出 4 支箭，每支 0.85 倍伤害并施加猎痕；命中带失衡目标可触发追猎连携。",
        },
        {
            id = 6, name = "掠袭换位", short = "换", unlockLevel = 9,
            cd = 10.0,
            desc = "瞬移到最近带猎痕的敌人身后，下一次普攻伤害 +25% 并额外施加 2 层猎痕。",
        },
    },
    mage = {
        {
            id = 1, name = "火球术", short = "火", unlockLevel = 1, element = "fire",
            cd = 2.0,
            desc = "发射火球，造成 2.0 倍伤害并附加燃烧 3 秒。",
        },
        {
            id = 2, name = "冰冻波", short = "冰", unlockLevel = 1, element = "ice",
            cd = 5.0,
            desc = "向前方扇形释放冰霜，造成 0.8 倍伤害并冰冻 1.5 秒。",
        },
        {
            id = 3, name = "雷击术", short = "雷", unlockLevel = 1, element = "bolt",
            cd = 4.0,
            desc = "雷击单体，造成 2.5 倍伤害；对燃烧或冰冻目标伤害 ×1.5。",
        },
        {
            id = 4, name = "冰锥术", short = "锥", unlockLevel = 3, element = "ice",
            cd = 3.0,
            desc = "射出冰锥，造成 1.2 倍伤害并减速 50%，持续 2 秒。",
        },
        {
            id = 5, name = "闪电链", short = "链", unlockLevel = 5, element = "bolt",
            cd = 6.0,
            desc = "闪电链弹射 3 个目标，每个 1.2 倍伤害；命中燃烧/冰冻目标触发过载增伤。",
        },
        {
            id = 6, name = "烈焰冲击", short = "焰", unlockLevel = 5, element = "fire",
            cd = 6.0,
            desc = "范围烈焰，造成 1.5 倍伤害；对燃烧目标伤害 +50%。",
        },
        {
            id = 7, name = "静电力场", short = "场", unlockLevel = 7, element = "bolt",
            cd = 8.0,
            desc = "生成 5 秒静电力场，每 0.5 秒造成 0.2 倍伤害并减速 20%。",
        },
        {
            id = 8, name = "流星陨落", short = "星", unlockLevel = 7, element = "fire",
            cd = 10.0,
            desc = "在最近敌人处落下流星，造成 3.0 倍范围伤害并附加燃烧 5 秒。",
        },
        {
            id = 9, name = "暴风雪", short = "雪", unlockLevel = 9, element = "ice",
            cd = 12.0,
            desc = "生成 4 秒暴风雪，每 0.5 秒造成 0.3 倍伤害并减速 30%。",
        },
    },
}

Config.Skills = Config.ClassSkills.swordsman

-- ---------------------------------------------------------------- 技能长按瞄准
-- 按住技能键 0.22 秒进入瞄准：dir = 选方向（显示扇形/直线预览），point = 选落点（显示圆圈）
-- 松手立刻释放；轻点（不到 0.22 秒且没拖动）仍然是原来的自动瞄准
Config.SkillAim = {
    swordsman = {},
    spearman = {
        [2] = { mode = "dir", range = 230, arc = math.rad(44) },
        [4] = { mode = "dir", range = 620, arc = math.rad(16) },
        [5] = { mode = "dir", range = 240, arc = math.rad(85) },
    },
    ranger = {
        [3] = { mode = "dir", range = 860, arc = math.rad(14) },
        [4] = { mode = "point", range = 420, r = 56 },
        [5] = { mode = "dir", range = 640, arc = math.rad(62) },
    },
    mage = {
        [1] = { mode = "dir", range = 760, arc = math.rad(18) },
        [2] = { mode = "dir", range = 128, arc = math.rad(62) },
        [3] = { mode = "point", range = 620, r = 150 },
        [4] = { mode = "dir", range = 860, arc = math.rad(12) },
        [5] = { mode = "point", range = 620, r = 150 },
        [6] = { mode = "dir", range = 120, arc = math.rad(140) },
        [8] = { mode = "point", range = 520, r = 100 },
    },
}

function Config.SkillAimOf(id)
    local group = Config.SkillAim[Config.PlayerClass]
    return group and group[id] or nil
end

function Config.SetClass(id)
    if Config.Classes[id] and Config.ClassSkills[id] then
        Config.PlayerClass = id
        Config.Skills = Config.ClassSkills[id]
    end
end

function Config.SkillByID(id)
    for _, s in ipairs(Config.Skills) do
        if s.id == id then return s end
    end
    return nil
end

-- ---------------------------------------------------------------- 健康
-- 步数 -> 超静息消耗百分比
function Config.ActivityPercent(steps)
    return steps * Config.STEP_KCAL / Config.REST_KCAL * 100
end

-- 百分比 -> 每 1% 金币
function Config.GoldRate(percent)
    if percent < 10 then return 1 end
    if percent < 20 then return 5 end
    if percent < 30 then return 20 end
    if percent < 40 then return 5 end
    return 1
end

function Config.StepGold(steps)
    local pct = Config.ActivityPercent(steps)
    return math.floor(pct * Config.GoldRate(pct) + 0.0001), pct
end

Config.StepUnlockThresholds = { 2000, 8000, 12000 }

-- 关卡开始时护盾的初始比例（1.0 = 满盾；0.5 = 半盾）
Config.StartShieldRatio = 1.0

-- 战斗房通关后的 Buff 三选一：品质权重随房间难度提升
Config.RewardWeights = {
    light = { white = 55, blue = 35, purple = 9, gold = 1 },
    standard = { white = 40, blue = 40, purple = 17, gold = 3 },
    mixed = { white = 20, blue = 40, purple = 32, gold = 8 },
    elite = { white = 0, blue = 25, purple = 55, gold = 20 },
    double = { white = 0, blue = 15, purple = 55, gold = 30 },
}

-- 连续健康天数奖励（v1 只给金币 + 技能点）
Config.StreakRewards = {
    { days = 3, gold = 300, sp = 0 },
    { days = 7, gold = 700, sp = 1 },
    { days = 14, gold = 1500, sp = 2 },
    { days = 30, gold = 3000, sp = 3 },
}

return Config

