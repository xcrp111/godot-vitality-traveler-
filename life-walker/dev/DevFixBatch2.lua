-- DevFixBatch2.lua — 本轮修复点回归（关卡门槛 / 农场品级提示）
local S = require "State"
local Save = require "Save"
local Farm = require "Farm"
local Run = require "Run"

local fails = 0
local function check(name, cond, detail)
    if cond then
        print("[Fx2] OK   " .. name)
    else
        fails = fails + 1
        print("[Fx2] FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
    end
end

function Start()
    local d = Save.Fresh()
    S.data = d
    S.screen = "menu"

    -- 1) 关卡门槛：步数够但没通关，只能进到「已通关 + 1」
    d.unlocked = 10
    d.stageCleared = 2
    check("可挑战关卡取两者较小", Save.MaxPlayable(d) == 3, Save.MaxPlayable(d))
    Run.Start(10)
    check("越级进入会落到可挑战关卡", S.run and S.run.level == 3, S.run and S.run.level)
    S.run = nil
    S.combat = nil
    S.screen = "menu"

    -- 2) 农场品级解锁提示（史诗 / 传说种子买不了时给条件，而不是灰按钮）
    d.stageCleared = 5
    local epic = Farm.TierUnlockText(d, "epic")
    check("史诗锁定时给出条件", epic ~= nil and epic:find("通关") ~= nil, epic)
    local legend = Farm.TierUnlockText(d, "legendary")
    check("传说锁定时给出条件", legend ~= nil and legend:find("15") ~= nil, legend)
    check("基础品级已解锁无提示", Farm.TierUnlockText(d, "basic") == nil,
        Farm.TierUnlockText(d, "basic"))

    -- 通关 12 关后史诗至少有一条路径可用
    d.stageCleared = 12
    check("通关 12 后史诗可买", Farm.TierUnlockText(d, "epic") == nil,
        Farm.TierUnlockText(d, "epic"))

    -- 3) 农场解锁：必须真的通关 2 关
    d.stageCleared = 1
    d.unlocked = 5
    check("没通关 2 关时农场仍锁", Farm.Unlocked(d) == false)
    d.stageCleared = 2
    check("通关 2 关后农场解锁", Farm.Unlocked(d) == true)

    print(string.format("[Fx2] done, failures = %d", fails))
end
