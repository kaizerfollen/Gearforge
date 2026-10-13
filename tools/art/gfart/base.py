"""Top-down entity helpers shared by every world-sprite generator.

* Sprites are exactly footprint x 64 px. The body is inset (2 px top/left, ~5 px bottom/right) so the soft drop
  shadow (offset to the bottom-right) stays inside the footprint.
* Directional entities are *described* in their north-facing frame and transformed to screen space with `Fr`, but
  every gradient is computed in screen space, so the light always comes from the top-left.
"""
from __future__ import annotations

import math

from PIL import Image

from .common import (T, Canvas, P, add_grit, alpha, bolt, circle, fill, fill_grad, hexc, lin, rad, rrect, shade,
                     src, stroke, with_shadow)

DIRS = ['n', 'e', 's', 'w']
OUT = P['outline']

# machine palette
BODY = hexc('#5d666f')
BODY_L = hexc('#7d8790')
BODY_D = hexc('#3a4148')
FRAME = hexc('#454c53')


class Fr:
    """North-frame (W x H px) -> screen transform for k clockwise quarter turns."""

    def __init__(self, W, H, k):
        self.W, self.H, self.k = W, H, k % 4

    @property
    def size(self):
        return (self.W, self.H) if self.k % 2 == 0 else (self.H, self.W)

    def pt(self, x, y):
        W, H = self.W, self.H
        for _ in range(self.k):
            x, y = H - y, x
            W, H = H, W
        return x, y

    def rect(self, x, y, w, h):
        x0, y0 = self.pt(x, y)
        x1, y1 = self.pt(x + w, y + h)
        return min(x0, x1), min(y0, y1), abs(x1 - x0), abs(y1 - y0)

    def vec(self, dx, dy):
        for _ in range(self.k):
            dx, dy = -dy, dx
        return dx, dy

    def angle(self, a):
        return a + self.k * math.pi / 2


def ent_canvas(fw, fh):
    return Canvas(int(fw * T), int(fh * T))


def finish(cv: Canvas, shadow=True, grit=0.03, dx=3, dy=3.5, blur=2.2, strength=0.5, seed=None) -> Image.Image:
    img = cv.pil()
    if grit:
        img = add_grit(img, grit, seed or f'{cv.w}x{cv.h}')
    if shadow:
        img = with_shadow(img, dx, dy, blur, strength)
    return img


def bevel_box(ctx, x, y, w, h, c, r=4, bev=2.5, outline=True, hi=1.25, lo=0.6, face_hi=1.1, face_lo=0.88):
    """A raised top-down box: outline, light top-left bevel, dark bottom-right bevel, gradient face."""
    rrect(ctx, x, y, w, h, r)
    fill_grad(ctx, lin(x, y, x + w, y + h, [(0, shade(c, hi)), (0.5, c), (1, shade(c, lo))]))
    rrect(ctx, x + bev, y + bev, w - 2 * bev, h - 2 * bev, max(0.5, r - bev * 0.6))
    fill_grad(ctx, lin(x, y, x + w * 0.5, y + h, [(0, shade(c, face_hi)), (1, shade(c, face_lo))]))
    if outline:
        rrect(ctx, x + 0.5, y + 0.5, w - 1, h - 1, r)
        stroke(ctx, OUT, 1.2)


def inset_box(ctx, x, y, w, h, c, r=3, depth=2.0):
    """A recessed panel: dark top-left inner edge, light bottom-right."""
    rrect(ctx, x, y, w, h, r)
    fill_grad(ctx, lin(x, y, x + w * 0.4, y + h, [(0, shade(c, 0.7)), (1, shade(c, 1.0))]))
    ctx.save(); rrect(ctx, x, y, w, h, r); ctx.clip()
    ctx.move_to(x, y + h); ctx.line_to(x, y); ctx.line_to(x + w, y)
    stroke(ctx, alpha(OUT, 0.75), depth * 1.6)
    ctx.move_to(x + w, y); ctx.line_to(x + w, y + h); ctx.line_to(x, y + h)
    stroke(ctx, alpha(shade(c, 1.7), 0.35), 1.4)
    ctx.restore()
    rrect(ctx, x + 0.5, y + 0.5, w - 1, h - 1, r)
    stroke(ctx, alpha(OUT, 0.6), 0.8)


def rivets(ctx, x, y, w, h, inset=4, r=1.5, mid=False, color=None):
    pts = [(x + inset, y + inset), (x + w - inset, y + inset), (x + inset, y + h - inset), (x + w - inset, y + h - inset)]
    if mid:
        pts += [(x + w / 2, y + inset), (x + w / 2, y + h - inset), (x + inset, y + h / 2), (x + w - inset, y + h / 2)]
    for px, py in pts:
        bolt(ctx, px, py, r, color)


def machine_frame(ctx, fw, fh, accent=None, body=BODY, r=6, stripe=True):
    """The common machine chassis: bevelled body plate inset in the footprint with a framed border.
    Returns the inner face rect (x, y, w, h)."""
    W, H = fw * T, fh * T
    x, y, w, h = 2, 2, W - 7, H - 7
    bevel_box(ctx, x, y, w, h, shade(body, 0.85), r=r, bev=3)
    # inner raised deck
    ix, iy, iw, ih = x + 6, y + 6, w - 12, h - 12
    bevel_box(ctx, ix, iy, iw, ih, body, r=max(2, r - 2), bev=2, hi=1.3, lo=0.55)
    if accent is not None and stripe:
        # accent corners (tier colour)
        for (cx, cy, sx, sy) in ((x, y, 1, 1), (x + w, y, -1, 1), (x, y + h, 1, -1), (x + w, y + h, -1, -1)):
            ctx.move_to(cx + sx * 3, cy + sy * 14); ctx.line_to(cx + sx * 3, cy + sy * 3); ctx.line_to(cx + sx * 14, cy + sy * 3)
            stroke(ctx, OUT, 4.2)
            ctx.move_to(cx + sx * 3, cy + sy * 14); ctx.line_to(cx + sx * 3, cy + sy * 3); ctx.line_to(cx + sx * 14, cy + sy * 3)
            stroke(ctx, accent, 2.4)
    rivets(ctx, x, y, w, h, inset=3.2 if accent is None else 8, r=1.4)
    return ix, iy, iw, ih


def pipe_seg(ctx, x0, y0, x1, y1, r=6, color=None, outline=True):
    """Axis-aligned pipe in screen space between two points (either horizontal or vertical)."""
    color = color or P['steel_m']
    if abs(y1 - y0) < 1e-6:  # horizontal
        xa, xb = min(x0, x1), max(x0, x1)
        ctx.rectangle(xa, y0 - r, xb - xa, 2 * r)
        fill_grad(ctx, lin(0, y0 - r, 0, y0 + r, [(0, shade(color, 0.95)), (0.28, shade(color, 1.45)), (0.6, color), (1, shade(color, 0.45))]))
        if outline:
            ctx.move_to(xa, y0 - r + 0.5); ctx.line_to(xb, y0 - r + 0.5)
            ctx.move_to(xa, y0 + r - 0.5); ctx.line_to(xb, y0 + r - 0.5)
            stroke(ctx, OUT, 1.1)
    else:
        ya, yb = min(y0, y1), max(y0, y1)
        ctx.rectangle(x0 - r, ya, 2 * r, yb - ya)
        fill_grad(ctx, lin(x0 - r, 0, x0 + r, 0, [(0, shade(color, 0.95)), (0.28, shade(color, 1.45)), (0.6, color), (1, shade(color, 0.45))]))
        if outline:
            ctx.move_to(x0 - r + 0.5, ya); ctx.line_to(x0 - r + 0.5, yb)
            ctx.move_to(x0 + r - 0.5, ya); ctx.line_to(x0 + r - 0.5, yb)
            stroke(ctx, OUT, 1.1)


def flange_at(ctx, x, y, r, horizontal_pipe, color=None, length=5):
    color = color or P['steel_l']
    if horizontal_pipe:
        bx, by, bw, bh = x - length / 2, y - r - 2, length, 2 * r + 4
        g = lin(0, by, 0, by + bh, [(0, shade(color, 1.0)), (0.25, shade(color, 1.4)), (0.6, color), (1, shade(color, 0.45))])
    else:
        bx, by, bw, bh = x - r - 2, y - length / 2, 2 * r + 4, length
        g = lin(bx, 0, bx + bw, 0, [(0, shade(color, 1.0)), (0.25, shade(color, 1.4)), (0.6, color), (1, shade(color, 0.45))])
    rrect(ctx, bx, by, bw, bh, 1.2)
    fill_grad(ctx, g)
    rrect(ctx, bx + 0.5, by + 0.5, bw - 1, bh - 1, 1.2)
    stroke(ctx, OUT, 1.0)


def fluid_port(ctx, fr: Fr, x, y, side, r=6.5, length=10, color=None):
    """A pipe stub sticking out of a machine towards `side` ('n','e','s','w' in the north frame) ending at the
    footprint edge. (x, y) is the edge point in the north frame."""
    dx, dy = {'n': (0, 1), 's': (0, -1), 'e': (-1, 0), 'w': (1, 0)}[side]
    ax, ay = fr.pt(x, y)
    bx, by = fr.pt(x + dx * length, y + dy * length)
    pipe_seg(ctx, ax, ay, bx, by, r, color)
    horiz = abs(ay - by) < 1e-6
    fx, fy = fr.pt(x + dx * 2.5, y + dy * 2.5)
    flange_at(ctx, fx, fy, r, horiz, length=4)


def arrow(ctx, fr: Fr, cx, cy, size, color, width=3.0, kind='chevron'):
    """Direction chevron pointing north in the north frame."""
    pts = [(cx - size, cy + size * 0.55), (cx, cy - size * 0.55), (cx + size, cy + size * 0.55)]
    sp = [fr.pt(*p) for p in pts]
    for wdt, col in ((width + 2.2, OUT), (width, color)):
        ctx.move_to(*sp[0]); ctx.line_to(*sp[1]); ctx.line_to(*sp[2])
        stroke(ctx, col, wdt)


def fan(ctx, cx, cy, r, blades=6, rot=0.0, color=None, hub=None):
    """A cooling fan / rotor seen from above (housing ring + blades + hub)."""
    color = color or P['steel_l']
    circle(ctx, cx, cy, r + 2.5)
    fill_grad(ctx, lin(cx - r, cy - r, cx + r, cy + r, [(0, shade(BODY_D, 0.6)), (1, shade(BODY_L, 1.2))]))
    circle(ctx, cx, cy, r + 2.5)
    stroke(ctx, OUT, 1.1)
    circle(ctx, cx, cy, r)
    fill(ctx, hexc('#14181b'))
    for i in range(blades):
        a = rot + i * 2 * math.pi / blades
        ctx.save()
        ctx.translate(cx, cy)
        ctx.rotate(a)
        ctx.move_to(r * 0.2, -r * 0.12)
        ctx.curve_to(r * 0.55, -r * 0.42, r * 0.92, -r * 0.30, r * 0.94, 0)
        ctx.curve_to(r * 0.7, r * 0.12, r * 0.45, r * 0.16, r * 0.2, r * 0.12)
        ctx.close_path()
        ctx.restore()
        fill(ctx, color, preserve=True)
        stroke(ctx, alpha(OUT, 0.8), 0.8)
    circle(ctx, cx, cy, r * 0.28)
    fill_grad(ctx, rad(cx - r * 0.1, cy - r * 0.1, 0, r * 0.3, [(0, shade(hub or P['steel_l'], 1.4)), (1, shade(hub or P['steel'], 0.8))]))
    circle(ctx, cx, cy, r * 0.28)
    stroke(ctx, OUT, 0.9)


def glow_spot(ctx, x, y, r, color, a=0.7):
    circle(ctx, x, y, r)
    fill_grad(ctx, rad(x, y, 0, r, [(0, alpha(shade(color, 1.4), a)), (0.4, alpha(color, a * 0.5)), (1, alpha(color, 0))]))


def light_lamp(ctx, x, y, r, color, on=True):
    if on:
        glow_spot(ctx, x, y, r * 3, color, 0.55)
    circle(ctx, x, y, r + 1)
    fill(ctx, OUT)
    circle(ctx, x, y, r)
    if on:
        fill_grad(ctx, rad(x - r * 0.3, y - r * 0.3, 0, r * 1.2, [(0, shade(color, 1.8)), (0.6, color), (1, shade(color, 0.8))]))
    else:
        fill_grad(ctx, rad(x - r * 0.3, y - r * 0.3, 0, r * 1.2, [(0, shade(color, 0.7)), (1, shade(color, 0.3))]))


def hazard_band(ctx, x, y, w, h, period=8, c1=None, c2=None):
    c1 = c1 or P['hazard']
    c2 = c2 or hexc('#1d1f22')
    ctx.save()
    rrect(ctx, x, y, w, h, 1.5)
    ctx.clip()
    ctx.rectangle(x, y, w, h)
    fill(ctx, c1)
    src(ctx, c2)
    k = -max(w, h) * 2
    while k < w + h + period:
        ctx.move_to(x + k, y + h); ctx.line_to(x + k + period / 2, y + h)
        ctx.line_to(x + k + period / 2 + h, y); ctx.line_to(x + k + h, y)
        ctx.close_path()
        k += period
    ctx.fill()
    ctx.restore()
    rrect(ctx, x + 0.5, y + 0.5, w - 1, h - 1, 1.5)
    stroke(ctx, alpha(OUT, 0.8), 1.0)


def vents_box(ctx, x, y, w, h, n, horizontal_slots):
    """A recessed vent panel with n slots (slots run along the long side)."""
    inset_box(ctx, x, y, w, h, BODY_D, r=2)
    for i in range(n):
        if horizontal_slots:
            sx = x + 3 + i * (w - 6) / n
            rrect(ctx, sx + 1, y + 2, (w - 6) / n - 2, h - 4, 1)
        else:
            sy = y + 3 + i * (h - 6) / n
            rrect(ctx, x + 2, sy + 1, w - 4, (h - 6) / n - 2, 1)
        fill(ctx, hexc('#101214'))
