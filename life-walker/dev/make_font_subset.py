#!/usr/bin/env python3
"""重新裁剪中文字体：只保留 scripts/ 里实际用到的字。

用法（项目根目录下）：
    python dev/make_font_subset.py

依赖 fonttools：pip install fonttools

背景：assets/Fonts/MiSans-Regular.ttf 是裁剪过的子集（9.7MB -> 250KB 左右）。
**每次在 scripts/ 里新增中文文案后都要重跑一次**，否则新字会没有字形（显示空白）。
源文件是 dev/fonts/MiSans-Regular.full.ttf（完整字体，不进构建包），输出覆盖 assets/ 里的子集。
"""
import glob
import io
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE_FONT = os.path.join(ROOT, "dev", "fonts", "MiSans-Regular.full.ttf")
FONT = os.path.join(ROOT, "assets", "Fonts", "MiSans-Regular.ttf")
CHARS_FILE = os.path.join(ROOT, ".tmp", "subset_chars.txt")

# 额外保险字符
EXTRA = "×·—…「」『』【】、。，：；！？（）《》“”‘’±%‰℃①②③④⑤"


def lua_texts():
    """scripts/ 与 dev/ 下的全部 .lua。

    早期只扫 scripts/，结果 dev 预览（DevActMapView 等）里新加的文案从来没进过子集，
    屏幕上就出现「本层机　房」这种缺字空洞。dev/ 不进构建包，但 dev 视图跑的是同一份
    assets/Fonts/MiSans-Regular.ttf，所以必须一起扫。
    """
    for sub in ("scripts", "dev"):
        for path in sorted(glob.glob(os.path.join(ROOT, sub, "*.lua"))):
            with io.open(path, encoding="utf-8") as f:
                yield path, f.read()


def main() -> int:
    chars = set()
    for _path, text in lua_texts():
        chars.update(text)
    chars.update(chr(c) for c in range(0x20, 0x7F))
    chars.update(EXTRA)
    # U+3000 全角空格：isprintable() 对它返回 False，但 Menu.lua 拿它做对齐，
    # 字体里没字形的话那处直接搜成一团，所以要显式保留。
    chars = {c for c in chars if c.isprintable() or c in (" ", "\u3000")}

    os.makedirs(os.path.dirname(CHARS_FILE), exist_ok=True)
    with io.open(CHARS_FILE, "w", encoding="utf-8") as f:
        f.write("".join(sorted(chars)))
    print("字符数:", len(chars))

    cmd = [
        sys.executable, "-m", "fontTools.subset", SOURCE_FONT,
        "--text-file=" + CHARS_FILE,
        "--layout-features=",
        "--drop-tables+=DSIG",
        "--output-file=" + FONT,
    ]
    result = subprocess.run(cmd)
    if result.returncode != 0:
        print("字体裁剪失败", file=sys.stderr)
        return result.returncode
    print("已完成:", FONT, os.path.getsize(FONT), "bytes")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
