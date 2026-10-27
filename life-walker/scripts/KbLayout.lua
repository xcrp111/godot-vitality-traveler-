-- KbLayout.lua — 按键布局编辑：拖动摆位置、点选后调大小，存进存档
local Config = require "Config"
local Save = require "Save"
local S = require "State"
local UI = require "UI"

local KbLayout = {}

-- 可调整的控件（id 要和 Combat 里 CtrlPos 用的 key 一致）
local ELEMENTS = {
    { id = "joy",    label = "摇杆",   minR = 46, maxR = 118 },
    { id = "attack", label = "普攻",   minR = 30, maxR = 84 },
    { id = "skill1", label = "技能1",  minR = 22, maxR = 68 },
    { id = "skill2", label = "技能2",  minR = 22, maxR = 68 },
    { id = "skill3", label = "技能3",  minR = 22, maxR = 68 },
    { id = "items",  label = "道具",   minR = 18, maxR = 52 },
    { id = "aim_cancel", label = "取消施法框", minR = 50, maxR = 130, box = true },
}

-- 矩形控件（目前只有取消施法框）：中心 + 半径 -> 外框
local function BoxOf(p)
    return p.x - p.r, p.y - p.r * 0.6, p.r * 2, p.r * 1.2
end
KbLayout.BoxOf = BoxOf

local TOOLBAR = {
    { id = "smaller", label = "缩小", x = 40,  y = 72, w = 120, h = 44 },
    { id = "larger",  label = "放大", x = 176, y = 72, w = 120, h = 44 },
    { id = "reset",   label = "重置", x = 312, y = 72, w = 120, h = 44 },
    { id = "done",    label = "完成", x = 1080, y = 72, w = 160, h = 44 },
}

-- 摇杆行为开关（文字随状态变化，单独放一行）
local TOGGLE_Y = 132
local TOGGLE_H = 40
local toggles = {
    { id = "joymode", x = 40,  w = 230 },
    { id = "follow",  x = 290, w = 230 },
}

local function ElementDef(id)
    for _, e in ipairs(ELEMENTS) do
        if e.id == id then return e end
    end
    return nil
end

local function State()
    if type(S.kbEdit) ~= "table" then
        S.kbEdit = { active = false, sel = "joy", dragging = false }
    end
    return S.kbEdit
end

function KbLayout.Open()
    local st = State()
    st.active = true
    st.sel = "joy"
    st.dragging = false
    Save.Layout(S.data)
end

function KbLayout.IsOpen()
    return State().active == true
end

function KbLayout.Close(save)
    local st = State()
    st.active = false
    st.dragging = false
    if save then Save.Write(S.data) end
end

local function HitElement(x, y)
    local L = Save.Layout(S.data)
    -- 从上层（后面的）往前找，保证重叠时选到画在最上面的
    for i = #ELEMENTS, 1, -1 do
        local e = ELEMENTS[i]
        local p = L[e.id]
        if p then
            if e.box then
                local bx, by, bw, bh = BoxOf(p)
                if x >= bx - 8 and x <= bx + bw + 8 and y >= by - 8 and y <= by + bh + 8 then
                    return e.id
                end
            else
                local d = math.sqrt((x - p.x) ^ 2 + (y - p.y) ^ 2)
                if d <= p.r + 14 then return e.id end
            end
        end
    end
    return nil
end

local function HitToolbar(x, y)
    for _, b in ipairs(TOOLBAR) do
        if x >= b.x and x <= b.x + b.w and y >= b.y and y <= b.y + b.h then
            return b.id
        end
    end
    for _, t in ipairs(toggles) do
        if x >= t.x and x <= t.x + t.w and y >= TOGGLE_Y and y <= TOGGLE_Y + TOGGLE_H then
            return t.id
        end
    end
    return nil
end

local function JoyModeLabel(data)
    return "摇杆：" .. ((data.joyMode == "fixed") and "固定位置" or "按下即定位")
end

local function FollowLabel(data)
    return "拖尾跟随：" .. ((data.joyFollow ~= false) and "开" or "关")
end

-- phase: "down" / "move" / "up"；x、y 为设计坐标
function KbLayout.Pointer(phase, x, y)
    local st = State()
    if not st.active then return false end
    local L = Save.Layout(S.data)

    if phase == "down" then
        local tb = HitToolbar(x, y)
        if tb then
            if tb == "done" then
                KbLayout.Close(true)
            elseif tb == "reset" then
                Save.ResetLayout(S.data)
            elseif tb == "joymode" then
                S.data.joyMode = (S.data.joyMode == "fixed") and "float" or "fixed"
                Save.Write(S.data)
            elseif tb == "follow" then
                S.data.joyFollow = not (S.data.joyFollow ~= false)
                Save.Write(S.data)
            else
                local def = ElementDef(st.sel)
                local p = L[st.sel]
                if def and p then
                    local step = def.id == "joy" and 6 or 4
                    if tb == "larger" then
                        p.r = math.min(def.maxR, p.r + step)
                    else
                        p.r = math.max(def.minR, p.r - step)
                    end
                end
            end
            return true
        end
        local hit = HitElement(x, y)
        if hit then
            st.sel = hit
            st.dragging = true
            return true
        end
        -- 点空白处：取消选择状态，但仍算消费掉，避免误触到下面的菜单
        st.dragging = false
        return true
    elseif phase == "move" then
        if st.dragging then
            local p = L[st.sel]
            if p then
                local r = p.r
                p.x = math.max(r, math.min(Config.DESIGN_W - r, x))
                p.y = math.max(r, math.min(Config.DESIGN_H - r, y))
            end
            return true
        end
        return false
    elseif phase == "up" then
        if st.dragging then
            st.dragging = false
            Save.Write(S.data)
            return true
        end
        return false
    end
    return false
end

function KbLayout.Draw()
    local st = State()
    if not st.active then return end
    local L = Save.Layout(S.data)

    -- 背景
    nvgBeginPath(S.ctx)
    nvgRect(S.ctx, 0, 0, Config.DESIGN_W, Config.DESIGN_H)
    nvgFillColor(S.ctx, nvgRGBA(14, 12, 20, 255))
    nvgFill(S.ctx)

    -- 画布边框（提示可放范围）
    nvgBeginPath(S.ctx)
    nvgRect(S.ctx, 1, 1, Config.DESIGN_W - 2, Config.DESIGN_H - 2)
    nvgStrokeColor(S.ctx, nvgRGBA(90, 84, 110, 120))
    nvgStrokeWidth(S.ctx, 2)
    nvgStroke(S.ctx)

    UI.Text(40, 26, 24, "按键布局", S.col.text)
    local cur = ElementDef(st.sel)
    UI.Text(180, 34, 14,
        "拖动摆放 · 当前选中：" .. (cur and cur.label or "-") .. "（点 缩小/放大 调大小）",
        S.col.dim)

    -- 工具栏
    for _, b in ipairs(TOOLBAR) do
        UI.Button("kb_" .. b.id, b.x, b.y, b.w, b.h, b.label,
            function() KbLayout.Pointer("down", b.x + b.w / 2, b.y + b.h / 2) end,
            { fill = b.id == "done" and { 44, 92, 62, 255 } or S.col.panel2 })
    end

    -- 摇杆行为开关
    for _, t in ipairs(toggles) do
        local label = t.id == "joymode" and JoyModeLabel(S.data) or FollowLabel(S.data)
        local active = (t.id == "joymode" and S.data.joyMode ~= "fixed")
            or (t.id == "follow" and S.data.joyFollow ~= false)
        UI.Button("kb_" .. t.id, t.x, TOGGLE_Y, t.w, TOGGLE_H, label,
            function() KbLayout.Pointer("down", t.x + t.w / 2, TOGGLE_Y + TOGGLE_H / 2) end,
            {
                fontSize = 14,
                fill = active and { 40, 68, 88, 255 } or S.col.panel2,
                stroke = active and S.col.cyan or S.col.line,
            })
    end

    -- 控件
    for _, e in ipairs(ELEMENTS) do
        local p = L[e.id]
        if p then
            local selected = (st.sel == e.id)
            if e.box then
                local bx, by, bw, bh = BoxOf(p)
                UI.Panel(bx, by, bw, bh, 12, { 40, 38, 54, 220 },
                    selected and { 255, 210, 120, 255 } or { 140, 140, 165, 220 }, selected and 4 or 2)
                local cx, cy = bx + bw / 2, by + bh / 2 - 10
                local rr = math.min(16, bh * 0.24)
                UI.Line(cx - rr, cy - rr, cx + rr, cy + rr,
                    selected and { 255, 210, 120, 255 } or { 190, 190, 210, 220 }, 3)
                UI.Line(cx - rr, cy + rr, cx + rr, cy - rr,
                    selected and { 255, 210, 120, 255 } or { 190, 190, 210, 220 }, 3)
                UI.Text(cx, by + bh - 18, 12, e.label,
                    selected and S.col.gold or S.col.dim, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            elseif e.id == "joy" then
                UI.Circle(p.x, p.y, p.r, { 30, 60, 100, 90 },
                    selected and { 255, 210, 120, 255 } or { 120, 170, 230, 200 }, selected and 4 or 2)
                UI.Circle(p.x, p.y, p.r * 0.35, { 120, 170, 230, 200 })
            else
                UI.Circle(p.x, p.y, p.r, { 40, 38, 54, 220 },
                    selected and { 255, 210, 120, 255 } or { 140, 140, 165, 220 }, selected and 4 or 2)
                UI.Text(p.x, p.y - 7, 13, e.label,
                    selected and S.col.gold or S.col.dim, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            end
        end
    end

    -- 道具槽的提示（3 个连排，只有第一个能拖）
    local ip = L.items
    if ip then
        for i = 2, 3 do
            local x = ip.x + (i - 1) * (ip.r * 2 + 12)
            UI.Circle(x, ip.y, ip.r, nil, { 120, 118, 140, 120 }, 2)
        end
    end

    UI.Text(40, Config.DESIGN_H - 40, 13,
        "「重置」恢复默认位置和大小 · 「完成」保存并返回；浮动模式下按下左半屏任意位置即定位摇杆", S.col.dim)
end

return KbLayout
