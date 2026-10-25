# godot-vitality-traveler

一个仓库，两个版本的健康主题游戏原型。

| 目录 | 版本 | 技术栈 | 一句话 |
|---|---|---|---|
| [`game-health/`](game-health/) | 原始原型 | Godot 4.6（Forward Plus） | 《Game Health》Godot 工程 |
| [`life-walker/`](life-walker/) | 《生命行者》 | UrhoX Lua + TapTap Maker | 重做版：健康养成 + 动作 Roguelike |

---

## game-health — Godot 版

- 用 **Godot 4.6** 打开 `game-health/project.godot`，主场景 `场景/main.tscn`
- 仓库里也带了导出版，Windows 可以直接双击 `game-health/Game Health.exe`
- 脚本在 `脚本/`，场景在 `场景/`，美术资源在 `资源/`

## life-walker — 《生命行者》

> 把每一步，走成力量。

现实步数换算成金币与经验，金币用于养成，经验分配给职业升级；关卡解锁也由当日步数决定。战斗部分是俯视角动作 Roguelike。

**玩法**

- 4 个职业：剑客（重装）/ 枪客（连击）/ 游侠（远程风筝）/ 法师（元素爆发），各自有等级、技能池与专属强化
- 196 条职业专属强化（54 + 44 + 50 + 48），只在对应职业的奖励、商店、事件里出现，且要求携带对应技能
- 连携系统：剑意、枪势、失衡、猎痕、元素亲和（燃烧 / 冰冻 / 过载 / 融化 / 蒸发）
- 8 种怪物（含 1 精英、2 Boss），第 7 关起进入畸变疫病派系
- 每个战斗房通关后 3 选 1 强化，房间难度越高，高品质概率越大

**技术**

- 纯 NanoVG 2D 渲染，1280×720 设计画布 + DPR 自适应
- UrhoX Lua（Lua 5.4），TapTap Maker 项目（`.project/` 是工程配置）
- 背景音乐是程序化合成的钢琴版《卡农》，48kHz 单声道，16.8 秒无缝循环

**怎么跑**

1. 装 **TapTap Maker**，用它打开 `life-walker` 目录，运行时会自动装好，可直接预览
2. 或者先备好 UrhoX 运行时（`.cli/UrhoXRuntime.exe`），再双击 `Play.bat`

> 注意：运行时（约 60MB，`.cli/`）和本地存档 `save.json` 不进仓库，所以刚 clone 下来直接双击 `Play.bat` 会找不到 exe。

**开发与回归**

`dev/` 下是回归脚本，逐个验证职业数值、技能机制、专属强化、怪物行为与界面排版，详见 [`life-walker/README.md`](life-walker/README.md)。

完整说明（已实现清单、数值公式、强化列表、测试脚本对照表）见 **[`life-walker/README.md`](life-walker/README.md)**。

---

## 分支

- `master` —— 主分支
- `dev1` / `dev2` / `dev3`、`test`、`ui` —— 各人开发用的分支

在仓库页面左上角的分支下拉框可以切换查看。只读浏览不需要登录；要直接往仓库推送，需要先被加为 Collaborator。
