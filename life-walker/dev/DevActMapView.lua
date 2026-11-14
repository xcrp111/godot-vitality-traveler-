-- DevActMapView.lua — 层卡三选一 + 局内节点图 的可视化预览（不参与正式构建）
--
-- 跑法（cwd = 项目根）：
--   .cli\UrhoXRuntime.exe dev\DevActMapView.lua -tapcode_dir=. -tool_mode
--   截图：加 -screenshot=<绝对路径> -screenshot-frame=120 -x 1280 -y 720
--
-- 说明：只画，不接 Run/Screens，所以可以随便改样式而不影响主干。
-- 点卡片可以切换下面那张节点图（用的是同一个 ActMap.GenerateLayer）。

local Config = require "Config"
local UI = require "UI"
local S = require "State"
local ActMap = require "ActMap"
local Opportunity = require "Opportunity"

-- ---------------------------------------------------------------- 房间配色
local ROOM = {
    start     = { fill = { 58, 53, 80 },  text = { 214, 207, 232 }, ch = "起", name = "起点" },
    light     = { fill = { 43, 57, 68 },  text = { 185, 205, 217 }, ch = "战", name = "轻战房" },
    standard  = { fill = { 47, 74, 110 }, text = { 207, 224, 245 }, ch = "战", name = "标战房" },
    mixed     = { fill = { 58, 92, 140 }, text = { 216, 232, 255 }, ch = "混", name = "混战房" },
    elite     = { fill = { 111, 52, 80 }, text = { 255, 217, 230 }, ch = "精", name = "精英房" },
    double    = { fill = { 140, 51, 69 }, text = { 255, 217, 221 }, ch = "双", name = "双精英" },
    shop      = { fill = { 107, 86, 32 }, text = { 255, 233, 168 }, ch = "商", name = "商店房" },
    boss      = { fill = { 125, 42, 54 }, text = { 255, 208, 214 }, ch = "B",  name = "Boss 房" },
    encounter = { fill = { 122, 101, 38 }, text = { 255, 240, 184 }, ch = "遇", name = "不期而遇" },
    wish      = { fill = { 42, 95, 110 }, text = { 200, 240, 255 }, ch = "愿", name = "得偿所愿" },
    -- 模板里的 event 格 = 老的三个硬编码事件，进层时会被改造成「不期而遇 / 得偿所愿」，
    -- 所以卡片上用「机遇占位」而不是「?」，和右侧「机遇 N」那个数字对得上
    event     = { fill = { 82, 70, 44 },  text = { 255, 238, 190 }, ch = "遇", name = "机遇房（进层时确定）" },
}
local function Room(kind) return ROOM[kind] or ROOM.event end

local ACCENT = {
    gold   = { 255, 209, 102, 255 },
    cyan   = { 76, 201, 240, 255 },
    green  = { 126, 231, 135, 255 },
    red    = { 255, 107, 107, 255 },
    purple = { 190, 140, 255, 255 },
}

-- ---------------------------------------------------------------- 预览状态
local View = {
    level = 12,
    cards = nil,
    layer = nil,
    picked = 1,
}

local function BuildLayer(index)
    View.picked = index
    View.layer = ActMap.GenerateLayer(View.level, View.cards[index])
end

local function LoadLevel(level)
    View.level = level
    math.randomseed(20261107 + level)
    View.cards = ActMap.RollCards(level)
    BuildLayer(1)
end

-- 截图脚本需要指定关卡：ACTMAP_LEVEL=1/12/20，没传就用 12
local function EnvLevel()
    if os and os.getenv then
        local v = tonumber(os.getenv("ACTMAP_LEVEL") or "")
        if v then return math.max(1, math.min(20, math.floor(v))) end
    end
    return 12
end

-- ---------------------------------------------------------------- 绘制
-- 颜色必须跟 RiskLabel 的档位一一对应，不能自己另用一套阈值：
-- 旧版是 risk<=0.02 算绿、<=0.28 算金，而 RiskLabel 是 -0.20 / 0.10 / 0.32，
-- 结果「轻松 -0.22」和「常规 -0.18」都是绿的，三张卡看起来还是一样。
local RISK_COLOR = {
    ["轻松"] = ACCENT.green,
    ["常规"] = { 148, 170, 200 },   -- 软蓝灰：中性档，又和选中框的青区分开
    ["吃紧"] = ACCENT.gold,
    ["险恶"] = ACCENT.red,
}

local function RiskColor(label)
    return RISK_COLOR[label] or ACCENT.red
end

local function DrawMiniGrid(grid, x, y, cell, gap)
    local rows, cols = #grid, #grid[1]
    -- 卡牌上格子只有 17px，字会糊成一点：小于 24px 就只画色块，让它当「地形指纹」用
    local showText = cell >= 24
    for r = 1, rows do
        for c = 1, cols do
            local room = Room(grid[r][c])
            local cx = x + (c - 1) * (cell + gap)
            local cy = y + (r - 1) * (cell + gap)
            UI.Panel(cx, cy, cell, cell, 4, room.fill, { 20, 16, 28, 255 }, 1)
            if showText then
                UI.Text(cx + cell / 2, cy + cell / 2, math.floor(cell * 0.44), room.ch, room.text,
                    NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            end
        end
    end
    return cols * cell + (cols - 1) * gap, rows * cell + (rows - 1) * gap
end

local function RGBA(c, a) return nvgRGBA(c[1], c[2], c[3], a or 255) end

-- UTF-8 取首字（中文 3 字节，ASCII 1 字节）
local function FirstChar(s)
    if not s or s == "" then return "" end
    local b = string.byte(s, 1) or 65
    if b >= 240 then return string.sub(s, 1, 4) end
    if b >= 224 then return string.sub(s, 1, 3) end
    if b >= 192 then return string.sub(s, 1, 2) end
    return string.sub(s, 1, 1)
end

-- 牌面纹章：同心环 + 放射刻线 + 多边形，参数全从卡片数据推，
-- 所以同一次抽卡里三张天然不一样（锐度/精英数/风险档都不同），不需要美术资源。
local function DrawSigil(cx, cy, r, card, tint)
    local ctx = S.ctx
    local pip = math.max(3, math.min(12, card.preview.combat + card.preview.elite * 2))

    -- 外轮廓按风险档变：轻松 = 圆，常规 = 六边，吃紧 = 四角星，险恶 = 八角星。
    -- 用形状而不是色差来区分档位——徽标颜色再鲜，离得远也看不出来。
    local label = card.riskLabel
    local pts, inner = 48, 1.0
    if label == "常规" then pts, inner = 6, 1.0
    elseif label == "吃紧" then pts, inner = 4, 0.58
    elseif label == "险恶" then pts, inner = 8, 0.62 end

    nvgBeginPath(ctx)
    for k = 0, pts - 1 do
        local a = (k / pts) * math.pi * 2 - math.pi / 2
        local rr = r * ((k % 2 == 0) and 1.0 or inner)
        local px, py = cx + math.cos(a) * rr, cy + math.sin(a) * rr
        if k == 0 then nvgMoveTo(ctx, px, py) else nvgLineTo(ctx, px, py) end
    end
    nvgClosePath(ctx)
    nvgStrokeColor(ctx, RGBA(tint, 190))
    nvgStrokeWidth(ctx, 2)
    nvgStroke(ctx)

    nvgBeginPath(ctx)
    nvgCircle(ctx, cx, cy, r * (inner < 1 and 0.46 or 0.74))
    nvgStrokeColor(ctx, RGBA(tint, 70))
    nvgStrokeWidth(ctx, 1)
    nvgStroke(ctx)

    -- 放射刻线（条数跟着房间数走）
    for k = 0, pip - 1 do
        local a = (k / pip) * math.pi * 2 - math.pi / 2
        local r1 = r * (inner < 1 and 0.50 or 0.80)
        local r2 = r * 0.92
        nvgBeginPath(ctx)
        nvgMoveTo(ctx, cx + math.cos(a) * r1, cy + math.sin(a) * r1)
        nvgLineTo(ctx, cx + math.cos(a) * r2, cy + math.sin(a) * r2)
        nvgStrokeColor(ctx, RGBA(tint, 85))
        nvgStrokeWidth(ctx, 1)
        nvgStroke(ctx)
    end
end

local function DrawCards()
    local cardW, cardH, gap = 232, 300, 20
    local totalW = cardW * 3 + gap * 2
    local x0 = (Config.DESIGN_W - totalW) / 2
    local y0 = 76

    for i, card in ipairs(View.cards) do
        local x = x0 + (i - 1) * (cardW + gap)
        local y = y0
        local picked = (i == View.picked)
        local rc = RiskColor(card.riskLabel)

        -- 牌背景：卡片自己的微色偏（按风险档取色），选中时更亮
        local lift = picked and 16 or 0
        local bg = {
            30 + math.floor(rc[1] * 0.06) + lift,
            26 + math.floor(rc[2] * 0.06) + lift,
            40 + math.floor(rc[3] * 0.06) + lift,
            255,
        }
        UI.Panel(x, y, cardW, cardH, 14, bg, picked and ACCENT.cyan or RGBA(rc, 150), picked and 3 or 2)

        -- 内框（真卡都有的一圈压边），让它看起来是印出来的而不是画在一块面板上
        UI.Panel(x + 7, y + 7, cardW - 14, cardH - 14, 10, { 0, 0, 0, 0 },
            picked and RGBA(ACCENT.cyan, 90) or RGBA(rc, 70), 1)

        -- 左上角标：关卡号（对应实体卡的花色/点数位置）
        UI.Text(x + 16, y + 16, 10, "第 " .. View.level .. " 关", { 158, 150, 178, 255 })

        -- 牌面窗：深色内凹 + 纹章 + 大字（词条首字）
        local winX, winY, winW, winH = x + 14, y + 32, cardW - 28, 112
        UI.Panel(winX, winY, winW, winH, 8,
            { 18 + math.floor(rc[1] * 0.05), 15 + math.floor(rc[2] * 0.05), 25 + math.floor(rc[3] * 0.05), 255 },
            RGBA(rc, 60), 1)
        local cx, cy = winX + winW / 2, winY + winH / 2 + 2
        DrawSigil(cx, cy, 40, card, rc)
        local glyph = FirstChar(card.modName)
        if glyph ~= "" then
            UI.Text(cx, cy, 40, glyph, RGBA(rc, 205), NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        end

        -- 牌顶色带：卡片身份的第一眼信号（实体卡的色条/烫边）
        UI.Panel(x + 7, y + 7, cardW - 14, 5, 3, RGBA(rc, 230), nil)

        -- 风险徽标浮在牌面右上角：实心亮底 + 深色字，拉远也能读
        local badgeW, badgeH = 92, 24
        local badgeX, badgeY = winX + winW - badgeW - 8, winY + 8
        UI.Panel(badgeX, badgeY, badgeW, badgeH, 12, rc, { 24, 20, 32, 200 }, 1)
        UI.Text(badgeX + badgeW / 2, badgeY + badgeH / 2, 13,
            string.format("%s %+.2f", card.riskLabel, card.risk), { 24, 20, 32, 255 },
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        -- B1：档名是按本组相对位置微调的卡打一个小点，数字仍是绝对强度
        if card.labelRelative then
            UI.Text(badgeX - 9, badgeY + badgeH / 2, 16, "·", RGBA(rc, 235),
                NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        end

        -- 牌名条
        UI.Text(x + 16, y + 150, 17, card.templateName, S.col.text)
        UI.Text(x + 16, y + 172, 12, "× " .. card.modName, ACCENT.cyan)
        UI.Line(x + 14, y + 188, x + cardW - 14, y + 188, RGBA(rc, 55), 1)

        -- 左下：迷你地图（4×4），右下：四项房数 + 银币
        DrawMiniGrid(card.grid, x + 16, y + 196, 17, 3)

        local tx = x + 112
        local p = card.preview
        UI.Text(tx, y + 194, 11, "战斗", S.col.dim)
        UI.Text(tx + 30, y + 193, 13, tostring(p.combat), S.col.text)
        UI.Text(tx, y + 211, 11, "精英", S.col.dim)
        UI.Text(tx + 30, y + 210, 13, tostring(p.elite), ACCENT.red)
        UI.Text(tx, y + 228, 11, "商店", S.col.dim)
        UI.Text(tx + 30, y + 227, 13, tostring(p.shop), ACCENT.gold)
        UI.Text(tx, y + 245, 11, "机遇", S.col.dim)
        UI.Text(tx + 30, y + 244, 13, tostring(p.special), ACCENT.purple)

        -- 底栏：银币（左）+ 相对分档（右，右对齐到卡片内边）
        -- M2：「轻松」只描述战斗强度，收益必须自己可读，不能靠比较数字。
        local tierColor = (card.silverTier == 3) and ACCENT.gold or { 158, 150, 176, 255 }
        UI.Text(x + 16, y + 278, 11, p.silver .. " 银币", S.col.text)
        UI.Text(x + cardW - 16, y + 278, 11,
            (card.silverStars or "") .. " " .. (card.silverLabel or ""),
            tierColor, NVG_ALIGN_RIGHT)

        UI.Region("card_" .. i, x, y, cardW, cardH, function()
            BuildLayer(i)
        end, true)
    end
end

local function DrawLayerGraph(x0, y0, cell, gap)
    local layer = View.layer
    if not layer then return end
    local rows, cols = layer.rows, layer.cols

    local function Center(r, c)
        return x0 + (c - 1) * (cell + gap) + cell / 2,
               y0 + (r - 1) * (cell + gap) + cell / 2
    end

    -- 连线先画，压在格子下面
    for r = 1, rows do
        for c = 1, cols do
            local list = layer.edges[ActMap.EKey(r, c)] or {}
            for _, nb in ipairs(list) do
                local x1, y1 = Center(r, c)
                local x2, y2 = Center(nb[1], nb[2])
                UI.Line(x1, y1, x2, y2, { 74, 66, 100, 255 }, 4)
            end
        end
    end

    -- 死胡同标记
    local dead = {}
    for _, s in ipairs(layer.specials) do
        if s.deadEnd then dead[s.r .. "," .. s.c] = true end
    end

    for r = 1, rows do
        for c = 1, cols do
            local kind = layer.grid[r][c]
            local room = Room(kind)
            local x = x0 + (c - 1) * (cell + gap)
            local y = y0 + (r - 1) * (cell + gap)
            local isSpecial = (kind == "encounter" or kind == "wish")
            local stroke = { 20, 16, 28, 255 }
            local sw = 2
            if isSpecial then stroke = ACCENT.gold; sw = 3 end
            if dead[r .. "," .. c] then stroke = ACCENT.gold; sw = 2 end
            UI.Panel(x, y, cell, cell, 9, room.fill, stroke, sw)
            UI.Text(x + cell / 2, y + cell / 2, math.floor(cell * 0.42), room.ch, room.text,
                NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            if dead[r .. "," .. c] then
                UI.Text(x + cell / 2, y + cell - 13, 11, "死胡同", ACCENT.gold,
                    NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
            end
        end
    end
end

local function DrawSideInfo(x0, y0, w)
    local card = View.cards[View.picked]
    local layer = View.layer

    UI.Text(x0, y0, 16, "这张卡：" .. card.templateName .. " × " .. card.modName, S.col.text)
    UI.TextBox(x0, y0 + 26, w, 13, card.mod.desc, S.col.dim)
    if card.labelRelative then
        -- B1 的档名是按本组相对位置微调的，数字才是绝对强度；不写清楚会被当成显示 bug
        UI.Text(x0, y0 + 52, 12, "· 档名按本组相对位置微调，真实强度看数字（" .. string.format("%+.2f", card.risk) .. "）",
            { 158, 150, 178, 255 })
    end

    local y = y0 + 70
    UI.Text(x0, y, 14, "本层机遇房", S.col.dim)
    y = y + 20
    if #layer.specials == 0 then
        UI.Text(x0, y, 15, "（没有）", S.col.dim)
        y = y + 22
    end
    for _, s in ipairs(layer.specials) do
        local room = Room(s.kind)
        UI.Panel(x0, y, 24, 24, 6, room.fill, ACCENT.gold, 1)
        UI.Text(x0 + 12, y + 12, 13, room.ch, room.text, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        local label = room.name .. "  (" .. s.r .. "," .. s.c .. ")"
        if s.deadEnd then label = label .. "  · 死胡同" end
        if s.wasEvent then label = label .. "  · 原事件房改造" end
        UI.Text(x0 + 34, y + 5, 14, label, S.col.text)
        y = y + 28
    end

    y = y + 8
    UI.Text(x0, y, 14, "图例", S.col.dim)
    y = y + 18
    local order = { "start", "light", "standard", "mixed", "elite", "double", "shop", "boss", "encounter", "wish" }
    for i, kind in ipairs(order) do
        local col = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        local rx = x0 + col * (w / 2)
        local ry = y + row * 20
        local room = Room(kind)
        UI.Panel(rx, ry, 18, 18, 4, room.fill, { 20, 16, 28, 255 }, 1)
        UI.Text(rx + 9, ry + 9, 11, room.ch, room.text, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        UI.Text(rx + 26, ry + 2, 13, room.name, S.col.dim)
    end
    UI.Text(x0, y + 5 * 20 + 4, 12, "卡片上的「遇」= 机遇占位（进层后才定具体类型）", S.col.dim)

    local noteY = y + 5 * 20 + 26
    UI.Text(x0, noteY, 12, "每层固定 1 个机遇房；村落改为战斗房 12% 掉落；", S.col.dim)
    UI.Text(x0, noteY + 18, 12, "「命运」收进得偿所愿的第五个方向「搏」。", S.col.dim)
end

function HandleRender()
    nvgBeginFrame(S.ctx, graphics:GetWidth(), graphics:GetHeight(), S.dpr)
    S.regions = {}
    UI.BeginDesign()

    nvgBeginPath(S.ctx)
    nvgRect(S.ctx, 0, 0, Config.DESIGN_W, Config.DESIGN_H)
    nvgFillColor(S.ctx, nvgRGBA(22, 17, 30, 255))
    nvgFill(S.ctx)

    local act = ActMap.ActOfLevel(View.level)
    UI.Text(48, 26, 26, "第 " .. View.level .. " 关", S.col.text)
    UI.Text(190, 32, 15, (act and ("第 " .. act.id .. " 幕 · " .. act.name) or ""), S.col.dim)
    UI.Text(48, 60, 14, "层卡三选一 · 点卡片切换下方节点图（这是 dev 预览，不进正式流程）", S.col.dim)

    DrawCards()

    -- 节点图：牌变高了，整块往下挪，格子从 72 收到 58，给底部留出呼吸
    local gx, gy, cell, gap = 48, 382, 58, 9
    DrawLayerGraph(gx, gy, cell, gap)
    local gw = View.layer.cols * cell + (View.layer.cols - 1) * gap
    UI.Text(gx, gy + View.layer.rows * (cell + gap) + 2, 12,
        "4×4 节点图 · 金框 = 机遇房 / 死胡同", S.col.dim)

    DrawSideInfo(gx + gw + 32, 376, 620)

    UI.Text(Config.DESIGN_W - 48, 34, 11, "DevActMapView · 数据来自 ActMap.RollCards / GenerateLayer",
        { 110, 103, 130, 255 }, NVG_ALIGN_RIGHT)

    UI.EndDesign()
    nvgEndFrame(S.ctx)
end

function HandleUpdate(eventType, eventData)
    UI.UpdateToast(eventData["TimeStep"]:GetFloat())
end

function Start()
    local dpr = graphics:GetDPR()
    if not dpr or dpr <= 0 then dpr = 1 end
    S.dpr = dpr
    S.W = graphics:GetWidth() / dpr
    S.H = graphics:GetHeight() / dpr
    S.scale = math.min(S.W / Config.DESIGN_W, S.H / Config.DESIGN_H)
    S.offX = (S.W - Config.DESIGN_W * S.scale) / 2
    S.offY = (S.H - Config.DESIGN_H * S.scale) / 2

    S.ctx = nvgCreate(1)
    S.font = nvgCreateFont(S.ctx, "sans", "Fonts/MiSans-Regular.ttf")
    if S.font == -1 then print("[View] WARNING: font load failed") end

    S.regions = {}
    S.data = { version = 1, gold = 0, exp = 0, levels = { swordsman = 1 }, classExp = {}, unlocked = 20 }

    View.level = EnvLevel()
    LoadLevel(View.level)

    -- 自检：把布局数字打出来，方便在无截图时也能核对
    local cardW, gap = 232, 20
    local totalW = cardW * 3 + gap * 2
    print(string.format("[View] level=%d cards=%d 卡片总宽=%d (画布 %d) 居中左边距=%d",
        View.level, #View.cards, totalW, Config.DESIGN_W, (Config.DESIGN_W - totalW) / 2))
    for i, c in ipairs(View.cards) do
        print(string.format("[View] card%d %s × %s  risk=%+.2f %s%s  silver=%d 战斗%d 精英%d 商店%d 机遇%d",
            i, c.templateName, c.modName, c.risk, c.riskLabel,
            c.labelRelative and "(相对)" or "", c.preview.silver,
            c.preview.combat, c.preview.elite, c.preview.shop, c.preview.special))
    end
    local l = View.layer
    local specials = {}
    for _, s in ipairs(l.specials) do
        specials[#specials + 1] = string.format("%s@(%d,%d)%s", s.kind, s.r, s.c, s.deadEnd and "·死胡同" or "")
    end
    local edgeCount = 0
    for _, list in pairs(l.edges) do edgeCount = edgeCount + #list end
    print(string.format("[View] layer %dx%d 边=%d 机遇房=%s", l.cols, l.rows, edgeCount, table.concat(specials, " ")))

    SubscribeToEvent(S.ctx, "NanoVGRender", "HandleRender")
    SubscribeToEvent("Update", "HandleUpdate")
    print("[View] started")
end
