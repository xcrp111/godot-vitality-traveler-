#!/usr/bin/env node
/**
 * 把整张作物序列图（4 列 × 9 行，深色底）整理成引擎能直接等分采样的透明图。
 *
 * 用法（项目根目录）：
 *     npm i pngjs --prefix .tmp/img-deps
 *     NODE_PATH=<img-deps/node_modules> node dev/make_crop_sheet.js <源图>
 *
 * 处理：
 *   1. 从四边泛洪去掉接近纯色的深色背景（只吃连通背景，不会抠进植物内部）
 *   2. 按实测的内容段切成 9 行 × 4 列
 *   3. 每格按「阶段目标高度」缩放：发芽 46% / 生长 72% / 成熟 100% / 果实 86%，
 *      这样各阶段体型差距明显（原图 2、3 阶段几乎一样大），成熟期也吃满格子
 *   4. 底部对齐到统一基线；发芽/生长/成熟三列的最底部做透明度羽化，
 *      让自带的土堆和图上的耕地土块融在一起（不再像贴纸一样浮在上面）
 *   5. 输出 1024×2304（4 列 × 9 行 @256）到 assets/image/farm/crops.png
 */
const { PNG } = require("pngjs");
const fs = require("fs");
const path = require("path");

const ROOT = path.resolve(__dirname, "..");
const SRC = process.argv[2] || path.join(ROOT, ".tmp/farmart/crops.png");
const OUT = path.join(ROOT, "assets", "image", "farm", "crops.png");

const CELL = 256;          // 输出单元格
const PAD_BOTTOM = 26;     // 底部留白，让植物"站"在同一基线上
const BG_TOL = 16;         // 背景色容差
const USABLE = CELL - PAD_BOTTOM - 4;   // 可用内容高度
// 每一列（1 发芽 / 2 生长 / 3 成熟 / 4 果实）占可用高度的比例
const STAGE_RATIO = { 1: 0.34, 2: 0.62, 3: 0.94, 4: 0.82 };
const MAX_W = Math.round(CELL * 0.88);  // 宽度上限，避免相邻地块互相压住
const FEATHER = 20;        // 底部羽化像素（只作用于 1~3 列）
// 羽化同时把颜色往耕地土块的平均色（140,78,33）上靠，
// 不然精灵自带的土堆边缘会像贴纸一样浮在耕地上
const SOIL = [140, 78, 33];

const img = PNG.sync.read(fs.readFileSync(SRC));
const W = img.width, H = img.height, D = img.data;
const at = (x, y) => { const i = (y * W + x) * 4; return [D[i], D[i + 1], D[i + 2], D[i + 3]]; };

// ---- 背景色：取左上角一小片的中位数
let sr = 0, sg = 0, sb = 0, n = 0;
for (let y = 0; y < 6; y++) for (let x = 0; x < 6; x++) {
    const c = at(x, y); sr += c[0]; sg += c[1]; sb += c[2]; n++;
}
const bg = [sr / n, sg / n, sb / n];
const isBgColor = (c) => Math.abs(c[0] - bg[0]) < BG_TOL
    && Math.abs(c[1] - bg[1]) < BG_TOL && Math.abs(c[2] - bg[2]) < BG_TOL;

// ---- 四边泛洪
const alpha = new Uint8Array(W * H).fill(255);
const seen = new Uint8Array(W * H);
const stack = [];
for (let x = 0; x < W; x++) { stack.push(x, 0, x, H - 1); }
for (let y = 0; y < H; y++) { stack.push(0, y, W - 1, y); }
while (stack.length) {
    const y = stack.pop(), x = stack.pop();
    if (x < 0 || y < 0 || x >= W || y >= H) continue;
    const idx = y * W + x;
    if (seen[idx]) continue;
    seen[idx] = 1;
    if (!isBgColor(at(x, y))) continue;
    alpha[idx] = 0;
    stack.push(x + 1, y, x - 1, y, x, y + 1, x, y - 1);
}

// ---- 行 / 列的内容段（用去背后的 alpha 投影，避免把背景当内容）
const colHas = new Array(W).fill(false);
const rowHas = new Array(H).fill(false);
for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
    if (alpha[y * W + x] > 0) { colHas[x] = true; rowHas[y] = true; }
}
function runs(arr, minLen) {
    const out = []; let st = -1;
    for (let i = 0; i < arr.length; i++) {
        if (arr[i] && st < 0) st = i;
        if (!arr[i] && st >= 0) { if (i - st >= minLen) out.push([st, i - 1]); st = -1; }
    }
    if (st >= 0) out.push([st, arr.length - 1]);
    return out;
}
const colRuns = runs(colHas, 20);
const rowRuns = runs(rowHas, 20);
if (colRuns.length !== 4 || rowRuns.length !== 9) {
    console.error("列段", colRuns.length, "行段", rowRuns.length, "—— 预期 4 × 9，切割可能不准");
}

// ---- 单元格边界取相邻内容段的中点
function bounds(runList, total) {
    const b = [0];
    for (let i = 1; i < runList.length; i++) {
        b.push(Math.floor((runList[i - 1][1] + runList[i][0]) / 2));
    }
    b.push(total);
    return b;
}
const bx = bounds(colRuns, W);
const by = bounds(rowRuns, H);

// ---- 铺到统一画布
const OUT_W = CELL * 4, OUT_H = CELL * 9;
const out = new PNG({ width: OUT_W, height: OUT_H });
out.data.fill(0);

for (let r = 0; r < 9; r++) {
    for (let c = 0; c < 4; c++) {
        const x0 = bx[c], x1 = bx[c + 1];
        const y0 = by[r], y1 = by[r + 1];
        // 内容包围盒
        let minX = 1e9, maxX = -1, minY = 1e9, maxY = -1;
        for (let y = y0; y < y1; y++) for (let x = x0; x < x1; x++) {
            if (alpha[y * W + x] > 0) {
                if (x < minX) minX = x; if (x > maxX) maxX = x;
                if (y < minY) minY = y; if (y > maxY) maxY = y;
            }
        }
        if (maxX < 0) continue;
        const cw = maxX - minX + 1, ch = maxY - minY + 1;
        // 阶段目标高度：成熟期吃满格子，发芽期只有一半不到，体型差距一眼能看出来
        const targetH = USABLE * (STAGE_RATIO[c + 1] || 1.0);
        const scale = Math.min(targetH / ch, MAX_W / cw);
        const dw = Math.round(cw * scale), dh = Math.round(ch * scale);
        const ox = c * CELL + Math.round((CELL - dw) / 2);
        const oy = r * CELL + (CELL - PAD_BOTTOM - dh);
        const baseline = CELL - PAD_BOTTOM;   // 目的地里内容底边所在的行（格内坐标）
        for (let dy = 0; dy < dh; dy++) {
            for (let dx = 0; dx < dw; dx++) {
                const sx = minX + Math.floor(dx / scale);
                const sy = minY + Math.floor(dy / scale);
                if (sx > maxX || sy > maxY) continue;
                const si = (sy * W + sx) * 4;
                const a = alpha[sy * W + sx];
                if (a === 0) continue;
                // 底部羽化 + 往耕地土色上靠：仅 1~3 列（土堆所在的列），果实不处理
                let fa = 1, mix = 0;
                if (c < 3 && FEATHER > 0) {
                    const fromBottom = baseline - dy;   // 0 = 最底一行
                    if (fromBottom < FEATHER) {
                        fa = Math.max(0, fromBottom / FEATHER);
                        fa = fa * fa * (3 - 2 * fa);    // smoothstep，边缘更软
                        mix = (1 - fa) * 0.75;
                    }
                }
                if (fa <= 0.02) continue;
                const di = ((oy + dy) * OUT_W + (ox + dx)) * 4;
                out.data[di] = Math.round(D[si] * (1 - mix) + SOIL[0] * mix);
                out.data[di + 1] = Math.round(D[si + 1] * (1 - mix) + SOIL[1] * mix);
                out.data[di + 2] = Math.round(D[si + 2] * (1 - mix) + SOIL[2] * mix);
                out.data[di + 3] = Math.round(255 * fa);
            }
        }
    }
}

fs.mkdirSync(path.dirname(OUT), { recursive: true });
const buf = PNG.sync.write(out);
fs.writeFileSync(OUT, buf);
console.log("已输出:", path.relative(ROOT, OUT), OUT_W + "x" + OUT_H, buf.length, "bytes");
console.log("列边界:", JSON.stringify(bx));
console.log("行边界:", JSON.stringify(by));
