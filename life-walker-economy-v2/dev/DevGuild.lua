-- DevGuild.lua — 公会系统验收脚本（开发用，不参与正式流程）
-- 1) 贡献币 / 公会经验 / 等级 / 商店解锁 / 科技上限 / 团本难度 的逻辑断言
-- 2) 团本实战：技能跟首页选择、Boss 伤害按难度放大、结算评级
-- 3) 公会界面 5 个页签各画一遍

local Config = require "Config"
local Save = require "Save"
local S = require "State"
local Guild = require "Guild"
local Run = require "Run"

local fails = 0
local function check(name, cond, detail)
    if cond then
        print("[GuildTest] OK   " .. name)
    else
        fails = fails + 1
        print("[GuildTest] FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
    end
end

local function logicTests()
    local data = Save.Fresh()
    Guild.Ensure(data)
    check("初始贡献币为 0", data.guild.coins == 0, data.guild.coins)
    check("初始公会等级 1", Guild.Level(data) == 1, Guild.Level(data))
    check("公会 1 级科技上限 2", Guild.TechCap(data) == 2, Guild.TechCap(data))
    check("公会 1 级只解锁普通团本", Guild.RaidTierMax(data) == 1, Guild.RaidTierMax(data))

    local ok, msg = Guild.Sign(data)
    check("签到 +20", ok and data.guild.coins == 20, msg)
    check("获得贡献币同时获得公会经验", data.guild.exp == 20, data.guild.exp)
    check("全员总经验 = 个人 x 成员数", Guild.TotalExp(data) == 20 * #Guild.Members,
        Guild.TotalExp(data))

    local list = Guild.RescueList(data)
    check("每日救援名单非空", #list > 0, #list)
    local before = data.guild.coins
    ok = Guild.Rescue(data, list[1].idx)
    check("救援 +80", ok and data.guild.coins == before + 80, data.guild.coins - before)

    ok = Guild.SendBounty(data, 1)
    check("悬赏拓印 +50", ok, ok)

    local feed = Guild.Feed(data)
    check("战报有内容", #feed >= 4, #feed)
    before = data.guild.coins
    ok = Guild.Like(data, 1)
    check("点赞 +5", ok and data.guild.coins == before + 5, data.guild.coins - before)

    -- 周上限
    local added, overflow = Guild.AddCoins(data, 99999)
    check("周上限封顶 3500", data.guild.weekEarned == Guild.COIN_CAP, data.guild.weekEarned)
    check("溢出折算感谢信", overflow > 0 and data.guild.thanks > 0, data.guild.thanks)

    -- 等级：经验达标 → 手动升级 → 科技上限 / 团本档位跟着涨
    data.guild.coins = 5000
    check("达标后可升级", Guild.CanLevelUp(data) == true)
    ok = Guild.LevelUpGuild(data)
    check("升级到 Lv.2", ok and Guild.Level(data) == 2, Guild.Level(data))
    check("Lv.2 科技上限 4", Guild.TechCap(data) == 4, Guild.TechCap(data))
    check("Lv.2 解锁困难团本", Guild.RaidTierMax(data) == 2, Guild.RaidTierMax(data))
    check("经验不因升级被扣", data.guild.exp == 3500, data.guild.exp)
    ok = Guild.LevelUpGuild(data)
    check("继续升到 Lv.3", ok and Guild.Level(data) == 3, Guild.Level(data))
    ok = Guild.LevelUpGuild(data)
    check("继续升到 Lv.4", ok and Guild.Level(data) == 4, Guild.Level(data))
    ok = Guild.LevelUpGuild(data)
    check("经验不足无法升 Lv.5", not ok, ok)
    check("Lv.4 科技上限 8", Guild.TechCap(data) == 8, Guild.TechCap(data))

    -- 商店等级解锁
    ok, msg = Guild.BuyWeekly(data, "stone")
    check("Lv.1 商品可直接买", ok, msg)
    data.guild.level = 1
    ok, msg = Guild.BuyWeekly(data, "crystal")
    check("低等级锁住稀有商品", not ok, msg)
    ok, msg = Guild.BuyPerk(data, "insurance")
    check("低等级锁住稀有特权", not ok, msg)
    data.guild.level = 4
    local expBefore = data.exp
    ok = Guild.BuyWeekly(data, "crystal")
    check("Lv.2 解锁经验结晶", ok, msg)
    check("经验结晶 +300 经验", data.exp == expBefore + 300, data.exp - expBefore)
    local sp = data.skillPoints
    ok = Guild.BuyWeekly(data, "stone")
    check("技能突破石 +1 技能点", ok and data.skillPoints == sp + 1)
    local keys = data.guild.keys
    ok = Guild.BuyWeekly(data, "key")
    check("钥匙 +1", ok and data.guild.keys == keys + 1)

    -- 科技树上限
    data.guild.tech.survival = 0
    data.guild.coins = 99999
    for i = 1, 4 do
        ok = Guild.UpgradeTech(data, "survival")
        if not ok then break end
    end
    check("科技升到 Lv.4", data.guild.tech.survival == 4, data.guild.tech.survival)
    for i = 1, 4 do Guild.UpgradeTech(data, "survival") end
    check("科技卡在公会等级上限 8", data.guild.tech.survival == 8, data.guild.tech.survival)
    ok, msg = Guild.UpgradeTech(data, "survival")
    check("超过上限升级被拒绝", not ok, msg)
    local b = Guild.Bonus(data)
    check("科技加成生效", math.abs(b.shieldPct - 0.12) < 1e-9, b.shieldPct)

    -- 团本难度档位
    ok, msg = Guild.SetRaidTier(data, 3)
    check("可选择已解锁档位", ok and Guild.RaidTier(data) == 3, msg)
    ok = Guild.SetRaidTier(data, 5)
    check("未解锁档位被夹到上限", Guild.RaidTier(data) == 4, Guild.RaidTier(data))
    check("难度 4 的 Boss 伤害倍率", math.abs(Guild.RaidAtkMul(4) - 2.4) < 1e-9, Guild.RaidAtkMul(4))

    -- 局内特权与开局结算
    data.guild.coins = 5000
    Guild.BuyPerk(data, "silver")
    Guild.BuyPerk(data, "reroll")
    Guild.BuyPerk(data, "insurance")
    Guild.BuyPerk(data, "warn")
    local run = { silver = 0, player = { mods = {} } }
    Guild.StartRun(run, data)
    check("开局加注 +50 银币", run.silver == 50, run.silver)
    check("重随券生效", run.guildRerolls == 1, run.guildRerolls)
    check("保险生效", run.guildInsurance == true)
    check("预警生效", run.guildEliteWarn == true)
    check("特权买完即清空", data.guild.perks.silver == 0 and data.guild.perks.reroll == 0)

    -- 团本评级（按输出量）+ 难度加成
    data.guild.raid.done = false
    data.guild.weekEarned = 0
    data.guild.coins = 0
    local grade, coins = Guild.CompleteRaid(data, 82, false, 8200)
    check("团本按输出评级 A", grade == "A", grade)
    check("难度加成生效（A 基础 875 x1.5）", coins == 1313, coins)
    check("团本每周只能结算一次", Guild.CompleteRaid(data, 100) == "A")
    check("结算记录档位与输出量", data.guild.raid.tier == 4 and data.guild.raid.damage == 8200,
        tostring(data.guild.raid.tier) .. "/" .. tostring(data.guild.raid.damage))
    check("团本结算后不可再挑战", Guild.RaidReady(data) == false)
    check("测试模式下团本可重复挑战", Guild.RaidReady(data, true) == true)
    local fg, fc = Guild.CompleteRaid(data, 100, true, 12000)
    check("测试模式重复结算不报错且给币", fg == "S" and fc > 0, tostring(fg) .. "/" .. tostring(fc))

    -- 存档往返
    ok = Save.Write(data)
    local loaded = Save.Load()
    check("公会数据写盘并读回", ok and loaded.guild and loaded.guild.coins == data.guild.coins,
        loaded.guild and loaded.guild.coins)
    check("公会等级持久化", Guild.Level(loaded) == 4, Guild.Level(loaded))
    check("科技等级持久化", loaded.guild.tech.survival == 8, loaded.guild.tech.survival)
    check("团本档位持久化", Guild.RaidTier(loaded) == 4, Guild.RaidTier(loaded))

    -- 局内 mods 注入
    local p = Run.NewPlayer(5)
    Guild.ApplyRunMods(p, loaded)
    Run.Recompute(p)
    check("初始护盾加成进了 maxShield", p.maxShield >= p.baseShield, p.maxShield)

    -- 一键重置（测试）
    data.guild.shop.bought.stone = 3
    data.guild.raid.done = true
    local rok, rmsg = Guild.ResetWeeklyForTest(data)
    check("一键重置清空周限购与团本次数", rok and data.guild.raid.done == false
        and next(data.guild.shop.bought) == nil, rmsg)

    print("[GuildTest] logic done, fails = " .. fails)
end

local function raidSmoke()
    local ok, err = pcall(function()
        local Combat = require "Combat"
        S.data = Save.Load()
        S.data.guild.raid.done = false
        S.data.guild.weekEarned = 0
        -- 让技能位有货：等级拉高 + 指定首页配置
        Save.SetClassLevel(S.data, 6)
        S.data.loadouts[S.data.class] = { 1, 2, 3 }

        Run.StartRaid()
        local cs = S.combat
        assert(cs and cs.guildRaid, "团本战斗没有创建")
        assert(S.run.loadout[1] == 1 and S.run.loadout[2] == 2 and S.run.loadout[3] == 3,
            "团本技能没有跟随首页选择: " .. tostring(S.run.loadout[1]) .. "," .. tostring(S.run.loadout[2]))
        check("团本技能跟随首页技能选择", true)

        for i = 1, 150 do Combat.Update(1 / 60) end
        assert(#cs.enemies > 0, "团本没有刷出敌人")
        local guard = 0
        while #cs.enemies > 0 and guard < 400 and not cs.raidFinished do
            for i = #cs.enemies, 1, -1 do Combat.KillEnemy(cs, cs.enemies[i]) end
            Combat.Update(1 / 60)
            guard = guard + 1
        end
        local boss = nil
        for i = 1, 300 do
            if cs.raidFinished then break end
            Combat.Update(1 / 60)
            boss = nil
            for _, e in ipairs(cs.enemies) do
                if e.kind == "boss" then boss = e end
            end
            if boss then break end
        end
        check("团本固定刷关底 Boss（瘟衰巨像）", boss ~= nil and boss.id == Guild.RAID_BOSS_ID,
            boss and boss.id)
        check("团本按第 1 关数值出怪", S.run.level == 1, S.run.level)
        if boss then
            local baseAtk = select(2, Config.MonsterStats(S.run.level, 9, "boss"))
            local expect = baseAtk * Guild.RaidAtkMul(S.run.raidTier or 1)
            check("Boss 伤害按难度档位放大", math.abs(boss.atk - expect) < 1e-6,
                tostring(boss.atk) .. " vs " .. tostring(expect))
            cs.raidDamage, cs.raidBossMax = 100, 100
            boss.hp = 1
            Combat.HitEnemy(cs, boss, 99999, false, true, false, "test", true)
            check("击杀 Boss 后自动结算 S 级", S.data.guild.raid.grade == "S",
                S.data.guild.raid.grade)
        end
        assert(S.screen == "menu" and S.guild == true, "结算后没有回到公会界面")
        print("[GuildTest] raid grade = " .. tostring(S.data.guild.raid.grade))
    end)
    check("团本战斗能跑帧并结算", ok, err)
end

local function drawTests()
    local ok, err = pcall(function()
        S.data = Save.Load()
        Config.SetClass(Save.ActiveClass(S.data))
        S.ctx = S.ctx or nvgCreate(1)
        S.font = nvgCreateFont(S.ctx, "sans", "Fonts/MiSans-Regular.ttf")
        S.screen = "menu"
        S.guild = true
        for tab = 1, 5 do
            S.guildTab = tab
            local Menu = require "Menu"
            Menu.Draw()
        end
        S.guild = false
        local Menu = require "Menu"
        Menu.Draw()
    end)
    check("公会界面 5 个页签绘制无错误", ok, err)
end

function Start()
    logicTests()
    raidSmoke()
    drawTests()
    print("[GuildTest] total fails = " .. fails)
end

function Stop() end
