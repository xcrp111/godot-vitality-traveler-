-- UI.lua
-- NanoVG 绘制与点击区域工具。所有界面坐标基于 1280x720 设计画布。

local S = require "State"

local UI = {}

local function C(c, a)
    local alpha = a
    if alpha == nil then alpha = c[4] or 255 end
    return nvgRGBA(c[1], c[2], c[3], alpha)
end
UI.C = C

-- 进入 / 离开设计画布坐标
function UI.BeginDesign()
    nvgSave(S.ctx)
    nvgTranslate(S.ctx, S.offX, S.offY)
    nvgScale(S.ctx, S.scale, S.scale)
end

function UI.EndDesign()
    nvgRestore(S.ctx)
end

-- 物理像素 -> 设计坐标
function UI.ToDesign(px, py)
    local lx = px / S.dpr
    local ly = py / S.dpr
    return (lx - S.offX) / S.scale, (ly - S.offY) / S.scale
end

-- 物理屏幕在设计坐标里的可视矩形：letterbox 也算进来，用来铺满整屏（不出现灰框）
function UI.ViewRect()
    return -S.offX / S.scale, -S.offY / S.scale, S.W / S.scale, S.H / S.scale
end

-- 用一块颜色铺满整个物理屏幕（含 letterbox 区域）
function UI.FillScreen(color)
    local x, y, w, h = UI.ViewRect()
    nvgBeginPath(S.ctx)
    nvgRect(S.ctx, x, y, w, h)
    nvgFillColor(S.ctx, C(color or S.col.bg))
    nvgFill(S.ctx)
end

function UI.Text(x, y, size, text, color, align)
    nvgFontFaceId(S.ctx, S.font)
    nvgFontSize(S.ctx, size)
    nvgTextAlign(S.ctx, align or (NVG_ALIGN_LEFT + NVG_ALIGN_TOP))
    nvgFillColor(S.ctx, C(color or S.col.text))
    nvgText(S.ctx, x, y, text, nil)
end

function UI.TextBox(x, y, w, size, text, color)
    nvgFontFaceId(S.ctx, S.font)
    nvgFontSize(S.ctx, size)
    nvgTextAlign(S.ctx, math.floor(NVG_ALIGN_LEFT + NVG_ALIGN_TOP))
    nvgFillColor(S.ctx, C(color or S.col.text))
    nvgTextBox(S.ctx, x, y, w, text, nil)
end

function UI.Panel(x, y, w, h, r, fill, stroke, strokeW)
    nvgBeginPath(S.ctx)
    nvgRoundedRect(S.ctx, x, y, w, h, r or 10)
    nvgFillColor(S.ctx, C(fill or S.col.panel))
    nvgFill(S.ctx)
    if stroke then
        nvgStrokeColor(S.ctx, C(stroke))
        nvgStrokeWidth(S.ctx, math.floor(strokeW or 1))
        nvgStroke(S.ctx)
    end
end

function UI.Line(x1, y1, x2, y2, color, width)
    nvgBeginPath(S.ctx)
    nvgMoveTo(S.ctx, x1, y1)
    nvgLineTo(S.ctx, x2, y2)
    nvgStrokeColor(S.ctx, C(color or S.col.line))
    nvgStrokeWidth(S.ctx, math.floor(width or 2))
    nvgStroke(S.ctx)
end

function UI.Circle(x, y, r, fill, stroke, strokeW)
    nvgBeginPath(S.ctx)
    nvgCircle(S.ctx, x, y, r)
    if fill then
        nvgFillColor(S.ctx, C(fill))
        nvgFill(S.ctx)
    end
    if stroke then
        nvgStrokeColor(S.ctx, C(stroke))
        nvgStrokeWidth(S.ctx, math.floor(strokeW or 2))
        nvgStroke(S.ctx)
    end
end

function UI.Bar(x, y, w, h, ratio, fill, back, stroke)
    ratio = math.max(0, math.min(1, ratio or 0))
    UI.Panel(x, y, w, h, h / 2, back or { 20, 18, 26, 255 })
    if ratio > 0 then
        nvgBeginPath(S.ctx)
        nvgRoundedRect(S.ctx, x, y, math.max(h, w * ratio), h, h / 2)
        nvgFillColor(S.ctx, C(fill or S.col.green))
        nvgFill(S.ctx)
    end
    if stroke then
        nvgBeginPath(S.ctx)
        nvgRoundedRect(S.ctx, x, y, w, h, h / 2)
        nvgStrokeColor(S.ctx, C(stroke))
        nvgStrokeWidth(S.ctx, 1)
        nvgStroke(S.ctx)
    end
end

-- 注册点击区域（设计坐标）
-- opts.press = true 时按下即触发（战斗里的攻击/技能键需要这种手感），
-- 否则默认「按下高亮、松手才触发」，避免误触和误跳转。
-- opts.selfHover = true 表示该控件自己画悬停效果（UI.Button 已内置放大高亮），
-- 通用悬停高亮就不会重复画。
function UI.Region(id, x, y, w, h, onClick, enabled, opts)
    S.regions[#S.regions + 1] = {
        id = id, x = x, y = y, w = w, h = h,
        onClick = onClick, enabled = enabled ~= false,
        press = (opts and opts.press) or false,
        selfHover = (opts and opts.selfHover) or false,
    }
end

local function Rgb(c, add)
    return { math.min(255, (c[1] or 0) + add), math.min(255, (c[2] or 0) + add),
        math.min(255, (c[3] or 0) + add), c[4] or 255 }
end

function UI.Button(id, x, y, w, h, label, onClick, opts)
    opts = opts or {}
    local enabled = opts.enabled ~= false
    local fill = opts.fill or S.col.panel2
    local stroke = opts.stroke or S.col.line
    local textColor = opts.textColor or S.col.text
    if not enabled then
        fill = { 40, 38, 48, 255 }
        stroke = { 56, 52, 66, 255 }
        textColor = { 110, 106, 120, 255 }
    end

    -- 鼠标悬停：略微放大 + 提亮 + 描边变亮（点击区域不变，避免边缘抖动）
    local hovered = false
    if enabled and S.hover then
        local hx, hy = S.hover.x, S.hover.y
        hovered = hx >= x and hx <= x + w and hy >= y and hy <= y + h
    end
    local dx0, dy0, dw, dh, fontSize = x, y, w, h, opts.fontSize or 22
    if hovered then
        local ex, ey = w * 0.035, h * 0.07
        dx0, dy0, dw, dh = x - ex, y - ey, w + ex * 2, h + ey * 2
        fontSize = fontSize + 1
        fill = Rgb(fill, 34)
        stroke = opts.accent and Rgb(opts.accent, 40) or S.col.cyan
    end

    UI.Panel(dx0, dy0, dw, dh, opts.radius or 10, fill, stroke, hovered and 2 or (opts.strokeW or 1))
    if opts.accent then
        nvgBeginPath(S.ctx)
        nvgRoundedRect(S.ctx, dx0, dy0, 4, dh, 2)
        nvgFillColor(S.ctx, C(hovered and Rgb(opts.accent, 30) or opts.accent))
        nvgFill(S.ctx)
    end
    UI.Text(dx0 + dw / 2, dy0 + dh / 2, fontSize, label, textColor,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    UI.Region(id, x, y, w, h, onClick, enabled, {
        press = opts.press, selfHover = true,
    })
end

-- 命中最上层区域（后画优先）
local function HitRegion(dx, dy)
    for i = #S.regions, 1, -1 do
        local r = S.regions[i]
        if r.enabled and dx >= r.x and dx <= r.x + r.w and dy >= r.y and dy <= r.y + r.h then
            return r
        end
    end
    return nil
end

-- 命中测试（无副作用）：右键走路时用它避开 UI 按钮
function UI.Hit(dx, dy)
    return HitRegion(dx, dy) ~= nil
end

-- 按下：只在区域上记录按住状态（press 型区域立即触发），松手时才真正执行 onClick
function UI.PointerDown(dx, dy, tid)
    local r = HitRegion(dx, dy)
    if not r then return false end
    S.uiPress = { id = r.id, x = r.x, y = r.y, w = r.w, h = r.h, tid = tid, fired = false }
    if r.press then
        S.uiPress.fired = true
        if r.onClick then r.onClick() end
    end
    return true
end

-- 松手：还在同一个区域上才算一次点击；手指/鼠标移出去就取消
function UI.PointerUp(dx, dy)
    local p = S.uiPress
    if not p then return false end
    S.uiPress = nil
    if p.fired then return true end
    local r
    if dx and dy then
        r = HitRegion(dx, dy)
    else
        -- 触屏抬手没有坐标：按 id 找回同一个控件
        for i = #S.regions, 1, -1 do
            local cand = S.regions[i]
            if cand.id == p.id then r = cand break end
        end
    end
    if r and r.id == p.id and r.enabled then
        if r.onClick then r.onClick() end
    end
    return true
end

-- 取消按压（切屏幕 / Esc / 弹层抢占输入时调用）
function UI.PointerCancel()
    S.uiPress = nil
end

-- 按压反馈：按住的那个按钮盖一层亮色 + 青色描边
function UI.DrawPress()
    local p = S.uiPress
    if not p then return end
    UI.Panel(p.x, p.y, p.w, p.h, 10, { 255, 255, 255, 20 }, S.col.cyan, 2)
end

-- 通用悬停反馈：鼠标下的可交互区域略微「鼓起来」+ 变色
-- 用外扩的圆角高亮框表现，不改动控件本身的绘制坐标（避免边缘抖动）
-- 只对桌面鼠标生效（触屏拖动不显示），并且跳过自己带悬停效果的按钮。
function UI.DrawHover()
    if not S.hoverIsMouse then return end
    local hx, hy = S.hover.x or -1, S.hover.y or -1
    if hx < 0 or hy < 0 then return end
    local hit
    for i = #S.regions, 1, -1 do
        local r = S.regions[i]
        if r.enabled and not r.selfHover
            and hx >= r.x and hx <= r.x + r.w and hy >= r.y and hy <= r.y + r.h then
            -- 过大的区域（整屏点击层、滚动列表容器）不画，否则会变成一个大框
            if r.w <= 520 and r.h <= 140 then
                hit = r
                break
            end
        end
    end
    if not hit then return end
    local g = 3
    UI.Panel(hit.x - g, hit.y - g, hit.w + g * 2, hit.h + g * 2, 8,
        { 255, 255, 255, 26 }, S.col.cyan, 2)
end

-- 命中测试：倒序，后画的优先
function UI.Click(dx, dy)
    for i = #S.regions, 1, -1 do
        local r = S.regions[i]
        if r.enabled and dx >= r.x and dx <= r.x + r.w and dy >= r.y and dy <= r.y + r.h then
            if r.onClick then r.onClick() end
            return true
        end
    end
    return false
end

function UI.SetToast(text, seconds)
    S.toast.text = text or ""
    S.toast.t = seconds or 2.0
end

function UI.DrawToast()
    if S.toast.t <= 0 or S.toast.text == "" then return end
    local w = 520
    local x = (S.designW - w) / 2
    local y = S.designH - 150
    UI.Panel(x, y, w, 56, 12, { 20, 18, 28, 235 }, S.col.line, 1)
    UI.Text(S.designW / 2, y + 28, 20, S.toast.text, S.col.text,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
end

function UI.UpdateToast(dt)
    if S.toast.t > 0 then
        S.toast.t = S.toast.t - dt
    end
end

function UI.FormatNumber(n)
    local s = tostring(math.floor(n or 0))
    local out = ""
    local count = 0
    for i = #s, 1, -1 do
        out = s:sub(i, i) .. out
        count = count + 1
        if count % 3 == 0 and i > 1 then
            out = "," .. out
        end
    end
    return out
end

return UI
