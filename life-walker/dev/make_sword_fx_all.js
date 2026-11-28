#!/usr/bin/env node
/**
 * 把剑客素材包里的【全部】特效整理成游戏图集（8 帧横条，单帧 128×128），
 * 并生成 scripts/SwordFxDefs.lua（id → 文件 / 帧率 / 是否循环）。
 *
 * 用法：
 *   NODE_PATH=.tools/deps/node_modules node dev/make_sword_fx_all.js <包目录>
 *
 * 命名：输出文件名统一加 swfx_ 前缀（例如 swfx_S02_hit.png），避免和已有特效撞名。
 * 帧率：按素材每帧 duration_ms 的总时长换算成 8 格横条的 fps，保证播放速度一致。
 */
const fs = require("fs");
const path = require("path");
const { PNG } = require("pngjs");

const ROOT = path.resolve(__dirname, "..");
const SRC = process.argv[2] || path.join(ROOT, ".tmp", "sword_in", "swordsman_assets");
const FX_DIR = path.join(SRC, "effects");
const OUT_DIR = path.join(ROOT, "assets", "image", "fx");
const LUA_OUT = path.join(ROOT, "scripts", "SwordFxDefs.lua");

const FRAMES = 8;
const CELL = 128;
const PREFIX = "swfx_";

function sample(img, fx, fy) {
    const x = Math.max(0, Math.min(img.width - 1, Math.round(fx)));
    const y = Math.max(0, Math.min(img.height - 1, Math.round(fy)));
    const i = (y * img.width + x) * 4;
    return [img.data[i], img.data[i + 1], img.data[i + 2], img.data[i + 3]];
}

fs.mkdirSync(OUT_DIR, { recursive: true });

const defs = [];
const dirs = fs.readdirSync(FX_DIR).filter((d) => fs.statSync(path.join(FX_DIR, d)).isDirectory()).sort();

for (const dirName of dirs) {
    const dir = path.join(FX_DIR, dirName);
    const jsonFile = fs.readdirSync(dir).find((f) => f.endsWith(".json"));
    if (!jsonFile) { console.log("跳过（无配置）: " + dirName); continue; }
    const meta = JSON.parse(fs.readFileSync(path.join(dir, jsonFile), "utf8"));
    const framesMeta = meta.frames || [];
    if (!framesMeta.length) { console.log("跳过（无帧）: " + dirName); continue; }

    const images = framesMeta.map((f) => PNG.sync.read(fs.readFileSync(path.join(dir, f.file))));
    const totalMs = framesMeta.reduce((s, f) => s + (f.duration_ms || 80), 0);
    const fps = Math.max(4, Math.min(30, Math.round((FRAMES * 1000) / Math.max(1, totalMs))));

    const sheet = new PNG({ width: CELL * FRAMES, height: CELL });
    sheet.data.fill(0);
    for (let i = 0; i < FRAMES; i++) {
        const si = images.length <= 1 ? 0
            : Math.min(images.length - 1, Math.floor((i * images.length) / FRAMES));
        const img = images[si];
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

    const id = PREFIX + dirName;
    fs.writeFileSync(path.join(OUT_DIR, id + ".png"), PNG.sync.write(sheet));
    defs.push({ id, dir: dirName, name: meta.name || dirName, fps, loop: !!meta.loop });
    console.log(`${id}  ← ${dirName}（${images.length} 帧, ${totalMs}ms, fps ${fps}${meta.loop ? ", loop" : ""}）`);
}

// 生成 Lua 表：EffectArt 启动时合并进 Defs
const lines = [];
lines.push("-- SwordFxDefs.lua — 由 dev/make_sword_fx_all.js 自动生成，请勿手改");
lines.push("-- 剑客素材包（swordswoman_complete_assets）里的全部特效");
lines.push("return {");
for (const d of defs) {
    lines.push(`    ${d.id} = { file = "image/fx/${d.id}.png", fps = ${d.fps}, loop = ${d.loop ? "true" : "false"}, scale = 1.0 }, -- ${d.name}`);
}
lines.push("}");
fs.writeFileSync(LUA_OUT, lines.join("\n") + "\n", "utf8");
console.log(`共 ${defs.length} 个特效；写出 ${LUA_OUT}`);
