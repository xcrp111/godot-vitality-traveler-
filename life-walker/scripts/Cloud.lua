-- Cloud.lua — 云端排行榜（clientCloud）
-- 榜单一：无尽层数 / 关卡进度 / 农场收获 / 公会贡献
-- 只在客户端运行时可用；本地 headless / 无平台环境下自动降级为「不支持」，不抛错。

local Cloud = {}

Cloud.TOP_N = 20              -- 每次拉取前 N 名
local CACHE_TTL = 45          -- 榜单缓存秒数
local SUBMIT_INTERVAL = 30    -- 两次上传的最小间隔

Cloud._state = {}             -- boardId -> 榜单数据
Cloud._names = {}             -- userId -> 昵称缓存
Cloud._lastAt = nil
Cloud._lastSig = nil
Cloud._seq = 0
Cloud._avail = nil

-- ---------------------------------------------------------------- 榜单定义
local function FarmHarvest(d)
    local f = d and d.farm
    return math.floor((f and f.harvestCount) or 0)
end

local function GuildContribution(d)
    local g = d and d.guild
    return math.floor((g and g.exp) or 0)
end

Cloud.Boards = {
    {
        id = "endless", key = "lh_endless", name = "无尽层数", unit = "层",
        tip = "历史最高层数",
        value = function(d) return math.floor((d and d.endlessBest) or 0) end,
    },
    {
        id = "stage", key = "lh_stage", name = "关卡进度", unit = "关",
        tip = "已通关的最高关卡",
        value = function(d) return math.floor((d and d.stageCleared) or 0) end,
    },
    {
        id = "farm", key = "lh_farm", name = "农场收获", unit = "次",
        tip = "累计收获次数",
        value = FarmHarvest,
    },
    {
        id = "guild", key = "lh_guild", name = "公会贡献", unit = "点",
        tip = "个人累计公会经验",
        value = GuildContribution,
    },
}

function Cloud.Board(id)
    for _, b in ipairs(Cloud.Boards) do
        if b.id == id then return b end
    end
    return Cloud.Boards[1]
end

-- ---------------------------------------------------------------- 环境探测
--- 云变量在当前运行环境里是否可用
--- 注意：平台可能在运行一段时间后才注入 clientCloud，所以「不可用」不缓存，每次都重新探测
function Cloud.Available()
    if Cloud._avail then return true end
    local ok, res = pcall(function()
        local c = rawget(_G, "clientCloud")
        if c == nil then return false end
        local t = type(c)
        if t ~= "table" and t ~= "userdata" then return false end
        return c.BatchSet ~= nil and c.GetRankList ~= nil
    end)
    Cloud._avail = (ok and res) or false
    return Cloud._avail
end

--- 诊断串：界面上一行说明为什么用不了（方便真机排查）
function Cloud.Diag()
    local ok, text = pcall(function()
        local c = rawget(_G, "clientCloud")
        if c == nil then return "clientCloud 未注入（未登录 / 该环境不提供云变量）" end
        local t = type(c)
        if t ~= "table" and t ~= "userdata" then return "clientCloud 类型异常：" .. t end
        if c.BatchSet == nil then return "clientCloud 缺少 BatchSet（SDK 未就绪）" end
        if c.GetRankList == nil then return "clientCloud 缺少 GetRankList" end
        return "接口齐全"
    end)
    return ok and text or "探测失败"
end

function Cloud.UserId()
    if not Cloud.Available() then return nil end
    local ok, id = pcall(function() return clientCloud.userId end)
    if ok then return id end
    return nil
end
-- ---------------------------------------------------------------- 榜单状态
local function NewState()
    return {
        status = "idle",   -- idle / loading / ok / error
        list = {},
        at = nil,
        total = nil,
        myRank = nil,
        myScore = nil,
        err = nil,
        seq = 0,
    }
end

function Cloud.State(id)
    local st = Cloud._state[id]
    if not st then
        st = NewState()
        Cloud._state[id] = st
    end
    return st
end

function Cloud.Nickname(userId)
    return Cloud._names[userId]
end

--- 是否是本人
function Cloud.IsMe(userId)
    local me = Cloud.UserId()
    return me ~= nil and userId == me
end

-- ---------------------------------------------------------------- 昵称
local function FetchNicknames(userIds, onDone)
    if #userIds == 0 then
        if onDone then onDone() end
        return
    end
    local missing = {}
    for _, uid in ipairs(userIds) do
        if uid and not Cloud._names[uid] then
            missing[#missing + 1] = uid
        end
    end
    if #missing == 0 then
        if onDone then onDone() end
        return
    end
    local ok = pcall(function()
        GetUserNickname({
            userIds = missing,
            onSuccess = function(list)
                for _, info in ipairs(list or {}) do
                    if info and info.userId then
                        Cloud._names[info.userId] = info.nickname
                    end
                end
                if onDone then onDone() end
            end,
            onError = function()
                if onDone then onDone() end
            end,
        })
    end)
    if not ok and onDone then onDone() end
end

-- ---------------------------------------------------------------- 上传
--- 有变化才上传，且两次上传至少间隔 SUBMIT_INTERVAL 秒；失败静默（下次再试）
function Cloud.MaybeSubmit(data)
    if not data or not Cloud.Available() then return false end
    local now = os.time()
    if Cloud._lastAt and now - Cloud._lastAt < SUBMIT_INTERVAL then return false end

    local parts = {}
    for _, b in ipairs(Cloud.Boards) do
        parts[#parts + 1] = tostring(b.value(data) or 0)
    end
    local sig = table.concat(parts, ",")
    if sig == Cloud._lastSig then return false end

    local ok = pcall(function()
        local batch = clientCloud:BatchSet()
        for _, b in ipairs(Cloud.Boards) do
            batch:SetInt(b.key, b.value(data) or 0)
        end
        batch:Save("排行榜同步", {})
    end)
    if ok then
        Cloud._lastAt = now
        Cloud._lastSig = sig
    end
    return ok
end

-- ---------------------------------------------------------------- 拉取
--- 刷新某个榜单；缓存未过期且非强制时直接返回
function Cloud.Refresh(id, force)
    local board = Cloud.Board(id)
    local st = Cloud.State(board.id)
    if not Cloud.Available() then
        st.status = "unsupported"
        return false
    end
    local now = os.time()
    if not force and (st.status == "loading" or (st.at and now - st.at < CACHE_TTL)) then
        return true
    end

    Cloud._seq = Cloud._seq + 1
    local seq = Cloud._seq
    st.seq = seq
    st.status = "loading"
    st.err = nil

    local ok = pcall(function()
        clientCloud:GetRankList(board.key, 0, Cloud.TOP_N, {
            ok = function(rankList)
                if st.seq ~= seq then return end
                local list = {}
                for i, item in ipairs(rankList or {}) do
                    local uid = item.userId or item.player
                    local iscore = item.iscore or {}
                    list[i] = {
                        rank = i,
                        userId = uid,
                        score = iscore[board.key] or 0,
                        nickname = Cloud._names[uid],
                    }
                end
                st.list = list
                st.status = "ok"
                st.at = os.time()
                local ids = {}
                for _, e in ipairs(list) do
                    ids[#ids + 1] = e.userId
                end
                FetchNicknames(ids, function()
                    for _, e in ipairs(st.list) do
                        e.nickname = Cloud._names[e.userId]
                    end
                end)
            end,
            error = function(code, reason)
                if st.seq ~= seq then return end
                st.status = "error"
                st.err = reason or code or "请求失败"
            end,
        })
    end)
    if not ok then
        st.status = "error"
        st.err = "云变量不可用"
        return false
    end

    -- 我的排名 / 上榜总人数（失败不影响榜单本体）
    pcall(function()
        local me = clientCloud.userId
        if me then
            clientCloud:GetUserRank(me, board.key, {
                ok = function(rank, score)
                    if st.seq ~= seq then return end
                    st.myRank = rank
                    st.myScore = score
                end,
                error = function() end,
            })
        end
        clientCloud:GetRankTotal(board.key, {
            ok = function(total)
                if st.seq ~= seq then return end
                st.total = total
            end,
            error = function() end,
        })
    end)
    return true
end

--- 拉取 + 上传一次，进入排行榜界面时调用
function Cloud.Sync(data, id)
    Cloud.MaybeSubmit(data)
    Cloud.Refresh(id, false)
end

return Cloud
