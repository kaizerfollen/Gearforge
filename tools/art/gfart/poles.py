"""Electric poles (top-down, visible insulators) and the wire pixel."""
from __future__ import annotations

import math

from PIL import Image

from .base import OUT, bevel_box, finish, rivets, light_lamp
from .common import Canvas, P, alpha, circle, fill, fill_grad, hexc, lin, rad, rrect, shade, stroke

INSUL = hexc('#5fb3a6')     # ceramic insulators (teal-green glaze)
COPPER = hexc('#c9773d')


def insulator(ctx, x, y, r=3.2):
    circle(ctx, x, y, r + 1.2)
    fill(ctx, OUT)
    for k, rr in enumerate((r, r * 0.66, r * 0.33)):
        circle(ctx, x, y, rr)
        fill_grad(ctx, rad(x - rr * 0.4, y - rr * 0.4, 0, rr * 1.3, [(0, shade(INSUL, 1.6 - k * 0.1)), (1, shade(INSUL, 0.7))]))
        circle(ctx, x, y, rr)
        stroke(ctx, alpha(OUT, 0.5), 0.6)


def beam(ctx, x0, y0, x1, y1, w, c):
    ang = math.atan2(y1 - y0, x1 - x0)
    L = math.hypot(x1 - x0, y1 - y0)
    ctx.save()
    ctx.translate(x0, y0)
    ctx.rotate(ang)
    rrect(ctx, -w / 2, -w / 2, L + w, w, w * 0.35)
    ctx.restore()
    # screen-space gradient: lit top-left
    fill_grad(ctx, lin(min(x0, x1) - w, min(y0, y1) - w, max(x0, x1) + w, max(y0, y1) + w,
                       [(0, shade(c, 1.3)), (1, shade(c, 0.7))]), preserve=True)
    stroke(ctx, OUT, 1.0)


def small_pole():
    cv = Canvas(64, 64)
    ctx = cv.ctx
    wood = P['wood']
    circle(ctx, 31, 31, 13)
    fill(ctx, alpha(hexc('#3b2c1e'), 0.5))
    beam(ctx, 9, 31, 53, 31, 9, wood)
    for x in (18, 44):
        ctx.move_to(x, 27); ctx.line_to(x, 35)
        stroke(ctx, alpha(P['wood_d'], 0.7), 1.0)
    circle(ctx, 31, 31, 10)
    fill_grad(ctx, rad(28, 28, 0, 11, [(0, P['wood_l']), (1, P['wood_d'])]))
    circle(ctx, 31, 31, 10)
    stroke(ctx, OUT, 1.2)
    for r in (3, 6.5):
        circle(ctx, 31, 31, r)
        stroke(ctx, alpha(P['wood_d'], 0.6), 0.8)
    insulator(ctx, 12, 31, 4.6)
    insulator(ctx, 50, 31, 4.6)
    return finish(cv, dx=4, dy=5, blur=2, strength=0.5, seed='pole_s')


def medium_pole():
    cv = Canvas(64, 64)
    ctx = cv.ctx
    st = P['steel_m']
    rrect(ctx, 15, 15, 33, 33, 3)
    stroke(ctx, OUT, 5)
    rrect(ctx, 15, 15, 33, 33, 3)
    stroke(ctx, shade(st, 1.15), 3)
    for (a, b) in (((15, 15), (48, 48)), ((48, 15), (15, 48))):
        ctx.move_to(*a); ctx.line_to(*b)
        stroke(ctx, OUT, 3.6)
        ctx.move_to(*a); ctx.line_to(*b)
        stroke(ctx, st, 2)
    beam(ctx, 7, 31.5, 56, 31.5, 7, shade(st, 0.95))
    bevel_box(ctx, 22, 22, 19, 19, hexc('#9a5a3a'), r=3, bev=2.2)
    insulator(ctx, 9, 31.5, 4.6)
    insulator(ctx, 54, 31.5, 4.6)
    circle(ctx, 31.5, 31.5, 3.5)
    fill(ctx, COPPER)
    circle(ctx, 31.5, 31.5, 3.5)
    stroke(ctx, OUT, 0.8)
    return finish(cv, dx=4, dy=5, blur=2, strength=0.5, seed='pole_m')


def big_pole():
    cv = Canvas(128, 128)
    ctx = cv.ctx
    st = P['steel_m']
    # four legs splaying to the footprint corners
    for (x, y) in ((14, 14), (110, 14), (14, 110), (110, 110)):
        beam(ctx, 62, 62, x, y, 6, shade(st, 0.85))
        rrect(ctx, x - 7, y - 7, 14, 14, 2)
        fill_grad(ctx, lin(x - 7, y - 7, x + 7, y + 7, [(0, hexc('#a39e93')), (1, hexc('#5f5b54'))]))
        rrect(ctx, x - 6.5, y - 6.5, 13, 13, 2)
        stroke(ctx, OUT, 1.0)
    # lattice ring
    rrect(ctx, 38, 38, 48, 48, 4)
    stroke(ctx, OUT, 5)
    rrect(ctx, 38, 38, 48, 48, 4)
    stroke(ctx, st, 3)
    # cross arms
    beam(ctx, 18, 62, 106, 62, 8, shade(st, 1.05))
    beam(ctx, 62, 32, 62, 92, 7, shade(st, 0.95))
    bevel_box(ctx, 50, 50, 24, 24, hexc('#9a5a3a'), r=4, bev=2.5)
    rivets(ctx, 50, 50, 24, 24, inset=4, r=1.4)
    for (x, y) in ((22, 62), (102, 62), (62, 36), (62, 88)):
        insulator(ctx, x, y, 4.8)
    return finish(cv, dx=5, dy=6, blur=2.5, strength=0.5, seed='pole_b')


def substation():
    cv = Canvas(128, 128)
    ctx = cv.ctx
    bevel_box(ctx, 6, 6, 112, 112, hexc('#4c555d'), r=8, bev=3.5)
    bevel_box(ctx, 16, 16, 92, 92, hexc('#626c75'), r=6, bev=2.5)
    rivets(ctx, 6, 6, 112, 112, inset=5, r=1.6, mid=True)
    # transformer core with cooling fins
    bevel_box(ctx, 38, 38, 48, 48, hexc('#3d6f6a'), r=5, bev=2.5)
    for k in range(5):
        rrect(ctx, 44, 44 + k * 8, 36, 4, 1.5)
        fill_grad(ctx, lin(0, 44 + k * 8, 0, 48 + k * 8, [(0, shade(hexc('#3d6f6a'), 1.4)), (1, shade(hexc('#3d6f6a'), 0.6))]))
    # four big insulator stacks at the corners
    for (x, y) in ((28, 28), (96, 28), (28, 96), (96, 96)):
        circle(ctx, x, y, 9)
        fill_grad(ctx, lin(x - 9, y - 9, x + 9, y + 9, [(0, P['steel_l']), (1, P['steel_d'])]))
        circle(ctx, x, y, 9)
        stroke(ctx, OUT, 1.0)
        insulator(ctx, x, y, 6)
    # copper bus bars
    for (a, b) in (((28, 34), (28, 90)), ((96, 34), (96, 90)), ((34, 28), (90, 28)), ((34, 96), (90, 96))):
        ctx.move_to(*a); ctx.line_to(*b)
        stroke(ctx, OUT, 4)
        ctx.move_to(*a); ctx.line_to(*b)
        stroke(ctx, COPPER, 2.2)
    light_lamp(ctx, 62, 62, 3, hexc('#7cf0a0'))
    return finish(cv, dx=4, dy=5, blur=2.4, strength=0.5, seed='substation')


def generate(reg, data):
    reg.add('e_small_electric_pole', small_pole(), 'poles', keep=True)
    reg.add('e_medium_electric_pole', medium_pole(), 'poles', keep=True)
    reg.add('e_big_electric_pole', big_pole(), 'poles', keep=True)
    reg.add('e_substation', substation(), 'poles', keep=True)
    reg.add('wire', Image.new('RGBA', (8, 8), (201, 119, 61, 255)), 'poles')
