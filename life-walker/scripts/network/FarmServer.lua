-- FarmServer.lua — 农场联机：服务端（权威数据服务，不参与战斗）
--
-- 职责：
--   1. 按 uid 从 serverCloud 读写「农场文档」
--   2. 处理客户端的浇水 / 偷菜 / 种植 / 收获 / 好友请求
--   3. 每个动作都以 FarmStore 的规则裁决，客户端只做展示
--
-- 只在 IsServerMode() 分支里被 main.lua 加载。

local FarmStore = require "FarmStore"
local FarmShared = require "network.FarmShared"

local FarmServer = {}

local EV = FarmShared.EVENTS
local DIAG_KEY = "farm_diag"      -- 服务端自检信息：写到玩家自己的云变量里，客户端能直接读到
local diag_ = { boot = os.time(), syncCount = 0, lastUid = nil, lastAt = 0 }

--- 把服务端状态写进该玩家自己的云变量（客户端 clientCloud:Get 能读到）
local function WriteDiag(uid)
    if not serverCloud or not uid or uid == "" then return end
    diag_.lastAt = os.time()
    diag_.serverCloud = true
    local payload = FarmShared.Encode(diag_)
    pcall(function() serverCloud:Set(tostring(uid), DIAG_KEY, payload) end)
end
local KEY = FarmShared.KEY

local store_ = {}           -- uid -> doc（内存缓存）
local codeIndex_ = {}       -- 好友码 -> uid（服务端内存索引；正式上量应换成持久索引）
local dirty_ = {}            -- uid -> true（标脏待批量落盘）
local SaveDoc               -- 前向声明：LoadDoc 里分配好友码后要写回
local connUid_ = {}         -- connKey -> uid
local queue_ = {}           -- uid -> { waiting = 是否正在读云端 }

-- ---------------------------------------------------------------- 存储
local function now()
    return os.time()
end

local function cacheUid(uid)
    uid = tostring(uid)
    return store_[uid]
end

--- 读文档：内存有就用内存，否则从 serverCloud 拉（不存在则新建）
---@param uid string
---@param cb fun(doc:table)
local function LoadDoc(uid, cb)
    uid = tostring(uid)
    local cached = cacheUid(uid)
    if cached then
        cb(cached)
        return
    end
    if not serverCloud then
        local doc = FarmStore.NewDoc(uid, "", now())
        store_[uid] = doc
        cb(doc)
        return
    end

    local slots = {}
    local pending = 0
    local finished = false

    local function finalize(raw)
        if finished then return end
        finished = true
        local doc
        if raw then
            doc = FarmStore.Ensure(raw) or FarmStore.NewDoc(uid, "", now())
            print("[Farm] 检测到旧版单槽存档，已拆分为 4 个槽")
            SaveDoc(doc)
        else
            local issues
            doc, issues = FarmStore.FromSlots(slots)
            for _, msg in ipairs(issues) do print("[Farm] 载入告警：" .. msg) end
        end
        doc.uid = uid
        if not doc.code or doc.code == "" then
            doc.code = FarmStore.GenerateCode()
            SaveDoc(doc)
        end
        codeIndex_[doc.code] = uid
        store_[uid] = doc
        cb(doc)
    end

    local function step()
        pending = pending - 1
        if pending > 0 then return end
        if type(slots[FarmStore.SLOT.META]) == "table" then
            finalize(nil)
            return
        end
        serverCloud:Get(uid, KEY, {
            ok = function(values)
                local raw = values and values[KEY] or nil
                local legacy = nil
                if type(raw) == "string" then
                    legacy = FarmShared.Decode(raw)
                elseif type(raw) == "table" then
                    legacy = raw
                end
                finalize(legacy)
            end,
            error = function() finalize(nil) end,
        })
    end

    for _, name in pairs(FarmStore.SLOT) do
        pending = pending + 1
        serverCloud:Get(uid, name, {
            ok = function(values)
                slots[name] = values and values[name] or nil
                step()
            end,
            error = function(code, reason)
                print(string.format("[Farm] 读槽失败 uid=%s slot=%s %s %s",
                    tostring(uid), tostring(name), tostring(code), tostring(reason)))
                slots[name] = nil
                step()
            end,
        })
    end
end

--- 写回 serverCloud（同时更新内存缓存）
local function FlushDoc(doc, cb)
    doc = FarmStore.Ensure(doc)
    if not doc then if cb then cb(false) end return end
    store_[doc.uid] = doc
    dirty_[doc.uid] = nil
    if not serverCloud then if cb then cb(true) end return end

    local slots = FarmStore.ToSlots(doc)
    local names = {}
    for name in pairs(slots) do names[#names + 1] = name end
    table.sort(names, function(a, b)
        if a == FarmStore.SLOT.META then return false end
        if b == FarmStore.SLOT.META then return true end
        return a < b
    end)
    local pending = #names
    local okAll = true
    local function step(ok)
        if ok == false then okAll = false end
        pending = pending - 1
        if pending == 0 and cb then cb(okAll) end
    end
    for _, name in ipairs(names) do
        local payload = FarmShared.Encode(slots[name]) or "{}"
        if #payload > 11 * 1024 then
            print(string.format("[Farm] 槽偏大 uid=%s slot=%s %dB",
                tostring(doc.uid), name, #payload))
        end
        serverCloud:Set(doc.uid, name, payload, {
            ok = function() step(true) end,
            error = function(code, reason)
                print(string.format("[Farm] 写槽失败 uid=%s slot=%s %s %s",
                    tostring(doc.uid), tostring(name), tostring(code), tostring(reason)))
                step(false)
            end,
        })
    end
end

--- 批量落盘：把标脏的文档合并写出去（由 FarmServer.Poll 每 5 秒调一次）
function FlushDirty()
    for uid in pairs(dirty_) do
        local doc = store_[uid]
        if doc then FlushDoc(doc) end
    end
end

SaveDoc = function(doc, cb)
    doc = FarmStore.Ensure(doc)
    if not doc then return end
    store_[doc.uid] = doc
    doc.updatedAt = now()
    if not cb then
        dirty_[doc.uid] = true
        return
    end
    FlushDoc(doc, cb)
end

-- ---------------------------------------------------------------- 工具
local function connectionUid(connection)
    if not connection then return nil end
    local key = tostring(connection)
    if connUid_[key] then return connUid_[key] end
    local id = connection.identity and connection.identity["user_id"] or nil
    if id then
        local uid = tostring(id:GetInt64())
        connUid_[key] = uid
        return uid
    end
    return nil
end

local function reply(connection, eventName, payload)
    if not connection then return end
    local okSend, err = pcall(function()
        connection:SendRemoteEvent(eventName, true, FarmShared.MakePayload(payload))
    end)
    if not okSend then
        print("[Farm] 回包失败 " .. tostring(eventName) .. ": " .. tostring(err))
    end
end

local function bodyOf(eventData)
    local raw = eventData["Data"]
    if raw then
        local ok, s = pcall(function() return raw:GetString() end)
        if ok and type(s) == "string" then return FarmShared.Decode(s) or {} end
    end
    return {}
end

--- 对外可见的好友列表（uid + 名字 + 友好度）
local function friendListOf(doc)
    local out = {}
    for _, uid in ipairs(FarmStore.FriendList(doc)) do
        local f = doc.friends[uid] or {}
        local d = store_[uid]
        out[#out + 1] = { uid = uid, name = f.name or uid, code = d and d.code or nil,
            friendship = f.friendship or 0, since = f.since or 0 }
    end
    return out
end

--- 未读事件
local function unreadEvents(doc)
    local out = {}
    for _, ev in ipairs(doc.events or {}) do
        if not ev.read then out[#out + 1] = ev end
    end
    return out
end

local function markRead(doc)
    for _, ev in ipairs(doc.events or {}) do ev.read = true end
end

--- 同步包：自己文档的全量可见部分 + 好友列表 + 未读事件
local function syncPayload(doc)
    return {
        ok = true,
        uid = doc.uid,
        name = doc.name,
        code = doc.code,
        landCount = doc.landCount,
        seeds = doc.seeds,
        fruits = doc.fruits,
        rep = doc.rep,
        plots = FarmStore.Snapshot(doc, now()).plots,
        friends = friendListOf(doc),
        incoming = doc.requests.incoming,
        outgoing = doc.requests.outgoing,
        events = unreadEvents(doc),
    }
end

-- ---------------------------------------------------------------- 事件处理
local pendingReply_ = nil

local function MakeReply(connection)
    if connection then
        return function(eventName, payload) reply(connection, eventName, payload) end
    end
    -- 纯逻辑调用（客户端假传输 / 联调测试）：回包走 pendingReply_
    return function(eventName, payload)
        if pendingReply_ then pendingReply_(eventName, payload) end
    end
end

local function HandleSync(eventType, eventData)
    local connection = eventData["Connection"] and eventData["Connection"]:GetPtr("Connection") or nil
    local body = bodyOf(eventData)
    local uid = connection and connectionUid(connection) or (type(body) == "table" and body.__uid or nil)
    local replyTo = MakeReply(connection)
    if not uid then return end
    diag_.syncCount = (diag_.syncCount or 0) + 1
    diag_.lastUid = uid
    WriteDiag(uid)
    LoadDoc(uid, function(doc)
        if type(body.name) == "string" and body.name ~= "" then
            doc.name = body.name
            SaveDoc(doc)
        end
        -- 先打包（带未读事件），再标记已读，否则事件永远是空的
        local payload = syncPayload(doc)
        markRead(doc)
        replyTo(EV.SYNC_RESULT, payload)
    end)
end

local function HandleVisit(eventType, eventData)
    local connection = eventData["Connection"] and eventData["Connection"]:GetPtr("Connection") or nil
    local body = bodyOf(eventData)
    local uid = connection and connectionUid(connection) or (type(body) == "table" and body.__uid or nil)
    local replyTo = MakeReply(connection)
    local targetUid = tostring(body.uid or "")
    if not uid or targetUid == "" then return end
    LoadDoc(uid, function(mine)
        if not mine.friends[targetUid] then
            replyTo(EV.VISIT_RESULT, { ok = false, msg = "不是好友" })
            return
        end
        LoadDoc(targetUid, function(theirs)
            replyTo(EV.VISIT_RESULT, {
                ok = true,
                snapshot = FarmStore.Snapshot(theirs, now()),
                friendship = (mine.friends[targetUid] or {}).friendship or 0,
            })
        end)
    end)
end

local function HandleOp(eventType, eventData)
    local connection = eventData["Connection"] and eventData["Connection"]:GetPtr("Connection") or nil
    local body = bodyOf(eventData)
    local uid = connection and connectionUid(connection) or (type(body) == "table" and body.__uid or nil)
    local replyTo = MakeReply(connection)
    if not uid then return end
    local op = tostring(body.op or "")
    local ts = now()

    LoadDoc(uid, function(mine)
        local function fail(msg)
            replyTo(EV.OP_RESULT, { ok = false, msg = msg })
        end

        if op == "plant" then
            local ok, err = FarmStore.Plant(mine, tonumber(body.index) or 0, tostring(body.crop or ""), ts)
            if not ok then return fail(err) end
            SaveDoc(mine, function(saved)
                replyTo(EV.OP_RESULT, { ok = saved, msg = saved and "种下了" or "保存失败",
                    seeds = mine.seeds, plots = FarmStore.Snapshot(mine, ts).plots })
            end)

        elseif op == "harvest" then
            local ok, got = FarmStore.Harvest(mine, tonumber(body.index) or 0, ts)
            if not ok then return fail(got) end
            SaveDoc(mine, function(saved)
                replyTo(EV.OP_RESULT, { ok = saved, msg = saved and ("收获 ×" .. tostring(got)) or "保存失败",
                    fruits = mine.fruits, plots = FarmStore.Snapshot(mine, ts).plots })
            end)

        elseif op == "water" or op == "steal" then
            local targetUid = tostring(body.uid or "")
            if targetUid == "" then return fail("缺少目标") end
            LoadDoc(targetUid, function(theirs)
                local visitor = { uid = uid, name = mine.name }
                local ok, err, ev
                if op == "water" then
                    ok, err, ev = FarmStore.Water(theirs, tonumber(body.index) or 0, ts, visitor)
                else
                    ok, err, ev = FarmStore.Steal(theirs, tonumber(body.index) or 0, ts, visitor)
                end
                if not ok then return fail(err) end
                -- 互相的友好度：双方各 +1（按天封顶由客户端记录，这里只累加）
                local rel = mine.friends[targetUid]
                if rel then rel.friendship = (rel.friendship or 0) + 1 end
                local back = theirs.friends[uid]
                if back then back.friendship = (back.friendship or 0) + 1 end
                SaveDoc(theirs, function()
                    SaveDoc(mine, function()
                        replyTo(EV.OP_RESULT, {
                            ok = true,
                            msg = (op == "water" and "浇水成功（-15 分钟）" or "偷菜成功"),
                            snapshot = FarmStore.Snapshot(theirs, ts),
                        })
                    end)
                end)
            end)

        else
            fail("未知操作")
        end
    end)
end

local function HandleFriendSearch(eventType, eventData)
    local connection = eventData["Connection"] and eventData["Connection"]:GetPtr("Connection") or nil
    local body = bodyOf(eventData)
    local uid = connection and connectionUid(connection) or (type(body) == "table" and body.__uid or nil)
    local replyTo = MakeReply(connection)
    local query = tostring(body.query or "")
    if not uid or query == "" then return end
    -- 搜索范围：当前在线玩家的缓存 + 自己已知好友（正式上线可换成服务端侧索引）
    local found = {}
    local byCode = tostring(query):upper():gsub("%s", "")
    local hitUid = codeIndex_[byCode]
    if hitUid and hitUid ~= uid then
        local doc = store_[hitUid]
        if doc then
            found[#found + 1] = { uid = hitUid, name = doc.name or hitUid, code = doc.code }
        end
    end
    -- 好友码没命中时，再按 uid / 名字前缀搜在线缓存
    if #found == 0 then
        for otherUid, doc in pairs(store_) do
            if otherUid ~= uid and FarmStore.MatchQuery(doc, query) then
                found[#found + 1] = { uid = otherUid, name = doc.name or otherUid, code = doc.code }
            end
        end
    end
    replyTo(EV.FRIEND_RESULT, { ok = true, kind = "search", list = found })
end

local function HandleFriendRequest(eventType, eventData)
    local connection = eventData["Connection"] and eventData["Connection"]:GetPtr("Connection") or nil
    local body = bodyOf(eventData)
    local uid = connection and connectionUid(connection) or (type(body) == "table" and body.__uid or nil)
    local replyTo = MakeReply(connection)
    local targetUid = tostring(body.uid or "")
    if not uid or targetUid == "" then return end
    LoadDoc(uid, function(mine)
        LoadDoc(targetUid, function(theirs)
            local ok, msg = FarmStore.RequestFriend(mine, theirs, now())
            SaveDoc(mine); SaveDoc(theirs)
            replyTo(EV.FRIEND_RESULT, { ok = ok, kind = "request", msg = msg })
        end)
    end)
end

local function HandleFriendAccept(eventType, eventData)
    local connection = eventData["Connection"] and eventData["Connection"]:GetPtr("Connection") or nil
    local body = bodyOf(eventData)
    local uid = connection and connectionUid(connection) or (type(body) == "table" and body.__uid or nil)
    local replyTo = MakeReply(connection)
    local fromUid = tostring(body.uid or "")
    if not uid or fromUid == "" then return end
    LoadDoc(uid, function(mine)
        LoadDoc(fromUid, function(theirs)
            local ok, msg = FarmStore.AcceptFriend(mine, theirs, now())
            SaveDoc(mine); SaveDoc(theirs)
            replyTo(EV.FRIEND_RESULT, { ok = ok, kind = "accept", msg = msg })
        end)
    end)
end

local function HandleFriendRemove(eventType, eventData)
    local connection = eventData["Connection"] and eventData["Connection"]:GetPtr("Connection") or nil
    local body = bodyOf(eventData)
    local uid = connection and connectionUid(connection) or (type(body) == "table" and body.__uid or nil)
    local replyTo = MakeReply(connection)
    local targetUid = tostring(body.uid or "")
    if not uid or targetUid == "" then return end
    LoadDoc(uid, function(mine)
        LoadDoc(targetUid, function(theirs)
            FarmStore.RemoveFriend(mine, targetUid, now())
            FarmStore.RemoveFriend(theirs, uid, now())
            SaveDoc(mine); SaveDoc(theirs)
            replyTo(EV.FRIEND_RESULT, { ok = true, kind = "remove", msg = "已删除好友" })
        end)
    end)
end

local function HandleClientDisconnected(eventType, eventData)
    local connection = eventData:GetPtr("Connection", "Connection")
    if connection then connUid_[tostring(connection)] = nil end
end

-- ---------------------------------------------------------------- 纯逻辑入口
-- 不依赖引擎的 Connection：客户端假传输 / 本机联调 / 回归测试都走这里。
-- body 里用 __uid 指定调用者身份，回包通过 replyFn(eventName, payload) 同步返回。
local HANDLERS = nil

---@param uid string 调用者 uid
---@param eventName string FarmShared.EVENTS 里的事件名
---@param body table 载荷
---@param replyFn fun(eventName:string, payload:table)
function FarmServer.Dispatch(uid, eventName, body, replyFn)
    if not HANDLERS then
        HANDLERS = {
            [EV.SYNC] = HandleSync,
            [EV.VISIT] = HandleVisit,
            [EV.OP] = HandleOp,
            [EV.FRIEND_SEARCH] = HandleFriendSearch,
            [EV.FRIEND_REQUEST] = HandleFriendRequest,
            [EV.FRIEND_ACCEPT] = HandleFriendAccept,
            [EV.FRIEND_REMOVE] = HandleFriendRemove,
        }
    end
    local handler = HANDLERS[eventName]
    if not handler then
        if replyFn then replyFn(eventName, { ok = false, msg = "未知请求" }) end
        return
    end
    body = body or {}
    body.__uid = tostring(uid)
    local encoded = FarmShared.Encode(body) or "{}"
    local fakeData = { ["Data"] = { GetString = function() return encoded end } }
    pendingReply_ = replyFn
    local ok, err = pcall(handler, "", fakeData)
    pendingReply_ = nil
    if not ok and replyFn then
        replyFn(eventName, { ok = false, msg = "服务端异常：" .. tostring(err) })
    end
end

-- ---------------------------------------------------------------- 云变量轮询（配合客户端 FarmClient.EnableCloudTransport）
local REQ_KEY = "farm_req"
local RESP_KEY = "farm_resp"
local reqSeq_ = {}          -- uid -> 已处理的请求序号
local pollClock_ = 0

--- 取当前连接的玩家 uid 列表
local function OnlineUids()
    local list = {}
    for uid in pairs(connUid_) do
        local sUid = tostring(uid)
        if sUid ~= "" and not list[sUid] then list[sUid] = true end
    end
    if SERVER_PLAYER_AUTH_INFOS then
        for uid in pairs(SERVER_PLAYER_AUTH_INFOS) do
            local sUid = tostring(uid)
            if sUid ~= "" then list[sUid] = true end
        end
    end
    local out = {}
    for uid in pairs(list) do out[#out + 1] = uid end
    table.sort(out)
    return out
end

--- 处理一个玩家的请求：把 farm_req 里最新的序号跑一遍，结果写进 farm_resp
local function PollOne(uid)
    if not serverCloud then return end
    serverCloud:Get(uid, REQ_KEY, {
        ok = function(values)
            local raw = values and values[REQ_KEY] or nil
            local req = nil
            if type(raw) == "string" then req = FarmShared.Decode(raw)
            elseif type(raw) == "table" then req = raw end
            if type(req) ~= "table" or not req.seq then return end
            if (reqSeq_[uid] or 0) >= req.seq then return end
            reqSeq_[uid] = req.seq
            FarmServer.Dispatch(uid, req.event, req.payload or {}, function(resp)
                resp.seq = req.seq
                resp.event = RESP_KEY
                serverCloud:Set(uid, RESP_KEY, FarmShared.Encode({
                    seq = req.seq,
                    event = req.event,
                    payload = resp,
                }))
            end)
        end,
        error = function() end,
    })
end

--- 引擎 Update 驱动（服务端每 0.5 秒轮一次）
function FarmServer.Poll()
    pollClock_ = (pollClock_ or 0) + 1
    if pollClock_ % 300 == 0 then pcall(FlushDirty) end
    if not serverCloud then return end
    if pollClock_ % 30 ~= 0 then return end     -- 约每 0.5 秒
    for _, uid in ipairs(OnlineUids()) do
        PollOne(uid)
    end
end

-- ---------------------------------------------------------------- 生命周期
function FarmServer.Start()
    FarmShared.RegisterEvents()
    SubscribeToEvent("Update", "FarmServerOnUpdate")
    SubscribeToEvent(EV.SYNC, "FarmHandleSync")
    SubscribeToEvent(EV.VISIT, "FarmHandleVisit")
    SubscribeToEvent(EV.OP, "FarmHandleOp")
    SubscribeToEvent(EV.FRIEND_SEARCH, "FarmHandleFriendSearch")
    SubscribeToEvent(EV.FRIEND_REQUEST, "FarmHandleFriendRequest")
    SubscribeToEvent(EV.FRIEND_ACCEPT, "FarmHandleFriendAccept")
    SubscribeToEvent(EV.FRIEND_REMOVE, "FarmHandleFriendRemove")
    SubscribeToEvent("ClientDisconnected", "FarmHandleClientDisconnected")
    FarmShared.RegisterEvents()
    print("[Farm] 服务端已启动（serverCloud=" .. tostring(serverCloud ~= nil) .. "）")
end

function FarmServer.Stop()
    for uid, doc in pairs(store_) do
        SaveDoc(doc)
    end
end

-- 供 main.lua 以全局函数名订阅
function FarmHandleSync(t, d) HandleSync(t, d) end
function FarmHandleVisit(t, d) HandleVisit(t, d) end
function FarmHandleOp(t, d) HandleOp(t, d) end
function FarmHandleFriendSearch(t, d) HandleFriendSearch(t, d) end
function FarmHandleFriendRequest(t, d) HandleFriendRequest(t, d) end
function FarmHandleFriendAccept(t, d) HandleFriendAccept(t, d) end
function FarmHandleFriendRemove(t, d) HandleFriendRemove(t, d) end
function FarmHandleClientDisconnected(t, d) HandleClientDisconnected(t, d) end

-- 测试用：直接拿内存文档（不经过网络）
FarmServer._store = store_
FarmServer.Reset = function() store_ = {}; FarmServer._store = store_ end
FarmServer.LoadDoc = LoadDoc
FarmServer.SaveDoc = SaveDoc
FarmServer.SyncPayload = syncPayload

return FarmServer
