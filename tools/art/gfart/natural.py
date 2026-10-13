"""Trees (round canopies) and rocks."""
from __future__ import annotations

import math

from .base import OUT, finish
from .common import Canvas, P, alpha, circle, fill, fill_grad, hexc, lin, rad, rng, shade, stroke
from .ores import chunk

TREES = {
    'tree_01': (hexc('#3f7f34'), hexc('#8fcf5c')),
    'tree_02': (hexc('#2f6a4a'), hexc('#6fbf86')),
    'tree_03': (hexc('#6f7f2a'), hexc('#d0c25a')),
}


def canopy(ctx, cx, cy, R, base, hi, r):
    # blobs around the rim + centre, drawn back-to-front (bottom-right first so lit lobes overlap)
    lobes = []
    n = 7
    for i in range(n):
        a = i * math.tau / n + r.uniform(-0.2, 0.2)
        d = R * r.uniform(0.48, 0.6)
        lobes.append((cx + math.cos(a) * d, cy + math.sin(a) * d, R * r.uniform(0.42, 0.52)))
    lobes.sort(key=lambda l: -(l[0] + l[1]))
    # dark silhouette
    for (x, y, rr) in lobes:
        circle(ctx, x, y, rr + 1.2)
        fill(ctx, OUT)
    circle(ctx, cx, cy, R * 0.62 + 1.2)
    fill(ctx, OUT)
    for (x, y, rr) in lobes:
        circle(ctx, x, y, rr)
        fill_grad(ctx, rad(x - rr * 0.35, y - rr * 0.35, rr * 0.1, rr * 1.15,
                           [(0, shade(hi, 0.95)), (0.55, base), (1, shade(base, 0.55))]))
    circle(ctx, cx - R * 0.08, cy - R * 0.08, R * 0.55)
    fill_grad(ctx, rad(cx - R * 0.3, cy - R * 0.3, R * 0.05, R * 0.7, [(0, hi), (0.6, shade(base, 1.1)), (1, alpha(base, 0))]))
    # leaf speckles
    for k in range(30):
        a = r.uniform(0, math.tau)
        d = R * math.sqrt(r.uniform(0, 0.75))
        x, y = cx + math.cos(a) * d, cy + math.sin(a) * d
        lit = (x - cx + y - cy) < 0
        circle(ctx, x, y, r.uniform(0.8, 1.8))
        fill(ctx, alpha(shade(hi, 1.1) if lit else shade(base, 0.6), 0.55))


def tree(tid):
    base, hi = TREES[tid]
    r = rng(tid)
    cv = Canvas(64, 64)
    ctx = cv.ctx
    canopy(ctx, 29, 29, 25 + r.uniform(-1, 1.5), base, hi, r)
    return finish(cv, dx=5, dy=6, blur=3.5, strength=0.55, grit=0.03, seed=tid)


def dead_tree():
    r = rng('dead')
    cv = Canvas(64, 64)
    ctx = cv.ctx
    bark = hexc('#6b5442')

    def branch(x, y, a, L, w, depth):
        x2, y2 = x + math.cos(a) * L, y + math.sin(a) * L
        for ww, c in ((w + 2, OUT), (w, bark)):
            ctx.move_to(x, y); ctx.line_to(x2, y2)
            stroke(ctx, c, ww)
        if depth > 0:
            for s in (-1, 1):
                branch(x2, y2, a + s * r.uniform(0.35, 0.7), L * r.uniform(0.55, 0.7), w * 0.62, depth - 1)

    for i in range(5):
        branch(30, 30, i * math.tau / 5 + r.uniform(-0.3, 0.3), r.uniform(10, 13), 4.0, 2)
    circle(ctx, 30, 30, 6)
    fill_grad(ctx, rad(28, 28, 0, 7, [(0, shade(bark, 1.4)), (1, shade(bark, 0.6))]))
    circle(ctx, 30, 30, 6)
    stroke(ctx, OUT, 1.1)
    circle(ctx, 30, 30, 3)
    stroke(ctx, alpha(shade(bark, 0.5), 0.8), 0.8)
    return finish(cv, dx=4, dy=5, blur=2.5, strength=0.5, seed='dead')


def rock(fw, seed):
    S = 64 * fw
    r = rng(seed)
    cv = Canvas(S, S)
    ctx = cv.ctx
    base, hi = hexc('#8a8174'), hexc('#d2c8b6')
    c = S / 2 - 3
    # main boulder plus satellites, back to front
    parts = [(c, c, S * 0.36)]
    for k in range(3 + fw):
        a = r.uniform(0, math.tau)
        d = S * r.uniform(0.22, 0.32)
        parts.append((c + math.cos(a) * d, c + math.sin(a) * d * 0.9, S * r.uniform(0.1, 0.17)))
    parts.sort(key=lambda p: p[1] - p[2] * 0.0)
    for (x, y, rr) in parts:
        chunk(ctx, x, y, rr, shade(base, r.uniform(0.9, 1.08)), hi, r, n=r.randint(7, 10), flat=0.85)
    # cracks / moss
    for k in range(fw * 3):
        x, y = c + r.uniform(-S * 0.2, S * 0.2), c + r.uniform(-S * 0.2, S * 0.2)
        ctx.move_to(x, y)
        for j in range(3):
            x += r.uniform(-5, 5); y += r.uniform(-5, 5)
            ctx.line_to(x, y)
        stroke(ctx, alpha(OUT, 0.5), 0.9)
    for k in range(fw * 5):
        x, y = c + r.uniform(-S * 0.25, S * 0.1), c + r.uniform(-S * 0.25, S * 0.1)
        circle(ctx, x, y, r.uniform(1.5, 3.5))
        fill(ctx, alpha(hexc('#5f7f3a'), 0.45))
    return finish(cv, dx=4 + fw, dy=5 + fw, blur=3, strength=0.55, seed=seed)


def generate(reg, data):
    for tid in TREES:
        reg.add(f'e_{tid}', tree(tid), 'natural', keep=True)
    reg.add('e_dead_tree', dead_tree(), 'natural', keep=True)
    reg.add('e_big_rock', rock(2, 'big_rock'), 'natural', keep=True)
    reg.add('e_huge_rock', rock(3, 'huge_rock'), 'natural', keep=True)
