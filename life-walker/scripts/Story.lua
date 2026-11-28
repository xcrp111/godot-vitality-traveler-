-- Story.lua — 序章与关卡节点的剧情演出
--
-- 表现参考常见 JRPG / 视觉小说：
--   ① 章节标题卡（黑场 → 标题淡入 → 淡出）
--   ② 对话框：角色名条 + 逐字显示 + 继续箭头闪烁
--   ③ 角色站位：主角在左、导师在右，说话的人亮、旁听的人暗
--   ④ 立绘暂用「方块剪影」占位（有素材后只换 DrawFigure 里的画法）
--
-- 只在指定关卡首次进入时触发，记录写进存档 storySeen。
local UI = require "UI"
local S = require "State"
local Config = require "Config"

local Story = {}

local function P(speaker, text)
    return { speaker = speaker, text = text }
end

Story.CAST = {
    hero = { name = "主角", color = { 150, 220, 255 }, side = "left" },
    mentor = { name = "导师", color = { 255, 205, 140 }, side = "right" },
    unknown = { name = "？？？", color = { 200, 160, 255 }, side = "right" },
}

-- 关卡节点 → { title, subtitle, pages }
-- 测试期：一段剧情对应一关（第 1 关序章、第 2 关第一章 …），
-- 正式版再决定放在哪些 Boss 关之后。
Story.Levels = {
    [1] = {
        title = "序章 · 坠入内境",
        subtitle = "又是一个熬到凌晨的夜",
        pages = {
            P("hero", "又是一个熬到凌晨的夜。屏幕的光刺得眼睛发酸。"),
            P("hero", "「明天一定早睡」——这句话我已经说了三年。"),
            P("hero", "闭上眼的瞬间，世界忽然翻了个面。不是梦，因为我能感觉到冷、有风，脚下还传来某种脉搏一样的震动。"),
            P("unknown", "别怕。你不是掉进了梦，你是掉进了「内境」——每个生命体内的镜像世界。"),
            P("hero", "你是谁？"),
            P("mentor", "前任生命行者。你能看见这里，说明你身上有罕见的「意识投射」体质，天生就能走进自己的内境。"),
            P("hero", "我的……内境？这里怎么这么乱。"),
            P("mentor", "因为你的生活乱了。熬夜、久坐、忘记喝水——失衡会在内境里长成「病魔」。"),
            P("mentor", "它们不是天生的敌人，是被混乱吞噬的身体的一部分。我们不是屠夫，是医者。理解它们为什么出现，比打倒它们更重要。"),
            P("hero", "我为什么要做这些？"),
            P("mentor", "因为你就是自己的第一个病人。让这里恢复秩序，现实里的你，也会跟着好起来。"),
            P("mentor", "跟我来，{name}。从脉动神殿开始，我教你怎么走这条路。"),
        },
    },
    [2] = {
        title = "第一章 · 脉动神殿",
        subtitle = "现实与内境的交界",
        pages = {
            P("mentor", "这里是「脉动神殿」，现实与内境的交界，所有生命行者的归宿。"),
            P("mentor", "内境是你身体和心情的镜像。平衡一旦被打破——坏习惯、感染、压力——病魔就会在这里滋生。"),
            P("hero", "那我该怎么进去，又该怎么和它们对抗？"),
            P("mentor", "内境传送门。第一站是被「冰火双子·寒热魔」占据的体温调节领域。那是每个行者的第一课。"),
            P("mentor", "记住，你的目标不是毁灭，是净化。看懂了它，才算真的赢。"),
            P("hero", "我准备好了。"),
            P("mentor", "很好，{name}。记住今天的这一步。"),
        },
    },
    [3] = {
        title = "第二章 · 失衡之影",
        subtitle = "你第一次看清病魔的来处",
        pages = {
            P("mentor", "你看到了——寒热魔不是天生的怪物，只是身体在环境骤变下做出的过度反抗。"),
            P("hero", "只是因为一次冷热交替……身体的平衡，竟然这么容易被打破。"),
            P("mentor", "每一个病魔背后，都藏着一个失衡的故事。"),
            P("mentor", "你击败了它，更要理解它。理解，才是最锋利的净化之力。"),
        },
    },
    [4] = {
        title = "第三章 · 现实之井",
        subtitle = "虚拟的战斗，现实的力量",
        pages = {
            P("mentor", "这是「现实之井」，内境与现实的连接之眼。"),
            P("mentor", "你在现实里做的每一件小事，都会让井水更清。"),
            P("hero", "原来这边赢，现实里也会变。"),
            P("mentor", "不是虚拟改变现实，是你自己在救自己。"),
            P("mentor", "今天的契约：走够步数、喝够水、早点睡。做到了，力量才会留在身上。"),
        },
    },
    [5] = {
        title = "第四章 · 自己的影子",
        subtitle = "每一只病魔，都是你生活的一部分",
        pages = {
            P("hero", "这些病魔……为什么它们的招式我这么熟悉？"),
            P("mentor", "因为它们本来就长在你的生活里。你打的每一只，都是你自己的一部分。"),
            P("hero", "那最里面那个，是什么？"),
            P("mentor", "熵增。所有失衡的源头，生命走向混乱的本能。"),
            P("mentor", "你赢不了它，但你可以一直和它对抗。这也是行者这条路的意义。"),
        },
    },
    [6] = {
        title = "终章 · 熵增",
        subtitle = "在无序里创造有序",
        pages = {
            P("mentor", "熵增是所有失衡的源头。你消灭不了它。"),
            P("hero", "那我在做什么？"),
            P("mentor", "在无序里创造有序。一天一天，一次一次，{name}。"),
            P("mentor", "这就是「生命脉冲」——规律的生活、健康的习惯、平和的内心，聚起来的力量。"),
            P("none", "光散去的时候，我听见了久违的闹钟。"),
            P("hero", "天亮了。"),
            P("none", "你起床，推开房门。生命行者的路，从今天的这一步开始。"),
            -- 结局落版
        },
        ending = "生命行者的征途，从今天的这一步开始",
    },
}

local st = {
    pages = nil,       -- 当前整段（含 title）
    phase = "dialog",  -- "title" | "dialog"
    titleT = 0,
    index = 1,
    chars = 0,
    onDone = nil,
    blipT = 0,
}

local SPEED = 32          -- 每秒显示字数
local TITLE_TIME = 2.2    -- 标题卡停留时长

function Story.IsOpen()
    return st.pages ~= nil
end

function Story.Phase()
    return st.pages and st.phase or nil
end

--- 播放一组剧情（可以只给 pages 数组，兼容旧调用）
function Story.Play(segment, onDone)
    if type(segment) == "table" and segment.pages then
        st.pages = segment.pages
        st.title = segment.title
        st.subtitle = segment.subtitle
        st.ending = segment.ending
    else
        st.pages = segment
        st.title = nil
        st.subtitle = nil
        st.ending = nil
    end
    if not st.pages or #st.pages == 0 then
        st.pages = nil
        if onDone then onDone() end
        return
    end
    st.phase = st.title and "title" or "dialog"
    st.titleT = 0
    st.index = 1
    st.chars = 0
    st.onDone = onDone
    st.blipT = 0
end

--- 点一下：标题卡 → 进入对白；对白 → 补全 / 翻页
function Story.Advance()
    if not st.pages then return end
    if st.phase == "title" then
        st.phase = "dialog"
        st.titleT = TITLE_TIME
        return
    end
    local page = st.pages[st.index]
    local total = utf8.len(page.text) or #page.text
    if math.floor(st.chars) < total then
        st.chars = total
        return
    end
    st.index = st.index + 1
    st.chars = 0
    if st.index > #st.pages then
        local cb = st.onDone
        st.pages = nil
        st.onDone = nil
        if cb then cb() end
    end
end

--- 直接跳过整段
function Story.Skip()
    local cb = st.onDone
    st.pages = nil
    st.onDone = nil
    if cb then cb() end
end

function Story.Update(dt)
    if not st.pages then return end
    dt = dt or 0
    if st.phase == "title" then
        st.titleT = st.titleT + dt
        if st.titleT >= TITLE_TIME + 0.8 then
            -- 标题卡自然结束
            st.phase = "dialog"
        end
        return
    end
    local page = st.pages[st.index]
    local total = utf8.len(page.text) or #page.text
    local before = math.floor(st.chars)
    st.chars = math.min(total, st.chars + SPEED * dt)
    -- 打字音效：每 4 个字轻响一下
    if math.floor(st.chars) > before then
        st.blipT = st.blipT - dt
        if st.blipT <= 0 and math.floor(st.chars) < total then
            st.blipT = 0.09
            pcall(function()
                require("Sfx").Play("ui_click", { gain = 0.18 })
            end)
        end
    end
end

local function PlayerName()
    local d = S.data
    if d and type(d.playerName) == "string" and d.playerName ~= "" then return d.playerName end
    return "主角"
end

Story.FormatText = function(text)
    if not text then return "" end
    return (text:gsub("{name}", PlayerName()))
end

local function VisibleText(text, n)
    n = math.floor(n)
    if n <= 0 then return "" end
    local total = utf8.len(text) or #text
    if n >= total then return text end
    local cut = utf8.offset(text, n + 1)
    return cut and text:sub(1, cut - 1) or text
end

--- 占位立绘：有正式立绘后只改这一个函数
local function DrawFigure(cx, feetY, color, active)
    local w, h = 132, 196
    local a = active and 255 or 96
    local fa = math.floor(a * 0.30)
    local sa = math.floor(a * 0.85)
    -- 身体
    UI.Panel(cx - w / 2, feetY - h, w, h, 14,
        { color[1], color[2], color[3], fa },
        { color[1], color[2], color[3], sa }, 2)
    -- 头
    UI.Circle(cx, feetY - h - 28, 30,
        { color[1], color[2], color[3], fa },
        { color[1], color[2], color[3], sa }, 2)
    -- 眼睛两个点（占位也能看出朝向）
    UI.Circle(cx - 10, feetY - h - 32, 3.5, { 250, 250, 255, a })
    UI.Circle(cx + 10, feetY - h - 32, 3.5, { 250, 250, 255, a })
    -- 脚下投影
    nvgBeginPath(S.ctx)
    nvgEllipse(S.ctx, cx, feetY + 6, 62, 10)
    nvgFillColor(S.ctx, nvgRGBA(0, 0, 0, math.floor(a * 0.35)))
    nvgFill(S.ctx)
end

local function DrawTitleCard(W, H)
    local k = math.min(1, st.titleT / 0.5)                 -- 淡入
    local out = st.titleT > TITLE_TIME and 1 or 0
    local fade = out == 1 and math.max(0, 1 - (st.titleT - TITLE_TIME) / 0.8) or k
    local a = math.floor(255 * fade)
    UI.FillScreen({ 4, 6, 10, 255 })
    if a <= 0 then return end
    UI.Text(W / 2, H / 2 - 30, 46, st.title or "", { 235, 240, 250, a },
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    if st.subtitle then
        local la = math.max(0, math.floor(a * 0.62))
        UI.Text(W / 2, H / 2 + 40, 16, st.subtitle, { 200, 210, 225, la },
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    end
    UI.Text(W / 2, H - 90, 12, "点击继续", { 200, 200, 215, math.floor(a * 0.5) },
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
end

local function DrawDialog(W, H)
    local page = st.pages[st.index]
    page = { speaker = page.speaker, text = Story.FormatText(page.text) }
    local speaker = Story.CAST[page.speaker]
    local narration = page.speaker == "none"

    -- 电影黑边 + 压暗
    UI.FillScreen({ 4, 6, 10, 170 })
    UI.Panel(0, 0, W, 56, 0, { 0, 0, 0, 200 })
    UI.Panel(0, H - 56, W, 56, 0, { 0, 0, 0, 200 })

    -- 占位立绘：主角左、导师右；说话的亮
    local heroActive = page.speaker == "hero"
    local mentorActive = page.speaker == "mentor" or page.speaker == "unknown"
    if not narration then
        DrawFigure(300, 470, Story.CAST.hero.color, heroActive)
        DrawFigure(980, 470, Story.CAST.mentor.color, mentorActive)
    end

    -- 对话框
    local boxW, boxH = 980, 200
    local x = (W - boxW) / 2
    local y = H - boxH - 78
    UI.Panel(x, y, boxW, boxH, 16, { 18, 18, 28, 244 }, S.col.line, 1)

    -- 角色名条（旁白不显示名字）
    local text
    if narration then
        text = VisibleText(page.text, st.chars)
        UI.TextBox(x + 44, y + 54, boxW - 88, 21, text, { 214, 220, 232 })
    else
        local name = speaker and speaker.name or ""
        if page.speaker == "hero" then name = PlayerName() end
        local color = speaker and speaker.color or S.col.gold
        local nameChars = utf8.len(name) or #name
        UI.Panel(x + 40, y - 24, 34 + nameChars * 20, 42, 10,
            { color[1], color[2], color[3], 46 }, { color[1], color[2], color[3], 200 }, 1)
        UI.Text(x + 40 + (17 + nameChars * 10), y - 3, 20, name, color,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        text = VisibleText(page.text, st.chars)
        UI.TextBox(x + 44, y + 52, boxW - 88, 21, text, S.col.text)
    end

    -- 页码
    UI.Text(x + boxW - 40, y + 16, 12,
        string.format("%d / %d", st.index, #st.pages), { 150, 155, 170 },
        NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)

    -- 继续箭头（闪烁）
    local total = utf8.len(page.text) or #page.text
    local done = math.floor(st.chars) >= total
    if done then
        local blink = 0.55 + 0.45 * math.sin((S.time or 0) * 6)
        local ay = y + boxH - 30 + math.floor(math.sin((S.time or 0) * 6) * 2)
        UI.Text(x + boxW - 44, ay, 16, st.index == #st.pages and "结束 ▼" or "继续 ▼",
            { 220, 226, 240, math.floor(200 * blink) },
            NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    end

    -- 跳过
    local skip = Story.SkipRect()
    UI.Panel(skip.x, skip.y, skip.w, skip.h, 8, { 40, 36, 50, 225 }, S.col.line, 1)
    UI.Text(skip.x + skip.w / 2, skip.y + skip.h / 2, 13, "跳过剧情", S.col.dim,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
end

function Story.SkipRect()
    return { x = 640 + 490 - 150, y = 60, w = 110, h = 34 }
end

function Story.HitSkip(dx, dy)
    local r = Story.SkipRect()
    return dx >= r.x and dx <= r.x + r.w and dy >= r.y and dy <= r.y + r.h
end

function Story.Draw()
    if not st.pages then return end
    local W, H = Config.DESIGN_W, Config.DESIGN_H
    if st.phase == "title" then
        DrawTitleCard(W, H)
    else
        DrawDialog(W, H)
    end
    UI.Region("story_click", 0, 0, W, H, function()
        Story.Advance()
    end, true)
end

--- 进入关卡时调用：首次到达指定节点就播对应剧情
function Story.MaybeShowLevel(level, data)
    local seg = Story.Levels[level]
    if not seg or not data then return false end
    data.storySeen = data.storySeen or {}
    local key = tostring(level)
    if data.storySeen[key] then return false end
    Story.Play(seg, function()
        data.storySeen[key] = true
        local ok, Save = pcall(require, "Save")
        if ok and Save and Save.Write then pcall(Save.Write, data) end
    end)
    return true
end

return Story
