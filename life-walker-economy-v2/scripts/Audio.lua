-- Audio.lua — 背景音乐开关 / 音量 / 循环播放
local Audio = {}

---@type Scene?
local scene_ = nil
---@type SoundSource?
local source_ = nil
---@type Sound?
local sound_ = nil

local function Apply(data)
    if not source_ or not sound_ then return end
    local vol = 0.32
    if data and type(data.musicVolume) == "number" then vol = data.musicVolume end
    vol = math.max(0, math.min(1, vol))
    local on = not (data and data.musicOn == false)
    source_.gain = vol
    if on then
        if not source_:IsPlaying() then
            -- 循环是 Sound 资源上的属性（SoundSource 没有 looped 字段）
            sound_.looped = true
            source_:Play(sound_, 0, vol)
        end
    else
        source_:Stop()
    end
end
Audio.Apply = Apply

-- 移动端 / 网页端：创建 Scene + SoundSource 会让运行时直接崩（不是普通 Lua 报错，pcall 兜不住），
-- 所以先在这些平台上整块跳过背景音乐，保证游戏能跑
local supported = true

local function PlatformBlocksAudio()
    local ok, blocked = pcall(function()
        local P = require("urhox-libs.Platform.PlatformUtils")
        return P.IsMobilePlatform() or P.IsWebPlatform()
    end)
    return (not ok) or blocked == true
end

-- 临时开关：先整块关掉背景音乐，用于确认手机端启动崩溃是不是音频引起的。
-- 确认后再把这条改回 false，并换成移动端可用的音频写法。
local AUDIO_DISABLED = true

---@param data table
function Audio.Init(data)
    if AUDIO_DISABLED then
        supported = false
        print("[Audio] 背景音乐已临时关闭（AUDIO_DISABLED），跳过 Scene/SoundSource 初始化")
        return
    end
    if PlatformBlocksAudio() then
        supported = false
        print("[Audio] 当前平台（移动端/网页端）跳过背景音乐，避免音频播放器初始化崩溃")
        return
    end
    pcall(function()
        scene_ = Scene()
        local node = scene_:CreateChild("Music")
        source_ = node:CreateComponent("SoundSource")
        sound_ = GetCache():GetResource("Sound", "audio/bgm_canon.wav")
        Apply(data)
    end)
end

---@param data table
---@param on boolean
function Audio.SetEnabled(data, on)
    data.musicOn = on and true or false
    pcall(function() Apply(data) end)
end

---@param data table
---@param volume number
function Audio.SetVolume(data, volume)
    data.musicVolume = math.max(0, math.min(1, volume))
    pcall(function() Apply(data) end)
end

function Audio.Update(dt)
    if scene_ then
        pcall(function() scene_:Update(dt) end)
    end
end

function Audio.Shutdown()
    if source_ then
        pcall(function() source_:Stop() end)
    end
    scene_ = nil
    source_ = nil
    sound_ = nil
end

return Audio
