-- FarmWalk.lua — 农场里的角色行走与走近交互
-- 坐标一律用「底图像素」（1400×941），绘制时再换算到设计坐标，
-- 这样和地块、水井、摊位的实测位置天然对齐。
local Farm = require "Farm"
local FarmArt = require "FarmArt"
local Save = require "Save"
local S = require "State"
local UI = require "UI"

local FarmWalk = {}

local SPEED = 300            -- 底图像素/秒
local REACH = 78             -- 交互距离（底图像素）
local SPAWN_X, SPAWN_Y = 700, 840

-- 地图上几个固定交互点（底图像素坐标）
local SPOTS = {
    { id = "well",  x = 152,  y = 352, label = "水井 · 浇水" },
    { id = "stall", x = 1150, y = 380, label = "摊位 · 商店" },
    { id = "gate",  x = 700,  y = 880, label = "木门 · 离开农场" },
}

-- 可走区域（底图像素）：栅栏内侧
local BOUND = { x0 = 70, y0 = 70, x1 = 1340, y1 = 900 }

FarmWalk.x = SPAWN_X
FarmWalk.y = SPAWN_Y
FarmWalk.face = -math.pi / 2
FarmWalk.walkT = 0
FarmWalk.moveTo = nil        -- 点地图走过去的落点
FarmWalk.nearest = nil       -- 当前可交互目标

function FarmWalk.Reset()
    FarmWalk.x, FarmWalk.y = SPAWN_X, SPAWN_Y
    FarmWalk.face = -math.pi / 2
    FarmWalk.walkT = 0
    FarmWalk.moveTo = nil
    FarmWalk.nearest = nil
end

--- 设计坐标 → 底图像素
function FarmWalk.ToMap(dx, dy)
    local s = FarmArt.scale
    return (dx - FarmArt.offX) / s, (dy - FarmArt.offY) / s
end

--- 底图像素 → 设计坐标
function FarmWalk.ToDesign(mx, my)
    local s = FarmArt.scale
    return FarmArt.offX + mx * s, FarmArt.offY + my * s
end

local function ClampToBounds()
    FarmWalk.x = math.max(BOUND.x0, math.min(BOUND.x1, FarmWalk.x))
    FarmWalk.y = math.max(BOUND.y0, math.min(BOUND.y1, FarmWalk.y))
end

--- 点地图：朝那个点走过去（触屏友好）
function FarmWalk.WalkToDesign(dx, dy)
    local mx, my = FarmWalk.ToMap(dx, dy)
    FarmWalk.moveTo = { x = mx, y = my }
end

-- 目标清单：固定的三个点 + 9 块地
local function Targets()
    local list = {}
    for _, s in ipairs(SPOTS) do
        list[#list + 1] = { id = s.id, x = s.x, y = s.y, label = s.label }
    end
    for i = 1, 9 do
        local col = (i - 1) % 3 + 1
        local row = math.floor((i - 1) / 3) + 1
        local x = FarmArt.COL_X[col] + FarmArt.PLOT_W / 2
        local y = FarmArt.ROW_Y[row] + FarmArt.PLOT_H / 2
        local info = Farm.PlotInfo(S.data, i)
        local label
        if info.status == "locked" then
            label = nil
        elseif info.status == "empty" then
            label = "第 " .. i .. " 块 · 播种"
        elseif info.status == "mature" then
            label = "第 " .. i .. " 块 · 收获"
        else
            label = "第 " .. i .. " 块 · 浇水（剩 " .. math.max(1, math.floor((info.remain or 0) / 60)) .. " 分）"
        end
        if label then
            list[#list + 1] = { id = "plot", index = i, x = x, y = y, label = label }
        end
    end
    return list
end

function FarmWalk.Update(dt)
    if not S.data then return end
    local dx, dy = S.input.x or 0, S.input.y or 0
    local moving = false

    if dx ~= 0 or dy ~= 0 then
        FarmWalk.moveTo = nil
        FarmWalk.x = FarmWalk.x + dx * SPEED * dt
        FarmWalk.y = FarmWalk.y + dy * SPEED * dt
        FarmWalk.face = math.atan(dy, dx)
        moving = true
    elseif FarmWalk.moveTo then
        local tx, ty = FarmWalk.moveTo.x, FarmWalk.moveTo.y
        local d = math.sqrt((tx - FarmWalk.x) ^ 2 + (ty - FarmWalk.y) ^ 2)
        if d < 6 then
            FarmWalk.moveTo = nil
        else
            local step = SPEED * dt
            FarmWalk.face = math.atan(ty - FarmWalk.y, tx - FarmWalk.x)
            FarmWalk.x = FarmWalk.x + (tx - FarmWalk.x) / d * step
            FarmWalk.y = FarmWalk.y + (ty - FarmWalk.y) / d * step
            moving = true
        end
    end
    ClampToBounds()
    FarmWalk.walkT = moving and (FarmWalk.walkT + dt) or (FarmWalk.walkT * 0.8)

    -- 找最近的可交互目标（同一时刻只提示一个，避免文字互相压住）
    local best, bestD
    for _, t in ipairs(Targets()) do
        local d = math.sqrt((t.x - FarmWalk.x) ^ 2 + (t.y - FarmWalk.y) ^ 2)
        if d <= REACH and (not bestD or d < bestD) then
            best, bestD = t, d
        end
    end
    FarmWalk.nearest = best
end

--- 触发当前最近目标
function FarmWalk.Interact()
    local t = FarmWalk.nearest
    if not t then
        UI.SetToast("走近水井 / 摊位 / 木门或地块再按 E", 1.6)
        return
    end
    if t.id == "gate" then
        S.farm = false
        S.farmPlot = nil
        UI.SetToast("离开农场", 1.4)
    elseif t.id == "stall" then
        S.farmTab = 3
        S.farmPlot = nil
    elseif t.id == "well" then
        -- 给最近的、正在生长的地块浇水
        local targetIdx, bestD
        for i = 1, 9 do
            local info = Farm.PlotInfo(S.data, i)
            if info.status == "growing" then
                local col = (i - 1) % 3 + 1
                local row = math.floor((i - 1) / 3) + 1
                local px = FarmArt.COL_X[col] + FarmArt.PLOT_W / 2
                local py = FarmArt.ROW_Y[row] + FarmArt.PLOT_H / 2
                local d = math.sqrt((px - FarmWalk.x) ^ 2 + (py - FarmWalk.y) ^ 2)
                if not bestD or d < bestD then bestD, targetIdx = d, i end
            end
        end
        if not targetIdx then
            UI.SetToast("现在没有正在生长的作物", 1.8)
            return
        end
        local ok, msg = Farm.Water(S.data, targetIdx)
        Save.Write(S.data)
        UI.SetToast(msg, 1.9)
        if not ok then
            local ok2, msg2 = Farm.WaterAll(S.data)
            if ok2 then
                Save.Write(S.data)
                UI.SetToast(msg2, 1.9)
            end
        end
    elseif t.id == "plot" then
        local info = Farm.PlotInfo(S.data, t.index)
        if info.status == "mature" then
            local ok, msg = Farm.Harvest(S.data, t.index)
            Save.Write(S.data)
            UI.SetToast(msg, 1.9)
        elseif info.status == "empty" then
            S.farmPlot = t.index
        else
            local ok, msg = Farm.Water(S.data, t.index)
            Save.Write(S.data)
            UI.SetToast(msg, 1.9)
        end
    end
end

--- 画角色 + 交互提示
function FarmWalk.Draw()
    local x, y = FarmWalk.ToDesign(FarmWalk.x, FarmWalk.y)
    local bob = math.sin(FarmWalk.walkT * 9) * 2

    -- 影子
    UI.Circle(x, y + 12, 15, { 0, 0, 0, 90 }, nil, 0)
    -- 身体
    UI.Circle(x, y - 4 + bob, 15, { 92, 150, 210, 255 }, { 30, 42, 58, 255 }, 2)
    -- 朝向的小尖
    local fx = x + math.cos(FarmWalk.face) * 15
    local fy = y - 4 + bob + math.sin(FarmWalk.face) * 15
    UI.Circle(fx, fy, 4, { 235, 240, 250, 255 }, nil, 0)

    -- 交互提示：只画最近的那一个，浮在目标上方，不会互相压住
    local t = FarmWalk.nearest
    if t then
        local tx, ty = FarmWalk.ToDesign(t.x, t.y)
        local label = t.label or "交互"
        local w = 26 + #label * 13
        local bx, by = tx - w / 2, ty - 92
        UI.Panel(bx, by, w, 30, 15, { 12, 16, 12, 225 }, { 130, 210, 150, 235 }, 2)
        UI.Text(tx, by + 15, 14, label, { 225, 245, 225, 255 },
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    end
end

return FarmWalk
