"""Transport belts, undergrounds and splitters.

Belts are rendered per pixel in *path space* (u = distance along travel 0..64, v = across, 0 = left side) so
straights and curves share one shading function and join seamlessly; lighting is computed in screen space from a
height field, so every rotation is lit from the top-left.

  belt_<id>_<shape>_<dir>_f<k>   64x64, shape straight|curve_l|curve_r, dir = output direction, k = 0..7
                                 (tread scrolls 8 px = 1/8 tile per frame in the travel direction)
  e_<id>_in_<dir> / e_<id>_out_<dir>   underground entrance / exit (belt half + hood)
  e_<id>_<dir>                   splitter, 128x64 (n/s) or 64x128 (e/w), belts included
"""
from __future__ import annotations

import math

import numpy as np
from PIL import Image

from .base import OUT, Fr, bevel_box, finish, inset_box
from .common import (T, Canvas, P, add_grit, alpha, bolt, fill, fill_grad, hexc, lin, rrect, shade, stroke,
                     with_shadow)

FRAMES = 8
PERIOD = 32          # tread pattern period (px); frames shift 8 px, so the pattern loops and reads unambiguously
SS = 3
DIRS = ['n', 'e', 's', 'w']

BELTS = {  # id -> (tier colour, underground id, splitter id)
    'transport_belt': (hexc('#e0a526'), 'underground_belt', 'splitter'),
    'fast_transport_belt': (hexc('#d2402e'), 'fast_underground_belt', 'fast_splitter'),
    'express_transport_belt': (hexc('#2f86d6'), 'express_underground_belt', 'express_splitter'),
}

RUBBER = np.array(hexc('#2b2d31')[:3])
SLAT = np.array(hexc('#3e4247')[:3])
STEEL_D = np.array(hexc('#1c1f22')[:3])
STEEL = np.array(hexc('#7a838b')[:3])
RAIL_W = 7


def _grid(n=T * SS):
    y, x = np.mgrid[0:n, 0:n].astype(np.float32)
    return (x + 0.5) / SS, (y + 0.5) / SS


def path_coords(shape: str, d: int):
    x, y = _grid()
    cx, cy = x - 32, y - 32
    for _ in range(d % 4):
        cx, cy = cy, -cx          # counter-rotate into the north-facing frame
    xn, yn = cx + 32, cy + 32
    if shape == 'straight':
        u, v = 64 - yn, xn
        inside = np.ones_like(u, bool)
    elif shape == 'curve_l':      # enters from the west travelling east, turns left, exits north
        r = np.hypot(xn, yn)
        th = np.arctan2(yn, xn)
        u = 64 * (1 - th / (math.pi / 2))
        v = r
        inside = r <= 64
    elif shape == 'curve_r':      # enters from the east travelling west, turns right, exits north
        r = np.hypot(64 - xn, yn)
        th = np.arctan2(yn, 64 - xn)
        u = 64 * (1 - th / (math.pi / 2))
        v = 64 - r
        inside = r <= 64
    else:
        raise KeyError(shape)
    return u, v, inside


def shade_belt(u, v, tc, shift):
    tc = np.array(tc[:3])
    h = np.zeros_like(u)
    col = np.zeros(u.shape + (3,), np.float32)
    rail = (v < RAIL_W) | (v > 64 - RAIL_W)
    tread = ~rail
    ut = (u - shift) % PERIOD
    col[tread] = RUBBER
    # slats across the tread (uneven spacing so motion direction stays readable)
    slat = tread & (((ut % 16) < 2.0))
    col[slat] = SLAT
    h[slat] = 0.6
    # one chevron per lane per period, pointing forward
    for vc in (19.5, 44.5):
        dv = np.abs(v - vc)
        p = (ut + dv * 0.75) % PERIOD
        chev = tread & (p > 7) & (p < 12) & (dv < 9.5)
        col[chev] = RUBBER * 0.35 + tc * 0.65
        h[chev] = 0.5
    # centre divider (two lanes)
    div = tread & (np.abs(v - 32) < 1.3)
    col[div] = STEEL * 0.8
    h[div] = 1.0
    # rails
    vr = np.where(v < 32, v, 64 - v)
    lip = rail & (vr < 1.8)
    band = rail & ~lip
    col[lip] = STEEL
    col[band] = tc * 0.92
    h[rail] = 3.0
    h[lip] = 2.4
    rv = rail & (np.hypot(((u % 16) - 8), vr - 4.0) < 1.35)
    col[rv] = np.array([0.86, 0.86, 0.86]) * 0.55 + tc * 0.45
    h[rv] += 0.7
    gap = (np.abs(v - RAIL_W) < 0.9) | (np.abs(v - (64 - RAIL_W)) < 0.9)
    col[gap] = STEEL_D
    h[gap] = -0.4
    return col, h


def light(col, h, strength=0.55):
    gy, gx = np.gradient(h * SS)
    L = np.array([-1.0, -1.0, 1.5])
    L /= np.linalg.norm(L)
    nx, ny, nz = -gx, -gy, np.ones_like(h)
    n = np.sqrt(nx * nx + ny * ny + nz * nz)
    d = (nx * L[0] + ny * L[1] + nz * L[2]) / n
    f = 1 + (d / L[2] - 1) * strength
    return np.clip(col * f[..., None], 0, 1)


_cache = {}


def belt_image(bid: str, shape: str, d: int, frame: int) -> Image.Image:
    key = (bid, shape, d, frame)
    if key in _cache:
        return _cache[key]
    u, v, inside = path_coords(shape, d)
    col, h = shade_belt(u, v, BELTS[bid][0], frame * (T / FRAMES))
    rgb = light(col, h)
    big = np.dstack([rgb, inside.astype(np.float32)])
    img = Image.fromarray((big * 255 + 0.5).astype(np.uint8), 'RGBA').resize((T, T), Image.BOX)
    img = add_grit(img, 0.025, 'belt' + bid)
    _cache[key] = img
    return img


# ------------------------------------------------------------------------------------------- undergrounds

def underground_image(bid: str, mode: str, d: int) -> Image.Image:
    """'in': items arrive from behind and dive under at the front; 'out': emerge from the hood at the back."""
    tc = BELTS[bid][0]
    base = belt_image(bid, 'straight', d, 0)
    fr = Fr(64, 64, d)
    cv = Canvas(64, 64)
    ctx = cv.ctx
    hy = 1 if mode == 'in' else 27
    hx, hw, hh = 1, 60, 36
    x, y, w, h = fr.rect(hx, hy, hw, hh)
    # side cheeks + hood body
    bevel_box(ctx, x, y, w, h, shade(P['steel_m'], 0.9), r=6, bev=2.5)
    ix, iy, iw, ih = fr.rect(hx + 6, hy + 6, hw - 12, hh - 12)
    bevel_box(ctx, ix, iy, iw, ih, tc, r=4, bev=2, hi=1.35, lo=0.55)
    # tunnel mouth: dark slot on the side facing the open belt half
    my = hy + hh - 6 if mode == 'in' else hy + 1
    mx, myy, mw, mh = fr.rect(hx + 8, my, hw - 16, 5)
    rrect(ctx, mx, myy, mw, mh, 2)
    fill(ctx, hexc('#0b0c0e'))
    # direction chevrons on the hood
    from .base import arrow
    cy = hy + hh / 2
    arrow(ctx, fr, 31, cy + (1 if mode == 'in' else -1), 8, shade(tc, 1.7), 2.6)
    for (bx, by) in ((hx + 3.5, hy + 3.5), (hx + hw - 3.5, hy + 3.5), (hx + 3.5, hy + hh - 3.5), (hx + hw - 3.5, hy + hh - 3.5)):
        bolt(ctx, *fr.pt(bx, by), 1.3)
    hood = finish(cv, dx=2.5, dy=3, strength=0.55)
    out = base.copy()
    out.alpha_composite(hood)
    return out


# ------------------------------------------------------------------------------------------- splitters

def splitter_image(bid: str, d: int) -> Image.Image:
    tc = BELTS[bid][0]
    fr = Fr(128, 64, d)
    W, H = fr.size
    out = Image.new('RGBA', (W, H))
    # belts under both tiles
    for i in range(2):
        px, py = fr.pt(i * 64 + 32, 32)
        out.alpha_composite(belt_image(bid, 'straight', d, 0), (int(px - 32), int(py - 32)))
    cv = Canvas(W, H)
    ctx = cv.ctx
    by, bh = 17, 30
    # end posts
    for x0 in (0, 116):
        bevel_box(ctx, *fr.rect(x0 + 1, 8, 11, 48), shade(P['steel'], 1.0), r=3, bev=2)
    # body bar across both belts
    bevel_box(ctx, *fr.rect(4, by, 120, bh), shade(P['steel_m'], 0.9), r=6, bev=2.5)
    bevel_box(ctx, *fr.rect(9, by + 5, 110, bh - 10), tc, r=4, bev=2, hi=1.35, lo=0.55)
    # central divider block
    bevel_box(ctx, *fr.rect(58, by - 5, 12, bh + 10), P['steel_l'], r=3, bev=2)
    from .base import arrow
    for cx in (33, 95):
        arrow(ctx, fr, cx, by + bh / 2, 9, shade(tc, 1.8), 2.8)
    for bx in (14, 52, 76, 114):
        bolt(ctx, *fr.pt(bx, by + bh / 2), 1.4)
    out.alpha_composite(finish(cv, dx=3, dy=3.5, strength=0.55))
    return out


def generate(reg, data):
    for bid, (tc, ug, sp) in BELTS.items():
        for shape in ('straight', 'curve_l', 'curve_r'):
            for d, dn in enumerate(DIRS):
                for f in range(FRAMES):
                    reg.add(f'belt_{bid}_{shape}_{dn}_f{f}', belt_image(bid, shape, d, f), 'belts')
        reg.add(f'e_{bid}', belt_image(bid, 'straight', 0, 0), 'belts', keep=True)
        for mode in ('in', 'out'):
            for d, dn in enumerate(DIRS):
                reg.add(f'e_{ug}_{mode}_{dn}', underground_image(bid, mode, d), 'belts', keep=(mode == 'in' and d == 0))
        reg.add(f'e_{ug}', reg.get(f'e_{ug}_in_n'), 'belts', keep=True)
        for d, dn in enumerate(DIRS):
            reg.add(f'e_{sp}_{dn}', splitter_image(bid, d), 'belts', keep=(d == 0))
        reg.add(f'e_{sp}', reg.get(f'e_{sp}_n'), 'belts', keep=True)
