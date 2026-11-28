-- GuildStore.lua — 公会联机的纯逻辑（双端共用，不碰网络 / 不碰 UI）
--
-- 设计依据（TapTap 制造周报 2026/3/16-3/22 的存档架构建议）：
--   · 按业务领域切槽：meta / members(分片) / raid / log
--   · 大集合分片，单片控制在 ~11KB（云端单条约 13KB 上限）
--   · 数值资源（贡献币、血量池）单独存数值槽，便于原子增减
--   · 反序列化失败只影响单个槽，不影响核心数据
--
-- 服务端：GuildServer 负责读写槽位；客户端：GuildClient 只拿快照与发请求。

local GuildStore = {}

GuildStore.MAX_MEMBERS = 30
GuildStore.MEMBER_CHUNK = 40          -- 每片成员上限（一条 ~120B，40 人仍在安全区）
GuildStore.MAX_APPLIES = 20
GuildStore.LOG_MAX = 30
GuildStore.NAME_MIN, GuildStore.NAME_MAX = 2, 12

local function nowStr()
    return os.date("%Y-%m-%d %H:%M")
end

local function clampInt(v, lo, hi, def)
    v = tonumber(v)
    if not v then return def end
    v = math.floor(v)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

-- ---------------------------------------------------------------- 校验
function GuildStore.ValidateName(name)
    name = tostring(name or "")
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    local n = utf8 and utf8.len and (utf8.len(name) or 0) or #name
    if n < GuildStore.NAME_MIN then return false, "公会名太短（至少 2 个字）" end
    if n > GuildStore.NAME_MAX then return false, "公会名太长（最多 12 个字）" end
    return true, name
end

function GuildStore.RoleRank(role)
    if role == "owner" then return 3 end
    if role == "admin" then return 2 end
    return 1
end

-- ---------------------------------------------------------------- 构建
---@param gid string 公会 ID（服务端生成，建议 = 会长短码 + 时间戳）
function GuildStore.NewGuild(gid, name, ownerUid, ownerName)
    local ok, fixed = GuildStore.ValidateName(name)
    if not ok then return nil, fixed end
    return {
        v = 1,
        id = tostring(gid),
        name = fixed,
        level = 1,
        exp = 0,
        notice = "",
        ownerUid = tostring(ownerUid),
        created = nowStr(),
        members = {
            {
                uid = tostring(ownerUid),
                name = tostring(ownerName or "会长"),
                role = "owner",
                joinAt = nowStr(),
                coins = 0,
                raidDmg = 0,
            },
        },
        applies = {},
        raid = { week = 0, hpMax = 0, dealt = 0, top = {} },
        log = { { at = nowStr(), text = "公会创建" } },
    }
end

--- 修复/补全（服务端读档后必过一遍；坏字段只影响自己）
function GuildStore.Ensure(g)
    if type(g) ~= "table" then return nil end
    g.v = 1
    g.id = tostring(g.id or "")
    g.name = tostring(g.name or "未命名公会")
    g.level = clampInt(g.level, 1, 5, 1)
    g.exp = clampInt(g.exp, 0, 1e9, 0)
    g.notice = tostring(g.notice or "")
    g.ownerUid = tostring(g.ownerUid or "")
    g.created = tostring(g.created or "")

    if type(g.members) ~= "table" then g.members = {} end
    local clean = {}
    for _, m in ipairs(g.members) do
        if type(m) == "table" and m.uid then
            clean[#clean + 1] = {
                uid = tostring(m.uid),
                name = tostring(m.name or "行者"),
                role = (m.role == "owner" or m.role == "admin") and m.role or "member",
                joinAt = tostring(m.joinAt or ""),
                coins = clampInt(m.coins, 0, 1e9, 0),
                raidDmg = clampInt(m.raidDmg, 0, 1e12, 0),
            }
        end
    end
    g.members = clean

    if type(g.applies) ~= "table" then g.applies = {} end
    local ap = {}
    for _, a in ipairs(g.applies) do
        if type(a) == "table" and a.uid then
            ap[#ap + 1] = { uid = tostring(a.uid), name = tostring(a.name or "行者"), at = tostring(a.at or "") }
        end
    end
    g.applies = ap

    if type(g.raid) ~= "table" then g.raid = { week = 0, hpMax = 0, dealt = 0, top = {} } end
    g.raid.week = clampInt(g.raid.week, 0, 1e9, 0)
    g.raid.hpMax = clampInt(g.raid.hpMax, 0, 1e12, 0)
    g.raid.dealt = clampInt(g.raid.dealt, 0, 1e12, 0)
    if type(g.raid.top) ~= "table" then g.raid.top = {} end

    if type(g.log) ~= "table" then g.log = {} end
    return g
end

-- ---------------------------------------------------------------- 成员
function GuildStore.FindMember(g, uid)
    uid = tostring(uid or "")
    for i, m in ipairs(g.members or {}) do
        if m.uid == uid then return m, i end
    end
    return nil, nil
end

function GuildStore.IsFull(g)
    return #(g.members or {}) >= GuildStore.MAX_MEMBERS
end

function GuildStore.AddMember(g, uid, name, role)
    uid = tostring(uid or "")
    if uid == "" then return false, "缺少玩家 ID" end
    if GuildStore.FindMember(g, uid) then return false, "已经在公会里了" end
    if GuildStore.IsFull(g) then return false, "公会人数已满（" .. GuildStore.MAX_MEMBERS .. "）" end
    g.members[#g.members + 1] = {
        uid = uid,
        name = tostring(name or "行者"),
        role = role or "member",
        joinAt = nowStr(),
        coins = 0,
        raidDmg = 0,
    }
    return true, "已加入公会"
end

function GuildStore.RemoveMember(g, uid)
    local _, idx = GuildStore.FindMember(g, uid)
    if not idx then return false, "不在公会里" end
    table.remove(g.members, idx)
    return true, "已退出公会"
end

function GuildStore.MemberCount(g)
    return #(g.members or {})
end

--- 权限：会长 > 管理员 > 成员
function GuildStore.CanManage(g, uid)
    local m = GuildStore.FindMember(g, uid)
    if not m then return false end
    return GuildStore.RoleRank(m.role) >= 2
end

-- ---------------------------------------------------------------- 申请
function GuildStore.AddApply(g, uid, name)
    uid = tostring(uid or "")
    if GuildStore.FindMember(g, uid) then return false, "你已经是本公会成员" end
    for _, a in ipairs(g.applies) do
        if a.uid == uid then return false, "已经申请过了，等待审批" end
    end
    if #g.applies >= GuildStore.MAX_APPLIES then
        table.remove(g.applies, 1)   -- 队列满了丢最旧的，避免无限增长
    end
    g.applies[#g.applies + 1] = { uid = uid, name = tostring(name or "行者"), at = nowStr() }
    return true, "申请已提交，等待会长审批"
end

function GuildStore.ApproveApply(g, targetUid)
    for i, a in ipairs(g.applies) do
        if a.uid == tostring(targetUid) then
            local ok, msg = GuildStore.AddMember(g, a.uid, a.name)
            if not ok then return false, msg end
            table.remove(g.applies, i)
            GuildStore.AddLog(g, a.name .. " 加入公会")
            return true, "已同意 " .. a.name .. " 的申请"
        end
    end
    return false, "没有这条申请"
end

function GuildStore.RejectApply(g, targetUid)
    for i, a in ipairs(g.applies) do
        if a.uid == tostring(targetUid) then
            table.remove(g.applies, i)
            return true, "已拒绝"
        end
    end
    return false, "没有这条申请"
end

-- ---------------------------------------------------------------- 贡献 / 等级
--- 数值资源：成员贡献累计 + 公会经验（公会总经验 = 个人 × 成员数，与单机版口径一致）
function GuildStore.AddContribution(g, uid, coins)
    local m = GuildStore.FindMember(g, uid)
    if not m then return false, "不在公会里" end
    coins = clampInt(coins, 0, 1e9, 0)
    if coins <= 0 then return false, "没有可记的贡献" end
    m.coins = m.coins + coins
    g.exp = g.exp + coins * math.max(1, GuildStore.MemberCount(g))
    return true, "贡献已记录"
end

function GuildStore.TotalExp(g)
    return (g.exp or 0)
end

function GuildStore.LevelNeed(level)
    -- 与单机版阈值一致：2/3/4/5 级
    return ({ 0, 2000, 8000, 20000, 40000 })[math.min(5, math.max(1, (level or 1) + 1))] or 0
end

function GuildStore.LevelUp(g)
    if g.level >= 5 then return false, "公会已满级" end
    local need = GuildStore.LevelNeed(g.level)
    if GuildStore.TotalExp(g) < need then
        return false, "公会经验不足：还差 " .. (need - GuildStore.TotalExp(g))
    end
    g.level = g.level + 1
    GuildStore.AddLog(g, "公会升到 Lv." .. g.level)
    return true, "公会升到 Lv." .. g.level
end

-- ---------------------------------------------------------------- 团本血量池（数值槽）
function GuildStore.RollWeek(g, week, hpMax)
    week = clampInt(week, 0, 1e9, 0)
    hpMax = clampInt(hpMax, 0, 1e12, 0)
    if g.raid.week ~= week then
        g.raid.week = week
        g.raid.hpMax = hpMax
        g.raid.dealt = 0
        g.raid.top = {}
        for _, m in ipairs(g.members) do m.raidDmg = 0 end
    elseif g.raid.hpMax <= 0 and hpMax > 0 then
        g.raid.hpMax = hpMax
    end
    return g.raid
end

--- 上报一次团本输出：服务端做上限校验（单次不超过血量池的 120%）
function GuildStore.RaidReport(g, uid, dmg, week, hpMax)
    local m = GuildStore.FindMember(g, uid)
    if not m then return false, "不在公会里" end
    local raid = GuildStore.RollWeek(g, week, hpMax)
    dmg = clampInt(dmg, 0, 1e12, 0)
    if dmg <= 0 then return false, "没有可上报的输出" end
    local cap = math.max(1, math.floor((raid.hpMax or 0) * 1.2))
    if dmg > cap then dmg = cap end          -- 粗校验：单人一次不可能打超过上限
    m.raidDmg = (m.raidDmg or 0) + dmg
    raid.dealt = (raid.dealt or 0) + dmg
    raid.top = GuildStore.RaidTop(g)
    return true, dmg, raid
end

--- 输出排行（最多 5 人）
function GuildStore.RaidTop(g)
    local list = {}
    for _, m in ipairs(g.members or {}) do
        if (m.raidDmg or 0) > 0 then
            list[#list + 1] = { uid = m.uid, name = m.name, dmg = m.raidDmg }
        end
    end
    table.sort(list, function(a, b) return a.dmg > b.dmg end)
    local out = {}
    for i = 1, math.min(5, #list) do out[i] = list[i] end
    return out
end

function GuildStore.RaidRemain(g)
    local raid = g.raid or {}
    return math.max(0, (raid.hpMax or 0) - (raid.dealt or 0))
end

-- ---------------------------------------------------------------- 日志
function GuildStore.AddLog(g, text)
    if type(g.log) ~= "table" then g.log = {} end
    g.log[#g.log + 1] = { at = nowStr(), text = tostring(text or "") }
    while #g.log > GuildStore.LOG_MAX do table.remove(g.log, 1) end
end

-- ---------------------------------------------------------------- 分槽 / 合槽（服务端持久化用）
--- 把公会拆成多个存档槽：meta / members（分片）/ raid / log
function GuildStore.ToSlots(g)
    g = GuildStore.Ensure(g)
    if not g then return nil end
    local members = {}
    local chunk = {}
    for _, m in ipairs(g.members) do
        chunk[#chunk + 1] = m
        if #chunk >= GuildStore.MEMBER_CHUNK then
            members[#members + 1] = chunk
            chunk = {}
        end
    end
    if #chunk > 0 then members[#members + 1] = chunk end
    return {
        meta = {
            v = g.v, id = g.id, name = g.name, level = g.level, exp = g.exp,
            notice = g.notice, ownerUid = g.ownerUid, created = g.created,
            memberChunks = #members, memberCount = #g.members,
        },
        members = members,
        raid = { week = g.raid.week, hpMax = g.raid.hpMax, dealt = g.raid.dealt, top = g.raid.top },
        log = g.log,
        applies = g.applies,
    }
end

--- 从槽恢复；任一槽坏了只丢那一块（周报：容错加载）
---@param slots table { meta, members, raid, log, applies }
---@return table guild, table issues
function GuildStore.FromSlots(slots)
    local issues = {}
    slots = slots or {}
    local meta = type(slots.meta) == "table" and slots.meta or nil
    if not meta then
        issues[#issues + 1] = "meta 缺失"
        return nil, issues
    end
    local g = {
        v = 1,
        id = tostring(meta.id or ""),
        name = tostring(meta.name or "未命名公会"),
        level = meta.level,
        exp = meta.exp,
        notice = meta.notice,
        ownerUid = meta.ownerUid,
        created = meta.created,
        members = {},
        applies = type(slots.applies) == "table" and slots.applies or {},
        raid = type(slots.raid) == "table" and slots.raid or { week = 0, hpMax = 0, dealt = 0, top = {} },
        log = type(slots.log) == "table" and slots.log or {},
    }
    if type(slots.members) ~= "table" then
        issues[#issues + 1] = "members 缺失"
    else
        for i, chunk in ipairs(slots.members) do
            if type(chunk) == "table" then
                for _, m in ipairs(chunk) do g.members[#g.members + 1] = m end
            else
                issues[#issues + 1] = "members 第 " .. i .. " 片损坏"
            end
        end
    end
    return GuildStore.Ensure(g), issues
end

return GuildStore
