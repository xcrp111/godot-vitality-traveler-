#!/usr/bin/env node
/**
 * 把「参考风格_角色单动作横条包」整理成游戏能直接采样的角色图集。
 *
 * 用法（项目根目录）：
 *     NODE_PATH=<img-deps/node_modules> node dev/make_char_sheets.js <包目录>
 *
 * 输入：<包目录>/剑客|枪客|游侠|法师/NN_<职业>_<动作>.png（横条，8 帧等分，2172px 宽）
 * 输出：assets/image/char/<class>.png —— 每职业一张，8 列 × 动作数行，单元 160×200
 *
 * 处理要点：
 *   1. 每张横条按 8 等分切帧（实测每个窗口正好一个人物）
 *   2. 每个动作算一次公共锚点：横向取 8 帧 bbox 中心的中位数，纵向取最低点当脚底，
 *      动作内的帧就不会左右漂、跳
 *   3. 按 144px（游戏内 72px 的 2 倍）缩放人物高度，等比缩小、预乘 alpha 双线性采样
 *   4. 输出尺寸：宽 160 × 高 200，人物脚底固定在 y=190
 */
const { PNG } = require("pngjs");
const fs = require("fs");
const path = require("path");

const ROOT = path.resolve(__dirname, "..");
const SRC = process.argv[2] || path.join(ROOT, ".tmp/charpack/参考风格_角色单动作横条包");
const OUT_DIR = path.join(ROOT, "assets", "image", "char");

const CLASSES = [
    { dir: "剑客", id: "swordsman" },
    { dir: "枪客", id: "spearman" },
    { dir: "游侠", id: "ranger" },
    { dir: "法师", id: "mage" },
];
const FRAMES = 8;
const CELL_W = 160, CELL_H = 200;
const BASE_Y = 190;        // 脚底在单元里的位置
const CHAR_H = 144;        // 缩放下的人物高度（游戏内按 72px 画 = 2 倍图）

fs.mkdirSync(OUT_DIR, { recursive: true });

function alphaBounds(img, x0, x1) {
    let minX = 1e9, maxX = -1, minY = 1e9, maxY = -1;
    for (let y = 0; y < img.height; y++) {
        for (let x = x0; x < x1; x++) {
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

// 预乘 alpha 的双线性采样，避免缩小后边缘发黑
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

const ACTION_ORDER = [];

for (const cls of CLASSES) {
    const dir = path.join(SRC, cls.dir);
    const files = fs.readdirSync(dir).filter((f) => f.endsWith(".png")).sort();
    const rows = [];

    for (const f of files) {
        const img = PNG.sync.read(fs.readFileSync(path.join(dir, f)));
        const boxes = [];
        for (let i = 0; i < FRAMES; i++) {
            const x0 = Math.round(i * img.width / FRAMES);
            const x1 = Math.round((i + 1) * img.width / FRAMES);
            boxes.push(alphaBounds(img, x0, x1));
        }
        const valid = boxes.filter(Boolean);
        if (valid.length === 0) continue;
        // 公共锚点：横向取「脚底那一小段的中心」（用 bbox 中心会被枪/剑拉偏），
        // 纵向取最低点当脚底。相对本帧起点算，不能直接用绝对坐标。
        const frameX0 = [];
        const relCenters = [];
        for (let i = 0; i < FRAMES; i++) {
            const x0 = Math.round(i * img.width / FRAMES);
            frameX0.push(x0);
            const b = boxes[i];
            if (!b) continue;
            const bandTop = b.maxY - Math.max(4, Math.round((b.maxY - b.minY + 1) * 0.12));
            // 脚底那一小段里取「最长的一段实体」的中点：腿脚是最宽的，
            // 立在旁边的枪杆/剑身只有几像素宽，不会把锚点拽偏
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
            mids.sort((a, b) => a - b);
            relCenters.push(mids.length ? mids[Math.floor(mids.length / 2)]
                : (b.minX + b.maxX) / 2 - x0);
        }
        relCenters.sort((a, b) => a - b);
        const anchorRel = relCenters[Math.floor(relCenters.length / 2)];
        const anchorBottom = Math.max(...valid.map((b) => b.maxY));
        const maxH = Math.max(...valid.map((b) => b.maxY - b.minY + 1));
        rows.push({ name: f.replace(/^\d+_/, "").replace(/\.png$/, ""), file: f, img, boxes,
            frameX0, anchorRel, anchorBottom, maxH });
        if (!ACTION_ORDER.includes(f)) ACTION_ORDER.push(f);
    }

    const scale = CHAR_H / Math.max(...rows.map((r) => r.maxH));
    const sheet = new PNG({ width: CELL_W * FRAMES, height: CELL_H * rows.length });
    sheet.data.fill(0);

    rows.forEach((row, ri) => {
        for (let i = 0; i < FRAMES; i++) {
            const b = row.boxes[i];
            if (!b) continue;
            const cx = (b.minX + b.maxX) / 2;
            // 目标位置：锚点（人物中心）落在单元中心，脚底落在 BASE_Y
            const dstCx = i * CELL_W + CELL_W / 2;
            const dstBottom = ri * CELL_H + BASE_Y;
            for (let dy = 0; dy < CELL_H; dy++) {
                for (let dx = 0; dx < CELL_W; dx++) {
                    const sx = row.frameX0[i] + row.anchorRel + (dx - CELL_W / 2) / scale;
                    const sy = row.anchorBottom - (BASE_Y - dy) / scale;
                    if (sx < b.minX - 1 || sx > b.maxX + 1 || sy < b.minY - 1 || sy > b.maxY + 1) continue;
                    if (sx < 0 || sy < 0 || sx >= row.img.width - 1 || sy >= row.img.height - 1) continue;
                    const c = sampleProc(row.img, sx, sy);
                    if (c[3] <= 4) continue;
                    const di = ((ri * CELL_H + dy) * sheet.width + (i * CELL_W + dx)) * 4;
                    sheet.data[di] = c[0];
                    sheet.data[di + 1] = c[1];
                    sheet.data[di + 2] = c[2];
                    sheet.data[di + 3] = c[3];
                }
            }
        }
    });

    const out = path.join(OUT_DIR, cls.id + ".png");
    const buf = PNG.sync.write(sheet);
    fs.writeFileSync(out, buf);
    console.log(cls.id, rows.length + " 行 × " + FRAMES + " 帧", "scale=" + scale.toFixed(3),
        (buf.length / 1024).toFixed(0) + "KB", "→", path.relative(ROOT, out));
    console.log("  动作:", rows.map((r) => r.name).join(" / "));
}
