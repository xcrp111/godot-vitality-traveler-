-- DevFriend.lua — 农场好友系统回归（浇水 / 偷菜 / 友好度 / 赠送 / 回访通知）
local Config = require "Config"
local Save = require "Save"
local S = require "State"
local Farm = require "Farm"
local Friend = require "Friend"

local fails = 0
local function check(name, cond, detail)
    if cond then
        print("[Friend] OK   " .. name)
    else
        fails = fails + 1
        print("[Friend] FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
    end
end

local function setup()
    S.data = Save.Load()
    S.data.farm = nil
    S.data.friend = nil
    S.data.stageCleared = 16          -- 解锁全部作物
    local f = Farm.Roll(S.data)
    f.landCount = 9
    return S.data
end

--- 把好友某块地调到「成熟且过了保护期」
local function RipeFree(f, idx, cropId)
    local crop = Farm.CropByID(cropId or "fire")
    f.farm.plots[idx] = { crop = crop.id, plantedAt = os.time() - crop.total * 3600 - 3 * 3600,
        waterBonus = 0, waterAt = 0, stolen = false }
end

--- 成熟但还在保护期
local function RipeProtected(f, idx, cropId)
    local crop = Farm.CropByID(cropId or "fire")
    f.farm.plots[idx] = { crop = crop.id, plantedAt = os.time() - crop.total * 3600 - 30 * 60,
        waterBonus = 0, waterAt = 0, stolen = false }
end

--- 生长中
local function Growing(f, idx, cropId)
    local crop = Farm.CropByID(cropId or "fire")
    f.farm.plots[idx] = { crop = crop.id, plantedAt = os.time() - 600,
        waterBonus = 0, waterAt = 0, stolen = false }
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

    local d = setup()

    -- 1) 初始化
    Friend.Bootstrap(d)
    local list = Friend.List(d)
    check("首次进入自动送 3 个好友", #list == 3, #list)
    check("我的好友码是 6 位", #Friend.MyCode(d) == 6, Friend.MyCode(d))
    local f = list[1]
    check("好友有名字", type(f.name) == "string" and #f.name > 0, f.name)
    check("好友有农场地块", f.farm and f.farm.landCount >= 4, f.farm and f.farm.landCount)

    -- 2) 添加好友
    local okAdd, _, nf = Friend.AddByCode(d, "ABC123")
    check("好友码添加成功", okAdd == true)
    check("添加后好友数 +1", #Friend.List(d) == 4, #Friend.List(d))
    local okDup = Friend.AddByCode(d, "ABC123")
    check("重复好友码被拒", okDup == false)
    local okBad = Friend.AddByCode(d, "AB")
    check("好友码格式校验", okBad == false)

    -- 3) 浇水：生长中才可浇，-15 分钟，友好度 +1
    Growing(f, 2)
    local before = Friend.PlotInfo(f, 2).stageRemain
    local okW, msgW = Friend.Water(d, f.id, 2)
    check("生长中可以浇水", okW == true, msgW)
    local after = Friend.PlotInfo(f, 2).stageRemain
    check("浇水利于加速（剩余减少约 15 分钟）", before - after >= 890 and before - after <= 910,
        string.format("%d → %d", before, after))
    check("浇水双方友好度 +1", (f.friendship or 0) == 1, f.friendship)
    local okW2 = Friend.Water(d, f.id, 2)
    check("同一块地 2 小时冷却生效", okW2 == false)
    f.farm.plots[3] = nil                      -- 清空 3 号地
    local okW3 = Friend.Water(d, f.id, 3)     -- 空地不能浇
    check("空地不能浇水", okW3 == false)

    -- 4) 偷菜：保护期不能偷，过保护期能偷，只能偷一次
    RipeProtected(f, 1, "fire")
    local info1 = Friend.PlotInfo(f, 1)
    check("成熟但保护期内不可偷", info1.canSteal == false and info1.status == "mature",
        string.format("%s canSteal=%s", info1.status, tostring(info1.canSteal)))
    local okS0, msgS0 = Friend.Steal(d, f.id, 1)
    check("保护期内偷菜被拒", okS0 == false, msgS0)

    RipeFree(f, 1, "fire")
    local fruitBefore = Farm.FruitCount(d, "fire")
    local okS, msgS = Friend.Steal(d, f.id, 1)
    check("过保护期可以偷菜", okS == true, msgS)
    check("偷到 1 个果实入库", Farm.FruitCount(d, "fire") == fruitBefore + 1,
        Farm.FruitCount(d, "fire"))
    check("地块标记为已被偷", f.farm.plots[1].stolen == true)
    local okS2 = Friend.Steal(d, f.id, 1)
    check("同一棵不能偷第二次", okS2 == false)
    check("偷菜也加友好度", (f.friendship or 0) >= 2, f.friendship)

    -- 5) 每日上限
    local before5 = Friend.Ensure(d).day.water
    Friend.Ensure(d).day.water = Friend.DAILY_WATER
    Growing(f, 4)
    local okCap = Friend.Water(d, f.id, 4)
    check("每日浇水次数上限生效", okCap == false)
    Friend.Ensure(d).day.water = before5

    -- 6) 一键三连要 Lv.2
    local okAll0 = Friend.WaterAll(d, f.id)
    check("Lv.2 之前不能一键三连", okAll0 == false)
    f.friendship = 120
    Growing(f, 5)
    local okAll, msgAll = Friend.WaterAll(d, f.id)
    check("Lv.2 后可以一键三连", okAll == true, msgAll)

    -- 7) 每日友好度上限 50
    f.dayGain = Friend.DAY_GAIN_CAP
    local gained = Friend.Gain(d, f, 10)
    check("单个好友每日友好度上限 50", gained == 0, gained)

    -- 8) 赠送种子
    f.dayGain = 0
    Farm.AddSeed(d, "fire", 3)
    Friend.Ensure(d).day.gift = 0
    local seedBefore = Farm.SeedCount(d, "fire")
    local okG, msgG = Friend.Gift(d, f.id)
    check("赠送种子成功", okG == true, msgG)
    check("赠送消耗 1 颗种子", Farm.SeedCount(d, "fire") == seedBefore - 1,
        Farm.SeedCount(d, "fire"))
    check("赠送双方友好度 +3", (f.friendship or 0) >= 123, f.friendship)
    local okG2 = Friend.Gift(d, f.id)
    check("每天只能赠送一次", okG2 == false)

    -- 9) 好友回访：玩家农场被浇水 / 被偷 → 通知 + 收获 -1
    local fr = Friend.Ensure(d)
    fr.lastTick = os.time() - 12 * 3600      -- 假装离线 12 小时
    local farm = Farm.Roll(d)
    farm.plots[1] = { crop = "fire", plantedAt = os.time() - 4 * 3600 - 3 * 3600,
        waterBonus = 0, waterAt = 0, stolen = false }
    local notifBefore = #fr.notify
    for _ = 1, 6 do Friend.Tick(d) end       -- 多跑几次，保证至少产生一条事件
    check("好友回访会产生通知", #fr.notify >= notifBefore, #fr.notify - notifBefore)

    -- 玩家地块被偷后收获 -1
    local crop = Farm.CropByID("fire")
    farm.plots[2] = { crop = "fire", plantedAt = os.time() - crop.total * 3600 - 60,
        waterBonus = 0, waterAt = 0, stolen = true }
    local fBefore = Farm.FruitCount(d, "fire")
    local okH, msgH = Farm.Harvest(d, 2)
    check("被偷过的地仍然能收获", okH == true, msgH)
    check("被偷后收获少 1 个", Farm.FruitCount(d, "fire") == fBefore + (crop.yield - 1),
        string.format("%d → %d（应 +%d）", fBefore, Farm.FruitCount(d, "fire"), crop.yield - 1))
    check("收获后 stolen 清掉", farm.plots[2].stolen ~= true)

    -- 10) 界面能画
    S.screen = "menu"
    S.farm = true
    local okDraw, err = pcall(function()
        S.friendOpen = true
        S.friendView = nil
        local FriendUI = require "FriendUI"
        FriendUI.Draw()
        S.friendView = { view = "farm", id = f.id }
        FriendUI.Draw()
        S.friendView = { view = "notify" }
        FriendUI.Draw()
        FriendUI.Close()
    end)
    check("好友界面三个视图都能绘制", okDraw, err)

    print(string.format("[Friend] done, failures = %d", fails))
end
