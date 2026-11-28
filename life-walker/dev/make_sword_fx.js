#!/usr/bin/env node
/**
 * 把「剑客素材包」里的技能特效整理成游戏图集（8 帧横条，单帧 128×128）。
 *
 * 用法：
 *   NODE_PATH=.tools/deps/node_modules node dev/make_sword_fx.js <包目录>
 *
 * 输入：<包目录>/effects/<特效>/animation.json + frames/*.png（单帧 256×256）
 * 输出：assets/image/fx/<ID>.png —— 8 帧横向，单帧 128
 */
const fs = require("fs");
const path = require("path");
const { PNG } = require("pngjs");

const ROOT = path.resolve(__dirname, "..");
const SRC = process.argv[2] || path.join(ROOT, ".tmp", "sword_in", "swordsman_assets");
const OUT_DIR = path.join(ROOT, "assets", "image", "fx");

const FRAMES = 8;
const CELL = 128;

// 游戏里的 id → 素材特效目录
const LIST = [
    ["sw_stab", "S01_impact"],       // 三段斩命中
    ["sw_dash", "S02_hit"],          // 闪影突进接触
    ["sw_guardaura", "S03_aura"],    // 剑心护体（循环）
    ["sw_spin", "S04_orbit"],        // 旋刃横斩剑轨
    ["sw_shadow", "S06_impact"],     // 瞬影连斩命中
    ["sw_parry", "S05_contact_fx"],  // 卸势格挡火花
];

function sample(img, fx, fy) {
    const x = Math.max(0, Math.min(img.width - 1, Math.round(fx)));
    const y = Math.max(0, Math.min(img.height - 1, Math.round(fy)));
    const i = (y * img.width + x) * 4;
    return [img.data[i], img.data[i + 1], img.data[i + 2], img.data[i + 3]];
}

fs.mkdirSync(OUT_DIR, { recursive: true });

for (const [id, dirName] of LIST) {
    const dir = path.join(SRC, "effects", dirName);
    const meta = JSON.parse(fs.readFileSync(path.join(dir, "animation.json"), "utf8"));
    const files = (meta.frames || []).map((f) => PNG.sync.read(fs.readFileSync(path.join(dir, f.file))));
    if (!files.length) throw new Error("没有帧: " + dir);

    const sheet = new PNG({ width: CELL * FRAMES, height: CELL });
    sheet.data.fill(0);

    for (let i = 0; i < FRAMES; i++) {
        const si = files.length <= 1 ? 0
            : Math.min(files.length - 1, Math.floor((i * files.length) / FRAMES));
        const img = files[si];
        const sx = img.width / CELL, sy = img.height / CELL;
        for (let dy = 0; dy < CELL; dy++) {
            for (let dx = 0; dx < CELL; dx++) {
                const [r, g, b, a] = sample(img, dx * sx, dy * sy);
                if (a === 0) continue;
                const o = (dy * sheet.width + i * CELL + dx) * 4;
                sheet.data[o] = r; sheet.data[o + 1] = g; sheet.data[o + 2] = b; sheet.data[o + 3] = a;
            }
        }
    }

    const out = path.join(OUT_DIR, id + ".png");
    fs.writeFileSync(out, PNG.sync.write(sheet));
    console.log(`${id}  ← ${dirName}（${files.length} 帧）→ ${out}`);
}
