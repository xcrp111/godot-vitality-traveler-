-- DevNet.lua — 联机层自检（公会服务端/客户端 + 农场分槽存档）
-- 用 NetCore 的假传输在本进程里跑完整的 客户端→服务端→回包 链路，不需要真服务器。

local NetCore = require "network.NetCore"
local GuildStore = require "GuildStore"
local GuildServer = require "network.GuildServer"
local GuildClient = require "network.GuildClient"
local GuildShared = require "network.GuildShared"
local FarmStore = require "FarmStore"

local fails = 0
local function check(name, cond, detail)
    if cond then
        print("[NetTest] OK   " .. name)
    else
        fails = fails + 1
        print("[NetTest] FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
    end
end

local curUid = "1001"

local function pump(event, body, cb)
    NetCore.ServerDispatch(curUid, event, body, function(resp)
        NetCore.ClientDispatch(event, resp)
    end)
    if cb then cb() end
end

-- ---------------------------------------------------------------- 分槽逻辑
local function testSlots()
    -- 把分片阈值临时调小，验证分片/容错（正式值 40，公会上限 30 人）
    local oldChunk = GuildStore.MEMBER_CHUNK
    GuildStore.MEMBER_CHUNK = 12

    local g = GuildStore.NewGuild("G1", "测试公会", "1001", "会长")
    for i = 2, 30 do GuildStore.AddMember(g, tostring(1000 + i), "成员" .. i) end
    check("成员上限 30", #g.members == 30, #g.members)
    local full = GuildStore.AddMember(g, "9999", "多余的人")
    check("超员加入被拒", full == false)

    local slots = GuildStore.ToSlots(g)
    check("成员分片（30 人 / 12 → 3 片）", #slots.members == 3, #slots.members)
    check("meta 记录分片数", slots.meta.memberChunks == 3, slots.meta.memberChunks)

    local back, issues = GuildStore.FromSlots(slots)
    check("分槽往返人数一致", back and #back.members == 30, back and #back.members)
    check("分槽往返无告警", #issues == 0, table.concat(issues, ","))

    -- 坏一片只丢那一片
    local broken = GuildStore.ToSlots(g)
    broken.members[2] = "被截断的字符串"
    local back2, issues2 = GuildStore.FromSlots(broken)
    check("单槽损坏只丢该片（12+6=18）", back2 and #back2.members == 18, back2 and #back2.members)
    check("损坏会记录告警", #issues2 > 0, table.concat(issues2, ","))

    GuildStore.MEMBER_CHUNK = oldChunk
end

-- ---------------------------------------------------------------- 农场分槽
local function testFarmSlots()
    local doc = FarmStore.NewDoc("2001", "农夫", 0)
    doc.code = "ABC123"
    doc.landCount = 6
    doc.plots[1] = { crop = "wheat", plantedAt = 100 }
    doc.seeds.wheat = 3
    doc.fruits.wheat = 2
    doc.friends["1001"] = { since = 10, friendship = 5 }
    doc.rep = 7

    local slots = FarmStore.ToSlots(doc)
    check("农场拆成 4 个槽", slots[FarmStore.SLOT.META] ~= nil
        and slots[FarmStore.SLOT.PLOTS] ~= nil
        and slots[FarmStore.SLOT.INV] ~= nil
        and slots[FarmStore.SLOT.SOCIAL] ~= nil)

    local back, issues = FarmStore.FromSlots(slots)
    check("农场分槽往返无告警", #issues == 0, table.concat(issues, ","))
    check("农场字段保留", back and back.code == "ABC123" and back.landCount == 6
        and back.rep == 7 and back.plots[1] and back.plots[1].crop == "wheat"
        and back.seeds.wheat == 3 and back.fruits.wheat == 2
        and back.friends["1001"] ~= nil)

    local broken = FarmStore.ToSlots(doc)
    broken[FarmStore.SLOT.PLOTS] = nil
    broken[FarmStore.SLOT.SOCIAL] = "坏数据"
    local back2, issues2 = FarmStore.FromSlots(broken)
    check("农场坏槽不影响核心", back2 and back2.code == "ABC123" and back2.seeds.wheat == 3)
    check("农场坏槽有告警", #issues2 >= 2, table.concat(issues2, ","))
end

-- ---------------------------------------------------------------- 公会联机全链路
local function testGuildNet()
    GuildServer.ResetForTest()
    GuildServer.Start()
    GuildClient.ResetForTest()

    NetCore.SetTransport({
        send = function(event, body)
            NetCore.ServerDispatch(curUid, event, body, function(resp)
                NetCore.ClientDispatch(event, resp)
            end)
        end,
    })
    GuildClient.online = true
    GuildClient.status = "idle"

    -- 1) 建会
    local created, err = nil, nil
    GuildClient.Create("生命行者", "会长", function(resp) created = resp end)
    check("创建公会成功", created and created.ok, created and created.msg or err)
    check("创建后拿到快照", created and created.guild and created.guild.name == "生命行者")
    local gid = created and created.guild and created.guild.id

    -- 2) 重复建会应被拒
    local again = nil
    GuildClient.Create("第二个会", "会长", function(resp) again = resp end)
    check("重复建会被拒绝", again and again.ok == false and again.code == "already",
        again and again.code)

    -- 3) 第二个玩家申请
    curUid = "1002"
    GuildClient.ResetForTest()
    GuildClient.online = true
    local applied = nil
    GuildClient.Apply(gid, "阿岚", function(resp) applied = resp end)
    check("他人申请入会", applied and applied.ok, applied and applied.msg)

    -- 4) 会长审批
    curUid = "1001"
    GuildClient.ResetForTest()
    GuildClient.online = true
    local sync1 = nil
    GuildClient.Sync(function(resp) sync1 = resp end)
    check("会长同步成功", sync1 and sync1.ok and sync1.guild)
    check("会长看到 1 条申请", sync1 and sync1.guild and #sync1.guild.applies == 1,
        sync1 and sync1.guild and #sync1.guild.applies)

    local approved = nil
    GuildClient.Approve("1002", function(resp) approved = resp end)
    check("审批通过", approved and approved.ok, approved and approved.msg)
    check("审批后成员 2 人", approved and approved.guild and approved.guild.memberCount == 2,
        approved and approved.guild and approved.guild.memberCount)

    -- 5) 普通成员不能审批
    curUid = "1003"
    GuildClient.ResetForTest()
    GuildClient.online = true
    local noPerm = nil
    GuildClient.Approve("1002", function(resp) noPerm = resp end)
    check("无公会时审批被拒", noPerm and noPerm.ok == false, noPerm and noPerm.code)

    -- 6) 贡献（数值走服务端）
    curUid = "1002"
    GuildClient.ResetForTest()
    GuildClient.online = true
    local donated = nil
    GuildClient.Donate(300, function(resp) donated = resp end)
    check("贡献被服务端记录", donated and donated.ok and donated.guild
        and donated.guild.myCoins == 300, donated and donated.guild and donated.guild.myCoins)
    check("公会经验随贡献增长", donated and donated.guild and donated.guild.exp > 0,
        donated and donated.guild and donated.guild.exp)

    -- 7) 团本上报 → 共享血量池
    local reported = nil
    GuildClient.RaidReport(1500, 42000, 2000, function(resp) reported = resp end)
    check("团本输出上报", reported and reported.ok, reported and reported.msg)
    check("血量池扣减", reported and reported.guild and reported.guild.raid.dealt == 1500,
        reported and reported.guild and reported.guild.raid.dealt)
    check("血量池剩余正确", reported and reported.guild
        and reported.guild.raid.remain == 500, reported and reported.guild and reported.guild.raid.remain)
    check("输出排行有本人", reported and reported.guild and reported.guild.raid.top[1]
        and reported.guild.raid.top[1].dmg == 1500)

    -- 8) 上限校验：单次超过 120% 血量池会被夹
    local capped = nil
    GuildClient.RaidReport(999999, 42000, 2000, function(resp) capped = resp end)
    check("超量上报被夹到上限", capped and capped.ok and capped.applied == 2400,
        capped and capped.applied)

    -- 9) 退会
    local left = nil
    GuildClient.Leave("阿岚", function(resp) left = resp end)
    check("退出公会", left and left.ok, left and left.msg)

    local afterLeave = nil
    GuildClient.Sync(function(resp) afterLeave = resp end)
    check("退会后没有公会", afterLeave and afterLeave.ok and afterLeave.guild == nil)

    -- 10) 离线降级
    NetCore.SetTransport(nil)
    GuildClient.online = false
    local offline = nil
    GuildClient.Sync(function(resp) offline = resp end)
    check("离线时 Sync 优雅降级", offline and offline.ok == false and offline.code == "offline",
        offline and offline.code)

    local stats = GuildServer.Stats()
    check("服务端有读写记录", stats.loads > 0 and stats.saves > 0,
        "loads=" .. stats.loads .. " saves=" .. stats.saves)
end

function Start()
    testSlots()
    testFarmSlots()
    testGuildNet()
    print("[NetTest] total fails = " .. fails)
end

function Stop() end
