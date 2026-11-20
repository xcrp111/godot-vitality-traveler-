-- DevAimEvent.lua — 走真实事件链验证「拖动选方向」
-- 用 SendEvent 派发 MouseButtonDown / MouseMove / MouseButtonUp，
-- 经过 main 的真实处理函数（含 UI.ToDesign 坐标换算）→ Combat.AimPointer
local Config = require "Config"
local Save = require "Save"
local S = require "State"
local Run = require "Run"
local Combat = require "Combat"

local fails = 0
local function check(name, cond, detail)
    if cond then
        print("[AimEv] OK   " .. name)
    else
        fails = fails + 1
        print("[AimEv] FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
    end
end

local function angDiff(a, b)
    local d = (a - b) % (math.pi * 2)
    if d > math.pi then d = d - math.pi * 2 end
    return math.abs(d)
end

-- 设计坐标 -> 物理像素（UI.ToDesign 的逆运算）
local function ToPhysical(dx, dy)
    return (dx * S.scale + S.offX) * S.dpr, (dy * S.scale + S.offY) * S.dpr
end

local function Send(name, dx, dy, button)
    local px, py = ToPhysical(dx, dy)
    local ok, err = pcall(function()
        local vm = VariantMap()
        vm["X"] = math.floor(px)
        vm["Y"] = math.floor(py)
        vm["DX"] = 0
        vm["DY"] = 0
        vm["Button"] = button or MOUSEB_LEFT
        vm["Buttons"] = 1
        vm["Qualifiers"] = 0
        vm["Wheel"] = 0
        vm["TouchID"] = 0
        SendEvent(name, vm)
    end)
    if not ok then print("[AimEv] SendEvent 失败 " .. name .. ": " .. tostring(err)) end
    return ok
end

function Start()
    require "main"
    local mainStart = Start   -- main.lua 的全局 Start
    if type(mainStart) == "function" then mainStart() end

    -- 换一个和设计分辨率不同的窗口尺寸，验证 ToDesign 换算
    S.W, S.H = 1600, 900
    S.scale = math.min(S.W / Config.DESIGN_W, S.H / Config.DESIGN_H)
    S.offX = (S.W - Config.DESIGN_W * S.scale) / 2
    S.offY = (S.H - Config.DESIGN_H * S.scale) / 2
    print(string.format("[AimEv] 窗口 %.0fx%.0f scale=%.3f off=(%.1f,%.1f) dpr=%s",
        S.W, S.H, S.scale, S.offX, S.offY, tostring(S.dpr)))

    S.data = Save.Load()
    Save.SetClass(S.data, "ranger")
    Save.SetClassLevel(S.data, 10)
    Config.SetClass("ranger")
    Run.Start(3, true)
    S.run.loadout = { 3, 4, 5 }
    local cs = Combat.Start(S.run, "standard", 1)
    S.combat = cs
    S.screen = "combat"
    cs.enemies = {}
    cs.walls = {}
    cs.waves = { {} }
    cs.waveIndex = 1
    cs.anim = nil
    cs.player.cooldowns = {}
    cs.player.charges = {}
    cs.player.freeCharges = {}
    Combat.SpawnWave(cs, { minion = 1 })
    local en = cs.enemies[1]
    if en then
        en.hp, en.maxHp = 99999, 99999
        en.x, en.y = cs.player.x - 200, cs.player.y
    end

    -- 技能 1 键位置（和 ACTION_BUTTONS 一致）
    local bx, by = 1080, 624
    cs.facing = 0
    Send("MouseButtonDown", bx, by)
    check("按下进入瞄准", cs.aim ~= nil)
    Send("MouseMove", bx + 40, by - 90)
    Send("MouseMove", bx + 40, by - 90)
    check("拖动记录到移动", cs.aim and cs.aim.moved == true,
        cs.aim and tostring(cs.aim.moved))
    local want = math.atan(-90, 40)
    check("拖动角度跟上", cs.aim and angDiff(cs.aim.angle or 0, want) < 0.06,
        cs.aim and tostring(cs.aim.angle))
    Send("MouseButtonUp", bx + 40, by - 90)
    check("松手按拖动方向出手", angDiff(cs.facing or 0, want) < 0.06,
        tostring(cs.facing))
    check("技能进入冷却", (cs.player.cooldowns[3] or 0) > 0,
        tostring(cs.player.cooldowns[3]))

    print(string.format("[AimEv] done, failures = %d", fails))
end

