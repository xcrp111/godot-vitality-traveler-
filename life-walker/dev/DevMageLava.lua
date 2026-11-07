-- DevMageLava.lua — 熔岩之心：余烬地面不能自我繁殖，叠层有上限
local Config = require "Config"
local Save = require "Save"
local S = require "State"
local Run = require "Run"
local Combat = require "Combat"

local fails = 0
local function check(name, cond, detail)
    if cond then
        print("[Lava] OK   " .. name)
    else
        fails = fails + 1
        print("[Lava] FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
    end
end

local function EmberCount(cs)
    local n = 0
    for _, f in ipairs(cs.mageFields) do
        if f.ember then n = n + 1 end
    end
    return n
end

function Start()
    S.data = Save.Load()
    Save.SetClass(S.data, "mage")
    Save.SetClassLevel(S.data, 12)
    Config.SetClass("mage")
    Run.Start(2)
    S.run.loadout = { 1, 6, 8 }   -- 火球 / 烈焰冲击 / 流星
    local p = S.run.player
    Run.GrantBuff(p, { id = "ma_p_lava", name = "熔岩之心", desc = "", rarity = "purple",
        classBuff = true, mod = {}, flag = { emberOnFire = 1 } })

    local cs = Combat.Start(S.run, "standard", 5)
    S.screen = "combat"
    cs.enemies = {}
    cs.walls = {}
    cs.waves = { {} }
    cs.waveIndex = 1

    -- 一个血很厚的"Boss"
    Combat.SpawnWave(cs, { boss = 1 })
    local boss = cs.enemies[1]
    boss.hp = 999999
    boss.maxHp = 999999
    boss.x = p.x + 150
    boss.y = p.y
    boss.stunTimer = 99
    boss.moveSpeed = 0

    local hp0 = boss.hp

    -- 按真实冷却连续放火系技能，跑 4 秒
    local t = 0
    for frame = 1, 240 do
        Combat.CastSkill(1)
        Combat.CastSkill(2)
        Combat.CastSkill(3)
        Combat.Update(1 / 60)
        t = t + 1 / 60
        if EmberCount(cs) > 6 then break end
    end

    local embers = EmberCount(cs)
    check("余烬数量不超过 6 片", embers <= 6, embers)

    local lost = hp0 - boss.hp
    local pct = lost / hp0
    check("4 秒内不会秒杀厚血 Boss", boss.hp > 0, string.format("剩余 %.0f", boss.hp))
    check("伤害占比合理（< 25%）", pct < 0.25, string.format("%.1f%%（%.0f 伤害）", pct * 100, lost))

    -- 单次火系命中只生成 1 片余烬
    cs.mageFields = {}
    Combat.CastSkill(1)   -- 火球
    for _ = 1, 40 do Combat.Update(1 / 60) end
    check("火球命中只生成少量余烬", EmberCount(cs) <= 2, EmberCount(cs))

    print(string.format("[Lava] 4 秒共造成 %.0f 伤害（Boss 血量 %.0f，%.1f%%）",
        lost, hp0, pct * 100))
    print("[Lava] done, failures = " .. fails)
end
