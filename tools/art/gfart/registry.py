"""Sprite registry: writes PNGs into the atlas folder and collects manifest entries."""
from __future__ import annotations

import json
import os
import re

from PIL import Image

FRAME_RE = re.compile(r'^(.*)_f(\d+)$')


class Registry:
    def __init__(self, out_dir: str, only: set[str] | None = None):
        self.out_dir = out_dir
        self.sprites: dict[str, dict] = {}
        self.groups: dict[str, list[str]] = {}
        self.only = only
        os.makedirs(out_dir, exist_ok=True)

    def add(self, name: str, img: Image.Image, group: str, anchor=(0.5, 0.5), **extra):
        assert re.match(r'^[a-z0-9_]+$', name), name
        img = img.convert('RGBA')
        path = os.path.join(self.out_dir, name + '.png')
        img.save(path, optimize=True)
        entry = {'w': img.size[0], 'h': img.size[1], 'anchor': [round(anchor[0], 4), round(anchor[1], 4)]}
        entry.update(extra)
        self.sprites[name] = entry
        self.groups.setdefault(group, []).append(name)
        m = FRAME_RE.match(name)
        if m:
            base = m.group(1)
            b = self.sprites.setdefault(base + '#anim', {'frames': 0})
            b['frames'] = max(b['frames'], int(m.group(2)) + 1)
            b.setdefault('w', img.size[0]); b.setdefault('h', img.size[1])
            b.setdefault('anchor', entry['anchor'])

    def manifest(self, extra: dict) -> dict:
        sprites = {}
        anims = {}
        for k, v in self.sprites.items():
            if k.endswith('#anim'):
                anims[k[:-5]] = v
            else:
                sprites[k] = v
        # base names of animated sets: if a static sprite exists with the same name, add 'frames' to it,
        # otherwise add an entry for the base name (not a real image) with "animOnly": true
        for base, v in anims.items():
            if base in sprites:
                sprites[base]['frames'] = v['frames']
            else:
                sprites[base] = {'w': v['w'], 'h': v['h'], 'anchor': v['anchor'], 'frames': v['frames'], 'animOnly': True}
        out = {'tileSize': 64, 'anchorConvention': 'SpriteKit anchorPoint (0..1, origin bottom-left) that maps to the '
               'centre of the entity footprint / tile', 'sprites': dict(sorted(sprites.items()))}
        out.update(extra)
        return out

    def write_manifest(self, path: str, extra: dict):
        with open(path, 'w') as f:
            json.dump(self.manifest(extra), f, indent=1, sort_keys=False)
            f.write('\n')
