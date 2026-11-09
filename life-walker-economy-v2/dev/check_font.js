#!/usr/bin/env node
/**
 * 构建前检查：渲染用到的每个字，字体子集里都要有字形（否则界面上是方框）。
 *
 * 用法（项目根目录下，需先装 fontkit）：
 *     NODE_PATH=<node_modules> node dev/check_font.js
 *
 * 扫 scripts/*.lua 的全部文本（含注释），逐个字符问字体有没有字形。
 * 退出码 0 = 全部有字形；1 = 有缺字（先跑 dev/make_font_subset.js 重新裁剪）。
 */
const fs = require("fs");
const path = require("path");
const fontkit = require("fontkit");

const ROOT = path.resolve(__dirname, "..");
const FONT = path.join(ROOT, "assets", "Fonts", "MiSans-Regular.ttf");

function main() {
    const font = fontkit.openSync(FONT);
    const dir = path.join(ROOT, "scripts");
    const chars = new Set();
    for (const f of fs.readdirSync(dir)) {
        if (!f.endsWith(".lua")) continue;
        for (const ch of fs.readFileSync(path.join(dir, f), "utf8")) chars.add(ch);
    }
    const missing = [];
    for (const ch of chars) {
        const cp = ch.codePointAt(0);
        if (cp < 0x20 || cp === 0x7f) continue;
        if (!font.hasGlyphForCodePoint(cp)) missing.push(ch);
    }
    console.log("脚本文本字符数:", chars.size, "| 字体缺字形:", missing.length);
    if (missing.length) {
        console.log("缺字:", missing.join(""));
        console.log("修法: 重新裁剪字体 -> dev/make_font_subset.js");
        return 1;
    }
    console.log("✅ 字体覆盖完整");
    return 0;
}

process.exit(main());
