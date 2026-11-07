-- DevStageGate.lua — 关卡解锁：步数解锁 + 必须通关上一关；开发调试按钮
local Config = require "Config"
local Save = require "Save"
local S = require "State"
local Run = require "Run"

local fails = 0
local function check(name, cond, detail)
    if cond then
        print("[Gate] OK   " .. name)
    else
        fails = fails + 1
        print("[Gate] FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
    end
end

function Start()
    -- ============ 旧存档迁移：不倒退进度 ============
    Save.Write({ version = 1, unlocked = 6, gold = 100 })
    local old = Save.Load()
    check("旧存档迁移：已通关 = 解锁-1", old.stageCleared == 5, old.stageCleared)
    check("旧存档迁移后仍能打到第 6 关", Save.MaxPlayable(old) == 6, Save.MaxPlayable(old))

    -- ============ 双条件 ============
    local data = Save.Load()
    data.unlocked = 5
    data.stageCleared = 0
    check("只靠步数解锁不能推进", Save.MaxPlayable(data) == 1, Save.MaxPlayable(data))

    Save.MarkCleared(data, 1)
    check("通第 1 关后可打第 2 关", Save.MaxPlayable(data) == 2, Save.MaxPlayable(data))

    Save.MarkCleared(data, 2)
    check("连通关卡可继续", Save.MaxPlayable(data) == 3, Save.MaxPlayable(data))

    data.unlocked = 2
    check("步数不够时仍受步数限制", Save.MaxPlayable(data) == 2, Save.MaxPlayable(data))

    data.unlocked = 10
    data.stageCleared = 4
    check("取两者较小值", Save.MaxPlayable(data) == 5, Save.MaxPlayable(data))

    -- ============ Run.Start 会卡住未解锁的关卡 ============
    data.unlocked = 10
    data.stageCleared = 1
    S.data = data
    Save.SetClass(data, "swordsman")
    Save.SetClassLevel(data, 6)
    Config.SetClass("swordsman")

    Run.Start(8)
    check("未解锁的关卡会被降到可玩关", S.run.level == 2, S.run.level)

    Run.Start(8, true)
    check("测试模式可绕过门槛", S.run.level == 8, S.run.level)

    -- ============ 通关 boss 会记录 ============
    local d2 = Save.Load()
    d2.unlocked = 20
    d2.stageCleared = 0
    S.data = d2
    Save.SetClassLevel(d2, 6)
    Run.Start(1, true)
    S.run.roomType = "boss"
    S.run.posR, S.run.posC = 1, 1
    Run.OnRoomCleared()
    check("打掉 Boss 记录通关", d2.stageCleared >= 1, d2.stageCleared)
    check("记录后开放下一关", Save.MaxPlayable(d2) >= 2, Save.MaxPlayable(d2))

    -- ============ 调试按钮 ============
    Save.DebugUnlockAll(d2)
    check("调试：解锁全部关卡", Save.MaxPlayable(d2) == 20, Save.MaxPlayable(d2))
    check("调试：步数也推满", d2.unlocked == 20, d2.unlocked)

    print("[Gate] done, failures = " .. fails)
end
