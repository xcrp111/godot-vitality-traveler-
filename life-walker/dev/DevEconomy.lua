-- DevEconomy.lua — 经济结算冒烟测试（不参与正式构建）
local Save = require "Save"
local S = require "State"
local Config = require "Config"

function Start()
    S.data = Save.Load()
    Save.Reset(S.data)
    Save.ResetToday(S.data)
    local g, u, st, rg, rsp = Save.Claim(S.data, 12000)
    print(string.format("[Econ] steps=12000 gold=%d unlocks=%d streak=%d rewardGold=%d rewardSp=%d skillPoints=%d",
        g, u, st, rg, rsp, S.data.skillPoints))
    print("[Econ] totalGold=" .. S.data.gold .. " exp=" .. S.data.exp .. " unlocked=" .. S.data.unlocked)
    Save.AllocateExp(S.data, S.data.exp)
    local ok, msg = Save.LevelUp(S.data)
    print("[Econ] levelup ok=" .. tostring(ok) .. " msg=" .. tostring(msg) .. " level=" .. Save.ClassLevel(S.data))
end

function Update()
end
