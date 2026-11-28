#!/usr/bin/env node
/**
 * 把「剑客素材包（swordswoman_complete_assets）」里的角色动作整理成游戏图集。
 *
 * 用法（项目根目录）：
 *   NODE_PATH=<png-deps/node_modules> node dev/make_swordsman_sheets.js <包目录>
 *
 * 输入：<包目录>/characters/right/<动作>/<动作>.json + frames/*.png
 *       单帧 256×256，脚底锚点 root=(128,232)，朝右
 * 输出：assets/image/char/swordsman.png —— 8 列 × 动作数行，单元 160×200，
 *       脚底固定 y=190，人物高度规整到 144px（和另外三个职业同一套尺度）
 *
 * 只处理剑客；其他职业的图集不动。
 */
const fs = require("fs");
const path = require("path");
const { PNG } = require("pngjs");

const ROOT = path.resolve(__dirname, "..");
const SRC = process.argv[2] || path.join(ROOT, ".tmp", "sword_in", "swordsman_assets");
const CHAR_DIR = path.join(SRC, "characters", "right");
const OUT = path.join(ROOT, "assets", "image", "char", "swordsman.png");

const FRAMES = 8;
const CELL_W = 160, CELL_H = 200;
const BASE_Y = 190;
const CHAR_H = 144;

// 图集行（1 开始）→ 素材包里的动作目录。改这里要同步 CharArt.ROWS.swordsman
const ROWS = [
    ["A02_idle",     "idle"],
    ["A04_move",     "walk"],
    ["A08_recoil",   "hurt"],
    ["A13_fall",     "death"],
    ["S00_attack",   "attack"],
    ["S01_stab1",    "skill1"],   // 三段斩
    ["S02_dash",     "skill2"],   // 闪影突进
    ["S03_activate", "skill3"],   // 剑心护体
    ["S04_spin",     "skill4"],   // 旋刃横斩
    ["S05_enter",    "skill5"],   // 卸势格挡
    ["S06_first",    "skill6"],   // 瞬影连斩
    ["A03_ready",    "victory"],
];

function alphaBounds(img) {
    let minX = 1e9, maxX = -1, minY = 1e9, maxY = -1;
    for (let y = 0; y < img.height; y++) {
        for (let x = 0; x < img.width; x++) {
            if (img.data[(y * img.width + x) * 4 + 3] > 16) {
                if (x < minX) minX = x;
                if (x > maxX) maxX = x;
                if (y < minY) minY = y;
                if (y > maxY) maxY = y;
            }
        }
    }
    return maxX < 0 ? null : { minX, maxX, minY, maxY };
}

// 预乘 alpha 双线性采样：缩小后边缘不发黑
function sampleProc(img, fx, fy) {
    const x0 = Math.max(0, Math.min(img.width - 1, Math.floor(fx)));
    const y0 = Math.max(0, Math.min(img.height - 1, Math.floor(fy)));
    const x1 = Math.min(img.width - 1, x0 + 1), y1 = Math.min(img.height - 1, y0 + 1);
    const tx = fx - x0, ty = fy - y0;
    const px = (x, y) => {
        const i = (y * img.width + x) * 4;
        return [img.data[i], img.data[i + 1], img.data[i + 2], img.data[i + 3]];
    };
    const c00 = px(x0, y0), c10 = px(x1, y0), c01 = px(x0, y1), c11 = px(x1, y1);
    const w00 = (1 - tx) * (1 - ty), w10 = tx * (1 - ty), w01 = (1 - tx) * ty, w11 = tx * ty;
    const a = c00[3] * w00 + c10[3] * w10 + c01[3] * w01 + c11[3] * w11;
    if (a < 1) return [0, 0, 0, 0];
    let r = 0, g = 0, b = 0;
    for (const [c, w] of [[c00, w00], [c10, w10], [c01, w01], [c11, w11]]) {
        r += c[0] * (c[3] / 255) * w;
        g += c[1] * (c[3] / 255) * w;
        b += c[2] * (c[3] / 255) * w;
    }
    const norm = a / 255;
    return [Math.round(r / norm), Math.round(g / norm), Math.round(b / norm), Math.round(a)];
}

function LoadAction(dirName) {
    const dir = path.join(CHAR_DIR, dirName);
    const jsonFile = fs.readdirSync(dir).find((f) => f.endsWith(".json"));
    if (!jsonFile) throw new Error("缺少动作配置: " + dir);
    const meta = JSON.parse(fs.readFileSync(path.join(dir, jsonFile), "utf8"));
    const frames = (meta.frames || []).map((f) => {
        const file = path.join(dir, f.file);
        if (!fs.existsSync(file)) throw new Error("缺少帧: " + file);
        return PNG.sync.read(fs.readFileSync(file));
    });
    if (!frames.length) throw new Error("没有帧: " + dir);
    const bounds = frames.map(alphaBounds);
    const valid = bounds.filter(Boolean);
    if (!valid.length) throw new Error("空图: " + dir);
    const maxH = Math.max(...valid.map((b) => b.maxY - b.minY + 1));
    const root = meta.root || [128, 232];
    return { dirName, frames, bounds, maxH, root };
}

const actions = ROWS.map(([dir]) => LoadAction(dir));
const scale = CHAR_H / Math.max(...actions.map((a) => a.maxH));

const sheet = new PNG({ width: CELL_W * FRAMES, height: CELL_H * actions.length });
sheet.data.fill(0);

actions.forEach((a, ri) => {
    const n = a.frames.length;
    for (let i = 0; i < FRAMES; i++) {
        // 帧数不是 8 的动作按比例拉伸取样，保持节奏完整
        const si = n <= 1 ? 0 : Math.min(n - 1, Math.floor((i * n) / FRAMES));
        const img = a.frames[si];
        const b = a.bounds[si] || alphaBounds(img);
        if (!b) continue;
        // 锚点：用素材声明的 root（脚底），比按包围盒推更稳
        const dstX0 = Math.round(i * CELL_W + CELL_W / 2 - a.root[0] * scale);
        const dstY0 = Math.round(ri * CELL_H + BASE_Y - a.root[1] * scale);
        const dw = Math.round(img.width * scale), dh = Math.round(img.height * scale);
        for (let dy = 0; dy < dh; dy++) {
            const py = dstY0 + dy;
            if (py < ri * CELL_H || py >= (ri + 1) * CELL_H) continue;
            for (let dx = 0; dx < dw; dx++) {
                const px = dstX0 + dx;
                if (px < i * CELL_W || px >= (i + 1) * CELL_W) continue;
                const [r, g, bl, al] = sampleProc(img, dx / scale, dy / scale);
                if (al === 0) continue;
                const o = (py * sheet.width + px) * 4;
                sheet.data[o] = r; sheet.data[o + 1] = g; sheet.data[o + 2] = bl; sheet.data[o + 3] = al;
            }
        }
    }
    console.log(`行 ${ri + 1}  ${a.dirName}  (${a.frames.length} 帧)  高度 ${a.maxH}px → ${CHAR_H}px`);
});

fs.writeFileSync(OUT, PNG.sync.write(sheet));
console.log(`写出 ${OUT}  ${sheet.width}×${sheet.height}  scale=${scale.toFixed(3)}`);
