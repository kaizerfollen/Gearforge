"""Pipes: pipe_<mask> (bit N=1, E=2, S=4, W=8 connected sides) and e_pipe_to_ground_<dir>.

pipe_to_ground: <dir> is the side of the above-ground connection; the buried run continues the opposite way.
"""
from __future__ import annotations

from .base import OUT, Fr, finish, flange_at, pipe_seg, rivets, bevel_box
from .common import Canvas, P, alpha, circle, fill, fill_grad, hexc, lin, rad, rrect, shade, stroke

PIPE = hexc('#7d8894')
R = 9.5
C = 31  # centre (body inset for the in-footprint shadow)
SIDES = [(1, 'n', (C, 0)), (2, 'e', (64, C)), (4, 's', (C, 64)), (8, 'w', (0, C))]


def pipe_image(mask: int):
    cv = Canvas(64, 64)
    ctx = cv.ctx
    conns = [(b, s, p) for (b, s, p) in SIDES if mask & b]
    # straight-through pipes are drawn as one segment
    horiz = [p for (b, s, p) in conns if s in 'ew']
    vert = [p for (b, s, p) in conns if s in 'ns']
    for (b, s, p) in conns:
        if s in 'ns':
            pipe_seg(ctx, C, C, C, p[1], R, PIPE)
    for (b, s, p) in conns:
        if s in 'ew':
            pipe_seg(ctx, C, C, p[0], C, R, PIPE)
    straight = mask in (5, 10)
    if not straight:
        # junction body: rounded box hub
        rrect(ctx, C - R - 2, C - R - 2, 2 * R + 4, 2 * R + 4, 6)
        fill_grad(ctx, lin(C - R, C - R, C + R, C + R, [(0, shade(PIPE, 1.4)), (0.5, PIPE), (1, shade(PIPE, 0.5))]))
        rrect(ctx, C - R - 1.5, C - R - 1.5, 2 * R + 3, 2 * R + 3, 6)
        stroke(ctx, OUT, 1.2)
        circle(ctx, C, C, 4.5)
        fill_grad(ctx, rad(C - 1.5, C - 1.5, 0, 5, [(0, shade(PIPE, 1.5)), (1, shade(PIPE, 0.7))]))
        circle(ctx, C, C, 4.5)
        stroke(ctx, alpha(OUT, 0.7), 1.0)
        if mask == 0:
            for (b, s, p) in SIDES:
                pass
    # flanges at the tile edges (joints) and mid-run collars
    for (b, s, p) in conns:
        if s == 'n':
            flange_at(ctx, C, 3, R, False, P['brass'], 5)
        elif s == 's':
            flange_at(ctx, C, 61, R, False, P['brass'], 5)
        elif s == 'e':
            flange_at(ctx, 61, C, R, True, P['brass'], 5)
        else:
            flange_at(ctx, 3, C, R, True, P['brass'], 5)
    if straight:
        if mask == 5:
            flange_at(ctx, C, C, R, False, P['steel_l'], 4)
        else:
            flange_at(ctx, C, C, R, True, P['steel_l'], 4)
    return finish(cv, dx=2.5, dy=3, strength=0.45, seed='pipe')


def ptg_image(d: int):
    fr = Fr(64, 64, d)
    cv = Canvas(64, 64)
    ctx = cv.ctx
    # above-ground stub from the north edge to the ground cap
    a = fr.pt(C, 0)
    b = fr.pt(C, 34)
    pipe_seg(ctx, a[0], a[1], b[0], b[1], R, PIPE)
    fx, fy = fr.pt(C, 3)
    flange_at(ctx, fx, fy, R, abs(a[1] - b[1]) < 1e-6, P['brass'], 5)
    # ground cap (a rounded block sinking into the ground)
    x, y, w, h = fr.rect(C - 14, 28, 28, 26)
    bevel_box(ctx, x, y, w, h, shade(PIPE, 0.9), r=7, bev=2.5)
    cx, cy = fr.pt(C, 41)
    circle(ctx, cx, cy, 7.5)
    fill_grad(ctx, rad(cx + 1, cy + 1, 0, 8, [(0, hexc('#0b0d0f')), (1, hexc('#2a3036'))]))
    circle(ctx, cx, cy, 7.5)
    stroke(ctx, OUT, 1.0)
    rivets(ctx, x, y, w, h, inset=3.5, r=1.2)
    # "down" marker: dashed line hint of the buried run
    for t in (56, 60):
        p = fr.pt(C, t)
        circle(ctx, p[0], p[1], 1.4)
        fill(ctx, alpha(shade(PIPE, 0.5), 0.8))
    return finish(cv, dx=2.5, dy=3, strength=0.45, seed='ptg')


def generate(reg, data):
    for m in range(16):
        reg.add(f'pipe_{m}', pipe_image(m), 'pipes', keep=(m == 10))
    reg.add('e_pipe', pipe_image(10), 'pipes', keep=True)
    for d, dn in enumerate('nesw'):
        reg.add(f'e_pipe_to_ground_{dn}', ptg_image(d), 'pipes', keep=(d == 0))
    reg.add('e_pipe_to_ground', reg.get('e_pipe_to_ground_n'), 'pipes', keep=True)
