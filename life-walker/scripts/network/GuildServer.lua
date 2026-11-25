-- GuildServer.lua — 公会服务端（权威数据 + 分槽持久化）
--
-- 存储模型（照周报的存档架构建议）：
--   guild_meta         名称/等级/经验/公告/会长/成员分片数
--   guild_members_<i>  成员分片（每片 ≤ GuildStore.MEMBER_CHUNK 人）
--   guild_raid         团本血量池（数值单独槽）
--   guild_log          战报（环形保留最近 30 条）
--   guild_applies      入会申请
--   guild_member_info  玩家 → 所属公会（写在玩家自己的 uid 下）
--
-- 每个槽都独立读、独立写、独立 pcall；某一槽坏掉只影响那一块，不会整档报废。
-- 没有 serverCloud（单机 / 本地联调）时自动退化为进程内内存表，接口不变。

local NetCore = require "network.NetCore"
local GuildShared = require "network.GuildShared"
local GuildStore = require "GuildStore"

local GuildServer = {}

GuildServer.ready = false
local mem = {}          -- "gid/slot" -> value（无 serverCloud 或云端读失败时的兜底）
local stats = { loads = 0, saves = 0, slotErrors = 0, oversize = 0 }

local function SK(gid, slot)
    return tostring(gid) .. "/" .. slot
end

-- ---------------------------------------------------------------- 槽读写
local function ReadSlot(gid, slot, cb)
    local k = SK(gid, slot)
    if not serverCloud then
        cb(mem[k])
        return
    end
    local done = false
    NetCore.CloudGet(gid, slot, function(v)
        if done then return end
        done = true
        if v == nil then
            cb(mem[k])          -- 云端没有 → 用内存兜底（首次创建 / 云端失败）
        else
            mem[k] = v
            cb(v)
        end
    end)
end

local function WriteSlot(gid, slot, value, cb)
    local k = SK(gid, slot)
    mem[k] = value
    local size = GuildShared.SizeOf(value)
    if size > GuildShared.SLOT_MAX_BYTES then
        stats.oversize = stats.oversize + 1
        print(string.format("[Guild] 槽偏大 %s %d bytes（软上限 %d）", slot, size,
            GuildShared.SLOT_MAX_BYTES))
    end
    if not serverCloud then
        if cb then cb(true) end
        return
    end
    NetCore.CloudSet(gid, slot, value, function(ok)
        if not ok then
            stats.slotErrors = stats.slotErrors + 1
            print("[Guild] 写槽失败：" .. tostring(slot))
        end
        if cb then cb(ok) end
    end)
end

-- ---------------------------------------------------------------- 玩家 → 公会
local function ReadMemberInfo(uid, cb)
    ReadSlot(uid, GuildShared.SLOT.MEMBER_INFO, function(v)
        cb(type(v) == "table" and v or nil)
    end)
end

local function WriteMemberInfo(uid, info, cb)
    WriteSlot(uid, GuildShared.SLOT.MEMBER_INFO, info, cb)
end

-- ---------------------------------------------------------------- 读整份公会
local function LoadGuild(gid, cb)
    stats.loads = stats.loads + 1
    ReadSlot(gid, GuildShared.SLOT.META, function(meta)
        if type(meta) ~= "table" then
            cb(nil, "guild_not_found")
            return
        end
        local chunks = math.max(0, math.min(50, math.floor(tonumber(meta.memberChunks) or 0)))
        local slots = {
            meta = meta,
            members = {},
            raid = nil,
            log = nil,
            applies = nil,
        }
        local pending = 3 + chunks
        local issues = {}
        local function step()
            pending = pending - 1
            if pending > 0 then return end
            local g, loadIssues = GuildStore.FromSlots(slots)
            for _, s in ipairs(loadIssues or {}) do issues[#issues + 1] = s end
            for _, s in ipairs(issues) do
                print("[Guild] 载入告警：" .. s)
            end
            cb(g, nil, issues)
        end
        ReadSlot(gid, GuildShared.SLOT.RAID, function(v) slots.raid = v; step() end)
        ReadSlot(gid, GuildShared.SLOT.LOG, function(v) slots.log = v; step() end)
        ReadSlot(gid, GuildShared.SLOT.APPLIES, function(v) slots.applies = v; step() end)
        for i = 1, chunks do
            ReadSlot(gid, GuildShared.MemberSlot(i), function(v)
                slots.members[i] = v
                step()
            end)
        end
    end)
end

-- ---------------------------------------------------------------- 写整份公会
local function SaveGuild(g, cb)
    if not g then
        if cb then cb(false) end
        return
    end
    stats.saves = stats.saves + 1
    local slots = GuildStore.ToSlots(g)
    if not slots then
        if cb then cb(false) end
        return
    end
    local pending = 4 + #slots.members
    local okAll = true
    local function step(ok)
        if ok == false then okAll = false end
        pending = pending - 1
        if pending > 0 then return end
        if cb then cb(okAll) end
    end
    -- 成员 / 团本 / 日志 / 申请先落，meta 最后落（meta 是分片指针）
    for i, chunk in ipairs(slots.members) do
        WriteSlot(g.id, GuildShared.MemberSlot(i), chunk, step)
    end
    WriteSlot(g.id, GuildShared.SLOT.RAID, slots.raid, step)
    WriteSlot(g.id, GuildShared.SLOT.LOG, slots.log, step)
    WriteSlot(g.id, GuildShared.SLOT.APPLIES, slots.applies, step)
    WriteSlot(g.id, GuildShared.SLOT.META, slots.meta, step)
end

-- ---------------------------------------------------------------- 客户端快照
local function Snapshot(g, uid)
    if not g then return nil end
    local me = GuildStore.FindMember(g, uid)
    local members = {}
    for _, m in ipairs(g.members) do
        members[#members + 1] = { uid = m.uid, name = m.name, role = m.role, coins = m.coins, raidDmg = m.raidDmg }
    end
    local applies = {}
    if me and GuildStore.RoleRank(me.role) >= 2 then
        for _, a in ipairs(g.applies) do
            applies[#applies + 1] = { uid = a.uid, name = a.name, at = a.at }
        end
    end
    local raid = g.raid or {}
    return {
        id = g.id,
        name = g.name,
        level = g.level,
        exp = g.exp,
        notice = g.notice,
        ownerUid = g.ownerUid,
        memberCount = #g.members,
        maxMembers = GuildStore.MAX_MEMBERS,
        myRole = me and me.role or nil,
        myCoins = me and me.coins or 0,
        myRaidDmg = me and me.raidDmg or 0,
        members = members,
        applies = applies,
        log = g.log,
        raid = {
            week = raid.week or 0,
            hpMax = raid.hpMax or 0,
            dealt = raid.dealt or 0,
            remain = GuildStore.RaidRemain(g),
            top = raid.top or {},
        },
    }
end

-- ---------------------------------------------------------------- 路由
local function replyGuild(reply, g, uid, extra)
    local snap = Snapshot(g, uid)
    local resp = { ok = snap ~= nil, guild = snap, serverBoot = GuildServer.bootAt or 0 }
    if extra then for k, v in pairs(extra) do resp[k] = v end end
    reply(resp)
end

GuildServer.bootAt = nil

--- 安全注册：单条路由出错不影响其它路由和服务端启动
local function route(event, handler)
    local ok, err = pcall(NetCore.ServerRoute, event, handler)
    if not ok then
        print("[Guild] 注册路由失败 " .. tostring(event) .. ": " .. tostring(err))
    end
end

function GuildServer.Start()
    if GuildServer.ready then return end
    GuildServer.ready = true
    GuildServer.bootAt = os.time()
    local okReg, errReg = pcall(GuildShared.RegisterEvents)
    if not okReg then print("[Guild] 事件注册失败: " .. tostring(errReg)) end

    local E = GuildShared.EVENTS

    NetCore.ServerRoute(E.CREATE, function(uid, body, reply)
        if uid == "" then
            reply({ ok = false, code = "no_uid", msg = "缺少玩家身份" })
            return
        end
        ReadMemberInfo(uid, function(info)
            if info and info.gid then
                reply({ ok = false, code = "already", msg = "你已经在一个公会里了" })
                return
            end
            local okName, name = GuildStore.ValidateName(body.name)
            if not okName then
                reply({ ok = false, code = "bad_name", msg = name })
                return
            end
            local gid = NetCore.PlayerCode(uid) .. "-" .. tostring(os.time())
            local g = GuildStore.NewGuild(gid, name, uid, body.nickname or ("行者" .. NetCore.PlayerCode(uid)))
            WriteMemberInfo(uid, { gid = gid, role = "owner" }, function()
                SaveGuild(g, function(saved)
                    replyGuild(reply, g, uid, { saved = saved })
                end)
            end)
        end)
    end)

    NetCore.ServerRoute(E.SYNC, function(uid, body, reply)
        ReadMemberInfo(uid, function(info)
            if not info or not info.gid then
                reply({ ok = true, guild = nil, msg = "还没有公会" })
                return
            end
            LoadGuild(info.gid, function(g, err)
                if not g then
                    reply({ ok = false, code = err or "load_failed", msg = "公会数据读取失败" })
                    return
                end
                replyGuild(reply, g, uid)
            end)
        end)
    end)

    NetCore.ServerRoute(E.APPLY, function(uid, body, reply)
        local gid = tostring(body.gid or "")
        if gid == "" then
            reply({ ok = false, code = "bad_gid", msg = "缺少公会 ID" })
            return
        end
        ReadMemberInfo(uid, function(info)
            if info and info.gid then
                reply({ ok = false, code = "already", msg = "你已经在一个公会里了" })
                return
            end
            LoadGuild(gid, function(g, err)
                if not g then
                    reply({ ok = false, code = err or "guild_not_found", msg = "找不到这个公会" })
                    return
                end
                local ok, msg = GuildStore.AddApply(g, uid, body.nickname)
                if not ok then
                    reply({ ok = false, code = "apply_failed", msg = msg })
                    return
                end
                SaveGuild(g, function()
                    reply({ ok = true, msg = msg })
                end)
            end)
        end)
    end)

    NetCore.ServerRoute(E.APPROVE, function(uid, body, reply)
        ReadMemberInfo(uid, function(info)
            if not info or not info.gid then
                reply({ ok = false, code = "no_guild", msg = "你还没有公会" })
                return
            end
            LoadGuild(info.gid, function(g)
                if not g then
                    reply({ ok = false, code = "guild_not_found", msg = "公会数据读取失败" })
                    return
                end
                if not GuildStore.CanManage(g, uid) then
                    reply({ ok = false, code = "no_permission", msg = "只有会长/管理员可以审批" })
                    return
                end
                local ok, msg = GuildStore.ApproveApply(g, body.target)
                if not ok then
                    reply({ ok = false, code = "approve_failed", msg = msg })
                    return
                end
                WriteMemberInfo(tostring(body.target), { gid = g.id }, function()
                    SaveGuild(g, function()
                        replyGuild(reply, g, uid, { msg = msg })
                    end)
                end)
            end)
        end)
    end)

    NetCore.ServerRoute(E.REJECT, function(uid, body, reply)
        ReadMemberInfo(uid, function(info)
            if not info or not info.gid then
                reply({ ok = false, code = "no_guild", msg = "你还没有公会" })
                return
            end
            LoadGuild(info.gid, function(g)
                if not g then
                    reply({ ok = false, code = "guild_not_found", msg = "公会数据读取失败" })
                    return
                end
                if not GuildStore.CanManage(g, uid) then
                    reply({ ok = false, code = "no_permission", msg = "没有审批权限" })
                    return
                end
                local ok, msg = GuildStore.RejectApply(g, body.target)
                if not ok then
                    reply({ ok = false, code = "reject_failed", msg = msg })
                    return
                end
                SaveGuild(g, function()
                    replyGuild(reply, g, uid, { msg = msg })
                end)
            end)
        end)
    end)

    NetCore.ServerRoute(E.LEAVE, function(uid, body, reply)
        ReadMemberInfo(uid, function(info)
            if not info or not info.gid then
                reply({ ok = false, code = "no_guild", msg = "你还没有公会" })
                return
            end
            LoadGuild(info.gid, function(g)
                if not g then
                    reply({ ok = false, code = "guild_not_found", msg = "公会数据读取失败" })
                    return
                end
                GuildStore.RemoveMember(g, uid)
                GuildStore.AddLog(g, (body.nickname or "成员") .. " 离开了公会")
                -- 会长退出：自动移交给第一个成员
                if g.ownerUid == uid and #g.members > 0 then
                    g.members[1].role = "owner"
                    g.ownerUid = g.members[1].uid
                    GuildStore.AddLog(g, g.members[1].name .. " 成为新会长")
                end
                WriteMemberInfo(uid, {}, function()
                    SaveGuild(g, function()
                        reply({ ok = true, msg = "已退出公会" })
                    end)
                end)
            end)
        end)
    end)

    NetCore.ServerRoute(E.DONATE, function(uid, body, reply)
        ReadMemberInfo(uid, function(info)
            if not info or not info.gid then
                reply({ ok = false, code = "no_guild", msg = "你还没有公会" })
                return
            end
            LoadGuild(info.gid, function(g)
                if not g then
                    reply({ ok = false, code = "guild_not_found", msg = "公会数据读取失败" })
                    return
                end
                local coins = math.floor(tonumber(body.coins) or 0)
                local ok, msg = GuildStore.AddContribution(g, uid, coins)
                if not ok then
                    reply({ ok = false, code = "donate_failed", msg = msg })
                    return
                end
                SaveGuild(g, function()
                    replyGuild(reply, g, uid, { msg = "贡献 +" .. coins })
                end)
            end)
        end)
    end)

    NetCore.ServerRoute(E.RAID, function(uid, body, reply)
        ReadMemberInfo(uid, function(info)
            if not info or not info.gid then
                reply({ ok = false, code = "no_guild", msg = "你还没有公会" })
                return
            end
            LoadGuild(info.gid, function(g)
                if not g then
                    reply({ ok = false, code = "guild_not_found", msg = "公会数据读取失败" })
                    return
                end
                local ok, applied = GuildStore.RaidReport(g, uid,
                    math.floor(tonumber(body.dmg) or 0),
                    math.floor(tonumber(body.week) or 0),
                    math.floor(tonumber(body.hpMax) or 0))
                if not ok then
                    reply({ ok = false, code = "raid_failed", msg = applied })
                    return
                end
                SaveGuild(g, function()
                    replyGuild(reply, g, uid, { applied = applied })
                end)
            end)
        end)
    end)

    NetCore.ServerRoute(E.LEVELUP, function(uid, body, reply)
        ReadMemberInfo(uid, function(info)
            if not info or not info.gid then
                reply({ ok = false, code = "no_guild", msg = "你还没有公会" })
                return
            end
            LoadGuild(info.gid, function(g)
                if not g then
                    reply({ ok = false, code = "guild_not_found", msg = "公会数据读取失败" })
                    return
                end
                if not GuildStore.CanManage(g, uid) then
                    reply({ ok = false, code = "no_permission", msg = "没有升级权限" })
                    return
                end
                local ok, msg = GuildStore.LevelUp(g)
                if not ok then
                    reply({ ok = false, code = "levelup_failed", msg = msg })
                    return
                end
                SaveGuild(g, function()
                    replyGuild(reply, g, uid, { msg = msg })
                end)
            end)
        end)
    end)

    NetCore.ServerRoute(E.SEARCH, function(uid, body, reply)
        local gid = tostring(body.gid or "")
        if gid == "" then
            reply({ ok = false, code = "bad_gid", msg = "请输入公会 ID" })
            return
        end
        LoadGuild(gid, function(g)
            if not g then
                reply({ ok = false, code = "guild_not_found", msg = "找不到这个公会" })
                return
            end
            reply({
                ok = true,
                guild = {
                    id = g.id, name = g.name, level = g.level,
                    memberCount = #g.members, ownerUid = g.ownerUid, notice = g.notice,
                },
            })
        end)
    end)

    print("[Guild] 服务端已注册 " .. tostring(#GuildServer.Routes()) .. " 条路由")
end

function GuildServer.Routes()
    local list = {}
    for _, name in pairs(GuildShared.EVENTS) do list[#list + 1] = name end
    return list
end

--- 测试/诊断用
function GuildServer.Stats()
    return stats
end

function GuildServer.MemorySnapshot()
    return mem
end

--- 清空内存兜底（单测用）
function GuildServer.ResetForTest()
    mem = {}
    stats = { loads = 0, saves = 0, slotErrors = 0, oversize = 0 }
end

return GuildServer
