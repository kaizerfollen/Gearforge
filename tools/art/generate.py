#!/usr/bin/env python3
"""Gearforge sprite generator — regenerates every sprite, the manifest and the app icon.

    pip install --break-system-packages pillow numpy pycairo     # once
    python3 tools/art/generate.py                                # everything (cleans the atlas first)
    python3 tools/art/generate.py --only belts,items             # a subset (manifest not rewritten)

Deterministic: same inputs -> identical PNGs (for the same Pillow/cairo versions).
Reads Core/Sources/FactoryCore/Resources/GameData.json for ids and sizes (phase == "mvp" only).
"""
from __future__ import annotations

import argparse
import glob
import json
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
ROOT = os.path.normpath(os.path.join(HERE, '..', '..'))
DATA = os.path.join(ROOT, 'Core', 'Sources', 'FactoryCore', 'Resources', 'GameData.json')
ATLAS = os.path.join(ROOT, 'App', 'Resources', 'Sprites.atlas')
MANIFEST = os.path.join(ROOT, 'App', 'Resources', 'sprite_manifest.json')
XCASSETS = os.path.join(ROOT, 'App', 'Resources', 'Assets.xcassets')

from gfart.registry import Registry  # noqa: E402
from gfart import (terrain, ores, natural, belts, inserters, pipes, poles, entities, character, items, ui,  # noqa: E402
                   appicon)

# order matters: items reuse entity sprites (miniatures), so entities come first
CATEGORIES = [
    ('terrain', terrain.generate),
    ('ores', ores.generate),
    ('natural', natural.generate),
    ('belts', belts.generate),
    ('inserters', inserters.generate),
    ('pipes', pipes.generate),
    ('poles', poles.generate),
    ('entities', entities.generate),
    ('character', character.generate),
    ('items', items.generate),
    ('ui', ui.generate),
]


def mvp(data):
    d = dict(data)
    for k in ('entities', 'items', 'fluids', 'recipes', 'technologies'):
        d[k] = [x for x in data.get(k, []) if x.get('phase', 'mvp') == 'mvp']
    return d


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--only', default=None,
                    help='comma separated categories: ' + ','.join(c for c, _ in CATEGORIES) + ',appicon')
    a = ap.parse_args()
    data = mvp(json.load(open(DATA)))
    only = set(a.only.split(',')) if a.only else None
    full = only is None
    if full:
        for f in glob.glob(os.path.join(ATLAS, '*.png')):
            os.remove(f)
    reg = Registry(ATLAS)
    t0 = time.time()
    for name, fn in CATEGORIES:
        if only and name not in only:
            continue
        t = time.time()
        fn(reg, data)
        print(f'{name:10s} {len(reg.groups.get(name, [])):5d} sprites  {time.time() - t:6.1f}s', flush=True)
    if full or 'appicon' in only:
        appicon.generate(XCASSETS)
        print('appicon written')
    if full:
        reg.write_manifest(MANIFEST)
        total = sum(os.path.getsize(f) for f in glob.glob(os.path.join(ATLAS, '*.png')))
        print(f'total {len(reg.sprites)} sprites, {total / 1e6:.2f} MB PNG, {time.time() - t0:.1f}s')


if __name__ == '__main__':
    main()
