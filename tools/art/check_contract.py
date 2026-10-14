#!/usr/bin/env python3
"""Checks App/Resources/sprite_manifest.json against the renderer naming contract (names + pixel sizes)."""
import json
import os
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..'))
m = json.load(open(os.path.join(ROOT, 'App', 'Resources', 'sprite_manifest.json')))
d = json.load(open(os.path.join(ROOT, 'Core', 'Sources', 'FactoryCore', 'Resources', 'GameData.json')))
ents = [e for e in d['entities'] if e.get('phase') == 'mvp']
items = [i for i in d['items'] if i.get('phase') == 'mvp']
D = 'nesw'
miss = []


def need(n, w=None, h=None):
    if n not in m:
        miss.append(n)
    elif w and (m[n]['w'], m[n]['h']) != (w, h):
        miss.append(f"{n} is {m[n]['w']}x{m[n]['h']}, expected {w}x{h}")


DIR_SQ = ['offshore_pump', 'boiler', 'steam_engine', 'pump', 'burner_mining_drill', 'electric_mining_drill',
          'pipe_to_ground', 'storage_tank', 'chemical_plant', 'oil_refinery']
ANIM = ['assembling_machine_1', 'assembling_machine_2', 'assembling_machine_3', 'chemical_plant', 'oil_refinery',
        'centrifuge', 'electric_furnace', 'stone_furnace', 'steel_furnace', 'burner_mining_drill',
        'electric_mining_drill', 'pumpjack', 'lab', 'beacon', 'radar', 'boiler', 'steam_engine']

for e in ents:
    i = e['id']
    w, h = e['size']
    if e['kind'] == 'character':
        continue
    need(f'e_{i}', w * 64, h * 64)
    if i in DIR_SQ:
        for k, dn in enumerate(D):
            ww, hh = (w, h) if k % 2 == 0 else (h, w)
            need(f'e_{i}_{dn}', ww * 64, hh * 64)
            if i in ANIM:
                for f in range(4):
                    need(f'e_{i}_{dn}_w{f}', ww * 64, hh * 64)
    elif i in ANIM:
        for f in range(4):
            need(f'e_{i}_w{f}', w * 64, h * 64)
    if e['kind'] == 'inserter':
        need(f'ins_{i}_base', 64, 64); need(f'ins_{i}_arm', 64, 16); need(f'ins_{i}_hand', 24, 24)
for b in ['transport_belt', 'fast_transport_belt', 'express_transport_belt']:
    for s in ['straight', 'curve_l', 'curve_r']:
        for dn in D:
            for f in range(8):
                need(f'belt_{b}_{s}_{dn}_f{f}', 64, 64)
for u in ['underground_belt', 'fast_underground_belt', 'express_underground_belt']:
    for io in ['in', 'out']:
        for dn in D:
            need(f'e_{u}_{io}_{dn}', 64, 64)
for s in ['splitter', 'fast_splitter', 'express_splitter']:
    for k, dn in enumerate(D):
        need(f'e_{s}_{dn}', *((128, 64) if k % 2 == 0 else (64, 128)))
for k in range(16):
    need(f'pipe_{k}', 64, 64)
need('wire', 8, 8)
for r in ['iron_ore', 'copper_ore', 'coal', 'stone', 'uranium_ore']:
    for s in range(8):
        need(f'ore_{r}_{s}', 64, 64)
need('ore_crude_oil', 64, 64)
for dn in D:
    need(f'char_{dn}_idle', 48, 64)
    for f in range(4):
        need(f'char_{dn}_f{f}', 48, 64)
for it in items:
    need(f"i_{it['id']}", 64, 64)
for f in d['fluids']:
    if f.get('phase', 'mvp') == 'mvp':
        need(f"f_{f['id']}", 64, 64)
for g in ('build remove rotate undo redo mine inventory map pause play research stats altmode close craft settings '
          'save load power alert check cross copy paste pipette joystick').split():
    need(f'ui_{g}', 64, 64)
for s in 'no_power low_power no_fuel output_full no_input no_recipe no_resources working'.split():
    need(f'status_{s}', 32, 32)
for t in d['tiles']:
    for v in range(4):
        need(f"tile_{t['id']}_v{v}", 64, 64)
atlas = os.path.join(ROOT, 'App', 'Resources', 'Sprites.atlas')
on_disk = {f[:-4] for d in (atlas, os.path.join(os.path.dirname(atlas), 'Terrain.atlas')) if os.path.isdir(d)
           for f in os.listdir(d) if f.endswith('.png')}
if on_disk != set(m):
    miss.append(f'manifest/atlas mismatch: {sorted(on_disk ^ set(m))[:10]}')
print(f'{len(m)} sprites in manifest; problems: {len(miss)}')
for x in miss:
    print('  ', x)
sys.exit(1 if miss else 0)
