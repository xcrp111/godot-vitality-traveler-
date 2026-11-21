-- NetCore.lua — 联机公共底座（农场 / 公会共用）
--
-- 目标：把「玩家身份、连接状态、请求-响应、云端读写、模块路由」这些每个联机玩法都要
-- 重复一遍的东西收成一套，新模块（比如公会）只需要注册自己的事件和 UI。
--
-- 双端共用同一个文件：
--   · 客户端：NetCore.UseConnection(conn) 后有网络出口
--   · 服务端：NetCore.ServerStart() 后注册路由
--   本地联调 / 回归测试：NetCore.SetTransport(fake)，把包直接打到 NetCore.ServerDispatch
--
-- 事件命名约定：`模块.动作`（小写），例如 farm.sync / guild.apply
-- 回包约定：{ ok = boolean, code = string|nil, msg = string|nil, ...业务字段 }

local NetCore = {}

-- ---------------------------------------------------------------- 状态
NetCore.online = false          -- 客户端是否已连上服务器
NetCore.uid = nil               -- 自己的玩家 ID（字符串）
NetCore.nickname = nil          -- 自己的昵称
NetCore.seq = 0                 -- 请求序号
NetCore.pending = {}            -- 请求序号 -> 回调
NetCore.lastError = nil

local transport_ = nil          -- 客户端出口 { send(event, payload) }
local clientRoutes_ = {}        -- 客户端事件 -> { fn, ... }
local serverRoutes_ = {}        -- 服务端事件 -> fn(uid, body, reply)
local serverStarted_ = false
local identityHooks_ = {}       -- 昵称/身份变化的订阅者

-- ---------------------------------------------------------------- 编解码
function NetCore.Encode(t)
    if not cjson then return nil end
    local ok, out = pcall(cjson.encode, t)
    return ok and out or nil
end

function NetCore.Decode(s)
    if not cjson or type(s) ~= "string" or s == "" then return nil end
    local ok, out = pcall(cjson.decode, s)
    return ok and (type(out) == "table" and out or nil) or nil
end

-- ---------------------------------------------------------------- 身份
--- 玩家 ID 转成可展示/可分享的短码（服务端也可用同样的规则做搜索索引）
function NetCore.PlayerCode(uid)
    uid = tostring(uid or "")
    if uid == "" then return "------" end
    -- 只保留字母数字，取后 6 位，不足补 0
    local clean = uid:gsub("[^%w]", "")
    if #clean <= 6 then return clean:upper() end
    return clean:sub(-6):upper()
end

function NetCore.SetIdentity(uid, nickname)
    NetCore.uid = uid and tostring(uid) or nil
    if nickname and nickname ~= "" then NetCore.nickname = nickname end
    for _, fn in ipairs(identityHooks_) do pcall(fn, NetCore.uid, NetCore.nickname) end
end

--- 订阅身份变化（UI 显示昵称/ID 用）
function NetCore.OnIdentity(fn)
    table.insert(identityHooks_, fn)
end

-- ---------------------------------------------------------------- 客户端：连接与收发
--- 设置传输层；t = { send(event, payload) }；传 nil 表示离线
function NetCore.SetTransport(t)
    transport_ = t
    NetCore.online = t ~= nil
end

function NetCore.UseConnection(connection)
    if not connection then
        NetCore.SetTransport(nil)
        NetCore.uid = nil
        return
    end
    NetCore.SetTransport({
        send = function(event, payload)
            connection:SendRemoteEvent(event, true, NetCore.Encode(payload) or "{}")
        end,
    })
end

--- 发请求；带 seq，回包用 NetCore.ClientDispatch 配对
---@param event string 事件名
---@param body table 载荷
---@param cb fun(resp:table)|nil 回包回调
---@return integer|nil seq
function NetCore.Request(event, body, cb)
    if not transport_ then
        NetCore.lastError = "offline"
        if cb then cb({ ok = false, code = "offline", msg = "当前是离线模式" }) end
        return nil
    end
    NetCore.seq = NetCore.seq + 1
    local seq = NetCore.seq
    body = body or {}
    body.seq = seq
    if cb then NetCore.pending[seq] = cb end
    local ok, err = pcall(transport_.send, event, body)
    if not ok then
        NetCore.pending[seq] = nil
        if cb then cb({ ok = false, code = "send_failed", msg = tostring(err) }) end
        return nil
    end
    return seq
end

--- 客户端收到包：配对的回包走 pending 回调，其余广播给订阅者
function NetCore.ClientDispatch(event, payload)
    if type(payload) == "string" then payload = NetCore.Decode(payload) or {} end
    if type(payload) ~= "table" then payload = {} end
    local seq = payload.seq
    if seq and NetCore.pending[seq] then
        local cb = NetCore.pending[seq]
        NetCore.pending[seq] = nil
        pcall(cb, payload)
    end
    for _, fn in ipairs(clientRoutes_[event] or {}) do pcall(fn, payload) end
end

--- 订阅服务端主动推送（非请求回包）
function NetCore.On(event, fn)
    clientRoutes_[event] = clientRoutes_[event] or {}
    table.insert(clientRoutes_[event], fn)
end

-- ---------------------------------------------------------------- 服务端：路由与云端读写
--- 注册服务端路由：handler(uid, body, reply)，reply(table) 把结果送回发起者
function NetCore.ServerRoute(event, handler)
    serverRoutes_[event] = handler
end

--- 服务端把事件表注册给引擎（network:RegisterRemoteEvent）
function NetCore.ServerStart(events)
    if not serverStarted_ then
        serverStarted_ = true
        if network and events then
            for _, name in pairs(events) do
                pcall(function() network:RegisterRemoteEvent(name) end)
            end
        end
    end
end

--- 服务端纯逻辑分发（不依赖引擎 Connection；客户端假传输 / 测试都走这里）
function NetCore.ServerDispatch(uid, event, body, replyFn)
    body = body or {}
    -- 回包统一补上 seq，客户端才能按请求配对（未知路由 / 异常也要带上）
    local function reply(resp)
        if not replyFn then return end
        resp = resp or {}
        if resp.seq == nil and body.seq ~= nil then resp.seq = body.seq end
        replyFn(resp)
    end
    local handler = serverRoutes_[event]
    if not handler then
        reply({ ok = false, code = "no_route", msg = "未知请求：" .. tostring(event) })
        return
    end
    local ok, err = pcall(handler, tostring(uid or body.__uid or ""), body, reply)
    if not ok then
        reply({ ok = false, code = "server_error", msg = tostring(err) })
    end
end

--- 引擎事件包装：把 eventData 里的 Connection + Data 解析成 (uid, body, reply)
function NetCore.WrapServerEvent(event, handler)
    return function(eventType, eventData)
        local connection = eventData["Connection"] and eventData["Connection"]:GetPtr("Connection") or nil
        local uid = nil
        if connection and connection.identity and connection.identity["user_id"] then
            uid = tostring(connection.identity["user_id"]:GetInt64())
        end
        local raw = eventData["Data"]
        local body = {}
        if raw then
            local okStr, s = pcall(function() return raw:GetString() end)
            if okStr then body = NetCore.Decode(s) or {} end
        end
        local function reply(resp)
            if connection then
                connection:SendRemoteEvent(event, true, NetCore.Encode(resp) or "{}")
            end
        end
        NetCore.ServerDispatch(uid, event, body, reply)
    end
end

--- 服务端云端 KV：读
---@param uid string
---@param key string
---@param cb fun(value:table|nil)
function NetCore.CloudGet(uid, key, cb)
    if not serverCloud then
        cb(nil)
        return
    end
    serverCloud:Get(uid, key, {
        ok = function(values)
            local raw = values and values[key] or nil
            local val = nil
            if type(raw) == "string" then val = NetCore.Decode(raw)
            elseif type(raw) == "table" then val = raw end
            cb(val)
        end,
        error = function(code, reason)
            print(string.format("[Net] CloudGet 失败 uid=%s key=%s %s %s",
                tostring(uid), tostring(key), tostring(code), tostring(reason)))
            cb(nil)
        end,
    })
end

--- 服务端云端 KV：写
function NetCore.CloudSet(uid, key, value, cb)
    if not serverCloud then
        if cb then cb(false) end
        return
    end
    serverCloud:Set(uid, key, NetCore.Encode(value), {
        ok = function() if cb then cb(true) end end,
        error = function(code, reason)
            print(string.format("[Net] CloudSet 失败 uid=%s key=%s %s %s",
                tostring(uid), tostring(key), tostring(code), tostring(reason)))
            if cb then cb(false) end
        end,
    })
end

-- ---------------------------------------------------------------- 状态文案（UI 用）
function NetCore.StatusText()
    if NetCore.online then
        local who = NetCore.nickname or ""
        if who == "" then who = "ID " .. tostring(NetCore.uid or "?") end
        return "● 已连服务器　" .. who
    end
    return "○ 离线（本地模拟）"
end

function NetCore.Disconnect()
    NetCore.online = false
    NetCore.uid = nil
    NetCore.pending = {}
    transport_ = nil
end

return NetCore
