"""Item icons i_<itemId> (64x64) and fluid icons f_<fluidId> (64x64).

Items that place an entity reuse the entity sprite as a centred miniature; everything else is drawn here.
All icons get a dark outline + small shadow so they read on dark UI.
"""
from __future__ import annotations

import math

from PIL import Image

from .base import OUT, bevel_box, inset_box, rivets
from .common import (Canvas, P, alpha, bolt, circle, ellipse, fill, fill_grad, finish_icon, fit_icon, gear_path, hexc,
                     lin, mix, poly, rad, rng, rrect, shade, src, stroke, pil_to_surf)
from .ores import ORES, chunk

CARD_COLORS = {
    'mechanics_card': hexc('#d63a2e'),
    'motion_card': hexc('#43b23a'),
    'defense_card': hexc('#34373c'),
    'reaction_card': hexc('#3a8ad8'),
    'fabrication_card': hexc('#9a4fc8'),
    'systems_card': hexc('#e8c22a'),
    'orbital_card': hexc('#eef0f2'),
}
MODULE_COLORS = {'speed': hexc('#3a7fe0'), 'efficiency': hexc('#3fbf4a'), 'productivity': hexc('#f08a24')}


def cv64():
    return Canvas(64, 64)


def done(cv, grit=0.015):
    return finish_icon(cv, grit=grit)


def g_tl(x, y, w, h, c, hi=1.3, lo=0.6):
    return lin(x, y, x + w, y + h, [(0, shade(c, hi)), (0.5, c), (1, shade(c, lo))])


# --------------------------------------------------------------------------------------------- raw / materials

def ore_icon(res):
    base, hi, acc = ORES[res]
    cv = cv64(); ctx = cv.ctx
    r = rng('icon' + res)
    for (x, y, rr) in ((22, 38, 13), (42, 40, 12), (32, 24, 14)):
        chunk(ctx, x, y, rr, base, hi, r, n=8, flat=0.9)
        if res == 'copper_ore':
            circle(ctx, x + 3, y + 2, 3); fill(ctx, acc)
        if res == 'coal':
            ctx.move_to(x - 6, y - 1); ctx.line_to(x - 1, y - 6)
            stroke(ctx, alpha(hexc('#d0d8e4'), 0.7), 1.4)
    return done(cv)


def wood():
    cv = cv64(); ctx = cv.ctx
    for (y, L) in ((38, 44), (24, 40)):
        x = 32 - L / 2
        rrect(ctx, x, y - 8, L, 16, 7)
        fill_grad(ctx, lin(0, y - 8, 0, y + 8, [(0, P['wood_l']), (0.5, P['wood']), (1, P['wood_d'])]), preserve=True)
        stroke(ctx, OUT, 1.2)
        ellipse(ctx, x + L - 6, y, 6, 7.5)
        fill(ctx, hexc('#e3b77a'), preserve=True)
        stroke(ctx, OUT, 1.0)
        for rr in (2, 4.5):
            ellipse(ctx, x + L - 6, y, rr * 0.8, rr)
            stroke(ctx, alpha(P['wood_d'], 0.7), 0.8)
    return done(cv)


def plates(c, stamp=None):
    cv = cv64(); ctx = cv.ctx
    for k, (x, y) in enumerate(((14, 30), (18, 22), (22, 14))):
        rrect(ctx, x, y + 4, 34, 20, 3)
        fill(ctx, shade(c, 0.45), preserve=True)
        stroke(ctx, OUT, 1.1)
        rrect(ctx, x, y, 34, 20, 3)
        fill_grad(ctx, g_tl(x, y, 34, 20, c, 1.35, 0.75), preserve=True)
        stroke(ctx, OUT, 1.1)
        ctx.move_to(x + 3, y + 3); ctx.line_to(x + 14, y + 3)
        stroke(ctx, alpha(hexc('#ffffff'), 0.5), 1.2)
    if stamp:
        rrect(ctx, 32, 18, 10, 10, 2)
        stroke(ctx, alpha(OUT, 0.6), 1.4)
    return done(cv)


def bricks():
    cv = cv64(); ctx = cv.ctx
    c = hexc('#b58a64')
    for (x, y) in ((8, 36), (32, 36), (20, 22), (14, 8 + 0), (38, 8 + 0)):
        if y == 8:
            continue
        bevel_box(ctx, x, y, 24, 14, c, r=2, bev=2)
    bevel_box(ctx, 20, 8, 24, 14, shade(c, 1.05), r=2, bev=2)
    return done(cv)


def gear_icon(cx=32, cy=32, r=24, c=None, teeth=10):
    cv = cv64(); ctx = cv.ctx
    c = c or hexc('#8f9aa4')
    gear_path(ctx, cx, cy, r, r * 0.78, teeth, 0.15, hole=r * 0.3)
    ctx.set_fill_rule(1)
    fill_grad(ctx, g_tl(cx - r, cy - r, 2 * r, 2 * r, c, 1.45, 0.55), preserve=True)
    stroke(ctx, OUT, 1.3)
    circle(ctx, cx, cy, r * 0.55)
    stroke(ctx, alpha(OUT, 0.45), 1.2)
    return done(cv)


def sticks():
    cv = cv64(); ctx = cv.ctx
    for (a, b) in (((14, 50), (46, 12)), ((20, 54), (52, 16))):
        ctx.move_to(*a); ctx.line_to(*b)
        stroke(ctx, OUT, 7.5)
        ctx.move_to(*a); ctx.line_to(*b)
        stroke(ctx, hexc('#8f9aa4'), 5)
        ctx.move_to(a[0] - 1, a[1] - 1); ctx.line_to(b[0] - 1, b[1] - 1)
        stroke(ctx, alpha(hexc('#e8eef2'), 0.7), 1.4)
    return done(cv)


def cable():
    cv = cv64(); ctx = cv.ctx
    c = hexc('#d07a3a')
    for k in range(4):
        ctx.save(); ctx.translate(32, 32 + (k - 1.5) * 5); ctx.scale(1, 0.55)
        circle(ctx, 0, 0, 20)
        ctx.restore()
        stroke(ctx, OUT, 5.2)
        ctx.save(); ctx.translate(32, 32 + (k - 1.5) * 5); ctx.scale(1, 0.55)
        circle(ctx, 0, 0, 20)
        ctx.restore()
        stroke(ctx, shade(c, 1.1 - k * 0.07), 3)
    ctx.move_to(50, 38); ctx.curve_to(58, 42, 56, 52, 48, 54)
    stroke(ctx, OUT, 5.2)
    ctx.move_to(50, 38); ctx.curve_to(58, 42, 56, 52, 48, 54)
    stroke(ctx, c, 3)
    return done(cv)


def circuit(board, chip_c, n_chips=1, gold=True):
    cv = cv64(); ctx = cv.ctx
    rrect(ctx, 8, 12, 48, 40, 4)
    fill_grad(ctx, g_tl(8, 12, 48, 40, board, 1.3, 0.6), preserve=True)
    stroke(ctx, OUT, 1.3)
    # traces
    tc = shade(board, 1.6)
    for (pts) in (((12, 20), (24, 20), (28, 26)), ((12, 44), (20, 44), (26, 38)), ((52, 22), (44, 22), (40, 28)),
                  ((52, 44), (42, 44), (38, 38))):
        ctx.move_to(*pts[0])
        for p in pts[1:]:
            ctx.line_to(*p)
        stroke(ctx, alpha(tc, 0.8), 1.6)
        circle(ctx, *pts[0], 1.8); fill(ctx, P['brass_l'])
    if n_chips == 1:
        bevel_box(ctx, 22, 22, 20, 20, chip_c, r=2, bev=1.6)
    else:
        bevel_box(ctx, 16, 22, 14, 20, chip_c, r=2, bev=1.5)
        bevel_box(ctx, 34, 22, 14, 20, chip_c, r=2, bev=1.5)
    if gold:
        for k in range(6):
            ctx.rectangle(14 + k * 6.5, 48, 3.5, 4)
            fill(ctx, P['brass_l'])
    return done(cv)


def processing_unit():
    cv = cv64(); ctx = cv.ctx
    rrect(ctx, 8, 8, 48, 48, 5)
    fill_grad(ctx, g_tl(8, 8, 48, 48, hexc('#2f5fb8'), 1.3, 0.55), preserve=True)
    stroke(ctx, OUT, 1.3)
    for k in range(5):
        for side in range(4):
            t = 17 + k * 7.5
            x, y = [(t, 10), (54, t), (t, 54), (10, t)][side]
            circle(ctx, x, y, 1.4); fill(ctx, P['brass_l'])
    bevel_box(ctx, 18, 18, 28, 28, hexc('#26292e'), r=3, bev=2)
    rrect(ctx, 25, 25, 14, 14, 2)
    fill_grad(ctx, rad(30, 30, 0, 12, [(0, hexc('#9fe8ff')), (1, hexc('#2f8fd8'))]))
    return done(cv)


def battery():
    cv = cv64(); ctx = cv.ctx
    rrect(ctx, 18, 10, 28, 46, 6)
    fill_grad(ctx, lin(18, 0, 46, 0, [(0, shade(hexc('#c9a03a'), 0.9)), (0.3, hexc('#f2d070')), (1, hexc('#8a6618'))]), preserve=True)
    stroke(ctx, OUT, 1.3)
    rrect(ctx, 18, 30, 28, 26, 6)
    fill_grad(ctx, lin(18, 0, 46, 0, [(0, hexc('#3a3d42')), (0.3, hexc('#62676e')), (1, hexc('#1f2124'))]), preserve=True)
    stroke(ctx, OUT, 1.3)
    rrect(ctx, 26, 5, 12, 7, 2)
    fill(ctx, P['steel_l'], preserve=True)
    stroke(ctx, OUT, 1.0)
    poly(ctx, [(34, 34), (27, 44), (32, 44), (30, 52), (37, 41), (32, 41)])
    fill(ctx, hexc('#ffe24a'), preserve=True)
    stroke(ctx, alpha(OUT, 0.7), 0.8)
    return done(cv)


def plastic():
    cv = cv64(); ctx = cv.ctx
    for (y, c) in ((34, hexc('#d8dde2')), (20, hexc('#f4f6f8'))):
        rrect(ctx, 10, y, 44, 14, 6)
        fill_grad(ctx, lin(0, y, 0, y + 14, [(0, shade(c, 1.05)), (0.35, c), (1, shade(c, 0.65))]), preserve=True)
        stroke(ctx, OUT, 1.2)
        ctx.move_to(16, y + 4); ctx.line_to(36, y + 4)
        stroke(ctx, alpha(hexc('#ffffff'), 0.9), 1.6)
    return done(cv)


def sulfur():
    cv = cv64(); ctx = cv.ctx
    r = rng('sulfur')
    c = hexc('#e8d23a')
    for (x, y, s) in ((22, 40, 12), (42, 42, 11), (32, 26, 13), (46, 26, 7), (16, 26, 7)):
        pts = [(x, y - s), (x + s * 0.8, y - s * 0.2), (x + s * 0.5, y + s * 0.8), (x - s * 0.5, y + s * 0.8), (x - s * 0.8, y - s * 0.2)]
        poly(ctx, pts)
        fill_grad(ctx, g_tl(x - s, y - s, 2 * s, 2 * s, c, 1.4, 0.55), preserve=True)
        stroke(ctx, OUT, 1.1)
        ctx.move_to(x, y - s); ctx.line_to(x, y + s * 0.2); ctx.line_to(x - s * 0.8, y - s * 0.2)
        stroke(ctx, alpha(hexc('#fff6b0'), 0.7), 0.9)
    return done(cv)


def solid_fuel():
    cv = cv64(); ctx = cv.ctx
    for (x, y) in ((10, 30), (30, 34), (20, 14)):
        bevel_box(ctx, x, y, 24, 18, hexc('#3a3633'), r=3, bev=2)
        rrect(ctx, x + 5, y + 5, 14, 6, 2)
        fill(ctx, hexc('#e8792a'))
    return done(cv)


def rocket_fuel():
    cv = cv64(); ctx = cv.ctx
    rrect(ctx, 16, 12, 32, 44, 7)
    fill_grad(ctx, lin(16, 0, 48, 0, [(0, hexc('#b8321e')), (0.3, hexc('#f0583a')), (1, hexc('#6a1408'))]), preserve=True)
    stroke(ctx, OUT, 1.3)
    rrect(ctx, 24, 6, 16, 8, 2)
    fill(ctx, P['steel_l'], preserve=True)
    stroke(ctx, OUT, 1)
    poly(ctx, [(32, 22), (40, 36), (36, 36), (36, 46), (28, 46), (28, 36), (24, 36)])
    fill(ctx, hexc('#ffd04a'), preserve=True)
    stroke(ctx, alpha(OUT, 0.6), 0.8)
    return done(cv)


def engine(electric=False):
    cv = cv64(); ctx = cv.ctx
    body = hexc('#3f6fb8') if electric else hexc('#8a8f94')
    bevel_box(ctx, 10, 16, 40, 34, body, r=5, bev=2.5)
    if electric:
        for k in range(4):
            rrect(ctx, 14 + k * 9, 20, 6, 26, 2)
            fill_grad(ctx, lin(0, 20, 0, 46, [(0, hexc('#f0a060')), (1, hexc('#8a4a1a'))]))
    else:
        for k in range(3):
            cyl = (18 + k * 12, 24)
            circle(ctx, cyl[0], cyl[1], 5)
            fill_grad(ctx, rad(cyl[0] - 1.5, cyl[1] - 1.5, 0, 6, [(0, P['steel_h']), (1, P['steel_d'])]), preserve=True)
            stroke(ctx, OUT, 1)
        rrect(ctx, 14, 34, 32, 10, 2)
        fill(ctx, hexc('#c8402f'), preserve=True)
        stroke(ctx, OUT, 1)
    # shaft + gear on the right
    gear_path(ctx, 50, 44, 11, 8.5, 9, 0.2, hole=3)
    ctx.set_fill_rule(1)
    fill_grad(ctx, g_tl(39, 33, 22, 22, hexc('#c9a03a'), 1.4, 0.6), preserve=True)
    stroke(ctx, OUT, 1.1)
    return done(cv)


def robot_frame():
    cv = cv64(); ctx = cv.ctx
    for (a, b) in (((14, 14), (50, 50)), ((50, 14), (14, 50))):
        ctx.move_to(*a); ctx.line_to(*b)
        stroke(ctx, OUT, 7); ctx.move_to(*a); ctx.line_to(*b)
        stroke(ctx, hexc('#9aa3ab'), 4.5)
    for (x, y) in ((14, 14), (50, 14), (14, 50), (50, 50)):
        circle(ctx, x, y, 8)
        fill(ctx, alpha(hexc('#cfe8ff'), 0.35), preserve=True)
        stroke(ctx, OUT, 1.2)
        circle(ctx, x, y, 2.5); fill(ctx, P['steel_d'])
    bevel_box(ctx, 22, 22, 20, 20, hexc('#e8792a'), r=4, bev=2)
    circle(ctx, 32, 32, 3.5); fill(ctx, hexc('#7cf0ff'), preserve=True); stroke(ctx, OUT, 0.8)
    return done(cv)


def lds():
    cv = cv64(); ctx = cv.ctx
    bevel_box(ctx, 8, 10, 48, 44, hexc('#c97a3e'), r=4, bev=3)
    ctx.save(); rrect(ctx, 12, 14, 40, 36, 2); ctx.clip()
    rrect(ctx, 12, 14, 40, 36, 2); fill(ctx, hexc('#b8bfc5'))
    for row in range(5):
        for col in range(5):
            x = 12 + col * 9 + (row % 2) * 4.5
            y = 16 + row * 8
            pts = [(x + 4.5 * math.cos(a), y + 4.5 * math.sin(a)) for a in [k * math.pi / 3 for k in range(6)]]
            poly(ctx, pts)
            stroke(ctx, alpha(OUT, 0.55), 1.0)
    ctx.restore()
    return done(cv)


def rcu():
    cv = cv64(); ctx = cv.ctx
    bevel_box(ctx, 8, 12, 48, 40, hexc('#2f8f9a'), r=5, bev=2.5)
    for k in range(3):
        bevel_box(ctx, 13 + k * 14, 20, 11, 14, hexc('#26292e'), r=2, bev=1.4)
        circle(ctx, 18.5 + k * 14, 42, 2.2); fill(ctx, [hexc('#7cff8a'), hexc('#ffd04a'), hexc('#ff6a4a')][k])
    return done(cv)


def rocket_part():
    cv = cv64(); ctx = cv.ctx
    rrect(ctx, 14, 8, 36, 48, 4)
    fill_grad(ctx, lin(14, 0, 50, 0, [(0, hexc('#c0c6cc')), (0.3, hexc('#f4f6f8')), (1, hexc('#6a737b'))]), preserve=True)
    stroke(ctx, OUT, 1.3)
    for y in (16, 48):
        ctx.rectangle(14, y - 2, 36, 4); fill(ctx, hexc('#c8402f'))
    for k in range(4):
        bolt(ctx, 19 + k * 9, 32, 1.4)
    return done(cv)


def satellite():
    cv = cv64(); ctx = cv.ctx
    for x in (4, 42):
        rrect(ctx, x, 22, 18, 20, 2)
        fill_grad(ctx, g_tl(x, 22, 18, 20, hexc('#2a55a8'), 1.4, 0.6), preserve=True)
        stroke(ctx, OUT, 1.1)
        ctx.move_to(x + 9, 22); ctx.line_to(x + 9, 42); ctx.move_to(x, 32); ctx.line_to(x + 18, 32)
        stroke(ctx, alpha(hexc('#a9c6ff'), 0.5), 0.8)
    bevel_box(ctx, 22, 18, 20, 28, hexc('#d8a838'), r=3, bev=2)
    circle(ctx, 32, 14, 6); fill(ctx, P['steel_l'], preserve=True); stroke(ctx, OUT, 1)
    return done(cv)


EMBLEMS = {}


def card(cid):
    c = CARD_COLORS[cid]
    cv = cv64(); ctx = cv.ctx
    # card body (tilted slightly for character)
    ctx.save(); ctx.translate(32, 32); ctx.rotate(-0.12); ctx.translate(-32, -32)
    rrect(ctx, 11, 6, 42, 52, 5)
    fill_grad(ctx, g_tl(11, 6, 42, 52, c, 1.35, 0.6), preserve=True)
    stroke(ctx, OUT, 1.4)
    # gold edge contacts
    for k in range(6):
        rrect(ctx, 15 + k * 6, 50, 4, 6, 1)
        fill(ctx, P['brass_l'], preserve=True)
        stroke(ctx, alpha(OUT, 0.5), 0.6)
    # trace lines
    tc = alpha(shade(c, 1.7) if cid != 'orbital_card' else hexc('#8a96a2'), 0.75)
    for (a, b, cc) in (((15, 14), (22, 14), (25, 18)), ((49, 14), (42, 14), (39, 18)), ((15, 44), (22, 44), (25, 40))):
        ctx.move_to(*a); ctx.line_to(*b); ctx.line_to(*cc)
        stroke(ctx, tc, 1.4)
    # emblem medallion
    circle(ctx, 32, 29, 12.5)
    dark = cid in ('orbital_card', 'systems_card')
    fill_grad(ctx, rad(29, 26, 1, 14, [(0, hexc('#3a3f46')), (1, hexc('#15181b'))]) if not dark else
              rad(29, 26, 1, 14, [(0, hexc('#4a4f56')), (1, hexc('#22262a'))]), preserve=True)
    stroke(ctx, OUT, 1.2)
    ec = shade(c, 1.45) if cid not in ('defense_card',) else hexc('#c9ced4')
    if cid == 'orbital_card':
        ec = hexc('#9fd8ff')
    emblem(ctx, cid, 32, 29, ec)
    ctx.restore()
    return done(cv)


def emblem(ctx, cid, x, y, c):
    if cid == 'mechanics_card':
        gear_path(ctx, x, y, 8.5, 6.5, 8, 0, hole=2.5)
        ctx.set_fill_rule(1); fill(ctx, c)
    elif cid == 'motion_card':
        poly(ctx, [(x - 8, y - 3), (x + 1, y - 3), (x + 1, y - 7), (x + 8, y), (x + 1, y + 7), (x + 1, y + 3), (x - 8, y + 3)])
        fill(ctx, c)
    elif cid == 'defense_card':
        ctx.move_to(x, y - 8); ctx.line_to(x + 7, y - 5); ctx.curve_to(x + 7, y + 3, x + 3, y + 7, x, y + 9)
        ctx.curve_to(x - 3, y + 7, x - 7, y + 3, x - 7, y - 5); ctx.close_path()
        fill(ctx, c)
    elif cid == 'reaction_card':
        pts = [(x + 8 * math.cos(a), y + 8 * math.sin(a)) for a in [k * math.pi / 3 + math.pi / 6 for k in range(6)]]
        poly(ctx, pts); stroke(ctx, c, 2.2)
        circle(ctx, x, y, 2.5); fill(ctx, c)
    elif cid == 'fabrication_card':
        ctx.move_to(x - 6, y + 6); ctx.line_to(x + 3, y - 3)
        stroke(ctx, c, 3.5)
        circle(ctx, x + 4.5, y - 4.5, 4.5); fill(ctx, c)
        circle(ctx, x + 6.5, y - 6.5, 2.2); fill(ctx, hexc('#15181b'))
    elif cid == 'systems_card':
        rrect(ctx, x - 5, y - 5, 10, 10, 1.5); fill(ctx, c)
        for k in (-3, 0, 3):
            for (dx, dy) in ((k, -8), (k, 8), (-8, k), (8, k)):
                ctx.move_to(x + dx * (1 if abs(dx) < 8 else 0.7), y + dy * (1 if abs(dy) < 8 else 0.7))
                ctx.line_to(x + dx, y + dy)
        stroke(ctx, c, 1.6)
    else:  # orbital
        circle(ctx, x, y, 5); fill(ctx, c)
        ctx.save(); ctx.translate(x, y); ctx.rotate(-0.4); ctx.scale(1, 0.38)
        circle(ctx, 0, 0, 10); ctx.restore()
        stroke(ctx, c, 1.6)


def module(kind, tier):
    c = MODULE_COLORS[kind]
    cv = cv64(); ctx = cv.ctx
    bevel_box(ctx, 8, 8, 48, 48, hexc('#4a5158'), r=6, bev=3)
    # coloured core
    rrect(ctx, 16, 14, 32, 28, 4)
    fill_grad(ctx, g_tl(16, 14, 32, 28, c, 1.45, 0.55), preserve=True)
    stroke(ctx, OUT, 1.2)
    # glyph
    gc = alpha(hexc('#ffffff'), 0.9)
    if kind == 'speed':
        for dx in (-6, 2):
            ctx.move_to(30 + dx, 21); ctx.line_to(36 + dx, 28); ctx.line_to(30 + dx, 35)
            stroke(ctx, gc, 3)
    elif kind == 'efficiency':
        ctx.move_to(24, 34); ctx.curve_to(24, 22, 34, 18, 41, 20); ctx.curve_to(41, 30, 34, 36, 24, 34)
        fill(ctx, gc)
        ctx.move_to(24, 34); ctx.line_to(36, 24)
        stroke(ctx, alpha(c, 0.9), 1.4)
    else:
        for k, h in enumerate((7, 11, 15)):
            ctx.rectangle(23 + k * 7, 36 - h, 5, h)
        fill(ctx, gc)
    # tier pips
    for k in range(tier):
        x = 32 - (tier - 1) * 6 + k * 12
        circle(ctx, x, 49, 4)
        fill_grad(ctx, rad(x - 1, 48, 0, 4.5, [(0, hexc('#ffffff')), (1, shade(c, 1.2))]), preserve=True)
        stroke(ctx, OUT, 0.9)
    return done(cv)


def barrel(fluid_color=None):
    cv = cv64(); ctx = cv.ctx
    body = hexc('#7d8894')
    rrect(ctx, 14, 8, 36, 50, 6)
    fill_grad(ctx, lin(14, 0, 50, 0, [(0, shade(body, 0.85)), (0.3, shade(body, 1.4)), (1, shade(body, 0.5))]), preserve=True)
    stroke(ctx, OUT, 1.3)
    if fluid_color is not None:
        rrect(ctx, 14, 24, 36, 18, 1)
        fill_grad(ctx, lin(14, 0, 50, 0, [(0, shade(fluid_color, 0.8)), (0.3, shade(fluid_color, 1.35)), (1, shade(fluid_color, 0.5))]))
    for y in (14, 24, 42, 52):
        ctx.rectangle(14, y - 1.2, 36, 2.4)
        fill(ctx, alpha(OUT, 0.55))
    # top lid ellipse + bung
    ellipse(ctx, 32, 9, 17, 4)
    fill(ctx, shade(body, 1.1), preserve=True)
    stroke(ctx, OUT, 1.1)
    circle(ctx, 39, 9, 2); fill(ctx, fluid_color or P['steel_d'])
    return done(cv)


def tile_icon(reg, tid):
    t = reg.get(f'tile_{tid}_v0')
    cv = cv64(); ctx = cv.ctx
    # stacked tile pieces
    surf = pil_to_surf(t.resize((40, 40), Image.LANCZOS))
    for (x, y) in ((16, 18), (8, 10)):
        rrect(ctx, x, y + 4, 40, 40, 3); fill(ctx, alpha(OUT, 0.9))
        ctx.save(); rrect(ctx, x, y, 40, 40, 3); ctx.clip()
        ctx.set_source_surface(surf, x, y); ctx.paint()
        ctx.restore()
        rrect(ctx, x + 0.5, y + 0.5, 39, 39, 3)
        stroke(ctx, OUT, 1.2)
        ctx.move_to(x + 2, y + 38); ctx.line_to(x + 2, y + 2); ctx.line_to(x + 38, y + 2)
        stroke(ctx, alpha(hexc('#ffffff'), 0.35), 1.5)
    return done(cv, grit=0)


def landfill():
    cv = cv64(); ctx = cv.ctx
    r = rng('landfill')
    ctx.move_to(6, 52); ctx.curve_to(14, 20, 50, 20, 58, 52); ctx.close_path()
    fill_grad(ctx, lin(10, 20, 54, 52, [(0, hexc('#a88a62')), (1, hexc('#5a4632'))]), preserve=True)
    stroke(ctx, OUT, 1.3)
    for k in range(18):
        x, y = r.uniform(14, 50), r.uniform(32, 50)
        circle(ctx, x, y, r.uniform(1, 2.6))
        fill(ctx, alpha(hexc('#d8c09a') if r.rand() < 0.5 else hexc('#3a2c1e'), 0.8))
    return done(cv)


def rail():
    cv = cv64(); ctx = cv.ctx
    ctx.save(); ctx.translate(32, 32); ctx.rotate(-math.pi / 4); ctx.translate(-32, -32)
    for k in range(5):
        y = 10 + k * 11
        rrect(ctx, 14, y, 36, 7, 2)
        fill_grad(ctx, lin(0, y, 0, y + 7, [(0, P['wood_l']), (1, P['wood_d'])]), preserve=True)
        stroke(ctx, OUT, 1.0)
    for x in (22, 42):
        ctx.rectangle(x - 3, 4, 6, 56)
        fill_grad(ctx, lin(x - 3, 0, x + 3, 0, [(0, P['steel_h']), (1, P['steel_d'])]), preserve=True)
        stroke(ctx, OUT, 1.0)
    ctx.restore()
    return done(cv)


# --------------------------------------------------------------------------------------------- fluids

def fluid_icon(fid, color):
    c = hexc('#%02x%02x%02x' % tuple(int(max(0, min(1, v)) * 255) for v in color))
    if fid == 'crude_oil':
        c = hexc('#2a2630')
    cv = cv64(); ctx = cv.ctx
    if fid == 'steam':
        for (x, y, r) in ((22, 38, 12), (40, 38, 13), (31, 26, 14), (44, 26, 8)):
            circle(ctx, x, y, r + 1.2); fill(ctx, OUT)
        for (x, y, r) in ((22, 38, 12), (40, 38, 13), (31, 26, 14), (44, 26, 8)):
            circle(ctx, x, y, r)
            fill_grad(ctx, rad(x - r * 0.4, y - r * 0.4, 0, r * 1.3, [(0, hexc('#ffffff')), (1, hexc('#9aa4ad'))]))
        return done(cv, grit=0)
    ctx.move_to(32, 6)
    ctx.curve_to(36, 18, 50, 28, 50, 40)
    ctx.curve_to(50, 51, 42, 58, 32, 58)
    ctx.curve_to(22, 58, 14, 51, 14, 40)
    ctx.curve_to(14, 28, 28, 18, 32, 6)
    ctx.close_path()
    hi = shade(c, 1.6) if fid != 'crude_oil' else hexc('#6a5a8a')
    fill_grad(ctx, rad(26, 36, 2, 30, [(0, hi), (0.45, c), (1, shade(c, 0.45))]), preserve=True)
    stroke(ctx, OUT, 1.5)
    ctx.save(); ctx.translate(24, 42); ctx.rotate(-0.5); ctx.scale(0.55, 1)
    circle(ctx, 0, 0, 6); ctx.restore()
    fill(ctx, alpha(hexc('#ffffff'), 0.6))
    circle(ctx, 40, 46, 2.2); fill(ctx, alpha(hexc('#ffffff'), 0.35))
    return done(cv, grit=0)


# --------------------------------------------------------------------------------------------- dispatch

def custom(reg, iid, fluids):
    if iid in ('iron_ore', 'copper_ore', 'coal', 'stone', 'uranium_ore'):
        return ore_icon(iid)
    if iid == 'wood': return wood()
    if iid == 'iron_plate': return plates(hexc('#8a99a8'))
    if iid == 'copper_plate': return plates(hexc('#d07a3a'))
    if iid == 'steel_plate': return plates(hexc('#5f7186'), stamp=True)
    if iid == 'stone_brick': return bricks()
    if iid == 'iron_gear_wheel': return gear_icon()
    if iid == 'iron_stick': return sticks()
    if iid == 'copper_cable': return cable()
    if iid == 'electronic_circuit': return circuit(hexc('#2f8f3a'), hexc('#2a2d31'))
    if iid == 'advanced_circuit': return circuit(hexc('#b8382a'), hexc('#2a2d31'), 2)
    if iid == 'processing_unit': return processing_unit()
    if iid == 'battery': return battery()
    if iid == 'plastic_bar': return plastic()
    if iid == 'sulfur': return sulfur()
    if iid == 'solid_fuel': return solid_fuel()
    if iid == 'rocket_fuel': return rocket_fuel()
    if iid == 'engine_unit': return engine(False)
    if iid == 'electric_engine_unit': return engine(True)
    if iid == 'flying_robot_frame': return robot_frame()
    if iid == 'low_density_structure': return lds()
    if iid == 'rocket_control_unit': return rcu()
    if iid == 'rocket_part': return rocket_part()
    if iid == 'satellite': return satellite()
    if iid in CARD_COLORS: return card(iid)
    for kind in MODULE_COLORS:
        if iid.startswith(kind + '_module'):
            tier = int(iid[-1]) if iid[-1].isdigit() else 1
            return module(kind, tier)
    if iid == 'empty_barrel': return barrel(None)
    if iid.endswith('_barrel'):
        fid = iid[:-7]
        col = fluids.get(fid, [0.5, 0.5, 0.5])
        c = hexc('#%02x%02x%02x' % tuple(int(max(0, min(1, v)) * 255) for v in col))
        if fid == 'crude_oil':
            c = hexc('#2a2630')
        return barrel(c)
    if iid in ('concrete', 'hazard_concrete', 'refined_concrete', 'refined_hazard_concrete', 'stone_brick'):
        return tile_icon(reg, iid)
    if iid == 'landfill': return landfill()
    if iid == 'rail': return rail()
    return None


def generate(reg, data):
    fluids = {f['id']: f['color'] for f in data['fluids']}
    ents = {e['id'] for e in data['entities']}
    missing = []
    for it in data['items']:
        iid = it['id']
        img = None
        pr = it.get('placeResult')
        if pr and pr in ents and iid != 'stone_brick':
            src_name = f'e_{pr}'
            img = fit_icon(reg.get(src_name), 64, 56)
        else:
            img = custom(reg, iid, fluids)
        if img is None:
            missing.append(iid)
            continue
        reg.add(f'i_{iid}', img, 'items')
    for f in data['fluids']:
        reg.add(f'f_{f["id"]}', fluid_icon(f['id'], f['color']), 'items')
    if missing:
        print('  items without icon:', missing)
