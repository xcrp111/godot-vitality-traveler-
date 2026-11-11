# 层间地图 / 局内地图 · 本轮交付说明（README）

> 时间：2026-11-09 ~ 2026-11-11　分支：`dev1(chen)`　作者：chen
> 设计说明见同目录 [`ACT_MAP.md`](ACT_MAP.md)；待办见 [`ACT_MAP_TODO.md`](ACT_MAP_TODO.md)。
> **本轮的代码还没接进真流程**（没改 `Run.lua` / `Screens.lua`），只在 `scripts/` 里新增两个模块 + `dev/` 预览与回归。

---

## 1. 这一轮做了什么

| 提交 | 内容 |
|---|---|
| `8fc0aab` | 层间地图（幕结构、层卡三选一）+ 局内节点图 + 机遇系统 P0 |
| `bfd1ec8` | `DevActMap` 加分组进度打印，引擎里定位卡点用 |
| `4b1e713` | `DevActMapView`：层卡 / 节点图的可视化预览（截图用） |
| `7b94235` | 卡片上的 event 格改叫「机遇占位」，和右侧「机遇 N」数字对齐 |
| `840c38e` | 重裁字体子集（缺 132 字形 → 0）+ 层卡风险徽标提权 |
| `dc86218` | 归一阶梯补 `mixed→elite`，第 20 关不再三张卡全「轻松」 |
| `64824fb` | `DevActMap` 补「三张卡风险档不全同名」回归护栏 + 量出全「常规」占比 |

### 1.1 新增文件

```
scripts/ActMap.lua       幕结构 / 层卡三选一 / 局内节点图生成
scripts/Opportunity.lua  机遇池（2 个地图节点 + 村落掉落 + 命运「搏」）
dev/DevActMap.lua        纯逻辑回归（1600+ 断言，failures 必须 = 0）
dev/DevActMapView.lua    层卡 / 节点图可视化预览（截图 & 点卡片切换）
docs/ACT_MAP.md          设计说明 + 三步接入指引
docs/ACT_MAP_README.md   本文件
docs/ACT_MAP_TODO.md     待办 / 周五排板清单
```

### 1.2 三个模块在做什么（一句话版）

- **幕（Act）**：每 5 关一幕，幕末给奖励。`ActMap.ActOfLevel / ActProgress / IsActEnd / ActEndReward`
- **层卡三选一**：进关前给 3 张卡（模板 × 词条），每张卡带一个 `risk`（相对目标强度的偏移）和一个「全清期望银币」预估，玩家按「轻松 / 常规 / 吃紧 / 险恶」选
- **局内节点图**：4×4 格子，金框标机遇房 / 死胡同，`GenerateLayer` 出 `grid + edges`
- **机遇系统**：把原来写死的事件房换成机遇池抽取，含「得偿所愿 · 搏」这种带代价的选项，以及战斗房清完 12% 概率的村落掉落

---

## 2. 怎么验

### 2.1 纯逻辑回归（0.6 秒，先跑这个）

```bat
F:\_vt_tools\py\python.exe F:\_vt_tools\run_lua.py F:\godot-vitality-traveler\life-walker DevActMap
```

要求：最后一行 `[Act] done, failures = 0`。

当前的量（2026-11-11）：

```
[Act] 层卡：600 张，其中低风险 410 张（68%），最大 |risk|=0.532，银币区间 192~689
[Act] 风险档：22/200 次抽卡三张同名，其中三张全「常规」22 次
[Act] done, failures = 0
```

### 2.2 引擎内（真 Lua，慢但真）

```bat
cd F:\godot-vitality-traveler\life-walker
.cli\UrhoXRuntime.exe dev\DevActMap.lua -tapcode_dir=. -tool_mode -graphicsheadless
```

print 落在 `.cli\logs\lua\lua-<时间>.log`（每行一个 JSON，正文在 `m` 字段）。

### 2.3 看效果（截图）

```powershell
cd "F:\godot-vitality-traveler\life-walker"
$p = Start-Process -FilePath ".\.cli\UrhoXRuntime.exe" `
  -ArgumentList 'dev\DevActMapView.lua','-tapcode_dir=.','-tool_mode',
                '-screenshot=F:\_vt_notes\shots\view.png','-screenshot-frame=100','-x','1280','-y','720' `
  -NoNewWindow -PassThru -RedirectStandardOutput "$env:TEMP\vt_o.txt" -RedirectStandardError "$env:TEMP\vt_e.txt"
$p.WaitForExit(90000) | Out-Null
```

- **必须**用 `Start-Process` + 重定向，直接 `&` 调用有概率秒退成一张全黑图
- 成功判据：中心像素 `RGB(22,17,30)`
- 换关卡：设环境变量 `ACTMAP_LEVEL=10` 再跑（默认 1）

### 2.4 改过中文文案之后

字体是**子集**（`assets/Fonts/MiSans-Regular.ttf`），子集里没有的字在界面上是**空白而不是方框**，肉眼极易漏掉。

```powershell
$env:PYTHONPATH="F:\_vt_tools\pylibs"
cd F:\godot-vitality-traveler\life-walker
& F:\_vt_tools\py\python.exe dev\make_font_subset.py
& F:\_vt_tools\py\python.exe dev\check_font.py   # 要「OK 字体覆盖完整」，退出码 0
```

扫描范围已含 `scripts/` 和 `dev/`（10-10 之前只扫 `scripts/`，导致 dev 预览里 132 个字形从来没进过子集）。
本机没有 node / npm，`.js` 版本跑不了，用对应的 `.py`。

---

## 3. 当前状态

### 3.1 第 20 关（截图 `shots/view20b.png`）

三张卡：

| 卡 | 模板 | 词条 | 风险档 | 全清期望 |
|---|---|---|---|---|
| 双精英 | 双精英 | 荒径 | 轻松 -0.22 | 379 银币 |
| 事件旅路 | 事件旅路 | 病巢密布 | 吃紧 +0.15 | 639 银币 |
| 轻战起步 | 轻战起步 | 迷雾 | 常规 -0.18 | 526 银币 |

绿 / 金 / 蓝灰三种徽标，一眼能分轻重。

### 3.2 还没解决的（已知，不是 bug）

**「三张卡分不出轻重」只是部分解决。** 绝对阈值下：

- 200 次抽卡里有 **22 次（11%）三张卡的风险档完全相同**，且全部是「常规」（第 2/3/4 关最常见）
- 原因是「常规」这一档太宽（`-0.20 ~ 0.10`，横跨 0.30），低级关卡 risk 都聚在 0 附近
- 第 10 关是另一种形态：两张「轻松」一模一样（-0.22 / -0.30）

**语义已定（2026-11-11）：「轻松 / 常规 / 吃紧 / 险恶」只描述房间战斗强度，不承诺收益高低。** 所以「轻松但给得少」是正常的；「更难还给得更少」（支配卡）才是 bug，它的修法见 `ACT_MAP_TODO.md` P0-1 的 M1 + M2。

更值得注意的是**标签和收益不对齐**。银币来自「战斗房数量 × 房间类型期望 × 银币系数 + 固定加成」，而 `risk` 只看「战斗房平均强度」，两个维度彼此独立，所以标签和收益本来就不相关——这本身不算 bug（「吃紧」那张靠「病巢密布」词条给到 599，是词条在做它该做的事）。

真正是 bug 的是**支配卡**：一张卡**既更难、又给得更少**（200 次抽卡里 55 次，27.5%，59 对）。典型一对：第 20 关 `detour` 比 `journey` 更难（-0.17 vs -0.18）却少给 47 银币。这种卡在三选一里永远没有被选的理由。

（附一条容易看错的：第 10 关两张「轻松」**不是**支配关系——-0.30 那张更简单也更穷，-0.22 那张更难也更富，这是正常的风险回报。它的问题只是**标签同名**。）

**已修（2026-11-11，M1 + M2）**：`ActMap.RepairPareto` 抽完三张后把支配关系消掉（先拆强度撞车，再补银币，补不起就降一级），`ActMap.AssignSilverTiers` 给三张卡打相对收益档（★☆☆ 偏少 / ★★☆ 一般 / ★★★ 偏多）。实测：支配对 59 → **0**，银币总量只涨 **+1.2%**（单张最大 +42%）。

### 3.3 视觉上的小毛病（不阻塞，想改随时改）

- 「常规」的蓝灰徽标和卡边框几乎同一灰度，读起来像禁用态——三档里视觉最弱
- 「全清期望」的数字和标签同色同重，数字本身读不出来
- 卡名下面 `× 荒径` 这一行偏暗
- 右下说明「什么都没有。地图保持模板原样。」容易被读成 bug，实际意思是「这张卡的词条没有额外效果」
- 左下角两行小字（节点图图例 / DevActMapView 署名）贴太近，第二行几乎顶到第一行下缘

---

## 4. 接进真流程（三步，还没做）

完整代码见 [`ACT_MAP.md`](ACT_MAP.md) 第 5 节，这里只给顺序：

1. `Run.OpenEvent` → `Run.OpenOpportunity`，`Run.EnterRoom` 的分发改走机遇系统
2. 进关前弹层卡三选一（`ActMap.RollCards(level)`），选中的卡决定这一关的 `grid` / 词条 / 步数风险加成
3. `Screens.DrawMap` 换成画节点图（4×4 + 金框），并接机遇界面的绘制

> 会碰 `ui` 分支的地盘（`Run.lua` 三处 + `Screens.DrawMap`），**时机等排板后再定**。

---

## 5. 红线 / 约定

- 只提交 `dev1(chen)`，永不碰 `master`
- 提交前 `DevActMap` 必须 `failures = 0`
- 不碰 `life-walker/Play.bat`（别人的未提交改动）
- 改中文文案后必须重裁字体子集
