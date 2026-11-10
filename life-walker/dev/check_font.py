#!/usr/bin/env python3
"""构建前检查：渲染用到的每个字，字体子集里都要有字形（否则界面上是空白）。

用法（项目根目录下）：
    python dev/check_font.py
    # 本机没有 pip/pip 装了 fonttools 时：
    PYTHONPATH=F:\\_vt_tools\\pylibs python dev/check_font.py

与 check_font.js 等价（Node 版给有 node 的环境用，这份给只有 python 的环境用）。
扫描范围是 scripts/*.lua 与 dev/*.lua —— dev 视图用的是同一份子集字体，
只扫 scripts/ 会漏掉 dev 文案里的缺字（历史事故：dev 预览里「本层机遇房」的「遇」是空白）。

退出码 0 = 全部有字形；1 = 有缺字（先跑 dev/make_font_subset.py 重新裁剪）。
"""
import glob
import io
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONT = os.path.join(ROOT, "assets", "Fonts", "MiSans-Regular.ttf")


def main() -> int:
    try:
        from fontTools.ttLib import TTFont
    except ImportError:
        print("缺少 fonttools：pip install fonttools（或设 PYTHONPATH 指向已装目录）", file=sys.stderr)
        return 2

    font = TTFont(FONT)
    cmap = set()
    for table in font["cmap"].tables:
        cmap.update(table.cmap.keys())

    chars = set()
    where = {}
    for sub in ("scripts", "dev"):
        for path in sorted(glob.glob(os.path.join(ROOT, sub, "*.lua"))):
            with io.open(path, encoding="utf-8") as f:
                for ch in f.read():
                    chars.add(ch)
                    where.setdefault(ch, os.path.relpath(path, ROOT))

    missing = []
    for ch in sorted(chars):
        cp = ord(ch)
        if cp < 0x20 or cp == 0x7F:
            continue
        if cp not in cmap:
            missing.append((ch, cp, where[ch]))

    print("脚本文本字符数:", len(chars), "| 字体字形数:", len(cmap), "| 字体缺字形:", len(missing))
    if missing:
        print("缺字:", "".join(m[0] for m in missing))
        for ch, cp, src in missing:
            print("  U+%04X %s  首次出现于 %s" % (cp, ch, src))
        print("修法: 重新裁剪字体 -> python dev/make_font_subset.py")
        return 1

    print("OK 字体覆盖完整")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
