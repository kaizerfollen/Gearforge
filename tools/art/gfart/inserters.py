"""Inserters: a static base plus separate arm and hand parts so the renderer can rotate/extend the arm.

Sprites (per inserter id)
  entity_<id>_base            64x64 (+pad), non-directional, anchor = tile centre (= arm pivot)
  entity_<id>_arm             telescoping arm pointing NORTH; anchor = pivot; natural length `armLength` px
                              (scale yScale = wantedLength / armLength, rotate zRotation to the hand angle)
  entity_<id>_hand_open|closed  claw pointing NORTH, anchor = grip centre (place it at the hand position)
  entity_<id>_<dir>           pre-composited still (base + arm + hand) for ghosts, icons and far zoom
Arm/hand shading is symmetric across the arm axis so any rotation still reads as lit from above.
"""
from __future__ import annotations

import math

from PIL import Image

from .common import (T, DIRS, ECanvas, Canvas, INSERTER_COLORS, P, alpha, bolt, circle, cyl_v, fill, fill_grad,
                     hexc, lin, rad, rrect, shade, stroke, with_shadow, add_grit, poly, rotate_img)

ARM_W = 12


def base_image(iid: str):
    c = INSERTER_COLORS[iid]
    cv = ECanvas(1, 1, (4, 10, 8, 8))
    ctx = cv.ctx
    # mounting plate
    rrect(ctx, 10, 12, 44, 44, 6)
    fill_grad(ctx, lin(0, 12, 0, 56, [(0, shade(P['steel_m'], 1.05)), (1, shade(P['steel'], 0.8))]))
    rrect(ctx, 10, 12, 44, 40, 6)
    fill_grad(ctx, lin(10, 12, 40, 52, [(0, shade(P['steel_l'], 0.95)), (1, shade(P['steel_m'], 0.85))]))
    rrect(ctx, 10.5, 12.5, 43, 43, 6)
    stroke(ctx, P['outline'], 1.0)
    for (x, y) in ((15, 17), (49, 17), (15, 47), (49, 47)):
        bolt(ctx, x, y, 1.6)
    if 'burner' in iid:
        # little firebox on the side
        rrect(ctx, 40, 36, 12, 12, 2)
        fill(ctx, hexc('#2a2420'))
        circle(ctx, 46, 42, 3.2)
        fill_grad(ctx, rad(46, 42, 0, 4, [(0, P['fire_l']), (1, alpha(P['fire'], 0.2))]))
    if 'filter' in iid:
        # filter indicator: small funnel plate
        poly(ctx, [(14, 40), (24, 40), (21, 46), (17, 46)])
        fill(ctx, shade(c, 1.2))
        poly(ctx, [(14, 40), (24, 40), (21, 46), (17, 46)])
        stroke(ctx, P['outline'], 0.8)
    if 'stack' in iid:
        for k in range(3):
            rrect(ctx, 40, 18 + k * 4, 10, 3, 1)
            fill(ctx, shade(c, 1.15 - k * 0.12))
    # hub (tier coloured cylinder)
    cyl_v(ctx, 32, 28, 12, 7, c, ry=7.5)
    circle(ctx, 32, 28, 5.5)
    fill_grad(ctx, rad(30, 26, 0, 6, [(0, P['steel_h']), (1, P['steel'])]))
    circle(ctx, 32, 28, 5.5)
    stroke(ctx, P['outline'], 1.0)
    circle(ctx, 32, 28, 1.6)
    fill(ctx, P['outline'])
    return cv.finish(shadow=True, dx=3, dy=4, blur=2, strength=0.45)


def arm_image(iid: str, length: int):
    """Arm pointing up; pivot at (W/2, H - pad)."""
    c = INSERTER_COLORS[iid]
    pad = 6
    W, H = ARM_W + 4, length + 2 * pad
    cv = Canvas(W, H)
    ctx = cv.ctx
    cx, py = W / 2, H - pad
    w = ARM_W
    def sym(x0, x1, col):
        return lin(x0, 0, x1, 0, [(0, shade(col, 0.55)), (0.35, shade(col, 1.25)), (0.5, shade(col, 1.35)),
                                  (0.65, shade(col, 1.1)), (1, shade(col, 0.5))])
    # inner rod (front 55 %)
    rrect(ctx, cx - w * 0.28, pad - 2, w * 0.56, length * 0.6, 2)
    ctx.set_source(sym(cx - w * 0.28, cx + w * 0.28, P['steel_l'])); ctx.fill()
    rrect(ctx, cx - w * 0.28 + 0.5, pad - 1.5, w * 0.56 - 1, length * 0.6 - 1, 2)
    stroke(ctx, P['outline'], 1.0)
    # outer sleeve (tier colour, rear 65 %)
    y0 = pad + length * 0.32
    rrect(ctx, cx - w / 2, y0, w, py - y0 + 2, 3)
    ctx.set_source(sym(cx - w / 2, cx + w / 2, c)); ctx.fill()
    rrect(ctx, cx - w / 2 + 0.5, y0 + 0.5, w - 1, py - y0 + 1, 3)
    stroke(ctx, P['outline'], 1.0)
    # sleeve collar
    rrect(ctx, cx - w / 2 - 0.5, y0, w + 1, 4, 1.5)
    ctx.set_source(sym(cx - w / 2, cx + w / 2, P['steel_m'])); ctx.fill()
    rrect(ctx, cx - w / 2, y0 + 0.5, w, 3, 1.5)
    stroke(ctx, P['outline'], 0.8)
    # stripes on long arms
    if length > 80:
        for k in range(3):
            yy = y0 + 12 + k * 14
            ctx.rectangle(cx - w / 2 + 1, yy, w - 2, 3)
            fill(ctx, alpha(P['outline'], 0.35))
    img = add_grit(cv.pil(), 0.02, 'arm')
    anchor = (0.5, pad / H)
    return img, anchor


def hand_image(iid: str, closed: bool):
    c = INSERTER_COLORS[iid]
    S = 28
    cv = Canvas(S, S)
    ctx = cv.ctx
    cx, cy = S / 2, S / 2
    spread = 3.0 if closed else 7.0
    wide = 'stack' in iid
    # wrist block
    ww = 14 if wide else 11
    rrect(ctx, cx - ww / 2, cy + 2, ww, 8, 2.5)
    fill_grad(ctx, lin(cx - ww / 2, 0, cx + ww / 2, 0, [(0, shade(c, 0.6)), (0.4, shade(c, 1.3)), (1, shade(c, 0.55))]))
    rrect(ctx, cx - ww / 2 + 0.5, cy + 2.5, ww - 1, 7, 2.5)
    stroke(ctx, P['outline'], 1.0)
    # two fingers
    for sgn in (-1, 1):
        x = cx + sgn * spread
        pts = [(x - 2, cy + 3), (x + 2, cy + 3), (x + 2 - sgn * 1.5, cy - 9), (x - sgn * 2.5, cy - 11), (x - 2, cy - 8)]
        if sgn < 0:
            pts = [(x - 2, cy + 3), (x + 2, cy + 3), (x + 2, cy - 8), (x + 2.5, cy - 11), (x - 2 + 1.5, cy - 9)]
        poly(ctx, pts)
        fill_grad(ctx, lin(x - 2.5, 0, x + 2.5, 0, [(0, shade(P['steel_l'], 0.7)), (0.5, P['steel_h']), (1, shade(P['steel_l'], 0.6))]))
        poly(ctx, pts)
        stroke(ctx, P['outline'], 1.0)
    if wide:
        rrect(ctx, cx - 1.5, cy - 7, 3, 9, 1)
        fill(ctx, P['steel_l'])
        rrect(ctx, cx - 1.5, cy - 7, 3, 9, 1)
        stroke(ctx, P['outline'], 0.8)
    return cv.pil(), (0.5, 0.5)


def composite(base, base_anchor, arm, arm_anchor, hand, d: int, length: int):
    """Base with the arm resting halfway, pointing towards the drop side (direction d)."""
    W, H = base.size
    out = base.copy()
    px, py = base_anchor[0] * W, (1 - base_anchor[1]) * H
    # rotate arm canvas around its pivot so it points along d; draw slightly shortened
    a = arm.copy()
    arm_scaled = a.resize((a.width, max(8, int(a.height * 0.62))), Image.LANCZOS)
    hp = (0.5, arm_anchor[1] / 0.62 * 0.62)
    aw, ah = arm_scaled.size
    pivot = (aw * 0.5, ah - 6)
    big = Image.new('RGBA', (W * 2, H * 2), (0, 0, 0, 0))
    big.alpha_composite(arm_scaled, (int(W - pivot[0]), int(H - pivot[1])))
    tip_len = pivot[1] - 4
    big.alpha_composite(hand, (int(W - hand.width / 2), int(H - tip_len - hand.height / 2)))
    big = big.rotate(-90 * d, center=(W, H), resample=Image.BICUBIC)
    big = with_shadow(big, 3, 5, 1.6, 0.4)
    out.alpha_composite(big.crop((int(W - px), int(H - py), int(W - px) + W, int(H - py) + H)))
    return out


def generate(reg, data):
    meta = {}
    for e in data['entities']:
        if e['kind'] != 'inserter' or e['phase'] != 'mvp':
            continue
        iid = e['id']
        ins = e['inserter']
        length = int(round(abs(ins['pickup']['y']) * T))
        base, ba = base_image(iid)
        reg.add(f'entity_{iid}_base', base, 'inserters', ba)
        arm, aa = arm_image(iid, length)
        reg.add(f'entity_{iid}_arm', arm, 'inserters', aa, armLength=length)
        for closed in (False, True):
            hand, ha = hand_image(iid, closed)
            reg.add(f'entity_{iid}_hand_{"closed" if closed else "open"}', hand, 'inserters', ha)
        hand, _ = hand_image(iid, True)
        for d, dn in enumerate(DIRS):
            reg.add(f'entity_{iid}_{dn}', composite(base, ba, arm, aa, hand, d, length), 'inserters', ba)
    return meta
