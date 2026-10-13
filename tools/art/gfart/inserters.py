"""Inserters: static platform + separate arm and hand so the renderer can rotate/extend the arm.

  ins_<id>_base   64x64 platform only (pivot = tile centre)
  ins_<id>_arm    64x16 arm bar pointing RIGHT (+x); pivot at the left-centre (0, 8). Renderer rotates/scales it.
  ins_<id>_hand   24x24 gripper, fingers pointing RIGHT (+x), centred; rotate it with the arm.
  e_<id>          composite still (north = items travel north) for ghosts / icons
Arm and hand shading is symmetric about the long axis so any rotation still reads as lit from above.
"""
from __future__ import annotations

import math

from PIL import Image

from .base import OUT, bevel_box, finish, inset_box, rivets
from .common import (Canvas, P, add_grit, alpha, bolt, circle, fill, fill_grad, hexc, lin, rad, rrect, shade,
                     stroke, with_shadow, poly)

COLORS = {
    'burner_inserter': hexc('#7a6048'),
    'inserter': hexc('#e2a823'),
    'long_handed_inserter': hexc('#cc3f2e'),
    'fast_inserter': hexc('#3a7fd2'),
    'filter_inserter': hexc('#9150c8'),
    'stack_inserter': hexc('#45a83c'),
    'stack_filter_inserter': hexc('#8a7fa0'),
}


def base_image(iid):
    c = COLORS[iid]
    cv = Canvas(64, 64)
    ctx = cv.ctx
    # square mounting plate
    bevel_box(ctx, 9, 9, 44, 44, P['steel'], r=6, bev=2.5)
    rivets(ctx, 9, 9, 44, 44, inset=4.5, r=1.5)
    # coloured turntable ring
    circle(ctx, 31, 31, 16)
    fill_grad(ctx, lin(15, 15, 47, 47, [(0, shade(c, 1.35)), (0.5, c), (1, shade(c, 0.55))]))
    circle(ctx, 31, 31, 16)
    stroke(ctx, OUT, 1.2)
    circle(ctx, 31, 31, 11)
    fill_grad(ctx, lin(20, 20, 42, 42, [(0, shade(P['steel_d'], 0.8)), (1, shade(P['steel_m'], 1.1))]))
    circle(ctx, 31, 31, 11)
    stroke(ctx, alpha(OUT, 0.8), 1.0)
    # tick marks on the ring
    for i in range(8):
        a = i * math.pi / 4
        ctx.move_to(31 + math.cos(a) * 12.5, 31 + math.sin(a) * 12.5)
        ctx.line_to(31 + math.cos(a) * 15, 31 + math.sin(a) * 15)
        stroke(ctx, alpha(OUT, 0.55), 1.0)
    if iid == 'burner_inserter':
        rrect(ctx, 41, 41, 10, 10, 2); fill(ctx, hexc('#1f1a16'))
        circle(ctx, 46, 46, 3); fill_grad(ctx, rad(46, 46, 0, 3.5, [(0, P['fire_l']), (1, alpha(P['fire'], 0.2))]))
    if 'filter' in iid:
        # filter slot: small inset panel with a funnel glyph
        inset_box(ctx, 11, 40, 12, 11, P['steel_d'], r=2)
        poly(ctx, [(13.5, 43), (20.5, 43), (18, 46.5), (18, 49), (16, 49), (16, 46.5)])
        fill(ctx, shade(c, 1.5))
    if 'stack' in iid:
        for k in range(3):
            rrect(ctx, 41, 12 + k * 3.3, 9, 2.2, 1)
            fill(ctx, shade(c, 1.3 - k * 0.15))
    return finish(cv, dx=2.5, dy=3, strength=0.5, seed='insbase')


def _sym(y0, y1, col):
    return lin(0, y0, 0, y1, [(0, shade(col, 0.55)), (0.3, shade(col, 1.3)), (0.5, shade(col, 1.4)),
                              (0.7, shade(col, 1.05)), (1, shade(col, 0.5))])


def arm_image(iid):
    c = COLORS[iid]
    cv = Canvas(64, 16)
    ctx = cv.ctx
    long = 'long' in iid
    # inner telescopic rod (front)
    rrect(ctx, 22, 5, 41, 6, 2)
    ctx.set_source(_sym(5, 11, P['steel_l'])); ctx.fill()
    rrect(ctx, 22.5, 5.5, 40, 5, 2)
    stroke(ctx, OUT, 1.0)
    # sleeve (type colour)
    rrect(ctx, 1, 2.5, 40, 11, 3.5)
    ctx.set_source(_sym(2.5, 13.5, c)); ctx.fill()
    rrect(ctx, 1.5, 3, 39, 10, 3.5)
    stroke(ctx, OUT, 1.1)
    if long:
        for k in range(3):
            ctx.rectangle(12 + k * 8, 3.5, 3, 9)
            fill(ctx, alpha(OUT, 0.35))
    # collar at the sleeve end
    rrect(ctx, 37, 2, 5, 12, 1.5)
    ctx.set_source(_sym(2, 14, P['steel_m'])); ctx.fill()
    rrect(ctx, 37.5, 2.5, 4, 11, 1.5)
    stroke(ctx, OUT, 0.9)
    # pivot hub
    circle(ctx, 7, 8, 5.5)
    fill_grad(ctx, rad(5.5, 6.5, 0, 6, [(0, P['steel_h']), (1, shade(P['steel'], 0.8))]))
    circle(ctx, 7, 8, 5.5)
    stroke(ctx, OUT, 1.0)
    circle(ctx, 7, 8, 1.6)
    fill(ctx, OUT)
    return add_grit(cv.pil(), 0.02, 'arm')


def hand_image(iid):
    c = COLORS[iid]
    cv = Canvas(24, 24)
    ctx = cv.ctx
    wide = 'stack' in iid
    spread = 6.0 if wide else 4.6
    # wrist block (left), fingers pointing right
    wh = 14 if wide else 11
    rrect(ctx, 3, 12 - wh / 2, 8, wh, 2.5)
    ctx.set_source(_sym(12 - wh / 2, 12 + wh / 2, c)); ctx.fill()
    rrect(ctx, 3.5, 12 - wh / 2 + 0.5, 7, wh - 1, 2.5)
    stroke(ctx, OUT, 1.0)
    for sgn in (-1, 1):
        y = 12 + sgn * spread
        pts = [(10, y - 2), (18, y - 2 + (0 if sgn < 0 else 0.5)), (21.5, y - sgn * 2.2), (19, y + 2), (10, y + 2)]
        poly(ctx, pts)
        ctx.set_source(_sym(y - 2, y + 2, P['steel_l'])); ctx.fill()
        poly(ctx, pts)
        stroke(ctx, OUT, 1.0)
    if wide:
        rrect(ctx, 10, 10.5, 9, 3, 1)
        fill(ctx, P['steel_l'])
        rrect(ctx, 10, 10.5, 9, 3, 1)
        stroke(ctx, OUT, 0.8)
    return add_grit(cv.pil(), 0.02, 'hand')


def composite(base, arm, hand, length=0.62):
    """Base with the arm pointing north, partly extended (for e_<id> / item icons)."""
    out = base.copy()
    big = Image.new('RGBA', (128, 128))
    aw = int(64 * length)
    a = arm.resize((aw, 16), Image.LANCZOS)
    big.alpha_composite(a, (64 - 7, 64 - 8))       # pivot hub (7, 8) -> centre
    big.alpha_composite(hand, (64 - 7 + aw - 8, 64 - 12))
    big = big.rotate(90, center=(64, 64), resample=Image.BICUBIC)   # +x -> north
    big = with_shadow(big, 3, 4, 1.6, 0.45)
    out.alpha_composite(big.crop((33, 33, 97, 97)))
    return out


def generate(reg, data):
    for e in data['entities']:
        if e['kind'] != 'inserter':
            continue
        iid = e['id']
        b = reg.add(f'ins_{iid}_base', base_image(iid), 'inserters')
        a = reg.add(f'ins_{iid}_arm', arm_image(iid), 'inserters')
        h = reg.add(f'ins_{iid}_hand', hand_image(iid), 'inserters')
        reg.add(f'e_{iid}', composite(b, a, h, 0.75 if 'long' in iid else 0.55), 'inserters', keep=True)
