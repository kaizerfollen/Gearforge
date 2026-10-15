#!/usr/bin/env python3
"""Diff two Factorio base data dumps (from load_data.py): recipes, technologies, start recipes, items, key entity stats.
Usage: diff_versions.py <old.json> <new.json>   (e.g. 1.1.110 vs 2.0.77; see docs/research/06_factorio_2_0_diff.md)"""
import json, sys
a = json.load(open(sys.argv[1])); b = json.load(open(sys.argv[2]))

def amounts(lst):
    out = {}
    for x in lst or []:
        if isinstance(x, list): out[x[0]] = x[1]
        else:
            amt = x.get('amount', f"{x.get('amount_min')}-{x.get('amount_max')}")
            if x.get('probability') not in (None, 1): amt = f"{amt}@{x['probability']}"
            out[x['name']] = amt
    return out

def recipe(r):
    if isinstance(r.get('normal'), dict): r = {**r, **r['normal']}
    res = amounts(r['results']) if r.get('results') is not None else {r.get('result'): r.get('result_count', 1)}
    return dict(time=r.get('energy_required', 0.5), ing=amounts(r.get('ingredients')), res=res,
                cat=r.get('category', 'crafting'),
                start=r.get('enabled', True) not in (False, 'false') and not r.get('hidden') and not r.get('parameter'))

def tech(t):
    if isinstance(t.get('normal'), dict): t = {**t, **t['normal']}
    u = t.get('unit') or {}
    eff = [e.get('recipe') or f"{e.get('type')}{'+' + str(e.get('modifier')) if e.get('modifier') is not None else ''}"
           for e in t.get('effects') or []]
    return dict(count=u.get('count'), formula=u.get('count_formula'), time=u.get('time'), packs=amounts(u.get('ingredients')),
                prereq=sorted(t.get('prerequisites') or []), trigger=t.get('research_trigger'), effects=eff,
                max_level=t.get('max_level'))

def section(title): print(f"\n## {title}")

RA = {k: recipe(v) for k, v in a['recipe'].items() if not k.startswith('parameter-')}
RB = {k: recipe(v) for k, v in b['recipe'].items() if not k.startswith('parameter-')}
section('Recipes'); print('removed:', sorted(set(RA) - set(RB))); print('added:', sorted(set(RB) - set(RA)))
for k in sorted(set(RA) & set(RB)):
    d = [f"{f}: {RA[k][f]} -> {RB[k][f]}" for f in ('time', 'ing', 'res', 'cat') if RA[k][f] != RB[k][f]]
    if d: print(f"  {k}: " + ' ; '.join(d))
section('Recipes available at game start')
sa = {k for k, v in RA.items() if v['start']}; sb = {k for k, v in RB.items() if v['start']}
print(f'old {len(sa)}, new {len(sb)}'); print('start only in old:', sorted(sa - sb)); print('start only in new:', sorted(sb - sa))

TA = {k: tech(v) for k, v in a['technology'].items()}; TB = {k: tech(v) for k, v in b['technology'].items()}
section('Technologies'); print('removed:', sorted(set(TA) - set(TB))); print('added:', sorted(set(TB) - set(TA)))
print('trigger technologies (new):')
for k, v in sorted(TB.items()):
    if v['trigger']: print(f"  {k}: {v['trigger']} -> unlocks {v['effects']}")
for k in sorted(set(TB) - set(TA)):
    v = TB[k]
    if not v['trigger']: print(f"  new {k}: {v['count']}x{v['time']}s {list(v['packs'])} prereq {v['prereq']} unlocks {v['effects']}")
for k in sorted(set(TA) & set(TB)):
    d = [f"{f}: {TA[k][f]} -> {TB[k][f]}" for f in ('count', 'formula', 'time', 'packs', 'prereq', 'effects', 'max_level')
         if TA[k][f] != TB[k][f]]
    if d: print(f"  {k}: " + ' ; '.join(d))

section('Items'); print('removed:', sorted(set(a['item']) - set(b['item'])))
print('added:', sorted(k for k in set(b['item']) - set(a['item']) if not k.startswith('parameter-')))
for k in sorted(set(a['item']) & set(b['item'])):
    if a['item'][k].get('stack_size') != b['item'][k].get('stack_size'):
        print(f"  stack {k}: {a['item'][k].get('stack_size')} -> {b['item'][k].get('stack_size')}")

section('Entity stats (selected fields)')
FIELDS = ['rotation_speed', 'extension_speed', 'energy_per_movement', 'energy_per_rotation', 'stack', 'filter_count',
          'speed', 'max_distance', 'mining_speed', 'resource_searching_radius', 'energy_usage', 'crafting_speed',
          'pumping_speed', 'maximum_wire_distance', 'supply_area_distance', 'distribution_effectivity', 'researching_speed',
          'rocket_parts_required', 'production', 'buffer_capacity', 'fluid_usage_per_tick', 'target_temperature',
          'energy_consumption', 'max_energy', 'charging_energy', 'mining_time', 'heat_capacity', 'stack_size', 'count']
for t in sorted(set(a) & set(b)):
    if t in ('recipe', 'technology', 'item'): continue
    for n in sorted(set(a[t]) & set(b[t])):
        x, y = a[t][n], b[t][n]
        if not isinstance(x, dict) or not isinstance(y, dict): continue
        d = []
        for f in FIELDS:
            vx, vy = x.get(f), y.get(f)
            if isinstance(vx, str) and isinstance(vy, str) and vx.lower() == vy.lower(): continue
            if vx != vy: d.append(f"{f}: {vx} -> {vy}")
        mx = x.get('minable') or {}; my = y.get('minable') or {}
        if (mx.get('results') or mx.get('result')) != (my.get('results') or my.get('result')) or mx.get('count') != my.get('count'):
            d.append(f"minable: {mx.get('results') or (mx.get('result'), mx.get('count'))} -> {my.get('results') or (my.get('result'), my.get('count'))}")
        if d: print(f"  [{t}] {n}: " + ' ; '.join(d))
