-- FriendUI.lua — 好友农场界面：好友列表 / 访问好友农场（浇水 · 偷菜）/ 消息
-- 数值与规则见 Friend.lua，设计依据 docs 农场系统设计（友好度 / 偷菜 / 浇水）

local Config = require "Config"
local UI = require "UI"
local S = require "State"
local Farm = require "Farm"
local Friend = require "Friend"
local FarmClient = require "network.FarmClient"

local FriendUI = {}

--- 联机状态：offline / connecting / online
local function NetState()
    if FarmClient.online then return "online" end
    if IsNetworkMode and IsNetworkMode() then return "connecting" end
    return "offline"
end



local PANEL = { x = 60, y = 66, w = 1160, h = 588 }

local function FmtTime(sec)
    sec = math.max(0, math.floor(sec or 0))
    if sec <= 0 then return "好了" end
    local h = math.floor(sec / 3600)
    local m = math.floor((sec % 3600) / 60)
    if h > 0 then return string.format("%d 小时 %d 分", h, m) end
    if m > 0 then return string.format("%d 分", m) end
    return string.format("%d 秒", sec)
end

local function StageColor(info)
    if info.status == "mature" then return { 140, 235, 150 } end
    if info.stolen then return { 200, 150, 110 } end
    if info.stage == 3 then return { 200, 220, 140 } end
    if info.stage == 2 then return { 150, 205, 160 } end
    return { 130, 165, 140 }
end

local function Backdrop()
    nvgBeginPath(S.ctx)
    nvgRect(S.ctx, 0, 0, Config.DESIGN_W, Config.DESIGN_H)
    nvgFillColor(S.ctx, nvgRGBA(8, 11, 9, 235))
    nvgFill(S.ctx)
    UI.Panel(PANEL.x, PANEL.y, PANEL.w, PANEL.h, 16, { 18, 22, 19, 250 }, { 70, 110, 82, 255 }, 1)
end

local function Header(title, sub)
    UI.Text(PANEL.x + 24, PANEL.y + 16, 24, title, { 185, 230, 175 })
    if sub then
        UI.Text(PANEL.x + 24, PANEL.y + 48, 12, sub, S.col.dim)
    end
    UI.Button("friend_back", PANEL.x + PANEL.w - 110, PANEL.y + 14, 90, 32, "返回", function()
        if S.friendView and (S.friendView.id or S.friendView.view == "search" or S.friendView.view == "requests" or S.friendView.view == "add") then
            S.friendView = nil            -- 从好友农场回到列表
        else
            S.friendOpen = false          -- 从列表回到农场
        end
    end, { fontSize = 14 })
end

-- ---------------------------------------------------------------- 好友列表
local function DrawList(data)
    local fr = Friend.Ensure(data)
    local list = Friend.List(data)
    if not FarmClient.online then
        UI.Text(PANEL.x + 24, PANEL.y + 96, 12,
            "离线模式：现在是本地模拟好友。加好友 / 访问真人农场请退出后从大厅选「联机农场」。",
            { 230, 190, 120 })
    end
    Header("好友农场", string.format("%s：%s　·　好友 %d / %d　·　今日 浇水 %d/%d　偷菜 %d/%d　赠送 %d/%d",
        FarmClient.online and "我的玩家ID" or (NetState() == "connecting" and "我的玩家ID" or "离线模拟码"),
        FarmClient.online and tostring(FarmClient.uid or "?") or fr.myCode,
        #list, Friend.MAX_FRIENDS,
        fr.day.water or 0, Friend.DAILY_WATER,
        fr.day.steal or 0, Friend.DAILY_STEAL,
        fr.day.gift or 0, Friend.DAILY_GIFT))

    UI.Button("friend_add", PANEL.x + PANEL.w - 220, PANEL.y + 14, 100, 32, "添加好友", function()
        S.friendView = { view = "add" }
        S.friendSearch = ""
        S.friendSearchResult = nil
    end, { fontSize = 13, fill = { 40, 96, 60, 255 }, stroke = { 120, 200, 140 } })

    -- 在线 / 离线状态
    local netState = NetState()
    local online = netState == "online"
    local stateText = netState == "online" and ("● 已连服务器　" .. tostring(FarmClient.uid or ""))
        or (netState == "connecting" and "◐ 正在连接服务器…" or "○ 离线（本地模拟）")
    if netState == "connecting" then
        stateText = string.format("◐ 正在连接服务器…（第 %d 次同步）", (S.farmNetTries or 0))
        -- 服务端自检：读服务端写进本人云变量的状态（能直接看出服务端到底跑没跑）
        S.diagClock = (S.diagClock or 0) + 1
        if S.diagClock % 60 == 1 then FarmClient.ReadServerDiag() end
        local sd = FarmClient.serverDiag
        if sd and sd.boot then
            UI.Text(PANEL.x + 24, PANEL.y + 74, 11,
                string.format("服务端自检：已启动（%s）· 收到同步 %s 次",
                    os.date("%H:%M:%S", sd.boot or 0), tostring(sd.syncCount or 0)),
                { 140, 220, 170 })
        elseif FarmClient.serverDiagErr then
            UI.Text(PANEL.x + 24, PANEL.y + 58, 11,
                "服务端自检：读不到（" .. tostring(FarmClient.serverDiagErr) .. "）", { 200, 170, 130 })
        else
            UI.Text(PANEL.x + 24, PANEL.y + 58, 11, "服务端自检：读取中…", S.col.dim)
        end
        if (S.farmNetTries or 0) >= 10 then
            UI.Text(PANEL.x + 24, PANEL.y + 58, 11,
                "服务端没有回包：可能服务端脚本没启动或事件没注册，请把这一屏反馈给开发",
                { 230, 160, 120 })
        end
    end
    UI.Text(PANEL.x + 24, PANEL.y + 74, 11, stateText,
        netState == "online" and { 120, 220, 150 }
        or (netState == "connecting" and { 230, 200, 120 } or S.col.dim))

    local unread = Friend.Unread(data)
    UI.Button("friend_msg", PANEL.x + PANEL.w - 320, PANEL.y + 14, 92, 32,
        unread > 0 and string.format("消息 %d", unread) or "消息", function()
            S.friendView = { view = "notify" }
            Friend.MarkRead(data)
        end, { fontSize = 13 })

    do
        local reqN = 0
        for _ in pairs(FarmClient.requestsIn or {}) do reqN = reqN + 1 end
        UI.Button("friend_search_btn", PANEL.x + 24, PANEL.y + 92, 130, 30, "搜索好友", function()
            if not FarmClient.online then
                UI.SetToast("需要联机模式：退回大厅选「联机进入」", 2.4)
                return
            end
            S.friendView = { view = "search" }
            S.friendSearch = ""
        end, { fontSize = 13, fill = { 40, 62, 96, 255 }, stroke = { 120, 170, 230 } })
        UI.Button("friend_req_btn", PANEL.x + 164, PANEL.y + 92, 130, 30,
            reqN > 0 and ("好友请求 " .. reqN) or "好友请求", function()
                if not FarmClient.online then
                    UI.SetToast("需要联机模式：退回大厅选「联机进入」", 2.4)
                    return
                end
                S.friendView = { view = "requests" }
            end, { fontSize = 13, fill = { 78, 62, 40, 255 }, stroke = S.col.orange })
    end

    if #list == 0 then
        UI.Text(PANEL.x + PANEL.w / 2, PANEL.y + 240, 16,
            "还没有好友　·　点右上角「添加好友」先加几个", S.col.dim,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        return
    end

    local w, h, gap = 540, 108, 16
    for i, f in ipairs(list) do
        local col = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        local x = PANEL.x + 24 + col * (w + gap)
        local y = PANEL.y + 84 + row * (h + 12)
        if y + h > PANEL.y + PANEL.h - 12 then break end

        local lv = Friend.LevelOf(f)
        local nextNeed = Friend.NextNeed(f)
        local levelName = Friend.LevelName(f)

        UI.Panel(x, y, w, h, 12, { 26, 32, 27, 240 }, { 74, 110, 86, 255 }, 1)
        UI.Text(x + 16, y + 12, 17, f.name, { 220, 235, 215 })
        UI.Text(x + 16, y + 36, 12, string.format("Lv.%d %s　·　友好度 %d%s",
            lv, levelName, f.friendship or 0,
            nextNeed and string.format(" / %d", nextNeed) or "（满级）"), S.col.dim)

        -- 进度条
        local from = Friend.LEVELS[lv + 1] and Friend.LEVELS[lv + 1].need or 0
        local prog = nextNeed and math.min(1, ((f.friendship or 0) - from) / math.max(1, nextNeed - from)) or 1
        nvgBeginPath(S.ctx)
        nvgRect(S.ctx, x + 16, y + 56, w - 32, 6)
        nvgFillColor(S.ctx, nvgRGBA(52, 60, 52, 255))
        nvgFill(S.ctx)
        nvgBeginPath(S.ctx)
        nvgRect(S.ctx, x + 16, y + 56, (w - 32) * prog, 6)
        nvgFillColor(S.ctx, nvgRGBA(120, 200, 140, 255))
        nvgFill(S.ctx)

        local growing, mature = 0, 0
        local land = f.farm and f.farm.landCount or 4
        for i2 = 1, land do
            local info = Friend.PlotInfo(f, i2)
            if info.status == "mature" then mature = mature + 1
            elseif info.status == "growing" then growing = growing + 1 end
        end
        UI.Text(x + 16, y + 72, 11, string.format("土地 %d 块　·　生长 %d　·　待收 %d%s",
            land, growing, mature,
            (f.dayGain or 0) >= Friend.DAY_GAIN_CAP and "　·　今日友好度已满" or ""), S.col.dim)

        UI.Button("friend_visit_" .. f.id, x + w - 206, y + 66, 96, 30, "访问农场",
            function() S.friendView = { view = "farm", id = f.id } end,
            { fontSize = 13, fill = { 40, 96, 60, 255 }, stroke = { 120, 200, 140 } })
        UI.Button("friend_gift_" .. f.id, x + w - 102, y + 66, 86, 30, "赠送种子",
            function()
                local ok, msg = Friend.Gift(data, f.id)
                UI.SetToast(msg, 2.4)
            end, { fontSize = 12, enabled = (Friend.Ensure(data).day.gift or 0) < Friend.DAILY_GIFT })
    end
end

-- ---------------------------------------------------------------- 好友农场
local function DrawFarm(data)
    local f = Friend.Get(data, S.friendView.id)
    if not f then
        S.friendView = nil
        return
    end
    local info0 = Friend.Plots(f)
    local land = f.farm.landCount or 4
    Header(string.format("%s 的农场", f.name),
        string.format("友好度 %d（Lv.%d %s）　·　我的今日浇水 %d/%d　偷菜 %d/%d",
            f.friendship or 0, Friend.LevelOf(f), Friend.LevelName(f),
            Friend.Ensure(data).day.water or 0, Friend.DAILY_WATER,
            Friend.Ensure(data).day.steal or 0, Friend.DAILY_STEAL))

    -- 一键三连
    local canAll = Friend.LevelOf(f) >= 2
    UI.Button("friend_waterall", PANEL.x + PANEL.w - 230, PANEL.y + 14, 110, 32,
        canAll and "一键三连" or "三连(Lv.2)", function()
            local ok, msg = Friend.WaterAll(data, f.id)
            UI.SetToast(msg, 2.4)
        end, { fontSize = 13, enabled = canAll })

    local cols = 3
    local cw, ch, gap = 300, 146, 16
    for i = 1, 9 do
        local info = info0[i] or { status = "locked" }
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        local x = PANEL.x + 24 + col * (cw + gap)
        local y = PANEL.y + 84 + row * (ch + 10)

        if info.status == "locked" then
            UI.Panel(x, y, cw, ch, 10, { 18, 20, 18, 200 }, { 50, 56, 50, 255 }, 1)
            UI.Text(x + cw / 2, y + ch / 2, 13, "未开垦", { 130, 135, 125 },
                NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        elseif info.status == "empty" then
            UI.Panel(x, y, cw, ch, 10, { 22, 26, 22, 230 }, { 62, 74, 62, 255 }, 1)
            UI.Text(x + cw / 2, y + ch / 2, 13, "空地", { 130, 140, 130 },
                NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        else
            local col2 = StageColor(info)
            UI.Panel(x, y, cw, ch, 10, { 26, 32, 27, 240 }, col2, 1)
            UI.Text(x + 14, y + 10, 16, info.crop.name, col2)
            UI.Text(x + 14, y + 34, 12, info.stageName, S.col.dim)
            if info.status == "mature" then
                if info.stolen then
                    UI.Text(x + 14, y + 56, 12, "已被偷过一次（收获 -1）", { 220, 170, 120 })
                else
                    UI.Text(x + 14, y + 56, 12,
                        info.canSteal and "已过保护期，可以偷" or
                        string.format("保护期还剩 %s", FmtTime(info.protectLeft)), S.col.dim)
                end
            else
                UI.Text(x + 14, y + 56, 12, string.format("阶段剩余 %s", FmtTime(info.stageRemain)), S.col.dim)
            end

            if info.status == "growing" then
                UI.Button("friend_water_" .. i, x + 14, y + ch - 44, cw - 28, 32,
                    info.waterReady and "浇水（-15 分钟 · 友好度 +1）" or
                    string.format("%d 分钟后可浇", math.ceil(info.waterCd / 60)),
                    function()
                        local ok, msg = Friend.Water(data, f.id, i)
                        UI.SetToast(msg, 2.4)
                    end, { fontSize = 12, enabled = info.waterReady,
                        fill = { 36, 92, 128, 255 }, stroke = { 120, 190, 230 } })
            else
                local label = info.stolen and "已被偷过"
                    or (info.canSteal and "偷菜（拿走 1 个果实）" or "还在保护期")
                UI.Button("friend_steal_" .. i, x + 14, y + ch - 44, cw - 28, 32, label,
                    function()
                        local ok, msg = Friend.Steal(data, f.id, i)
                        UI.SetToast(msg, 2.4)
                    end, { fontSize = 12, enabled = info.canSteal,
                        fill = { 120, 86, 40, 255 }, stroke = { 230, 190, 120 } })
            end
        end
    end
end



-- ---------------------------------------------------------------- 加好友（输入好友码）
local function MyCode()
    if FarmClient.online and FarmClient.code then return FarmClient.code end
    return Friend.MyCode(S.data)
end

local function DrawAddFriend(data)
    Header("添加好友", "输入对方的 6 位好友码即可添加；好友码在「我的」或个人界面里能查到")

    -- 我的好友码（方便念给对方）
    UI.Panel(PANEL.x + 24, PANEL.y + 92, 420, 62, 10, { 24, 32, 26, 240 }, S.col.cyan, 1)
    UI.Text(PANEL.x + 40, PANEL.y + 102, 12, "我的好友码", S.col.dim)
    UI.Text(PANEL.x + 40, PANEL.y + 120, 24, MyCode(), { 150, 240, 180 })
    local st = NetState()
    UI.Text(PANEL.x + 300, PANEL.y + 116, 11,
        st == "online" and "在线 · 可被搜索"
        or (st == "connecting" and "连接中…" or "离线模拟"), S.col.dim)

    -- 输入区
    local q = S.friendSearch or ""
    UI.Panel(PANEL.x + 24, PANEL.y + 168, 420, 54, 10, { 22, 26, 32, 240 }, S.col.line, 1)
    UI.Text(PANEL.x + 40, PANEL.y + 182, 22, q ~= "" and q or "输入 6 位好友码…",
        q ~= "" and S.col.text or S.col.dim)

    -- 软键盘（只到输入好友码需要的字符集）
    local x0, y0 = PANEL.x + 24, PANEL.y + 240
    local kw, kh, gap = 40, 40, 5
    for i = 1, #KEY_CHARS do
        local ch = KEY_CHARS:sub(i, i)
        local col = (i - 1) % 10
        local row = math.floor((i - 1) / 10)
        UI.Button("ak_" .. ch, x0 + col * (kw + gap), y0 + row * (kh + gap), kw, kh, ch,
            function()
                if #(S.friendSearch or "") < 8 then
                    S.friendSearch = (S.friendSearch or "") .. ch
                end
            end, { fontSize = 15 })
    end
    local rx = x0 + 10 * (kw + gap) + 10
    UI.Button("ak_back", rx, y0, 110, kh, "退格", function()
        local t = S.friendSearch or ""
        S.friendSearch = t:sub(1, math.max(0, #t - 1))
    end, { fontSize = 14 })
    UI.Button("ak_clear", rx, y0 + (kh + gap), 110, kh, "清空", function()
        S.friendSearch = ""
    end, { fontSize = 14 })
    UI.Button("ak_go", rx, y0 + (kh + gap) * 2, 110, kh, "查找并添加", function()
        local code = (S.friendSearch or ""):upper():gsub("%s", "")
        if #code ~= 6 then
            UI.SetToast("好友码是 6 位字母数字", 1.8)
            return
        end
        if FarmClient.online then
            FarmClient.Search(code)          -- 服务端按好友码查
        else
            local okAdd, msg = Friend.AddByCode(data, code)   -- 离线：本地模拟加好友
            UI.SetToast(msg or (okAdd and "已添加好友" or "添加失败"), 2.2)
            if okAdd then S.friendView = nil end
        end
    end, { fontSize = 13, fill = { 40, 96, 60, 255 }, stroke = { 120, 200, 140 } })

    -- 右侧：查找结果
    local res = FarmClient.searchResult or {}
    UI.Text(PANEL.x + 500, PANEL.y + 92, 14,
        FarmClient.online and string.format("查找结果（%d）", #res) or "离线模式",
        S.col.cyan)
    if not FarmClient.online then
        UI.TextBox(PANEL.x + 500, PANEL.y + 122, 420, 12,
            "现在没有连服务器，输入好友码只会在本地模拟加一个好友。\n想加真人：退回大厅选「联机进入」，进来后再用这里的搜索。",
            S.col.dim)
        return
    end
    for i, r in ipairs(res) do
        local y = PANEL.y + 124 + (i - 1) * 56
        if y > PANEL.y + PANEL.h - 60 then break end
        UI.Panel(PANEL.x + 500, y, 420, 48, 8, { 26, 30, 28, 240 }, S.col.line, 1)
        UI.Text(PANEL.x + 516, y + 8, 15, r.name or r.uid, S.col.text)
        UI.Text(PANEL.x + 516, y + 28, 10,
            "好友码 " .. tostring(r.code or "-") .. "　ID " .. tostring(r.uid), S.col.dim)
        UI.Button("ak_add_" .. tostring(r.uid), PANEL.x + 800, y + 10, 108, 28, "加好友",
            function()
                FarmClient.RequestFriend(r.uid)
                UI.SetToast("已发送好友请求", 1.8)
            end, { fontSize = 12, fill = { 40, 96, 60, 255 }, stroke = { 120, 200, 140 } })
    end
end

-- ---------------------------------------------------------------- 搜索好友（带软键盘）
local KEY_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

local function DrawKeyboard()
    local x0, y0 = PANEL.x + 24, PANEL.y + 210
    local kw, kh, gap = 74, 40, 6
    for i = 1, #KEY_CHARS do
        local ch = KEY_CHARS:sub(i, i)
        local col = (i - 1) % 10
        local row = math.floor((i - 1) / 10)
        UI.Button("fk_" .. ch, x0 + col * (kw + gap), y0 + row * (kh + gap), kw, kh, ch,
            function()
                if #(S.friendSearch or "") < 16 then
                    S.friendSearch = (S.friendSearch or "") .. ch
                end
            end, { fontSize = 16 })
    end
    local rx = x0 + 10 * (kw + gap) + 8
    UI.Button("fk_back", rx, y0, 92, kh, "退格", function()
        local t = S.friendSearch or ""
        S.friendSearch = t:sub(1, math.max(0, #t - 1))
    end, { fontSize = 14 })
    UI.Button("fk_clear", rx, y0 + (kh + gap), 92, kh, "清空", function()
        S.friendSearch = ""
    end, { fontSize = 14 })
    UI.Button("fk_go", rx, y0 + (kh + gap) * 2, 92, kh, "搜索", function()
        local q = S.friendSearch or ""
        if q == "" then
            UI.SetToast("先输入玩家 ID 或名字", 1.6)
            return
        end
        FarmClient.Search(q)
    end, { fontSize = 14, fill = { 40, 96, 60, 255 }, stroke = { 120, 200, 140 } })
end

local function DrawSearch()
    Header("搜索好友", "输入玩家 ID（精确）或名字（前缀）——在线时才能搜到真实玩家")
    local q = S.friendSearch or ""
    UI.Panel(PANEL.x + 24, PANEL.y + 130, 620, 56, 10, { 22, 26, 32, 240 }, S.col.cyan, 1)
    UI.Text(PANEL.x + 40, PANEL.y + 146, 22, q ~= "" and q or "点下面键盘输入…",
        q ~= "" and S.col.text or S.col.dim)

    DrawKeyboard()

    -- 搜索结果
    local res = FarmClient.searchResult or {}
    UI.Text(PANEL.x + 680, PANEL.y + 130, 14, string.format("搜索结果（%d）", #res), S.col.cyan)
    for i, r in ipairs(res) do
        local y = PANEL.y + 162 + (i - 1) * 52
        if y > PANEL.y + PANEL.h - 60 then break end
        UI.Panel(PANEL.x + 680, y, 380, 44, 8, { 26, 30, 28, 240 }, S.col.line, 1)
        UI.Text(PANEL.x + 694, y + 6, 15, r.name or r.uid, S.col.text)
        UI.Text(PANEL.x + 694, y + 26, 10, "ID " .. tostring(r.uid), S.col.dim)
        UI.Button("fx_add_" .. tostring(r.uid), PANEL.x + 940, y + 8, 106, 28, "加好友",
            function()
                FarmClient.RequestFriend(r.uid)
                UI.SetToast("已发送好友请求", 1.8)
            end, { fontSize = 12, fill = { 40, 96, 60, 255 }, stroke = { 120, 200, 140 } })
    end
end

-- ---------------------------------------------------------------- 好友请求
local function DrawRequests()
    Header("好友请求", "同意后就能互相访问农场、浇水、偷菜")
    local list = {}
    for uid, info in pairs(FarmClient.requestsIn or {}) do
        list[#list + 1] = { uid = uid, name = (type(info) == "table" and info.name) or uid }
    end
    table.sort(list, function(a, b) return a.uid < b.uid end)
    if #list == 0 then
        UI.Text(PANEL.x + PANEL.w / 2, PANEL.y + 240, 15, "暂时没有新的好友请求", S.col.dim,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        return
    end
    for i, r in ipairs(list) do
        local y = PANEL.y + 100 + (i - 1) * 60
        if y > PANEL.y + PANEL.h - 60 then break end
        UI.Panel(PANEL.x + 24, y, 620, 52, 8, { 26, 30, 28, 240 }, S.col.line, 1)
        UI.Text(PANEL.x + 40, y + 8, 16, r.name, S.col.text)
        UI.Text(PANEL.x + 40, y + 30, 10, "ID " .. r.uid, S.col.dim)
        UI.Button("freq_ok_" .. r.uid, PANEL.x + 470, y + 10, 80, 32, "同意", function()
            FarmClient.AcceptFriend(r.uid)
            UI.SetToast("已同意", 1.6)
        end, { fontSize = 13, fill = { 40, 96, 60, 255 }, stroke = { 120, 200, 140 } })
        UI.Button("freq_no_" .. r.uid, PANEL.x + 558, y + 10, 80, 32, "拒绝", function()
            FarmClient.RemoveFriend(r.uid)
            UI.SetToast("已拒绝", 1.6)
        end, { fontSize = 13, fill = { 70, 40, 44, 255 }, stroke = S.col.red })
    end
end

-- ---------------------------------------------------------------- 消息
local function DrawNotify(data)
    local fr = Friend.Ensure(data)
    Header("农场消息", "好友帮你浇水、偷菜、来串门的记录")
    local list = fr.notify or {}
    if #list == 0 then
        UI.Text(PANEL.x + PANEL.w / 2, PANEL.y + 240, 15, "暂时没有新消息", S.col.dim,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        return
    end
    local y = PANEL.y + 84
    for i = #list, math.max(1, #list - 11), -1 do
        local m = list[i]
        UI.Text(PANEL.x + 24, y, 13,
            os.date("%m-%d %H:%M", m.t or 0) .. "　" .. tostring(m.text), S.col.text)
        y = y + 34
    end
end

-- ---------------------------------------------------------------- 主绘制
function FriendUI.Draw()
    local data = S.data
    if not data then return end
    local v = S.friendView or {}
    -- 打开界面时做一次"好友回访"结算（真联机后换成服务端事件）
    if not S.friendTicked then
        S.friendTicked = true
        Friend.Bootstrap(data)
        Friend.Tick(data)
    end
    Backdrop()
    if v.view == "add" then
        DrawAddFriend(S.data)
    elseif v.view == "search" then
        DrawSearch()
    elseif v.view == "requests" then
        DrawRequests()
    elseif v.view == "farm" and v.id then
        DrawFarm(data)
    elseif v.view == "notify" then
        DrawNotify(data)
    else
        DrawList(data)
    end
end

function FriendUI.Open()
    S.friendOpen = true
    S.friendView = nil
    S.friendTicked = nil
end

function FriendUI.Close()
    S.friendOpen = false
    S.friendView = nil
end

return FriendUI
