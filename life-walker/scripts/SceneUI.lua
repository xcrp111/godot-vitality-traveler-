-- SceneUI.lua — 主界面场景（相机跟随的可移动小人）
-- 素材来自 game-health（assets/art/）
--   art/home_bg.jpg     场景背景（2282x1280，世界坐标 = 背景像素坐标）
--   art/hero_idle.png   法师待机 6 帧（2081x561，每帧约 346.8x561）
--   art/hero_walk.png   法师走路 10 帧（6000x1000，每帧 600x1000）
-- 操作：WASD / 方向键移动，点击地面走过去，走近物件按 E（或点气泡）交互
--
-- 坐标系约定：世界坐标 = 背景图像素坐标（左上角 0,0，右下角 2282,1280）
-- 相机永远把人物放在屏幕正中；人物不会走出 GROUND 范围

local Config = require "Config"
local Save = require "Save"
local UI = require "UI"
local S = require "State"
local Art = require "Art"
local Economy = require "Economy"
local Pet = require "Pet"

local SceneUI = {}

-- ---------------------------------------------------------------- 世界与相机
SceneUI.WORLD_W = 2282
SceneUI.WORLD_H = 1280
local VIEW_W, VIEW_H = 1280, 720          -- 设计画布大小

local SPEED = 245                          -- 世界像素 / 秒
local GROUND = { minX = 70, maxX = 2212, minY = 300, maxY = 1266 }

-- ---------------------------------------------------------------- 人物精灵
-- 两张精灵表里角色本体的位置/大小都不一样：
--   idle：6 帧，帧宽 2081/6 ≈ 346.8，本体约 415px 高，脚底在 y≈497
--   walk：9 帧，帧宽 6000/9 ≈ 666.7，本体约 468px 高，脚底在 y≈701
--   注意 walk 是 9 帧不是 10 帧（6000 宽 ÷ 9 = 666.7，按 600 切会把相邻帧切进来）
-- 所以每帧都给一个「本体中心 x + 脚底 y」锚点：按 unitH 统一缩放，
-- 再把锚点钉在人物的世界坐标上 —— 待机和走路的高度、站位完全对得上，
-- 走路时也不会因为残影把角色推歪（源图每帧本体中心 x 在 327~332 之间小漂移）。
local HERO = {
    charH = 82,                            -- 角色本体在屏幕上的高度（设计像素）
    idle = {
        path = "art/hero_idle.png", frames = 6, fw = 2081 / 6, fh = 561,
        unitH = 414.8, fps = 5,
        anchors = {
            { 187.9, 497 }, { 196.8, 498 }, { 191.1, 490 },
            { 180.9, 498 }, { 176.5, 499 }, { 160.6, 496 },
        },
    },
    walk = {
        path = "art/hero_walk.png", frames = 9, fw = 6000 / 9, fh = 1000,
        unitH = 468.1, fps = 13,
        -- 锚点是扫描出来的：每帧本体重心 x + 统一脚底 y（F5 的 712 是脚后残影，不收进来，免得上下一跳）
        anchors = {
            { 330.7, 701 }, { 330.0, 701 }, { 328.6, 701 }, { 331.6, 701 },
            { 327.5, 701 }, { 330.1, 701 }, { 330.8, 701 }, { 327.0, 701 },
            { 332.4, 701 },
        },
    },
}
SceneUI.HERO = HERO

-- ---------------------------------------------------------------- 建筑碰撞盒
-- 全部按背景图像素量的（x, y, w, h），人物脚底不会踩进这些矩形
local OBSTACLES = {
    -- 大建筑
    { name = "左上大屋",   x = 700,  y = 78,   w = 452, h = 384 },
    { name = "右上大屋",   x = 1612, y = 100,  w = 420, h = 482 },
    { name = "石纪念碑",   x = 425,  y = 292,  w = 168, h = 332 },
    { name = "石门塔·左",  x = 1160, y = 952,  w = 150, h = 265 },
    { name = "石门塔·右",  x = 1365, y = 952,  w = 136, h = 265 },
    { name = "石门塔·上",  x = 1160, y = 952,  w = 341, h = 196 },
    { name = "院墙·左",    x = 1696, y = 770,  w = 30,  h = 245 },
    { name = "院墙·右",    x = 2048, y = 680,  w = 32,  h = 335 },
    { name = "院墙·下",    x = 1696, y = 978,  w = 384, h = 36  },
    { name = "院中祭坛",   x = 1788, y = 705,  w = 172, h = 205 },
    -- 院墙栅栏（左上大屋的院子，门口留了缺口）
    { name = "栅栏·竖",    x = 628,  y = 253,  w = 38,  h = 285 },
    { name = "栅栏·下左",  x = 628,  y = 494,  w = 190, h = 44  },
    { name = "栅栏·下右",  x = 995,  y = 494,  w = 165, h = 44  },
    { name = "木栅栏",     x = 1143, y = 885,  w = 380, h = 60  },
    -- 摆件
    { name = "喷泉",       x = 866,  y = 782,  w = 136, h = 145 },
    { name = "蓝水晶",     x = 772,  y = 874,  w = 162, h = 228 },
    { name = "书台",       x = 212,  y = 538,  w = 133, h = 90  },
    { name = "墓碑",       x = 524,  y = 715,  w = 98,  h = 142 },
    { name = "菜园",       x = 545,  y = 860,  w = 218, h = 168 },
    { name = "木桶三连",   x = 612,  y = 560,  w = 196, h = 76  },
    { name = "木桶二连",   x = 240,  y = 390,  w = 140, h = 112 },
    { name = "木箱·左",    x = 776,  y = 800,  w = 95,  h = 98  },
    { name = "木箱·右",    x = 1013, y = 803,  w = 86,  h = 98  },
    { name = "木箱·北",    x = 1506, y = 531,  w = 64,  h = 79  },
    { name = "大木桶",     x = 2048, y = 512,  w = 70,  h = 101 },
    { name = "灌木岩石",   x = 1440, y = 76,   w = 122, h = 78  },
    -- 大树
    { name = "左侧大树",   x = 0,    y = 600,  w = 320, h = 300 },
    { name = "左侧黄树",   x = 0,    y = 810,  w = 190, h = 250 },
    { name = "棕榈",       x = 150,  y = 925,  w = 140, h = 100 },
}

-- ---------------------------------------------------------------- 交互点
local SPOTS = {
    { id = "gate",   name = "试炼之门", icon = "门", x = 1337, y = 1212, r = 44,
      panel = "levels", hint = "进入关卡挑战", color = { 120, 200, 255 } },
    { id = "book",   name = "生命之书", icon = "书", x = 278,  y = 583,  r = 38,
      panel = "char",   hint = "查看角色",     color = { 255, 200, 120 } },
    { id = "sports", name = "运动之泉", icon = "泉", art = "art/icon_spring.png", x = 934,  y = 858,  r = 40,
      panel = "sports", hint = "今日运动与步数结算", color = { 120, 240, 170 } },
}

local START_X, START_Y = 1337, 1248

local function scene()
    if type(S.scene) ~= "table" then
        S.scene = { wx = START_X, wy = START_Y, facing = 1, frame = 0, animT = 0,
            moving = false, grid = true }
    end
    return S.scene
end

function SceneUI.Init()
    local sc = scene()
    if not sc.inited then
        sc.wx, sc.wy = START_X, START_Y
        sc.facing = 1
        sc.frame, sc.animT = 0, 0
        sc.moving = false
        sc.path = nil
        if sc.grid == nil then sc.grid = true end
        sc.inited = true
    end
end

--- 相机（世界坐标左上角）：人物永远在屏幕正中，不做边界夹取，靠镜像背景补齐画面
function SceneUI.Camera()
    local sc = scene()
    return sc.wx - VIEW_W / 2, sc.wy - VIEW_H / 2
end

-- ---------------------------------------------------------------- 碰撞
local FOOT_HW, FOOT_HH = 15, 17            -- 脚底碰撞盒半宽 / 高

local function blockedAt(wx, wy)
    local x1, y1 = wx - FOOT_HW, wy - FOOT_HH
    local x2, y2 = wx + FOOT_HW, wy
    for _, o in ipairs(OBSTACLES) do
        if x1 < o.x + o.w and x2 > o.x and y1 < o.y + o.h and y2 > o.y then
            return true
        end
    end
    return false
end

--- 某个世界坐标能不能站（调试 / 回归用）
---@param wx number
---@param wy number
---@return boolean
function SceneUI.Blocked(wx, wy)
    return blockedAt(wx, wy)
end

--- 从 (x, y) 往外找一个不被建筑挡住、且在可行走区域内的落点
---@return number|nil, number|nil
local function nearestFree(x, y, maxR)
    local function inGround(px, py)
        return px >= GROUND.minX and px <= GROUND.maxX
            and py >= GROUND.minY and py <= GROUND.maxY
    end
    if inGround(x, y) and not blockedAt(x, y) then return x, y end
    for r = 12, maxR or 160, 12 do
        for i = 0, 15 do
            local a = i / 16 * math.pi * 2
            local px = x + math.cos(a) * r
            local py = y + math.sin(a) * r
            if inGround(px, py) and not blockedAt(px, py) then
                return px, py
            end
        end
    end
    return nil, nil
end

-- ---------------------------------------------------------------- 寻路
-- 场景里是「点地面走过去」，但障碍物是一堆矩形：直线走会顶在墙上（旧版走 0.35 秒就放弃，
-- 看起来就是「点了不动」）。这里用 32px 网格做一次 BFS，再做视线平滑，沿路点走。
local PATH_STEP = 32

local function lineClear(x0, y0, x1, y1)
    local dx, dy = x1 - x0, y1 - y0
    local dist = math.sqrt(dx * dx + dy * dy)
    local steps = math.max(1, math.ceil(dist / 12))
    for i = 1, steps - 1 do
        local t = i / steps
        if blockedAt(x0 + dx * t, y0 + dy * t) then return false end
    end
    return true
end

--- 从 (sx,sy) 到 (tx,ty) 的路点列表（最后一个就是终点）；走不过去返回 nil
---@return table[]|nil
local function findPath(sx, sy, tx, ty)
    local step = PATH_STEP
    local minCX, maxCX = math.floor(GROUND.minX / step), math.floor(GROUND.maxX / step)
    local minCY, maxCY = math.floor(GROUND.minY / step), math.floor(GROUND.maxY / step)
    local W = maxCX - minCX + 1

    local function idx(cx, cy) return (cy - minCY) * W + (cx - minCX) + 1 end
    local function freeCell(cx, cy)
        if cx < minCX or cx > maxCX or cy < minCY or cy > maxCY then return false end
        return not blockedAt(cx * step + step * 0.5, cy * step + step * 0.5)
    end
    local function snap(cx, cy)
        if freeCell(cx, cy) then return cx, cy end
        for r = 1, 4 do
            for dx = -r, r do
                for dy = -r, r do
                    if math.max(math.abs(dx), math.abs(dy)) == r and freeCell(cx + dx, cy + dy) then
                        return cx + dx, cy + dy
                    end
                end
            end
        end
        return nil
    end

    local ax, ay = snap(math.floor(sx / step), math.floor(sy / step))
    local bx, by = snap(math.floor(tx / step), math.floor(ty / step))
    if not ax or not bx then return nil end

    local start, goal = idx(ax, ay), idx(bx, by)
    local prev = { [start] = -1 }
    local q, head = { start }, 1
    local dirs = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 },
        { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }
    local found = start == goal
    while head <= #q and not found do
        local cur = q[head]
        head = head + 1
        local cx = (cur - 1) % W + minCX
        local cy = math.floor((cur - 1) / W) + minCY
        for _, d in ipairs(dirs) do
            local nx, ny = cx + d[1], cy + d[2]
            if freeCell(nx, ny) then
                -- 斜向不允许贴墙角穿过去
                local ok = d[1] == 0 or d[2] == 0
                    or (freeCell(cx + d[1], cy) and freeCell(cx, cy + d[2]))
                if ok then
                    local ni = idx(nx, ny)
                    if prev[ni] == nil then
                        prev[ni] = cur
                        if ni == goal then found = true break end
                        q[#q + 1] = ni
                    end
                end
            end
        end
    end
    if not found then return nil end

    local cells = {}
    local cur = goal
    while cur ~= nil and cur ~= -1 do
        local cx = (cur - 1) % W + minCX
        local cy = math.floor((cur - 1) / W) + minCY
        table.insert(cells, 1, { cx * step + step * 0.5, cy * step + step * 0.5 })
        cur = prev[cur]
    end
    cells[#cells + 1] = { tx, ty }

    -- 视线平滑：能直达的中间点全部跳过，不然会走成锯齿
    local out = {}
    local fromX, fromY = sx, sy
    local i = 1
    while i <= #cells do
        local j = #cells
        while j > i and not lineClear(fromX, fromY, cells[j][1], cells[j][2]) do
            j = j - 1
        end
        out[#out + 1] = cells[j]
        fromX, fromY = cells[j][1], cells[j][2]
        i = j + 1
    end
    return out
end

--- 朝某个世界坐标走过去（自动绕障碍）；走不过去返回 false
---@param wx number
---@param wy number
---@param approach string|nil 走到后自动打开的交互点 id
---@return boolean
function SceneUI.WalkTo(wx, wy, approach)
    if S.screen ~= "menu" or S.panelMode then return false end
    local sc = scene()
    local tx, ty = nearestFree(wx, wy, 180)
    if not tx then return false end
    tx = math.max(GROUND.minX, math.min(GROUND.maxX, tx))
    ty = math.max(GROUND.minY, math.min(GROUND.maxY, ty))
    local path = findPath(sc.wx, sc.wy, tx, ty)
    if not path or #path == 0 then return false end
    sc.path = path
    sc.approach = approach
    sc.stuck = 0
    return true
end

-- ---------------------------------------------------------------- 更新
function SceneUI.Update(dt)
    if S.screen ~= "menu" or S.panelMode then return end
    local sc = scene()

    local ix, iy = S.input.x or 0, S.input.y or 0
    local moving = false
    local dx, dy = 0, 0

    if ix ~= 0 or iy ~= 0 then
        sc.path = nil                         -- 有输入就取消寻路
        local len = math.sqrt(ix * ix + iy * iy)
        if len > 0 then
            dx = ix / len * SPEED * dt
            dy = iy / len * SPEED * dt
            if math.abs(ix) > 0.15 then sc.facing = (ix > 0) and 1 or -1 end
            moving = true
        end
    elseif sc.path and #sc.path > 0 then
        local wp = sc.path[1]
        local tx, ty = wp[1] - sc.wx, wp[2] - sc.wy
        local dist = math.sqrt(tx * tx + ty * ty)
        if dist < 7 then
            table.remove(sc.path, 1)
            if #sc.path == 0 then
                sc.path = nil
                SceneUI.AutoInteract()
            end
        else
            local step = math.min(SPEED * dt, dist)
            dx = tx / dist * step
            dy = ty / dist * step
            if math.abs(tx) > 1 then sc.facing = (tx > 0) and 1 or -1 end
            moving = true
        end
    end

    if moving then
        -- 分轴移动：撞到建筑只停那一条轴，可以顺着墙滑
        local moved = false
        if dx ~= 0 then
            local nx = sc.wx + dx
            if not blockedAt(nx, sc.wy) then sc.wx = nx; moved = true end
        end
        if dy ~= 0 then
            local ny = sc.wy + dy
            if not blockedAt(sc.wx, ny) then sc.wy = ny; moved = true end
        end
        sc.wx = math.max(GROUND.minX, math.min(GROUND.maxX, sc.wx))
        sc.wy = math.max(GROUND.minY, math.min(GROUND.maxY, sc.wy))
        -- 被卡住（点到了墙里）就别一直原地踏步
        if not moved then
            sc.stuck = (sc.stuck or 0) + dt
            if sc.stuck > 0.35 then
                sc.path = nil
                sc.stuck = 0
            end
            moving = false                      -- 顶着墙走不动就不出走路动画
        else
            sc.stuck = 0
        end
    end

    -- 没有移动指令时保持静止：回到待机第 0 帧
    if moving ~= sc.moving then
        sc.frame = 0
        sc.animT = 0
    end
    sc.moving = moving
    if moving then
        sc.animT = sc.animT + dt
        local frameTime = 1 / HERO.walk.fps
        while sc.animT >= frameTime do
            sc.animT = sc.animT - frameTime
            sc.frame = (sc.frame + 1) % HERO.walk.frames
        end
    end
end

--- 点击地面：走过去（设计坐标 → 世界坐标）
---@return boolean 是否消费了这次点击
function SceneUI.GroundClick(dx, dy)
    if S.screen ~= "menu" or S.panelMode then return false end
    if dy < 92 then return false end
    local camX, camY = SceneUI.Camera()
    local wx, wy = dx + camX, dy + camY
    if wy < GROUND.minY - 60 or wy > GROUND.maxY + 30 then return false end
    if not SceneUI.WalkTo(wx, wy) then
        UI.SetToast("那边走不过去", 1.2)
        return false
    end
    return true
end

local function nearSpot()
    local sc = scene()
    for _, sp in ipairs(SPOTS) do
        local dx, dy = sc.wx - sp.x, sc.wy - sp.y
        local reach = sp.r + 86
        if dx * dx + dy * dy <= reach * reach then
            return sp
        end
    end
    return nil
end

--- 走到交互点后自动打开面板
function SceneUI.AutoInteract()
    local sc = scene()
    local want = sc.approach
    sc.approach = nil
    if want then
        for _, sp in ipairs(SPOTS) do
            if sp.id == want then
                local dx, dy = sc.wx - sp.x, sc.wy - sp.y
                if dx * dx + dy * dy <= (sp.r + 150) * (sp.r + 150) then
                    S.panelMode = sp.panel
                    return true
                end
            end
        end
    end
    local sp = nearSpot()
    if not sp then return false end
    S.panelMode = sp.panel
    return true
end

--- 与最近的物件交互
---@return boolean
function SceneUI.Interact()
    if S.screen ~= "menu" or S.panelMode then return false end
    local sp = nearSpot()
    if not sp then
        UI.SetToast("走近物件后再互动", 1.5)
        return false
    end
    S.panelMode = sp.panel
    return true
end

-- ---------------------------------------------------------------- 绘制工具
--- 画背景的一块（支持水平/垂直翻转），用于把世界外的画面用镜像补齐
local function DrawBgPiece(img, sx, sy, sw, sh, dx, dy, dw, dh, flipX, flipY)
    local ctx = S.ctx
    local iw, ih = Art.Size(img)
    if iw <= 0 or ih <= 0 then return end
    local kx, ky = dw / sw, dh / sh
    nvgSave(ctx)
    nvgTranslate(ctx, flipX and (dx + dw) or dx, flipY and (dy + dh) or dy)
    nvgScale(ctx, flipX and -1 or 1, flipY and -1 or 1)
    nvgScissor(ctx, 0, 0, dw, dh)
    local paint = nvgImagePattern(ctx, -sx * kx, -sy * ky, iw * kx, ih * ky, 0, img, 1)
    nvgBeginPath(ctx)
    nvgRect(ctx, -sx * kx, -sy * ky, iw * kx, ih * ky)
    nvgFillPaint(ctx, paint)
    nvgFill(ctx)
    nvgRestore(ctx)
end

--- 世界外的过渡：镜像铺开 + 跨过边界的柔和雾幕
-- 渐变从「世界内侧 INNER」一直延伸到「世界外 reach」，两侧同一个斜率，
-- 所以世界边界上没有亮度突变，不会出现一道竖线/横线（也不会出现灰色框）。
local function DrawEdgeFade(vx, vy, vw, vh, left, right, top, bottom)
    local ctx = S.ctx
    local R, G, B = 10, 22, 14
    local CLEAR, DARK = 0, 150
    local W, H = SceneUI.WORLD_W, SceneUI.WORLD_H
    local reach, inner = 460, 120

    local function fadeRect(x, y, w, h, gx1, gy1, gx2, gy2, a1, a2)
        if w <= 0 or h <= 0 then return end
        local paint = nvgLinearGradient(ctx, gx1, gy1, gx2, gy2,
            nvgRGBA(R, G, B, a1), nvgRGBA(R, G, B, a2))
        nvgBeginPath(ctx)
        nvgRect(ctx, x, y, w, h)
        nvgFillPaint(ctx, paint)
        nvgFill(ctx)
    end

    if left then
        local x0 = math.max(vx, -reach)
        fadeRect(x0, vy, inner - x0, vh, x0, 0, inner, 0, DARK, CLEAR)
    end
    if right then
        local x1 = math.min(vx + vw, W + reach)
        fadeRect(W - inner, vy, x1 - (W - inner), vh, W - inner, 0, x1, 0, CLEAR, DARK)
    end
    if top then
        local y0 = math.max(vy, -reach)
        fadeRect(vx, y0, vw, inner - y0, 0, y0, 0, inner, DARK, CLEAR)
    end
    if bottom then
        local y1 = math.min(vy + vh, H + reach)
        fadeRect(vx, H - inner, vw, y1 - (H - inner), 0, H - inner, 0, y1, CLEAR, DARK)
    end
end

--- 把整张背景铺满可视区域：世界内 1:1，世界外用镜像延伸 + 边缘渐变（不出现灰边）
local function DrawBackdrop(vx, vy, vw, vh)
    local img = Art.Get("art/home_bg.jpg")
    local W, H = SceneUI.WORLD_W, SceneUI.WORLD_H
    if not img then
        nvgBeginPath(S.ctx)
        nvgRect(S.ctx, vx, vy, vw, vh)
        nvgFillColor(S.ctx, nvgRGBA(42, 64, 38, 255))
        nvgFill(S.ctx)
        return
    end

    DrawBgPiece(img, 0, 0, W, H, 0, 0, W, H, false, false)

    local left = vx < 0
    local right = vx + vw > W
    local top = vy < 0
    local bottom = vy + vh > H

    if left then DrawBgPiece(img, 0, 0, W, H, -W, 0, W, H, true, false) end
    if right then DrawBgPiece(img, 0, 0, W, H, W, 0, W, H, true, false) end
    if top then DrawBgPiece(img, 0, 0, W, H, 0, -H, W, H, false, true) end
    if bottom then DrawBgPiece(img, 0, 0, W, H, 0, H, W, H, false, true) end
    if left and top then DrawBgPiece(img, 0, 0, W, H, -W, -H, W, H, true, true) end
    if left and bottom then DrawBgPiece(img, 0, 0, W, H, -W, H, W, H, true, true) end
    if right and top then DrawBgPiece(img, 0, 0, W, H, W, -H, W, H, true, true) end
    if right and bottom then DrawBgPiece(img, 0, 0, W, H, W, H, W, H, true, true) end

    if left or right or top or bottom then
        DrawEdgeFade(vx, vy, vw, vh, left, right, top, bottom)
    end
end

-- ---------------------------------------------------------------- 绘制：网格 + 直角坐标系（辅助）
-- 世界坐标 = 背景图像素坐标：原点在图片左上角，X 向右、Y 向下。
-- G 键开关。打开后画：细网格（50px）/ 粗网格（250px）、X/Y 轴与原点、
-- 顶部与左侧标尺（世界坐标数字）、寻路终点标记、角色脚底十字准星与实时坐标。
local GRID_MINOR = 50
local GRID_MAJOR = 250
local RULER_STEP = 250
local RULER_TOP_H = 18
local RULER_LEFT_W = 56

local function GridOn()
    return scene().grid ~= false
end

--- 世界空间：网格线
local function DrawGrid(vx, vy, vw, vh)
    local ctx = S.ctx
    local x1, y1 = vx + vw, vy + vh

    for x = math.floor(vx / GRID_MINOR) * GRID_MINOR, x1, GRID_MINOR do
        if x >= 0 and x <= SceneUI.WORLD_W then
            local major = (x % GRID_MAJOR == 0)
            nvgBeginPath(ctx)
            nvgMoveTo(ctx, x + 0.5, vy)
            nvgLineTo(ctx, x + 0.5, y1)
            nvgStrokeColor(ctx, nvgRGBA(226, 240, 255, major and 58 or 24))
            nvgStrokeWidth(ctx, major and 1.6 or 1)
            nvgStroke(ctx)
        end
    end
    for y = math.floor(vy / GRID_MINOR) * GRID_MINOR, y1, GRID_MINOR do
        if y >= 0 and y <= SceneUI.WORLD_H then
            local major = (y % GRID_MAJOR == 0)
            nvgBeginPath(ctx)
            nvgMoveTo(ctx, vx, y + 0.5)
            nvgLineTo(ctx, x1, y + 0.5)
            nvgStrokeColor(ctx, nvgRGBA(226, 240, 255, major and 58 or 24))
            nvgStrokeWidth(ctx, major and 1.6 or 1)
            nvgStroke(ctx)
        end
    end
end

--- 世界空间：X / Y 轴（世界 x=0、y=0）与原点 O
local function DrawAxes(vx, vy, vw, vh)
    local ctx = S.ctx
    local col = nvgRGBA(120, 226, 255, 165)
    if vx <= 1 and vx + vw >= 0 then          -- Y 轴：x = 0
        nvgBeginPath(ctx)
        nvgMoveTo(ctx, 0.5, vy)
        nvgLineTo(ctx, 0.5, vy + vh)
        nvgStrokeColor(ctx, col)
        nvgStrokeWidth(ctx, 2.4)
        nvgStroke(ctx)
    end
    if vy <= 1 and vy + vh >= 0 then          -- X 轴：y = 0
        nvgBeginPath(ctx)
        nvgMoveTo(ctx, vx, 0.5)
        nvgLineTo(ctx, vx + vw, 0.5)
        nvgStrokeColor(ctx, col)
        nvgStrokeWidth(ctx, 2.4)
        nvgStroke(ctx)
    end
    if vx <= 0 and vy <= 0 and vx + vw >= 0 and vy + vh >= 0 then
        UI.Circle(0, 0, 4, { 120, 226, 255, 220 })
        UI.Text(7, 5, 11, "O(0,0)", S.col.cyan)
    end
end

--- 世界空间：寻路终点标记（右键点地面后显示）
local function DrawWalkTarget()
    local sc = scene()
    if not sc.path or #sc.path == 0 then return end
    local wp = sc.path[#sc.path]
    local pulse = 0.5 + 0.5 * math.sin(S.time * 6)
    UI.Circle(wp[1], wp[2], 9 + pulse * 5, { 120, 226, 255, 26 }, { 120, 226, 255, 190 }, 2)
    UI.Circle(wp[1], wp[2], 2.5, { 200, 245, 255, 220 })
end

--- 屏幕空间：顶部 / 左侧标尺（贴边，不跟相机走）
local function DrawRulers(vx, vy, vw, vh, camX, camY)
    local ctx = S.ctx

    nvgBeginPath(ctx)
    nvgRect(ctx, vx, vy, vw, RULER_TOP_H)
    nvgFillColor(ctx, nvgRGBA(8, 12, 20, 185))
    nvgFill(ctx)
    nvgBeginPath(ctx)
    nvgRect(ctx, vx, vy, RULER_LEFT_W, vh)
    nvgFillColor(ctx, nvgRGBA(8, 12, 20, 185))
    nvgFill(ctx)

    local tickCol = nvgRGBA(150, 226, 255, 150)
    local tickColHot = nvgRGBA(190, 240, 255, 235)

    -- 顶部：世界 X
    for wx = math.floor(camX / RULER_STEP) * RULER_STEP, camX + vw, RULER_STEP do
        if wx >= 0 and wx <= SceneUI.WORLD_W then
            local sx = wx - camX
            if sx >= vx + RULER_LEFT_W + 12 then
                local hot = (wx % 1000 == 0)
                nvgBeginPath(ctx)
                nvgMoveTo(ctx, sx + 0.5, vy + RULER_TOP_H - (hot and 10 or 6))
                nvgLineTo(ctx, sx + 0.5, vy + RULER_TOP_H)
                nvgStrokeColor(ctx, hot and tickColHot or tickCol)
                nvgStrokeWidth(ctx, 1)
                nvgStroke(ctx)
                UI.Text(sx + 3, vy + 3, 10, tostring(wx), { 178, 232, 255, 225 })
            end
        end
    end

    -- 左侧：世界 Y
    for wy = math.floor(camY / RULER_STEP) * RULER_STEP, camY + vh, RULER_STEP do
        if wy >= 0 and wy <= SceneUI.WORLD_H then
            local sy = wy - camY
            if sy >= vy + RULER_TOP_H + 10 then
                local hot = (wy % 1000 == 0)
                nvgBeginPath(ctx)
                nvgMoveTo(ctx, vx + RULER_LEFT_W - (hot and 10 or 6), sy + 0.5)
                nvgLineTo(ctx, vx + RULER_LEFT_W, sy + 0.5)
                nvgStrokeColor(ctx, hot and tickColHot or tickCol)
                nvgStrokeWidth(ctx, 1)
                nvgStroke(ctx)
                UI.Text(vx + 5, sy - 5, 10, tostring(wy), { 178, 232, 255, 205 })
            end
        end
    end

    UI.Text(vx + 5, vy + 3, 10, "X", S.col.cyan)
    UI.Text(vx + 5, vy + RULER_TOP_H + 3, 10, "Y", S.col.cyan)
end

--- 屏幕空间：角色脚底十字准星 + 左上角实时坐标读数
local function DrawHeroCoords(camX, camY, vx, vy)
    local sc = scene()
    local ctx = S.ctx
    local sx, sy = sc.wx - camX, sc.wy - camY

    nvgBeginPath(ctx)
    nvgMoveTo(ctx, sx - 26, sy + 0.5)
    nvgLineTo(ctx, sx + 26, sy + 0.5)
    nvgMoveTo(ctx, sx + 0.5, sy - 34)
    nvgLineTo(ctx, sx + 0.5, sy + 8)
    nvgStrokeColor(ctx, nvgRGBA(120, 226, 255, 110))
    nvgStrokeWidth(ctx, 1)
    nvgStroke(ctx)

    -- 读数放左上角（放在头顶会和交互提示气泡叠在一起）
    local label = string.format("角色  x %d   y %d", math.floor(sc.wx), math.floor(sc.wy))
    local w = 156
    local bx = vx + RULER_LEFT_W + 8
    local by = vy + RULER_TOP_H + 8
    UI.Panel(bx, by, w, 22, 7, { 8, 14, 22, 210 }, S.col.cyan, 1)
    UI.Text(bx + w / 2, by + 11, 11, label, S.col.cyan, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
end

-- ---------------------------------------------------------------- 绘制：角色
local function DrawHero()
    local sc = scene()
    local set = sc.moving and HERO.walk or HERO.idle
    local idx = sc.moving and sc.frame or 0
    local a = set.anchors[idx + 1] or set.anchors[1]
    local k = HERO.charH / set.unitH
    local flip = sc.facing < 0
    local anchorX = flip and (set.fw - a[1]) or a[1]
    local dw, dh = set.fw * k, set.fh * k
    local x = sc.wx - anchorX * k
    local y = sc.wy - a[2] * k

    -- 影子
    nvgBeginPath(S.ctx)
    nvgEllipse(S.ctx, sc.wx, sc.wy + 1, 17, 6)
    nvgFillColor(S.ctx, nvgRGBA(0, 0, 0, 85))
    nvgFill(S.ctx)

    local ok = Art.DrawFrame(set.path, idx * set.fw, 0, set.fw, set.fh,
        x, y, dw, dh, 1, flip)
    if not ok then
        UI.Circle(sc.wx, sc.wy - HERO.charH / 2, 18, S.col.cyan)
    end
end

-- ---------------------------------------------------------------- 绘制：交互点
local function DrawSpots(camX, camY, withInput)
    local sc = scene()
    for _, sp in ipairs(SPOTS) do
        local dx, dy = sc.wx - sp.x, sc.wy - sp.y
        local inRange = dx * dx + dy * dy <= (sp.r + 86) * (sp.r + 86)
        local pulse = 0.5 + 0.5 * math.sin(S.time * 2.2)

        -- 设计坐标（悬停判定与点击区域都用设计坐标）
        local sx, sy = sp.x - camX, sp.y - camY
        local hovered = withInput and S.hover and S.hover.x >= sx - sp.r and S.hover.x <= sx + sp.r
            and S.hover.y >= sy - sp.r and S.hover.y <= sy + sp.r
        local grow = hovered and 1.08 or 1
        local r = sp.r * grow
        local alpha = hovered and 255 or 232

        UI.Circle(sp.x, sp.y, r + 10 + pulse * 6, { sp.color[1], sp.color[2], sp.color[3], 40 })
        UI.Circle(sp.x, sp.y, r, { 66, 56, 96, alpha }, sp.color, hovered and 3 or 2)
        UI.Circle(sp.x, sp.y, r - 6, { 44, 38, 66, 200 })
        -- 有贴图就用贴图当入口图标（泉 = 背景图里泉水那块裁成的圆形勋章）；缺贴图退回单字
        local drewArt = false
        if sp.art then
            local sz = (r - 6) * 2
            drewArt = Art.Draw(sp.art, sp.x - sz / 2, sp.y - sz / 2, sz, sz, 1)
        end
        if not drewArt then
            UI.Text(sp.x, sp.y - 1, 22 * grow, sp.icon, sp.color, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        end

        local nameW = 84
        UI.Panel(sp.x - nameW / 2, sp.y + r + 5, nameW, 20, 7, { 20, 17, 30, 200 }, nil, 0)
        UI.Text(sp.x, sp.y + r + 8, 12, sp.name, S.col.text, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)

        if withInput then
            UI.Region("scene_spot_body_" .. sp.id, sx - r, sy - r, r * 2, r * 2, function()
                local ddx, ddy = sc.wx - sp.x, sc.wy - sp.y
                if ddx * ddx + ddy * ddy <= (sp.r + 86) * (sp.r + 86) then
                    SceneUI.Interact()
                else
                    local ax, ay = nearestFree(sp.x, sp.y + sp.r + 48, 200)
                    if ax and SceneUI.WalkTo(ax, ay, sp.id) then
                        -- 走过去后由 AutoInteract 打开面板
                    else
                        UI.SetToast("那边走不过去", 1.2)
                    end
                end
            end, true, { press = true, selfHover = true })

            if inRange then
                UI.Panel(sp.x - 112, sp.y - sp.r - 58, 224, 32, 9, { 24, 20, 36, 238 }, sp.color, 1)
                UI.Text(sp.x, sp.y - sp.r - 42, 12, "按 E / 点这里：" .. sp.hint, S.col.text,
                    NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                UI.Region("scene_spot_" .. sp.id, sx - 112, sy - sp.r - 58, 224, 32,
                    function() SceneUI.Interact() end, true, { selfHover = true })
            end
        end
    end
end

-- ---------------------------------------------------------------- 绘制：HUD
local ENTRIES = {
    { id = "sports",   name = "运动", open = function() S.panelMode = "sports" end },
    { id = "bag",      name = "背包", open = function() S.bag = true; S.bagPage = 1 end },
    { id = "pet",      name = "宠物", open = function()
        S.pet = true; S.petTab = S.petTab or 1; S.petPickLow = false end },
    { id = "camp",     name = "营地", open = function() S.camp = true; S.campTab = S.campTab or 1 end },
    { id = "guild",    name = "公会", open = function() S.guild = true; S.guildTab = S.guildTab or 1 end },
    { id = "settings", name = "设置", open = function() S.settings = true end },
    { id = "codex",    name = "图鉴", open = function()
        S.compendium = true; S.compendiumTab = 1; S.codexPage = 1 end },
}

local function DrawHUD()
    local data = S.data

    -- 右上：货币
    UI.Panel(1056, 14, 208, 50, 9, { 20, 17, 30, 200 }, S.col.line, 1)
    UI.Text(1068, 21, 11, "精粹", S.col.dim)
    UI.Text(1252, 18, 14, UI.FormatNumber(Economy.Essence(data)), S.col.gold,
        NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
    UI.Text(1068, 41, 11, "宠物代币", S.col.dim)
    UI.Text(1252, 39, 12, UI.FormatNumber(Pet.Coins(data)), S.col.purple,
        NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)

    -- 顶部功能入口（缩小）
    local w, h, gap = 72, 26, 6
    local total = #ENTRIES * w + (#ENTRIES - 1) * gap
    local startX = (VIEW_W - total) / 2
    for i, e in ipairs(ENTRIES) do
        local x = startX + (i - 1) * (w + gap)
        UI.Button("scene_" .. e.id, x, 26, w, h, e.name, e.open,
            { fontSize = 12, radius = 8, fill = { 74, 60, 106, 255 }, stroke = S.col.line })
    end

    -- 底部提示
    UI.Text(640, 700, 10, "WASD / 方向键移动　·　右键点地面走过去　·　E 与身旁物件互动　·　G 网格/坐标",
        S.col.dim, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)

    -- 右下：今日运动（独立主入口，带今日步数）+ 选关
    UI.Button("scene_sports_entry", 1016, 620, 236, 34,
        "今日运动 · " .. UI.FormatNumber(S.data.todaySteps or 0) .. " 步", function()
            S.panelMode = "sports"
        end, { fontSize = 13, radius = 8, accent = S.col.gold,
            fill = { 62, 50, 28, 255 }, stroke = S.col.gold })

    UI.Button("scene_levels", 1128, 662, 124, 30, "选关", function()
        S.panelMode = "levels"
    end, { fontSize = 13, radius = 8, accent = S.col.cyan,
        fill = { 40, 116, 74, 255 }, stroke = S.col.green })
end

-- ---------------------------------------------------------------- 调试：碰撞盒
SceneUI.debugBoxes = false

function SceneUI.DrawDebug()
    for _, o in ipairs(OBSTACLES) do
        nvgBeginPath(S.ctx)
        nvgRect(S.ctx, o.x, o.y, o.w, o.h)
        nvgFillColor(S.ctx, nvgRGBA(255, 60, 60, 42))
        nvgFill(S.ctx)
        nvgStrokeColor(S.ctx, nvgRGBA(255, 90, 90, 200))
        nvgStrokeWidth(S.ctx, 2)
        nvgStroke(S.ctx)
    end
    local sc = scene()
    nvgBeginPath(S.ctx)
    nvgRect(S.ctx, sc.wx - FOOT_HW, sc.wy - FOOT_HH, FOOT_HW * 2, FOOT_HH)
    nvgFillColor(S.ctx, nvgRGBA(60, 255, 120, 120))
    nvgFill(S.ctx)
end

-- ---------------------------------------------------------------- 绘制：主体
--- 只画世界（背景 / 网格 / 交互点 / 人物），不画 HUD；铺满整个物理屏幕
---@param opts table|nil { dim = 暗幕透明度, input = 是否注册点击区域 }
function SceneUI.DrawWorld(opts)
    opts = opts or {}
    local camX, camY = SceneUI.Camera()

    -- 物理屏幕在设计坐标里的范围（letterbox 也算进来，杜绝灰边）
    local vl, vt, vw, vh = UI.ViewRect()

    nvgSave(S.ctx)
    nvgTranslate(S.ctx, -camX, -camY)
    nvgScissor(S.ctx, camX + vl, camY + vt, vw, vh)

    DrawBackdrop(camX + vl, camY + vt, vw, vh)
    local gridOn = GridOn()
    if gridOn then
        DrawGrid(camX + vl, camY + vt, vw, vh)
        DrawAxes(camX + vl, camY + vt, vw, vh)
    end
    DrawWalkTarget()
    DrawSpots(camX, camY, opts.input ~= false)
    DrawHero()
    if SceneUI.debugBoxes then SceneUI.DrawDebug() end

    nvgRestore(S.ctx)

    if gridOn then
        DrawRulers(vl, vt, vw, vh, camX, camY)
        DrawHeroCoords(camX, camY, vl, vt)
    end

    if opts.dim and opts.dim > 0 then
        UI.FillScreen({ 8, 6, 16, opts.dim })
    end
end

--- 面板模式的背景：场景铺满 + 不注册点击区域（面板自己接管输入）
function SceneUI.DrawPanelBg()
    SceneUI.DrawWorld({ input = false })
end

function SceneUI.Draw()
    SceneUI.DrawWorld()

    local vl, vt, vw, vh = UI.ViewRect()

    -- 顶部 / 底部轻微压暗，保证 HUD 可读
    nvgBeginPath(S.ctx)
    nvgRect(S.ctx, vl, vt, vw, 62)
    nvgFillColor(S.ctx, nvgRGBA(10, 8, 18, 105))
    nvgFill(S.ctx)
    nvgBeginPath(S.ctx)
    nvgRect(S.ctx, vl, vt + vh - 42, vw, 42)
    nvgFillColor(S.ctx, nvgRGBA(10, 8, 18, 88))
    nvgFill(S.ctx)

    DrawHUD()
end

--- 面板模式下的返回按钮
function SceneUI.DrawPanelBack()
    UI.Button("scene_back", 1108, 20, 136, 30, "← 返回场景", function()
        S.panelMode = nil
    end, { fontSize = 13, radius = 8, fill = { 40, 116, 74, 255 }, stroke = S.col.green })
end

--- 网格开关（G 键）
function SceneUI.ToggleGrid()
    local sc = scene()
    sc.grid = not sc.grid
    UI.SetToast(sc.grid and "网格 / 坐标：开" or "网格 / 坐标：关", 1.2)
end

return SceneUI
