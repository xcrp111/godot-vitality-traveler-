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
function UI.Region(id, x, y, w, h, onClick, enabled)
    S.regions[#S.regions + 1] = {
        id = id, x = x, y = y, w = w, h = h,
        onClick = onClick, enabled = enabled ~= false,
    }
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
    UI.Panel(x, y, w, h, opts.radius or 10, fill, stroke, opts.strokeW or 1)
    if opts.accent then
        nvgBeginPath(S.ctx)
        nvgRoundedRect(S.ctx, x, y, 4, h, 2)
        nvgFillColor(S.ctx, C(opts.accent))
        nvgFill(S.ctx)
    end
    UI.Text(x + w / 2, y + h / 2, opts.fontSize or 22, label, textColor,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    UI.Region(id, x, y, w, h, onClick, enabled)
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
