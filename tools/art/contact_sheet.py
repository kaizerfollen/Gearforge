#!/usr/bin/env python3
"""Contact sheets for reviewing generated sprites.

Examples
  python3 tools/art/contact_sheet.py 'i_*' --out docs/art/contact_items.png --cell 72
  python3 tools/art/contact_sheet.py 'e_*' --scale 0.5 --bg grass
  python3 tools/art/contact_sheet.py --mosaic grass_1,dirt --out /tmp/mosaic.png      # seam check
  python3 tools/art/contact_sheet.py --belt transport_belt --out /tmp/belts.png                 # belt layout check
"""
from __future__ import annotations

import argparse
import fnmatch
import os
import random

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ATLAS = os.path.normpath(os.path.join(HERE, '..', '..', 'App', 'Resources', 'Sprites.atlas'))


def load(name):
    return Image.open(os.path.join(ATLAS, name + '.png')).convert('RGBA')


def background(w, h, bg):
    if bg == 'checker':
        img = Image.new('RGBA', (w, h), (90, 90, 96, 255))
        d = ImageDraw.Draw(img)
        for y in range(0, h, 8):
            for x in range(0, w, 8):
                if (x // 8 + y // 8) % 2:
                    d.rectangle([x, y, x + 7, y + 7], fill=(110, 110, 118, 255))
        return img
    if bg in ('grass', 'dirt', 'concrete', 'sand'):
        tid = {'grass': 'grass_1', 'dirt': 'dirt', 'concrete': 'concrete', 'sand': 'sand'}[bg]
        img = Image.new('RGBA', (w, h))
        r = random.Random(1)
        for y in range(0, h, 64):
            for x in range(0, w, 64):
                img.paste(load(f'tile_{tid}_v{r.randint(0, 3)}'), (x, y))
        return img
    c = {'dark': (28, 30, 34, 255), 'ui': (44, 48, 54, 255), 'light': (200, 200, 200, 255)}.get(bg, (60, 60, 66, 255))
    return Image.new('RGBA', (w, h), c)


def sheet(names, out, scale=1.0, bg='checker', cols=None, cell=None, label=True):
    imgs = [load(n) for n in names]
    if scale != 1.0:
        imgs = [i.resize((max(1, int(i.size[0] * scale)), max(1, int(i.size[1] * scale))), Image.LANCZOS) for i in imgs]
    cw = cell or max(i.size[0] for i in imgs)
    ch = cell or max(i.size[1] for i in imgs)
    cw = max(cw, max(i.size[0] for i in imgs))
    ch = max(ch, max(i.size[1] for i in imgs))
    lab = 11 if label else 0
    cols = cols or max(1, min(len(imgs), 1800 // (cw + 4)))
    rows = (len(imgs) + cols - 1) // cols
    W, H = cols * (cw + 4) + 4, rows * (ch + 4 + lab) + 4
    img = background(W, H, bg)
    d = ImageDraw.Draw(img)
    try:
        font = ImageFont.truetype('DejaVuSans.ttf', 9)
    except Exception:
        font = ImageFont.load_default()
    for k, (n, im) in enumerate(zip(names, imgs)):
        x = 4 + (k % cols) * (cw + 4)
        y = 4 + (k // cols) * (ch + 4 + lab)
        img.alpha_composite(im, (x + (cw - im.size[0]) // 2, y + (ch - im.size[1]) // 2))
        if label:
            t = n
            d.text((x, y + ch + 1), t[: max(4, cw // 5)], fill=(235, 235, 235, 255), font=font)
    img.save(out)
    print(out, img.size, len(names))


def mosaic(tids, out, n=8):
    r = random.Random(7)
    W = n * 64
    img = Image.new('RGBA', (W * len(tids), W))
    for k, t in enumerate(tids):
        for y in range(n):
            for x in range(n):
                img.paste(load(f'tile_{t}_v{r.randint(0, 3)}'), (k * W + x * 64, y * 64))
    img.save(out)
    print(out, img.size)


def belt_layout(bid, out, frame=0, scale=1.0):
    """A loop with both curve kinds plus an underground pair and a splitter, as the renderer would place them."""
    g = [
        (1, 4, 'curve_r', 'n'), (1, 3, 'straight', 'n'), (1, 2, 'straight', 'n'), (1, 1, 'curve_r', 'e'),
        (2, 1, 'straight', 'e'), (3, 1, 'straight', 'e'), (4, 1, 'curve_r', 's'), (4, 2, 'straight', 's'),
        (4, 3, 'straight', 's'), (4, 4, 'curve_r', 'w'), (3, 4, 'straight', 'w'), (2, 4, 'straight', 'w'),
        (6, 4, 'straight', 'n'), (6, 3, 'curve_l', 'w'), (5, 3, 'straight', 'w'),
        (6, 1, 'straight', 'n'), (6, 2, 'straight', 'n'), (7, 1, 'curve_l', 's'), (7, 0, 'curve_r', 'e'),
    ]
    img = background(10 * 64, 7 * 64, 'grass')
    for (x, y, shape, d) in g:
        img.alpha_composite(load(f'belt_{bid}_{shape}_{d}_f{frame}'), (x * 64, y * 64))
    ug = {'transport_belt': 'underground_belt', 'fast_transport_belt': 'fast_underground_belt',
          'express_transport_belt': 'express_underground_belt'}[bid]
    sp = ug.replace('underground_belt', 'splitter')
    img.alpha_composite(load(f'e_{ug}_in_e'), (1 * 64, 6 * 64))
    img.alpha_composite(load(f'e_{ug}_out_e'), (4 * 64, 6 * 64))
    img.alpha_composite(load(f'belt_{bid}_straight_e_f{frame}'), (0, 6 * 64))
    img.alpha_composite(load(f'e_{sp}_n'), (8 * 64, 4 * 64))
    img.alpha_composite(load(f'e_{sp}_e'), (8 * 64, 1 * 64))
    if scale != 1.0:
        img = img.resize((int(img.size[0] * scale), int(img.size[1] * scale)), Image.LANCZOS)
    img.save(out)
    print(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('pattern', nargs='?', default=None)
    ap.add_argument('--out', default='/tmp/contact.png')
    ap.add_argument('--scale', type=float, default=1.0)
    ap.add_argument('--bg', default='checker')
    ap.add_argument('--cols', type=int, default=None)
    ap.add_argument('--cell', type=int, default=None)
    ap.add_argument('--nolabel', action='store_true')
    ap.add_argument('--mosaic', default=None)
    ap.add_argument('--belt', default=None)
    ap.add_argument('--frame', type=int, default=0)
    ap.add_argument('--exclude', default=None, help='regex; names matching it are skipped')
    a = ap.parse_args()
    if a.mosaic:
        mosaic(a.mosaic.split(','), a.out)
        return
    if a.belt:
        belt_layout(a.belt, a.out, a.frame, a.scale)
        return
    pats = a.pattern.split(',')
    names = sorted(f[:-4] for f in os.listdir(ATLAS) if f.endswith('.png') and any(fnmatch.fnmatch(f[:-4], p) for p in pats))
    if a.exclude:
        import re
        names = [n for n in names if not re.search(a.exclude, n)]
    if not names:
        print('no match')
        return
    sheet(names, a.out, a.scale, a.bg, a.cols, a.cell, not a.nolabel)


if __name__ == '__main__':
    main()
