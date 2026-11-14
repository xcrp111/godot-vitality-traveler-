-- DevEnemyPath.lua — 敌人绕墙回归：角色站在墙正对面时，怪物要能绕过来
local Config = require "Config"
local Save = require "Save"
local S = require "State"
local Run = require "Run"
local Combat = require "Combat"
local VirtualControls = require "urhox-libs.UI.VirtualControls"

local fails = 0
local function check(name, cond, detail)
    if cond then
        print("[Path] OK   " .. name)
    else
        fails = fails + 1
        print("[Path] FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
    end
end

local function setupScene()
    Run.Start(1)
    local cs = Combat.Start(S.run, "standard", 1)
    -- 清掉随机地图，手工摆一堵墙：玩家在墙下方，敌人在墙上方
    cs.walls = {
        { x = 420, y = 260, w = 440, h = 60 },
    }
    cs.enemies = {}
    cs.bullets = {}
    local p = cs.player
    p.x, p.y = 640, 460
    local e = {
        id = "germ", kind = "minion", behavior = "chase",
        x = 640, y = 200, radius = 14, speed = 128,
        hp = 100, maxHp = 100, atk = 5, attackCd = 1,
        slowTimer = 0, hitFlash = 0, stagger = 0,
        crack = 0, crackTimer = 0, crackFlash = 0, hunt = 0, huntTimer = 0,
        penVulnTimer = 0, rootTimer = 0, slowPct = 0.4, burnStacks = 0,
    }
    cs.enemies[1] = e
    S.screen = "combat"
    return cs, p, e
end

function Start()
    local dpr = graphics:GetDPR()
    if not dpr or dpr <= 0 then dpr = 1 end
    S.dpr = dpr
    S.W = graphics:GetWidth() / dpr
    S.H = graphics:GetHeight() / dpr
    S.scale = math.min(S.W / Config.DESIGN_W, S.H / Config.DESIGN_H)
    S.offX = (S.W - Config.DESIGN_W * S.scale) / 2
    S.offY = (S.H - Config.DESIGN_H * S.scale) / 2
    VirtualControls.Initialize(Config.DESIGN_W, Config.DESIGN_H)
    S.data = Save.Load()
    Save.SetClassLevel(S.data, 5)

    _DBGNAV = true
    local cs, p, e = setupScene()
    local startDist = math.sqrt((e.x - p.x) ^ 2 + (e.y - p.y) ^ 2)

    -- 跑 4 秒：如果会绕墙，敌人应该明显接近玩家
    local dt = 1 / 60
    local minDist = startDist
    local touchedWall = false
    for _ = 1, 480 do
        cs.enemies[1] = e
        Combat.Update(dt)
        local d = math.sqrt((e.x - p.x) ^ 2 + (e.y - p.y) ^ 2)
        if d < minDist then minDist = d end
        for _, w in ipairs(cs.walls) do
            if e.x > w.x - e.radius and e.x < w.x + w.w + e.radius
                and e.y > w.y - e.radius and e.y < w.y + w.h + e.radius then
                touchedWall = true
            end
        end
    end

    check("初始距离 260", math.abs(startDist - 260) < 1, startDist)
    check("8 秒内接近到近身（<120）", minDist < 120, string.format("minDist=%.0f", minDist))
    check("确实被墙挡过（不是走了空路）", touchedWall)

    -- 再验证：敌人没有被挤进墙里
    local inside = false
    for _, w in ipairs(cs.walls) do
        if e.x > w.x + 1 and e.x < w.x + w.w - 1
            and e.y > w.y + 1 and e.y < w.y + w.h - 1 then
            inside = true
        end
    end
    check("敌人没有卡在墙体内部", not inside,
        string.format("e=(%.0f,%.0f)", e.x, e.y))

    print(string.format("[Path] done, failures = %d", fails))
end
