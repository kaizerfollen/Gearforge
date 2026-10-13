"""Transport belts, undergrounds and splitters.

Belts are rendered per-pixel in a *path space* (u = distance along travel 0..64, v = distance across, 0 = left
side of travel) so straights and curves share one shading function and join seamlessly; lighting is computed in
screen space from a height field, so every rotation is lit from the top-left.

Sprites
  belt_<tier>_<shape>_<dir>_f<n>   64x64, shape in straight|curve_left|curve_right, dir = facing (output side),
                                   n = 0..BELT_FRAMES-1. curve_left = input from the belt's left side.
  entity_<tier-id>_underground_belt_in|out_<dir>   static, includes the belt stub
  entity_<tier-id>_splitter_<dir>                  housing overlay; draw belt straights under both tiles
"""
from __future__ import annotations

import math

import numpy as np
from PIL import Image

from .common import (T, DIRS, ECanvas, P, TIERS, add_grit, alpha, block, bolt, fill, fill_grad, hexc, lin, plate,
                     rrect, shade, stroke, with_shadow, rot_vec, circle)

BELT_FRAMES = 16
PERIOD = 32          # tread pattern period (px); 64 % PERIOD == 0 so neighbours line up
SS = 3               # supersampling
TIER_IDS = {'basic': '', 'fast': 'fast_', 'express': 'express_'}

RUBBER = np.array(hexc('#2a2c2f')[:3])
RIB = np.array(hexc('#4a4e53')[:3])
STEEL_D = np.array(hexc('#24282c')[:3])
STEEL = np.array(hexc('#6b747c')[:3])


def _grid(n=T * SS):
    y, x = np.mgrid[0:n, 0:n].astype(np.float32)
    return (x + 0.5) / SS, (y + 0.5) / SS


def path_coords(shape: str, d: int):
    """Return (u, v, inside) arrays in path space for a belt facing direction d (0=n,1=e,2=s,3=w)."""
    x, y = _grid()
    # rotate the screen coordinates into the north-facing frame (counter-rotate by d quarter turns)
    cx, cy = x - 32, y - 32
    for _ in range(d % 4):
        cx, cy = cy, -cx          # rotate counter-clockwise
    xn, yn = cx + 32, cy + 32
    if shape == 'straight':
        u = 64 - yn
        v = xn
        inside = np.ones_like(u, bool)
    elif shape == 'curve_left':          # input from west, output north, corner at (0, 0)
        r = np.hypot(xn, yn)
        th = np.arctan2(yn, xn)
        u = 64 * (1 - th / (math.pi / 2))
        v = r
        inside = r <= 64
    elif shape == 'curve_right':         # input from east, output north, corner at (64, 0)
        r = np.hypot(64 - xn, yn)
        th = np.arctan2(yn, 64 - xn)
        u = 64 * (1 - th / (math.pi / 2))
        v = 64 - r
        inside = r <= 64
    else:
        raise KeyError(shape)
    return u, v, inside


def shade_belt(u, v, inside, tier: str, shift: float):
    tc = np.array(TIERS[tier][:3])
    h = np.zeros_like(u)
    col = np.zeros(u.shape + (3,), np.float32)
    rail = (v < 7) | (v > 57)
    tread = ~rail
    # --- tread
    ut = (u - shift) % PERIOD
    rib = ((ut % 8) < 2.2)
    col[tread] = RUBBER
    col[tread & rib] = RIB
    h[tread] = 0.0
    h[tread & rib] = 0.7
    # chevrons pointing along travel
    p = (ut + np.abs(v - 32) * 0.55) % PERIOD
    chev = tread & (p > 12) & (p < 17) & (np.abs(v - 32) < 18)
    col[chev] = col[chev] * 0.5 + tc * 0.5
    h[chev] += 0.25
    # lane groove in the middle
    groove = tread & (np.abs(v - 32) < 0.7)
    col[groove] *= 0.75
    # --- rails (static)
    vr = np.where(v < 32, v, 64 - v)          # distance from the outer edge
    lip = rail & ((vr < 1.6) | (vr > 5.6))
    band = rail & ~lip
    col[lip] = STEEL
    col[band] = tc
    h[rail] = 3.0
    h[lip & (vr > 5.6)] = 2.2
    # rivets along the rails every 16 px
    rv = rail & (np.hypot(((u % 16) - 8), vr - 3.6) < 1.25)
    col[rv] = np.array(hexc('#dcdcdc')[:3]) * 0.6 + tc * 0.4
    h[rv] += 0.6
    # dark gap between rail and tread
    gap = (np.abs(v - 7) < 0.9) | (np.abs(v - 57) < 0.9)
    col[gap] = STEEL_D
    h[gap] = -0.3
    return col, h, inside


def light(col, h, strength=0.55):
    gy, gx = np.gradient(h * SS)
    L = np.array([-1.0, -1.0, 1.5])
    L /= np.linalg.norm(L)
    nx, ny, nz = -gx, -gy, np.ones_like(h)
    n = np.sqrt(nx * nx + ny * ny + nz * nz)
    d = (nx * L[0] + ny * L[1] + nz * L[2]) / n
    f = 1 + (d / L[2] - 1) * strength
    return np.clip(col * f[..., None], 0, 1)


def belt_image(tier: str, shape: str, d: int, frame: int) -> Image.Image:
    u, v, inside = path_coords(shape, d)
    col, h, inside = shade_belt(u, v, inside, tier, frame * PERIOD / BELT_FRAMES)
    rgb = light(col, h)
    a = inside.astype(np.float32)
    big = np.dstack([rgb, a])
    img = Image.fromarray((big * 255 + 0.5).astype(np.uint8), 'RGBA').resize((T, T), Image.BOX)
    return add_grit(img, 0.03, f'belt{tier}')


# ------------------------------------------------------------------------------------------- undergrounds

def underground_image(tier: str, mode: str, d: int) -> tuple[Image.Image, tuple]:
    """mode 'in': items enter from the back and dive under at the front; 'out': emerge at the back."""
    base = belt_image(tier, 'straight', d, 0)
    tc = TIERS[tier]
    cv = ECanvas(1, 1, (4, 10, 8, 8))
    ctx = cv.ctx
    # draw in the north-facing frame, rotated about the tile centre
    ctx.save()
    ctx.translate(32, 32)
    ctx.rotate(d * math.pi / 2)
    ctx.translate(-32, -32)
    # hood covers the front half for 'in' (the tunnel is ahead), the back half for 'out'
    hy = -4 if mode == 'in' else 30
    hh = 38
    # side walls + hood (rounded arch)
    rrect(ctx, 1, hy, 62, hh, 7)
    fill_grad(ctx, lin(0, hy, 0, hy + hh, [(0, shade(P['steel_m'], 1.15)), (1, shade(P['steel'], 0.75))]))
    rrect(ctx, 1.5, hy + 0.5, 61, hh - 1, 7)
    stroke(ctx, P['outline'], 1.0)
    # tier colour band
    rrect(ctx, 5, hy + 5, 54, hh - 10, 5)
    fill_grad(ctx, lin(5, hy, 59, hy + hh, [(0, shade(tc, 1.2)), (1, shade(tc, 0.75))]))
    rrect(ctx, 5.5, hy + 5.5, 53, hh - 11, 5)
    stroke(ctx, alpha(P['outline'], 0.7), 1.0)
    # tunnel mouth: dark opening facing the open belt half
    my = hy + hh - 12 if mode == 'in' else hy + 2
    rrect(ctx, 10, my, 44, 10, 3)
    fill_grad(ctx, lin(0, my, 0, my + 10, [(0, hexc('#0c0d0f')), (1, hexc('#22262a'))]))
    # chevron on the hood pointing in travel direction (north in this frame)
    cy = hy + hh / 2 - (3 if mode == 'in' else -3)
    ctx.move_to(22, cy + 5); ctx.line_to(32, cy - 5); ctx.line_to(42, cy + 5)
    stroke(ctx, alpha(P['outline'], 0.8), 4.0)
    ctx.move_to(22, cy + 5); ctx.line_to(32, cy - 5); ctx.line_to(42, cy + 5)
    stroke(ctx, shade(tc, 1.45), 2.2)
    for bx in (4.5, 59.5):
        bolt(ctx, bx, hy + 4, 1.3)
        bolt(ctx, bx, hy + hh - 4, 1.3)
    ctx.restore()
    hood, anchor = cv.finish(shadow=True, dx=3, dy=4, blur=2, strength=0.5)
    out = Image.new('RGBA', hood.size, (0, 0, 0, 0))
    out.alpha_composite(base, (cv.pad[0], cv.pad[1]))
    out.alpha_composite(hood)
    return out, anchor


# ------------------------------------------------------------------------------------------- splitters

def splitter_image(tier: str, d: int) -> tuple[Image.Image, tuple]:
    """Housing overlay; footprint 2x1 when facing n/s, 1x2 when facing e/w."""
    tc = TIERS[tier]
    fw, fh = (2, 1) if d % 2 == 0 else (1, 2)
    cv = ECanvas(fw, fh, (4, 14, 10, 10))
    ctx = cv.ctx
    ctx.save()
    # north-facing frame is 128 x 64; rotate about footprint centre
    ctx.translate(cv.pw / 2, cv.ph / 2)
    ctx.rotate(d * math.pi / 2)
    ctx.translate(-64, -32)
    # side posts
    for x0 in (-2, 120):
        block(ctx, x0, 6, 10, 56, P['steel'], depth=5, r=3)
    # cross beam (the splitter body) across both lanes, raised
    by, bh = 14, 34
    block(ctx, 2, by, 124, bh, shade(P['steel_m'], 0.95), depth=7, r=5)
    plate(ctx, 8, by + 4, 112, bh - 15, tc, r=3)
    # divider in the middle
    rrect(ctx, 61, by - 4, 6, bh + 6, 2)
    fill_grad(ctx, lin(61, 0, 67, 0, [(0, shade(P['steel_l'], 1.1)), (1, shade(P['steel'], 0.7))]))
    rrect(ctx, 61.5, by - 3.5, 5, bh + 5, 2)
    stroke(ctx, P['outline'], 1.0)
    # two arrows (one per lane)
    for cx in (34, 94):
        ctx.move_to(cx - 9, by + 16); ctx.line_to(cx, by + 8); ctx.line_to(cx + 9, by + 16)
        stroke(ctx, alpha(P['outline'], 0.8), 4.2)
        ctx.move_to(cx - 9, by + 16); ctx.line_to(cx, by + 8); ctx.line_to(cx + 9, by + 16)
        stroke(ctx, shade(tc, 1.6), 2.2)
    for bx in (12, 56, 72, 116):
        bolt(ctx, bx, by + 23, 1.4)
    ctx.restore()
    return cv.finish(shadow=True, dx=4, dy=5)


# ------------------------------------------------------------------------------------------- generate

def generate(reg, data):
    meta = {}
    for tier in TIERS:
        for shape in ('straight', 'curve_left', 'curve_right'):
            for d, dn in enumerate(DIRS):
                for f in range(BELT_FRAMES):
                    reg.add(f'belt_{tier}_{shape}_{dn}_f{f}', belt_image(tier, shape, d, f), 'belts')
        tid = TIER_IDS[tier]
        for mode in ('in', 'out'):
            for d, dn in enumerate(DIRS):
                img, anc = underground_image(tier, mode, d)
                reg.add(f'entity_{tid}underground_belt_{mode}_{dn}', img, 'belts', anc)
        for d, dn in enumerate(DIRS):
            img, anc = splitter_image(tier, d)
            reg.add(f'entity_{tid}splitter_{dn}', img, 'belts', anc, composite='belt_straight_under')
    meta['beltFrames'] = BELT_FRAMES
    meta['beltPatternPeriodPx'] = PERIOD
    return meta
