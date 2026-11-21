-- DevCamp.lua — 营地界面回归：农场页已删除，只留局外商店 / 窝
local Config = require "Config"
local Save = require "Save"
local S = require "State"
local Camp = require "Camp"
local CampUI = require "CampUI"
local UI = require "UI"

local fails = 0
local function check(name, cond, detail)
    if cond then
        print("[Camp] OK   " .. name)
    else
        fails = fails + 1
        print("[Camp] FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
    end
end

function Start()
    local dpr = graphics:GetDPR(); if not dpr or dpr <= 0 then dpr = 1 end
    S.dpr = dpr
    S.W = graphics:GetWidth() / dpr
    S.H = graphics:GetHeight() / dpr
    S.scale = math.min(S.W / Config.DESIGN_W, S.H / Config.DESIGN_H)
    S.offX = (S.W - Config.DESIGN_W * S.scale) / 2
    S.offY = (S.H - Config.DESIGN_H * S.scale) / 2
    S.ctx = nvgCreate(1)
    S.font = nvgCreateFont(S.ctx, "sans", "Fonts/MiSans-Game.ttf")
    S.data = Save.Load()
    S.screen = "menu"

    -- 商店里不该再卖农场种子
    local names = {}
    for _, it in ipairs(Camp.ShopItems) do
        names[#names + 1] = it.name
        check("商店条目不是种子：" .. it.name, not it.name:find("种子"),
            it.name)
    end
    check("商店还剩 4 条（钥匙 / 间断卡 / 两种建材）", #Camp.ShopItems == 4, #Camp.ShopItems)

    -- 背包不再列营地种子
    local c = Camp.Ensure(S.data)
    c.seeds.basic, c.seeds.rare = 3, 1
    local listed = {}
    for _, row in ipairs(Camp.Inventory(S.data)) do listed[row.name] = true end
    check("背包不列基础种子", not listed["基础种子"])
    check("背包不列稀有种子", not listed["稀有种子"])

    -- 营地页签只有两个：局外商店 / 窝；老存档的 campTab=3 会被夹回去
    S.camp = true
    for _, tab in ipairs({ 1, 2, 3 }) do
        S.campTab = tab
        local ok, err = pcall(function() CampUI.Draw() end)
        check("campTab=" .. tab .. " 能正常绘制", ok, err)
        check("campTab=" .. tab .. " 被夹到有效页", (S.campTab or 1) <= 2, S.campTab)
    end

    -- 农场模块本身没被动到（走的是独立 Farm / FarmUI）
    local Farm = require "Farm"
    check("独立农场模块可用", type(Farm.Crops) == "table" and #Farm.Crops > 0)

    print(string.format("[Camp] done, failures = %d", fails))
end
