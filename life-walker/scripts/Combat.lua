-- Combat.lua — 房间战斗：剑客 / 小兵 / 精英 / Boss / 子弹 / 冲击波

local Config = require "Config"
local Run = require "Run"
local UI = require "UI"
local S = require "State"
local Save = require "Save"
local Guild = require "Guild"

---@class Enemy
---@field id string
---@field name string
---@field kind string
---@field behavior string
---@field x number
---@field y number
---@field radius number
---@field hp number
---@field maxHp number
---@field atk number
---@field speed number
---@field color number[]
---@field attackCd number
---@field shootCd number
---@field burstCd number
---@field crack integer
---@field crackTimer number
---@field hitFlash number
---@field slowTimer number
---@field enraged boolean
---@field bossSkillCd number
---@field chargeCd number
---@field chargeState string|nil
---@field chargeT number
---@field chargeDirX number
---@field chargeDirY number
---@field chargeHit boolean
---@field summoned1 boolean
---@field summoned2 boolean

---@class Bullet
---@field x number
---@field y number
---@field vx number
---@field vy number
---@field r number
---@field dmg number
---@field life number
---@field color number[]
---@field segments table<number, boolean>|nil
---@field segCount integer|nil
---@field maxR number|nil
---@field speed number|nil
---@field hit boolean|nil
---@field shock boolean|nil

---@class Shockwave
---@field x number
---@field y number
---@field r number
---@field maxR number
---@field speed number
---@field dmg number
---@field hit boolean

---@class FloatText
---@field x number
---@field y number
---@field text string
---@field color number[]
---@field t number
---@field life number
---@field size number

---@class Particle
---@field x number
---@field y number
---@field vx number
---@field vy number
---@field r number
---@field color number[]
---@field t number
---@field life number

---@class CombatState
---@field run RunState
---@field roomType string
---@field step integer
---@field player PlayerState
---@field enemies Enemy[]
---@field bullets Bullet[]
---@field walls table[]
---@field waves table
---@field waveIndex integer
---@field waveDelay number
---@field cleared boolean
---@field clearTimer number
---@field bossKilled boolean
---@field pendingHits table
---@field dash any
---@field effects Particle[]
---@field texts FloatText[]
---@field time number
---@field shake number
---@field facing number
---@field attackFlash number
--- swordHeartTimer number
--- showBuffs boolean
---@field buttons any[]
---@field attackButton any | nil
---@field joystick any | nil

local Combat = {}

local WORLD_W = Run.WORLD_W
local WORLD_H = Run.WORLD_H

-- 屏幕右下角的动作键（位置可被“按键布局”改写，见 CtrlPos）
local ACTION_BUTTONS = {
    { id = "attack", x = 1186, y = 626, r = 48, key = "SPACE", kind = "attack" },
    { id = "skill1", x = 1080, y = 624, r = 36, key = "J", kind = "skill", slot = 1 },
    { id = "skill2", x = 1110, y = 526, r = 36, key = "K", kind = "skill", slot = 2 },
    { id = "skill3", x = 1202, y = 514, r = 32, key = "L", kind = "skill", slot = 3 },
}

-- 当前镜头偏移（世界 -> 设计坐标）
local function CameraPos(cs)
    local camX = cs.player.x - S.designW / 2
    local camY = cs.player.y - S.designH / 2
    if WORLD_W <= S.designW then
        camX = (WORLD_W - S.designW) / 2
    else
        camX = Config.Clamp(camX, 0, WORLD_W - S.designW)
    end
    if WORLD_H <= S.designH then
        camY = (WORLD_H - S.designH) / 2
    else
        camY = Config.Clamp(camY, 0, WORLD_H - S.designH)
    end
    return camX, camY
end

local function Dist(x1, y1, x2, y2)
    local dx = x2 - x1
    local dy = y2 - y1
    return math.sqrt(dx * dx + dy * dy)
end

local function AngleDiff(a, b)
    local d = (a - b + math.pi) % (math.pi * 2) - math.pi
    return math.abs(d)
end

-- 冲刺/闪避方向：有摇杆或键盘输入时朝输入方向，否则用面朝方向
-- 返回 dirx, diry, angle, hasInput
local function DashDir(cs)
    local ix, iy = S.input.x, S.input.y
    local len = math.sqrt(ix * ix + iy * iy)
    if len > 0.25 then
        return ix / len, iy / len, math.atan(iy, ix), true
    end
    return math.cos(cs.facing), math.sin(cs.facing), cs.facing, false
end

-- ---------------------------------------------------------------- 专属强化参数
-- flags 由 Run.GrantBuff 累加，key 不存在时按 0 处理
local function F(p, key)
    return p.flags and p.flags[key] or 0
end

local function IntentMax(p)
    local m = 5 + math.floor(F(p, "intentCapDelta"))
    if m < 1 then m = 1 end
    return m
end

local function AddIntent(p, n)
    p.intent = math.min(IntentMax(p), p.intent + math.floor(n))
    p.intentTimer = 5.0
end

-- 职业与资源（剑客=剑意，枪客=枪势；统一存在 p.intent 里）
local function IsSpear()
    return Config.PlayerClass == "spearman"
end

local function IsRanger()
    return Config.PlayerClass == "ranger"
end

local function IsMage()
    return Config.PlayerClass == "mage"
end

local function IsRanged()
    return IsRanger() or IsMage()
end

local SpawnAfterimage -- 前向声明（各职业技能都会调用）

local function ResourceMax(p)
    if IsSpear() then
        return (Config.Class().resourceMax or 3) + math.floor(F(p, "momentumMax"))
    end
    if IsRanger() then
        return (Config.Class().resourceMax or 3) + math.floor(F(p, "dodgeCap"))
    end
    if IsMage() then return 0 end
    return IntentMax(p)
end

local function AddMomentum(p, n)
    p.intent = math.min(ResourceMax(p), p.intent + math.floor(n))
    p.intentTimer = 5.0
end

-- 受“枪势获取速度降低”影响时按概率少给层数
local function GainMomentum(p, n)
    local chance = 1 - math.min(0.9, F(p, "momentumGainMul"))
    local got = 0
    for _ = 1, n do
        if chance >= 0.999 or math.random() < chance then got = got + 1 end
    end
    AddMomentum(p, got)
    return got
end

-- 每损失 10% 生命 +5% 攻击（狂剑士），最多 50%
local function MissingHpBonus(p)
    if F(p, "berserk") <= 0 then return 0 end
    local missing = 1 - p.hp / math.max(1, p.maxHp)
    return math.min(0.5, math.floor(missing * 10 + 1e-4) * 0.05)
end

local function DamageMul(cs, isSkill)
    local p = cs.player
    local mul = 1 + F(p, "allDmgPct") + MissingHpBonus(p)
    if isSkill and cs.parryDmgTimer and cs.parryDmgTimer > 0 then
        mul = mul + F(p, "parryDmgBuff")
    end
    if (p.weakenTimer or 0) > 0 then mul = mul * 0.8 end
    return mul
end

-- 负面叠层上限：武链共生/三态洞悉会压低异种负面
local function DebuffCap(p, kind)
    local cap = 3
    if kind == "crack" or kind == "hunt" then cap = 5 end
    if IsSpear() and kind == "stagger" then cap = 2 end
    if F(p, "chainSymbiosis") > 0 then cap = math.floor(cap / 2) end
    if F(p, "insight") > 0 and kind ~= "crack" then cap = math.min(cap, 2) end
    if F(p, "debuffCap2") > 0 and kind ~= "crack" then cap = math.min(cap, 2) end
    return math.max(1, cap)
end

local function CrackCap(cs)
    local p = cs.player
    local cap = DebuffCap(p, "crack")
    if (cs.crackCapTimer or 0) > 0 then cap = cap + math.floor(F(p, "parryCrackCap")) end
    if cs.swordHeartTimer > 0 then cap = cap + math.floor(F(p, "stanceCrackCap")) end
    return cap
end

local function ExtendCrack(e, secs)
    if e.crack and e.crack > 0 then
        e.crackTimer = math.max(e.crackTimer or 0, 0) + secs
    end
end

local function AddText(cs, x, y, text, color, size)
    cs.texts[#cs.texts + 1] = { x = x, y = y, text = text, color = color, t = 0, life = 0.95, size = size or 18 }
end

-- 读取设置项（存档里没有就用默认值）
local function Opt(key, default)
    local d = S.data
    if type(d) ~= "table" then return default end
    local v = d[key]
    if v == nil then return default end
    return v
end

-- 伤害数字：完整 / 简化（更小更淡）/ 关闭
local function DmgText(cs, x, y, text, color, size, crit)
    local mode = Opt("damageText", "full")
    if mode == "off" then return end
    if mode == "simple" then
        local c = color
        if crit then c = color end
        AddText(cs, x, y, text, { c[1], c[2], c[3], 190 }, math.floor((size or 18) * 0.75))
    else
        AddText(cs, x, y, text, color, size)
    end
end

local function AddParticles(cs, x, y, color, count)
    if Opt("lowQuality", false) then count = math.max(1, math.floor(count * 0.35)) end
    for i = 1, count do
        local a = math.random() * math.pi * 2
        local sp = 40 + math.random() * 160
        cs.effects[#cs.effects + 1] = {
            x = x, y = y, vx = math.cos(a) * sp, vy = math.sin(a) * sp,
            r = 2 + math.random() * 4, color = color, t = 0, life = 0.35 + math.random() * 0.35,
        }
    end
end

-- 挥砍弧线 / 扩散环 / 冲刺残影：用于给“有伤害但看不见”的效果补视觉
local function AddSlash(cs, x, y, facing, range, arc, color, width)
    cs.slashes = cs.slashes or {}
    cs.slashes[#cs.slashes + 1] = {
        x = x, y = y, facing = facing, range = range, arc = arc,
        t = 0, life = 0.20, color = color or { 210, 238, 255 }, width = width or 6,
    }
end

local function AddRing(cs, x, y, maxR, color, life, width)
    cs.rings = cs.rings or {}
    cs.rings[#cs.rings + 1] = {
        x = x, y = y, maxR = maxR, t = 0, life = life or 0.32,
        color = color or { 160, 225, 255 }, width = width or 5,
    }
end

local function AddTrail(cs, x, y, color, radius)
    if Opt("lowQuality", false) then return end
    cs.trails = cs.trails or {}
    cs.trails[#cs.trails + 1] = {
        x = x, y = y, t = 0, life = 0.22, color = color or { 120, 200, 255 },
        r = radius or 13,
    }
end

-- 技能范围提示：释放瞬间按真实判定范围画一次轮廓，随后淡出。
-- kind = "sector"(扇形) / "circle"(圆形) / "corridor"(直线通道) / "line"(两点连线)
local function AddTelegraph(cs, o)
    cs.telegraphs = cs.telegraphs or {}
    o.t = 0
    o.life = o.life or 0.42
    o.color = o.color or { 170, 225, 255 }
    cs.telegraphs[#cs.telegraphs + 1] = o
end

-- 闪电折线（闪电链 / 雷击术）
local function AddBolt(cs, x1, y1, x2, y2, color, life)
    cs.bolts = cs.bolts or {}
    local d = Dist(x1, y1, x2, y2)
    if d < 1 then return end
    local nx, ny = -(y2 - y1) / d, (x2 - x1) / d
    local seg = math.max(3, math.floor(d / 26))
    local pts = {}
    for i = 0, seg do
        local k = i / seg
        local jitter = 0
        if i > 0 and i < seg then jitter = (math.random() - 0.5) * math.min(26, d * 0.28) end
        pts[#pts + 1] = {
            x = x1 + (x2 - x1) * k + nx * jitter,
            y = y1 + (y2 - y1) * k + ny * jitter,
        }
    end
    cs.bolts[#cs.bolts + 1] = {
        pts = pts, t = 0, life = life or 0.2,
        color = color or { 255, 235, 140 },
    }
end

-- 技能自动瞄准：在 range 内、朝向锥（默认 ±80°）里挑最近的敌人并把朝向转过去，
-- 避免“明明怪在旁边却空挥”。返回锁定的目标。
local function AimAt(cs, range, maxAngle)
    local p = cs.player
    if cs.aimLock then return nil end   -- 玩家长按瞄准过：尊重手动方向，不自动转头
    local limit = maxAngle or math.rad(80)
    local best, bd = nil, range
    for _, e in ipairs(cs.enemies) do
        if (e.hp or 0) > 0 then
            local d = Dist(p.x, p.y, e.x, e.y) - (e.radius or 0)
            if d <= bd then
                local a = math.atan(e.y - p.y, e.x - p.x)
                if math.abs(AngleDiff(a, cs.facing)) <= limit then
                    best, bd = e, d
                end
            end
        end
    end
    if best then
        cs.facing = math.atan(best.y - p.y, best.x - p.x)
    end
    return best
end

local function RectsOverlap(a, b)
    return a.x < b.x + b.w and a.x + a.w > b.x and a.y < b.y + b.h and a.y + a.h > b.y
end

-- ---------------------------------------------------------------- 物理负面 / 连携
local function AddCrack(cs, e, n)
    if F(cs.player, "chainSymbiosis") > 0 then return end -- 原生挫裂被封印
    local before = e.crack or 0
    e.crack = math.min(CrackCap(cs), before + n)
    e.crackTimer = 4.0
    if e.crack > before then
        -- 挫裂：碎片粒子 + 飘字 + 橙色冲击环 + 目标短暂高亮，触发看得见
        AddParticles(cs, e.x, e.y, { 255, 170, 90 }, 4)
        AddText(cs, e.x, e.y - (e.radius or 14) - 34,
            "挫裂 " .. e.crack, { 255, 178, 96 }, 15)
        AddRing(cs, e.x, e.y, (e.radius or 14) + 16, { 255, 170, 90 }, 0.22, 3)
        e.crackFlash = 0.18
    end
end

local function AddStagger(cs, e, n)
    local p = cs.player
    local before = e.stagger or 0
    e.stagger = math.min(DebuffCap(p, "stagger"), before + n)
    if IsSpear() then
        e.staggerTimer = 3.0 + F(p, "staggerDur")
    else
        e.staggerTimer = F(p, "staggerShort") > 0 and 2.0 or 4.0
    end
    if e.stagger > before then AddParticles(cs, e.x, e.y, { 130, 215, 255 }, 2) end
end

local function AddHunt(cs, e, n)
    local p = cs.player
    local before = e.hunt or 0
    e.hunt = math.min(DebuffCap(p, "hunt"), before + n)
    e.huntTimer = 6.0 * (1 - math.min(0.5, F(p, "huntDurMul")))
    if e.hunt > before then AddParticles(cs, e.x, e.y, { 195, 150, 255 }, 2) end
end

-- ---------------------------------------------------------------- 元素与状态
local function SlowEnemy(e, seconds, pct)
    e.slowTimer = math.max(e.slowTimer or 0, seconds)
    e.slowPct = math.max(e.slowPct or 0, pct or 0.4)
end

local function FreezeMul(cs)
    local p = cs.player
    local mul = 1 + F(p, "freezeDur")
    if cs.mageSpec == "ice" then mul = mul + 0.5 end
    return mul
end

local function ApplyBurn(cs, e, dur, dps)
    local p = cs.player
    if F(p, "bakeMaster") > 0 then
        e.burnStacks = math.min(5, (e.burnStacks or 0) + 1)
    end
    e.burnTimer = math.max(e.burnTimer or 0, dur)
    e.burnDps = math.max(e.burnDps or 0, dps + (e.burnStacks or 0) * p.atk * 0.05)
end

local function ApplyFreeze(cs, e, dur)
    e.freezeTimer = math.max(e.freezeTimer or 0, dur * FreezeMul(cs))
end

local function ElemMul(cs, element)
    local p = cs.player
    local mul = 1 + F(p, "elemPct")
    if element == "fire" then
        mul = mul + F(p, "firePct")
    elseif element == "ice" then
        mul = mul + F(p, "icePct")
    elseif element == "bolt" then
        mul = mul + F(p, "boltPct")
    end
    if cs.mageSpec == "resonance" then
        mul = mul + 0.10
    elseif cs.mageSpec == element and element == "fire" then
        mul = mul + 0.25
    end
    if F(p, "iceArmor") > 0 and element == "ice" and p.shield > 0 then
        mul = mul + F(p, "iceArmor")
    end
    if (cs.resonanceTimer or 0) > 0 then
        mul = mul + (cs.resonanceStacks or 0) * 0.05
    end
    if cs.quizElement == element then
        mul = mul + (cs.quizStacks or 0) * 0.2
    end
    if (cs.overloadTimer or 0) > 0 then mul = mul + 0.4 end
    if (cs.chaosTimer or 0) > 0 then mul = mul + 0.3 end
    if element == "fire" and F(p, "bakeMaster") > 0 then mul = mul * 0.5 end
    return mul
end

local function ApplyElementHit(cs, e, element, skillId)
    local p = cs.player
    if element == "fire" then
        cs.lastElement = "fire"
        if (e.freezeTimer or 0) > 0 then
            local melt = 1.2 * ((F(p, "meltDouble") > 0) and 2 or 1)
            Combat.HitEnemy(cs, e, p.atk * melt, false, true, false, "combo")
            AddText(cs, e.x, e.y - e.radius - 24, "融化", { 255, 170, 90 }, 18)
            e.freezeTimer = 0
        end
        ApplyBurn(cs, e, 3 + F(p, "burnDur"), p.atk * 0.2)
        if F(p, "burnShield") > 0 then
            p.shield = math.min(p.maxShield * 1.5, p.shield + p.atk * F(p, "burnShield"))
        end
        if F(p, "emberOnFire") > 0 then
            -- 余烬最多同时存在 6 片：火系多段命中时不再无限叠
            local emberCount = 0
            for _, f in ipairs(cs.mageFields) do
                if f.ember then emberCount = emberCount + 1 end
            end
            if emberCount >= 6 then
                for i = 1, #cs.mageFields do
                    if cs.mageFields[i].ember then
                        table.remove(cs.mageFields, i)
                        break
                    end
                end
            end
            cs.mageFields[#cs.mageFields + 1] = {
                x = e.x, y = e.y, r = 60 * (1 + F(p, "emberRadius")),
                t = 0, life = 2, tick = 0, dmg = p.atk * 0.12, slow = 0,
                element = "fire", ember = true,
            }
        end
        if F(p, "burnSpread") > 0 then
            local r = 24 + F(p, "burnSpread") * 32
            for _, o in ipairs(cs.enemies) do
                if o ~= e and Dist(e.x, e.y, o.x, o.y) < r then
                    ApplyBurn(cs, o, 2, p.atk * 0.1)
                end
            end
        end
    elseif element == "ice" then
        if (e.burnTimer or 0) > 0 then
            ApplyFreeze(cs, e, 3)
            AddText(cs, e.x, e.y - e.radius - 24, "蒸发", { 150, 220, 255 }, 18)
            for _, o in ipairs(cs.enemies) do
                if o ~= e and Dist(e.x, e.y, o.x, o.y) < 100 then
                    ApplyBurn(cs, o, 2, p.atk * 0.1)
                end
            end
        else
            if F(p, "absoluteZero") > 0 and (e.freezeTimer or 0) > 0 then
                Combat.HitEnemy(cs, e, p.atk, false, true, true, "combo")
            end
            ApplyFreeze(cs, e, 1.5)
            SlowEnemy(e, 1.5, 0.5 + F(p, "slowBonus"))
        end
        if F(p, "blizzardIce") > 0 then
            e.iceVuln = 1 + F(p, "blizzardIce")
        end
    elseif element == "bolt" then
        local states = 0
        if (e.burnTimer or 0) > 0 then states = states + 1 end
        if (e.freezeTimer or 0) > 0 then states = states + 1 end
        if states > 0 then
            local bonus = 0.3 * states
            if cs.mageSpec == "resonance" then bonus = bonus + F(p, "elemComboPct") end
            Combat.HitEnemy(cs, e, p.atk * bonus, true, true, false, "combo")
            AddText(cs, e.x, e.y - e.radius - 24, "过载", { 255, 230, 120 }, 18)
        end
    end
end

local function HealPlayer(p, amount)
    if (p.necrosisTimer or 0) > 0 then amount = amount * 0.5 end
    p.hp = math.min(p.maxHp, p.hp + amount)
    return amount
end

local function InBoltField(cs)
    for _, f in ipairs(cs.mageFields or {}) do
        if f.element == "bolt" and Dist(cs.player.x, cs.player.y, f.x, f.y) < f.r then
            return true
        end
    end
    return false
end

local function NearestEnemy(cs, x, y, maxDist)
    local best, bd = nil, maxDist or 99999
    for _, e in ipairs(cs.enemies) do
        local d = Dist(x, y, e.x, e.y)
        if d < bd then best, bd = e, d end
    end
    return best, bd
end

-- 离“瞄准落点”最近的敌人（长按瞄准时按落点选目标）
local function NearestEnemyTo(cs, x, y, maxDist)
    local best, bd = nil, maxDist or 99999
    for _, e in ipairs(cs.enemies) do
        local d = Dist(x, y, e.x, e.y) - (e.radius or 0)
        if d < bd then best, bd = e, d end
    end
    return best, bd
end

-- 远程弹道（箭矢 / 元素弹）
local function SpawnProj(cs, o)
    cs.projs[#cs.projs + 1] = {
        x = o.x, y = o.y, vx = o.vx, vy = o.vy,
        r = o.r or 9, life = o.life or 2.0,
        dmg = o.dmg, isSkill = o.isSkill,
        pierce = o.pierce or 0, hit = {},
        kind = o.kind or "arrow",
        element = o.element, skill = o.skill,
        hunt = o.hunt or 0, slow = o.slow,
        combo = o.combo, crit = o.crit,
        aoe = o.aoe, aoePct = o.aoePct,
        color = o.color or { 235, 245, 255 },
        splash = o.splash, splashPct = o.splashPct,
        lifesteal = o.lifesteal,
        boom = o.boom,
        execute = o.execute,
    }
end

-- 武链共生：攻击时按概率补上另外两类物理负面（含被封禁的原生挫裂）
local function ForceCrack(cs, e, n)
    local p = cs.player
    e.crack = math.min(DebuffCap(p, "crack"), (e.crack or 0) + n)
    e.crackTimer = 4.0
end

local function SymbiosisRoll(cs, e)
    local p = cs.player
    local chance = F(p, "debuffChance")
    if chance <= 0 then return end
    if math.random() >= chance then return end
    local kinds = { "crack", "stagger", "hunt" }
    local a = math.random(1, 3)
    local b = a % 3 + 1
    for _, k in ipairs({ kinds[a], kinds[b] }) do
        if k == "crack" then
            ForceCrack(cs, e, 1)
        elseif k == "stagger" then
            AddStagger(cs, e, 1)
        else
            AddHunt(cs, e, 1)
        end
    end
end

---@param cs any
---@param e any
---@param pairKind string|nil 指定连携类型（千影碎击：粉碎）
---@return boolean
local function TryCombo(cs, e, pairKind)
    local p = cs.player
    if F(p, "comboMaster") <= 0 and pairKind == nil then return false end
    local crack = e.crack or 0
    local stag = e.stagger or 0
    local hunt = e.hunt or 0
    local mis = F(p, "misalign") > 0
    local kind = pairKind

    if not kind then
        if F(p, "comboAll") > 0 then
            if stag > 0 and crack > 0 then
                kind = "震荡"
            elseif stag > 0 and hunt > 0 then
                kind = "追猎"
            elseif crack > 0 and hunt > 0 then
                kind = "震荡"
            end
        elseif crack > 0 and stag > 0 then
            kind = mis and "追猎" or "粉碎"
        elseif crack > 0 and hunt > 0 then
            kind = mis and "粉碎" or "震荡"
        elseif stag > 0 and hunt > 0 then
            kind = mis and "震荡" or "追猎"
        end
    end
    if not kind then return false end
    if kind == "粉碎" and crack <= 0 then return false end
    cs.comboCount = (cs.comboCount or 0) + 1

    local mult = 1.0 + F(p, "comboDmg")
    if mis and pairKind == nil then mult = mult * 0.6 end
    if cs.comboWeakTimer and cs.comboWeakTimer > 0 then mult = mult * 0.65 end

    local dmg = p.atk * mult
    local col = { 255, 214, 120 }
    if kind == "粉碎" then
        dmg = dmg * 1.2
        AddText(cs, e.x, e.y - e.radius - 26, "粉碎", col, 20)
        AddRing(cs, e.x, e.y, e.radius + 42, { 255, 205, 120 }, 0.3, 7)
        AddParticles(cs, e.x, e.y, { 255, 210, 130 }, 10)
        local burst = F(p, "comboBurst")
        if burst > 0 then
            for i = #cs.enemies, 1, -1 do
                local other = cs.enemies[i]
                if other and other ~= e and Dist(e.x, e.y, other.x, other.y) < 100 then
                    Combat.HitEnemy(cs, other, p.atk * burst, false, true, false, "combo")
                end
            end
        end
    elseif kind == "震荡" then
        dmg = dmg * 0.9
        col = { 150, 220, 255 }
        AddText(cs, e.x, e.y - e.radius - 26, "震荡", col, 20)
        local spreadR = 90 + F(p, "spreadAdd") * 32
        AddRing(cs, e.x, e.y, spreadR, { 150, 220, 255 }, 0.3, 6)
        for i = #cs.enemies, 1, -1 do
            local other = cs.enemies[i]
            if other and other ~= e and Dist(e.x, e.y, other.x, other.y) < spreadR then
                Combat.HitEnemy(cs, other, p.atk * 0.6, false, true, false, "combo")
                if F(p, "spreadMul") <= 0 then AddCrack(cs, other, 1) end
                if F(p, "comboHuntChance") > 0 and math.random() < F(p, "comboHuntChance") then
                    AddHunt(cs, other, 1)
                end
            end
        end
    else
        dmg = dmg * 0.8
        col = { 190, 255, 200 }
        AddText(cs, e.x, e.y - e.radius - 26, "追猎", col, 20)
        AddRing(cs, p.x, p.y, 55, { 190, 255, 200 }, 0.26, 5)
        AddParticles(cs, p.x, p.y, { 190, 255, 200 }, 6)
        for id, v in pairs(p.cooldowns) do
            if v > 0 then p.cooldowns[id] = math.max(0, v - 1.0) end
        end
    end

    Combat.HitEnemy(cs, e, dmg, false, true, false, "combo")

    -- 消耗触发的负面
    if e.crack and e.crack > 0 then e.crack = math.max(0, e.crack - 1) end
    if kind == "粉碎" or (e.stagger or 0) > 0 then e.stagger = 0 end
    if (e.hunt or 0) > 0 then e.hunt = 0 end
    e.staggerTimer, e.huntTimer = 0, 0

    -- Debuff 回响：向周围扩散负面，并让接下来 5 秒技能冷却变长
    if F(p, "comboEcho") > 0 then
        for _, other in ipairs(cs.enemies) do
            if other ~= e and Dist(e.x, e.y, other.x, other.y) < 120 then
                if math.random() < 0.5 then AddStagger(cs, other, 1) else AddHunt(cs, other, 1) end
            end
        end
        cs.comboEchoPenalty = 5.0
    end
    return true
end


local function GenerateWalls(cs)
    local walls = {}
    local count = math.random(8, 10)
    local gap = 105
    for _ = 1, count do
        for _ = 1, 120 do
            local w = math.random(50, 95)
            local h = math.random(35, 70)
            local x = math.random(60, WORLD_W - 60 - w)
            local y = math.random(150, WORLD_H - 80 - h)
            local rect = { x = x, y = y, w = w, h = h }
            local cx = x + w / 2
            local cy = y + h / 2
            local ok = Dist(cx, cy, WORLD_W / 2, WORLD_H / 2) > 170
            if ok then
                for _, o in ipairs(walls) do
                    local dx = math.max(0, math.max(rect.x - (o.x + o.w), o.x - (rect.x + rect.w)))
                    local dy = math.max(0, math.max(rect.y - (o.y + o.h), o.y - (rect.y + rect.h)))
                    if dx * dx + dy * dy < gap * gap then
                        ok = false
                        break
                    end
                end
            end
            if ok then
                walls[#walls + 1] = rect
                break
            end
        end
    end
    cs.walls = walls
end

-- 圆 vs 矩形推出
local function ResolveCircleWalls(cs, x, y, r)
    for _ = 1, 2 do
        for _, w in ipairs(cs.walls) do
            local cx = Config.Clamp(x, w.x, w.x + w.w)
            local cy = Config.Clamp(y, w.y, w.y + w.h)
            local dx = x - cx
            local dy = y - cy
            local d2 = dx * dx + dy * dy
            if d2 < r * r then
                if d2 > 0.0001 then
                    local d = math.sqrt(d2)
                    local push = r - d
                    x = x + dx / d * push
                    y = y + dy / d * push
                else
                                        local dLeft = x - w.x
                    local dRight = w.x + w.w - x
                    local dTop = y - w.y
                    local dBottom = w.y + w.h - y
                    local m = math.min(dLeft, dRight, dTop, dBottom)
                    if m == dLeft then
                        x = w.x - r
                    elseif m == dRight then
                        x = w.x + w.w + r
                    elseif m == dTop then
                        y = w.y - r
                    else
                        y = w.y + w.h + r
                    end
                end
            end
        end
    end
    return x, y
end

local function PointInWalls(cs, x, y)
    for _, w in ipairs(cs.walls) do
        if x > w.x and x < w.x + w.w and y > w.y and y < w.y + w.h then
            return true
        end
    end
    return false
end

local function CircleHitsWalls(cs, x, y, r)
    for _, w in ipairs(cs.walls) do
        local cx = Config.Clamp(x, w.x, w.x + w.w)
        local cy = Config.Clamp(y, w.y, w.y + w.h)
        local dx = x - cx
        local dy = y - cy
        if dx * dx + dy * dy < r * r then
            return true
        end
    end
    return false
end

-- 冲击波圆环是否碰到墙体（碰到就消散，不能穿墙）
-- 从冲击波中心到圆周点的射线是否被墙挡住
local function LineHitsWall(cs, x0, y0, x1, y1)
    local steps = 6
    for s = 1, steps do
        local t = s / steps
        if PointInWalls(cs, x0 + (x1 - x0) * t, y0 + (y1 - y0) * t) then
            return true
        end
    end
    return false
end

local function MakeRingSegments(n)
    local segs = {}
    for i = 1, n do segs[i] = true end
    return segs
end

function Combat.Start(run, roomType, step)
    local p = run.player
    p.x = WORLD_W / 2
    p.y = WORLD_H / 2
    p.attackTimer = 0
    p.attackQueued = false
    p.intent = 0
    p.intentTimer = 0
    p.parryTimer = 0
    p.parryLeft = 0
    p.noDamageTimer = 0
    p.infectTimer = 0
    p.infectDps = 0
    p.necrosisTimer = 0
    p.weakenTimer = 0
    p.decayTimer = 0
    p.charges = {}
    p.freeCharges = {}
    -- 脱战回盾：每个房间开局满盾
    p.shield = p.maxShield
    p.cooldowns = {}
    for i = 1, 3 do
        local id = run.loadout[i]
        if id then p.cooldowns[id] = 0 end
    end

    ---@type CombatState
    local cs = {
        run = run,
        roomType = roomType,
        step = step,
        player = p,
        enemies = {},
        bullets = {},
        walls = {},
        waves = Config.RoomWaves[roomType] or Config.RoomWaves.standard,
        waveIndex = 0,
        waveDelay = 0.5,
        cleared = false,
        clearTimer = 0,
        bossKilled = false,
        pendingHits = {},
        dash = nil,
        effects = {},
        texts = {},
        time = 0,
        shake = 0,
        facing = 0,
        attackFlash = 0,
        swordHeartTimer = 0,
        showBuffs = false,
        paused = false,
        buttons = {},
        joystick = nil,
        windWaves = {},
        phantoms = {},
        slashes = {},
        rings = {},
        trails = {},
        spearShots = {},
        spearFields = {},
        spearCombo = 0,
        spearBuffTimer = 0,
        spearBuffHits = 0,
        spearCastAsTimer = 0,
        spearMsTimer = 0,
        next3aTimer = 0,
        guardTimer = 0,
        guardUsedMomentum = false,
        guardReflect = 0,
        guardNextMomentum = 0,
        momentumDebuffTimer = 0,
        chargeStacks = 0,
        killAtkStacks = 0,
        playerHitFlash = 0,
        phantomCount = 0,
        waveCount = 0,
        healTextTimer = 0,
        comboEchoPenalty = 0,
        shieldFlash = 0,
        buffPage = 1,
        buffDetail = nil,
        parryDmgTimer = 0,
        parryLifestealTimer = 0,
        crackCapTimer = 0,
        storedDebuffs = 0,
        storedHits = 0,
        lastHitSrc = nil,
        tripleSegments = 0,
        nextBasicIntent = 0,
        stanceAlive = false,
        projs = {},
        mageFields = {},
        rangerTraps = {},
        hazardFields = {},
        telegraphs = {},
        bolts = {},
        snipeCharge = nil,
        rapidTimer = 0,
        rapidStacks = 0,
        rangerCrit = 0,
        rangerSwap = 0,
        mageSpec = nil,
        resonanceStacks = 0,
        resonanceTimer = 0,
        overloadTimer = 0,
        chaosTimer = 0,
        quizElement = nil,
        quizStacks = 0,
        lastSpellElement = nil,
        spreadMul = 1,
    }
    -- 法师元素亲和：按出战技能配比决定专精
    if IsMage() then
        local fire, ice, bolt = 0, 0, 0
        for _, sid in ipairs(run.loadout or {}) do
            local sk = Config.SkillByID(sid)
            if sk and sk.element == "fire" then fire = fire + 1
            elseif sk and sk.element == "ice" then ice = ice + 1
            elseif sk and sk.element == "bolt" then bolt = bolt + 1 end
        end
        if fire == 3 then cs.mageSpec = "fire"
        elseif ice == 3 then cs.mageSpec = "ice"
        elseif bolt == 3 then cs.mageSpec = "bolt"
        elseif fire >= 1 and ice >= 1 and bolt >= 1 then cs.mageSpec = "resonance" end
    end
    S.combat = cs
    if roomType == "raid" then
        cs.guildRaid = true
        cs.raidDamage = 0
        cs.raidBossMax = 0
        cs.raidFinished = false
    end
    GenerateWalls(cs)
    Combat.CreateControls(cs)
    Combat.SpawnWave(cs, cs.waves[1])
    cs.waveIndex = 1
    return cs
end

-- ---------------------------------------------------------------- 自绘虚拟摇杆
-- 不再依赖 urhox-libs/UI/VirtualControls：那个库会额外创建一个 NanoVG 上下文、
-- 并把同一个字体再加载一次，在手机测试端会让引擎报错（闪一个 Start() failed）。
-- 这里自己实现，逻辑更简单，Y 轴方向也和键盘保持一致。
local JOY_BASE_X = 140
local JOY_BASE_Y = 578
local JOY_R = 74

local function JoystickApply(js, x, y)
    local dx, dy = x - js.baseX, y - js.baseY
    local len = math.sqrt(dx * dx + dy * dy)
    if len > js.radius and len > 0 then
        local over = len - js.radius
        if js.follow then
            -- 拖尾跟随：基座朝手指方向挪，摇杆头始终留在边缘，手指拖远了也不会脱手
            js.baseX = js.baseX + dx / len * over
            js.baseY = js.baseY + dy / len * over
            js.baseX = math.max(js.radius, math.min(Config.DESIGN_W - js.radius, js.baseX))
            js.baseY = math.max(js.radius, math.min(Config.DESIGN_H - js.radius, js.baseY))
            dx, dy = x - js.baseX, y - js.baseY
            local l2 = math.sqrt(dx * dx + dy * dy)
            if l2 > js.radius and l2 > 0 then
                dx, dy = dx / l2 * js.radius, dy / l2 * js.radius
            end
        else
            dx, dy = dx / len * js.radius, dy / len * js.radius
        end
    end
    js.kx, js.ky = js.baseX + dx, js.baseY + dy
    local nx, ny = dx / js.radius, dy / js.radius
    -- 死区 + 次幂曲线，灵敏度在设置里可选：高=轻推就走 / 低=更稳
    local sens = Opt("joySensitivity", "mid")
    local dead = 0.06
    local curve = 0.65
    if sens == "high" then dead, curve = 0.035, 0.55
    elseif sens == "low" then dead, curve = 0.105, 0.78 end
    local mag = math.sqrt(nx * nx + ny * ny)
    if mag < dead then
        S.input.x = 0
        S.input.y = 0
        return
    end
    local shaped = mag ^ curve
    local k = shaped / mag
    S.input.x = nx * k
    S.input.y = ny * k
    if math.abs(S.input.x) < 0.04 then S.input.x = 0 end
    if math.abs(S.input.y) < 0.04 then S.input.y = 0 end
end

-- 按键布局（位置/大小可在设置里调整）：按 id 取当前值，没有就用默认值
local function CtrlPos(id, dx, dy, dr)
    local L = S.data and S.data.layout
    local e = type(L) == "table" and L[id] or nil
    if type(e) == "table" then
        return e.x or dx, e.y or dy, e.r or dr
    end
    return dx, dy, dr
end
Combat.CtrlPos = CtrlPos

-- 道具槽位：第一个的位置来自布局，其余向右排开
local function ItemSlot(i)
    local ix, iy, ir = CtrlPos("items", 1080, 420, 27)
    local gap = ir * 2 + 12
    return { x = ix + (i - 1) * gap, y = iy, r = ir }
end

function Combat.CreateControls(cs)
    local jx, jy, jr = CtrlPos("joy", JOY_BASE_X, JOY_BASE_Y, JOY_R)
    local data = S.data or {}
    cs.joystick = {
        anchorX = jx, anchorY = jy,      -- 固定位置 / 浮动模式的待机提示位置
        baseX = jx, baseY = jy,          -- 当前基座（浮动/拖尾时会移动）
        kx = jx, ky = jy,
        radius = jr,
        active = false,
        touchId = nil,                   -- 正在控制摇杆的那根手指（多指隔离）
        mode = (data.joyMode == "fixed") and "fixed" or "float",
        follow = data.joyFollow ~= false,
    }
    S.input.x = 0
    S.input.y = 0
end

-- 浮动模式下，按下即定位的激活区域：左半屏、避开顶部 HUD
local FLOAT_ZONE_MAX_X = Config.DESIGN_W * 0.5
local FLOAT_ZONE_MIN_Y = 170

-- 触屏 / 鼠标 -> 摇杆，x、y 是设计坐标；id 是 TouchID（鼠标为 nil）。
-- 返回 true 表示这次输入被摇杆吃掉。只有"按下时抓住摇杆的那根手指"能控制它，
-- 否则右手点技能会打断左手摇杆的方向。
function Combat.JoystickPointer(phase, x, y, id)
    local cs = S.combat
    if not cs or not cs.joystick then return false end
    if cs.showBuffs then return false end
    local js = cs.joystick
    if phase == "down" then
        if js.active then return false end   -- 已经有一根手指在控制摇杆
        if js.mode == "float" then
            -- 软追踪：按在哪里，摇杆就出现在哪里
            if x <= FLOAT_ZONE_MAX_X and y >= FLOAT_ZONE_MIN_Y then
                js.active = true
                js.touchId = id
                js.baseX = math.max(js.radius, math.min(Config.DESIGN_W - js.radius, x))
                js.baseY = math.max(js.radius, math.min(Config.DESIGN_H - js.radius, y))
                js.kx, js.ky = js.baseX, js.baseY
                S.input.x = 0
                S.input.y = 0
                return true
            end
            return false
        end
        local dx, dy = x - js.baseX, y - js.baseY
        -- 抓取范围放宽到 2.4 倍半径，手指稍微偏一点也能抓到
        local grab = js.radius * 2.4
        if dx * dx + dy * dy <= grab * grab then
            js.active = true
            js.touchId = id
            JoystickApply(js, x, y)
            return true
        end
    elseif phase == "move" then
        if js.active and js.touchId == id then
            JoystickApply(js, x, y)
            return true
        end
    elseif phase == "up" then
        if js.active and js.touchId == id then
            js.active = false
            js.touchId = nil
            -- 松手后回到待机位置（浮动模式回到锚点，拖尾偏移也一并复位）
            js.baseX = js.anchorX
            js.baseY = js.anchorY
            js.kx, js.ky = js.baseX, js.baseY
            S.input.x = 0
            S.input.y = 0
            return true
        end
    end
    return false
end

-- ---------------------------------------------------------------- 技能长按瞄准
-- 按住技能键进入瞄准（显示范围预览），松手释放；轻点仍然是自动瞄准
local AIM_HOLD = 0.22

-- 长按阈值可在设置里改（0.15 / 0.22 / 0.30）
local function AimHoldValue()
    local v = Opt("aimHold", AIM_HOLD)
    if type(v) ~= "number" then return AIM_HOLD end
    return v
end
local AIM_MOVE_EPS = 14
local AIM_DIR_DEADZONE = 10    -- 手指几乎没离开按键时，方向保持不变（避免抖）
local AIM_FULL_PULL = 120      -- 摇杆式选位：拖满 120px 到达最远落点
-- 取消施法框：位置和大小在「设置 → 按键布局」里拖（id = aim_cancel），中心 + 半径 = 宽 2r 高 1.2r
local AIM_CANCEL_DEFAULT = { 1170, 378, 80 }
local function AimCancelRect()
    local cx, cy, r = CtrlPos("aim_cancel",
        AIM_CANCEL_DEFAULT[1], AIM_CANCEL_DEFAULT[2], AIM_CANCEL_DEFAULT[3])
    return { x = cx - r, y = cy - r * 0.6, w = r * 2, h = r * 1.2 }
end
Combat.AimCancelRect = AimCancelRect

local function InAimCancel(x, y)
    local z = AimCancelRect()
    return x >= z.x and x <= z.x + z.w and y >= z.y and y <= z.y + z.h
end

function Combat.SkillReady(cs, id)
    local p = cs.player
    if (p.cooldowns[id] or 0) <= 0 then return true end
    if p.freeCharges and (p.freeCharges[id] or 0) > 0 then return true end
    if p.charges and (p.charges[id] or 0) > 0 then return true end
    return false
end

-- 选位技能最远落点：不超过角色自身的攻击范围
local function AimMaxRange(cs)
    local class = Config.Class()
    return class.basicRange * (1 + (cs.player.rangePct or 0))
end

local function AimUpdateTarget(cs, dx, dy)
    local aim = cs.aim
    if not aim then return end
    local p = cs.player
    local spec = aim.spec
    local ox, oy = dx - aim.bx, dy - aim.by
    local len = math.sqrt(ox * ox + oy * oy)
    -- “有没有真的拖动”一律相对按下的落点算：手指按在按键边缘时不会被误判成瞄准，
    -- 这样轻点仍然走智能施法（自动瞄准）
    local dragged = Dist(dx, dy, aim.sx, aim.sy) > AIM_DIR_DEADZONE

    if spec.mode == "dir" then
        -- 方向技能：以技能键为摇杆圆心 —— 手指从按键往上，技能就朝上
        if len > AIM_DIR_DEADZONE then
            aim.angle = math.atan(oy, ox)
        end
    else
        -- 选位技能：两种手感，设置里切换
        local maxR = math.min(spec.range or 9999, AimMaxRange(cs))
        local byButton = not (S.data and S.data.aimMode == "screen")
        local wx, wy
        if byButton then
            -- 技能键当摇杆：方向从按键算，拖动距离决定放多远
            if dragged and len > AIM_DIR_DEADZONE then
                local ang = math.atan(oy, ox)
                local pull = math.min(1, len / AIM_FULL_PULL)
                wx = p.x + math.cos(ang) * pull * maxR
                wy = p.y + math.sin(ang) * pull * maxR
            else
                wx, wy = p.x, p.y
            end
        else
            -- 屏幕落点：手指指哪放哪
            local camX, camY = CameraPos(cs)
            wx, wy = dx + camX, dy + camY
            local d = Dist(p.x, p.y, wx, wy)
            if d > maxR and d > 1 then
                local k = maxR / d
                wx = p.x + (wx - p.x) * k
                wy = p.y + (wy - p.y) * k
            end
        end
        aim.point = { x = wx, y = wy }
        aim.angle = math.atan(wy - p.y, wx - p.x)
    end

    if Dist(dx, dy, aim.sx, aim.sy) > AIM_MOVE_EPS then aim.moved = true end
    aim.fx, aim.fy = dx, dy
    aim.cancel = InAimCancel(dx, dy)
end

-- 返回 true 表示这次触摸被瞄准逻辑吃掉了（不要再走 UI.Click）
function Combat.AimPointer(phase, dx, dy, id)
    local cs = S.combat
    if S.screen ~= "combat" or not cs then return false end
    if cs.showBuffs or cs.paused then
        if phase == "up" and cs.aim then
            cs.aim = nil
            return true
        end
        return false
    end
    local aim = cs.aim
    if phase == "down" then
        -- 瞄准期间只认“按下技能键的那根手指”，别的手指（比如左手摇杆）必须放行，
        -- 否则一边瞄准一边就走不动了
        if aim then return aim.tid ~= nil and aim.tid == id end
        for _, b in ipairs(ACTION_BUTTONS) do
            if b.kind == "skill" then
                local sid = cs.run.loadout[b.slot]
                local spec = sid and Config.SkillAimOf(sid)
                if spec and Combat.SkillReady(cs, sid) then
                    local bx, by, br = CtrlPos(b.id, b.x, b.y, b.r)
                    local ddx, ddy = dx - bx, dy - by
                    if ddx * ddx + ddy * ddy <= (br + 16) * (br + 16) then
                        cs.aim = {
                            slot = b.slot, id = sid, spec = spec, tid = id,
                            t = 0, sx = dx, sy = dy, moved = false,
                            bx = bx, by = by,        -- 技能键圆心：摇杆式瞄准的原点
                            angle = cs.facing,
                            point = { x = cs.player.x, y = cs.player.y },
                            cancel = false,
                        }
                        AimUpdateTarget(cs, dx, dy)
                        return true
                    end
                end
            end
        end
        return false
    elseif phase == "move" then
        if not aim then return false end
        if id and aim.tid and id ~= aim.tid then return false end
        AimUpdateTarget(cs, dx, dy)
        return true
    elseif phase == "up" then
        if not aim then return false end
        if id and aim.tid and id ~= aim.tid then return false end
        cs.aim = nil
        if aim.cancel then
            -- 拖进取消区域松手：不放技能、也不吃冷却
            UI.SetToast("已取消施法", 0.8)
            return true
        end
        if aim.t >= AimHoldValue() or aim.moved then
            cs.facing = aim.angle
            cs.aimLock = true
            if aim.spec.mode == "point" then cs.aimPoint = aim.point end
        end
        Combat.CastSkill(aim.slot)
        cs.aimLock = nil
        cs.aimPoint = nil
        return true
    end
    return false
end

local function DrawJoystick(cs)
    local js = cs.joystick
    if not js then return end
    if not js.active then
        -- 待机：浮动模式只画一个很淡的提示圈，固定模式画完整摇杆
        local faint = js.mode == "float" and 38 or 85
        UI.Circle(js.anchorX, js.anchorY, js.radius,
            { 20, 18, 28, math.floor(faint * 0.30) }, { 150, 160, 190, faint }, 3)
        if js.mode ~= "float" then
            UI.Circle(js.anchorX, js.anchorY, 26,
                { 90, 130, 200, math.floor(faint * 0.65) },
                { 190, 215, 255, math.min(255, faint + 60) }, 3)
        end
        return
    end
    UI.Circle(js.baseX, js.baseY, js.radius,
        { 20, 18, 28, math.floor(160 * 0.30) }, { 150, 160, 190, 160 }, 3)
    UI.Circle(js.kx, js.ky, 26,
        { 90, 130, 200, math.floor(160 * 0.65) }, { 190, 215, 255, 220 }, 3)
end

function Combat.AttackCooldown(cs)
    local p = cs.player
    local as = p.attackSpeed
    if p.rageTimer > 0 then as = as * 1.3 end
    if cs.swordHeartTimer > 0 then as = as * 1.2 end
    if (cs.spearCastAsTimer or 0) > 0 then as = as * (1 + F(p, "castAs")) end
    if IsRanger() then
        as = as * (1 + (p.intent or 0) * 0.08)
        as = as * (1 + (cs.rapidStacks or 0) * (0.06 + F(p, "rapidPct")))
    end
    as = as * (1 + MissingHpBonus(p))
    local cd = 1 / math.max(0.2, as)
    cd = cd * (1 - math.min(0.4, F(p, "basicNoRecovery")))
    if IsSpear() then cd = cd * (Config.Class().attackCdMul or 1) end
    return cd
end

function Combat.ManualAttack()
    local cs = S.combat
    if not cs or cs.showBuffs or cs.paused then return end
    local p = cs.player
    if p.attackTimer > 0 then
        -- 冷却中点击：缓存一次，冷却结束立刻打出
        p.attackQueued = true
        return
    end
    p.attackQueued = false
    Combat.BasicAttack(cs)
    p.attackTimer = Combat.AttackCooldown(cs)
end

local function ApplyItem(cs, id, info)
    local p = cs.player
    if id == "potion_small" then
        Run.Heal(p, Config.Shop.PotionSmall.heal)
    elseif id == "potion_large" then
        Run.Heal(p, Config.Shop.PotionLarge.heal)
    elseif id == "shield" then
        local gain = p.maxShield * 0.5
        p.shield = math.min(p.maxShield * 1.5, p.shield + gain)
        AddText(cs, p.x, p.y - 46, string.format("+%d 护盾", math.floor(gain)), S.col.cyan, 20)
        AddParticles(cs, p.x, p.y, S.col.cyan, 12)
    elseif id == "rage" then
        p.rageTimer = 10
    end
    UI.SetToast("使用 " .. info.name, 1.4)
end

function Combat.UseItemAt(index)
    local cs = S.combat
    if not cs or cs.showBuffs then return end
    local id, info = Run.UseItemAt(index)
    if not id or not info then
        UI.SetToast("没有可用道具")
        return
    end
    ApplyItem(cs, id, info)
end

function Combat.UseItem()
    Combat.UseItemAt(1)
end

function Combat.ToggleBuffPanel()
    local cs = S.combat
    if not cs then return end
    cs.showBuffs = not cs.showBuffs
    cs.buffDetail = nil
end

function Combat.RebuildControls(cs)
    if not cs then return end
    Combat.CreateControls(cs)
end

function Combat.Exit(success)
    local roomType = S.combat and S.combat.roomType or "standard"
    if S.combat and S.combat.joystick then
        local js = S.combat.joystick
        js.active = false
        js.kx, js.ky = js.baseX, js.baseY
    end
    S.input.x = 0
    S.input.y = 0
    if success then
        Run.OnCombatCleared(roomType)
    end
end

-- ---------------------------------------------------------------- 生成怪物
local function SpawnEnemy(cs, kind, defId)
    local def
    if defId then
        for _, m in ipairs(Config.Monsters) do
            if m.id == defId then def = m end
        end
    else
        def = Config.Monsters[1]
    end
    if not def then return end

    local hpm, atk = Config.MonsterStats(cs.run.level, cs.step, kind)
    -- 公会团本：难度档位直接放大 Boss 伤害
    if cs.guildRaid and kind == "boss" then
        atk = atk * Guild.RaidAtkMul(cs.run.raidTier or 1)
    end
    local x, y = 0, 0
    for _ = 1, 40 do
        local side = math.random(1, 4)
        if side == 1 then
            x, y = math.random(70, WORLD_W - 70), 140
        elseif side == 2 then
            x, y = math.random(70, WORLD_W - 70), WORLD_H - 70
        elseif side == 3 then
            x, y = 70, math.random(140, WORLD_H - 70)
        else
            x, y = WORLD_W - 70, math.random(140, WORLD_H - 70)
        end
        if Dist(x, y, cs.player.x, cs.player.y) > 280 and not CircleHitsWalls(cs, x, y, def.radius + 8) then break end
    end
    local rx, ry = ResolveCircleWalls(cs, x, y, def.radius)
    x, y = rx, ry

    ---@type Enemy
    local e = {
        id = def.id,
        name = def.name,
        kind = kind,
        behavior = def.behavior,
        x = x, y = y,
        radius = def.radius,
        hp = hpm, maxHp = hpm,
        atk = atk,
        speed = def.speed,
        color = def.color,
        attackCd = 0,
        shootCd = 1.2 + math.random() * 1.2,
        burstCd = 3.0,
        crack = 0,
        crackTimer = 0,
        stagger = 0,
        staggerTimer = 0,
        hunt = 0,
        huntTimer = 0,
        bleedDps = 0,
        bleedTimer = 0,
        hitFlash = 0,
        slowTimer = 0,
        enraged = false,
        bossSkillCd = 3.0,
        chargeCd = 6.0,
        chargeState = nil,
        chargeT = 0,
        chargeDirX = 0,
        chargeDirY = 0,
        chargeHit = false,
        summoned1 = false,
        summoned2 = false,
    }
    cs.enemies[#cs.enemies + 1] = e
end

-- 测试模式：按 id 精确生成指定怪物
function Combat.SpawnTestEnemy(cs, kind, id)
    SpawnEnemy(cs, kind, id)
end

function Combat.SpawnWave(cs, wave)
    if not wave then return end
    local level = (cs.run and cs.run.level) or 1
    local late = level >= 7
    for _ = 1, wave.minion or 0 do
        if late and math.random() < 0.35 then
            SpawnEnemy(cs, "minion", "abscess")
        else
            local pool = Config.MinionPool
            local id = pool[math.random(1, #pool)]
            SpawnEnemy(cs, "minion", id)
        end
    end
    for _ = 1, wave.elite or 0 do
        local id = "mycel"
        if late and math.random() < 0.5 then id = "golem" end
        SpawnEnemy(cs, "elite", id)
    end
    for _ = 1, wave.boss or 0 do
        -- 公会团本固定用关底 Boss 模型
        local bossId = cs.guildRaid and Guild.RAID_BOSS_ID or (late and "colossus" or "plague")
        SpawnEnemy(cs, "boss", bossId)
    end
end

function Combat.SummonMinions(cs, boss, count)
    if #cs.enemies >= 12 then return end
    local pool = Config.MinionPool
    for _ = 1, count do
        local before = #cs.enemies
        SpawnEnemy(cs, "minion", pool[math.random(1, #pool)])
        local e = cs.enemies[before + 1]
        if e then
            local a = math.random() * math.pi * 2
            e.x = boss.x + math.cos(a) * 90
            e.y = boss.y + math.sin(a) * 90
            local ex, ey = ResolveCircleWalls(cs, e.x, e.y, e.radius)
            e.x = Config.Clamp(ex, e.radius, WORLD_W - e.radius)
            e.y = Config.Clamp(ey, e.radius, WORLD_H - e.radius)
            e.attackCd = 1.0
        end
    end
    S.toast.text = "疫魔召唤了病菌"
    S.toast.t = 1.6
end

-- ---------------------------------------------------------------- 伤害
local function Lifesteal(cs, dmg)
    local p = cs.player
    local ls = p.lifesteal
    if cs.swordHeartTimer > 0 then ls = ls + 0.06 + F(p, "stanceLifesteal") end
    if cs.parryLifestealTimer and cs.parryLifestealTimer > 0 then ls = ls + F(p, "parryLifesteal") end
    if p.hp < p.maxHp * 0.4 then ls = ls + F(p, "lowLifesteal") end
    if ls > 0 then
        local heal = math.min(dmg * ls, dmg * 0.5)
        HealPlayer(p, heal)
        if heal >= 1 and (cs.healTextTimer or 0) <= 0 then
            AddText(cs, p.x, p.y - 74, "+" .. math.floor(heal), S.col.green, 15)
            cs.healTextTimer = 0.45
        end
    end
end

function Combat.HitEnemy(cs, e, amount, isSkill, physical, noCrit, src, forceCrit)
    local p = cs.player
    local dmg = amount * DamageMul(cs, isSkill)
    if physical and e.crack > 0 then
        dmg = dmg * (1 + e.crack * 0.12)
    end
    -- 破甲：普攻命中后目标受到的物理伤害提高（可被后续普攻/技能吃到）
    if physical and (e.penVulnTimer or 0) > 0 then
        dmg = dmg * (1 + F(p, "penVuln"))
    end
    if physical and not isSkill and (e.hunt or 0) > 0 then
        dmg = dmg * (1 + e.hunt * 0.14) -- 猎痕只加成普攻
    end
    local crit = false
    if forceCrit then
        dmg = dmg * p.critDmg
        crit = true
    elseif not noCrit and p.crit > 0 and math.random() < p.crit then
        dmg = dmg * p.critDmg
        crit = true
    end

    e.hp = e.hp - dmg
    -- 公会团本：累计对 Boss 的伤害，用于评级
    if cs.guildRaid and e.kind == "boss" then
        cs.raidDamage = (cs.raidDamage or 0) + dmg
        if (e.maxHp or 0) > (cs.raidBossMax or 0) then cs.raidBossMax = e.maxHp end
    end
    e.hitFlash = 0.12
    AddParticles(cs, e.x, e.y, { 255, 236, 190 }, 3)
    DmgText(cs, e.x, e.y - e.radius - 16, string.format("%d", math.floor(dmg)),
        crit and S.col.gold or S.col.text, crit and 34 or 28, crit)
    Lifesteal(cs, dmg)
    if crit and p.critHeal > 0 then
        p.hp = math.min(p.maxHp, p.hp + p.critHeal)
    end

    -- 破甲：普攻给目标挂 4 秒易伤
    if physical and not isSkill and F(p, "penVuln") > 0 and e.hp > 0 then
        if (e.penVulnTimer or 0) <= 0 then
            AddText(cs, e.x, e.y - (e.radius or 14) - 50, "破甲", { 255, 196, 120 }, 14)
        end
        e.penVulnTimer = 4.0
    end

    -- 流血（噬魂侵蚀 / 持续蚀伤）
    local bleed = F(p, "bleedDps")
    if physical and bleed > 0 and e.hp > 0 then
        e.bleedDps = p.atk * bleed
        e.bleedTimer = 3.0
        e.bleedTick = e.bleedTick or 0.5
    end

    -- 物理负面补挂（武链共生）
    if physical and src ~= "combo" and src ~= "bleed" then
        SymbiosisRoll(cs, e)
    end
    -- 万象枪势：消耗枪势后的技能命中挂异种负面
    if physical and src == "skill" and (cs.momentumDebuffTimer or 0) > 0 then
        if F(p, "momentumCrack") > 0 and math.random() < F(p, "momentumCrack") then
            AddCrack(cs, e, 1)
        end
        if F(p, "momentumHunt") > 0 and math.random() < F(p, "momentumHunt") then
            AddHunt(cs, e, 1)
        end
    end

    if (src == nil or src == "combo") then
        cs.lastHitSrc = isSkill and "skill" or "basic"
    else
        cs.lastHitSrc = src
    end

    if e.hp <= 0 then
        Combat.KillEnemy(cs, e)
    elseif physical and src ~= "bleed" and src ~= "thorn" and src ~= "combo" then
        TryCombo(cs, e)
    end
end

function Combat.KillEnemy(cs, e)
    local idx = nil
    for i, other in ipairs(cs.enemies) do
        if other == e then idx = i break end
    end
    if not idx then return end
    table.remove(cs.enemies, idx)

    local p = cs.player

    -- 收割增益 / 瞬杀剑意 / 千影碎击
    local killCdr = F(p, "killCdr")
    if killCdr > 0 then
        for id, v in pairs(p.cooldowns) do
            if v > 0 then p.cooldowns[id] = math.max(0, v - killCdr) end
        end
        AddText(cs, e.x, e.y - e.radius - 54, "收割", S.col.gold, 16)
    end
    local killIntent = F(p, "killIntent")
    if killIntent > 0 then AddIntent(p, killIntent) end
    if F(p, "killAtkPct") > 0 then
        cs.killAtkStacks = math.min(30, (cs.killAtkStacks or 0) + 1)
        AddText(cs, e.x, e.y - e.radius - 54, "攻击 +" .. math.floor(F(p, "killAtkPct") * 100) .. "%",
            S.col.gold, 14)
    end

    if cs.lastHitSrc == "dash" and F(p, "dashKillReset") > 0 then
        p.cooldowns[2] = 0
        AddText(cs, e.x, e.y - e.radius - 72, "瞬杀·重置", S.col.gold, 16)
        if F(p, "dashKillBurst") > 0 then Combat.SwordBurst(cs) end
    end
    if cs.lastHitSrc == "blink" and F(p, "blinkKillReset") > 0 then
        p.cooldowns[6] = 0
        AddText(cs, e.x, e.y - e.radius - 72, "千影·重置", S.col.gold, 16)
    end

    -- 代偿流转：抽取目标身上全部负面
    if F(p, "compensate") > 0 then
        local stored = cs.storedDebuffs or 0
        stored = stored + math.min(9, (e.crack or 0) + (e.stagger or 0) + (e.hunt or 0))
        cs.storedDebuffs = math.min(9, stored)
        cs.storedHits = 5
        AddText(cs, e.x, e.y - e.radius - 90, "代偿 " .. cs.storedDebuffs, S.col.purple, 16)
    end

    -- 凤凰余烬：火系击杀自动放一次火球
    if F(p, "phoenix") > 0 and cs.lastElement == "fire" and (cs.phoenixCd or 0) <= 0 then
        cs.phoenixCd = 1.0
        local tgt = NearestEnemy(cs, e.x, e.y, 600)
        local ang = tgt and math.atan(tgt.y - e.y, tgt.x - e.x) or cs.facing
        SpawnProj(cs, {
            x = e.x, y = e.y,
            vx = math.cos(ang) * 700, vy = math.sin(ang) * 700,
            r = 12, life = 1.2,
            dmg = p.atk * 2.0 * (1 + p.skillPct), isSkill = true,
            kind = "fire", element = "fire", color = { 255, 150, 90 },
        })
        AddText(cs, e.x, e.y - e.radius - 60, "凤凰余烬", S.col.orange, 14)
    end

    AddParticles(cs, e.x, e.y, e.color, e.kind == "boss" and 30 or 10)
    if e.kind == "minion" then
        local drop = Config.SilverDrop.minion
        local n = math.random(drop[1], drop[2])
        n = math.max(1, math.floor(n * Guild.SilverMul(S.data) + 0.5))
        cs.run.silver = cs.run.silver + n
        AddText(cs, e.x, e.y - e.radius - 34, "+" .. n, S.col.gold)
    elseif e.kind == "elite" then
        local drop = Config.SilverDrop.elite
        local n = math.random(drop[1], drop[2])
        n = math.max(1, math.floor(n * Guild.SilverMul(S.data) + 0.5))
        cs.run.silver = cs.run.silver + n
        AddText(cs, e.x, e.y - e.radius - 34, "+" .. n, S.col.gold)
        cs.shake = math.max(cs.shake, 6)
    else
        cs.bossKilled = true
        cs.shake = 18
        S.toast.text = "Boss 已击败"
        S.toast.t = 2.0
        if cs.guildRaid then
            Combat.FinishRaid(cs, true)
            return
        end
    end
end

-- 公会团本结算：killed = 是否真的打死了 Boss
function Combat.FinishRaid(cs, killed)
    if not cs or cs.raidFinished then return end
    cs.raidFinished = true
    local percent = 0
    local maxHp = cs.raidBossMax or 0
    if maxHp > 0 then
        percent = math.floor((cs.raidDamage or 0) / maxHp * 100 + 0.5)
    end
    if killed and percent < 100 then percent = 100 end
    if percent > 120 then percent = 120 end
    local grade, coins, msg = Guild.CompleteRaid(S.data, percent, S.dev == true, cs.raidDamage)
    local tierName = Guild.RaidTierInfo(cs.run and cs.run.raidTier or 1).name
    Save.Write(S.data)
    S.input.x = 0
    S.input.y = 0
    if cs.joystick then
        cs.joystick.active = false
        cs.joystick.kx = cs.joystick.baseX
        cs.joystick.ky = cs.joystick.baseY
    end
    S.run = nil
    S.combat = nil
    S.reward = false
    S.screen = "menu"
    S.guild = true
    S.guildTab = 4
    S.toast.text = "团本结算（" .. tierName .. "）· " .. tostring(grade) .. " 级：" .. tostring(msg)
    S.toast.t = 4.5
    print("[Raid] finish " .. tostring(grade) .. " tier=" .. tierName .. " percent=" .. percent
        .. " damage=" .. tostring(cs.raidDamage) .. " coins=" .. tostring(coins))
end

function Combat.DamagePlayer(cs, amount)
    local p = cs.player

    -- 突进：剑客无敌帧，枪客突进是减伤
    if p.invulnTimer > 0 then
        return
    end
    if cs.dash and cs.dash.iframe then
        return
    end

    -- 卸势格挡：窗口内完全免伤（反复被砸也全挡），成功格挡给足反馈 + 剑气反打 + 技能冷却返还
    if p.parryTimer > 0 then
        p.parryLeft = math.max(0, (p.parryLeft or 0) - 1)
        cs.parryFlash = 0.32
        cs.parryCombo = (cs.parryCombo or 0) + 1
        cs.shake = math.max(cs.shake, 7)

        AddIntent(p, 1 + math.floor(F(p, "parryIntent")))
        AddText(cs, p.x, p.y - 46, "格挡!", { 150, 235, 255 }, 22)
        AddRing(cs, p.x, p.y, 76, { 150, 235, 255 }, 0.34, 7)
        AddRing(cs, p.x, p.y, 52, { 235, 250, 255 }, 0.2, 4)
        AddParticles(cs, p.x, p.y, S.col.cyan, 16)

        -- 弹反剑气：正面 170 范围横扫，附带伤害
        local riposte = 0.9 * (1 + F(p, "parryRiposte"))
        Combat.ArcHitAt(cs, p.x, p.y, cs.facing, 170, math.rad(110), riposte, true, 0,
            { src = "skill", slashColor = { 190, 245, 255 }, slashWidth = 7 })

        -- 降低其他技能冷却
        local refund = 0.8 + F(p, "parryCdr")
        for oid, v in pairs(p.cooldowns) do
            if oid ~= 5 and v > 0 then p.cooldowns[oid] = math.max(0, v - refund) end
        end

        local heal = F(p, "parryHeal")
        if heal > 0 then
            local amount = p.maxHp * heal
            p.hp = math.min(p.maxHp, p.hp + amount)
            AddText(cs, p.x, p.y - 82, "+" .. math.floor(amount), S.col.green, 15)
        end
        if F(p, "parrySpinCd") > 0 then
            p.cooldowns[4] = math.max(0, (p.cooldowns[4] or 0) - F(p, "parrySpinCd"))
        end
        if F(p, "parryBlinkCharge") > 0 then
            p.freeCharges = p.freeCharges or {}
            p.freeCharges[6] = (p.freeCharges[6] or 0) + 1
        end
        if F(p, "parryLifesteal") > 0 then cs.parryLifestealTimer = 3.0 end
        if F(p, "parryDmgBuff") > 0 then cs.parryDmgTimer = 4.0 end
        if F(p, "parryCrackCap") > 0 then cs.crackCapTimer = 4.0 end
        if F(p, "parryCrackAoE") > 0 then
            for _, e in ipairs(cs.enemies) do
                if Dist(p.x, p.y, e.x, e.y) < 140 then AddCrack(cs, e, 1) end
            end
        end
        if F(p, "danceFlow") > 0 then
            p.cooldowns[4] = 0
            p.cooldowns[6] = 0
            AddText(cs, p.x, p.y - 100, "剑舞流转·刷新", S.col.purple, 15)
        end
        if F(p, "thorns") > 0 then
            Combat.ReflectThorns(cs)
        end
        return
    end
    if p.dodge > 0 and math.random() < p.dodge then
        AddText(cs, p.x, p.y - 40, "闪避", S.col.green)
        return
    end

    p.noDamageTimer = 0
    local dmg = amount
    if cs.dash and (cs.dash.dr or 0) > 0 then
        dmg = dmg * (1 - cs.dash.dr)
    end
    if (cs.guardTimer or 0) > 0 then
        dmg = dmg * (1 - (0.12 + math.min(0.4, F(p, "guardDR"))))
    end
    if F(p, "heavyDR") > 0 and (cs.chargeStacks or 0) > 0 then
        dmg = dmg * (1 - F(p, "heavyDR"))
    end
    -- 减伤：稳固心神 / 剑心护体 / 狂剑士
    dmg = dmg * (1 - math.min(0.6, F(p, "hurtReduction")))
    if cs.swordHeartTimer > 0 then
        dmg = dmg * (1 - math.min(0.5, F(p, "stanceDR")))
    end
    if F(p, "berserk") > 0 then
        dmg = dmg * (1 - MissingHpBonus(p))
    end

    local before = dmg
    if p.shield > 0 then
        local absorbed = math.min(p.shield, dmg)
        p.shield = p.shield - absorbed
        dmg = dmg - absorbed
        if absorbed > 0 then
            AddText(cs, p.x, p.y - 64, string.format("护盾 -%d", math.floor(absorbed)),
                S.col.cyan, 17)
            AddParticles(cs, p.x, p.y, S.col.cyan, 6)
            cs.shieldFlash = 0.22
        end
    end
    if dmg > 0 then
        p.hp = p.hp - dmg
        cs.playerHitFlash = 0.18
        DmgText(cs, p.x, p.y - 46, string.format("-%d", math.floor(dmg)), S.col.red, 18)
        cs.shake = math.max(cs.shake, 5)
        if p.hurtHeal > 0 then
            p.hurtHealAmount = p.hurtHealAmount + dmg * p.hurtHeal
            p.hurtHealTimer = 2.0
        end
        if cs.swordHeartTimer > 0 and F(p, "stanceShieldOnHit") > 0 then
            local gain = dmg * F(p, "stanceShieldOnHit")
            p.shield = math.min(p.maxShield * 1.5, p.shield + gain)
            AddText(cs, p.x, p.y - 82, string.format("+%d 护盾", math.floor(gain)),
                S.col.cyan, 16)
        end
        if F(p, "thorns") > 0 then
            Combat.ReflectThorns(cs)
        end
    end
    -- 被动反伤也让攻击者吃到挫裂
    if F(p, "thornsCrack") > 0 and math.random() < F(p, "thornsCrack") then
        for _, e in ipairs(cs.enemies) do
            if Dist(p.x, p.y, e.x, e.y) < 80 then AddCrack(cs, e, 1) end
        end
    end

    if p.hp <= 0 then
        if p.guildInsurance and not p.guildInsuranceUsed then
            p.guildInsuranceUsed = true
            p.hp = 1
            S.toast.text = "公会保险：致命伤保留 1 血"
            S.toast.t = 2.0
        elseif p.revive > 0 and not p.reviveUsed then
            p.reviveUsed = true
            p.hp = p.maxHp * 0.3
            p.shield = 0
            S.toast.text = "复活：以 30% 生命站起"
            S.toast.t = 2.0
        elseif cs.guildRaid then
            p.hp = 0
            Combat.FinishRaid(cs, false)
            return
        else
            p.hp = 0
            S.input.x = 0
            S.input.y = 0
            S.screen = "gameover"
        end
    end
    if before <= 0 then return end
end

function Combat.ReflectThorns(cs)
    local p = cs.player
    local amount = p.atk * F(p, "thorns")
    if amount <= 0 then return end
    local hit = false
    for i = #cs.enemies, 1, -1 do
        local e = cs.enemies[i]
        if e and Dist(p.x, p.y, e.x, e.y) < 70 then
            Combat.HitEnemy(cs, e, amount, false, true, true, "thorn")
            hit = true
        end
    end
    if hit then
        AddText(cs, p.x, p.y - 60, "反击", S.col.orange, 16)
        AddRing(cs, p.x, p.y, 78, { 255, 170, 110 }, 0.3, 6)
        AddParticles(cs, p.x, p.y, S.col.orange, 6)
    end
end

-- 铁枪固守：子弹被弹开，可选反击
function Combat.GuardBlockBullet(cs, bx, by, color)
    local p = cs.player
    AddParticles(cs, bx, by, { 255, 220, 150 }, 6)
    AddRing(cs, bx, by, 26, { 255, 210, 140 }, 0.2, 3)
    if F(p, "guardShieldOnBlock") > 0 then
        p.shield = math.min(p.maxShield * 1.5, p.shield + p.maxShield * F(p, "guardShieldOnBlock"))
    end
    if F(p, "guardNextMomentum") > 0 then
        cs.guardNextMomentum = (cs.guardNextMomentum or 0) + 1
    end
    local reflect = F(p, "guardReflect")
    if reflect > 0 then
        local target, nd = nil, 520
        for _, e in ipairs(cs.enemies) do
            local d = Dist(bx, by, e.x, e.y)
            if d < nd then target, nd = e, d end
        end
        if target then
            Combat.HitEnemy(cs, target, p.atk * reflect, true, true, false, "skill")
            if F(p, "reflectStagger") > 0 then AddStagger(cs, target, 1) end
            AddText(cs, p.x, p.y - 56, "弹反", S.col.orange, 15)
        end
    end
end

-- ---------------------------------------------------------------- 剑客攻击
local function ArcTargets(cs, cx, cy, facing, range, arc)
    local list = {}
    for _, e in ipairs(cs.enemies) do
        local d = Dist(cx, cy, e.x, e.y)
        if d <= range + e.radius then
            local a = math.atan(e.y - cy, e.x - cx)
            -- 用怪物半径折算角度容差，避免大体型怪中心在扇形外但身体已经贴到剑上却打不到
            local extra = math.atan(e.radius / math.max(1, d))
            if arc >= math.pi * 2 - 0.01 or AngleDiff(a, facing) <= arc / 2 + extra then
                list[#list + 1] = e
            end
        end
    end
    return list
end

function Combat.ArcHitAt(cs, x, y, facing, range, arc, coef, isSkill, crackCount, opts)
    opts = opts or {}
    local p = cs.player
    local targets = ArcTargets(cs, x, y, facing, range, arc)
    for _, e in ipairs(targets) do
        Combat.HitEnemy(cs, e, p.atk * coef * (isSkill and (1 + p.skillPct) or (1 + p.basicPct)),
            isSkill, true, false, opts.src)
        if crackCount and crackCount > 0 then AddCrack(cs, e, crackCount) end
        if opts.crackChance and math.random() < opts.crackChance then AddCrack(cs, e, 1) end
        if opts.staggerChance and math.random() < opts.staggerChance then AddStagger(cs, e, 1) end
        if opts.crackExtend and opts.crackExtend > 0 then ExtendCrack(e, opts.crackExtend) end
        if opts.knock and opts.knock > 0 then
            local d = Dist(x, y, e.x, e.y)
            if d > 1 then
                e.x = e.x + (e.x - x) / d * 42
                e.y = e.y + (e.y - y) / d * 42
            end
        end
        AddIntent(p, 1 + (opts.intentGain or 0))
    end
    p.intentTimer = 5.0
    cs.attackFlash = 0.16
    AddSlash(cs, x, y, facing, range, arc,
        opts.slashColor or (isSkill and { 190, 235, 255 } or { 230, 245, 255 }), opts.slashWidth or (isSkill and 7 or 6))
    return #targets
end

function Combat.ArcHit(cs, range, arc, coef, isSkill, crackCount, opts)
    local p = cs.player
    return Combat.ArcHitAt(cs, p.x, p.y, cs.facing, range, arc, coef, isSkill, crackCount, opts)
end

-- 剑影复刻：按刚释放的技能复刻攻击方式与范围
local function ReplayPhantomSkill(cs, ph)
    cs.phantomHits = (cs.phantomHits or 0) + 1
    local factor = ph.coef
    local x, y, facing = ph.x, ph.y, ph.facing
    local col = ph.color or { 180, 225, 255 }
    local src = "skill"
    if ph.skill == 1 then
        Combat.ArcHitAt(cs, x, y, facing, 82, math.rad(120), 1.0 * factor, true, 0,
            { src = src, slashColor = col })
        Combat.ArcHitAt(cs, x, y, facing, 86, math.rad(120), 1.1 * factor, true, 0,
            { src = src, slashColor = col })
        Combat.ArcHitAt(cs, x, y, facing, 92, math.rad(130), 1.3 * factor, true, 0,
            { src = src, slashColor = col })
    elseif ph.skill == 2 then
        Combat.ArcHitAt(cs, x, y, facing, 150, math.rad(60), 1.7 * factor, true, 0,
            { src = src, slashColor = col })
    elseif ph.skill == 4 then
        Combat.ArcHitAt(cs, x, y, facing, 98, math.pi * 2, 1.5 * factor, true, 0,
            { src = src, slashColor = col })
    elseif ph.skill == 6 then
        Combat.ArcHitAt(cs, x, y, facing, 105, math.rad(70), 1.2 * factor, true, 0,
            { src = src, slashColor = col })
        Combat.ArcHitAt(cs, x, y, facing, 105, math.rad(70), 1.2 * factor, true, 0,
            { src = src, slashColor = col })
    else
        Combat.ArcHitAt(cs, x, y, facing, 105, math.pi * 2, factor, false, 0,
            { src = src, slashColor = col })
    end
    if ph.debuff then
        local targets = ArcTargets(cs, x, y, facing, 130, math.rad(170))
        for _, e in ipairs(targets) do
            if math.random() < 0.5 then AddStagger(cs, e, 1) else AddHunt(cs, e, 1) end
        end
    end
end

function Combat.SwordBurst(cs)
    local p = cs.player
    AddParticles(cs, p.x, p.y, S.col.cyan, 16)
    AddRing(cs, p.x, p.y, 110, { 150, 235, 255 }, 0.35, 8)
    AddSlash(cs, p.x, p.y, 0, 105, math.pi * 2, { 200, 245, 255 }, 8)
    cs.shake = math.max(cs.shake, 8)
    local targets = ArcTargets(cs, p.x, p.y, 0, 105, math.pi * 2)
    for _, e in ipairs(targets) do
        Combat.HitEnemy(cs, e, p.atk * 1.5 * (1 + p.basicPct), false, true)
        AddCrack(cs, e, 1)
    end
end

-- 剑意全满的拔刀剑气（鬼剑术）
local function SwordWave(cs, coef, crackOnHit)
    local p = cs.player
    cs.windWaves = cs.windWaves or {}
    cs.windWaves[#cs.windWaves + 1] = {
        x = p.x, y = p.y,
        dirx = math.cos(cs.facing), diry = math.sin(cs.facing),
        speed = 980, life = 0.62, r = 44,
        coef = coef, crack = crackOnHit and 1 or 0, hit = {}, trail = 0,
    }
    cs.waveCount = (cs.waveCount or 0) + 1
    cs.attackFlash = 0.16
    AddParticles(cs, p.x + math.cos(cs.facing) * 30, p.y + math.sin(cs.facing) * 30, S.col.cyan, 8)
end

-- 代偿流转：把储存的负面打到新目标身上
local function ApplyStoredDebuffs(cs, e)
    local p = cs.player
    if (cs.storedHits or 0) <= 0 or (cs.storedDebuffs or 0) <= 0 then return end
    local n = 1
    for _ = 1, n do
        if cs.storedDebuffs <= 0 then break end
        local roll = math.random(1, 3)
        if roll == 1 then ForceCrack(cs, e, 1)
        elseif roll == 2 then AddStagger(cs, e, 1)
        else AddHunt(cs, e, 1) end
        cs.storedDebuffs = cs.storedDebuffs - 1
    end
    cs.storedHits = cs.storedHits - 1
    cs.comboWeakTimer = 4.0
    if cs.storedHits <= 0 then cs.storedDebuffs = 0 end
end

function Combat.BasicAttack(cs)
    -- 弹幕清除：普通攻击挥出去的同时，把攻击范围内的敌人子弹打碎
    local cp = cs.player
    if F(cp, "clearBullet") > 0 then
        local base = Config.Class().basicRange or 80
        local clearR = base * (1 + (cp.rangePct or 0)) * 1.15
        for i = #cs.bullets, 1, -1 do
            local b = cs.bullets[i]
            if not b.shock and Dist(b.x, b.y, cp.x, cp.y) <= clearR then
                AddParticles(cs, b.x, b.y, b.color or { 200, 225, 255 }, 3)
                table.remove(cs.bullets, i)
            end
        end
    end
    if IsSpear() then return Combat.SpearBasicAttack(cs) end
    if IsRanger() then return Combat.RangerBasicAttack(cs) end
    if IsMage() then return Combat.MageBasicAttack(cs) end
    local p = cs.player
    local range = Config.Classes.swordsman.basicRange * (1 + p.rangePct)
    local arc = Config.Classes.swordsman.basicArc

    -- 鬼剑术：剑意满时改为远程拔刀剑气
    if F(p, "oni") > 0 and p.intent >= IntentMax(p) then
        SwordWave(cs, 3.4, true)
        return
    end

    local targets = ArcTargets(cs, p.x, p.y, cs.facing, range, arc)
    if #targets == 0 then
        cs.attackFlash = 0.12
        return
    end

    local coef = Config.Classes.swordsman.basicCoef * (1 + p.intent * 0.06) * (1 + p.basicPct)
    local applyCrack = p.intent >= 3
    local insight = F(p, "insight") > 0
    local staggerChance = F(p, "staggerChance")
    for _, e in ipairs(targets) do
        Combat.HitEnemy(cs, e, p.atk * coef, false, true, false, "basic")
        if applyCrack then AddCrack(cs, e, 1) end
        if insight and (e.crack or 0) > 0 then
            if math.random() < 0.45 then AddStagger(cs, e, 1) end
            if math.random() < 0.25 then AddHunt(cs, e, 1) end
        end
        if staggerChance > 0 and math.random() < staggerChance then AddStagger(cs, e, 1) end
        ApplyStoredDebuffs(cs, e)
    end

    local gain = 1 + math.floor(F(p, "skillIntent") > 0 and (cs.nextBasicIntent or 0) or 0)
    if cs.swordHeartTimer > 0 then gain = gain + 1 end
    AddIntent(p, gain)
    AddSlash(cs, p.x, p.y, cs.facing, range, arc, { 232, 244, 255 }, 5)
    cs.nextBasicIntent = 0
    cs.attackFlash = 0.12

    if p.intent >= IntentMax(p) then
        Combat.SwordBurst(cs)
        p.intent = 0
    end
end

-- ---------------------------------------------------------------- 枪客普攻（三段循环）
function Combat.SpearBasicAttack(cs)
    local p = cs.player
    local class = Config.Class()
    local held = p.intent > 0
    local range = class.basicRange + (p.rangePct or 0) * class.basicRange
    local arc = class.basicArc
    if held then
        -- 枪势加成收敛：原来 +32 距离 / +35° 扇形，视觉上像角色变大了一圈
        range = range + 18
        arc = arc + math.rad(18)
    end
    local seg = (cs.spearCombo or 0) + 1
    if seg > 3 then seg = 1 end
    local base = (seg == 3) and 1.8 or 0.9
    local empowered = (cs.spearBuffHits or 0) > 0
    local extra = 0
    local forceCrit = false
    local isThird = seg == 3

    if seg == 1 then extra = extra + F(p, "a1Pct") end
    if seg == 2 then extra = extra + F(p, "a2Pct") end
    if isThird then
        extra = extra + F(p, "a3Pct") + F(p, "combo3Pct")
        if (cs.next3aTimer or 0) > 0 then extra = extra + F(p, "next3aPct") end
        if F(p, "chargePct") > 0 then
            extra = extra + math.min(10, cs.chargeStacks or 0) * F(p, "chargePct")
        end
        if F(p, "a3Crit") > 0 then forceCrit = true end
    end
    if seg == 2 and F(p, "sweepPct") > 0 then
        range = range * (1 + F(p, "sweepRange"))
        extra = extra + F(p, "sweepPct")
    end
    if empowered and seg == 1 then extra = extra + 0.4 end

    local coef = base * (1 + p.basicPct) * (1 + extra)
    local targets = ArcTargets(cs, p.x, p.y, cs.facing, range, arc)
    local totalDmg = 0
    for _, e in ipairs(targets) do
        local dmg = p.atk * coef
        if isThird and (e.hp / math.max(1, e.maxHp)) < 0.35 and F(p, "executePct") > 0 then
            dmg = dmg * (1 + F(p, "executePct"))
        end
        if (cs.killAtkStacks or 0) > 0 and F(p, "killAtkPct") > 0 then
            dmg = dmg * (1 + cs.killAtkStacks * F(p, "killAtkPct"))
        end
        Combat.HitEnemy(cs, e, dmg, false, true, false, "basic", forceCrit)
        totalDmg = totalDmg + dmg
        if seg == 2 and F(p, "a2True") > 0 then
            Combat.HitEnemy(cs, e, p.atk * F(p, "a2True"), false, true, false, "basic")
        end

        -- 失衡：持有枪势、强化普攻、或专属加成
        if (held or empowered) and F(p, "chainSymbiosis") <= 0 then AddStagger(cs, e, 1) end
        if F(p, "basicStaggerChance") > 0 and math.random() < F(p, "basicStaggerChance") then
            AddStagger(cs, e, 1)
        end
        if seg == 2 and F(p, "sweepStagger") > 0 then AddStagger(cs, e, 1) end
        if isThird and F(p, "combo3Stagger") > 0 then AddStagger(cs, e, 1) end
        ApplyStoredDebuffs(cs, e)
        if F(p, "a3CritMaxStagger") > 0 and forceCrit then
            e.stagger = DebuffCap(p, "stagger")
            e.staggerTimer = 3.0
        end

        -- 第三段击退
        if isThird then
            local kb = 48 + F(p, "comboKnock") + (empowered and 24 or 0)
            local d = Dist(p.x, p.y, e.x, e.y)
            if d > 1 then
                e.x = e.x + (e.x - p.x) / d * kb
                e.y = e.y + (e.y - p.y) / d * kb
            end
        end

        -- 吸血
        if seg == 1 and F(p, "a1Lifesteal") > 0 then
            p.hp = math.min(p.maxHp, p.hp + dmg * F(p, "a1Lifesteal"))
        end
        if empowered and seg == 2 then
            p.hp = math.min(p.maxHp, p.hp + dmg * 0.25)
            AddText(cs, p.x, p.y - 70, "+" .. math.floor(dmg * 0.25), S.col.green, 14)
        end

        -- 三段命中带挫裂 → 震荡
        if isThird and (e.crack or 0) > 0 and (F(p, "a3Combo") > 0 or empowered) then
            TryCombo(cs, e, "震荡")
        end
        -- 印记共振：攻击带失衡目标概率挂猎痕
        if F(p, "huntOnStagger") > 0 and (e.stagger or 0) > 0 and math.random() < F(p, "huntOnStagger") then
            AddHunt(cs, e, 1)
        end
    end

    -- 强化普攻：每次命中让全部技能冷却 -1 秒
    if empowered and #targets > 0 then
        for id, v in pairs(p.cooldowns) do
            if v > 0 then p.cooldowns[id] = math.max(0, v - 1.0) end
        end
        cs.spearBuffHits = math.max(0, cs.spearBuffHits - 1)
        if cs.spearBuffHits <= 0 then cs.spearBuffTimer = 0 end
    end
    -- 连环挑击：第三段命中减技能 1 冷却
    if isThird and #targets > 0 and F(p, "combo3Cdr") > 0 then
        p.cooldowns[1] = math.max(0, (p.cooldowns[1] or 0) - F(p, "combo3Cdr"))
    end

    -- 2A 枪风领域
    if seg == 2 and F(p, "a2Wind") > 0 then
        cs.spearFields = cs.spearFields or {}
        cs.spearFields[#cs.spearFields + 1] = {
            x = p.x + math.cos(cs.facing) * 40,
            y = p.y + math.sin(cs.facing) * 40,
            r = 70, t = 0, life = 2.0, tick = 0,
            dmg = p.atk * 0.4, stagger = F(p, "windStagger") > 0,
        }
    end

    -- 连击推进与枪势
    cs.spearCombo = isThird and 0 or seg
    if isThird then
        GainMomentum(p, 1 + math.floor(F(p, "comboFullMomentum")))
        if F(p, "comboFullRefund") > 0 then p.cooldowns[1] = 0 end
        if F(p, "chargePct") > 0 then
            cs.chargeStacks = math.min(10, (cs.chargeStacks or 0) + 1)
        end
        if (cs.guardNextMomentum or 0) > 0 then
            AddMomentum(p, cs.guardNextMomentum)
            cs.guardNextMomentum = 0
        end
    end

    -- 视觉
    AddSlash(cs, p.x, p.y, cs.facing, range, arc,
        empowered and { 255, 220, 150 } or { 255, 205, 150 }, isThird and 8 or 5)
    if isThird then
        AddRing(cs, p.x, p.y, range * 0.8, { 255, 200, 130 }, 0.2, 4)
        cs.shake = math.max(cs.shake, 4)
    end
    cs.attackFlash = 0.12
    p.intentTimer = 5.0
end

-- ---------------------------------------------------------------- 游侠 / 法师普攻
function Combat.RangerBasicAttack(cs)
    local p = cs.player
    local class = Config.Class()
    local range = class.basicRange * (1 + p.rangePct)
    local target = NearestEnemy(cs, p.x, p.y, range * 1.3)
    local facing = target and math.atan(target.y - p.y, target.x - p.x) or cs.facing
    cs.facing = facing
    local coef = class.basicCoef * (1 + p.basicPct)
    local hunt = 1 + math.floor(F(p, "huntPerHit"))
    local crit = false
    if (cs.rangerCrit or 0) > 0 then
        crit = true
        cs.rangerCrit = cs.rangerCrit - 1
    end
    if (cs.rangerSwap or 0) > 0 then
        -- 换位后第一发：伤害加成（原来给攻速，手感上体现不出来）
        coef = coef * (1 + 0.25 + F(p, "swapBasicPct") + F(p, "swapAs"))
        hunt = hunt + 1 + math.floor(F(p, "swapHunt"))
        if F(p, "swapCrit") > 0 then crit = true end
        cs.rangerSwap = 0
    end
    SpawnProj(cs, {
        x = p.x, y = p.y,
        vx = math.cos(facing) * 950, vy = math.sin(facing) * 950,
        r = 7, life = range / 950 + 0.5,
        dmg = p.atk * coef, isSkill = false,
        pierce = math.floor(F(p, "basicPierce")), kind = "arrow",
        hunt = hunt, slow = F(p, "basicSlow"), crit = crit,
        color = { 190, 245, 200 },
        splash = F(p, "basicSplash") > 0, splashPct = F(p, "basicSplashPct"),
        lifesteal = F(p, "basicLifesteal"),
        combo = "追猎",
    })
    cs.attackFlash = 0.10
    AddSlash(cs, p.x, p.y, facing, range, class.basicArc, { 190, 245, 200 }, 3)
end

function Combat.MageBasicAttack(cs)
    local p = cs.player
    local class = Config.Class()
    local range = class.basicRange * (1 + p.rangePct)
    local target = NearestEnemy(cs, p.x, p.y, range * 1.3)
    local facing = target and math.atan(target.y - p.y, target.x - p.x) or cs.facing
    cs.facing = facing
    SpawnProj(cs, {
        x = p.x, y = p.y,
        vx = math.cos(facing) * 720, vy = math.sin(facing) * 720,
        r = 9, life = range / 720 + 0.5,
        dmg = p.atk * class.basicCoef * (1 + p.basicPct), isSkill = false,
        kind = "orb", color = { 200, 170, 255 }, combo = nil,
    })
    cs.attackFlash = 0.10
end

-- ---------------------------------------------------------------- 游侠技能
local function RangerSkillCD(cs, id, base)
    local p = cs.player
    local cd = base * (1 - p.cdr)
    if id == 2 then cd = cd + F(p, "r2Cd") end
    if id == 4 then cd = cd + F(p, "trapCd") end
    if id == 6 then cd = cd + F(p, "swapCd") end
    if (cs.comboEchoPenalty or 0) > 0 then cd = cd * 1.2 end
    return math.max(0.4, cd)
end

function Combat.RangerCastSkill(slot)
    local cs = S.combat
    if not cs or cs.showBuffs then return end
    local p = cs.player
    local id = cs.run.loadout[slot]
    local sk = id and Config.SkillByID(id)
    if not sk then return end

    local cd = RangerSkillCD(cs, id, sk.cd)
    -- 换位需要目标：没有可换位的敌人时不空放，也不吃冷却
    if id == 6 then
        local has = false
        for _, e in ipairs(cs.enemies) do
            if (e.hunt or 0) > 0 then has = true break end
        end
        if not has and not NearestEnemy(cs, p.x, p.y, 500) then
            UI.SetToast("附近没有目标", 0.8)
            return
        end
    end
    if (p.cooldowns[id] or 0) > 0 then
        if (p.freeCharges and p.freeCharges[id] or 0) > 0 then
            p.freeCharges[id] = p.freeCharges[id] - 1
        elseif id == 6 and F(p, "swapCharge") > 0 and (p.charges[id] or 0) > 0 then
            p.charges[id] = p.charges[id] - 1
        else
            return
        end
    else
        p.cooldowns[id] = cd
    end

    SpawnAfterimage(cs, 0, F(p, "illusionChance"), id)

    if id == 1 then
        cs.rapidTimer = 5 + F(p, "rapidDur")
        cs.rapidStacks = 0
        AddText(cs, p.x, p.y - 50, "精准速射", S.col.green, 16)
        AddTelegraph(cs, { kind = "circle", x = p.x, y = p.y, r = 54,
            color = { 150, 240, 170 }, life = 0.36 })
    elseif id == 2 then
        -- 有摇杆/键盘输入时朝输入方向翻滚，没有输入才向后撤
        local back = 80
        local dirx, diry, ang, hasInput = DashDir(cs)
        local bx, by
        if hasInput then
            bx = p.x + dirx * back
            by = p.y + diry * back
        else
            bx = p.x - math.cos(cs.facing) * back
            by = p.y - math.sin(cs.facing) * back
        end
        local rx, ry = ResolveCircleWalls(cs, bx, by, p.radius)
        local fromX, fromY = p.x, p.y
        p.x = Config.Clamp(rx, p.radius, WORLD_W - p.radius)
        p.y = Config.Clamp(ry, p.radius, WORLD_H - p.radius)
        p.invulnTimer = 0.3 + F(p, "dodgeInvuln")
        GainMomentum(p, 1 + math.floor(F(p, "dodgeStacks")))
        AddTrail(cs, p.x, p.y, { 140, 230, 170 }, 13)
        AddTelegraph(cs, { kind = "line", x = fromX, y = fromY, x2 = p.x, y2 = p.y,
            color = { 150, 240, 170 }, life = 0.3 })
        if F(p, "dodgeStacks") > 0 then GainMomentum(p, 1) end
    elseif id == 3 then
        local charge = math.max(0, 0.6 + F(p, "snipeCharge"))
        local coef = 2.6 * (1 + F(p, "snipePct"))
        AimAt(cs, 900, math.rad(120))
        local function shoot()
            local target = NearestEnemy(cs, p.x, p.y, 900)
            local facing
            if cs.aimLock then
                facing = cs.facing     -- 玩家手动瞄准的朝向
            else
                facing = target and math.atan(target.y - p.y, target.x - p.x) or cs.facing
            end
            cs.snipeCharge = nil
            SpawnProj(cs, {
                x = p.x, y = p.y,
                vx = math.cos(facing) * 1150, vy = math.sin(facing) * 1150,
                r = 9, life = 1.2, dmg = p.atk * coef * (1 + p.skillPct),
                isSkill = true, pierce = 6, kind = "arrow",
                hunt = 2, crit = false, color = { 255, 230, 150 },
                combo = "追猎", boom = F(p, "snipeBoom"),
            })
            AddTelegraph(cs, { kind = "corridor", x = p.x, y = p.y, facing = facing,
                len = 860, width = 34, color = { 255, 230, 150 }, life = 0.3 })
            AddParticles(cs, p.x, p.y, { 255, 230, 150 }, 10)
            cs.shake = math.max(cs.shake, 5)
        end
        if charge <= 0.01 then
            shoot()
        else
            AddText(cs, p.x, p.y - 50, "蓄力", S.col.gold, 14)
            cs.snipeCharge = { x = p.x, y = p.y, facing = cs.facing, dur = charge, t = 0 }
            cs.pendingHits[#cs.pendingHits + 1] = { t = charge, fn = shoot }
        end
    elseif id == 4 then
        cs.rangerTraps = cs.rangerTraps or {}
        local maxTraps = 1 + math.floor(F(p, "trapCount"))
        if #cs.rangerTraps >= maxTraps then table.remove(cs.rangerTraps, 1) end
        -- 夹子判定明显小于视觉外框，避免“擦边就触发”的错觉
        local trapR = 46 * (1 + F(p, "trapRadius"))
        local tx, ty = p.x + math.cos(cs.facing) * 90, p.y + math.sin(cs.facing) * 90
        if cs.aimPoint then tx, ty = cs.aimPoint.x, cs.aimPoint.y end
        local rx, ry = ResolveCircleWalls(cs, tx, ty, 10)
        tx = Config.Clamp(rx, 20, WORLD_W - 20)
        ty = Config.Clamp(ry, 20, WORLD_H - 20)
        cs.rangerTraps[#cs.rangerTraps + 1] = {
            x = tx, y = ty, r = trapR,
            t = 3 + F(p, "trapDur"), slow = 0.4 + F(p, "trapSlow"),
            hunt = 1 + math.floor(F(p, "trapHuntStacks")),
            crit = 1 + math.floor(F(p, "trapCritStacks")),
            root = 1.2 + F(p, "trapRoot"),
            triggered = false,
        }
        AddTelegraph(cs, { kind = "circle", x = tx, y = ty, r = trapR + 10,
            color = { 150, 240, 170 }, life = 0.5 })
        AddText(cs, tx, ty - 30, "陷阱", S.col.green, 16)
    elseif id == 5 then
        AimAt(cs, 700, math.rad(110))
        local count = 4 + math.floor(F(p, "volleyArrows"))
        local coef = 0.85 * (1 + F(p, "volleyPct"))
        for i = 1, count do
            local spread = (i - (count + 1) / 2) * 0.10
            local ang = cs.facing + spread
            SpawnProj(cs, {
                x = p.x, y = p.y,
                vx = math.cos(ang) * 900, vy = math.sin(ang) * 900,
                r = 6, life = 1.0, dmg = p.atk * coef * (1 + p.skillPct),
                isSkill = true, kind = "arrow", hunt = 1,
                color = { 190, 245, 200 }, combo = "追猎",
                execute = F(p, "volleyComboChance"),
            })
        end
        AddTelegraph(cs, { kind = "sector", x = p.x, y = p.y, facing = cs.facing,
            range = 640, arc = 0.10 * count + 0.14,
            color = { 190, 245, 200 }, life = 0.42 })
        cs.attackFlash = 0.12
    elseif id == 6 then
        local target = nil
        for _, e in ipairs(cs.enemies) do
            if (e.hunt or 0) > 0 then target = e break end
        end
        target = target or NearestEnemy(cs, p.x, p.y, 500)
        if target then
            local ang = math.atan(target.y - p.y, target.x - p.x)
            -- 穿到目标身后落地，回头面对它
            local behind = (target.radius or 14) + p.radius + 24
            local nx = target.x + math.cos(ang) * behind
            local ny = target.y + math.sin(ang) * behind
            local rx, ry = ResolveCircleWalls(cs, nx, ny, p.radius)
            local fromX, fromY = p.x, p.y
            p.x = Config.Clamp(rx, p.radius, WORLD_W - p.radius)
            p.y = Config.Clamp(ry, p.radius, WORLD_H - p.radius)
            cs.facing = ang + math.pi
            AddTrail(cs, p.x, p.y, { 190, 245, 200 }, 13)
            AddTelegraph(cs, { kind = "line", x = fromX, y = fromY, x2 = p.x, y2 = p.y,
                color = { 190, 245, 200 }, life = 0.34 })
            AddTelegraph(cs, { kind = "circle", x = p.x, y = p.y, r = 130,
                color = { 190, 245, 200 }, life = 0.42 })
            cs.rangerSwap = 1
            cs.rangerSwapCombo = F(p, "swapCombo") > 0 and 1 or 0
            cs.rapidTimer = math.max(cs.rapidTimer or 0, 1.0)
            if F(p, "swapAoeHunt") > 0 then
                for _, e in ipairs(cs.enemies) do
                    if Dist(p.x, p.y, e.x, e.y) < 130 then AddHunt(cs, e, 1) end
                end
            end
            if F(p, "huntCycle") > 0 then
                p.cooldowns[4] = math.max(0, (p.cooldowns[4] or 0) - 2)
            end
        end
    end
end

-- ---------------------------------------------------------------- 法师技能
local function MageSkillCD(cs, id, base)
    local p = cs.player
    local cd = base * (1 - p.cdr)
    if id == 2 then cd = cd + F(p, "m2Cd") end
    local sk = Config.SkillByID(id)
    if sk and sk.element == "bolt" and cs.mageSpec == "bolt" then cd = cd * 0.8 end
    if (cs.comboEchoPenalty or 0) > 0 then cd = cd * 1.2 end
    return math.max(0.3, cd)
end

local function MageField(cs, o)
    cs.mageFields[#cs.mageFields + 1] = o
end

function Combat.MageCastSkill(slot)
    local cs = S.combat
    if not cs or cs.showBuffs then return end
    local p = cs.player
    local id = cs.run.loadout[slot]
    local sk = id and Config.SkillByID(id)
    if not sk then return end

    local cd = MageSkillCD(cs, id, sk.cd)
    if (p.cooldowns[id] or 0) > 0 then return end
    -- 单体技能没有目标时不空放，也不吃冷却
    if id == 3 and not NearestEnemy(cs, p.x, p.y, 700) then
        UI.SetToast("附近没有目标", 0.8)
        return
    end
    p.cooldowns[id] = cd
    if sk.element == "bolt" then
        cs.boltCasts = (cs.boltCasts or 0) + 1
        if F(p, "overloadCharge") > 0 and cs.boltCasts >= 3 then
            cs.boltCasts = 0
            p.cooldowns[id] = 0
            AddText(cs, p.x, p.y - 56, "电能暴走", S.col.gold, 15)
        end
    end

    -- 元素亲和 / 时间法师 / 共鸣 / 过载 / 混沌 / 答题
    cs.resonanceStacks = math.min(5, (cs.resonanceStacks or 0) + (F(p, "elemResonance") > 0 and 1 or 0))
    if (cs.resonanceStacks or 0) > 0 then cs.resonanceTimer = 8 end
    if F(p, "timeMage") > 0 then
        for oid, v in pairs(p.cooldowns) do
            if oid ~= id and v > 0 then p.cooldowns[oid] = math.max(0, v - 0.25) end
        end
    end
    if sk.element then
        if cs.quizElement == sk.element then
            cs.quizStacks = math.min(5, (cs.quizStacks or 0) + (F(p, "quiz") > 0 and 1 or 0))
        else
            cs.quizElement = sk.element
            cs.quizStacks = 0
        end
    end
    if F(p, "elemOverload") > 0 and math.random() < 0.2 then
        p.cooldowns[id] = 0
        cs.overloadTimer = 1.0
    end
    if F(p, "chaos") > 0 and math.random() < 0.2 then cs.chaosTimer = 1.0 end

    local target
    if cs.aimPoint then target = NearestEnemyTo(cs, cs.aimPoint.x, cs.aimPoint.y, 280) end
    target = target or NearestEnemy(cs, p.x, p.y, 700)
    local facing
    if cs.aimLock then
        facing = cs.facing          -- 手动瞄准：用玩家选的方向
    else
        facing = target and math.atan(target.y - p.y, target.x - p.x) or cs.facing
        cs.facing = facing
    end

    local elemMul = sk.element and ElemMul(cs, sk.element) or 1
    if sk.element == "bolt" and F(p, "staticBolt") > 0 and InBoltField(cs) then
        elemMul = elemMul * (1 + F(p, "staticBolt"))
    end
    local skillMul = 1 + p.skillPct + F(p, "m" .. id .. "Pct")

    if id == 1 then
        if F(p, "dragonBreath") > 0 then
            local radius = 160
            for _, e in ipairs(ArcTargets(cs, p.x, p.y, facing, radius, math.rad(120))) do
                Combat.HitEnemy(cs, e, p.atk * 2.0 * skillMul * elemMul, true, true, false, "skill")
                ApplyElementHit(cs, e, "fire", id)
            end
            AddSlash(cs, p.x, p.y, facing, radius, math.rad(120), { 255, 150, 90 }, 7)
            AddTelegraph(cs, { kind = "sector", x = p.x, y = p.y, facing = facing,
                range = radius, arc = math.rad(120), color = { 255, 150, 90 }, life = 0.45 })
        else
            SpawnProj(cs, {
                x = p.x, y = p.y,
                vx = math.cos(facing) * 700, vy = math.sin(facing) * 700,
                r = 12, life = 1.2, dmg = p.atk * 2.0 * skillMul * elemMul,
                isSkill = true, kind = "fire", element = "fire", skill = id,
                color = { 255, 150, 90 },
            })
            AddTelegraph(cs, { kind = "corridor", x = p.x, y = p.y, facing = facing,
                len = 760, width = 40, color = { 255, 150, 90 }, life = 0.4 })
        end
    elseif id == 2 then
        local radius = 128
        local arc = math.rad(60) + F(p, "freezeArc")
        local targets
        if F(p, "iceNova") > 0 then
            targets = ArcTargets(cs, p.x, p.y, facing, radius, math.pi * 2)
            AddRing(cs, p.x, p.y, radius, { 150, 220, 255 }, 0.3, 6)
            AddTelegraph(cs, { kind = "circle", x = p.x, y = p.y, r = radius,
                color = { 150, 220, 255 }, life = 0.42 })
        else
            targets = ArcTargets(cs, p.x, p.y, facing, radius, arc)
            AddSlash(cs, p.x, p.y, facing, radius, arc, { 150, 220, 255 }, 7)
            AddTelegraph(cs, { kind = "sector", x = p.x, y = p.y, facing = facing,
                range = radius, arc = arc, color = { 150, 220, 255 }, life = 0.42 })
        end
        for _, e in ipairs(targets) do
            local amount = p.atk * 0.8 * skillMul * elemMul
            if F(p, "absoluteZero") > 0 and (e.freezeTimer or 0) > 0 then
                amount = amount + p.atk
            end
            Combat.HitEnemy(cs, e, amount, true, true, false, "skill")
            ApplyElementHit(cs, e, "ice", id)
        end
    elseif id == 3 then
        local e = target
        if e then
            local bonus = 1
            if (e.burnTimer or 0) > 0 or (e.freezeTimer or 0) > 0 then bonus = 1.5 end
            if F(p, "thunderCrit") > 0 then bonus = bonus + (F(p, "thunderCrit") - 1.5) end
            AddBolt(cs, e.x, e.y - 210, e.x, e.y, { 255, 240, 150 }, 0.22)
            AddTelegraph(cs, { kind = "line", x = p.x, y = p.y, x2 = e.x, y2 = e.y,
                color = { 255, 235, 140 }, life = 0.28 })
            Combat.HitEnemy(cs, e, p.atk * 2.5 * bonus * skillMul * elemMul, true, true, false, "skill")
            ApplyElementHit(cs, e, "bolt", id)
            AddSlash(cs, p.x, p.y, facing, 420, math.rad(8), { 255, 235, 140 }, 6)
        end
    elseif id == 4 then
        SpawnProj(cs, {
            x = p.x, y = p.y,
            vx = math.cos(facing) * 820, vy = math.sin(facing) * 820,
            r = 9, life = 1.1, dmg = p.atk * 1.2 * skillMul * elemMul,
            isSkill = true, kind = "ice", element = "ice", skill = id,
            slow = 0.5 + F(p, "slowBonus"), color = { 150, 220, 255 },
        })
        AddTelegraph(cs, { kind = "corridor", x = p.x, y = p.y, facing = facing,
            len = 860, width = 30, color = { 150, 220, 255 }, life = 0.38 })
    elseif id == 5 then
        local first = target
        if not first and #cs.enemies > 0 then first = cs.enemies[1] end
        if first then
            local chain = 3 + math.floor(F(p, "boltChain"))
            local range = 96 + F(p, "boltRange") * 32
            local done = {}
            local current = first
            local count = 0
            AddTelegraph(cs, { kind = "line", x = p.x, y = p.y, x2 = first.x, y2 = first.y,
                color = { 255, 235, 140 }, life = 0.3 })
            while current and count < chain do
                done[current] = true
                local amount = p.atk * 1.2 * skillMul * elemMul
                if F(p, "thunderExecute") > 0 and current.hp < current.maxHp * 0.5 then
                    amount = amount * 2
                end
                Combat.HitEnemy(cs, current, amount, true, true, false, "skill")
                ApplyElementHit(cs, current, "bolt", id)
                if F(p, "boltKillCdr") > 0 then
                    for oid, v in pairs(p.cooldowns) do
                        if v > 0 then p.cooldowns[oid] = math.max(0, v - F(p, "boltKillCdr")) end
                    end
                end
                count = count + 1
                local nextE = nil
                for _, e in ipairs(cs.enemies) do
                    if not done[e] and Dist(current.x, current.y, e.x, e.y) < range then
                        nextE = e
                        break
                    end
                end
                if nextE then
                    AddBolt(cs, current.x, current.y, nextE.x, nextE.y, { 255, 235, 150 }, 0.2)
                end
                current = nextE
            end
            if F(p, "lightningStorm") > 0 then
                for _, e in ipairs(ArcTargets(cs, first.x, first.y, 0, 128, math.pi * 2)) do
                    Combat.HitEnemy(cs, e, p.atk * 1.0 * skillMul * elemMul, true, true, false, "skill")
                    ApplyElementHit(cs, e, "bolt", id)
                end
                AddRing(cs, first.x, first.y, 130, { 255, 235, 140 }, 0.3, 5)
                AddTelegraph(cs, { kind = "circle", x = first.x, y = first.y, r = 128,
                    color = { 255, 235, 140 }, life = 0.42 })
            end
        end
    elseif id == 6 then
        local targets = ArcTargets(cs, p.x, p.y, facing, 120, math.rad(140))
        for _, e in ipairs(targets) do
            local amount = p.atk * 1.5 * skillMul * elemMul
            if (e.burnTimer or 0) > 0 then
                amount = amount * (1 + 0.5 + F(p, "burnBonus"))
            end
            Combat.HitEnemy(cs, e, amount, true, true, false, "skill")
            ApplyElementHit(cs, e, "fire", id)
        end
        AddSlash(cs, p.x, p.y, facing, 120, math.rad(140), { 255, 150, 90 }, 7)
        AddTelegraph(cs, { kind = "sector", x = p.x, y = p.y, facing = facing,
            range = 120, arc = math.rad(140), color = { 255, 150, 90 }, life = 0.42 })
    elseif id == 7 then
        local fieldR = 96 * (1 + F(p, "staticRadius"))
        MageField(cs, {
            x = p.x, y = p.y, r = fieldR,
            t = 0, life = 5, tick = 0, dmg = 0.2, slow = 0.2,
            element = "bolt", skill = id,
        })
        AddTelegraph(cs, { kind = "circle", x = p.x, y = p.y, r = fieldR,
            color = { 255, 235, 140 }, life = 0.55 })
    elseif id == 8 then
        local cx, cy = p.x + math.cos(facing) * 200, p.y + math.sin(facing) * 200
        if cs.aimPoint then cx, cy = cs.aimPoint.x, cs.aimPoint.y
        elseif target then cx, cy = target.x, target.y end
        AddBolt(cs, cx, cy - 240, cx, cy, { 255, 170, 100 }, 0.26)
        for _, e in ipairs(ArcTargets(cs, cx, cy, 0, 96, math.pi * 2)) do
            Combat.HitEnemy(cs, e, p.atk * 3.0 * skillMul * elemMul, true, true, false, "skill")
            ApplyElementHit(cs, e, "fire", id)
        end
        AddRing(cs, cx, cy, 100, { 255, 140, 80 }, 0.35, 8)
        AddTelegraph(cs, { kind = "circle", x = cx, y = cy, r = 100,
            color = { 255, 140, 80 }, life = 0.45 })
        cs.shake = math.max(cs.shake, 8)
    elseif id == 9 then
        MageField(cs, {
            x = p.x, y = p.y, r = 128,
            t = 0, life = 4 + F(p, "blizzardDur"), tick = 0, dmg = 0.3,
            slow = 0.3 + F(p, "blizzardSlow"), element = "ice", skill = id,
            eternal = F(p, "eternalWinter") > 0,
            iceBonus = F(p, "blizzardIce"),
        })
        AddTelegraph(cs, { kind = "circle", x = p.x, y = p.y, r = 128,
            color = { 150, 220, 255 }, life = 0.55 })
    end

    -- 奥术回响：同系技能复读 40%
    if F(p, "arcaneEcho") > 0 and cs.lastSpellElement == sk.element and target then
        local echo = p.atk * 0.4 * 2.0
        for _, e in ipairs(ArcTargets(cs, target.x, target.y, 0, 100, math.pi * 2)) do
            Combat.HitEnemy(cs, e, echo, true, true, false, "skill")
        end
        AddRing(cs, target.x, target.y, 90, { 200, 170, 255 }, 0.3, 4)
    end
    cs.lastSpellElement = sk.element
end

-- 远程/法术剑影复刻
local function ReplayRangedPhantom(cs, ph)
    local p = cs.player
    cs.phantomHits = (cs.phantomHits or 0) + 1
    local f = ph.coef
    local target = NearestEnemy(cs, ph.x, ph.y, 500)
    local facing = target and math.atan(target.y - ph.y, target.x - ph.x) or ph.facing
    local dmg = p.atk * 1.0 * f
    SpawnProj(cs, {
        x = ph.x, y = ph.y,
        vx = math.cos(facing) * 900, vy = math.sin(facing) * 900,
        r = 8, life = 1.0, dmg = dmg, isSkill = true,
        pierce = 1, kind = IsRanger() and "arrow" or "orb",
        color = ph.color or { 200, 180, 255 }, combo = "追猎", hunt = 1,
    })
end

local function ChargeMax(p, id)
    if IsRanger() then
        if id == 6 then return 1 + math.floor(F(p, "swapCharge")) end
        return 1
    end
    if IsSpear() then
        if id == 2 then return 1 + math.floor(F(p, "dashCharges")) end
        if id == 5 then return 1 + math.floor(F(p, "backCharges")) end
        return 1
    end
    if id == 2 then return 1 + math.floor(F(p, "dashCharges")) end
    if id == 4 then return 1 + math.floor(F(p, "spinCharges")) end
    return 1
end

local function SkillCD(cs, id, base)
    local p = cs.player
    local cd = base * (1 - p.cdr)
    if id == 2 then cd = cd + F(p, "dashCd") end
    if id == 4 then cd = (cd + F(p, "spinCd")) * (1 + F(p, "spinCdMul")) end
    if id == 5 then cd = cd + F(p, "parryCd") end
    if id == 6 then cd = (cd + F(p, "blinkCd")) * (1 + F(p, "blinkCdMul")) end
    if (cs.comboEchoPenalty or 0) > 0 then cd = cd * 1.2 end
    return math.max(0.5, cd)
end

-- 技能释放后留下的剑影 / 虚影
-- 枪客剑影复刻：按技能形态打对应范围
local function ReplaySpearPhantom(cs, ph)
    cs.phantomHits = (cs.phantomHits or 0) + 1
    local p = cs.player
    local f = ph.coef
    local x, y, facing = ph.x, ph.y, ph.facing
    local col = ph.color or { 255, 205, 150 }
    local hits = 0
    if ph.skill == 2 then
        hits = Combat.ArcHitAt(cs, x, y, facing, 150, math.rad(60), 1.6 * f, true, 0,
            { src = "skill", slashColor = col })
    elseif ph.skill == 3 or ph.skill == 6 then
        hits = Combat.ArcHitAt(cs, x, y, facing, 145, math.pi * 2, 1.8 * f, true, 1,
            { src = "skill", slashColor = col })
    elseif ph.skill == 4 then
        hits = Combat.ArcHitAt(cs, x, y, facing, 170, math.rad(45), 1.7 * f, true, 0,
            { src = "skill", slashColor = col })
    elseif ph.skill == 5 then
        hits = Combat.ArcHitAt(cs, x, y, facing, 110, math.rad(70), 1.6 * f, true, 0,
            { src = "skill", slashColor = col })
    else
        hits = hits + Combat.ArcHitAt(cs, x, y, facing, 82, math.rad(120), 0.9 * f, true, 0,
            { src = "skill", slashColor = col })
        hits = hits + Combat.ArcHitAt(cs, x, y, facing, 86, math.rad(120), 0.9 * f, true, 0,
            { src = "skill", slashColor = col })
        hits = hits + Combat.ArcHitAt(cs, x, y, facing, 92, math.rad(130), 1.8 * f, true, 0,
            { src = "skill", slashColor = col })
    end
    if hits > 0 then
        if F(p, "phantomMomentum") > 0 then GainMomentum(p, 1) end
        if F(p, "phantomStagger") > 0 then
            for _, e in ipairs(ArcTargets(cs, x, y, facing, 150, math.rad(180))) do
                AddStagger(cs, e, 1)
            end
        end
        if ph.debuff then
            for _, e in ipairs(ArcTargets(cs, x, y, facing, 150, math.rad(180))) do
                if math.random() < 0.5 then AddStagger(cs, e, 1) else AddHunt(cs, e, 1) end
            end
        end
    end
end

SpawnAfterimage = function(cs, phantom, illusion, skillId)
    local p = cs.player
    cs.phantoms = cs.phantoms or {}
    local replay
    if IsSpear() then
        replay = ReplaySpearPhantom
    elseif IsRanged() then
        replay = ReplayRangedPhantom
    else
        replay = ReplayPhantomSkill
    end
    if phantom > 0 then
        local ph = {
            x = p.x, y = p.y, facing = cs.facing, radius = 95,
            t = 0.7, total = 0.7, color = { 150, 220, 255 }, kind = "phantom",
            skill = skillId, coef = phantom,
        }
        cs.phantoms[#cs.phantoms + 1] = ph
        cs.phantomCount = (cs.phantomCount or 0) + 1
        cs.pendingHits[#cs.pendingHits + 1] = { t = 0.35, fn = function()
            replay(cs, ph)
        end }
    end
    if illusion > 0 and math.random() < illusion then
        local ph = {
            x = p.x, y = p.y, facing = cs.facing, radius = 130,
            t = 0.75, total = 0.75, color = { 195, 150, 255 }, kind = "illusion",
            skill = skillId, coef = 0.35, debuff = true,
        }
        cs.phantoms[#cs.phantoms + 1] = ph
        cs.phantomCount = (cs.phantomCount or 0) + 1
        cs.pendingHits[#cs.pendingHits + 1] = { t = 0.40, fn = function()
            replay(cs, ph)
        end }
    end
end

local function StartDash(cs, coef, speed, t, src)
    local dirx, diry, ang, hasInput = DashDir(cs)
    if hasInput then cs.facing = ang end   -- 朝输入方向冲，冲完面朝也转过去
    cs.dash = {
        t = t, dirx = dirx, diry = diry,
        speed = speed, coef = coef, hit = {}, src = src, iframe = true,
    }
end

-- 枪客突进：不是无敌，而是减伤（部分专属可以改成无敌）
local function SpearStartDash(cs, coef, speed, t, iframe, dr)
    local dirx, diry, ang, hasInput = DashDir(cs)
    if hasInput then cs.facing = ang end
    cs.dash = {
        t = t, dirx = dirx, diry = diry,
        speed = speed, coef = coef, hit = {}, src = "dash",
        spear = true, iframe = iframe, dr = dr or 0,
    }
end

function Combat.CastSkill(slot)
    if S.combat and (S.combat.showBuffs or S.combat.paused) then return end
    if IsSpear() then return Combat.SpearCastSkill(slot) end
    if IsRanger() then return Combat.RangerCastSkill(slot) end
    if IsMage() then return Combat.MageCastSkill(slot) end
    local cs = S.combat
    if not cs or cs.showBuffs then return end
    local p = cs.player
    local run = cs.run
    local id = run.loadout[slot]
    local sk = id and Config.SkillByID(id)
    if not sk then return end

    local cd = SkillCD(cs, id, sk.cd)
    local free = (p.freeCharges and p.freeCharges[id]) or 0
    if (p.cooldowns[id] or 0) > 0 then
        if free > 0 then
            p.freeCharges[id] = free - 1
        elseif (p.charges[id] or 0) > 0 then
            p.charges[id] = p.charges[id] - 1
        else
            return
        end
    else
        p.cooldowns[id] = cd
    end

    -- 狂剑士：技能消耗当前生命 10%，但不会把自己扣到 25% 以下
    if F(p, "berserk") > 0 then
        local cost = p.hp * 0.10
        local floorHp = p.maxHp * 0.25
        if p.hp - cost < floorHp then cost = math.max(0, p.hp - floorHp) end
        if cost > 0 then
            p.hp = p.hp - cost
            AddText(cs, p.x, p.y - 52, string.format("-%d", math.floor(cost)), { 255, 120, 120, 255 }, 16)
        end
    end

    -- 柔化/速斩：技能后下一次普攻的额外剑意
    if F(p, "skillIntent") > 0 then cs.nextBasicIntent = 1 end

    local damaging = (id == 1 or id == 2 or id == 4 or id == 6)
    if damaging then
        SpawnAfterimage(cs, F(p, "phantomPct"), F(p, "illusionChance"), id)
    end

    if id == 1 then
        -- 三段斩
        local tp = F(p, "triplePct")
        local fast = 1 - math.min(0.7, F(p, "tripleFast"))
        local wind = F(p, "tripleWind") > 0
        local extend = F(p, "tripleCrackExtend")
        local knock = F(p, "tripleKnock")
        local intentGain = F(p, "tripleIntentAll")
        cs.tripleSegments = 0

        local function segment(delay, range, deg, coef, crackCount, chance, isLast)
            cs.pendingHits[#cs.pendingHits + 1] = { t = delay * fast, fn = function()
                local n = Combat.ArcHit(cs, range, math.rad(deg), coef, true, crackCount, {
                    crackChance = chance,
                    crackExtend = isLast and extend or 0,
                    knock = isLast and knock or 0,
                    staggerChance = isLast and F(p, "staggerChance") or 0,
                    intentGain = intentGain,
                    src = "skill",
                })
                if n > 0 then cs.tripleSegments = (cs.tripleSegments or 0) + 1 end
                if isLast then cs.shake = math.max(cs.shake, 4) end
            end }
        end

        segment(0.05, 82, 120, 1.0 * (1 + tp + F(p, "triple1Pct")), math.floor(F(p, "triple1Crack")), nil, false)
        segment(0.20, 86, 120, 1.1 * (1 + tp), 0, nil, false)
        if wind then
            cs.pendingHits[#cs.pendingHits + 1] = { t = 0.36 * fast, fn = function()
                SwordWave(cs, 1.4 * (1 + tp), true)
                cs.tripleSegments = (cs.tripleSegments or 0) + 1
                cs.shake = math.max(cs.shake, 4)
            end }
        else
            segment(0.36, 92, 130, 1.3 * (1 + tp + F(p, "triple3Pct")), 0, F(p, "triple3CrackChance"), true)
        end

        -- 段数结算 / 空放返还
        cs.pendingHits[#cs.pendingHits + 1] = { t = 0.42 * fast, fn = function()
            if (cs.tripleSegments or 0) >= 3 then
                if F(p, "tripleReset") > 0 then
                    p.cooldowns[1] = 0
                    AddText(cs, p.x, p.y - 70, "瞬斩重置", S.col.gold, 17)
                end
                local bonus = F(p, "tripleFullIntent")
                if bonus > 0 then AddIntent(p, bonus) end
            end
            if (cs.tripleSegments or 0) == 0 and F(p, "missRefund") > 0 then
                p.cooldowns[1] = math.max(0, (p.cooldowns[1] or 0) - cd * F(p, "missRefund"))
            end
        end }
    elseif id == 2 then
        -- 闪影突进
        StartDash(cs, 1.7 * (1 + F(p, "dashPct")), 950 * (1 + F(p, "dashDist")), 0.18, "dash")
        p.invulnTimer = 0.22 + F(p, "dashInvuln")
    elseif id == 3 then
        -- 剑心护体
        cs.swordHeartTimer = 1.8 + F(p, "stanceDur")
        cs.stanceAlive = true
        AddText(cs, p.x, p.y - 48, "剑心", S.col.cyan)
    elseif id == 4 then
        -- 旋刃横斩
        local spinRange = 98 * (1 + F(p, "spinRange"))
        local hits = Combat.ArcHit(cs, spinRange, math.pi * 2, 1.5 * (1 + F(p, "spinPct")), true, 1, {
            crackChance = F(p, "spinCrackChance"),
            staggerChance = F(p, "staggerChance"),
            src = "skill",
        })
        -- 剑舞流转：命中直接叠满挫裂，并缩短格挡冷却
        if F(p, "danceFlow") > 0 then
            for _, e in ipairs(ArcTargets(cs, p.x, p.y, cs.facing, spinRange, math.pi * 2)) do
                e.crack = CrackCap(cs)
                e.crackTimer = 4.0
            end
            if hits > 0 then
                p.cooldowns[5] = math.max(0, (p.cooldowns[5] or 0) - 1.5)
            end
        end
        -- 轮转灭阵：挫裂扩散
        local spread = F(p, "spinSpread")
        if spread > 0 then
            for _, e in ipairs(cs.enemies) do
                if (e.crack or 0) > 0 and Dist(p.x, p.y, e.x, e.y) < spinRange + e.radius
                    and math.random() < spread then
                    for _, o in ipairs(cs.enemies) do
                        if o ~= e and Dist(e.x, e.y, o.x, o.y) < 110 then AddCrack(cs, o, 1) end
                    end
                end
            end
        end
        if hits == 0 and F(p, "missRefund") > 0 then
            p.cooldowns[4] = math.max(0, (p.cooldowns[4] or 0) - cd * F(p, "missRefund"))
        end
        cs.shake = math.max(cs.shake, 6)
    elseif id == 5 then
        -- 卸势格挡：1 秒内免伤，可连续挡下多次攻击
        p.parryTimer = 1.0 + F(p, "parryDur")
        p.parryLeft = 99
        cs.parryFlash = 0.3
        AddText(cs, p.x, p.y - 48, "格挡姿态", S.col.cyan, 18)
        AddRing(cs, p.x, p.y, 66, { 150, 235, 255 }, 0.26, 5)
    elseif id == 6 then
        -- 瞬影连斩
        local stages = 2 + math.floor(F(p, "blinkStages"))
        local coef = 1.2 * (1 + F(p, "blinkPct"))
        local speed = 900 * (1 + F(p, "blinkDist"))
        StartDash(cs, coef, speed, 0.14, "blink")
        p.invulnTimer = 0.45
        for i = 2, stages do
            cs.pendingHits[#cs.pendingHits + 1] = { t = 0.18 * (i - 1), fn = function()
                StartDash(cs, coef, speed, 0.14, "blink")
                p.invulnTimer = 0.2
            end }
        end
    end
end

-- ---------------------------------------------------------------- 枪客技能
local function SpearSkillCD(cs, id, base)
    local p = cs.player
    local cd = base * (1 - p.cdr)
    if id == 2 then cd = cd + F(p, "dashCd") end
    if id == 4 then cd = cd + F(p, "throwCd") end
    if id == 5 then cd = cd + F(p, "backCd") end
    if id == 6 then cd = cd + F(p, "shockCd") end
    if (id == 4 or id == 5 or id == 6) and F(p, "skillCdMul") > 0 then
        cd = cd * (1 + F(p, "skillCdMul"))
    end
    if (cs.comboEchoPenalty or 0) > 0 then cd = cd * 1.2 end
    return math.max(0.5, cd)
end

local function SpearShock(cs, usedMomentum)
    local p = cs.player
    local radius = 140 * (1 + F(p, "shockRange"))
    local base = p.atk * 1.8 * (1 + F(p, "shockPct")) * (1 + p.skillPct)
    local targets = ArcTargets(cs, p.x, p.y, 0, radius, math.pi * 2)
    local hits = 0
    for _, e in ipairs(targets) do
        local amount = base
        if (e.hp / math.max(1, e.maxHp)) < 0.35 and F(p, "executePct") > 0 then
            amount = amount * (1 + F(p, "executePct"))
        end
        Combat.HitEnemy(cs, e, amount, true, true, false, "skill")
        AddStagger(cs, e, 1 + math.floor(F(p, "shockStagger"))
            + (F(p, "shockStaggerStack") > 0 and 1 or 0))
        if F(p, "heavyStagger") > 0 then AddStagger(cs, e, 1) end
        if F(p, "shockHunt") > 0 and math.random() < F(p, "shockHunt") then AddHunt(cs, e, 1) end
        if usedMomentum and (e.crack or 0) > 0 then TryCombo(cs, e, "震荡") end
        local d = Dist(p.x, p.y, e.x, e.y)
        local kb = 40 * (1 + F(p, "shockKnock"))
        if d > 1 then
            e.x = e.x + (e.x - p.x) / d * kb
            e.y = e.y + (e.y - p.y) / d * kb
        end
        hits = hits + 1
    end
    AddRing(cs, p.x, p.y, radius + 10, { 255, 200, 130 }, 0.32, 7)
    AddSlash(cs, p.x, p.y, 0, radius, math.pi * 2, { 255, 215, 150 }, 8)
    AddTelegraph(cs, { kind = "circle", x = p.x, y = p.y, r = radius,
        color = { 255, 205, 145 }, life = 0.4 })
    AddParticles(cs, p.x, p.y, { 255, 205, 140 }, 12)
    cs.shake = math.max(cs.shake, 8)
    if F(p, "shockRefund") > 0 and hits >= 2 and math.random() < F(p, "shockRefund") then
        GainMomentum(p, 1)
    end
    if F(p, "momentumOnSkill") > 0 then GainMomentum(p, 1) end
    return hits
end

function Combat.SpearCastSkill(slot)
    local cs = S.combat
    if not cs or cs.showBuffs then return end
    local p = cs.player
    local id = cs.run.loadout[slot]
    local sk = id and Config.SkillByID(id)
    if not sk then return end

    local cd = SpearSkillCD(cs, id, sk.cd)
    local extraCharges = 0
    if id == 2 then extraCharges = math.floor(F(p, "dashCharges"))
    elseif id == 5 then extraCharges = math.floor(F(p, "backCharges")) end
    local free = (p.freeCharges and p.freeCharges[id]) or 0
    if (p.cooldowns[id] or 0) > 0 then
        if free > 0 then
            p.freeCharges[id] = free - 1
        elseif extraCharges > 0 and (p.charges[id] or 0) > 0 then
            p.charges[id] = p.charges[id] - 1
        else
            return
        end
    else
        p.cooldowns[id] = cd
    end

    -- 消耗 1 层枪势换取连携
    local freeNew = F(p, "momentumFreeNew") > 0 and (id == 4 or id == 5 or id == 6)
    local keepBack = (id == 5 and F(p, "momentumKeepBack") > 0)
    local usedMomentum = false
    if p.intent > 0 and not freeNew and not keepBack then
        p.intent = p.intent - 1
        usedMomentum = true
        AddText(cs, p.x, p.y - 72, "枪势 -1", S.col.orange, 14)
        if id ~= 1 and (F(p, "momentumCrack") > 0 or F(p, "momentumHunt") > 0) then
            cs.momentumDebuffTimer = 1.2
        end
    end

    if F(p, "castAs") > 0 then cs.spearCastAsTimer = 3 end
    SpawnAfterimage(cs, F(p, "phantomPct"), F(p, "illusionChance"), id)

    if id == 1 then
        cs.spearBuffTimer = 5 + F(p, "buffDur")
        cs.spearBuffHits = 3 + math.floor(F(p, "buffHits"))
        AddText(cs, p.x, p.y - 50, "三段枪式", S.col.orange, 17)
        AddRing(cs, p.x, p.y, 60, { 255, 200, 130 }, 0.3, 4)
        AddTelegraph(cs, { kind = "circle", x = p.x, y = p.y, r = 60,
            color = { 255, 205, 140 }, life = 0.4 })
    elseif id == 2 then
        AimAt(cs, 360, math.rad(90))
        local dashSpeed = 1080 * (1 + F(p, "dashDist"))
        SpearStartDash(cs, 1.6 * (1 + F(p, "dashPct")), dashSpeed, 0.20,
            F(p, "dashInvuln") > 0, 0.10)
        cs.dash.usedMomentum = usedMomentum
        AddTelegraph(cs, { kind = "corridor", x = p.x, y = p.y, facing = cs.facing,
            len = dashSpeed * 0.20 + 40, width = 62, color = { 255, 205, 150 }, life = 0.36 })
        if F(p, "next3aPct") > 0 then cs.next3aTimer = 3 end
        if F(p, "momentumOnSkill") > 0 then GainMomentum(p, 1) end
    elseif id == 3 then
        cs.guardTimer = 2.5 + F(p, "guardDur")
        cs.guardUsedMomentum = usedMomentum
        cs.guardReflect = F(p, "guardReflect")
        AddText(cs, p.x, p.y - 50, "铁枪固守", S.col.orange, 17)
        AddRing(cs, p.x, p.y, 70, { 255, 205, 140 }, 0.3, 5)
        AddTelegraph(cs, { kind = "circle", x = p.x, y = p.y, r = 90,
            color = { 255, 205, 140 }, life = 0.45 })
    elseif id == 4 then
        AimAt(cs, 640, math.rad(85))
        local maxDist = 620 * (1 + F(p, "throwRange"))
        cs.spearShots[#cs.spearShots + 1] = {
            x = p.x, y = p.y,
            dirx = math.cos(cs.facing), diry = math.sin(cs.facing),
            speed = 980, traveled = 0, maxDist = maxDist,
            pierce = 3 + math.floor(F(p, "throwPierce")), hit = {},
            dmg = p.atk * 1.7 * (1 + F(p, "throwPct")) * (1 + p.skillPct),
            usedMomentum = usedMomentum,
            stagger = 1 + math.floor(F(p, "throwStagger")),
            returning = false,
        }
        AddTelegraph(cs, { kind = "corridor", x = p.x, y = p.y, facing = cs.facing,
            len = maxDist, width = 46, color = { 255, 205, 150 }, life = 0.5 })
        if F(p, "momentumOnSkill") > 0 then GainMomentum(p, 1) end
    elseif id == 5 then
        AimAt(cs, 360, math.rad(100))
        local back = 60 * (1 + F(p, "backDist"))
        local bx = p.x - math.cos(cs.facing) * back
        local by = p.y - math.sin(cs.facing) * back
        local rx, ry = ResolveCircleWalls(cs, bx, by, p.radius)
        local fromX, fromY = p.x, p.y
        p.x = Config.Clamp(rx, p.radius, WORLD_W - p.radius)
        p.y = Config.Clamp(ry, p.radius, WORLD_H - p.radius)
        AddTrail(cs, p.x, p.y, { 255, 205, 150 }, 13)
        AddTelegraph(cs, { kind = "line", x = fromX, y = fromY, x2 = p.x, y2 = p.y,
            color = { 255, 205, 150 }, life = 0.3 })
        local thrustRange = 170
        local thrustArc = math.rad(85)
        AddTelegraph(cs, { kind = "sector", x = p.x, y = p.y, facing = cs.facing,
            range = thrustRange + 32, arc = thrustArc, color = { 255, 205, 150 }, life = 0.42 })
        if F(p, "backMs") > 0 then cs.spearMsTimer = 2 end
        if F(p, "momentumOnSkill") > 0 then GainMomentum(p, 1) end
        cs.pendingHits[#cs.pendingHits + 1] = { t = 0.14, fn = function()
            -- 后撤之后向前补一段突刺身位，缩掉“撤了打不到”的断层
            local lunge = 52
            local lx = p.x + math.cos(cs.facing) * lunge
            local ly = p.y + math.sin(cs.facing) * lunge
            local lrx, lry = ResolveCircleWalls(cs, lx, ly, p.radius)
            p.x = Config.Clamp(lrx, p.radius, WORLD_W - p.radius)
            p.y = Config.Clamp(lry, p.radius, WORLD_H - p.radius)
            AddTrail(cs, p.x, p.y, { 255, 205, 150 }, 13)

            local tx = p.x + math.cos(cs.facing) * 20
            local ty = p.y + math.sin(cs.facing) * 20
            Combat.ArcHitAt(cs, tx, ty, cs.facing, thrustRange, thrustArc,
                1.75 * (1 + F(p, "backPct")), true, 0,
                { src = "skill", slashColor = { 255, 205, 150 }, slashWidth = 8 })
            for _, e in ipairs(ArcTargets(cs, tx, ty, cs.facing, thrustRange, thrustArc)) do
                AddStagger(cs, e, 1)
                if usedMomentum and (e.crack or 0) > 0 then TryCombo(cs, e, "震荡") end
                if F(p, "backMomentum") > 0 and math.random() < F(p, "backMomentum") then
                    GainMomentum(p, 1)
                end
                if F(p, "backStaggerChance") > 0 and math.random() < F(p, "backStaggerChance") then
                    for _, o in ipairs(cs.enemies) do
                        if o ~= e and Dist(e.x, e.y, o.x, o.y) < 110 then AddStagger(cs, o, 1) end
                    end
                end
            end
            cs.shake = math.max(cs.shake, 5)
        end }
    elseif id == 6 then
        SpearShock(cs, usedMomentum)
        if F(p, "shockWaves") > 0 then
            cs.pendingHits[#cs.pendingHits + 1] = { t = 0.26, fn = function()
                SpearShock(cs, usedMomentum)
            end }
        end
        if F(p, "shockSpreadCrack") > 0 and usedMomentum then
            cs.pendingHits[#cs.pendingHits + 1] = { t = 0.30, fn = function()
                for _, e in ipairs(ArcTargets(cs, p.x, p.y, 0, 180, math.pi * 2)) do
                    if (e.crack or 0) == 0 then AddCrack(cs, e, 1) end
                end
            end }
        end
    end
end

function Combat.SkillCooldown(cs, id)
    local sk = Config.SkillByID(id)
    if not sk then return 0 end
    if IsSpear() then return SpearSkillCD(cs, id, sk.cd) end
    return SkillCD(cs, id, sk.cd)
end


-- ---------------------------------------------------------------- 更新
function Combat.Update(dt)
    local cs = S.combat
    if not cs then return end
    cs.time = cs.time + dt
    -- 长按瞄准：计时；技能不再可用时自动取消
    if cs.aim then
        cs.aim.t = cs.aim.t + dt
        if not Combat.SkillReady(cs, cs.aim.id) then cs.aim = nil end
    end
    if cs.joystick then cs.joystick.visible = not cs.showBuffs end
    if cs.shake > 0 then cs.shake = math.max(0, cs.shake - dt * 30) end
    if cs.attackFlash > 0 then cs.attackFlash = cs.attackFlash - dt end
    if (cs.shieldFlash or 0) > 0 then cs.shieldFlash = math.max(0, cs.shieldFlash - dt) end
    local stanceBefore = cs.swordHeartTimer
    if cs.swordHeartTimer > 0 then cs.swordHeartTimer = cs.swordHeartTimer - dt end
    if stanceBefore > 0 and cs.swordHeartTimer <= 0 then
        -- 剑心护体结束：震波反击
        local shock = F(cs.player, "stanceShock")
        if shock > 0 then
            local p = cs.player
            AddParticles(cs, p.x, p.y, S.col.cyan, 14)
            AddRing(cs, p.x, p.y, 130, { 140, 230, 255 }, 0.35, 7)
            cs.shake = math.max(cs.shake, 6)
            for _, e in ipairs(ArcTargets(cs, p.x, p.y, 0, 125, math.pi * 2)) do
                Combat.HitEnemy(cs, e, p.atk * shock, true, true, false, "skill")
                AddCrack(cs, e, 1)
            end
            AddText(cs, p.x, p.y - 44, "震波", S.col.cyan, 18)
        end
        cs.stanceAlive = false
    end

    -- 面板打开时暂停战斗
    if cs.showBuffs then return end

    Combat.UpdatePlayer(cs, dt)
    if S.screen ~= "combat" then return end
    Combat.UpdateEnemies(cs, dt)
    if S.screen ~= "combat" then return end
    Combat.UpdateBullets(cs, dt)
    Combat.UpdateWaves(cs, dt)
    Combat.UpdateEffects(cs, dt)

    -- 自定义按钮在 Combat.Draw 中直接读玩家状态绘制，无需同步
end

function Combat.UpdatePlayer(cs, dt)
    local p = cs.player

    p.noDamageTimer = p.noDamageTimer + dt
    if p.rageTimer > 0 then p.rageTimer = p.rageTimer - dt end
    if p.parryTimer > 0 then p.parryTimer = p.parryTimer - dt end
    if (cs.parryFlash or 0) > 0 then cs.parryFlash = math.max(0, cs.parryFlash - dt) end
    if p.invulnTimer > 0 then p.invulnTimer = p.invulnTimer - dt end
    if IsSpear() then
        -- 枪势不会自然衰减
        if p.intent > ResourceMax(p) then p.intent = ResourceMax(p) end
    else
        if p.intentTimer > 0 then
            p.intentTimer = p.intentTimer - dt
            if p.intentTimer <= 0 then p.intent = 0 end
        end
        if p.intent > IntentMax(p) then p.intent = IntentMax(p) end
    end
    if (cs.spearBuffTimer or 0) > 0 then
        cs.spearBuffTimer = cs.spearBuffTimer - dt
        if cs.spearBuffTimer <= 0 then cs.spearBuffHits = 0 end
    end
    if (cs.spearCastAsTimer or 0) > 0 then cs.spearCastAsTimer = cs.spearCastAsTimer - dt end
    if (cs.spearMsTimer or 0) > 0 then cs.spearMsTimer = cs.spearMsTimer - dt end
    if (cs.next3aTimer or 0) > 0 then cs.next3aTimer = cs.next3aTimer - dt end
    if (cs.momentumDebuffTimer or 0) > 0 then cs.momentumDebuffTimer = cs.momentumDebuffTimer - dt end
    if (cs.guardTimer or 0) > 0 then
        cs.guardTimer = cs.guardTimer - dt
        if cs.guardTimer <= 0 then
            cs.guardTimer = 0
            SpearShock(cs, cs.guardUsedMomentum)
            if F(p, "guardSlam") > 0 then
                local slam = p.atk * F(p, "guardSlam") * (1 + p.skillPct)
                for _, e in ipairs(ArcTargets(cs, p.x, p.y, 0, 150, math.pi * 2)) do
                    Combat.HitEnemy(cs, e, slam, true, true, false, "skill")
                    AddStagger(cs, e, 1)
                    if cs.guardUsedMomentum and (e.crack or 0) > 0 and F(p, "guardSlamCombo") > 0 then
                        TryCombo(cs, e, "震荡")
                    end
                end
                AddRing(cs, p.x, p.y, 160, { 255, 220, 150 }, 0.35, 8)
                cs.shake = math.max(cs.shake, 10)
            end
        end
    end
    if cs.comboEchoPenalty > 0 then cs.comboEchoPenalty = cs.comboEchoPenalty - dt end
    if cs.parryDmgTimer > 0 then cs.parryDmgTimer = cs.parryDmgTimer - dt end
    if cs.parryLifestealTimer > 0 then cs.parryLifestealTimer = cs.parryLifestealTimer - dt end
    if cs.crackCapTimer > 0 then cs.crackCapTimer = cs.crackCapTimer - dt end
    if cs.comboWeakTimer and cs.comboWeakTimer > 0 then cs.comboWeakTimer = cs.comboWeakTimer - dt end
    if (cs.healTextTimer or 0) > 0 then cs.healTextTimer = cs.healTextTimer - dt end

    for id, v in pairs(p.cooldowns) do
        if v > 0 then
            p.cooldowns[id] = math.max(0, v - dt)
        else
            -- 冷却结束后补满充能（双重闪击 / 轮转灭阵）
            local maxc = ChargeMax(p, id) - 1
            if maxc > 0 and (p.charges[id] or 0) < maxc then p.charges[id] = maxc end
        end
    end

    if p.regen > 0 then
        p.hp = math.min(p.maxHp, p.hp + p.regen * dt)
    end
    if p.hurtHealTimer > 0 then
        p.hurtHealTimer = p.hurtHealTimer - dt
        local heal = p.hurtHealAmount * dt / 2
        p.hp = math.min(p.maxHp, p.hp + heal)
        if p.hurtHealTimer <= 0 then p.hurtHealAmount = 0 end
    end
    if p.noDamageTimer > 5 and p.shield < p.maxShield then
        p.shield = math.min(p.maxShield, p.shield + p.maxShield * 0.10 * dt)
    end

    -- 移动
    local ix, iy = S.input.x, S.input.y
    local mag = math.sqrt(ix * ix + iy * iy)
    local speed = p.moveSpeed
    if p.rageTimer > 0 then speed = speed * 1.2 end
    if cs.swordHeartTimer > 0 then speed = speed * 1.25 end
    if (cs.spearMsTimer or 0) > 0 then speed = speed * (1 + F(p, "backMs")) end
    if (p.hazardSlowTimer or 0) > 0 then speed = speed * 0.7 end
    -- 狂剑士：攻速随缺血提升，移速不变；追击本能：场上有残血敌人时加速
    local execMs = F(p, "executeMs")
    if execMs > 0 then
        for _, e in ipairs(cs.enemies) do
            if e.hp < e.maxHp * 0.3 and Dist(p.x, p.y, e.x, e.y) < 260 then
                speed = speed * (1 + execMs)
                break
            end
        end
    end

    if mag > 0.12 then
        local nx, ny = ix / mag, iy / mag
        p.x = p.x + nx * speed * mag * dt
        p.y = p.y + ny * speed * mag * dt
        if mag > 0.2 then cs.facing = math.atan(ny, nx) end
    end

    -- 冲刺
    if cs.dash then
        local d = cs.dash
        d.t = d.t - dt
        d.trailTimer = (d.trailTimer or 0) - dt
        if d.trailTimer <= 0 then
            d.trailTimer = 0.025
            AddTrail(cs, p.x, p.y,
                d.src == "blink" and { 190, 160, 255 } or { 130, 205, 255 }, 12)
        end
        p.x = p.x + d.dirx * d.speed * dt
        p.y = p.y + d.diry * d.speed * dt
        for i = #cs.enemies, 1, -1 do
            local e = cs.enemies[i]
            local already = e == nil
            if e then
                for _, hit in ipairs(d.hit) do
                    if hit == e then already = true end
                end
            end
            if e and not already and Dist(p.x, p.y, e.x, e.y) < e.radius + 34 then
                d.hit[#d.hit + 1] = e
                local idx = #d.hit
                if d.spear then
                    local extra = (idx > 1) and F(p, "dashPierce") or 0
                    Combat.HitEnemy(cs, e, p.atk * d.coef * (1 + p.skillPct) * (1 + extra),
                        true, true, false, "dash")
                    AddCrack(cs, e, 1)
                    if F(p, "dashStagger") > 0 then AddStagger(cs, e, 1) end
                    if F(p, "huntOnStagger") > 0 and math.random() < F(p, "huntOnStagger") then
                        AddHunt(cs, e, 1)
                    end
                    if F(p, "dashHeal") > 0 then
                        p.hp = math.min(p.maxHp, p.hp + p.maxHp * F(p, "dashHeal"))
                        AddText(cs, p.x, p.y - 70, "+" .. math.floor(p.maxHp * F(p, "dashHeal")),
                            S.col.green, 14)
                    end
                    if d.usedMomentum and (e.crack or 0) > 0 then
                        TryCombo(cs, e, "震荡")
                    end
                    AddRing(cs, e.x, e.y, e.radius + 22, { 255, 205, 140 }, 0.22, 4)
                    AddParticles(cs, e.x, e.y, { 255, 215, 160 }, 4)
                else
                    local extra = (idx > 1) and F(p, "dashPierce") or 0
                    Combat.HitEnemy(cs, e, p.atk * d.coef * (1 + p.skillPct) * (1 + extra),
                        true, true, false, d.src)
                    AddRing(cs, e.x, e.y, e.radius + 22,
                        d.src == "blink" and { 195, 160, 255 } or { 150, 225, 255 }, 0.22, 4)
                    AddParticles(cs, e.x, e.y, { 210, 235, 255 }, 4)
                    AddIntent(p, 1)
                    if d.src == "dash" and F(p, "dashCrack") > 0 then AddCrack(cs, e, 1) end
                    if d.src == "dash" and F(p, "dashHeal") > 0 then
                        p.hp = math.min(p.maxHp, p.hp + p.maxHp * F(p, "dashHeal"))
                    end
                    if d.src == "blink" then
                        if F(p, "blinkCrackExtend") > 0 then ExtendCrack(e, F(p, "blinkCrackExtend")) end
                        if F(p, "danceFlow") > 0 then
                            e.crack, e.crackTimer = CrackCap(cs), 4.0
                            p.cooldowns[5] = math.max(0, (p.cooldowns[5] or 0) - 1.5)
                        end
                        if F(p, "blinkCombo") > 0 then TryCombo(cs, e, "粉碎") end
                    end
                end
            end
        end
        if d.t <= 0 then
            if d.src == "dash" and not d.spear then
                if #d.hit > 0 then
                    p.cooldowns[2] = math.max(0, (p.cooldowns[2] or 0) - 0.8)
                elseif F(p, "missRefund") > 0 then
                    local sk2 = Config.SkillByID(2)
                    local base = (sk2 and sk2.cd or 6.0) * (1 - p.cdr)
                    p.cooldowns[2] = math.max(0, (p.cooldowns[2] or 0) - base * F(p, "missRefund"))
                end
            elseif d.spear and #d.hit > 0 then
                -- 突刺收尾：给一点停顿感（震屏 + 环 + 叠失衡），别像滑过去
                cs.shake = math.max(cs.shake, 6)
                AddRing(cs, p.x, p.y, 78, { 255, 205, 140 }, 0.24, 4)
                for _, e in ipairs(cs.enemies) do
                    if Dist(p.x, p.y, e.x, e.y) < 92 then AddStagger(cs, e, 1) end
                end
            elseif d.src == "blink" and #d.hit == 0 and F(p, "missRefund") > 0 then
                local sk6 = Config.SkillByID(6)
                local base = (sk6 and sk6.cd or 7.0) * (1 - p.cdr)
                p.cooldowns[6] = math.max(0, (p.cooldowns[6] or 0) - base * F(p, "missRefund"))
            end
            cs.dash = nil
        end
    end

    -- 剑气波
    if cs.windWaves then
        for i = #cs.windWaves, 1, -1 do
            local w = cs.windWaves[i]
            w.x = w.x + w.dirx * w.speed * dt
            w.y = w.y + w.diry * w.speed * dt
            w.life = w.life - dt
            w.trail = (w.trail or 0) - dt
            if w.trail <= 0 then
                w.trail = 0.04
                AddParticles(cs, w.x, w.y, { 150, 230, 255 }, 2)
            end

            for b = #cs.bullets, 1, -1 do
                local bu = cs.bullets[b]
                if not bu.shock and Dist(w.x, w.y, bu.x, bu.y) < w.r + (bu.r or 6) then
                    table.remove(cs.bullets, b)
                end
            end
            for _, e in ipairs(cs.enemies) do
                local already = false
                for _, h in ipairs(w.hit) do if h == e then already = true end end
                if not already and Dist(w.x, w.y, e.x, e.y) < e.radius + w.r * 0.5 then
                    w.hit[#w.hit + 1] = e
                    Combat.HitEnemy(cs, e, p.atk * w.coef * (1 + p.skillPct), true, true, false, "skill")
                    if w.crack > 0 then AddCrack(cs, e, w.crack) end
                end
            end
            if w.life <= 0 or PointInWalls(cs, w.x, w.y) then table.remove(cs.windWaves, i) end
        end
    end

    -- 掷枪（可折返）
    if cs.spearShots then
        for i = #cs.spearShots, 1, -1 do
            local s = cs.spearShots[i]
            local step = s.speed * dt
            s.x = s.x + s.dirx * step
            s.y = s.y + s.diry * step
            s.traveled = s.traveled + step
            AddParticles(cs, s.x, s.y, { 255, 210, 150 }, 1)
            for _, e in ipairs(cs.enemies) do
                local already = false
                for _, h in ipairs(s.hit) do if h == e then already = true end end
                if not already and #s.hit < s.pierce and Dist(s.x, s.y, e.x, e.y) < e.radius + 14 then
                    s.hit[#s.hit + 1] = e
                    Combat.HitEnemy(cs, e, s.dmg, true, true, false, "skill", false)
                    AddStagger(cs, e, s.stagger)
                    if F(p, "throwStaggerChance") > 0 and math.random() < F(p, "throwStaggerChance") then
                        AddStagger(cs, e, 1)
                    end
                    if s.usedMomentum and (e.crack or 0) > 0 then TryCombo(cs, e, "震荡") end
                    if F(p, "huntOnStagger") > 0 and math.random() < F(p, "huntOnStagger") then
                        AddHunt(cs, e, 1)
                    end
                    AddRing(cs, e.x, e.y, e.radius + 18, { 255, 210, 150 }, 0.2, 3)
                end
            end
            local remove = s.traveled >= s.maxDist or PointInWalls(cs, s.x, s.y)
            if s.traveled >= s.maxDist and F(p, "throwReturn") > 0 and not s.returning then
                s.returning = true
                s.dirx = -s.dirx
                s.diry = -s.diry
                s.traveled = 0
                s.hit = {}
                remove = false
            end
            if remove then table.remove(cs.spearShots, i) end
        end
    end

    -- 枪风领域
    if cs.spearFields then
        for i = #cs.spearFields, 1, -1 do
            local f = cs.spearFields[i]
            f.t = f.t + dt
            f.tick = (f.tick or 0) - dt
            if f.tick <= 0 then
                f.tick = 0.5
                for _, e in ipairs(cs.enemies) do
                    if Dist(f.x, f.y, e.x, e.y) < f.r + e.radius then
                        Combat.HitEnemy(cs, e, f.dmg, false, true, false, "skill")
                        if f.stagger then AddStagger(cs, e, 1) end
                    end
                end
            end
            if f.t >= f.life then table.remove(cs.spearFields, i) end
        end
    end

    -- 玩家异常状态
    if (p.infectTimer or 0) > 0 then
        p.infectTimer = p.infectTimer - dt
        p.infectTick = (p.infectTick or 0) - dt
        if p.infectTick <= 0 then
            p.infectTick = 0.5
            Combat.DamagePlayer(cs, (p.infectDps or 0) * 0.5)
        end
    end
    if (p.necrosisTimer or 0) > 0 then p.necrosisTimer = p.necrosisTimer - dt end
    if (p.weakenTimer or 0) > 0 then p.weakenTimer = p.weakenTimer - dt end
    if (p.hazardSlowTimer or 0) > 0 then p.hazardSlowTimer = p.hazardSlowTimer - dt end
    if (cs.rapidTimer or 0) > 0 then
        cs.rapidTimer = cs.rapidTimer - dt
        if cs.rapidTimer <= 0 then cs.rapidStacks = 0 end
    end
    if (cs.resonanceTimer or 0) > 0 then
        cs.resonanceTimer = cs.resonanceTimer - dt
        if cs.resonanceTimer <= 0 then cs.resonanceStacks = 0 end
    end
    if (cs.overloadTimer or 0) > 0 then cs.overloadTimer = cs.overloadTimer - dt end
    if (cs.chaosTimer or 0) > 0 then cs.chaosTimer = cs.chaosTimer - dt end
    if (cs.phoenixCd or 0) > 0 then cs.phoenixCd = cs.phoenixCd - dt end

    -- 远程弹道
    if cs.projs then
        for i = #cs.projs, 1, -1 do
            local pr = cs.projs[i]
            pr.x = pr.x + pr.vx * dt
            pr.y = pr.y + pr.vy * dt
            pr.life = pr.life - dt
            local remove = pr.life <= 0 or PointInWalls(cs, pr.x, pr.y)
            if not remove then
                for _, e in ipairs(cs.enemies) do
                    local already = false
                    for _, h in ipairs(pr.hit) do if h == e then already = true end end
                    if not already and Dist(pr.x, pr.y, e.x, e.y) < e.radius + pr.r then
                        pr.hit[#pr.hit + 1] = e
                        local amount = pr.dmg
                        if pr.execute and (e.hp / math.max(1, e.maxHp)) < 0.5
                            and math.random() < pr.execute then
                            amount = amount * 1.5
                        end
                        Combat.HitEnemy(cs, e, amount, pr.isSkill, true, false,
                            pr.isSkill and "skill" or "basic", pr.crit)
                        if pr.hunt > 0 then AddHunt(cs, e, pr.hunt) end
                        if pr.slow and pr.slow > 0 then SlowEnemy(e, 2, pr.slow) end
                        if pr.element then ApplyElementHit(cs, e, pr.element, pr.skill) end
                        if pr.splash and pr.splashPct then
                            local n = 0
                            for _, o in ipairs(cs.enemies) do
                                if o ~= e and n < 1 and Dist(e.x, e.y, o.x, o.y) < 80 then
                                    Combat.HitEnemy(cs, o, amount * pr.splashPct, pr.isSkill, true, false, "skill")
                                    AddHunt(cs, o, 1)
                                    n = n + 1
                                end
                            end
                        end
                        if pr.lifesteal and pr.lifesteal > 0 then
                            HealPlayer(p, amount * pr.lifesteal)
                        end
                        if pr.boom and pr.boom > 0 then
                            for _, o in ipairs(ArcTargets(cs, e.x, e.y, 0, 80, math.pi * 2)) do
                                if o ~= e then
                                    Combat.HitEnemy(cs, o, p.atk * pr.boom * (1 + p.skillPct), true, true, false, "skill")
                                    AddHunt(cs, o, 1)
                                end
                            end
                            AddRing(cs, e.x, e.y, 80, { 255, 225, 150 }, 0.25, 4)
                        end
                        if pr.combo and (e.stagger or 0) > 0 and (e.hunt or 0) > 0 then
                            TryCombo(cs, e, pr.combo)
                        end
                        if not pr.isSkill and (cs.rangerSwapCombo or 0) > 0 then
                            if (e.stagger or 0) > 0 then TryCombo(cs, e, "追猎") end
                            cs.rangerSwapCombo = 0
                        end
                        if not pr.isSkill then
                            -- 游侠普攻相关的专属
                            if (cs.rapidTimer or 0) > 0 and (cs.rapidStacks or 0) < 5 then
                                cs.rapidStacks = (cs.rapidStacks or 0) + 1
                            end
                            if F(p, "huntCdr") > 0 and (e.hunt or 0) > 0 then
                                for oid, v in pairs(p.cooldowns) do
                                    if v > 0 then p.cooldowns[oid] = math.max(0, v - F(p, "huntCdr")) end
                                end
                            end
                            if F(p, "huntBasicPct") > 0 and (e.hunt or 0) > 0 then
                                Combat.HitEnemy(cs, e, amount * F(p, "huntBasicPct") * (e.hunt or 0),
                                    false, true, true, "basic")
                            end
                            if F(p, "staggerOnHunt") > 0 and (e.hunt or 0) > 0
                                and math.random() < F(p, "staggerOnHunt") then AddStagger(cs, e, 1) end
                            if F(p, "huntTargetStagger") > 0 and (e.hunt or 0) > 0
                                and math.random() < F(p, "huntTargetStagger") then AddStagger(cs, e, 1) end
                            if F(p, "huntTargetCrack") > 0 and (e.hunt or 0) > 0
                                and math.random() < F(p, "huntTargetCrack") then AddCrack(cs, e, 1) end
                            if F(p, "critHunt") > 0 and pr.crit then AddHunt(cs, e, 1) end
                            if F(p, "critSlow") > 0 and pr.crit then SlowEnemy(e, 2, 0.6) end
                            if F(p, "fateArrow") > 0 then
                                local roll = math.random(1, 3)
                                if roll == 1 then
                                    for _, o in ipairs(ArcTargets(cs, e.x, e.y, 0, 70, math.pi * 2)) do
                                        if o ~= e then Combat.HitEnemy(cs, o, amount * 0.5, false, true, false, "basic") end
                                    end
                                elseif roll == 2 then
                                    HealPlayer(p, amount * 0.12)
                                else
                                    Combat.HitEnemy(cs, e, amount * 0.4, false, true, true, "basic")
                                end
                            end
                        end
                        if #pr.hit > pr.pierce then
                            remove = true
                            break
                        end
                    end
                end
            end
            if remove then table.remove(cs.projs, i) end
        end
    end

    -- 法师地面（暴风雪 / 静电力场 / 余烬）
    if cs.mageFields then
        for i = #cs.mageFields, 1, -1 do
            local f = cs.mageFields[i]
            f.t = f.t + dt
            f.tick = (f.tick or 0) - dt
            if f.tick <= 0 then
                f.tick = 0.5
                for _, e in ipairs(cs.enemies) do
                    if Dist(f.x, f.y, e.x, e.y) < f.r + e.radius then
                        local mul = f.element and ElemMul(cs, f.element) or 1
                        Combat.HitEnemy(cs, e, p.atk * (f.dmg or 0.2) * mul * (1 + p.skillPct),
                            true, true, false, "skill")
                        if f.slow and f.slow > 0 then SlowEnemy(e, 1.2, f.slow) end
                        if f.ember then
                            -- 余烬只是地面灼烧：不再触发"火系命中"，否则会不断生成新余烬（指数级叠层）
                            SlowEnemy(e, 1.2, 0.15 + F(p, "emberSlow"))
                        elseif f.element then
                            ApplyElementHit(cs, e, f.element, f.skill)
                        end
                        if f.eternal then
                            SlowEnemy(e, 1.2, 0.5)
                            Combat.HitEnemy(cs, e, p.atk * 0.15 * dt, true, true, true, "skill")
                        end
                    end
                end
            end
            if f.t >= f.life then table.remove(cs.mageFields, i) end
        end
    end

    -- 游侠陷阱
    if cs.rangerTraps then
        for i = #cs.rangerTraps, 1, -1 do
            local tr = cs.rangerTraps[i]
            tr.t = tr.t - dt
            local triggered = false
            for _, e in ipairs(cs.enemies) do
                if Dist(tr.x, tr.y, e.x, e.y) < tr.r + e.radius then
                    SlowEnemy(e, 2, tr.slow)
                    e.rootTimer = math.max(e.rootTimer or 0, tr.root or 1.2)   -- 夹住：短时间不能移动
                    AddHunt(cs, e, tr.hunt)
                    if F(p, "trapHuntAoe") > 0 then
                        for _, o in ipairs(cs.enemies) do
                            if o ~= e and Dist(e.x, e.y, o.x, o.y) < 100 then AddHunt(cs, o, 1) end
                        end
                    end
                    cs.rangerCrit = math.min(3, (cs.rangerCrit or 0) + tr.crit)
                    if F(p, "huntCycle") > 0 then
                        p.cooldowns[5] = 0
                        p.cooldowns[6] = 0
                    end
                    AddRing(cs, tr.x, tr.y, tr.r, { 190, 245, 200 }, 0.3, 4)
                    triggered = true
                    break
                end
            end
            if triggered or tr.t <= 0 then table.remove(cs.rangerTraps, i) end
        end
    end

    -- 怪物地面（脓水 / 腐液 / 衰竭疫域）
    if cs.hazardFields then
        for i = #cs.hazardFields, 1, -1 do
            local hz = cs.hazardFields[i]
            hz.t = hz.t + dt
            hz.tick = (hz.tick or 0) - dt
            if hz.tick <= 0 then
                hz.tick = 0.5
                if Dist(p.x, p.y, hz.x, hz.y) < hz.r + p.radius then
                    Combat.DamagePlayer(cs, (hz.dps or 0) * 0.5)
                    if hz.slow then p.hazardSlowTimer = 0.6 end
                end
            end
            if hz.t >= hz.life then table.remove(cs.hazardFields, i) end
        end
    end

    local px, py = ResolveCircleWalls(cs, p.x, p.y, p.radius)
    p.x = Config.Clamp(px, p.radius, WORLD_W - p.radius)
    p.y = Config.Clamp(py, p.radius, WORLD_H - p.radius)

    -- 朝向最近敌人
    ---@type Enemy|nil
    local nearest = nil
    local nearestD = 340.0
    for _, e in ipairs(cs.enemies) do
        local d = Dist(p.x, p.y, e.x, e.y)
        if d < nearestD then nearest, nearestD = e, d end
    end
    if nearest then
        cs.facing = math.atan(nearest.y - p.y, nearest.x - p.x)
    end

    -- 普攻
    p.attackTimer = p.attackTimer - dt
    if p.attackQueued and p.attackTimer <= 0 then
        p.attackQueued = false
        Combat.BasicAttack(cs)
        p.attackTimer = Combat.AttackCooldown(cs)
    end
    if p.attackTimer <= 0 and nearest and Opt("autoAttack", true) then
        local class = Config.Class()
        local range = class.basicRange * (1 + p.rangePct) + nearest.radius
        if IsSpear() and p.intent > 0 then range = range + 32 end
        -- 鬼剑术：剑气满时普攻变远程剑气，自动锁敌距离同步拉长
        if F(p, "oni") > 0 and p.intent >= IntentMax(p) then range = 560 end
        if nearestD <= range then
            Combat.BasicAttack(cs)
            p.attackTimer = Combat.AttackCooldown(cs)
        end
    end

    -- 延迟攻击
    for i = #cs.pendingHits, 1, -1 do
        local ph = cs.pendingHits[i]
        ph.t = ph.t - dt
        if ph.t <= 0 then
            table.remove(cs.pendingHits, i)
            ph.fn()
        end
    end

    -- 剑影淡出
    if cs.phantoms then
        for i = #cs.phantoms, 1, -1 do
            local ph = cs.phantoms[i]
            ph.t = ph.t - dt
            if ph.t <= 0 then table.remove(cs.phantoms, i) end
        end
    end
end

-- 新怪物的命中负面 / 地面效果
local function ApplyEnemyDebuff(cs, e)
    local p = cs.player
    if e.id == "abscess" then
        p.infectTimer = 4
        p.infectDps = e.atk * 0.8
        p.infectTick = 0.5
        AddText(cs, p.x, p.y - 86, "感染", S.col.red, 14)
    elseif e.id == "golem" then
        p.necrosisTimer = 4
        AddText(cs, p.x, p.y - 86, "坏死", S.col.purple, 14)
    elseif e.id == "colossus" then
        p.weakenTimer = 4
        AddText(cs, p.x, p.y - 86, "衰弱", S.col.purple, 14)
    end
end

local function AddHazard(cs, x, y, r, life, dps, slow)
    cs.hazardFields[#cs.hazardFields + 1] = {
        x = x, y = y, r = r, t = 0, life = life, dps = dps, slow = slow, tick = 0,
    }
end

function Combat.UpdateEnemies(cs, dt)
    local p = cs.player

    -- 流血结算
    for i = #cs.enemies, 1, -1 do
        local e = cs.enemies[i]
        if e and (e.bleedTimer or 0) > 0 then
            e.bleedTimer = e.bleedTimer - dt
            e.bleedTick = (e.bleedTick or 0.5) - dt
            if e.bleedTick <= 0 then
                e.bleedTick = 0.5
                Combat.HitEnemy(cs, e, (e.bleedDps or 0) * 0.5, false, true, true, "bleed")
                if F(p, "bleedRefresh") > 0 and (e.crack or 0) > 0 then e.crackTimer = 4.0 end
            end
            if e.bleedTimer <= 0 then e.bleedDps = 0 end
        end
    end
    -- 燃烧结算
    for i = #cs.enemies, 1, -1 do
        local e = cs.enemies[i]
        if e and (e.burnTimer or 0) > 0 then
            e.burnTimer = e.burnTimer - dt
            e.burnTick = (e.burnTick or 0.5) - dt
            if e.burnTick <= 0 then
                e.burnTick = 0.5
                Combat.HitEnemy(cs, e, (e.burnDps or 0) * 0.5, false, false, true, "burn")
            end
            if e.burnTimer <= 0 then
                e.burnDps = 0
                e.burnStacks = 0
            end
        end
    end
    if S.screen ~= "combat" then return end

    for _, e in ipairs(cs.enemies) do
        if e.hitFlash > 0 then e.hitFlash = e.hitFlash - dt end
        if (e.freezeTimer or 0) > 0 then e.freezeTimer = e.freezeTimer - dt end
        if (e.crack or 0) > 0 and F(p, "crackNoDecay") <= 0 then
            if (e.crackFlash or 0) > 0 then
                e.crackFlash = math.max(0, e.crackFlash - dt)
            end
            if e.crackTimer > 0 then
                e.crackTimer = e.crackTimer - dt
                if e.crackTimer <= 0 then e.crack = 0 end
            end
        end
        if e.staggerTimer and e.staggerTimer > 0 then
            e.staggerTimer = e.staggerTimer - dt
            if e.staggerTimer <= 0 then e.stagger = 0 end
        end
        if e.huntTimer and e.huntTimer > 0 then
            e.huntTimer = e.huntTimer - dt
            if e.huntTimer <= 0 then e.hunt = 0 end
        end
        if e.slowTimer > 0 then e.slowTimer = e.slowTimer - dt end
        if (e.rootTimer or 0) > 0 then
            e.rootTimer = e.rootTimer - dt
            if e.rootTimer <= 0 then e.rootTimer = nil end
        end
        if (e.penVulnTimer or 0) > 0 then
            e.penVulnTimer = e.penVulnTimer - dt
            if e.penVulnTimer <= 0 then e.penVulnTimer = nil end
        end

        local d = Dist(e.x, e.y, p.x, p.y)
        local spd = e.speed
        if (e.rootTimer or 0) > 0 then spd = 0 end   -- 被夹子束缚
        if e.enraged then spd = spd * 1.3 end
        if e.slowTimer > 0 then spd = spd * (1 - (e.slowPct or 0.45)) end
        if (e.freezeTimer or 0) > 0 then spd = spd * 0.15 end
        if (e.stagger or 0) > 0 then spd = spd * 0.88 end

        local oldX, oldY = e.x, e.y
        local bossCharging = e.behavior == "boss" and e.chargeState ~= nil

        if e.behavior == "shooter" then
            if d > 320 then
                e.x = e.x + (p.x - e.x) / d * spd * dt
                e.y = e.y + (p.y - e.y) / d * spd * dt
            elseif d < 190 and d > 1 then
                e.x = e.x - (p.x - e.x) / d * spd * dt
                e.y = e.y - (p.y - e.y) / d * spd * dt
            end
            e.shootCd = e.shootCd - dt
            if e.shootCd <= 0 and d < 560 then
                e.shootCd = 2.2
                local a = math.atan(p.y - e.y, p.x - e.x)
                cs.bullets[#cs.bullets + 1] = {
                    x = e.x, y = e.y,
                    vx = math.cos(a) * 210, vy = math.sin(a) * 210,
                    r = 7, dmg = e.atk, life = 4.0, color = { 140, 230, 170 },
                }
            end
        elseif not bossCharging then
            if d > e.radius + p.radius + 2 then
                e.x = e.x + (p.x - e.x) / d * spd * dt
                e.y = e.y + (p.y - e.y) / d * spd * dt
            end
            e.attackCd = e.attackCd - dt
            if d <= e.radius + p.radius + 6 and e.attackCd <= 0 then
                e.attackCd = 0.9
                Combat.DamagePlayer(cs, e.atk)
                ApplyEnemyDebuff(cs, e)
            end
            if e.id == "abscess" and not e.pusDone and e.hp < e.maxHp * 0.4 then
                e.pusDone = true
                AddHazard(cs, e.x, e.y, 60, 5, e.atk * 0.4, true)
                AddParticles(cs, e.x, e.y, { 190, 150, 100 }, 10)
            end
        end

        local ex, ey = ResolveCircleWalls(cs, e.x, e.y, e.radius)
        -- 被墙正面挡住时尝试沿垂直方向滑动，避免绕不过墙角
        if d > e.radius + p.radius + 8 and Dist(ex, ey, oldX, oldY) < spd * dt * 0.4 then
            local nx2 = -(p.y - oldY) / d
            local ny2 = (p.x - oldX) / d
            local sx2, sy2 = ResolveCircleWalls(cs, oldX + nx2 * spd * dt, oldY + ny2 * spd * dt, e.radius)
            if Dist(sx2, sy2, oldX, oldY) > Dist(ex, ey, oldX, oldY) then
                ex, ey = sx2, sy2
            end
        end
        e.x = Config.Clamp(ex, e.radius, WORLD_W - e.radius)
        e.y = Config.Clamp(ey, e.radius, WORLD_H - e.radius)

        if e.behavior == "golem" then
            e.stompCd = (e.stompCd or 4.0) - dt
            if e.stompCd <= 0 then
                e.stompCd = 5.0
                AddHazard(cs, e.x, e.y, 85, 4.0, e.atk * 0.5, true)
                AddRing(cs, e.x, e.y, 90, { 180, 130, 80 }, 0.3, 5)
                AddParticles(cs, e.x, e.y, { 160, 120, 80 }, 10)
            end
        elseif e.behavior == "colossus" then
            e.decayCd = (e.decayCd or 0) - dt
            if e.decayCd <= 0 then
                e.decayCd = 0.5
                if Dist(e.x, e.y, p.x, p.y) < 180 then
                    Combat.DamagePlayer(cs, e.atk * 0.3)
                    p.hazardSlowTimer = 0.6
                end
            end
            e.bossSkillCd = (e.bossSkillCd or 4.0) - dt
            if e.bossSkillCd <= 0 then
                e.bossSkillCd = e.enraged and 4.0 or 5.0
                cs.bullets[#cs.bullets + 1] = {
                    x = e.x, y = e.y, r = 0, maxR = 360, speed = 230,
                    dmg = e.atk * 1.2, hit = false, shock = true,
                    segCount = 72, segments = MakeRingSegments(72),
                }
                AddHazard(cs, e.x, e.y, 150, 3.0, e.atk * 0.3, true)
            end
            if not e.enraged and e.hp < e.maxHp * 0.5 then
                e.enraged = true
                AddRing(cs, e.x, e.y, 200, { 160, 90, 200 }, 0.5, 10)
                S.toast.text = "瘟衰巨像进入狂暴"
                S.toast.t = 2.0
            end
            if not e.exploded and e.hp < e.maxHp * 0.3 then
                e.exploded = true
                AddHazard(cs, e.x, e.y, 200, 5.0, e.atk * 0.5, true)
                AddRing(cs, e.x, e.y, 220, { 200, 100, 200 }, 0.5, 10)
            end
        elseif e.behavior == "elite" then
            e.burstCd = e.burstCd - dt
            if e.burstCd <= 0 then
                e.burstCd = 4.5
                for k = 1, 8 do
                    local a = k / 8 * math.pi * 2
                    cs.bullets[#cs.bullets + 1] = {
                        x = e.x, y = e.y,
                        vx = math.cos(a) * 170, vy = math.sin(a) * 170,
                        r = 7, dmg = e.atk * 0.8, life = 3.0, color = { 180, 220, 110 },
                    }
                end
            end
        elseif e.behavior == "boss" then
            if not e.enraged and e.hp < e.maxHp * 0.5 then
                e.enraged = true
                S.toast.text = "高热疫魔进入狂暴"
                S.toast.t = 2.0
            end

            if e.chargeState == "telegraph" then
                e.chargeT = e.chargeT - dt
                if e.chargeT <= 0 then
                    e.chargeState = "dash"
                    e.chargeT = 0.32
                    e.chargeHit = false
                end
            elseif e.chargeState == "dash" then
                e.x = e.x + e.chargeDirX * 520 * dt
                e.y = e.y + e.chargeDirY * 520 * dt
                local cx2, cy2 = ResolveCircleWalls(cs, e.x, e.y, e.radius)
                e.x = Config.Clamp(cx2, e.radius, WORLD_W - e.radius)
                e.y = Config.Clamp(cy2, e.radius, WORLD_H - e.radius)
                if not e.chargeHit and Dist(e.x, e.y, p.x, p.y) < e.radius + p.radius + 12 then
                    e.chargeHit = true
                    Combat.DamagePlayer(cs, e.atk * 2)
                    cs.shake = math.max(cs.shake, 10)
                end
                e.chargeT = e.chargeT - dt
                if e.chargeT <= 0 then
                    e.chargeState = nil
                    e.chargeCd = 7.0
                end
            else
                e.chargeCd = e.chargeCd - dt
                if e.chargeCd <= 0 and d > 120 then
                    e.chargeState = "telegraph"
                    e.chargeT = 0.7
                    e.chargeDirX = (p.x - e.x) / math.max(1, d)
                    e.chargeDirY = (p.y - e.y) / math.max(1, d)
                end

                e.bossSkillCd = e.bossSkillCd - dt
                if e.bossSkillCd <= 0 then
                    e.bossSkillCd = 4.2
                    local baseAngle = math.atan(p.y - e.y, p.x - e.x)
                    for k = -2, 2 do
                        local ang = baseAngle + k * 0.18
                        cs.bullets[#cs.bullets + 1] = {
                            x = e.x, y = e.y,
                            vx = math.cos(ang) * 230, vy = math.sin(ang) * 230,
                            r = 8, dmg = e.atk * 0.7, life = 4.0,
                            color = { 255, 120, 90 },
                        }
                    end
                end

                if not e.summoned1 and e.hp < e.maxHp * 0.66 then
                    e.summoned1 = true
                    Combat.SummonMinions(cs, e, 2)
                end
                if not e.summoned2 and e.hp < e.maxHp * 0.33 then
                    e.summoned2 = true
                    Combat.SummonMinions(cs, e, 2)
                end
            end

            e.burstCd = e.burstCd - dt
            if e.burstCd <= 0 then
                e.burstCd = e.enraged and 3.6 or 5.2
                cs.bullets[#cs.bullets + 1] = {
                    x = e.x, y = e.y, r = 0, maxR = 420, speed = 240,
                    dmg = e.atk * 1.5, hit = false, shock = true,
                    segCount = 72, segments = MakeRingSegments(72),
                }
            end
        end
    end

    -- 简单分离，避免完全重叠
    for i = 1, #cs.enemies do
        local a = cs.enemies[i]
        for j = i + 1, #cs.enemies do
            local b = cs.enemies[j]
            local d = Dist(a.x, a.y, b.x, b.y)
            local minD = a.radius + b.radius
            if d > 0 and d < minD then
                local push = (minD - d) / 2
                local nx = (b.x - a.x) / d
                local ny = (b.y - a.y) / d
                a.x = a.x - nx * push
                a.y = a.y - ny * push
                b.x = b.x + nx * push
                b.y = b.y + ny * push
            end
        end
    end
end

function Combat.UpdateBullets(cs, dt)
    local p = cs.player
    for i = #cs.bullets, 1, -1 do
        local b = cs.bullets[i]
        if b.shock then
            b.r = b.r + (b.speed or 0) * dt
            local n = b.segCount or 72
            local segs = b.segments
            if segs then
                for k = 1, n do
                    if segs[k] then
                        local a = (k - 1) / n * math.pi * 2 - math.pi
                        local px = b.x + math.cos(a) * b.r
                        local py = b.y + math.sin(a) * b.r
                        if LineHitsWall(cs, b.x, b.y, px, py) then
                            segs[k] = false
                        end
                    end
                end
            end

            local d = Dist(b.x, b.y, p.x, p.y)
            if not b.hit and math.abs(d - b.r) < 24 then
                local a = math.atan(p.y - b.y, p.x - b.x)
                local idx = math.floor(((a + math.pi) / (math.pi * 2)) * n) + 1
                if idx < 1 then idx = 1 elseif idx > n then idx = n end
                if not segs or segs[idx] then
                    b.hit = true
                    Combat.DamagePlayer(cs, b.dmg)
                end
            end
            if b.r >= b.maxR then table.remove(cs.bullets, i) end
        else
            b.x = b.x + b.vx * dt
            b.y = b.y + b.vy * dt
            b.life = b.life - dt
            local blocked = PointInWalls(cs, b.x, b.y)
            local hit = (not blocked) and Dist(b.x, b.y, p.x, p.y) < b.r + p.radius
            if hit then
                if (cs.guardTimer or 0) > 0 then
                    Combat.GuardBlockBullet(cs, b.x, b.y, b.color)
                elseif F(p, "reflectBullet") > 0 and math.random() < F(p, "reflectBullet") then
                    -- 镜面反射：把这一发打回去，本次免伤
                    local target = NearestEnemy(cs, p.x, p.y, 700)
                    local ang = target and math.atan(target.y - p.y, target.x - p.x)
                        or math.atan(-b.vy, -b.vx)
                    SpawnProj(cs, {
                        x = p.x, y = p.y,
                        vx = math.cos(ang) * 900, vy = math.sin(ang) * 900,
                        r = 8, life = 1.3,
                        dmg = p.atk * 1.5 * (1 + p.skillPct),
                        isSkill = true, kind = "orb", color = { 150, 235, 255 },
                    })
                    AddText(cs, p.x, p.y - 44, "反弹", S.col.cyan, 16)
                    AddRing(cs, p.x, p.y, 62, { 150, 235, 255 }, 0.26, 4)
                else
                    Combat.DamagePlayer(cs, b.dmg)
                    AddParticles(cs, b.x, b.y, b.color, 4)
                end
                table.remove(cs.bullets, i)
            elseif blocked then
                AddParticles(cs, b.x, b.y, b.color, 3)
                table.remove(cs.bullets, i)
            elseif b.life <= 0 or b.x < -40 or b.x > WORLD_W + 40 or b.y < -40 or b.y > WORLD_H + 40 then
                table.remove(cs.bullets, i)
            end
        end
    end
end

function Combat.UpdateWaves(cs, dt)
    if cs.testMode then return end
    if cs.cleared then
        cs.clearTimer = cs.clearTimer - dt
        if cs.clearTimer <= 0 then
            Combat.Exit(true)
        end
        return
    end

    if #cs.enemies == 0 then
        if cs.waveIndex < #cs.waves then
            cs.waveDelay = cs.waveDelay - dt
            if cs.waveDelay <= 0 then
                cs.waveIndex = cs.waveIndex + 1
                Combat.SpawnWave(cs, cs.waves[cs.waveIndex])
                cs.waveDelay = 1.2
            end
        else
            cs.cleared = true
            cs.clearTimer = 1.3
            S.toast.text = "房间已清空"
            S.toast.t = 1.3
        end
    end
end

function Combat.UpdateEffects(cs, dt)
    for i = #cs.texts, 1, -1 do
        local t = cs.texts[i]
        t.t = t.t + dt
        t.y = t.y - 34 * dt
        if t.t >= t.life then table.remove(cs.texts, i) end
    end
    for i = #cs.effects, 1, -1 do
        local e = cs.effects[i]
        e.t = e.t + dt
        e.x = e.x + e.vx * dt
        e.y = e.y + e.vy * dt
        e.vx = e.vx * 0.94
        e.vy = e.vy * 0.94
        if e.t >= e.life then table.remove(cs.effects, i) end
    end
    if cs.slashes then
        for i = #cs.slashes, 1, -1 do
            local s = cs.slashes[i]
            s.t = s.t + dt
            if s.t >= s.life then table.remove(cs.slashes, i) end
        end
    end
    if cs.rings then
        for i = #cs.rings, 1, -1 do
            local r = cs.rings[i]
            r.t = r.t + dt
            if r.t >= r.life then table.remove(cs.rings, i) end
        end
    end
    if cs.trails then
        for i = #cs.trails, 1, -1 do
            local tr = cs.trails[i]
            tr.t = tr.t + dt
            if tr.t >= tr.life then table.remove(cs.trails, i) end
        end
    end
    if cs.telegraphs then
        for i = #cs.telegraphs, 1, -1 do
            local g = cs.telegraphs[i]
            g.t = g.t + dt
            if g.t >= g.life then table.remove(cs.telegraphs, i) end
        end
    end
    if cs.bolts then
        for i = #cs.bolts, 1, -1 do
            local b = cs.bolts[i]
            b.t = b.t + dt
            if b.t >= b.life then table.remove(cs.bolts, i) end
        end
    end
    if cs.snipeCharge then
        cs.snipeCharge.t = cs.snipeCharge.t + dt
        if cs.snipeCharge.t >= cs.snipeCharge.dur + 0.25 then cs.snipeCharge = nil end
    end
    if (cs.playerHitFlash or 0) > 0 then
        cs.playerHitFlash = math.max(0, cs.playerHitFlash - dt)
    end
end

-- ---------------------------------------------------------------- 渲染
local function CameraBegin(cs)
    local camX, camY = CameraPos(cs)
    local sx, sy = 0.0, 0.0
    if cs.shake > 0 and Opt("screenShake", true) then
        sx = (math.random() - 0.5) * cs.shake
        sy = (math.random() - 0.5) * cs.shake
    end
    nvgSave(S.ctx)
    nvgTranslate(S.ctx, -camX + sx, -camY + sy)
    return camX, camY
end

local function CameraEnd()
    nvgRestore(S.ctx)
end

local function DrawFloor()
    nvgBeginPath(S.ctx)
    nvgRect(S.ctx, 0, 0, WORLD_W, WORLD_H)
    nvgFillColor(S.ctx, nvgRGBA(30, 20, 34, 255))
    nvgFill(S.ctx)

    for x = 0, WORLD_W, 80 do
        nvgBeginPath(S.ctx)
        nvgMoveTo(S.ctx, x, 0)
        nvgLineTo(S.ctx, x, WORLD_H)
        nvgStrokeColor(S.ctx, nvgRGBA(70, 40, 62, 70))
        nvgStrokeWidth(S.ctx, 1)
        nvgStroke(S.ctx)
    end
    for y = 0, WORLD_H, 80 do
        nvgBeginPath(S.ctx)
        nvgMoveTo(S.ctx, 0, y)
        nvgLineTo(S.ctx, WORLD_W, y)
        nvgStrokeColor(S.ctx, nvgRGBA(70, 40, 62, 70))
        nvgStrokeWidth(S.ctx, 1)
        nvgStroke(S.ctx)
    end

    nvgBeginPath(S.ctx)
    nvgRect(S.ctx, 2, 2, WORLD_W - 4, WORLD_H - 4)
    nvgStrokeColor(S.ctx, nvgRGBA(120, 60, 90, 120))
    nvgStrokeWidth(S.ctx, 4)
    nvgStroke(S.ctx)
end

local function DrawWalls(cs)
    for _, w in ipairs(cs.walls) do
        UI.Panel(w.x, w.y, w.w, w.h, 8, { 58, 40, 62, 255 }, { 132, 88, 120, 255 }, 3)
        UI.Panel(w.x + 6, w.y + 6, w.w - 12, w.h - 12, 6, { 46, 32, 52, 255 }, { 92, 64, 96, 255 }, 1)
        local x1 = w.x + 16 + (w.w * 0.27) % 24
        local y1 = w.y + 16 + (w.h * 0.33) % 18
        UI.Line(x1, y1, x1 + 18, y1 + 10, { 124, 82, 116, 130 }, 2)
        UI.Line(w.x + w.w - 20, w.y + w.h * 0.6, w.x + w.w - 36, w.y + w.h * 0.6 + 12,
            { 124, 82, 116, 130 }, 2)
    end
end

local function DrawEnemy(cs, e)
    local r = e.radius
    -- 光晕
    nvgBeginPath(S.ctx)
    nvgCircle(S.ctx, e.x, e.y, r + 8)
    nvgFillColor(S.ctx, nvgRGBA(e.color[1], e.color[2], e.color[3], 28))
    nvgFill(S.ctx)

    -- 本体
    nvgBeginPath(S.ctx)
    nvgCircle(S.ctx, e.x, e.y, r)
    local flash = e.hitFlash > 0
    if flash then
        nvgFillColor(S.ctx, nvgRGBA(255, 255, 255, 240))
    else
        nvgFillColor(S.ctx, nvgRGBA(e.color[1], e.color[2], e.color[3], 235))
    end
    nvgFill(S.ctx)

    -- 纤毛 / 尖刺
    local spikes = e.kind == "boss" and 14 or (e.kind == "elite" and 10 or 6)
    for i = 1, spikes do
        local a = i / spikes * math.pi * 2 + cs.time * 0.7
        local x1 = e.x + math.cos(a) * (r - 2)
        local y1 = e.y + math.sin(a) * (r - 2)
        local x2 = e.x + math.cos(a) * (r + 8)
        local y2 = e.y + math.sin(a) * (r + 8)
        nvgBeginPath(S.ctx)
        nvgMoveTo(S.ctx, x1, y1)
        nvgLineTo(S.ctx, x2, y2)
        nvgStrokeColor(S.ctx, nvgRGBA(e.color[1], e.color[2], e.color[3], 200))
        nvgStrokeWidth(S.ctx, 3)
        nvgStroke(S.ctx)
    end

    -- 眼睛
    nvgBeginPath(S.ctx)
    nvgCircle(S.ctx, e.x - r * 0.3, e.y - r * 0.2, r * 0.16)
    nvgCircle(S.ctx, e.x + r * 0.3, e.y - r * 0.2, r * 0.16)
    nvgFillColor(S.ctx, nvgRGBA(20, 10, 22, 230))
    nvgFill(S.ctx)

    -- 血条
    local bw = r * 2.4
    local bx = e.x - bw / 2
    local by = e.y - r - 16
    UI.Panel(bx, by, bw, 6, 3, { 20, 14, 20, 220 })
    if Opt("enemyHpBar", true) then
        UI.Bar(bx, by, bw, 6, e.hp / e.maxHp, e.kind == "boss" and S.col.orange or S.col.red)
    end
    if e.kind ~= "minion" then
        UI.Text(e.x, by - 18, 14, e.name, S.col.text, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    end
    if e.crack > 0 then
        -- 挫裂：目标套一圈橙边，右侧显示层数，层数越高边越亮
        local ca = math.floor(90 + 30 * e.crack + ((e.crackFlash or 0) > 0 and 110 or 0))
        UI.Circle(e.x, e.y, r + 3, nil, { 255, 170, 90, math.min(255, ca) },
            (e.crackFlash or 0) > 0 and 3 or 2)
        -- 裂片小图标（三道斜线），比纯文字更直观
        local gx, gy = e.x + r + 10, e.y - 8
        for k = 0, 2 do
            UI.Line(gx + k * 4, gy - 5, gx + k * 4 + 3, gy + 5,
                { 255, 180, 100, 230 }, 1)
        end
        UI.Text(gx + 16, gy, 13, tostring(e.crack), S.col.orange,
            NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    end
    if (e.stagger or 0) > 0 then
        UI.Text(e.x + r + 10, e.y + 10, 13, "衡" .. e.stagger, S.col.cyan,
            NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    end
    if (e.hunt or 0) > 0 then
        UI.Text(e.x + r + 10, e.y + 26, 13, "痕" .. e.hunt, S.col.purple,
            NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    end
    if (e.bleedTimer or 0) > 0 then
        UI.Text(e.x + r + 10, e.y - 26, 12, "血", S.col.red,
            NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    end
    if (e.freezeTimer or 0) > 0 then
        UI.Circle(e.x, e.y, r + 5, { 140, 210, 255, 45 }, { 160, 225, 255, 210 }, 2)
    end
    if (e.burnTimer or 0) > 0 then
        UI.Circle(e.x, e.y, r + 7, nil, { 255, 140, 70, 190 }, 2)
        UI.Text(e.x + r + 10, e.y - 42, 12, "燃", { 255, 150, 80, 255 },
            NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    end

    -- Boss 冲锋预警
    if e.behavior == "boss" and e.chargeState == "telegraph" then
        local pulse = 0.5 + 0.5 * math.sin(cs.time * 22)
        local len = 320
        UI.Line(e.x, e.y, e.x + e.chargeDirX * len, e.y + e.chargeDirY * len,
            { 255, 70, 60, math.floor(70 + 130 * pulse) }, 10)
    elseif e.behavior == "boss" and e.chargeState == "dash" then
        UI.Circle(e.x, e.y, e.radius + 10, nil, { 255, 80, 60, 220 }, 4)
    end
end

local function DrawSector(cx, cy, r, facing, half, fill, stroke, strokeW)
    local steps = 16
    nvgBeginPath(S.ctx)
    nvgMoveTo(S.ctx, cx, cy)
    for i = 0, steps do
        local a = facing - half + (2 * half) * (i / steps)
        nvgLineTo(S.ctx, cx + math.cos(a) * r, cy + math.sin(a) * r)
    end
    nvgClosePath(S.ctx)
    nvgFillColor(S.ctx, fill)
    nvgFill(S.ctx)

    if stroke then
        nvgBeginPath(S.ctx)
        for i = 0, steps do
            local a = facing - half + (2 * half) * (i / steps)
            local x = cx + math.cos(a) * r
            local y = cy + math.sin(a) * r
            if i == 0 then
                nvgMoveTo(S.ctx, x, y)
            else
                nvgLineTo(S.ctx, x, y)
            end
        end
        nvgStrokeColor(S.ctx, stroke)
        nvgStrokeWidth(S.ctx, math.floor(strokeW or 3))
        nvgStroke(S.ctx)
    end
end

local function DrawArcBand(x, y, r0, r1, a0, a1, fill, stroke, strokeW)
    local span = a1 - a0
    local steps = math.max(8, math.floor(math.abs(span) / (math.pi * 2) * 48))
    local mid = (r0 + r1) / 2
    local bandW = math.max(1, r1 - r0)
    -- 整圆用 UI.Circle 画：首尾重合的多段线在 NanoVG 里可能退化成空路径
    if math.abs(span) >= math.pi * 2 - 0.01 then
        if fill then UI.Circle(x, y, mid, nil, fill, math.floor(bandW)) end
        if stroke then UI.Circle(x, y, r1, nil, stroke, strokeW or 3) end
        return
    end
    if fill then
        nvgBeginPath(S.ctx)
        for i = 0, steps do
            local a = a0 + span * (i / steps)
            local px, py = x + math.cos(a) * mid, y + math.sin(a) * mid
            if i == 0 then nvgMoveTo(S.ctx, px, py) else nvgLineTo(S.ctx, px, py) end
        end
        nvgStrokeColor(S.ctx, fill)
        nvgStrokeWidth(S.ctx, bandW)
        nvgStroke(S.ctx)
    end
    if stroke then
        nvgBeginPath(S.ctx)
        for i = 0, steps do
            local a = a0 + span * (i / steps)
            local px, py = x + math.cos(a) * r1, y + math.sin(a) * r1
            if i == 0 then nvgMoveTo(S.ctx, px, py) else nvgLineTo(S.ctx, px, py) end
        end
        nvgStrokeColor(S.ctx, stroke)
        nvgStrokeWidth(S.ctx, strokeW or 3)
        nvgStroke(S.ctx)
    end
end

local function DrawPlayer(cs)
    local p = cs.player
    local r = p.radius

    nvgBeginPath(S.ctx)
    nvgCircle(S.ctx, p.x, p.y, r + 12)
    nvgFillColor(S.ctx, nvgRGBA(120, 200, 255, 26))
    nvgFill(S.ctx)

    -- 普攻范围与方向（与实际判定一致）
    local class = Config.Class()
    local baseRange = class.basicRange * (1 + p.rangePct)
    local atkRange = baseRange
    if IsSpear() and p.intent > 0 then atkRange = atkRange + 18 end
    local halfArc = class.basicArc / 2
    if Opt("showSkillRange", true) then
        if IsRanged() then
            -- 远程职业只画一条瞄准线，避免大扇形挡住画面
            UI.Line(p.x, p.y, p.x + math.cos(cs.facing) * atkRange,
                p.y + math.sin(cs.facing) * atkRange,
                { 150, 210, 255, 55 }, 2)
        else
            DrawSector(p.x, p.y, atkRange, cs.facing, halfArc, nvgRGBA(130, 200, 255, 18), nil)
        end
    end

    if cs.attackFlash > 0 then
        local alpha = math.floor(cs.attackFlash / 0.16 * 190)
        if IsRanged() then
            UI.Line(p.x, p.y, p.x + math.cos(cs.facing) * atkRange,
                p.y + math.sin(cs.facing) * atkRange,
                { 220, 240, 255, alpha }, 3)
        else
            DrawSector(p.x, p.y, atkRange, cs.facing, halfArc,
                nvgRGBA(200, 232, 255, math.floor(alpha * 0.35)),
                nvgRGBA(230, 245, 255, alpha), 4)
        end
    end

    -- 身体
    nvgBeginPath(S.ctx)
    nvgCircle(S.ctx, p.x, p.y, r)
    nvgFillColor(S.ctx, nvgRGBA(110, 180, 240, 255))
    nvgFill(S.ctx)
    nvgBeginPath(S.ctx)
    nvgCircle(S.ctx, p.x, p.y, r)
    nvgStrokeColor(S.ctx, nvgRGBA(210, 235, 255, 220))
    nvgStrokeWidth(S.ctx, 2)
    nvgStroke(S.ctx)

    -- 剑心护体：持续光晕
    if cs.swordHeartTimer > 0 then
        local pulse = 0.5 + 0.5 * math.sin(cs.time * 12)
        UI.Circle(p.x, p.y, r + 12 + pulse * 3, nil,
            { 110, 225, 255, math.floor(90 + 80 * pulse) }, 3)
    end

    -- 卸势格挡：横剑架势 + 正面盾弧 + 剩余时间呼吸
    if p.parryTimer > 0 then
        local half = math.rad(70)
        local pulse = 0.5 + 0.5 * math.sin(cs.time * 16)
        DrawArcBand(p.x, p.y, r + 10, r + 22, cs.facing - half, cs.facing + half,
            { 120, 225, 255, math.floor(60 + 45 * pulse) }, { 200, 248, 255, 240 }, 5)
        DrawArcBand(p.x, p.y, r + 26, r + 32, cs.facing - half * 0.8, cs.facing + half * 0.8,
            { 140, 230, 255, 26 }, { 190, 245, 255, 150 }, 2)
        -- 横剑：剑身垂直于面朝方向横在胸前
        local px = math.cos(cs.facing + math.pi / 2)
        local py = math.sin(cs.facing + math.pi / 2)
        local cx2 = p.x + math.cos(cs.facing) * (r + 12)
        local cy2 = p.y + math.sin(cs.facing) * (r + 12)
        local halfLen = r + 26
        nvgBeginPath(S.ctx)
        nvgMoveTo(S.ctx, cx2 - px * halfLen, cy2 - py * halfLen)
        nvgLineTo(S.ctx, cx2 + px * halfLen, cy2 + py * halfLen)
        nvgStrokeColor(S.ctx, nvgRGBA(225, 245, 255, 250))
        nvgStrokeWidth(S.ctx, 6)
        nvgStroke(S.ctx)
        nvgBeginPath(S.ctx)
        nvgMoveTo(S.ctx, cx2 - px * (halfLen + 3), cy2 - py * (halfLen + 3))
        nvgLineTo(S.ctx, cx2 + px * (halfLen + 3), cy2 + py * (halfLen + 3))
        nvgStrokeColor(S.ctx, nvgRGBA(150, 230, 255, 120))
        nvgStrokeWidth(S.ctx, 2)
        nvgStroke(S.ctx)
    end

    -- 格挡成功：强闪光环，一眼看得见
    if (cs.parryFlash or 0) > 0 then
        local k = math.min(1, cs.parryFlash / 0.32)
        UI.Circle(p.x, p.y, r + 20 + (1 - k) * 48, { 190, 245, 255, math.floor(70 * k) },
            { 235, 252, 255, math.floor(255 * k) }, 6)
    end

    -- 受击闪红
    if (cs.playerHitFlash or 0) > 0 then
        local a = math.floor(220 * math.min(1, cs.playerHitFlash / 0.18))
        UI.Circle(p.x, p.y, r + 4, { 255, 70, 70, math.floor(a * 0.25) },
            { 255, 90, 90, a }, 3)
    end

    -- 护盾环：有盾时一直显示，受击吸收时更亮
    if p.shield > 0 then
        local ratio = math.min(1, p.shield / math.max(1, p.maxShield))
        local a = math.floor(60 + ratio * 90)
        if (cs.shieldFlash or 0) > 0 then a = a + 110 end
        UI.Circle(p.x, p.y, r + 7, nil, { 90, 210, 255, math.min(255, a) }, 3)
    end

    -- 突进无敌高亮
    if p.invulnTimer > 0 then
        local a = math.floor(130 + 90 * math.sin(cs.time * 32))
        UI.Circle(p.x, p.y, r + 10, nil, { 120, 230, 255, a }, 3)
    end

    -- 武器：剑客是剑，枪客是长枪
    local sx = p.x + math.cos(cs.facing) * (r + 4)
    local sy = p.y + math.sin(cs.facing) * (r + 4)
    local ex, ey
    if IsSpear() then
        -- 枪身长度贴合实际判定：命中范围是从角色中心算到怪物中心 + 怪物半径，
        -- 所以枪尖画到 basicRange 附近即可，画太长会让人误以为能打到更远
        local len = baseRange - 4
        ex = p.x + math.cos(cs.facing) * len
        ey = p.y + math.sin(cs.facing) * len
        nvgBeginPath(S.ctx)
        nvgMoveTo(S.ctx, sx, sy)
        nvgLineTo(S.ctx, ex, ey)
        nvgStrokeColor(S.ctx, nvgRGBA(255, 205, 140, 245))
        nvgStrokeWidth(S.ctx, 6)
        nvgStroke(S.ctx)
        -- 枪头
        nvgBeginPath(S.ctx)
        local hx = ex + math.cos(cs.facing) * 8
        local hy = ey + math.sin(cs.facing) * 8
        nvgMoveTo(S.ctx, hx, hy)
        nvgLineTo(S.ctx, ex + math.cos(cs.facing + 0.5) * 5, ey + math.sin(cs.facing + 0.5) * 5)
        nvgLineTo(S.ctx, ex + math.cos(cs.facing - 0.5) * 5, ey + math.sin(cs.facing - 0.5) * 5)
        nvgClosePath(S.ctx)
        nvgFillColor(S.ctx, nvgRGBA(255, 235, 190, 255))
        nvgFill(S.ctx)
    elseif IsRanger() then
        -- 弓：面向方向的一段圆弧 + 弦
        DrawArcBand(p.x, p.y, r + 12, r + 18,
            cs.facing - math.rad(55), cs.facing + math.rad(55),
            nil, { 160, 235, 175, 240 }, 4)
        nvgBeginPath(S.ctx)
        local bx1 = p.x + math.cos(cs.facing - math.rad(55)) * (r + 15)
        local by1 = p.y + math.sin(cs.facing - math.rad(55)) * (r + 15)
        local bx2 = p.x + math.cos(cs.facing + math.rad(55)) * (r + 15)
        local by2 = p.y + math.sin(cs.facing + math.rad(55)) * (r + 15)
        nvgMoveTo(S.ctx, bx1, by1)
        nvgLineTo(S.ctx, p.x + math.cos(cs.facing) * (r + 2), p.y + math.sin(cs.facing) * (r + 2))
        nvgLineTo(S.ctx, bx2, by2)
        nvgStrokeColor(S.ctx, nvgRGBA(210, 250, 220, 200))
        nvgStrokeWidth(S.ctx, 1.5)
        nvgStroke(S.ctx)
    elseif IsMage() then
        -- 法杖：必须和弹道同向，否则瞄准和实际弹道会错位
        local ax = cs.facing + 0.28
        local tx = p.x + math.cos(ax) * (r + 30)
        local ty = p.y + math.sin(ax) * (r + 30)
        nvgBeginPath(S.ctx)
        nvgMoveTo(S.ctx, p.x + math.cos(ax) * 8, p.y + math.sin(ax) * 8)
        nvgLineTo(S.ctx, tx, ty)
        nvgStrokeColor(S.ctx, nvgRGBA(200, 180, 255, 235))
        nvgStrokeWidth(S.ctx, 4)
        nvgStroke(S.ctx)
        -- 杖头光球放在正前方（弹道起点方向上），而不是偏 34 度
        local ox = p.x + math.cos(cs.facing) * (r + 26)
        local oy = p.y + math.sin(cs.facing) * (r + 26)
        local pulse = 0.5 + 0.5 * math.sin(cs.time * 8)
        UI.Circle(ox, oy, 6 + pulse * 2, { 190, 160, 255, 120 }, { 220, 200, 255, 240 }, 2)
    elseif not (p.parryTimer > 0) then
        -- 剑：格挡时改画横剑（见上），平时正常指向面朝方向
        ex = p.x + math.cos(cs.facing) * (atkRange + 4)
        ey = p.y + math.sin(cs.facing) * (atkRange + 4)
        nvgBeginPath(S.ctx)
        nvgMoveTo(S.ctx, sx, sy)
        nvgLineTo(S.ctx, ex, ey)
        nvgStrokeColor(S.ctx, nvgRGBA(235, 245, 255, 240))
        nvgStrokeWidth(S.ctx, 5)
        nvgStroke(S.ctx)
    end

    -- 铁枪固守：整圈护盾
    if (cs.guardTimer or 0) > 0 then
        local pulse = 0.5 + 0.5 * math.sin(cs.time * 10)
        UI.Circle(p.x, p.y, r + 16 + pulse * 2, { 255, 210, 140, 20 },
            { 255, 220, 160, math.floor(150 + 80 * pulse) }, 4)
    end

    -- 资源点：剑意 / 枪势 / 狩猎冲动
    local class = Config.Class()
    if class.showResource ~= false then
        local imax = ResourceMax(p)
        local resColor = { 120, 230, 255 }
        if IsSpear() then resColor = { 255, 200, 130 }
        elseif IsRanger() then resColor = { 150, 240, 175 } end
        for i = 1, imax do
            local x = p.x - (imax - 1) * 6.5 + (i - 1) * 13
            local y = p.y - r - 20
            nvgBeginPath(S.ctx)
            nvgCircle(S.ctx, x, y, 4)
            if i <= p.intent then
                nvgFillColor(S.ctx, nvgRGBA(resColor[1], resColor[2], resColor[3], 255))
                nvgFill(S.ctx)
            else
                nvgStrokeColor(S.ctx, nvgRGBA(resColor[1], resColor[2], resColor[3], 120))
                nvgStrokeWidth(S.ctx, 1)
                nvgStroke(S.ctx)
            end
        end
    end
end

local function DrawBullets(cs)
    for _, b in ipairs(cs.bullets) do
        if b.shock then
            local alpha = math.floor(200 * (1 - b.r / b.maxR))
            local n = b.segCount or 72
            local segs = b.segments
            nvgBeginPath(S.ctx)
            for k = 1, n do
                if not segs or segs[k] then
                    local a0 = (k - 1) / n * math.pi * 2 - math.pi
                    local a1 = k / n * math.pi * 2 - math.pi
                    local x0 = b.x + math.cos(a0) * b.r
                    local y0 = b.y + math.sin(a0) * b.r
                    local x1 = b.x + math.cos(a1) * b.r
                    local y1 = b.y + math.sin(a1) * b.r
                    nvgMoveTo(S.ctx, x0, y0)
                    nvgLineTo(S.ctx, x1, y1)
                end
            end
            nvgStrokeColor(S.ctx, nvgRGBA(255, 90, 70, math.max(20, alpha)))
            nvgStrokeWidth(S.ctx, 14)
            nvgStroke(S.ctx)
        else
            nvgBeginPath(S.ctx)
            nvgCircle(S.ctx, b.x, b.y, b.r)
            nvgFillColor(S.ctx, nvgRGBA(b.color[1], b.color[2], b.color[3], 255))
            nvgFill(S.ctx)
            nvgBeginPath(S.ctx)
            nvgCircle(S.ctx, b.x, b.y, b.r + 4)
            nvgFillColor(S.ctx, nvgRGBA(b.color[1], b.color[2], b.color[3], 60))
            nvgFill(S.ctx)
        end
    end
end

local function DrawWindWaves(cs)
    for _, w in ipairs(cs.windWaves or {}) do
        local ang = math.atan(w.diry, w.dirx)
        local rOut = w.r
        local rIn = w.r * 0.5
        nvgBeginPath(S.ctx)
        for i = 0, 14 do
            local a = ang - 1.0 + 2.0 * (i / 14)
            local x = w.x + math.cos(a) * rOut
            local y = w.y + math.sin(a) * rOut
            if i == 0 then nvgMoveTo(S.ctx, x, y) else nvgLineTo(S.ctx, x, y) end
        end
        for i = 14, 0, -1 do
            local a = ang - 0.7 + 1.4 * (i / 14)
            nvgLineTo(S.ctx, w.x + math.cos(a) * rIn, w.y + math.sin(a) * rIn)
        end
        nvgClosePath(S.ctx)
        nvgFillColor(S.ctx, nvgRGBA(120, 220, 255, 165))
        nvgFill(S.ctx)

        nvgBeginPath(S.ctx)
        for i = 0, 14 do
            local a = ang - 1.0 + 2.0 * (i / 14)
            local x = w.x + math.cos(a) * rOut
            local y = w.y + math.sin(a) * rOut
            if i == 0 then nvgMoveTo(S.ctx, x, y) else nvgLineTo(S.ctx, x, y) end
        end
        nvgStrokeColor(S.ctx, nvgRGBA(220, 245, 255, 230))
        nvgStrokeWidth(S.ctx, 4)
        nvgStroke(S.ctx)
    end
end

local function DrawPhantoms(cs)
    for _, ph in ipairs(cs.phantoms or {}) do
        local ratio = math.max(0, math.min(1, ph.t / math.max(0.01, ph.total)))
        local alpha = math.floor(150 * ratio)
        local c = ph.color
        -- 剑影本体
        nvgBeginPath(S.ctx)
        nvgCircle(S.ctx, ph.x, ph.y, 15)
        nvgFillColor(S.ctx, nvgRGBA(c[1], c[2], c[3], math.floor(alpha * 0.45)))
        nvgFill(S.ctx)
        nvgBeginPath(S.ctx)
        nvgCircle(S.ctx, ph.x, ph.y, 15)
        nvgStrokeColor(S.ctx, nvgRGBA(c[1], c[2], c[3], alpha))
        nvgStrokeWidth(S.ctx, 2)
        nvgStroke(S.ctx)
        -- 剑影斩击（按复刻的技能画对应的攻击方式）
        local swing = 1 - ratio
        local half = math.rad(55)
        local base = ph.facing - half + half * 2 * swing
        if ph.skill == 4 then
            UI.Circle(ph.x, ph.y, ph.radius, nil,
                { c[1], c[2], c[3], math.min(255, alpha + 70) }, 5)
        elseif ph.skill == 2 or ph.skill == 6 then
            UI.Line(ph.x, ph.y, ph.x + math.cos(ph.facing) * ph.radius,
                ph.y + math.sin(ph.facing) * ph.radius,
                { c[1], c[2], c[3], math.min(255, alpha + 70) }, 6)
        else
            DrawSector(ph.x, ph.y, ph.radius, base, half * 0.55,
                nvgRGBA(c[1], c[2], c[3], math.floor(alpha * 0.22)),
                nvgRGBA(c[1], c[2], c[3], math.min(255, alpha + 60)), 3)
        end
    end
end

local function DrawTrails(cs)
    for _, tr in ipairs(cs.trails or {}) do
        local k = math.min(1, tr.t / tr.life)
        local a = math.floor(120 * (1 - k))
        local c = tr.color
        UI.Circle(tr.x, tr.y, tr.r * (1 - k * 0.3),
            { c[1], c[2], c[3], math.floor(a * 0.45) },
            { c[1], c[2], c[3], a }, 2)
    end
end

local function DrawSlashes(cs)
    for _, s in ipairs(cs.slashes or {}) do
        local k = math.min(1, s.t / s.life)
        local a = math.floor(235 * (1 - k))
        local r1 = s.range * (1 + 0.10 * k)
        local r0 = math.max(8, r1 * 0.72)
        local half = s.arc / 2
        DrawArcBand(s.x, s.y, r0, r1, s.facing - half, s.facing + half,
            { s.color[1], s.color[2], s.color[3], math.floor(a * 0.22) },
            { s.color[1], s.color[2], s.color[3], a }, s.width)
    end
end

local function DrawRings(cs)
    for _, r in ipairs(cs.rings or {}) do
        local k = math.min(1, r.t / r.life)
        local rad = r.maxR * (0.35 + 0.65 * k)
        local a = math.floor(230 * (1 - k))
        UI.Circle(r.x, r.y, rad, nil, { r.color[1], r.color[2], r.color[3], a }, r.width)
    end
end

-- 技能范围提示：轮廓 + 极淡填充，越到后面越淡
local function DrawTelegraphs(cs)
    for _, g in ipairs(cs.telegraphs or {}) do
        local k = math.min(1, g.t / g.life)
        local a = math.floor(165 * (1 - k) * (1 - k))
        local c = g.color
        -- 敌方预警加强（偏红的预警更亮更明显）
        local warnW = 2
        if Opt("bossWarn", true) and c[1] >= c[2] and c[1] >= c[3] then
            a = math.min(255, math.floor(a * 1.55))
            warnW = 3
        end
        local fillA = math.floor(a * 0.14)
        if g.kind == "sector" then
            local half = g.arc / 2
            DrawSector(g.x, g.y, g.range, g.facing, half,
                nvgRGBA(c[1], c[2], c[3], fillA), nil)
            DrawArcBand(g.x, g.y, g.range - 2, g.range, g.facing - half, g.facing + half,
                nil, { c[1], c[2], c[3], a }, warnW)
            UI.Line(g.x, g.y, g.x + math.cos(g.facing - half) * g.range,
                g.y + math.sin(g.facing - half) * g.range, { c[1], c[2], c[3], math.floor(a * 0.55) }, 1)
            UI.Line(g.x, g.y, g.x + math.cos(g.facing + half) * g.range,
                g.y + math.sin(g.facing + half) * g.range, { c[1], c[2], c[3], math.floor(a * 0.55) }, 1)
        elseif g.kind == "circle" then
            UI.Circle(g.x, g.y, g.r, { c[1], c[2], c[3], fillA },
                { c[1], c[2], c[3], a }, warnW)
            UI.Circle(g.x, g.y, g.r * 0.55, nil, { c[1], c[2], c[3], math.floor(a * 0.30) }, 1)
        elseif g.kind == "corridor" then
            local dx, dy = math.cos(g.facing), math.sin(g.facing)
            local nx, ny = -dy * g.width / 2, dx * g.width / 2
            local x1, y1 = g.x + nx, g.y + ny
            local x2, y2 = g.x - nx, g.y - ny
            local x3, y3 = g.x + dx * g.len - nx, g.y + dy * g.len - ny
            local x4, y4 = g.x + dx * g.len + nx, g.y + dy * g.len + ny
            nvgBeginPath(S.ctx)
            nvgMoveTo(S.ctx, x1, y1)
            nvgLineTo(S.ctx, x2, y2)
            nvgLineTo(S.ctx, x3, y3)
            nvgLineTo(S.ctx, x4, y4)
            nvgClosePath(S.ctx)
            nvgFillColor(S.ctx, nvgRGBA(c[1], c[2], c[3], math.floor(fillA * 0.55)))
            nvgFill(S.ctx)
            nvgBeginPath(S.ctx)
            nvgMoveTo(S.ctx, x1, y1)
            nvgLineTo(S.ctx, x2, y2)
            nvgLineTo(S.ctx, x3, y3)
            nvgLineTo(S.ctx, x4, y4)
            nvgClosePath(S.ctx)
            nvgStrokeColor(S.ctx, nvgRGBA(c[1], c[2], c[3], a))
            nvgStrokeWidth(S.ctx, 2)
            nvgStroke(S.ctx)
            UI.Line(g.x, g.y, g.x + dx * g.len, g.y + dy * g.len,
                { c[1], c[2], c[3], math.floor(a * 0.45) }, 1)
        elseif g.kind == "line" then
            UI.Line(g.x, g.y, g.x2, g.y2, { c[1], c[2], c[3], a }, 3)
            UI.Circle(g.x2, g.y2, 5, nil, { c[1], c[2], c[3], a }, warnW)
        end
    end
    -- 蓄力中的狙击：随蓄力增长的前方指示
    local ch = cs.snipeCharge
    if ch then
        local prog = math.min(1, ch.t / math.max(0.05, ch.dur))
        local len = 120 + (900 - 120) * prog
        local pulse = 0.55 + 0.45 * math.sin(cs.time * 16)
        local a = math.floor(70 + 110 * pulse * prog)
        local c = { 255, 230, 150 }
        UI.Line(ch.x, ch.y, ch.x + math.cos(ch.facing) * len, ch.y + math.sin(ch.facing) * len,
            { c[1], c[2], c[3], a }, warnW)
        UI.Circle(ch.x, ch.y, 26 + 10 * prog, nil, { c[1], c[2], c[3], a }, warnW)
    end
end

local function DrawBolts(cs)
    for _, b in ipairs(cs.bolts or {}) do
        local k = math.min(1, b.t / b.life)
        local a = math.floor(240 * (1 - k))
        local c = b.color
        -- 外层辉光
        nvgBeginPath(S.ctx)
        for i, p in ipairs(b.pts) do
            if i == 1 then nvgMoveTo(S.ctx, p.x, p.y) else nvgLineTo(S.ctx, p.x, p.y) end
        end
        nvgStrokeColor(S.ctx, nvgRGBA(c[1], c[2], c[3], math.floor(a * 0.30)))
        nvgStrokeWidth(S.ctx, 7)
        nvgStroke(S.ctx)
        -- 内层亮线
        nvgBeginPath(S.ctx)
        for i, p in ipairs(b.pts) do
            if i == 1 then nvgMoveTo(S.ctx, p.x, p.y) else nvgLineTo(S.ctx, p.x, p.y) end
        end
        nvgStrokeColor(S.ctx, nvgRGBA(255, 255, 240, a))
        nvgStrokeWidth(S.ctx, 2)
        nvgStroke(S.ctx)
    end
end

local function DrawSpearShots(cs)
    for _, s in ipairs(cs.spearShots or {}) do
        local ang = math.atan(s.diry, s.dirx)
        local bx = s.x - math.cos(ang) * 26
        local by = s.y - math.sin(ang) * 26
        local tx = s.x + math.cos(ang) * 26
        local ty = s.y + math.sin(ang) * 26
        nvgBeginPath(S.ctx)
        nvgMoveTo(S.ctx, bx, by)
        nvgLineTo(S.ctx, tx, ty)
        nvgStrokeColor(S.ctx, nvgRGBA(255, 210, 150, 235))
        nvgStrokeWidth(S.ctx, 5)
        nvgStroke(S.ctx)
        nvgBeginPath(S.ctx)
        nvgCircle(S.ctx, s.x, s.y, 16)
        nvgFillColor(S.ctx, nvgRGBA(255, 220, 160, 45))
        nvgFill(S.ctx)
    end
    for _, f in ipairs(cs.spearFields or {}) do
        local k = math.min(1, f.t / f.life)
        local a = math.floor(120 * (1 - k))
        UI.Circle(f.x, f.y, f.r, { 255, 200, 120, math.floor(a * 0.12) },
            { 255, 205, 135, a }, 2)
        for i = 1, 4 do
            local ang = cs.time * 2 + i * math.pi / 2
            local px = f.x + math.cos(ang) * f.r * 0.7
            local py = f.y + math.sin(ang) * f.r * 0.7
            UI.Line(f.x, f.y, px, py, { 255, 220, 160, math.floor(a * 0.5) }, 2)
        end
    end
end

local function DrawRangedFx(cs)
    for _, h in ipairs(cs.hazardFields or {}) do
        local k = math.min(1, h.t / h.life)
        local a = math.floor(90 * (1 - k))
        UI.Circle(h.x, h.y, h.r, { 150, 110, 80, math.floor(a * 0.3) },
            { 190, 150, 100, a }, 2)
    end
    for _, tr in ipairs(cs.rangerTraps or {}) do
        -- 夹子外形：底座 + 上下两片锯齿夹颚 + 中心触发板
        local glow = 150 + math.floor(80 * (0.5 + 0.5 * math.sin(cs.time * 10)))
        UI.Circle(tr.x, tr.y, tr.r + 9, { 40, 70, 52, 90 }, { 90, 170, 115, 120 }, 2)
        DrawArcBand(tr.x, tr.y, tr.r - 7, tr.r, -math.pi + 0.22, -0.22,
            { 70, 130, 95, 55 }, { 170, 240, 190, glow }, 4)
        DrawArcBand(tr.x, tr.y, tr.r - 7, tr.r, 0.22, math.pi - 0.22,
            { 70, 130, 95, 55 }, { 170, 240, 190, glow }, 4)
        for i = 1, 8 do
            local ang = (i - 0.5) / 8 * math.pi * 2
            UI.Line(tr.x + math.cos(ang) * (tr.r - 9), tr.y + math.sin(ang) * (tr.r - 9),
                tr.x + math.cos(ang) * (tr.r + 4), tr.y + math.sin(ang) * (tr.r + 4),
                { 190, 245, 200, 190 }, 2)
        end
        UI.Circle(tr.x, tr.y, 7, { 150, 240, 170, 60 }, { 200, 250, 210, 200 }, 2)
    end
    for _, f in ipairs(cs.mageFields or {}) do
        local c = { 255, 235, 140 }
        if f.element == "fire" then c = { 255, 150, 90 }
        elseif f.element == "ice" then c = { 150, 220, 255 } end
        local k = math.min(1, f.t / f.life)
        local a = math.floor(110 * (1 - k))
        UI.Circle(f.x, f.y, f.r, { c[1], c[2], c[3], math.floor(a * 0.18) },
            { c[1], c[2], c[3], a }, 2)
    end
    for _, pr in ipairs(cs.projs or {}) do
        local c = pr.color
        local ang = math.atan(pr.vy, pr.vx)
        if pr.kind == "arrow" then
            local x1 = pr.x - math.cos(ang) * 16
            local y1 = pr.y - math.sin(ang) * 16
            local x2 = pr.x + math.cos(ang) * 16
            local y2 = pr.y + math.sin(ang) * 16
            UI.Line(x1, y1, x2, y2, { c[1], c[2], c[3], 240 }, 3)
            UI.Circle(x2, y2, 3, { 255, 255, 255, 230 })
        else
            UI.Circle(pr.x, pr.y, pr.r, { c[1], c[2], c[3], 200 },
                { c[1], c[2], c[3], 255 }, 2)
            UI.Circle(pr.x, pr.y, pr.r + 5, { c[1], c[2], c[3], 45 })
        end
    end
end

local function DrawEffects(cs)
    for _, e in ipairs(cs.effects) do
        local a = math.floor(255 * (1 - e.t / e.life))
        nvgBeginPath(S.ctx)
        nvgCircle(S.ctx, e.x, e.y, e.r)
        nvgFillColor(S.ctx, nvgRGBA(e.color[1], e.color[2], e.color[3], a))
        nvgFill(S.ctx)
    end
    for _, t in ipairs(cs.texts) do
        local a = math.floor(255 * (1 - t.t / t.life))
        UI.Text(t.x + 2, t.y + 2, t.size, t.text, { 0, 0, 0, math.floor(a * 0.65) },
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        UI.Text(t.x, t.y, t.size, t.text, { t.color[1], t.color[2], t.color[3], a },
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    end
end

local function DrawHUD(cs)
    local p = cs.player
    local run = cs.run

    UI.Panel(24, 20, 330, 108, 12, { 18, 16, 26, 220 }, S.col.line, 1)
    UI.Text(40, 32, 15, Config.Class().name .. " Lv." .. p.classLevel, S.col.dim)
    UI.Bar(40, 56, 298, 14, p.hp / p.maxHp, S.col.red)
    UI.Text(338, 34, 13, string.format("%d / %d", math.floor(p.hp), math.floor(p.maxHp)), S.col.text,
        NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
    UI.Bar(40, 78, 298, 8, p.shield / math.max(1, p.maxShield), S.col.cyan)
    if Config.Class().showResource ~= false then
        UI.Text(40, 98, 14, Config.Class().resourceName .. " " .. p.intent .. " / " .. ResourceMax(p),
            IsSpear() and S.col.orange or (IsRanger() and S.col.green or S.col.cyan))
    end
    UI.Text(338, 96, 12, string.format("护盾 %d / %d", math.floor(p.shield), p.maxShield),
        S.col.cyan, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)

    UI.Text(640, 24, 22, Config.RoomNames[cs.roomType] or cs.roomType, S.col.text,
        NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    UI.Text(640, 54, 14, "第 " .. cs.waveIndex .. " / " .. #cs.waves .. " 波", S.col.dim,
        NVG_ALIGN_CENTER + NVG_ALIGN_TOP)

    UI.Panel(990, 20, 266, 64, 10, { 18, 16, 26, 220 }, S.col.line, 1)
    UI.Text(1006, 36, 16, "银币", S.col.dim)
    UI.Text(1064, 32, 22, tostring(run.silver), S.col.gold)
    UI.Text(1006, 62, 16, "关卡", S.col.dim)
    UI.Text(1064, 58, 18, "第 " .. run.level .. " 关 · 房 " .. cs.step, S.col.text)

    if p.rageTimer > 0 then
        UI.Text(640, 80, 16, string.format("狂暴 %.1fs", p.rageTimer), S.col.orange,
            NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    end

    if not cs.showBuffs and not cs.paused then
        UI.Button("pause_btn", 1030, 96, 60, 36, "暂停", function()
            Combat.SetPaused(cs, true)
        end, { fontSize = 14, fill = { 40, 46, 62, 235 } })
        UI.Button("buff_toggle", 1100, 96, 156, 36, "强化面板 Tab", function()
            Combat.ToggleBuffPanel()
        end, { fontSize = 14, fill = { 40, 46, 62, 235 } })
    end
end

-- 暂停：停掉战斗更新，弹出继续 / 状态 / 退出
function Combat.SetPaused(cs, v)
    cs = cs or S.combat
    if not cs then return end
    cs.paused = v and true or false
    if cs.paused then
        S.input.x = 0
        S.input.y = 0
        if cs.joystick then
            cs.joystick.active = false
            cs.joystick.kx, cs.joystick.ky = cs.joystick.baseX, cs.joystick.baseY
        end
    end
end

function Combat.TogglePause()
    local cs = S.combat
    if not cs then return end
    Combat.SetPaused(cs, not cs.paused)
end

local function DrawPause(cs)
    nvgBeginPath(S.ctx)
    nvgRect(S.ctx, 0, 0, Config.DESIGN_W, Config.DESIGN_H)
    nvgFillColor(S.ctx, nvgRGBA(0, 0, 0, 190))
    nvgFill(S.ctx)

    UI.Panel(430, 210, 420, 300, 18, { 28, 24, 38, 252 }, S.col.line, 1)
    UI.Text(640, 244, 32, "已暂停", S.col.gold, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    UI.Text(640, 288, 13, "战斗已停止，随时可以回来", S.col.dim,
        NVG_ALIGN_CENTER + NVG_ALIGN_TOP)

    UI.Button("pause_resume", 470, 330, 340, 46, "继续游戏", function()
        Combat.SetPaused(cs, false)
    end, { fontSize = 17, accent = S.col.green, fill = { 40, 74, 52, 255 },
        stroke = { 90, 150, 105, 255 } })

    UI.Button("pause_status", 470, 388, 340, 42, "状态面板", function()
        cs.statusPanel = cs.statusPanel or { page = 1, detail = nil }
        Combat.SetPaused(cs, false)
        cs.showBuffs = true
    end, { fontSize = 16 })

    local quitLabel = cs.testMode and "退出测试，返回主菜单" or "退出关卡"
    UI.Button("pause_quit", 470, 440, 340, 42, quitLabel, function()
        Combat.SetPaused(cs, false)
        Run.ReturnToMenu()
    end, { fontSize = 16, fill = { 62, 34, 38, 255 }, stroke = { 130, 70, 76, 255 } })
end

local function AttackInterval(cs)
    local p = cs.player
    local as = p.attackSpeed
    if p.rageTimer > 0 then as = as * 1.3 end
    if cs.swordHeartTimer > 0 then as = as * 1.2 end
    as = as * (1 + MissingHpBonus(p))
    local cd = 1 / math.max(0.2, as)
    return cd * (1 - math.min(0.4, F(p, "basicNoRecovery")))
end

-- 返回 label, color, remaining, total, enabled
local function ActionInfo(cs, b)
    local run = cs.run
    local p = cs.player
    if b.kind == "attack" then
        return "攻", { 255, 226, 170 }, p.attackTimer, AttackInterval(cs), true
    elseif b.kind == "skill" then
        local id = run.loadout[b.slot]
        local sk = id and Config.SkillByID(id)
        if not sk then
            return "—", { 120, 120, 130 }, 0, 0, false
        end
        return sk.short, { 150, 200, 255 }, p.cooldowns[id] or 0,
            Combat.SkillCooldown(cs, id), true
    else
        local it = run.items[1]
        if not it then
            return "无", { 120, 120, 130 }, 0, 0, false
        end
        local info = Run.ItemInfo(it.id)
        local label = (info and info.short or "?") .. "x" .. it.count
        return label, { 150, 230, 170 }, 0, 0, true
    end
end

local function DrawCooldownWedge(x, y, r, progress)
    -- progress = 剩余比例（1 满冷却 -> 0 就绪）
    local steps = 20
    nvgBeginPath(S.ctx)
    nvgMoveTo(S.ctx, x, y)
    for i = 0, steps do
        local a = -math.pi / 2 + progress * math.pi * 2 * (i / steps)
        nvgLineTo(S.ctx, x + math.cos(a) * (r - 1), y + math.sin(a) * (r - 1))
    end
    nvgClosePath(S.ctx)
    nvgFillColor(S.ctx, nvgRGBA(0, 0, 0, 170))
    nvgFill(S.ctx)

    -- 外圈：走完整圈的高亮弧，粗细随按钮大小走，远处也能看清还剩多少
    nvgBeginPath(S.ctx)
    for i = 0, steps do
        local a = -math.pi / 2 + progress * math.pi * 2 * (i / steps)
        local px = x + math.cos(a) * (r - 2)
        local py = y + math.sin(a) * (r - 2)
        if i == 0 then
            nvgMoveTo(S.ctx, px, py)
        else
            nvgLineTo(S.ctx, px, py)
        end
    end
    nvgStrokeColor(S.ctx, nvgRGBA(255, 168, 66, 255))
    nvgStrokeWidth(S.ctx, math.max(4, math.floor(r * 0.16)))
    nvgStroke(S.ctx)
end

local function DrawActionButton(b, label, color, remaining, total, enabled, charges, flashK)
    local x, y, r = b.x, b.y, b.r
    local key = b.key or ""
    local hasKey = key ~= ""
    local cd = (enabled and remaining and remaining > 0) and remaining or 0

    UI.Circle(x, y, r, { 18, 16, 26, 230 },
        { color[1], color[2], color[3], enabled and 235 or 80 }, 2)

    if charges and charges > 0 then
        UI.Circle(x + r * 0.78, y - r * 0.78, 10, { 255, 170, 70, 255 }, { 40, 32, 20, 255 }, 1)
        UI.Text(x + r * 0.78, y - r * 0.78, 12, tostring(charges + 1), { 30, 22, 12, 255 },
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    end

    if cd > 0 and total and total > 0 then
        DrawCooldownWedge(x, y, r, math.min(1, cd / total))
    end

    -- 刚就绪：绿色扩散环，明确告诉玩家能按了
    if flashK and flashK > 0 then
        local k = math.min(1, flashK)
        UI.Circle(x, y, r + 3 + 8 * (1 - k), nil,
            { 120, 255, 160, math.floor(235 * k) }, 4)
    end

    if cd > 0 then
        -- 冷却中：大号倒计时盖在按钮中央，一眼能看出还要等多久
        UI.Text(x, y, math.max(15, math.floor(r * 0.60)), string.format("%.1f", cd),
            { 255, 196, 120, 250 }, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    else
        UI.Text(x, hasKey and (y - 5) or y, r * 0.48,
            enabled and label or label, enabled and color or { 110, 106, 120, 255 },
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    end
    if hasKey then
        UI.Text(x, y + r * 0.40, math.max(10, r * 0.26), "[" .. key .. "]",
            { 205, 205, 215, 170 }, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    end
end

-- 瞄准时右上角的「取消施法」区域：手指拖进去，松手就不放技能
local function DrawAimCancel(cs)
    local aim = cs.aim
    if not aim then return end
    local z = AimCancelRect()
    local active = aim.cancel

    -- 技能键摇杆指示：从按键圆心连到手指，手指处画一个小圆（设置里可关）
    if aim.fx and aim.bx and Opt("aimIndicator", true) then
        local readyK = (aim.t >= AimHoldValue() or aim.moved) and 1 or 0.5
        UI.Circle(aim.bx, aim.by, 26, nil, { 170, 215, 255, math.floor(70 * readyK) }, 2)
        UI.Line(aim.bx, aim.by, aim.fx, aim.fy,
            { 180, 225, 255, math.floor(120 * readyK) }, 2)
        UI.Circle(aim.fx, aim.fy, 12,
            { 180, 225, 255, math.floor(45 * readyK) },
            { 220, 240, 255, math.floor(220 * readyK) }, 2)
    end
    local fill = active and { 128, 38, 52, 238 } or { 26, 24, 38, 170 }
    local stroke = active and { 255, 120, 120, 245 } or { 150, 150, 180, 175 }
    UI.Panel(z.x, z.y, z.w, z.h, 12, fill, stroke, active and 3 or 2)
    local cx, cy = z.x + z.w / 2, z.y + z.h / 2 - 12
    local r = 15
    UI.Line(cx - r, cy - r, cx + r, cy + r, stroke, 3)
    UI.Line(cx - r, cy + r, cx + r, cy - r, stroke, 3)
    UI.Text(z.x + z.w / 2, z.y + z.h - 24, 14,
        active and "松手取消" or "取消施法",
        active and { 255, 205, 205, 255 } or { 190, 190, 210, 220 },
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
end

local function DrawActionButtons(cs)
    local p = cs.player
    cs.lastCd = cs.lastCd or {}
    cs.readyAt = cs.readyAt or {}
    for _, b in ipairs(ACTION_BUTTONS) do
        local label, color, remaining, total, enabled = ActionInfo(cs, b)
        local charges = nil
        if b.kind == "skill" then
            local id = cs.run.loadout[b.slot]
            charges = id and p.charges[id] or nil
        end
        local bx, by, br = CtrlPos(b.id, b.x, b.y, b.r)
        -- 由冷却中变成就绪时记一个时间点，用来放就绪提示
        local cd = (enabled and remaining and remaining > 0) and remaining or 0
        local last = cs.lastCd[b.id] or 0
        if last > 0.001 and cd <= 0.001 then cs.readyAt[b.id] = cs.time end
        cs.lastCd[b.id] = cd
        local flashK = 0
        local since = cs.time - (cs.readyAt[b.id] or -99)
        if since >= 0 and since < 0.45 then flashK = 1 - since / 0.45 end
        DrawActionButton({ x = bx, y = by, r = br, key = b.key, id = b.id },
            label, color, remaining, total, enabled, charges, flashK)
    end

    local itemCount = #cs.run.items
    for i = 1, 3 do
        local slot = ItemSlot(i)
        local it = cs.run.items[i]
        if it then
            local info = Run.ItemInfo(it.id)
            local label = (info and info.short or "?") .. "x" .. it.count
            DrawActionButton(
                { x = slot.x, y = slot.y, r = slot.r, key = (i == 1 and "E" or "") },
                label, { 150, 230, 170 }, 0, 0, true)
        elseif i == 1 and itemCount == 0 then
            DrawActionButton({ x = slot.x, y = slot.y, r = slot.r, key = "E" },
                "无", { 120, 120, 130 }, 0, 0, false)
        end
    end
    DrawAimCancel(cs)
end

-- 状态/强化面板：战斗内 Tab 和选关界面共用同一套
-- p=玩家 run=本局数据 st={page,detail} subtitle=副标题 onClose=关闭回调
local function DrawBuffPanel(p, run, st, subtitle, onClose)

    nvgBeginPath(S.ctx)
    nvgRect(S.ctx, 0, 0, Config.DESIGN_W, Config.DESIGN_H)
    nvgFillColor(S.ctx, nvgRGBA(0, 0, 0, 185))
    nvgFill(S.ctx)

    UI.Panel(300, 64, 680, 592, 18, { 28, 24, 38, 252 }, S.col.line, 1)
    UI.Text(340, 90, 30, "强化面板", S.col.gold)
    UI.Text(340, 130, 14, subtitle or "点击强化名字查看效果", S.col.dim)

    local summary = {
        { "银币", tostring(run.silver) },
        { "生命", string.format("%d / %d", math.floor(p.hp), p.maxHp) },
        { "护盾", string.format("%d / %d", math.floor(p.shield), p.maxShield) },
        { "攻击", string.format("%.1f", p.atk) },
        { "攻速", string.format("%.2f / 秒", p.attackSpeed) },
        { "移速", string.format("%.0f", p.moveSpeed) },
        { "暴击率", string.format("%.0f%%", p.crit * 100) },
        { "暴击伤害", string.format("%.0f%%", p.critDmg * 100) },
        { "吸血", string.format("%.0f%%", p.lifesteal * 100) },
        { "冷却缩减", string.format("%.0f%%", p.cdr * 100) },
        { "普攻伤害", string.format("+%.0f%%", p.basicPct * 100) },
        { "技能伤害", string.format("+%.0f%%", p.skillPct * 100) },
    }
    for i, row in ipairs(summary) do
        local col = (i - 1) % 2
        local line = math.floor((i - 1) / 2)
        local x = 340 + col * 300
        local y = 166 + line * 26
        UI.Text(x, y, 15, row[1], S.col.dim)
        UI.Text(x + 110, y, 15, row[2], S.col.text)
    end

    local y0 = 166 + 6 * 26 + 12
    UI.Text(340, y0, 18, "已获得强化", S.col.cyan)
    UI.Text(470, y0 + 4, 12, "（名字颜色代表品质）", S.col.dim)

    ---@class BuffGroup
    ---@field buff table
    ---@field count integer
    ---@type BuffGroup[]
    local order = {}
    for _, bf in ipairs(p.buffs) do
        ---@type BuffGroup|nil
        local found = nil
        for _, entry in ipairs(order) do
            if entry.buff.id == bf.id then
                found = entry
                break
            end
        end
        if not found then
            found = { buff = bf, count = 0 }
            order[#order + 1] = found
        end
        found.count = found.count + 1
    end

    if #order == 0 then
        UI.Text(340, y0 + 36, 16, "还没有获得任何强化", S.col.dim)
    else
        local cols, rowsPerPage = 4, 6
        local perPage = cols * rowsPerPage
        local pages = math.max(1, math.ceil(#order / perPage))
        local page = math.min(pages, math.max(1, st.page or 1))
        st.page = page
        local start = (page - 1) * perPage + 1
        local gridY = y0 + 34
        for i = start, math.min(#order, start + perPage - 1) do
            local entry = order[i]
            local idx = i - start
            local col = idx % cols
            local row = math.floor(idx / cols)
            local x = 330 + col * 160
            local y = gridY + row * 34
            local rarity = Config.Rarity[entry.buff.rarity]
            local rc = rarity and rarity.color or S.col.text
            local label = entry.buff.name
            if entry.count > 1 then label = label .. " x" .. entry.count end
            if entry.buff.classBuff then
                UI.Circle(x + 3, y + 8, 3, rc)
                UI.Text(x + 12, y, 14, label, rc)
            else
                UI.Text(x, y, 14, label, rc)
            end
            UI.Region("buff_item_" .. entry.buff.id, x - 4, y - 4, 152, 26, function()
                st.detail = entry.buff.id
            end, true)
        end

        UI.Button("buff_prev", 340, 594, 52, 44, "<", function()
            local c = S.combat
            if c then c.buffPage = math.max(1, (c.buffPage or 1) - 1) end
        end, { fontSize = 18 })
        UI.Text(452, 616, 15, string.format("%d / %d（共 %d 种）", page, pages, #order),
            S.col.dim, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        UI.Button("buff_next", 620, 594, 52, 44, ">", function()
            local c = S.combat
            if c then c.buffPage = math.min(pages, (c.buffPage or 1) + 1) end
        end, { fontSize = 18 })

        -- 点击强化名字后的详情弹窗
        if st.detail then
            ---@type BuffGroup|nil
            local detail = nil
            for _, entry in ipairs(order) do
                if entry.buff.id == st.detail then detail = entry break end
            end
            if not detail then
                st.detail = nil
            else
                local bf = detail.buff
                local rarity = Config.Rarity[bf.rarity]
                local rc = rarity and rarity.color or S.col.text
                UI.Region("buff_detail_bg", 0, 0, Config.DESIGN_W, Config.DESIGN_H, function()
                    st.detail = nil
                end, true)
                UI.Panel(428, 188, 424, 278, 16, { 24, 21, 34, 255 }, rc, 2)
                UI.Text(456, 210, 24, bf.name, rc)
                local tag = (rarity and rarity.name or "") .. (bf.classBuff and (" · " .. Config.Class().name .. "专属") or "")
                UI.Text(456, 246, 14, tag, S.col.dim)
                local needText = Config.ClassBuffNeedText(bf)
                if needText then
                    UI.Text(456, 270, 13, "需要携带：" .. needText, S.col.orange)
                else
                    UI.Text(456, 270, 13, "通用效果，不受携带技能限制", S.col.dim)
                end
                UI.Text(456, 292, 13, "已获得 x" .. detail.count, S.col.dim)
                UI.TextBox(456, 320, 368, 14, bf.desc or "", S.col.text)
                UI.Button("buff_detail_close", 560, 414, 160, 40, "关闭", function()
                    st.detail = nil
                end, { fontSize = 16 })
            end
        end
    end

    UI.Button("buff_close_btn", 760, 594, 180, 44, "关闭 (Esc)", function()
        if onClose then onClose() end
    end, { fontSize = 18 })
end

-- 给外部（选关界面等）用的状态面板
function Combat.DrawStatusPanel(p, run, st, subtitle, onClose)
    if not p or not run then return end
    DrawBuffPanel(p, run, st, subtitle, onClose)
end

local function RegisterControlRegions(cs)
    if cs.showBuffs or cs.paused then
        return
    end
    for _, b in ipairs(ACTION_BUTTONS) do
        local _, _, _, _, enabled = ActionInfo(cs, b)
        if enabled then
            local bx, by, br = CtrlPos(b.id, b.x, b.y, b.r)
            UI.Region("act_" .. b.id, bx - br - 5, by - br - 5, (br + 5) * 2, (br + 5) * 2,
                function()
                    if b.kind == "attack" then
                        Combat.ManualAttack()
                    elseif b.kind == "skill" then
                        Combat.CastSkill(b.slot)
                    end
                end, true)
        end
    end

    local itemCount = math.min(3, #cs.run.items)
    for i = 1, itemCount do
        local slot = ItemSlot(i)
        if slot then
            UI.Region("item_slot_" .. i, slot.x - slot.r - 4, slot.y - slot.r - 4,
                (slot.r + 4) * 2, (slot.r + 4) * 2, function()
                    Combat.UseItemAt(i)
                end, true)
        end
    end
end

-- 长按瞄准：画出技能的实际作用范围
local function DrawAimPreview(cs)
    local aim = cs.aim
    if not aim then return end
    local p = cs.player
    local spec = aim.spec
    local ready = aim.t >= AimHoldValue() or aim.moved
    local k = ready and 1 or 0.45
    local function a(v) return math.floor(v * k) end
    if spec.mode == "point" then
        UI.Circle(aim.point.x, aim.point.y, spec.r, { 150, 240, 170, a(40) },
            { 200, 252, 215, a(225) }, 3)
        UI.Line(p.x, p.y, aim.point.x, aim.point.y, { 200, 252, 215, a(120) }, 2)
        UI.Circle(aim.point.x, aim.point.y, 7, nil, { 235, 255, 240, a(240) }, 2)
        for i = 1, 4 do
            local ang = i * math.pi / 2
            UI.Line(aim.point.x + math.cos(ang) * (spec.r - 10), aim.point.y + math.sin(ang) * (spec.r - 10),
                aim.point.x + math.cos(ang) * (spec.r + 6), aim.point.y + math.sin(ang) * (spec.r + 6),
                { 200, 252, 215, a(180) }, 2)
        end
    else
        DrawSector(p.x, p.y, spec.range, aim.angle, spec.arc / 2,
            nvgRGBA(130, 210, 255, a(30)), nvgRGBA(205, 240, 255, a(180)), 3)
        UI.Line(p.x, p.y, p.x + math.cos(aim.angle) * spec.range,
            p.y + math.sin(aim.angle) * spec.range, { 215, 242, 255, a(130) }, 2)
    end
    if ready then
        UI.Text(p.x, p.y - p.radius - 54, 13, "松手释放",
            { 210, 240, 255, 220 }, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    end
end

function Combat.Draw()
    local cs = S.combat
    if not cs then return end
    CameraBegin(cs)
    DrawFloor()
    DrawWalls(cs)
    DrawTelegraphs(cs)
    DrawBullets(cs)
    DrawTrails(cs)
    for _, e in ipairs(cs.enemies) do
        DrawEnemy(cs, e)
    end
    DrawSlashes(cs)
    DrawRings(cs)
    DrawBolts(cs)
    DrawWindWaves(cs)
    DrawSpearShots(cs)
    DrawRangedFx(cs)
    DrawPlayer(cs)
    DrawAimPreview(cs)
    DrawPhantoms(cs)
    DrawEffects(cs)
    CameraEnd()
    DrawJoystick(cs)
    DrawHUD(cs)
    DrawActionButtons(cs)
    if cs.showBuffs then
        cs.statusPanel = cs.statusPanel or { page = 1, detail = nil }
        DrawBuffPanel(cs.player, cs.run, cs.statusPanel,
            "战斗已暂停 · 点击强化名字查看效果 · Tab / Esc 关闭",
            function()
                cs.showBuffs = false
                cs.statusPanel.detail = nil
            end)
    end
    if cs.paused then
        DrawPause(cs)
    end
    RegisterControlRegions(cs)
end

return Combat
