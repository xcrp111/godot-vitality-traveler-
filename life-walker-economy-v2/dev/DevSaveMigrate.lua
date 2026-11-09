-- DevSaveMigrate.lua — 存档版本迁移 / 结构矫正（v1 → v2）
-- 覆盖：远古无版本存档、v1 全量迁移、幂等、未来版本不倒退、脏字段纠正、
--       金币清零、账号等级同步、写盘往返、子系统结构完整性。
-- 运行方式（在 .cli 目录下）：
--   UrhoXRuntime.exe ../dev/DevSaveMigrate.lua "-tapcode_dir=<项目根>" -tool_mode \
--     -graphicsheadless -validate -validate-frames=5 -validate-timeout=30

local Config = require "Config"
local Save = require "Save"
local Economy = require "Economy"

local fails, total = 0, 0
local function check(name, cond, detail)
    total = total + 1
    if cond then
        print("[Save] OK   " .. name)
    else
        fails = fails + 1
        print("[Save] FAIL " .. name .. (detail ~= nil and (" — " .. tostring(detail)) or ""))
    end
end

local function loadFrom(tbl)
    Save.Write(tbl)
    return Save.Load()
end

function Start()
    print("[Save] schema version = " .. Save.SchemaVersion())
    check("当前结构版本是 2", Save.SchemaVersion() == 2, Save.SchemaVersion())

    -- 1) 远古存档：连 version 字段都没有
    local ancient = loadFrom({ level = 3, loadout = { 2, 3, 1 }, gold = 5000 })
    check("无版本存档被升到 2", ancient.version == 2, ancient.version)
    check("旧单一等级落到当前职业", ancient.levels.swordsman == 3, ancient.levels.swordsman)
    check("旧单一 loadout 落到当前职业",
        ancient.loadouts.swordsman[1] == 2 and ancient.loadouts.swordsman[2] == 3
        and ancient.loadouts.swordsman[3] == 1,
        table.concat(ancient.loadouts.swordsman or {}, ","))
    check("旧 level / loadout 字段被清掉", ancient.level == nil and ancient.loadout == nil)
    check("读档金币清零（金币只在关卡内有效）", ancient.gold == 0, ancient.gold)
    check("没有通关记录时按解锁进度补齐", type(ancient.stageCleared) == "number")

    -- 2) v1 全量迁移：exp → essence，classExp 退回总池
    local v1 = loadFrom({
        version = 1, exp = 100, classExp = { swordsman = 50, spearman = 20 },
        unlocked = 5, stageCleared = 4,
    })
    check("exp 并入精粹", Economy.Essence(v1) == 170, Economy.Essence(v1))
    check("exp 字段被移除", v1.exp == nil)
    check("已投入职业经验清零", Save.ClassExp(v1) == 0, Save.ClassExp(v1))
    check("迁移不动关卡进度", v1.unlocked == 5 and v1.stageCleared == 4,
        tostring(v1.unlocked) .. "/" .. tostring(v1.stageCleared))
    check("版本升到 2", v1.version == 2, v1.version)

    -- 3) 幂等：同一份存档 Load 两次，关键字段不变
    Save.Write(v1)
    local again = Save.Load()
    check("重复读档不重复加精粹", Economy.Essence(again) == 170, Economy.Essence(again))
    check("重复读档关卡进度不变",
        again.unlocked == v1.unlocked and again.stageCleared == v1.stageCleared)
    check("重复读档版本不变", again.version == 2, again.version)

    -- 4) 未来版本：不倒退版本号、不跑迁移
    local future = loadFrom({ version = 99, essence = 7, gold = 3 })
    check("未来版本不被写回旧版本", future.version == 99, future.version)
    check("未来版本数据不被改动", Economy.Essence(future) == 7, Economy.Essence(future))

    -- 5) 脏字段（手改存档）：全部纠正到合法值
    local dirty = loadFrom({
        version = 2,
        class = "nope",
        essence = "abc",
        bodyFat = 99,
        unlocked = 999,
        stageCleared = -3,
        levels = { swordsman = 0, ranger = "x" },
        loadouts = { mage = { 99, 1, 1 } },
        damageText = 123,
        joyMode = "??",
        fpsCap = "60",
        aimHold = 0.7,
        musicVolume = 5,
        claimed = "yes",
        dayKey = 7,
    })
    check("非法职业回落到剑客", dirty.class == "swordsman", dirty.class)
    check("非数字精粹变成 0", Economy.Essence(dirty) == 0, Economy.Essence(dirty))
    check("体脂率夹到 60", dirty.bodyFat == 60, dirty.bodyFat)
    check("解锁关卡夹到 20", dirty.unlocked == 20, dirty.unlocked)
    check("通关数夹到 0..20", dirty.stageCleared == 0, dirty.stageCleared)
    check("等级 0 夹到 1", dirty.levels.swordsman == 1, dirty.levels.swordsman)
    check("等级 \"x\" 回落 1", dirty.levels.ranger == 1, dirty.levels.ranger)
    check("不存在的技能 id 被剔除",
        dirty.loadouts.mage[1] == 1 and dirty.loadouts.mage[2] == 2 and dirty.loadouts.mage[3] == 3,
        table.concat(dirty.loadouts.mage or {}, ","))
    check("伤害数字枚举回落 full", dirty.damageText == "full", dirty.damageText)
    check("摇杆模式枚举回落 float", dirty.joyMode == "float", dirty.joyMode)
    check("帧率 \"60\" 回落 60", dirty.fpsCap == 60, dirty.fpsCap)
    check("非法长按阈值回落 0.22", dirty.aimHold == 0.22, dirty.aimHold)
    check("音量夹到 1", dirty.musicVolume == 1, dirty.musicVolume)
    check("布尔字段回落 false", dirty.claimed == false, tostring(dirty.claimed))
    check("日期键被补成合法字符串", type(dirty.dayKey) == "string" and #dirty.dayKey > 0,
        tostring(dirty.dayKey))
    check("布局表被补齐", type(dirty.layout) == "table" and type(dirty.layout.joy) == "table")

    -- 6) 账号等级：由累计获得精粹重算，不发错技能点
    local lv = loadFrom({ version = 2, essence = 0, essenceEarned = 1000, accountLevel = 1 })
    check("账号等级按累计精粹重算", Economy.AccountLevel(lv) == 6, Economy.AccountLevel(lv))
    check("等级同步写回存档", lv.accountLevel == 6, lv.accountLevel)

    -- 7) 写盘往返：编解码两轮后出战技能仍是 3 个数字
    Save.Write(lv)
    local round = Save.Load()
    Save.Write(round)
    local round2 = Save.Load()
    local okLo = true
    for _, class in ipairs({ "swordsman", "spearman", "ranger", "mage" }) do
        local lo = round2.loadouts[class]
        if type(lo) ~= "table" or #lo ~= 3 then okLo = false end
        for i = 1, 3 do
            if type(lo[i]) ~= "number" then okLo = false end
        end
    end
    check("往返后四职业出战技能完整", okLo)

    -- 8) 结构完整性：Defaults 里的每个字段读档后都存在
    local def = Save.Defaults()
    local missing = {}
    for k in pairs(def) do
        if round2[k] == nil then missing[#missing + 1] = k end
    end
    check("读档补齐了所有默认字段", #missing == 0, table.concat(missing, ","))

    -- 9) 子系统结构（公会 / 营地 / 宠物）
    check("公会有存档结构", type(round2.guild) == "table")
    check("营地有存档结构", type(round2.camp) == "table")
    check("宠物有存档结构", type(round2.pet) == "table" and type(round2.pet.seen) == "table")

    print(string.format("[Save] done, %d checks, failures = %d", total, fails))
end
