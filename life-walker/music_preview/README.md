# 背景音乐 · Canon in D（钢琴）

## 游戏内文件

- `assets/audio/bgm_canon.ogg`（4.0 MB，48kHz 立体声，OGG Vorbis q0.4）
- `assets/audio/bgm_canon.ogg.meta`（UUID 由 Maker 的 generate_resource_meta 生成）
- 时长 7:42，循环播放；`scripts/Audio.lua` 负责加载、循环、开关与音量
- 处理：源文件峰值归一化到 -0.9 dBFS 后编码（响度更接近手机外放需要的水平）

## 预览源文件（不进仓库）

- `music_preview/Canon_in_D_piano_snipsound_PDM.mp3`
- 48 kHz / 192 kbps，10.6 MB，与游戏内 OGG 是同一段演奏

## 来源与授权

- 来源页面：https://snipsound.com/free-music/track/canon-in-d-45/
- 直链：https://media.snipsound.com/audio/rf_pachelbel_canon_in_d.mp3
- 授权：页面标注 **CC Public Domain Mark 1.0**
  （https://creativecommons.org/publicdomain/mark/1.0/），页面原文写明
  "free for commercial use, no attribution"（可商用、无需署名）
- 作曲：Johann Pachelbel（约 1680 年），作品本身早已进入公有领域
- 内容核对：低音走向 D–A–B–F♯–G–D–G–A（卡农经典低音线），钢琴独奏

## 备注

- 这是第三方录音：CC PDM 表示录音本身也被标记为公有领域，可商用；
  发布前建议把本页和来源链接一起留档，作为授权凭证。
- 如果以后要压缩包体，可把 OGG 质量降到 q0.3（约 3 MB）或裁剪成 2~3 分钟循环段；
  当前先保留完整 7:42，保证听感与试听版本一致。
