-- DevJoystick.lua — 自绘虚拟摇杆：固定 / 浮动 / 拖尾跟随 / 死区 / 释放
local Config = require "Config"
local Save = require "Save"
local S = require "State"
local Run = require "Run"
local Combat = require "Combat"

local fails = 0
local function check(name, cond, detail)
    if cond then
        print("[Joy] OK   " .. name)
    else
        fails = fails + 1
        print("[Joy] FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
    end
end

local function NewCombat(mode, follow)
    S.data.joyMode = mode
    S.data.joyFollow = follow
    Run.Start(1)
    local cs = Combat.Start(S.run, "standard", 1)
    S.screen = "combat"
    cs.enemies = {}
    cs.walls = {}
    cs.waves = { {} }
    cs.waveIndex = 1
    return cs
end

function Start()
    S.data = Save.Load()
    Save.SetClass(S.data, "swordsman")
    Save.SetClassLevel(S.data, 5)
    Config.SetClass("swordsman")
    Save.ResetLayout(S.data)

    -- ================= 固定模式 =================
    local cs = NewCombat("fixed", false)
    local js = cs.joystick
    check("固定模式生效", js.mode == "fixed")
    check("摇杆已创建", js ~= nil and js.baseX ~= nil)

    Combat.JoystickPointer("down", js.baseX, js.baseY - 70)
    check("按下后激活", js.active == true)
    check("向上推 y 为负", S.input.y < -0.5, S.input.y)
    check("向上推 x 接近 0", math.abs(S.input.x) < 0.05, S.input.x)

    Combat.JoystickPointer("move", js.baseX, js.baseY + 70)
    check("向下推 y 为正", S.input.y > 0.5, S.input.y)

    Combat.JoystickPointer("move", js.baseX - 70, js.baseY)
    check("向左推 x 为负", S.input.x < -0.5, S.input.x)

    Combat.JoystickPointer("move", js.baseX + 2, js.baseY + 2)
    check("死区内归零", S.input.x == 0 and S.input.y == 0, S.input.x .. "," .. S.input.y)

    Combat.JoystickPointer("move", js.baseX, js.baseY - js.radius * 0.35)
    check("轻推就有速度", S.input.y < -0.45, S.input.y)

    Combat.JoystickPointer("up", js.baseX, js.baseY)
    check("松手后清零", S.input.x == 0 and S.input.y == 0)
    check("松手后取消激活", js.active == false)

    local eaten = Combat.JoystickPointer("down", 900, 200)
    check("固定模式区域外不吃输入", eaten == false)

    -- 拖尾关：拖出圈外基座不动
    local baseX0 = js.baseX
    Combat.JoystickPointer("down", js.baseX, js.baseY)
    Combat.JoystickPointer("move", js.baseX + 400, js.baseY)
    check("拖尾关闭时基座不动", math.abs(js.baseX - baseX0) < 0.01, js.baseX)
    Combat.JoystickPointer("up", 0, 0)

    -- ================= 拖尾跟随 =================
    cs = NewCombat("fixed", true)
    js = cs.joystick
    baseX0 = js.baseX
    Combat.JoystickPointer("down", js.baseX, js.baseY)
    Combat.JoystickPointer("move", js.baseX + 400, js.baseY)
    check("拖尾开启时基座跟随", js.baseX > baseX0 + 100, js.baseX)
    check("拖尾时仍是满速", math.abs(S.input.x - 1) < 0.05, S.input.x)
    Combat.JoystickPointer("up", 0, 0)
    check("松手后基座回锚点", math.abs(js.baseX - js.anchorX) < 0.01, js.baseX)

    -- ================= 浮动（按下即定位） =================
    cs = NewCombat("float", true)
    js = cs.joystick
    check("浮动模式生效", js.mode == "float")

    -- 左半屏任意位置按下
    Combat.JoystickPointer("down", 300, 300)
    check("按下即定位", js.active and js.baseX == 300 and js.baseY == 300,
        js.baseX .. "," .. js.baseY)
    check("刚按下时无输入", S.input.x == 0 and S.input.y == 0)

    Combat.JoystickPointer("move", 300, 230)
    check("浮动后向上推有效", S.input.y < -0.4, S.input.y)

    Combat.JoystickPointer("up", 300, 230)
    check("浮动松手回锚点", math.abs(js.baseX - js.anchorX) < 0.01, js.baseX)
    check("浮动松手清零", S.input.x == 0 and S.input.y == 0)

    -- 右半屏（技能区）按下不应被摇杆吃掉
    local eaten2 = Combat.JoystickPointer("down", 1100, 500)
    check("浮动模式右半屏不吃输入", eaten2 == false)

    -- 顶部 HUD 区域也不吃
    local eaten3 = Combat.JoystickPointer("down", 200, 100)
    check("浮动模式顶部不吃输入", eaten3 == false)

    -- 实际移动
    local p = cs.player
    local y0 = p.y
    Combat.JoystickPointer("down", 300, 400)
    Combat.JoystickPointer("move", 300, 330)
    for _ = 1, 20 do Combat.Update(1 / 60) end
    check("浮动摇杆能推角色移动", p.y < y0 - 5, string.format("%.1f -> %.1f", y0, p.y))
    Combat.JoystickPointer("up", 300, 330)

    -- ================= 多指隔离（右手点技能不能打断左手摇杆） =================
    cs = NewCombat("float", true)
    js = cs.joystick

    Combat.JoystickPointer("down", 300, 400, 1)     -- 左手按摇杆
    Combat.JoystickPointer("move", 300, 330, 1)
    local heldY = S.input.y
    check("左手按下并推动", heldY < -0.4, heldY)

    -- 右手按技能键（右半屏）并移动
    local eatenSkill = Combat.JoystickPointer("down", 1100, 520, 2)
    check("技能手指不抢摇杆", eatenSkill == false)
    Combat.JoystickPointer("move", 900, 200, 2)
    check("技能手指移动不影响方向", math.abs(S.input.y - heldY) < 0.0001,
        string.format("%.3f vs %.3f", S.input.y, heldY))

    -- 技能手指抬起，摇杆不能跟着释放
    Combat.JoystickPointer("up", 0, 0, 2)
    check("技能手指抬起不释放摇杆", js.active == true)
    check("摇杆方向仍在", math.abs(S.input.y - heldY) < 0.0001, S.input.y)

    -- 摇杆手指继续控制
    Combat.JoystickPointer("move", 300, 430, 1)
    check("摇杆手指仍能改方向", S.input.y > 0.4, S.input.y)

    -- 摇杆手指抬起才释放
    Combat.JoystickPointer("up", 0, 0, 1)
    check("摇杆手指抬起才释放", js.active == false and S.input.x == 0 and S.input.y == 0)

    -- 已经在控制时，第二根手指按在左半屏也不应重置基座
    Combat.JoystickPointer("down", 300, 400, 1)
    local baseY = js.baseY
    Combat.JoystickPointer("down", 500, 500, 3)
    check("第二根手指不重设摇杆", js.baseY == baseY and js.touchId == 1, js.baseY .. "/" .. tostring(js.touchId))
    Combat.JoystickPointer("up", 0, 0, 1)

    -- 全新存档的默认值
    local fresh = Save.Fresh()
    check("默认模式是浮动", fresh.joyMode == "float", fresh.joyMode)
    check("默认开启拖尾跟随", fresh.joyFollow ~= false, tostring(fresh.joyFollow))

    print("[Joy] done, failures = " .. fails)
end
