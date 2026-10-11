"""Terrain tiles: tile_<id>_v0..v3 (64x64, seamless, interchangeable variants).

Seamlessness: every tile is built from a *periodic* base field (FFT noise on a 64x64 torus) shared by all
variants, plus per-variant detail that is faded out near the borders. All four variants therefore share the
exact same border pixels and can be placed next to each other in any combination.
"""
from __future__ import annotations

import math

import numpy as np
from PIL import Image

from .common import (T, Canvas, P, alpha, circle, ellipse, fill, from_np, hexc, lin, fill_grad, pil_to_surf,
                     rng, shade, src, stroke, rrect)


def pnoise(r: np.random.RandomState, beta=2.0, size=T, cutoff=None):
    n = r.randn(size, size)
    F = np.fft.fft2(n)
    fx = np.fft.fftfreq(size)[:, None]
    fy = np.fft.fftfreq(size)[None, :]
    f = np.sqrt(fx ** 2 + fy ** 2)
    f[0, 0] = 1
    F = F / f ** (beta / 2)
    if cutoff is not None:
        F = F * np.exp(-(f / cutoff) ** 2)
    F[0, 0] = 0
    out = np.real(np.fft.ifft2(F))
    out = (out - out.mean()) / (out.std() + 1e-9)
    return out


def window(margin=12, size=T):
    x = np.arange(size) + 0.5
    d = np.minimum(x, size - x)
    t = np.clip((d - 2) / margin, 0, 1)
    t = t * t * (3 - 2 * t)
    return t[:, None] * t[None, :]


def ramp(v, colors):
    """Map v in [0,1] through a list of RGB colours (floats)."""
    v = np.clip(v, 0, 1) * (len(colors) - 1)
    i = np.clip(np.floor(v).astype(int), 0, len(colors) - 2)
    t = (v - i)[..., None]
    c = np.array([c[:3] for c in colors])
    return c[i] * (1 - t) + c[i + 1] * t


def relief(h, strength=0.12):
    """Top-left light on a height field (periodic gradient)."""
    gx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5
    gy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5
    # light from top-left: brighter where height decreases toward bottom-right
    l = -(gx + gy) / math.sqrt(2)
    return 1 + np.clip(l * strength, -0.35, 0.35)


def to_img(rgb):
    a = np.dstack([np.clip(rgb, 0, 1), np.ones(rgb.shape[:2])])
    return from_np(a)


def wrap_positions(x, y, pad=8):
    out = [(x, y)]
    for dx in (-T, 0, T):
        for dy in (-T, 0, T):
            if dx == 0 and dy == 0:
                continue
            xx, yy = x + dx, y + dy
            if -pad <= xx <= T + pad and -pad <= yy <= T + pad:
                out.append((xx, yy))
    return out


# ------------------------------------------------------------------------------------------- natural

NATURAL = {
    #            colours (dark -> light)                                   beta  grain  relief
    'grass_1':   (['#2f4a1f', '#3e5d26', '#4f722e', '#64873a'],          2.2, 0.05, 0.9),
    'grass_2':   (['#5a5528', '#6f6a33', '#857f40', '#9a9250'],          2.2, 0.05, 0.9),
    'dirt':      (['#4d3826', '#614731', '#77593d', '#8c6c4a'],          2.0, 0.06, 1.2),
    'sand':      (['#a48b5d', '#b59c6b', '#c6ae7c', '#d5bf8e'],          2.4, 0.04, 0.8),
    'red_desert': (['#6f3b20', '#874a29', '#9e5c34', '#b06d40'],         2.1, 0.05, 1.1),
    'landfill':  (['#3b352d', '#4a4238', '#595045', '#6a6054'],          1.8, 0.08, 1.4),
    'water':     (['#1a4d60', '#1f5a6f', '#256a80', '#2d7a90'],          2.8, 0.015, 0.0),
    'deep_water': (['#10323f', '#143c4b', '#184656', '#1d5162'],         2.8, 0.012, 0.0),
}


def natural_tile(tid: str, variant: int) -> Image.Image:
    cols, beta, grain, rel = NATURAL[tid]
    cols = [hexc(c) for c in cols]
    base_r = rng('tile:' + tid)
    vr = rng(f'tile:{tid}:v{variant}')
    th = window(16) * (math.pi / 2)
    cb, sb = np.cos(th), np.sin(th)          # variance-preserving blend: no contrast grid at the borders
    def blend(beta_):
        return pnoise(base_r, beta_) * cb + pnoise(vr, beta_) * sb
    h = blend(beta) * 0.45 + blend(1.3) * 0.35
    fine = blend(0.3)
    v = 0.5 + h * 0.17 + fine * grain
    rgb = ramp(v, cols)
    if rel > 0:
        rgb = rgb * relief(h * 3.0, 0.10 * rel)[..., None]
    img = to_img(rgb)
    # decorations
    cv = Canvas(T, T)
    ctx = cv.ctx
    ctx.set_source_surface(pil_to_surf(img), 0, 0)
    ctx.paint()
    deco = DECOR.get(tid)
    if deco:
        # shared wrap-around decorations (seamless) + per-variant interior decorations
        deco(ctx, rng('deco:' + tid), wrap=True, cols=cols)
        deco(ctx, vr, wrap=False, cols=cols)
    return cv.pil()


def _interior(r, n, margin=10):
    return [(margin + r.rand() * (T - 2 * margin), margin + r.rand() * (T - 2 * margin)) for _ in range(n)]


def _anywhere(r, n):
    return [(r.rand() * T, r.rand() * T) for _ in range(n)]


def deco_grass(ctx, r, wrap, cols, dry=False):
    n = 9 if wrap else 7
    pts = _anywhere(r, n) if wrap else _interior(r, n)
    for (x, y) in pts:
        kind = r.rand()
        tuft = []
        for _ in range(3 + r.randint(3)):
            a = -math.pi / 2 + (r.rand() - 0.5) * 1.2
            ln = 2.5 + r.rand() * 3.5
            ox = (r.rand() - 0.5) * 4
            tuft.append((ox, a, ln))
        lightc = shade(cols[3], 1.18 if not dry else 1.12)
        darkc = shade(cols[0], 0.8)
        for (px, py) in (wrap_positions(x, y) if wrap else [(x, y)]):
            for (ox, a, ln) in tuft:
                ctx.move_to(px + ox, py)
                ctx.line_to(px + ox + math.cos(a) * ln, py + math.sin(a) * ln)
                src(ctx, alpha(darkc, 0.55)); ctx.set_line_width(1.3); ctx.stroke()
                ctx.move_to(px + ox - 0.4, py - 0.4)
                ctx.line_to(px + ox - 0.4 + math.cos(a) * ln * 0.8, py - 0.4 + math.sin(a) * ln * 0.8)
                src(ctx, alpha(lightc, 0.55)); ctx.set_line_width(0.8); ctx.stroke()
            if not dry and not wrap and kind > 0.82:
                # tiny flower
                fc = [hexc('#e8d36a'), hexc('#e8e4d6'), hexc('#c98ad8')][r.randint(3)]
                circle(ctx, px + 1.5, py - 4, 1.1)
                fill(ctx, fc)


def deco_pebbles(ctx, r, wrap, cols, n_wrap=6, n_int=5, size=(1.0, 2.6), pc=None):
    n = n_wrap if wrap else n_int
    pts = _anywhere(r, n) if wrap else _interior(r, n)
    pc = pc or shade(cols[3], 1.08)
    for (x, y) in pts:
        rx = size[0] + r.rand() * (size[1] - size[0])
        ry = rx * (0.6 + r.rand() * 0.3)
        tone = 0.85 + r.rand() * 0.3
        for (px, py) in (wrap_positions(x, y) if wrap else [(x, y)]):
            ellipse(ctx, px + 0.8, py + 0.9, rx, ry)
            fill(ctx, alpha(shade(cols[0], 0.6), 0.5))
            ellipse(ctx, px, py, rx, ry)
            fill_grad(ctx, lin(px - rx, py - ry, px + rx, py + ry, [(0, shade(pc, tone * 1.15)), (1, shade(pc, tone * 0.75))]))


def deco_dirt(ctx, r, wrap, cols):
    deco_pebbles(ctx, r, wrap, cols, 6, 5, (0.9, 2.2), shade(cols[2], 1.15))
    if not wrap:
        # a few darker cracks / patches
        for _ in range(2):
            x, y = _interior(r, 1, 14)[0]
            ctx.move_to(x, y)
            for _ in range(3):
                x += (r.rand() - 0.5) * 8
                y += (r.rand() - 0.5) * 8
                ctx.line_to(x, y)
            stroke(ctx, alpha(shade(cols[0], 0.7), 0.45), 0.9)


def deco_sand(ctx, r, wrap, cols):
    # wind ripples
    if wrap:
        for i in range(4):
            y0 = 8 + i * 16 + r.rand() * 4
            for (px, py) in wrap_positions(0, y0, 0):
                pass
            ph = r.rand() * 2 * math.pi
            for oy in (-T, 0, T):
                ctx.move_to(-2, y0 + oy)
                for x in range(0, T + 4, 4):
                    ctx.line_to(x, y0 + oy + math.sin(x / T * 2 * math.pi * 2 + ph) * 2.0)
                stroke(ctx, alpha(shade(cols[3], 1.12), 0.35), 1.1)
                ctx.move_to(-2, y0 + 1.2 + oy)
                for x in range(0, T + 4, 4):
                    ctx.line_to(x, y0 + 1.2 + oy + math.sin(x / T * 2 * math.pi * 2 + ph) * 2.0)
                stroke(ctx, alpha(shade(cols[0], 0.85), 0.25), 0.8)
    deco_pebbles(ctx, r, wrap, cols, 3, 3, (0.7, 1.5), shade(cols[1], 0.9))


def deco_red(ctx, r, wrap, cols):
    deco_pebbles(ctx, r, wrap, cols, 6, 5, (1.0, 2.8), shade(cols[2], 1.1))


def deco_landfill(ctx, r, wrap, cols):
    deco_pebbles(ctx, r, wrap, cols, 14, 10, (0.8, 2.2), hexc('#77706a'))


def deco_water(ctx, r, wrap, cols, deep=False):
    n = 5 if wrap else 4
    pts = _anywhere(r, n) if wrap else _interior(r, n, 12)
    for (x, y) in pts:
        ln = 4 + r.rand() * 7
        for (px, py) in (wrap_positions(x, y, 12) if wrap else [(x, y)]):
            ctx.move_to(px - ln / 2, py)
            ctx.curve_to(px - ln / 4, py - 1.6, px + ln / 4, py - 1.6, px + ln / 2, py)
            stroke(ctx, alpha(hexc('#bfe6ee'), 0.22 if not deep else 0.12), 1.0)
            ctx.move_to(px - ln / 2 + 1, py + 1.2)
            ctx.curve_to(px - ln / 4, py + 0.2, px + ln / 4, py + 0.2, px + ln / 2 - 1, py + 1.2)
            stroke(ctx, alpha(shade(cols[0], 0.6), 0.25), 0.8)


DECOR = {
    'grass_1': deco_grass,
    'grass_2': lambda c, r, wrap, cols: deco_grass(c, r, wrap, cols, dry=True),
    'dirt': deco_dirt,
    'sand': deco_sand,
    'red_desert': deco_red,
    'landfill': deco_landfill,
    'water': deco_water,
    'deep_water': lambda c, r, wrap, cols: deco_water(c, r, wrap, cols, deep=True),
}


# ------------------------------------------------------------------------------------------- paved

def _grain_img(seed, variant, c_lo, c_hi, amount=0.05, beta=0.6):
    br = rng(seed)
    vr = rng(f'{seed}:v{variant}')
    th = window(12) * (math.pi / 2)
    n = pnoise(br, beta) * np.cos(th) + pnoise(vr, beta) * np.sin(th)
    m = pnoise(br, 2.0) * np.cos(th) + pnoise(vr, 2.0) * np.sin(th)
    v = 0.5 + n * amount + m * 0.08
    rgb = ramp(v, [c_lo, c_hi])
    return rgb, vr


def stone_path(variant: int) -> Image.Image:
    rgb, vr = _grain_img('stone_path', variant, hexc('#5a554c'), hexc('#8e877a'), 0.06)
    img = to_img(rgb)
    cv = Canvas(T, T)
    ctx = cv.ctx
    ctx.set_source_surface(pil_to_surf(img), 0, 0)
    ctx.paint()
    # 4 rows x 16 px, bricks never cross the tile border
    rows = [[(0, 32), (32, 64)], [(0, 16), (16, 48), (48, 64)], [(0, 32), (32, 64)], [(0, 16), (16, 48), (48, 64)]]
    br = rng('stone_path:bricks')
    for ri, row in enumerate(rows):
        y0 = ri * 16
        for (x0, x1) in row:
            interior = 8 < x0 and x1 < 56 and 0 < ri < 3
            rr = vr if interior else br
            tone = 0.9 + rr.rand() * 0.22
            c = shade(hexc('#7d766a'), tone)
            gx0 = x0 + (1.0 if x0 > 0 else 0.5)
            gx1 = x1 - (1.0 if x1 < 64 else 0.5)
            gy0, gy1 = y0 + 1.0, y0 + 15.0
            rrect(ctx, gx0, gy0, gx1 - gx0, gy1 - gy0, 2.5)
            ctx.save(); ctx.clip_preserve()
            src(ctx, alpha(c, 0.55)); ctx.fill()
            # bevel
            ctx.move_to(gx0, gy1); ctx.line_to(gx0, gy0); ctx.line_to(gx1, gy0)
            stroke(ctx, alpha(hexc('#d8d0bf'), 0.35), 1.6)
            ctx.move_to(gx1, gy0); ctx.line_to(gx1, gy1); ctx.line_to(gx0, gy1)
            stroke(ctx, alpha(hexc('#26231f'), 0.45), 1.6)
            ctx.restore()
    # grout darkening at the joints
    for ri in range(5):
        ctx.move_to(0, ri * 16); ctx.line_to(T, ri * 16)
    stroke(ctx, alpha(hexc('#2c2924'), 0.7), 1.2)
    for ri, row in enumerate(rows):
        for (x0, x1) in row:
            if x0 > 0:
                ctx.move_to(x0, ri * 16); ctx.line_to(x0, ri * 16 + 16)
    stroke(ctx, alpha(hexc('#2c2924'), 0.7), 1.2)
    # interior wear / cracks
    if variant:
        for _ in range(variant):
            x, y = 14 + vr.rand() * 36, 14 + vr.rand() * 36
            ctx.move_to(x, y)
            for _ in range(3):
                x += (vr.rand() - 0.5) * 7; y += (vr.rand() - 0.5) * 7
                ctx.line_to(x, y)
            stroke(ctx, alpha(hexc('#2c2924'), 0.5), 0.8)
    return cv.pil()


def concrete(variant: int, refined=False) -> Image.Image:
    if refined:
        rgb, vr = _grain_img('refined_concrete', variant, hexc('#45464a'), hexc('#5b5d61'), 0.025, 0.9)
    else:
        rgb, vr = _grain_img('concrete', variant, hexc('#62605b'), hexc('#7e7b74'), 0.07, 0.4)
    img = to_img(rgb)
    cv = Canvas(T, T)
    ctx = cv.ctx
    ctx.set_source_surface(pil_to_surf(img), 0, 0)
    ctx.paint()
    slabs = [(0, 0, 64, 64)] if refined else [(0, 0, 32, 32), (32, 0, 32, 32), (0, 32, 32, 32), (32, 32, 32, 32)]
    for (x, y, w, h) in slabs:
        # bevels: light top-left, dark bottom-right, half-pixel grooves shared with neighbours
        ctx.move_to(x + 0.5, y + h - 1); ctx.line_to(x + 0.5, y + 0.5); ctx.line_to(x + w - 1, y + 0.5)
        stroke(ctx, alpha(hexc('#ffffff'), 0.10 if refined else 0.14), 1.0)
        ctx.move_to(x + w - 0.5, y + 1); ctx.line_to(x + w - 0.5, y + h - 0.5); ctx.line_to(x + 1, y + h - 0.5)
        stroke(ctx, alpha(hexc('#141414'), 0.45 if refined else 0.5), 1.0)
    if refined:
        # subtle polished sheen + corner markers
        ctx.rectangle(0, 0, T, T)
        fill_grad(ctx, lin(0, 0, T, T, [(0, alpha(hexc('#ffffff'), 0.06)), (0.5, alpha(hexc('#ffffff'), 0.0)), (1, alpha(hexc('#000000'), 0.05))]))
        for (cx, cy) in ((6, 6), (58, 6), (6, 58), (58, 58)):
            circle(ctx, cx, cy, 1.1); fill(ctx, alpha(hexc('#1c1d20'), 0.6))
            circle(ctx, cx - 0.3, cy - 0.3, 0.6); fill(ctx, alpha(hexc('#9a9ca0'), 0.5))
    # interior stains/cracks per variant
    if variant:
        for k in range(variant):
            x, y = 16 + vr.rand() * 32, 16 + vr.rand() * 32
            if refined:
                ellipse(ctx, x, y, 4 + vr.rand() * 5, 3 + vr.rand() * 3)
                fill(ctx, alpha(hexc('#000000'), 0.05))
            else:
                ctx.move_to(x, y)
                for _ in range(3):
                    x += (vr.rand() - 0.5) * 9; y += (vr.rand() - 0.5) * 9
                    ctx.line_to(x, y)
                stroke(ctx, alpha(hexc('#2a2926'), 0.45), 0.8)
    return cv.pil()


def hazard_concrete(variant: int, refined=False) -> Image.Image:
    base = concrete(variant, refined)
    a = np.asarray(base).astype(np.float32) / 255
    yy, xx = np.mgrid[0:T, 0:T] + 0.5
    period = 32
    s = ((xx + yy) % period) / period
    stripe = (s < 0.5).astype(np.float32)
    # antialias edges
    d = np.minimum(np.abs(s - 0.0), np.abs(s - 0.5))
    d = np.minimum(d, np.abs(s - 1.0)) * period / math.sqrt(2)
    aa = np.clip(d / 0.8, 0, 1)
    stripe = stripe * aa + (1 - aa) * 0.5
    yellow = np.array(hexc('#d9a21f')[:3]) if not refined else np.array(hexc('#e2ab26')[:3])
    black = np.array(hexc('#222120')[:3])
    lum = a[..., :3].mean(-1, keepdims=True)
    lum = lum / lum.mean()
    col = yellow * stripe[..., None] + black * (1 - stripe[..., None])
    mixamt = 0.82 if refined else 0.75
    rgb = a[..., :3] * (1 - mixamt) + col * lum * mixamt
    # wear on non-refined: blotches reveal concrete
    if not refined:
        th = window(12) * (math.pi / 2)
        wear = pnoise(rng('hazard:wear'), 1.6) * np.cos(th) + pnoise(rng(f'hazard:wear:{variant}'), 1.6) * np.sin(th)
        w = np.clip((wear - 1.0) * 1.5, 0, 0.6)[..., None]
        rgb = rgb * (1 - w) + a[..., :3] * w
    out = np.dstack([rgb, np.ones((T, T))])
    img = from_np(out)
    # re-draw slab grooves on top
    cv = Canvas(T, T)
    ctx = cv.ctx
    ctx.set_source_surface(pil_to_surf(img), 0, 0)
    ctx.paint()
    slabs = [(0, 0, 64, 64)] if refined else [(0, 0, 32, 32), (32, 0, 32, 32), (0, 32, 32, 32), (32, 32, 32, 32)]
    for (x, y, w, h) in slabs:
        ctx.move_to(x + 0.5, y + h - 1); ctx.line_to(x + 0.5, y + 0.5); ctx.line_to(x + w - 1, y + 0.5)
        stroke(ctx, alpha(hexc('#ffffff'), 0.12), 1.0)
        ctx.move_to(x + w - 0.5, y + 1); ctx.line_to(x + w - 0.5, y + h - 0.5); ctx.line_to(x + 1, y + h - 0.5)
        stroke(ctx, alpha(hexc('#141414'), 0.5), 1.0)
    return cv.pil()


def tile_image(tid: str, variant: int) -> Image.Image:
    if tid in NATURAL:
        return natural_tile(tid, variant)
    if tid == 'stone_path':
        return stone_path(variant)
    if tid == 'concrete':
        return concrete(variant)
    if tid == 'refined_concrete':
        return concrete(variant, refined=True)
    if tid == 'hazard_concrete':
        return hazard_concrete(variant)
    if tid == 'refined_hazard_concrete':
        return hazard_concrete(variant, refined=True)
    raise KeyError(tid)


def generate(reg, data):
    for t in data['tiles']:
        for v in range(4):
            reg.add(f"tile_{t['id']}_v{v}", tile_image(t['id'], v), 'terrain')
