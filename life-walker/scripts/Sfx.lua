-- Sfx.lua — 法师音效包（同学交付的 64 项音频）的播放层
--
-- 素材位置：assets/audio/mage/<分类>/<ID>.wav|ogg（资源根下 = "audio/mage/..."）
-- 设计要点：
--   · 懒初始化：第一次真正要发声时才建 Scene / SoundSource，避免手机端启动首帧看门狗
--   · 固定小音源池：手游上不无限 CreateComponent，池满就复用最早的
--   · 每个音效有 gap（最小重复间隔）与 voices（同时最多几条），防止机枪一样叠在一起
--   · 音量/开关读 S.data.sfxOn / S.data.sfxVolume，和音乐分开
local Sfx = {}

-- 通道选择（实测结论）：这个客户端的 SOUND_EFFECT(3D) 通道能"播放成功"但完全听不到，
-- 而 SOUND_MUSIC 通道正常（背景音乐可闻）。音效统一走音乐通道，
-- 音量仍由每个音源自己的 gain 控制，不受菜单里的"音乐音量"影响。
local CHANNEL = SOUND_MUSIC


-- 音效定义
--   file  资源根下的完整路径（必须写成整串字面量，构建期资源扫描才认得）
--   gain  基础音量（0..1）
--   gap   最小重复间隔（秒）
--   voice 同时最多几条
Sfx.Defs = {
    -- 角色
    spawn         = { file = "audio/mage/character_feedback/B07_player_spawn.wav", gain = 0.85, gap = 1.0, voice = 1 },
    player_hit    = { file = "audio/mage/character_feedback/B05_player_hit.wav",   gain = 0.75, gap = 0.12, voice = 2 },
    player_death  = { file = "audio/mage/character_feedback/B06_player_death.wav", gain = 0.9,  gap = 1.0, voice = 1 },
    basic_cast    = { file = "audio/mage/character_feedback/B08_basic_cast.wav",   gain = 0.45, gap = 0.04, voice = 3 },
    basic_hit     = { file = "audio/mage/character_feedback/B09_basic_hit.wav",    gain = 0.5,  gap = 0.04, voice = 3 },
    -- 界面
    ui_click      = { file = "audio/mage/character_feedback/B12_ui_click.wav",     gain = 0.5,  gap = 0.05, voice = 2 },
    upgrade       = { file = "audio/mage/character_feedback/B11_skill_upgrade.wav", gain = 0.75, gap = 0.5, voice = 1 },

    -- 火：1 火球 / 6 烈焰 / 8 流星
    fireball_cast = { file = "audio/mage/fire/C01_fireball_cast.wav", gain = 0.7, gap = 0.05, voice = 3 },
    fireball_hit  = { file = "audio/mage/fire/C03_fireball_hit_L1.wav", gain = 0.75, gap = 0.05, voice = 3 },
    flame_cast    = { file = "audio/mage/fire/C04_flame_cast.wav", gain = 0.7, gap = 0.1, voice = 2 },
    flame_burst   = { file = "audio/mage/fire/C05_flame_burst_L1.wav", gain = 0.85, gap = 0.12, voice = 2 },
    meteor_cast   = { file = "audio/mage/fire/C06_meteor_cast.wav", gain = 0.7, gap = 0.15, voice = 2 },
    meteor_fall   = { file = "audio/mage/fire/C07_meteor_fall.wav", gain = 0.6, gap = 0.15, voice = 2 },
    meteor_hit    = { file = "audio/mage/fire/C08_meteor_impact_L1.wav", gain = 0.95, gap = 0.2, voice = 2 },
    -- 冰：2 冰霜波 / 4 冰锥 / 9 暴风雪
    frost_cast    = { file = "audio/mage/ice/C09_frost_wave_cast.wav", gain = 0.7, gap = 0.08, voice = 2 },
    frost_burst   = { file = "audio/mage/ice/C10_frost_wave_L1.wav", gain = 0.8, gap = 0.1, voice = 2 },
    ice_cast      = { file = "audio/mage/ice/C11_ice_spike_cast.wav", gain = 0.6, gap = 0.05, voice = 3 },
    ice_hit       = { file = "audio/mage/ice/C13_ice_spike_hit_L1.wav", gain = 0.75, gap = 0.05, voice = 3 },
    blizzard_cast = { file = "audio/mage/ice/C14_blizzard_cast.wav", gain = 0.7, gap = 0.2, voice = 1 },
    -- 雷：3 雷击 / 5 闪电链 / 7 静电场
    thunder_cast  = { file = "audio/mage/lightning/C18_thunder_cast.wav", gain = 0.7, gap = 0.1, voice = 2 },
    thunder_hit   = { file = "audio/mage/lightning/C19_thunder_impact_L1.wav", gain = 0.9, gap = 0.1, voice = 2 },
    chain_cast    = { file = "audio/mage/lightning/C16_chain_cast.wav", gain = 0.7, gap = 0.06, voice = 2 },
    chain_link    = { file = "audio/mage/lightning/C17_chain_link_L1.wav", gain = 0.6, gap = 0.03, voice = 4 },
    static_cast   = { file = "audio/mage/lightning/C20_static_cast.wav", gain = 0.65, gap = 0.2, voice = 1 },
    static_pulse  = { file = "audio/mage/lightning/C22_static_pulse.wav", gain = 0.45, gap = 0.1, voice = 2 },
    -- 状态
    burn_apply    = { file = "audio/mage/states/D01_burn_loop.wav", gain = 0.35, gap = 0.4, voice = 1 },
    freeze_start  = { file = "audio/mage/states/D02_freeze_start.wav", gain = 0.6, gap = 0.3, voice = 1 },
    freeze_break  = { file = "audio/mage/states/D04_freeze_break.wav", gain = 0.6, gap = 0.3, voice = 1 },
    slow_apply    = { file = "audio/mage/states/D05_slow_apply.wav", gain = 0.5, gap = 0.3, voice = 1 },
    thunder_crit  = { file = "audio/mage/states/D06_thunder_critical.wav", gain = 0.55, gap = 0.2, voice = 1 },
}

-- 循环音效：由技能区域（暴风雪 / 静电场）持有句柄，区域结束调用 handle:Stop()
Sfx.Loops = {
    blizzard = { file = "audio/mage/ice/C15_blizzard_loop_L1.wav", gain = 0.4 },
    static   = { file = "audio/mage/lightning/C21_static_loop_L1.wav", gain = 0.35 },
}

local DEFAULT_VOLUME = 0.8
local POOL_SIZE = 8

---@type Scene?
local scene_ = nil
---@type SoundSource[]
local pool_ = {}
local poolIdx_ = 0
local failed_ = false

local lastPlay_ = {}   -- id -> 时间（秒，用引擎累计时间）
local now_ = 0
local loops_ = {}      -- 当前在播的循环音效句柄（Shutdown 时统一停掉）
local pending_ = {}    -- 延迟播放队列 { id, t }
---@type SoundListener?
local listener_ = nil  -- 场景里的 SoundListener（3D 音效必需）
---@type SoundSource?
local lastSource_ = nil -- 最近一次播放用的音源（自检用）

local function Data()
    local S = require "State"
    ---@type table|nil
    local d = S.data
    return d
end

local function Enabled()
    local d = Data()
    if d and d.sfxOn == false then return false end
    return true
end

local function Volume()
    local d = Data()
    local v = DEFAULT_VOLUME
    if d and type(d.sfxVolume) == "number" then v = d.sfxVolume end
    return math.max(0, math.min(1, v))
end

local function EnsureScene()
    if scene_ or failed_ then return scene_ ~= nil end
    local ok, err = pcall(function()
        scene_ = Scene()
        -- 关键：3D 音源（SOUND_EFFECT）只有在场景里存在 SoundListener 时才会被混音。
        -- 之前只建了 Scene + SoundSource，背景音乐（SOUND_MUSIC 不受 3D 影响）能响，
        -- 音效却完全没声——就是缺了这个监听器。
        local node = scene_:CreateChild("Listener")
        listener_ = node:CreateComponent("SoundListener")
    end)
    if not ok or not scene_ then
        failed_ = true
        print("[Sfx] 音频场景创建失败，音效已跳过：" .. tostring(err))
        return false
    end
    return true
end

local warned_ = {}

local function LoadSound(path)
    local ok, sound = pcall(function()
        return GetCache():GetResource("Sound", path)
    end)
    if ok and sound then return sound end
    -- 只报一次：打包漏资源 / DWP 还没下好时，日志里能直接看出来
    if not warned_[path] then
        warned_[path] = true
        print("[Sfx] 音效加载失败：" .. path)
    end
    return nil
end

local function NextSource()
    local scene = scene_
    if not scene then return nil end
    if #pool_ == 0 then
        for i = 1, POOL_SIZE do
            local ok, src = pcall(function()
                local node = scene:CreateChild("Sfx" .. i)
                node.position = Vector3(0, 0, 0)
                local s = node:CreateComponent("SoundSource")
                s.soundType = CHANNEL
                -- 2D 游戏没有 3D 空间：关掉距离衰减，音量只由 gain 控制
                pcall(function() s.attenuation = 0 end)
                return s
            end)
            if ok and src then table.insert(pool_, src) end
        end
        if #pool_ == 0 then return nil end
    end
    poolIdx_ = math.floor(poolIdx_ % #pool_) + 1
    return pool_[poolIdx_]
end

--- 播放一次性音效
---@param id string Sfx.Defs 里的键
---@param opts? { gain?: number, pan?: number }
---@return boolean 是否真的播了
function Sfx.Play(id, opts)
    local def = Sfx.Defs[id]
    if not def then return false end
    if not Enabled() then return false end

    local gap = def.gap or 0
    if gap > 0 and (now_ - (lastPlay_[id] or -999)) < gap then return false end
    lastPlay_[id] = now_

    local sound = LoadSound(def.file)
    if not sound then return false end

    opts = opts or {}
    local gain = math.max(0, math.min(1, (def.gain or 0.7) * Volume() * (opts.gain or 1)))

    -- 首选：走 Audio 的「音乐场景」——实测卡农能从那条路径出声，
    -- 而自建 Scene 里的音源虽然 IsPlaying=true 却完全听不到。
    local okA, played = pcall(function()
        local Audio = require "Audio"
        return Audio.PlayTemp(def.file, gain, (sound.length or 0.3) + 0.25)
    end)
    if okA and played then return true end

    -- 兜底：Audio 场景不可用时，退回自建音源池
    if not EnsureScene() then return false end
    local src = NextSource()
    if not src then return false end
    local freq = 0.0
    local okFreq, f = pcall(function() return sound:GetFrequency() end)
    if okFreq and type(f) == "number" then freq = f end
    local okPlay = pcall(function()
        src:Play(sound, freq, gain, opts.pan or 0)
    end)
    if okPlay then lastSource_ = src end
    return okPlay
end

--- 开始一个循环音效，返回句柄（句柄可 nil，调用方要判空）
---@param id string Sfx.Loops 里的键
---@param opts? { gain?: number }
---@return table|nil { Stop = fun(), IsPlaying = fun(): boolean }
function Sfx.StartLoop(id, opts)
    local def = Sfx.Loops[id]
    if not def then return nil end
    if not EnsureScene() then return nil end
    local sound = LoadSound(def.file)
    if not sound then return nil end

    opts = opts or {}
    local gain = (def.gain or 0.4) * Volume() * (opts.gain or 1)
    local scene = scene_
    if not scene then return nil end
    local ok, handle = pcall(function()
        local node = scene:CreateChild("Loop_" .. id)
        node.position = Vector3(0, 0, 0)
        local src = node:CreateComponent("SoundSource")
        if not src then return nil end
        src.soundType = CHANNEL
        pcall(function() src.attenuation = 0 end)
        sound.looped = true
        local freq = 0.0
        local okFreq, f = pcall(function() return sound:GetFrequency() end)
        if okFreq and type(f) == "number" then freq = f end
        src:Play(sound, freq, math.max(0, math.min(1, gain)))
        return {
            source = src,
            node = node,
            Stop = function(self)
                if not self or self.stopped then return end
                self.stopped = true
                pcall(function() self.source:Stop() end)
                pcall(function() self.node:Remove() end)
            end,
            IsPlaying = function(self)
                if not self or self.stopped then return false end
                local okp, p = pcall(function() return self.source:IsPlaying() end)
                return okp and p or false
            end,
        }
    end)
    if not ok then return nil end
    if handle then table.insert(loops_, handle) end
    return handle
end

--- 延迟播放（陨石落地这类「特效延后 0.2 秒」的场合，声音跟特效对齐）
---@param id string
---@param delay number 秒
function Sfx.PlayAfter(id, delay)
    if not Sfx.Defs[id] then return end
    table.insert(pending_, { id = id, t = delay or 0 })
end

--- 每帧调用（由 main 的 Update 转发），推进时间轴、跑延迟队列、回收循环句柄
function Sfx.Update(dt)
    now_ = now_ + (dt or 0)
    if scene_ then pcall(function() scene_:Update(dt or 0) end) end
    for i = #pending_, 1, -1 do
        local p = pending_[i]
        p.t = p.t - (dt or 0)
        if p.t <= 0 then
            table.remove(pending_, i)
            Sfx.Play(p.id)
        end
    end
    for i = #loops_, 1, -1 do
        if loops_[i].stopped then table.remove(loops_, i) end
    end
end

--- 切换开关 / 音量（菜单里以后接 UI 用得上）
function Sfx.SetEnabled(on)
    local d = Data()
    if d then d.sfxOn = on and true or false end
end

function Sfx.SetVolume(v)
    local d = Data()
    if d then d.sfxVolume = math.max(0, math.min(1, v or 0)) end
end

--- 停掉所有正在循环的音效（离开战斗 / 清场时调用）
function Sfx.StopAllLoops()
    for i = #loops_, 1, -1 do
        pcall(function() loops_[i]:Stop() end)
    end
    loops_ = {}
end

--- 自检：把「开关 / 场量 / 资源 / 播放」一次性报出来（测试面板用）
function Sfx.Diag()
    local d = Data()
    local lines = {}
    lines[#lines + 1] = string.format("开关=%s 音量=%.2f",
        tostring(not d or d.sfxOn ~= false), Volume())
    if GetAudio ~= nil then
        local ok, g = pcall(function() return GetAudio():GetMasterGain(CHANNEL) end)
        lines[#lines + 1] = "通道主音量=" .. tostring(ok and g or "n/a")
    end
    lines[#lines + 1] = "场景=" .. tostring(EnsureScene())
        .. " 监听器=" .. tostring(listener_ ~= nil)
    local s = LoadSound(Sfx.Defs.ui_click.file)
    lines[#lines + 1] = "资源=" .. tostring(s ~= nil)
    if s then
        lastPlay_["ui_click"] = nil
        local played = Sfx.Play("ui_click")
        lines[#lines + 1] = "播放=" .. tostring(played)
            .. string.format(" 时长=%.2fs", s.length or 0)
        if lastSource_ then
            local ok, p = pcall(function() return lastSource_:IsPlaying() end)
            lines[#lines + 1] = "在播=" .. tostring(ok and p or "n/a") .. " 通道=自建"
        else
            lines[#lines + 1] = "通道=Audio(卡农路径)"
        end
    end
    local out = table.concat(lines, " | ")
    -- 顺手把背景音乐状态一起报出来：判断是「只有音效哑」还是「整个音频都没出」
    local okA, musicPlaying = pcall(function() return require("Audio").IsPlaying() end)
    out = out .. " | 音乐在播=" .. tostring(okA and musicPlaying)
    print("[Sfx] 自检：" .. out)
    return out
end

--- 通道探针：分别用 SOUND_EFFECT / SOUND_MUSIC 播同一个音，判断是哪条通路不响
---@param asMusic boolean 为 true 时用 SOUND_MUSIC 通道播放
---@return boolean
function Sfx.Probe(asMusic)
    if not EnsureScene() then return false end
    local s = LoadSound(Sfx.Defs.player_death.file)
    local src = NextSource()
    if not (s and src) then return false end
    local ok = pcall(function()
        src.soundType = asMusic and SOUND_MUSIC or SOUND_EFFECT
        pcall(function() src.attenuation = 0 end)
        src:Play(s, 0, 0.9)
    end)
    print(string.format("[Sfx] 通道探针 %s ok=%s",
        asMusic and "SOUND_MUSIC" or "SOUND_EFFECT", tostring(ok)))
    return ok
end

--- 退出战斗 / 回主界面时清空音源
function Sfx.Shutdown()
    for i = #loops_, 1, -1 do
        pcall(function() loops_[i]:Stop() end)
    end
    loops_ = {}
    pending_ = {}
    for i = #pool_, 1, -1 do
        pcall(function() pool_[i]:Stop() end)
    end
    pool_ = {}
    poolIdx_ = 0
    lastPlay_ = {}
    now_ = 0
    -- 场景留给下一次进入游戏复用；只有模块被卸载时才真正丢弃
    scene_ = nil
    listener_ = nil
    lastSource_ = nil
    failed_ = false
end

return Sfx
