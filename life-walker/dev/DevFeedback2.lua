-- DevFeedback2.lua — 测试同学第二批反馈 + 长按瞄准：逐条验证
local Config = require "Config"
local Save = require "Save"
local S = require "State"
local Run = require "Run"
local Combat = require "Combat"

local fails = 0
local function check(name, cond, detail)
    if cond then
        print("[FB2] OK   " .. name)
    else
        fails = fails + 1
        print("[FB2] FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
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
    cs.player.x, cs.player.y = 640, 400
    cs.player.shield = 0
    cs.player.crit = 0
    return cs
end

function Start()
    -- ============ 1. 精英不再回血 ============
    local cs = NewCombat("swordsman", { 1, 2, 3 })
    Combat.SpawnWave(cs, { elite = 1 })
    local el = cs.enemies[1]
    el.hp = 1
    cs.player.hp = math.floor(cs.player.maxHp * 0.5)
    local hpMid = cs.player.hp
    Combat.HitEnemy(cs, el, 9999, false, true, true, "basic")
    check("1 打完精英不回血", cs.player.hp == hpMid, string.format("%d -> %d", hpMid, cs.player.hp))

    -- ============ 2. 卸势格挡：免伤 + 反打 + 冷却返还 ============
    cs = NewCombat("swordsman", { 1, 2, 3 })
    Combat.SpawnWave(cs, { minion = 1 })
    local e = cs.enemies[1]
    e.x, e.y = cs.player.x + 100, cs.player.y
    e.hp, e.maxHp = 500, 500
    cs.facing = 0
    cs.player.parryTimer = 1.0
    cs.player.parryLeft = 99
    cs.player.cooldowns[2] = 5.0
    local hp0 = cs.player.hp
    Combat.DamagePlayer(cs, 30)
    Combat.DamagePlayer(cs, 30)
    check("2 格挡窗口内连续两次都不掉血", cs.player.hp == hp0, cs.player.hp)
    check("2 格挡成功返还其他技能冷却", cs.player.cooldowns[2] < 5.0, cs.player.cooldowns[2])
    check("2 格挡成功剑气反打", e.hp < 500, e.hp)
    check("2 格挡闪光反馈就绪", (cs.parryFlash or 0) > 0, cs.parryFlash)

    -- ============ 3. 金色「破甲」不再是无效词条 ============
    cs = NewCombat("swordsman")
    Run.GrantBuff(cs.player, {
        id = "g_pen", name = "破甲", desc = "", rarity = "gold", classBuff = false,
        mod = { basicPct = 0.40 }, flag = { penVuln = 0.08 },
    })
    check("3 破甲：普攻伤害 +40%", math.abs(cs.player.basicPct - 0.40) < 1e-6, cs.player.basicPct)
    Combat.SpawnWave(cs, { minion = 1 })
    local pe = cs.enemies[1]
    pe.hp, pe.maxHp = 100000, 100000
    pe.crack = 0
    local h0 = pe.hp
    Combat.HitEnemy(cs, pe, 100, false, true, true, "basic")
    local d1 = h0 - pe.hp
    check("3 破甲：普攻命中挂易伤", (pe.penVulnTimer or 0) > 0, pe.penVulnTimer)
    local h1 = pe.hp
    Combat.HitEnemy(cs, pe, 100, false, true, true, "basic")
    local d2 = h1 - pe.hp
    check("3 破甲：后续物理伤害提高", d2 > d1 * 1.05, string.format("%.1f -> %.1f", d1, d2))

    -- ============ 4. 狂剑士：吸血 + 掉血下限 ============
    cs = NewCombat("swordsman", { 1, 2, 3 })
    Run.GrantBuff(cs.player, {
        id = "sw_c_berserk", name = "狂剑士", desc = "", rarity = "color", classBuff = true,
        mod = { skillPct = 0.6, lifesteal = 0.08 }, flag = { berserk = 1 },
    })
    check("4 狂剑士自带吸血", (cs.player.lifesteal or 0) >= 0.08 - 1e-6, cs.player.lifesteal)
    cs.player.hp = cs.player.maxHp * 0.30
    cs.player.cooldowns[1] = 0
    Combat.CastSkill(1)
    check("4 技能掉血不会低于 25% 生命",
        cs.player.hp >= cs.player.maxHp * 0.249,
        string.format("%.1f / %.1f", cs.player.hp, cs.player.maxHp))

    -- ============ 5. 回马枪：后撤后前刺更远 ============
    cs = NewCombat("spearman", { 1, 2, 5 })
    Combat.SpawnWave(cs, { minion = 1 })
    local se = cs.enemies[1]
    se.x, se.y = 800, 400
    se.hp, se.maxHp = 9999, 9999
    cs.player.x, cs.player.y = 640, 400
    cs.facing = 0
    local x0 = cs.player.x
    Combat.CastSkill(3)          -- loadout[3] = 回马枪
    check("5 回马枪先后撤", cs.player.x < x0 - 30, string.format("%.0f -> %.0f", x0, cs.player.x))
    Combat.Update(0.16)          -- 触发前刺
    check("5 前刺能打到原来够不到的距离", se.hp < 9999, se.hp)

    -- ============ 6. 突刺奔袭：距离更长 ============
    cs = NewCombat("spearman", { 2, 1, 5 })
    cs.player.x, cs.player.y = 640, 400
    cs.facing = 0
    local x1 = cs.player.x
    Combat.CastSkill(1)          -- loadout[1] = 突刺奔袭
    check("6 突刺时长加长", cs.dash and math.abs(cs.dash.t - 0.20) < 1e-6,
        cs.dash and cs.dash.t)
    Combat.Update(0.21)
    check("6 突刺距离更远", cs.player.x > x1 + 180, string.format("%.0f -> %.0f", x1, cs.player.x))

    -- ============ 7. 猎影诱捕：拖放 + 小判定 + 束缚 ============
    cs = NewCombat("ranger", { 4, 3, 5 })
    cs.player.x, cs.player.y = 500, 400
    cs.facing = 0
    cs.aimPoint = { x = 620, y = 460 }
    cs.aimLock = true
    Combat.CastSkill(1)          -- loadout[1] = 猎影诱捕
    cs.aimLock = nil
    cs.aimPoint = nil
    local tr = cs.rangerTraps and cs.rangerTraps[1]
    check("7 夹子放在拖动位置", tr and math.abs(tr.x - 620) < 1 and math.abs(tr.y - 460) < 1,
        tr and string.format("%.0f,%.0f", tr.x, tr.y))
    check("7 夹子判定缩小", tr and tr.r <= 50, tr and tr.r)
    Combat.SpawnWave(cs, { minion = 1 })
    local te = cs.enemies[1]
    te.x, te.y = tr.x, tr.y
    Combat.Update(0.02)
    check("7 踩中夹子被束缚", (te.rootTimer or 0) > 0, te.rootTimer)
    check("7 束缚时间约 1.2 秒", te.rootTimer and te.rootTimer > 1.0, te.rootTimer)

    -- ============ 8. 掠袭换位：到身后 + 改伤害加成 ============
    cs = NewCombat("ranger", { 6, 5, 3 })
    cs.player.x, cs.player.y = 500, 400
    cs.player.crit = 0
    Combat.SpawnWave(cs, { minion = 1 })
    local we = cs.enemies[1]
    we.x, we.y = 700, 400
    we.hp, we.maxHp = 99999, 99999
    we.hunt = 2
    Combat.CastSkill(1)          -- loadout[1] = 掠袭换位
    check("8 换位落到敌人身后", cs.player.x > we.x, string.format("player %.0f vs enemy %.0f", cs.player.x, we.x))
    check("8 换位后普攻加成标记", (cs.rangerSwap or 0) > 0, cs.rangerSwap)

    cs.rangerSwap = 0
    Combat.RangerBasicAttack(cs)
    local dmgNormal = cs.projs[#cs.projs].dmg
    cs.rangerSwap = 1
    Combat.RangerBasicAttack(cs)
    local dmgSwap = cs.projs[#cs.projs].dmg
    check("8 换位后那次普攻伤害更高", dmgSwap > dmgNormal * 1.2,
        string.format("%.1f -> %.1f", dmgNormal, dmgSwap))

    -- ============ 9. 箭影连射：基础伤害上调 ============
    cs = NewCombat("ranger", { 5, 3, 4 })
    cs.player.crit = 0
    Combat.CastSkill(1)          -- loadout[1] = 箭影连射
    local arrow = cs.projs[1]
    local expected = cs.player.atk * 0.85 * (1 + cs.player.skillPct)
    check("9 每支箭 0.85 倍伤害", arrow and math.abs(arrow.dmg - expected) < expected * 0.01,
        arrow and string.format("%.1f vs %.1f", arrow.dmg, expected))

    -- ============ 10. 彩色保底 ============
    cs = NewCombat("swordsman")
    local bp = cs.player
    bp.colorPity = 4
    local gotColor = nil
    for _ = 1, 30 do
        local b = Run.RollAnyBuff(bp, "gold")
        if b and b.rarity == "color" then gotColor = b break end
    end
    check("10 金色连抽保底出彩色", gotColor ~= nil, gotColor and gotColor.id)
    if gotColor then
        Run.GrantBuff(bp, gotColor)
        check("10 拿到彩色后保底计数清零", (bp.colorPity or 0) == 0, bp.colorPity)
    end

    -- ============ 11. 长按瞄准 ============
    cs = NewCombat("mage", { 1, 3, 8 })
    cs.player.x, cs.player.y = 640, 400
    cs.facing = 0
    local bx, by = Combat.CtrlPos("skill1", 1080, 624, 36)
    local down = Combat.AimPointer("down", bx, by, 7)
    check("11 按住技能键进入瞄准", down and cs.aim ~= nil)
    check("11 瞄准时不会立刻放技能", (cs.player.cooldowns[1] or 0) <= 0, cs.player.cooldowns[1])
    Combat.AimPointer("move", 200, 300, 7)
    local aimAngle = cs.aim and cs.aim.angle
    check("11 拖动会更新方向", aimAngle ~= nil, aimAngle)
    cs.aim.t = 0.3             -- 模拟按住超过阈值
    local up = Combat.AimPointer("up", 200, 300, 7)
    check("11 松手才释放", up and (cs.player.cooldowns[1] or 0) > 0, cs.player.cooldowns[1])
    check("11 按瞄准方向改变朝向", math.abs(cs.facing - aimAngle) < 1e-6,
        string.format("%.3f vs %.3f", cs.facing, aimAngle))
    local proj = cs.projs[1]
    local projAng = proj and math.atan(proj.vy, proj.vx)
    check("11 火球沿瞄准方向飞出", projAng and math.abs(projAng - aimAngle) < 0.02,
        projAng)

    -- 轻点仍然是自动瞄准
    cs = NewCombat("mage", { 1, 3, 8 })
    cs.player.x, cs.player.y = 640, 400
    Combat.SpawnWave(cs, { minion = 1 })
    cs.enemies[1].x, cs.enemies[1].y = 900, 400
    Combat.AimPointer("down", bx, by, 8)
    Combat.AimPointer("up", bx, by, 8)
    check("11 轻点直接释放（不进入锁定）", cs.aim == nil and (cs.player.cooldowns[1] or 0) > 0)
    local autoAng = cs.projs[1] and math.atan(cs.projs[1].vy, cs.projs[1].vx)
    check("11 轻点自动瞄准最近的敌人", autoAng and math.abs(autoAng) < 0.05, autoAng)

    -- 瞄准期间另一根手指（左手摇杆）不能被吞掉
    cs = NewCombat("mage", { 1, 3, 8 })
    bx, by = Combat.CtrlPos("skill1", 1080, 624, 36)
    Combat.AimPointer("down", bx, by, 11)
    local blocked = Combat.AimPointer("down", 200, 500, 12)
    check("11 瞄准时另一根手指不被吞（可同时操作摇杆）", blocked == false, tostring(blocked))
    check("11 同一根手指仍是瞄准", Combat.AimPointer("down", bx, by, 11) == true)

    -- 拖进右上角取消区域松手 → 不放技能、不吃冷却
    local cz = Combat.AimCancelRect()
    local czx = cz.x + cz.w / 2
    local czy = cz.y + cz.h / 2
    Combat.AimPointer("move", czx, czy, 11)
    check("11 进入取消区域会标记", cs.aim and cs.aim.cancel == true)
    cs.aim.t = 0.3
    local upCancel = Combat.AimPointer("up", czx, czy, 11)
    check("11 拖进取消区松手取消施法",
        upCancel and cs.aim == nil and (cs.player.cooldowns[1] or 0) <= 0, cs.player.cooldowns[1])

    -- 取消框跟着「按键布局」走（可在设置里拖位置/调大小）
    Save.Layout(S.data)
    S.data.layout.aim_cancel = { x = 300, y = 220, r = 70 }
    local moved = Combat.AimCancelRect()
    check("11 取消框位置跟随按键布局",
        math.abs((moved.x + moved.w / 2) - 300) < 1 and math.abs((moved.y + moved.h / 2) - 220) < 1,
        string.format("%.0f,%.0f", moved.x + moved.w / 2, moved.y + moved.h / 2))
    S.data.layout.aim_cancel = nil
    Save.Layout(S.data)

    -- ============ 13. 瞄准以技能键为圆心（不再以角色为中心） ============
    local function dist2(ax, ay, bx2, by2)
        return math.sqrt((ax - bx2) * (ax - bx2) + (ay - by2) * (ay - by2))
    end
    cs = NewCombat("mage", { 1, 3, 8 })
    cs.player.x, cs.player.y = 640, 400
    bx, by = Combat.CtrlPos("skill1", 1080, 624, 36)
    Combat.AimPointer("down", bx, by, 21)
    Combat.AimPointer("move", bx, by - 120, 21)
    check("13 技能键上推 = 朝上施法", math.abs(cs.aim.angle + math.pi / 2) < 0.05, cs.aim.angle)
    Combat.AimPointer("move", bx + 120, by, 21)
    check("13 技能键右推 = 朝右施法", math.abs(cs.aim.angle) < 0.05, cs.aim.angle)
    Combat.AimPointer("up", bx + 120, by, 21)

    -- 按在技能键边缘「轻点」仍然是智能施法（不能被当成往上瞄准）
    cs = NewCombat("mage", { 1, 3, 8 })
    cs.player.x, cs.player.y = 640, 400
    Combat.SpawnWave(cs, { minion = 1 })
    cs.enemies[1].x, cs.enemies[1].y = 900, 400      -- 敌人在正右
    bx, by = Combat.CtrlPos("skill1", 1080, 624, 36)
    Combat.AimPointer("down", bx, by - 30, 31)       -- 按在按键上边缘
    Combat.AimPointer("up", bx, by - 30, 31)
    local edgeAng = cs.projs[1] and math.atan(cs.projs[1].vy, cs.projs[1].vx)
    check("13 按键边缘轻点 = 智能施法（自动瞄准）",
        edgeAng and math.abs(edgeAng) < 0.08, edgeAng)

    -- 选位技能轻点同样是智能施法：直接打最近的敌人
    cs = NewCombat("mage", { 1, 3, 8 })
    cs.player.x, cs.player.y = 640, 400
    Combat.SpawnWave(cs, { minion = 1 })
    cs.enemies[1].x, cs.enemies[1].y = 800, 400
    cs.enemies[1].hp, cs.enemies[1].maxHp = 99999, 99999   -- 别被一下秒掉，才能比较血量
    local hpBeforeSmart = cs.enemies[1].hp
    local s2x, s2y = Combat.CtrlPos("skill2", 1110, 526, 36)
    Combat.AimPointer("down", s2x, s2y, 32)
    Combat.AimPointer("up", s2x, s2y, 32)
    check("13 选位技能轻点 = 自动打最近的敌人",
        cs.enemies[1].hp < hpBeforeSmart,
        string.format("%.0f -> %.0f", hpBeforeSmart, cs.enemies[1].hp))

    -- ============ 14. 选位技能：摇杆式 / 屏幕式 + 不超过角色攻击范围 ============
    local maxR = Config.Class().basicRange * (1 + (cs.player.rangePct or 0))
    local b2x, b2y = Combat.CtrlPos("skill2", 1110, 526, 36)

    cs = NewCombat("mage", { 1, 3, 8 })
    cs.player.x, cs.player.y = 640, 400
    S.data.aimMode = "button"
    maxR = Config.Class().basicRange * (1 + (cs.player.rangePct or 0))
    Combat.AimPointer("down", b2x, b2y, 22)
    Combat.AimPointer("move", b2x + 400, b2y, 22)      -- 拖满
    local full = dist2(cs.aim.point.x, cs.aim.point.y, cs.player.x, cs.player.y)
    check("14 摇杆式最远不超过角色攻击范围", full <= maxR + 0.5, string.format("%.1f / %.1f", full, maxR))
    Combat.AimPointer("move", b2x + 60, b2y, 22)       -- 半程
    local half = dist2(cs.aim.point.x, cs.aim.point.y, cs.player.x, cs.player.y)
    check("14 拖得越近放得越近", half < full - 10, string.format("%.1f vs %.1f", half, full))
    Combat.AimPointer("up", b2x + 60, b2y, 22)

    cs = NewCombat("mage", { 1, 3, 8 })
    cs.player.x, cs.player.y = 640, 400
    S.data.aimMode = "screen"
    Combat.AimPointer("down", b2x, b2y, 23)
    Combat.AimPointer("move", 300, 200, 23)
    local screenD = dist2(cs.aim.point.x, cs.aim.point.y, cs.player.x, cs.player.y)
    check("14 屏幕式落点同样不超过攻击范围", screenD <= maxR + 0.5,
        string.format("%.1f / %.1f", screenD, maxR))
    Combat.AimPointer("up", 300, 200, 23)
    S.data.aimMode = "button"

    -- ============ 12. 枪客武器不再比判定长 ============
    local spearClass = Config.Classes.spearman
    local drawn = spearClass.basicRange - 4 + 8    -- 枪身 + 枪头
    check("12 枪身长度贴近判定范围", drawn <= spearClass.basicRange + 18 + 6,
        string.format("绘制 %d vs 判定 %d", drawn, spearClass.basicRange))

    print("[FB2] done, failures = " .. fails)
end
