#!/usr/bin/env python3
# Procedural sound generator for the atc-ai-traffic addon.
# Uses ONLY the Python standard library (wave, struct, math, random, os).
# Emits 9 standard 16-bit PCM MONO .wav files at SR=22050 Hz into ../Sounds.
# Regenerate with:  python3 Tools/generate_sounds.py

import wave
import struct
import math
import random
import os

SR = 22050                 # sample rate (mono)
SEED = 20240101            # fixed seed -> reproducible assets
OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "Sounds")


# ----------------------------------------------------------------------------
# Low level helpers
# ----------------------------------------------------------------------------
def clamp(x, lo=-1.0, hi=1.0):
    if x < lo:
        return lo
    if x > hi:
        return hi
    return x


def write_wav(path, samples):
    """Clamp floats to [-1,1] and write 16-bit PCM mono frames. Returns byte size."""
    frames = bytearray()
    ap = frames.extend
    pk = struct.pack
    for s in samples:
        iv = int(round(clamp(s) * 32767.0))
        if iv > 32767:
            iv = 32767
        elif iv < -32768:
            iv = -32768
        ap(pk("<h", iv))
    with wave.open(path, "wb") as w:
        w.setnchannels(1)        # mono
        w.setsampwidth(2)        # 16-bit
        w.setframerate(SR)
        w.writeframes(bytes(frames))
    return os.path.getsize(path)


def normalize(samples, peak=0.9):
    m = 0.0
    for x in samples:
        a = x if x >= 0 else -x
        if a > m:
            m = a
    if m <= 1e-9:
        return samples
    g = peak / m
    return [x * g for x in samples]


def secs(d):
    return max(1, int(round(SR * d)))


def lin_env(i, n, atk, rel):
    """Linear attack / release envelope (length of each phase in samples)."""
    if atk > 0 and i < atk:
        return i / float(atk)
    if rel > 0 and i >= n - rel:
        return max(0.0, (n - i) / float(rel))
    return 1.0


def resonator_bank(signal, centers, bandwidth=120.0):
    """Sum of simple 2nd-order bandpass resonators (constant-peak) at given Hz."""
    wide = [0.0] * len(signal)
    for f in centers:
        R = math.exp(-math.pi * bandwidth / SR)
        theta = 2.0 * math.pi * f / SR
        a1 = 2.0 * R * math.cos(theta)
        a2 = -(R * R)
        b0 = 1.0 - R
        y1 = 0.0
        y2 = 0.0
        for i, x in enumerate(signal):
            y = b0 * x + a1 * y1 + a2 * y2
            y2 = y1
            y1 = y
            wide[i] += y
    return wide


def smooth(sig, radius):
    if radius <= 0:
        return list(sig)
    n = len(sig)
    out = [0.0] * n
    # running-sum (box) smoothing -> gentle envelope
    win = 2 * radius + 1
    acc = 0.0
    for i in range(n):
        acc += sig[i]
        if i - win >= 0:
            acc -= sig[i - win]
        lo = i - radius
        if lo < 0:
            lo = 0
        hi = i + radius
        if hi > n - 1:
            hi = n - 1
        out[i] = acc / float(hi - lo + 1)
    return out


# ----------------------------------------------------------------------------
# Sound generators (each returns a list of float samples in [-1,1])
# ----------------------------------------------------------------------------
def gen_ui_click():
    """0.05s: bandpassed impulse click + tiny 2kHz blip."""
    n = secs(0.05)
    rnd = random.Random(SEED + 1)
    out = [0.0] * n
    a_noise = math.exp(-1.0 / (0.004 * SR))   # ~4 ms noise decay
    a_tone = math.exp(-1.0 / (0.010 * SR))     # ~10 ms blip decay
    env = 1.0
    ph = 0.0
    f = 2000.0
    dph = 2.0 * math.pi * f / SR
    for i in range(n):
        out[i] += rnd.uniform(-1.0, 1.0) * env * 0.7
        out[i] += math.sin(ph) * env * 0.4
        ph += dph
        env *= a_noise
    return normalize(out, 0.85)


def gen_squelch():
    """0.25s: white+brown noise burst, fast attack, exponential decay."""
    n = secs(0.25)
    rnd = random.Random(SEED + 2)
    out = [0.0] * n
    atk = max(1, int(SR * 0.004))
    decay = math.exp(-1.0 / (0.055 * SR))
    brown = 0.0
    env = 0.0
    for i in range(n):
        env *= decay
        if i < atk:
            env += (1.0 - env) * (i / float(atk))   # fast attack
        wn = rnd.uniform(-1.0, 1.0)
        brown = brown + 0.02 * rnd.uniform(-1.0, 1.0)  # leaky-integrator brown
        if brown > 1.0:
            brown = 1.0
        elif brown < -1.0:
            brown = -1.0
        out[i] = (0.75 * wn + 0.9 * brown) * env
    return normalize(out, 0.9)


def gen_call_tone():
    """0.35s: two-tone beep 1200Hz then 900Hz, framed envelope."""
    n = secs(0.35)
    half = n // 2
    out = [0.0] * n
    atk = max(1, int(SR * 0.008))
    rel = max(1, int(SR * 0.02))
    ph = 0.0
    for i in range(n):
        f = 1200.0 if i < half else 900.0
        ph += 2.0 * math.pi * f / SR
        out[i] = math.sin(ph) * lin_env(i, n, atk, rel)
    return normalize(out, 0.85)


def gen_chatter():
    """~2.5s: filtered-noise 'speech-like' chatter (NOT a pure tone)."""
    n = secs(2.5)
    rnd = random.Random(SEED + 4)
    noise = [rnd.uniform(-1.0, 1.0) for _ in range(n)]
    # three formant bands
    bands = resonator_bank(noise, [300.0, 1000.0, 2500.0], bandwidth=140.0)
    # syllabic envelope: random target amplitude, box-smoothed, chunked words/gaps
    raw = [rnd.random() for _ in range(n)]
    raw = smooth(raw, int(SR * 0.03))
    env = smooth(raw, int(SR * 0.05))
    # carve short silent gaps between 'words'
    words = 12
    wlen = n // words
    for w in range(words):
        start = w * wlen
        if w % 2 == 1:
            gap = int(wlen * 0.35)
            for i in range(start, min(start + gap, n)):
                env[i] *= 0.05
    # light noise floor so it reads as distant radio
    out = [0.0] * n
    dep = 0.0
    for i in range(n):
        g = clamp(env[i], 0.0, 1.0)
        out[i] = bands[i] * (0.25 + 1.0 * g) + noise[i] * 0.05
    return normalize(out, 0.82)


def gen_engine():
    """1.5s: looping engine whine (120/240/360 Hz harmonics + whine to ~1.5kHz)."""
    n = secs(1.5)
    rnd = random.Random(SEED + 5)
    out = [0.0] * n
    base = 120.0
    ph1 = ph2 = ph3 = ph4 = phw = 0.0
    d1 = 2.0 * math.pi * base / SR
    d2 = 2.0 * math.pi * (2 * base) / SR
    d3 = 2.0 * math.pi * (3 * base) / SR
    d4 = 2.0 * math.pi * (4 * base) / SR
    for i in range(n):
        t = i / float(SR)
        # whine slowly wanders 900..1500 Hz with slight vibrato
        wf = 1200.0 + 250.0 * math.sin(2.0 * math.pi * (t / 1.5)) + 40.0 * math.sin(2.0 * math.pi * 7.0 * t)
        dw = 2.0 * math.pi * wf / SR
        ph1 += d1; ph2 += d2; ph3 += d3; ph4 += d4; phw += dw
        # slight amplitude variance around a stable level
        var = 1.0 + 0.05 * rnd.uniform(-1.0, 1.0) + 0.03 * math.sin(2.0 * math.pi * (t / 1.5))
        s = 0.55 * math.sin(ph1) + 0.30 * math.sin(ph2) + 0.20 * math.sin(ph3) \
            + 0.10 * math.sin(ph4) + 0.22 * math.sin(phw)
        out[i] = s * var
    return normalize(out, 0.85)


def gen_flyby():
    """2.5s: doppler-ish pass. Pitch & loudness rise to a peak then fall."""
    n = secs(2.5)
    rnd = random.Random(SEED + 6)
    out = [0.0] * n
    f0 = 150.0
    ph = 0.0
    for i in range(n):
        t = i / float(n)          # 0..1 across the pass
        bump = math.sin(math.pi * t)           # 0->1->0
        f = f0 * (1.0 + 0.45 * bump)           # pitch rises then falls
        amp = pow(bump, 0.8)                    # loudness to peak then drop
        dph = 2.0 * math.pi * f / SR
        ph += dph
        nz = rnd.uniform(-1.0, 1.0) * 0.05
        out[i] = (0.85 * math.sin(ph) + 0.15 * math.sin(2.0 * ph) + nz) * amp
    # gentle head/tail fade so it starts/ends cleanly (still clearly gated)
    fade = max(1, int(SR * 0.05))
    for i in range(fade):
        out[i] *= i / float(fade)
        out[n - 1 - i] *= i / float(fade)
    return normalize(out, 0.92)


def gen_gear():
    """0.4s: mechanical thunk (sine 60->40Hz sweep) + noise click."""
    n = secs(0.4)
    rnd = random.Random(SEED + 7)
    out = [0.0] * n
    ph = 0.0
    decay = math.exp(-1.0 / (0.10 * SR))
    env = 1.0
    for i in range(n):
        t = i / float(n)
        f = 60.0 - 20.0 * t           # 60 -> 40 Hz
        ph += 2.0 * math.pi * f / SR
        out[i] += 0.9 * math.sin(ph) * env
        env *= decay
    # initial noise click (fast decay), like the latch
    click = max(1, int(SR * 0.02))
    ce = 1.0
    cd = math.exp(-1.0 / (0.006 * SR))
    for i in range(click):
        out[i] += rnd.uniform(-1.0, 1.0) * ce * 0.6
        ce *= cd
    return normalize(out, 0.9)


def gen_stall():
    """0.5s: intermittent 800Hz ding (on/off pattern)."""
    n = secs(0.5)
    out = [0.0] * n
    on = int(SR * 0.09)
    off = int(SR * 0.06)
    ph = 0.0
    dph = 2.0 * math.pi * 800.0 / SR
    i = 0
    on_phase = True
    while i < n:
        seg = on if on_phase else off
        if on_phase:
            for k in range(min(seg, n - i)):
                j = i + k
                e = lin_env(k, seg, max(1, int(SR * 0.006)), max(1, int(SR * 0.006)))
                out[j] += math.sin(ph) * e
                ph += dph
        else:
            ph += dph * seg   # keep phase advancing (muted)
        i += seg
        on_phase = not on_phase
    return normalize(out, 0.85)


def gen_alarm():
    """1.0s: repeating 1000Hz alarm, 3 beeps."""
    n = secs(1.0)
    out = [0.0] * n
    beep = int(SR * 0.13)
    gap = int(SR * 0.20)
    dph = 2.0 * math.pi * 1000.0 / SR
    ph = 0.0
    pos = 0
    for b in range(3):
        if pos >= n:
            break
        end = min(pos + beep, n)
        for j in range(pos, end):
            e = lin_env(j - pos, end - pos, max(1, int(SR * 0.008)), max(1, int(SR * 0.12)))
            ph += dph
            out[j] += math.sin(ph) * e
        pos = end + gap
    return normalize(out, 0.9)


def gen_beacon():
    """1.2s: marker-beacon morse 1300Hz, pattern short-short-long, steady tone."""
    n = secs(1.2)
    out = [0.0] * n
    dph = 2.0 * math.pi * 1300.0 / SR
    dot = int(SR * 0.15)
    dash = int(SR * 0.40)
    intra = int(SR * 0.06)
    # encode (state,dur): 1=on,0=off  -> short short long with gaps, then rest
    seq = [(1, dot), (0, intra), (1, dot), (0, intra), (1, dash)]
    ph = 0.0
    pos = 0
    for state, dur in seq:
        end = min(pos + dur, n)
        for j in range(pos, end):
            if state:
                e = lin_env(j - pos, dur, max(1, int(SR * 0.006)), max(1, int(SR * 0.006)))
                out[j] += math.sin(ph) * e
            ph += dph
        pos = end
        if pos >= n:
            break
    return normalize(out, 0.85)


# ----------------------------------------------------------------------------
# Build table (basename -> generator) and emit
# ----------------------------------------------------------------------------
FILES = [
    ("ui-click.wav", gen_ui_click),
    ("squelch.wav", gen_squelch),
    ("call-tone.wav", gen_call_tone),
    ("chatter.wav", gen_chatter),
    ("engine.wav", gen_engine),
    ("flyby.wav", gen_flyby),
    ("gear.wav", gen_gear),
    ("stall.wav", gen_stall),
    ("alarm.wav", gen_alarm),
    ("beacon.wav", gen_beacon),
]


def main():
    random.seed(SEED)
    os.makedirs(OUT_DIR, exist_ok=True)
    total = 0
    for name, fn in FILES:
        path = os.path.join(OUT_DIR, name)
        samples = fn()
        size = write_wav(path, samples)
        total += 1
        dur = len(samples) / float(SR)
        print("%-14s %8d bytes  (%.2fs, %d frames)" % (name, size, dur, len(samples)))
    print("----")
    print("Generated %d files in %s" % (total, OUT_DIR))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
