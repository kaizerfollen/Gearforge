"""App icon (1024x1024, opaque) + asset catalog Contents.json files + warm-orange AccentColor."""
from __future__ import annotations

import json
import os

from PIL import Image

from .common import Canvas, alpha, circle, fill, fill_grad, gear_path, hexc, lin, poly, rad, rrect, stroke

OUT = hexc('#14171a')


def icon():
    S = 1024
    cv = Canvas(S, S)
    ctx = cv.ctx
    # background: deep teal-charcoal with a warm glow behind the gear
    ctx.rectangle(0, 0, S, S)
    fill_grad(ctx, lin(0, 0, S, S, [(0, hexc('#1f3a40')), (1, hexc('#10181c'))]))
    circle(ctx, 512, 450, 520)
    fill_grad(ctx, rad(512, 450, 0, 520, [(0, alpha(hexc('#ff9a3a'), 0.45)), (1, alpha(hexc('#ff9a3a'), 0))]))
    for k in range(0, S, 128):
        ctx.move_to(k, 0); ctx.line_to(k, S); ctx.move_to(0, k); ctx.line_to(S, k)
    stroke(ctx, alpha(hexc('#ffffff'), 0.04), 3)
    # conveyor belt along the bottom
    rrect(ctx, -20, 820, S + 40, 120, 20)
    fill(ctx, hexc('#24272b'), preserve=True)
    stroke(ctx, OUT, 10)
    for x in range(-40, S + 40, 96):
        poly(ctx, [(x, 850), (x + 34, 880), (x, 910), (x + 22, 910), (x + 56, 880), (x + 22, 850)])
        fill(ctx, hexc('#e8a523'))
    for y in (826, 924):
        ctx.rectangle(-20, y, S + 40, 12)
        fill(ctx, hexc('#c8862a'))
    # big gear
    cx, cy, R = 512, 440, 330
    gear_path(ctx, cx + 14, cy + 18, R, R * 0.8, 12, 0.13)
    fill(ctx, alpha(hexc('#000000'), 0.35))
    gear_path(ctx, cx, cy, R, R * 0.8, 12, 0.13)
    fill_grad(ctx, lin(cx - R, cy - R, cx + R, cy + R,
                       [(0, hexc('#ffc163')), (0.5, hexc('#f08a24')), (1, hexc('#9a4a10'))]), preserve=True)
    stroke(ctx, OUT, 14)
    circle(ctx, cx, cy, R * 0.62)
    fill_grad(ctx, lin(cx - R, cy - R, cx + R, cy + R, [(0, hexc('#203238')), (1, hexc('#0e1518'))]), preserve=True)
    stroke(ctx, OUT, 12)
    # factory silhouette inside the gear: saw-tooth roof + chimney
    base_y = cy + 110
    poly(ctx, [(cx - 150, base_y), (cx - 150, cy - 10), (cx - 90, cy - 60), (cx - 90, cy - 10), (cx - 30, cy - 60),
               (cx - 30, cy - 10), (cx + 30, cy - 60), (cx + 30, cy - 10), (cx + 70, cy - 10), (cx + 70, cy - 150),
               (cx + 120, cy - 150), (cx + 120, cy - 10), (cx + 150, cy - 10), (cx + 150, base_y)])
    fill_grad(ctx, lin(cx - 150, cy - 150, cx + 150, base_y, [(0, hexc('#e8eef2')), (1, hexc('#9aa6b0'))]), preserve=True)
    stroke(ctx, OUT, 10)
    for k in range(3):
        rrect(ctx, cx - 130 + k * 60, cy + 20, 36, 40, 6)
        fill(ctx, hexc('#ffb84a'))
    for (x, y, r) in ((cx + 95, cy - 185, 28), (cx + 128, cy - 225, 36), (cx + 175, cy - 255, 26)):
        circle(ctx, x, y, r)
        fill(ctx, alpha(hexc('#dfe6ea'), 0.85))
    img = cv.pil()
    bg = Image.new('RGB', img.size, (16, 24, 28))
    bg.paste(img, mask=img.getchannel('A'))
    return bg


def generate(xcassets):
    os.makedirs(os.path.join(xcassets, 'AppIcon.appiconset'), exist_ok=True)
    os.makedirs(os.path.join(xcassets, 'AccentColor.colorset'), exist_ok=True)
    icon().save(os.path.join(xcassets, 'AppIcon.appiconset', 'icon_1024.png'), optimize=True)
    info = {'author': 'xcode', 'version': 1}
    with open(os.path.join(xcassets, 'Contents.json'), 'w') as f:
        json.dump({'info': info}, f, indent=2)
    with open(os.path.join(xcassets, 'AppIcon.appiconset', 'Contents.json'), 'w') as f:
        json.dump({'images': [{'filename': 'icon_1024.png', 'idiom': 'universal', 'platform': 'ios',
                               'size': '1024x1024'}], 'info': info}, f, indent=2)
    with open(os.path.join(xcassets, 'AccentColor.colorset', 'Contents.json'), 'w') as f:
        json.dump({'colors': [{'color': {'color-space': 'srgb', 'components': {
            'alpha': '1.000', 'red': '0.941', 'green': '0.541', 'blue': '0.141'}}, 'idiom': 'universal'}],
            'info': info}, f, indent=2)
