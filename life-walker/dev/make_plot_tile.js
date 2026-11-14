#!/usr/bin/env node
/**
 * 耕地贴图去草边：把 plot_tilled.png 外围那圈绿草裁掉，只留中间那块土。
 *
 * 用法（项目根目录）：
 *     NODE_PATH=<img-deps/node_modules> node dev/make_plot_tile.js <源图>
 *
 * 处理：
 *   1. 从中线往两边扫，找到第一块「不是绿草」的像素，量出中间土块的矩形
 *   2. 按这个矩形裁剪（四角圆角处残留的草直接改成透明）
 *   3. 输出到 assets/image/farm/plot_tilled.png（沿用原 .meta / UUID）
 *
 * 这样游戏里画的就只有土块本身，边缘不会再带一圈草；
 * 圆角处透出底图原本的草地，看起来是土块压在草地上，而不是贴了个草边框。
 */
const { PNG } = require("pngjs");
const fs = require("fs");
const path = require("path");

const ROOT = path.resolve(__dirname, "..");
const SRC = process.argv[2] || path.join(ROOT, ".tmp/farmart/plot_raw.png");
const OUT = path.join(ROOT, "assets", "image", "farm", "plot_tilled.png");

const img = PNG.sync.read(fs.readFileSync(SRC));
const W = img.width, H = img.height, D = img.data;
const at = (x, y) => {
    const i = (y * W + x) * 4;
    return [D[i], D[i + 1], D[i + 2], D[i + 3]];
};
// 绿草：不透明且绿色通道明显高于红色；土块是棕红（R > G）
const isGrass = (c) => c[3] > 8 && c[1] > c[0] + 6;

// ---- 中线往两侧扫，量出中间土块的范围
const cy = Math.floor(H / 2), cx = Math.floor(W / 2);
let left = 0, right = W - 1, top = 0, bottom = H - 1;
for (let x = cx; x >= 0; x--) { if (isGrass(at(x, cy))) { left = x + 1; break; } }
for (let x = cx; x < W; x++) { if (isGrass(at(x, cy))) { right = x - 1; break; } }
for (let y = cy; y >= 0; y--) { if (isGrass(at(cx, y))) { top = y + 1; break; } }
for (let y = cy; y < H; y++) { if (isGrass(at(cx, y))) { bottom = y - 1; break; } }

// 留 1px 余量，把土块自带的深色描边完整保留
left = Math.max(0, left - 1); top = Math.max(0, top - 1);
right = Math.min(W - 1, right + 1); bottom = Math.min(H - 1, bottom + 1);

const cw = right - left + 1, ch = bottom - top + 1;
const out = new PNG({ width: cw, height: ch });

// 先把草像素标出来，再往内扩 3px：草和土之间的过渡像素（黄绿、橄榄色）用窄阈值抓不干净，
// 直接按「离草 3px 以内都算草」抹掉，边缘就不会留一圈绿毛边。
// 这组素材里土是强棕红（R 比 G 大 50 以上），草/过渡色都满足 G > R-40。
const grass = new Uint8Array(cw * ch);
const isGrassLoose = (c) => c[3] > 8 && c[1] > c[0] - 40;
for (let y = 0; y < ch; y++) {
    for (let x = 0; x < cw; x++) {
        const si = ((top + y) * W + (left + x)) * 4;
        const c = [D[si], D[si + 1], D[si + 2], D[si + 3]];
        if (c[3] === 0 || isGrassLoose(c)) grass[y * cw + x] = 1;
    }
}
const ERASE = 3;
const kill = new Uint8Array(cw * ch);
for (let y = 0; y < ch; y++) {
    for (let x = 0; x < cw; x++) {
        if (!grass[y * cw + x]) continue;
        for (let dy = -ERASE; dy <= ERASE; dy++) {
            for (let dx = -ERASE; dx <= ERASE; dx++) {
                const nx = x + dx, ny = y + dy;
                if (nx < 0 || ny < 0 || nx >= cw || ny >= ch) continue;
                kill[ny * cw + nx] = 1;
            }
        }
    }
}

for (let y = 0; y < ch; y++) {
    for (let x = 0; x < cw; x++) {
        if (kill[y * cw + x]) continue;
        const si = ((top + y) * W + (left + x)) * 4;
        const di = (y * cw + x) * 4;
        out.data[di] = D[si];
        out.data[di + 1] = D[si + 1];
        out.data[di + 2] = D[si + 2];
        out.data[di + 3] = D[si + 3];
    }
}

fs.writeFileSync(OUT, PNG.sync.write(out));
console.log("已输出:", path.relative(ROOT, OUT), cw + "x" + ch,
    "（原图", W + "x" + H + "，裁掉草边 left=" + left + " top=" + top + "）");
