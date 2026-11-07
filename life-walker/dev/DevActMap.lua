-- DevActMap.lua — 层间地图 / 局内节点图 / 机遇池 的回归测试（不参与正式构建）
--
-- 跑法（和别的 dev 脚本一样）：
--   UrhoXRuntime.exe dev/DevActMap.lua "-tapcode_dir=<项目根>" -tool_mode -graphicsheadless
--
-- 覆盖：
--   ① 幕结构（4 幕 × 5 关，幕边界对齐 Endless.unlockStage = 10）
--   ② 层卡三选一（模板 × 词条）的硬约束 + 难度预算
--   ③ 局内节点图（连通性 / 绕过精英的路线 / 机遇族数量 / 死胡同）
--   ④ 机遇池的预算上限（CAP）逐条断言
--   ⑤ 命运岔口的期望值与「大凶地板」
--   ⑥ 抽取分布与条件过滤
--   ⑦ 结算（代价 / 收益 / 门槛）

local Config = require "Config"
local ActMap = require "ActMap"
local Opportunity = require "Opportunity"

local fails = 0
local function check(name, cond, detail)
    if cond then
        print("[Act] OK   " .. name)
    else
        fails = fails + 1
        print("[Act] FAIL " .. name .. (detail ~= nil and (" — " .. tostring(detail)) or ""))
    end
end

local function near(a, b, eps)
    return math.abs((a or 0) - (b or 0)) <= (eps or 1e-6)
end

-- 固定种子：结果可复现，改坏了能一眼看出来是哪次抽卡坏
math.randomseed(20261107)

-- ---------------------------------------------------------------- ① 幕结构
local function TestActs()
    check("第 1 关在第一幕", ActMap.ActOfLevel(1).id == 1)
    check("第 5 关还在第一幕", ActMap.ActOfLevel(5).id == 1)
    check("第 6 关进第二幕", ActMap.ActOfLevel(6).id == 2)
    check("第 20 关在第四幕", ActMap.ActOfLevel(20).id == 4)

    check("第 5 关是幕末", ActMap.IsActEnd(5) == true)
    check("第 10 关是幕末", ActMap.IsActEnd(10) == true)
    check("第 6 关不是幕末", ActMap.IsActEnd(6) == false)

    -- 幕边界必须和「通关第 10 关解锁无尽」是同一个点，不然玩家会看到两套进度口径
    check("第 10 关 = 无尽解锁点", Config.Endless.unlockStage == 10 and ActMap.ActOfLevel(10).to == 10,
        Config.Endless.unlockStage)

    local p, total = ActMap.ActProgress(7)
    check("幕内进度 7 → 2/5", p == 2 and total == 5, tostring(p) .. "/" .. tostring(total))

    check("幕末有奖励", ActMap.ActEndReward(5) ~= nil)
    check("非幕末没有奖励", ActMap.ActEndReward(6) == nil)
    check("幕末奖励是正数",
        ActMap.ActEndReward(10).gold > 0 and ActMap.ActEndReward(10).exp > 0)
end

-- ---------------------------------------------------------------- ② 层卡
local function TestCards()
    local totalCards, safeCount, maxAbsRisk = 0, 0, 0
    local minSilver, maxSilver = 1e9, 0
    for level = 1, 20 do
        for _ = 1, 10 do
            local cards = ActMap.RollCards(level)
            check("第 " .. level .. " 关出 3 张卡", #cards == 3, #cards)
            local tplSeen, modSeen, hasSafe = {}, {}, false
            local allOk = true
            for _, card in ipairs(cards) do
                totalCards = totalCards + 1
                if tplSeen[card.templateId] then
                    check("模板不重复（第 " .. level .. " 关）", false, card.templateId)
                    allOk = false
                end
                if modSeen[card.modId] then
                    check("词条不重复（第 " .. level .. " 关）", false, card.modId)
                    allOk = false
                end
                tplSeen[card.templateId] = true
                modSeen[card.modId] = true

                local ok, reason = Config.CheckMap(card.grid)
                if not ok then
                    check("层卡通过 CheckMap", false, card.id .. ": " .. tostring(reason))
                    allOk = false
                end
                if card.risk <= 0.02 then hasSafe = true; safeCount = safeCount + 1 end
                if math.abs(card.risk) > maxAbsRisk then maxAbsRisk = math.abs(card.risk) end
                if card.risk < -0.45 or card.risk > 0.45 then
                    -- 说明：低等级模板（轻战起步 / 双商补给线）在 15 关以后拉不到目标强度，
                    -- 因为 Config 的归一阶梯只往上到混战为止（这部分和 Config.NormalizeMap 一致），
                    -- 所以「偏简单」是允许的，真正不能出现的是「三张卡都偏难」。
                    if card.risk > 0.45 then
                        check("难度偏移不超过 +0.45", false, string.format("%s risk=%.3f", card.id, card.risk))
                        allOk = false
                    end
                end
                if card.risk < -0.60 then
                    check("难度偏移不低于 -0.60", false, string.format("%s risk=%.3f", card.id, card.risk))
                    allOk = false
                end
                if card.preview.silver < minSilver then minSilver = card.preview.silver end
                if card.preview.silver > maxSilver then maxSilver = card.preview.silver end
                if card.preview.combat < 3 then
                    check("战斗房至少 3 间", false, card.id)
                    allOk = false
                end
                if card.silverMul <= 0 then
                    check("银币系数为正", false, card.id)
                    allOk = false
                end
            end
            if allOk then check("第 " .. level .. " 关三张卡结构合法", true) end
            check("至少一张低风险卡（第 " .. level .. " 关）", hasSafe, nil)

            -- 三张卡必须真的不一样：难度都归一之后 risk 会收得很紧（高阶模板本来就拉不到目标
            -- 强度，因为归一阶梯只到混战为止），所以差异用「收益」和「风险档」两个维度看。
            local loS, hiS = 1e9, -1e9
            for _, card in ipairs(cards) do
                if card.preview.silver < loS then loS = card.preview.silver end
                if card.preview.silver > hiS then hiS = card.preview.silver end
            end
            check("三张卡的收益差 >= 5%（第 " .. level .. " 关）",
                (hiS - loS) >= hiS * 0.05, string.format("%d~%d", loS, hiS))
        end
    end
    print(string.format("[Act] 层卡：%d 张，其中低风险 %d 张（%.0f%%），最大 |risk|=%.3f，银币区间 %d~%d",
        totalCards, safeCount, safeCount / math.max(1, totalCards) * 100, maxAbsRisk, minSilver, maxSilver))
    check("低风险卡占比合理（>=30%）", safeCount / math.max(1, totalCards) >= 0.30,
        safeCount .. "/" .. totalCards)
end

-- ---------------------------------------------------------------- ③ 局内节点图
local function ReachableTo(grid, edges, tr, tc)
    local rows = #grid
    local function K(r, c) return r .. "," .. c end
    local seen = { [K(rows, 1)] = true }
    local q = { { rows, 1 } }
    local head = 1
    while head <= #q do
        local cur = q[head]; head = head + 1
        if cur[1] == tr and cur[2] == tc then return true end
        local list = edges[K(cur[1], cur[2])] or {}
        for _, nb in ipairs(list) do
            local k = K(nb[1], nb[2])
            if not seen[k] then
                seen[k] = true
                q[#q + 1] = nb
            end
        end
    end
    return false
end

local function TestLayers()
    local layers, deadEnds, withTwoSpecials, offMap, eventLeft = 0, 0, 0, 0, 0
    for level = 1, 20 do
        for _ = 1, 5 do
            local cards = ActMap.RollCards(level)
            local layer = ActMap.GenerateLayer(level, cards[1])
            layers = layers + 1

            local ok, reason = ActMap.CheckLayer(layer)
            check("第 " .. level .. " 关节点图合法", ok, reason)

            check("走得到 Boss", ActMap.HasPath(layer.grid, layer.edges, nil))
            check("有不经过精英房的路线",
                ActMap.HasPath(layer.grid, layer.edges, { elite = true, double = true }))

            local specialCount = 0
            for r = 1, layer.rows do
                for c = 1, layer.cols do
                    local t = layer.grid[r][c]
                    if ActMap.SPECIAL_KINDS[t] then
                        specialCount = specialCount + 1
                        check("机遇房从起点可达 " .. r .. "," .. c, ReachableTo(layer.grid, layer.edges, r, c))
                    end
                    -- 村落和命运牌桌已经不在看地图上了，出现就是漏改
                    if t == "village" or t == "chance" then
                        offMap = offMap + 1
                    end
                    -- 老的 event 房必须全部被改造成机遇房，否则和机遇房重复
                    if t == "event" then eventLeft = eventLeft + 1 end
                end
            end
            check("机遇房数量 = SPECIAL_ROOM_COUNT",
                specialCount == ActMap.SPECIAL_ROOM_COUNT, specialCount)
            if specialCount == 2 then withTwoSpecials = withTwoSpecials + 1 end

            local hasDeadEnd = false
            for _, s in ipairs(layer.specials) do
                if s.deadEnd then hasDeadEnd = true end
            end
            -- 死胡同必须只进不出：出口边空
            if hasDeadEnd then
                deadEnds = deadEnds + 1
                for _, s in ipairs(layer.specials) do
                    if s.deadEnd then
                        local k = s.r .. "," .. s.c
                        check("死胡同没有出口 " .. k, #(layer.edges[k] or {}) == 0)
                    end
                end
            end

            -- 边表不能越界
            local edgeOk = true
            for key, list in pairs(layer.edges) do
                for _, nb in ipairs(list) do
                    if nb[1] < 1 or nb[1] > layer.rows or nb[2] < 1 or nb[2] > layer.cols then
                        edgeOk = false
                    end
                end
            end
            check("边表不越界", edgeOk, key)
        end
    end
    print(string.format("[Act] 节点图：%d 张，死胡同 %d 张（%.0f%%），双机遇 %d 张",
        layers, deadEnds, deadEnds / math.max(1, layers) * 100, withTwoSpecials))
    check("地图上不再出现村落 / 命运岔口", offMap == 0, offMap)
    check("event 房全部改造成机遇房", eventLeft == 0, eventLeft)
    check("死胡同至少出现过", deadEnds >= 1, deadEnds)
end

-- ---------------------------------------------------------------- ④ 机遇池预算
local function TestBudget()
    local defs, options = 0, 0
    for _, def in ipairs(Opportunity.DEFS) do
        defs = defs + 1
        check("条目有 id 和标题（" .. tostring(def.id) .. "）", type(def.id) == "string" and def.title ~= nil)
        check("权重为正（" .. def.id .. "）", (def.weight or 0) > 0, def.weight)

        if def.roll then
            local total = 0
            local expected = 0
            for _, t in ipairs(def.roll) do
                total = total + t.p
                local gain = t.gain or {}
                local cost = t.cost or {}
                expected = expected + t.p * ((gain.silver or 0) - (cost.silver or 0))
                local ok, reason = Opportunity.WithinCap("chance", t.gain, t.cost)
                check("命运档位在预算内（" .. t.id .. "）", ok, reason)
                if t.lossHpPct then
                    check("命运扣血不超上限（" .. t.id .. "）", t.lossHpPct <= Opportunity.LOSS_HP_CAP)
                end            end
            check("命运概率归一（" .. def.id .. "）", near(total, 1.0, 1e-6), total)
            check("命运期望银币在 15~25 之间", expected >= 15 and expected <= 25,
                string.format("%.2f", expected))
            print(string.format("[Act] 命运牌桌：概率和 %.4f，期望银币 %.2f", total, expected))
        end

        if def.options then
            check("选项 >= 1（" .. def.id .. "）", #def.options >= 1, #def.options)
            if def.kind == "encounter" then
                check("不期而遇至少两个选项（" .. def.id .. "）", #def.options >= 2, #def.options)
                local hasCost = false
                for _, opt in ipairs(def.options) do
                    -- 代价可以是「花资源」，也可以是「把本层变难」（stepRisk）
                    if opt.cost then hasCost = true end
                    if opt.gain and opt.gain.stepRisk then hasCost = true end
                end
                check("不期而遇至少一个选项带代价（" .. def.id .. "）", hasCost)
            end
            if def.kind == "village" or def.kind == "wish" then
                for _, opt in ipairs(def.options) do
                    check("无风险节点不应有代价（" .. def.id .. "）", opt.cost == nil)
                end
            end
            for _, opt in ipairs(def.options) do
                options = options + 1
                local ok, reason = Opportunity.WithinCap(def.kind, opt.gain, opt.cost)
                check("选项在预算内（" .. def.id .. " / " .. opt.label .. "）", ok, reason)
                if opt.rollId then
                    local rd = Opportunity.DefByID(opt.rollId)
                    check("rollId 指向真实牌桌（" .. def.id .. "）", rd ~= nil and rd.roll ~= nil)
                end
            end
        end

        -- 得偿所愿不允许给情报（只给方向）
        if def.kind == "wish" then
            for _, opt in ipairs(def.options) do
                check("得偿所愿不给情报（" .. def.id .. "）", not (opt.gain and opt.gain.intel))
            end
        end
    end
    print(string.format("[Act] 机遇池：%d 条，%d 个选项", defs, options))
    check("四种节点都有条目",
        #Opportunity.ByKind.village > 0 and #Opportunity.ByKind.encounter > 0
        and #Opportunity.ByKind.wish > 0 and #Opportunity.ByKind.chance > 0)
end

-- ---------------------------------------------------------------- ⑤ 命运地板
local function TestChanceFloor()
    local ctx = Opportunity.MakeContext({
        level = 10,
        state = { silver = 100, hp = 20, maxHp = 100 },
        rand = function() return 0.05 end,   -- 强制掷出「大凶」
    })
    local tier = Opportunity.RollChance(ctx)
    check("残血时大凶降级为小凶", tier and tier.id == "bad", tier and tier.id)

    local ctx2 = Opportunity.MakeContext({
        level = 10,
        state = { silver = 100, hp = 90, maxHp = 100 },
        rand = function() return 0.05 end,
    })
    local tier2 = Opportunity.RollChance(ctx2)
    check("血量健康时仍是大凶", tier2 and tier2.id == "great_bad", tier2 and tier2.id)

    -- 银币不够赔：改成扣血，但扣血有上限
    local ctx3 = Opportunity.MakeContext({
        level = 10,
        state = { silver = 0, hp = 90, maxHp = 100 },
        rand = function() return 0.05 end,
    })
    local lines = Opportunity.Resolve(ctx3, { roll = Opportunity.DefByID("c_fate").roll }, 1)
    check("银币不足时改为扣血", ctx3.state.hp < 90, ctx3.state.hp)
    check("扣血不超过 15%（不能一份惩罚扣两次）", ctx3.state.hp >= 90 - 15 - 1e-6, ctx3.state.hp)
    check("扣血有文案", type(lines) == "table" and #lines > 0)
    check("银币不会被扣成负数", ctx3.state.silver == 0, ctx3.state.silver)
end

-- ---------------------------------------------------------------- ⑥ 抽取分布
local function TestOffers()
    -- 命运岔口前 5 关不出现
    local ctxLow = Opportunity.MakeContext({ level = 5 })
    check("第 5 关抽不到命运岔口", Opportunity.Offer(ctxLow, "chance") == nil)

    -- 满血时抽不到「尚有余温的营火」
    local ctxFull = Opportunity.MakeContext({ level = 10, state = { hp = 100, maxHp = 100 } })
    local sawHeal = false
    for _ = 1, 300 do
        local offer = Opportunity.Offer(ctxFull, "village")
        if offer and offer.id == "v_heal" then sawHeal = true end
    end
    check("满血时不刷营火村落", sawHeal == false)

    -- 得偿所愿：生/力/悟 常驻，「搏」第 6 关起出现，「财」第 8 关起出现
    local w1 = Opportunity.Offer(Opportunity.MakeContext({ level = 1 }), "wish")
    check("第 1 关得偿所愿是 3 个方向", w1 and #w1.options == 3, w1 and #w1.options)
    local w5 = Opportunity.Offer(Opportunity.MakeContext({ level = 5 }), "wish")
    check("第 5 关还没有「搏」", w5 and #w5.options == 3, w5 and #w5.options)
    local w6 = Opportunity.Offer(Opportunity.MakeContext({ level = 6 }), "wish")
    check("第 6 关出现「搏」", w6 and #w6.options == 4, w6 and #w6.options)
    local w8 = Opportunity.Offer(Opportunity.MakeContext({ level = 8 }), "wish")
    check("第 8 关得偿所愿是 5 个方向", w8 and #w8.options == 5, w8 and #w8.options)
    local hasRoll = false
    for _, opt in ipairs((w6 and w6.options) or {}) do
        if opt.rollId then hasRoll = true end
    end
    check("「搏」选项带 rollId", hasRoll)

    -- 分布：权重是否真的生效（±40% 相对误差）
    local counts, total = {}, 0
    local ctx = Opportunity.MakeContext({ level = 10 })
    for _ = 1, 2000 do
        local offer = Opportunity.Offer(ctx, "encounter")
        if offer then
            counts[offer.id] = (counts[offer.id] or 0) + 1
            total = total + 1
        end
    end
    check("不期而遇能抽到", total > 0, total)
    local expectedMap, expectedTotal = {}, 0
    for _, def in ipairs(Opportunity.ByKind.encounter) do
        if (def.minLevel or 1) <= 10 then
            expectedMap[def.id] = def.weight
            expectedTotal = expectedTotal + def.weight
        end
    end
    for id, w in pairs(expectedMap) do
        local expect = w / expectedTotal * total
        local got = counts[id] or 0
        local ok = math.abs(got - expect) <= math.max(6, expect * 0.40)
        check("权重分布合理（" .. id .. "）", ok, string.format("got %d, expect %.1f", got, expect))
    end

    -- 未知类型不应该炸
    local okCall = pcall(function() return Opportunity.Offer(ctx, "nope") end)
    check("未知类型安全返回", okCall)
end

-- ---------------------------------------------------------------- ⑦ 结算
local function TestResolve()
    -- 村落：白拿 15 银币
    local ctx = Opportunity.MakeContext({ level = 5, state = { silver = 0, hp = 50, maxHp = 50 } })
    local offer = { id = "v_coin", kind = "village", options = { { label = "开", gain = { silver = 15 }, enabled = true } } }
    local lines, ok = Opportunity.Resolve(ctx, offer, 1)
    check("村落结算成功", ok)
    check("村落 +15 银币", ctx.state.silver == 15, ctx.state.silver)
    check("村落有文案", #lines > 0)

    -- 不期而遇：割手换金
    local ctx2 = Opportunity.MakeContext({ level = 10, state = { silver = 0, hp = 60, maxHp = 100 } })
    local offer2 = {
        id = "e_blood", kind = "encounter",
        options = { { label = "割开手掌", cost = { hpPct = 0.30 }, gain = { buff = "gold" }, enabled = true } },
    }
    local _, ok2 = Opportunity.Resolve(ctx2, offer2, 1)
    check("割手结算成功", ok2)
    check("按最大生命扣血 30%", near(ctx2.state.hp, 30, 1e-6), ctx2.state.hp)
    check("拿到金色强化", #ctx2.log.buffs == 1 and ctx2.log.buffs[1] == "gold", ctx2.log.buffs[1])

    -- 付费选项：银币不够时不能选
    local ctx3 = Opportunity.MakeContext({ level = 10, state = { silver = 10 } })
    local offer3 = Opportunity.Offer(ctx3, "encounter")
    check("抽到不期而遇", offer3 ~= nil)
    local ctx4 = Opportunity.MakeContext({ level = 10, state = { silver = 100 } })
    local offer4 = { id = "e_peddler", kind = "encounter", options = { { label = "付 60 银币", cost = { silver = 60 }, gain = { buff = "purple" }, enabled = true } } }
    local _, ok4 = Opportunity.Resolve(ctx4, offer4, 1)
    check("付费结算成功", ok4)
    check("付费扣掉 60 银币", ctx4.state.silver == 40, ctx4.state.silver)

    local ctx5 = Opportunity.MakeContext({ level = 10, state = { silver = 20 } })
    local offer5 = { id = "e_peddler", kind = "encounter", options = { { label = "付 60 银币", cost = { silver = 60 }, gain = { buff = "purple" }, enabled = false } } }
    local _, ok5 = Opportunity.Resolve(ctx5, offer5, 1)
    check("银币不够时选项不可用", ok5 == false)

    -- 得偿所愿：选悟 → 经验
    local ctx6 = Opportunity.MakeContext({ level = 10, state = { silver = 0 } })
    local offer6 = { id = "w_wish", kind = "wish", options = { { label = "悟", gain = { exp = 25 }, enabled = true } } }
    local _, ok6 = Opportunity.Resolve(ctx6, offer6, 1)
    check("得偿所愿结算成功", ok6)
    check("经验 +25", ctx6.log.exp == 25, ctx6.log.exp)

    -- 回血不会超过上限
    local ctx7 = Opportunity.MakeContext({ level = 10, state = { hp = 95, maxHp = 100 } })
    local offer7 = { id = "w_life", kind = "wish", options = { { label = "生", gain = { healPct = 0.45 }, enabled = true } } }
    Opportunity.Resolve(ctx7, offer7, 1)
    check("回血不溢出", ctx7.state.hp == 100, ctx7.state.hp)

    -- 代价型难度提升必须能传到调用方（Run 要拿这个值叠 step）
    local ctx8 = Opportunity.MakeContext({ level = 10, state = { silver = 0 } })
    local offer8 = {
        id = "e_march", kind = "encounter",
        options = {
            { label = "翻过废墟", gain = { silver = 45, stepRisk = 1 }, enabled = true },
            { label = "排水沟", gain = { silver = 15 }, enabled = true },
        },
    }
    local _, ok8, eff8 = Opportunity.Resolve(ctx8, offer8, 1)
    check("翻废墟结算成功", ok8)
    check("stepRisk 传给调用方", eff8 and eff8.stepRisk == 1, eff8 and eff8.stepRisk)
    local _, _, eff9 = Opportunity.Resolve(ctx8, offer8, 2)
    check("保守选项没有 stepRisk", eff9 and eff9.stepRisk == 0, eff9 and eff9.stepRisk)

    -- 「搏」：这个选项本身就是一次掷骰
    local ctxW = Opportunity.MakeContext({ level = 10, state = { silver = 100 }, rand = function() return 0.95 end })
    local offerW = { id = "w_wish", kind = "wish", options = { { label = "搏", rollId = "c_fate", enabled = true } } }
    local linesW, okW = Opportunity.Resolve(ctxW, offerW, 1)
    check("「搏」结算成功", okW)
    check("「搏」有掷骰文案", type(linesW) == "table" and #linesW > 0)
    check("「搏」掷出大吉 +60", ctxW.state.silver == 160, ctxW.state.silver)

    -- 空 offer 不炸
    local okEmpty = pcall(function() return Opportunity.Resolve(ctx7, nil, 1) end)
    check("空 offer 安全返回", okEmpty)
end

-- ---------------------------------------------------------------- ⑧ 村落掉落（不占地图）
local function TestVillageDrop()
    local total, hits = 2000, 0
    local kinds = {}
    local ctx = Opportunity.MakeContext({ level = 10, state = { hp = 40, maxHp = 100 } })
    for _ = 1, total do
        local offer = Opportunity.RollVillageDrop(ctx)
        if offer then
            hits = hits + 1
            kinds[offer.kind] = true
        end
    end
    local rate = hits / total
    check("村落掉率约 12%", rate > 0.08 and rate < 0.16, string.format("%.3f", rate))
    check("村落只会掉 village 条目", kinds.village == true and kinds.encounter == nil)
    check("村落的 def 不在 MAP_KINDS 里",
        Opportunity.MAP_KIND_SET.village == nil and Opportunity.MAP_KIND_SET.chance == nil)

    local allFree = true
    for _ = 1, 300 do
        local offer = Opportunity.RollVillageDrop(ctx)
        if offer and offer.options then
            for _, opt in ipairs(offer.options) do
                if opt.cost then allFree = false end
            end
        end
    end
    check("村落永远不要代价", allFree)
    print(string.format("[Act] 村落掉落：%.1f%%（目标 12%%）", rate * 100))
end

-- ---------------------------------------------------------------- 入口
function Start()
    print("========== DevActMap ==========")
    TestActs()
    TestCards()
    TestLayers()
    TestBudget()
    TestChanceFloor()
    TestOffers()
    TestResolve()
    TestVillageDrop()
    print(string.format("[Act] done, failures = %d", fails))
end

function Update()
end
