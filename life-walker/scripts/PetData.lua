-- PetData.lua — 宠物系统数据表（口径：《宠物系统（最新）.docx》）
--   · 纯收集系统：与战力、属性、战斗增益完全无关
--   · 三档品质：低阶 10 / 高阶 15 / 究极 17，合计 42
--   · 7 属性：火 冰 毒 光 暗 雷 风
--   · 每只宠物是一条进化链（forms），进化只改外观，不加战力

local PetData = {}

-- ---------------------------------------------------------------- 属性
PetData.Attrs = {
    { id = "fire",   name = "火", color = { 255, 122, 62 } },
    { id = "ice",    name = "冰", color = { 118, 208, 255 } },
    { id = "poison", name = "毒", color = { 168, 226, 76 } },
    { id = "light",  name = "光", color = { 255, 238, 150 } },
    { id = "dark",   name = "暗", color = { 176, 132, 236 } },
    { id = "thunder", name = "雷", color = { 120, 176, 255 } },
    { id = "wind",   name = "风", color = { 140, 232, 196 } },
}

function PetData.AttrInfo(id)
    for _, a in ipairs(PetData.Attrs) do
        if a.id == id then return a end
    end
    return { id = id, name = "?", color = { 220, 220, 220 } }
end

-- ---------------------------------------------------------------- 品质档位
PetData.Tiers = {
    low   = { id = "low",   name = "低阶", hatchHours = 6,  dupCoin = 20,  evolve = 2, color = { 186, 208, 230 } },
    high  = { id = "high",  name = "高阶", hatchHours = 12, dupCoin = 100, evolve = 1, color = { 150, 200, 255 } },
    ultra = { id = "ultra", name = "究极", hatchHours = 24, dupCoin = 500, evolve = 0, color = { 255, 196, 92 } },
}
PetData.TierOrder = { "low", "high", "ultra" }

function PetData.TierInfo(id)
    return PetData.Tiers[id] or PetData.Tiers.low
end

-- ---------------------------------------------------------------- 42 只宠物（每条 = 一条进化链）
-- forms：从初始形态到最终形态；evolve 次数由品质决定（低阶 3 形态 / 高阶 2 形态 / 究极 1 形态）
PetData.List = {
    -- 火
    { id = "fire_l1",  attr = "fire", tier = "low",   forms = { "火花荧", "炎甲虫", "爆裂火甲" } },
    { id = "fire_l2",  attr = "fire", tier = "low",   forms = { "火毛虫", "火甲蛹", "幽火蝶" } },
    { id = "fire_h1",  attr = "fire", tier = "high",  forms = { "炎猭", "熔岩巨猿" } },
    { id = "fire_h2",  attr = "fire", tier = "high",  forms = { "焰火鸢", "炽阳鹰王" } },
    { id = "fire_h3",  attr = "fire", tier = "high",  forms = { "火焰喵喵", "斑火猫", "炽焰虎" } },
    { id = "fire_u1",  attr = "fire", tier = "ultra", forms = { "混沌烬焱" } },
    { id = "fire_u2",  attr = "fire", tier = "ultra", forms = { "赤焰凤王" } },
    { id = "fire_u3",  attr = "fire", tier = "ultra", forms = { "星陨炎龙" } },
    -- 冰
    { id = "ice_l1",   attr = "ice", tier = "low",   forms = { "冰蚕", "雪茧", "霜绒蛾" } },
    { id = "ice_l2",   attr = "ice", tier = "low",   forms = { "雪霜兔", "冰棱兔", "寒晶灵兔" } },
    { id = "ice_h1",   attr = "ice", tier = "high",  forms = { "霜雾狐", "冰幻狐" } },
    { id = "ice_h2",   attr = "ice", tier = "high",  forms = { "冰棘熊", "凛冬巨熊" } },
    { id = "ice_h3",   attr = "ice", tier = "high",  forms = { "霜牙狼崽", "冰鬃战狼" } },
    { id = "ice_u1",   attr = "ice", tier = "ultra", forms = { "永寂寒魄" } },
    { id = "ice_u2",   attr = "ice", tier = "ultra", forms = { "霜晶巨龙" } },
    { id = "ice_u3",   attr = "ice", tier = "ultra", forms = { "霜铁霸麝牛" } },
    -- 毒
    { id = "poison_l1", attr = "poison", tier = "low",  forms = { "毒囊工蚁", "毒螯兵蚁", "瘟疫蚁后" } },
    { id = "poison_l2", attr = "poison", tier = "low",  forms = { "箭毒蝇卵", "腐刺幼虫", "毒雾蛾后" } },
    { id = "poison_h1", attr = "poison", tier = "high", forms = { "腐沼蝌蚪", "毒腹蛙王" } },
    { id = "poison_h2", attr = "poison", tier = "high", forms = { "毒斑幼蜥", "腐喉毒蜥" } },
    { id = "poison_h3", attr = "poison", tier = "high", forms = { "幽毒影蛛", "冥网蚀蛛" } },
    { id = "poison_u1", attr = "poison", tier = "ultra", forms = { "毒厄巨蟒" } },
    { id = "poison_u2", attr = "poison", tier = "ultra", forms = { "冥刺毒蝎" } },
    -- 光（仅究极）
    { id = "light_u1", attr = "light", tier = "ultra", forms = { "圣翼炽天使" } },
    { id = "light_u2", attr = "light", tier = "ultra", forms = { "晨曦树灵" } },
    -- 暗（仅究极）
    { id = "dark_u1",  attr = "dark", tier = "ultra", forms = { "夜魇魔君" } },
    { id = "dark_u2",  attr = "dark", tier = "ultra", forms = { "暗蚀亡者" } },
    -- 雷
    { id = "thunder_l1", attr = "thunder", tier = "low",  forms = { "小闪电", "闪电球", "双生电磁" } },
    { id = "thunder_l2", attr = "thunder", tier = "low",  forms = { "闪跃犬", "雷暴犬", "疾雷狼" } },
    { id = "thunder_h1", attr = "thunder", tier = "high", forms = { "电羽雀", "闪雷鸢" } },
    { id = "thunder_h2", attr = "thunder", tier = "high", forms = { "电棘鼠", "棘雷豚" } },
    { id = "thunder_h3", attr = "thunder", tier = "high", forms = { "雷龙蜥", "雷龙兽" } },
    { id = "thunder_u1", attr = "thunder", tier = "ultra", forms = { "九霄雷幼龙" } },
    { id = "thunder_u2", attr = "thunder", tier = "ultra", forms = { "雷电暴君" } },
    -- 风
    { id = "wind_l1", attr = "wind", tier = "low",  forms = { "风茧幼虫", "裂翅蛹", "羽风蝶" } },
    { id = "wind_l2", attr = "wind", tier = "low",  forms = { "风艇", "风刃蜻蜓", "风暴蜻蜓" } },
    { id = "wind_h1", attr = "wind", tier = "high", forms = { "幼岚羚", "岚角羚羊" } },
    { id = "wind_h2", attr = "wind", tier = "high", forms = { "云海豚", "风云巨鲸" } },
    { id = "wind_h3", attr = "wind", tier = "high", forms = { "云狼", "风影狼" } },
    { id = "wind_u1", attr = "wind", tier = "ultra", forms = { "九霄鹏皇" } },
    { id = "wind_u2", attr = "wind", tier = "ultra", forms = { "风律苍澜" } },
    { id = "wind_u3", attr = "wind", tier = "ultra", forms = { "九霄岚龙" } },
}

function PetData.Get(id)
    for _, p in ipairs(PetData.List) do
        if p.id == id then return p end
    end
    return nil
end

--- 初始形态名（显示名用第一个形态）
function PetData.Name(pet)
    return pet and pet.forms and pet.forms[1] or "?"
end

--- 进化链文案：A → B → C
function PetData.ChainText(pet)
    if not pet or not pet.forms then return "" end
    return table.concat(pet.forms, " → ")
end

--- 按品质列出池子
function PetData.Pool(tier)
    local out = {}
    for _, p in ipairs(PetData.List) do
        if p.tier == tier then out[#out + 1] = p end
    end
    return out
end

function PetData.CountByTier()
    local n = { low = 0, high = 0, ultra = 0 }
    for _, p in ipairs(PetData.List) do
        n[p.tier] = (n[p.tier] or 0) + 1
    end
    return n
end

function PetData.TotalCount()
    return #PetData.List
end

-- ---------------------------------------------------------------- 灵宠孵蛋匣（抽蛋）
PetData.Gacha = {
    odds = { low = 72, high = 25, ultra = 3 },   -- 3.1 基础概率
    pity10 = 10,                                  -- 每 10 抽必出高阶及以上
    pity90 = 90,                                  -- 累计 90 抽必出究极，抽到后重置
    priceOnce = 20,                               -- 单抽消耗宠物代币（文档未给数值，暂定）
    priceTen = 180,                               -- 十连消耗（九折，文档未给数值，暂定）
    pity10Odds = { high = 90, ultra = 10 },       -- 十连保底时的品质权重
}

-- ---------------------------------------------------------------- 图鉴阶段奖励（7 表）
PetData.Rewards = {
    { id = "unique5",  kind = "unique", tier = nil,     need = 5,  coins = 100,  title = "初遇灵伴",
      desc = "累计解锁 5 只不同宠物" },
    { id = "unique10", kind = "unique", tier = nil,     need = 10, coins = 250,  title = "饲宠新手",
      desc = "累计解锁 10 只不同宠物" },
    { id = "unique15", kind = "unique", tier = nil,     need = 15, coins = 400,  title = "萌宠收藏家",
      desc = "累计解锁 15 只不同宠物" },
    { id = "allLow",   kind = "tier",   tier = "low",   need = 10, coins = 600,  title = "低阶饲育师",
      desc = "集齐全部 10 只低阶宠物" },
    { id = "allHigh",  kind = "tier",   tier = "high",  need = 15, coins = 1000, title = "高阶寻宠者",
      desc = "集齐全部 15 只高阶宠物" },
    { id = "ultra3",   kind = "tier",   tier = "ultra", need = 3,  coins = 1500, title = "究极邂逅",
      desc = "集齐 ≥3 只不同究极宠物" },
    { id = "all42",    kind = "total",  tier = nil,     need = 42, coins = 3000, title = "万灵饲主",
      desc = "全图鉴 42 只全部收集完成（额外送限定动态图鉴背景）" },
}

-- ---------------------------------------------------------------- 宠物商店（只收宠物代币；不出售究极蛋）
-- 文档只给了商品种类，没给价格；下列价格均为暂定值，可直接改这里
PetData.Shop = {
    { id = "egg_high", name = "高阶宠物蛋",     price = 150, desc = "直接获得 1 颗高阶蛋（随机）" },
    { id = "egg_low",  name = "自选低阶宠物蛋", price = 60,  desc = "从 10 只低阶里指定一只" },
    { id = "speed",    name = "孵化加速道具",   price = 60,  desc = "指定一颗蛋，孵化时间 -4 小时" },
    { id = "decor",    name = "家园装饰摆件",   price = 100, desc = "纯外观，摆在家园里" },
    { id = "bg",       name = "图鉴背景皮肤",   price = 200, desc = "纯外观，换图鉴底色" },
    { id = "cap",      name = "仓库扩容 +5 格", price = 50,  desc = "宠物 / 宠物蛋仓库各 +5 格，每次涨价 30" },
    { id = "slot",     name = "孵化槽 +1",      price = 200, desc = "同时孵化的上限 +1（默认 3，最多 6）" },
}

function PetData.ShopItem(id)
    for _, it in ipairs(PetData.Shop) do
        if it.id == id then return it end
    end
    return nil
end

-- ---------------------------------------------------------------- 宠物家园地块
-- 初始只有草地；收集到某属性的宠物后解锁该属性主题地块
PetData.HomePlots = {
    { id = "grass",   name = "草地",  attr = nil },
    { id = "fire",    name = "炽焰苑", attr = "fire" },
    { id = "ice",     name = "霜雪庭", attr = "ice" },
    { id = "poison",  name = "腐殖池", attr = "poison" },
    { id = "thunder", name = "雷鸣台", attr = "thunder" },
    { id = "wind",    name = "流风原", attr = "wind" },
    { id = "light",   name = "曦光坛", attr = "light" },
    { id = "dark",    name = "幽影窟", attr = "dark" },
}

-- 家园互动：每次 +3 代币，每日上限 30
PetData.Feed = { coins = 3, dailyCap = 30 }

-- 精粹 → 宠物代币（沿用旧版抽卡的价格：5 精粹 = 一次抽蛋的 20 代币）
PetData.CoinPacks = {
    { coins = 20,  essence = 5 },    -- 一次抽蛋的量（旧版低阶抽卡 5 精粹 / 次）
    { coins = 180, essence = 45 },   -- 十连的量（同九折）
}

-- 孵化槽：同时只能孵这么多颗，其余排队
PetData.BaseSlots = 3
PetData.SlotMax = 6
-- 第 4/5/6 个槽的价格（前 BaseSlots 个免费，文档未给数值，暂定）
PetData.SlotPrices = { 200, 300, 450 }

-- 仓库默认格子上限（文档只说“自带基础格子上限、可扩容”）
PetData.BaseCap = 20
PetData.CapStep = 5

return PetData
