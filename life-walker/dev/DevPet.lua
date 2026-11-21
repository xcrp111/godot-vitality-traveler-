-- DevPet.lua — 宠物系统回归（口径：《宠物系统（最新）.docx》）
-- 抽蛋概率/保底、重复折币、孵化、仓库容量、图鉴奖励、家园互动、代币商店
local Pet = require "Pet"
local PetData = require "PetData"
local Save = require "Save"

local fails = 0
local function check(name, cond, detail)
    if cond then
        print("[Pet] OK   " .. name)
    else
        fails = fails + 1
        print("[Pet] FAIL " .. name .. (detail ~= nil and (" — " .. tostring(detail)) or ""))
    end
end
local function eq(name, got, want)
    check(name, got == want, "got=" .. tostring(got) .. " want=" .. tostring(want))
end

local function ReadSaveRaw()
    local ok, text = pcall(function()
        if fileSystem and fileSystem:FileExists("save.json") then
            local f = File("save.json", FILE_READ)
            if f and f:IsOpen() then
                local t = f:ReadString(); f:Close(); return t
            end
        end
        return nil
    end)
    if ok then return text end
    return nil
end
local function WriteSaveRaw(text)
    if not text then return end
    pcall(function()
        local f = File("save.json", FILE_WRITE)
        if f and f:IsOpen() then f:WriteString(text); f:Close() end
    end)
end
local BACKUP = ReadSaveRaw()

function Start()
    local data = Save.Fresh()
    local p = Pet.Ensure(data)

    -- ---------------------------------------------------------------- 数据表
    local n = PetData.CountByTier()
    eq("低阶 10 只", n.low, 10)
    eq("高阶 15 只", n.high, 15)
    eq("究极 17 只", n.ultra, 17)
    eq("合计 42 只", PetData.TotalCount(), 42)
    eq("属性 7 种", #PetData.Attrs, 7)
    -- 品质与进化形态数：低阶 3 形态（两次进化）、高阶至少 2、究极单形态（文档里高阶「火焰喵喵」链是 3 形态）
    local badForms = 0
    for _, pet in ipairs(PetData.List) do
        if pet.tier == "low" and #pet.forms ~= 3 then badForms = badForms + 1 end
        if pet.tier == "high" and #pet.forms < 2 then badForms = badForms + 1 end
        if pet.tier == "ultra" and #pet.forms ~= 1 then badForms = badForms + 1 end
    end
    eq("进化链形态数符合品质", badForms, 0)

    -- ---------------------------------------------------------------- 代币
    eq("初始代币 0", Pet.Coins(data), 0)
    Pet.GrantStarter(data)
    local starter = Pet.Coins(data)
    check("首次一次性启动代币 > 0", starter > 0, starter)
    Pet.GrantStarter(data)
    eq("启动代币只发一次", Pet.Coins(data), starter)

    -- ---------------------------------------------------------------- 精粹换代币（沿用旧版抽卡价：5 精粹 = 20 代币）
    do
        local Economy = require "Economy"
        p.coins = 0
        Economy.AddEssence(data, 100, false)
        local ess0 = Economy.Essence(data)
        local okPack, msgPack = Pet.BuyCoinsWithEssence(data, 1)
        check("精粹买代币成功", okPack, msgPack)
        eq("20 代币对应 5 精粹", ess0 - Economy.Essence(data), 5)
        eq("代币到账 20", p.coins, 20)
        local okPack2 = Pet.BuyCoinsWithEssence(data, 2)
        check("十连档位也能买", okPack2, "pack2")
        eq("十连档位到账 180", p.coins, 200)
        p.coins = 0
        Economy.SpendEssence(data, Economy.Essence(data))
        local okNoEss, msgNoEss = Pet.BuyCoinsWithEssence(data, 1)
        check("精粹不足不能换", not okNoEss, msgNoEss)
    end

    -- ---------------------------------------------------------------- 抽蛋：余额 / 重复折币 / 入仓库
    p.coins = 0
    local okPoor, msgPoor = Pet.Draw(data, 1)
    check("代币不足不能抽", not okPoor, msgPoor)

    Pet.AddCoins(data, 100000)
    p.eggs = {}
    local coinsBefore = Pet.Coins(data)
    local okDraw, msgDraw, results = Pet.Draw(data, 1)
    check("抽一次成功", okDraw, msgDraw)
    eq("单抽扣 20 代币", coinsBefore - Pet.Coins(data), PetData.Gacha.priceOnce)
    eq("结果 1 条", #results, 1)
    eq("新蛋入仓库", #p.eggs, 1)
    check("新蛋带孵化结束时间", p.eggs[1].endAt > os.time(), p.eggs[1].endAt)

    -- 重复：手动把这只标成已点亮，再抽同一只 → 折币
    local dupId = p.eggs[1].id
    local dupTier = PetData.Get(dupId).tier
    p.seen[dupId] = true
    p.pets = { dupId }
    p.eggs = {}
    local dupCoinsBefore = Pet.Coins(data)
    -- 固定池子只有究极 1~2 只，这里直接模拟一次重复：注入 pity 让它必出究极并预先把所有究极标为已拥有
    for _, pet in ipairs(PetData.List) do
        if pet.tier == "ultra" then p.seen[pet.id] = true end
    end
    p.pity90 = PetData.Gacha.pity90 - 1
    local okDup, _, dupResults = Pet.Draw(data, 1)
    check("保底究极抽成功", okDup, "dup")
    eq("抽到究极", dupResults[1].tier, "ultra")
    eq("重复不再入蛋仓", #p.eggs, 0)
    check("重复折算代币", Pet.Coins(data) > dupCoinsBefore, Pet.Coins(data) - dupCoinsBefore)
    eq("大保底抽到后计数清零", p.pity90, 0)

    -- 十连保底：第 10 抽必出高阶及以上
    do
        p.eggs = {}
        p.seen = {}
        p.pity10 = PetData.Gacha.pity10 - 1
        local ok10, _, res10 = Pet.Draw(data, 10)
        check("十连成功", ok10, "ten")
        eq("十连出 10 条结果", #res10, 10)
        local first = res10[1]
        check("十连第一抽触发保底=高阶或究极", first.tier == "high" or first.tier == "ultra", first.tier)
        -- 保底触发后计数清零，剩下 9 抽重新累加到 9
        eq("十连后保底计数回到 9", p.pity10, 9)
    end

    -- 仓满：不能抽
    do
        p.eggs = {}
        for i = 1, Pet.EggCap(data) do
            p.eggs[i] = { id = "fire_l1", endAt = os.time() + 3600 }
        end
        local okFull, msgFull = Pet.Draw(data, 1)
        check("宠物蛋仓库满时不能抽", not okFull and string.find(msgFull, "仓库已满") ~= nil, msgFull)
        p.eggs = {}
    end

    -- ---------------------------------------------------------------- 孵化
    do
        p.pets = {}
        p.seen = {}
        p.eggs = { { id = "ice_l1", endAt = os.time() - 1 } }
        local hatched = Pet.Sweep(data)
        eq("到期孵化 1 只", hatched, 1)
        eq("蛋仓清空", #p.eggs, 0)
        eq("宠物仓 +1", #p.pets, 1)
        check("图鉴点亮", Pet.IsSeen(data, "ice_l1"), "ice_l1")
        eq("点亮总数 1", Pet.Unlocked(data), 1)

        -- 加速
        p.eggs = { { id = "wind_h1", endAt = os.time() + 12 * 3600 } }
        local before = Pet.EggLeft(p.eggs[1])
        Pet.SpeedUp(data, 1, 4)
        local after = Pet.EggLeft(p.eggs[1])
        check("加速后剩余时间减少 4 小时", before - after >= 4 * 3600 - 5, before - after)
    end

    -- ---------------------------------------------------------------- 图鉴奖励
    do
        p.seen = {}
        p.claimed = {}
        p.titles = {}
        p.pets = {}
        local ids = { "fire_l1", "fire_l2", "ice_l1", "ice_l2", "fire_h1" }
        for _, id in ipairs(ids) do p.seen[id] = true end
        eq("已点亮 5 只", Pet.Unlocked(data), 5)

        local coins0 = Pet.Coins(data)
        local okClaim, msgClaim = Pet.ClaimReward(data, "unique5")
        check("5 只奖励可领取", okClaim, msgClaim)
        eq("奖励发 100 代币", Pet.Coins(data) - coins0, 100)
        eq("称号 +1", Pet.TitleCount(data), 1)
        local okAgain = Pet.ClaimReward(data, "unique5")
        check("不能重复领取", not okAgain, "again")
        local okNotYet, msgNotYet = Pet.ClaimReward(data, "unique10")
        check("没达标的领不了", not okNotYet, msgNotYet)

        -- 全图鉴
        p.seen = {}
        for _, pet in ipairs(PetData.List) do p.seen[pet.id] = true end
        eq("全点亮 42 只", Pet.Unlocked(data), 42)
        local okAll = Pet.ClaimReward(data, "all42")
        check("全图鉴奖励可领", okAll, "all42")
        check("解锁限定图鉴背景", p.bgOwned, "bg")
    end

    -- ---------------------------------------------------------------- 家园
    do
        p.seen = { fire_l1 = true }
        p.pets = { "fire_l1" }
        p.home = { placed = {}, feedDay = "", feedCoins = 0 }

        local firePlot = nil
        for _, plot in ipairs(Pet.Plots(data)) do
            if plot.def.attr == "fire" then firePlot = plot end
        end
        check("收集火系后火系地块解锁", firePlot and not firePlot.locked, "fire plot")
        local icePlot = nil
        for _, plot in ipairs(Pet.Plots(data)) do
            if plot.def.attr == "ice" then icePlot = plot end
        end
        check("没冰系时冰系地块锁定", icePlot and icePlot.locked, "ice plot")

        local okPlace, msgPlace = Pet.Place(data, "fire_l1", "fire")
        check("放置成功", okPlace, msgPlace)
        local okLocked = Pet.Place(data, "fire_l1", "ice")
        check("不能放到锁定的地块", not okLocked, "locked")

        -- 每日互动：3/次，上限 30
        local coins1 = Pet.Coins(data)
        for _ = 1, 10 do Pet.Feed(data, "fire") end
        eq("互动 10 次 = 30 代币", Pet.Coins(data) - coins1, 30)
        eq("今日已满 30", Pet.FeedToday(data), 30)
        local okFeed, msgFeed = Pet.Feed(data, "fire")
        check("超过每日上限被拒", not okFeed, msgFeed)
    end

    -- ---------------------------------------------------------------- 孵化槽：同时孵化数量受限
    do
        p.eggs = {}
        p.pets = {}
        p.seen = {}
        p.slots = PetData.BaseSlots
        Pet.AddCoins(data, 100000)
        eq("默认孵化槽 3 个", Pet.Slots(data), 3)
        for _ = 1, 5 do Pet.Draw(data, 1) end
        local hatching, waiting = 0, 0
        for _, egg in ipairs(p.eggs) do
            if egg.state == "waiting" then waiting = waiting + 1 else hatching = hatching + 1 end
        end
        eq("同时只能孵 3 颗", hatching, 3)
        eq("剩下 2 颗排队", waiting, 2)
        eq("占用孵化槽 3", Pet.SlotsUsed(data), 3)

        -- 加速排队中的蛋会被拒
        local waitIdx = nil
        for i, egg in ipairs(p.eggs) do
            if egg.state == "waiting" then waitIdx = i break end
        end
        local okSpd, msgSpd = Pet.SpeedUp(data, waitIdx, 4)
        check("排队中的蛋不能加速", not okSpd, msgSpd)

        -- 一颗孵出来 → 排队的自动顶上
        for _, egg in ipairs(p.eggs) do
            if egg.state ~= "waiting" then egg.endAt = os.time() - 1 break end
        end
        Pet.Sweep(data)
        local h2, w2 = 0, 0
        for _, egg in ipairs(p.eggs) do
            if egg.state == "waiting" then w2 = w2 + 1 else h2 = h2 + 1 end
        end
        eq("孵出一颗后仍在孵的补满 3", h2, 3)
        eq("排队数减到 1", w2, 1)
        eq("宠物 +1", #p.pets, 1)

        -- 买孵化槽
        local price4 = Pet.SlotPrice(data)
        eq("第 4 个槽价格 = SlotPrices[1]", price4, PetData.SlotPrices[1])
        local okSlot, msgSlot = Pet.Buy(data, "slot")
        check("买孵化槽成功", okSlot, msgSlot)
        eq("孵化槽变 4 个", Pet.Slots(data), 4)
        eq("扩容后排队立即顶上", Pet.SlotsUsed(data), 4)
        p.slots = PetData.SlotMax
        check("满级后不能继续买", Pet.Buy(data, "slot") == false, "max slot")
        check("满级后 SlotPrice 为 nil", Pet.SlotPrice(data) == nil, "nil")
        p.slots = PetData.BaseSlots
        p.eggs = {}
    end

    -- ---------------------------------------------------------------- 宠物蛋列表滚动
    do
        local S = require "State"
        local PetUI = require "PetUI"
        S.data = data
        p.eggs = {}
        for i = 1, 18 do p.eggs[i] = { id = "fire_l1", endAt = os.time() + 3600 } end
        S.pet, S.petTab, S.petBagTab, S.petEggScroll, S.petEggDrag = true, 2, 1, 0, nil
        eq("滚动初始偏移 0", S.petEggScroll, 0)
        check("滚轮在蛋列表里被吃掉", PetUI.Wheel(-1) == true, "wheel")
        eq("滚轮下滑 1 行", S.petEggScroll, 1)
        for _ = 1, 30 do PetUI.Wheel(-1) end
        eq("滑到底被夹在 8（18-10）", S.petEggScroll, 8)
        PetUI.Wheel(1)
        eq("滚轮上滑 1 行", S.petEggScroll, 7)

        S.petEggDrag = nil
        check("列表内按下被接管", PetUI.Pointer("down", 200, 300) == true, "drag down")
        PetUI.Pointer("move", 200, 300 + 2 * 44)
        eq("往下拖 2 行 = 往上滚 2 行（偏移 7→5）", S.petEggScroll, 5)
        PetUI.Pointer("up", 200, 300 + 2 * 44)
        check("松手后不再拖拽", S.petEggDrag == nil, "drag nil")
        check("加速按钮列（x>890）不接管拖拽", PetUI.Pointer("down", 950, 300) == false, "outside")

        S.pet = false
        check("不在蛋页时滚轮不被吃", PetUI.Wheel(-1) == false, "wheel off")
        S.petEggScroll, S.petEggDrag, p.eggs = 0, nil, {}
    end

    -- ---------------------------------------------------------------- 商店
    do
        Pet.AddCoins(data, 5000)
        local capBefore = Pet.EggCap(data)
        local priceBefore = Pet.CapPrice(data)
        local okCap = Pet.Buy(data, "cap")
        check("扩容成功", okCap, "cap")
        eq("蛋仓 +5 格", Pet.EggCap(data), capBefore + PetData.CapStep)
        eq("扩容涨价 30", Pet.CapPrice(data), priceBefore + 30)

        p.eggs = {}
        local okHigh = Pet.Buy(data, "egg_high")
        check("买高阶蛋成功", okHigh, "egg_high")
        eq("高阶蛋入仓", #p.eggs, 1)
        eq("买到的是高阶", PetData.Get(p.eggs[1].id).tier, "high")

        p.eggs = {}
        local okLow = Pet.Buy(data, "egg_low", "wind_l1")
        check("自选低阶蛋成功", okLow, "egg_low")
        eq("指定的是 wind_l1", p.eggs[1].id, "wind_l1")

        p.eggs = { { id = "wind_l1", endAt = os.time() + 6 * 3600 } }
        local okSpeed = Pet.Buy(data, "speed", 1)
        check("加速道具成功", okSpeed, "speed")
        check("加速后剩余 <= 2 小时", Pet.EggLeft(p.eggs[1]) <= 2 * 3600 + 5, Pet.EggLeft(p.eggs[1]))

        local decoBefore = p.decor
        Pet.Buy(data, "decor")
        eq("摆件 +1", p.decor, decoBefore + 1)
        p.bgOwned = false
        local okBg = Pet.Buy(data, "bg")
        check("背景皮肤可买", okBg, "bg")
        check("买完标记已拥有", p.bgOwned, "bgOwned")
    end

    print(string.format("[Pet] done, failures = %d", fails))
    WriteSaveRaw(BACKUP)
    print("[Pet] save.json restored")
end
