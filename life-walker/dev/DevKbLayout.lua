-- DevKbLayout.lua — 按键布局：默认值、拖动、缩放、边界、存档、战斗内生效
local Config = require "Config"
local Save = require "Save"
local S = require "State"
local Run = require "Run"
local Combat = require "Combat"
local KbLayout = require "KbLayout"

local fails = 0
local function check(name, cond, detail)
    if cond then
        print("[KB] OK   " .. name)
    else
        fails = fails + 1
        print("[KB] FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
    end
end

function Start()
    S.data = Save.Load()
    Save.SetClass(S.data, "swordsman")
    Save.SetClassLevel(S.data, 5)
    Config.SetClass("swordsman")
    Save.ResetLayout(S.data)   -- 每次从默认布局开始，测试可重复
    S.data.joyMode = "fixed"   -- 这一组测的是布局位置，用固定摇杆更直观

    local L = Save.Layout(S.data)
    check("默认摇杆位置", L.joy.x == 140 and L.joy.y == 578 and L.joy.r == 74,
        L.joy.x .. "," .. L.joy.y .. "," .. L.joy.r)
    check("默认普攻位置", L.attack.x == 1186 and L.attack.r == 48, L.attack.x .. "," .. L.attack.r)

    -- 打开编辑器
    KbLayout.Open()
    check("编辑器已打开", KbLayout.IsOpen() == true)

    -- 点选摇杆并拖到 (300, 400)
    KbLayout.Pointer("down", L.joy.x, L.joy.y)
    KbLayout.Pointer("move", 300, 400)
    KbLayout.Pointer("up", 300, 400)
    check("拖动后摇杆位置更新", L.joy.x == 300 and L.joy.y == 400, L.joy.x .. "," .. L.joy.y)

    -- 拖出边界应被夹住
    KbLayout.Pointer("down", 300, 400)
    KbLayout.Pointer("move", -500, -500)
    KbLayout.Pointer("up", -500, -500)
    check("越界被夹住", L.joy.x == L.joy.r and L.joy.y == L.joy.r, L.joy.x .. "," .. L.joy.y)

    -- 选中技能1 放大
    KbLayout.Pointer("down", L.skill1.x, L.skill1.y)
    local r0 = L.skill1.r
    KbLayout.Pointer("down", 236, 94)   -- 工具栏「放大」按钮
    check("放大生效", L.skill1.r > r0, L.skill1.r .. " vs " .. r0)
    KbLayout.Pointer("down", 236, 94)
    check("可连续放大", L.skill1.r > r0, L.skill1.r)

    -- 缩小
    local r1 = L.skill1.r
    KbLayout.Pointer("down", 100, 94)   -- 「缩小」
    check("缩小生效", L.skill1.r < r1, L.skill1.r .. " vs " .. r1)

    -- 重置（注意：ResetLayout 会换掉整张表，要重新取一次）
    KbLayout.Pointer("down", 372, 94)   -- 「重置」
    L = Save.Layout(S.data)
    check("重置回默认", L.joy.x == 140 and L.skill1.r == 36, L.joy.x .. "," .. L.skill1.r)

    -- 改一个位置后完成，检查存档里写进去了
    KbLayout.Pointer("down", L.joy.x, L.joy.y)
    KbLayout.Pointer("move", 220, 520)
    KbLayout.Pointer("up", 220, 520)
    KbLayout.Pointer("down", 1160, 94)  -- 「完成」
    check("完成后关闭", KbLayout.IsOpen() == false)
    check("存档里保留布局", type(S.data.layout) == "table" and S.data.layout.joy.x == 220,
        S.data.layout and S.data.layout.joy.x)

    -- 战斗里生效
    Run.Start(1)
    local cs = Combat.Start(S.run, "standard", 1)
    S.screen = "combat"
    cs.enemies = {}
    cs.walls = {}
    cs.waves = { {} }
    cs.waveIndex = 1
    check("战斗摇杆用新位置", cs.joystick.baseX == 220 and cs.joystick.baseY == 520,
        cs.joystick.baseX .. "," .. cs.joystick.baseY)

    local bx, by, br = Combat.CtrlPos("attack", 0, 0, 0)
    check("普攻按钮取布局值", bx == 1186 and br == 48, bx .. "," .. br)

    -- 摇杆仍能正常推动（向上推 -> y 变小）
    local p = cs.player
    local py0 = p.y
    Combat.JoystickPointer("down", 220, 480)
    for _ = 1, 15 do Combat.Update(1 / 60) end
    check("改用新位置后摇杆可用", p.y < py0, string.format("%.1f -> %.1f", py0, p.y))
    Combat.JoystickPointer("up", 220, 480)

    -- 取消施法框也能在布局编辑器里拖位置、调大小
    KbLayout.Open()
    local dz = Combat.AimCancelRect()
    check("取消框有默认位置", dz.w > 100 and dz.h > 60, string.format("%.0f x %.0f", dz.w, dz.h))
    KbLayout.Pointer("down", dz.x + dz.w / 2, dz.y + dz.h / 2)   -- 选中它
    KbLayout.Pointer("move", 900, 300)
    KbLayout.Pointer("up", 900, 300)
    local moved = Combat.AimCancelRect()
    check("取消框能拖动",
        math.abs((moved.x + moved.w / 2) - 900) < 2 and math.abs((moved.y + moved.h / 2) - 300) < 2,
        string.format("%.0f,%.0f", moved.x + moved.w / 2, moved.y + moved.h / 2))
    local w0 = moved.w
    KbLayout.Pointer("down", 176 + 60, 72 + 22)                 -- 「放大」
    local bigger = Combat.AimCancelRect()
    check("取消框能调大小", bigger.w > w0, string.format("%.0f -> %.0f", w0, bigger.w))
    KbLayout.Pointer("down", 1160, 94)                          -- 「完成」

    print("[KB] done, failures = " .. fails)
end
