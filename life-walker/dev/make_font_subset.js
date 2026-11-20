#!/usr/bin/env node
/**
 * 重新裁剪中文字体：只保留 scripts/ 里实际用到的字（Node 版，无需 Python）。
 *
 * 用法（项目根目录下）：
 *     npm i subset-font --prefix .tmp/font-deps
 *     NODE_PATH=<装 subset-font 的 node_modules> node dev/make_font_subset.js
 *
 * 背景：assets/Fonts/MiSans-Regular.ttf 是裁剪过的子集（9.7MB -> 260KB 左右）。
 * **每次在 scripts/ 里新增中文文案后都要重跑一次**，否则新字没有字形（显示成方框）。
 * 源文件是 dev/fonts/MiSans-Regular.full.ttf（完整字体，不进构建包）。
 */
const fs = require("fs");
const path = require("path");
const subsetFont = require("subset-font");

const ROOT = path.resolve(__dirname, "..");
const SOURCE = path.join(ROOT, "dev", "fonts", "MiSans-Regular.full.ttf");
const OUT = path.join(ROOT, "assets", "Fonts", "MiSans-Regular.ttf");

// 额外保险字符（标点、符号、圈号）
const EXTRA = "×·—…「」『』【】、。，：；！？（）《》“”‘’±%‰℃①②③④⑤·・－";

(async () => {
    const dir = path.join(ROOT, "scripts");
    const chars = new Set();
    for (const f of fs.readdirSync(dir)) {
        if (!f.endsWith(".lua")) continue;
        const text = fs.readFileSync(path.join(dir, f), "utf8");
        for (const ch of text) chars.add(ch);
    }
    for (let c = 0x20; c <= 0x7e; c++) chars.add(String.fromCodePoint(c));
    for (const ch of EXTRA) chars.add(ch);

    const codes = [...chars]
        .filter((ch) => !/[\u0000-\u001f\u007f]/.test(ch))
        .map((ch) => ch.codePointAt(0));

    const text = codes.map((cp) => String.fromCodePoint(cp)).join("");
    const buf = await subsetFont(fs.readFileSync(SOURCE), text, { targetFormat: "truetype" });
    fs.writeFileSync(OUT, Buffer.from(buf));

    console.log("字符数:", codes.length);
    console.log("已输出:", path.relative(ROOT, OUT), fs.statSync(OUT).size, "bytes");

    // 昵称字体：排行榜里显示的是 TapTap 账号昵称，字集无法预知，
    // 所以额外裁一份「常用汉字（GB2312 一级 3755 字）+ ASCII + 标点」，
    // 只在画昵称时按需加载，不影响主字体的体积。
    const NICK_OUT = path.join(ROOT, "assets", "Fonts", "MiSans-Nickname.ttf");
    const nickChars = new Set();
    const gbk = new TextDecoder("gbk");
    for (let hi = 0xb0; hi <= 0xd7; hi++) {
        for (let lo = 0xa1; lo <= 0xfe; lo++) {
            const ch = gbk.decode(Buffer.from([hi, lo]));
            if (ch.length === 1 && ch !== "�") nickChars.add(ch);
        }
    }
    for (let c = 0x20; c <= 0x7e; c++) nickChars.add(String.fromCodePoint(c));
    for (const ch of EXTRA) nickChars.add(ch);
    const nickText = [...nickChars].map((ch) => ch.codePointAt(0))
        .map((cp) => String.fromCodePoint(cp)).join("");
    const nickBuf = await subsetFont(fs.readFileSync(SOURCE), nickText, { targetFormat: "truetype" });
    fs.writeFileSync(NICK_OUT, Buffer.from(nickBuf));
    console.log("昵称字体:", path.relative(ROOT, NICK_OUT), fs.statSync(NICK_OUT).size, "bytes",
        "（" + nickChars.size + " 字）");
})().catch((e) => {
    console.error("字体裁剪失败:", e);
    process.exit(1);
});
