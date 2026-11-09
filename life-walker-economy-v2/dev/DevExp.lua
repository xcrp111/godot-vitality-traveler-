-- DevExp.lua — 角色升级 / 分职业等级 / 旧存档迁移（v2 双币线：升级从精粹池扣）
local Config = require "Config"
local Save = require "Save"
local Economy = require "Economy"

local fails = 0
local function check(name, cond, detail)
    if cond then
        print("[Exp] OK   " .. name)
    else
        fails = fails + 1
        print("[Exp] FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
    end
end

function Start()
    -- 旧存档迁移：单一等级转成当前职业等级，旧「可分配经验」并入精粹
    Save.Write({ version = 1, level = 7, exp = 123, loadout = { 1, 2, 3 } })
    local old = Save.Load()
    check("旧存档等级迁移", old.levels.swordsman == 7, old.levels and old.levels.swordsman)
    check("旧存档经验并入精粹", Economy.Essence(old) == 123, Economy.Essence(old))
    check("旧经验字段清空", old.exp == nil, old.exp)
    check("旧等级字段清空", old.level == nil, old.level)
    check("迁移后版本为 2", old.version == 2, old.version)

    -- 迁移：旧「已投入职业经验」并回总池
    Save.Write({ version = 1, exp = 100, classExp = { swordsman = 50, spearman = 20 } })
    local migrated = Save.Load()
    check("已投入经验并回总池", Economy.Essence(migrated) == 170, Economy.Essence(migrated))
    check("迁移后职业经验清零", Save.ClassExp(migrated) == 0, Save.ClassExp(migrated))

    -- 新存档：升级直接从精粹池扣
    local data = Save.Fresh()
    Save.SetClass(data, "swordsman")
    Economy.AddEssence(data, 100, false)     -- 不计入累计获得，只当钱包余额
    local cost1 = Config.LevelCost[1]
    local ok, msg = Save.LevelUp(data)
    check("直接用精粹升级", ok and Save.ClassLevel(data) == 2, msg)
    check("扣掉正好一级的量", Economy.Essence(data) == 100 - cost1,
        Economy.Essence(data) .. " vs " .. (100 - cost1))

    -- 精粹不足时不升级、不扣
    data.essence = 0
    local ok2, msg2 = Save.LevelUp(data)
    check("精粹不足不能升", not ok2 and Save.ClassLevel(data) == 2, msg2)
    check("失败不扣精粹", Economy.Essence(data) == 0, Economy.Essence(data))

    -- 切职业：各职业等级独立，池子共用
    Save.SetClass(data, "spearman")
    check("切换后职业等级独立", Save.ClassLevel(data) == 1, Save.ClassLevel(data))
    Economy.AddEssence(data, Config.LevelCost[1], false)
    local ok3, msg3 = Save.LevelUp(data)
    check("枪客也能升级", ok3 and Save.ClassLevel(data) == 2, msg3)
    check("共用同一个池子", Economy.Essence(data) == 0, Economy.Essence(data))
    Save.SetClass(data, "swordsman")
    check("剑客等级不受影响", Save.ClassLevel(data) == 2, Save.ClassLevel(data))

    -- 分职业门槛：10→11 需要连续健康
    Save.SetClass(data, "spearman")
    Save.SetClassLevel(data, 10)
    Economy.AddEssence(data, 999999, false)
    data.streak = 0
    local ok4, msg4 = Save.LevelUp(data)
    check("10→11 需要连续健康", not ok4 and string.find(msg4 or "", "连续健康") ~= nil, msg4)
    check("被门槛挡住不扣精粹", Economy.Essence(data) == 999999, Economy.Essence(data))
    data.streak = 3
    local ok5 = Save.LevelUp(data)
    check("连续 3 天后可升 11", ok5 and Save.ClassLevel(data) == 11, Save.ClassLevel(data))

    -- 等级上限 20，任何入口都不得越过
    Save.SetClassLevel(data, 99)
    check("等级夹到 20", Save.ClassLevel(data) == 20, Save.ClassLevel(data))
    local ok6, msg6 = Save.LevelUp(data)
    check("满级后不能再升", not ok6 and string.find(msg6 or "", "满级") ~= nil, msg6)

    print(string.format("[Exp] done, failures = %d", fails))
end
