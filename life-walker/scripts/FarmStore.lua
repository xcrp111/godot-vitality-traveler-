-- FarmStore.lua — 农场联机：服务端数据层（纯逻辑，不依赖引擎）
--
-- 设计目标：这一层同时跑在服务端（权威校验）和客户端（本地预演/单机回退），
-- 因此不 require 任何引擎或 UI 模块，只处理表结构与规则。
--
-- 数据按玩家 uid 存一份「农场文档」：
--   doc = {
--     uid = "string",
--     name = "玩家名",
--     updatedAt = 秒,
--     landCount = 4..9,
--     plots = { [1..9] = { crop=, plantedAt=, waterBonus=, waterAt=, stolen=, stolenBy= } },
--     seeds = { [cropId] = n },
--     fruits = { [cropId] = n },
--     rep = 累计声望,
--     events = { { id=, kind="water"|"steal"|"visit", from=, fromName=, plot=, at=, read=false } },
--     friends = { [uid] = { since=, friendship= } },
--     requests = { incoming = {[uid]={name=,at=}}, outgoing = {[uid]={at=}} },
--   }

local FarmStore = {}

FarmStore.PROTECT = 2 * 3600      -- 成熟后保护期
FarmStore.WATER_CD = 2 * 3600     -- 同一块地浇水冷却
FarmStore.WATER_SEC = 15 * 60     -- 每次浇水减少 15 分钟
FarmStore.EVENT_CAP = 50          -- 每份文档最多保留的事件数

-- 作物表（与 Farm.Crops 保持同构；服务端不能 require Farm，所以复制一份最小字段）
FarmStore.CROPS = {
    fire     = { total = 4,  stages = { 1, 1.5, 1.5 }, yield = 3 },
    ice      = { total = 6,  stages = { 1.5, 2.5, 2 }, yield = 3 },
    thunder  = { total = 8,  stages = { 2, 3, 3 },     yield = 4 },
    gold     = { total = 6,  stages = { 1.5, 2.5, 2 }, yield = 5 },
    life     = { total = 12, stages = { 3, 5, 4 },     yield = 3 },
    mushroom = { total = 8,  stages = { 2, 3, 3 },     yield = 3 },
    timevine = { total = 16, stages = { 4, 7, 5 },     yield = 3 },
    chaos    = { total = 14, stages = { 3.5, 6, 4.5 }, yield = 3 },
    phoenix  = { total = 24, stages = { 6, 10, 8 },    yield = 2 },
}

local CODE_CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

--- 生成一个 6 位好友码（去掉易混淆的 I/O/0/1）
function FarmStore.GenerateCode(seed)
    local out = {}
    for i = 1, 6 do
        local k = math.random(1, #CODE_CHARS)
        out[i] = CODE_CHARS:sub(k, k)
    end
    return table.concat(out)
end

local function num(v, d)
    if type(v) ~= "number" then return d end
    return v
end

--- 新建一份空文档
function FarmStore.NewDoc(uid, name, now)
    return {
        uid = tostring(uid or ""),
        name = tostring(name or ""),
        updatedAt = math.floor(now or 0),
        landCount = 4,
        plots = {},
        seeds = {},
        fruits = {},
        rep = 0,
        events = {},
        friends = {},
        requests = { incoming = {}, outgoing = {} },
    }
end

--- 修复/补齐文档结构（读云端数据时先过一遍，防止脏数据）
function FarmStore.Ensure(doc)
    if type(doc) ~= "table" then return nil end
    doc.uid = tostring(doc.uid or "")
    doc.name = tostring(doc.name or "")
    doc.updatedAt = num(doc.updatedAt, 0)
    doc.landCount = math.max(4, math.min(9, math.floor(num(doc.landCount, 4))))
    if type(doc.plots) ~= "table" then doc.plots = {} end
    if type(doc.seeds) ~= "table" then doc.seeds = {} end
    if type(doc.fruits) ~= "table" then doc.fruits = {} end
    doc.rep = math.max(0, math.floor(num(doc.rep, 0)))
    if type(doc.events) ~= "table" then doc.events = {} end
    if type(doc.friends) ~= "table" then doc.friends = {} end
    if type(doc.requests) ~= "table" then doc.requests = { incoming = {}, outgoing = {} } end
    if type(doc.requests.incoming) ~= "table" then doc.requests.incoming = {} end
    if type(doc.requests.outgoing) ~= "table" then doc.requests.outgoing = {} end
    return doc
end

--- 单块地的状态（与客户端 Friend.PlotInfo 同一套算法）
function FarmStore.PlotInfo(doc, index, now)
    doc = FarmStore.Ensure(doc)
    if not doc then return { status = "locked" } end
    if index < 1 or index > (doc.landCount or 4) then return { status = "locked" } end
    local plot = doc.plots[index]
    local crop = plot and plot.crop and FarmStore.CROPS[plot.crop] or nil
    if not crop then return { status = "empty" } end
    local elapsed = math.max(0, now - (plot.plantedAt or 0)) + (plot.waterBonus or 0)
    local total = crop.total * 3600
    local s1 = (crop.stages[1] or 0) * 3600
    local s2 = (crop.stages[2] or 0) * 3600
    local c1, c2 = s1, s1 + s2
    local stage = 1
    if elapsed >= c1 then stage = 2 end
    if elapsed >= c2 then stage = 3 end
    local mature = elapsed >= total
    local matureAt = (plot.plantedAt or 0) + total - (plot.waterBonus or 0)
    local protectLeft = mature and math.max(0, (matureAt + FarmStore.PROTECT) - now) or 0
    local stageEnd = (stage == 1 and c1) or (stage == 2 and c2) or total
    return {
        status = mature and "mature" or "growing",
        crop = plot.crop,
        stage = stage,
        remain = math.max(0, total - elapsed),
        stageRemain = math.max(0, stageEnd - elapsed),
        protectLeft = protectLeft,
        waterCd = math.max(0, FarmStore.WATER_CD - (now - (plot.waterAt or 0))),
        stolen = plot.stolen == true,
        yield = crop.yield,
    }
end

--- 好友能看到的快照（不含种子/果实等隐私字段）
function FarmStore.Snapshot(doc, now)
    doc = FarmStore.Ensure(doc)
    if not doc then return nil end
    local plots = {}
    for i = 1, doc.landCount do
        local p = doc.plots[i]
        if p and p.crop then
            plots[i] = {
                crop = p.crop, plantedAt = p.plantedAt, waterBonus = p.waterBonus,
                waterAt = p.waterAt, stolen = p.stolen == true,
            }
        end
    end
    return {
        uid = doc.uid, name = doc.name, updatedAt = doc.updatedAt,
        landCount = doc.landCount, plots = plots,
    }
end

local function pushEvent(doc, ev)
    doc.events[#doc.events + 1] = ev
    while #doc.events > FarmStore.EVENT_CAP do table.remove(doc.events, 1) end
end

--- 好友帮浇水（服务端权威）：返回 ok, err, event
---@param doc table 目标（被浇水的人）
---@param index integer 地块
---@param now number 秒
---@param visitor table { uid=, name= }
function FarmStore.Water(doc, index, now, visitor)
    doc = FarmStore.Ensure(doc)
    if not doc then return false, "农场数据不可用" end
    if not visitor or visitor.uid == doc.uid then return false, "不能给自己的地浇水" end
    if not doc.friends[visitor.uid] then return false, "不是好友" end
    local info = FarmStore.PlotInfo(doc, index, now)
    if info.status ~= "growing" then return false, "只有生长中的作物能浇水" end
    if info.waterCd > 0 then
        return false, string.format("这块地还要 %d 分钟才能再浇", math.ceil(info.waterCd / 60))
    end
    local reduce = math.min(FarmStore.WATER_SEC, info.stageRemain or 0)
    if reduce <= 0 then return false, "当前阶段已经结束" end
    local plot = doc.plots[index]
    plot.waterBonus = (plot.waterBonus or 0) + reduce
    plot.waterAt = now
    doc.updatedAt = now
    local ev = { id = string.format("%s-%d-%d", visitor.uid, index, now), kind = "water",
        from = visitor.uid, fromName = visitor.name or "", plot = index, at = now }
    pushEvent(doc, ev)
    return true, nil, ev
end

--- 好友偷菜（服务端权威）：成熟 + 过保护期 + 未被偷
function FarmStore.Steal(doc, index, now, visitor)
    doc = FarmStore.Ensure(doc)
    if not doc then return false, "农场数据不可用" end
    if not visitor or visitor.uid == doc.uid then return false, "不能偷自己的菜" end
    if not doc.friends[visitor.uid] then return false, "不是好友" end
    local info = FarmStore.PlotInfo(doc, index, now)
    if info.status == "empty" then return false, "这块地已经空啦～下次早点来！" end
    if info.status ~= "mature" then return false, "这块地还没成熟，再等等吧～" end
    if info.stolen then return false, "这棵作物已经被偷过啦～" end
    if info.protectLeft > 0 then
        return false, string.format("这块地还在保护中（还要 %d 分钟）", math.ceil(info.protectLeft / 60))
    end
    doc.plots[index].stolen = true
    doc.plots[index].stolenBy = visitor.uid
    doc.updatedAt = now
    local ev = { id = string.format("%s-steal-%d-%d", visitor.uid, index, now), kind = "steal",
        from = visitor.uid, fromName = visitor.name or "", plot = index, at = now,
        crop = doc.plots[index].crop }
    pushEvent(doc, ev)
    return true, nil, ev
end

--- 收获（服务端权威）：被偷过就少 1 个
function FarmStore.Harvest(doc, index, now)
    doc = FarmStore.Ensure(doc)
    if not doc then return false, "农场数据不可用" end
    local info = FarmStore.PlotInfo(doc, index, now)
    if info.status ~= "mature" then return false, "作物还没成熟" end
    local yield = info.yield or 3
    if doc.plots[index].stolen then yield = math.max(0, yield - 1) end
    doc.fruits[info.crop] = (doc.fruits[info.crop] or 0) + yield
    doc.plots[index] = { crop = nil, plantedAt = 0, waterBonus = 0, waterAt = 0, stolen = false }
    doc.updatedAt = now
    return true, yield
end

--- 种下作物（服务端权威：校验种子与地块）
function FarmStore.Plant(doc, index, cropId, now)
    doc = FarmStore.Ensure(doc)
    if not doc then return false, "农场数据不可用" end
    if index < 1 or index > doc.landCount then return false, "这块土地还没解锁" end
    if doc.plots[index] and doc.plots[index].crop then return false, "这块地已经种了作物" end
    if not FarmStore.CROPS[cropId] then return false, "没有这种作物" end
    if (doc.seeds[cropId] or 0) <= 0 then return false, "没有这种种子" end
    doc.seeds[cropId] = doc.seeds[cropId] - 1
    if doc.seeds[cropId] <= 0 then doc.seeds[cropId] = nil end
    doc.plots[index] = { crop = cropId, plantedAt = now, waterBonus = 0, waterAt = 0, stolen = false }
    doc.updatedAt = now
    return true
end

-- ---------------------------------------------------------------- 好友关系
--- 发起好友请求
function FarmStore.RequestFriend(fromDoc, toDoc, now)
    fromDoc = FarmStore.Ensure(fromDoc)
    toDoc = FarmStore.Ensure(toDoc)
    if not fromDoc or not toDoc then return false, "玩家不存在" end
    if fromDoc.uid == toDoc.uid then return false, "不能加自己为好友" end
    if fromDoc.friends[toDoc.uid] then return false, "已经是好友了" end
    if toDoc.requests.incoming[fromDoc.uid] then return false, "已经发过请求，等对方确认" end
    -- 对方已经请求过我：直接互相通过
    if fromDoc.requests.incoming[toDoc.uid] then
        return FarmStore.AcceptFriend(toDoc, fromDoc, now)
    end
    if #FarmStore.FriendList(fromDoc) >= 30 then return false, "好友已满（30 人）" end
    toDoc.requests.incoming[fromDoc.uid] = { name = fromDoc.name, at = now }
    fromDoc.requests.outgoing[toDoc.uid] = { at = now }
    toDoc.updatedAt, fromDoc.updatedAt = now, now
    return true, "已发送好友请求"
end

--- 接受好友请求
function FarmStore.AcceptFriend(doc, requesterDoc, now)
    doc = FarmStore.Ensure(doc)
    requesterDoc = FarmStore.Ensure(requesterDoc)
    if not doc or not requesterDoc then return false, "玩家不存在" end
    if not doc.requests.incoming[requesterDoc.uid] then return false, "没有这个请求" end
    doc.requests.incoming[requesterDoc.uid] = nil
    requesterDoc.requests.outgoing[doc.uid] = nil
    doc.friends[requesterDoc.uid] = doc.friends[requesterDoc.uid] or { since = now, friendship = 0 }
    requesterDoc.friends[doc.uid] = requesterDoc.friends[doc.uid] or { since = now, friendship = 0 }
    doc.updatedAt, requesterDoc.updatedAt = now, now
    return true, "已成为好友"
end

--- 拒绝 / 删除好友
function FarmStore.RemoveFriend(doc, otherUid, now)
    doc = FarmStore.Ensure(doc)
    if not doc then return false end
    local removed = false
    if doc.friends[otherUid] then doc.friends[otherUid] = nil; removed = true end
    if doc.requests.incoming[otherUid] then doc.requests.incoming[otherUid] = nil; removed = true end
    if doc.requests.outgoing[otherUid] then doc.requests.outgoing[otherUid] = nil; removed = true end
    doc.updatedAt = now or doc.updatedAt
    return removed
end

--- 好友 uid 列表（稳定排序，便于分页/测试）
function FarmStore.FriendList(doc)
    doc = FarmStore.Ensure(doc)
    local out = {}
    if not doc then return out end
    for uid in pairs(doc.friends) do out[#out + 1] = uid end
    table.sort(out)
    return out
end

--- 玩家 id 搜索：精确匹配（客户端把名字搜索也归一到这个接口）
function FarmStore.MatchQuery(doc, query)
    if type(doc) ~= "table" or type(query) ~= "string" or query == "" then return false end
    if doc.uid == query then return true end
    local name = doc.name or ""
    if name ~= "" and name:find(query, 1, true) == 1 then return true end
    return false
end


-- ---------------------------------------------------------------- 分槽（联机持久化）
-- 依据周报的存档架构建议：按业务领域切槽，单槽独立读写、独立容错。
--   farm_meta    名字 / 好友码 / 地块数 / 声望 / 更新时间
--   farm_plots   每块地的作物状态（会随操作频繁变化，单独一槽）
--   farm_inv     种子 / 果实
--   farm_social  好友 / 好友申请 / 事件流
FarmStore.SLOT = {
    META   = "farm_meta",
    PLOTS  = "farm_plots",
    INV    = "farm_inv",
    SOCIAL = "farm_social",
}

--- 拆成 4 个槽
function FarmStore.ToSlots(doc)
    doc = FarmStore.Ensure(doc) or FarmStore.NewDoc("", "", 0)
    return {
        [FarmStore.SLOT.META] = {
            uid = doc.uid, name = doc.name, code = doc.code,
            updatedAt = doc.updatedAt, landCount = doc.landCount, rep = doc.rep,
        },
        [FarmStore.SLOT.PLOTS] = doc.plots or {},
        [FarmStore.SLOT.INV] = { seeds = doc.seeds or {}, fruits = doc.fruits or {} },
        [FarmStore.SLOT.SOCIAL] = {
            friends = doc.friends or {},
            requests = doc.requests or { incoming = {}, outgoing = {} },
            events = doc.events or {},
        },
    }
end

--- 合回一份文档；任一槽坏了只丢那一块，其余照常（附 issues 供打日志）
---@return table doc, table issues
function FarmStore.FromSlots(slots)
    slots = slots or {}
    local issues = {}
    local meta = slots[FarmStore.SLOT.META]
    if type(meta) ~= "table" then
        issues[#issues + 1] = "meta 缺失"
        meta = {}
    end
    local doc = FarmStore.NewDoc(meta.uid or "", meta.name or "", meta.updatedAt or 0)
    doc.code = meta.code
    doc.landCount = tonumber(meta.landCount) or doc.landCount
    doc.rep = tonumber(meta.rep) or 0

    local plots = slots[FarmStore.SLOT.PLOTS]
    if type(plots) == "table" then
        doc.plots = plots
    else
        issues[#issues + 1] = "plots 槽损坏"
    end

    local inv = slots[FarmStore.SLOT.INV]
    if type(inv) == "table" then
        if type(inv.seeds) == "table" then doc.seeds = inv.seeds end
        if type(inv.fruits) == "table" then doc.fruits = inv.fruits end
    else
        issues[#issues + 1] = "inv 槽损坏"
    end

    local social = slots[FarmStore.SLOT.SOCIAL]
    if type(social) == "table" then
        if type(social.friends) == "table" then doc.friends = social.friends end
        if type(social.requests) == "table" then doc.requests = social.requests end
        if type(social.events) == "table" then doc.events = social.events end
    else
        issues[#issues + 1] = "social 槽损坏"
    end

    return FarmStore.Ensure(doc) or doc, issues
end

return FarmStore
