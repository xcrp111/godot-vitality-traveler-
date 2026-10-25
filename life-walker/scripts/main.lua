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
local VirtualControls = require "urhox-libs.UI.VirtualControls"

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

function Start()
    graphics.windowTitle = Config.GAME_TITLE
    Layout()

    S.ctx = nvgCreate(1)
    if not S.ctx then
        print("[main] ERROR: nvgCreate failed")
        return
    end

    S.font = nvgCreateFont(S.ctx, "sans", "Fonts/MiSans-Regular.ttf")
    if S.font == -1 then
        print("[main] WARNING: font load failed")
    end

    VirtualControls.Initialize(Config.DESIGN_W, Config.DESIGN_H)

    math.randomseed(os.time())

    S.data = Save.Load()
    Config.SetClass(Save.ActiveClass(S.data))
    if S.data.unlocked < 1 then S.data.unlocked = 1 end
    S.selectedLevel = S.data.unlocked
    S.screen = "menu"

    -- 背景音乐（简单循环，无音频设备时静默跳过）
    Audio.Init(S.data)

    SubscribeToEvent(S.ctx, "NanoVGRender", "HandleRender")
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("MouseButtonDown", "HandleMouseDown")
    SubscribeToEvent("TouchBegin", "HandleTouchBegin")
    SubscribeToEvent("KeyDown", "HandleKeyDown")
    SubscribeToEvent("KeyUp", "HandleKeyUp")

    print(string.format("[main] 生命行者 v%s started, logical=%dx%d dpr=%.2f scale=%.3f",
        Config.VERSION, S.W, S.H, S.dpr, S.scale))
end

function Stop()
    Audio.Shutdown()
    VirtualControls.Shutdown()
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

    if S.screen == "combat" and S.combat then
        Combat.Update(dt)
    end
end

function HandleRender(eventType, eventData)
    if not S.ctx then return end
    nvgBeginFrame(S.ctx, graphics:GetWidth(), graphics:GetHeight(), S.dpr)

    S.regions = {}
    UI.BeginDesign()

    -- 背景
    local bg = nvgLinearGradient(S.ctx, 0, 0, 0, Config.DESIGN_H,
        nvgRGBA(26, 20, 36, 255), nvgRGBA(12, 10, 18, 255))
    nvgBeginPath(S.ctx)
    nvgRect(S.ctx, 0, 0, Config.DESIGN_W, Config.DESIGN_H)
    nvgFillPaint(S.ctx, bg)
    nvgFill(S.ctx)

    if S.screen == "menu" then
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

    UI.DrawToast()
    UI.EndDesign()
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
    UI.Click(dx, dy)
end

---@param eventType string
---@param eventData TouchBeginEventData
function HandleTouchBegin(eventType, eventData)
    local px = eventData["X"]:GetInt()
    local py = eventData["Y"]:GetInt()
    local dx, dy = UI.ToDesign(px, py)
    UI.Click(dx, dy)
end

---@param eventType string
---@param eventData KeyDownEventData
function HandleKeyDown(eventType, eventData)
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
        if S.settings then
            S.settings = false
        elseif S.confirmReset then
            S.confirmReset = false
        elseif S.test then
            S.test = false
        elseif S.compendium then
            S.compendium = false
        elseif S.screen == "combat" and S.combat and S.combat.showBuffs then
            if S.combat.buffDetail then
                S.combat.buffDetail = nil
            else
                S.combat.showBuffs = false
            end
        elseif S.skillPicker then
            S.skillPicker = false
        elseif S.screen == "reward" then
            Run.SkipReward()
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
