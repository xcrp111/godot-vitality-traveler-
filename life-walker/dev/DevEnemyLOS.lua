-- DevEnemyLOS.lua — 敌人视线回归：被墙挡住时不隔墙输出，先绕位
local Config = require "Config"
local Save = require "Save"
local S = require "State"
local Run = require "Run"
local Combat = require "Combat"

local fails = 0
local function check(name, cond, detail)
    if cond then
        print("[Los] OK   " .. name)
    else
        fails = fails + 1
        print("[Los] FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
    end
end

local function Enemy(kind, behavior, x, y, radius)
    return {
        id = kind, kind = kind, behavior = behavior,
        x = x, y = y, radius = radius or 14, speed = 120,
        hp = 9999, maxHp = 9999, atk = 3, attackCd = 0, shootCd = 0,
        slowTimer = 0, hitFlash = 0, stagger = 0,
        crack = 0, crackTimer = 0, crackFlash = 0, hunt = 0, huntTimer = 0,
        penVulnTimer = 0, rootTimer = 0, slowPct = 0.4, burnStacks = 0,
    }
end

local function NewCombat(walls, px, py)
    S.data = Save.Load()
    Run.Start(1, true)
    local cs = Combat.Start(S.run, "standard", 1)
    S.screen = "combat"
    cs.walls = walls or {}
    cs.enemies, cs.bullets, cs.projs, cs.waves, cs.waveIndex = {}, {}, {}, { {} }, 1
    cs.player.x, cs.player.y = px, py
    cs.player.hp = cs.player.maxHp
    cs.player.invulnTimer = 0
    cs.player.shield = 0
    return cs
end

local dt = 1 / 60

-- 1) 射手：墙后有视线遮挡时不应该开火
do
    local cs = NewCombat({ { x = 600, y = 200, w = 40, h = 240 } }, 660, 320)
    local e = Enemy("spitter", "shooter", 580, 320, 14)
    cs.enemies[1] = e
    local blockedBullets = 0
    for _ = 1, 30 do
        Combat.Update(dt)
        blockedBullets = math.max(blockedBullets, #cs.bullets)
    end
    check("射手被墙挡住时不隔墙开火", blockedBullets == 0, blockedBullets)
    -- 它应该往能看见玩家的方向移动（不是原地发呆）
    check("射手被挡时会绕位（坐标发生变化）",
        math.abs(e.x - 580) > 2 or math.abs(e.y - 320) > 2,
        string.format("e=(%.0f,%.0f)", e.x, e.y))
    -- 绕到能看见之后就该恢复开火
    local later = 0
    for _ = 1, 420 do
        Combat.Update(dt)
        later = math.max(later, #cs.bullets)
    end
    check("射手绕出视线后会恢复输出", later > 0, later)
end

-- 2) 射手：视线通畅时正常开火
do
    local cs = NewCombat({}, 660, 320)
    local e = Enemy("spitter", "shooter", 580, 320, 14)
    cs.enemies[1] = e
    local maxBullets = 0
    for _ = 1, 180 do
        Combat.Update(dt)
        maxBullets = math.max(maxBullets, #cs.bullets)
    end
    check("射手视线通畅时会开火", maxBullets > 0, maxBullets)
end

-- 3) 近战：贴得很近但隔着墙，不该造成伤害
do
    local cs = NewCombat({ { x = 620, y = 280, w = 20, h = 80 } }, 650, 320)
    local e = Enemy("germ", "chase", 610, 320, 20)
    cs.enemies[1] = e
    local hp0 = cs.player.hp
    for _ = 1, 20 do Combat.Update(dt) end
    check("近战不隔墙挥击（玩家不掉血）", cs.player.hp >= hp0, hp0 - cs.player.hp)
    check("近战会绕路而不是贴墙站桩",
        math.abs(e.x - 610) > 2 or math.abs(e.y - 320) > 2,
        string.format("e=(%.0f,%.0f)", e.x, e.y))
    -- 绕过去以后照常能打
    local hitLater = false
    for _ = 1, 300 do
        Combat.Update(dt)
        if cs.player.hp < hp0 then hitLater = true end
    end
    check("近战绕过去后能正常攻击", hitLater, hp0 - cs.player.hp)
end

-- 4) 近战：没有障碍时照常贴脸攻击
do
    local cs = NewCombat({}, 650, 320)
    local e = Enemy("germ", "chase", 610, 320, 20)
    cs.enemies[1] = e
    local hp0 = cs.player.hp
    for _ = 1, 180 do Combat.Update(dt) end
    check("无障碍时近战正常造成伤害", cs.player.hp < hp0, hp0 - cs.player.hp)
end

print(string.format("[Los] done, failures = %d", fails))
