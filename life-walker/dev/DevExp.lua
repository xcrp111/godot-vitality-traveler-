-- DevExp.lua — 全局经验池直接用于升级（不再两步投入）/ 分职业等级 / 旧存档迁移
local Config = require "Config"
local Save = require "Save"
local S = require "State"

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
    -- 旧存档迁移：单一等级转成当前职业等级
    Save.Write({ version = 1, level = 7, exp = 123, loadout = { 1, 2, 3 } })
    local old = Save.Load()
    check("旧存档等级迁移", old.levels.swordsman == 7, old.levels and old.levels.swordsman)
    check("旧存档经验保留", old.exp == 123, old.exp)
    check("旧等级字段清空", old.level == nil, old.level)

    -- 迁移：旧「已投入职业经验」并回总池
    Save.Write({ version = 1, exp = 100, classExp = { swordsman = 50, spearman = 20 } })
    local migrated = Save.Load()
    check("已投入经验并回总池", migrated.exp == 170, migrated.exp)
    check("迁移后职业经验清零", Save.ClassExp(migrated) == 0, Save.ClassExp(migrated))

    -- 新存档：升级直接从总池扣
    local data = Save.Load()
    data.levels = { swordsman = 1, spearman = 1, ranger = 1, mage = 1 }
    data.classExp = { swordsman = 0, spearman = 0, ranger = 0, mage = 0 }
    Save.SetClass(data, "swordsman")
    data.exp = 100
    local cost1 = Config.LevelCost[1]
    local ok, msg = Save.LevelUp(data)
    check("直接用总池升级", ok and Save.ClassLevel(data) == 2, msg)
    check("扣掉正好一级的量", data.exp == 100 - cost1, data.exp .. " vs " .. (100 - cost1))

    -- 经验不足时不升级、不扣
    data.exp = 0
    local ok2, msg2 = Save.LevelUp(data)
    check("经验不足不能升", not ok2 and Save.ClassLevel(data) == 2, msg2)
    check("失败不扣经验", data.exp == 0, data.exp)

    -- 切职业：各职业等级独立，池子共用
    Save.SetClass(data, "spearman")
    check("切换后职业等级独立", Save.ClassLevel(data) == 1, Save.ClassLevel(data))
    data.exp = Config.LevelCost[1]
    local ok3, msg3 = Save.LevelUp(data)
    check("枪客也能升级", ok3 and Save.ClassLevel(data) == 2, msg3)
    check("共用同一个池子", data.exp == 0, data.exp)
    Save.SetClass(data, "swordsman")
    check("剑客等级不受影响", Save.ClassLevel(data) == 2, Save.ClassLevel(data))

    -- 分职业门槛：10→11 需要连续健康
    Save.SetClass(data, "spearman")
    Save.SetClassLevel(data, 10)
    data.exp = 999999
    data.streak = 0
    local ok4, msg4 = Save.LevelUp(data)
    check("10→11 需要连续健康", not ok4 and string.find(msg4, "连续健康") ~= nil, msg4)
    check("被门槛挡住不扣经验", data.exp == 999999, data.exp)
    data.streak = 3
    local ok5 = Save.LevelUp(data)
    check("连续 3 天后可升 11", ok5 and Save.ClassLevel(data) == 11, Save.ClassLevel(data))

    print(string.format("[Exp] done, failures = %d", fails))
end
