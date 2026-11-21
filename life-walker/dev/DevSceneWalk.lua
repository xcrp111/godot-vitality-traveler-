-- DevSceneWalk.lua — 主界面场景的移动 / 寻路
-- 背景：玩家反馈「角色无法正常移动」。两个原因：
--   1) 出生点在南侧门廊前的窄袋形区域，两侧石门塔的碰撞盒太高，左右几乎走不动
--   2) 点地面是直线移动，顶到墙 0.35 秒就放弃寻路 → 点哪都不动
-- 本脚本断言：出生点四方向都能走、点地面能绕障到达三个交互点、走不过去会明确失败。
-- 运行方式（在 .cli 目录下，先把本文件复制进 scripts/）：
--   UrhoXRuntime.exe _tmp_dev.lua "-tapcode_dir=<项目根>" -tool_mode -graphicsheadless \
--     -validate -validate-frames=5 -validate-timeout=30 "-validate-output=../.tmp/v.json"

local Config = require "Config"
local Save = require "Save"
local S = require "State"
local SceneUI = require "SceneUI"

require "main"     -- 拿全局输入处理器（测右键走路 / 左键不走路）

local fails = 0
local function check(name, cond, detail)
    if cond then
        print("[Walk] OK   " .. name)
    else
        fails = fails + 1
        print("[Walk] FAIL " .. name .. (detail ~= nil and (" — " .. tostring(detail)) or ""))
    end
end

local SPAWN_X, SPAWN_Y = 1337, 1248

local function mouseEvent(btn, x, y)
    return {
        Button = { GetInt = function() return btn end },
        X = { GetInt = function() return x end },
        Y = { GetInt = function() return y end },
    }
end

local function reset()
    local sc = S.scene
    sc.wx, sc.wy = SPAWN_X, SPAWN_Y
    sc.path, sc.approach, sc.stuck = nil, nil, 0
    S.panelMode = nil
    S.input.x, S.input.y = 0, 0
end

--- 按住某个方向走 frames 帧，返回位移
local function walkDir(dx, dy, frames)
    reset()
    local sx, sy = S.scene.wx, S.scene.wy
    S.input.x, S.input.y = dx, dy
    for _ = 1, frames do SceneUI.Update(1 / 60) end
    S.input.x, S.input.y = 0, 0
    return math.sqrt((S.scene.wx - sx) ^ 2 + (S.scene.wy - sy) ^ 2)
end

--- 点地面走到某个目标，返回 ok, 到位与否, 打开的 panel, 终点
local function walkTo(tx, ty, panel)
    reset()
    local ok = SceneUI.WalkTo(tx, ty, panel)
    if not ok then return false, false, nil end
    local arrived = false
    for _ = 1, 3600 do
        SceneUI.Update(1 / 60)
        if S.panelMode or not S.scene.path then arrived = true break end
    end
    return true, arrived, S.panelMode, S.scene.wx, S.scene.wy
end

function Start()
    S.data = Save.Load()
    Config.SetClass(Save.ActiveClass(S.data))
    S.screen = "menu"
    SceneUI.Init()
    reset()

    -- 1) 出生点没有被卡住
    check("网格 / 坐标辅助默认打开", S.scene.grid ~= false)
    check("出生点本身站得下", not SceneUI.Blocked(SPAWN_X, SPAWN_Y))
    check("出生点四方向都不是直接贴墙",
        not SceneUI.Blocked(SPAWN_X + 24, SPAWN_Y) and not SceneUI.Blocked(SPAWN_X - 24, SPAWN_Y)
        and not SceneUI.Blocked(SPAWN_X, SPAWN_Y - 24))

    -- 2) 四方向都能走出可见距离（0.5 秒 ≈ 122px）
    local up = walkDir(0, -1, 30)
    local down = walkDir(0, 1, 30)
    local left = walkDir(-1, 0, 30)
    local right = walkDir(1, 0, 30)
    check("向左能走", left > 30, string.format("%.1f", left))
    check("向右能走", right > 30, string.format("%.1f", right))
    check("向上能走", up > 30, string.format("%.1f", up))
    check("向下有空间（到地图下边为止）", down >= 10, string.format("%.1f", down))

    -- 3) 点地面：三个交互点都要能绕过去并自动打开面板
    local ok, arrived, panel = walkTo(1337, 1212 + 44 + 48, "levels")
    check("走到试炼之门并自动打开选关", ok and arrived and panel == "levels",
        string.format("ok=%s arrived=%s panel=%s", tostring(ok), tostring(arrived), tostring(panel)))

    ok, arrived, panel = walkTo(278, 583 + 38 + 48, "char")
    check("绕过喷泉/木桶走到生命之书", ok and arrived and panel == "char",
        string.format("ok=%s arrived=%s panel=%s", tostring(ok), tostring(arrived), tostring(panel)))

    ok, arrived, panel = walkTo(934, 858 + 40 + 48, "sports")
    check("走到运动之泉", ok and arrived and panel == "sports",
        string.format("ok=%s arrived=%s panel=%s", tostring(ok), tostring(arrived), tostring(panel)))

    -- 4) 走不过去的地方明确失败（不发呆也不无限卡住）
    reset()
    check("世界外坐标明确拒绝", SceneUI.WalkTo(-500, -500) == false)
    check("拒绝后没有残留寻路", S.scene.path == nil)

    -- 5) 走到广场中心（没有交互点，不应该弹面板）
    ok, arrived, panel = walkTo(1100, 700, nil)
    check("广场中心能到且不弹面板", ok and arrived and panel == nil,
        string.format("ok=%s arrived=%s panel=%s", tostring(ok), tostring(arrived), tostring(panel)))

    -- 5) 右键走路 / 左键不走路（左键留给 UI）
    reset()
    HandleMouseDown("MouseButtonDown", mouseEvent(MOUSEB_RIGHT or 2, 600, 380))
    check("右键点地面会寻路", S.scene.path ~= nil and #S.scene.path > 0)
    local rightTarget = S.scene.path and S.scene.path[#S.scene.path]
    check("右键落点在地面范围内", rightTarget ~= nil
        and rightTarget[2] >= 300 and rightTarget[2] <= SceneUI.WORLD_H)

    reset()
    HandleMouseDown("MouseButtonDown", mouseEvent(MOUSEB_LEFT or 1, 600, 380))
    check("左键不再触发走路", S.scene.path == nil)

    print(string.format("[Walk] done, failures = %d", fails))
end
