-- GuildClient.lua — 公会联机客户端
--
-- 只做三件事：1) 把服务端快照缓存成 UI 能直接用的结构 2) 发请求 3) 离线优雅降级
-- 真正的权威数据在 GuildServer + serverCloud，客户端不改数值。

local NetCore = require "network.NetCore"
local GuildShared = require "network.GuildShared"

local GuildClient = {}

GuildClient.online = false       -- 是否连上服务器
GuildClient.synced = false       -- 是否已经同步到一份公会数据
GuildClient.guild = nil          -- 服务端快照（nil = 没有公会）
GuildClient.lastError = nil
GuildClient.lastSyncAt = nil
GuildClient.nickname = nil
GuildClient.status = "idle"      -- idle / syncing / ready / error / offline
GuildClient.search = nil         -- 最近一次搜索结果
GuildClient.busy = false         -- 有请求在飞

local function now()
    return os.time()
end

local function fail(msg, code)
    GuildClient.lastError = msg
    GuildClient.busy = false
    return false, msg, code
end

-- ---------------------------------------------------------------- 连接
function GuildClient.UseConnection(connection)
    if not connection then
        GuildClient.online = false
        GuildClient.status = "offline"
        GuildClient.synced = false
        return
    end
    NetCore.UseConnection(connection)
    GuildClient.online = true
    GuildClient.status = "idle"
end

--- 进服后设一次身份（服务端会用同一个 uid 做归属）
function GuildClient.SetIdentity(uid, nickname)
    NetCore.SetIdentity(uid, nickname)
    GuildClient.uid = NetCore.uid
    GuildClient.nickname = nickname
end

function GuildClient.Available()
    return GuildClient.online and NetCore.online
end

--- NetCore 是否离线（UI 显示用）
function GuildClient.StatusText()
    if not GuildClient.online then return "○ 离线（本地模拟）" end
    if GuildClient.status == "syncing" then return "◎ 正在同步公会…" end
    if GuildClient.status == "error" then return "◍ 公会同步失败：" .. tostring(GuildClient.lastError or "") end
    if GuildClient.guild then
        return "● " .. GuildClient.guild.name .. "  Lv." .. tostring(GuildClient.guild.level or 1)
    end
    return "● 已连服务器（还没有公会）"
end

-- ---------------------------------------------------------------- 请求封装
local function call(event, body, cb)
    if not GuildClient.Available() then
        fail("当前是离线模式，联机公会不可用", "offline")
        if cb then cb({ ok = false, code = "offline", msg = GuildClient.lastError }) end
        return false
    end
    GuildClient.busy = true
    NetCore.Request(event, body or {}, function(resp)
        GuildClient.busy = false
        resp = resp or {}
        if resp.guild ~= nil then
            GuildClient.guild = resp.guild
            GuildClient.synced = true
            GuildClient.status = "ready"
            GuildClient.lastSyncAt = now()
        end
        if not resp.ok then
            GuildClient.lastError = resp.msg or resp.code or "请求失败"
            if GuildClient.status ~= "ready" then GuildClient.status = "error" end
        else
            GuildClient.lastError = nil
        end
        if cb then cb(resp) end
    end)
    return true
end

-- ---------------------------------------------------------------- 业务接口
function GuildClient.Sync(cb)
    if not GuildClient.Available() then
        GuildClient.status = "offline"
        if cb then cb({ ok = false, code = "offline" }) end
        return false
    end
    GuildClient.status = "syncing"
    return call(GuildShared.EVENTS.SYNC, {}, cb)
end

function GuildClient.Create(name, nickname, cb)
    return call(GuildShared.EVENTS.CREATE, { name = name, nickname = nickname }, cb)
end

function GuildClient.Apply(gid, nickname, cb)
    return call(GuildShared.EVENTS.APPLY, { gid = gid, nickname = nickname }, cb)
end

function GuildClient.Approve(targetUid, cb)
    return call(GuildShared.EVENTS.APPROVE, { target = targetUid }, cb)
end

function GuildClient.Reject(targetUid, cb)
    return call(GuildShared.EVENTS.REJECT, { target = targetUid }, cb)
end

function GuildClient.Leave(nickname, cb)
    GuildClient.guild = nil
    GuildClient.synced = false
    return call(GuildShared.EVENTS.LEAVE, { nickname = nickname }, cb)
end

function GuildClient.Donate(coins, cb)
    return call(GuildShared.EVENTS.DONATE, { coins = coins }, cb)
end

function GuildClient.LevelUp(cb)
    return call(GuildShared.EVENTS.LEVELUP, {}, cb)
end

--- 团本上报：服务端会做上限校验并更新共享血量池
function GuildClient.RaidReport(dmg, week, hpMax, cb)
    return call(GuildShared.EVENTS.RAID, { dmg = dmg, week = week, hpMax = hpMax }, cb)
end

function GuildClient.Search(gid, cb)
    return call(GuildShared.EVENTS.SEARCH, { gid = gid }, function(resp)
        GuildClient.search = resp and resp.guild or nil
        if cb then cb(resp) end
    end)
end

-- ---------------------------------------------------------------- UI 便利
--- 服务端血量池（没连上或没有公会时返回 nil，调用方回退到本地 RaidCloud）
function GuildClient.RaidPool()
    local g = GuildClient.guild
    if not g or type(g.raid) ~= "table" then return nil end
    local raid = g.raid
    if (raid.hpMax or 0) <= 0 then return nil end
    return {
        bossMax = raid.hpMax,
        dealt = raid.dealt or 0,
        remain = raid.remain or 0,
        ratio = math.min(1, (raid.dealt or 0) / math.max(1, raid.hpMax)),
        top = raid.top or {},
        myDamage = g.myRaidDmg or 0,
        participants = #(raid.top or {}),
        week = raid.week or 0,
    }
end

function GuildClient.MyRole()
    return GuildClient.guild and GuildClient.guild.myRole or nil
end

function GuildClient.CanManage()
    local role = GuildClient.MyRole()
    return role == "owner" or role == "admin"
end

function GuildClient.ResetForTest()
    GuildClient.online = false
    GuildClient.synced = false
    GuildClient.guild = nil
    GuildClient.status = "idle"
    GuildClient.lastError = nil
    GuildClient.search = nil
    GuildClient.busy = false
end

return GuildClient
