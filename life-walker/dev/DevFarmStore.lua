-- DevFarmStore.lua — 农场联机服务端数据层回归（纯逻辑）
local FarmStore = require "FarmStore"

local fails = 0
local function check(name, cond, detail)
    if cond then
        print("[Store] OK   " .. name)
    else
        fails = fails + 1
        print("[Store] FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
    end
end

function Start()
    local now = 1000000

    local a = FarmStore.NewDoc("uidA", "阿茶", now)
    local b = FarmStore.NewDoc("uidB", "白露", now)

    -- 1) 好友关系
    local okReq = FarmStore.RequestFriend(a, b, now)
    check("发起好友请求", okReq == true)
    check("请求进了对方收件箱", b.requests.incoming["uidA"] ~= nil)
    check("还没成为好友", a.friends["uidB"] == nil)
    local okAcc = FarmStore.AcceptFriend(b, a, now + 1)
    check("接受好友请求", okAcc == true)
    check("双向成为好友", a.friends["uidB"] ~= nil and b.friends["uidA"] ~= nil)
    check("收件箱清空", b.requests.incoming["uidA"] == nil)

    -- 2) 种植
    b.seeds.fire = 2
    local okPlant = FarmStore.Plant(b, 1, "fire", now)
    check("种下作物", okPlant == true)
    check("种子扣除", (b.seeds.fire or 0) == 1, b.seeds.fire)

    -- 3) 浇水（生长中）
    local okW, errW = FarmStore.Water(b, 1, now + 60, { uid = "uidA", name = "阿茶" })
    check("好友可以浇水", okW == true, errW)
    local info = FarmStore.PlotInfo(b, 1, now + 60)
    check("浇水后阶段剩余减少约 15 分钟",
        info.stageRemain <= 3600 - 890, math.floor(info.stageRemain))
    local okW2 = FarmStore.Water(b, 1, now + 120, { uid = "uidA", name = "阿茶" })
    check("2 小时冷却生效", okW2 == false)
    local okSelf = FarmStore.Water(b, 1, now + 3 * 3600, { uid = "uidB", name = "白露" })
    check("不能给自己浇水", okSelf == false)
    local c = FarmStore.NewDoc("uidC", "陌生人", now)
    local okStranger = FarmStore.Water(b, 1, now + 3 * 3600, { uid = "uidC", name = "陌生人" })
    check("非好友不能浇水", okStranger == false)

    -- 4) 偷菜：未成熟 / 保护期 / 过保护期
    local okS0 = FarmStore.Steal(b, 1, now + 600, { uid = "uidA" })
    check("未成熟不能偷", okS0 == false)
    local matured = now + 4 * 3600 + 120      -- 火灵果 4 小时成熟
    local okS1 = FarmStore.Steal(b, 1, matured + 60, { uid = "uidA" })
    check("保护期内不能偷", okS1 == false)
    local okS2, errS2 = FarmStore.Steal(b, 1, matured + 3 * 3600, { uid = "uidA" })
    check("过保护期可以偷", okS2 == true, errS2)
    local okS3 = FarmStore.Steal(b, 1, matured + 3 * 3600, { uid = "uidA" })
    check("同一棵只能偷一次", okS3 == false)

    -- 5) 收获：被偷少 1 个
    local okH, got = FarmStore.Harvest(b, 1, matured + 4 * 3600)
    check("能收获", okH == true, got)
    check("被偷后收获少 1 个", got == 2, got)
    check("收获入果实仓库", (b.fruits.fire or 0) == 2, b.fruits.fire)
    check("地块清空", FarmStore.PlotInfo(b, 1, matured + 4 * 3600).status == "empty")

    -- 6) 事件队列
    check("被浇水事件记录", (function()
        for _, e in ipairs(b.events) do if e.kind == "water" then return true end end
        return false
    end)())
    check("被偷事件记录", (function()
        for _, e in ipairs(b.events) do if e.kind == "steal" then return true end end
        return false
    end)())

    -- 7) 快照不含隐私字段
    local snap = FarmStore.Snapshot(b, now)
    check("快照有地块数", snap.landCount >= 4, snap.landCount)
    check("快照不带种子/果实", snap.seeds == nil and snap.fruits == nil)

    -- 8) 搜索
    check("按 id 搜索命中", FarmStore.MatchQuery(b, "uidB") == true)
    check("按名字前缀搜索命中", FarmStore.MatchQuery(b, "白") == true)
    check("搜不到返回 false", FarmStore.MatchQuery(b, "张三") == false)

    -- 9) 删除好友
    check("删除好友", FarmStore.RemoveFriend(b, "uidA", now) == true)
    check("删除后不再互为好友", b.friends["uidA"] == nil)

    print(string.format("[Store] done, failures = %d", fails))
end
