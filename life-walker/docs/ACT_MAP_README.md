# 层间地图 / 局内地图 / 机遇系统 · 交付说明（2026-11-27 更新）

> 分支：`dev1(chen)`　作者：chen　最近一轮累计：2026-11-09 ~ 2026-11-27
> 配套文件：设计说明 [`ACT_MAP.md`](ACT_MAP.md)、待办 [`ACT_MAP_TODO.md`](ACT_MAP_TODO.md)
> **代码仍未接进真流程**——没改 `Run.lua` / `Screens.lua`，全部在 `scripts/` 新增模块 + `dev/` 回归与预览里。

---

## 1. 这一轮交付了什么

| 提交 | 内容 |
|---|---|
| `8fc0aab` | 层间地图（幕结构、层卡三选一）+ 局内节点图 + 机遇系统 P0 |
| `bfd1ec8` | `DevActMap` 加分组进度打印 |
| `4b1e713` | `DevActMapView`：层卡 / 节点图可视化预览 |
| `7b94235` | 卡片上的 event 格改叫「机遇占位」 |
| `840c38e` | 重裁字体子集（缺 132 字形 → 0）+ 层卡风险徽标提权 |
| `dc86218` | 归一阶梯补 `mixed→elite`，第 20 关不再三张全「轻松」 |
| `64824fb` | `DevActMap` 补「三张卡风险档不全同名」回归护栏 |
| `833e375` | **M1 帕累托消解** + **M2 收益分档**（支配卡 59 → 0，银币总量 +1.2%） |
| `5b946e0` | **B1 同档拆分**：三张卡同档 22/200 → 0，并给相对档名打小圆点 |
| `0e2f68d` | 机遇池 16 → **22 条 / 35 个选项**，扣银币成为真正的代价 |
| `2e1a32e` | 底栏星级 11→13px 并提亮；`plain` 词条文案改清楚 |
| `43bfdd9` | 徽标下移 4px、纹章 40→36、副标题提亮、说明区右移加宽 |
| `0465641` / `2422673` | 无尽等效关卡诊断（含逐关最低 risk，只打印不断言） |
| `2273123` / `bd3b991` | 文档：TODO 与设计说明对齐代码 |

### 文件清单

```
scripts/ActMap.lua       幕 / 层卡三选一 / 局内节点图生成
scripts/Opportunity.lua  机遇池（2 个地图节点 + 村落掉落 + 命运「搏」）
dev/DevActMap.lua        纯逻辑回归（1600+ 断言，failures 必须 = 0）
dev/DevActMapView.lua    层卡 / 节点图可视化预览（截图用）
docs/ACT_MAP.md          设计说明 + 三步接入指引
docs/ACT_MAP_TODO.md     待办 / 拍板清单（P0/P1/P2）
docs/ACT_MAP_README.md   本文件
```

---

## 2. 三个模块在做什么

- **幕（Act）**：每 5 关一幕，幕末给奖励。`ActMap.ActOfLevel / ActProgress / IsActEnd / ActEndReward`
- **层卡三选一**：进关前给 3 张卡（模板 × 词条），每张卡带 `risk`（相对目标强度的偏移）与「全清期望银币」，并按风险分「轻松 / 常规 / 吃紧 / 险恶」四档
- **局内节点图**：4×4 格子，金框标机遇房 / 死胡同，`GenerateLayer` 出 `grid + edges`
- **机遇系统**：事件房换成机遇池抽取，含「得偿所愿 · 搏」这类带代价的选项，以及战斗房清完 12% 概率的村落掉落

### 层卡生成时做的三次「整体修复」（顺序不能乱）

`ActMap.RollCards` 抽完三张后依次跑：

1. `RepairPareto` —— 消掉「既更难、又给得更少」的支配卡（先拆强度撞车，再补银币，补不起就降一级）
2. `AssignSilverTiers` —— 按三张卡的相对排名打 1~3 星（偏少 / 一般 / 偏多）
3. `BreakLabelCollapse` —— 三张卡落在同一强度档时，把组内最低降一档、最高升一档

> **注意**：B1 会让档名「漂移」（同一张卡在不同三张里可能叫不同名字），所以**卡面上的 `risk` 数字不能省**——它是玩家看到绝对强度的唯一渠道。

---

## 3. 怎么验

### 3.1 纯逻辑回归（0.6 秒，先跑这个）

```bat
F:\_vt_tools\py\python.exe F:\_vt_tools\run_lua.py F:\godot-vitality-traveler\life-walker DevActMap
```

要求最后一行是 `[Act] done, failures = 0`。当前输出：

```
[Act] 层卡：600 张，其中低风险 407 张（68%），最大 |risk|=0.532，银币区间 192~689
[Act] 风险档：0/200 次抽卡三张同名；22 次用到了组内相对档名
[Act] 帕累托：0/200 次抽卡存在被支配的卡
[Act] 收益修复（M1）：54 张卡被补过银币；总量 222619 -> 225228（+1.2%），单张最大 +42%
[Act] 机遇池：22 条，35 个选项
[Act] 房间期望银币：light=9 standard=12 mixed=47 elite=44 double=75 boss=6
[Act] 无尽等效关卡（21–60，各 3 次）：risk 区间 -1.00 ~ +0.17；三张同档 0/42；
      档位分布 轻松=71 常规=48 吃紧=7 险恶=0
```

### 3.2 引擎内

```bat
cd F:\godot-vitality-traveler\life-walker
.cli\UrhoXRuntime.exe dev\DevActMap.lua -tapcode_dir=. -tool_mode -graphicsheadless
```

print 落在 `.cli\logs\lua\lua-<时间>.log`（每行一个 JSON，正文在 `m` 字段）。

### 3.3 看效果（截图）

```powershell
cd "F:\godot-vitality-traveler\life-walker"
$p = Start-Process -FilePath ".\.cli\UrhoXRuntime.exe" `
  -ArgumentList 'dev\DevActMapView.lua','-tapcode_dir=.','-tool_mode',
                '-screenshot=F:\_vt_notes\shots\v.png','-screenshot-frame=100','-x','1280','-y','720' `
  -NoNewWindow -PassThru -RedirectStandardOutput "$env:TEMP\vt_o.txt" -RedirectStandardError "$env:TEMP\vt_e.txt"
$p.WaitForExit(90000) | Out-Null
```

- **必须**用 `Start-Process` + 重定向，直接 `&` 调用有概率秒退成一张全黑图
- 成功判据：中心像素 `RGB(22,17,30)`
- 换关卡：设 `ACTMAP_LEVEL=1/12/20`；强制种子：`ACTMAP_SEED=<n>`；只想看哪些关卡会出「相对档」：`ACTMAP_SCAN=1`

### 3.4 改过中文之后（**注释也算**）

```powershell
$env:PYTHONPATH="F:\_vt_tools\pylibs"
cd F:\godot-vitality-traveler\life-walker
& F:\_vt_tools\py\python.exe dev\make_font_subset.py
& F:\_vt_tools\py\python.exe dev\check_font.py    # 要「OK 字体覆盖完整」，退出码 0
```

字体是**子集**，缺字在界面上是**空白而不是方框**，肉眼极易漏。本机没有 node / npm，用 `.py` 版本。

---

## 4. 当前状态

- **层卡**：200 次抽卡里，三张同档 0 次、被支配卡 0 次；银币区间 192~689
- **机遇池**：22 条 / 35 个选项，含 5 条「扣银币」型不期而遇 + 2 条村落 + 1 张「押钱袋」牌桌
- **视觉**：11-20 那份六条清单已改掉四条半（星级 13px、词条文案、徽标压纹章、副标题对比度、说明区间距），**只剩「画布最右侧一小片空」**，收益低未动
- **无尽模式若要接层卡**：实测会退化成以「轻松」为主（见下）

### 无尽层卡的实测结论（11-25/26）

| 指标 | 数值 |
|---|---|
| risk 区间（第 21–60 关） | **−1.00 ~ +0.17** |
| 三张卡同档 | 0 / 42（B1 仍有效） |
| 档位分布（126 张卡） | 轻松 71（56%）／常规 48／**吃紧 7（5.5%）**／**险恶 0** |

根因：`MapTargetCost(60) = 2.95` 已贴着模板上限（双精英 3.0），归一阶梯几乎没有往上走的空间。

两条路（**未选，需拍板**）：

1. 给无尽单独的目标曲线，例如 `1.15 + 0.03 × min(level, 30)`，30 关后封顶
2. 承认高层卡只是「选路线」，把难度标签换成别的表达

对照页（给会上看）：`F:\_vt_notes\无尽层卡-对照页.html`，截图 `F:\_vt_notes\shots\wuceng-duizhao.png`

---

## 5. 还没做的两件事（都要拍板）

1. **接进真流程**：`Run.lua` 三处 + `Screens.DrawMap`，会碰 `ui` 分支的地盘——用户说等 `ui` 合并完
2. **「每日一卦」彩蛋**：文案样本已写 6 条（`F:\_vt_notes\每日一卦-文案样本.md`），三条硬规则是——不断言未来、不涉及具体人、零数值产出。等团队会上定

---

## 6. 踩过的坑（留给接手的人）

- **改中文（含注释）必须重裁字体子集**，否则界面上是空白；`check_font` 会拦，别跳过
- **截图直接用 `&` 调用会全黑**，必须 `Start-Process` + 重定向
- **文档会跟代码漂**：`ACT_MAP.md` 第 7 节曾写着"归一阶梯只到混战"，早已过期——对着代码读文档，别对着文档读代码
- **别拿单一数字当结论**：层卡的风险档曾用绝对阈值，结果三张卡全叫「轻松」；后来才发现问题在"归一阶梯够不到目标"，不在标签

---

## 7. 红线

- 只提交 `dev1(chen)`，永不碰 `master`
- 提交前 `DevActMap` 必须 `failures = 0`；改中文则 `check_font` 必须 exit 0
- 不碰 `life-walker/Play.bat`（别人的未提交改动）
- 改数值前先跑一次诊断打印，别凭印象改
