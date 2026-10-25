-- DevDays.lua — 下一天 / 连续健康 / 10→11 门槛冒烟
local Save = require "Save"
local S = require "State"

function Start()
    S.data = Save.Load()
    local d = S.data
    d.dayOffset = 0
    d.streak = 0
    d.lastActiveDay = 0
    d.claimed = false
    d.dayKey = ""
    d.level = 10
    d.exp = 10000

    local _, _, st1 = Save.Claim(d, 12000)
    print("[Days] day1 streak=" .. st1 .. " claimed=" .. tostring(d.claimed))

    Save.NextDay(d)
    local _, _, st2 = Save.Claim(d, 12000)
    print("[Days] day2 streak=" .. st2 .. " claimed=" .. tostring(d.claimed))

    Save.NextDay(d)
    local _, _, st3 = Save.Claim(d, 12000)
    print("[Days] day3 streak=" .. st3 .. " claimed=" .. tostring(d.claimed))

    local ok, msg = Save.LevelUp(d)
    print("[Days] levelup ok=" .. tostring(ok) .. " msg=" .. msg .. " level=" .. d.level)

    Save.NextDay(d)
    local _, _, st4 = Save.Claim(d, 12000)
    print("[Days] day4 streak=" .. st4 .. " claimed=" .. tostring(d.claimed))
end
