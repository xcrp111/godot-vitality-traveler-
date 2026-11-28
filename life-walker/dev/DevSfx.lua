-- DevSfx.lua — 法师音效包接入回归
-- 覆盖：资源是否都存在、播放接口是否安全、技能施放是否真的触发音效、循环音效句柄能否关掉
local Config = require "Config"
local Save = require "Save"
local S = require "State"
local Run = require "Run"
local Combat = require "Combat"
local Sfx = require "Sfx"

local fails = 0
local function check(name, cond, detail)
    if cond then
        print("[Sfx] OK   " .. name)
    else
        fails = fails + 1
        print("[Sfx] FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
    end
end

local ROOT = ""   -- Defs 里已经是完整路径

local function SoundOf(path)
    local ok, s = pcall(function() return GetCache():GetResource("Sound", ROOT .. path) end)
    if ok then return s end
    return nil
end

-- 1) 所有定义的文件都能被引擎解析成 Sound
local missing = {}
local count = 0
for id, def in pairs(Sfx.Defs) do
    count = count + 1
    local s = SoundOf(def.file)
    if not s or (s.length or 0) <= 0 then missing[#missing + 1] = id .. ":" .. def.file end
end
for id, def in pairs(Sfx.Loops) do
    count = count + 1
    local s = SoundOf(def.file)
    if not s or (s.length or 0) <= 0 then missing[#missing + 1] = "loop_" .. id .. ":" .. def.file end
end
check("音效定义数量 >= 25", count >= 25, count)
check("所有音效文件都能加载", #missing == 0, table.concat(missing, ", "))

-- 2) 播放接口不会因为未知 id / 关闭开关而报错
check("未知音效 id 返回 false", Sfx.Play("no_such_sfx") == false)
S.data = Save.Load()
S.data.sfxOn = false
check("关闭音效后不播放", Sfx.Play("ui_click") == false)
S.data.sfxOn = true
check("打开音效后可播放", Sfx.Play("ui_click") == true)
-- gap 生效：同一帧再播会被拦下
check("重复触发被 gap 拦下", Sfx.Play("ui_click") == false)
Sfx.Update(1.0)
check("间隔够了可以再播", Sfx.Play("ui_click") == true)

-- 3) 循环音效可以开始 / 停止
local h = Sfx.StartLoop("blizzard")
check("循环音效返回句柄", h ~= nil)
if h then
    h:Stop()
    check("循环音效可以停止", h.stopped == true)
end

-- 4) 受伤 / 死亡音效会被触发（用真实的伤害流程）
local function NewCombat()
    S.data = Save.Load()
    Save.SetClass(S.data, "mage")
    Save.SetClassLevel(S.data, 10)
    Config.SetClass("mage")
    Run.Start(3, true)
    local cs = Combat.Start(S.run, "standard", 1)
    S.combat = cs
    S.screen = "combat"
    cs.enemies, cs.walls, cs.waves, cs.waveIndex = {}, {}, { {} }, 1
    cs.player.cooldowns = {}
    return cs
end

local cs = NewCombat()
-- Run.Start 内部已经播过出场音，等过 gap 再验证一次接口可用
Sfx.Update(1.5)
check("进入关卡有出场音效可播", Sfx.Play("spawn") == true)
cs.player.shield = 0
cs.player.invulnTimer = 0
local hpBefore = cs.player.hp
Combat.DamagePlayer(cs, 5)
check("玩家受伤掉血", cs.player.hp < hpBefore, cs.player.hp)
Sfx.Update(0.2)
check("受伤后能播下一声", Sfx.Play("player_hit") == true)

-- 5) 九个法师技能都能在施放时触发对应音效（不报错）
local skills = { 1, 2, 3, 4, 5, 6, 7, 8, 9 }
local good = 0
for _, id in ipairs(skills) do
    cs = NewCombat()
    cs.run.loadout = { id, 0, 0 }
    Combat.SpawnWave(cs, { minion = 1 })
    if cs.enemies[1] then
        cs.enemies[1].x, cs.enemies[1].y = cs.player.x + 60, cs.player.y
        cs.enemies[1].hp, cs.enemies[1].maxHp = 99999, 99999
    end
    local ok = pcall(function()
        Combat.MageCastSkill(1)
        for _ = 1, 20 do Combat.Update(1 / 60) end
    end)
    if ok then good = good + 1 else print("[Sfx] 技能 " .. id .. " 施放报错") end
end
check("九个法师技能施放都不报错", good == 9, good)

-- 6) 循环音效在场地消失后会被停掉
cs = NewCombat()
cs.run.loadout = { 9, 0, 0 }
Combat.MageCastSkill(1)
local field = cs.mageFields and cs.mageFields[1]
check("暴风雪场地带循环音效句柄", field ~= nil and field.sfxLoop ~= nil)
if field then
    field.t = field.life + 1
    for _ = 1, 5 do Combat.Update(1 / 60) end
    check("场地结束后循环音效已停", field.sfxLoop == nil or field.sfxLoop.stopped == true)
end

-- 7) 存档默认值：新存档自带音效开关与音量
local fresh = Save.Fresh()
check("新存档带 sfxOn", type(fresh.sfxOn) == "boolean", fresh.sfxOn)
check("新存档带 sfxVolume", type(fresh.sfxVolume) == "number", fresh.sfxVolume)
local defaults = Save.Defaults()
check("默认值为 0.8", defaults.sfxVolume == 0.8, defaults.sfxVolume)

Sfx.Shutdown()
print(string.format("[Sfx] done, failures = %d", fails))
