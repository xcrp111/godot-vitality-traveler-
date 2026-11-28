-- Audio.lua — 背景音乐（卡农）/ 开关 / 音量 / 循环播放
-- 曲目：Pachelbel – Canon in D（钢琴），CC Public Domain Mark 1.0，可商用
-- 来源与授权见 music_preview/README.md
local Audio = {}

local BGM_PATH = "audio/bgm_canon.ogg"
local MEDITATE_PATH = "audio/bgm_meditate.ogg"
local DEFAULT_VOLUME = 0.32

---@type Scene?
local scene_ = nil
---@type SoundSource?
local source_ = nil
---@type Sound?
local sound_ = nil

---@type table?
local data_ = nil

-- 冥想音乐：单独一条音轨，冥想时淡入，同时把主 BGM 压低
---@type SoundSource?
local medSource_ = nil
---@type Sound?
local medSound_ = nil
local meditateOn = false
local medGainLevel = 0
local mainGainLevel = nil

-- 延迟到启动若干秒后再初始化：Start() 里做重活容易触发手机端首帧看门狗，
-- 之前音频就是在启动阶段创建 Scene/SoundSource，被怀疑为崩溃来源。
local temp_ = {}   -- 临时音源（排查/试听）
local pool_ = {}      -- 固定音源池：复用，避免每次播放都创建节点导致延迟
local poolIdx_ = 0
local POOL_SIZE = 12
local initDelay = 1.5
local initAttempts = 0
local failed = false
local retryTimer = 0.0

local function Volume()
    local v = DEFAULT_VOLUME
    if data_ and type(data_.musicVolume) == "number" then v = data_.musicVolume end
    return math.max(0, math.min(1, v))
end

local function Wanted()
    return not (data_ and data_.musicOn == false)
end

local function Apply()
    if not source_ or not sound_ then return end
    local vol = Volume()
    if Wanted() then
        source_.gain = vol
        if not source_:IsPlaying() then
            sound_.looped = true
            source_:Play(sound_, 0, vol)
        end
    else
        source_:Stop()
    end
end
Audio.Apply = Apply

local function InitNow()
    if scene_ or failed then return end
    initAttempts = initAttempts + 1
    local ok, err = pcall(function()
        scene_ = Scene()
        local node = scene_:CreateChild("Music")
        source_ = node:CreateComponent("SoundSource")
        source_.soundType = SOUND_MUSIC
        sound_ = GetCache():GetResource("Sound", BGM_PATH)
    end)
    if not ok or not scene_ or not source_ or not sound_ then
        -- 资源可能还在后台下载（DWP）：过一会儿再试；连续失败就放弃，不影响游戏
        scene_, source_, sound_ = nil, nil, nil
        if initAttempts >= 6 then
            failed = true
            print("[Audio] 背景音乐加载失败，已跳过：" .. tostring(err))
        else
            initDelay = 2.0
        end
        return
    end
    print(string.format("[Audio] 背景音乐已加载：%.1f 秒", sound_.length or 0))
    Apply()
end

---@param data table
function Audio.Init(data)
    data_ = data
    initDelay = 1.5
    initAttempts = 0
    failed = false
    retryTimer = 0
    -- 这里不创建 Scene/SoundSource，交给 Update 延迟初始化
end

---@param data table
---@param on boolean
function Audio.SetEnabled(data, on)
    data_ = data
    data.musicOn = on and true or false
    if on and not scene_ and not failed then initDelay = 0 end
    pcall(Apply)
end

---@param data table
---@param volume number
function Audio.SetVolume(data, volume)
    data_ = data
    data.musicVolume = math.max(0, math.min(1, volume))
    pcall(Apply)
end

-- 玩家第一次操作时调用：网页端自动播放可能被拦，等有手势后再补一次播放
function Audio.Kick()
    if scene_ and source_ and sound_ and Wanted() and not source_:IsPlaying() then
        pcall(Apply)
    end
end

-- 冥想音乐：需要时才加载，加载失败也只是没有声音，不影响游戏
local function EnsureMeditate()
    if medSound_ or not scene_ then return end
    pcall(function()
        local node = scene_:CreateChild("Meditate")
        medSource_ = node:CreateComponent("SoundSource")
        if medSource_ then medSource_.soundType = SOUND_MUSIC end
        medSound_ = GetCache():GetResource("Sound", MEDITATE_PATH)
        if not medSound_ then medSource_ = nil end
        if medSound_ then print(string.format("[Audio] 冥想音乐已加载：%.1f 秒", medSound_.length or 0)) end
    end)
end

--- 进入 / 离开冥想：主音乐压低、冥想音乐淡入淡出
---@param on boolean
function Audio.SetMeditate(on)
    on = on and true or false
    if meditateOn == on then return end
    meditateOn = on
    if on then
        if not scene_ and not failed then InitNow() end
        EnsureMeditate()
    end
end

function Audio.IsMeditating()
    return meditateOn
end

--- 音乐是否真的在播（自检用）
function Audio.IsPlaying()
    if not (source_ and sound_) then return false end
    local ok, p = pcall(function() return source_:IsPlaying() end)
    return ok and p or false
end

function Audio.Update(dt)
    if not scene_ and not failed and Wanted() then
        initDelay = initDelay - dt
        if initDelay <= 0 then InitNow() end
    end
    if scene_ then
        pcall(function() scene_:Update(dt) end)
        -- 播放状态被系统打断（来电 / 切后台）时自动恢复
        if source_ and sound_ and Wanted() and not source_:IsPlaying() then
            retryTimer = retryTimer - dt
            if retryTimer <= 0 then
                retryTimer = 2.0
                pcall(Apply)
            end
        end
    end

    -- 冥想时的双轨混音：主音乐降到 12%，冥想音乐淡入到 80%
    local base = Wanted() and Volume() or 0
    local mainTarget = meditateOn and base * 0.12 or base
    if source_ and sound_ then
        local cur = mainGainLevel or mainTarget
        mainGainLevel = cur + (mainTarget - cur) * math.min(1, dt * 3)
        pcall(function() source_.gain = mainGainLevel end)
    end

    if meditateOn and Wanted() then
        EnsureMeditate()
        if medSource_ and medSound_ then
            if not medSource_:IsPlaying() then
                pcall(function()
                    medSound_.looped = true
                    medSource_:Play(medSound_, 0, 0)
                end)
            end
            local target = base * 0.8
            medGainLevel = medGainLevel + (target - medGainLevel) * math.min(1, dt * 1.5)
            pcall(function() medSource_.gain = medGainLevel end)
        end
    else
        medGainLevel = medGainLevel + (0 - medGainLevel) * math.min(1, dt * 2.5)
        if medSource_ then
            pcall(function()
                medSource_.gain = medGainLevel
                if medGainLevel < 0.003 and medSource_:IsPlaying() then
                    medSource_:Stop()
                end
            end)
        end
    end

    -- 临时音源（排查/试听用）：到时间就移除节点
    if #temp_ > 0 then
        for i = #temp_, 1, -1 do
            local item = temp_[i]
            item.t = item.t - (dt or 0)
            if item.t <= 0 then
                pcall(function() item.node:Remove() end)
                table.remove(temp_, i)
            end
        end
    end
end

--- 在「已经能出声」的音乐场景里播一个临时音（排查用）
---@param path string 资源根下的完整路径
---@param gain? number
---@param seconds? number 播多久后移除
---@return boolean
local function EnsurePool()
    if #pool_ > 0 or not scene_ then return end
    for i = 1, POOL_SIZE do
        local ok, src = pcall(function()
            local node = scene_:CreateChild("SfxPool" .. i)
            local s = node:CreateComponent("SoundSource")
            s.soundType = SOUND_MUSIC
            return s
        end)
        if ok and src then pool_[#pool_ + 1] = src end
    end
end

--- 取一个当前没在播的音源（都忙就轮流覆盖最早的那个）
local function FreeSource()
    EnsurePool()
    if #pool_ == 0 then return nil end
    for i = 1, #pool_ do
        local ok, playing = pcall(function() return pool_[i]:IsPlaying() end)
        if not ok or not playing then return pool_[i] end
    end
    poolIdx_ = math.floor(poolIdx_ % #pool_) + 1
    return pool_[poolIdx_]
end

--- 在「已经能出声」的音乐场景里播一个音效（复用音源池，低延迟）
---@param path string 资源根下的完整路径
---@param gain? number
---@param seconds? number 兼容旧参数，池化后不需要（保留签名）
---@return boolean
function Audio.PlayTemp(path, gain, seconds)
    if not scene_ then InitNow() end
    if not scene_ then return false end
    local done = false
    pcall(function()
        local sound = GetCache():GetResource("Sound", path)
        if not sound then return end
        local src = FreeSource()
        if not src then return end
        src.gain = math.max(0, math.min(1, gain or 0.6))
        -- 频率传 0：引擎按素材采样率播放（和卡农完全同一条路径）
        src:Play(sound, 0, src.gain)
        done = true
    end)
    return done
end

function Audio.Shutdown()
    if source_ then
        pcall(function() source_:Stop() end)
    end
    if medSource_ then
        pcall(function() medSource_:Stop() end)
    end
    scene_ = nil
    temp_ = {}
    pool_ = {}
    poolIdx_ = 0
    source_ = nil
    sound_ = nil
    medSource_ = nil
    medSound_ = nil
    mainGainLevel = nil
    medGainLevel = 0
end

return Audio
