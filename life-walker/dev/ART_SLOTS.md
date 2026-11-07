# 美术素材占位清单

当前版本全部使用程序化几何图形绘制，不依赖图片。后续替换素材时，按下面的文件名放进 `assets/` 对应目录即可；我会加一层图片加载模块，只替换绘制函数，不改玩法逻辑。

## 约定

- 格式：PNG，透明背景
- 风格：卡通像素，俯视角
- 尺寸：2 的幂优先（32 / 64 / 128 / 256）
- 朝向：默认朝右；如果做 8 方向，请按 `名字_方向.png` 命名
- 动画：`名字_动作_序号.png`，序号从 0 开始

## 角色

| 用途 | 建议路径 | 尺寸 | 说明 |
|---|---|---|---|
| 剑客 · 待机 | `assets/sprites/player_swordsman_idle.png` | 48×48 | 朝右 |
| 剑客 · 移动 | `assets/sprites/player_swordsman_move_0..3.png` | 48×48 | 4 帧循环 |
| 剑客 · 普攻 | `assets/sprites/player_swordsman_attack_0..3.png` | 64×64 | 含剑光 |
| 剑客 · 受击 | `assets/sprites/player_swordsman_hurt.png` | 48×48 | 可选 |

## 怪物

| 用途 | 建议路径 | 尺寸 | 说明 |
|---|---|---|---|
| 游移病菌（小兵） | `assets/sprites/enemy_germ.png` | 32×32 | 球状、纤毛 |
| 病毒孢子囊（小兵） | `assets/sprites/enemy_spore.png` | 40×40 | 半透明囊泡 |
| 潮热沙蠕（小兵） | `assets/sprites/enemy_worm.png` | 36×36 | 贴地蠕虫 |
| 腐败菌丝怪（精英） | `assets/sprites/enemy_mycel.png` | 64×64 | 黑色菌丝 |
| 高热疫魔（Boss） | `assets/sprites/enemy_plague.png` | 128×128 | 赤红肿胀 |

## 投射物 / 特效

| 用途 | 建议路径 | 尺寸 | 说明 |
|---|---|---|---|
| 孢子弹 | `assets/sprites/bullet_spore.png` | 16×16 | 绿色 |
| 精英孢子弹 | `assets/sprites/bullet_mycel.png` | 16×16 | 黄绿 |
| 冲击波 | `assets/sprites/fx_shockwave.png` | 256×256 | 环形，可程序化 |
| 受击火花 | `assets/sprites/fx_hit.png` | 32×32 | 可选，程序化已够用 |
| 剑气 | `assets/sprites/fx_slash.png` | 128×128 | 弧形剑光 |

## UI

| 用途 | 建议路径 | 尺寸 | 说明 |
|---|---|---|---|
| 技能图标 | `assets/image/skill_<id>.png` | 64×64 | id 1~6：斩/突/护/旋/格/瞬 |
| 摇杆底盘 | `assets/image/joystick_base.png` | 256×256 | 可选，当前是圆形 |
| 摇杆头 | `assets/image/joystick_knob.png` | 128×128 | 可选 |
| 房间图标 | `assets/image/room_<type>.png` | 64×64 | type：light/standard/mixed/elite/double/shop/event/boss |
| 面板底纹 | `assets/image/panel_bg.png` | 可九宫格 | 可选 |

## 场景

| 用途 | 建议路径 | 尺寸 | 说明 |
|---|---|---|---|
| 地面瓦片 | `assets/sprites/floor_tile.png` | 64×64 | 可平铺，人体内部质感 |
| 墙体 / 边界 | `assets/sprites/wall_tile.png` | 64×64 | 可选 |

## 字体

当前 `assets/Fonts/MiSans-Regular.ttf` 是 Windows 黑体占位，正式发布前替换为有授权的商用中文字体（MiSans / 思源黑体等）。
