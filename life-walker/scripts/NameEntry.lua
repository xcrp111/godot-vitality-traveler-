-- NameEntry.lua — 进入游戏前的昵称登记（类似常见手游的「起个名字」）
--
-- 交互：
--   · 手机端唤起系统软键盘（支持中文输入法），监听引擎 TextInput 事件
--   · 桌面端直接用键盘打字，退格删除，回车确认
--   · 也可以直接点「随机」拿一个名字
local UI = require "UI"
local S = require "State"
local Config = require "Config"

local NameEntry = {}

local MAX_CHARS = 8
local RANDOM_POOL = {
    "夜行者", "晨跑者", "早睡君", "清水", "肺叶旅人", "心跳节拍",
    "内境旅人", "小行者", "光之种", "呼吸练习生", "慢跑の猫", "青苔",
}

local st = {
    open = false,
    text = "",
    onDone = nil,
    caretT = 0,
}

local PANEL = { x = 300, y = 190, w = 680, h = 340 }

function NameEntry.IsOpen()
    return st.open
end

local function SetKeyboard(on)
    pcall(function()
        if input and input.SetScreenKeyboardVisible then
            input:SetScreenKeyboardVisible(on and true or false)
        end
    end)
end

local function RandomName()
    return RANDOM_POOL[math.random(#RANDOM_POOL)]
end

--- 打开登记界面；onDone(name) 在确认后调用
function NameEntry.Open(onDone)
    st.open = true
    st.text = (S.data and type(S.data.playerName) == "string") and S.data.playerName or ""
    if st.text == "" then st.text = RandomName() end
    st.onDone = onDone
    st.caretT = 0
    SetKeyboard(true)
end

function NameEntry.Close(confirm)
    if not st.open then return end
    local name = st.text
    if confirm and name == "" then name = RandomName() end
    st.open = false
    SetKeyboard(false)
    local cb = st.onDone
    st.onDone = nil
    if confirm and cb then cb(name) end
end

--- 引擎 TextInput 事件（全局函数名回调）
function NameEntryOnText(eventType, eventData)
    if not st.open then return end
    local ok, text = pcall(function() return eventData["Text"]:GetString() end)
    if not ok or type(text) ~= "string" then return end
    for ch in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        if ch:byte() >= 32 then
            local n = utf8.len(st.text) or 0
            if n < MAX_CHARS then st.text = st.text .. ch end
        end
    end
end

function NameEntry.Backspace()
    if st.text == "" then return end
    local n = utf8.len(st.text) or 0
    if n <= 1 then st.text = ""; return end
    local cut = utf8.offset(st.text, n)
    if cut then st.text = st.text:sub(1, cut - 1) end
end

function NameEntry.Confirm()
    NameEntry.Close(true)
end

function NameEntry.Text()
    return st.text
end

function NameEntry.Update(dt)
    if not st.open then return end
    st.caretT = (st.caretT + (dt or 0)) % 1
end

local function ButtonRect(id)
    if id == "ok" then
        return { x = PANEL.x + PANEL.w - 300, y = PANEL.y + PANEL.h - 84, w = 130, h = 46 }
    elseif id == "random" then
        return { x = PANEL.x + PANEL.w - 160, y = PANEL.y + PANEL.h - 84, w = 120, h = 46 }
    end
    return { x = 0, y = 0, w = 0, h = 0 }
end

function NameEntry.Pointer(phase, dx, dy)
    if not st.open then return false end
    if phase ~= "down" then return true end
    local ok = ButtonRect("ok")
    if dx >= ok.x and dx <= ok.x + ok.w and dy >= ok.y and dy <= ok.y + ok.h then
        NameEntry.Confirm()
        return true
    end
    local rnd = ButtonRect("random")
    if dx >= rnd.x and dx <= rnd.x + rnd.w and dy >= rnd.y and dy <= rnd.y + rnd.h then
        st.text = RandomName()
        return true
    end
    return true
end

function NameEntry.Draw()
    if not st.open then return end
    local W = Config.DESIGN_W
    UI.FillScreen({ 6, 8, 12, 214 })

    UI.Panel(PANEL.x, PANEL.y, PANEL.w, PANEL.h, 18, { 22, 22, 33, 252 }, S.col.line, 1)
    UI.Text(PANEL.x + 40, PANEL.y + 34, 30, "给自己起个名字", S.col.gold)
    UI.Text(PANEL.x + 40, PANEL.y + 82, 14,
        "这是你在内境里的名字，导师和以后遇到的人都会这样称呼你。", S.col.dim)
    UI.Text(PANEL.x + 40, PANEL.y + 104, 13,
        "1～8 个字，可以是中文、英文或数字，之后想改随时可以在角色面板里改。", S.col.dim)

    -- 输入框
    local bx, by, bw, bh = PANEL.x + 40, PANEL.y + 146, PANEL.w - 80, 64
    UI.Panel(bx, by, bw, bh, 12, { 14, 16, 24, 255 }, S.col.cyan, 2)
    local name = st.text ~= "" and st.text or "（点下面「随机」或直接打字）"
    local color = st.text ~= "" and S.col.text or { 130, 130, 145 }
    UI.Text(bx + 22, by + bh / 2, 26, name, color, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    -- 光标
    if st.text ~= "" then
        local wok, textW = pcall(function()
            nvgFontFaceId(S.ctx, S.font)
            nvgFontSize(S.ctx, 26)
            return nvgTextBounds(S.ctx, 0, 0, st.text, nil)
        end)
        local cx = bx + 22 + ((wok and textW) or 100) + 4
        if st.caretT < 0.55 then
            UI.Line(cx, by + 16, cx, by + bh - 16, S.col.cyan, 2)
        end
    end
    UI.Text(bx + bw - 16, by + 12, 12,
        string.format("%d/%d", utf8.len(st.text) or 0, MAX_CHARS), S.col.dim,
        NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)

    -- 按钮
    local ok = ButtonRect("ok")
    UI.Button("name_ok", ok.x, ok.y, ok.w, ok.h, "就叫这个", function() end,
        { fontSize = 16, accent = S.col.green, fill = { 40, 74, 52, 255 },
            stroke = { 90, 150, 105, 255 } })
    local rnd = ButtonRect("random")
    UI.Button("name_random", rnd.x, rnd.y, rnd.w, rnd.h, "随机", function() end,
        { fontSize = 15, fill = { 42, 40, 58, 255 }, stroke = S.col.line })

    UI.Text(PANEL.x + 40, PANEL.y + PANEL.h - 62, 12,
        "手机端点输入框会弹出键盘；桌面端直接打字，回车确认。", S.col.dim)
end

return NameEntry
