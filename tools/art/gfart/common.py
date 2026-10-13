"""Gearforge art toolkit — shared drawing helpers (pycairo + Pillow + numpy).

Conventions
-----------
* 64 px per tile. Light comes from the TOP-LEFT. Shadows fall to the bottom-right.
* "3/4 view": an object's top face is drawn inside its footprint and a darker front (south) face of a few
  pixels shows its height.
* Everything is deterministic: randomness comes from `rng(name)` seeded by a CRC of a string.
"""
from __future__ import annotations

import math
import zlib

import cairo
import numpy as np
from PIL import Image, ImageFilter

T = 64  # pixels per tile

# --------------------------------------------------------------------------------------------- palette

def hexc(h: str, a: float = 1.0):
    h = h.lstrip('#')
    return (int(h[0:2], 16) / 255, int(h[2:4], 16) / 255, int(h[4:6], 16) / 255, a)


def shade(c, f: float):
    """f > 1 lightens towards white, f < 1 darkens towards black."""
    r, g, b = c[:3]
    a = c[3] if len(c) > 3 else 1.0
    if f >= 1:
        t = f - 1
        return (r + (1 - r) * t, g + (1 - g) * t, b + (1 - b) * t, a)
    return (r * f, g * f, b * f, a)


def mix(c1, c2, t: float):
    a1 = c1[3] if len(c1) > 3 else 1.0
    a2 = c2[3] if len(c2) > 3 else 1.0
    return tuple(c1[i] * (1 - t) + c2[i] * t for i in range(3)) + (a1 * (1 - t) + a2 * t,)


def alpha(c, a):
    return (c[0], c[1], c[2], a)


P = {
    'outline': hexc('#14171a'),
    'steel_d': hexc('#2a2f34'),
    'steel': hexc('#4d565e'),
    'steel_m': hexc('#6b757e'),
    'steel_l': hexc('#97a1a9'),
    'steel_h': hexc('#d0d7dc'),
    'iron': hexc('#5b6168'),
    'brass_d': hexc('#6a4816'),
    'brass': hexc('#b8862e'),
    'brass_l': hexc('#e0b35a'),
    'brass_h': hexc('#f7e0a0'),
    'copper': hexc('#c56a35'),
    'copper_l': hexc('#e8975c'),
    'amber': hexc('#f2a81d'),
    'glow': hexc('#ffd36a'),
    'fire': hexc('#ff7a1a'),
    'fire_l': hexc('#ffc44d'),
    'rubber': hexc('#25272a'),
    'rubber_l': hexc('#3b3e42'),
    'wood': hexc('#8a5a2f'),
    'wood_l': hexc('#b98348'),
    'wood_d': hexc('#4f321a'),
    'stone': hexc('#9a8e78'),
    'stone_l': hexc('#c3b79c'),
    'stone_d': hexc('#5f574a'),
    'glass': hexc('#7fc6d6'),
    'hazard': hexc('#e8b021'),
    'green': hexc('#4fae3c'),
    'teal': hexc('#2f9e94'),
    'shadow': (0.04, 0.05, 0.06, 1.0),
}

TIERS = {
    'basic': hexc('#e3a823'),    # yellow / amber
    'fast': hexc('#d0412e'),     # red
    'express': hexc('#2f88d4'),  # blue
}

INSERTER_COLORS = {
    'burner_inserter': hexc('#8a6238'),
    'inserter': hexc('#e0a526'),
    'long_handed_inserter': hexc('#c8402f'),
    'fast_inserter': hexc('#3a7fd0'),
    'filter_inserter': hexc('#8e4fc4'),
    'stack_inserter': hexc('#4caa3e'),
    'stack_filter_inserter': hexc('#aab4bd'),
}

MACHINE_TIERS = {1: hexc('#d9a02a'), 2: hexc('#3b78c9'), 3: hexc('#2fa37a')}

CARD_COLORS = {
    'mechanics_card': hexc('#d43c2f'),
    'motion_card': hexc('#4cb43a'),
    'defense_card': hexc('#3a3d42'),
    'reaction_card': hexc('#3a8fd8'),
    'fabrication_card': hexc('#9a4fc8'),
    'systems_card': hexc('#e8c62c'),
    'orbital_card': hexc('#eef0f2'),
}

# --------------------------------------------------------------------------------------------- rng

def rng(name: str) -> np.random.RandomState:
    return np.random.RandomState(zlib.crc32(name.encode('utf-8')) & 0x7FFFFFFF)


# --------------------------------------------------------------------------------------------- canvas

class Canvas:
    def __init__(self, w: int, h: int):
        self.w, self.h = int(w), int(h)
        self.surf = cairo.ImageSurface(cairo.FORMAT_ARGB32, self.w, self.h)
        self.ctx = cairo.Context(self.surf)
        self.ctx.set_line_join(cairo.LINE_JOIN_ROUND)
        self.ctx.set_line_cap(cairo.LINE_CAP_ROUND)

    def pil(self) -> Image.Image:
        return surf_to_pil(self.surf)


def surf_to_pil(surf: cairo.ImageSurface) -> Image.Image:
    surf.flush()
    w, h = surf.get_width(), surf.get_height()
    stride = surf.get_stride()
    a = np.ndarray((h, stride // 4, 4), np.uint8, surf.get_data())[:, :w, :].astype(np.float32)
    al = a[..., 3:4]
    rgb = np.where(al > 0, a[..., [2, 1, 0]] * 255.0 / np.maximum(al, 1), 0)
    out = np.dstack([np.clip(rgb + 0.5, 0, 255), al]).astype(np.uint8)
    return Image.fromarray(out, 'RGBA')


def pil_to_surf(img: Image.Image) -> cairo.ImageSurface:
    img = img.convert('RGBA')
    w, h = img.size
    a = np.asarray(img).astype(np.float32)
    al = a[..., 3:4] / 255.0
    pm = np.dstack([a[..., 2:3] * al, a[..., 1:2] * al, a[..., 0:1] * al, a[..., 3:4]])
    surf = cairo.ImageSurface(cairo.FORMAT_ARGB32, w, h)
    stride = surf.get_stride()
    buf = np.ndarray((h, stride // 4, 4), np.uint8, surf.get_data())
    buf[:, :w, :] = np.clip(pm + 0.5, 0, 255).astype(np.uint8)
    surf.mark_dirty()
    return surf


def np_rgba(img: Image.Image) -> np.ndarray:
    return np.asarray(img.convert('RGBA')).astype(np.float32) / 255.0


def from_np(a: np.ndarray) -> Image.Image:
    return Image.fromarray(np.clip(a * 255 + 0.5, 0, 255).astype(np.uint8), 'RGBA')


def over(dst: Image.Image, src: Image.Image, pos=(0, 0)) -> Image.Image:
    out = dst.copy()
    out.alpha_composite(src, pos)
    return out


# --------------------------------------------------------------------------------------------- shadows

def shadow_from_alpha(alpha_img: Image.Image, dx=3, dy=4, blur=2.2, strength=0.42) -> Image.Image:
    """alpha_img: 'L' image of the caster silhouette (same size as the sprite)."""
    w, h = alpha_img.size
    sh = Image.new('L', (w, h), 0)
    sh.paste(alpha_img, (int(dx), int(dy)))
    sh = sh.filter(ImageFilter.GaussianBlur(blur))
    a = (np.asarray(sh).astype(np.float32) * strength).astype(np.uint8)
    out = np.zeros((h, w, 4), np.uint8)
    out[..., 0], out[..., 1], out[..., 2] = 10, 12, 14
    out[..., 3] = a
    return Image.fromarray(out, 'RGBA')


def with_shadow(img: Image.Image, dx=3, dy=4, blur=2.2, strength=0.42, caster: Image.Image | None = None):
    al = (caster if caster is not None else img).getchannel('A')
    sh = shadow_from_alpha(al, dx, dy, blur, strength)
    sh.alpha_composite(img)
    return sh


# --------------------------------------------------------------------------------------------- paths

def rrect(ctx, x, y, w, h, r):
    r = max(0.0, min(r, w / 2, h / 2))
    ctx.new_sub_path()
    ctx.arc(x + w - r, y + r, r, -math.pi / 2, 0)
    ctx.arc(x + w - r, y + h - r, r, 0, math.pi / 2)
    ctx.arc(x + r, y + h - r, r, math.pi / 2, math.pi)
    ctx.arc(x + r, y + r, r, math.pi, 3 * math.pi / 2)
    ctx.close_path()


def circle(ctx, x, y, r):
    ctx.new_sub_path()
    ctx.arc(x, y, r, 0, 2 * math.pi)
    ctx.close_path()


def ellipse(ctx, x, y, rx, ry):
    ctx.save()
    ctx.translate(x, y)
    ctx.scale(max(rx, 1e-3), max(ry, 1e-3))
    ctx.new_sub_path()
    ctx.arc(0, 0, 1, 0, 2 * math.pi)
    ctx.close_path()
    ctx.restore()


def poly(ctx, pts, close=True):
    ctx.move_to(*pts[0])
    for p in pts[1:]:
        ctx.line_to(*p)
    if close:
        ctx.close_path()


def gear_path(ctx, cx, cy, r_out, r_in, teeth, rot=0.0, tooth_frac=0.5, hole=0.0):
    """A gear outline with trapezoid teeth. hole > 0 adds an inner hole (use EVEN_ODD fill)."""
    n = teeth
    pts = []
    for i in range(n):
        a0 = rot + 2 * math.pi * i / n
        step = 2 * math.pi / n
        w = step * tooth_frac
        # base of tooth (r_in) -> tip (r_out) with slight taper
        pts.append((a0 - w * 0.62, r_in))
        pts.append((a0 - w * 0.40, r_out))
        pts.append((a0 + w * 0.40, r_out))
        pts.append((a0 + w * 0.62, r_in))
    ctx.new_sub_path()
    for k, (a, r) in enumerate(pts):
        x, y = cx + r * math.cos(a), cy + r * math.sin(a)
        if k == 0:
            ctx.move_to(x, y)
        else:
            ctx.line_to(x, y)
    ctx.close_path()
    if hole > 0:
        ctx.new_sub_path()
        ctx.arc_negative(cx, cy, hole, 2 * math.pi, 0)
        ctx.close_path()


# --------------------------------------------------------------------------------------------- paint helpers

def src(ctx, c):
    if len(c) == 3:
        ctx.set_source_rgb(*c)
    else:
        ctx.set_source_rgba(*c)


def fill(ctx, c, preserve=False):
    src(ctx, c)
    ctx.fill_preserve() if preserve else ctx.fill()


def stroke(ctx, c, w=1.0, preserve=False):
    src(ctx, c)
    ctx.set_line_width(w)
    ctx.stroke_preserve() if preserve else ctx.stroke()


def lin(x0, y0, x1, y1, stops):
    g = cairo.LinearGradient(x0, y0, x1, y1)
    for off, c in stops:
        if len(c) == 3:
            g.add_color_stop_rgb(off, *c)
        else:
            g.add_color_stop_rgba(off, *c)
    return g


def rad(cx, cy, r0, r1, stops, fx=None, fy=None):
    g = cairo.RadialGradient(fx if fx is not None else cx, fy if fy is not None else cy, r0, cx, cy, r1)
    for off, c in stops:
        if len(c) == 3:
            g.add_color_stop_rgb(off, *c)
        else:
            g.add_color_stop_rgba(off, *c)
    return g


def fill_grad(ctx, g, preserve=False):
    ctx.set_source(g)
    ctx.fill_preserve() if preserve else ctx.fill()


def tl_grad(x, y, w, h, c, lo=0.82, hi=1.12):
    """Top-left lit gradient for a flat face."""
    return lin(x, y, x + w * 0.6, y + h, [(0, shade(c, hi)), (1, shade(c, lo))])


# --------------------------------------------------------------------------------------------- primitives

def block(ctx, x, y, w, h, color, depth=6, r=4, outline=True, top_hi=1.14, top_lo=0.86, front=0.62, edge=True):
    """A 3/4-view box occupying (x,y,w,h) on screen; the bottom `depth` px is the front face.
    Returns the top-face rect (x, y, w, h-depth)."""
    th = h - depth
    # front face (whole silhouette first so the rounded corners read)
    rrect(ctx, x, y, w, h, r)
    fill_grad(ctx, lin(0, y + th - 2, 0, y + h, [(0, shade(color, front + 0.08)), (1, shade(color, front - 0.14))]))
    # top face
    rrect(ctx, x, y, w, th, r)
    fill_grad(ctx, tl_grad(x, y, w, th, color, top_lo, top_hi))
    if edge:
        # highlight on top-left edges
        ctx.save()
        rrect(ctx, x + 0.5, y + 0.5, w - 1, th - 1, max(r - 0.5, 0))
        ctx.clip()
        ctx.set_line_width(1.6)
        src(ctx, alpha(shade(color, 1.55), 0.55))
        ctx.move_to(x + 0.8, y + th - r)
        ctx.line_to(x + 0.8, y + 0.8)
        ctx.line_to(x + w - r, y + 0.8)
        ctx.stroke()
        ctx.restore()
        # crease between top and front
        ctx.move_to(x + r * 0.6, y + th + 0.5)
        ctx.line_to(x + w - r * 0.6, y + th + 0.5)
        stroke(ctx, alpha(shade(color, 0.42), 0.9), 1.0)
    if outline:
        rrect(ctx, x + 0.5, y + 0.5, w - 1, h - 1, r)
        stroke(ctx, P['outline'], 1.0)
    return (x, y, w, th)


def plate(ctx, x, y, w, h, color, r=3, inset=False, hi=1.12, lo=0.86, line=True):
    """A flat panel (raised or inset) on a top face."""
    rrect(ctx, x, y, w, h, r)
    if inset:
        fill_grad(ctx, lin(x, y, x + w * 0.5, y + h, [(0, shade(color, 0.72)), (1, shade(color, 1.0))]))
    else:
        fill_grad(ctx, tl_grad(x, y, w, h, color, lo, hi))
    if line:
        if inset:
            # dark top-left inner edge, light bottom-right
            ctx.save(); rrect(ctx, x, y, w, h, r); ctx.clip()
            ctx.move_to(x, y + h); ctx.line_to(x, y); ctx.line_to(x + w, y)
            stroke(ctx, alpha(P['outline'], 0.7), 2.0)
            ctx.move_to(x + w, y); ctx.line_to(x + w, y + h); ctx.line_to(x, y + h)
            stroke(ctx, alpha(shade(color, 1.5), 0.45), 1.5)
            ctx.restore()
        else:
            ctx.save(); rrect(ctx, x, y, w, h, r); ctx.clip()
            ctx.move_to(x + w, y + 0.5); ctx.line_to(x + 0.5, y + 0.5); ctx.line_to(x + 0.5, y + h)
            stroke(ctx, alpha(shade(color, 1.6), 0.5), 1.2)
            ctx.move_to(x + 0.5, y + h - 0.5); ctx.line_to(x + w - 0.5, y + h - 0.5); ctx.line_to(x + w - 0.5, y)
            stroke(ctx, alpha(shade(color, 0.45), 0.7), 1.2)
            ctx.restore()
            rrect(ctx, x + 0.5, y + 0.5, w - 1, h - 1, r)
            stroke(ctx, alpha(P['outline'], 0.55), 0.8)


def bolt(ctx, x, y, r=1.6, color=None):
    color = color or P['steel_l']
    circle(ctx, x + 0.4, y + 0.5, r + 0.3)
    fill(ctx, alpha(P['outline'], 0.6))
    circle(ctx, x, y, r)
    fill_grad(ctx, rad(x - r * 0.4, y - r * 0.4, 0, r * 1.4, [(0, shade(color, 1.5)), (1, shade(color, 0.7))]))


def vents(ctx, x, y, w, h, n, color=None, horizontal=True):
    color = color or P['steel_d']
    if horizontal:
        step = h / n
        for i in range(n):
            yy = y + i * step + step * 0.25
            rrect(ctx, x, yy, w, step * 0.5, step * 0.25)
            fill(ctx, shade(color, 0.55))
            ctx.move_to(x + 1, yy + step * 0.5 + 0.6)
            ctx.line_to(x + w - 1, yy + step * 0.5 + 0.6)
            stroke(ctx, alpha(P['steel_h'], 0.25), 0.8)
    else:
        step = w / n
        for i in range(n):
            xx = x + i * step + step * 0.25
            rrect(ctx, xx, y, step * 0.5, h, step * 0.25)
            fill(ctx, shade(color, 0.55))
            ctx.move_to(xx + step * 0.5 + 0.6, y + 1)
            ctx.line_to(xx + step * 0.5 + 0.6, y + h - 1)
            stroke(ctx, alpha(P['steel_h'], 0.25), 0.8)


def lamp(ctx, x, y, r, color, on=True):
    if on:
        circle(ctx, x, y, r * 2.6)
        fill_grad(ctx, rad(x, y, 0, r * 2.6, [(0, alpha(color, 0.55)), (1, alpha(color, 0))]))
    circle(ctx, x, y, r + 0.8)
    fill(ctx, P['outline'])
    circle(ctx, x, y, r)
    if on:
        fill_grad(ctx, rad(x - r * 0.3, y - r * 0.3, 0, r * 1.2, [(0, shade(color, 1.7)), (0.6, color), (1, shade(color, 0.8))]))
    else:
        fill_grad(ctx, rad(x - r * 0.3, y - r * 0.3, 0, r * 1.2, [(0, shade(color, 0.75)), (1, shade(color, 0.35))]))


def hazard(ctx, x, y, w, h, period=8, c1=None, c2=None, angle=1):
    c1 = c1 or P['hazard']
    c2 = c2 or P['outline']
    ctx.save()
    ctx.rectangle(x, y, w, h)
    ctx.clip()
    fill_grad(ctx, lin(x, y, x, y + h, [(0, shade(c1, 1.05)), (1, shade(c1, 0.85))]))
    ctx.rectangle(x, y, w, h)
    ctx.new_path()
    src(ctx, c2)
    k = -period * 4
    while k < w + h + period:
        ctx.move_to(x + k, y + h) if angle > 0 else ctx.move_to(x + k, y)
        ctx.line_to(x + k + period / 2, y + h) if angle > 0 else ctx.line_to(x + k + period / 2, y)
        ctx.line_to(x + k + period / 2 + h, y) if angle > 0 else ctx.line_to(x + k + period / 2 + h, y + h)
        ctx.line_to(x + k + h, y) if angle > 0 else ctx.line_to(x + k + h, y + h)
        ctx.close_path()
        k += period
    ctx.fill()
    ctx.restore()


def glow(ctx, x, y, r, color, a=0.6):
    circle(ctx, x, y, r)
    fill_grad(ctx, rad(x, y, 0, r, [(0, alpha(color, a)), (0.5, alpha(color, a * 0.35)), (1, alpha(color, 0))]))


def cyl_v(ctx, cx, top_y, rx, height, color, ry=None, cap=None, outline=True):
    """Upright cylinder in 3/4 view: ellipse top centred (cx, top_y), body extends `height` down."""
    ry = ry if ry is not None else rx * 0.62
    # body
    ctx.new_path()
    ctx.move_to(cx - rx, top_y)
    ctx.line_to(cx - rx, top_y + height)
    ctx.save(); ctx.translate(cx, top_y + height); ctx.scale(rx, ry); ctx.arc_negative(-1 + 1, 0, 1, math.pi, 0); ctx.restore()
    ctx.line_to(cx + rx, top_y)
    ctx.close_path()
    fill_grad(ctx, lin(cx - rx, 0, cx + rx, 0, [(0, shade(color, 1.05)), (0.3, shade(color, 1.18)), (0.75, shade(color, 0.72)), (1, shade(color, 0.5))]))
    if outline:
        ctx.move_to(cx - rx, top_y)
        ctx.line_to(cx - rx, top_y + height)
        ctx.save(); ctx.translate(cx, top_y + height); ctx.scale(rx, ry); ctx.arc_negative(0, 0, 1, math.pi, 0); ctx.restore()
        ctx.line_to(cx + rx, top_y)
        stroke(ctx, P['outline'], 1.0)
    # top
    ellipse(ctx, cx, top_y, rx, ry)
    capc = cap or shade(color, 1.1)
    fill_grad(ctx, lin(cx - rx, top_y - ry, cx + rx * 0.6, top_y + ry, [(0, shade(capc, 1.2)), (1, shade(capc, 0.82))]))
    if outline:
        ellipse(ctx, cx, top_y, rx - 0.5, ry - 0.5)
        stroke(ctx, P['outline'], 1.0)


def pipe_h(ctx, x0, x1, cy, r, color=None):
    color = color or P['steel_m']
    ctx.rectangle(x0, cy - r, x1 - x0, 2 * r)
    fill_grad(ctx, lin(0, cy - r, 0, cy + r, [(0, shade(color, 0.9)), (0.25, shade(color, 1.35)), (0.6, color), (1, shade(color, 0.45))]))
    ctx.move_to(x0, cy - r + 0.5); ctx.line_to(x1, cy - r + 0.5)
    ctx.move_to(x0, cy + r - 0.5); ctx.line_to(x1, cy + r - 0.5)
    stroke(ctx, P['outline'], 1.0)


def pipe_v(ctx, y0, y1, cx, r, color=None):
    color = color or P['steel_m']
    ctx.rectangle(cx - r, y0, 2 * r, y1 - y0)
    fill_grad(ctx, lin(cx - r, 0, cx + r, 0, [(0, shade(color, 0.95)), (0.3, shade(color, 1.35)), (0.65, color), (1, shade(color, 0.45))]))
    ctx.move_to(cx - r + 0.5, y0); ctx.line_to(cx - r + 0.5, y1)
    ctx.move_to(cx + r - 0.5, y0); ctx.line_to(cx + r - 0.5, y1)
    stroke(ctx, P['outline'], 1.0)


def flange(ctx, cx, cy, r, vertical, color=None, length=4):
    """A ring/flange around a pipe. vertical=True means the pipe runs vertically (flange is horizontal band)."""
    color = color or P['brass']
    if vertical:
        x, y, w, h = cx - r - 2, cy - length / 2, 2 * r + 4, length
        rrect(ctx, x, y, w, h, 1.2)
        fill_grad(ctx, lin(x, 0, x + w, 0, [(0, shade(color, 1.0)), (0.3, shade(color, 1.4)), (0.7, color), (1, shade(color, 0.5))]))
    else:
        x, y, w, h = cx - length / 2, cy - r - 2, length, 2 * r + 4
        rrect(ctx, x, y, w, h, 1.2)
        fill_grad(ctx, lin(0, y, 0, y + h, [(0, shade(color, 1.0)), (0.25, shade(color, 1.4)), (0.6, color), (1, shade(color, 0.5))]))
    rrect(ctx, x + 0.5, y + 0.5, w - 1, h - 1, 1.2)
    stroke(ctx, P['outline'], 1.0)


def text_center(ctx, s, cx, cy, size, color, bold=True, font='DejaVu Sans'):
    ctx.select_font_face(font, cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_BOLD if bold else cairo.FONT_WEIGHT_NORMAL)
    ctx.set_font_size(size)
    xb, yb, tw, th, xa, ya = ctx.text_extents(s)
    ctx.move_to(cx - tw / 2 - xb, cy - th / 2 - yb)
    ctx.text_path(s)
    src(ctx, color)
    ctx.fill()


def outline_image(img: Image.Image, width=1.0, color=(20, 23, 26), strength=1.0) -> Image.Image:
    """Adds a dark outline around the silhouette of an icon (for readability on any background)."""
    a = img.getchannel('A')
    grown = a.filter(ImageFilter.MaxFilter(3))
    if width > 1.2:
        grown = grown.filter(ImageFilter.MaxFilter(3))
    grown = grown.filter(ImageFilter.GaussianBlur(0.5))
    g = (np.asarray(grown).astype(np.float32) * strength).astype(np.uint8)
    base = np.zeros((img.size[1], img.size[0], 4), np.uint8)
    base[..., 0], base[..., 1], base[..., 2] = color
    base[..., 3] = g
    out = Image.fromarray(base, 'RGBA')
    out.alpha_composite(img)
    return out


def rotate_img(img: Image.Image, k: int) -> Image.Image:
    """Rotate clockwise by k*90 degrees."""
    k %= 4
    if k == 0:
        return img.copy()
    return img.transpose({1: Image.Transpose.ROTATE_270, 2: Image.Transpose.ROTATE_180, 3: Image.Transpose.ROTATE_90}[k])


DIRS = ['n', 'e', 's', 'w']


def rot_vec(x, y, k):
    """Rotate a (x, y) offset (screen coords, y down) clockwise k quarter turns."""
    for _ in range(k % 4):
        x, y = -y, x
    return x, y


# --------------------------------------------------------------------------------------------- entity canvas

class ECanvas(Canvas):
    """Canvas for a world sprite whose *footprint* is fw x fh tiles.

    Drawing coordinates are footprint pixels: (0,0) = top-left corner of the footprint, (fw*T, fh*T) = bottom-right.
    Padding (left, top, right, bottom) allows overhang: height above the footprint (top) and baked shadows
    (right/bottom). `finish()` returns (PIL image, SpriteKit anchor) where the anchor maps to the footprint centre.
    """

    def __init__(self, fw: float, fh: float, pad=(4, 14, 10, 10)):
        self.fw, self.fh = fw, fh
        self.pad = pad
        self.W = int(round(fw * T)) + pad[0] + pad[2]
        self.H = int(round(fh * T)) + pad[1] + pad[3]
        super().__init__(self.W, self.H)
        self.ctx.translate(pad[0], pad[1])
        self.pw, self.ph = fw * T, fh * T

    def anchor(self):
        l, t, r, b = self.pad
        return ((l + self.pw / 2) / self.W, (b + self.ph / 2) / self.H)

    def finish(self, shadow=True, dx=4, dy=5, blur=2.4, strength=0.45, grit=0.035, caster=None):
        img = self.pil()
        if grit:
            img = add_grit(img, grit, seed=f'{self.W}x{self.H}')
        if shadow:
            img = with_shadow(img, dx, dy, blur, strength, caster)
        return img, self.anchor()


def add_grit(img: Image.Image, amount=0.035, seed='grit') -> Image.Image:
    """Subtle deterministic luminance noise + low-frequency grime on the opaque pixels (material texture)."""
    a = np.asarray(img).astype(np.float32)
    h, w = a.shape[:2]
    r = rng('grit:' + seed)
    n = r.randn(h, w).astype(np.float32)
    # low-frequency grime: blurred noise
    g = Image.fromarray(np.clip(128 + r.randn(h // 4 + 1, w // 4 + 1) * 60, 0, 255).astype(np.uint8), 'L')
    g = np.asarray(g.resize((w, h), Image.BICUBIC)).astype(np.float32) / 128.0 - 1.0
    f = 1.0 + n * amount + g * amount * 1.4
    a[..., :3] = np.clip(a[..., :3] * f[..., None], 0, 255)
    return Image.fromarray(a.astype(np.uint8), 'RGBA')


def fit_icon(img: Image.Image, size=64, box=54, outline=True, shadow=True) -> Image.Image:
    """Scale a sprite into a size x size icon (keeps aspect, centred), with outline + small shadow."""
    img = img.copy()
    bb = img.getchannel('A').point(lambda v: 255 if v > 40 else 0).getbbox()
    if bb:
        img = img.crop(bb)
    w, h = img.size
    s = box / max(w, h)
    nw, nh = max(1, int(round(w * s))), max(1, int(round(h * s)))
    img = img.resize((nw, nh), Image.LANCZOS)
    out = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    out.alpha_composite(img, ((size - nw) // 2, (size - nh) // 2))
    if outline:
        out = outline_image(out, 1.0, strength=0.85)
    if shadow:
        out = with_shadow(out, 1.5, 2, 1.2, 0.45)
    return out


def icon_canvas(size=64):
    return Canvas(size, size)


def finish_icon(cv: Canvas, grit=0.02, outline=True, shadow=True) -> Image.Image:
    img = cv.pil()
    if grit:
        img = add_grit(img, grit, 'icon')
    if outline:
        img = outline_image(img, 1.0, strength=0.9)
    if shadow:
        img = with_shadow(img, 1.5, 2, 1.2, 0.45)
    return img
