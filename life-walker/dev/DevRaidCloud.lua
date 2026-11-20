-- DevRaidCloud.lua — 公会共斗（共享血量池）离线自检
-- 验证：周标记、血量池算法、本地累计与跨周重置、离线降级不崩

local Save = require "Save"
local Guild = require "Guild"
local RaidCloud = require "RaidCloud"
local Cloud = require "Cloud"
local Config = require "Config"
local S = require "State"

local fails = 0
local function check(name, cond, detail)
    if cond then
        print("[RaidCloudTest] OK   " .. name)
    else
        fails = fails + 1
        print("[RaidCloudTest] FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
    end
end

function Start()
    local data = Save.Fresh()
    Guild.Ensure(data)

    -- 周标记：必须是周一
    local tag = RaidCloud.WeekTag()
    local mondayDay = tag * 86400
    check("周标记以周一为起点", tonumber(os.date("%w", mondayDay)) == 1,
        os.date("%Y-%m-%d", mondayDay))

    -- Boss 血量 = 第 1 关关底
    local bossMax = RaidCloud.BossMax()
    check("Boss 血量取第 1 关关底", bossMax > 0, bossMax)

    -- 本地（无云数据）也能算血量池
    local pool0 = RaidCloud.Pool(data)
    check("离线血量池 = 满血", pool0.remaining == bossMax and pool0.dealt == 0,
        tostring(pool0.dealt) .. "/" .. tostring(bossMax))

    local dmg = math.floor(bossMax / 4)
    local total = RaidCloud.AddLocalDamage(data, dmg)
    check("本地累计输出", total == dmg and RaidCloud.LocalDamage(data) == dmg, total)
    local pool1 = RaidCloud.Pool(data)
    check("血量池扣减", pool1.dealt >= dmg and pool1.remaining == math.max(0, bossMax - pool1.dealt),
        tostring(pool1.dealt) .. "/" .. tostring(pool1.remaining))
    check("血量池比例与剩余自洽",
        math.abs(pool1.ratio - math.min(1, pool1.dealt / bossMax)) < 1e-9, pool1.ratio)

    RaidCloud.AddLocalDamage(data, 0)
    check("累加 0 不改变", RaidCloud.LocalDamage(data) == dmg)

    -- 跨周：旧记录应作废
    data.guild.raidCloud.week = 0
    check("跨周后本地输出清零", RaidCloud.LocalDamage(data) == 0,
        RaidCloud.LocalDamage(data))
    local pool2 = RaidCloud.Pool(data)
    check("跨周后血量池回满", pool2.dealt == 0 and pool2.remaining == bossMax)

    -- 离线提交：静默失败，不抛错
    local ok, err = pcall(function()
        return RaidCloud.Submit(data, true)
    end)
    check("离线上报不抛错", ok and err == false, tostring(err))

    -- 血量池被打穿
    RaidCloud.AddLocalDamage(data, bossMax + 100)
    check("输出超过总血量时剩余夹到 0", RaidCloud.Pool(data).remaining == 0)
    check("Defeated 判定", RaidCloud.Defeated(data) == true)

    -- 团本结算后本地会累进（走 Combat.FinishRaid 的同一条路径）
    data.guild.raidCloud = { week = RaidCloud.WeekTag(), dmg = 0 }
    local before = RaidCloud.LocalDamage(data)
    Guild.CompleteRaid(data, 90, true, 5000)
    RaidCloud.AddLocalDamage(data, 5000)
    check("团本结算后累计输出", RaidCloud.LocalDamage(data) == before + 5000,
        RaidCloud.LocalDamage(data))

    local okDraw, errDraw = pcall(function()
        S.data = Save.Load()
        Config.SetClass(Save.ActiveClass(S.data))
        S.ctx = S.ctx or nvgCreate(1)
        S.font = nvgCreateFont(S.ctx, "sans", "Fonts/MiSans-Regular.ttf")
        -- 伪造一份带公会名片的榜单缓存，检查详情面板两条分支
        local st = Cloud.State(Cloud.Boards[1].id)
        st.status = "ok"
        st.total = 2
        st.myRank = 2
        st.myScore = 9
        st.list = {
            { rank = 1, userId = 1001, score = 12, nickname = "测试行者",
              snap = { lv = 3, total = 8800, tech = 7, grade = "A" } },
            { rank = 2, userId = 1002, score = 9, nickname = "无名行者" },
        }
        S.rank = true
        S.rankTab = 1
        S.rankSel = st.list[1]
        require("RankUI").Draw()
        S.rankSel = st.list[2]
        require("RankUI").Draw()
        S.rankSel = nil
        require("RankUI").Draw()
        S.rank = false

        -- 公会团本页（含共享血量池 + 离线分支）
        S.screen = "menu"
        S.guild = true
        S.guildTab = 4
        require("Menu").Draw()
        S.guild = false
        require("Menu").Draw()
    end)
    check("排行榜详情面板/公会团本页绘制无错误", okDraw, errDraw)

    print("[RaidCloudTest] total fails = " .. fails)
end

function Stop() end
