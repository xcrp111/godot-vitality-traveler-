-- Friend.lua — 农场好友系统（第一版：单机模拟好友）
-- 设计依据：docs 农场系统设计（好友偷菜 / 帮忙浇水 / 友好度）
--
-- 当前阶段是「单机版社交模拟」：好友列表、好友农场都在本地生成并按真实时间生长，
-- 浇水 / 偷菜 / 赠送都会真实生效（玩家农场也会被"好友"浇水、偷菜）。
-- 以后接真联机时，只需要把 Friend.FarmOf / Friend.Tick 换成服务端读写即可，
-- 上层 UI 和结算逻辑不用动。

local Farm = require "Farm"

local Friend = {}

-- ---------------------------------------------------------------- 数值
Friend.PROTECT = 2 * 3600          -- 成熟后保护期：2 小时内不可偷
Friend.WATER_CD = 2 * 3600         -- 同一块地浇水冷却 2 小时
Friend.DAILY_WATER = 20            -- 每日浇水次数上限
Friend.DAILY_STEAL = 20            -- 每日偷菜次数上限
Friend.DAILY_GIFT = 1              -- 每日赠送次数
Friend.DAY_GAIN_CAP = 50           -- 单个好友每日最多涨 50 友好度
Friend.MAX_FRIENDS = 12

Friend.LEVELS = {
    { need = 0,    name = "陌生人",   unlock = "基础功能：访问农场、偷菜、浇水" },
    { need = 30,   name = "点头之交", unlock = "浇水冷却 2 小时 → 1.5 小时" },
    { need = 100,  name = "普通好友", unlock = "一键三连：一次帮好友所有作物浇水" },
    { need = 300,  name = "亲密好友", unlock = "解锁特殊作物：彩虹蘑菇" },
    { need = 600,  name = "最佳搭档", unlock = "专属称号「最佳拍档」" },
    { need = 1200, name = "莫逆之交", unlock = "种子共享：每周可白拿 5 颗" },
    { need = 1800, name = "灵魂羁绊", unlock = "共生农场（下一版）" },
}

Friend.NAMES = {
    "林小满", "白露", "阿茶", "陈拾光", "苏晚", "老周", "柚子", "南风",
    "禾木", "叶知秋", "小满", "唐不苦", "青柠", "温故", "海盐", "云游",
}

local CODE_CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

local function RandCode(n)
    local out = {}
    for i = 1, (n or 6) do
        local k = math.random(1, #CODE_CHARS)
        out[i] = CODE_CHARS:sub(k, k)
    end
    return table.concat(out)
end

-- ---------------------------------------------------------------- 存档
local function SaveNow()
    local Save = require "Save"
    Save.Write(require("State").data)
end

local function defaultFriend()
    return {
        myCode = RandCode(6),
        seq = 0,
        list = {},
        day = { key = "", water = 0, steal = 0, gift = 0 },
        notify = {},
        lastTick = 0,
    }
end

--- 补齐/修复好友存档
function Friend.Ensure(data)
    if type(data) ~= "table" then return nil end
    local fr = data.friend
    if type(fr) ~= "table" then
        fr = defaultFriend()
        data.friend = fr
    end
    if type(fr.myCode) ~= "string" or fr.myCode == "" then fr.myCode = RandCode(6) end
    if type(fr.list) ~= "table" then fr.list = {} end
    if type(fr.day) ~= "table" then fr.day = { key = "", water = 0, steal = 0, gift = 0 } end
    if type(fr.notify) ~= "table" then fr.notify = {} end
    fr.seq = math.floor(tonumber(fr.seq) or #fr.list)
    for _, f in ipairs(fr.list) do
        if type(f.farm) ~= "table" then f.farm = { landCount = 4, plots = {} } end
        if type(f.farm.plots) ~= "table" then f.farm.plots = {} end
        f.farm.landCount = math.max(4, math.min(9, math.floor(tonumber(f.farm.landCount) or 4)))
        f.friendship = math.max(0, math.floor(tonumber(f.friendship) or 0))
        f.dayGain = math.max(0, math.floor(tonumber(f.dayGain) or 0))
    end
    return fr
end

local function TodayKey()
    return os.date("%Y-%m-%d")
end

--- 跨天：清每日计数
function Friend.RollDay(data)
    local fr = Friend.Ensure(data)
    if not fr then return nil end
    local key = TodayKey()
    if fr.day.key ~= key then
        fr.day = { key = key, water = 0, steal = 0, gift = 0 }
        for _, f in ipairs(fr.list) do f.dayGain = 0 end
    end
    return fr
end

-- ---------------------------------------------------------------- 好友列表
function Friend.List(data)
    local fr = Friend.RollDay(data)
    return fr and fr.list or {}
end

function Friend.Get(data, id)
    for _, f in ipairs(Friend.List(data)) do
        if f.id == id then return f end
    end
    return nil
end

function Friend.Count(data)
    return #Friend.List(data)
end

function Friend.MyCode(data)
    local fr = Friend.Ensure(data)
    return fr and fr.myCode or "------"
end

-- ---------------------------------------------------------------- 好友度
function Friend.LevelOf(friend)
    local v = friend and friend.friendship or 0
    local lv = 0
    for i, row in ipairs(Friend.LEVELS) do
        if v >= row.need then lv = i - 1 end
    end
    return lv
end

function Friend.LevelName(friend)
    local lv = Friend.LevelOf(friend)
    local row = Friend.LEVELS[lv + 1]
    return row and row.name or "陌生人"
end

--- 下一级门槛（已满级返回 nil）
function Friend.NextNeed(friend)
    local lv = Friend.LevelOf(friend)
    local row = Friend.LEVELS[lv + 2]
    return row and row.need or nil
end

--- 友好度双向增长：单个好友每天有上限，同时按同数额加到农场声望（商店/等级继续沿用）
function Friend.Gain(data, friend, n)
    local fr = Friend.RollDay(data)
    if not fr or not friend or n <= 0 then return 0 end
    local room = math.max(0, Friend.DAY_GAIN_CAP - (friend.dayGain or 0))
    local added = math.min(room, math.floor(n))
    if added <= 0 then return 0 end
    friend.friendship = (friend.friendship or 0) + added
    friend.dayGain = (friend.dayGain or 0) + added
    Farm.AddRep(data, added)
    return added
end

-- ---------------------------------------------------------------- 好友农场
local function NewPlot(cropId, plantedAt)
    return { crop = cropId, plantedAt = plantedAt, waterBonus = 0, waterAt = 0, stolen = false }
end

--- 生成一个模拟好友（好友码添加 / 首次进游戏自动送几个）
local function MakeFriend(data, code, name)
    local fr = Friend.Ensure(data)
    fr.seq = (fr.seq or 0) + 1
    local landCount = math.random(4, 7)
    local farm = { landCount = landCount, plots = {} }
    local now = os.time()
    local pool = Farm.UnlockedCrops(data)
    if #pool == 0 then pool = { Farm.Crops[1] } end
    local planted = 0
    for i = 1, 9 do
        if i <= landCount and planted < math.random(2, landCount) then
            local crop = pool[math.random(1, #pool)]
            -- 种下时间随机落在 0 ~ 1.6 个生长周期之前，这样能看到各种阶段
            local back = math.random(0, math.floor(crop.total * 3600 * 1.6))
            farm.plots[i] = NewPlot(crop.id, now - back)
            planted = planted + 1
        end
    end
    local f = {
        id = fr.seq,
        name = name or Friend.NAMES[math.random(1, #Friend.NAMES)],
        code = code or RandCode(6),
        friendship = 0,
        dayGain = 0,
        addedAt = now,
        lastVisit = 0,
        farm = farm,
    }
    fr.list[#fr.list + 1] = f
    return f
end

--- 首次进入：送 3 个模拟好友（真联机后删掉这一段）
function Friend.Bootstrap(data)
    local fr = Friend.Ensure(data)
    if not fr then return end
    if #fr.list > 0 then return end
    for _ = 1, 3 do MakeFriend(data) end
    SaveNow()
end

--- 用好友码添加（当前版本只校验格式，然后生成一个模拟好友）
---@return boolean, string, table|nil
function Friend.AddByCode(data, code)
    local fr = Friend.RollDay(data)
    if not fr then return false, "好友数据不可用" end
    code = tostring(code or ""):upper():gsub("%s", "")
    if #code ~= 6 then return false, "好友码是 6 位字母数字" end
    if code == fr.myCode then return false, "这是你自己的好友码" end
    if #fr.list >= Friend.MAX_FRIENDS then
        return false, string.format("好友已满（%d 人）", Friend.MAX_FRIENDS)
    end
    for _, f in ipairs(fr.list) do
        if f.code == code then return false, "已经是好友了" end
    end
    local f = MakeFriend(data, code)
    SaveNow()
    return true, "已添加好友：" .. f.name, f
end

function Friend.Remove(data, id)
    local fr = Friend.Ensure(data)
    if not fr then return end
    for i, f in ipairs(fr.list) do
        if f.id == id then
            table.remove(fr.list, i)
            SaveNow()
            return true
        end
    end
    return false
end

local function CropOf(plot)
    return plot and plot.crop and Farm.CropByID(plot.crop) or nil
end

--- 好友某块地的状态（和 Farm.PlotInfo 同一套阶段算法，冷却固定 2 小时）
function Friend.PlotInfo(friend, index)
    local farm = friend and friend.farm
    local plot = farm and farm.plots and farm.plots[index]
    if not farm or index > (farm.landCount or 4) then return { status = "locked" } end
    local crop = CropOf(plot)
    if not crop then return { status = "empty" } end
    local now = os.time()
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
    local protectLeft = mature and math.max(0, (matureAt + Friend.PROTECT) - now) or 0
    local stageEnd = (stage == 1 and c1) or (stage == 2 and c2) or total
    local waterCd = math.max(0, Friend.WATER_CD - (now - (plot.waterAt or 0)))
    return {
        status = mature and "mature" or "growing",
        crop = crop,
        stage = stage,
        stageName = mature and "可收获" or ({ "发芽期", "生长期", "成熟期" })[stage],
        remain = math.max(0, total - elapsed),
        stageRemain = math.max(0, stageEnd - elapsed),
        waterCd = waterCd,
        waterReady = (not mature) and waterCd <= 0,
        protectLeft = protectLeft,
        stolen = plot.stolen == true,
        canSteal = mature and protectLeft <= 0 and not plot.stolen,
    }
end

--- 好友农场的所有地块
function Friend.Plots(friend)
    local out = {}
    local land = friend and friend.farm and friend.farm.landCount or 4
    for i = 1, 9 do
        out[i] = Friend.PlotInfo(friend, i)
    end
    return out, land
end

--- 帮好友浇水：当前阶段剩余 -15 分钟，双方友好度 +1
---@return boolean, string
function Friend.Water(data, friendId, index)
    local fr = Friend.RollDay(data)
    local friend = Friend.Get(data, friendId)
    if not fr or not friend then return false, "找不到这个好友" end
    if (fr.day.water or 0) >= Friend.DAILY_WATER then
        return false, string.format("今日浇水次数已用完（%d 次）", Friend.DAILY_WATER)
    end
    local info = Friend.PlotInfo(friend, index)
    if info.status ~= "growing" then return false, "只有生长中的作物能浇水" end
    if not info.waterReady then
        return false, string.format("这块地还要 %d 分钟才能再浇", math.ceil(info.waterCd / 60))
    end
    local reduce = math.min(Farm.WATER_SEC, info.stageRemain or 0)
    if reduce <= 0 then return false, "当前阶段已经结束" end
    local plot = friend.farm.plots[index]
    plot.waterBonus = (plot.waterBonus or 0) + reduce
    plot.waterAt = os.time()
    fr.day.water = (fr.day.water or 0) + 1
    local gained = Friend.Gain(data, friend, 1)
    SaveNow()
    return true, string.format("帮 %s 浇水成功：剩余时间 -%d 分钟（友好度 +%d）",
        friend.name, math.floor(reduce / 60 + 0.5), gained)
end

--- 一键三连（友好度 Lv.2）：给这个好友所有可浇水的作物浇一遍，只消耗 1 次浇水次数
function Friend.WaterAll(data, friendId)
    local fr = Friend.RollDay(data)
    local friend = Friend.Get(data, friendId)
    if not fr or not friend then return false, "找不到这个好友" end
    if Friend.LevelOf(friend) < 2 then return false, "友好度达到「普通好友」(Lv.2) 才能一键浇水" end
    if (fr.day.water or 0) >= Friend.DAILY_WATER then
        return false, string.format("今日浇水次数已用完（%d 次）", Friend.DAILY_WATER)
    end
    local land = friend.farm.landCount or 4
    local n = 0
    for i = 1, land do
        local info = Friend.PlotInfo(friend, i)
        if info.status == "growing" and info.waterReady then
            local plot = friend.farm.plots[i]
            local reduce = math.min(Farm.WATER_SEC, info.stageRemain or 0)
            if reduce > 0 then
                plot.waterBonus = (plot.waterBonus or 0) + reduce
                plot.waterAt = os.time()
                n = n + 1
            end
        end
    end
    if n == 0 then return false, "现在没有可以浇水的地" end
    fr.day.water = (fr.day.water or 0) + 1
    local gained = Friend.Gain(data, friend, 1)
    SaveNow()
    return true, string.format("一键三连：帮 %s 浇了 %d 块地（友好度 +%d）", friend.name, n, gained)
end

--- 偷菜：成熟且过了保护期、且没被偷过 → 玩家拿到 1 个果实，好友收获 -1
---@return boolean, string
function Friend.Steal(data, friendId, index)
    local fr = Friend.RollDay(data)
    local friend = Friend.Get(data, friendId)
    if not fr or not friend then return false, "找不到这个好友" end
    if (fr.day.steal or 0) >= Friend.DAILY_STEAL then
        return false, string.format("今日偷菜次数已用完（%d 次）", Friend.DAILY_STEAL)
    end
    local info = Friend.PlotInfo(friend, index)
    if info.status == "empty" then return false, "这块地已经空啦～下次早点来！" end
    if info.status ~= "mature" then return false, "这块地还没成熟，再等等吧～" end
    if info.stolen then return false, "这棵作物已经被偷过啦～" end
    if not info.canSteal then
        return false, string.format("这块地还在保护中（还要 %d 分钟）", math.ceil((info.protectLeft or 0) / 60))
    end
    local f = Farm.Roll(data)
    if f and (f.fruits[info.crop.id] or 0) + 1 > Farm.FRUIT_CAP then
        return false, "你的果实仓库满了，先去用掉一些"
    end
    friend.farm.plots[index].stolen = true
    friend.farm.plots[index].stolenAt = os.time()
    if f then Farm.AddFruit(data, info.crop.id, 1) end
    fr.day.steal = (fr.day.steal or 0) + 1
    local gained = Friend.Gain(data, friend, 1)
    SaveNow()
    return true, string.format("偷到 %s 的 %s ×1（友好度 +%d）", friend.name, info.crop.fruitName, gained)
end

--- 赠送种子：消耗自己 1 颗基础种子，双方友好度 +3（每日 1 次）
function Friend.Gift(data, friendId)
    local fr = Friend.RollDay(data)
    local friend = Friend.Get(data, friendId)
    if not fr or not friend then return false, "找不到这个好友" end
    if (fr.day.gift or 0) >= Friend.DAILY_GIFT then
        return false, "今天已经送过种子了"
    end
    local f = Farm.Roll(data)
    local cropId = nil
    for _, c in ipairs(Farm.Crops) do
        if c.seedType == "basic" and (f.seeds[c.id] or 0) > 0 then cropId = c.id break end
    end
    if not cropId then return false, "没有可以赠送的基础种子" end
    f.seeds[cropId] = f.seeds[cropId] - 1
    if f.seeds[cropId] <= 0 then f.seeds[cropId] = nil end
    fr.day.gift = (fr.day.gift or 0) + 1
    local gained = Friend.Gain(data, friend, 3)
    SaveNow()
    return true, string.format("送给 %s 一颗%s种子（友好度 +%d）",
        friend.name, Farm.CropByID(cropId).name, gained)
end

-- ---------------------------------------------------------------- 通知
function Friend.Notify(data, text)
    local fr = Friend.Ensure(data)
    if not fr then return end
    fr.notify[#fr.notify + 1] = { t = os.time(), text = text, read = false }
    while #fr.notify > 30 do table.remove(fr.notify, 1) end
end

function Friend.Unread(data)
    local fr = Friend.Ensure(data)
    if not fr then return 0 end
    local n = 0
    for _, m in ipairs(fr.notify) do
        if not m.read then n = n + 1 end
    end
    return n
end

function Friend.MarkRead(data)
    local fr = Friend.Ensure(data)
    if not fr then return end
    for _, m in ipairs(fr.notify) do m.read = true end
end

-- ---------------------------------------------------------------- 好友对玩家的回访（模拟）
--- 打开农场时调用：按离线时长模拟"好友来访"——帮忙浇水、偷菜、作物成熟提醒。
--- 真联机后这一段换成服务端事件拉取。
function Friend.Tick(data)
    local fr = Friend.Ensure(data)
    if not fr then return end
    local now = os.time()
    local last = tonumber(fr.lastTick) or 0
    fr.lastTick = now
    if last <= 0 or #fr.list == 0 then return end
    local elapsed = math.max(0, now - last)
    local rounds = math.min(3, math.floor(elapsed / (3 * 3600)))   -- 每 3 小时最多来一次，最多补 3 次
    if rounds <= 0 then return end

    local f = Farm.Roll(data)
    if not f then return end
    local land = f.landCount or 4

    for _ = 1, rounds do
        local friend = fr.list[math.random(1, #fr.list)]
        local action = math.random(1, 3)
        if action == 1 then
            -- 好友帮我浇水：找一块生长中的地
            local candidates = {}
            for i = 1, land do
                local info = Farm.PlotInfo(data, i)
                if info.status == "growing" then candidates[#candidates + 1] = i end
            end
            if #candidates > 0 then
                local idx = candidates[math.random(1, #candidates)]
                local plot = f.plots[idx]
                local info = Farm.PlotInfo(data, idx)
                local reduce = math.min(Farm.WATER_SEC, info.stageRemain or 0)
                if reduce > 0 then
                    plot.waterBonus = (plot.waterBonus or 0) + reduce
                    plot.waterAt = now
                    Friend.Notify(data, string.format("%s 帮你的%s浇了水（-15 分钟）",
                        friend.name, info.crop.name))
                    friend.wateredMe = (friend.wateredMe or 0) + 1
                end
            end
        elseif action == 2 then
            -- 好友偷菜：找成熟且过了保护期、没被偷过的地
            local candidates = {}
            for i = 1, land do
                local info = Farm.PlotInfo(data, i)
                if info.status == "mature" and not info.stolen
                    and (info.remain or 1) <= 0 then
                    candidates[#candidates + 1] = i
                end
            end
            if #candidates > 0 then
                local idx = candidates[math.random(1, #candidates)]
                local info = Farm.PlotInfo(data, idx)
                f.plots[idx].stolen = true
                f.plots[idx].stolenAt = now
                Friend.Notify(data, string.format("%s 偷偷摘走了你 1 个%s！",
                    friend.name, info.crop.fruitName))
            end
        else
            Friend.Notify(data, string.format("%s 来你的农场逛了一圈", friend.name))
        end
    end
    SaveNow()
end

return Friend
