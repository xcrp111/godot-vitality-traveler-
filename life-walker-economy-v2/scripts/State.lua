-- State.lua
-- 全局共享状态（单例）。所有模块 require 到的是同一张表。

---@class Region
---@field id string
---@field x number
---@field y number
---@field w number
---@field h number
---@field onClick fun()|nil
---@field enabled boolean

---@class ToastState
---@field text string
---@field t number

---@class InputState
---@field x number
---@field y number

---@class SaveData
---@field version integer
---@field class string
---@field gold number          -- 金币（局内掉落，上限 = 账号等级 × 300）
---@field essence number       -- 精粹（每日能量消耗结算，用于局外养成）
---@field essenceEarned number -- 累计获得精粹（账号等级里程碑）
---@field accountLevel integer
---@field bodyFat number        -- 体脂率（%），≥25 走超重肥胖单价阶梯
---@field levels table<string, integer>
---@field classExp table<string, number>
---@field unlocked integer
---@field stageCleared integer
---@field dayKey string
---@field todaySteps integer
---@field claimed boolean
---@field streak integer
---@field lastActiveDay integer
---@field dayOffset integer
---@field skillPoints integer
---@field streakRewardIndex integer
---@field musicOn boolean
---@field musicVolume number
---@field loadouts table<string, integer[]>
---@field layout any
---@field joyMode string
---@field joyFollow boolean
---@field aimMode string
---@field fpsCap integer
---@field lowQuality boolean
---@field screenShake boolean
---@field damageText string
---@field joySensitivity string
---@field aimHold number
---@field autoAttack boolean
---@field aimIndicator boolean
---@field showSkillRange boolean
---@field enemyHpBar boolean
---@field bossWarn boolean
---@field waterMl number
---@field sleptEarly boolean
---@field earlySleepPending boolean
---@field playSeconds number
---@field moveBuffUntil number
---@field cdrBuffUntil number
---@field endlessBest integer
---@field endlessMedal integer
---@field endlessDayKey string
---@field endlessDayBest integer
---@field endlessWeekKey string
---@field endlessWeekBest integer
---@field endlessMonthKey string
---@field endlessMonthBest integer
---@field devUnlockEndless boolean
---@field guild table|nil
-- SaveData 字段与 Save.lua 的 Defaults 保持一致

---@class KeyState
---@field up boolean
---@field down boolean
---@field left boolean
---@field right boolean
---@field active boolean

---@class GameState
---@field ctx any
---@field font integer
---@field audioScene any
---@field musicSource any
---@field W number
---@field H number
---@field dpr number
---@field designW number
---@field designH number
---@field scale number
---@field offX number
---@field offY number
---@field screen string
---@field panelMode string|nil
---@field hover table
---@field time number
---@field data SaveData
---@field run any
---@field combat any
---@field reward any
---@field regions Region[]
---@field toast ToastState
---@field input InputState
---@field keys KeyState
---@field dev boolean
---@field selectedLevel integer
---@field skillPicker any
---@field compendium boolean
---@field compendiumTab integer
---@field codexPage integer
---@field settings boolean
---@field test boolean
---@field testPage integer
---@field testBuffs table<string, boolean>
---@field testGeneral table<string, boolean>
---@field testMonsterCount table<string, integer>
---@field testSkills table<number, boolean>
---@field testLevel integer
---@field testDetail table|nil
---@field confirmReset boolean
---@field showStatus boolean
---@field statusPanel any
---@field kbEdit any
---@field settingsTab string
---@field settingsWipeConfirm boolean
---@field healthTasks boolean
---@field endlessPanel boolean
---@field guild boolean
---@field guildTab integer
---@field camp boolean
---@field campTab integer
---@field campBagPage integer
---@field bag boolean
---@field bagPage integer
---@field pet boolean
---@field petTab integer
---@field petBagTab integer
---@field petEggScroll integer
---@field petEggDrag table|nil
---@field petAttr string
---@field petLastDraw table|nil
---@field petPickLow boolean
---@field restPrompt any
---@field meditate any
---@field col table

---@type GameState
local S = {
    ctx = nil,
    font = -1,
    W = 1280,
    H = 720,
    dpr = 1,
    designW = 1280,
    designH = 720,
    scale = 1,
    offX = 0,
    offY = 0,
    screen = "title",          -- title 初始界面 / menu 主界面场景 / map / combat ...
    panelMode = nil,        -- 主界面的子面板："char" / "sports" / "levels"
    hover = { x = -1, y = -1 },   -- 鼠标/触点设计坐标（按钮悬停反馈用）
    hoverIsMouse = false,         -- 当前 hover 是否来自鼠标（触屏不算，不然手指一拖就到处高亮）
    time = 0,
    data = {
        version = 1,
        class = "swordsman",
        gold = 0,
        essence = 0,
        essenceEarned = 0,
        accountLevel = 1,
        bodyFat = 0,
        levels = { swordsman = 1, spearman = 1, ranger = 1, mage = 1 },
        classExp = { swordsman = 0, spearman = 0, ranger = 0, mage = 0 },
        unlocked = 1,
        stageCleared = 0,
        dayKey = "",
        todaySteps = 0,
        claimed = false,
        streak = 0,
        lastActiveDay = 0,
        dayOffset = 0,
        skillPoints = 0,
        streakRewardIndex = 0,
        musicOn = true,
        musicVolume = 0.32,
        joyMode = "float",
        joyFollow = true,
        aimMode = "button",
        waterMl = 0,
        sleptEarly = false,
        earlySleepPending = false,
        playSeconds = 0,
        moveBuffUntil = 0,
        cdrBuffUntil = 0,
        endlessBest = 0,
        endlessMedal = 0,
        endlessDayKey = "",
        endlessDayBest = 0,
        endlessWeekKey = "",
        endlessWeekBest = 0,
        endlessMonthKey = "",
        endlessMonthBest = 0,
        devUnlockEndless = false,
        fpsCap = 60,
        lowQuality = false,
        screenShake = true,
        damageText = "full",
        joySensitivity = "mid",
        aimHold = 0.22,
        autoAttack = true,
        aimIndicator = true,
        showSkillRange = true,
        enemyHpBar = true,
        bossWarn = true,
        loadouts = {
            swordsman = { 1, 2, 3 },
            spearman = { 1, 2, 4 },
            ranger = { 1, 2, 5 },
            mage = { 1, 2, 3 },
        },
    },
    run = nil,
    combat = nil,
    reward = false,
    regions = {},
    toast = { text = "", t = 0 },
    input = { x = 0, y = 0 },
    keys = { up = false, down = false, left = false, right = false, active = false },
    dev = true,
    selectedLevel = 1,
    skillPicker = false,
    compendium = false,
    compendiumTab = 1,
    codexPage = 1,
    settings = false,
    test = false,
    testPage = 1,
    testBuffs = {},
    testGeneral = {},
    testMonsterCount = { germ = 3, spore = 0, worm = 0, mycel = 0, plague = 0 },
    testSkills = {},
    testLevel = 1,
    testDetail = nil,
    healthTasks = false,
    endlessPanel = false,
    guild = false,
    guildTab = 1,
    camp = false,
    campTab = 1,
    campBagPage = 1,
    bag = false,
    bagPage = 1,
    pet = false,
    petTab = 1,
    petBagTab = 1,
    petEggScroll = 0,
    petEggDrag = nil,
    petAttr = "fire",
    petLastDraw = nil,
    petPickLow = false,
    restPrompt = nil,
    meditate = nil,
    settingsTab = "control",
    settingsWipeConfirm = false,
    confirmReset = false,
    showStatus = false,
    statusPanel = nil,
    col = {
        bg       = { 14, 10, 22, 255 },
        bg2      = { 30, 22, 46, 255 },
        panel    = { 52, 42, 76, 255 },
        panel2   = { 74, 60, 106, 255 },
        line     = { 136, 118, 184, 255 },
        text     = { 250, 248, 255, 255 },
        dim      = { 196, 188, 222, 255 },
        green    = { 104, 244, 138, 255 },
        red      = { 255, 88, 104, 255 },
        gold     = { 255, 214, 84, 255 },
        cyan     = { 82, 224, 255, 255 },
        purple   = { 202, 148, 255, 255 },
        orange   = { 255, 164, 72, 255 },
    },
}

return S

