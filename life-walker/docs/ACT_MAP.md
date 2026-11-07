# 层间地图 / 局内地图（P0 设计与实现说明）

> 对应代码：`scripts/ActMap.lua`、`scripts/Opportunity.lua`、`dev/DevActMap.lua`
> 状态：纯逻辑模块已落地并通过回归（`dev/DevActMap.lua` 1600+ 条断言，failures = 0）
> 还没接进 Run / Screens —— 接入步骤见最后一节，一共三步。

---

## 0. 这一版做了什么改动

第一版把机遇房分成了四种（村 / 遇 / 愿 / 机）。四种摆在 4×4 的地图里太重：图标要认四个、规则要记四套，还把「选择」稀释了。这一版压成**两种**，但不是简单删掉，而是各给了去处：

| 原来 | 现在 | 为什么不丢玩法 |
|---|---|---|
| 遗弃村落（白拿、随机、小） | **清完战斗房后 12% 概率「路过」** | 惊喜感靠「走着走着掉出来」给，比摆在地图上更意外 |
| 不期而遇（选、有代价） | 保留为地图节点 | 决策感的核心，必须让玩家看得见 |
| 得偿所愿（选、无风险） | 保留为地图节点 | 保底感的来源，也顺手承载了「赌」 |
| 命运岔口（纯赌） | **得偿所愿的第五个方向「搏」** | 想赌的人自己按，不想赌的人看不见它 |

顺带砍掉一处真冗余：模板里的 `event` 格（`Run.OpenEvent` 那三个硬编码事件：骰子赌局 / 藏宝洞 / 篝火陌生人）和机遇房功能完全重叠——赌 = 命运、藏宝 = 得偿所愿、篝火 = 不期而遇。现在 `GenerateLayer` 把它们**就地改造成机遇房**，不再额外占格子。

结果：**每层固定 1 个机遇房**（`ActMap.SPECIAL_ROOM_COUNT = 1`，改成 2 就回到双机遇房），地图上的非战斗房是「商店 1~2 + 机遇 1 + 起点 + Boss」，4×4 的格子终于不再拥挤。

---

## 1. 三层结构

| 层 | 单位 | 玩家在这里做的决定 | 代码 |
|---|---|---|---|
| 幕 Act | 5 关 | 看进度、拿幕末奖励 | `ActMap.ACTS` / `ActMap.ActOfLevel` |
| 层卡 Card | 1 关 / 1 层 | 三选一：这次走什么样的地图 | `ActMap.RollCards` |
| 局内节点图 | 一间房 | 走哪条路、绕不绕路、进不进机遇房 | `ActMap.GenerateLayer` |

**关键设计判断**：`Config.MapTemplates` 里那 7 张手工模板本来就是「地图变体」，现在被 `Config.PickMainMap` 随机抽掉了，玩家没有选择权。层间地图要做的不是新造一套进度系统，而是把「随机抽一张」变成「看得见、选得动的一张」。所以这一版没有新货币、没有新经验层，也不碰「步数解锁关卡」这条现实挂钩。

**为什么是「层卡三选一」而不是明日方舟那种树状节点图**：设计画布 1280×720、手机竖屏、NanoVG 立即模式，现有房间格子已经 120~140px，20 个带标签的分叉节点会挤成一团。三张大卡信息密度相同、点击目标够大、还能塞下完整收益预告。

---

## 2. 两个节点，两种情绪

| 节点 | 玩家有选择权 | 有代价 | 结果可预期 | 情绪目标 |
|---|---|---|---|---|
| 不期而遇 `encounter` | 有（2 选 1） | 有 | 半可知 | **决策** |
| 得偿所愿 `wish` | 有（5 个方向） | 无（「搏」除外） | 品质受限 | **保底 / 小赌** |

得偿所愿的五个方向，按关卡逐步开放（新手期不给赌）：

| 方向 | 效果 | 出现条件 |
|---|---|---|
| 生 | 恢复 45% 生命 + 5 银币 | 第 1 关起 |
| 力 | 一次保底蓝色的三选一 | 第 1 关起 |
| 悟 | +25 可分配经验 | 第 1 关起 |
| 搏 | 掷一次命运牌桌（期望 ≈ 20 银币） | 第 6 关起 |
| 财 | +35 银币 | 第 8 关起 |

**只给「方向」不给「具体物品」**——所以永远不会出现「抽到一个用不上的金色强化」这种挫败感，这正是方舟当初这么设计的原因。

---

## 3. 数值：先立汇率，再定额度

全部从 `Config.lua` 的现有价格反推，不拍脑袋：

| 换算 | 依据 | 汇率 |
|---|---|---|
| 1% 最大生命 ↔ 银币 | 小药 12 银币 = 33%，大药 24 = 66% | **0.36 银币 / 1%** |
| 1 个强化品质档 | 白 24 / 蓝 40 / 紫 64 / 金 115 | **≈ 22 银币** |
| 局外金币 ↔ 局外经验 | 12000 步 = 533 金币 + 533 经验 | **1 : 1，且不与银币互换** |

### 3.1 预算上限（`Opportunity.CAP`）

| 类型 | 银币 | 强化次数 | 局外金币 | 局外经验 | 回血 |
|---|---|---|---|---|---|
| 村落 `village`（掉落） | 20 | 0 | 20 | 10 | 25% |
| 不期而遇 `encounter` | 50 | 1 | 25 | 15 | 45% |
| 得偿所愿 `wish` | 40 | 1 | 30 | 30 | 50% |
| 命运牌桌 `chance` | 60 | 1 | 30 | 20 | 35% |

代价上限 `CAP_COST`：银币 80 / 生命 35% / 道具 1 / 难度 +1 档。改数值只改这两张表，`dev/DevActMap.lua` 会逐条断言。

**局外资源的硬上限**：任何单次机遇最多给 60 金币或 40 经验。理由是 12000 步的完整日收益是 533，单次超过 11% 就能把「走步」这个核心循环架空。所以局外资源只出现在村落掉落和幕末，不进普通机遇房。

### 3.2 每类房间的期望银币（代码里从 `RoomWaves` + `SilverDrop` 反推）

| 房间 | 轻战 | 标战 | 混战 | 精英 | 双精 | Boss |
|---|---|---|---|---|---|---|
| 期望银币 | 9 | 12 | 46 | 43 | 75 | 6 |

一个标准战斗房 = 12 银币 + 1 次三选一 ≈ 1 个预算单位。一关全清大约 192~693 银币（层卡实测区间），商店一个紫要 64 银币——所以机遇给 15 / 25 / 35 / 60 银币，正好是「半个紫」到一个紫多一点。

### 3.3 命运牌桌（得偿所愿 · 搏）

| 档位 | 概率 | 结果 |
|---|---|---|
| 大凶 | 10% | −25 银币（不够就扣生命） |
| 小凶 | 20% | −10 银币 |
| 平静 | 25% | +10 银币 |
| 小吉 | 25% | +25 银币 |
| 大吉 | 20% | +60 银币，30% 额外送一次紫保底 |

期望 **+16.25 银币**，加上紫保底期望约 **20**。比「财」的稳定 35 低——这是故意的：**赌买的是方差和爽点，不是收益**。

两条地板规则：

- **大凶地板**：生命 ≤ 25% 时大凶自动降级为小凶
- **扣血上限**：银币不够赔时改成扣血，但最多扣 15% 最大生命

健康游戏里「赌一把直接输掉整局」是劝退级体验，这两条不能省。

### 3.4 层词条（`ActMap.MODS`）

| 词条 | 地图影响 | 强度偏移 | 银币 |
|---|---|---|---|
| 荒径 `plain` | 无 | 0 | ×1.00 |
| 商路通畅 `market` | 商店 +1、战斗房 −1 | −0.15 | ×0.90 |
| 病巢密布 `nest` | 精英 +1，强化品质权重上移 | +0.35 | ×1.25 |
| 浅滩缓行 `shallow` | 战斗房 −2，房间倍率按低 2 档 | −0.30 | ×0.80 |
| 疫风过境 `plague` | 清 Boss 额外 +40 银币 | +0.20 | ×1.00 |
| 迷雾 `fog` | 隐藏精英/Boss，但必有 1 个不期而遇 | 0 | ×1.00 |

硬约束：三张卡里**至少一张强度偏移 ≤ 0**，否则玩家没得选，选择等于不存在。

---

## 4. 局内节点图（元气骑士的结构，不改渲染）

借它的**分支 + 死胡同**，不借它的走廊（房间是整屏、镜头不动、包里没有地形美术，走廊成本是连线的 10 倍、收益是 0）。

- 每层 **1 个**机遇房，只可能是「不期而遇」或「得偿所愿」（权重 58 : 42）
- 模板里的 `event` 格就地改造成机遇房，地图上不再有 `?` 事件房
- **存在一条不经过任何精英房就能到 Boss 的路线**（这条 `Config.CheckMap` 没查，本模块补上了）
- 约有 45% 的层会出现一个「死胡同」机遇房：只能从左边进、没有出口

**免费平衡杠杆**：绕路 = 房间数变多 = `step` 变大 = 后面所有房间更硬（`Config.RoomMul(level, step)`，step 锁 9）。所以「多走一间房拿个机遇，后面每个房间都强一点」这个权衡，不需要任何新数值就成立了。

---

## 5. 接入步骤（三步）

### 第一步：把 `Run.OpenEvent` 换成机遇系统

```lua
-- Run.lua 顶部
local Opportunity = require "Opportunity"

-- 新增（放在 Run.OpenEvent 附近）
function Run.OpenOpportunity(kind)
    ReleaseInput()
    local run = S.run
    local p = run.player
    local ctx = Opportunity.MakeContext({
        level = run.level,
        state = {
            silver = run.silver, hp = p.hp, maxHp = p.maxHp,
            shield = p.shield, maxShield = p.maxShield, items = #run.items,
        },
        hooks = {
            grantBuff = function(rarity) return Run.GrantRandomBuff(p, rarity) end,
            addGold   = function(n) S.data.gold = (S.data.gold or 0) + n; Save.Write(S.data) end,
            addExp    = function(n) S.data.exp  = (S.data.exp  or 0) + n; Save.Write(S.data) end,
            addItem   = function(n) for _ = 1, (n or 1) do Run.AddItem("random") end end,
            useItem   = function(n) return Run.ConsumeItem(n) end,   -- 需要新写：从 run.items 里扣
            reveal    = function() run.revealAll = true end,         -- DrawMap 读到就画出所有房间类型
            reroll    = function(n) run.guildRerolls = (run.guildRerolls or 0) + n end,
        },
    })
    run.opportunity = { ctx = ctx, offer = Opportunity.Offer(ctx, kind or "encounter"), kind = kind }
    S.screen = "opportunity"
end

function Run.ChooseOpportunity(index)
    local o = S.run and S.run.opportunity
    if not o or o.result or not o.offer then return end
    local lines, ok, effects = Opportunity.Resolve(o.ctx, o.offer, index)
    -- ctx.state 是独立副本，必须手动同步回去
    S.run.silver = o.ctx.state.silver
    S.run.player.hp = o.ctx.state.hp
    S.run.player.shield = o.ctx.state.shield
    if effects.stepRisk > 0 then
        S.run.stepRiskBonus = (S.run.stepRiskBonus or 0) + effects.stepRisk
    end
    o.result = table.concat(lines, "  ")
end
```

`Run.EnterRoom` 里的分发改成：

```lua
    elseif roomType == "event" or ActMap.SPECIAL_KINDS[roomType] then
        Run.OpenOpportunity(roomType == "event" and "encounter" or roomType)
        S.screen = "opportunity"
```

代价型难度提升接进战斗（Run.lua:520 那一行）：

```lua
        S.combat = Combat.Start(run, roomType, math.min(9, run.step + (run.stepRiskBonus or 0)))
```

### 第一步补：战斗房清完的村落掉落

在 `Run.OnCombatCleared(roomType)` 末尾加：

```lua
    local offer = Opportunity.RollVillageDrop(run.opportunityCtx or BuildOpportunityCtx())
    if offer then
        run.opportunity = { ctx = ctx, offer = offer, kind = "village", drop = true }
        S.screen = "opportunity"
    end
```

12% 概率，白拿一份，不占地图格子。

### 第二步：层卡三选一

`Run.Start` / `Run.NextEndlessLayer` 里把 `GenMainMap(level)` 换成：

```lua
    run.cards = ActMap.RollCards(level, { needShop = run.lastLayerShop ~= true })
    S.screen = "layerpick"          -- 新界面：三张卡，选完再 return
```

选完把 `run.map = card.grid`、`run.card = card`，并且把 `card.stepPenalty` 折进 `run.step`（浅滩模式 = 房间倍率按低 2 档算）。

`ActMap.GenerateLayer(level, card)` 用来产出带边表的节点图：`layer.edges` 直接替掉 `Run.CanMove` 里的坐标推断。

### 第三步：渲染

- `Screens.DrawMap`：房间图标用 `Opportunity.KINDS[kind].icon`（现在只有「遇」「愿」两种），连线改读 `run.edges`；`run.revealAll` 时把隐藏房间也画出来
- 新增 `Screens.DrawLayerPick`：三张卡，直接抄 `DrawReward` 的卡片布局，每张写 `模板名 × 词条名 / 精英数 / 商店数 / 期望银币 / 难度标签`
- 新增 `Screens.DrawOpportunity`：得偿所愿是 5 个方向的卡片（手机上一行 3 + 一行 2），不期而遇是 2 张卡

---

## 6. 跑测试

和别的 dev 脚本一样（需要 `.cli/UrhoXRuntime.exe`，仓库里没有）：

```bat
cd life-walker\.cli
UrhoXRuntime.exe ..\dev\DevActMap.lua "-tapcode_dir=.." -tool_mode -graphicsheadless
```

没有运行时也能跑：本机有 Python + `lupa`（自带 Lua 5.4）时，用 `_vt_tools/run_lua.py` 直接执行同样逻辑，0.6 秒跑完全部断言。开发时这条快得多。

---

## 7. 已知取舍与待定

- **每层只有 1 个机遇房**是刻意的：`ActMap.SPECIAL_ROOM_COUNT = 1`，改成 2 就回到双机遇房版本（其余代码不用动）。
- **强模板在高关拉不到目标强度**：`Config.NormalizeMap` 的归一阶梯只往上到混战为止，所以第 15 关以后「轻战起步」这类模板的 `risk` 会到 −0.3 左右。这是故意保留的（给玩家一条轻松路），断言只卡「不能三张都偏难」。
- **幕在主线里是只读的**：关卡解锁已经被「步数 + 通关上一关」双条件锁住，幕地图不能有解锁权。
- **`event` 房在 P0 里只在节点图层被改造**，`Config.CheckMap` 仍然要求模板里有 `event` 格——因为 `RollCards` 校验的是改造前的 `card.grid`。等 Run/Screens 接完，可以把 `CheckMap` 的 `opts.event` 关掉。
- **需要 `Run` 侧补三个小函数**：`ConsumeItem`、`revealAll` 的绘制、`BuildOpportunityCtx`（复用 `OpenOpportunity` 里那段 ctx 构造）。
- **美术**：P0 全部用文字徽标（遇 / 愿），等 `ART_SLOTS.md` 的槽位有素材再换。
- **无尽模式的层卡**还没做「已走路径回顾」，等 P1。
