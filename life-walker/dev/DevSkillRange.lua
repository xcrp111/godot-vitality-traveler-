-- DevSkillRange.lua — 枪客 / 游侠 / 法师：技能范围提示、自动瞄准、空放保护
local Config = require "Config"
local Save = require "Save"
local S = require "State"
local Run = require "Run"
local Combat = require "Combat"
local VirtualControls = require "urhox-libs.UI.VirtualControls"

local fails = 0
local function check(name, cond, detail)
    if cond then
        print("[Range] OK   " .. name)
    else
        fails = fails + 1
        print("[Range] FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
    end
end

local function Step(cs, frames)
    for _ = 1, frames do
        Combat.Update(1 / 60)
        if S.screen ~= "combat" then return end
    end
end

-- 建一场干净的战斗：清墙、清怪，再按坐标放怪
local function Scene(class, loadout, spots)
    Save.SetClass(S.data, class)
    Save.SetClassLevel(S.data, 12)
    Config.SetClass(class)
    Run.Start(1)
    S.run.loadout = loadout
    local cs = Combat.Start(S.run, "standard", 3)
    S.screen = "combat"
    cs.enemies = {}
    cs.walls = {}
    cs.waves = { {} }
    cs.waveIndex = 1
    local p = cs.player
    for _, sp in ipairs(spots or {}) do
        Combat.SpawnWave(cs, { minion = 1 })
        local e = cs.enemies[#cs.enemies]
        e.hp = 99999
        e.maxHp = 99999
        e.x = p.x + sp[1]
        e.y = p.y + sp[2]
        e.stunTimer = 99
        e.moveSpeed = 0
    end
    cs.facing = 0
    return cs, p
end

local function HasKind(cs, kind)
    for _, g in ipairs(cs.telegraphs or {}) do
        if g.kind == kind then return g end
    end
    return nil
end

function Start()
    VirtualControls.Initialize(Config.DESIGN_W, Config.DESIGN_H)
    S.data = Save.Load()
    math.randomseed(21)

    -- ================================================ 枪客
    local cs, p = Scene("spearman", { 2, 4, 6 }, { { 200, 80 } })   -- 怪在斜上方约 22°
    Combat.CastSkill(1)                                             -- 突刺奔袭
    local aimErr = math.abs(math.atan(80, 200))
    check("枪客 突刺自动转向目标", math.abs(cs.facing - aimErr) < 0.02, cs.facing)
    local cor = HasKind(cs, "corridor")
    check("枪客 突刺显示冲刺范围", cor ~= nil and cor.len > 150, cor and cor.len)

    cs.telegraphs = {}
    cs, p = Scene("spearman", { 2, 4, 6 }, { { 300, 0 } })
    Combat.CastSkill(2)                                             -- 掷枪
    cor = HasKind(cs, "corridor")
    check("枪客 掷枪显示投掷距离", cor ~= nil and math.abs(cor.len - 620) < 1, cor and cor.len)

    cs.telegraphs = {}
    cs, p = Scene("spearman", { 2, 4, 6 }, { { 80, 0 } })
    Combat.CastSkill(3)                                             -- 枪阵震地
    local circ = HasKind(cs, "circle")
    check("枪客 枪阵震地显示环形范围", circ ~= nil and math.abs(circ.r - 140) < 1, circ and circ.r)
    check("枪客 范围提示会自然消失", (#cs.telegraphs > 0))
    Step(cs, 45)
    check("枪客 范围提示 45 帧后清空", #(cs.telegraphs or {}) == 0, #(cs.telegraphs or {}))

    -- ================================================ 游侠
    cs, p = Scene("ranger", { 3, 4, 5 }, { { 260, 0 } })
    Combat.CastSkill(1)                                             -- 穿魂狙击（蓄力）
    check("游侠 狙击进入蓄力", cs.snipeCharge ~= nil)
    check("游侠 蓄力指示带方向与时长", cs.snipeCharge ~= nil
        and cs.snipeCharge.dur >= 0.59 and cs.snipeCharge.facing ~= nil)
    Step(cs, 50)
    check("游侠 蓄力结束后放出", cs.snipeCharge == nil)
    check("游侠 放出后显示穿刺路径", HasKind(cs, "corridor") ~= nil)

    cs.telegraphs = {}
    cs, p = Scene("ranger", { 3, 4, 5 }, { { 120, 0 } })
    Combat.CastSkill(2)                                             -- 猎影诱捕
    circ = HasKind(cs, "circle")
    check("游侠 陷阱显示作用半径", circ ~= nil and math.abs(circ.r - 70) < 1, circ and circ.r)

    cs.telegraphs = {}
    cs, p = Scene("ranger", { 3, 4, 5 }, { { 260, 60 } })
    Combat.CastSkill(3)                                             -- 箭影连射
    local sec = HasKind(cs, "sector")
    check("游侠 连射显示扇形范围", sec ~= nil and sec.range > 500, sec and sec.range)

    cs.telegraphs = {}
    cs, p = Scene("ranger", { 1, 2, 3 }, {})
    p.cooldowns[1] = 0
    Combat.CastSkill(1)                                             -- 精准速射（buff 类）
    check("游侠 速射也有反馈", #(cs.telegraphs or {}) > 0)

    -- 空放保护
    cs, p = Scene("ranger", { 6, 1, 2 }, {})
    Combat.CastSkill(1)                                             -- 掠袭换位，无目标
    check("游侠 无目标不空放", (p.cooldowns[6] or 0) == 0, p.cooldowns[6])

    -- ================================================ 法师
    cs, p = Scene("mage", { 1, 2, 5 }, { { 300, 0 } })
    Combat.CastSkill(1)                                             -- 火球术
    cor = HasKind(cs, "corridor")
    check("法师 火球显示飞行路径", cor ~= nil and cor.len > 500, cor and cor.len)

    cs.telegraphs = {}
    cs, p = Scene("mage", { 1, 2, 5 }, { { 90, 30 } })
    Combat.CastSkill(2)                                             -- 冰冻波
    sec = HasKind(cs, "sector")
    check("法师 冰冻波显示扇形范围", sec ~= nil and math.abs(sec.range - 128) < 1, sec and sec.range)

    cs.telegraphs = {}
    cs, p = Scene("mage", { 1, 2, 5 }, { { 120, 0 }, { 190, 0 }, { 260, 0 } })
    Combat.CastSkill(3)                                             -- 闪电链
    check("法师 闪电链画出连锁闪电", #(cs.bolts or {}) >= 1, #(cs.bolts or {}))
    check("法师 闪电链有起手连线", HasKind(cs, "line") ~= nil)

    cs, p = Scene("mage", { 1, 2, 5 }, { { 200, 0 } })
    Combat.CastSkill(1)                                             -- 火球术
    local boltsBefore = #(cs.bolts or {})
    cs.telegraphs = {}
    cs.enemies = {}
    Combat.CastSkill(2)                                             -- 冰冻波（扇形，不需要目标，正常放）
    check("法师 破冰波无目标也能放", (p.cooldowns[2] or 0) > 0)
    check("法师 火球不额外产生闪电", #(cs.bolts or {}) == boltsBefore)

    cs, p = Scene("mage", { 3, 1, 4 }, {})
    Combat.CastSkill(1)                                             -- 雷击术，无目标
    check("法师 雷击无目标不空放", (p.cooldowns[3] or 0) == 0, p.cooldowns[3])

    cs, p = Scene("mage", { 3, 1, 4 }, { { 200, 0 } })
    Combat.CastSkill(1)                                             -- 雷击术，有目标
    check("法师 雷击有目标就放", (p.cooldowns[3] or 0) > 0)
    check("法师 雷击画出落雷", #(cs.bolts or {}) >= 1, #(cs.bolts or {}))

    -- 一局长跑冒烟：三个职业各跑 240 帧不崩
    for _, cls in ipairs({ "spearman", "ranger", "mage" }) do
        local c2 = Scene(cls, { 1, 2, 3 }, { { 140, 40 }, { 220, -60 } })
        for f = 1, 240 do
            c2.player.attackTimer = 0
            Combat.BasicAttack(c2)
            if f % 40 == 0 then Combat.CastSkill((f / 40) % 3 + 1) end
            Combat.Update(1 / 60)
            if S.screen ~= "combat" then break end
        end
        check(cls .. " 长跑 240 帧存活", S.screen == "combat" or S.screen == "reward"
            or S.screen == "levelclear", S.screen)
    end

    print("[Range] done, failures = " .. fails)
end
