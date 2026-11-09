-- DevCamp.lua — 营地系统回归（局外商店 / 农场 / 窝 / 金币每关重置）
-- 跑法：复制到 scripts/ 下当入口跑（脚本根是 scripts/）
local Config = require "Config"
local Save = require "Save"
local Economy = require "Economy"
local Camp = require "Camp"
local Run = require "Run"
local S = require "State"

local fails = 0
local function check(name, cond, detail)
    if cond then
        print("[Camp] OK   " .. name)
    else
        fails = fails + 1
        print("[Camp] FAIL " .. name .. (detail ~= nil and (" — " .. tostring(detail)) or ""))
    end
end
local function eq(name, got, want)
    check(name, got == want, "got=" .. tostring(got) .. " want=" .. tostring(want))
end

-- 备份玩家存档
local function ReadSaveRaw()
    local ok, text = pcall(function()
        if fileSystem and fileSystem:FileExists("save.json") then
            local f = File("save.json", FILE_READ)
            if f and f:IsOpen() then
                local t = f:ReadString(); f:Close(); return t
            end
        end
        return nil
    end)
    if ok then return text end
    return nil
end
local function WriteSaveRaw(text)
    if not text then return end
    pcall(function()
        local f = File("save.json", FILE_WRITE)
        if f and f:IsOpen() then f:WriteString(text); f:Close() end
    end)
end
local BACKUP = ReadSaveRaw()

function Start()
    local data = Save.Fresh()
    Economy.AddEssence(data, 100000)
    local c = Camp.Ensure(data)

    -- ---------------------------------------------------------------- 3 表：局外商店
    local ok1 = Camp.Buy(data, "key")
    check("买钥匙成功（10 精粹）", ok1, "key")
    eq("钥匙 +1", c.keys, 1)
    eq("钥匙今日已购 1", c.day.keyBought, 1)
    Camp.Buy(data, "key"); Camp.Buy(data, "key")
    eq("钥匙每日限 3 把", c.day.keyBought, 3)
    local ok4, msg4 = Camp.Buy(data, "key")
    check("第 4 把被限购拦住", not ok4 and string.find(msg4, "限购") ~= nil, msg4)

    local okCard = Camp.Buy(data, "streakcard")
    check("买间断卡成功", okCard, "card")
    local okCard2, msgCard2 = Camp.Buy(data, "streakcard")
    check("间断卡每 3 天只能买 1 张", not okCard2, msgCard2)

    local beforeMats = c.mats.basic
    Camp.Buy(data, "mat_basic")
    eq("基础建材每次 10 个", c.mats.basic - beforeMats, 10)
    local beforeMid = c.mats.mid
    Camp.Buy(data, "mat_mid")
    eq("中级建材每次 5 个", c.mats.mid - beforeMid, 5)

    data.dayKey = "2099-01-01"
    Camp.RollDay(data)
    eq("跨天后钥匙限购归零", c.day.keyBought, 0)
    eq("跨天后种子限购归零", c.day.seedBasicBought, 0)

    -- 宠物相关商品已从营地移出
    check("营地不再卖抽卡次数", Camp.Item("gacha_low") == nil, "gacha_low")
    check("营地不再卖孵化加速卡", Camp.Item("speed50") == nil, "speed50")

    -- ---------------------------------------------------------------- 农场
    Camp.Buy(data, "seed_basic")
    Camp.Buy(data, "seed_rare")
    eq("基础种子 1 颗", c.seeds.basic, 1)
    eq("稀有种子 1 颗", c.seeds.rare, 1)
    eq("窝 Lv.1 有 2 块地", Camp.Plots(data), 2)
    local okPlant = Camp.Plant(data, 1, "basic")
    check("播种成功", okPlant, "plant")
    check("同一块地不能重复种", not Camp.Plant(data, 1, "basic"))
    local okEarly, msgEarly = Camp.Harvest(data, 1)
    check("没熟不能收", not okEarly, msgEarly)
    check("第 3 块地还没开垦", not Camp.Plant(data, 3, "rare"))

    c.plots[1].readyAt = os.time()
    local okHarvest = Camp.Harvest(data, 1)
    check("成熟可收获", okHarvest, "harvest")
    local fruitCount = 0
    for _, v in pairs(c.fruits) do fruitCount = fruitCount + v end
    eq("果实总数 +1", fruitCount, 1)

    -- ---------------------------------------------------------------- 窝
    eq("初始窝等级 Lv.1", c.nestLevel, 1)
    local okNest0, msgNest0 = Camp.UpgradeNest(data)
    check("建材不够不能盖窝", not okNest0, msgNest0)
    c.mats.basic = 999
    c.mats.mid = 999
    local okNest = Camp.UpgradeNest(data)
    check("盖窝成功", okNest, "nest")
    eq("窝升到 Lv.2", c.nestLevel, 2)
    eq("地块 +1", Camp.Plots(data), 3)
    for _ = 1, 3 do Camp.UpgradeNest(data) end
    eq("窝满级 Lv.5", c.nestLevel, 5)
    eq("满级地块 6", Camp.Plots(data), 6)
    local okMaxNest = Camp.UpgradeNest(data)
    check("满级不能再升", not okMaxNest, "max nest")

    -- ---------------------------------------------------------------- 背包清单
    do
        c.keys = 2
        c.fruits.purple = 3
        local list = Camp.Inventory(data)
        check("背包有内容", #list > 0, #list)
        local hasKey, hasFruit = false, false
        for _, it in ipairs(list) do
            if it.name == "钥匙" then hasKey = it.count == 2 end
            if it.name == "紫色果实" then hasFruit = it.count == 3 end
        end
        check("背包列出钥匙且数量正确", hasKey, "key")
        check("背包列出果实且数量正确", hasFruit, "fruit")
    end

    -- ---------------------------------------------------------------- 果实 → 开局 Buff
    c.fruits.blue = 1
    local okEquip = Camp.EquipFruit(data, "blue")
    check("装果实成功", okEquip, "equip")
    eq("背包里有蓝色果实", c.equippedFruit, "blue")

    Save.SetClass(data, "swordsman")
    data.unlocked = 1
    data.stageCleared = 0
    S.data = data
    Run.Start(1, true)
    local run = S.run
    check("开局消耗了果实", c.equippedFruit == nil, c.equippedFruit)
    check("开局给了一个 Buff", run and #run.player.buffs >= 1, run and #run.player.buffs)

    -- 钥匙带入本局
    c.keys = 2
    Run.Start(1, true)
    check("钥匙带入本局", (S.run.guildKeys or 0) >= 2, S.run and S.run.guildKeys)
    eq("带入后局外钥匙清零", c.keys, 0)

    -- ---------------------------------------------------------------- 金币：每关重置，房内不清，无尽不清
    do
        data.unlocked = 20
        data.stageCleared = 19
        Run.Start(1, true)
        eq("开新关时金币从 0 开始", Economy.Gold(data), 0)
        Economy.AddGold(data, 120)
        eq("关内攒到 120", Economy.Gold(data), 120)
        S.run.posR, S.run.posC = 1, 2
        eq("换房间不清金币", Economy.Gold(data), 120)
        Run.Start(2, true)
        eq("下一关金币重置为 0", Economy.Gold(data), 0)

        Run.StartEndless()
        eq("无尽开局金币 0", Economy.Gold(data), 0)
        Economy.AddGold(data, 80)
        Run.NextEndlessLayer()
        eq("无尽下一层保留金币", Economy.Gold(data), 80)
        Economy.ResetGold(data)
    end

    print(string.format("[Camp] done, failures = %d", fails))
    WriteSaveRaw(BACKUP)
    print("[Camp] save.json restored")
end
