"""Machines and other placeable entities (everything not covered by belts / inserters / pipes / poles / natural).

Naming: e_<id> (idle, north), e_<id>_<dir> for directional entities, e_<id>[_<dir>]_w<k> (k = 0..3) working frames.
Each draw function has the signature f(d, frame) -> PIL image, where d = 0..3 (n, e, s, w) and frame is None for
the idle look or 0..3 for the working animation.
"""
from __future__ import annotations

import math

from PIL import Image

from .base import (BODY, BODY_D, BODY_L, OUT, Fr, arrow, bevel_box, fan, finish, flange_at, fluid_port, glow_spot,
                   hazard_band, inset_box, light_lamp, machine_frame, pipe_seg, rivets)
from .common import (T, Canvas, P, alpha, bolt, circle, ellipse, fill, fill_grad, gear_path, hexc, lin, mix, rad,
                     rng, rrect, shade, src, stroke, poly)

DIRS = ['n', 'e', 's', 'w']
FIRE = [0.78, 1.0, 0.86, 0.95]
GREEN = hexc('#6dff8a')
AMBER = hexc('#ffb03a')
RED = hexc('#ff4a3a')


def status(ctx, x, y, frame, color=GREEN):
    light_lamp(ctx, x, y, 2.4, color if frame is not None else color, on=frame is not None and frame % 2 == 0 or frame == 1)


def cyl_top(ctx, cx, cy, r, c, rim=True, cap=True):
    """Upright cylinder seen from above: shaded disc + rim + cap plate."""
    circle(ctx, cx, cy, r)
    fill_grad(ctx, lin(cx - r, cy - r, cx + r, cy + r, [(0, shade(c, 1.35)), (0.5, c), (1, shade(c, 0.5))]))
    circle(ctx, cx, cy, r - 0.5)
    stroke(ctx, OUT, 1.2)
    if rim:
        circle(ctx, cx, cy, r * 0.82)
        fill_grad(ctx, lin(cx - r, cy - r, cx + r, cy + r, [(0, shade(c, 0.8)), (1, shade(c, 1.15))]))
        circle(ctx, cx, cy, r * 0.82)
        stroke(ctx, alpha(OUT, 0.5), 0.8)
    if cap:
        circle(ctx, cx, cy, r * 0.62)
        fill_grad(ctx, rad(cx - r * 0.25, cy - r * 0.25, 0, r * 0.75, [(0, shade(c, 1.3)), (1, shade(c, 0.85))]))
        circle(ctx, cx, cy, r * 0.62)
        stroke(ctx, alpha(OUT, 0.6), 0.8)


def capsule(ctx, x, y, w, h, c):
    """A lying cylinder (tank) seen from above; long axis = the longer side."""
    r = min(w, h) / 2
    rrect(ctx, x, y, w, h, r)
    if w >= h:
        g = lin(0, y, 0, y + h, [(0, shade(c, 0.85)), (0.25, shade(c, 1.4)), (0.55, c), (1, shade(c, 0.45))])
    else:
        g = lin(x, 0, x + w, 0, [(0, shade(c, 0.85)), (0.25, shade(c, 1.4)), (0.55, c), (1, shade(c, 0.45))])
    fill_grad(ctx, g)
    rrect(ctx, x + 0.5, y + 0.5, w - 1, h - 1, r)
    stroke(ctx, OUT, 1.2)


def bands(ctx, x, y, w, h, n, c, horizontal_tank=True):
    for i in range(1, n + 1):
        if horizontal_tank:
            bx = x + w * i / (n + 1)
            ctx.rectangle(bx - 1.5, y + 1, 3, h - 2)
        else:
            by = y + h * i / (n + 1)
            ctx.rectangle(x + 1, by - 1.5, w - 2, 3)
        fill(ctx, alpha(shade(c, 0.55), 0.8))


def window_glow(ctx, x, y, w, h, frame, base=None, r=3):
    """A furnace window: dark when idle, orange flickering when working."""
    rrect(ctx, x, y, w, h, r)
    fill(ctx, hexc('#120d0a'))
    if frame is not None:
        f = FIRE[frame]
        rrect(ctx, x + 1, y + 1, w - 2, h - 2, r)
        fill_grad(ctx, rad(x + w / 2, y + h * 0.65, 0, max(w, h) * 0.7,
                           [(0, alpha(hexc('#fff2b0'), f)), (0.35, alpha(P['fire_l'], f)), (0.8, alpha(P['fire'], 0.85 * f)), (1, alpha(hexc('#7a1e08'), 0.8))]))
    rrect(ctx, x + 0.5, y + 0.5, w - 1, h - 1, r)
    stroke(ctx, OUT, 1.2)


# ============================================================================================ chests

def chest(kind):
    def f(d, frame):
        cv = Canvas(64, 64)
        ctx = cv.ctx
        if kind == 'wooden_chest':
            c = P['wood']
            bevel_box(ctx, 7, 8, 49, 47, c, r=4, bev=2.5)
            for k in range(1, 4):
                yy = 10 + k * 11
                ctx.move_to(10, yy); ctx.line_to(53, yy)
                stroke(ctx, alpha(P['wood_d'], 0.8), 1.2)
            for x in (14, 48):
                ctx.rectangle(x - 2.5, 9, 5, 45)
                fill_grad(ctx, lin(x - 2.5, 0, x + 2.5, 0, [(0, P['steel_l']), (1, P['steel_d'])]))
                bolt(ctx, x, 14, 1.2); bolt(ctx, x, 49, 1.2)
            rrect(ctx, 27, 27, 9, 8, 1.5)
            fill_grad(ctx, lin(27, 27, 36, 35, [(0, P['brass_l']), (1, P['brass_d'])]))
            rrect(ctx, 27, 27, 9, 8, 1.5)
            stroke(ctx, OUT, 0.8)
        elif kind == 'iron_chest':
            c = hexc('#7b848c')
            bevel_box(ctx, 6, 7, 51, 49, c, r=4, bev=3)
            inset_box(ctx, 13, 14, 37, 35, shade(c, 0.95), r=2)
            ctx.move_to(13, 31.5); ctx.line_to(50, 31.5)
            stroke(ctx, alpha(OUT, 0.8), 1.5)
            rivets(ctx, 6, 7, 51, 49, inset=3.8, r=1.5, mid=True)
            rrect(ctx, 27, 28, 9, 7, 1.5)
            fill_grad(ctx, lin(27, 28, 36, 35, [(0, P['steel_h']), (1, P['steel'])]))
            rrect(ctx, 27, 28, 9, 7, 1.5)
            stroke(ctx, OUT, 0.8)
        else:  # steel
            c = hexc('#58687a')
            bevel_box(ctx, 5, 6, 53, 51, c, r=5, bev=3)
            bevel_box(ctx, 11, 12, 41, 39, shade(c, 1.1), r=3, bev=2)
            for (a, b) in (((13, 14), (50, 49)), ((50, 14), (13, 49))):
                ctx.move_to(*a); ctx.line_to(*b)
                stroke(ctx, alpha(OUT, 0.7), 3.6)
                ctx.move_to(*a); ctx.line_to(*b)
                stroke(ctx, shade(c, 1.35), 1.8)
            rivets(ctx, 5, 6, 53, 51, inset=3.5, r=1.5)
            rrect(ctx, 26, 27, 11, 9, 2)
            fill_grad(ctx, lin(26, 27, 37, 36, [(0, P['brass_l']), (1, P['brass_d'])]))
            rrect(ctx, 26, 27, 11, 9, 2)
            stroke(ctx, OUT, 0.9)
        return finish(cv, seed=kind)
    return f


# ============================================================================================ crafting machines

AM = {1: (hexc('#6e747b'), hexc('#d9a02a')), 2: (hexc('#5a7590'), hexc('#d2402e')), 3: (hexc('#5f826d'), hexc('#2f86d6'))}


def assembler(tier):
    body, acc = AM[tier]

    def f(d, frame):
        cv = Canvas(192, 192)
        ctx = cv.ctx
        ix, iy, iw, ih = machine_frame(ctx, 3, 3, acc, body)
        cx, cy = 92.5, 92.5
        # four corner service blocks
        for (x, y) in ((ix + 6, iy + 6), (ix + iw - 32, iy + 6), (ix + 6, iy + ih - 32), (ix + iw - 32, iy + ih - 32)):
            bevel_box(ctx, x, y, 26, 26, shade(body, 0.9), r=4, bev=2)
            inset_box(ctx, x + 6, y + 6, 14, 14, BODY_D, r=2)
        # vents on the four edges between the corner blocks
        from .base import vents_box
        vents_box(ctx, cx - 22, iy + 4, 44, 9, 5, True)
        vents_box(ctx, cx - 22, iy + ih - 13, 44, 9, 5, True)
        vents_box(ctx, ix + 4, cy - 22, 9, 44, 5, False)
        vents_box(ctx, ix + iw - 13, cy - 22, 9, 44, 5, False)
        # tier pips on the top-left block
        for k in range(tier):
            light_lamp(ctx, ix + 12 + k * 7, iy + 19, 2.0, acc, on=True)
        # crafting chamber
        circle(ctx, cx, cy, 52)
        fill_grad(ctx, lin(cx - 52, cy - 52, cx + 52, cy + 52, [(0, shade(body, 1.35)), (1, shade(body, 0.55))]))
        circle(ctx, cx, cy, 52)
        stroke(ctx, OUT, 1.4)
        circle(ctx, cx, cy, 44)
        fill_grad(ctx, lin(cx - 44, cy - 44, cx + 44, cy + 44, [(0, hexc('#15191c')), (1, hexc('#2c3237'))]))
        circle(ctx, cx, cy, 44)
        stroke(ctx, OUT, 1.2)
        # ring of bolts on the chamber lip
        for i in range(12):
            a = i * math.tau / 12
            bolt(ctx, cx + math.cos(a) * 48, cy + math.sin(a) * 48, 1.4)
        if frame is not None:
            glow_spot(ctx, cx, cy, 40, acc, 0.35)
        # rotating 4-arm manipulator
        rot = (frame or 0) * math.pi / 8 + math.pi / 8
        for i in range(4):
            a = rot + i * math.pi / 2
            ctx.save()
            ctx.translate(cx, cy)
            ctx.rotate(a)
            rrect(ctx, 6, -5, 32, 10, 3)
            ctx.restore()
            fill(ctx, OUT, preserve=False)
            ctx.save(); ctx.translate(cx, cy); ctx.rotate(a)
            rrect(ctx, 7, -4, 30, 8, 2.5)
            ctx.restore()
            fill_grad(ctx, lin(cx - 38, cy - 38, cx + 38, cy + 38, [(0, shade(acc, 1.35)), (1, shade(acc, 0.7))]))
            hx, hy = cx + math.cos(a) * 37, cy + math.sin(a) * 37
            circle(ctx, hx, hy, 5)
            fill_grad(ctx, rad(hx - 1.5, hy - 1.5, 0, 6, [(0, P['steel_h']), (1, P['steel'])]))
            circle(ctx, hx, hy, 5)
            stroke(ctx, OUT, 1.0)
        gear_path(ctx, cx, cy, 15, 11.5, 10, rot * 0.5)
        fill_grad(ctx, rad(cx - 4, cy - 4, 0, 16, [(0, P['steel_h']), (1, P['steel'])]), preserve=True)
        stroke(ctx, OUT, 1.1)
        circle(ctx, cx, cy, 5)
        fill(ctx, BODY_D, preserve=True)
        stroke(ctx, OUT, 1.0)
        light_lamp(ctx, ix + iw - 12, iy + ih - 12, 2.6, GREEN, on=frame is not None and frame % 2 == 0)
        return finish(cv, seed=f'am{tier}')
    return f


def lab(d, frame):
    cv = Canvas(192, 192)
    ctx = cv.ctx
    ix, iy, iw, ih = machine_frame(ctx, 3, 3, hexc('#d8dde2'), hexc('#7d8a96'))
    cx, cy = 92.5, 92.5
    # hexagonal base ring
    pts = [(cx + math.cos(a) * 62, cy + math.sin(a) * 62) for a in [math.pi / 6 + k * math.pi / 3 for k in range(6)]]
    poly(ctx, pts)
    fill_grad(ctx, lin(cx - 60, cy - 60, cx + 60, cy + 60, [(0, hexc('#e7ecf0')), (1, hexc('#8a96a2'))]), preserve=True)
    stroke(ctx, OUT, 1.4)
    # card slots around the dome (7 colours)
    cols = ['#d43c2f', '#4cb43a', '#3a3d42', '#3a8fd8', '#9a4fc8', '#e8c62c', '#eef0f2']
    for k, c in enumerate(cols):
        a = -math.pi / 2 + k * math.tau / 7
        x, y = cx + math.cos(a) * 50, cy + math.sin(a) * 50
        ctx.save(); ctx.translate(x, y); ctx.rotate(a + math.pi / 2)
        rrect(ctx, -5, -3.5, 10, 7, 1.5)
        ctx.restore()
        fill(ctx, hexc(c), preserve=True)
        stroke(ctx, OUT, 1.0)
    # glass dome
    pulse = [0.55, 0.85, 1.0, 0.75][frame] if frame is not None else 0
    circle(ctx, cx, cy, 38)
    fill_grad(ctx, rad(cx - 12, cy - 14, 2, 42, [(0, hexc('#d8f6ff')), (0.35, hexc('#6fc3dc')), (1, hexc('#1f5a70'))]))
    if frame is not None:
        hue = [hexc('#7ef0ff'), hexc('#a8ff8a'), hexc('#ffd86a'), hexc('#d89aff')][frame]
        glow_spot(ctx, cx, cy, 36, hue, 0.7 * pulse + 0.2)
    # inner apparatus visible through glass
    circle(ctx, cx, cy, 14)
    fill(ctx, alpha(hexc('#2a3a44'), 0.7))
    for k in range(3):
        a = k * math.tau / 3 + (frame or 0) * math.pi / 6
        ctx.move_to(cx, cy); ctx.line_to(cx + math.cos(a) * 26, cy + math.sin(a) * 26)
        stroke(ctx, alpha(hexc('#20323c'), 0.75), 3)
        circle(ctx, cx + math.cos(a) * 26, cy + math.sin(a) * 26, 4)
        fill(ctx, alpha(hexc('#e8f4ff'), 0.85))
    circle(ctx, cx, cy, 38)
    stroke(ctx, OUT, 1.6)
    # specular highlight
    ctx.save(); ctx.translate(cx - 13, cy - 15); ctx.rotate(-0.7); ctx.scale(1, 0.45)
    circle(ctx, 0, 0, 13)
    ctx.restore()
    fill(ctx, alpha(hexc('#ffffff'), 0.55))
    light_lamp(ctx, ix + iw - 12, iy + ih - 12, 2.6, GREEN, on=frame is not None and frame % 2 == 0)
    return finish(cv, seed='lab')


def furnace_stone(d, frame):
    cv = Canvas(128, 128)
    ctx = cv.ctx
    stone, stone_l, stone_d = P['stone'], P['stone_l'], P['stone_d']
    # rounded stone body
    rrect(ctx, 3, 3, 117, 117, 22)
    fill_grad(ctx, lin(3, 3, 120, 120, [(0, shade(stone, 1.15)), (1, shade(stone, 0.6))]))
    rrect(ctx, 3.5, 3.5, 116, 116, 22)
    stroke(ctx, OUT, 1.4)
    # brick courses (concentric rounded rings of blocks)
    r = rng('stonefurnace')
    for ring, (inset, n) in enumerate(((8, 16), (24, 12))):
        s = 117 - 2 * inset
        x0 = 3 + inset
        for k in range(n):
            # bricks along the ring perimeter
            t0, t1 = k / n, (k + 0.92) / n
            per = 4 * s
            def at(t):
                p = (t % 1) * per
                if p < s: return (x0 + p, x0)
                if p < 2 * s: return (x0 + s, x0 + p - s)
                if p < 3 * s: return (x0 + 3 * s - p, x0 + s)
                return (x0, x0 + 4 * s - p)
            (ax, ay), (bx, by) = at(t0), at(t1)
            if abs(ax - bx) > 1 and abs(ay - by) > 1:
                continue
            cxx, cyy = (ax + bx) / 2, (ay + by) / 2
            bw = max(abs(ax - bx), 12)
            bh = max(abs(ay - by), 12)
            c = shade(stone, r.uniform(0.85, 1.12))
            bevel_box(ctx, cxx - bw / 2, cyy - bh / 2, bw, bh, c, r=3, bev=1.6, outline=True)
    # fire pit
    window_glow(ctx, 40, 40, 43, 43, frame, r=14)
    # grate bars
    for k in range(4):
        x = 47 + k * 9.5
        ctx.move_to(x, 44); ctx.line_to(x, 79)
        stroke(ctx, alpha(hexc('#2a2420'), 0.9), 2.4)
    if frame is not None:
        glow_spot(ctx, 61.5, 61.5, 50, P['fire'], 0.25 * FIRE[frame])
    return finish(cv, seed='stonef')


def furnace_steel(d, frame):
    cv = Canvas(128, 128)
    ctx = cv.ctx
    c = hexc('#5b6670')
    bevel_box(ctx, 3, 3, 117, 117, shade(c, 0.85), r=10, bev=3.5)
    bevel_box(ctx, 12, 12, 99, 99, c, r=7, bev=2.5)
    rivets(ctx, 3, 3, 117, 117, inset=5, r=1.6, mid=True)
    # heat shield plates
    for (x, y) in ((18, 18), (18, 86)):
        rrect(ctx, x, y, 87, 19, 3)
        fill_grad(ctx, lin(0, y, 0, y + 19, [(0, shade(c, 1.25)), (1, shade(c, 0.7))]))
        rrect(ctx, x + 0.5, y + 0.5, 86, 18, 3)
        stroke(ctx, alpha(OUT, 0.8), 1.0)
        for k in range(6):
            ctx.move_to(x + 8 + k * 14, y + 4); ctx.line_to(x + 8 + k * 14, y + 15)
            stroke(ctx, alpha(OUT, 0.5), 2)
    window_glow(ctx, 30, 41, 63, 41, frame, r=6)
    for k in range(5):
        ctx.move_to(36 + k * 12.5, 43); ctx.line_to(36 + k * 12.5, 80)
        stroke(ctx, alpha(hexc('#1d2024'), 0.9), 2.2)
    if frame is not None:
        glow_spot(ctx, 61.5, 61.5, 52, P['fire'], 0.25 * FIRE[frame])
    # chimney (top-right)
    cyl_top(ctx, 98, 26, 10, hexc('#3b4248'), cap=False)
    circle(ctx, 98, 26, 6)
    fill(ctx, hexc('#0d0f10'))
    return finish(cv, seed='steelf')


def furnace_electric(d, frame):
    cv = Canvas(192, 192)
    ctx = cv.ctx
    ix, iy, iw, ih = machine_frame(ctx, 3, 3, hexc('#c94a2a'), hexc('#a7b0b8'))
    cx, cy = 92.5, 92.5
    inset_box(ctx, cx - 50, cy - 50, 100, 100, hexc('#3a3f44'), r=10)
    f = FIRE[frame] if frame is not None else 0
    # heating coils (concentric square spirals)
    for k in range(4):
        s = 84 - k * 20
        rrect(ctx, cx - s / 2, cy - s / 2, s, s, 6)
        stroke(ctx, OUT, 6)
        rrect(ctx, cx - s / 2, cy - s / 2, s, s, 6)
        if frame is not None:
            hot = mix(hexc('#ff5a1a'), hexc('#ffe08a'), (k / 3) * f)
            stroke(ctx, hot, 3.6)
        else:
            stroke(ctx, hexc('#7a5a4a'), 3.6)
    if frame is not None:
        glow_spot(ctx, cx, cy, 60, hexc('#ff7a2a'), 0.45 * f)
    # side ceramic insulators
    for (x, y) in ((ix + 10, cy), (ix + iw - 10, cy), (cx, iy + 10), (cx, iy + ih - 10)):
        circle(ctx, x, y, 6)
        fill_grad(ctx, rad(x - 2, y - 2, 0, 7, [(0, hexc('#ffffff')), (1, hexc('#9aa6b0'))]), preserve=True)
        stroke(ctx, OUT, 1.0)
    light_lamp(ctx, ix + iw - 12, iy + ih - 12, 2.6, GREEN, on=frame is not None and frame % 2 == 0)
    return finish(cv, seed='elf')


# ============================================================================================ drills

def drill_burner(d, frame):
    fr = Fr(128, 128, d)
    cv = Canvas(128, 128)
    ctx = cv.ctx
    c = hexc('#6f6458')
    bevel_box(ctx, 3, 3, 117, 117, shade(c, 0.85), r=10, bev=3.5)
    rivets(ctx, 3, 3, 117, 117, inset=5, r=1.6)
    # output chute toward the facing side (north frame: top edge)
    x, y, w, h = fr.rect(48, 0, 28, 18)
    bevel_box(ctx, x, y, w, h, hexc('#4d4740'), r=3, bev=2)
    arrow(ctx, fr, 62, 8, 6, P['hazard'], 2.4)
    # drill housing
    cxy = fr.pt(62, 62)
    rot = (frame or 0) * math.pi / 8
    gear_path(ctx, cxy[0], cxy[1], 30, 25, 14, rot)
    fill_grad(ctx, lin(cxy[0] - 30, cxy[1] - 30, cxy[0] + 30, cxy[1] + 30, [(0, P['steel_l']), (1, P['steel_d'])]), preserve=True)
    stroke(ctx, OUT, 1.2)
    circle(ctx, cxy[0], cxy[1], 20)
    fill_grad(ctx, lin(cxy[0] - 20, cxy[1] - 20, cxy[0] + 20, cxy[1] + 20, [(0, hexc('#2a2622')), (1, hexc('#4a443c'))]), preserve=True)
    stroke(ctx, OUT, 1.0)
    for k in range(3):
        a = rot * 2 + k * math.tau / 3
        ctx.move_to(cxy[0], cxy[1])
        ctx.line_to(cxy[0] + math.cos(a) * 17, cxy[1] + math.sin(a) * 17)
        stroke(ctx, P['steel_l'], 4)
    circle(ctx, cxy[0], cxy[1], 5)
    fill(ctx, P['brass'], preserve=True)
    stroke(ctx, OUT, 1)
    # firebox at the back (south in north frame) + chimney
    x, y, w, h = fr.rect(20, 96, 40, 20)
    bevel_box(ctx, x, y, w, h, hexc('#3d3833'), r=3, bev=2)
    wx, wy, ww, wh = fr.rect(26, 101, 28, 10)
    window_glow(ctx, wx, wy, ww, wh, frame, r=2)
    chx, chy = fr.pt(92, 104)
    cyl_top(ctx, chx, chy, 9, hexc('#3b3631'), cap=False)
    circle(ctx, chx, chy, 5)
    fill(ctx, hexc('#0d0c0b'))
    if frame is not None:
        glow_spot(ctx, *fr.pt(40, 106), 24, P['fire'], 0.35 * FIRE[frame])
    return finish(cv, seed='bdrill')


def drill_electric(d, frame):
    fr = Fr(192, 192, d)
    cv = Canvas(192, 192)
    ctx = cv.ctx
    ix, iy, iw, ih = machine_frame(ctx, 3, 3, P['hazard'], hexc('#66707a'))
    # output chute toward facing side
    x, y, w, h = fr.rect(78, 0, 36, 22)
    bevel_box(ctx, x, y, w, h, BODY_D, r=3, bev=2)
    hx, hy, hw, hh = fr.rect(80, 14, 32, 6)
    hazard_band(ctx, hx, hy, hw, hh, 6)
    arrow(ctx, fr, 96, 8, 8, P['hazard'], 2.6)
    # side motor housings (left/right in north frame)
    for xx in (14, 150):
        x, y, w, h = fr.rect(xx, 40, 28, 104)
        bevel_box(ctx, x, y, w, h, hexc('#58616a'), r=4, bev=2)
        vx, vy, vw, vh = fr.rect(xx + 6, 52, 16, 80)
        inset_box(ctx, vx, vy, vw, vh, BODY_D, r=2)
    cx, cy = fr.pt(96, 92)
    # drill head: big ring + 3 spiral cutters
    rot = (frame or 0) * math.pi / 6
    circle(ctx, cx, cy, 50)
    fill_grad(ctx, lin(cx - 50, cy - 50, cx + 50, cy + 50, [(0, P['steel_l']), (1, shade(P['steel_d'], 0.8))]))
    circle(ctx, cx, cy, 50)
    stroke(ctx, OUT, 1.4)
    for i in range(16):
        a = i * math.tau / 16
        bolt(ctx, cx + math.cos(a) * 45.5, cy + math.sin(a) * 45.5, 1.4)
    circle(ctx, cx, cy, 40)
    fill(ctx, hexc('#1a1d20'))
    for k in range(3):
        a = rot + k * math.tau / 3
        ctx.save(); ctx.translate(cx, cy); ctx.rotate(a)
        ctx.move_to(0, -6)
        ctx.curve_to(18, -10, 32, -2, 38, 12)
        ctx.line_to(30, 14)
        ctx.curve_to(24, 4, 14, 2, 0, 6)
        ctx.close_path()
        ctx.restore()
        fill_grad(ctx, lin(cx - 38, cy - 38, cx + 38, cy + 38, [(0, P['hazard']), (1, shade(P['hazard'], 0.55))]), preserve=True)
        stroke(ctx, OUT, 1.1)
    circle(ctx, cx, cy, 10)
    fill_grad(ctx, rad(cx - 3, cy - 3, 0, 11, [(0, P['steel_h']), (1, P['steel'])]), preserve=True)
    stroke(ctx, OUT, 1.1)
    lx, ly = fr.pt(170, 172)
    light_lamp(ctx, lx, ly, 2.6, GREEN, on=frame is not None and frame % 2 == 0)
    return finish(cv, seed='edrill')


def pumpjack(d, frame):
    cv = Canvas(192, 192)
    ctx = cv.ctx
    c = hexc('#5d6670')
    # concrete pad
    bevel_box(ctx, 6, 6, 173, 173, hexc('#8d8a82'), r=8, bev=3)
    hazard_band(ctx, 14, 14, 157, 8, 8)
    hazard_band(ctx, 14, 163, 157, 8, 8)
    # well head (south) with pipe stub
    cyl_top(ctx, 92, 142, 14, hexc('#4a5258'))
    circle(ctx, 92, 142, 5)
    fill(ctx, hexc('#121416'))
    # A-frame (samson post) at the centre
    bevel_box(ctx, 70, 80, 45, 24, shade(c, 0.9), r=4, bev=2)
    # walking beam along N-S; its head bobs (top-down: shifts and scales)
    off = [0, 4, 7, 4][frame] if frame is not None else 2
    bx0, bx1 = 92, 92
    rrect(ctx, 84, 34 - off, 17, 104 + off * 0.5, 4)
    fill_grad(ctx, lin(84, 0, 101, 0, [(0, shade(hexc('#c8402f'), 1.3)), (1, shade(hexc('#c8402f'), 0.6))]))
    rrect(ctx, 84.5, 34.5 - off, 16, 103 + off * 0.5, 4)
    stroke(ctx, OUT, 1.2)
    # horse head at the top end
    poly(ctx, [(78, 30 - off), (107, 30 - off), (103, 46 - off), (82, 46 - off)])
    fill_grad(ctx, lin(78, 30, 107, 46, [(0, P['steel_l']), (1, P['steel_d'])]), preserve=True)
    stroke(ctx, OUT, 1.2)
    # counterweight crank (south end)
    a = (frame or 0) * math.pi / 2
    circle(ctx, 92, 116, 16)
    fill_grad(ctx, lin(76, 100, 108, 132, [(0, P['steel_l']), (1, P['steel_d'])]), preserve=True)
    stroke(ctx, OUT, 1.2)
    ctx.save(); ctx.translate(92, 116); ctx.rotate(a)
    rrect(ctx, -6, -18, 12, 22, 3)
    ctx.restore()
    fill(ctx, hexc('#2c3136'), preserve=True)
    stroke(ctx, OUT, 1.0)
    bolt(ctx, 92, 116, 2.5, P['brass_l'])
    bolt(ctx, 92, 92, 3, P['steel_h'])
    return finish(cv, seed='pumpjack')


# ============================================================================================ power

def boiler(d, frame):
    fr = Fr(192, 128, d)
    W, H = fr.size
    cv = Canvas(W, H)
    ctx = cv.ctx
    # water ports (west/east) and steam output (north)
    fluid_port(ctx, fr, 0, 84, 'w', length=22)
    fluid_port(ctx, fr, 192, 84, 'e', length=22)
    fluid_port(ctx, fr, 96, 0, 'n', length=22)
    # main horizontal drum (in north frame)
    x, y, w, h = fr.rect(14, 18, 164, 52)
    capsule(ctx, x, y, w, h, hexc('#8a939b'))
    bands(ctx, x, y, w, h, 4, hexc('#8a939b'), horizontal_tank=(w >= h))
    # steam dome
    sx, sy = fr.pt(96, 34)
    cyl_top(ctx, sx, sy, 13, hexc('#9aa3ab'))
    # firebox block (south half)
    x, y, w, h = fr.rect(30, 70, 132, 50)
    bevel_box(ctx, x, y, w, h, hexc('#4a3f36'), r=6, bev=3)
    wx, wy, ww, wh = fr.rect(62, 82, 68, 26)
    window_glow(ctx, wx, wy, ww, wh, frame, r=4)
    for k in range(5):
        a = fr.pt(70 + k * 13, 84)
        b = fr.pt(70 + k * 13, 106)
        ctx.move_to(*a); ctx.line_to(*b)
        stroke(ctx, alpha(hexc('#1a1512'), 0.9), 2.2)
    rx, ry, rw, rh = fr.rect(30, 70, 132, 50)
    rivets(ctx, rx, ry, rw, rh, inset=5, r=1.5)
    if frame is not None:
        glow_spot(ctx, *fr.pt(96, 95), 50, P['fire'], 0.3 * FIRE[frame])
    return finish(cv, seed='boiler')


def steam_engine(d, frame):
    fr = Fr(192, 320, d)
    W, H = fr.size
    cv = Canvas(W, H)
    ctx = cv.ctx
    fluid_port(ctx, fr, 96, 0, 'n', length=24)
    fluid_port(ctx, fr, 96, 320, 's', length=24)
    # base skid
    x, y, w, h = fr.rect(22, 20, 146, 278)
    bevel_box(ctx, x, y, w, h, hexc('#4c545b'), r=8, bev=3)
    rivets(ctx, x, y, w, h, inset=6, r=1.6, mid=True)
    # cylinder (north part)
    x, y, w, h = fr.rect(56, 28, 78, 112)
    capsule(ctx, x, y, w, h, hexc('#8d969e'))
    bands(ctx, x, y, w, h, 3, hexc('#8d969e'), horizontal_tank=(w >= h))
    # piston rod (moves)
    po = [0, 10, 20, 10][frame] if frame is not None else 10
    a = fr.pt(95, 138); b = fr.pt(95, 170 + po)
    pipe_seg(ctx, a[0], a[1], b[0], b[1], 4, P['steel_h'])
    # flywheel (south part)
    cx, cy = fr.pt(95, 222)
    rot = (frame or 0) * math.pi / 8
    circle(ctx, cx, cy, 56)
    fill_grad(ctx, lin(cx - 56, cy - 56, cx + 56, cy + 56, [(0, hexc('#3a3f44')), (1, hexc('#1c1f22'))]))
    circle(ctx, cx, cy, 56)
    stroke(ctx, OUT, 1.4)
    circle(ctx, cx, cy, 50)
    stroke(ctx, hexc('#c56a35'), 7)
    circle(ctx, cx, cy, 50)
    stroke(ctx, alpha(OUT, 0.6), 1)
    for k in range(6):
        aa = rot + k * math.pi / 3
        ctx.move_to(cx, cy); ctx.line_to(cx + math.cos(aa) * 47, cy + math.sin(aa) * 47)
        stroke(ctx, OUT, 7)
        ctx.move_to(cx, cy); ctx.line_to(cx + math.cos(aa) * 47, cy + math.sin(aa) * 47)
        stroke(ctx, P['steel_l'], 4.5)
    circle(ctx, cx, cy, 12)
    fill_grad(ctx, rad(cx - 4, cy - 4, 0, 13, [(0, P['brass_h']), (1, P['brass_d'])]), preserve=True)
    stroke(ctx, OUT, 1.2)
    # crank pin
    pa = rot * 2
    bolt(ctx, cx + math.cos(pa) * 24, cy + math.sin(pa) * 24, 3.5, P['steel_h'])
    lx, ly = fr.pt(150, 290)
    light_lamp(ctx, lx, ly, 2.6, GREEN, on=frame is not None and frame % 2 == 0)
    return finish(cv, seed='steameng')


def solar_panel(d, frame):
    cv = Canvas(192, 192)
    ctx = cv.ctx
    bevel_box(ctx, 3, 3, 181, 181, hexc('#9aa3ab'), r=6, bev=3)
    cell = hexc('#1f3f78')
    for gy in range(3):
        for gx in range(3):
            x, y = 10 + gx * 56.5, 10 + gy * 56.5
            rrect(ctx, x, y, 53, 53, 2)
            fill_grad(ctx, lin(x, y, x + 53, y + 53, [(0, hexc('#4f7fc8')), (0.4, cell), (1, hexc('#0f2244'))]))
            for k in range(1, 4):
                ctx.move_to(x + k * 13.25, y + 1); ctx.line_to(x + k * 13.25, y + 52)
                ctx.move_to(x + 1, y + k * 13.25); ctx.line_to(x + 52, y + k * 13.25)
            stroke(ctx, alpha(hexc('#a9c6ff'), 0.35), 0.8)
            rrect(ctx, x + 0.5, y + 0.5, 52, 52, 2)
            stroke(ctx, OUT, 1.0)
            # specular stripe
            ctx.save(); rrect(ctx, x, y, 53, 53, 2); ctx.clip()
            poly(ctx, [(x + 6, y), (x + 20, y), (x, y + 20), (x, y + 6)])
            fill(ctx, alpha(hexc('#ffffff'), 0.18))
            ctx.restore()
    return finish(cv, seed='solar')


def accumulator(d, frame):
    cv = Canvas(128, 128)
    ctx = cv.ctx
    bevel_box(ctx, 3, 3, 117, 117, hexc('#4f585f'), r=8, bev=3)
    rivets(ctx, 3, 3, 117, 117, inset=5, r=1.5)
    for (x, y) in ((36, 36), (87, 36), (36, 87), (87, 87)):
        cyl_top(ctx, x, y, 22, hexc('#3f7f8a'))
        # terminals
        for sx, c in ((-7, hexc('#d84a3a')), (7, hexc('#3a6ad8'))):
            circle(ctx, x + sx, y, 3.5)
            fill(ctx, c, preserve=True)
            stroke(ctx, OUT, 0.9)
    # bus bars
    for (a, b) in (((43, 36), (80, 36)), ((43, 87), (80, 87))):
        ctx.move_to(*a); ctx.line_to(*b)
        stroke(ctx, OUT, 4); ctx.move_to(*a); ctx.line_to(*b)
        stroke(ctx, hexc('#c9773d'), 2.2)
    light_lamp(ctx, 61.5, 61.5, 3, GREEN)
    return finish(cv, seed='acc')


# ============================================================================================ fluids

def offshore_pump(d, frame):
    fr = Fr(64, 64, d)
    cv = Canvas(64, 64)
    ctx = cv.ctx
    # output pipe toward the facing side, intake grille at the back (over water)
    fluid_port(ctx, fr, 31, 0, 'n', length=14, r=8)
    x, y, w, h = fr.rect(3, 11, 56, 34)
    bevel_box(ctx, x, y, w, h, hexc('#6b7f8c'), r=6, bev=2.5)
    mx, my = fr.pt(31, 28)
    cyl_top(ctx, mx, my, 12, hexc('#3d6f9a'))
    x, y, w, h = fr.rect(6, 44, 50, 16)
    bevel_box(ctx, x, y, w, h, hexc('#3a444c'), r=3, bev=2)
    for k in range(6):
        a = fr.pt(11 + k * 8, 47); b = fr.pt(11 + k * 8, 57)
        ctx.move_to(*a); ctx.line_to(*b)
        stroke(ctx, OUT, 3)
        ctx.move_to(*a); ctx.line_to(*b)
        stroke(ctx, P['steel_l'], 1.6)
    x, y, w, h = fr.rect(3, 11, 56, 34)
    rivets(ctx, x, y, w, h, inset=3.5, r=1.3)
    return finish(cv, seed='offshore')


def pump(d, frame):
    fr = Fr(64, 128, d)
    W, H = fr.size
    cv = Canvas(W, H)
    ctx = cv.ctx
    a = fr.pt(31, 0); b = fr.pt(31, 128)
    pipe_seg(ctx, a[0], a[1], b[0], b[1], 9, hexc('#7d8894'))
    for yy in (3, 125):
        p = fr.pt(31, yy)
        flange_at(ctx, p[0], p[1], 9, abs(a[1] - b[1]) < 1e-6, P['brass'], 5)
    x, y, w, h = fr.rect(9, 30, 45, 66)
    bevel_box(ctx, x, y, w, h, hexc('#5d7a8f'), r=6, bev=2.5)
    mx, my = fr.pt(31, 56)
    fan(ctx, mx, my, 12, 5, 0.3)
    arrow(ctx, fr, 31, 84, 7, hexc('#7fe0ff'), 2.4)
    rivets(ctx, x, y, w, h, inset=3.5, r=1.3)
    return finish(cv, seed='pump')


def storage_tank(d, frame):
    fr = Fr(192, 192, d % 2)
    cv = Canvas(192, 192)
    ctx = cv.ctx
    # connection stubs (two diagonal corners; n/s identical, e/w mirrored)
    fluid_port(ctx, fr, 32, 0, 'n', length=26)
    fluid_port(ctx, fr, 160, 192, 's', length=26)
    fluid_port(ctx, fr, 0, 32, 'w', length=26)
    fluid_port(ctx, fr, 192, 160, 'e', length=26)
    cx, cy = 92.5, 92.5
    # legs at the corners
    for (x, y) in ((24, 24), (161, 24), (24, 161), (161, 161)):
        rrect(ctx, x - 9, y - 9, 18, 18, 3)
        fill_grad(ctx, lin(x - 9, y - 9, x + 9, y + 9, [(0, P['steel_l']), (1, P['steel_d'])]), preserve=True)
        stroke(ctx, OUT, 1.0)
    circle(ctx, cx, cy, 80)
    fill_grad(ctx, lin(cx - 80, cy - 80, cx + 80, cy + 80, [(0, hexc('#c9cfd4')), (0.5, hexc('#8c959d')), (1, hexc('#4a5258'))]))
    circle(ctx, cx, cy, 79.5)
    stroke(ctx, OUT, 1.5)
    for rr in (64, 44):
        circle(ctx, cx, cy, rr)
        stroke(ctx, alpha(OUT, 0.35), 1.2)
    for i in range(24):
        a = i * math.tau / 24
        bolt(ctx, cx + math.cos(a) * 73, cy + math.sin(a) * 73, 1.5)
    cyl_top(ctx, cx, cy, 16, hexc('#9aa3ab'))
    # hatch + level gauge
    rrect(ctx, cx + 26, cy - 44, 22, 14, 3)
    fill(ctx, hexc('#2a3036'), preserve=True)
    stroke(ctx, OUT, 1)
    rrect(ctx, cx + 28, cy - 42, 12, 10, 2)
    fill(ctx, hexc('#4fa8d8'))
    return finish(cv, seed='tank')


def chemical_plant(d, frame):
    fr = Fr(192, 192, d)
    cv = Canvas(192, 192)
    ctx = cv.ctx
    ix, iy, iw, ih = machine_frame(ctx, 3, 3, hexc('#3fae7a'), hexc('#6a7a72'))
    # inputs on the back edge, outputs on the front edge (north frame)
    for x in (32, 160):
        fluid_port(ctx, fr, x, 192, 's', length=16)
        fluid_port(ctx, fr, x, 0, 'n', length=16)
    # two reactor vessels with glass tops
    liquid = hexc('#7ad84a')
    for k, (vx, vy) in enumerate(((62, 72), (124, 116))):
        cx, cy = fr.pt(vx, vy)
        circle(ctx, cx, cy, 34)
        fill_grad(ctx, lin(cx - 34, cy - 34, cx + 34, cy + 34, [(0, P['steel_l']), (1, P['steel_d'])]))
        circle(ctx, cx, cy, 34)
        stroke(ctx, OUT, 1.3)
        circle(ctx, cx, cy, 25)
        fill_grad(ctx, rad(cx - 6, cy - 6, 2, 27, [(0, shade(liquid, 1.4)), (0.6, liquid), (1, shade(liquid, 0.4))]))
        if frame is not None:
            r = rng(f'bub{k}{frame}')
            for j in range(6):
                a = r.uniform(0, math.tau); dd = r.uniform(0, 18)
                circle(ctx, cx + math.cos(a) * dd, cy + math.sin(a) * dd, r.uniform(1.5, 3.5))
                fill(ctx, alpha(hexc('#eaffd8'), 0.75))
            glow_spot(ctx, cx, cy, 30, liquid, 0.35)
        # stirrer
        rot = (frame or 0) * math.pi / 4 + k
        ctx.save(); ctx.translate(cx, cy); ctx.rotate(rot)
        rrect(ctx, -20, -2.5, 40, 5, 2)
        ctx.restore()
        fill(ctx, alpha(hexc('#20302a'), 0.8))
        circle(ctx, cx, cy, 25)
        stroke(ctx, OUT, 1.2)
        ctx.save(); ctx.translate(cx - 9, cy - 10); ctx.rotate(-0.7); ctx.scale(1, 0.45)
        circle(ctx, 0, 0, 9)
        ctx.restore()
        fill(ctx, alpha(hexc('#ffffff'), 0.45))
    # connecting pipe between vessels
    a = fr.pt(124, 72); b = fr.pt(124, 82)
    cx1, cy1 = fr.pt(62, 116)
    cyl_top(ctx, cx1, cy1, 16, hexc('#b8862e'))
    cx2, cy2 = fr.pt(130, 60)
    cyl_top(ctx, cx2, cy2, 13, hexc('#5f6c75'))
    lx, ly = fr.pt(170, 172)
    light_lamp(ctx, lx, ly, 2.6, GREEN, on=frame is not None and frame % 2 == 0)
    return finish(cv, seed='chem')


def oil_refinery(d, frame):
    fr = Fr(320, 320, d)
    cv = Canvas(320, 320)
    ctx = cv.ctx
    # concrete pad
    bevel_box(ctx, 3, 3, 309, 309, hexc('#8d8a82'), r=10, bev=3.5)
    rivets(ctx, 3, 3, 309, 309, inset=6, r=1.8, mid=True)
    hx, hy, hw, hh = fr.rect(14, 292, 292, 9)
    hazard_band(ctx, hx, hy, hw, hh, 9)
    # inputs: back edge (2), outputs: front edge (3)
    for x in (96, 224):
        fluid_port(ctx, fr, x, 320, 's', length=26)
    for x in (32, 160, 288):
        fluid_port(ctx, fr, x, 0, 'n', length=26)
    # pipe rack linking things
    for (x0, y0, x1, y1) in ((32, 26, 32, 120), (160, 26, 160, 92), (288, 26, 288, 120), (96, 294, 96, 220), (224, 294, 224, 220)):
        a = fr.pt(x0, y0); b = fr.pt(x1, y1)
        pipe_seg(ctx, a[0], a[1], b[0], b[1], 6, hexc('#7d8894'))
    # two storage tanks
    for (x, y) in ((70, 100), (250, 100)):
        cx, cy = fr.pt(x, y)
        cyl_top(ctx, cx, cy, 40, hexc('#b8bfc5'))
        circle(ctx, cx, cy, 14)
        stroke(ctx, alpha(OUT, 0.4), 1)
    # distillation column (big tower) centre
    cx, cy = fr.pt(160, 170)
    circle(ctx, cx, cy, 58)
    fill_grad(ctx, lin(cx - 58, cy - 58, cx + 58, cy + 58, [(0, hexc('#d9a64a')), (0.5, hexc('#a8742a')), (1, hexc('#5a3c14'))]))
    circle(ctx, cx, cy, 57.5)
    stroke(ctx, OUT, 1.5)
    for rr in (48, 36):
        circle(ctx, cx, cy, rr)
        stroke(ctx, alpha(OUT, 0.45), 2)
    for i in range(16):
        a = i * math.tau / 16
        bolt(ctx, cx + math.cos(a) * 53, cy + math.sin(a) * 53, 1.6)
    cyl_top(ctx, cx, cy, 24, hexc('#c9cfd4'))
    # heater block (back)
    x, y, w, h = fr.rect(120, 236, 80, 44)
    bevel_box(ctx, x, y, w, h, hexc('#4a3f36'), r=5, bev=2.5)
    wx, wy, ww, wh = fr.rect(132, 246, 56, 22)
    window_glow(ctx, wx, wy, ww, wh, frame, r=3)
    # flare stack (corner) with flame when working
    fx, fy = fr.pt(282, 262)
    cyl_top(ctx, fx, fy, 14, hexc('#5a6168'), cap=False)
    circle(ctx, fx, fy, 8)
    fill(ctx, hexc('#121416'))
    if frame is not None:
        f = FIRE[frame]
        glow_spot(ctx, fx, fy, 30, P['fire'], 0.6 * f)
        circle(ctx, fx, fy, 6 + 2 * f)
        fill_grad(ctx, rad(fx, fy, 0, 8 + 2 * f, [(0, hexc('#fff4c0')), (0.5, P['fire_l']), (1, alpha(P['fire'], 0))]))
    for (x, y) in ((40, 280), (60, 280)):
        lx, ly = fr.pt(x, y)
        light_lamp(ctx, lx, ly, 3, GREEN if frame is not None else GREEN, on=frame is not None and frame % 2 == 0)
    return finish(cv, seed='refinery')


# ============================================================================================ misc

def beacon(d, frame):
    cv = Canvas(192, 192)
    ctx = cv.ctx
    ix, iy, iw, ih = machine_frame(ctx, 3, 3, hexc('#8a6ad8'), hexc('#5f6672'))
    cx, cy = 92.5, 92.5
    # module bays
    for (x, y) in ((ix + 10, iy + 10), (ix + iw - 34, iy + ih - 34)):
        inset_box(ctx, x, y, 24, 24, BODY_D, r=3)
        rrect(ctx, x + 6, y + 5, 12, 14, 2)
        fill(ctx, hexc('#4a6ad8'), preserve=True)
        stroke(ctx, OUT, 0.8)
    pulse = [0.4, 0.7, 1.0, 0.7][frame] if frame is not None else 0
    if frame is not None:
        for k in range(3):
            rr = 28 + ((frame + k * 1.33) % 4) * 11
            circle(ctx, cx, cy, rr)
            stroke(ctx, alpha(hexc('#c9a8ff'), 0.55 * (1 - (rr - 28) / 48)), 2.5)
    # pyramid emitter (4 faces lit differently)
    s = 30
    faces = [((cx - s, cy - s), (cx + s, cy - s), 1.35), ((cx + s, cy - s), (cx + s, cy + s), 0.75),
             ((cx + s, cy + s), (cx - s, cy + s), 0.55), ((cx - s, cy + s), (cx - s, cy - s), 1.15)]
    for (a, b, sh) in faces:
        poly(ctx, [a, b, (cx, cy)])
        fill(ctx, shade(hexc('#6a7686'), sh), preserve=True)
        stroke(ctx, OUT, 1.0)
    glow_spot(ctx, cx, cy, 24, hexc('#b48cff'), 0.4 + 0.5 * pulse)
    circle(ctx, cx, cy, 7)
    fill_grad(ctx, rad(cx - 2, cy - 2, 0, 8, [(0, hexc('#ffffff')), (1, hexc('#9a6aff') if frame is not None else hexc('#4a3a6a'))]), preserve=True)
    stroke(ctx, OUT, 1.0)
    return finish(cv, seed='beacon')


def radar(d, frame):
    cv = Canvas(192, 192)
    ctx = cv.ctx
    ix, iy, iw, ih = machine_frame(ctx, 3, 3, hexc('#3fae7a'), hexc('#68727c'))
    cx, cy = 92.5, 92.5
    circle(ctx, cx, cy, 58)
    fill_grad(ctx, lin(cx - 58, cy - 58, cx + 58, cy + 58, [(0, hexc('#2b3136')), (1, hexc('#454d55'))]))
    circle(ctx, cx, cy, 58)
    stroke(ctx, OUT, 1.3)
    for rr in (20, 38):
        circle(ctx, cx, cy, rr)
        stroke(ctx, alpha(hexc('#4fdc8a'), 0.25), 1)
    rot = (frame or 0) * math.pi / 4 - 0.5
    # symmetric bar antenna (2-fold symmetric so 4 frames x 45deg loop)
    ctx.save(); ctx.translate(cx, cy); ctx.rotate(rot)
    rrect(ctx, -56, -11, 112, 22, 6)
    ctx.restore()
    fill_grad(ctx, lin(cx - 56, cy - 56, cx + 56, cy + 56, [(0, hexc('#e3e8ec')), (1, hexc('#7a858f'))]), preserve=True)
    stroke(ctx, OUT, 1.3)
    ctx.save(); ctx.translate(cx, cy); ctx.rotate(rot)
    for k in range(-5, 6):
        ctx.move_to(k * 9.5, -8); ctx.line_to(k * 9.5, 8)
    ctx.restore()
    stroke(ctx, alpha(OUT, 0.4), 1.2)
    cyl_top(ctx, cx, cy, 13, hexc('#3fae7a'))
    light_lamp(ctx, ix + iw - 12, iy + ih - 12, 2.6, GREEN, on=frame is not None and frame % 2 == 0)
    return finish(cv, seed='radar')


def small_lamp(on):
    def f(d, frame):
        cv = Canvas(64, 64)
        ctx = cv.ctx
        bevel_box(ctx, 12, 12, 39, 39, hexc('#6b747c'), r=6, bev=2)
        rivets(ctx, 12, 12, 39, 39, inset=4, r=1.2)
        c = hexc('#fff0b0')
        if on:
            glow_spot(ctx, 31.5, 31.5, 30, c, 0.6)
        circle(ctx, 31.5, 31.5, 12)
        if on:
            fill_grad(ctx, rad(28, 28, 0, 14, [(0, hexc('#ffffff')), (0.5, c), (1, hexc('#e8b040'))]))
        else:
            fill_grad(ctx, rad(28, 28, 0, 14, [(0, hexc('#e6eef2')), (0.5, hexc('#9fb0ba')), (1, hexc('#56646e'))]))
        circle(ctx, 31.5, 31.5, 12)
        stroke(ctx, OUT, 1.2)
        for a in (0, math.pi / 2):
            ctx.move_to(31.5 + math.cos(a) * 12, 31.5 + math.sin(a) * 12)
            ctx.line_to(31.5 - math.cos(a) * 12, 31.5 - math.sin(a) * 12)
        stroke(ctx, alpha(OUT, 0.4), 1)
        return finish(cv, seed='lamp')
    return f


def rocket_silo(d, frame):
    S = 576
    cv = Canvas(S, S)
    ctx = cv.ctx
    bevel_box(ctx, 4, 4, S - 12, S - 12, hexc('#7f7c75'), r=18, bev=5)
    bevel_box(ctx, 26, 26, S - 56, S - 56, hexc('#9a978f'), r=14, bev=4)
    for x in range(26, S - 30, 48):
        ctx.move_to(x, 30); ctx.line_to(x, S - 34)
        ctx.move_to(30, x); ctx.line_to(S - 34, x)
    stroke(ctx, alpha(OUT, 0.15), 1.2)
    c = S / 2 - 4
    # corner gantries
    for (x, y) in ((40, 40), (S - 130, 40), (40, S - 130), (S - 130, S - 130)):
        bevel_box(ctx, x, y, 82, 82, hexc('#5d666f'), r=8, bev=3)
        cyl_top(ctx, x + 41, y + 41, 22, hexc('#c8402f'))
        rivets(ctx, x, y, 82, 82, inset=6, r=1.8)
    # hazard ring + silo pit
    circle(ctx, c, c, 196)
    fill(ctx, P['hazard'])
    ctx.save()
    circle(ctx, c, c, 196); ctx.clip()
    src(ctx, hexc('#1d1f22'))
    for k in range(36):
        a = k * math.tau / 36
        ctx.move_to(c, c)
        ctx.arc(c, c, 200, a, a + math.tau / 72)
        ctx.close_path()
    ctx.fill()
    ctx.restore()
    circle(ctx, c, c, 196)
    stroke(ctx, OUT, 2)
    circle(ctx, c, c, 176)
    fill_grad(ctx, lin(c - 176, c - 176, c + 176, c + 176, [(0, hexc('#5d666f')), (1, hexc('#2c3136'))]))
    circle(ctx, c, c, 176)
    stroke(ctx, OUT, 2)
    # two hatch doors
    for sgn in (-1, 1):
        ctx.new_sub_path()
        if sgn < 0:
            ctx.arc(c, c, 164, math.pi / 2, 3 * math.pi / 2)
        else:
            ctx.arc(c, c, 164, -math.pi / 2, math.pi / 2)
        ctx.close_path()
        g = lin(c - 164, c - 164, c + 164, c + 164, [(0, hexc('#b8bfc5')), (1, hexc('#59626a'))])
        fill_grad(ctx, g, preserve=True)
        stroke(ctx, OUT, 2)
        for k in range(5):
            yy = c - 120 + k * 60
            ctx.move_to(c + sgn * 20, yy); ctx.line_to(c + sgn * 140, yy)
            stroke(ctx, alpha(OUT, 0.3), 2)
    ctx.move_to(c, c - 164); ctx.line_to(c, c + 164)
    stroke(ctx, OUT, 4)
    for k in range(-3, 4):
        bolt(ctx, c - 8, c + k * 40, 2.5)
        bolt(ctx, c + 8, c + k * 40, 2.5)
    for k in range(24):
        a = k * math.tau / 24
        bolt(ctx, c + math.cos(a) * 186, c + math.sin(a) * 186, 2.6)
    return finish(cv, seed='silo')


# ============================================================================================ spec table

# id -> (draw fn, directional, animated)
SPECS = {
    'wooden_chest': (chest('wooden_chest'), False, False),
    'iron_chest': (chest('iron_chest'), False, False),
    'steel_chest': (chest('steel_chest'), False, False),
    'assembling_machine_1': (assembler(1), False, True),
    'assembling_machine_2': (assembler(2), False, True),
    'assembling_machine_3': (assembler(3), False, True),
    'lab': (lab, False, True),
    'stone_furnace': (furnace_stone, False, True),
    'steel_furnace': (furnace_steel, False, True),
    'electric_furnace': (furnace_electric, False, True),
    'burner_mining_drill': (drill_burner, True, True),
    'electric_mining_drill': (drill_electric, True, True),
    'pumpjack': (pumpjack, False, True),
    'boiler': (boiler, True, True),
    'steam_engine': (steam_engine, True, True),
    'solar_panel': (solar_panel, False, False),
    'accumulator': (accumulator, False, False),
    'offshore_pump': (offshore_pump, True, False),
    'pump': (pump, True, False),
    'storage_tank': (storage_tank, True, False),
    'chemical_plant': (chemical_plant, True, True),
    'oil_refinery': (oil_refinery, True, True),
    'beacon': (beacon, False, True),
    'radar': (radar, False, True),
    'small_lamp': (small_lamp(False), False, False),
    'rocket_silo': (rocket_silo, False, False),
}


def generate(reg, data):
    ids = {e['id'] for e in data['entities']}
    for eid, (fn, directional, animated) in SPECS.items():
        if eid not in ids:
            continue
        if directional:
            for d, dn in enumerate(DIRS):
                reg.add(f'e_{eid}_{dn}', fn(d, None), 'entities', keep=(d == 0))
                if animated:
                    for k in range(4):
                        reg.add(f'e_{eid}_{dn}_w{k}', fn(d, k), 'entities')
            reg.add(f'e_{eid}', reg.get(f'e_{eid}_n'), 'entities', keep=True)
        else:
            reg.add(f'e_{eid}', fn(0, None), 'entities', keep=True)
            if animated:
                for k in range(4):
                    reg.add(f'e_{eid}_w{k}', fn(0, k), 'entities')
    if 'small_lamp' in ids:
        reg.add('e_small_lamp_on', small_lamp(True)(0, None), 'entities')
