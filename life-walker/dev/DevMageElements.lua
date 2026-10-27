-- DevMageElements.lua — 法师强化按携带元素过滤：没带哪系就抽不到哪系
local Config = require "Config"
local Save = require "Save"
local S = require "State"
local Run = require "Run"

local fails = 0
local function check(name, cond, detail)
    if cond then
        print("[Elem] OK   " .. name)
    else
        fails = fails + 1
        print("[Elem] FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
    end
end

local RARITIES = { "white", "blue", "purple", "gold", "color" }

local function Usable(id)
    for _, rarity in ipairs(RARITIES) do
        for _, b in ipairs(Config.ClassBuffs.mage[rarity] or {}) do
            if b.id == id then return Run.ClassBuffUsable(b) end
        end
    end
    return nil
end

local function AllBuffs()
    local list = {}
    for _, rarity in ipairs(RARITIES) do
        for _, b in ipairs(Config.ClassBuffs.mage[rarity] or {}) do
            list[#list + 1] = b
        end
    end
    return list
end

local function Setup(loadout)
    S.data = Save.Load()
    Save.SetClass(S.data, "mage")
    Save.SetClassLevel(S.data, 12)
    Config.SetClass("mage")
    Run.Start(2)
    S.run.loadout = loadout
end

function Start()
    local all = AllBuffs()
    check("法师强化总数 48", #all == 48, #all)

    -- ============ 全冰（冰冻波 2 / 冰锥 4 / 暴风雪 9）============
    Setup({ 2, 4, 9 })
    check("全冰：冰系强化可用", Usable("ma_w_ice") == true)
    check("全冰：火系强化不可用", Usable("ma_w_fire") == false)
    check("全冰：电系强化不可用", Usable("ma_w_bolt") == false)
    check("全冰：冰系专属可用", Usable("ma_w_blizzard") == true)
    check("全冰：火系专属不可用", Usable("ma_w_fireball") == false)
    check("全冰：电系专属不可用", Usable("ma_w_boltstrike") == false)
    check("全冰：元素协调不可用（缺火/电）", Usable("ma_p_resonance") == false)
    check("全冰：冰火两重天不可用（缺火）", Usable("ma_c_melt") == false)

    -- 不变量：可用的强化，其需要的元素必须全都带着
    local iceOnly = { ice = true }
    local violated = 0
    for _, b in ipairs(all) do
        local need = Config.ClassBuffElementNeed(b)
        if need and Run.ClassBuffUsable(b) then
            for el in pairs(need) do
                if not iceOnly[el] then violated = violated + 1 end
            end
        end
    end
    check("全冰：没有越界条目", violated == 0, violated)

    -- ============ 全火（火球 1 / 烈焰 6 / 流星 8）============
    Setup({ 1, 6, 8 })
    check("全火：火系可用", Usable("ma_w_fire") == true)
    check("全火：冰系不可用", Usable("ma_w_ice") == false)
    check("全火：电系不可用", Usable("ma_w_bolt") == false)
    check("全火：熔岩之心可用（带火）", Usable("ma_p_lava") == true)
    check("全火：龙息术可用", Usable("ma_p_dragon") == true)
    check("全火：寒霜领域不可用", Usable("ma_b_frostfield") == false)

    -- ============ 全电（雷击 3 / 闪电链 5 / 静电力场 7）============
    Setup({ 3, 5, 7 })
    check("全电：电系可用", Usable("ma_w_bolt") == true)
    check("全电：火系不可用", Usable("ma_w_fire") == false)
    check("全电：冰系不可用", Usable("ma_w_ice") == false)
    check("全电：雷暴导体可用", Usable("ma_p_thunder") == true)
    check("全电：熔岩之心不可用", Usable("ma_p_lava") == false)

    -- ============ 三系各一（火球 1 / 冰冻波 2 / 雷击 3）============
    Setup({ 1, 2, 3 })
    check("三系：火系可用", Usable("ma_w_fire") == true)
    check("三系：冰系可用", Usable("ma_w_ice") == true)
    check("三系：电系可用", Usable("ma_w_bolt") == true)
    check("三系：元素协调可用（三系齐全）", Usable("ma_p_resonance") == true)
    check("三系：冰火两重天可用（冰火齐全）", Usable("ma_c_melt") == true)

    -- ============ 通用强化任何配装都能出 ============
    Setup({ 1, 6, 8 })
    check("通用：能量虹吸始终可用", Usable("ma_w_siphon") == true)
    check("通用：时空法师始终可用", Usable("ma_c_time") == true)
    check("通用：元素共鸣·极始终可用", Usable("ma_g_ultimate") == true)

    -- ============ 需求文案 ============
    Setup({ 1, 2, 3 })
    local function NeedText(id)
        for _, b in ipairs(all) do
            if b.id == id then return Config.ClassBuffNeedText(b) end
        end
        return nil
    end
    check("冰系需求文案", NeedText("ma_w_ice") == "冰系技能", NeedText("ma_w_ice"))
    check("三系需求文案", NeedText("ma_p_resonance") == "火系 + 冰系 + 电系技能",
        NeedText("ma_p_resonance"))
    check("冰火需求文案", NeedText("ma_c_melt") == "火系 + 冰系技能", NeedText("ma_c_melt"))

    print("[Elem] done, failures = " .. fails)
end
