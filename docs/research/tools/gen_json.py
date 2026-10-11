#!/usr/bin/env python3
"""Export a normalized, Gearforge-id JSON snapshot of the 1.1 base data (input for Phase 2 data-as-code).

Output: docs/research/data/gearforge_base_1_1.json
Energy is converted to plain numbers: *_kw (kilowatts), *_kj, *_mj. Graphics are stripped.
"""
import sys, os, json
sys.path.insert(0, os.path.dirname(__file__))
from gf_common import *

raw = load_raw(sys.argv[1])
OUT = sys.argv[2]
items = all_items(raw)
prod_limit = set(raw['module']['productivity-module']['limitation'])
char_cats = set(raw['character']['character']['crafting_categories'])
unlocked_by = {}
for tn, t in raw['technology'].items():
    for e in t.get('effects', []) or []:
        if e.get('type') == 'unlock-recipe':
            unlocked_by.setdefault(e['recipe'], []).append(tech_id(tn))

def conv_energy(d):
    out = {}
    for k, v in d.items():
        if isinstance(v, str):
            try:
                j = energy_j(v.replace('KW', 'kW').replace('KJ', 'kJ'))
                if v.strip().endswith('W'):
                    out[k + '_kw'] = j / 1000
                else:
                    out[k + '_kj'] = j / 1000
                continue
            except Exception:
                pass
        out[k] = v
    return out

def ref(name):
    return gid(name) if isinstance(name, str) else name

data = {'meta': {'source': 'Factorio 1.1.110 base (wube/factorio-data tag 1.1.110), normal difficulty',
                 'generator': 'docs/research/tools/gen_json.py', 'ids': 'Gearforge snake_case ids'},
        'items': {}, 'fluids': {}, 'recipes': {}, 'technologies': {}, 'entities': {}, 'resources': {}}

for n, p in items.items():
    if n in EDITOR_ONLY:
        continue
    d = {'id': gid(n), 'name': display(n), 'type': p['type'], 'subgroup': p.get('subgroup'), 'order': p.get('order'),
         'stack_size': p.get('stack_size'), 'phase': item_phase(raw, n),
         'group': raw['item-subgroup'].get(p.get('subgroup', 'other'), {}).get('group')}
    if p.get('fuel_value'):
        d['fuel_mj'] = mj(p['fuel_value']); d['fuel_category'] = p.get('fuel_category')
        for k in ('fuel_acceleration_multiplier', 'fuel_top_speed_multiplier'):
            if p.get(k):
                d[k] = p[k]
    if p.get('burnt_result'):
        d['burnt_result'] = gid(p['burnt_result'])
    if p.get('place_result'):
        d['place_result'] = gid(p['place_result'])
    if p.get('place_as_tile'):
        d['place_as_tile'] = p['place_as_tile']['result']
    if p.get('rocket_launch_product'):
        d['rocket_launch_product'] = {'item': gid(p['rocket_launch_product'][0]), 'count': p['rocket_launch_product'][1]}
    if p['type'] == 'module':
        d['module'] = {'category': p['category'], 'tier': p['tier'], 'effect': {k: v['bonus'] for k, v in p['effect'].items()},
                       'limitation': [gid(x) for x in p.get('limitation', [])] or None}
    if 'hidden' in (p.get('flags') or []):
        d['hidden'] = True
    data['items'][gid(n)] = d

for n, f in raw['fluid'].items():
    if n in EDITOR_ONLY:
        continue
    data['fluids'][gid(n)] = {'id': gid(n), 'name': display(n), 'default_temperature': f['default_temperature'],
                              'max_temperature': f.get('max_temperature', f['default_temperature']),
                              'heat_capacity_kj': energy_j(f['heat_capacity'].replace('KJ', 'kJ')) / 1000,
                              'base_color': f.get('base_color'), 'phase': phase_of(n)}

for n, r in raw['recipe'].items():
    if n in EDITOR_ONLY:
        continue
    rr = dict(r)
    if r.get('normal'):
        rr.update(r['normal'])
    ings = ingr_list(rr.get('ingredients'))
    res = ingr_list(rr['results']) if rr.get('results') else [{'type': 'item', 'name': rr['result'], 'amount': rr.get('result_count', 1)}]
    has_fluid = any(x['type'] == 'fluid' for x in ings + res)
    cat = rr.get('category', 'crafting')
    def norm(x):
        o = {'type': x['type'], 'id': gid(x['name'])}
        for k in ('amount', 'amount_min', 'amount_max', 'probability', 'temperature', 'minimum_temperature', 'maximum_temperature', 'catalyst_amount'):
            if x.get(k) is not None:
                o[k] = x[k]
        return o
    main = res[0]['name'] if len(res) == 1 else None
    data['recipes'][gid(n)] = {'id': gid(n), 'name': display(main) if main and gid(main) == gid(n) else display(n), 'phase': recipe_phase(raw, n), 'category': cat, 'time': rr.get('energy_required', 0.5),
                               'ingredients': [norm(x) for x in ings], 'results': [norm(x) for x in res],
                               'main_product': gid(rr['main_product']) if rr.get('main_product') else None,
                               'handcraftable': cat in char_cats and not has_fluid, 'allow_productivity': n in prod_limit,
                               'enabled_at_start': rr.get('enabled', True) is not False, 'unlocked_by': unlocked_by.get(n, []),
                               'hidden': bool(rr.get('hidden')), 'subgroup': rr.get('subgroup'), 'order': rr.get('order')}

ROCKET = rocket_closure(raw)
for n, t in raw['technology'].items():
    tt = dict(t)
    if t.get('normal'):
        tt.update(t['normal'])
    u = tt['unit']
    effs = []
    for e in tt.get('effects') or []:
        e2 = dict(e)
        if 'recipe' in e2:
            e2['recipe'] = gid(e2['recipe'])
        effs.append(e2)
    data['technologies'][tech_id(n)] = {
        'id': tech_id(n), 'name': tech_display(n), 'prerequisites': [tech_id(p) for p in tt.get('prerequisites') or []],
        'count': u.get('count'), 'count_formula': u.get('count_formula'), 'time': u['time'],
        'ingredients': [{'id': gid(i[0] if isinstance(i, list) else i['name']), 'amount': i[1] if isinstance(i, list) else i['amount']} for i in u['ingredients']],
        'effects': effs, 'max_level': tt.get('max_level'), 'upgrade': bool(tt.get('upgrade')), 'order': tt.get('order'), 'phase': tech_phase_of(raw, n, ROCKET)}

def rgb01(c):
    if isinstance(c, dict):
        v = [c.get('r', 0), c.get('g', 0), c.get('b', 0)]
    else:
        v = list(c[:3])
    if max(v) > 1:
        v = [x / 255 for x in v]
    return [round(x, 4) for x in v]

ENT_TYPES = ['transport-belt', 'underground-belt', 'splitter', 'inserter', 'container', 'logistic-container', 'pipe', 'pipe-to-ground',
             'pump', 'offshore-pump', 'storage-tank', 'electric-pole', 'boiler', 'generator', 'solar-panel', 'accumulator', 'reactor',
             'heat-pipe', 'mining-drill', 'furnace', 'assembling-machine', 'lab', 'beacon', 'rocket-silo', 'radar', 'lamp', 'roboport',
             'logistic-robot', 'construction-robot', 'arithmetic-combinator', 'decider-combinator', 'constant-combinator', 'power-switch',
             'programmable-speaker', 'locomotive', 'cargo-wagon', 'fluid-wagon', 'artillery-wagon', 'train-stop', 'rail-signal',
             'rail-chain-signal', 'straight-rail', 'curved-rail', 'car', 'spider-vehicle', 'ammo-turret', 'electric-turret', 'fluid-turret',
             'artillery-turret', 'wall', 'gate', 'land-mine', 'character']
KEEP_NESTED = {'energy_source', 'burner', 'heat_buffer', 'fluid_box', 'output_fluid_box', 'input_fluid_box', 'fluid_boxes',
               'module_specification', 'minable', 'attack_parameters'}
DROP = {'resistances', 'flags', 'selection_box', 'damaged_trigger_effect', 'dying_trigger_effect', 'open_door_trigger_effect',
        'close_door_trigger_effect', 'fire_glow', 'fire', 'localised_name', 'localised_description', 'icon_draw_specification'}

def clean(v, depth=0):
    if isinstance(v, dict):
        return {k: clean(x, depth + 1) for k, x in conv_energy(v).items() if k not in DROP and not (isinstance(x, dict) and not x)}
    if isinstance(v, list):
        return [clean(x, depth + 1) for x in v]
    return v

for t in ENT_TYPES:
    for n, p in raw.get(t, {}).items():
        if n in EDITOR_ONLY or n.startswith('crash-site') or 'logo' in n or (t != 'character' and not (p.get('minable') or t in ('straight-rail', 'curved-rail'))):
            continue
        d = {'id': gid(n), 'name': display(n), 'type': t, 'size': list(box_size(p.get('collision_box')) or (0, 0)), 'phase': phase_of(n, t)}
        if p.get('map_color'):
            d['map_color'] = rgb01(p['map_color'])
        for k, v in p.items():
            if k in DROP or k in ('name', 'type'):
                continue
            if isinstance(v, (int, float, bool)) or (isinstance(v, str) and k not in ('order', 'subgroup')):
                d.update(conv_energy({k: v}))
            elif k in KEEP_NESTED or k in ('collision_box', 'crafting_categories', 'resource_categories', 'allowed_effects', 'inputs',
                                           'pickup_position', 'insert_position', 'vector_to_place_result', 'mining_categories'):
                d[k] = clean(v)
        if isinstance(d.get('inputs'), list):
            d['inputs'] = [gid(x) for x in d['inputs']]
        if isinstance(d.get('minable'), dict) and d['minable'].get('result'):
            d['minable']['result'] = gid(d['minable']['result'])
        for k in ('next_upgrade', 'fixed_recipe'):
            if p.get(k):
                d[k] = gid(p[k])
        data['entities'][gid(n)] = d

for n, r in raw['resource'].items():
    data['resources'][gid(n)] = clean({k: r[k] for k in ('category', 'minable', 'infinite', 'minimum', 'normal', 'infinite_depletion_amount') if k in r})
    data['resources'][gid(n)]['name'] = display(n)
    data['resources'][gid(n)]['map_color'] = rgb01(r['map_color']) if r.get('map_color') else None

# ---- item groups / subgroups (display layout)
data['item_groups'] = {gid(n): {'id': gid(n), 'order': g.get('order')} for n, g in raw['item-group'].items()}
data['item_subgroups'] = {gid(n): {'id': gid(n), 'group': gid(g['group']), 'order': g.get('order')} for n, g in raw['item-subgroup'].items()}

# ---- tiles (subset used by Gearforge)
def rgb01(c):
    if isinstance(c, dict):
        v = [c.get('r', 0), c.get('g', 0), c.get('b', 0)]
    else:
        v = list(c[:3])
    if max(v) > 1:
        v = [x / 255 for x in v]
    return [round(x, 4) for x in v]
data['tiles'] = {}
for n, t in raw['tile'].items():
    data['tiles'][n] = {'name': n, 'walking_speed_modifier': t.get('walking_speed_modifier', 1),
                        'is_water': 'water-tile' in (t.get('collision_mask') or []),
                        'map_color': rgb01(t['map_color']) if t.get('map_color') else None,
                        'mined_item': gid(t['minable']['result']) if t.get('minable') else None}

# ---- natural entities (trees, rocks)
data['natural'] = {}
for n, p in raw.get('tree', {}).items():
    m = p.get('minable') or {}
    data['natural'][n] = {'type': 'tree', 'max_health': p.get('max_health'), 'mining_time': m.get('mining_time'),
                          'results': [{'id': gid(m['result']), 'amount': m.get('count', 1)}] if m.get('result') else []}
for n in ('rock-big', 'rock-huge', 'sand-rock-big'):
    p = raw['simple-entity'][n]
    m = p['minable']
    res = ingr_list(m.get('results')) if m.get('results') else [{'name': m['result'], 'amount': m.get('count', 1)}]
    data['natural'][n] = {'type': 'rock', 'max_health': p.get('max_health'), 'mining_time': m.get('mining_time'),
                          'size': list(box_size(p.get('collision_box'))),
                          'results': [{'id': gid(x['name']), 'amount': x.get('amount'), 'amount_min': x.get('amount_min'), 'amount_max': x.get('amount_max')} for x in res]}

os.makedirs(os.path.dirname(OUT), exist_ok=True)
with open(OUT, 'w') as f:
    json.dump(data, f, indent=1, sort_keys=True)
print({k: len(v) for k, v in data.items() if isinstance(v, dict)})
