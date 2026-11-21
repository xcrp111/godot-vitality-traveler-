# 更新日志 · 生命行者（life-walker）

> 本文件随每次同步生成，记录 **`life-walker/`** 目录的变更。
> 目标分支：`dev2(dong)`

---

## 2026-11-21 · 联机落地：公会服务端（新）+ 农场存档分槽（加固）

> 依据 TapTap 制造周报 2026/3/16–3/22 的「存档架构心法」：按域切槽 / 大集合分片（单条 ~13KB）/ 脏标记批量写 / 数值资源独立 / 单槽容错。

### 新增：公会联机（服务端权威）

| 文件 | 职责 |
|---|---|
| `scripts/GuildStore.lua` | 双端共用纯逻辑：成员/申请/贡献/等级/团本血量池，以及 `ToSlots/FromSlots` 分槽 |
| `scripts/network/GuildShared.lua` | 11 个事件名 + 6 个存档槽 key + 编解码 + 单槽字节上限 |
| `scripts/network/GuildServer.lua` | 服务端权威：create/sync/apply/approve/reject/leave/donate/raid/levelup/search |
| `scripts/network/GuildClient.lua` | 客户端：同步/操作/离线降级/血量池快照 |

**槽位设计**：`guild_meta`（名称/等级/经验/会长/分片数）· `guild_members_<i>`（每片 ≤40 人）· `guild_raid`（血量池数值）· `guild_log`（环形 30 条）· `guild_applies` · `guild_member_info`（玩家→公会，存在玩家自己 uid 下）。
写盘顺序：成员/团本/日志/申请先写，**meta 最后写**（meta 是"这份存档有效"的指针）。

**接入**：`server_main.lua` 与 `main.lua` 的服务端分支启动 `GuildServer`；客户端在 `ClientConnected` 事件里初始化 `GuildClient` 并同步。
**UI**：公会主页新增联机状态（`● 已连服务器 / ○ 离线`）+「同步联机公会」「创建联机公会」；团本页在已连服时优先显示**服务端权威血量池**（否则回退本地 + 排行榜快照）。

### 加固：农场存档按域拆槽

- `FarmStore.ToSlots / FromSlots`：拆成 `farm_meta` / `farm_plots` / `farm_inv` / `farm_social`
- `FarmServer`：
  - 读档改 4 槽并行读，**meta 缺失时回退读旧单槽 `farm_doc` 并自动迁移**
  - 写档逐槽写、单槽失败不影响其它槽，meta 最后写；>11KB 打告警
  - 高频调用（种植/收获/浇水，无回调路径）改为**标脏 + 每 5 秒批量落盘**；带回调的路径仍然同步写，保证语义不变
  - 每个槽独立错误处理，坏槽只丢那一块

### 验证

- `dev/DevNet.lua`（新）：**31 项断言全过** —— 分片/坏槽隔离、农场分槽往返、以及用假传输跑完整 客户端→服务端→回包 链路（建会/申请/审批/权限/贡献/团本血量池/上限夹取/退会/离线降级）
- `dev/DevGuild.lua` / `dev/DevRaidCloud.lua`：**0 fail**（回归）
- 联机 validate（`--network`）：`COMPLETED`，Lua 错误 0、资源错误 0
- 服务端脚本自检：`[server] 服务端已就绪` + `[Guild] 服务端已注册 11 条路由`

### 修复

- 上游代码引用 `Fonts/MiSans-Game.ttf` 但仓库里没有该文件 → 生成同名子集副本，并在 `dev/make_font_subset.py` 里同步产出，消除启动期资源报错

### 补充：公会的创建 / 加入 / 退出入口

- 主页联机区改成 4 个明确按钮：**同步** / **创建公会** / **申请加入** / **退出公会**（离线时最后一个是「重置本地公会」）
- 「申请加入」弹出文本输入框（新增 `TextInput` 事件接入 + Enter 提交 / Esc 取消），输入会长给的公会 ID 即可
- 「退出公会」调 `GuildClient.Leave`；离线时该按钮改为重置本地模拟公会（贡献币/等级/科技清零）
- 互助页新增**入会申请审批**：会长/管理员看到申请人，直接「同意 / 拒绝」
- 主页显示自己的**公会 ID**，方便发给队友

### 已知问题

- `validate --network` 的 load 阶段会有一条引擎提示 `Server error occurred before connection (history_errors=1)`，随后自动重连并 `COMPLETED`（init/run/scene 全 PASS）。服务端日志在远端，本地暂时读不到；已记录待平台侧排查。

## 2026-11-21 · 同步上游 master `10c596b9`（联机底座 + 好友 + 农场联机）

### 新增（上游）

- **联机底座**：`scripts/network/NetCore.lua`（身份 / 连接 / 请求-响应 / 服务端路由 / 云端 KV）、`network/FarmShared.lua`、`network/FarmServer.lua`、`network/FarmClient.lua`
- **双入口**：`scripts/server_main.lua`（服务端入口）、`scripts/lobby_runtime.lua`（自定义大厅：单机 / 联机）
- **好友**：`scripts/Friend.lua` + `FriendUI.lua`
- **农场联机**：`scripts/FarmStore.lua`（双端共用纯逻辑）
- **其它**：`EffectArt.lua`、`DevPanel.lua`，以及 `docs/联机接入指南.md`、`docs/联机踩坑记录-2026-11-21.md`、`docs/农场联机方案-2026-11-16.md`
- 上游同时改动：`Combat` `Menu` `main` `State` `SceneUI` `Farm` `FarmUI` `CampUI` `CharArt`

### 工程变化

- 切换为**多人游戏模式**：`.project/settings.json` → `@runtime.multiplayer.enabled = true`（Maker 构建回报"本项目是多人游戏模式"）
- 本地预览校验必须加 `--network`（会分配测试服务器）；不加会报"网络/server 项目"

### 合并方式

以 `9f80429` 为 base 做三方合并：`git merge`，冲突仅 13 个 `.meta`（取上游带 `path_refs` 的版本），业务代码自动合并。
**保留我们的改动**：`RaidCloud.lua`（公会共斗血量池）、`Guild/GuildUI` 的公会等级 / 科技上限 / 团本档位、`Cloud.lua` 公会名片、`RankUI.lua` 详情面板、字体子集脚本的 `U+3000` 修复。

### 修复

- `FriendUI.lua` 用了字体里没有的 `◐`(U+25D0)，显示为方框 → 改为 `◎`(U+25CE)，并把 `◎○●◆◇` 加进子集 `EXTRA`
- 字体重新裁剪：1678 字符 / 423 KB，`scripts/*.lua` **缺字 0**

### 验证

- `dev/DevGuild.lua`：**total fails = 0**
- `dev/DevRaidCloud.lua`：**total fails = 0**
- 联机模式 validate（`--network`）：`COMPLETED`，**Lua 错误 0**

## 2026-11-20 · 异步联机（A，不含农场）+ 公会共斗（B）

### 新增：公会团本共享血量池（B）

为了不引入服务端，把"共享血量"定义成一个可计算量：

```
剩余血量 = BOSS_MAX − Σ(本周全体成员上报的输出)
```

每个玩家只上传**自己的**本周输出（`clientCloud` 只允许写自己的云变量），任何人拉一次排行榜就能算出同一个血量池。

- 新增 `scripts/RaidCloud.lua`
  - iscores：`lh_raid_dmg`（本周输出，参与排序）、`lh_raid_week`（周标记，周一为界）
  - 快照：`lh_raid_snap`（公会等级 / 评级，展示用）
  - 缓存 20s、上报节流 20s；**离线/未登录自动降级**为本地单机团本，不报错
- 团本结算自动上报：`Combat.FinishRaid` → `RaidCloud.AddLocalDamage` + `Submit`
- 公会社团本页新增：共享血量池进度条、剩余 %、参与人数、我的输出、输出前三、刷新按钮
- 周切换时本地与云端均自动归零（云端按 `lh_raid_week` 过滤）

### 新增：公会数据上云 + 排行榜详情（A）

- `Cloud.GuildSnapshot()`：随排行榜一起上传公会名片（等级 / 累计贡献 / 科技总等级 / 本周团本评级）
- `Cloud` 拉榜时附带 `lh_guild_snap` 字段，榜单项带 `snap`
- `RankUI`：任意一行可点击 → 详情面板显示对方公会名片；未上传名片的玩家给出引导文案

### 按需求未做

- **农场联机**：本次不做（按需求移除）
- **跨玩家写入**（浇水/送礼给对方结算）：`clientCloud` 无法写他人数据，需要服务端，属 C 阶段

### 验证

- `dev/DevRaidCloud.lua`：**18 项断言全过**（周标记 / 血量池算法 / 跨周重置 / 离线降级 / 结算累加 / 界面绘制）
- `dev/DevGuild.lua`：**total fails = 0**（公会回归）
- 本地启动 validate：`COMPLETED`，Lua 错误 0、资源错误 0
- 字体子集重新裁剪：1639 字符 / 413 KB，`scripts/*.lua` 缺字 0

### 已知限制

- 伤害在本地上报，**没有服务端校验**，共斗只作乐趣用，不适合做竞技排名；要真防作弊得走服务端（C 阶段）

## 2026-11-20

### 同步上游 master（`9f80429`：合并 test → master）

**新增模块（20 个）**
`ActMap` · `Art` · `BagUI` · `Camp` · `CampUI` · `CharArt` · `Cloud` · `Economy` · `Farm` · `FarmArt` · `FarmUI` · `FarmWalk` · `LevelCards` · `Opportunity` · `Pet` · `PetData` · `PetUI` · `RankUI` · `SceneUI` · `TitleUI`

**主要内容**
- **ui 经济 v2**：局外货币全面改名 —— 经验 → **精粹**、金币 → **生息**、银币 → **血尘**（公会商店 / 特权 / 科技文案同步更新）
- **dev1 层卡 / 机遇系统**（LevelCards、Opportunity、ActMap）
- **农场**（Farm / FarmArt / FarmUI / FarmWalk）与宠物（Pet / PetData / PetUI）
- **战斗与农场修复**：合并残留清理、鼠标拖动选施法方向修复（`S.hover` 为 nil 导致 MouseMove 报错）等
- 排行榜（RankUI）、云存档（Cloud）、营地（Camp / CampUI）、背包（BagUI）、标题与场景 UI（TitleUI / SceneUI）

**工程结构变化**
- `scripts/` 13 → **53** 项（含新增 `.meta`）
- `dev/` 51 → **85** 项（新增 DevFarm / DevPet / DevActMap / DevCloud / DevFeedback4 / DevFixBatch2-3 等自检脚本）
- 新增 `docs/`（策划与接入文档）、`music_preview/`（音乐预览素材）

**验证**
- 本地原生预览 `validate`：`COMPLETED`，**Lua 错误 0**，资源错误 0（仅启动首帧耗时 227ms 的环境抖动）
- `dev/DevGuild.lua` 公会回归自检：**total fails = 0**（公会等级 / 科技上限 / 团本档位 / 商店解锁 全部通过）
- 字体子集覆盖：`scripts/*.lua` 全量字符 **1637 字形、缺字 0**，无需重新裁剪

### 环境问题记录

- 本地预览 `validate` 报 `ENOENT … maker-cache-<hash>\.maker-preview-owner.json`：这是 `%TEMP%` 下的旧缓存残留，把 `TEMP/TMP` 指向项目内目录（如 `.backup/tmp`）后重跑即可，属环境问题、与工程代码无关

---

## 2026-10-28

### 新增：公会系统（依据《公会贡献币》策划文档）

- `scripts/Guild.lua`：贡献币经济 / 周软上限 3500 / 感谢信 / 周限购 / 局内特权 / 科技树 / 团本 / 战报与救援的离线模拟，纯逻辑、状态存 `data.guild`
- `scripts/GuildUI.lua`：主菜单右上「公会」入口，5 个页签（主页 / 商店 / 科技 / 团本 / 互助）
- `dev/DevGuild.lua`：65 条验收断言 + 团本实战 + 5 页签绘制自检

**经济规则**
| 途径 | 产出 | 每日上限 |
|---|---|---|
| 签到/捐赠 | 20 贡献币 | 1 次 |
| 灵魂摆渡（救援） | 80 | 3 次 |
| 悬赏拓印 | 50 | 2 次 |
| 战报点赞 | 5 | 5 次 |
| 公会团本 | 500~1000（按输出评级 D~S，再乘难度系数） | 每周 1 次 |

- 每周一 00:00 重置：周产出上限 / 周限购 / 团本次数与评级
- 达到周上限后产出停止，溢出按 100:1 折算「感谢信」

**公会等级（1~5）**
- 每获得 1 贡献币 → 个人公会经验 +1，全员合计 = 个人 × 10
- 达到阈值后手动点「提升公会等级」，阈值（总经验）：2000 / 8000 / 20000 / 40000
- 等级解锁：科技上限（2/4/6/8/10）、商店稀有度（普通→稀有→史诗→传说）、团本难度档位

**科技树（3 线 × 10 级，单线满级 7500 币）**
- 生存线：初始护盾 +1.5%/级，脱战回复延迟 -0.1s/级
- 经济线：局内货币 +2%/级，局外收益 +1%/级
- 输出线：技能冷却 -1%/级，暴击伤害 +1%/级

**团本（公会团本 · 瘟衰巨像）**
- 沿用关底 Boss 模型（`colossus`），数值按第 1 关关底计算
- 出场技能跟随主界面选择的技能配置
- 难度档位：普通 / 困难 / 噩梦 / 炼狱 / 灭世，Boss 伤害 ×1.0 / 1.35 / 1.8 / 2.4 / 3.2，贡献币 ×1.0 / 1.15 / 1.3 / 1.5 / 1.75
- 团本中死亡不掉进度，按已造成的输出量结算评级

**局内特权**：Buff 重随券、初始资金加注（+50 局内货币）、濒死护盾保险（首次致命伤保留 1 血）、精英怪预警（地图标记精英/Boss 房）、钥匙房钥匙（地图上开一次额外三选一）

**测试用按钮**（仅 `S.dev = true` 显示）
- 主页：+1000 贡献币
- 团本页：一键重置周限购 + 团本次数；团本无限次重复体验

### 修复

- **启动崩溃**：Lua 5.4 下 `string.format("%d", 物理宽/dpr)` 在非整数 dpr（Windows 125% 缩放、高 DPI 手机）会抛 `number has no integer representation`；已在 `main.lua` 顶部用 `formatIntSafe` 包装 `string.format` 兜底
- **团本 Boss 名称与模型**：UI 之前写错为「畸变巨像」，实际为 `colossus` 瘟衰巨像；团本固定刷关底 Boss
- **字体方框（tofu）**：`assets/Fonts/MiSans-Regular.ttf` 是按用语裁剪的子集，新增中文文案缺字形会显示方框；重跑 `dev/make_font_subset.py`，并修掉 `U+3000` 全角空格被过滤导致的老问题

---

## 发布记录

| 日期 | Maker 提交 | 内容 |
|---|---|---|
| 2026-11-21 | `1e288c8` | 公会创建/加入/退出的明确入口 + 入会审批 UI + 公会 ID 展示 |
| 2026-11-21 | `4fe938b` | 公会联机（服务端权威 + 分槽）+ 农场存档分槽/批量落盘 + `MiSans-Game.ttf` 修复 |
| 2026-11-21 | `d74b190` | 同步上游 master `10c596b9`（联机底座 / 好友 / 农场联机）+ 工程切多人模式 |
| 2026-11-20 | `898a2c9` | 补 Maker 自动生成的 `RaidCloud.lua.meta`（资源元数据）|
| 2026-11-20 | `523f5c0` | 异步联机 A（公会名片上云 + 排行榜详情）+ 公会共斗共享血量池（B）|
| 2026-11-20 | `80df2e2` | 同步上游 master `9f80429`（ui 经济 v2 / 层卡机遇 / 农场宠物 / 战斗修复）|
| 2026-10-28 | `b081778` | 公会：一键重置、团本档位/BOSS 详情、团本按第 1 关数值 |
| 2026-10-28 | `dc3a379` | 公会：等级 1~5、贡献币→公会经验、科技上限、团本难度档位 |
| 2026-10-28 | `b96c0bf` | 同步上游 `50652a8` + 字体子集重建 |
| 2026-10-27 | `d612329` | 修复 `%d` 浮点导致的 Start 崩溃 |
| 2026-10-27 | `80e6791` | 初始化 Maker 工程（迁移到新应用 `lifehealth`）|
