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
local Sfx = require "Sfx"
local KbLayout = require "KbLayout"
local PetUI = require "PetUI"
local TitleUI = require "TitleUI"
local SceneUI = require "SceneUI"
local FarmUI = require "FarmUI"
local FriendUI = require "FriendUI"
local DevPanel = require "DevPanel"
local RankUI = require "RankUI"
local LevelCards = require "LevelCards"
local FarmWalk = require "FarmWalk"
local Cloud = require "Cloud"
local Art = require "Art"

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
    -- 字体：优先项目自带子集；联机模式下资源可能是「边玩边下」，启动瞬间还没就位，
    -- 所以失败时依次降级，并且留一个每帧重试（见 HandleUpdate 里的 fontRetry）
    local function loadFont(path)
        local id = nvgCreateFont(S.ctx, "sans", path)
        if id and id ~= -1 then return id end
        return nil
    end
    local FONT_PATHS = {
        "Fonts/MiSans-Game.ttf",
        "Fonts/MiSans-Regular.ttf",
        "Fonts/MiSans-Nickname.ttf",
        "MiSans-Game.ttf",
        "assets/Fonts/MiSans-Game.ttf",
    }
    for _, path in ipairs(FONT_PATHS) do
        local id = nvgCreateFont(S.ctx, "sans_" .. path:gsub("[^%w]", "_"), path)
        if id and id ~= -1 then
            S.font = id
            S.fontPath = path
            break
        end
    end
    if not S.font then
        S.font = -1
        S.fontRetry = 1800          -- 每 30 帧试一次，最长约 90 秒（联机客户端资源可能很晚才到）
        print("[main] WARNING: font load failed, will retry")
    else
        print("[main] font ok id=" .. tostring(S.font))
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
    S.screen = "title"
    S.panelMode = nil
    SceneUI.Init()

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
    -- 输入处理器会直接调这些模块：缺一个会让点击静默失效，启动时就把问题打出来
    local okModules, moduleErr = pcall(function()
        assert(PetUI and PetUI.Pointer and PetUI.Wheel, "PetUI 未正确加载")
    end)
    if not okModules then
        print("[main] MODULE ERROR: " .. tostring(moduleErr))
    end

    -- 主界面/标题界面用到的贴图先加载，避免首帧空白
    pcall(function()
        Art.Preload({ "art/title_bg.jpg", "art/home_bg.jpg", "art/hero_idle.png" })
    end)
end

--- 判断当前进程是不是服务端：优先 IsServerMode()，其次看引擎注入的玩家认证表
local function IsServerProcess()
    if IsServerMode then
        local okS, v = pcall(IsServerMode)
        if okS and v then return true end
    end
    if type(SERVER_PLAYER_AUTH_INFOS) == "table" and next(SERVER_PLAYER_AUTH_INFOS) ~= nil then
        return true
    end
    return false
end

function Start()
    -- 服务端模式：只跑农场数据服务，不需要渲染
    if IsServerProcess() then
        print("[main] SERVER MODE: starting farm data service")
        local ok, err = xpcall(function()
            local FarmServer = require "network.FarmServer"
            FarmServer.Start()
        end, function(e) return tostring(e) end)
        if not ok then print("[main] SERVER START ERROR: " .. tostring(err)) end
        return
    end

    -- 大厅可能已经建过 NanoVG 上下文：复用同一个，避免两套字体图集互相干扰
    if not S.ctx then
        S.ctx = nvgCreate(1)
        if not S.ctx then
            print("[main] ERROR: nvgCreate failed")
            return
        end
    end

    -- 先订阅事件：这样即使后面初始化失败，也能把错误画到屏幕上
    SubscribeToEvent(S.ctx, "NanoVGRender", "HandleRender")
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("MouseButtonDown", "HandleMouseDown")
    SubscribeToEvent("MouseButtonUp", "HandleMouseUp")
    SubscribeToEvent("MouseMove", "HandleMouseMove")
    SubscribeToEvent("MouseWheel", "HandleMouseWheel")
    SubscribeToEvent("TouchBegin", "HandleTouchBegin")
    SubscribeToEvent("TouchMove", "HandleTouchMove")
    SubscribeToEvent("TouchEnd", "HandleTouchEnd")
    SubscribeToEvent("KeyDown", "HandleKeyDown")
    SubscribeToEvent("KeyUp", "HandleKeyUp")

    -- 昵称登记：接系统文本输入（手机端走软键盘输入法）
    pcall(function() require("NameEntry") end)
    pcall(function() SubscribeToEvent("TextInput", "NameEntryOnText") end)

    -- 农场联机：只有在真连上服务器时才初始化（单机模式下完全不碰云变量，避免影响排行榜）
    S.farmNetEnabled = false
    pcall(function() SubscribeToEvent("ClientConnected", "HandleFarmClientConnected") end)

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
    Sfx.Shutdown()
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
        Sfx.Update(dt)
        -- 离开战斗时停掉暴风雪 / 静电场这类循环音效，避免回到菜单还在响
        if S.screen ~= "combat" then Sfx.StopAllLoops() end
        TitleUI.Update(dt)
        SceneUI.Update(dt)
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

        -- 云变量轮询：拉服务端回包
        if S.screen then
            pcall(function()
                require("network.FarmClient").Poll(S.time or 0)
            end)
        end

        -- 联机同步重试：按时间（每秒一次，最长 60 秒），每次都记日志方便排查
        do
            S.farmNetClock = (S.farmNetClock or 0) + dt
            local FarmClient = require "network.FarmClient"
            if not FarmClient.online and S.farmNetClock >= 1 then
                S.farmNetClock = 0
                local hasConn = false
                if network and network.GetServerConnection then
                    local okC, conn = pcall(function() return network:GetServerConnection() end)
                    hasConn = okC and conn ~= nil
                end
                if hasConn then
                    S.farmNetTries = (S.farmNetTries or 0) + 1
                    if S.farmNetTries <= 60 then
                        if not FarmClient.cloudMode then
                            FarmClient.EnableCloudTransport()
                            FarmClient.Sync("")
                            print("[FarmNet] 检测到服务器连接，已启用云通道")
                        else
                            FarmClient.Sync("")
                        end
                    end
                end
            end
        end

        UpdateKeyboardInput()

        -- 健康弹层（久坐提醒 / 冥想）：计时并接管输入
        Menu.UpdateOverlays(dt)
        pcall(function() require("Story").Update(dt) end)
        pcall(function() require("NameEntry").Update(dt) end)
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
        -- 背景：铺满整个物理屏幕（含 letterbox），屏幕上下不会出现未绘制的灰框
        UI.FillScreen(S.col.bg)

        if startError or not S.data then
            DrawStartError(startError or "启动未完成（S.data 为空）")
        elseif KbLayout.IsOpen() then
            KbLayout.Draw()
        elseif S.screen == "title" then
            TitleUI.Draw()
        elseif S.screen == "menu" then
            if S.levelCards then
                LevelCards.Draw()
            elseif S.farm then
                FarmUI.Draw()
                if S.friendOpen then FriendUI.Draw() end
            elseif S.rank then
                RankUI.Draw()
            else
            -- 场景是主界面；任意子面板打开时改画面板（面板内部自己 dispatch）
            local panelOpen = S.panelMode or S.bag or S.pet or S.camp or S.guild or S.settings
                or S.compendium or S.healthTasks or S.endlessPanel or S.test or S.skillPicker
                or S.classDetail
            if panelOpen then
                if S.panelMode and not (S.bag or S.pet or S.camp or S.guild or S.settings or S.compendium) then
                    -- 主界面子面板：场景压暗当背景，只画对应模块
                    SceneUI.DrawPanelBg()
                    if S.panelMode == "char" then
                        Menu.DrawCharacter()
                    elseif S.panelMode == "sports" then
                        Menu.DrawSports()
                    else
                        Menu.DrawLevels()
                    end
                    SceneUI.DrawPanelBack()
                    -- 叠加层（选技能 / 图鉴 / 设置等）画在子面板之上，关掉后回到原子面板
                    if S.skillPicker or S.compendium or S.settings or S.healthTasks
                        or S.endlessPanel or S.test or S.classDetail then
                        Menu.Draw()
                    end
                else
                    Menu.Draw()
                end
            else
                SceneUI.Draw()
            end
            end
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

        -- 开发工具面板：盖在所有界面之上
        if S.devPanel then DevPanel.Draw() end

        -- 按钮按住时的反馈（画在所有控件之上）
        UI.DrawPress()
        -- 鼠标悬停：可交互区域略微抬起 + 变色（只在主界面/面板里做）
        if S.screen == "menu" then UI.DrawHover() end

        UI.DrawToast()
        FontDiagDraw()
    end, function(e) return tostring(e) end)
    UI.EndDesign()
    return ok, err
end

--- 主动检查服务器连接（联机模式下脚本可能比连接更晚启动，ClientConnected 已经错过）
function TryWireFarmSync(verbose)
    if not (network and network.GetServerConnection) then
        if verbose then print("[FarmNet] 当前不是联网模式") end
        return false
    end
    local okConn, conn = pcall(function() return network:GetServerConnection() end)
    if not okConn or not conn then
        if verbose then print("[FarmNet] 还没有服务器连接") end
        return false
    end
    local FarmClient = require "network.FarmClient"
    if FarmClient.online then return true end
    -- 云变量模式：不要接管远程事件（会把云传输覆盖掉），直接重发同步即可
    if FarmClient.cloudMode then
        local sent = FarmClient.Sync("")
        if verbose then
            print(string.format("[FarmNet] 云通道重发同步 sent=%s tries=%s",
                tostring(sent), tostring(S.farmNetTries or 0)))
        end
        return true
    end
    -- 远程事件模式：接管连接并重发
    FarmClient.UseConnection(conn)
    local sent = FarmClient.Sync("")
    if verbose then
        print(string.format("[FarmNet] 已发送同步请求 sent=%s tries=%s",
            tostring(sent), tostring(S.farmNetTries or 0)))
    end
    return true
end

--- 连上服务器：接入农场同步（离线模式不会触发）
function HandleFarmClientConnected(eventType, eventData)
    local ok, err = xpcall(function()
        local FarmClient = require "network.FarmClient"
        local conn = eventData:GetPtr("Connection", "Connection")
        if not conn then return end
        FarmClient.UseConnection(conn)
        -- 昵称：拿得到就用，拿不到服务端保留原名
        local name = ""
        if GetUserNickname then
            pcall(function()
                local uid = GetUserId and GetUserId() or nil
                if uid then
                    GetUserNickname({
                        userIds = { uid },
                        onSuccess = function(list)
                            if list and list[1] and list[1].nickname then name = list[1].nickname end
                            FarmClient.Sync(name)
                        end,
                        onError = function() FarmClient.Sync("") end,
                    })
                end
            end)
        end
        if name == "" then FarmClient.Sync(name) end
    end, function(e) return tostring(e) end)
    if not ok then print("[main] FARM CLIENT CONNECT ERROR: " .. tostring(err)) end
end


-- ---------------------------------------------------------------- 文字诊断（开发期用）
-- 联机模式下出现过「所有文字画不出来」的问题，这台机器没法真机调试，
-- 所以用几个彩色圆点把关键状态编码出来，截图就能定位：
--   1 绿 = 字体创建成功 / 红 = 失败
--   2 绿 = nvgText 未被第三方接管 / 紫 = 被 i18n 之类的包装过
--   3 绿 = 测量"测试"宽度 > 0（真正能排字）/ 红 = 宽 0
--   4 绿 = 当前绘制上下文 == 创建字体时的上下文 / 红 = 不一致
--   5 绿 = 当前字号 > 0 / 红 = 字号为 0（会被缩成看不见）
local fontDiagCtx = nil
local rawNvgText = nvgText

function FontDiagDraw()
    if not S.dev or not S.ctx then return end
    local checks = {}
    checks[1] = (S.font and S.font ~= -1) and { 90, 220, 130 } or { 230, 90, 90 }
    checks[2] = (nvgText == rawNvgText) and { 90, 220, 130 } or { 190, 130, 230 }
    local w = 0
    if S.font and S.font ~= -1 then
        if fontDiagCtx ~= S.ctx then fontDiagCtx = S.ctx end
        local okCall, res = pcall(function()
            nvgFontFaceId(S.ctx, S.font)
            nvgFontSize(S.ctx, 20)
            return nvgTextBounds(S.ctx, 0, 0, "测试", nil)
        end)
        if okCall and type(res) == "number" then w = res end
    end
    checks[3] = w > 0 and { 90, 220, 130 } or { 230, 90, 90 }
    checks[4] = (fontDiagCtx == nil or fontDiagCtx == S.ctx) and { 90, 220, 130 } or { 230, 90, 90 }
    local okSize, size = pcall(function() return nvgGetFontSize(S.ctx) end)
    checks[5] = (okSize and type(size) == "number" and size > 0) and { 90, 220, 130 } or { 230, 90, 90 }

    for i = 1, 5 do
        local c = checks[i] or { 150, 150, 150 }
        nvgBeginPath(S.ctx)
        nvgCircle(S.ctx, 24 + (i - 1) * 22, Config.DESIGN_H - 24, 8)
        nvgFillColor(S.ctx, nvgRGBA(c[1], c[2], c[3], 230))
        nvgFill(S.ctx)
    end
    -- 第 6 个点：文字宽度能做到多少（绿越多说明排字越正常）
    local bars = math.min(10, math.floor((w or 0) / 8))
    for i = 1, bars do
        nvgBeginPath(S.ctx)
        nvgRect(S.ctx, 150 + (i - 1) * 10, Config.DESIGN_H - 30, 6, 12)
        nvgFillColor(S.ctx, nvgRGBA(120, 200, 240, 220))
        nvgFill(S.ctx)
    end
end

--- 字体在 Boot 阶段可能建不出来（联机时资源/GL 还没完全就绪），
--- 放到渲染阶段重试：这是真正有 GL 上下文、能建字体图集的时机
-- 玩家昵称是运行时输入的，字集无法预知：给主字体挂一份常用汉字 fallback
local function AttachNickFallback()
    if not S.font or S.font == -1 or S.nickFallback then return end
    if os.clock() - (S.nickTryAt or -99) < 0.5 then return end
    S.nickTryAt = os.clock()
    local ok, id = pcall(function()
        return nvgCreateFont(S.ctx, "nick_fallback", "Fonts/MiSans-Nickname.ttf")
    end)
    if ok and type(id) == "number" and id ~= -1 then
        pcall(function() nvgAddFallbackFontId(S.ctx, S.font, id) end)
        S.nickFallback = id
        print("[main] nickname fallback attached id=" .. tostring(id))
    end
    -- 再兜一层：引擎自带的完整字体（设备上有，本地 CLI 可能没有）
    local ok2, id2 = pcall(function()
        return nvgCreateFont(S.ctx, "engine_fallback", "Fonts/MiSans-Regular.ttf")
    end)
    if ok2 and type(id2) == "number" and id2 ~= -1 then
        pcall(function() nvgAddFallbackFontId(S.ctx, S.font, id2) end)
        print("[main] engine fallback attached id=" .. tostring(id2))
    end
end

local function TryLoadFont()
    if S.font and S.font ~= -1 then return true end
    if os.clock() - (S.fontLastTry or -99) < 0.5 then return false end
    S.fontLastTry = os.clock()
    S.fontTryTag = (S.fontTryTag or 0) + 1
    local tag = "fontTry" .. S.fontTryTag
    for _, path in ipairs({ "Fonts/MiSans-Game.ttf", "Fonts/MiSans-Regular.ttf",
        "Fonts/MiSans-Nickname.ttf", "MiSans-Game.ttf", "assets/Fonts/MiSans-Game.ttf" }) do
        local id = nvgCreateFont(S.ctx, tag .. path:gsub("[^%w]", "_"), path)
        if id and id ~= -1 then
            S.font = id
            S.fontPath = path
            print("[main] font recovered in render id=" .. tostring(id) .. " path=" .. path)
            return true
        end
    end
    if (S.fontTryTag % 20) == 1 then
        print("[main] font still failing in render, try=" .. tostring(S.fontTryTag))
    end
    return false
end

function HandleRender(eventType, eventData)
    if not S.ctx then return end
    if not S.font or S.font == -1 then TryLoadFont() end
    AttachNickFallback()
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
---@param eventData MouseWheelEventData
function HandleMouseWheel(eventType, eventData)
    local wheel = 0
    pcall(function() wheel = eventData["Wheel"]:GetInt() end)
    if wheel == 0 then return end
    if PetUI.Wheel(wheel) then return end
end

---@param eventType string
---@param eventData MouseButtonDownEventData
function HandleMouseDown(eventType, eventData)
    local button = eventData["Button"]:GetInt()
    local px = eventData["X"]:GetInt()
    local py = eventData["Y"]:GetInt()
    local dx, dy = UI.ToDesign(px, py)

    -- 右键 = 场景里走路（左键留给 UI 按钮，避免点面板时角色乱跑）
    if button == (MOUSEB_RIGHT or 2) then
        if not Menu.OverlayActive() and not KbLayout.IsOpen()
            and S.screen == "menu" and not S.panelMode
            and not UI.Hit(dx, dy) then
            SceneUI.GroundClick(dx, dy)
        end
        return
    end

    if button ~= MOUSEB_LEFT then return end
    S.hoverIsMouse = true
    S.clickDX, S.clickDY = dx, dy
    if Menu.OverlayPointer("down", dx, dy) then UI.PointerCancel() return end
    if KbLayout.IsOpen() then
        KbLayout.Pointer("down", dx, dy)
        return
    end
    if SceneUI.Pointer("down", dx, dy, 0) then return end
    if Combat.AimPointer("down", dx, dy, 0) then return end
    if Combat.JoystickPointer("down", dx, dy) then return end
    if PetUI.Pointer("down", dx, dy) then return end
    -- 左键只走 UI；没点到控件就什么也不做（走路改用右键）
    UI.PointerDown(dx, dy, 0)
end

---@param eventType string
---@param eventData MouseMoveEventData
function HandleMouseMove(eventType, eventData)
    local px = eventData["X"]:GetInt()
    local py = eventData["Y"]:GetInt()
    local dx, dy = UI.ToDesign(px, py)
    S.hover.x, S.hover.y = dx, dy
    S.hoverIsMouse = true
    if Menu.OverlayPointer("move", dx, dy) then return end
    if KbLayout.IsOpen() then
        KbLayout.Pointer("move", dx, dy)
        return
    end
    if SceneUI.Pointer("move", dx, dy, 0) then return end
    if Combat.AimPointer("move", dx, dy, 0) then return end
    if PetUI.Pointer("move", dx, dy) then return end
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
    if SceneUI.Pointer("up", dx, dy, 0) then return end
    if Combat.AimPointer("up", dx, dy, 0) then return end
    if Combat.JoystickPointer("up", dx, dy) then return end
    if PetUI.Pointer("up", dx, dy) then return end
    UI.PointerUp(dx, dy)
end

---@param eventType string
---@param eventData TouchBeginEventData
function HandleTouchBegin(eventType, eventData)
    local px = eventData["X"]:GetInt()
    local py = eventData["Y"]:GetInt()
    local tid = nil
    pcall(function() tid = eventData["TouchID"]:GetInt() end)
    local dx, dy = UI.ToDesign(px, py)
    S.touchMode = true                 -- 见过触屏：主场景显示左下方向摇杆
    S.clickDX, S.clickDY = dx, dy
    if Menu.OverlayPointer("down", dx, dy) then UI.PointerCancel() return end
    if KbLayout.IsOpen() then
        KbLayout.Pointer("down", dx, dy)
        return
    end
    if SceneUI.Pointer("down", dx, dy, tid or 0) then return end
    if Combat.AimPointer("down", dx, dy, tid or 0) then return end
    if Combat.JoystickPointer("down", dx, dy, tid) then return end
    if PetUI.Pointer("down", dx, dy) then return end
    if not UI.PointerDown(dx, dy, tid) then SceneUI.GroundClick(dx, dy) end
end

---@param eventType string
---@param eventData TouchMoveEventData
function HandleTouchMove(eventType, eventData)
    local px = eventData["X"]:GetInt()
    local py = eventData["Y"]:GetInt()
    local tid = nil
    pcall(function() tid = eventData["TouchID"]:GetInt() end)
    local dx, dy = UI.ToDesign(px, py)
    S.hover.x, S.hover.y = dx, dy
    S.hoverIsMouse = false
    if Menu.OverlayPointer("move", dx, dy) then return end
    if KbLayout.IsOpen() then
        KbLayout.Pointer("move", dx, dy)
        return
    end
    if SceneUI.Pointer("move", dx, dy, tid or 0) then return end
    if Combat.AimPointer("move", dx, dy, tid or 0) then return end
    if PetUI.Pointer("move", dx, dy) then return end
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
    if SceneUI.Pointer("up", 0, 0, tid or 0) then return end
    if Combat.AimPointer("up", 0, 0, tid or 0) then return end
    Combat.JoystickPointer("up", 0, 0, tid)
    if PetUI.Pointer("up", 0, 0) then return end
    UI.PointerUp(nil, nil)
end

---@param eventType string
---@param eventData KeyDownEventData
function HandleKeyDown(eventType, eventData)
    local key = eventData["Key"]:GetInt()
    -- 昵称登记：退格删除 / 回车确认
    local okNE, NameEntry = pcall(require, "NameEntry")
    if okNE and NameEntry and NameEntry.IsOpen() then
        if key == KEY_BACKSPACE then
            NameEntry.Backspace()
        elseif key == KEY_RETURN or key == KEY_ENTER then
            NameEntry.Confirm()
        end
        return
    end
    -- 剧情：空格 / 回车 翻页
    local okStory, Story = pcall(require, "Story")
    if okStory and Story and Story.IsOpen() then
        if key == KEY_SPACE or key == KEY_RETURN or key == KEY_ENTER then Story.Advance() end
        return
    end
    if Menu.OverlayActive() then return end
    if key == KEY_W or key == KEY_UP then S.keys.up = true end
    if key == KEY_S or key == KEY_DOWN then S.keys.down = true end
    if key == KEY_A or key == KEY_LEFT then S.keys.left = true end
    if key == KEY_D or key == KEY_RIGHT then S.keys.right = true end

    -- 初始界面：Enter / 空格开始游戏
    if S.screen == "title" then
        if key == KEY_RETURN or key == KEY_ENTER or key == KEY_SPACE then
            TitleUI.StartGame()
        end
        return
    end

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
if S.farm and (S.farmTab or 1) == 1 then
                    FarmWalk.Interact()
                else
                    Combat.UseItem()
                end
            elseif key == KEY_TAB then
                Combat.ToggleBuffPanel()
            end
        end
    elseif S.screen == "menu" and not S.panelMode then
        -- 主界面场景：E 与身旁的物件互动，G 开关坐标网格
        pcall(function()
            if not eventData["Repeat"]:GetBool() and key == KEY_E then
                SceneUI.Interact()
            elseif not eventData["Repeat"]:GetBool() and key == KEY_G then
                SceneUI.ToggleGrid()
            end
        end)
    end

    if key == KEY_ESCAPE then
        UI.PointerCancel()
        if KbLayout.IsOpen() then
            KbLayout.Close(true)
        elseif S.levelCards then
            LevelCards.Close()
            S.panelMode = "levels"
        elseif S.devPanel then
            DevPanel.Close()
        elseif S.friendOpen then
            FriendUI.Close()
        elseif S.farm then
            S.farm = false
        elseif S.rank then
            S.rank = false
        elseif S.healthTasks then
            S.healthTasks = false
        elseif S.pet then
            S.pet = false
            S.petPickLow = false
        elseif S.bag then
            S.bag = false
        elseif S.camp then
            S.camp = false
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
        elseif S.classDetail then
            S.classDetail = false
        elseif S.skillPicker then
            S.skillPicker = false
        elseif S.panelMode then
            S.panelMode = nil
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
    if key == KEY_UP then S.keys.up = false end
    if key == KEY_DOWN then S.keys.down = false end
    if key == KEY_LEFT then S.keys.left = false end
    if key == KEY_RIGHT then S.keys.right = false end
    if key == KEY_W then S.keys.up = false end
    if key == KEY_S then S.keys.down = false end
    if key == KEY_A then S.keys.left = false end
    if key == KEY_D then S.keys.right = false end
end
