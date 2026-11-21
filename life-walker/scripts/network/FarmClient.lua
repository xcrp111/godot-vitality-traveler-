-- FarmClient.lua — 农场联机：客户端同步层
--
-- 职责：
--   · 连上服务器后，把自己的农场文档 / 好友 / 事件同步下来
--   · 所有改动（种/收/浇水/偷菜/好友）都发给服务端裁决，客户端只做展示
--   · 离线时 online=false，UI 层可以退回本地模拟（Friend.lua）
--
-- 传输层是抽象出来的（FarmClient.SetTransport），默认走引擎 connection；
-- 这样本地联调 / 回归测试可以塞一个假传输，直接打到 FarmServer.Dispatch。

local FarmShared = require "network.FarmShared"

local FarmClient = {}

local EV = FarmShared.EVENTS

FarmClient.online = false          -- 是否连上服务器并同步过
FarmClient.uid = nil               -- 自己的 uid
FarmClient.doc = nil               -- 自己文档（服务端下发）
FarmClient.remote = {}             -- 好友 uid -> 快照
FarmClient.friends = {}            -- { {uid,name,friendship}, ... }
FarmClient.events = {}             -- 未读事件
FarmClient.requestsIn = {}         -- 收到的好友请求
FarmClient.requestsOut = {}        -- 我发出的请求
FarmClient.lastError = nil
FarmClient.searchResult = nil      -- 最近一次搜索结果

local transport_ = nil             -- { send(eventName, payload) }
local listeners_ = {}              -- eventName -> { fn, ... }

-- ---------------------------------------------------------------- 传输
--- 设置传输层；t = { send = function(eventName, payload) end }
function FarmClient.SetTransport(t)
    transport_ = t
end

--- 默认传输：走引擎 connection
function FarmClient.UseConnection(connection)
    if not connection then transport_ = nil; return end
    transport_ = {
        send = function(eventName, payload)
            -- 引擎要求第三参是 VariantMap（直接传字符串会抛 argument #2 is string）
            local okSend, err = pcall(function()
                connection:SendRemoteEvent(eventName, true, FarmShared.MakePayload(payload))
            end)
            if not okSend then
                FarmClient.lastError = tostring(err)
                print("[Farm] 发送失败 " .. tostring(eventName) .. ": " .. tostring(err))
            end
        end,
    }
end

local function send(eventName, payload)
    if not transport_ then return false end
    transport_.send(eventName, payload or {})
    return true
end

--- 收到网络包（由 main 的事件订阅转进来）
function FarmClient.OnPacket(eventName, payload)
    if type(payload) == "string" then payload = FarmShared.Decode(payload) or {} end
    if type(payload) ~= "table" then payload = {} end

    if eventName == EV.SYNC_RESULT then
        FarmClient.uid = payload.uid
        FarmClient.code = payload.code
        FarmClient.doc = payload
        FarmClient.friends = payload.friends or {}
        FarmClient.events = payload.events or {}
        FarmClient.requestsIn = payload.incoming or {}
        FarmClient.requestsOut = payload.outgoing or {}
        FarmClient.online = true
    elseif eventName == EV.VISIT_RESULT then
        if payload.ok and payload.snapshot then
            FarmClient.remote[payload.snapshot.uid] = payload.snapshot
        end
    elseif eventName == EV.OP_RESULT then
        if payload.ok then
            if payload.plots and FarmClient.doc then FarmClient.doc.plots = payload.plots end
            if payload.seeds and FarmClient.doc then FarmClient.doc.seeds = payload.seeds end
            if payload.fruits and FarmClient.doc then FarmClient.doc.fruits = payload.fruits end
        end
        if payload.snapshot then
            FarmClient.remote[payload.snapshot.uid] = payload.snapshot
        end
    elseif eventName == EV.FRIEND_RESULT then
        if payload.kind == "search" then FarmClient.searchResult = payload.list or {} end
    end

    for _, fn in ipairs(listeners_[eventName] or {}) do
        pcall(fn, payload)
    end
end

--- 订阅某类回包
function FarmClient.On(eventName, fn)
    listeners_[eventName] = listeners_[eventName] or {}
    table.insert(listeners_[eventName], fn)
end

-- ---------------------------------------------------------------- 云变量轮询传输（不依赖远程事件）
-- 远程事件在当前环境下不通（客户端发得出去、服务端收不到），
-- 这里改用「客户端写自己的 farm_req，服务端轮询并写回 farm_resp」的方式，
-- 完全走云变量，和排行榜用的是同一套通道。
FarmClient.REQ_KEY = "farm_req"
FarmClient.RESP_KEY = "farm_resp"
FarmClient.lastRespSeq = 0

local function cloudWrite(key, value)
    if not (clientCloud and clientCloud.Set) then return false end
    local okSet = pcall(function() clientCloud:Set(key, value) end)
    return okSet
end

local function cloudRead(key, cb)
    if not (clientCloud and clientCloud.Get) then
        cb(nil)
        return
    end
    pcall(function()
        clientCloud:Get(key, {
            ok = function(values)
                local raw = values and values[key] or nil
                local data = nil
                if type(raw) == "string" then data = FarmShared.Decode(raw)
                elseif type(raw) == "table" then data = raw end
                cb(data)
            end,
            error = function() cb(nil) end,
        })
    end)
end

--- 打开云变量传输（替换远程事件发送）
function FarmClient.EnableCloudTransport()
    FarmClient.cloudMode = true
    FarmClient.SetTransport({
        send = function(eventName, payload)
            FarmClient.seq = (FarmClient.seq or 0) + 1
            local req = {
                seq = FarmClient.seq,
                event = eventName,
                payload = payload,
                at = os.time(),
            }
            if not cloudWrite(FarmClient.REQ_KEY, FarmShared.Encode(req)) then
                FarmClient.lastError = "clientCloud 写入失败"
            end
        end,
    })
end

--- 轮询服务端回包（每帧调，内部自己控频）
function FarmClient.Poll(now)
    if not FarmClient.cloudMode then return end
    if now - (FarmClient._lastPoll or 0) < 0.5 then return end
    FarmClient._lastPoll = now
    cloudRead(FarmClient.RESP_KEY, function(resp)
        if type(resp) ~= "table" or not resp.seq then return end
        if resp.seq <= (FarmClient.lastRespSeq or 0) then return end
        FarmClient.lastRespSeq = resp.seq
        FarmClient.OnPacket(resp.event or "", resp.payload or {})
    end)
end

-- ---------------------------------------------------------------- 引擎事件回调
--- 引擎通过全局函数名订阅：收到 VariantMap 后解出 Data 交给 OnPacket
function FarmClientOnPacket(eventType, eventData)
    local okRun, err = pcall(function()
        local event = tostring(eventType)
        local payload = FarmShared.ReadPayload(eventData)
        FarmClient.OnPacket(event, payload)
    end)
    if not okRun then print("[FarmNet] 处理回包出错: " .. tostring(err)) end
end

-- ---------------------------------------------------------------- 注册远程事件
function FarmClient.RegisterEvents()
    if FarmClient._registered then return true end
    FarmClient._registered = true
    print("[FarmNet] 客户端开始注册农场事件（network=" .. tostring(network ~= nil) .. "）")
    local okReg, errReg = pcall(FarmShared.RegisterEvents)
    if not okReg then print("[FarmNet] 注册远程事件异常: " .. tostring(errReg)) end
    for _, name in pairs({ EV.SYNC_RESULT, EV.VISIT_RESULT, EV.OP_RESULT, EV.FRIEND_RESULT }) do
        local okSub, errSub = pcall(function() SubscribeToEvent(name, "FarmClientOnPacket") end)
        if okSub then
            print("[FarmNet] 已订阅回包 " .. tostring(name))
        else
            print("[FarmNet] 订阅失败 " .. tostring(name) .. ": " .. tostring(errSub))
        end
    end
    return true
end

-- 兼容别名（早期 main 里调的是 Subscribe）
FarmClient.Subscribe = FarmClient.RegisterEvents

--- 读服务端自检信息（服务端把状态写进了本人的云变量）
function FarmClient.ReadServerDiag(cb)
    if not (clientCloud and clientCloud.Get) then
        if cb then cb(nil, "clientCloud 不可用") end
        return
    end
    local okGet, err = pcall(function()
        clientCloud:Get("farm_diag", {
            ok = function(values)
                local raw = values and values["farm_diag"] or nil
                local data = nil
                if type(raw) == "string" then data = FarmShared.Decode(raw)
                elseif type(raw) == "table" then data = raw end
                FarmClient.serverDiag = data
                if cb then cb(data) end
            end,
            error = function(code, reason)
                FarmClient.serverDiagErr = tostring(code) .. " " .. tostring(reason)
                if cb then cb(nil, FarmClient.serverDiagErr) end
            end,
        })
    end)
    if not okGet then FarmClient.serverDiagErr = tostring(err) end
end

-- ---------------------------------------------------------------- API
function FarmClient.Sync(name)
    return send(EV.SYNC, { name = name or "" })
end

function FarmClient.Visit(uid)
    return send(EV.VISIT, { uid = tostring(uid) })
end

function FarmClient.Water(uid, index)
    return send(EV.OP, { op = "water", uid = tostring(uid), index = index })
end

function FarmClient.Steal(uid, index)
    return send(EV.OP, { op = "steal", uid = tostring(uid), index = index })
end

function FarmClient.Plant(index, crop)
    return send(EV.OP, { op = "plant", index = index, crop = crop })
end

function FarmClient.Harvest(index)
    return send(EV.OP, { op = "harvest", index = index })
end

function FarmClient.Search(query)
    return send(EV.FRIEND_SEARCH, { query = tostring(query or "") })
end

function FarmClient.RequestFriend(uid)
    return send(EV.FRIEND_REQUEST, { uid = tostring(uid) })
end

function FarmClient.AcceptFriend(uid)
    return send(EV.FRIEND_ACCEPT, { uid = tostring(uid) })
end

function FarmClient.RemoveFriend(uid)
    return send(EV.FRIEND_REMOVE, { uid = tostring(uid) })
end

--- 好友快照（没访问过返回 nil）
function FarmClient.SnapshotOf(uid)
    return FarmClient.remote[tostring(uid)]
end

--- 离线 / 在线状态文案（UI 右上角小标签用）
function FarmClient.StatusText()
    if FarmClient.online then
        return "已连服务器 · " .. tostring(FarmClient.uid or "?")
    end
    return "离线（本地模拟）"
end

--- 断开（掉线 / 回大厅）
function FarmClient.Disconnect()
    FarmClient.online = false
    FarmClient.doc = nil
    FarmClient.remote = {}
    FarmClient.friends = {}
    FarmClient.events = {}
    transport_ = nil
end

return FarmClient
