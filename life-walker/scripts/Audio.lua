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

---@param data table
function Audio.Init(data)
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
