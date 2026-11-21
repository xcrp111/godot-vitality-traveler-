-- lobby_runtime.lua — 自定义大厅入口（multiplayer.lobby_runtime 指定的脚本）
--
-- 重要：这里**不使用 urhox-libs/UI**，而是用项目自己的 NanoVG 界面（UI.lua）。
-- 原因：urhox-libs/UI 会自己创建并持有一个 NanoVG 上下文与字体图集，
-- 在联机模式下会和游戏本体的上下文冲突——表现为「所有文字都画不出来」。
-- 用项目自己的 UI 绘制层，大厅和游戏共用一套上下文，就不会互相污染。
--
-- 两个分支：
--   1. 单机开始：直接跑项目现有的单人玩法（不需要网络）
--   2. 联机进入：建房 → 开战 → 连服务器 → 进游戏后客户端同步云端农场
--
-- 入口契约：返回 function(ctx)，ctx = { client, root }（root 不用，我们自绘）

local Config = require "Config"
local S = require "State"
local UI = require "UI"

return function(ctx)
    local client = ctx and ctx.client or nil

    local state = { screen = "home", status = "", roomId = nil }
    local active = true

    -- ---------------------------------------------------------------- 画布准备
    local function Layout()
        local dpr = graphics:GetDPR()
        if not dpr or dpr <= 0 then dpr = 1 end
        local w, h = graphics:GetWidth() / dpr, graphics:GetHeight() / dpr
        S.W, S.H, S.dpr = w, h, dpr
        S.scale = math.min(w / Config.DESIGN_W, h / Config.DESIGN_H)
        S.offX = (w - Config.DESIGN_W * S.scale) / 2
        S.offY = (h - Config.DESIGN_H * S.scale) / 2
    end

    if not S.ctx then S.ctx = nvgCreate(1) end
    Layout()
    if not S.font or S.font == -1 then
        S.font = nvgCreateFont(S.ctx, "sans", "Fonts/MiSans-Game.ttf")
        if not S.font or S.font == -1 then
            S.font = nvgCreateFont(S.ctx, "sans", "Fonts/MiSans-Regular.ttf")
        end
    end

    --- 启动游戏前把自己的 NanoVG 上下文销毁：否则新旧两个上下文会抢字体图集，
    --- 表现为进游戏后所有文字画不出来（字体创建返回 -1）
    local function ReleaseGfx()
        if S.ctx then
            pcall(function() UnsubscribeFromEvent(S.ctx, "NanoVGRender") end)
            pcall(function() nvgDelete(S.ctx) end)
            S.ctx = nil
            S.font = nil
        end
    end

    -- ---------------------------------------------------------------- 启动游戏
    local function StartLocalGame()
        state.screen = "connecting"
        state.status = "正在启动单机模式…"
        active = false
        ReleaseGfx()
        local ok, err = pcall(function()
            require "main"
            if type(Start) == "function" then Start() end
        end)
        if not ok then
            state.screen = "error"
            state.status = "单机启动失败：" .. tostring(err)
            return
        end
        active = false          -- 让大厅停止绘制，画面交给游戏
    end

    local function StartGameNow()
        active = false
        ReleaseGfx()
        if not client then
            state.screen = "error"
            state.status = "当前环境不支持联机"
            return
        end
        state.screen = "connecting"
        state.status = "正在连接服务器…"
        client:StartGame({
            onStarted = function() state.status = "服务器正在准备…" end,
            onMatchFound = function() state.status = "服务器已分配，正在进服…" end,
            onProgress = function(progress, message)
                state.status = string.format("%s %d%%",
                    tostring(message or "连接中"), math.floor((progress or 0) * 100))
            end,
            onError = function(code, message)
                state.screen = "error"
                state.status = string.format("开始游戏失败（%s）：%s", tostring(code), tostring(message))
            end,
        })
    end

    local function CreateRoom()
        if not client then
            state.screen = "error"
            state.status = "当前环境不支持联机"
            return
        end
        state.screen = "connecting"
        state.status = "正在创建房间…"
        client:CreateRoom({
            onCreated = function(roomId)
                state.roomId = roomId
                StartGameNow()
            end,
            onError = function(code, message)
                state.screen = "error"
                state.status = string.format("创建房间失败（%s）：%s", tostring(code), tostring(message))
            end,
        })
    end

    -- ---------------------------------------------------------------- 绘制
    function LobbyRender()
        if not active or not S.ctx then return end
        Layout()
        nvgBeginFrame(S.ctx, graphics:GetWidth(), graphics:GetHeight(), S.dpr)
        S.regions = {}

        UI.BeginDesign()
        UI.FillScreen({ 14, 16, 20 })

        local cx = Config.DESIGN_W / 2
        UI.Text(cx, 120, 44, "生命行者", { 240, 226, 170 }, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        UI.Text(cx, 176, 15, "健康生活 × 肉鸽战斗", { 180, 176, 200 },
            NVG_ALIGN_CENTER + NVG_ALIGN_TOP)

        if state.screen == "home" then
            UI.Button("lobby_local", cx - 180, 250, 360, 54, "单机开始（离线可玩）", function()
                StartLocalGame()
            end, { fontSize = 18, accent = { 150, 235, 170 },
                fill = { 40, 96, 64, 255 }, stroke = { 120, 200, 140 } })

            UI.Button("lobby_online", cx - 180, 322, 360, 54, "联机进入（好友浇水 / 偷菜）", function()
                CreateRoom()
            end, { fontSize = 18, fill = { 44, 60, 96, 255 }, stroke = { 120, 170, 230 } })

            UI.Text(cx, 400, 12, "联机需要网络；单机不需要，玩法完全一样。", { 150, 150, 165 },
                NVG_ALIGN_CENTER + NVG_ALIGN_TOP)

        else
            UI.Text(cx, 250, 18, state.status or "", { 230, 230, 240 },
                NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
            if state.roomId then
                UI.Text(cx, 284, 12, "房间号 " .. tostring(state.roomId), { 160, 160, 180 },
                    NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
            end
            if state.screen == "error" then
                UI.Button("lobby_back", cx - 180, 330, 360, 46, "返回", function()
                    state.screen = "home"; state.status = ""; state.roomId = nil
                end, { fontSize = 15 })
            end
            UI.Button("lobby_retry_local", cx - 180, 392, 360, 46, "仍然单机开始", function()
                StartLocalGame()
            end, { fontSize = 15, fill = { 40, 96, 64, 255 }, stroke = { 120, 200, 140 } })
        end

        UI.EndDesign()
        nvgEndFrame(S.ctx)
    end

    -- ---------------------------------------------------------------- 输入
    function LobbyMouseDown(eventType, eventData)
        if not active then return end
        if eventData["Button"]:GetInt() ~= MOUSEB_LEFT then return end
        local dx, dy = UI.ToDesign(eventData["X"]:GetInt(), eventData["Y"]:GetInt())
        UI.PointerDown(dx, dy, 0)
    end

    function LobbyMouseUp(eventType, eventData)
        if not active then return end
        if eventData["Button"]:GetInt() ~= MOUSEB_LEFT then return end
        local dx, dy = UI.ToDesign(eventData["X"]:GetInt(), eventData["Y"]:GetInt())
        UI.PointerUp(dx, dy)
    end

    function LobbyTouchBegin(eventType, eventData)
        if not active then return end
        local tid = nil
        pcall(function() tid = eventData["TouchID"]:GetInt() end)
        local dx, dy = UI.ToDesign(eventData["X"]:GetInt(), eventData["Y"]:GetInt())
        UI.PointerDown(dx, dy, tid or 0)
    end

    function LobbyTouchEnd(eventType, eventData)
        if not active then return end
        UI.PointerUp(nil, nil)
    end

    SubscribeToEvent(S.ctx, "NanoVGRender", "LobbyRender")
    SubscribeToEvent("MouseButtonDown", "LobbyMouseDown")
    SubscribeToEvent("MouseButtonUp", "LobbyMouseUp")
    SubscribeToEvent("TouchBegin", "LobbyTouchBegin")
    SubscribeToEvent("TouchEnd", "LobbyTouchEnd")

    return {
        stop = function()
            active = false
            UnsubscribeFromEvent(S.ctx, "NanoVGRender")
            UnsubscribeFromEvent("MouseButtonDown")
            UnsubscribeFromEvent("MouseButtonUp")
            UnsubscribeFromEvent("TouchBegin")
            UnsubscribeFromEvent("TouchEnd")
        end,
    }
end
