#!/usr/bin/env node
'use strict';

// Faithful Node.js mirror of Tools/generate_sounds.py (same 10 files,
// 16-bit PCM MONO, SR=22050). Uses a CPython-compatible MT19937 so the
// fixed-seed noise sequences and the round-half-to-even sample counts match.

const fs = require('fs');
const path = require('path');

const SR = 22050;
const SEED = 20240101;
const OUT_DIR = path.join(__dirname, '..', 'Sounds');

const PI = Math.PI;
const tr = Math.trunc;
const fl = Math.floor;
const mn = Math.min;
const mx = Math.max;

function pyRound(x) {
  const f = Math.floor(x);
  const diff = x - f;
  if (diff < 0.5) return f;
  if (diff > 0.5) return f + 1;
  return (f % 2 === 0) ? f : f + 1;
}

function clamp(x, lo, hi) {
  lo = (lo === undefined) ? -1.0 : lo;
  hi = (hi === undefined) ? 1.0 : hi;
  if (x < lo) return lo;
  if (x > hi) return hi;
  return x;
}

// ---- MT19937, CPython-compatible seeding + genrand_res53 ----
const MT_N = 624, MT_M = 397, MT_MATRIX_A = 0x9908b0df;
const MT_UPPER = 0x80000000, MT_LOWER = 0x7fffffff;

class MTRandom {
  constructor(seed) {
    this.mt = new Uint32Array(MT_N);
    this.mti = MT_N + 1;
    this.seed(seed);
  }
  seed(seed) {
    const key = [];
    if (seed === 0) {
      key.push(0);
    } else {
      let x = Math.abs(seed);
      while (x > 0) { key.push(x % 4294967296); x = Math.floor(x / 4294967296); }
    }
    this.initByArray(key);
  }
  initGenrand(s) {
    const mt = this.mt;
    mt[0] = s >>> 0;
    for (let i = 1; i < MT_N; i++) {
      const prev = mt[i - 1];
      mt[i] = (Math.imul(1812433253, (prev ^ (prev >>> 30)) >>> 0) + i) >>> 0;
    }
    this.mti = MT_N;
  }
  initByArray(init_key) {
    const mt = this.mt;
    const key_length = init_key.length;
    this.initGenrand(19650218);
    let i = 1, j = 0;
    let k = (MT_N > key_length) ? MT_N : key_length;
    for (; k > 0; k--) {
      const t = (mt[i] ^ Math.imul((mt[i - 1] ^ (mt[i - 1] >>> 30)) >>> 0, 1664525)) >>> 0;
      mt[i] = (t + init_key[j] + j) >>> 0;
      i++; j++;
      if (i >= MT_N) { mt[0] = mt[MT_N - 1]; i = 1; }
      if (j >= key_length) j = 0;
    }
    for (k = MT_N - 1; k > 0; k--) {
      const t = (mt[i] ^ Math.imul((mt[i - 1] ^ (mt[i - 1] >>> 30)) >>> 0, 1566083941)) >>> 0;
      mt[i] = (t - i) >>> 0;
      i++;
      if (i >= MT_N) { mt[0] = mt[MT_N - 1]; i = 1; }
    }
    mt[0] = 0x80000000;
    this.mti = MT_N;
  }
  genrandU32() {
    const mt = this.mt;
    const mag01 = [0x0, MT_MATRIX_A];
    let y, kk;
    if (this.mti >= MT_N) {
      for (kk = 0; kk < MT_N - MT_M; kk++) {
        y = (mt[kk] & MT_UPPER) | (mt[kk + 1] & MT_LOWER);
        mt[kk] = (mt[kk + MT_M] ^ (y >>> 1) ^ mag01[y & 0x1]) >>> 0;
      }
      for (; kk < MT_N - 1; kk++) {
        y = (mt[kk] & MT_UPPER) | (mt[kk + 1] & MT_LOWER);
        mt[kk] = (mt[kk + (MT_M - MT_N)] ^ (y >>> 1) ^ mag01[y & 0x1]) >>> 0;
      }
      y = (mt[MT_N - 1] & MT_UPPER) | (mt[0] & MT_LOWER);
      mt[MT_N - 1] = (mt[MT_M - 1] ^ (y >>> 1) ^ mag01[y & 0x1]) >>> 0;
      this.mti = 0;
    }
    y = mt[this.mti++];
    y = (y ^ (y >>> 11)) >>> 0;
    y = (y ^ ((y << 7) & 0x9d2c5680)) >>> 0;
    y = (y ^ ((y << 15) & 0xefc60000)) >>> 0;
    y = (y ^ (y >>> 18)) >>> 0;
    return y;
  }
  random() {
    const a = this.genrandU32() >>> 5;
    const b = this.genrandU32() >>> 6;
    return (a * 67108864.0 + b) / 9007199254740992.0;
  }
  uniform(a, b) {
    return a + (b - a) * this.random();
  }
}

function writeWav(filePath, samples) {
  const n = samples.length;
  const frames = Buffer.alloc(n * 2);
  for (let i = 0; i < n; i++) {
    let iv = pyRound(clamp(samples[i]) * 32767.0);
    if (iv > 32767) iv = 32767;
    else if (iv < -32768) iv = -32768;
    frames.writeInt16LE(iv, i * 2);
  }
  const dataSize = n * 2;
  const buf = Buffer.alloc(44 + dataSize);
  buf.write('RIFF', 0, 'latin1');
  buf.writeUInt32LE(36 + dataSize, 4);
  buf.write('WAVE', 8, 'latin1');
  buf.write('fmt ', 12, 'latin1');
  buf.writeUInt32LE(16, 16);
  buf.writeUInt16LE(1, 20);
  buf.writeUInt16LE(1, 22);
  buf.writeUInt32LE(SR, 24);
  buf.writeUInt32LE(SR * 2, 28);
  buf.writeUInt16LE(2, 32);
  buf.writeUInt16LE(16, 34);
  buf.write('data', 36, 'latin1');
  buf.writeUInt32LE(dataSize, 40);
  frames.copy(buf, 44);
  fs.writeFileSync(filePath, buf);
  return fs.statSync(filePath).size;
}

function normalize(samples, peak) {
  let m = 0.0;
  for (let i = 0; i < samples.length; i++) {
    const a = samples[i] >= 0 ? samples[i] : -samples[i];
    if (a > m) m = a;
  }
  if (m <= 1e-9) return samples;
  const g = peak / m;
  const out = new Array(samples.length);
  for (let i = 0; i < samples.length; i++) out[i] = samples[i] * g;
  return out;
}

function secs(d) { return mx(1, pyRound(SR * d)); }

function linEnv(i, n, atk, rel) {
  if (atk > 0 && i < atk) return i / atk;
  if (rel > 0 && i >= n - rel) {
    const v = (n - i) / rel;
    return v > 0.0 ? v : 0.0;
  }
  return 1.0;
}

function resonatorBank(signal, centers, bandwidth) {
  bandwidth = (bandwidth === undefined) ? 120.0 : bandwidth;
  const n = signal.length;
  const wide = new Array(n).fill(0.0);
  for (let c = 0; c < centers.length; c++) {
    const f = centers[c];
    const R = Math.exp(-PI * bandwidth / SR);
    const theta = 2.0 * PI * f / SR;
    const a1 = 2.0 * R * Math.cos(theta);
    const a2 = -(R * R);
    const b0 = 1.0 - R;
    let y1 = 0.0, y2 = 0.0;
    for (let i = 0; i < n; i++) {
      const x = signal[i];
      const y = b0 * x + a1 * y1 + a2 * y2;
      y2 = y1; y1 = y;
      wide[i] += y;
    }
  }
  return wide;
}

function smooth(sig, radius) {
  if (radius <= 0) return sig.slice();
  const n = sig.length;
  const out = new Array(n).fill(0.0);
  const win = 2 * radius + 1;
  let acc = 0.0;
  for (let i = 0; i < n; i++) {
    acc += sig[i];
    if (i - win >= 0) acc -= sig[i - win];
    let lo = i - radius; if (lo < 0) lo = 0;
    let hi = i + radius; if (hi > n - 1) hi = n - 1;
    out[i] = acc / (hi - lo + 1);
  }
  return out;
}

function gen_ui_click() {
  const n = secs(0.05);
  const rnd = new MTRandom(SEED + 1);
  const out = new Array(n).fill(0.0);
  const a_noise = Math.exp(-1.0 / (0.004 * SR));
  let env = 1.0;
  let ph = 0.0;
  const f = 2000.0;
  const dph = 2.0 * PI * f / SR;
  for (let i = 0; i < n; i++) {
    out[i] += rnd.uniform(-1.0, 1.0) * env * 0.7;
    out[i] += Math.sin(ph) * env * 0.4;
    ph += dph;
    env *= a_noise;
  }
  return normalize(out, 0.85);
}

function gen_squelch() {
  const n = secs(0.25);
  const rnd = new MTRandom(SEED + 2);
  const out = new Array(n).fill(0.0);
  const atk = mx(1, tr(SR * 0.004));
  const decay = Math.exp(-1.0 / (0.055 * SR));
  let brown = 0.0;
  let env = 0.0;
  for (let i = 0; i < n; i++) {
    env *= decay;
    if (i < atk) env += (1.0 - env) * (i / atk);
    const wn = rnd.uniform(-1.0, 1.0);
    brown = brown + 0.02 * rnd.uniform(-1.0, 1.0);
    if (brown > 1.0) brown = 1.0;
    else if (brown < -1.0) brown = -1.0;
    out[i] = (0.75 * wn + 0.9 * brown) * env;
  }
  return normalize(out, 0.9);
}

function gen_call_tone() {
  const n = secs(0.35);
  const half = fl(n / 2);
  const out = new Array(n).fill(0.0);
  const atk = mx(1, tr(SR * 0.008));
  const rel = mx(1, tr(SR * 0.02));
  let ph = 0.0;
  for (let i = 0; i < n; i++) {
    const f = (i < half) ? 1200.0 : 900.0;
    ph += (2.0 * PI * f) / SR;
    out[i] = Math.sin(ph) * linEnv(i, n, atk, rel);
  }
  return normalize(out, 0.85);
}

function gen_chatter() {
  const n = secs(2.5);
  const rnd = new MTRandom(SEED + 4);
  const noise = new Array(n);
  for (let i = 0; i < n; i++) noise[i] = rnd.uniform(-1.0, 1.0);
  const bands = resonatorBank(noise, [300.0, 1000.0, 2500.0], 140.0);
  let raw = new Array(n);
  for (let i = 0; i < n; i++) raw[i] = rnd.random();
  raw = smooth(raw, tr(SR * 0.03));
  const env = smooth(raw, tr(SR * 0.05));
  const words = 12;
  const wlen = fl(n / words);
  for (let w = 0; w < words; w++) {
    const start = w * wlen;
    if (w % 2 === 1) {
      const gap = tr(wlen * 0.35);
      for (let i = start; i < mn(start + gap, n); i++) env[i] *= 0.05;
    }
  }
  const out = new Array(n).fill(0.0);
  for (let i = 0; i < n; i++) {
    const g = clamp(env[i], 0.0, 1.0);
    out[i] = bands[i] * (0.25 + 1.0 * g) + noise[i] * 0.05;
  }
  return normalize(out, 0.82);
}

function gen_engine() {
  const n = secs(1.5);
  const rnd = new MTRandom(SEED + 5);
  const out = new Array(n).fill(0.0);
  const base = 120.0;
  let ph1 = 0.0, ph2 = 0.0, ph3 = 0.0, ph4 = 0.0, phw = 0.0;
  const d1 = 2.0 * PI * base / SR;
  const d2 = 2.0 * PI * (2 * base) / SR;
  const d3 = 2.0 * PI * (3 * base) / SR;
  const d4 = 2.0 * PI * (4 * base) / SR;
  for (let i = 0; i < n; i++) {
    const t = i / SR;
    const wf = 1200.0 + 250.0 * Math.sin(2.0 * PI * (t / 1.5)) + 40.0 * Math.sin(2.0 * PI * 7.0 * t);
    const dw = 2.0 * PI * wf / SR;
    ph1 += d1; ph2 += d2; ph3 += d3; ph4 += d4; phw += dw;
    const varr = 1.0 + 0.05 * rnd.uniform(-1.0, 1.0) + 0.03 * Math.sin(2.0 * PI * (t / 1.5));
    const s = 0.55 * Math.sin(ph1) + 0.30 * Math.sin(ph2) + 0.20 * Math.sin(ph3)
      + 0.10 * Math.sin(ph4) + 0.22 * Math.sin(phw);
    out[i] = s * varr;
  }
  return normalize(out, 0.85);
}

function gen_flyby() {
  const n = secs(2.5);
  const rnd = new MTRandom(SEED + 6);
  const out = new Array(n).fill(0.0);
  const f0 = 150.0;
  let ph = 0.0;
  for (let i = 0; i < n; i++) {
    const t = i / n;
    const bump = Math.sin(PI * t);
    const f = f0 * (1.0 + 0.45 * bump);
    const amp = Math.pow(bump, 0.8);
    const dph = 2.0 * PI * f / SR;
    ph += dph;
    const nz = rnd.uniform(-1.0, 1.0) * 0.05;
    out[i] = (0.85 * Math.sin(ph) + 0.15 * Math.sin(2.0 * ph) + nz) * amp;
  }
  const fade = mx(1, tr(SR * 0.05));
  for (let i = 0; i < fade; i++) {
    out[i] *= i / fade;
    out[n - 1 - i] *= i / fade;
  }
  return normalize(out, 0.92);
}

function gen_gear() {
  const n = secs(0.4);
  const rnd = new MTRandom(SEED + 7);
  const out = new Array(n).fill(0.0);
  let ph = 0.0;
  const decay = Math.exp(-1.0 / (0.10 * SR));
  let env = 1.0;
  for (let i = 0; i < n; i++) {
    const t = i / n;
    const f = 60.0 - 20.0 * t;
    ph += 2.0 * PI * f / SR;
    out[i] += 0.9 * Math.sin(ph) * env;
    env *= decay;
  }
  const click = mx(1, tr(SR * 0.02));
  let ce = 1.0;
  const cd = Math.exp(-1.0 / (0.006 * SR));
  for (let i = 0; i < click; i++) {
    out[i] += rnd.uniform(-1.0, 1.0) * ce * 0.6;
    ce *= cd;
  }
  return normalize(out, 0.9);
}

function gen_stall() {
  const n = secs(0.5);
  const out = new Array(n).fill(0.0);
  const on = tr(SR * 0.09);
  const off = tr(SR * 0.06);
  let ph = 0.0;
  const dph = 2.0 * PI * 800.0 / SR;
  let i = 0;
  let onPhase = true;
  while (i < n) {
    const seg = onPhase ? on : off;
    if (onPhase) {
      const lim = mn(seg, n - i);
      for (let k = 0; k < lim; k++) {
        const j = i + k;
        const e = linEnv(k, seg, mx(1, tr(SR * 0.006)), mx(1, tr(SR * 0.006)));
        out[j] += Math.sin(ph) * e;
        ph += dph;
      }
    } else {
      ph += dph * seg;
    }
    i += seg;
    onPhase = !onPhase;
  }
  return normalize(out, 0.85);
}

function gen_alarm() {
  const n = secs(1.0);
  const out = new Array(n).fill(0.0);
  const beep = tr(SR * 0.13);
  const gap = tr(SR * 0.20);
  const dph = 2.0 * PI * 1000.0 / SR;
  let ph = 0.0;
  let pos = 0;
  for (let b = 0; b < 3; b++) {
    if (pos >= n) break;
    const end = mn(pos + beep, n);
    for (let j = pos; j < end; j++) {
      const e = linEnv(j - pos, end - pos, mx(1, tr(SR * 0.008)), mx(1, tr(SR * 0.12)));
      ph += dph;
      out[j] += Math.sin(ph) * e;
    }
    pos = end + gap;
  }
  return normalize(out, 0.9);
}

function gen_beacon() {
  const n = secs(1.2);
  const out = new Array(n).fill(0.0);
  const dph = 2.0 * PI * 1300.0 / SR;
  const dot = tr(SR * 0.15);
  const dash = tr(SR * 0.40);
  const intra = tr(SR * 0.06);
  const seq = [[1, dot], [0, intra], [1, dot], [0, intra], [1, dash]];
  let ph = 0.0;
  let pos = 0;
  for (let s = 0; s < seq.length; s++) {
    const state = seq[s][0];
    const dur = seq[s][1];
    const end = mn(pos + dur, n);
    for (let j = pos; j < end; j++) {
      if (state) {
        const e = linEnv(j - pos, dur, mx(1, tr(SR * 0.006)), mx(1, tr(SR * 0.006)));
        out[j] += Math.sin(ph) * e;
      }
      ph += dph;
    }
    pos = end;
    if (pos >= n) break;
  }
  return normalize(out, 0.85);
}

const FILES = [
  ['ui-click.wav', gen_ui_click],
  ['squelch.wav', gen_squelch],
  ['call-tone.wav', gen_call_tone],
  ['chatter.wav', gen_chatter],
  ['engine.wav', gen_engine],
  ['flyby.wav', gen_flyby],
  ['gear.wav', gen_gear],
  ['stall.wav', gen_stall],
  ['alarm.wav', gen_alarm],
  ['beacon.wav', gen_beacon],
];

function main() {
  fs.mkdirSync(OUT_DIR, { recursive: true });
  let total = 0;
  for (let i = 0; i < FILES.length; i++) {
    const name = FILES[i][0];
    const fn = FILES[i][1];
    const fp = path.join(OUT_DIR, name);
    const samples = fn();
    const size = writeWav(fp, samples);
    total += 1;
    const dur = samples.length / SR;
    console.log(name.padEnd(14) + ' ' + String(size).padStart(8) +
      ' bytes  (' + dur.toFixed(2) + 's, ' + samples.length + ' frames)');
  }
  console.log('----');
  console.log('Generated ' + total + ' files in ' + OUT_DIR);
  return 0;
}

if (require.main === module) {
  process.exit(main());
}
module.exports = { MTRandom };
