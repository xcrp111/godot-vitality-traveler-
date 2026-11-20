-- Pet.lua — 宠物系统逻辑（口径：《宠物系统（最新）.docx》）
-- 纯收集：抽蛋 → 孵化 → 仓库/图鉴/家园，全程不提供任何战力或属性加成。
-- 专属货币：宠物代币（pet coins），与精粹、金币完全独立。

local PetData = require "PetData"

local Pet = {}

-- ---------------------------------------------------------------- 存档结构
local function defaultPet()
    return {
        coins = 0,               -- 宠物代币
        pity10 = 0,              -- 十连保底计数（每 10 抽触发）
        pity90 = 0,              -- 大保底计数（90 抽必出究极）
        eggs = {},               -- { { id = petId, state = "waiting"|"hatching", endAt = number } }
        pets = {},               -- 已孵化宠物 id 列表（不重复）
        slots = 0,               -- 孵化槽数量（0 → 用 PetData.BaseSlots）
        seen = {},               -- 图鉴点亮 [petId] = true
        claimed = {},            -- 已领取的图鉴阶段奖励
        titles = {},             -- 已获得称号（= 奖励 id）
        eggCap = 0,              -- 0 → 用 PetData.BaseCap
        petCap = 0,
        capBought = 0,           -- 扩容次数（涨价用）
        bgOwned = false,         -- 图鉴背景皮肤
        decor = 0,               -- 家园装饰摆件数量
        home = { placed = {}, feedDay = "", feedCoins = 0 },
        starterGranted = false,
        stageRewards = {},       -- 已发过代币的关卡节点
        season = { id = "", lit = {}, claimed = {} },
    }
end

--- 补齐存档结构；顺手清掉旧版（精粹抽蛋）留下的字段
---@param data table
---@return table
function Pet.Ensure(data)
    if type(data) ~= "table" then return defaultPet() end
    local def = defaultPet()
    local p = data.pet
    if type(p) ~= "table" then
        data.pet = defaultPet()
        p = data.pet
    end
    for k, v in pairs(def) do
        if p[k] == nil then p[k] = v end
    end
    -- 旧版营地里用精粹养宠物的字段，直接废弃（品种已作废）
    if type(data.camp) == "table" then
        data.camp.pets = nil
        data.camp.eggs = nil
        data.camp.gacha = nil
        data.camp.speed50 = nil
        data.camp.speed20 = nil
    end
    for _, k in ipairs({ "coins", "pity10", "pity90", "eggCap", "petCap", "capBought", "decor" }) do
        p[k] = math.max(0, math.floor(p[k] or 0))
    end
    if type(p.eggs) ~= "table" then p.eggs = {} end
    if type(p.pets) ~= "table" then p.pets = {} end
    -- 孵化槽：默认 BaseSlots，上限 SlotMax；超出上限的同时孵化退回排队
    p.slots = math.max(PetData.BaseSlots, math.min(PetData.SlotMax, math.floor(p.slots or 0)))
    -- 蛋状态迁移：没 state 的按有无 endAt 判断；超过孵化槽的同时孵化退回排队
    for _, egg in ipairs(p.eggs) do
        if egg.state == nil then
            egg.state = ((egg.endAt or 0) > 0) and "hatching" or "waiting"
        end
    end
    local used = 0
    for _, egg in ipairs(p.eggs) do
        if egg.state ~= "waiting" then
            used = used + 1
            if used > p.slots then
                egg.state = "waiting"
                egg.endAt = nil
            end
        end
    end
    if type(p.seen) ~= "table" then p.seen = {} end
    if type(p.claimed) ~= "table" then p.claimed = {} end
    if type(p.titles) ~= "table" then p.titles = {} end
    if type(p.stageRewards) ~= "table" then p.stageRewards = {} end
    if type(p.home) ~= "table" then p.home = defaultPet().home end
    if type(p.home.placed) ~= "table" then p.home.placed = {} end
    if type(p.season) ~= "table" then p.season = defaultPet().season end
    return p
end

-- ---------------------------------------------------------------- 宠物代币
function Pet.Coins(data)
    return Pet.Ensure(data).coins
end

---@return integer 实际入账
function Pet.AddCoins(data, n)
    local p = Pet.Ensure(data)
    n = math.floor((n or 0) + 0.5)
    if n <= 0 then return 0 end
    p.coins = p.coins + n
    return n
end

---@return boolean
function Pet.SpendCoins(data, n)
    local p = Pet.Ensure(data)
    n = math.floor((n or 0) + 0.5)
    if n <= 0 then return true end
    if p.coins < n then return false end
    p.coins = p.coins - n
    return true
end

--- 首次进入宠物系统的一次性启动代币（文档：首次解锁时发启动资金）
---@return integer 本次发放数量
function Pet.GrantStarter(data)
    local p = Pet.Ensure(data)
    if p.starterGranted then return 0 end
    p.starterGranted = true
    return Pet.AddCoins(data, 200)   -- 文档未给数值，暂定 200
end

--- 用精粹买宠物代币（价格沿用旧版抽卡：5 精粹 = 20 代币）
---@param data table
---@param packIndex integer PetData.CoinPacks 下标
---@return boolean, string
function Pet.BuyCoinsWithEssence(data, packIndex)
    local pack = PetData.CoinPacks[packIndex or 0]
    if not pack then return false, "没有这个兑换档位" end
    local Economy = require "Economy"
    if Economy.Essence(data) < pack.essence then
        return false, string.format("精粹不足，还差 %d", pack.essence - Economy.Essence(data))
    end
    Economy.SpendEssence(data, pack.essence)
    Pet.AddCoins(data, pack.coins)
    return true, string.format("-%d 精粹　+%d 宠物代币", pack.essence, pack.coins)
end

--- 主线阶段性通关追加少量代币（文档：章节阶段性通关追加，未给数值 → 每 3 关 +50）
---@return integer
function Pet.OnStageCleared(data, level)
    local p = Pet.Ensure(data)
    level = math.floor(level or 0)
    if level <= 0 or level % 3 ~= 0 then return 0 end
    local key = "s" .. level
    if p.stageRewards[key] then return 0 end
    p.stageRewards[key] = true
    return Pet.AddCoins(data, 50)
end

-- ---------------------------------------------------------------- 孵化槽
---@return integer
function Pet.Slots(data)
    local p = Pet.Ensure(data)
    return math.max(PetData.BaseSlots, math.min(PetData.SlotMax, p.slots or PetData.BaseSlots))
end

--- 正在占用孵化槽的数量（含已孵好待领取的）
---@return integer
function Pet.SlotsUsed(data)
    local p = Pet.Ensure(data)
    local n = 0
    for _, egg in ipairs(p.eggs) do
        if egg.state ~= "waiting" then n = n + 1 end
    end
    return n
end

--- 下一个孵化槽的价格（已满返回 nil）
---@return integer|nil
function Pet.SlotPrice(data)
    local owned = Pet.Slots(data)
    if owned >= PetData.SlotMax then return nil end
    return PetData.SlotPrices[owned - PetData.BaseSlots + 1]
end

--- 有空槽就把排队的蛋放进去孵（按入仓顺序）
---@return integer 本次开始孵化的数量
function Pet.AutoIncubate(data)
    local p = Pet.Ensure(data)
    local started = 0
    while Pet.SlotsUsed(data) < Pet.Slots(data) do
        local picked = nil
        for i, egg in ipairs(p.eggs) do
            if egg.state == "waiting" then picked = i break end
        end
        if not picked then break end
        local egg = p.eggs[picked]
        local tier = PetData.TierInfo(PetData.Get(egg.id).tier)
        egg.state = "hatching"
        egg.endAt = os.time() + tier.hatchHours * 3600
        started = started + 1
    end
    return started
end

-- ---------------------------------------------------------------- 仓库容量
function Pet.EggCap(data)
    local p = Pet.Ensure(data)
    return (p.eggCap > 0) and p.eggCap or PetData.BaseCap
end

function Pet.PetCap(data)
    local p = Pet.Ensure(data)
    return (p.petCap > 0) and p.petCap or PetData.BaseCap
end

function Pet.EggCount(data)
    return #Pet.Ensure(data).eggs
end

function Pet.PetCount(data)
    return #Pet.Ensure(data).pets
end

--- 扩容价格（每次 +30）
function Pet.CapPrice(data)
    local p = Pet.Ensure(data)
    return 50 + 30 * (p.capBought or 0)
end

-- ---------------------------------------------------------------- 抽蛋（灵宠孵蛋匣）
local function pickWeighted(weights)
    local total = 0
    for _, v in pairs(weights) do total = total + v end
    local r = math.random() * total
    for k, v in pairs(weights) do
        r = r - v
        if r <= 0 then return k end
    end
    return "low"
end

local function pickFromPool(tier)
    local pool = PetData.Pool(tier)
    if #pool == 0 then return nil end
    return pool[math.random(1, #pool)]
end

--- 抽一次（内部）：返回 { tier, pet, dup, coins }
local function rollOnce(data, forcedTier)
    local p = Pet.Ensure(data)
    local tier = forcedTier or pickWeighted(PetData.Gacha.odds)
    local pet = pickFromPool(tier)
    local dup = pet ~= nil and p.seen[pet.id] == true
    return { tier = tier, pet = pet, dup = dup }
end

--- 抽蛋：times = 1 或 10
---@param data table
---@param times integer|nil
---@return boolean ok, string message, table results
function Pet.Draw(data, times)
    local p = Pet.Ensure(data)
    times = (times == 10) and 10 or 1
    local price = (times == 10) and PetData.Gacha.priceTen or PetData.Gacha.priceOnce
    if #p.eggs >= Pet.EggCap(data) then
        return false, "宠物蛋仓库已满：先孵化或扩容仓库", {}
    end
    if p.coins < price then
        return false, string.format("宠物代币不足，还差 %d", price - p.coins), {}
    end
    Pet.SpendCoins(data, price)

    local results = {}
    local eggRoom = Pet.EggCap(data) - #p.eggs
    for i = 1, times do
        local forced = nil
        -- 大保底：累计 90 抽必出究极
        p.pity90 = p.pity90 + 1
        if p.pity90 >= PetData.Gacha.pity90 then
            forced = "ultra"
            p.pity90 = 0
        end
        -- 十连保底：每 10 抽必出高阶及以上
        p.pity10 = p.pity10 + 1
        if not forced and p.pity10 >= PetData.Gacha.pity10 then
            forced = pickWeighted(PetData.Gacha.pity10Odds)
            p.pity10 = 0
        end

        local r = rollOnce(data, forced)
        if r.tier == "ultra" then p.pity90 = 0 end

        if r.dup then
            local coins = PetData.TierInfo(r.tier).dupCoin
            Pet.AddCoins(data, coins)
            r.coins = coins
        elseif eggRoom > 0 then
            local tier = PetData.TierInfo(r.tier)
            p.eggs[#p.eggs + 1] = {
                id = r.pet.id,
                state = "waiting",
            }
            eggRoom = eggRoom - 1
            r.queued = true
        else
            -- 仓库已满：按重复处理，折算代币（避免卡住抽蛋流程）
            local coins = PetData.TierInfo(r.tier).dupCoin
            Pet.AddCoins(data, coins)
            r.coins = coins
            r.full = true
        end
        results[#results + 1] = r
    end

    local newN, dupN = 0, 0
    for _, r in ipairs(results) do
        if r.coins then dupN = dupN + 1 else newN = newN + 1 end
    end
    -- 有空孵化槽就自动开始孵化（槽满则排队）
    local started = Pet.AutoIncubate(data)
    return true, string.format("抽蛋完成：新蛋 %d 颗（开始孵化 %d，排队 %d），重复折算 %d 次",
        newN, started, math.max(0, newN - started), dupN), results
end

-- ---------------------------------------------------------------- 孵化
---@return integer 剩余秒数（排队中返回 -1；<=0 表示已可领取）
function Pet.EggLeft(egg)
    if not egg then return 0 end
    if egg.state == "waiting" then return -1 end
    return math.max(0, math.floor((egg.endAt or 0) - os.time()))
end

--- 把到时间的蛋孵出来（进宠物仓库 + 点亮相册）；宠物仓库满则留在蛋页等待
---@return integer hatched, integer blocked
function Pet.Sweep(data)
    local p = Pet.Ensure(data)
    local now = os.time()
    local hatched, blocked = 0, 0
    for i = #p.eggs, 1, -1 do
        local egg = p.eggs[i]
        if egg.state ~= "waiting" and (egg.endAt or 0) <= now then
            if #p.pets >= Pet.PetCap(data) then
                blocked = blocked + 1
            else
                table.remove(p.eggs, i)
                if not p.seen[egg.id] then
                    p.seen[egg.id] = true
                end
                p.pets[#p.pets + 1] = egg.id
                hatched = hatched + 1
            end
        end
    end
    -- 腾出孵化槽后，排队的蛋顶上
    Pet.AutoIncubate(data)
    return hatched, blocked
end

--- 加速一颗蛋（小时）
---@return boolean, string
function Pet.SpeedUp(data, index, hours)
    local p = Pet.Ensure(data)
    local egg = p.eggs[index]
    if not egg then return false, "没有这颗蛋" end
    if egg.state == "waiting" then return false, "这颗蛋还在排队，先等孵化槽空出来" end
    local left = Pet.EggLeft(egg)
    if left <= 0 then return false, "这颗蛋已经孵好了" end
    egg.endAt = egg.endAt - math.max(1, math.floor(hours or 4)) * 3600
    if egg.endAt < os.time() then egg.endAt = os.time() end
    return true, string.format("加速完成（-%d 小时）", hours or 4)
end

-- ---------------------------------------------------------------- 图鉴
function Pet.Unlocked(data)
    local p = Pet.Ensure(data)
    local n = 0
    for _ in pairs(p.seen) do n = n + 1 end
    return n
end

function Pet.IsSeen(data, petId)
    return Pet.Ensure(data).seen[petId] == true
end

--- 某品质已点亮数量
function Pet.TierUnlocked(data, tier)
    local p = Pet.Ensure(data)
    local n = 0
    for id, v in pairs(p.seen) do
        if v then
            local pet = PetData.Get(id)
            if pet and pet.tier == tier then n = n + 1 end
        end
    end
    return n
end

--- 某属性已点亮数量
function Pet.AttrUnlocked(data, attr)
    local p = Pet.Ensure(data)
    local n = 0
    for id, v in pairs(p.seen) do
        if v then
            local pet = PetData.Get(id)
            if pet and pet.attr == attr then n = n + 1 end
        end
    end
    return n
end

--- 奖励进度：返回 progress, need, done, claimed
function Pet.RewardState(data, reward)
    local progress
    if reward.kind == "unique" then
        progress = Pet.Unlocked(data)
    elseif reward.kind == "tier" then
        progress = Pet.TierUnlocked(data, reward.tier)
    else
        progress = Pet.Unlocked(data)
    end
    local p = Pet.Ensure(data)
    return progress, reward.need, progress >= reward.need, p.claimed[reward.id] == true
end

--- 领取图鉴阶段奖励
---@return boolean, string
function Pet.ClaimReward(data, rewardId)
    local p = Pet.Ensure(data)
    local reward
    for _, r in ipairs(PetData.Rewards) do
        if r.id == rewardId then reward = r break end
    end
    if not reward then return false, "没有这个奖励" end
    if p.claimed[reward.id] then return false, "已经领过了" end
    local _, _, done = Pet.RewardState(data, reward)
    if not done then return false, "收集数量还不够" end
    p.claimed[reward.id] = true
    p.titles[reward.id] = true
    Pet.AddCoins(data, reward.coins)
    if reward.id == "all42" then p.bgOwned = true end
    return true, string.format("领取成功：+%d 宠物代币，称号「%s」", reward.coins, reward.title)
end

function Pet.TitleCount(data)
    local p = Pet.Ensure(data)
    local n = 0
    for _ in pairs(p.titles) do n = n + 1 end
    return n
end

-- ---------------------------------------------------------------- 宠物家园
local function dayKey()
    return os.date("%Y-%m-%d")
end

--- 地块列表：返回 { def, locked, petId, canFeed }
function Pet.Plots(data)
    local p = Pet.Ensure(data)
    local out = {}
    for _, def in ipairs(PetData.HomePlots) do
        local locked = def.attr ~= nil and Pet.AttrUnlocked(data, def.attr) <= 0
        out[#out + 1] = {
            def = def,
            locked = locked,
            petId = p.home.placed[def.id],
        }
    end
    return out
end

--- 放一只宠物到地块
---@return boolean, string
function Pet.Place(data, petId, plotId)
    local p = Pet.Ensure(data)
    if not PetData.Get(petId) then return false, "没有这只宠物" end
    local owned = false
    for _, id in ipairs(p.pets) do
        if id == petId then owned = true break end
    end
    if not owned then return false, "你还没有这只宠物" end
    for _, def in ipairs(PetData.HomePlots) do
        if def.id == plotId then
            if def.attr and Pet.AttrUnlocked(data, def.attr) <= 0 then
                return false, "这个地块还没解锁（先收集该属性的宠物）"
            end
        end
    end
    -- 同一只宠物不能同时出现在两个地块
    for k, v in pairs(p.home.placed) do
        if v == petId then p.home.placed[k] = nil end
    end
    p.home.placed[plotId] = petId
    return true, "已放置"
end

function Pet.RemoveFromPlot(data, plotId)
    local p = Pet.Ensure(data)
    if p.home.placed[plotId] then
        p.home.placed[plotId] = nil
        return true
    end
    return false
end

--- 家园互动（喂食）：每次 +3 代币，每日上限 30
---@return boolean, string
function Pet.Feed(data, plotId)
    local p = Pet.Ensure(data)
    local petId = p.home.placed[plotId]
    if not petId then return false, "这块地上没有宠物" end
    local today = dayKey()
    if p.home.feedDay ~= today then
        p.home.feedDay = today
        p.home.feedCoins = 0
    end
    if p.home.feedCoins >= PetData.Feed.dailyCap then
        return false, string.format("今日互动代币已满（%d/%d）", p.home.feedCoins, PetData.Feed.dailyCap)
    end
    local gain = PetData.Feed.coins
    if p.home.feedCoins + gain > PetData.Feed.dailyCap then
        gain = PetData.Feed.dailyCap - p.home.feedCoins
    end
    p.home.feedCoins = p.home.feedCoins + gain
    Pet.AddCoins(data, gain)
    return true, string.format("和 %s 互动：+%d 宠物代币（今日 %d/%d）",
        PetData.Name(PetData.Get(petId)), gain, p.home.feedCoins, PetData.Feed.dailyCap)
end

--- 今日互动进度
function Pet.FeedToday(data)
    local p = Pet.Ensure(data)
    if p.home.feedDay ~= dayKey() then return 0 end
    return p.home.feedCoins or 0
end

-- ---------------------------------------------------------------- 宠物商店
---@return boolean, string
function Pet.Buy(data, itemId, arg)
    local p = Pet.Ensure(data)
    local item = PetData.ShopItem(itemId)
    if not item then return false, "没有这个商品" end
    local price = item.price
    if itemId == "cap" then price = Pet.CapPrice(data) end
    if itemId == "slot" then
        local sp = Pet.SlotPrice(data)
        if not sp then return false, "孵化槽已经满级（" .. PetData.SlotMax .. " 个）" end
        price = sp
    end

    if not Pet.SpendCoins(data, price) then
        return false, string.format("宠物代币不足，还差 %d", price - p.coins)
    end

    if itemId == "egg_high" then
        if #p.eggs >= Pet.EggCap(data) then
            Pet.AddCoins(data, price)
            return false, "宠物蛋仓库已满"
        end
        local pet = pickFromPool("high")
        p.eggs[#p.eggs + 1] = { id = pet.id, state = "waiting" }
        Pet.AutoIncubate(data)
        return true, "获得高阶蛋：" .. PetData.Name(pet)
    elseif itemId == "egg_low" then
        local pet = arg and PetData.Get(arg) or nil
        if not pet or pet.tier ~= "low" then
            Pet.AddCoins(data, price)
            return false, "要指定一只低阶宠物"
        end
        if #p.eggs >= Pet.EggCap(data) then
            Pet.AddCoins(data, price)
            return false, "宠物蛋仓库已满"
        end
        p.eggs[#p.eggs + 1] = { id = pet.id, state = "waiting" }
        Pet.AutoIncubate(data)
        return true, "获得低阶蛋：" .. PetData.Name(pet)
    elseif itemId == "speed" then
        local idx = tonumber(arg) or 0
        local egg = p.eggs[idx]
        if not egg then
            Pet.AddCoins(data, price)
            return false, "要指定一颗正在孵的蛋"
        end
        Pet.SpeedUp(data, idx, 4)
        return true, "加速完成：孵化时间 -4 小时"
    elseif itemId == "decor" then
        p.decor = (p.decor or 0) + 1
        return true, "买到一件家园摆件（纯外观）"
    elseif itemId == "bg" then
        if p.bgOwned then
            Pet.AddCoins(data, price)
            return false, "已经有图鉴背景皮肤了"
        end
        p.bgOwned = true
        return true, "已解锁图鉴背景皮肤（纯外观）"
    elseif itemId == "cap" then
        p.capBought = (p.capBought or 0) + 1
        p.eggCap = Pet.EggCap(data) + PetData.CapStep
        p.petCap = Pet.PetCap(data) + PetData.CapStep
        return true, string.format("仓库扩容 +%d 格（现在各 %d 格）", PetData.CapStep, Pet.EggCap(data))
    elseif itemId == "slot" then
        p.slots = Pet.Slots(data) + 1
        Pet.AutoIncubate(data)
        return true, string.format("孵化槽 +1（现在 %d 个）", Pet.Slots(data))
    end
    Pet.AddCoins(data, price)
    return false, "这个商品还没实现"
end

return Pet
