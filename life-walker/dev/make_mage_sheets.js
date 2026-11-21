#!/usr/bin/env node
/**
 * 把「法师迭代素材包（mage_assets_62_sheets）」里的角色动作整理成游戏图集。
 *
 * 用法（项目根目录）：
 *   NODE_PATH=<png-deps/node_modules> node dev/make_mage_sheets.js <包目录>
 *
 * 输入：<包目录>/characters/<动作>/<动作>.png —— 512×256，4 列 × 2 行，单帧 128×128，
 *       脚底锚点 (64,112)，先左到右再上到下。
 * 输出：assets/image/char/mage.png —— 8 列 × 动作数行，单元 160×200，脚底固定 y=190，
 *       人物高度规整到 144px（和另外三个职业同一套尺度）。
 *
 * 只处理法师；其他职业的图集不动。
 */
const { PNG } = require("pngjs");
const fs = require("fs");
const path = require("path");

const ROOT = path.resolve(__dirname, "..");
const SRC = process.argv[2] || path.join(ROOT, ".tmp_mage", "mage_assets");
const OUT = path.join(ROOT, "assets", "image", "char", "mage.png");

const FRAMES = 8;
const CELL_W = 160, CELL_H = 200;
const BASE_Y = 190;
const CHAR_H = 144;

// 行动作 → 图集行（1 开始）。改这里就同时改 CharArt.ROWS.mage
const ROWS = [
    ["A01_idle", "idle"],
    ["A02_walk", "walk"],
    ["A04_hit", "hurt"],
    ["A05_death", "death"],
    ["A08_basic_attack", "attack"],
    ["A03_run", "run"],
    ["A06_channel", "channel"],
    ["A07_appear", "dodge"],
    ["A09_fireball_cast", "skill1"],
    ["A12_frost_wave_cast", "skill2"],
    ["A16_thunder_strike_cast", "skill3"],
    ["A13_ice_spike_cast", "skill4"],
    ["A15_chain_lightning_cast", "skill5"],
    ["A10_flame_burst_cast", "skill6"],
    ["A17_static_field_cast", "skill7"],
    ["A11_meteor_cast", "skill8"],
    ["A14_blizzard_channel", "skill9"],
    ["A07_appear", "victory"],
];

function alphaBounds(img, x0, y0, w, h) {
    let minX = 1e9, maxX = -1, minY = 1e9, maxY = -1;
    for (let y = y0; y < y0 + h; y++) {
        for (let x = x0; x < x0 + w; x++) {
            const a = img.data[(y * img.width + x) * 4 + 3];
            if (a > 16) {
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

const actions = ROWS.map(([dirName, key]) => {
    const file = path.join(SRC, "characters", dirName, dirName + ".png");
    if (!fs.existsSync(file)) throw new Error("缺少动作图: " + file);
    const img = PNG.sync.read(fs.readFileSync(file));
    const fw = Math.floor(img.width / 4), fh = Math.floor(img.height / 2);
    const boxes = [], origins = [];
    for (let i = 0; i < FRAMES; i++) {
        const col = i % 4, row = Math.floor(i / 4);
        const x0 = col * fw, y0 = row * fh;
        origins.push({ x0, y0 });
        boxes.push(alphaBounds(img, x0, y0, fw, fh));
    }
    const valid = boxes.filter(Boolean);
    if (!valid.length) throw new Error("空图: " + file);

    // 公共锚点：横向取脚底那一小段里最宽实体的中点（法杖不会把锚点拽偏），纵向取最低点
    const relCenters = [];
    for (let i = 0; i < FRAMES; i++) {
        const b = boxes[i];
        if (!b) { relCenters.push(null); continue; }
        const { x0 } = origins[i];
        const bandTop = b.maxY - Math.max(4, Math.round((b.maxY - b.minY + 1) * 0.12));
        const mids = [];
        for (let y = bandTop; y <= b.maxY; y++) {
            let bestLen = 0, bestMid = null, runStart = -1;
            for (let x = b.minX; x <= b.maxX + 1; x++) {
                const on = x <= b.maxX && img.data[(y * img.width + x) * 4 + 3] > 16;
                if (on && runStart < 0) runStart = x;
                if (!on && runStart >= 0) {
                    const len = x - runStart;
                    if (len > bestLen) { bestLen = len; bestMid = (runStart + x - 1) / 2; }
                    runStart = -1;
                }
            }
            if (bestMid) mids.push(bestMid - x0);
        }
        mids.sort((a, b2) => a - b2);
        relCenters.push(mids.length ? mids[Math.floor(mids.length / 2)]
            : (b.minX + b.maxX) / 2 - x0);
    }
    const sorted = relCenters.filter((v) => v != null).sort((a, b) => a - b);
    const anchorRel = sorted[Math.floor(sorted.length / 2)];
    const maxH = Math.max(...valid.map((b) => b.maxY - b.minY + 1));
    return { key, dirName, img, boxes, origins, anchorRel, maxH, fw, fh };
});

const scale = CHAR_H / Math.max(...actions.map((a) => a.maxH));
const sheet = new PNG({ width: CELL_W * FRAMES, height: CELL_H * actions.length });
sheet.data.fill(0);

actions.forEach((a, ri) => {
    for (let i = 0; i < FRAMES; i++) {
        const b = a.boxes[i];
        if (!b) continue;
        const { x0, y0 } = a.origins[i];
        const feetY = b.maxY + 1;
        const dw = Math.round(a.fw * scale), dh = Math.round(a.fh * scale);
        const dstX0 = Math.round(i * CELL_W + CELL_W / 2 - a.anchorRel * scale);
        const dstY0 = Math.round(ri * CELL_H + BASE_Y - (feetY - y0) * scale);
        for (let dy = 0; dy < dh; dy++) {
            const ty = ri * CELL_H + dy + dstY0 - ri * CELL_H;   // 单元内局部坐标
            const py = dstY0 + dy;
            if (py < ri * CELL_H || py >= (ri + 1) * CELL_H) continue;
            for (let dx = 0; dx < dw; dx++) {
                const px = dstX0 + dx;
                if (px < i * CELL_W || px >= (i + 1) * CELL_W) continue;
                const fx = x0 + dx / scale, fy = y0 + dy / scale;
                const [r, g, bl, al] = sampleProc(a.img, fx, fy);
                if (al === 0) continue;
                const o = (py * sheet.width + px) * 4;
                sheet.data[o] = r; sheet.data[o + 1] = g; sheet.data[o + 2] = bl; sheet.data[o + 3] = al;
            }
        }
    }
    console.log(`行 ${ri + 1}  ${a.dirName}  (${a.key})  高度 ${a.maxH}px → ${CHAR_H}px`);
});

fs.writeFileSync(OUT, PNG.sync.write(sheet));
console.log(`写出 ${OUT}  ${sheet.width}×${sheet.height}`);
