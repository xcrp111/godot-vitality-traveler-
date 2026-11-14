-- DevFarm.lua — 农场系统逻辑回归
local Config = require "Config"
local Save = require "Save"
local S = require "State"
local Farm = require "Farm"

local fails = 0
local function check(name, cond, detail)
    if cond then
        print("[Farm] OK   " .. name)
    else
        fails = fails + 1
        print("[Farm] FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
    end
end

function Start()
    S.data = Save.Fresh()
    local d = S.data

    -- 解锁
    d.stageCleared = 1
    check("通关 1 关未解锁", Farm.Unlocked(d) == false)
    d.stageCleared = 2
    check("通关 2 关解锁", Farm.Unlocked(d) == true)
    local starter = Farm.Ensure(d)
    check("首次解锁送起步种子", starter.seeds.fire == 2 and starter.seeds.ice == 2,
        tostring(starter.seeds.fire) .. "/" .. tostring(starter.seeds.ice))
    starter.seeds = {}
    starter.starterGiven = true

    -- 种植 / 浇水 / 阶段
    Farm.AddSeed(d, "fire", 2)
    local ok, msg = Farm.Plant(d, 1, "fire")
    check("种下火灵果", ok, msg)
    check("种子消耗 1 个", Farm.SeedCount(d, "fire") == 1, Farm.SeedCount(d, "fire"))
    local info = Farm.PlotInfo(d, 1)
    check("刚种下是发芽期", info.status == "growing" and info.stage == 1, info.stageName)

    local plot = Farm.Ensure(d).plots[1]
    plot.plantedAt = Farm.Now(d) - 3600 * 1.6   -- 1.6 小时
    info = Farm.PlotInfo(d, 1)
    check("1.6 小时后进生长期", info.stage == 2, info.stageName)

    local before = info.stageRemain
    local wok = Farm.Water(d, 1)
    info = Farm.PlotInfo(d, 1)
    check("浇水减少 15 分钟", wok and math.abs((before - info.stageRemain) - 900) < 2,
        before - info.stageRemain)
    check("浇水进入冷却", Farm.PlotInfo(d, 1).waterReady == false)
    check("浇水声望 +1", Farm.Ensure(d).rep == 1, Farm.Ensure(d).rep)

    -- 成熟 / 收获
    plot.plantedAt = Farm.Now(d) - 4 * 3600 - 10
    info = Farm.PlotInfo(d, 1)
    check("4 小时后成熟", info.status == "mature", info.status)
    local fok, fmsg = Farm.Harvest(d, 1)
    check("收获火灵果 ×3", fok and Farm.FruitCount(d, "fire") == 3, fmsg)
    check("收获后土地变空", Farm.PlotInfo(d, 1).status == "empty")

    -- 仓库上限
    Farm.Ensure(d).fruits.fire = 30
    Farm.AddSeed(d, "fire", 1)
    Farm.Plant(d, 1, "fire")
    Farm.Ensure(d).plots[1].plantedAt = Farm.Now(d) - 5 * 3600
    local capOk, capMsg = Farm.Harvest(d, 1)
    check("果实满 30 个不能收获", (not capOk) and string.find(capMsg or "", "仓库已满", 1, true) ~= nil, capMsg)
    Farm.Ensure(d).plots[1].crop = nil

    -- 携带果实 → 开局生效
    local fd = Farm.Ensure(d)
    fd.fruits = { fire = 2, gold = 1, timevine = 1, phoenix = 1, mushroom = 1, chaos = 1 }
    fd.equipped = { "fire", "gold", "timevine", "phoenix" }
    local p = { mods = {}, flags = {}, revive = 0, reviveUsed = false }
    local run = { silver = 0, guildRerolls = 0, player = p }
    local randoms = Farm.ApplyRunBuffs(run, d)
    check("火灵果攻击 +10%", math.abs((p.mods.atkPct or 0) - 0.10) < 1e-6, p.mods.atkPct)
    check("金币花银币 +50", run.silver == 50, run.silver)
    check("时空藤奖励重随 +3", run.guildRerolls == 3, run.guildRerolls)
    check("凤凰花复活 +1（写进 mods，开局重算后仍保留）", p.mods.revive == 1, p.mods.revive)
    check("果实被消耗", Farm.FruitCount(d, "fire") == 1, Farm.FruitCount(d, "fire"))
    check("携带列表清空", #Farm.EquippedList(d) == 0)
    check("随机强化列表正确", #randoms == 0)   -- 本次没携带蘑菇

    -- 蘑菇 / 混沌随机强化
    fd.equipped = { "mushroom", "chaos" }
    randoms = Farm.ApplyRunBuffs({ player = { mods = {}, flags = {} }, silver = 0 }, d)
    check("蘑菇+混沌返回 2 个随机品级", #randoms == 2, #randoms)
    check("随机品级有效", randoms[1] == "white" and (randoms[2] == "blue" or randoms[2] == "purple"),
        table.concat(randoms, ","))

    -- 金币商店
    d.gold = 1000
    local gok = Farm.BuyGoldSeed(d, "basic")
    check("金币商店买基础种子", gok, gok)
    local gok2, gmsg2 = Farm.BuyGoldSeed(d, "basic")
    Farm.BuyGoldSeed(d, "basic")
    local gok3, gmsg3 = Farm.BuyGoldSeed(d, "basic")
    check("金币商店每日限购 3 次", gok3 == false, gmsg3)

    -- 声望商店 / 土地解锁
    fd.rep = 2000
    local land0 = fd.landCount
    local lok, lmsg = Farm.BuyRep(d, "land")
    check("声望商店解锁土地", lok and fd.landCount == land0 + 1, lmsg)
    check("土地解锁消耗声望", fd.rep == 1800, fd.rep)
    check("chaos 累计消耗计入", fd.repSpent >= 200, fd.repSpent)

    -- 日常任务：3 场战斗
    fd.dailyBattles = 0
    fd.battleReward = false
    Farm.OnBattleFinished(d)
    Farm.OnBattleFinished(d)
    local seed3 = Farm.OnBattleFinished(d)
    check("3 场战斗奖励基础种子", seed3 ~= nil, seed3)

    -- 周常：10 层
    fd.weeklyLayers = 0
    fd.layerReward = false
    local last
    for _ = 1, 10 do last = Farm.OnEndlessLayer(d) end
    check("10 层奖励稀有种子", last ~= nil, last)

    -- 战斗掉落（强制概率 1）
    d.stageCleared = 20
    local drop = Farm.CombatDrop(d, "boss", 1)
    check("Boss 掉落稀有种子", drop ~= nil, drop)

    print("[Farm] done, failures = " .. fails)
end
