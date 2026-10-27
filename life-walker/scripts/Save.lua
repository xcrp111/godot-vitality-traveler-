-- Save.lua
-- 本地存档：金币 / 经验 / 职业等级 / 今日步数 / 关卡进度 / 技能配置

local Config = require "Config"

local Save = {}

local SAVE_FILE = "save.json"
local SAVE_VERSION = 1

local function Defaults()
    return {
        version = SAVE_VERSION,
        class = "swordsman",    -- 当前出战职业
        gold = 0,
        exp = 0,                -- 可分配经验池（所有职业共用，需要玩家自己分配）
        levels = { swordsman = 1, spearman = 1, ranger = 1, mage = 1 },   -- 各职业等级
        classExp = { swordsman = 0, spearman = 0, ranger = 0, mage = 0 }, -- 各职业已投入、尚未消耗的经验
        unlocked = 1,           -- 步数解锁到的最高关卡
        stageCleared = 0,       -- 已通关的最高关卡（必须通关上一关才能进下一关）
        dayKey = "",
        todaySteps = 0,
        claimed = false,
        streak = 0,             -- 连续健康天数
        lastActiveDay = 0,      -- 最近一次达标的日序号
        dayOffset = 0,          -- 开发用：虚拟推进的天数
        skillPoints = 0,        -- 技能点（v1 先积累，技能升级后续开放）
        streakRewardIndex = 0,  -- 已领取到第几档连续奖励
        musicOn = true,         -- 背景音乐开关
        musicVolume = 0.32,     -- 背景音乐音量 0~1
        layout = nil,           -- 按键布局（由 Save.Layout 补齐默认值）
        joyMode = "float",      -- 摇杆模式：fixed 固定位置 / float 按下即定位
        joyFollow = true,       -- 拖尾跟随：手指拖出圈时基座跟着走
        aimMode = "button",     -- 选位技能瞄准：button 技能键当摇杆 / screen 拖到屏幕对应位置
        -- 画面与性能
        fpsCap = 60,            -- 帧率上限 30 / 60 / 120
        lowQuality = false,     -- 低画质：粒子/拖尾/残影减量
        screenShake = true,     -- 屏幕震动
        damageText = "full",    -- 伤害数字：full 完整 / simple 简化 / off 关闭
        -- 操作手感
        joySensitivity = "mid", -- 摇杆灵敏度：low / mid / high
        aimHold = 0.22,         -- 长按施法阈值（秒）
        autoAttack = true,      -- 自动攻击：进入普攻范围后自动出刀
        aimIndicator = true,    -- 瞄准时显示按键摇杆指示线
        -- 战斗显示
        showSkillRange = true,  -- 常驻显示普攻范围
        enemyHpBar = true,      -- 怪物血条
        bossWarn = true,        -- 敌方预警加强
        loadouts = {
            swordsman = { 1, 2, 3 },
            spearman = { 1, 2, 4 },
            ranger = { 1, 2, 5 },
            mage = { 1, 2, 3 },
        },
    }
end

local CLASS_DEFAULT_LOADOUT = {
    swordsman = { 1, 2, 3 },
    spearman = { 1, 2, 4 },
    ranger = { 1, 2, 5 },
    mage = { 1, 2, 3 },
}

-- 按键布局默认值：{x, y, 半径}，设计坐标 1280x720
local LAYOUT_DEFAULTS = {
    joy    = { 140, 578, 74 },
    attack = { 1186, 626, 48 },
    skill1 = { 1080, 624, 36 },
    skill2 = { 1110, 526, 36 },
    skill3 = { 1202, 514, 32 },
    items  = { 1080, 420, 27 },
    aim_cancel = { 1170, 378, 80 },   -- 瞄准时的「取消施法」框（中心 + 半径，宽 2r 高 1.2r）
}

local LAYOUT_IDS = { "joy", "attack", "skill1", "skill2", "skill3", "items", "aim_cancel" }

-- 读取（并补齐）按键布局，返回 data.layout
---@param data table
---@return table
function Save.Layout(data)
    if type(data.layout) ~= "table" then data.layout = {} end
    local L = data.layout
    for _, id in ipairs(LAYOUT_IDS) do
        local d = LAYOUT_DEFAULTS[id]
        local cur = L[id]
        if type(cur) ~= "table" then
            L[id] = { x = d[1], y = d[2], r = d[3] }
        else
            if type(cur.x) ~= "number" then cur.x = d[1] end
            if type(cur.y) ~= "number" then cur.y = d[2] end
            if type(cur.r) ~= "number" then cur.r = d[3] end
        end
    end
    return L
end

-- 恢复默认布局
---@param data table
function Save.ResetLayout(data)
    data.layout = nil
    Save.Layout(data)
    Save.Write(data)
end

---@param data table
---@return string
function Save.ActiveClass(data)
    return (data and data.class) or "swordsman"
end

local function EnsureMaps(data)
    if type(data.levels) ~= "table" then data.levels = {} end
    if type(data.classExp) ~= "table" then data.classExp = {} end
    for id in pairs(Config.Classes) do
        if type(data.levels[id]) ~= "number" then data.levels[id] = 1 end
        if type(data.classExp[id]) ~= "number" then data.classExp[id] = 0 end
    end
end

---@param data table
---@return integer
function Save.ClassLevel(data)
    EnsureMaps(data)
    return data.levels[Save.ActiveClass(data)] or 1
end

---@param data table
---@param level integer
function Save.SetClassLevel(data, level)
    EnsureMaps(data)
    data.levels[Save.ActiveClass(data)] = math.max(1, math.floor(level))
end

---@param data table
---@return number
function Save.ClassExp(data)
    EnsureMaps(data)
    return data.classExp[Save.ActiveClass(data)] or 0
end

-- 从可分配经验池投入当前职业（已废弃：升级现在直接从总池扣，保留只为兼容旧调用）
---@param data table
---@param amount number
---@return number 实际投入
function Save.AllocateExp(data, amount)
    amount = math.floor(math.min(amount, data.exp))
    if amount <= 0 then return 0 end
    EnsureMaps(data)
    data.exp = data.exp - amount
    local class = Save.ActiveClass(data)
    data.classExp[class] = (data.classExp[class] or 0) + amount
    Save.Write(data)
    return amount
end

---@param data table
---@return integer[]
function Save.Loadout(data)
    local class = Save.ActiveClass(data)
    data.loadouts = data.loadouts or {}
    local lo = data.loadouts[class]
    if type(lo) ~= "table" then
        lo = {}
        local def = CLASS_DEFAULT_LOADOUT[class] or { 1, 2, 3 }
        for i = 1, 3 do lo[i] = def[i] or i end
        data.loadouts[class] = lo
    end
    return lo
end

function Save.SetClass(data, id)
    if Config.Classes[id] then
        data.class = id
        Config.SetClass(id)
        Save.Loadout(data)
        Save.Write(data)
        return true
    end
    return false
end

local function MergeDefaults(data)
    -- 旧存档没有通关记录：按原来的解锁进度补齐，避免进度倒退
    if type(data.stageCleared) ~= "number" then
        local u = type(data.unlocked) == "number" and data.unlocked or 1
        data.stageCleared = math.max(0, u - 1)
    end
    local def = Defaults()
    for k, v in pairs(def) do
        if data[k] == nil then
            data[k] = v
        end
    end
    if type(data.class) ~= "string" or not Config.Classes[data.class] then
        data.class = "swordsman"
    end
    -- 旧存档：把单一 loadout 迁移到多职业结构
    if type(data.loadouts) ~= "table" then data.loadouts = {} end
    if type(data.loadout) == "table" and type(data.loadouts.swordsman) ~= "table" then
        data.loadouts.swordsman = {
            data.loadout[1] or 1, data.loadout[2] or 2, data.loadout[3] or 3,
        }
    end
    for class, list in pairs(CLASS_DEFAULT_LOADOUT) do
        local lo = data.loadouts[class]
        if type(lo) ~= "table" then
            lo = {}
            data.loadouts[class] = lo
        end
        for i = 1, 3 do
            if type(lo[i]) ~= "number" then lo[i] = list[i] or i end
        end
    end
    -- 旧存档：单一等级迁移到当前职业
    if type(data.levels) ~= "table" then data.levels = {} end
    if type(data.classExp) ~= "table" then data.classExp = {} end
    if type(data.level) == "number" then
        data.levels[data.class] = math.max(1, data.level)
        data.level = nil
    end
    if type(data.musicOn) ~= "boolean" then data.musicOn = true end
    if type(data.musicVolume) ~= "number" then data.musicVolume = 0.32 end
    data.musicVolume = math.max(0, math.min(1, data.musicVolume))
    EnsureMaps(data)
    -- 升级改成直接从总池扣之后，旧存档里"已投入职业"的经验并回总池，避免丢经验
    local refund = 0
    for id, v in pairs(data.classExp) do
        if type(v) == "number" and v > 0 then
            refund = refund + v
            data.classExp[id] = 0
        end
    end
    if refund > 0 then data.exp = (data.exp or 0) + refund end
    data.loadout = nil
    return data
end

function Save.TodayKey(data)
    local offset = (data and data.dayOffset) or 0
    return os.date("%Y-%m-%d", os.time() + offset * 86400)
end

-- 全新存档（不读文件）。手机/网页端读写不可用时用它兜底，保证游戏能跑
---@return SaveData
function Save.Fresh()
    local data = MergeDefaults({})
    Save.RollDay(data)
    return data
end

-- 设置页「恢复默认设置」用：拿到一份默认值（不动存档）
function Save.Defaults()
    return Defaults()
end

---@return SaveData
function Save.Load()
    local data = nil
    -- 移动端 / 网页端可能没有 fileSystem 或 File，统一用 pcall 兜底
    pcall(function()
        if fileSystem and fileSystem:FileExists(SAVE_FILE) then
            local f = File(SAVE_FILE, FILE_READ)
            if f and f:IsOpen() then
                local text = f:ReadString()
                f:Close()
                local ok, decoded = pcall(cjson.decode, text)
                if ok and type(decoded) == "table" then
                    data = decoded
                end
            end
        end
    end)
    data = MergeDefaults(data or {})
    Save.RollDay(data)
    return data
end

-- 实际可挑战的最高关卡：既要步数解锁，也要把上一关打完
---@param data table
---@return integer
function Save.MaxPlayable(data)
    local stepUnlocked = math.max(1, math.min(20, data.unlocked or 1))
    local cleared = math.max(0, data.stageCleared or 0)
    return math.max(1, math.min(stepUnlocked, cleared + 1))
end

-- 通关某一关后调用
---@param data table
---@param level integer
function Save.MarkCleared(data, level)
    data.stageCleared = math.max(data.stageCleared or 0, level)
    Save.Write(data)
end

-- 开发用：直接把关卡进度推满
---@param data table
function Save.DebugUnlockAll(data)
    data.unlocked = 20
    data.stageCleared = 19
    Save.Write(data)
end

---@return boolean
function Save.Write(data)
    if type(data) ~= "table" then return false end
    local ok, result = pcall(function()
        local f = File(SAVE_FILE, FILE_WRITE)
        if f and f:IsOpen() then
            f:WriteString(cjson.encode(data))
            f:Close()
            return true
        end
        return false
    end)
    return ok and result == true
end

-- 跨天重置
---@return SaveData
function Save.RollDay(data)
    local today = Save.TodayKey(data)
    if data.dayKey ~= today then
        data.dayKey = today
        data.todaySteps = 0
        data.claimed = false
    end
    return data
end

-- 领取今日步数：返回 获得金币, 解锁关卡数, 当前连续天数
---@return number, number, number, number, number
function Save.Claim(data, steps)
    Save.RollDay(data)
    data.todaySteps = steps
    if data.claimed then
        return 0, 0, data.streak, 0, 0
    end

    local gain, pct = Config.StepGold(steps)
    data.gold = data.gold + gain
    data.exp = data.exp + gain

    local unlocks = 0
    for _, need in ipairs(Config.StepUnlockThresholds) do
        if steps >= need then
            unlocks = unlocks + 1
        end
    end
    local before = data.unlocked
    data.unlocked = data.unlocked + unlocks
    if data.unlocked > 20 then
        data.unlocked = 20
    end
    local gotUnlocked = data.unlocked - before

    local dayNum = math.floor(os.time() / 86400) + (data.dayOffset or 0)
    if pct >= 10 then
        if data.lastActiveDay == dayNum - 1 then
            data.streak = data.streak + 1
        elseif data.lastActiveDay ~= dayNum then
            data.streak = 1
        end
        data.lastActiveDay = dayNum
    else
        data.streak = 0
    end

    local rewardGold, rewardSp = 0, 0
    for i = data.streakRewardIndex + 1, #Config.StreakRewards do
        local r = Config.StreakRewards[i]
        if data.streak >= r.days then
            data.streakRewardIndex = i
            data.gold = data.gold + r.gold
            data.skillPoints = data.skillPoints + r.sp
            rewardGold = rewardGold + r.gold
            rewardSp = rewardSp + r.sp
        end
    end

    data.claimed = true
    Save.Write(data)
    return gain, gotUnlocked, data.streak, rewardGold, rewardSp
end

-- 开发用：重置今日领取
function Save.ResetToday(data)
    data.dayKey = Save.TodayKey(data)
    data.todaySteps = 0
    data.claimed = false
    Save.Write(data)
end

-- 开发用：推进到下一天（用于测试连续健康天数 / 等级门槛）
function Save.NextDay(data)
    data.dayOffset = (data.dayOffset or 0) + 1
    data.dayKey = Save.TodayKey(data)
    data.todaySteps = 0
    data.claimed = false
    Save.Write(data)
    return data.dayOffset
end

-- 开发用：把存档恢复成初始状态（等级 / 金币 / 经验 / 关卡 / 连续天数全部清空）
function Save.Reset(data)
    local def = Defaults()
    for k in pairs(data) do data[k] = nil end
    for k, v in pairs(def) do data[k] = v end
    Save.RollDay(data)
    Save.Write(data)
    return data
end

-- 下一级消耗，满级返回 nil
---@return number|nil
function Save.NextCost(data)
    local level = Save.ClassLevel(data)
    if level >= 20 then return nil end
    return Config.LevelCost[level]
end

-- 升级：直接从全局可分配经验里扣掉这一级需要的量
-- 返回 ok, 失败原因
---@return boolean, string
function Save.LevelUp(data)
    local level = Save.ClassLevel(data)
    if level >= 20 then
        return false, "已经满级"
    end
    local needGate, gateName = Config.LevelGate(level + 1)
    if data.streak < needGate then
        return false, "需要连续健康 " .. needGate .. " 天（" .. gateName .. "）"
    end
    local cost = Config.LevelCost[level]
    if not cost then
        return false, "已经满级"
    end
    if (data.exp or 0) < cost then
        return false, string.format("可分配经验不足，还差 %d", math.ceil(cost - (data.exp or 0)))
    end
    local class = Save.ActiveClass(data)
    data.exp = data.exp - cost
    data.levels[class] = level + 1
    Save.Write(data)
    return true, Config.Class().name .. "升到 Lv." .. (level + 1)
end

-- 当前等级已解锁的技能 id 列表
---@return integer[]
function Save.UnlockedSkills(level)
    local list = {}
    for _, s in ipairs(Config.Skills) do
        if level >= s.unlockLevel then
            list[#list + 1] = s.id
        end
    end
    return list
end

---@return boolean
function Save.IsSkillUnlocked(level, id)
    local s = Config.SkillByID(id)
    return s ~= nil and level >= s.unlockLevel
end

return Save

