-- FarmArt.lua — 农场实景地图（图片底图 + 9 块地按真实坐标对齐）
-- 底图 1400×941（已裁掉生成图右侧的参考栏），游戏里按高度适配到 720 设计高度。
-- 9 块地在底图里的像素位置是量出来的，换算到设计坐标后可直接做点击判定。
local UI = require "UI"

local FarmArt = {}

FarmArt.PATH = "image/farm/farm_map.jpg"

-- 底图像素尺寸（用于点击坐标换算）
FarmArt.IMG_W = 1400
FarmArt.IMG_H = 941

-- 9 块地在底图里的位置（左上角 x, y）与格子尺寸
FarmArt.COL_X = { 340, 536, 728 }
FarmArt.ROW_Y = { 252, 416, 576 }
FarmArt.PLOT_W = 144
FarmArt.PLOT_H = 116

--- 地图当前绘制偏移与缩放（由 DrawMap 更新）
---@type number
FarmArt.scale = 1.0
---@type number
FarmArt.offX = 0.0
---@type number
FarmArt.offY = 0.0

--- 按设计画布高度铺满整张地图，水平居中
function FarmArt.Layout(designH)
    local h = designH or 720
    FarmArt.scale = h / FarmArt.IMG_H
    FarmArt.offX = (1280 - FarmArt.IMG_W * FarmArt.scale) / 2
    FarmArt.offY = 0
    return FarmArt.scale, FarmArt.offX, FarmArt.offY
end

--- 画地图底图；返回是否成功（失败时调用方回退矢量画法）
function FarmArt.DrawMap()
    FarmArt.Layout(720)
    local w = FarmArt.IMG_W * FarmArt.scale
    local h = FarmArt.IMG_H * FarmArt.scale
    return UI.Image(FarmArt.PATH, FarmArt.offX, FarmArt.offY, w, h)
end

--- 第 index 块地（1~9，行优先）在设计画布上的矩形
---@return number, number, number, number
function FarmArt.PlotRect(index)
    local col = (index - 1) % 3 + 1
    local row = math.floor((index - 1) / 3) + 1
    local ix = FarmArt.COL_X[col] or FarmArt.COL_X[1]
    local iy = FarmArt.ROW_Y[row] or FarmArt.ROW_Y[1]
    local s = FarmArt.scale
    return FarmArt.offX + ix * s, FarmArt.offY + iy * s,
        FarmArt.PLOT_W * s, FarmArt.PLOT_H * s
end

--- 设计坐标 → 地块序号（没点中返回 nil）
function FarmArt.HitTest(dx, dy)
    for i = 1, 9 do
        local x, y, w, h = FarmArt.PlotRect(i)
        -- 判定区域比视觉稍大一点，手指点着不费劲
        local pad = 8
        if dx >= x - pad and dx <= x + w + pad and dy >= y - pad and dy <= y + h + pad then
            return i
        end
    end
    return nil
end
-- ---------------------------------------------------------------- 作物序列帧
-- assets/image/farm/crops.png：4 列 × 9 行 @256，列 = 发芽 / 生长 / 成熟 / 果实
FarmArt.CROP_PATH = "image/farm/crops.png"
FarmArt.CROP_CELL = 256

-- 行号（1 开始）→ 作物 id，按美术给的顺序定的；如果对不上改这里就行
FarmArt.CropRow = {
    ice = 1, thunder = 2, gold = 3, life = 4, mushroom = 5,
    chaos = 6, timevine = 7, fire = 8, phoenix = 9,
}

--- 画某种作物的第 col 列（1 发芽 / 2 生长 / 3 成熟 / 4 果实）
---@param cropId string
---@param col integer
---@param x number 左
---@param y number 上
---@param w number
---@param h number
---@return boolean
function FarmArt.DrawCrop(cropId, col, x, y, w, h, alpha)
    local row = FarmArt.CropRow[cropId]
    if not row then return false end
    local cell = FarmArt.CROP_CELL
    return UI.ImageRect(FarmArt.CROP_PATH,
        (col - 1) * cell, (row - 1) * cell, cell, cell,
        x, y, w, h, alpha)
end

--- 已开垦的地块贴图（泥土），画在作物下面
--- 贴图本身已经去掉了绿草边；四周再多画 4px，
--- 底图上每块地自带一圈草皮，贴图的圆角处会透出来，
--- 所以先垫一层土色圆角底把草皮完全盖住，再叠土块贴图。
FarmArt.PLOT_PATH = "image/farm/plot_tilled.png"
FarmArt.PLOT_PAD = 4
FarmArt.PLOT_SOIL = { 118, 64, 28, 255 }
function FarmArt.DrawPlotTile(x, y, w, h)
    local p = FarmArt.PLOT_PAD
    local bx, by, bw, bh = x - p, y - p, w + p * 2, h + p * 2
    UI.Panel(bx, by, bw, bh, 11, FarmArt.PLOT_SOIL)
    return UI.Image(FarmArt.PLOT_PATH, bx, by, bw, bh)
end

return FarmArt
