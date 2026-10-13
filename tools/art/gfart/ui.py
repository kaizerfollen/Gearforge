"""UI glyphs ui_<name> (white template glyphs, 64x64, rounded strokes) and status_<name> badges (coloured, 32x32)."""
from __future__ import annotations

import math

from PIL import Image

from .common import Canvas, alpha, circle, fill, fill_grad, gear_path, hexc, lin, poly, rad, rrect, shade, stroke

W = (1, 1, 1, 1)
LW = 5.0


def S(ctx, w=LW):
    stroke(ctx, W, w)


def F(ctx):
    fill(ctx, W)


def arrow_head(ctx, x, y, ang, size=9):
    a1, a2 = ang + math.pi * 0.8, ang - math.pi * 0.8
    ctx.move_to(x + math.cos(a1) * size, y + math.sin(a1) * size)
    ctx.line_to(x, y)
    ctx.line_to(x + math.cos(a2) * size, y + math.sin(a2) * size)
    S(ctx)


def g_build(ctx):
    # hammer
    ctx.move_to(14, 52); ctx.line_to(38, 28); S(ctx, 6)
    ctx.save(); ctx.translate(40, 24); ctx.rotate(math.pi / 4)
    rrect(ctx, -16, -7, 32, 14, 3); ctx.restore(); F(ctx)


def g_remove(ctx):
    ctx.move_to(14, 18); ctx.line_to(50, 18); S(ctx)
    ctx.move_to(26, 18); ctx.line_to(28, 11); ctx.line_to(36, 11); ctx.line_to(38, 18); S(ctx, 4)
    ctx.move_to(18, 24); ctx.line_to(21, 53); ctx.line_to(43, 53); ctx.line_to(46, 24); S(ctx)
    for x in (28, 36):
        ctx.move_to(x, 30); ctx.line_to(x, 46); S(ctx, 3.5)


def g_rotate(ctx):
    ctx.arc(32, 33, 17, -math.pi * 0.35, math.pi * 1.25); S(ctx)
    ex, ey = 32 + 17 * math.cos(-math.pi * 0.35), 33 + 17 * math.sin(-math.pi * 0.35)
    poly(ctx, [(ex + 9, ey - 3), (ex - 6, ey - 8), (ex - 1, ey + 8)]); F(ctx)


def g_undo(ctx, mirror=False):
    ctx.save()
    if mirror:
        ctx.translate(64, 0); ctx.scale(-1, 1)
    ctx.move_to(18, 26); ctx.line_to(38, 26)
    ctx.curve_to(52, 26, 52, 50, 38, 50); ctx.line_to(26, 50)
    S(ctx)
    poly(ctx, [(10, 26), (22, 15), (22, 37)]); F(ctx)
    ctx.restore()


def g_mine(ctx):
    ctx.move_to(20, 50); ctx.line_to(42, 22); S(ctx, 6)
    ctx.move_to(14, 22); ctx.curve_to(26, 8, 48, 8, 54, 30); S(ctx, 6)


def g_inventory(ctx):
    rrect(ctx, 12, 20, 40, 32, 6); S(ctx)
    ctx.move_to(24, 20); ctx.line_to(24, 14); ctx.line_to(40, 14); ctx.line_to(40, 20); S(ctx, 4.5)
    ctx.move_to(12, 32); ctx.line_to(52, 32); S(ctx, 4)
    rrect(ctx, 28, 29, 8, 8, 2); F(ctx)


def g_map(ctx):
    poly(ctx, [(10, 16), (24, 11), (40, 17), (54, 12), (54, 48), (40, 53), (24, 47), (10, 52)]); S(ctx, 4.5)
    ctx.move_to(24, 11); ctx.line_to(24, 47); ctx.move_to(40, 17); ctx.line_to(40, 53); S(ctx, 4)


def g_pause(ctx):
    rrect(ctx, 18, 14, 10, 36, 3); F(ctx)
    rrect(ctx, 36, 14, 10, 36, 3); F(ctx)


def g_play(ctx):
    ctx.move_to(22, 14); ctx.line_to(50, 32); ctx.line_to(22, 50); ctx.close_path()
    ctx.set_line_join(1); F(ctx)
    ctx.move_to(22, 14); ctx.line_to(50, 32); ctx.line_to(22, 50); ctx.close_path(); S(ctx, 4)


def g_research(ctx):
    for a in (0, math.pi / 3, -math.pi / 3):
        ctx.save(); ctx.translate(32, 32); ctx.rotate(a); ctx.scale(1, 0.4)
        circle(ctx, 0, 0, 22); ctx.restore(); S(ctx, 3.5)
    circle(ctx, 32, 32, 5); F(ctx)


def g_stats(ctx):
    ctx.move_to(12, 12); ctx.line_to(12, 52); ctx.line_to(54, 52); S(ctx, 4.5)
    for k, h in enumerate((14, 26, 20, 34)):
        rrect(ctx, 19 + k * 9, 46 - h, 6, h, 2); F(ctx)


def g_altmode(ctx):
    for k, y in enumerate((40, 30, 20)):
        poly(ctx, [(32, y - 9), (52, y), (32, y + 9), (12, y)])
        if k == 2:
            F(ctx)
        else:
            S(ctx, 4)


def g_close(ctx):
    ctx.move_to(18, 18); ctx.line_to(46, 46); ctx.move_to(46, 18); ctx.line_to(18, 46); S(ctx, 6)


def g_craft(ctx):
    gear_path(ctx, 26, 36, 15, 11, 8, 0.2, hole=5)
    ctx.set_fill_rule(1); F(ctx)
    gear_path(ctx, 45, 20, 10, 7, 7, 0.0, hole=3.2)
    ctx.set_fill_rule(1); F(ctx)


def g_settings(ctx):
    for k, (y, x) in enumerate(((18, 40), (32, 22), (46, 34))):
        ctx.move_to(12, y); ctx.line_to(52, y); S(ctx, 3.5)
        circle(ctx, x, y, 6); F(ctx)


def g_save(ctx):
    ctx.move_to(32, 10); ctx.line_to(32, 36); S(ctx)
    arrow_head(ctx, 32, 38, math.pi / 2, 11)
    ctx.move_to(12, 38); ctx.line_to(12, 52); ctx.line_to(52, 52); ctx.line_to(52, 38); S(ctx)


def g_load(ctx):
    ctx.move_to(32, 38); ctx.line_to(32, 12); S(ctx)
    arrow_head(ctx, 32, 10, -math.pi / 2, 11)
    ctx.move_to(12, 38); ctx.line_to(12, 52); ctx.line_to(52, 52); ctx.line_to(52, 38); S(ctx)


def bolt_path(ctx, s=1.0, ox=0, oy=0):
    pts = [(36, 8), (16, 36), (30, 36), (26, 56), (48, 26), (34, 26), (40, 8)]
    poly(ctx, [(ox + (x - 32) * s + 32, oy + (y - 32) * s + 32) for x, y in pts])


def g_power(ctx):
    bolt_path(ctx); F(ctx)


def g_alert(ctx):
    ctx.move_to(32, 10); ctx.line_to(56, 52); ctx.line_to(8, 52); ctx.close_path(); S(ctx)
    ctx.move_to(32, 24); ctx.line_to(32, 38); S(ctx, 5.5)
    circle(ctx, 32, 45.5, 3.2); F(ctx)


def g_check(ctx):
    ctx.move_to(14, 34); ctx.line_to(27, 47); ctx.line_to(50, 18); S(ctx, 6.5)


def g_cross(ctx):
    circle(ctx, 32, 32, 22); S(ctx, 4.5)
    ctx.move_to(23, 23); ctx.line_to(41, 41); ctx.move_to(41, 23); ctx.line_to(23, 41); S(ctx, 5)


def g_copy(ctx):
    rrect(ctx, 22, 22, 28, 30, 5); S(ctx, 4.5)
    ctx.move_to(14, 40); ctx.line_to(14, 16); ctx.curve_to(14, 13, 15, 12, 18, 12); ctx.line_to(38, 12); S(ctx, 4.5)


def g_paste(ctx):
    rrect(ctx, 14, 14, 36, 40, 5); S(ctx, 4.5)
    rrect(ctx, 24, 9, 16, 10, 3); F(ctx)
    for y in (30, 38, 46):
        ctx.move_to(22, y); ctx.line_to(42 if y < 46 else 34, y); S(ctx, 3.5)


def g_pipette(ctx):
    ctx.save(); ctx.translate(32, 32); ctx.rotate(math.pi / 4)
    rrect(ctx, -5, -26, 10, 14, 4); F(ctx)
    ctx.move_to(-10, -11); ctx.line_to(10, -11); S(ctx, 4.5)
    ctx.move_to(-3.5, -9); ctx.line_to(-3.5, 14); ctx.line_to(0, 22); ctx.line_to(3.5, 14); ctx.line_to(3.5, -9); S(ctx, 3.5)
    ctx.restore()


def g_joystick(ctx):
    circle(ctx, 32, 32, 22); S(ctx, 4)
    circle(ctx, 32, 32, 10); F(ctx)
    for a in range(4):
        ang = a * math.pi / 2 - math.pi / 2
        x, y = 32 + math.cos(ang) * 17, 32 + math.sin(ang) * 17
        poly(ctx, [(x + math.cos(ang) * 3, y + math.sin(ang) * 3),
                   (x + math.cos(ang + 2.2) * 3.5, y + math.sin(ang + 2.2) * 3.5),
                   (x + math.cos(ang - 2.2) * 3.5, y + math.sin(ang - 2.2) * 3.5)]); F(ctx)


GLYPHS = {
    'build': g_build, 'remove': g_remove, 'rotate': g_rotate, 'undo': g_undo, 'redo': lambda c: g_undo(c, True),
    'mine': g_mine, 'inventory': g_inventory, 'map': g_map, 'pause': g_pause, 'play': g_play,
    'research': g_research, 'stats': g_stats, 'altmode': g_altmode, 'close': g_close, 'craft': g_craft,
    'settings': g_settings, 'save': g_save, 'load': g_load, 'power': g_power, 'alert': g_alert, 'check': g_check,
    'cross': g_cross, 'copy': g_copy, 'paste': g_paste, 'pipette': g_pipette, 'joystick': g_joystick,
}


# --------------------------------------------------------------------------------------------- status badges

OUTL = hexc('#14171a')


def badge(ctx, c, shape='circle'):
    if shape == 'circle':
        circle(ctx, 32, 32, 27)
    else:
        ctx.move_to(32, 5); ctx.line_to(60, 55); ctx.line_to(4, 55); ctx.close_path()
    fill_grad(ctx, lin(10, 6, 54, 58, [(0, shade(c, 1.35)), (1, shade(c, 0.7))]), preserve=True)
    stroke(ctx, OUTL, 3.5)


def st_no_power(ctx):
    badge(ctx, hexc('#d8382a'))
    bolt_path(ctx, 0.62); F(ctx)
    ctx.move_to(16, 48); ctx.line_to(48, 16); stroke(ctx, OUTL, 7); ctx.move_to(16, 48); ctx.line_to(48, 16); S(ctx, 4)


def st_low_power(ctx):
    badge(ctx, hexc('#f0b81e'), 'tri')
    bolt_path(ctx, 0.5, 0, 6); fill(ctx, OUTL)


def st_no_fuel(ctx):
    badge(ctx, hexc('#e86a1e'))
    ctx.move_to(32, 13); ctx.curve_to(44, 26, 46, 34, 44, 40); ctx.curve_to(42, 48, 36, 51, 32, 51)
    ctx.curve_to(26, 51, 20, 47, 20, 40); ctx.curve_to(20, 32, 28, 28, 32, 13); ctx.close_path()
    S(ctx, 4.5)


def st_output_full(ctx):
    badge(ctx, hexc('#e8a21e'))
    rrect(ctx, 18, 30, 28, 20, 3); F(ctx)
    ctx.move_to(32, 26); ctx.line_to(32, 12); stroke(ctx, W, 4.5)
    arrow_head(ctx, 32, 11, -math.pi / 2, 8)


def st_no_input(ctx):
    badge(ctx, hexc('#d8382a'))
    ctx.set_dash([5, 4])
    rrect(ctx, 17, 20, 30, 24, 3); S(ctx, 4)
    ctx.set_dash([])


def st_no_recipe(ctx):
    badge(ctx, hexc('#6f7882'))
    gear_path(ctx, 32, 32, 19, 15, 8, 0.2, hole=10)
    ctx.set_fill_rule(1); F(ctx)
    ctx.set_fill_rule(0)
    ctx.select_font_face('DejaVu Sans', 0, 1); ctx.set_font_size(16)
    xb, yb, tw, th, _, _ = ctx.text_extents('?')
    ctx.move_to(32 - tw / 2 - xb, 32 - th / 2 - yb); ctx.text_path('?'); F(ctx)


def st_no_resources(ctx):
    badge(ctx, hexc('#d8382a'))
    ctx.move_to(22, 46); ctx.line_to(38, 24); S(ctx, 5)
    ctx.move_to(18, 24); ctx.curve_to(26, 14, 42, 14, 46, 30); S(ctx, 5)


def st_working(ctx):
    badge(ctx, hexc('#38b54a'))
    ctx.move_to(19, 33); ctx.line_to(28, 42); ctx.line_to(45, 21); S(ctx, 6)


STATUS = {
    'no_power': st_no_power, 'low_power': st_low_power, 'no_fuel': st_no_fuel, 'output_full': st_output_full,
    'no_input': st_no_input, 'no_recipe': st_no_recipe, 'no_resources': st_no_resources, 'working': st_working,
}


def generate(reg, data):
    for name, fn in GLYPHS.items():
        cv = Canvas(64, 64)
        cv.ctx.set_line_cap(1); cv.ctx.set_line_join(1)
        fn(cv.ctx)
        reg.add(f'ui_{name}', cv.pil(), 'ui')
    for name, fn in STATUS.items():
        cv = Canvas(64, 64)
        cv.ctx.set_line_cap(1); cv.ctx.set_line_join(1)
        fn(cv.ctx)
        reg.add(f'status_{name}', cv.pil().resize((32, 32), Image.LANCZOS), 'ui')
