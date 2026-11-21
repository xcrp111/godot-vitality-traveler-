#!/usr/bin/env node
/**
 * 把素材包里的技能特效整理成游戏能直接采样的横条图集。
 *
 * 用法（项目根目录）：
 *   NODE_PATH=<png-deps/node_modules> node dev/make_fx_sheets.js <包目录> [ID ...]
 *
 * 输入：<包目录>/skills/<ID>/<ID>.png —— 1024×512，4 列 × 2 行，单帧 256×256
 * 输出：assets/image/fx/<ID>.png —— 横条 8 帧，单帧 CELL×CELL（默认 128×128，即缩小一半）
 *
 * 每张按「8 帧的公共内容框」裁切再缩放，帧内内容始终位于单元中心，
 * 游戏里按帧号取格子、以锚点(0.5,0.5)对齐即可。
 */
const { PNG } = require("pngjs");
const fs = require("fs");
const path = require("path");

const ROOT = path.resolve(__dirname, "..");
const SRC = process.argv[2] || path.join(ROOT, ".tmp_mage", "mage_assets");
const OUT_DIR = process.env.FX_OUT || path.join(ROOT, "assets", "image", "fx");
const IDS = process.argv.slice(3).filter((a) => a.startsWith("E") || a.startsWith("S"));

const FRAMES = 8;
const CELL = 128;          // 输出单帧尺寸
const PAD = 2;             // 裁剪时留一点边

fs.mkdirSync(OUT_DIR, { recursive: true });

function alphaBounds(img, x0, y0, w, h) {
    let minX = 1e9, maxX = -1, minY = 1e9, maxY = -1;
    for (let y = y0; y < y0 + h; y++) {
        for (let x = x0; x < x0 + w; x++) {
            if (img.data[(y * img.width + x) * 4 + 3] > 8) {
                if (x < minX) minX = x;
                if (x > maxX) maxX = x;
                if (y < minY) minY = y;
                if (y > maxY) maxY = y;
            }
        }
    }
    return maxX < 0 ? null : { minX, maxX, minY, maxY };
}

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

for (const id of IDS) {
    // skills/ 与 states/ 两类素材都支持（S 开头是状态特效）
    let file = path.join(SRC, "skills", id, id + ".png");
    if (!fs.existsSync(file)) file = path.join(SRC, "states", id, id + ".png");
    if (!fs.existsSync(file)) { console.log("跳过（没有这张）：" + id); continue; }
    const img = PNG.sync.read(fs.readFileSync(file));
    const fw = Math.floor(img.width / 4), fh = Math.floor(img.height / 2);

    // 按帧各自的内容框居中缩放（弹道/命中每帧内容位置不同，用公共框会互相挤扁）
    const boxes = [];
    for (let i = 0; i < FRAMES; i++) {
        const col = i % 4, row = Math.floor(i / 4);
        boxes.push(alphaBounds(img, col * fw, row * fh, fw, fh));
    }
    const valid = boxes.filter(Boolean);
    if (!valid.length) { console.log("空图：" + id); continue; }
    const maxW = Math.max(...valid.map((b) => b.maxX - b.minX + 1 + PAD * 2));
    const maxH = Math.max(...valid.map((b) => b.maxY - b.minY + 1 + PAD * 2));
    const scale = Math.min(CELL / maxW, CELL / maxH);

    const sheet = new PNG({ width: CELL * FRAMES, height: CELL });
    sheet.data.fill(0);

    for (let i = 0; i < FRAMES; i++) {
        const b = boxes[i];
        if (!b) continue;
        const col = i % 4, row = Math.floor(i / 4);
        const fxo = col * fw, fyo = row * fh;
        const bx0 = Math.max(fxo, b.minX - PAD), bx1 = Math.min(fxo + fw - 1, b.maxX + PAD);
        const by0 = Math.max(fyo, b.minY - PAD), by1 = Math.min(fyo + fh - 1, b.maxY + PAD);
        const cw = bx1 - bx0 + 1, ch = by1 - by0 + 1;
        const dw = Math.max(1, Math.round(cw * scale)), dh = Math.max(1, Math.round(ch * scale));
        const ox = i * CELL + Math.round((CELL - dw) / 2);
        const oy = Math.round((CELL - dh) / 2);
        for (let dy = 0; dy < dh; dy++) {
            for (let dx = 0; dx < dw; dx++) {
                const sx = bx0 + dx / scale, sy = by0 + dy / scale;
                const [r, g, bl, al] = sampleProc(img, sx, sy);
                if (al === 0) continue;
                const o = ((oy + dy) * sheet.width + (ox + dx)) * 4;
                sheet.data[o] = r; sheet.data[o + 1] = g; sheet.data[o + 2] = bl; sheet.data[o + 3] = al;
            }
        }
    }
    const out = path.join(OUT_DIR, id + ".png");
    fs.writeFileSync(out, PNG.sync.write(sheet));
    console.log(`${id}  最大内容 ${maxW}×${maxH} → 缩放 ${scale.toFixed(2)}（单帧 ${CELL}）`);
}
