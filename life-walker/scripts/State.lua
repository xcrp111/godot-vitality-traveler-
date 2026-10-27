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
---@field gold number
---@field exp number
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
    screen = "menu",
    time = 0,
    data = {
        version = 1,
        class = "swordsman",
        gold = 0,
        exp = 0,
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
    confirmReset = false,
    showStatus = false,
    statusPanel = nil,
    col = {
        bg       = { 16, 14, 22, 255 },
        bg2      = { 24, 20, 32, 255 },
        panel    = { 34, 30, 46, 255 },
        panel2   = { 46, 40, 60, 255 },
        line     = { 82, 74, 104, 255 },
        text     = { 236, 232, 242, 255 },
        dim      = { 158, 152, 176, 255 },
        green    = { 126, 231, 135, 255 },
        red      = { 255, 107, 107, 255 },
        gold     = { 255, 209, 102, 255 },
        cyan     = { 76, 201, 240, 255 },
        purple   = { 190, 140, 255, 255 },
        orange   = { 255, 159, 88, 255 },
    },
}

return S

