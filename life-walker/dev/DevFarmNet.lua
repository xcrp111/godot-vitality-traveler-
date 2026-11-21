-- DevFarmNet.lua — 客户端 ↔ 服务端全链路回归（用假传输直连 FarmServer.Dispatch）
local FarmStore = require "FarmStore"
local FarmShared = require "network.FarmShared"
local FarmServer = require "network.FarmServer"
local FarmClient = require "network.FarmClient"
local Friend = require "Friend"

local fails = 0
local function check(name, cond, detail)
    if cond then
        print("[Net] OK   " .. name)
    else
        fails = fails + 1
        print("[Net] FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
    end
end

local EV = FarmShared.EVENTS
local currentUid = nil

--- 假传输：客户端发出的包直接打到服务端的纯逻辑入口
local function InstallFakeTransport()
    FarmClient.SetTransport({
        send = function(eventName, payload)
            local uid = payload.__uid or currentUid
            FarmServer.Dispatch(uid, eventName, payload, function(name, reply)
                FarmClient.OnPacket(name, reply)
            end)
        end,
    })
end

local function As(uid, fn)
    currentUid = uid
    fn()
    currentUid = nil
end

function Start()
    FarmServer.Reset()
    FarmClient.Disconnect()
    InstallFakeTransport()

    -- 1) 两个人各自同步
    As("u1", function() FarmClient.Sync("阿茶") end)
    check("u1 同步成功", FarmClient.online == true and FarmClient.uid == "u1", FarmClient.uid)
    check("同步后拿到自己文档", FarmClient.doc ~= nil and FarmClient.doc.landCount == 4)

    As("u2", function() FarmClient.Sync("白露") end)
    check("u2 同步成功", FarmClient.uid == "u2")

    -- 2) u1 种地 / 收获
    As("u1", function() FarmClient.Plant(1, "fire") end)
    check("没种子种不了", FarmClient.doc and (FarmClient.doc.plots[1] == nil), "地块应为空")
    local doc1 = FarmServer.LoadDoc and nil
    -- 直接给 u1 发种子（服务端侧）
    local srvDoc = FarmServer._store["u1"]
    srvDoc.seeds.fire = 2
    As("u1", function() FarmClient.Plant(1, "fire") end)
    check("有种子可以种", FarmClient.doc.plots[1] and FarmClient.doc.plots[1].crop == "fire",
        FarmClient.doc.plots[1] and FarmClient.doc.plots[1].crop)

    -- 3) 好友搜索 / 请求 / 同意
    As("u1", function() FarmClient.Search("白露") end)
    check("按名字搜到 u2", (function()
        for _, f in ipairs(FarmClient.searchResult or {}) do
            if f.uid == "u2" then return true end
        end
        return false
    end)())
    As("u1", function() FarmClient.RequestFriend("u2") end)
    As("u2", function() FarmClient.Sync("白露") end)
    check("u2 收到好友请求", FarmClient.requestsIn["u1"] ~= nil,
        FarmClient.requestsIn and next(FarmClient.requestsIn))
    As("u2", function() FarmClient.AcceptFriend("u1") end)
    As("u2", function() FarmClient.Sync("白露") end)
    check("u2 好友列表有 u1", (function()
        for _, f in ipairs(FarmClient.friends or {}) do
            if f.uid == "u1" then return true end
        end
        return false
    end)())

    -- 4) 访问好友农场
    As("u2", function() FarmClient.Visit("u1") end)
    local snap = FarmClient.SnapshotOf("u1")
    check("拿到好友农场快照", snap ~= nil and snap.uid == "u1")
    check("快照里能看到对方种的火灵果", snap and snap.plots[1] and snap.plots[1].crop == "fire",
        snap and snap.plots[1] and snap.plots[1].crop)

    -- 5) 浇水（u1 的地刚种下，处于生长期）
    As("u2", function() FarmClient.Water("u1", 1) end)
    local info = FarmStore.PlotInfo(FarmServer._store["u1"], 1, os.time())
    check("好友浇水生效（阶段剩余减少）", info.stageRemain < 3600, math.floor(info.stageRemain))

    -- 6) 偷菜：没成熟时被拒
    As("u2", function() FarmClient.Steal("u1", 1) end)
    local evs = FarmServer._store["u1"].events
    check("未成熟偷菜不写事件", (function()
        for _, e in ipairs(evs) do if e.kind == "steal" then return false end end
        return true
    end)())

    -- 7) 事件回传给主人
    As("u1", function() FarmClient.Sync("阿茶") end)
    check("主人能收到浇水事件", (function()
        for _, e in ipairs(FarmClient.events or {}) do
            if e.kind == "water" then return true end
        end
        return false
    end)())

    -- 10) 好友码：同步后有码，按码能搜到对方
    As("u1", function() FarmClient.Sync("阿茶") end)
    local myCode = FarmClient.code
    check("同步后拿到自己的好友码", type(myCode) == "string" and #myCode == 6, myCode)
    As("u2", function() FarmClient.Sync("白露") end)
    local u2Code = FarmClient.code
    check("u2 也有好友码", type(u2Code) == "string" and #u2Code == 6, u2Code)
    As("u1", function() FarmClient.Search(u2Code) end)
    check("按好友码能搜到 u2", (function()
        for _, r in ipairs(FarmClient.searchResult or {}) do
            if r.uid == "u2" then return true end
        end
        return false
    end)(), u2Code)
    FarmClient.On(EV.FRIEND_RESULT, function(pl)
        print("[Dbg] resp ok=" .. tostring(pl.ok) .. " kind=" .. tostring(pl.kind)
            .. " n=" .. tostring(pl.list and #pl.list) .. " msg=" .. tostring(pl.msg))
    end)
    As("u1", function() FarmClient.Search("ZZZZZZ") end)
    local missList = FarmClient.searchResult or {}
    check("查不到的好友码返回空", #missList == 0,
        "#" .. #missList .. " 首项=" .. tostring(missList[1] and (missList[1].uid .. "/" .. tostring(missList[1].name))))

    -- 8) 离线状态
    FarmClient.Disconnect()
    check("断开后回到离线", FarmClient.online == false)
    check("离线文案", FarmClient.StatusText():find("离线") ~= nil, FarmClient.StatusText())

    -- 9) 离线时 Friend（本地模拟）仍然可用
    local data = { farm = {}, gold = 0 }
    check("离线本地好友模块可用", type(Friend.Ensure) == "function")

    print(string.format("[Net] done, failures = %d", fails))
end
