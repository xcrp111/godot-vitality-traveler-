-- DevEconomy.lua — 经济系统 v2 回归（《描述表格_经济系统优化版》定稿口径）
-- 跑法：UrhoXRuntime.exe ../dev/DevEconomy.lua "-tapcode_dir=<项目根>" -tool_mode -graphicsheadless
local Config = require "Config"
local Save = require "Save"
local Economy = require "Economy"
local S = require "State"

local fails = 0

-- 回归会直接写 save.json（运行时 cwd = .cli），先备份，跑完原样还回去
local function ReadSaveRaw()
    local ok, text = pcall(function()
        if fileSystem and fileSystem:FileExists("save.json") then
            local f = File("save.json", FILE_READ)
            if f and f:IsOpen() then
                local t = f:ReadString()
                f:Close()
                return t
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
        if f and f:IsOpen() then
            f:WriteString(text)
            f:Close()
        end
    end)
end

local SAVE_BACKUP = ReadSaveRaw()
local function check(name, cond, detail)
    if cond then
        print("[Eco] OK   " .. name)
    else
        fails = fails + 1
        print("[Eco] FAIL " .. name .. (detail ~= nil and (" — " .. tostring(detail)) or ""))
    end
end

local function eq(name, got, want)
    check(name, got == want, "got=" .. tostring(got) .. " want=" .. tostring(want))
end

-- ---------------------------------------------------------------- 2 表：体脂率阶梯
-- 正常范围：4×1 + 5×5 + 6×20 + 5×5 = 174（20% 档）
eq("正常范围 20% 累计精粹 = 174", Economy.TierEssence(20, "normal"), 174)
eq("超重肥胖 20% 累计精粹 = 209", Economy.TierEssence(20, "over"), 209)
eq("正常范围 15% 累计精粹 = 149", Economy.TierEssence(15, "normal"), 149)
eq("正常范围 21% 累计精粹 = 175", Economy.TierEssence(21, "normal"), 175)
eq("正常范围 25% 累计精粹 = 179", Economy.TierEssence(25, "normal"), 179)
eq("超重肥胖 9% 累计精粹 = 54", Economy.TierEssence(9, "over"), 54)
eq("0% 不给精粹", Economy.TierEssence(0, "normal"), 0)

-- ---------------------------------------------------------------- 连击倍率与固定项
eq("未达标倍率 1", Economy.StreakMult(10, 9), 1)
eq("连续 3 天 → 健康 ×2", Economy.StreakMult(3, 15), 2)
eq("连续 7 天 → 健康 ×2", Economy.StreakMult(7, 15), 2)
eq("连续 8 天 → 活力满满 ×3", Economy.StreakMult(8, 15), 3)
eq("未达标固定项 = 3", Economy.DailyFixed(10, 5), 3)
eq("活力满满固定项 = 8", Economy.DailyFixed(8, 20), 8)

-- ---------------------------------------------------------------- 日峰值：174×3+3+5 = 530
do
    local data = { bodyFat = 18 }
    local steps = math.ceil(20 * Config.REST_KCAL / (Config.STEP_KCAL * 100))  -- 20%
    local total, detail = Economy.DailyEssence(data, steps, 8)
    eq("正常范围 20% · 活力满满 = 530", total, 530)
    eq("明细：阶梯", detail.tiered, 174)
    eq("明细：倍率", detail.mult, 3)
    eq("明细：固定", detail.fixed, 8)

    data.bodyFat = 30
    local overTotal, overDetail = Economy.DailyEssence(data, steps, 8)
    eq("超重肥胖 20% · 活力满满 = 635", overTotal, 635)
    eq("超重肥胖走另一条阶梯", overDetail.tiered, 209)

    -- 未达标：只拿阶梯 + 基础 3
    local lowSteps = math.ceil(5 * Config.REST_KCAL / (Config.STEP_KCAL * 100))
    local lowTotal = Economy.DailyEssence({ bodyFat = 18 }, lowSteps, 8)
    eq("未达标（5%）不乘倍率 = 9 + 3", lowTotal, 12)
end

-- ---------------------------------------------------------------- 4 表 B：角色升级 7260
do
    local sum = 0
    for _, c in ipairs(Config.LevelCost) do sum = sum + c end
    eq("角色满级累计 = 7260 精粹", sum, 7260)
    eq("19 级阶梯", #Config.LevelCost, 19)

    -- 角色等级上限 20：任何入口都不能越过
    local d4 = Save.Fresh()
    d4.levels.swordsman = 19
    d4.streak = 30
    Economy.AddEssence(d4, 999999)
    local ok20 = Save.LevelUp(d4)
    check("19 → 20 可以升", ok20, "to20")
    eq("角色满级 = 20", Save.ClassLevel(d4), 20)
    local ok21, msg21 = Save.LevelUp(d4)
    check("20 级不能再升", not ok21, msg21)
    eq("满级后仍为 20", Save.ClassLevel(d4), 20)
    Save.SetClassLevel(d4, 30)
    eq("SetClassLevel 硬钳在 20", Save.ClassLevel(d4), 20)
    eq("满级后无下级消耗", Save.NextCost(d4), nil)
end

-- ---------------------------------------------------------------- 4 表 C：账号等级里程碑
do
    eq("账号等级表内 22 级", Economy.AccountMaxLevel(), 22)
    local data = { essence = 0, essenceEarned = 0, accountLevel = 1, skillPoints = 0 }
    eq("0 精粹 → Lv.1", Economy.AccountLevel(data), 1)
    data.essenceEarned = 115
    eq("累计 115 → Lv.2", Economy.AccountLevel(data), 2)
    data.essenceEarned = 24650
    eq("累计 24650 → Lv.22", Economy.AccountLevel(data), 22)
    -- 22 级之后不封顶：每级 +2000
    data.essenceEarned = 26650
    eq("累计 26650 → Lv.23", Economy.AccountLevel(data), 23)
    data.essenceEarned = 46650
    eq("累计 46650 → Lv.33", Economy.AccountLevel(data), 33)
    data.essenceEarned = 999999
    eq("不设上限（999999 → Lv.509）", Economy.AccountLevel(data), 509)
    -- 高等级下的门槛与基线
    local d3 = { essence = 0, essenceEarned = 24650, accountLevel = 22 }
    local need23, _ = Economy.AccountNext(d3)
    eq("22 级下一级门槛 26650", need23, 26650)
    eq("Lv.22 基线 24650", Economy.AccountBase(22), 24650)
    eq("Lv.23 基线 26650", Economy.AccountBase(23), 26650)

    -- 升级发技能点
    local d2 = { essence = 0, essenceEarned = 0, accountLevel = 1, skillPoints = 0 }
    local got, up = Economy.AddEssence(d2, 218)
    eq("获得 218 精粹", got, 218)
    eq("累计 218 跨 2 级", up, 2)
    eq("技能点随等级发放", d2.skillPoints, 2)
end

-- ---------------------------------------------------------------- 5 表：金币掉落与 194 期望
do
    local drop = Config.GoldDrop
    eq("小兵掉落 2~4", drop.minion[1] == 2 and drop.minion[2] == 4, true)
    eq("精英掉落 15~25", drop.elite[1] == 15 and drop.elite[2] == 25, true)
    eq("Boss 掉落 50~70", drop.boss[1] == 50 and drop.boss[2] == 70, true)
    -- 常规 9 房：18 小兵 + 4 精英 + 1 Boss
    local expect = 18 * 3 + 4 * 20 + 1 * 60
    eq("单局金币期望 = 194", expect, Config.Economy.goldPerRun)
    local ratio = expect / Config.Economy.goldMinRun
    check("单局产出 ÷ 最小花费 ∈ [1.0,1.62]", ratio >= 1.0 and ratio <= 1.62, ratio)
    eq("单局金币按产出倍率放大到 1940", Economy.ScaleGoldIncome(expect), 1940)
    eq("产出倍率 = 10", Economy.GoldIncomeMul(), 10)
end

-- ---------------------------------------------------------------- 金币上限 = 账号等级 × 300
do
    local data = { essence = 0, essenceEarned = 0, accountLevel = 1, gold = 0 }
    eq("Lv.1 金币上限 300×10", Economy.GoldCap(data), 300 * 10)
    local got = Economy.AddGold(data, 9000)
    eq("超出上限只入账到上限", got, 3000)
    eq("金币封顶在 3000", Economy.Gold(data), 3000)
    eq("已满再捡不涨", Economy.AddGold(data, 100), 0)
    check("花超余额失败", Economy.SpendGold(data, 3001) == false, "spend 3001")
    eq("花钱成功", Economy.SpendGold(data, 2000), true)
    eq("余额 1000", Economy.Gold(data), 1000)

    data.essenceEarned = 24650
    Economy.SyncAccountLevel(data)
    eq("Lv.22 金币上限 66000", Economy.GoldCap(data), 66000)
end

-- ---------------------------------------------------------------- 6 表：价格表
do
    eq("小恢复 20", Config.Shop.PotionSmall.price, 20)
    eq("大恢复 40", Config.Shop.PotionLarge.price, 40)
    eq("付费刷新 20", Config.Shop.RefreshPrice, 20)
    eq("付费刷新上限 3 次", Config.Shop.RefreshLimit, 3)
    eq("白 Buff 40", Config.Rarity.white.price, 40)
    eq("蓝 Buff 60", Config.Rarity.blue.price, 60)
    eq("紫 Buff 100", Config.Rarity.purple.price, 100)
    eq("金 Buff 180", Config.Rarity.gold.price, 180)
    eq("彩 Buff 280", Config.Rarity.color.price, 280)
    local w = Config.Rarity.white.weight + Config.Rarity.blue.weight + Config.Rarity.purple.weight
        + Config.Rarity.gold.weight + Config.Rarity.color.weight
    eq("品质权重合计 100", w, 100)
    check("彩色 280 > 单局 194（必须跨关攒钱）", Config.Rarity.color.price > Config.Economy.goldPerRun, true)
end

-- ---------------------------------------------------------------- 存档结算：真跑一次领取
do
    local data = Save.Fresh()
    data.bodyFat = 18
    data.streak = 7
    data.lastActiveDay = math.floor(os.time() / 86400) + (data.dayOffset or 0) - 1
    data.claimed = false
    local steps = math.ceil(20 * Config.REST_KCAL / (Config.STEP_KCAL * 100))
    local total = Save.Claim(data, steps)
    check("领取返回精粹 > 0", (total or 0) > 0, total)
    check("精粹入账", Economy.Essence(data) >= 530, Economy.Essence(data))
    check("累计获得同步", data.essenceEarned >= 530, data.essenceEarned)
    eq("连击天数累到 8", data.streak, 8)
    check("账号等级已提升", Economy.AccountLevel(data) >= 2, Economy.AccountLevel(data))

    -- 重复领取不再加钱
    local before = Economy.Essence(data)
    Save.Claim(data, steps)
    eq("重复领取不重复发奖", Economy.Essence(data), before)

    -- 升级花的是精粹
    local d2 = Save.Fresh()
    Economy.AddEssence(d2, 1000)
    d2.levels.swordsman = 1
    d2.streak = 3
    local ok = Save.LevelUp(d2)
    check("用精粹升级成功", ok, "levelup")
    eq("扣掉 1→2 的 6 精粹", Economy.Essence(d2), 994)

    -- 旧存档迁移：exp → essence
    Save.Write({ version = 1, exp = 1234 })
    local old = Save.Load()
    check("旧存档 exp 迁移到精粹", Economy.Essence(old) >= 1234, Economy.Essence(old))
    eq("旧字段已清除", old.exp, nil)
end

print(string.format("[Eco] done, failures = %d", fails))
-- 把玩家存档写回去，回归不影响真实进度
WriteSaveRaw(SAVE_BACKUP)
print("[Eco] save.json restored")
