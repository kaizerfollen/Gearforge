"""Ore overlays: ore_<resource>_<stage> (stage 0 sparse .. 7 dense), 64x64 transparent, plus ore_crude_oil.

Chunks stay inside the tile (no seams); a fixed jittered layout per variant is revealed progressively, so higher
stages are supersets of lower ones and grow slightly larger.
"""
from __future__ import annotations

import math

import numpy as np

from .base import OUT
from .common import (Canvas, P, add_grit, alpha, circle, ellipse, fill, fill_grad, hexc, lin, rad, rng, shade,
                     stroke, with_shadow, poly)

ORES = {
    #             base,              highlight,         accent (speckles / crystals)
    'iron_ore': (hexc('#5d7389'), hexc('#a9c0d4'), hexc('#2f3d4a')),
    'copper_ore': (hexc('#b8622f'), hexc('#f0a066'), hexc('#3fa58a')),
    'coal': (hexc('#2a2b2f'), hexc('#6c7078'), hexc('#121315')),
    'stone': (hexc('#a8916c'), hexc('#dccaa4'), hexc('#6b5a42')),
    'uranium_ore': (hexc('#4b4f49'), hexc('#9aa595'), hexc('#a6ff4d')),
}


def chunk(ctx, cx, cy, r, base, hi, r_: np.random.RandomState, n=None, flat=0.8, facets=True):
    """An irregular faceted rock seen from above, lit from the top-left."""
    n = n or r_.randint(6, 9)
    a0 = r_.uniform(0, math.tau)
    pts = []
    for i in range(n):
        a = a0 + i * math.tau / n + r_.uniform(-0.25, 0.25)
        rr = r * r_.uniform(0.75, 1.1)
        pts.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr * flat))
    poly(ctx, pts)
    fill_grad(ctx, lin(cx - r, cy - r, cx + r, cy + r, [(0, shade(base, 1.25)), (0.55, base), (1, shade(base, 0.5))]))
    if facets:
        # a lit top facet
        k = r_.uniform(0.35, 0.5)
        tx, ty = cx - r * 0.18, cy - r * 0.2
        fpts = [(tx + (x - cx) * k, ty + (y - cy) * k) for (x, y) in pts]
        poly(ctx, fpts)
        fill_grad(ctx, lin(tx - r * k, ty - r * k, tx + r * k, ty + r * k, [(0, shade(hi, 1.1)), (1, shade(base, 1.05))]))
        for (p, q) in zip(pts, fpts):
            if p[0] + p[1] < cx + cy:   # only edges toward the light
                ctx.move_to(*p); ctx.line_to(*q)
                stroke(ctx, alpha(hi, 0.35), 0.7)
    poly(ctx, pts)
    stroke(ctx, alpha(OUT, 0.9), 1.0)
    return pts


def layout(seed, n=25, margin=7):
    r = rng(seed)
    pts = []
    # jittered 5x5 grid, shuffled so reveal order is spread
    for gy in range(5):
        for gx in range(5):
            x = margin + (gx + 0.5) * (64 - 2 * margin) / 5 + r.uniform(-3.5, 3.5)
            y = margin + (gy + 0.5) * (64 - 2 * margin) / 5 + r.uniform(-3.5, 3.5)
            pts.append((x, y))
    order = r.permutation(len(pts))
    return [pts[i] for i in order[:n]]


def ore_image(res, stage):
    base, hi, acc = ORES[res]
    cv = Canvas(64, 64)
    ctx = cv.ctx
    pts = layout('ore' + res)
    count = [3, 6, 9, 12, 15, 18, 21, 25][stage]
    scale = 0.8 + stage * 0.06
    r_ = rng(f'ore{res}{stage}')
    # tinted ground stain under the chunks (reads as an ore field from afar)
    for i, (x, y) in enumerate(pts[:count]):
        circle(ctx, x, y, 9 + stage * 0.6)
        fill_grad(ctx, rad(x, y, 0, 9 + stage * 0.6, [(0, alpha(shade(base, 0.7), 0.28)), (1, alpha(shade(base, 0.7), 0))]))
    for i, (x, y) in enumerate(pts[:count]):
        rr = rng(f'{res}chunk{i}')
        rad_ = (4.6 + rr.uniform(0, 3.4)) * scale
        chunk(ctx, x, y, rad_, shade(base, rr.uniform(0.9, 1.1)), hi, rr)
        if res == 'copper_ore' and rr.rand() < 0.5:
            circle(ctx, x + rad_ * 0.25, y + rad_ * 0.2, rad_ * 0.28)
            fill(ctx, alpha(acc, 0.9))
        if res == 'uranium_ore':
            # glowing crystal shards
            for k in range(2):
                a = rr.uniform(0, math.tau)
                px, py = x + math.cos(a) * rad_ * 0.35, y + math.sin(a) * rad_ * 0.3
                circle(ctx, px, py, rad_ * 0.9)
                fill_grad(ctx, rad(px, py, 0, rad_ * 0.9, [(0, alpha(acc, 0.35)), (1, alpha(acc, 0))]))
                poly(ctx, [(px, py - rad_ * 0.45), (px + rad_ * 0.22, py), (px, py + rad_ * 0.35), (px - rad_ * 0.22, py)])
                fill(ctx, shade(acc, 1.2), preserve=True)
                stroke(ctx, alpha(OUT, 0.7), 0.6)
        if res == 'coal':
            # glossy sheen
            ctx.move_to(x - rad_ * 0.5, y - rad_ * 0.1); ctx.line_to(x - rad_ * 0.1, y - rad_ * 0.5)
            stroke(ctx, alpha(hexc('#c9d0dc'), 0.6), 1.0)
    # tiny pebbles/dust in between (more with density)
    for k in range(4 + stage * 2):
        x, y = r_.uniform(6, 58), r_.uniform(6, 58)
        circle(ctx, x, y, r_.uniform(0.9, 1.7))
        fill(ctx, alpha(shade(base, r_.uniform(0.7, 1.2)), 0.9))
    img = add_grit(cv.pil(), 0.03, 'ore' + res)
    return with_shadow(img, 1.5, 2, 1.0, 0.55)


def crude_oil():
    cv = Canvas(64, 64)
    ctx = cv.ctx
    r = rng('crude')
    # dark stain
    ellipse(ctx, 32, 33, 26, 22)
    fill_grad(ctx, rad(32, 33, 4, 27, [(0, alpha(hexc('#0b0b0d'), 0.85)), (0.7, alpha(hexc('#16151a'), 0.55)), (1, alpha(hexc('#16151a'), 0))]))
    # puddle blobs
    for (x, y, rx, ry) in ((32, 32, 15, 12), (22, 40, 7, 5), (43, 24, 6, 4.5)):
        ellipse(ctx, x, y, rx, ry)
        fill_grad(ctx, rad(x - rx * 0.3, y - ry * 0.4, 0, rx * 1.1, [(0, hexc('#2c2a33')), (1, hexc('#08080a'))]))
        ellipse(ctx, x, y, rx, ry)
        stroke(ctx, alpha(OUT, 0.9), 1.0)
    # iridescent sheen arcs
    for (c, off) in ((hexc('#7a5cc8'), 0), (hexc('#3fa0b0'), 1.6), (hexc('#c8a040'), 3.2)):
        ctx.save(); ctx.translate(30, 29); ctx.scale(1, 0.75)
        ctx.arc(0, 0, 8 + off, math.pi * 1.05, math.pi * 1.55)
        ctx.restore()
        stroke(ctx, alpha(c, 0.55), 1.1)
    # marker ring
    ctx.save(); ctx.translate(32, 32); ctx.scale(1, 0.85)
    ctx.arc(0, 0, 27, 0, math.tau)
    ctx.restore()
    ctx.set_dash([4, 3])
    stroke(ctx, alpha(hexc('#2a2830'), 0.7), 1.6)
    ctx.set_dash([])
    return cv.pil()


def generate(reg, data):
    for res in ORES:
        for s in range(8):
            reg.add(f'ore_{res}_{s}', ore_image(res, s), 'ores')
    reg.add('ore_crude_oil', crude_oil(), 'ores')
