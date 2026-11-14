-- DevAim.lua — 施法瞄准回归：点按=自动索敌、拖动=手动选方向
-- 复现用户反馈：按住技能键拖动后松手，技能必须朝拖动方向，不能被自动索敌覆盖
local Config = require "Config"
local Save = require "Save"
local S = require "State"
local Run = require "Run"
local Combat = require "Combat"

local fails = 0
local function check(name, cond, detail)
    if cond then
        print("[Aim] OK   " .. name)
    else
        fails = fails + 1
        print("[Aim] FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
    end
end

local function angDiff(a, b)
    local d = (a - b) % (math.pi * 2)
    if d > math.pi then d = d - math.pi * 2 end
    return math.abs(d)
end

-- 技能键（和 Combat.ACTION_BUTTONS 一致）
local SK = {
    [1] = { x = 1080, y = 624 },
    [2] = { x = 1110, y = 526 },
    [3] = { x = 1202, y = 514 },
}

local function NewCombat(loadout, class)
    S.data = Save.Load()
    Save.SetClass(S.data, class or "ranger")
    Save.SetClassLevel(S.data, 10)
    Config.SetClass(class or "ranger")
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
    cs.player.charges = {}
    cs.player.freeCharges = {}
    cs.player.energy = 999
    cs.player.mp = 999
    return cs
end

--- 放一个敌人在玩家左侧，用来验证自动索敌方向 = π
local function EnemyLeft(cs)
    cs.enemies = {}
    local p = cs.player
    Combat.SpawnWave(cs, { minion = 1 })
    local en = cs.enemies[1]
    if en then
        en.hp, en.maxHp = 99999, 99999
        en.x, en.y = p.x - 200, p.y
    end
    return en
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

    -- 游侠：3=穿魂狙击(dir) 4=凝固寒箭(point) 5=箭影连射(dir)
    local cs = NewCombat({ 3, 4, 5 })

    -- 1) 拖动：按下技能键 3，往右上拖，松手 → 朝向必须是拖的方向（约 -45°）
    EnemyLeft(cs)
    cs.facing = 0
    local b = SK[1]
    local hitDown = Combat.AimPointer("down", b.x, b.y, 0)
    check("按下技能键进入瞄准", hitDown == true and S.combat.aim ~= nil)
    Combat.AimPointer("move", b.x + 40, b.y - 90, 0)
    check("拖动后有角度", S.combat.aim and S.combat.aim.moved == true,
        S.combat.aim and tostring(S.combat.aim.moved))
    local want = math.atan(-90, 40)
    local faced = S.combat.aim and S.combat.aim.angle
    check("拖动角度正确", faced and angDiff(faced, want) < 0.05,
        tostring(faced) .. " vs " .. tostring(want))
    Combat.AimPointer("up", b.x + 40, b.y - 90, 0)
    check("松手后按拖动方向出手", angDiff(cs.facing or 0, want) < 0.05,
        tostring(cs.facing) .. " vs " .. tostring(want))
    check("技能真的放出去了（进冷却）", (cs.player.cooldowns[3] or 0) > 0,
        tostring(cs.player.cooldowns[3]))

    -- 2) 点按：按下立刻松手 → 自动索敌
    --    敌人放在正左，玩家朝左上（差 60°，在自动索敌锥内），松手后应自动转头锁定敌人
    cs = NewCombat({ 3, 4, 5 })
    EnemyLeft(cs)
    cs.facing = math.rad(120)
    b = SK[1]
    Combat.AimPointer("down", b.x, b.y, 0)
    Combat.AimPointer("up", b.x, b.y, 0)
    check("点按走自动索敌", angDiff(cs.facing or 0, math.pi) < 0.15,
        tostring(cs.facing))
    check("点按也放出了技能", (cs.player.cooldowns[3] or 0) > 0,
        tostring(cs.player.cooldowns[3]))

    -- 3) 连射(dir) 同样拖动生效
    cs = NewCombat({ 3, 4, 5 })
    EnemyLeft(cs)
    b = SK[3]      -- slot3 = 技能5 箭影连射
    local want2 = math.atan(70, -80)   -- 往左下拖
    Combat.AimPointer("down", b.x, b.y, 0)
    Combat.AimPointer("move", b.x - 80, b.y + 70, 0)
    Combat.AimPointer("up", b.x - 80, b.y + 70, 0)
    check("连射拖动生效", angDiff(cs.facing or 0, want2) < 0.08,
        tostring(cs.facing) .. " vs " .. tostring(want2))

    -- 4) 选位技能：拖动后 aimPoint 落在拖动方向上
    cs = NewCombat({ 3, 4, 5 })
    EnemyLeft(cs)
    local castPoint
    local realCast = Combat.CastSkillNow
    b = SK[2]      -- slot2 = 技能4 凝固寒箭(point)
    Combat.AimPointer("down", b.x, b.y, 0)
    Combat.AimPointer("move", b.x, b.y - 100, 0)
    local aim = S.combat.aim
    check("选位技能拖动后有点位", aim and aim.point and aim.point.x ~= nil)
    if aim and aim.point then
        local p = cs.player
        check("选位技能点位在玩家上方",
            aim.point.y < p.y - 10 and math.abs(aim.point.x - p.x) < 30,
            string.format("(%.1f,%.1f) player(%.1f,%.1f)", aim.point.x, aim.point.y, p.x, p.y))
    end
    Combat.AimPointer("up", b.x, b.y - 100, 0)
    check("选位技能放下了", (cs.player.cooldowns[4] or 0) > 0,
        tostring(cs.player.cooldowns[4]))

    -- 5) 法师：火球(dir) + 闪电链(point) 同样要能拖动选方向
    cs = NewCombat({ 1, 5, 6 }, "mage")   -- 1=火球(dir) 5=闪电链(point) 6=烈焰冲击(dir)
    EnemyLeft(cs)
    b = SK[1]
    local wantM = math.atan(90, -60)  -- 往左下拖
    Combat.AimPointer("down", b.x, b.y, 0)
    Combat.AimPointer("move", b.x - 60, b.y + 90, 0)
    Combat.AimPointer("up", b.x - 60, b.y + 90, 0)
    check("法师火球拖动生效", angDiff(cs.facing or 0, wantM) < 0.1,
        tostring(cs.facing) .. " vs " .. tostring(wantM))

    cs = NewCombat({ 1, 5, 6 }, "mage")
    EnemyLeft(cs)
    b = SK[2]                          -- slot2 = 闪电链（选位）
    Combat.AimPointer("down", b.x, b.y, 0)
    Combat.AimPointer("move", b.x + 90, b.y, 0)
    local aimM = S.combat.aim
    check("法师选位拖动有点位", aimM and aimM.point and aimM.point.x > cs.player.x,
        aimM and aimM.point and string.format("%.0f>%.0f", aimM.point.x, cs.player.x))
    Combat.AimPointer("up", b.x + 90, b.y, 0)

    print(string.format("[Aim] done, failures = %d", fails))
end
