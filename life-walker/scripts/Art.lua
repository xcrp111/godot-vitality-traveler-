-- Art.lua — 贴图加载与绘制（NanoVG）
-- 素材来自 game-health 项目，放在 assets/art/ 下（资源根是 assets/）
-- 用法：
--   Art.Draw("art/home_bg.jpg", x, y, w, h)
--   Art.DrawFrame("art/hero_idle.png", fx, fy, fw, fh, x, y, w, h, alpha, flip)

local S = require "State"

local Art = {}

local cache = {}      -- path -> handle（false 表示加载失败，避免反复尝试）
local sizeCache = {}  -- handle -> {w, h}

local function ensureCtx()
    return S.ctx
end

--- 取图片句柄（失败返回 nil）
---@param path string
---@return integer|nil
function Art.Get(path)
    local ctx = ensureCtx()
    if not ctx then return nil end
    local hit = cache[path]
    if hit ~= nil then
        if hit == false then return nil end
        return hit
    end
    local ok, img = pcall(nvgCreateImage, ctx, path, 0)
    if not ok or not img or img <= 0 then
        cache[path] = false
        print("[art] load failed: " .. tostring(path))
        return nil
    end
    cache[path] = img
    return img
end

--- 图片原始尺寸（失败返回 0,0）
---@param handle integer
---@return number, number
function Art.Size(handle)
    local ctx = ensureCtx()
    if not ctx or not handle then return 0, 0 end
    local hit = sizeCache[handle]
    if hit then return hit[1], hit[2] end
    local w, h = 0, 0
    pcall(function() w, h = nvgImageSize(ctx, handle) end)
    w = tonumber(w) or 0
    h = tonumber(h) or 0
    sizeCache[handle] = { w, h }
    return w, h
end

--- 整张图缩放到 (x, y, w, h)
---@return boolean ok
function Art.Draw(path, x, y, w, h, alpha)
    local img = Art.Get(path)
    if not img then return false end
    local ctx = S.ctx
    local paint = nvgImagePattern(ctx, x, y, w, h, 0, img, alpha or 1)
    nvgBeginPath(ctx)
    nvgRect(ctx, x, y, w, h)
    nvgFillPaint(ctx, paint)
    nvgFill(ctx)
    return true
end

--- 按 "cover" 方式铺满（保持比例，超出裁剪）
function Art.DrawCover(path, x, y, w, h, alpha)
    local img = Art.Get(path)
    if not img then return false end
    local iw, ih = Art.Size(img)
    if iw <= 0 or ih <= 0 then return false end
    local scale = math.max(w / iw, h / ih)
    local dw, dh = iw * scale, ih * scale
    local dx = x - (dw - w) / 2
    local dy = y - (dh - h) / 2
    local ctx = S.ctx
    nvgSave(ctx)
    nvgScissor(ctx, x, y, w, h)
    local paint = nvgImagePattern(ctx, dx, dy, dw, dh, 0, img, alpha or 1)
    nvgBeginPath(ctx)
    nvgRect(ctx, dx, dy, dw, dh)
    nvgFillPaint(ctx, paint)
    nvgFill(ctx)
    nvgRestore(ctx)
    return true
end

--- 画精灵图中的一帧：源图里从 (fx, fy) 取 (fw, fh)，缩放到 (x, y, w, h)
---@param flip boolean|nil 水平翻转（角色朝左/朝右）
function Art.DrawFrame(path, fx, fy, fw, fh, x, y, w, h, alpha, flip)
    local img = Art.Get(path)
    if not img then return false end
    local iw, ih = Art.Size(img)
    if iw <= 0 or ih <= 0 or fw <= 0 or fh <= 0 then return false end
    local ctx = S.ctx
    local sx = w / fw
    local sy = h / fh

    nvgSave(ctx)
    if flip then
        nvgTranslate(ctx, x + w, y)
        nvgScale(ctx, -1, 1)
    else
        nvgTranslate(ctx, x, y)
    end
    nvgScissor(ctx, 0, 0, w, h)
    local paint = nvgImagePattern(ctx, -fx * sx, -fy * sy, iw * sx, ih * sy, 0, img, alpha or 1)
    nvgBeginPath(ctx)
    nvgRect(ctx, -fx * sx, -fy * sy, iw * sx, ih * sy)
    nvgFillPaint(ctx, paint)
    nvgFill(ctx)
    nvgRestore(ctx)
    return true
end

--- 预加载（可选，避免首帧卡顿）
function Art.Preload(paths)
    for _, p in ipairs(paths or {}) do Art.Get(p) end
end

return Art
