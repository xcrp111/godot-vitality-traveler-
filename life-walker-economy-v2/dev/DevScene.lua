-- DevScene.lua — 主界面场景回归（走路动画 / 静止 / 相机跟随 / 碰撞 / 交互 / 面板）
-- 运行：把本文件复制到 scripts/ 再以 DevScene.lua 作入口（引擎只认 scripts/ 下的脚本名）：
--   Copy-Item dev/DevScene.lua scripts/DevScene.lua -Force
--   cd .cli
--   UrhoXRuntime.exe DevScene.lua "-tapcode_dir=<项目根>" -tool_mode -x 640 -y 360
local Config = require "Config"
local Save = require "Save"
local S = require "State"
local SceneUI = require "SceneUI"

local fails = 0
local function check(name, cond, detail)
    if cond then
        print("[Scene] OK   " .. name)
    else
        fails = fails + 1
        print("[Scene] FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
    end
end

local function Reset(wx, wy)
    S.scene = { wx = wx, wy = wy, facing = 1, frame = 0, animT = 0, moving = false, grid = false }
    S.screen = "menu"
    S.panelMode = nil
    S.input.x, S.input.y = 0, 0
end

local function Walk(frames, dt)
    dt = dt or 1 / 60
    for _ = 1, frames do SceneUI.Update(dt) end
end

function Start()
    S.data = Save.Load()
    Config.SetClass("mage")
    print("[Scene] begin")

    -- ---------------------------------------------------------------- 精灵表配置
    local walk, idle = SceneUI.HERO.walk, SceneUI.HERO.idle
    check("走路是 9 帧", walk.frames == 9, walk.frames)
    check("走路帧宽 = 6000 / 9", math.abs(walk.fw - 6000 / 9) < 0.01, walk.fw)
    check("走路锚点数量等于帧数", #walk.anchors == walk.frames, #walk.anchors)
    check("待机是 6 帧", idle.frames == 6, idle.frames)
    check("待机锚点数量等于帧数", #idle.anchors == idle.frames, #idle.anchors)
    check("走路与待机锚点不共用", walk.anchors ~= idle.anchors)

    -- ---------------------------------------------------------------- 移动 → 走路动画
    Reset(1100, 700)
    S.input.x, S.input.y = 1, 0
    Walk(2)
    local sc = S.scene
    check("有输入时进入移动状态", sc.moving == true)
    check("朝向随输入翻转", sc.facing == 1, sc.facing)

    local framesSeen = {}
    local x0 = sc.wx
    for _ = 1, 90 do
        Walk(1)
        framesSeen[sc.frame] = true
    end
    check("走路动画循环到多帧", (function()
        local n = 0
        for _ in pairs(framesSeen) do n = n + 1 end
        return n >= 7
    end)(), "seen " .. tostring(#framesSeen))
    check("走路时角色真的在移动", sc.wx > x0 + 20, string.format("%.1f -> %.1f", x0, sc.wx))
    check("帧号始终在合法范围", sc.frame >= 0 and sc.frame < walk.frames, sc.frame)

    S.input.x, S.input.y = -1, 0
    Walk(2)
    check("向左走时朝向翻转", sc.facing == -1, sc.facing)

    -- ---------------------------------------------------------------- 无输入 → 保持静止
    S.input.x, S.input.y = 0, 0
    Walk(1)
    local fx, fy = sc.wx, sc.wy
    check("松手当帧退出走路", sc.moving == false)
    check("松手回到待机第 0 帧", sc.frame == 0, sc.frame)
    Walk(60)
    check("静止时不再移动", sc.wx == fx and sc.wy == fy,
        string.format("%.1f,%.1f -> %.1f,%.1f", fx, fy, sc.wx, sc.wy))
    check("静止时帧号保持 0", sc.frame == 0, sc.frame)
    check("静止时动画计时清零（不会偷偷推进）", sc.animT < 0.0001, sc.animT)

    -- ---------------------------------------------------------------- 相机跟随
    local camX, camY = SceneUI.Camera()
    check("相机把人物放在屏幕正中 x", math.abs((sc.wx - camX) - 1280 / 2) < 0.01, sc.wx - camX)
    check("相机把人物放在屏幕正中 y", math.abs((sc.wy - camY) - 720 / 2) < 0.01, sc.wy - camY)
    Reset(300, 900)
    Walk(1)
    camX, camY = SceneUI.Camera()
    check("换位置后仍是正中", math.abs((S.scene.wx - camX) - 640) < 0.01 and
        math.abs((S.scene.wy - camY) - 360) < 0.01)

    -- ---------------------------------------------------------------- 碰撞：建筑挡人
    Reset(700, 600)
    S.input.x, S.input.y = 0, -1        -- 往左上大屋方向（700,78,452,384）走
    for _ = 1, 120 do Walk(1) end
    check("撞到建筑不会穿进去", S.scene.wy > 384 + 10, S.scene.wy)
    check("撞住后不出走路动画", S.scene.moving == false)

    -- 点击建筑内部 → 落点被挪到空地
    Reset(1300, 900)
    S.input.x, S.input.y = 0, 0
    local okClick = SceneUI.GroundClick(640, 360)
    check("点地面会被接受", okClick == true)
    check("点建筑内部时落点被修正", S.scene.targetX ~= nil)

    -- ---------------------------------------------------------------- 交互点
    Reset(300, 640)                    -- 生命之书在 (278, 583)
    Walk(1)
    check("靠近生命之书能互动", SceneUI.Interact() == true)
    check("生命之书只开角色面板", S.panelMode == "char", S.panelMode)

    S.panelMode = nil
    Reset(1337, 1210)                  -- 试炼之门在 (1337, 1212)
    Walk(1)
    check("靠近试炼之门能互动", SceneUI.Interact() == true)
    check("试炼之门开选关面板", S.panelMode == "levels", S.panelMode)

    S.panelMode = nil
    Reset(934, 900)                    -- 运动之泉在 (934, 858)
    Walk(1)
    check("靠近运动之泉能互动", SceneUI.Interact() == true)
    check("运动之泉开今日运动面板", S.panelMode == "sports", S.panelMode)

    -- ---------------------------------------------------------------- 面板打开时冻结
    Reset(1100, 700)
    S.input.x, S.input.y = 1, 0
    S.panelMode = "char"
    local px, py = S.scene.wx, S.scene.wy
    Walk(30)
    check("面板打开时人物不动", S.scene.wx == px and S.scene.wy == py)
    check("面板打开时没有走路状态", S.scene.moving == false)
    check("面板打开时互动被拦掉", SceneUI.Interact() == false)
    S.panelMode = nil

    -- ---------------------------------------------------------------- 世界边界
    Reset(70, 600)
    S.input.x, S.input.y = -1, 0
    for _ = 1, 60 do Walk(1) end
    check("不会走出可行走区域", S.scene.wx >= 70 - 0.01, S.scene.wx)

    print("[Scene] done, failures = " .. fails)
    engine:Exit()
end

function HandleUpdate() end
function HandleRender() end
