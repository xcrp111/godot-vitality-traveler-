#!/usr/bin/env node
/**
 * 生成冥想背景音乐 assets/audio/bgm_meditate.ogg（原创合成，无版权问题）
 *
 * 用法（项目根目录）：
 *     npm i vorbis-encoder-js --prefix .tmp/audio-deps
 *     NODE_PATH=<audio-deps/node_modules> node dev/make_meditation_audio.js
 *
 * 编曲思路（按真实手碟独奏的听感来，不是按拍子乱敲）：
 *   1. 铺底是很轻的长音，只做和声底色，不抢戏
 *   2. 手碟用「分解和弦 / 滚奏 / 低音与旋律呼应」三种织体，
 *      同一乐句里的音彼此错开 90~150ms，像手指顺着音区滚过去
 *   3. 音色去掉最刺耳的高次泛音，起音放缓、衰减拉长，整体再过一道低通
 *   4. 乐句之间有呼吸，节奏偏自由（轻微抢拍拖拍），不做节拍器式的一拍一下
 */
const fs = require("fs");
const path = require("path");
const VorbisEncoder = require("vorbis-encoder-js").encoder;

const ROOT = path.resolve(__dirname, "..");
const OUT = path.join(ROOT, "assets", "audio", "bgm_meditate.ogg");

const SR = 22050;              // 冥想铺底没有高频内容，22.05k 足够
const CHORD_SEC = 16;          // 每段 16 秒
const CHORDS = 4;              // 4 段 → 64 秒
const TOTAL = CHORD_SEC * CHORDS;
const N = SR * TOTAL;

const buf = new Float32Array(N);
const pan = new Float32Array(N);   // 手碟单独一条轨，最后统一柔化

const hz = (n) => 440 * Math.pow(2, (n - 69) / 12);   // MIDI 音高 → 频率

// D 小调手碟常用音区
const D2 = hz(38), A2 = hz(45), D3 = hz(50), F3 = hz(53), G3 = hz(55), A3 = hz(57);
const Bb3 = hz(58), C4 = hz(60), D4 = hz(62), E4 = hz(64), F4 = hz(65), A4 = hz(69);

// ---------------------------------------------------------------- 音色
function addTone(startSec, durSec, freq, amp, attack, release) {
    const s0 = Math.floor(startSec * SR);
    const len = Math.floor(durSec * SR);
    const atk = Math.max(1, Math.floor(attack * SR));
    const rel = Math.max(1, Math.floor(release * SR));
    for (let i = 0; i < len; i++) {
        const idx = s0 + i;
        if (idx < 0 || idx >= N) continue;
        const t = i / SR;
        let env = 1;
        if (i < atk) env = i / atk;
        else if (i > len - rel) env = Math.max(0, (len - i) / rel);
        const breathe = 0.88 + 0.12 * Math.sin(2 * Math.PI * 0.037 * (startSec + t));
        buf[idx] += amp * env * breathe * Math.sin(2 * Math.PI * freq * t);
    }
}

/**
 * 手碟音（柔化版）
 * - 起音 18ms（原来 4ms，太「啪」）
 * - 去掉 4.87 倍那层最金属的泛音，2 次 / 3 次泛音也压低
 * - 加极轻的颤音，模拟余音的自然晃动
 */
function addHandpan(startSec, freq, amp, bright) {
    const s0 = Math.floor(startSec * SR);
    const len = Math.floor(7.0 * SR);
    const b = bright === undefined ? 1 : bright;
    const atkLen = 0.018 * SR;
    for (let i = 0; i < len; i++) {
        const idx = s0 + i;
        if (idx >= N) break;
        const t = i / SR;
        const atk = Math.min(1, i / atkLen);
        const env = atk * Math.exp(-t * 0.85);
        const vib = 1 + 0.0012 * Math.sin(2 * Math.PI * 4.2 * t) * Math.min(1, t * 0.8);
        const core = Math.sin(2 * Math.PI * freq * vib * t)
            + 0.26 * b * Math.sin(2 * Math.PI * freq * 2.01 * vib * t) * Math.exp(-t * 2.0)
            + 0.07 * b * Math.sin(2 * Math.PI * freq * 3.02 * vib * t) * Math.exp(-t * 3.0)
            + 0.18 * Math.sin(2 * Math.PI * freq * 1.003 * t) * Math.exp(-t * 0.9);
        // 敲击的颗粒感只留一点点，不然又刺了
        const tick = (Math.random() * 2 - 1) * Math.exp(-t * 120) * 0.04;
        pan[idx] += amp * env * core + amp * tick;
    }
}

// ---------------------------------------------------------------- 织体
// 分解和弦：顺着音区滚过去，间隔 90~150ms，首尾音略重
function arpeggio(startSec, freqs, amp, step) {
    const gap = step || 0.12;
    freqs.forEach((f, i) => {
        const jitter = (i % 2 === 0) ? 0 : 0.012;     // 轻微抢拍 / 拖拍，别太机械
        const a = amp * (i === 0 ? 1 : (i === freqs.length - 1 ? 1.1 : 0.78));
        addHandpan(startSec + i * gap + jitter, f, a);
    });
}

// 滚奏：同一个音快速轻敲几下，最后一击落下
function roll(startSec, freq, times, amp, spacing) {
    const gap = spacing || 0.08;
    for (let i = 0; i < times; i++) {
        addHandpan(startSec + i * gap, freq, amp * (i === times - 1 ? 1 : 0.42));
    }
}

// ---------------------------------------------------------------- 和声底色
const PADS = [
    [hz(45), hz(52), hz(60)],   // Am
    [hz(41), hz(48), hz(57)],   // F
    [hz(48), hz(55), hz(64)],   // C
    [hz(43), hz(50), hz(59)],   // G
];
for (let c = 0; c < CHORDS; c++) {
    const start = c * CHORD_SEC;
    for (const f of PADS[c % PADS.length]) {
        addTone(start, CHORD_SEC + 4, f, 0.026, 5.0, 7.0);
        addTone(start, CHORD_SEC + 4, f * 1.001, 0.014, 6.0, 7.0);
    }
}

// ---------------------------------------------------------------- 乐句
// 每条乐句：低音起 → 上行分解 → 顶点滚奏 → 回落，中间留白
const PHRASES = [
    (t) => {
        addHandpan(t + 0.0, D2, 0.13, 0.6);
        arpeggio(t + 0.6, [D3, A3, C4, D4], 0.16, 0.12);
        roll(t + 2.4, D4, 5, 0.13, 0.085);
        arpeggio(t + 3.6, [A3, C4, E4], 0.12, 0.13);
        addHandpan(t + 5.2, D3, 0.10, 0.7);
        roll(t + 6.0, A3, 4, 0.10, 0.09);
        arpeggio(t + 7.4, [D4, C4, A3, D3], 0.13, 0.14);
    },
    (t) => {
        arpeggio(t + 1.2, [D3, F3, A3, C4], 0.14, 0.13);
        addHandpan(t + 3.0, C4, 0.15);
        roll(t + 4.0, A3, 6, 0.11, 0.08);
        arpeggio(t + 6.0, [E4, F4, E4, C4], 0.12, 0.15);
    },
    (t) => {
        addHandpan(t + 0.0, A2, 0.12, 0.6);
        arpeggio(t + 0.9, [C4, E4, A4], 0.14, 0.13);
        addHandpan(t + 2.8, G3, 0.11);
        roll(t + 3.8, E4, 4, 0.12, 0.085);
        arpeggio(t + 5.0, [A4, F4, E4, C4, A3], 0.12, 0.125);
        addHandpan(t + 7.6, D3, 0.09, 0.6);
    },
    (t) => {
        addHandpan(t + 0.0, D2, 0.11, 0.6);
        arpeggio(t + 1.0, [D3, G3, Bb3, D4], 0.13, 0.13);
        addHandpan(t + 3.4, D4, 0.14);
        roll(t + 4.4, Bb3, 5, 0.10, 0.085);
        arpeggio(t + 6.2, [G3, A3, D3], 0.12, 0.15);
    },
];
for (let c = 0; c < CHORDS; c++) {
    PHRASES[c % PHRASES.length](c * CHORD_SEC);
}

// ---------------------------------------------------------------- 空间与混音
// 空气感：极轻的低通噪声
let lp = 0;
for (let i = 0; i < N; i++) {
    const t = i / SR;
    const white = Math.random() * 2 - 1;
    lp += (white - lp) * 0.002;
    buf[i] += lp * 0.03 * (0.7 + 0.3 * Math.sin(2 * Math.PI * 0.017 * t));
}

// 手碟单独过一道柔和低通，压掉刺耳的高频
let hp = 0;
const LP_A = 0.45;                       // 一阶低通，约 3kHz
for (let i = 0; i < N; i++) {
    hp += (pan[i] - hp) * LP_A;
    buf[i] += hp;
}

// 空间感：中长延迟 + 反馈，像石屋里的余响
const T1 = Math.floor(0.21 * SR);
const T2 = Math.floor(0.37 * SR);
const T3 = Math.floor(0.53 * SR);
for (let i = T3; i < N; i++) {
    buf[i] += buf[i - T1] * 0.22 + buf[i - T2] * 0.12 + buf[i - T3] * 0.06;
}

// 首尾交叉淡化，循环点不爆音
const XF = Math.floor(2.0 * SR);
for (let i = 0; i < XF; i++) {
    const k = i / XF;
    buf[i] = buf[i] * k + buf[N - XF + i] * (1 - k);
}

// 归一化
let peak = 0;
for (let i = 0; i < N - XF; i++) peak = Math.max(peak, Math.abs(buf[i]));
const norm = peak > 0 ? 0.70 / peak : 1;

const samples = new Float32Array(N - XF);
for (let i = 0; i < samples.length; i++) {
    samples[i] = Math.max(-1, Math.min(1, buf[i] * norm));
}

(async () => {
    const encoder = new VorbisEncoder(SR, 1, 0.45);
    // 编码器内存只有 16MB，整段塞进去会 abort；按 2 秒一块流式编码
    const CHUNK = SR * 2;
    for (let off = 0; off < samples.length; off += CHUNK) {
        const piece = Float32Array.from(samples.subarray(off, Math.min(samples.length, off + CHUNK)));
        encoder.encode([piece]);
    }
    const done = encoder.finish();
    const ogg = done && typeof done.arrayBuffer === "function"
        ? Buffer.from(await done.arrayBuffer())
        : Buffer.from(done);
    fs.writeFileSync(OUT, ogg);
    console.log("已输出:", path.relative(ROOT, OUT), ogg.length, "bytes",
        "(" + (samples.length / SR).toFixed(1) + " 秒)");
})();
