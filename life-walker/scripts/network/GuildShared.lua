-- GuildShared.lua — 公会联机：事件名 / 存档槽 key / 编解码（双端共用）

local NetCore = require "network.NetCore"

local GuildShared = {}

-- 事件名（约定 `模块.动作`）
GuildShared.EVENTS = {
    CREATE  = "guild.create",
    SYNC    = "guild.sync",
    APPLY   = "guild.apply",
    APPROVE = "guild.approve",
    REJECT  = "guild.reject",
    LEAVE   = "guild.leave",
    DONATE  = "guild.donate",
    RAID    = "guild.raid",
    LEVELUP = "guild.levelup",
    SEARCH  = "guild.search",
    NOTIFY  = "guild.notify",
}

-- 存档槽（周报建议：按业务切槽，大集合分片）
GuildShared.SLOT = {
    META        = "guild_meta",          -- 名称/等级/经验/公告/会长/分片数
    MEMBER_FMT  = "guild_members_%d",    -- 成员分片，每片 GuildStore.MEMBER_CHUNK 人
    RAID        = "guild_raid",          -- 团本血量池（数值，单独槽）
    LOG         = "guild_log",           -- 战报（环形保留）
    APPLIES     = "guild_applies",       -- 入会申请队列
    MEMBER_INFO = "guild_member_info",   -- 玩家 → 所属公会（存在玩家自己的 uid 下）
}

GuildShared.SLOT_MAX_BYTES = 11 * 1024   -- 单槽软上限（云端单条约 13KB）
GuildShared.CHUNK_SAFETY   = 40          -- 与 GuildStore.MEMBER_CHUNK 对齐

function GuildShared.MemberSlot(i)
    return string.format(GuildShared.SLOT.MEMBER_FMT, i)
end

function GuildShared.Encode(t)
    return NetCore.Encode(t)
end

function GuildShared.Decode(s)
    return NetCore.Decode(s)
end

--- 估算一个槽占多少字节（编码后），用于分片告警
function GuildShared.SizeOf(value)
    local s = GuildShared.Encode(value)
    return s and #s or 0
end

--- 双端注册远程事件（服务端走 NetCore.ServerStart，客户端走 network:RegisterRemoteEvent）
function GuildShared.RegisterEvents()
    NetCore.ServerStart(GuildShared.EVENTS)
end

return GuildShared
