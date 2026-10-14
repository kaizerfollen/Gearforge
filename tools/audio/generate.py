#!/usr/bin/env python3
"""Gearforge procedural sound generator.

Synthesises every sound of the game from scratch (numpy + scipy, no samples, no downloads) and writes
16-bit mono WAV files into App/Resources/Sounds/ (copied into the app bundle as the folder reference
"Sounds").  Fully deterministic: every sound has its own fixed RNG seed, so re-running produces
bit-identical files.

    python3 tools/audio/generate.py            # generate all + verification table
    python3 tools/audio/generate.py --check    # only verify the files already on disk
    python3 tools/audio/generate.py --only ui_tap loop_belt

Design: calm industrial.  Soft transients, low-mid machine beds, modal (D dorian / A aeolian) music.

Seamless loops: machine loops and music are rendered *circularly* -- every tone has an integer number
of cycles per loop, noise is synthesised in the frequency domain (an inverse FFT is periodic by
construction), filters are run over three copies of the signal and the last copy is kept (steady state),
reverb is a circular FFT convolution and every event that would run past the end wraps around to the
start.  The last sample therefore flows into the first exactly as any two neighbouring samples do; no
crossfade (and no crossfade "dip") is needed.
"""
from __future__ import annotations

import argparse
import os
import sys
import wave

import numpy as np
from scipy import signal

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT_DIR = os.path.join(REPO, "App", "Resources", "Sounds")

SR = 44100          # one-shots and machine loops
MUSIC_SR = 16000    # music (see README: size budget)
TAU = 2.0 * np.pi

PEAK_LIMIT = 0.9
TOTAL_LIMIT = 6_000_000
MUSIC_FILE_LIMIT = 2_500_000

# --------------------------------------------------------------------------------------------- helpers


def taxis(dur: float, sr: int = SR) -> np.ndarray:
    return np.arange(int(round(dur * sr))) / sr


def nsamp(dur: float, sr: int = SR) -> int:
    return int(round(dur * sr))


def sos_bp(lo: float, hi: float, sr: int = SR, order: int = 2):
    return signal.butter(order, [lo, hi], btype="bandpass", fs=sr, output="sos")


def sos_lp(fc: float, sr: int = SR, order: int = 2):
    return signal.butter(order, fc, btype="lowpass", fs=sr, output="sos")


def sos_hp(fc: float, sr: int = SR, order: int = 2):
    return signal.butter(order, fc, btype="highpass", fs=sr, output="sos")


def filt(x: np.ndarray, sos) -> np.ndarray:
    return signal.sosfilt(sos, x)


def cfilt(x: np.ndarray, sos) -> np.ndarray:
    """Circular (steady-state) IIR filtering of a periodic signal."""
    n = len(x)
    return signal.sosfilt(sos, np.tile(x, 3))[2 * n:]


def bp(x, lo, hi, sr=SR, order=2):
    return filt(x, sos_bp(lo, hi, sr, order))


def lp(x, fc, sr=SR, order=2):
    return filt(x, sos_lp(fc, sr, order))


def hp(x, fc, sr=SR, order=2):
    return filt(x, sos_hp(fc, sr, order))


def white(rng, n):
    return rng.standard_normal(n)


def fft_noise(rng, n: int, sr: int, shape) -> np.ndarray:
    """Periodic coloured noise: random spectrum * shape(f) -> irfft.  Normalised to RMS 1."""
    f = np.fft.rfftfreq(n, 1.0 / sr)
    spec = (rng.standard_normal(len(f)) + 1j * rng.standard_normal(len(f))) * shape(f)
    spec[0] = 0.0
    x = np.fft.irfft(spec, n)
    r = np.sqrt(np.mean(x * x))
    return x / r if r > 0 else x


def band_shape(lo, hi, slope=2.0):
    """Smooth band-pass magnitude shape for fft_noise."""
    def shape(f):
        fs = np.maximum(f, 1e-3)
        return 1.0 / np.sqrt((1 + (lo / fs) ** (2 * slope)) * (1 + (fs / hi) ** (2 * slope)))
    return shape


def lp_shape(fc, slope=2.0, tilt=0.0):
    def shape(f):
        fs = np.maximum(f, 1e-3)
        return (1.0 / np.sqrt(1 + (fs / fc) ** (2 * slope))) * (np.maximum(fs, 20.0) / 20.0) ** (-tilt)
    return shape


def qf(f: float, loop: float) -> float:
    """Quantise a frequency so it completes an integer number of cycles per loop."""
    return max(1, round(f * loop)) / loop


def exp_env(t, tau):
    return np.exp(-t / tau)


def attack(t, a):
    """Raised-cosine attack of `a` seconds."""
    if a <= 0:
        return np.ones_like(t)
    x = np.clip(t / a, 0.0, 1.0)
    return 0.5 - 0.5 * np.cos(np.pi * x)


def hann_env(n):
    return np.hanning(n) if n > 2 else np.ones(n)


def smoothstep(x):
    x = np.clip(x, 0.0, 1.0)
    return x * x * (3 - 2 * x)


def sweep_phase(f_of_t: np.ndarray, sr: int = SR) -> np.ndarray:
    return TAU * np.cumsum(f_of_t) / sr


def modes(t, freqs, decays, amps):
    out = np.zeros_like(t)
    for f, d, a in zip(freqs, decays, amps):
        out += a * np.sin(TAU * f * t) * np.exp(-t / d)
    return out


def place(buf: np.ndarray, ev: np.ndarray, pos: int, wrap: bool) -> None:
    """Add `ev` into `buf` at sample `pos`; wrap around the end for loops, truncate otherwise."""
    n = len(buf)
    if wrap:
        idx = (pos + np.arange(len(ev))) % n
        np.add.at(buf, idx, ev)
    else:
        if pos >= n:
            return
        m = min(len(ev), n - pos)
        buf[pos:pos + m] += ev[:m]


def finalize_oneshot(x: np.ndarray, peak: float, sr: int = SR) -> np.ndarray:
    x = hp(x, 25.0, sr, order=2)
    fi = max(2, int(0.0015 * sr))
    fo = max(2, int(0.010 * sr))
    x[:fi] *= np.linspace(0.0, 1.0, fi)
    x[-fo:] *= 0.5 + 0.5 * np.cos(np.linspace(0, np.pi, fo))
    m = np.max(np.abs(x))
    return x * (peak / m) if m > 0 else x


def finalize_loop(x: np.ndarray, rms: float, peak_cap: float = 0.8, sr: int = SR) -> np.ndarray:
    x = cfilt(x - np.mean(x), sos_hp(20.0, sr))
    r = np.sqrt(np.mean(x * x))
    x = x * (rms / r)
    m = np.max(np.abs(x))
    if m > peak_cap:
        x *= peak_cap / m
    return x


def midi(m: float) -> float:
    return 440.0 * 2 ** ((m - 69) / 12)


# ------------------------------------------------------------------------------------------ one-shots


def s_ui_tap(rng):
    t = taxis(0.07)
    x = 0.6 * np.sin(TAU * 1800 * t) * exp_env(t, 0.012)
    x += 0.25 * np.sin(TAU * 3100 * t) * exp_env(t, 0.006)
    x += 0.3 * bp(white(rng, len(t)), 2000, 6000) * exp_env(t, 0.003)
    return finalize_oneshot(x, 0.42)


def _pluck(t, f, tau, h2=0.2, h3=0.0):
    e = attack(t, 0.004) * exp_env(t, tau)
    return e * (np.sin(TAU * f * t) + h2 * np.sin(TAU * 2 * f * t) + h3 * np.sin(TAU * 3 * f * t))


def _seq(dur, notes, sr=SR):
    """notes: list of (start, f, tau, amp)."""
    buf = np.zeros(nsamp(dur, sr))
    for st, f, tau, amp in notes:
        tt = taxis(dur - st, sr)
        place(buf, amp * _pluck(tt, f, tau), nsamp(st, sr), wrap=False)
    return buf


def s_ui_open(rng):
    x = _seq(0.24, [(0.0, midi(81), 0.05, 0.8), (0.055, midi(86), 0.07, 1.0)])
    t = taxis(0.24)
    x += 0.08 * bp(white(rng, len(t)), 1500, 5000) * attack(t, 0.03) * exp_env(t, 0.04)
    return finalize_oneshot(x, 0.45)


def s_ui_close(rng):
    x = _seq(0.24, [(0.0, midi(86), 0.05, 0.8), (0.055, midi(81), 0.07, 0.9)])
    t = taxis(0.24)
    x += 0.08 * bp(white(rng, len(t)), 1000, 3500) * attack(t, 0.03) * exp_env(t, 0.04)
    return finalize_oneshot(x, 0.40)


def s_ui_error(rng):
    dur = 0.34
    buf = np.zeros(nsamp(dur))
    for st, amp in ((0.0, 1.0), (0.16, 0.85)):
        t = taxis(0.13)
        w = np.zeros_like(t)
        for f in (146.8, 149.6):
            for k in (1, 3, 5, 7, 9):
                w += np.sin(TAU * f * k * t) / (k * k)
        e = attack(t, 0.008) * np.clip((0.13 - t) / 0.035, 0.0, 1.0)
        place(buf, amp * w * e, nsamp(st), wrap=False)
    buf = lp(buf, 1100, order=2)
    return finalize_oneshot(buf, 0.5)


def _bell(t, f, length=1.0):
    parts = [(1.0, 1.0, 0.65), (2.0, 0.32, 0.30), (3.0, 0.12, 0.16), (4.17, 0.07, 0.08), (5.43, 0.03, 0.05)]
    out = np.zeros_like(t)
    for r, a, d in parts:
        out += a * np.sin(TAU * f * r * t) * np.exp(-t / (d * length))
    return out * attack(t, 0.003)


def s_ui_success(rng):
    dur = 1.0
    buf = np.zeros(nsamp(dur))
    for st, m, amp, ln in ((0.0, 74, 0.75, 0.7), (0.11, 81, 0.75, 0.8), (0.22, 86, 0.9, 1.2)):
        t = taxis(dur - st)
        place(buf, amp * _bell(t, midi(m), ln), nsamp(st), wrap=False)
    return finalize_oneshot(buf, 0.6)


def s_ui_craft_done(rng):
    t = taxis(0.14)
    f = 300 + 700 * np.exp(-t / 0.02)
    x = np.sin(sweep_phase(f)) * attack(t, 0.002) * exp_env(t, 0.03)
    x += 0.15 * bp(white(rng, len(t)), 2000, 7000) * exp_env(t, 0.004)
    return finalize_oneshot(x, 0.5)


def _clunk(t, rng, base=1.0, metal=1.0):
    f = 60 * base + 60 * base * np.exp(-t / 0.03)
    x = np.sin(sweep_phase(f)) * exp_env(t, 0.09)
    x += metal * modes(t, [523 * base, 1187 * base, 1764 * base, 2410 * base, 3320 * base],
                       [0.12, 0.08, 0.06, 0.04, 0.03], [0.5, 0.35, 0.25, 0.15, 0.1])
    x += 0.5 * bp(white(rng, len(t)), 1500, 5000) * exp_env(t, 0.008)
    return x


def s_build_place(rng):
    dur = 0.42
    buf = np.zeros(nsamp(dur))
    place(buf, _clunk(taxis(dur), rng), 0, wrap=False)
    place(buf, 0.35 * _clunk(taxis(dur - 0.07), rng, base=1.12, metal=0.6), nsamp(0.07), wrap=False)
    return finalize_oneshot(buf, 0.8)


def s_build_remove(rng):
    dur = 0.38
    t = taxis(dur)
    n = len(t)
    mix = smoothstep(t / 0.3)
    x = (1 - mix) * bp(white(rng, n), 300, 900) + mix * 0.8 * bp(white(rng, n), 1500, 4000)
    e = (np.clip(t / 0.29, 0, 1) ** 2) * np.clip((dur - t) / 0.07, 0, 1)
    x *= e
    x += 0.35 * np.sin(sweep_phase(300 + 400 * np.clip(t / 0.3, 0, 1))) * e
    tick = taxis(dur - 0.3)
    place(x, 0.4 * modes(tick, [2200, 3400], [0.015, 0.01], [1, 0.5]), nsamp(0.3), wrap=False)
    return finalize_oneshot(x, 0.55)


def _click(t, rng, f=2600):
    x = bp(white(rng, len(t)), 2000, 6000) * exp_env(t, 0.003)
    x += 0.3 * np.sin(TAU * f * t) * exp_env(t, 0.01)
    x += 0.3 * np.sin(TAU * 400 * t) * exp_env(t, 0.015)
    return x


def s_rotate(rng):
    dur = 0.15
    buf = np.zeros(nsamp(dur))
    for i, (st, a) in enumerate(((0.0, 0.7), (0.035, 0.85), (0.07, 1.0))):
        place(buf, a * _click(taxis(dur - st), rng, 2400 + 150 * i), nsamp(st), wrap=False)
    return finalize_oneshot(buf, 0.5)


def s_paste(rng):
    dur = 0.34
    t = taxis(dur)
    buf = np.zeros(len(t))
    wl = nsamp(0.12)
    place(buf, 0.35 * bp(white(rng, wl), 800, 3000) * hann_env(wl), 0, wrap=False)
    for st, a in ((0.11, 0.8), (0.17, 1.0)):
        tt = taxis(dur - st)
        ev = 0.6 * np.sin(TAU * 120 * tt) * exp_env(tt, 0.04)
        ev += modes(tt, [700, 1600, 2500], [0.05, 0.035, 0.02], [0.5, 0.3, 0.15])
        ev += 0.3 * bp(white(rng, len(tt)), 2000, 6000) * exp_env(tt, 0.004)
        place(buf, a * ev, nsamp(st), wrap=False)
    return finalize_oneshot(buf, 0.6)


def s_mine_hit_ore(rng):
    dur = 0.28
    t = taxis(dur)
    x = 0.6 * hp(white(rng, len(t)), 2000) * exp_env(t, 0.004)
    x += modes(t, [2350, 3720, 5100], [0.06, 0.04, 0.025], [0.3, 0.2, 0.1])
    x += 0.5 * bp(white(rng, len(t)), 300, 1500) * exp_env(t, 0.03)
    x += 0.7 * np.sin(sweep_phase(80 + 40 * np.exp(-t / 0.02))) * exp_env(t, 0.05)
    for _ in range(5):
        st = rng.uniform(0.02, 0.12)
        gl = nsamp(0.012)
        place(x, rng.uniform(0.05, 0.15) * bp(white(rng, gl), 1500, 6000) * hann_env(gl), nsamp(st), wrap=False)
    return finalize_oneshot(x, 0.62)


def s_mine_hit_tree(rng):
    dur = 0.3
    t = taxis(dur)
    x = 0.5 * bp(white(rng, len(t)), 1000, 4000) * exp_env(t, 0.005)
    x += modes(t, [210, 480, 830, 1290], [0.07, 0.05, 0.035, 0.02], [0.6, 0.45, 0.3, 0.15])
    x += 0.4 * bp(white(rng, len(t)), 400, 1200) * exp_env(t, 0.025)
    x += 0.5 * np.sin(TAU * 90 * t) * exp_env(t, 0.04)
    return finalize_oneshot(x, 0.62)


def s_mine_done(rng):
    dur = 0.42
    buf = np.zeros(nsamp(dur))
    for i in range(12):
        st = rng.uniform(0.0, 0.18)
        gl = nsamp(rng.uniform(0.01, 0.03))
        a = 0.6 * (1 - st / 0.25) * rng.uniform(0.4, 1.0)
        place(buf, a * bp(white(rng, gl), 500, 3000) * hann_env(gl), nsamp(st), wrap=False)
    t = taxis(dur - 0.13)
    f = 420 + 420 * smoothstep(t / 0.05)
    place(buf, 0.6 * np.sin(sweep_phase(f)) * attack(t, 0.004) * exp_env(t, 0.06), nsamp(0.13), wrap=False)
    return finalize_oneshot(buf, 0.55)


def s_pickup(rng):
    x = _seq(0.2, [(0.0, midi(76), 0.04, 0.7), (0.055, midi(81), 0.05, 0.9)])
    return finalize_oneshot(x, 0.45)


def make_footstep(variant: int):
    def gen(rng):
        dur = 0.17
        t = taxis(dur)
        n = len(t)
        fc = [950, 1200, 1050, 1350][variant]
        x = lp(white(rng, n), fc, order=2) * attack(t, 0.006) * exp_env(t, 0.035)
        st = 0.03 + 0.007 * variant
        tt = taxis(dur - st)
        scuff = bp(white(rng, len(tt)), 2000, 6000) * attack(tt, 0.004) * exp_env(tt, 0.025)
        place(x, (0.15 + 0.03 * variant) * scuff, nsamp(st), wrap=False)
        x += 0.5 * np.sin(TAU * (66 + 6 * variant) * t) * attack(t, 0.004) * exp_env(t, 0.03)
        return finalize_oneshot(x, 0.32)
    return gen


def s_rocket_launch(rng):
    dur = 4.6
    t = taxis(dur)
    n = len(t)
    p = t / dur
    swell = smoothstep(t / 3.4) * np.clip((dur - t) / 1.3, 0, 1) ** 1.5
    brown = fft_noise(rng, n, SR, lp_shape(2000, 1.0, tilt=1.0))
    low = lp(brown, 120, order=2)
    mid = bp(brown, 120, 400) * smoothstep(p / 0.5)
    high = bp(white(rng, n), 400, 1500) * smoothstep((p - 0.25) / 0.45)
    hiss = bp(white(rng, n), 1500, 6000) * smoothstep((p - 0.45) / 0.3) * 0.25
    x = 1.0 * low / np.std(low) + 0.7 * mid / np.std(mid) + 0.35 * high / max(np.std(high), 1e-9) + hiss
    flutter = 1 + 0.12 * lp(white(rng, n), 9, order=2) / max(np.std(lp(white(rng, n), 9, order=2)), 1e-9)
    x *= flutter
    x += 1.4 * np.sin(sweep_phase(38 + 26 * smoothstep(p))) * smoothstep(t / 2.0)
    crack = np.zeros(n)
    k = int(150)
    for _ in range(k):
        u = rng.uniform(0, 1) ** 0.5
        st = nsamp(u * (dur - 0.5))
        gl = nsamp(rng.uniform(0.002, 0.006))
        crack[st:st + gl] += rng.exponential(0.6) * hann_env(gl) * white(rng, gl)
    x += 0.6 * hp(crack, 1200) * smoothstep(p / 0.6)
    x *= swell
    return finalize_oneshot(x, 0.85)


def s_alert(rng):
    dur = 0.75
    buf = np.zeros(nsamp(dur))
    for st, m, a in ((0.0, 81, 1.0), (0.22, 76, 0.9), (0.46, 76, 0.25)):
        t = taxis(0.2)
        w = np.sin(TAU * midi(m) * t) + np.sin(TAU * 3 * midi(m) * t) / 9
        e = attack(t, 0.01) * np.clip((0.2 - t) / 0.06, 0, 1)
        place(buf, a * w * e, nsamp(st), wrap=False)
    return finalize_oneshot(lp(buf, 4000), 0.55)


# -------------------------------------------------------------------------------------- machine loops


def _loop_events(n, rng, count, make, wrap=True, buf=None, jitter_range=(0.0, 1.0)):
    buf = np.zeros(n) if buf is None else buf
    for _ in range(count):
        pos = int(rng.uniform(*jitter_range) * n)
        place(buf, make(rng), pos, wrap)
    return buf


def l_assembler(rng):
    L = 1.2
    t = taxis(L)
    n = len(t)
    f0 = qf(98, L)
    x = np.zeros(n)
    for k, a in zip(range(1, 6), (1, 0.5, 0.25, 0.15, 0.08)):
        x += 0.25 * a * np.sin(TAU * f0 * k * t)
    am = (0.6 + 0.4 * np.sin(TAU * 8 * t / L)) ** 2
    x += 0.3 * fft_noise(rng, n, SR, band_shape(400, 1400)) * am
    for st, a in ((0.15, 1.0), (0.75, 0.8)):
        tt = taxis(0.25)
        ev = modes(tt, [740, 1650, 2480], [0.05, 0.035, 0.02], [0.35, 0.2, 0.1])
        ev += 0.3 * np.sin(TAU * 140 * tt) * exp_env(tt, 0.03)
        ev *= attack(tt, 0.002)
        place(x, a * ev, nsamp(st), wrap=True)
    sl = nsamp(0.4)
    place(x, 0.25 * cfilt(white(rng, sl), sos_bp(200, 600)) * hann_env(sl), nsamp(0.4), wrap=True)
    return finalize_loop(x, 0.10)


def l_furnace(rng):
    L = 1.5
    t = taxis(L)
    n = len(t)
    roar = fft_noise(rng, n, SR, lp_shape(260, 1.5, tilt=0.5))
    am = 0.85 + 0.15 * np.sin(TAU * 1 * t / L) + 0.07 * np.sin(TAU * 3 * t / L + 1.0)
    x = roar * am
    flick = fft_noise(rng, n, SR, lp_shape(6, 2.0))
    flick = 0.5 + 0.5 * np.tanh(flick)
    x += 0.35 * fft_noise(rng, n, SR, band_shape(600, 2000)) * flick
    def crack(r):
        gl = nsamp(r.uniform(0.001, 0.004))
        return r.exponential(1.0) * hann_env(gl) * white(r, gl)
    cr = _loop_events(n, rng, 16, crack)
    x += 0.8 * cfilt(cr, sos_hp(2000))
    return finalize_loop(x, 0.11)


def l_drill(rng):
    L = 1.0
    t = taxis(L)
    n = len(t)
    f0 = qf(73, L)
    rot = 0.7 + 0.3 * np.sin(TAU * 6 * t / L)
    x = np.zeros(n)
    for k, a in zip(range(1, 6), (1, 0.6, 0.35, 0.2, 0.1)):
        x += 0.3 * a * np.sin(TAU * f0 * k * t)
    x *= rot
    grind = fft_noise(rng, n, SR, band_shape(700, 2500)) * (0.4 + 0.6 * np.abs(np.sin(np.pi * 6 * t / L)) ** 1.5)
    x += 0.35 * grind
    x += 0.5 * fft_noise(rng, n, SR, lp_shape(180, 2.0))
    def tick(r):
        tl = taxis(0.03)
        return r.uniform(0.2, 0.5) * np.sin(TAU * r.uniform(1800, 3200) * tl) * exp_env(tl, 0.006)
    x += _loop_events(n, rng, 10, tick)
    return finalize_loop(x, 0.11)


def l_belt(rng):
    L = 1.0
    t = taxis(L)
    n = len(t)
    ticks = np.zeros(n)
    for i in range(20):
        pos = nsamp(i * L / 20 + rng.uniform(-0.005, 0.005)) % n
        tl = taxis(0.02)
        ev = bp(white(rng, len(tl)), 1500, 4500) * exp_env(tl, 0.002)
        ev += 0.2 * np.sin(TAU * rng.uniform(2000, 3500) * tl) * exp_env(tl, 0.004)
        place(ticks, rng.uniform(0.3, 1.0) * ev, pos, wrap=True)
    x = 0.6 * ticks
    x += 0.35 * fft_noise(rng, n, SR, lp_shape(150, 2.0))
    x += 0.12 * np.sin(TAU * qf(50, L) * t)
    for i in range(4):
        tl = taxis(0.06)
        place(x, 0.25 * np.sin(TAU * 110 * tl) * attack(tl, 0.003) * exp_env(tl, 0.015), nsamp(0.1 + i * 0.25), wrap=True)
    return finalize_loop(x, 0.06)


def l_steam_engine(rng):
    L = 1.2
    t = taxis(L)
    n = len(t)
    x = np.zeros(n)
    for st, a in ((0.05, 1.0), (0.35, 0.72), (0.65, 0.9), (0.95, 0.68)):
        tl = taxis(0.3)
        ch = bp(white(rng, len(tl)), 400, 1800) * attack(tl, 0.008) * exp_env(tl, 0.07)
        ch += 0.4 * bp(white(rng, len(tl)), 1800, 5000) * attack(tl, 0.004) * exp_env(tl, 0.03)
        ch += 0.9 * np.sin(TAU * 55 * tl) * attack(tl, 0.004) * exp_env(tl, 0.05)
        place(x, a * ch, nsamp(st), wrap=True)
    x += 0.05 * fft_noise(rng, n, SR, band_shape(2000, 6000))
    x += 0.1 * np.sin(TAU * qf(45, L) * t) * (0.7 + 0.3 * np.sin(TAU * 2 * t / L))
    return finalize_loop(x, 0.11)


def l_boiler(rng):
    L = 1.5
    t = taxis(L)
    n = len(t)
    x = fft_noise(rng, n, SR, lp_shape(200, 2.0, tilt=0.3))
    def bubble(r):
        d = r.uniform(0.015, 0.04)
        tl = taxis(d)
        f = r.uniform(180, 500)
        return r.uniform(0.1, 0.45) * np.sin(sweep_phase(f * (1 + 0.5 * tl / d))) * hann_env(len(tl))
    x += 1.2 * _loop_events(n, rng, 19, bubble)
    x += 0.06 * fft_noise(rng, n, SR, band_shape(3000, 7000))
    return finalize_loop(x, 0.09)


def l_inserter(rng):
    L = 1.0
    t = taxis(L)
    n = len(t)
    f0 = qf(520, L)
    dev = 140.0
    ph = TAU * f0 * t + dev * L * (1 - np.cos(TAU * t / L))
    whine = np.sin(ph) + 0.3 * np.sin(2 * ph) + 0.1 * np.sin(3 * ph)
    def gate(a, b, edge=0.04):
        return np.clip((t - a) / edge, 0, 1) * np.clip((b - t) / edge, 0, 1)
    g = gate(0.05, 0.40) + gate(0.55, 0.90)
    g = 0.5 - 0.5 * np.cos(np.pi * g)
    x = 0.5 * whine * g
    x += 0.3 * fft_noise(rng, n, SR, band_shape(800, 2500)) * g
    for st in (0.40, 0.90):
        tl = taxis(0.04)
        place(x, 0.5 * _click(tl, rng, 1800), nsamp(st), wrap=True)
    x += 0.06 * np.sin(TAU * qf(60, L) * t) + 0.03 * fft_noise(rng, n, SR, band_shape(300, 1200))  # idle hum
    x = cfilt(x, sos_lp(5000))
    return finalize_loop(x, 0.06)


def l_lab(rng):
    L = 1.5
    t = taxis(L)
    n = len(t)
    f1 = qf(110, L)
    x = np.sin(TAU * f1 * t) + 0.8 * np.sin(TAU * (f1 + 2 / L) * t)
    x += 0.3 * np.sin(TAU * qf(165, L) * t) + 0.25 * np.sin(TAU * qf(220, L) * t)
    x *= 0.3
    x += 0.04 * np.sin(TAU * qf(880, L) * t) * (0.5 + 0.5 * np.sin(TAU * 3 * t / L))
    pent = [midi(m) for m in (81, 84, 86, 88, 91, 93)]
    def bleep(r):
        tl = taxis(0.12)
        return 0.12 * np.sin(TAU * r.choice(pent) * tl) * attack(tl, 0.003) * exp_env(tl, 0.03)
    x += _loop_events(n, rng, 6, bleep)
    x += 0.03 * fft_noise(rng, n, SR, band_shape(1000, 4000))
    return finalize_loop(x, 0.07)


def l_pumpjack(rng):
    L = 2.0
    t = taxis(L)
    n = len(t)
    f0 = qf(48, L)
    x = np.zeros(n)
    for k, a in zip(range(1, 5), (1, 0.5, 0.25, 0.12)):
        x += 0.2 * a * np.sin(TAU * f0 * k * t)
    for st, a in ((0.25, 1.0), (1.25, 0.6)):
        tl = taxis(0.5)
        place(x, a * 0.8 * np.sin(TAU * 65 * tl) * attack(tl, 0.04) * exp_env(tl, 0.12), nsamp(st), wrap=True)
    cl = nsamp(0.35)
    creak = np.zeros(cl)
    pos, rate = 0.0, 35.0
    while pos < 0.35:
        gl = taxis(0.012)
        place(creak, np.sin(TAU * rng.uniform(800, 1000) * gl) * exp_env(gl, 0.003), nsamp(pos), wrap=False)
        pos += 1.0 / rate
        rate += 3.0
    creak = bp(creak, 600, 1400) * hann_env(cl)
    place(x, 0.5 * creak, nsamp(0.8), wrap=True)
    gurg = fft_noise(rng, n, SR, lp_shape(300, 2.0))
    mod = 0.5 + 0.5 * np.tanh(1.5 * fft_noise(rng, n, SR, lp_shape(5, 2.0)))
    x += 0.3 * gurg * mod
    return finalize_loop(x, 0.09)


# --------------------------------------------------------------------------------------------- music


def _pad_note(n_total: int, sr: int, start: float, length: float, f: float, amp: float,
              bright, att=3.0, rel=4.0) -> tuple[np.ndarray, int]:
    """Additive, detuned, band-limited pad note.  `bright(tabs)` gives brightness 0..1 at absolute time."""
    tl = taxis(length + rel, sr)
    tabs = (start + tl) % (n_total / sr)
    e = attack(tl, att) * np.where(tl < length, 1.0, 0.5 + 0.5 * np.cos(np.pi * np.clip((tl - length) / rel, 0, 1)))
    b = bright(tabs)
    out = np.zeros_like(tl)
    for det in (-0.0018, 0.0, 0.0021):
        fd = f * (1 + det)
        ph0 = (det + 0.003) * 1000.0
        for k in range(1, 9):
            if fd * k > sr * 0.42:
                break
            out += (1.0 / k ** 1.3) * (b ** (k - 1)) * np.sin(TAU * fd * k * tl + ph0 * k)
    return amp * out * e / 3.0, nsamp(start, sr)


def _arp_note(sr, f, amp, length=2.6):
    tl = taxis(length, sr)
    idx = 1.1 * np.exp(-tl / 0.25)
    ph = TAU * f * tl + idx * np.sin(TAU * 2 * f * tl)
    x = np.sin(ph) + 0.15 * np.sin(2 * TAU * f * tl)
    e = attack(tl, 0.006) * exp_env(tl, 0.55) * np.clip((length - tl) / 0.3, 0, 1)
    return amp * x * e


def _reverb_ir(rng, sr, rt=3.6, length=4.5):
    tl = taxis(length, sr)
    bright = lp(white(rng, len(tl)), 3500, sr)
    dark = lp(white(rng, len(tl)), 900, sr)
    mix = np.clip(tl / 1.5, 0, 1)
    ir = ((1 - mix) * bright + mix * dark) * np.exp(-6.91 * tl / rt) * attack(tl, 0.02)
    ir[0] += 0.0
    return ir / np.sqrt(np.sum(ir * ir))


def _circ_conv(x, ir):
    n = len(x)
    h = np.zeros(n)
    h[:len(ir)] = ir
    return np.fft.irfft(np.fft.rfft(x) * np.fft.rfft(h), n)


def render_music(rng, chords, root_midi_offset, step, arp_octave, arp_rest, bell_prob, dur=60.0, sr=MUSIC_SR):
    n = nsamp(dur, sr)
    chord_len = dur / len(chords)
    pad = np.zeros(n)
    bass = np.zeros(n)
    arp = np.zeros(n)
    m1 = rng.integers(1, 3)
    bright = lambda ta: 0.42 + 0.14 * np.sin(TAU * m1 * ta / dur) + 0.06 * np.sin(TAU * 5 * ta / dur + 0.7)
    for ci, notes in enumerate(chords):
        st = ci * chord_len
        for j, m in enumerate(notes):
            ev, pos = _pad_note(n, sr, st, chord_len, midi(m), 0.55 if j else 0.7, bright)
            place(pad, ev, pos, wrap=True)
        root = notes[0] + root_midi_offset
        tl = taxis(chord_len + 4.0, sr)
        e = attack(tl, 2.0) * np.where(tl < chord_len, 1.0, 0.5 + 0.5 * np.cos(np.pi * np.clip((tl - chord_len) / 4.0, 0, 1)))
        fb = midi(root)
        place(bass, (np.sin(TAU * fb * tl) + 0.25 * np.sin(TAU * 2 * fb * tl)) * e, nsamp(st, sr), wrap=True)
        tones = sorted(set((m % 12) for m in notes))
        base = 12 * arp_octave
        cand = sorted(base + p for p in tones) + sorted(base + 12 + p for p in tones)[:2]
        steps = int(round(chord_len / step))
        k = int(rng.integers(0, len(cand)))
        for s in range(steps):
            if rng.uniform() < arp_rest:
                continue
            k = (k + int(rng.choice([1, 1, 2, -1]))) % len(cand)
            vel = rng.uniform(0.45, 0.9) * (1.0 if s % 4 == 0 else 0.8)
            place(arp, _arp_note(sr, midi(cand[k]), vel), nsamp(st + s * step, sr), wrap=True)
        if rng.uniform() < bell_prob:
            tl = taxis(3.0, sr)
            place(arp, 0.35 * _bell(tl, midi(cand[-1] + 12), 2.5), nsamp(st + 0.5, sr), wrap=True)
    arp = cfilt(arp, sos_lp(4500, sr))
    d = nsamp(step * 1.5, sr)
    arp_echo = arp + 0.32 * np.roll(cfilt(arp, sos_lp(2500, sr)), d) + 0.14 * np.roll(cfilt(arp, sos_lp(1500, sr)), 2 * d)
    air = fft_noise(rng, n, sr, band_shape(300, 1800, 1.5))
    air *= 0.5 + 0.5 * np.sin(TAU * 3 * np.arange(n) / n)
    dry = 0.55 * pad / np.std(pad) + 0.28 * bass / np.std(bass) + 0.3 * arp_echo / np.std(arp_echo) + 0.03 * air
    ir = _reverb_ir(rng, sr)
    wet = _circ_conv(0.6 * pad / np.std(pad) + arp_echo / np.std(arp_echo), ir)
    x = dry + 0.45 * wet / np.std(wet) * np.std(dry) / 1.0 * 0.6
    x = cfilt(x - x.mean(), sos_hp(30, sr))
    return x * (0.7 / np.max(np.abs(x)))


def m_music_1(rng):
    # D dorian, unhurried: Dm9 - Fmaj7 - Am7 - G6 (the B natural gives the dorian colour).
    chords = [[50, 53, 57, 60, 64], [53, 57, 60, 64], [57, 60, 64, 67], [55, 59, 62, 64]]
    return render_music(rng, chords, -12, step=0.625, arp_octave=6, arp_rest=0.35, bell_prob=0.5)


def m_music_2(rng):
    # A aeolian, darker and sparser: Am(add9) - Fmaj7 - Dm9 - Em7.
    chords = [[57, 60, 64, 71], [53, 57, 60, 64], [50, 53, 57, 60, 64], [52, 55, 59, 62]]
    return render_music(rng, chords, -12, step=0.9375, arp_octave=6, arp_rest=0.45, bell_prob=0.75)


# ------------------------------------------------------------------------------------------ registry

# name -> (generator, seed, kind, sample rate)
SOUNDS: dict[str, tuple] = {}


def reg(name, fn, seed, kind="oneshot", sr=SR):
    SOUNDS[name] = (fn, seed, kind, sr)


reg("ui_tap", s_ui_tap, 101)
reg("ui_open", s_ui_open, 102)
reg("ui_close", s_ui_close, 103)
reg("ui_error", s_ui_error, 104)
reg("ui_success", s_ui_success, 105)
reg("ui_craft_done", s_ui_craft_done, 106)
reg("build_place", s_build_place, 201)
reg("build_remove", s_build_remove, 202)
reg("rotate", s_rotate, 203)
reg("paste", s_paste, 204)
reg("mine_hit_ore", s_mine_hit_ore, 301)
reg("mine_hit_tree", s_mine_hit_tree, 302)
reg("mine_done", s_mine_done, 303)
reg("pickup", s_pickup, 304)
for _i in range(4):
    reg(f"footstep_{_i + 1}", make_footstep(_i), 310 + _i)
reg("rocket_launch", s_rocket_launch, 501, kind="event")
reg("alert", s_alert, 502)
reg("loop_assembler", l_assembler, 401, kind="loop")
reg("loop_furnace", l_furnace, 402, kind="loop")
reg("loop_drill", l_drill, 403, kind="loop")
reg("loop_belt", l_belt, 404, kind="loop")
reg("loop_steam_engine", l_steam_engine, 405, kind="loop")
reg("loop_boiler", l_boiler, 406, kind="loop")
reg("loop_inserter", l_inserter, 407, kind="loop")
reg("loop_lab", l_lab, 408, kind="loop")
reg("loop_pumpjack", l_pumpjack, 409, kind="loop")
reg("music_1", m_music_1, 601, kind="music", sr=MUSIC_SR)
reg("music_2", m_music_2, 602, kind="music", sr=MUSIC_SR)


# ------------------------------------------------------------------------------------------------ io


def write_wav(path: str, x: np.ndarray, sr: int) -> None:
    pcm = np.round(np.clip(x, -1.0, 1.0) * 32767.0).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(pcm.tobytes())


def read_wav(path: str) -> tuple[np.ndarray, int, int, int]:
    with wave.open(path, "rb") as w:
        ch, sw, sr, nf = w.getnchannels(), w.getsampwidth(), w.getframerate(), w.getnframes()
        data = np.frombuffer(w.readframes(nf), dtype="<i2").astype(np.float64) / 32768.0
    return data, sr, ch, sw


DUR_LIMITS = {"oneshot": (0.03, 1.5), "event": (4.0, 6.0), "loop": (1.0, 3.0), "music": (60.0, 90.0)}


def verify() -> bool:
    ok = True
    total = 0
    rows = []
    for name, (_, _, kind, sr_expected) in SOUNDS.items():
        path = os.path.join(OUT_DIR, name + ".wav")
        if not os.path.exists(path):
            rows.append((name, kind, "-", "-", "-", "-", "-", "MISSING"))
            ok = False
            continue
        size = os.path.getsize(path)
        total += size
        x, sr, ch, sw = read_wav(path)
        dur = len(x) / sr
        peak = float(np.max(np.abs(x)))
        rms = float(np.sqrt(np.mean(x * x)))
        problems = []
        if ch != 1 or sw != 2 or sr != sr_expected:
            problems.append("format")
        if peak > PEAK_LIMIT:
            problems.append("clip")
        lo, hi = DUR_LIMITS[kind]
        if not (lo <= dur <= hi):
            problems.append("duration")
        seam = "-"
        if kind in ("loop", "music"):
            d = np.abs(np.diff(x))
            jump = abs(x[0] - x[-1])
            ref = float(np.percentile(d, 99.9))
            w = int(0.05 * sr)
            r_head = np.sqrt(np.mean(x[:w] ** 2))
            r_tail = np.sqrt(np.mean(x[-w:] ** 2))
            db = 20 * np.log10(max(r_head, 1e-9) / max(r_tail, 1e-9))
            seam = f"jump {jump:.4f}/p99.9 {ref:.4f} rms {db:+.1f}dB"
            # head/tail loudness only matters when the seam is not in a deliberate quiet gap
            loud = max(r_head, r_tail) > 0.01
            if jump > ref or (loud and abs(db) > 6.0):
                problems.append("seam")
        else:
            if abs(x[0]) > 0.01 or abs(x[-1]) > 0.01:
                problems.append("edges")
        if kind == "music" and size > MUSIC_FILE_LIMIT:
            problems.append("size")
        if problems:
            ok = False
        rows.append((name, kind, f"{sr}", f"{dur:6.2f}s", f"{peak:.3f}", f"{rms:.3f}", seam,
                     "OK" if not problems else "FAIL:" + ",".join(problems), size))
    print(f"{'sound':20} {'kind':8} {'rate':>6} {'dur':>8} {'peak':>6} {'rms':>6} {'size':>9}  {'loop seam':42} status")
    for r in rows:
        if len(r) == 8:
            print(f"{r[0]:20} {r[1]:8} {'':>6} {'':>8} {'':>6} {'':>6} {'':>9}  {'':42} {r[7]}")
        else:
            print(f"{r[0]:20} {r[1]:8} {r[2]:>6} {r[3]:>8} {r[4]:>6} {r[5]:>6} {r[8]:>9}  {r[6]:42} {r[7]}")
    stray = sorted(f for f in os.listdir(OUT_DIR) if f.endswith(".wav") and f[:-4] not in SOUNDS) if os.path.isdir(OUT_DIR) else []
    if stray:
        print("stray files (not generated by this script):", ", ".join(stray))
    print(f"total {total:,} bytes ({total / 1e6:.2f} MB) limit {TOTAL_LIMIT:,}")
    if total > TOTAL_LIMIT:
        ok = False
    print("verify OK" if ok else "verify FAILED")
    return ok


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--check", action="store_true", help="only verify existing files")
    ap.add_argument("--only", nargs="*", help="generate only these sounds")
    args = ap.parse_args()
    os.makedirs(OUT_DIR, exist_ok=True)
    if not args.check:
        names = args.only or list(SOUNDS)
        for name in names:
            if name not in SOUNDS:
                print(f"unknown sound {name}", file=sys.stderr)
                return 2
            fn, seed, _, sr = SOUNDS[name]
            x = fn(np.random.default_rng(seed))
            write_wav(os.path.join(OUT_DIR, name + ".wav"), x, sr)
    return 0 if verify() else 1


if __name__ == "__main__":
    sys.exit(main())
