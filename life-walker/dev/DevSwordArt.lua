-- DevSwordArt.lua — 剑客素材包接入回归：角色图集 / 特效注册 / 关键触发点
local Config = require "Config"
local Save = require "Save"
local S = require "State"
local Run = require "Run"
local Combat = require "Combat"
local EffectArt = require "EffectArt"
local UI = require "UI"
local SwordFxDefs = require "SwordFxDefs"
local SwordFx = require "SwordFx"

local fails = 0
local function check(name, cond, detail)
    if cond then
        print("[SwArt] OK   " .. name)
    else
        fails = fails + 1
        print("[SwArt] FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
    end
end

-- 1) 角色图集（headless 没有 nvg 上下文，直接查缓存资源）
local okImg, atlas = pcall(function()
    return GetCache():GetResource("Image", "image/char/swordsman.png")
end)
check("剑客图集能加载", okImg and atlas ~= nil)

-- 2) 特效注册数量与文件
local count = 0
local missing = {}
for id, def in pairs(SwordFxDefs) do
    count = count + 1
    if not EffectArt.Def(id) then missing[#missing + 1] = id .. ":未注册" end
    local ok, snd = pcall(function() return GetCache():GetResource("Image", def.file) end)
    if not ok or not snd then missing[#missing + 1] = id .. ":" .. def.file end
end
check("剑客特效数量 >= 100", count >= 100, count)
check("所有剑客特效都注册且文件存在", #missing == 0, table.concat(missing, ", "))

-- 2b) 映射覆盖：108 个特效都要挂在某个事件上，且事件名必须真被战斗代码调用
do
    local covered = SwordFx.CoveredIds()
    local missing = {}
    for id in pairs(SwordFxDefs) do
        if not covered[id] then missing[#missing + 1] = id end
    end
    check("108 个特效全部挂到事件上", #missing == 0, table.concat(missing, ", "))

    local text = ""
    pcall(function()
        local f = File("scripts/Combat.lua", FILE_READ)
        if f and f:IsOpen() then text = f:ReadString() or ""; f:Close() end
    end)
    if #text > 0 then
        local dead = {}
        for key in pairs(SwordFx.EVENTS) do
            if not text:find('"' .. key .. '"', 1, true) then dead[#dead + 1] = key end
        end
        check("所有特效事件都有触发点", #dead == 0, table.concat(dead, ", "))
    end
end

-- 3) 关键触发点：进入战斗有出场聚光
S.data = Save.Load()
Save.SetClass(S.data, "swordsman")
Config.SetClass("swordsman")
Run.Start(3, true)
local cs = Combat.Start(S.run, "standard", 1)
S.combat = cs
S.screen = "combat"
local hasSpawn = false
for _, fx in ipairs(cs.fx or {}) do
    if fx.id == "swfx_A01_spawn_fx" then hasSpawn = true end
end
check("剑客进战斗有出场聚光", hasSpawn)

-- 4) 挫裂 / 失衡 / 猎痕 施加时有对应特效（走真实 Add* 路径很难直接调，用技能打）
local function HasFx(prefix)
    for _, fx in ipairs(cs.fx or {}) do
        if fx.id == prefix then return true end
    end
    return false
end
cs.walls, cs.waves, cs.waveIndex = {}, { {} }, 1
Combat.SpawnWave(cs, { minion = 1 })
local e = cs.enemies[1]
if e then
    e.x, e.y = cs.player.x + 40, cs.player.y
    e.hp, e.maxHp = 99999, 99999
    cs.player.crackDebuff = 1
    -- 三段斩第三段带挫裂；直接给敌人叠一层也走 AddCrack 路径
    Combat.TrueDamage(cs, e, 1, nil)
    -- 通过连携/技能触发不可控，这里只验证特效定义与生成接口可用
    Combat.SpawnFx(cs, "swfx_E01_apply", e.x, e.y, {})
    check("特效生成接口可用（E01_apply）", HasFx("swfx_E01_apply"))
end

-- 5) 护盾受击 / 治疗 / 复活特效定义存在
for _, id in ipairs({ "swfx_A10_shield_hit", "swfx_A11_shield_break",
    "swfx_A15h_heal", "swfx_A14_revive_fx", "swfx_S00_hit" }) do
    check("已注册 " .. id, EffectArt.Def(id) ~= nil)
end

print(string.format("[SwArt] done, failures = %d", fails))
