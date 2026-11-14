-- CharArt.lua — 像素角色序列帧（侧视 8 帧横条图集）
-- 图集由 dev/make_char_sheets.js 生成：每个职业一张，8 列（帧）× N 行（动作），单元 160×200。
-- 侧视素材：朝右画，向左移动时水平翻转（俯视战斗里当作"侧身"表现）。
local UI = require "UI"
local Config = require "Config"
local S = require "State"

local CharArt = {}

CharArt.CELL_W = 160
CharArt.CELL_H = 200
CharArt.FRAMES = 8
CharArt.BASE_Y = 190      -- 脚底在单元里的位置（生成脚本里固定）
CharArt.CHAR_H = 144      -- 单元内人物高度（生成脚本里固定）
-- 屏幕上的绘制尺寸：想让站立高度约 72px，整个单元就是 72 * 200/144
CharArt.DRAW_H = 100
CharArt.DRAW_W = 80

-- 行号（1 开始，和生成顺序一致）
local ROWS = {
    swordsman = {
        idle = 1, walk = 2, hurt = 3, death = 4, attack = 5, victory = 12,
        skill = { [1] = 6, [2] = 7, [3] = 8, [4] = 9, [5] = 10, [6] = 11 },
    },
    spearman = {
        idle = 1, walk = 2, hurt = 3, death = 4, attack = 5, victory = 12,
        skill = { [1] = 6, [2] = 7, [3] = 8, [4] = 9, [5] = 10, [6] = 11 },
    },
    ranger = {
        idle = 1, walk = 2, hurt = 3, death = 4, attack = 5, victory = 12,
        skill = { [1] = 6, [2] = 7, [3] = 8, [4] = 9, [5] = 10, [6] = 11 },
    },
    mage = {
        idle = 1, walk = 2, hurt = 3, death = 4, attack = 5, victory = 16, dodge = 15,
        -- 火球 / 冰冻波 / 雷击术 / 冰锥术 / 闪电链 / 烈焰冲击 / 静电力场 / 流星陨落 / 暴风雪
        skill = { [1] = 6, [2] = 9, [3] = 13, [4] = 10, [5] = 12, [6] = 7, [7] = 14, [8] = 8, [9] = 11 },
    },
}

-- 逐动作帧数据
--   fps      ：8 帧摊开的播放速度（时长 = FRAMES / fps）
--   hitFrame ：第几帧结算命中 / 弹道（1 开始），伤害按这个时间触发
--   stride   ：行走一整个步态的屏幕位移（px），用来跟移速同步播放速度
-- 参考：轻攻 12~15fps、受击 20fps 左右、待机 6~8fps、行走 8~12fps
CharArt.ACTIONS = {
    idle    = { fps = 8 },
    walk    = { fps = 10, stride = 42 },   -- 实测脚底跨距≈37px，取 42 折中：脚基本不打滑
    attack  = { fps = 14, hitFrame = 3 },
    skill   = { fps = 12, hitFrame = 4 },
    hurt    = { fps = 20, hitFrame = 2 },
    death   = { fps = 7 },
    victory = { fps = 6 },
    dodge   = { fps = 14, hitFrame = 2 },
}

-- 个别技能覆盖默认帧数据：位移类要更快起手，读条类命中更晚
CharArt.SKILL_TUNE = {
    swordsman = {
        [2] = { fps = 20, hitFrame = 2 },   -- 闪影突进
        [6] = { fps = 18, hitFrame = 2 },   -- 瞬影连斩
        [3] = { fps = 12, hitFrame = 2 },   -- 剑心护体（自身增益，早生效）
    },
    spearman = {
        [2] = { fps = 20, hitFrame = 2 },   -- 突刺奔袭
        [5] = { fps = 18, hitFrame = 2 },   -- 回马枪
        [3] = { fps = 14, hitFrame = 2 },   -- 铁枪固守
        [1] = { fps = 14, hitFrame = 2 },   -- 三段枪式（增益）
    },
    ranger = {
        [2] = { fps = 20, hitFrame = 2 },   -- 疾退腾挪
        [6] = { fps = 18, hitFrame = 2 },   -- 掠袭换位
        [1] = { fps = 15, hitFrame = 2 },   -- 精准速射（增益）
        [3] = { fps = 10, hitFrame = 5 },   -- 穿魂狙击（蓄力后出手）
    },
    mage = {
        [8] = { fps = 10, hitFrame = 5 },   -- 流星陨落
        [9] = { fps = 10, hitFrame = 5 },   -- 暴风雪
    },
}

local FAILED = {}            -- 加载失败的职业，避免每帧重试

local function ClassId()
    local id = Config.PlayerClass
    return ROWS[id] and id or "swordsman"
end

function CharArt.RowOf(classId, action, skillId)
    local set = ROWS[classId] or ROWS.swordsman
    if action == "skill" then
        return (set.skill and set.skill[skillId]) or set.attack
    end
    return set[action] or set.idle
end

--- 取某个动作的帧数据（技能可被 SKILL_TUNE 覆盖）
function CharArt.FrameData(classId, action, skillId)
    local base = CharArt.ACTIONS[action] or CharArt.ACTIONS.idle
    if action == "skill" and skillId then
        local tune = CharArt.SKILL_TUNE[classId]
        local o = tune and tune[skillId]
        if o then
            return {
                fps = o.fps or base.fps,
                hitFrame = o.hitFrame or base.hitFrame,
                stride = base.stride,
            }
        end
    end
    return base
end

--- 这个动作从起手到命中需要多少秒（没有命中帧返回 0）
function CharArt.HitDelay(action, opts)
    opts = opts or {}
    local data = CharArt.FrameData(ClassId(), action, opts.skill)
    if not data.hitFrame then return 0 end
    return (data.hitFrame - 1) / data.fps
end

--- 动作总时长（秒）
function CharArt.Duration(action, opts)
    opts = opts or {}
    local data = CharArt.FrameData(ClassId(), action, opts.skill)
    return CharArt.FRAMES / (data.fps or 10)
end

--- 播一个动作
---@param cs table
---@param action string idle|walk|hurt|death|attack|skill|victory|dodge
---@param opts table|nil {dur=number, skill=number}
function CharArt.Play(cs, action, opts)
    local classId = ClassId()
    opts = opts or {}
    local row = CharArt.RowOf(classId, action, opts.skill)
    local loop = (action == "idle" or action == "walk")
    local data = CharArt.FrameData(classId, action, opts.skill)
    local fps = data.fps or 10
    cs.anim = {
        class = classId,
        action = action,
        row = row,
        t = 0,
        fps = fps,
        stride = data.stride,
        hitFrame = data.hitFrame,
        dur = opts.dur or (CharArt.FRAMES / fps),
        loop = loop,
    }
end

--- 行走时按实际移速换算播放速度：脚才不会一直「打滑」
--- 一个完整步态走 stride 像素，所以 fps = 帧数 × 移速 / 步幅
local WALK_FPS_MIN, WALK_FPS_MAX = 8, 20
local function WalkFps(cs)
    local data = CharArt.ACTIONS.walk
    local stride = data.stride or 70
    local speed = cs and cs.player and cs.player.moveSpeed or 120
    local fps = CharArt.FRAMES * speed / math.max(1, stride)
    return math.max(WALK_FPS_MIN, math.min(WALK_FPS_MAX, fps))
end

--- 每帧推进：常态在「待机 / 行走」之间自动切换，一次性动作播完回落
function CharArt.Update(cs, dt)
    local moving = S.input ~= nil and (S.input.x ~= 0 or S.input.y ~= 0)
    local want = moving and "walk" or "idle"
    local a = cs.anim
    if not a then
        CharArt.Play(cs, want)          -- 没有当前动作：直接按移动状态起手，不用等下一帧
        a = cs.anim
    elseif a.loop and a.action ~= want then
        CharArt.Play(cs, want)
        a = cs.anim
    end
    -- 行走：播放速度跟着移速走（跑得快步子迈得快）
    if a and a.action == "walk" then a.fps = WalkFps(cs) end
    a.t = (a.t or 0) + (dt or 0)
    if not a.loop and a.t >= a.dur then
        cs.anim = nil      -- 一次性动作播完，下一帧回落到待机/行走
    end
end

--- 当前帧号（1..8）
local function FrameOf(a)
    if not a then return 1 end
    local fps = a.fps or 10
    if a.loop then
        return math.floor((a.t or 0) * fps) % CharArt.FRAMES + 1
    end
    local k = math.min(0.999, (a.t or 0) * fps / CharArt.FRAMES)
    return math.floor(k * CharArt.FRAMES) + 1
end

--- 画角色；x,y 为脚底位置（朝右的原图，flip=true 时水平镜像）
function CharArt.Draw(classId, row, frame, x, y, flip, alpha, scaleY)
    if FAILED[classId] then return false end
    local img = UI.ImageHandle("image/char/" .. classId .. ".png")
    if not img then FAILED[classId] = true; return false end
    local iw, ih = nvgImageSize(S.ctx, img)
    if not iw or iw <= 0 or not ih or ih <= 0 then
        FAILED[classId] = true
        return false
    end
    local cw, ch = CharArt.CELL_W, CharArt.CELL_H
    local dw, dh = CharArt.DRAW_W, CharArt.DRAW_H
    local k = scaleY or 1
    dh = dh * k                     -- 纵向缩放绕脚底，脚不能离地
    local sx, sy = (frame - 1) * cw, (row - 1) * ch
    nvgSave(S.ctx)
    if flip then
        nvgTranslate(S.ctx, x + dw / 2, y - dh)
        nvgScale(S.ctx, -dw / cw, dh / ch)
    else
        nvgTranslate(S.ctx, x - dw / 2, y - dh)
        nvgScale(S.ctx, dw / cw, dh / ch)
    end
    local paint = nvgImagePattern(S.ctx, -sx, -sy, iw, ih, 0, img, alpha or 1)
    nvgBeginPath(S.ctx)
    nvgRect(S.ctx, 0, 0, cw, ch)
    nvgFillPaint(S.ctx, paint)
    nvgFill(S.ctx)
    nvgRestore(S.ctx)
    return true
end

--- 战斗里画玩家：常态动作在这里决定（有强制动作时用强制动作）
function CharArt.DrawPlayer(cs)
    local p = cs.player
    local a = cs.anim
    if not a then
        local moving = S.input ~= nil and (S.input.x ~= 0 or S.input.y ~= 0)
        a = { class = ClassId(), row = CharArt.RowOf(ClassId(), moving and "walk" or "idle"),
            t = cs.time or 0, loop = true }
    end

    local facing = cs.facing or 0
    local flip, ox, oy, k = math.cos(facing) < 0, 0, 0, 1

    -- 方案 A（先在剑客身上试）：朝向防抖 + 出手前冲 + 纵向浮沉
    if Config.PlayerClass == "swordsman" then
        local ax = math.cos(facing)
        -- 朝正上/正下时 cos≈0，这里留一个迟滞区，避免左右来回闪
        if math.abs(ax) > 0.35 then cs.faceLR = (ax >= 0) and 1 or -1 end
        flip = (cs.faceLR or 1) < 0

        local vert = math.abs(math.sin(facing)) > 0.7
        -- 只有出手动作才前冲；受击/死亡/胜利不乱动
        if a and not a.loop and (a.action == "attack" or a.action == "skill") then
            -- 一次动作：朝面向冲出去，命中帧最远，收招回位
            local dur = math.max(0.01, a.dur or 0.3)
            local prog = math.min(1, (a.t or 0) / dur)
            local hitK = math.min(0.9, ((a.hitFrame or 3) - 1) / (a.fps or 10) / dur)
            local e
            if prog <= hitK then
                e = prog / math.max(0.01, hitK)
            else
                e = 1 - (prog - hitK) / math.max(0.01, 1 - hitK)
            end
            local amp = vert and 9 or 6          -- 上下出手要顶得更多才读得出来
            ox = math.cos(facing) * amp * e
            oy = math.sin(facing) * amp * e
            -- 上下出手再用一点纵向形变补方向：向上拉高、向下压扁
            if vert then k = math.sin(facing) > 0 and 0.955 or 1.055 end
        end
        -- 行走：上下浮沉，减轻整体平移感
        if a and a.action == "walk" then
            oy = oy + math.sin((a.t or 0) * 13) * 1.4
        end
    end

    return CharArt.Draw(a.class or ClassId(), a.row or 1, FrameOf(a),
        p.x + ox, p.y + p.radius + oy, flip, 1, k)
end

return CharArt
