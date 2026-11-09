-- GuildUI.lua — 公会界面（主菜单覆盖层）
-- 5 个页签：主页 / 商店 / 科技 / 团本 / 互助

local Config = require "Config"
local Save = require "Save"
local UI = require "UI"
local S = require "State"
local Guild = require "Guild"
local Run = require "Run"

local GuildUI = {}

local TABS = { "主页", "商店", "科技", "团本", "互助" }

local function toast(msg, sec)
    UI.SetToast(msg, sec or 2.2)
end

-- 落盘 + 提示
local function commit(ok, msg)
    Save.Write(S.data)
    toast(msg)
    return ok
end

local function drawHeader()
    local g = Guild.Roll(S.data)
    UI.Text(130, 66, 28, "生命行者公会", S.col.text)
    UI.Text(130, 100, 13,
        "公会 Lv." .. Guild.Level(S.data) .. "/" .. Guild.MAX_LEVEL
        .. " · 离线公会：成员与战报由本地模拟，贡献币 / 经验 / 科技真实生效", S.col.dim)

    UI.Panel(880, 62, 270, 56, 12, S.col.panel2, S.col.line, 1)
    UI.Text(898, 74, 13, "贡献币", S.col.dim)
    UI.Text(1010, 70, 24, UI.FormatNumber(g.coins), S.col.gold)
    UI.Text(898, 96, 12, "本周 " .. g.weekEarned .. " / " .. Guild.COIN_CAP, S.col.dim)

    -- 页签
    for i, name in ipairs(TABS) do
        local x = 130 + (i - 1) * 152
        local active = (S.guildTab or 1) == i
        UI.Button("guild_tab_" .. i, x, 118, 140, 38, name, function()
            S.guildTab = i
        end, {
            fontSize = 16,
            fill = active and { 46, 76, 92, 255 } or { 34, 31, 46, 255 },
            stroke = active and S.col.cyan or S.col.line,
            accent = active and S.col.cyan or nil,
        })
    end

    UI.Button("guild_close", 1000, 118, 150, 38, "关闭 Esc", function()
        S.guild = false
    end, { fontSize = 15 })
end

-- ---------------------------------------------------------------- 主页
local function drawHome()
    local g = Guild.Roll(S.data)
    local lv = Guild.Level(S.data)
    local total = Guild.TotalExp(S.data)
    local need = Guild.LevelNeed(S.data)
    local prog = Guild.LevelProgress(S.data)
    local canUp = Guild.CanLevelUp(S.data)

    UI.Panel(130, 168, 520, 452, 14, S.col.panel, S.col.line, 1)
    UI.Text(154, 186, 20, "公会等级 Lv." .. lv .. " / " .. Guild.MAX_LEVEL, S.col.cyan)

    if need then
        UI.Bar(154, 216, 472, 14, prog, S.col.cyan, { 40, 36, 52, 255 }, S.col.line)
        UI.Text(154, 238, 12,
            "公会总经验 " .. UI.FormatNumber(total) .. " / " .. UI.FormatNumber(need) .. "（升 Lv." .. (lv + 1) .. "）",
            S.col.dim)
    else
        UI.Bar(154, 216, 472, 14, 1, S.col.gold, { 40, 36, 52, 255 }, S.col.line)
        UI.Text(154, 238, 12, "公会总经验 " .. UI.FormatNumber(total) .. "（已满级）", S.col.dim)
    end

    -- 升级按钮
    UI.Button("guild_levelup", 154, 262, 240, 40,
        (need and canUp) and ("提升到 Lv." .. (lv + 1)) or (need and "经验不足" or "已满级"),
        function()
            local ok, msg = Guild.LevelUpGuild(S.data)
            commit(ok, msg)
        end, { fontSize = 15, enabled = canUp,
               fill = canUp and { 44, 66, 50, 255 } or nil,
               stroke = canUp and { 90, 150, 105, 255 } or nil })

    UI.Text(410, 272, 12, "个人经验 " .. (g.exp or 0) .. "  ·  全员合计 ×" .. #Guild.Members, S.col.dim)
    UI.Text(154, 310, 12,
        "每获得 1 贡献币，个人公会经验 +1；全员合计经验决定是否可以升级", S.col.dim)

    UI.Text(154, 344, 15, "贡献币余额", S.col.dim)
    UI.Text(154, 364, 28, UI.FormatNumber(g.coins), S.col.gold)
    if S.dev then
        UI.Button("guild_add_coins", 400, 356, 226, 40, "+1000 贡献币（测试）", function()
            local g2 = Guild.Roll(S.data)
            g2.coins = g2.coins + 1000
            g2.exp = (g2.exp or 0) + 1000
            Save.Write(S.data)
            toast("测试按钮：贡献币 +1000，个人公会经验 +1000")
        end, { fontSize = 13, fill = { 40, 52, 70, 255 }, stroke = { 76, 110, 150, 255 } })
    end

    local capRatio, earned = Guild.CapProgress(S.data)
    UI.Text(154, 410, 15, "本周产出 " .. earned .. " / " .. Guild.COIN_CAP .. "（软上限）", S.col.dim)
    UI.Bar(154, 434, 472, 14, capRatio, S.col.gold, { 40, 36, 52, 255 }, S.col.line)
    UI.Text(154, 456, 12,
        "达到上限后产出停止，溢出按 100:1 折算感谢信；社交行为仍可进行", S.col.dim)

    UI.Text(154, 486, 14, "累计贡献 " .. UI.FormatNumber(g.total or 0) .. " 币", S.col.text)
    UI.Text(154, 510, 14, "感谢信 " .. (g.thanks or 0) .. " 封", S.col.text)
    UI.Button("guild_thanks", 154, 536, 200, 36, "上交感谢信 +10 经验", function()
        local ok, msg = Guild.SubmitThanks(S.data)
        commit(ok, msg)
    end, { fontSize = 13, enabled = (g.thanks or 0) > 0 })

    UI.Text(154, 590, 12, "每周一 00:00 刷新：周产出上限 / 周限购商店 / 团本次数与评级", S.col.dim)

    -- 右：每日社交动作
    UI.Panel(674, 168, 476, 452, 14, S.col.panel, S.col.line, 1)
    UI.Text(698, 186, 20, "今日社交（每周一 00:00 刷新周产出）", S.col.cyan)

    UI.Button("guild_sign", 698, 216, 424, 40,
        g.sign and "今日已签到" or "签到并捐赠材料  +20", function()
            local ok, msg = Guild.Sign(S.data)
            commit(ok, msg)
        end, { fontSize = 15, enabled = not g.sign,
               fill = { 40, 62, 48, 255 }, stroke = { 86, 140, 100, 255 } })

    UI.Text(698, 268, 14, "灵魂摆渡（今日 " .. g.rescue .. "/3） 每次 +80", S.col.dim)
    local list = Guild.RescueList(S.data)
    for i, m in ipairs(list) do
        if i <= 3 then
            local y = 290 + (i - 1) * 44
            local used = S.data.guild.liked["rescue_" .. m.idx]
            local cls = Config.Classes[m.class]
            UI.Panel(698, y, 424, 38, 10, S.col.panel2, S.col.line, 1)
            UI.Text(712, y + 10, 14, m.name .. "（" .. (cls and cls.name or "?") .. "）",
                used and S.col.dim or S.col.text)
            UI.Button("guild_rescue_" .. i, 1010, y + 5, 100, 28,
                used and "已救援" or "+80 救援", function()
                    local ok, msg = Guild.Rescue(S.data, m.idx)
                    commit(ok, msg)
                end, { fontSize = 12, enabled = (not used) and g.rescue < 3 })
        end
    end

    UI.Text(698, 428, 14, "悬赏拓印（今日 " .. g.bounty .. "/2） 每次 +50", S.col.dim)
    local bl = Guild.BountyList(S.data)
    for i, b in ipairs(bl) do
        local y = 450 + (i - 1) * 44
        local used = S.data.guild.liked["bounty_" .. i]
        UI.Panel(698, y, 424, 38, 10, S.col.panel2, S.col.line, 1)
        UI.Text(712, y + 10, 14, b.name .. " 求购「" .. b.buff .. "」（" .. b.rarity .. "）",
            used and S.col.dim or S.col.text)
        UI.Button("guild_bounty_" .. i, 1010, y + 5, 100, 28,
            used and "已寄出" or "+50 寄出", function()
                local ok, msg = Guild.SendBounty(S.data, i)
                commit(ok, msg)
            end, { fontSize = 12, enabled = (not used) and g.bounty < 2 })
    end
end

-- ---------------------------------------------------------------- 商店
local function drawShop()
    local g = Guild.Roll(S.data)
    local lv = Guild.Level(S.data)

    UI.Panel(130, 168, 546, 452, 14, S.col.panel, S.col.line, 1)
    UI.Text(154, 186, 19, "每周限购 · 硬通货（公会 Lv." .. lv .. "）", S.col.gold)
    for i, item in ipairs(Guild.WeeklyItems) do
        local y = 214 + (i - 1) * 66
        local bought = g.shop.bought[item.id] or 0
        local locked = lv < (item.minLevel or 1)
        local soldOut = bought >= item.limit
        UI.Panel(154, y, 500, 60, 10, locked and { 30, 28, 40, 255 } or S.col.panel2, S.col.line, 1)
        UI.Text(168, y + 6, 15, "[" .. item.rarity .. "] " .. item.name,
            locked and S.col.dim or S.col.text)
        UI.Text(168, y + 26, 11, item.desc, S.col.dim)
        UI.Text(168, y + 44, 11, "已购 " .. bought .. "/" .. item.limit, S.col.dim)

        if locked then
            UI.Button("guild_buy_" .. item.id, 510, y + 12, 128, 36,
                "Lv." .. item.minLevel .. " 解锁", function()
                    toast("公会等级不足：需要 Lv." .. item.minLevel)
                end, { fontSize = 12, enabled = false })
        else
            UI.Button("guild_buy_" .. item.id, 510, y + 12, 128, 36,
                soldOut and "本周已满" or (item.price .. " 币"), function()
                    local ok, msg = Guild.BuyWeekly(S.data, item.id)
                    commit(ok, msg)
                end, { fontSize = 13, enabled = (not soldOut) and g.coins >= item.price })
        end
    end

    UI.Panel(690, 168, 460, 452, 14, S.col.panel, S.col.line, 1)
    UI.Text(714, 186, 19, "局内特权（下次开局生效）", S.col.cyan)
    for i, perk in ipairs(Guild.Perks) do
        local y = 216 + (i - 1) * 78
        local owned = g.perks[perk.id] or 0
        local locked = lv < (perk.minLevel or 1)
        UI.Panel(714, y, 412, 68, 10, locked and { 30, 28, 40, 255 } or S.col.panel2, S.col.line, 1)
        UI.Text(728, y + 8, 15,
            "[" .. perk.rarity .. "] " .. perk.name .. (owned > 0 and ("  x" .. owned) or ""),
            locked and S.col.dim or S.col.text)
        UI.Text(728, y + 30, 11, perk.desc, S.col.dim)
        if locked then
            UI.Button("guild_perk_" .. perk.id, 1030, y + 18, 88, 32,
                "Lv." .. perk.minLevel .. " 解锁", function()
                    toast("公会等级不足：需要 Lv." .. perk.minLevel)
                end, { fontSize = 11, enabled = false })
        else
            UI.Button("guild_perk_" .. perk.id, 1030, y + 18, 88, 32,
                perk.price .. " 币", function()
                    local ok, msg = Guild.BuyPerk(S.data, perk.id)
                    commit(ok, msg)
                end, { fontSize = 13, enabled = g.coins >= perk.price })
        end
    end

    UI.Button("guild_convert", 714, 546, 200, 38, "币转金币 10:1", function()
        local ok, msg = Guild.ConvertToGold(S.data)
        commit(ok, msg)
    end, { fontSize = 13, enabled = g.coins >= 10 })

    UI.Button("guild_cosmetic", 930, 546, 196, 38, "纪念物 / 外观（二期）", function()
        toast("纪念物与外观素材尚未接入，本期先不开放购买", 2.6)
    end, { fontSize = 12, enabled = false })
end

-- ---------------------------------------------------------------- 科技
local function drawTech()
    local g = Guild.Roll(S.data)
    local cap = Guild.TechCap(S.data)
    local lv = Guild.Level(S.data)
    UI.Text(130, 176, 15,
        "科技上限随公会等级提升：当前 Lv." .. lv .. " 公会 → 每条支线最高 " .. cap
        .. " 级（满级公会 10 级）", S.col.dim)
    for i, b in ipairs(Guild.Tech) do
        local y = 204 + (i - 1) * 138
        local tl = g.tech[b.id] or 0
        local c = S.col[b.color] or S.col.cyan
        UI.Panel(130, y, 1000, 124, 14, S.col.panel, S.col.line, 1)
        UI.Text(154, y + 12, 19, b.name .. "  Lv." .. tl .. "/" .. Guild.TECH_MAX, c)
        UI.Text(154, y + 40, 12, b.effectText, S.col.dim)
        UI.Text(154, y + 60, 12, b.maxText, S.col.dim)
        UI.Text(154, y + 84, 12,
            "已投入 " .. UI.FormatNumber(Guild.TechSpent(b.id, tl)) .. " 币", S.col.dim)

        -- 等级格子（超出公会等级上限的部分压暗）
        for k = 1, Guild.TECH_MAX do
            local px = 470 + (k - 1) * 26
            local filled = k <= tl
            local unlocked = k <= cap
            UI.Panel(px, y + 16, 20, 20, 5,
                filled and c or (unlocked and { 44, 40, 58, 255 } or { 28, 26, 36, 255 }),
                unlocked and S.col.line or { 40, 38, 50, 255 }, 1)
        end

        if tl >= cap then
            if cap >= Guild.TECH_MAX then
                UI.Text(850, y + 80, 15, "已满级", S.col.green)
            else
                UI.Text(850, y + 72, 13,
                    "公会 Lv." .. lv .. " 上限 " .. cap .. " 级", S.col.dim)
                UI.Text(850, y + 92, 12,
                    "升到 Lv." .. (lv + 1) .. " 解锁到 " .. (cap + 2) .. " 级", S.col.orange)
            end
        else
            local cost = Guild.TechCost(b.id, tl + 1)
            UI.Button("guild_tech_" .. b.id, 862, y + 48, 240, 44,
                "升级 → Lv." .. (tl + 1) .. "（" .. cost .. " 币）", function()
                    local ok, msg = Guild.UpgradeTech(S.data, b.id)
                    commit(ok, msg)
                end, { fontSize = 14, enabled = g.coins >= cost,
                       fill = { 40, 52, 70, 255 }, stroke = { 76, 110, 150, 255 } })
        end
    end
    UI.Text(130, 618, 12,
        "满级后多余的贡献币可走「币转金币」通道兜底（10:1）", S.col.dim)
end

-- ---------------------------------------------------------------- 团本
local function raidBossName()
    for _, m in ipairs(Config.Monsters) do
        if m.id == Guild.RAID_BOSS_ID then return m.name end
    end
    return Guild.RAID_BOSS_ID
end

local function drawRaid()
    local g = Guild.Roll(S.data)
    local lv = Guild.Level(S.data)
    local tier = Guild.RaidTier(S.data)
    local info = Guild.RaidTierInfo(tier)
    local maxTier = Guild.RaidTierMax(S.data)
    local bossName = raidBossName()

    UI.Panel(130, 168, 520, 452, 14, S.col.panel, S.col.line, 1)
    UI.Text(154, 184, 20, "公会团本 · " .. bossName, S.col.orange)
    UI.TextBox(154, 208, 472, 12,
        "每周一次（周一重置）。Boss 使用关底模型，数值先按第 1 关关底计算；"
        .. "出场技能跟随主界面选择的技能配置，个人贡献按输出量评 D~S。", S.col.dim)

    -- 当前档位 + BOSS 信息
    UI.Panel(154, 250, 472, 56, 10, S.col.panel2, S.col.line, 1)
    UI.Text(168, 258, 14, "难度：" .. info.name .. "  ·  BOSS：" .. bossName, S.col.cyan)
    UI.Text(168, 280, 12,
        "Boss 伤害 x" .. info.atkMul .. "  ·  结算贡献币 x" .. info.coinMul
        .. "  ·  已解锁 " .. maxTier .. "/" .. #Guild.RAID_TIERS .. " 档", S.col.text)

    UI.Text(154, 318, 13, "切换难度（公会 Lv." .. lv .. " 已解锁 " .. maxTier .. " 档）", S.col.dim)
    for i = 1, #Guild.RAID_TIERS do
        local ti = Guild.RAID_TIERS[i]
        local x = 154 + (i - 1) * 98
        local unlocked = i <= maxTier
        local active = (tier == i)
        UI.Button("guild_tier_" .. i, x, 338, 90, 34,
            unlocked and ti.name or (ti.name .. "·锁"), function()
                if not unlocked then
                    toast("公会 Lv." .. i .. " 解锁" .. ti.name .. "难度")
                    return
                end
                local ok, msg = Guild.SetRaidTier(S.data, i)
                commit(ok, msg)
            end, { fontSize = 13, enabled = unlocked,
                   fill = active and { 62, 44, 36, 255 }
                       or (unlocked and { 36, 34, 48, 255 } or { 28, 26, 36, 255 }),
                   stroke = active and S.col.orange or S.col.line })
    end

    local canRaid = Guild.RaidReady(S.data, S.dev)
    UI.Text(154, 384, 14, "本周状态：" ..
        (g.raid.done and ("已结算 · " .. (g.raid.tier and Guild.RaidTierInfo(g.raid.tier).name or "")
            .. " · 评级 " .. g.raid.grade .. "（输出 " .. g.raid.percent .. "%）")
            or "可挑战"), g.raid.done and S.col.dim or S.col.green)

    UI.Button("guild_raid_start", 154, 408, 300, 50,
        (g.raid.done and S.dev) and "再次挑战（测试）" or (g.raid.done and "本周已完成" or "挑战团本"),
        function()
            if not Guild.RaidReady(S.data, S.dev) then
                toast("本周团本已经结算过了")
                return
            end
            S.guild = false
            Run.StartRaid()
        end, { fontSize = 18, enabled = canRaid,
               fill = { 64, 40, 34, 255 }, stroke = { 150, 90, 60, 255 } })

    UI.Text(154, 466, 12, "提示：团本里死亡不会掉进度，按已造成的输出量结算评级。", S.col.dim)

    if S.dev then
        UI.Button("guild_reset_week", 154, 490, 380, 36,
            "一键重置（测试）：周限购 + 团本次数", function()
                local ok, msg = Guild.ResetWeeklyForTest(S.data)
                commit(ok, msg)
            end, { fontSize = 13, fill = { 56, 40, 36, 255 }, stroke = { 130, 80, 60, 255 } })
        UI.Text(154, 534, 12, "测试模式：团本可无限次重复体验，不计每周次数", S.col.cyan)
    end

    UI.Panel(690, 168, 460, 452, 14, S.col.panel, S.col.line, 1)
    UI.Text(714, 186, 20, "评级与奖励", S.col.gold)
    for i, row in ipairs(Guild.RAID_GRADES) do
        local y = 222 + (i - 1) * 56
        UI.Panel(714, y, 412, 48, 10, S.col.panel2, S.col.line, 1)
        UI.Text(730, y + 12, 22, row.grade,
            row.grade == "S" and S.col.gold or (row.grade == "A" and S.col.orange or S.col.text))
        UI.Text(790, y + 10, 13, "输出 ≥ Boss 血量 " .. row.min .. "%", S.col.dim)
        UI.Text(1090, y + 10, 18,
            math.floor(row.coins * info.coinMul + 0.5) .. " 币", S.col.gold,
            NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
    end
    UI.Text(714, 500, 12, "本周已获得团本贡献：" .. (g.raid.coins or 0) .. " 币", S.col.dim)
    UI.Text(714, 522, 12, "难度越高 Boss 伤害越高，贡献币也越多", S.col.dim)
    UI.Text(714, 544, 12, "BOSS 数值来源：第 1 关关底（瘟衰巨像模型）", S.col.dim)
end

-- ---------------------------------------------------------------- 互助（战报）
local function drawSocial()
    local g = Guild.Roll(S.data)
    UI.Text(130, 176, 15, "公会战报 · 点赞每次 +5 贡献币（今日 " .. g.likes .. "/5）", S.col.dim)
    local feed = Guild.Feed(S.data)
    for i, post in ipairs(feed) do
        local y = 204 + (i - 1) * 84
        UI.Panel(130, y, 1000, 74, 12, S.col.panel, S.col.line, 1)
        UI.Text(152, y + 10, 14, post.author .. " · " .. post.title, S.col.cyan)
        UI.TextBox(152, y + 32, 700, 12, post.text, S.col.text)
        UI.Button("guild_like_" .. i, 1022, y + 20, 88, 34,
            post.liked and "已赞" or "点赞 +5", function()
                local ok, msg = Guild.Like(S.data, i)
                commit(ok, msg)
            end, { fontSize = 13, enabled = (not post.liked) and g.likes < 5 })
    end
    UI.Text(130, 620, 12,
        "战报由本地模拟生成，每天刷新；达到周上限后点赞不产出贡献币，但仍可互动。", S.col.dim)
end

-- ---------------------------------------------------------------- 入口
function GuildUI.Draw()
    nvgBeginPath(S.ctx)
    nvgRect(S.ctx, 0, 0, Config.DESIGN_W, Config.DESIGN_H)
    nvgFillColor(S.ctx, nvgRGBA(0, 0, 0, 200))
    nvgFill(S.ctx)

    UI.Panel(90, 48, 1100, 624, 18, { 28, 24, 38, 252 }, S.col.line, 1)
    drawHeader()

    local tab = S.guildTab or 1
    if tab == 1 then drawHome()
    elseif tab == 2 then drawShop()
    elseif tab == 3 then drawTech()
    elseif tab == 4 then drawRaid()
    else drawSocial() end
end

return GuildUI
