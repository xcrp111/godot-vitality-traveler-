-- RankUI.lua — 云端排行榜界面（主菜单覆盖层）
-- 数据来自 Cloud.lua（clientCloud）；界面只读缓存，异步回调由 Cloud 负责。
local Config = require "Config"
local UI = require "UI"
local S = require "State"
local Cloud = require "Cloud"

local RankUI = {}

-- 实时性：打开页面先把本地最新贡献推上去，等一拍再强制拉一次；
-- 停留期间每 12 秒自动强刷，避免「榜上是旧数据、要关掉再开才更新」。
local AUTO_REFRESH = 12
local lastBoard = nil
local pendingAt = nil
local autoAt = 0

local MEDAL = {
    { 240, 205, 90 },    -- 第 1 名
    { 205, 210, 220 },   -- 第 2 名
    { 205, 155, 105 },   -- 第 3 名
}

-- 昵称是平台账号名，字集无法预知，单独用一份常用汉字字体，第一次画的时候才加载
local nickFace = nil
local nickTried = false
local function NickFace()
    if nickFace or nickTried then return nickFace end
    nickTried = true
    local ok, f = pcall(function()
        return nvgCreateFont(S.ctx, "nick", "Fonts/MiSans-Nickname.ttf")
    end)
    if ok and type(f) == "number" and f >= 0 then nickFace = f end
    return nickFace
end

local function BoardId()
    local tab = S.rankTab or 1
    local board = Cloud.Boards[tab] or Cloud.Boards[1]
    return board.id, board
end

local function DisplayName(entry)
    local name = entry.nickname
    if not name or name == "" then
        name = entry.userId and ("行者#" .. tostring(entry.userId)) or "未知行者"
    end
    return name
end

-- ---------------------------------------------------------------- 头部
local function drawHeader()
    UI.Panel(200, 60, 880, 600, 18, { 22, 26, 24, 252 }, S.col.line, 1)
    UI.Text(232, 78, 28, "排行榜", { 190, 225, 200 })
    UI.Text(352, 88, 13, "全服数据 · 只在联网时同步，离线也能正常游玩", S.col.dim)

    UI.Button("rank_close", 960, 72, 100, 36, "关闭 Esc", function()
        S.rank = false
    end, { fontSize = 14 })

    for i, board in ipairs(Cloud.Boards) do
        local x = 232 + (i - 1) * 156
        local active = (S.rankTab or 1) == i
        UI.Button("rank_tab_" .. i, x, 112, 146, 34, board.name, function()
            S.rankTab = i
            Cloud.Refresh(board.id, true)
        end, {
            fontSize = 15,
            fill = active and { 44, 68, 54, 255 } or { 34, 31, 40, 255 },
            stroke = active and { 120, 200, 140, 255 } or S.col.line,
            enabled = true,
        })
    end
end

-- ---------------------------------------------------------------- 列表
local function drawEmpty(msg, color)
    UI.Text(640, 380, 16, msg, color or S.col.dim,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
end

local function drawRows(board, st, x, y, w)
    local rowH = 21
    for i, entry in ipairs(st.list) do
        local ry = y + (i - 1) * rowH
        if ry + rowH > 596 then break end
        local me = Cloud.IsMe(entry.userId)
        if me then
            UI.Panel(x - 6, ry - 1, w + 12, rowH, 6, { 40, 60, 44, 255 },
                { 110, 190, 130, 255 }, 1)
        elseif i % 2 == 0 then
            UI.Panel(x - 6, ry - 1, w + 12, rowH, 6, { 30, 30, 28, 255 }, nil, 0)
        end
        local medal = MEDAL[i]
        local rankColor = medal and { medal[1], medal[2], medal[3], 255 } or S.col.dim
        UI.Text(x + 6, ry + 2, 14, tostring(entry.rank), rankColor)
        UI.Text(x + 52, ry + 2, 14, DisplayName(entry), me and S.col.green or S.col.text,
            NVG_ALIGN_LEFT + NVG_ALIGN_TOP, NickFace())
        UI.Text(x + w - 8, ry + 2, 14,
            string.format("%d %s", entry.score or 0, board.unit), S.col.gold,
            NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
        if entry.snap then
            UI.Text(x + w - 96, ry + 2, 11, "名片", { 130, 190, 160 },
                NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
        end
        UI.Region("rank_row_" .. i, x - 6, ry - 1, w + 12, rowH, function()
            if S.rankSel == entry then S.rankSel = nil else S.rankSel = entry end
        end, true)
    end
end

local function drawFooter(board, st)
    local parts = {}
    if st.myRank then
        parts[#parts + 1] = string.format("我的排名：第 %d 名", st.myRank)
    elseif st.status == "ok" then
        parts[#parts + 1] = "我还没有上榜"
    end
    if st.total then parts[#parts + 1] = string.format("共 %d 人上榜", st.total) end
    parts[#parts + 1] = board.tip
    UI.Text(232, 610, 13, table.concat(parts, "  ·  "), S.col.dim)
    UI.Button("rank_refresh", 940, 600, 120, 30, "刷新", function()
        Cloud.Refresh(board.id, true)
    end, { fontSize = 13 })
end

-- ---------------------------------------------------------------- 详情（公会名片）
local function drawDetail(board)
    local e = S.rankSel
    if not e then return end
    local x, y, w, h = 700, 372, 372, 212
    UI.Panel(x, y, w, h, 12, { 18, 22, 20, 252 }, { 90, 130, 105, 255 }, 1)
    UI.Text(x + 16, y + 12, 17, DisplayName(e), S.col.text,
        NVG_ALIGN_LEFT + NVG_ALIGN_TOP, NickFace())
    UI.Text(x + w - 16, y + 14, 12, "第 " .. tostring(e.rank) .. " 名", S.col.dim,
        NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
    UI.Text(x + 16, y + 40, 13,
        string.format("%s %d %s", board.name, e.score or 0, board.unit), S.col.gold)

    local snap = e.snap
    UI.Line(x + 16, y + 64, x + w - 16, y + 64, S.col.line, 1)
    if snap then
        local grade = (snap.grade ~= "" and snap.grade) or "—"
        UI.Text(x + 16, y + 74, 13, "公会等级", S.col.dim)
        UI.Text(x + 116, y + 74, 14, "Lv." .. tostring(snap.lv or 1), S.col.cyan)
        UI.Text(x + 16, y + 98, 13, "累计贡献", S.col.dim)
        UI.Text(x + 116, y + 98, 14, UI.FormatNumber(snap.total or 0), S.col.text)
        UI.Text(x + 16, y + 122, 13, "科技总等级", S.col.dim)
        UI.Text(x + 116, y + 122, 14, tostring(snap.tech or 0) .. " / 30", S.col.text)
        UI.Text(x + 16, y + 146, 13, "本周团本", S.col.dim)
        UI.Text(x + 116, y + 146, 14, grade .. " 级", S.col.orange)
        UI.Text(x + 16, y + 170, 11, "名片随排行榜一起上传，非实时刷新", S.col.dim)
    else
        UI.Text(x + 16, y + 78, 13, "这位行者还没上传公会名片", S.col.dim)
        UI.Text(x + 16, y + 100, 11, "对方打开过一次排行榜后就会带上名片", S.col.dim)
    end
    UI.Button("rank_sel_close", x + w - 100, y + h - 40, 84, 28, "关闭", function()
        S.rankSel = nil
    end, { fontSize = 12 })
end

-- ---------------------------------------------------------------- 主入口
function RankUI.Draw()
    local id, board = BoardId()
    local nowT = os.time()
    if lastBoard ~= id then
        -- 切榜 / 刚打开：立刻上传本地进度，1 秒后强制重拉（等上传落库）
        lastBoard = id
        Cloud.SubmitNow(S.data)
        pendingAt = nowT + 1
        autoAt = nowT + AUTO_REFRESH
    else
        Cloud.MaybeSubmit(S.data)
        if pendingAt and nowT >= pendingAt then
            pendingAt = nil
            Cloud.Refresh(id, true)
        elseif nowT >= autoAt then
            autoAt = nowT + AUTO_REFRESH
            Cloud.Refresh(id, true)
        end
    end
    local st = Cloud.State(id)

    nvgBeginPath(S.ctx)
    nvgRect(S.ctx, 0, 0, Config.DESIGN_W, Config.DESIGN_H)
    nvgFillColor(S.ctx, nvgRGBA(10, 12, 10, 215))
    nvgFill(S.ctx)

    drawHeader()

    UI.Panel(212, 158, 856, 436, 12, { 26, 28, 26, 235 }, S.col.line, 1)
    UI.Text(232, 168, 12, "排名", S.col.dim)
    UI.Text(284, 168, 12, "行者", S.col.dim)
    UI.Text(1044, 168, 12, board.name, S.col.dim, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
    UI.Line(226, 186, 1054, 186, S.col.line, 1)

    if st.status == "unsupported" then
        drawEmpty("当前环境不支持云排行")
        UI.Text(640, 406, 13, "需要在 TapTap 客户端内运行（本地调试 / 离线时不显示榜单）",
            S.col.dim, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        UI.Text(640, 428, 12, "诊断：" .. Cloud.Diag(), S.col.dim,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    elseif st.status == "error" and #st.list == 0 then
        drawEmpty("同步失败：" .. (st.err or "网络不可用"), { 220, 150, 140 })
    elseif #st.list == 0 then
        if st.status == "loading" then
            drawEmpty("正在同步榜单…")
        else
            drawEmpty("还没有人上榜，去打出第一个纪录")
        end
    end

    drawRows(board, st, 232, 192, 820)
    drawDetail(board)

    drawFooter(board, st)
end

return RankUI
