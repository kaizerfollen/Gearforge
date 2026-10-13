"""Sprite registry: writes PNGs into the atlas folder and collects manifest entries ({name: {w, h}})."""
from __future__ import annotations

import json
import os
import re

from PIL import Image


class Registry:
    def __init__(self, out_dir: str):
        self.out_dir = out_dir
        self.sprites: dict[str, dict] = {}
        self.groups: dict[str, list[str]] = {}
        self.images: dict[str, Image.Image] = {}
        os.makedirs(out_dir, exist_ok=True)

    def add(self, name: str, img: Image.Image, group: str, keep=False):
        assert re.match(r'^[a-z0-9_]+$', name), name
        assert name not in self.sprites, 'duplicate sprite ' + name
        img = img.convert('RGBA')
        img.save(os.path.join(self.out_dir, name + '.png'), optimize=True)
        self.sprites[name] = {'w': img.size[0], 'h': img.size[1]}
        self.groups.setdefault(group, []).append(name)
        if keep:
            self.images[name] = img
        return img

    def get(self, name: str) -> Image.Image:
        if name in self.images:
            return self.images[name]
        return Image.open(os.path.join(self.out_dir, name + '.png')).convert('RGBA')

    def write_manifest(self, path: str):
        rows = [f'  {json.dumps(k)}: {{"w": {v["w"]}, "h": {v["h"]}}}' for k, v in sorted(self.sprites.items())]
        with open(path, 'w') as f:
            f.write('{\n' + ',\n'.join(rows) + '\n}\n')
