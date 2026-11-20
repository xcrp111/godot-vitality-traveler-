-- RaidCloud.lua — 公会团本「共享血量池」（异步共斗）
--
-- 为什么这样做：clientCloud 只能写自己的云变量，没有共享可变对象。
-- 于是把「共享血量」定义成一个可计算量：
--     剩余血量 = BOSS_MAX - Σ(本周所有玩家上报的输出)
-- 每个玩家只上传自己的本周输出（iscores: lh_raid_dmg + 周标记 lh_raid_week），
-- 任何人拉一次排行榜就能得到同一个血量池，不需要服务器。
--
-- 无网络 / 未登录时 Available() = false，调用方退回本地单机团本，不报错。

local Config = require "Config"
local Cloud = require "Cloud"

local RaidCloud = {}

RaidCloud.KEY_DMG = "lh_raid_dmg"      -- 本周输出（整数，参与排序）
RaidCloud.KEY_WEEK = "lh_raid_week"    -- 周标记（整数：周一的 epoch 天数）
RaidCloud.KEY_SNAP = "lh_raid_snap"    -- 附带快照（昵称徽记 / 评级等，展示用）
RaidCloud.TOP_N = 100
RaidCloud.CACHE_TTL = 20
RaidCloud.SUBMIT_INTERVAL = 20

local state = {
    status = "idle",   -- idle / loading / ok / error
    at = nil,
    week = nil,
    dealt = 0,
    participants = 0,
    mine = 0,
    list = {},         -- { { userId, dmg, nickname }, ... } 本周有输出的人，按输出降序
    err = nil,
    seq = 0,
}

local lastSubmitAt = nil
local lastSubmitSig = nil

-- ---------------------------------------------------------------- 基础
--- 本周标记：以周一 00:00 为界（与公会周重置一致）
function RaidCloud.WeekTag()
    local t = os.time()
    local wd = tonumber(os.date("%w", t)) or 0     -- 0 = 周日
    local monday = t - ((wd + 6) % 7) * 86400
    return math.floor(monday / 86400)
end

--- 共享 Boss 的最大血量（= 第 1 关关底 Boss 血量，与团本出怪数值一致）
function RaidCloud.BossMax()
    local hp = Config.MonsterStats(1, 9, "boss")
    return math.max(1, math.floor(hp or 1))
end

function RaidCloud.Available()
    return Cloud.Available()
end

function RaidCloud.State()
    return state
end

--- 本地记录的本周已上报输出（离线也保留，联网后补传）
function RaidCloud.LocalDamage(data)
    local g = data and data.guild
    local rc = g and g.raidCloud
    local week = RaidCloud.WeekTag()
    if not rc or rc.week ~= week then return 0 end
    return math.floor(rc.dmg or 0)
end

--- 记一笔输出到存档（团本结算时调用），返回累计值
function RaidCloud.AddLocalDamage(data, dmg)
    if not data or not data.guild then return 0 end
    local g = data.guild
    local week = RaidCloud.WeekTag()
    if not g.raidCloud or g.raidCloud.week ~= week then
        g.raidCloud = { week = week, dmg = 0 }
    end
    g.raidCloud.dmg = math.floor((g.raidCloud.dmg or 0) + math.max(0, dmg or 0))
    return g.raidCloud.dmg
end

-- ---------------------------------------------------------------- 血量池
---@return table { available, bossMax, dealt, remaining, ratio, participants, mine, week }
function RaidCloud.Pool(data)
    local bossMax = RaidCloud.BossMax()
    local mine = RaidCloud.LocalDamage(data)
    local out = {
        available = RaidCloud.Available(),
        bossMax = bossMax,
        dealt = 0,
        remaining = bossMax,
        ratio = 0,
        participants = 0,
        mine = mine,
        week = RaidCloud.WeekTag(),
        status = state.status,
    }
    if out.available and state.status == "ok" and state.week == out.week then
        -- 云端已汇总（更大，可能含自己以外的玩家）；本地值兜住「刚打完还没上传」
        out.dealt = math.max(state.dealt, mine)
        out.participants = state.participants
        if mine > 0 and not state.list then out.participants = math.max(1, out.participants) end
    else
        out.dealt = mine
        if mine > 0 then out.participants = 1 end
    end
    out.remaining = math.max(0, bossMax - out.dealt)
    out.ratio = math.min(1, out.dealt / bossMax)
    return out
end

function RaidCloud.Defeated(data)
    local p = RaidCloud.Pool(data)
    return p.remaining <= 0 and p.dealt > 0
end

-- ---------------------------------------------------------------- 上传
--- 把「本周累计输出」推到云端（有变化 / 超过节流才发）
function RaidCloud.Submit(data, force)
    if not data or not RaidCloud.Available() then return false end
    local week = RaidCloud.WeekTag()
    local total = RaidCloud.LocalDamage(data)
    if total <= 0 then return false end
    local now = os.time()
    local sig = tostring(week) .. ":" .. tostring(total)

    if not force then
        if sig == lastSubmitSig then return false end
        if lastSubmitAt and now - lastSubmitAt < RaidCloud.SUBMIT_INTERVAL then return false end
    end

    local ok = pcall(function()
        local batch = clientCloud:BatchSet()
        batch:SetInt(RaidCloud.KEY_DMG, total)
        batch:SetInt(RaidCloud.KEY_WEEK, week)
        batch:Set(RaidCloud.KEY_SNAP, {
            week = week,
            lv = (data.guild and data.guild.level) or 1,
            grade = (data.guild and data.guild.raid and data.guild.raid.grade) or "",
        })
        batch:Save("团本贡献上报", {})
    end)
    if ok then
        lastSubmitAt = now
        lastSubmitSig = sig
    end
    return ok
end

-- ---------------------------------------------------------------- 拉取
function RaidCloud.Refresh(force)
    if not RaidCloud.Available() then
        state.status = "unsupported"
        return false
    end
    local now = os.time()
    if not force and (state.status == "loading" or (state.at and now - state.at < RaidCloud.CACHE_TTL)) then
        return true
    end

    state.seq = state.seq + 1
    local seq = state.seq
    local week = RaidCloud.WeekTag()
    state.status = "loading"
    state.err = nil
    state.week = week

    local ok = pcall(function()
        clientCloud:GetRankList(RaidCloud.KEY_DMG, 0, RaidCloud.TOP_N, {
            ok = function(rankList)
                if state.seq ~= seq then return end
                local dealt, list = 0, {}
                for _, item in ipairs(rankList or {}) do
                    local is = item.iscore or {}
                    local d = is[RaidCloud.KEY_DMG]
                    local w = is[RaidCloud.KEY_WEEK]
                    if type(d) == "number" and d > 0 and w == week then
                        dealt = dealt + d
                        list[#list + 1] = {
                            userId = item.userId,
                            dmg = d,
                            nickname = Cloud.Nickname(item.userId),
                        }
                    end
                end
                table.sort(list, function(a, b) return (a.dmg or 0) > (b.dmg or 0) end)
                state.dealt = dealt
                state.list = list
                state.participants = #list
                state.status = "ok"
                state.at = os.time()
                local ids = {}
                for _, e in ipairs(list) do ids[#ids + 1] = e.userId end
                Cloud.FetchNicknames(ids, function()
                    for _, e in ipairs(state.list) do
                        e.nickname = Cloud.Nickname(e.userId)
                    end
                end)
            end,
            error = function(code, reason)
                if state.seq ~= seq then return end
                state.status = "error"
                state.err = reason or code or "请求失败"
            end,
        }, RaidCloud.KEY_WEEK, RaidCloud.KEY_SNAP)
    end)
    if not ok then
        state.status = "error"
        state.err = "云变量不可用"
        return false
    end
    return true
end

--- 进入团本页时调用：先把本地上报补上，再拉一次
function RaidCloud.Sync(data)
    RaidCloud.Submit(data)
    RaidCloud.Refresh(false)
end

return RaidCloud
