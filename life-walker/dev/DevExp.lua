-- DevExp.lua — 总经验池 / 职业分配 / 分职业等级
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
    -- 旧存档迁移
    Save.Write({ version = 1, level = 7, exp = 123, loadout = { 1, 2, 3 } })
    local old = Save.Load()
    check("旧存档等级迁移", old.levels.swordsman == 7, old.levels and old.levels.swordsman)
    check("旧存档经验保留", old.exp == 123, old.exp)
    check("旧等级字段清空", old.level == nil, old.level)

    -- 新存档分配
    local data = Save.Load()
    data.levels = { swordsman = 1, spearman = 1 }
    data.classExp = { swordsman = 0, spearman = 0 }
    Save.SetClass(data, "swordsman")
    data.exp = 1000
    data.classExp.swordsman = 0
    data.classExp.spearman = 0
    local got = Save.AllocateExp(data, 400)
    check("投入 400", got == 400 and data.exp == 600 and Save.ClassExp(data) == 400,
        string.format("pool=%d class=%d", data.exp, Save.ClassExp(data)))
    Save.SetClass(data, "spearman")
    check("切换后职业经验独立", Save.ClassExp(data) == 0, Save.ClassExp(data))
    check("切换后职业等级独立", Save.ClassLevel(data) == 1, Save.ClassLevel(data))
    Save.AllocateExp(data, 100)
    check("枪客投入 100", Save.ClassExp(data) == 100 and data.exp == 500,
        string.format("pool=%d class=%d", data.exp, Save.ClassExp(data)))
    Save.AllocateExp(data, data.exp)
    check("全部投入", data.exp == 0 and Save.ClassExp(data) == 600,
        string.format("pool=%d class=%d", data.exp, Save.ClassExp(data)))

    -- 升级只消耗本职业经验
    local ok, msg = Save.LevelUp(data)
    check("枪客升到 2 级", ok and Save.ClassLevel(data) == 2, msg)
    check("升级消耗本职业经验", Save.ClassExp(data) == 594, Save.ClassExp(data))
    Save.SetClass(data, "swordsman")
    check("剑客经验不受影响", Save.ClassExp(data) == 400 and Save.ClassLevel(data) == 1,
        string.format("exp=%d lv=%d", Save.ClassExp(data), Save.ClassLevel(data)))

    -- 升到 11 级需要连续健康（分职业门槛）
    Save.SetClass(data, "spearman")
    Save.SetClassLevel(data, 10)
    data.classExp.spearman = 5000
    data.streak = 0
    local ok2, msg2 = Save.LevelUp(data)
    check("10→11 需要连续健康", not ok2 and string.find(msg2, "连续健康") ~= nil, msg2)
    data.streak = 3
    local ok3 = Save.LevelUp(data)
    check("连续 3 天后可升 11", ok3 and Save.ClassLevel(data) == 11, Save.ClassLevel(data))

    print(string.format("[Exp] done, failures = %d", fails))
end
