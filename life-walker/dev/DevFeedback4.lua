-- DevFeedback4.lua — 2026-10-31 测试反馈回归
-- 1) 拖动技能选方向时，技能方向不再被左摇杆覆盖（闪影突进 / 瞬影连斩 / 枪客位移 / 三段斩）
-- 2) 公会周限购按自然周重置（不依赖 os.date("%w")，模拟 %w 失效的平台）
-- 3) 公会商店的 Buff 重随券能真正刷新奖励三选一
-- 4) 灵魂摆渡次数正确累加
-- 5) 健康任务跨天重置
-- 6) 取消施法框默认位置上移，老存档自动迁移
local Config = require "Config"
local Save = require "Save"
local S = require "State"
local Run = require "Run"
local Combat = require "Combat"
local Guild = require "Guild"

local fails = 0
local function check(name, cond, detail)
    if cond then
        print("[FB4] OK   " .. name)
    else
        fails = fails + 1
        print("[FB4] FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
    end
end

local function NewCombat(class, loadout)
    S.data = Save.Load()
    Save.SetClass(S.data, class)
    Save.SetClassLevel(S.data, 10)
    Config.SetClass(class)
    Run.Start(3, true)
    S.run.loadout = loadout or { 1, 2, 3 }
    local cs = Combat.Start(S.run, "standard", 1)
    S.screen = "combat"
    cs.enemies = {}
    cs.walls = {}
    cs.waves = { {} }
    cs.waveIndex = 1
    cs.player.x, cs.player.y = 640, 400
    cs.player.shield = 0
    return cs
end

local function ReleaseInput()
    S.input.x, S.input.y = 0, 0
end

function Start()
    -- ============ 1. 拖动瞄准后，技能方向不被左摇杆覆盖 ============
    local cs = NewCombat("swordsman", { 1, 2, 3 })
    S.input.x, S.input.y = 1, 0          -- 左手一直往右推
    cs.aimLock = true
    cs.facing = -math.pi / 2             -- 右手拖动选的是"上"
    Combat.CastSkill(2)                  -- 闪影突进
    check("1 闪影突进按瞄准方向（上），不是摇杆方向（右）",
        cs.dash ~= nil and math.abs(cs.dash.diry + 1) < 0.05 and math.abs(cs.dash.dirx) < 0.05,
        cs.dash and string.format("%.2f,%.2f", cs.dash.dirx, cs.dash.diry))
    ReleaseInput()

    -- 没有瞄准时仍然跟随摇杆（原来的手感不能被改掉）
    cs = NewCombat("swordsman", { 1, 2, 3 })
    S.input.x, S.input.y = 1, 0
    cs.facing = -math.pi / 2
    Combat.CastSkill(2)
    check("1 没瞄准时突进仍跟随摇杆",
        cs.dash ~= nil and math.abs(cs.dash.dirx - 1) < 0.05,
        cs.dash and string.format("%.2f,%.2f", cs.dash.dirx, cs.dash.diry))
    ReleaseInput()

    -- 枪客突刺
    cs = NewCombat("spearman", { 1, 2, 4 })
    S.input.x, S.input.y = 1, 0
    cs.aimLock = true
    cs.facing = -math.pi / 2
    Combat.CastSkill(2)                  -- 突刺奔袭
    check("1 枪客突刺按瞄准方向",
        cs.dash ~= nil and math.abs(cs.dash.diry + 1) < 0.05,
        cs.dash and string.format("%.2f,%.2f", cs.dash.dirx, cs.dash.diry))
    ReleaseInput()

    -- 瞬影连斩第二段沿用第一段方向
    cs = NewCombat("swordsman", { 6, 2, 3 })
    S.input.x, S.input.y = 1, 0
    cs.aimLock = true
    cs.facing = -math.pi / 2
    Combat.CastSkill(1)                  -- loadout[1] = 瞬影连斩
    cs.aimLock = nil                     -- 松手后瞄准标志会被清掉
    cs.facingLock = 0.45                 -- 但朝向锁还在
    Combat.Update(0.31)                  -- 触发第二段
    check("1 瞬影连斩第二段仍按瞄准方向",
        cs.dash ~= nil and math.abs(cs.dash.diry + 1) < 0.05,
        cs.dash and string.format("%.2f,%.2f", cs.dash.dirx, cs.dash.diry))
    ReleaseInput()

    -- 三段斩：延迟结算的命中也要用手动方向
    cs = NewCombat("swordsman", { 1, 2, 3 })
    Combat.SpawnWave(cs, { minion = 1 })
    local up = cs.enemies[1]
    up.x, up.y = 640, 330                -- 正上方
    up.hp, up.maxHp = 9999, 9999
    S.input.x, S.input.y = 1, 0
    cs.aimLock = true
    cs.facing = -math.pi / 2
    Combat.CastSkill(1)                  -- 三段斩
    cs.aimLock = nil
    cs.facingLock = 0.45
    Combat.Update(0.10)                  -- 第一段延迟 0.05 秒结算
    check("1 三段斩按瞄准方向命中上方敌人", up.hp < 9999, up.hp)
    ReleaseInput()

    -- ============ 2. 公会周限购按自然周重置（模拟 %w 失效） ============
    local realDate, realTime = os.date, os.time
    os.date = function(fmt, t)
        if type(fmt) == "string" and string.find(fmt, "%%w", 1, true) then return "" end
        return realDate(fmt, t)
    end
    local data = { dayOffset = 0, guild = { coins = 100000, level = 5,
        week = "", shop = { week = "", bought = {} } } }
    local base = 1793395200                 -- 2026-10-31（周六）
    local weeks = {}
    os.time = function() return base end
    Guild.BuyWeekly(data, "stone")
    check("2 周六买到 1 个技能石", (data.guild.shop.bought.stone or 0) == 1,
        data.guild.shop.bought.stone)
    for d = 0, 9 do
        os.time = function() return base + d * 86400 end
        local g = Guild.Roll(data)
        weeks[d] = { week = g.week, bought = g.shop.bought.stone or 0 }
    end
    check("2 周日计数不清零", weeks[1].bought == 1, weeks[1].bought)
    check("2 周一才清零", weeks[2].bought == 0, weeks[2].bought)
    check("2 一周内周键不变", weeks[0].week == weeks[1].week)
    os.date, os.time = realDate, realTime

    -- ============ 3. Buff 重随券真正生效 ============
    local S3 = Save.Fresh()
    S3.guild.level = 5
    S3.guild.coins = 1000
    local okBuy = Guild.BuyPerk(S3, "reroll")
    S.data = S3
    Config.SetClass("swordsman")
    Run.Start(1, true)
    check("3 重随券开局带进局内", (S.run.guildRerolls or 0) == 1, S.run.guildRerolls)
    S.reward = { options = {}, roomType = "standard" }
    local rolled = Run.RerollReward()
    check("3 重随券能刷新三选一", rolled == true and #S.reward.options == 3,
        rolled and #S.reward.options)
    check("3 重随券用掉后次数减少", (S.run.guildRerolls or 0) == 0, S.run.guildRerolls)

    -- ============ 4. 灵魂摆渡次数累加 ============
    local S4 = Save.Fresh()
    local list = Guild.RescueList(S4)
    Guild.Rescue(S4, list[1].idx)
    Guild.Rescue(S4, list[2].idx)
    check("4 摆渡计数累加到 2", Guild.Roll(S4).rescue == 2, Guild.Roll(S4).rescue)
    Guild.Rescue(S4, list[3].idx)
    local ok4 = Guild.Rescue(S4, list[1].idx)
    check("4 摆渡满 3 次后拒绝", Guild.Roll(S4).rescue == 3 and ok4 == false,
        tostring(Guild.Roll(S4).rescue) .. "/" .. tostring(ok4))

    -- ============ 5. 健康任务跨天重置 ============
    local S5 = Save.Fresh()
    S5.waterMl = 2000
    S5.sleptEarly = true
    local t0 = os.time()
    realTime = os.time
    os.time = function() return t0 + 2 * 86400 end
    Save.RollDay(S5)
    os.time = realTime
    check("5 跨天饮水归零", (S5.waterMl or 0) == 0, S5.waterMl)
    check("5 跨天早睡打卡重置", S5.sleptEarly == false, S5.sleptEarly)

    -- ============ 6. 取消施法框默认位置上移 ============
    local L1 = Save.Layout({ layout = { aim_cancel = { x = 1170, y = 378, r = 80 } } })
    check("6 老默认值自动迁移到新位置", L1.aim_cancel.y == 300, L1.aim_cancel.y)
    local L2 = Save.Layout({ layout = { aim_cancel = { x = 1134, y = 209, r = 80 } } })
    check("6 玩家自定义位置不被改", L2.aim_cancel.y == 209, L2.aim_cancel.y)
    local L3 = Save.Layout({})
    check("6 新存档默认位置是 300", L3.aim_cancel.y == 300, L3.aim_cancel.y)

    print("[FB4] done, failures = " .. fails)
end
