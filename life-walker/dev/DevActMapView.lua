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
local function RiskColor(risk)
    if risk <= 0.02 then return ACCENT.green end
    if risk <= 0.28 then return ACCENT.gold end
    return ACCENT.red
end

local function DrawMiniGrid(grid, x, y, cell, gap)
    local rows, cols = #grid, #grid[1]
    for r = 1, rows do
        for c = 1, cols do
            local room = Room(grid[r][c])
            local cx = x + (c - 1) * (cell + gap)
            local cy = y + (r - 1) * (cell + gap)
            UI.Panel(cx, cy, cell, cell, 5, room.fill, { 20, 16, 28, 255 }, 1)
            UI.Text(cx + cell / 2, cy + cell / 2, math.floor(cell * 0.44), room.ch, room.text,
                NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        end
    end
    return cols * cell + (cols - 1) * gap, rows * cell + (rows - 1) * gap
end

local function DrawCards()
    local cardW, cardH, gap = 384, 214, 18
    local totalW = cardW * 3 + gap * 2
    local x0 = (Config.DESIGN_W - totalW) / 2
    local y0 = 96

    for i, card in ipairs(View.cards) do
        local x = x0 + (i - 1) * (cardW + gap)
        local picked = (i == View.picked)
        local border = picked and ACCENT.cyan or S.col.line
        UI.Panel(x, y0, cardW, cardH, 12, picked and { 36, 42, 58, 255 } or S.col.panel, border, picked and 2 or 1)

        UI.Text(x + 18, y0 + 14, 20, card.templateName, S.col.text)
        UI.Text(x + 18, y0 + 44, 14, "× " .. card.modName, ACCENT.cyan)

        -- 风险徽标：三选一里最该先被看见的就是「这关多难」，所以给它带色的实心底 +
        -- 大一号的字，边框加粗。以前是近乎黑色的底 + 13px 字，跟旁边的小数字一个重量，
        -- 两张「轻松」几乎看不出区别。
        local rc = RiskColor(card.risk)
        local badgeW, badgeH = 104, 28
        local badgeX = x + cardW - 18 - badgeW
        UI.Panel(badgeX, y0 + 16, badgeW, badgeH, 14,
            { rc[1], rc[2], rc[3], 58 }, rc, 2)
        UI.Text(badgeX + badgeW / 2, y0 + 16 + badgeH / 2, 15,
            string.format("%s %+.2f", card.riskLabel, card.risk), rc,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

        -- 迷你地图
        DrawMiniGrid(card.grid, x + 18, y0 + 72, 30, 4)

        -- 数据
        local tx = x + 18 + 4 * 30 + 3 * 4 + 20
        local p = card.preview
        UI.Text(tx, y0 + 74, 14, "战斗", S.col.dim)
        UI.Text(tx + 44, y0 + 74, 15, tostring(p.combat), S.col.text)
        UI.Text(tx, y0 + 98, 14, "精英", S.col.dim)
        UI.Text(tx + 44, y0 + 98, 15, tostring(p.elite), ACCENT.red)
        UI.Text(tx, y0 + 122, 14, "商店", S.col.dim)
        UI.Text(tx + 44, y0 + 122, 15, tostring(p.shop), ACCENT.gold)
        UI.Text(tx, y0 + 146, 14, "机遇", S.col.dim)
        UI.Text(tx + 44, y0 + 146, 15, tostring(p.special), ACCENT.purple)
        UI.Text(tx, y0 + 174, 14, "全清期望", S.col.dim)
        -- 银币以前是 17px 亮绿，比难度徽标还抢眼（玩家先看到「能扫多少钱」）。
        -- 压回普通数字的重量，让风险排在收益前面。
        UI.Text(tx + 64, y0 + 172, 15, p.silver .. " 银币", S.col.text)

        UI.Region("card_" .. i, x, y0, cardW, cardH, function()
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

    local y = y0 + 76
    UI.Text(x0, y, 14, "本层机遇房", S.col.dim)
    y = y + 22
    if #layer.specials == 0 then
        UI.Text(x0, y, 15, "（没有）", S.col.dim)
        y = y + 24
    end
    for _, s in ipairs(layer.specials) do
        local room = Room(s.kind)
        UI.Panel(x0, y, 24, 24, 6, room.fill, ACCENT.gold, 1)
        UI.Text(x0 + 12, y + 12, 13, room.ch, room.text, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        local label = room.name .. "  (" .. s.r .. "," .. s.c .. ")"
        if s.deadEnd then label = label .. "  · 死胡同" end
        if s.wasEvent then label = label .. "  · 原事件房改造" end
        UI.Text(x0 + 34, y + 5, 14, label, S.col.text)
        y = y + 30
    end

    y = y + 10
    UI.Text(x0, y, 14, "图例", S.col.dim)
    y = y + 20
    local order = { "start", "light", "standard", "mixed", "elite", "double", "shop", "boss", "encounter", "wish" }
    for i, kind in ipairs(order) do
        local col = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        local rx = x0 + col * (w / 2)
        local ry = y + row * 24
        local room = Room(kind)
        UI.Panel(rx, ry, 18, 18, 4, room.fill, { 20, 16, 28, 255 }, 1)
        UI.Text(rx + 9, ry + 9, 11, room.ch, room.text, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        UI.Text(rx + 26, ry + 2, 13, room.name, S.col.dim)
    end
    UI.Text(x0, y + 5 * 24 + 2, 13, "卡片上的「遇」= 机遇占位（进层后才定具体类型）", S.col.dim)

    local noteY = y + 5 * 24 + 26
    UI.Text(x0, noteY, 13, "每层固定 1 个机遇房；村落改为战斗房 12% 掉落；", S.col.dim)
    UI.Text(x0, noteY + 20, 13, "「命运」收进得偿所愿的第五个方向「搏」。", S.col.dim)
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

    -- 节点图
    local gx, gy, cell, gap = 48, 336, 72, 12
    DrawLayerGraph(gx, gy, cell, gap)
    local gw = View.layer.cols * cell + (View.layer.cols - 1) * gap
    UI.Text(gx, gy + View.layer.rows * (cell + gap) + 4, 13,
        "4×4 节点图 · 金框 = 机遇房 / 死胡同", S.col.dim)

    DrawSideInfo(gx + gw + 40, 336, 560)

    UI.Text(48, 690, 13, "DevActMapView · 数据来自 ActMap.RollCards / GenerateLayer，种子固定", { 120, 112, 140, 255 })

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
    local cardW, gap = 384, 18
    local totalW = cardW * 3 + gap * 2
    print(string.format("[View] level=%d cards=%d 卡片总宽=%d (画布 %d) 居中左边距=%d",
        View.level, #View.cards, totalW, Config.DESIGN_W, (Config.DESIGN_W - totalW) / 2))
    for i, c in ipairs(View.cards) do
        print(string.format("[View] card%d %s × %s  risk=%+.2f %s  silver=%d 战斗%d 精英%d 商店%d 机遇%d",
            i, c.templateName, c.modName, c.risk, c.riskLabel, c.preview.silver,
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
