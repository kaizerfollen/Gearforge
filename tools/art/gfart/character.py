"""The engineer: char_<dir>_f<k> (4 walk frames) and char_<dir>_idle, 48x64, feet at the bottom centre (24, 58).

Original design: orange work suit, teal trousers/visor, white helmet with an orange crest, grey backpack.
Geometry is mirrored for e/w but gradients stay in screen space (light from the top-left).
"""
from __future__ import annotations

import math

from .base import OUT
from .common import Canvas, alpha, circle, ellipse, fill, fill_grad, hexc, lin, rad, rrect, shade, stroke

SUIT = hexc('#e8792a')
SUIT_D = hexc('#a84a14')
TEAL = hexc('#1f8f8a')
TEAL_D = hexc('#145a58')
HELM = hexc('#eef1f2')
VISOR = hexc('#2fd0c6')
PACK = hexc('#5d666f')
BOOT = hexc('#2a2c30')
SKIN = hexc('#e0b08a')


def part(ctx, x, y, w, h, r, c, lw=1.1):
    rrect(ctx, x, y, w, h, r)
    fill_grad(ctx, lin(x, y, x + w, y + h, [(0, shade(c, 1.25)), (0.5, c), (1, shade(c, 0.6))]))
    rrect(ctx, x + 0.4, y + 0.4, w - 0.8, h - 0.8, r)
    stroke(ctx, OUT, lw)


def helmet(ctx, cx, cy, view, sgn=1):
    circle(ctx, cx, cy, 10)
    fill_grad(ctx, rad(cx - 4, cy - 4, 1, 12, [(0, shade(HELM, 1.05)), (0.6, HELM), (1, shade(HELM, 0.62))]))
    circle(ctx, cx, cy, 10)
    stroke(ctx, OUT, 1.2)
    # crest stripe
    if view in ('s', 'n'):
        rrect(ctx, cx - 2, cy - 10, 4, 12, 2)
    else:
        ctx.save(); ctx.translate(cx, cy); ctx.scale(sgn, 1)
        rrect(ctx, -6, -10, 12, 4, 2)
        ctx.restore()
    fill(ctx, SUIT)
    if view == 's':
        rrect(ctx, cx - 7.5, cy - 1, 15, 8, 3.5)
        fill_grad(ctx, lin(cx - 7, cy - 1, cx + 7, cy + 7, [(0, shade(VISOR, 1.5)), (1, shade(VISOR, 0.55))]))
        rrect(ctx, cx - 7.5, cy - 1, 15, 8, 3.5)
        stroke(ctx, OUT, 1.0)
        ctx.move_to(cx - 5, cy + 1); ctx.line_to(cx - 1, cy + 1)
        stroke(ctx, alpha(hexc('#ffffff'), 0.8), 1.2)
    elif view in ('e', 'w'):
        x0 = cx + sgn * 2
        rrect(ctx, min(x0, x0 + sgn * 9), cy - 1, 9, 8, 3.5)
        fill_grad(ctx, lin(cx - 7, cy - 1, cx + 7, cy + 7, [(0, shade(VISOR, 1.5)), (1, shade(VISOR, 0.55))]))
        rrect(ctx, min(x0, x0 + sgn * 9), cy - 1, 9, 8, 3.5)
        stroke(ctx, OUT, 1.0)


def draw(view, phase, moving):
    cv = Canvas(48, 64)
    ctx = cv.ctx
    s = math.sin(phase) if moving else 0.0
    bob = abs(math.sin(phase)) * 1.2 if moving else 0.0
    ellipse(ctx, 24, 58, 12, 4)
    fill(ctx, alpha(hexc('#0a0c0e'), 0.38))
    y0 = -bob
    if view in ('s', 'n'):
        # legs (stride shown as length change)
        for sgn in (-1, 1):
            dl = sgn * s * 3
            lx = 24 + sgn * 5 - 3.5
            part(ctx, lx, 42 + y0 - max(0, -dl), 7, 13 + dl * (1 if view == 's' else -1) * 0.6, 3, TEAL)
            part(ctx, lx - 0.5, 52 + y0 + dl * (0.6 if view == 's' else -0.6), 8, 5, 2.5, BOOT)
        # arms swing opposite
        for sgn in (-1, 1):
            da = -sgn * s * 3
            part(ctx, 24 + sgn * 12 - 3, 27 + y0 + da * 0.5, 6, 14, 3, SUIT)
            circle(ctx, 24 + sgn * 12, 41.5 + y0 + da * 0.5, 2.6)
            fill(ctx, BOOT, preserve=True)
            stroke(ctx, OUT, 0.9)
        part(ctx, 13, 25 + y0, 22, 21, 6, SUIT)
        if view == 's':
            part(ctx, 18, 29 + y0, 12, 8, 2.5, TEAL)          # chest panel
            circle(ctx, 21.5, 33 + y0, 1.4); fill(ctx, hexc('#9dffb0'))
        else:
            part(ctx, 15, 25 + y0, 18, 17, 4, PACK)           # backpack
            part(ctx, 18, 28 + y0, 12, 5, 2, shade(PACK, 1.3))
            circle(ctx, 24, 37 + y0, 2.5); fill(ctx, hexc('#ff9a3a'), preserve=True); stroke(ctx, OUT, 0.8)
        ctx.rectangle(14, 42 + y0, 20, 3)
        fill(ctx, TEAL_D)
        helmet(ctx, 24, 16 + y0, view)
    else:
        sgn = 1 if view == 'e' else -1
        # far leg / arm first
        for k, (c, ph) in enumerate(((shade(TEAL, 0.8), -1), (TEAL, 1))):
            dx = ph * s * 5 * sgn
            part(ctx, 24 - 3.5 + dx, 42 + y0, 7, 12, 3, c)
            part(ctx, 24 - 3.5 + dx + (1.5 * sgn), 52 + y0, 8, 5, 2.5, BOOT)
            if k == 0:
                da = -ph * s * 4 * sgn
                part(ctx, 24 - 3 + da, 27 + y0, 6, 14, 3, shade(SUIT, 0.8))
        # backpack behind
        part(ctx, 24 - sgn * 9.5 - 3.5, 26 + y0, 7, 16, 3, PACK)
        part(ctx, 16, 25 + y0, 16, 21, 6, SUIT)
        ctx.rectangle(16.5, 42 + y0, 15, 3)
        fill(ctx, TEAL_D)
        da = s * 4 * sgn
        part(ctx, 24 - 3 + da, 27 + y0, 6, 14, 3, SUIT)
        circle(ctx, 24 + da, 41.5 + y0, 2.6)
        fill(ctx, BOOT, preserve=True)
        stroke(ctx, OUT, 0.9)
        helmet(ctx, 24 + sgn * 1, 16 + y0, view, sgn)
    return cv.pil()


def generate(reg, data):
    for view in 'nesw':
        reg.add(f'char_{view}_idle', draw(view, 0, False), 'character', keep=(view == 's'))
        for k in range(4):
            reg.add(f'char_{view}_f{k}', draw(view, k * math.pi / 2 + math.pi / 4, True), 'character')
