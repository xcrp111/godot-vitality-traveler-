-- main.lua — 生命行者 入口
-- 纯 NanoVG 2D 渲染 + urhox-libs VirtualControls（虚拟摇杆 / 技能键）

local Config = require "Config"
local Save = require "Save"
local UI = require "UI"
local S = require "State"
local Menu = require "Menu"
local Run = require "Run"
local Combat = require "Combat"
local Screens = require "Screens"
local Audio = require "Audio"
local KbLayout = require "KbLayout"

-- 设备端 urhox-libs/Engine/i18n 会把 string.format 换成一个包装函数，而 Lua 5.4 的 %d
-- 一旦收到「带小数的浮点」（比如 screensize / dpr 得到的 989.53），会直接抛
-- "number has no integer representation"，把所在的 Start / Update / Draw 整段打断。
-- 测试壳只会笼统弹一句 "Game script Start() failed"，从表象完全看不出是这里。
-- 所以这里统一给整型占位符的浮点参数取整：任何一个漏改的调用点都不会再炸。
do
    local rawFormat = string.format
    local ALL_SPEC = "diouxXeEfgGaAcs"   -- 全部转换符，用来判断一个格式串写完了没
    local INT_SPEC = "diouxXc"           -- 需要整数的转换符
    local function formatIntSafe(fmt, ...)
        if type(fmt) ~= "string" then return rawFormat(fmt, ...) end
        local args = table.pack(...)
        local idx, i, n = 1, 1, #fmt
        while i <= n do
            local p = string.find(fmt, "%", i, true)
            if not p or p >= n then break end
            local j = p + 1
            if string.sub(fmt, j, j) == "%" then
                i = j + 1            -- 转义的 %%
            else
                local k, conv = j, nil
                while k <= n do
                    local ch = string.sub(fmt, k, k)
                    if string.find(ALL_SPEC, ch, 1, true) then conv = ch; break end
                    k = k + 1
                end
                if not conv then break end
                if string.find(INT_SPEC, conv, 1, true) then
                    local v = args[idx]
                    -- math.floor 对整数原样返回；对浮点给出整数值（可表示时是 integer 子类型）
                    if type(v) == "number" then args[idx] = math.floor(v) end
                end
                idx = idx + 1
                i = k + 1
            end
        end
        return rawFormat(fmt, table.unpack(args, 1, args.n))
    end
    string.format = formatIntSafe
end

local function Layout()
    local physW = graphics:GetWidth()
    local physH = graphics:GetHeight()
    local dpr = graphics:GetDPR()
    if not dpr or dpr <= 0 then dpr = 1 end
    S.W = physW / dpr
    S.H = physH / dpr
    S.dpr = dpr
    S.scale = math.min(S.W / Config.DESIGN_W, S.H / Config.DESIGN_H)
    S.offX = (S.W - Config.DESIGN_W * S.scale) / 2
    S.offY = (S.H - Config.DESIGN_H * S.scale) / 2
end

-- 启动期错误：记录下来并画到屏幕上，方便在手机上定位（引擎只会笼统报 Start() failed）
local startError = nil
local startStage = "init"

local function DrawStartError(msg)
    local ctx = S.ctx
    nvgBeginPath(ctx)
    nvgRect(ctx, 0, 0, Config.DESIGN_W, Config.DESIGN_H)
    nvgFillColor(ctx, nvgRGBA(40, 12, 16, 255))
    nvgFill(ctx)
    UI.Text(48, 48, 26, "启动失败 / Start() failed", { 255, 120, 120, 255 })
    UI.Text(48, 92, 16, "阶段: " .. tostring(startStage), { 255, 200, 140, 255 })
    nvgFontFaceId(ctx, S.font)
    nvgFontSize(ctx, 15)
    nvgTextAlign(ctx, math.floor(NVG_ALIGN_LEFT + NVG_ALIGN_TOP))
    nvgFillColor(ctx, nvgRGBA(240, 232, 240, 255))
    nvgTextBox(ctx, 48, 124, Config.DESIGN_W - 96, tostring(msg), nil)
    UI.Text(48, Config.DESIGN_H - 40, 14, "把这一屏截图发我就能定位", { 180, 176, 200, 255 })
end

-- 按阶段初始化：每步单独 pcall，某一步失败不会拖垮整个启动
local function Boot()
    startStage = "layout"
    Layout()

    startStage = "font"
    S.font = nvgCreateFont(S.ctx, "sans", "Fonts/MiSans-Regular.ttf")
    if S.font == -1 then
        print("[main] WARNING: font load failed")
    end

    startStage = "save"
    local okSave, saveResult = pcall(Save.Load)
    if okSave and type(saveResult) == "table" then
        S.data = saveResult
    else
        -- 手机 / 网页端可能没有存档文件系统：用全新存档兜底，保证能玩
        print("[main] WARNING: save load failed, using fresh data: " .. tostring(saveResult))
        S.data = Save.Fresh()
    end
    startStage = "class"
    Config.SetClass(Save.ActiveClass(S.data))
    if S.data.unlocked < 1 then S.data.unlocked = 1 end
    S.selectedLevel = Save.MaxPlayable(S.data)
    S.screen = "menu"

    -- 画面设置：帧率上限（超低端机可以靠它省电/稳帧）
    startStage = "video"
    pcall(function()
        S.data.fpsCap = S.data.fpsCap or 60
        if engine then engine.maxFps = S.data.fpsCap end
    end)

    -- 背景音乐（无音频设备时静默跳过）
    startStage = "audio"
    pcall(Audio.Init, S.data)

    startStage = "done"
end

function Start()
    S.ctx = nvgCreate(1)
    if not S.ctx then
        print("[main] ERROR: nvgCreate failed")
        return
    end

    -- 先订阅事件：这样即使后面初始化失败，也能把错误画到屏幕上
    SubscribeToEvent(S.ctx, "NanoVGRender", "HandleRender")
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("MouseButtonDown", "HandleMouseDown")
    SubscribeToEvent("MouseButtonUp", "HandleMouseUp")
    SubscribeToEvent("MouseMove", "HandleMouseMove")
    SubscribeToEvent("TouchBegin", "HandleTouchBegin")
    SubscribeToEvent("TouchMove", "HandleTouchMove")
    SubscribeToEvent("TouchEnd", "HandleTouchEnd")
    SubscribeToEvent("KeyDown", "HandleKeyDown")
    SubscribeToEvent("KeyUp", "HandleKeyUp")

    local ok, err = xpcall(Boot, function(e)
        local tb = e
        local okTb, trace = pcall(function() return debug.traceback("", 2) end)
        if okTb and trace then tb = tostring(e) .. "\n" .. trace end
        return tostring(tb)
    end)
    if not ok then
        startError = err
        print("[main] START FAILED at [" .. tostring(startStage) .. "]: " .. tostring(err))
        return
    end

    print(string.format("[main] 生命行者 v%s started, logical=%dx%d dpr=%.2f scale=%.3f",
        Config.VERSION, math.floor(S.W), math.floor(S.H), S.dpr, S.scale))
end

function Stop()
    Audio.Shutdown()
    if S.ctx then
        nvgDelete(S.ctx)
        S.ctx = nil
    end
end

local lastW, lastH = 0, 0
local resizeTimer = 0.0

local function UpdateKeyboardInput()
    local k = S.keys
    local x, y = 0, 0
    if k.left then x = x - 1 end
    if k.right then x = x + 1 end
    if k.up then y = y - 1 end
    if k.down then y = y + 1 end
    local len = math.sqrt(x * x + y * y)
    if len > 0 then
        S.input.x = x / len
        S.input.y = y / len
        k.active = true
    elseif k.active then
        S.input.x = 0
        S.input.y = 0
        k.active = false
    end
end

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    S.time = S.time + dt
    if startError or not S.data then return end   -- 启动失败时只画错误屏
    local okUp, errUp = xpcall(function()
        UI.UpdateToast(dt)
        Audio.Update(dt)
        -- 窗口尺寸变化：重新计算设计画布；战斗中的虚拟按键也要重建
        local w, h = graphics:GetWidth(), graphics:GetHeight()
        if w ~= lastW or h ~= lastH then
            lastW, lastH = w, h
            Layout()
            resizeTimer = 0.25
        end
        if resizeTimer > 0 then
            resizeTimer = resizeTimer - dt
            if resizeTimer <= 0 then
                resizeTimer = 0
                if S.screen == "combat" and S.combat then
                    Combat.RebuildControls(S.combat)
                end
            end
        end

        UpdateKeyboardInput()

        -- 健康弹层（久坐提醒 / 冥想）：计时并接管输入
        Menu.UpdateOverlays(dt)
        if Menu.OverlayActive() then
            S.input.x = 0
            S.input.y = 0
        elseif S.screen == "combat" and S.combat and not S.combat.paused then
            Combat.Update(dt)
        end
    end, function(e) return tostring(e) end)
    if not okUp then
        print("[main] UPDATE ERROR: " .. tostring(errUp))
    end
end

local function DrawFrame()
    UI.BeginDesign()
    local ok, err = xpcall(function()
        -- 背景（纯色填充，不再用渐变，避免手机端 NanoVG 渐变路径出问题）
        nvgBeginPath(S.ctx)
        nvgRect(S.ctx, 0, 0, Config.DESIGN_W, Config.DESIGN_H)
        nvgFillColor(S.ctx, nvgRGBA(22, 17, 30, 255))
        nvgFill(S.ctx)

        if startError or not S.data then
            DrawStartError(startError or "启动未完成（S.data 为空）")
        elseif KbLayout.IsOpen() then
            KbLayout.Draw()
        elseif S.screen == "menu" then
            Menu.Draw()
        elseif S.screen == "map" then
            Screens.DrawMap()
        elseif S.screen == "combat" then
            Combat.Draw()
        elseif S.screen == "shop" then
            Screens.DrawShop()
        elseif S.screen == "event" then
            Screens.DrawEvent()
        elseif S.screen == "reward" then
            Screens.DrawReward()
        elseif S.screen == "levelclear" then
            Screens.DrawLevelClear()
        elseif S.screen == "gameover" then
            Screens.DrawGameOver()
        end

        -- 健康弹层画在最上层
        Menu.DrawOverlays()

        UI.DrawToast()
    end, function(e) return tostring(e) end)
    UI.EndDesign()
    return ok, err
end

function HandleRender(eventType, eventData)
    if not S.ctx then return end
    nvgBeginFrame(S.ctx, graphics:GetWidth(), graphics:GetHeight(), S.dpr)

    S.regions = {}
    local ok, err = DrawFrame()
    if not ok then
        -- 单帧渲染出错不拖垮后续帧，只写日志
        print("[main] FRAME ERROR: " .. tostring(err))
    end

    nvgEndFrame(S.ctx)
end

---@param eventType string
---@param eventData MouseButtonDownEventData
function HandleMouseDown(eventType, eventData)
    local button = eventData["Button"]:GetInt()
    if button ~= MOUSEB_LEFT then return end
    local px = eventData["X"]:GetInt()
    local py = eventData["Y"]:GetInt()
    local dx, dy = UI.ToDesign(px, py)
    if Menu.OverlayPointer("down", dx, dy) then return end
    if KbLayout.IsOpen() then
        KbLayout.Pointer("down", dx, dy)
        return
    end
    if Combat.AimPointer("down", dx, dy, 0) then return end
    if Combat.JoystickPointer("down", dx, dy) then return end
    UI.Click(dx, dy)
end

---@param eventType string
---@param eventData MouseMoveEventData
function HandleMouseMove(eventType, eventData)
    local px = eventData["X"]:GetInt()
    local py = eventData["Y"]:GetInt()
    local dx, dy = UI.ToDesign(px, py)
    if Menu.OverlayPointer("move", dx, dy) then return end
    if KbLayout.IsOpen() then
        KbLayout.Pointer("move", dx, dy)
        return
    end
    if Combat.AimPointer("move", dx, dy, 0) then return end
    if S.screen ~= "combat" then return end
    Combat.JoystickPointer("move", dx, dy)
end

---@param eventType string
---@param eventData MouseButtonUpEventData
function HandleMouseUp(eventType, eventData)
    if eventData["Button"]:GetInt() ~= MOUSEB_LEFT then return end
    local px = eventData["X"]:GetInt()
    local py = eventData["Y"]:GetInt()
    local dx, dy = UI.ToDesign(px, py)
    if Menu.OverlayPointer("up", dx, dy) then return end
    if KbLayout.IsOpen() then
        KbLayout.Pointer("up", dx, dy)
        return
    end
    if Combat.AimPointer("up", dx, dy, 0) then return end
    Combat.JoystickPointer("up", dx, dy)
end

---@param eventType string
---@param eventData TouchBeginEventData
function HandleTouchBegin(eventType, eventData)
    local px = eventData["X"]:GetInt()
    local py = eventData["Y"]:GetInt()
    local tid = nil
    pcall(function() tid = eventData["TouchID"]:GetInt() end)
    local dx, dy = UI.ToDesign(px, py)
    if Menu.OverlayPointer("down", dx, dy) then return end
    if KbLayout.IsOpen() then
        KbLayout.Pointer("down", dx, dy)
        return
    end
    if Combat.AimPointer("down", dx, dy, tid or 0) then return end
    if Combat.JoystickPointer("down", dx, dy, tid) then return end
    UI.Click(dx, dy)
end

---@param eventType string
---@param eventData TouchMoveEventData
function HandleTouchMove(eventType, eventData)
    local px = eventData["X"]:GetInt()
    local py = eventData["Y"]:GetInt()
    local tid = nil
    pcall(function() tid = eventData["TouchID"]:GetInt() end)
    local dx, dy = UI.ToDesign(px, py)
    if Menu.OverlayPointer("move", dx, dy) then return end
    if KbLayout.IsOpen() then
        KbLayout.Pointer("move", dx, dy)
        return
    end
    if Combat.AimPointer("move", dx, dy, tid or 0) then return end
    if S.screen ~= "combat" then return end
    Combat.JoystickPointer("move", dx, dy, tid)
end

---@param eventType string
---@param eventData TouchEndEventData
function HandleTouchEnd(eventType, eventData)
    local tid = nil
    pcall(function() tid = eventData["TouchID"]:GetInt() end)
    if Menu.OverlayPointer("up", 0, 0) then return end
    if KbLayout.IsOpen() then
        KbLayout.Pointer("up", 0, 0)
        return
    end
    if Combat.AimPointer("up", 0, 0, tid or 0) then return end
    Combat.JoystickPointer("up", 0, 0, tid)
end

---@param eventType string
---@param eventData KeyDownEventData
function HandleKeyDown(eventType, eventData)
    if Menu.OverlayActive() then return end
    local key = eventData["Key"]:GetInt()
    if key == KEY_W then S.keys.up = true end
    if key == KEY_S then S.keys.down = true end
    if key == KEY_A then S.keys.left = true end
    if key == KEY_D then S.keys.right = true end

    if S.screen == "combat" and S.combat then
        local isRepeat = eventData["Repeat"]:GetBool()
        if not isRepeat then
            if key == KEY_SPACE then
                Combat.ManualAttack()
            elseif key == KEY_J then
                Combat.CastSkill(1)
            elseif key == KEY_K then
                Combat.CastSkill(2)
            elseif key == KEY_L then
                Combat.CastSkill(3)
            elseif key == KEY_E then
                Combat.UseItem()
            elseif key == KEY_TAB then
                Combat.ToggleBuffPanel()
            end
        end
    end

    if key == KEY_ESCAPE then
        if KbLayout.IsOpen() then
            KbLayout.Close(true)
        elseif S.healthTasks then
            S.healthTasks = false
        elseif S.endlessPanel then
            S.endlessPanel = false
        elseif S.guild then
            S.guild = false
        elseif S.settings then
            S.settings = false
            S.settingsWipeConfirm = false
        elseif S.confirmReset then
            S.confirmReset = false
        elseif S.test then
            S.test = false
        elseif S.compendium then
            S.compendium = false
        elseif S.screen == "combat" and S.combat and S.combat.showBuffs then
            if S.combat.statusPanel and S.combat.statusPanel.detail then
                S.combat.statusPanel.detail = nil
            else
                S.combat.showBuffs = false
            end
        elseif S.screen == "combat" and S.combat then
            Combat.TogglePause()
        elseif S.showStatus then
            S.showStatus = false
        elseif S.skillPicker then
            S.skillPicker = false
        elseif S.screen == "reward" then
            if S.reward and S.reward.pending then
                Run.CancelReplace()
            else
                Run.SkipReward()
            end
        elseif S.screen ~= "menu" then
            Run.ReturnToMenu()
        end
    end
end

---@param eventType string
---@param eventData KeyUpEventData
function HandleKeyUp(eventType, eventData)
    local key = eventData["Key"]:GetInt()
    if key == KEY_W then S.keys.up = false end
    if key == KEY_S then S.keys.down = false end
    if key == KEY_A then S.keys.left = false end
    if key == KEY_D then S.keys.right = false end
end
