#!/usr/bin/env python3
"""Phase 2: convert docs/research/data/gearforge_base_1_1.json into the engine's GameData.json.

Schema: Core/Sources/FactoryCore/Prototypes/Prototypes.swift (root GameDataFile, camelCase keys).
Usage: gen_gamedata.py [research_json] [out_json]
Units: energy J, power W, time s, belt speed 1/256 tile per tick, inserter turns/tick & tiles/tick.
Vector convention: an entity's direction = direction items move. North-facing inserter: pickup (0,1), drop (0,-1.2)
(1.1 raw y negated). Drill output vector unchanged (1.1 drills already output "forward"/north).
Fluid connection positions: 1.1 north orientation, centre-relative.
"""
import sys, os, re, json

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..', '..'))
SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, 'docs/research/data/gearforge_base_1_1.json')
OUT = sys.argv[2] if len(sys.argv) > 2 else os.path.join(ROOT, 'Core/Sources/FactoryCore/Resources/GameData.json')

D = json.load(open(SRC))

def snake(s):
    return s.replace('-', '_') if isinstance(s, str) else s

def phase(p):
    p = p or 'mvp'
    if '(needed for rocket' in p:
        return 'mvp'          # rocket prerequisites (railway, robotics) are researchable in MVP
    p = p.split(' ')[0]
    return {'mvp*': 'mvp', 'circuit': 'circuits'}.get(p, p)

def drop_none(d):
    return {k: v for k, v in d.items() if v is not None}

# ------------------------------------------------------------------------------------------- items
ITEM_KIND = {'item': 'item', 'tool': 'tool', 'module': 'module', 'ammo': 'ammo', 'armor': 'armor', 'gun': 'gun',
             'capsule': 'capsule', 'repair-tool': 'repairTool', 'item-with-entity-data': 'item', 'rail-planner': 'item'}
MODULE_CAT = {'speed': 'speed', 'productivity': 'productivity', 'effectivity': 'efficiency'}

items = []
for iid, it in D['items'].items():
    if it.get('hidden') and iid != 'rocket_part':
        continue              # vehicle-internal guns etc.
    e = {'id': iid, 'name': it['name'], 'kind': ITEM_KIND.get(it['type'], 'other'),
         'subgroup': snake(it.get('subgroup') or 'other'), 'order': it.get('order') or '', 'stackSize': it['stack_size'],
         'phase': phase(it['phase'])}
    if it.get('fuel_mj'):
        e['fuelValue'] = it['fuel_mj'] * 1e6
        e['fuelCategory'] = it.get('fuel_category')
    if it.get('burnt_result'):
        e['burntResult'] = it['burnt_result']
    if it.get('place_result'):
        e['placeResult'] = it['place_result']
    if it.get('place_as_tile'):
        e['placeAsTile'] = snake(it['place_as_tile'].replace('-left', ''))
    if it.get('module'):
        m = it['module']
        e['module'] = {k: m['effect'].get(k, 0.0) for k in ('speed', 'productivity', 'consumption', 'pollution')}
        e['moduleCategory'] = MODULE_CAT[m['category']]
        e['moduleTier'] = m['tier']
    if it.get('rocket_launch_product'):
        r = it['rocket_launch_product']
        e['rocketLaunchProducts'] = [{'id': r['item'], 'amount': r['count']}]
    items.append(e)
item_ids = {i['id'] for i in items}

# ------------------------------------------------------------------------------------------- fluids
fluids = []
for fid, f in D['fluids'].items():
    c = f.get('base_color') or {}
    fluids.append({'id': fid, 'name': f['name'], 'defaultTemperature': f['default_temperature'],
                   'maxTemperature': f['max_temperature'], 'heatCapacity': f['heat_capacity_kj'] * 1000,
                   'color': [round(c.get('r', 0), 4), round(c.get('g', 0), 4), round(c.get('b', 0), 4)], 'phase': phase(f['phase'])})

# ------------------------------------------------------------------------------------------- recipes
recipes = []
for rid, r in D['recipes'].items():
    def comp(x, product):
        amt = x.get('amount')
        if amt is None:
            amt = (x['amount_min'] + x['amount_max']) / 2
        c = {'type': x['type'], 'id': x['id'], 'amount': amt}
        if product and x.get('probability') is not None and x['probability'] != 1:
            c['probability'] = x['probability']
        return c
    recipes.append(drop_none({'id': rid, 'name': r['name'], 'category': r['category'], 'time': r['time'],
                              'ingredients': [comp(x, False) for x in r['ingredients']],
                              'results': [comp(x, True) for x in r['results']],
                              'mainProduct': r.get('main_product') or None, 'enabledAtStart': r['enabled_at_start'],
                              'handcraftable': r['handcraftable'], 'allowProductivity': r['allow_productivity'],
                              'hidden': r['hidden'], 'subgroup': snake(r.get('subgroup')), 'order': r.get('order'),
                              'phase': phase(r['phase'])}))

# ------------------------------------------------------------------------------------------- technologies
def norm_formula(f):
    if not f:
        return None
    f = f.replace(' ', '')
    f = re.sub(r'(\d)\(', r'\1*(', f)       # 100(L-6) -> 100*(L-6)
    f = re.sub(r'\)(\d|L|\()', r')*\1', f)
    f = re.sub(r'(\d)L', r'\1*L', f)
    assert re.fullmatch(r'[0-9L+\-*/^().]+', f), f
    return f

tech_ids = set(D['technologies'])
techs = []
for tid, t in D['technologies'].items():
    m = re.match(r'^(.*)_(\d+)$', tid)
    level = None
    if m:
        base, n = m.group(1), int(m.group(2))
        if t.get('upgrade') or f'{base}_{n + 1}' in tech_ids or f'{base}_{n - 1}' in tech_ids or t.get('max_level'):
            level = n
    max_level = None
    if t.get('max_level') == 'infinite':
        max_level = -1
    elif isinstance(t.get('max_level'), int):
        max_level = t['max_level']
    effects = []
    for e in t['effects']:
        if e['type'] == 'unlock-recipe':
            effects.append({'type': 'unlock-recipe', 'recipe': e['recipe']})
        else:
            # NOTE: ammo_category / turret_id qualifiers of combat modifiers are not representable in TechEffect yet.
            mod = e.get('modifier')
            if isinstance(mod, bool):
                mod = 1.0 if mod else 0.0      # boolean modifiers (e.g. character-logistic-requests) → 1/0
            elif not isinstance(mod, (int, float)):
                mod = None
            effects.append(drop_none({'type': e['type'], 'modifier': mod}))
    techs.append(drop_none({'id': tid, 'name': t['name'], 'prerequisites': t['prerequisites'], 'effects': effects,
                            'count': t.get('count'), 'countFormula': norm_formula(t.get('count_formula')),
                            'ingredients': t['ingredients'], 'time': t['time'], 'maxLevel': max_level, 'level': level,
                            'upgrade': t['upgrade'], 'order': t.get('order'), 'phase': phase(t['phase'])}))

# ------------------------------------------------------------------------------------------- entities
KIND = {'transport-belt': 'transportBelt', 'underground-belt': 'undergroundBelt', 'splitter': 'splitter', 'inserter': 'inserter',
        'container': 'container', 'logistic-container': 'container', 'mining-drill': 'miningDrill', 'furnace': 'furnace',
        'assembling-machine': 'assemblingMachine', 'rocket-silo': 'rocketSilo', 'lab': 'lab', 'boiler': 'boiler',
        'generator': 'generator', 'solar-panel': 'solarPanel', 'accumulator': 'accumulator', 'electric-pole': 'electricPole',
        'pipe': 'pipe', 'pipe-to-ground': 'pipeToGround', 'pump': 'pump', 'offshore-pump': 'offshorePump',
        'storage-tank': 'storageTank', 'beacon': 'beacon', 'radar': 'radar', 'lamp': 'lamp', 'wall': 'wall', 'gate': 'gate',
        'ammo-turret': 'turret', 'electric-turret': 'turret', 'fluid-turret': 'turret', 'artillery-turret': 'turret',
        'character': 'character'}
ROTATABLE_KINDS = {'transportBelt', 'undergroundBelt', 'splitter', 'inserter', 'miningDrill', 'pump', 'offshorePump', 'boiler',
                   'generator', 'pipeToGround', 'storageTank'}
ROTATABLE_OTHER = {'arithmetic_combinator', 'decider_combinator', 'rail_signal', 'rail_chain_signal', 'train_stop',
                   'straight_rail', 'curved_rail', 'locomotive', 'cargo_wagon', 'fluid_wagon', 'artillery_wagon', 'car', 'tank'}
ALL_EFFECTS = ['consumption', 'speed', 'productivity', 'pollution']

def W(d, key):
    """Read an energy value converted by gen_json (key_kw / key_kj) and return W or J."""
    if d is None:
        return None
    if d.get(key + '_kw') is not None:
        return d[key + '_kw'] * 1000
    if d.get(key + '_kj') is not None:
        return d[key + '_kj'] * 1000
    return None

def fluidbox(fb, default_type):
    conns = []
    for c in fb.get('pipe_connections', []):
        pos = c.get('position') or (c.get('positions') or [None])[0]   # per-direction arrays: take north entry
        conn = {'position': {'x': float(pos[0]), 'y': float(pos[1])}, 'type': c.get('type', 'input-output')}
        if c.get('max_underground_distance'):
            conn['undergroundMaxDistance'] = int(c['max_underground_distance'])
        conns.append(conn)
    return drop_none({'volume': fb.get('base_area', 1) * 100 * fb.get('height', 1),
                      'productionType': fb.get('production_type', default_type),
                      'filter': snake(fb.get('filter')), 'minimumTemperature': fb.get('minimum_temperature'),
                      'connections': conns})

def energy_source(e, ent):
    es = e.get('energy_source') or e.get('burner')
    if not es:
        return None
    t = es.get('type') or ('burner' if e.get('burner') else None)
    out = {'type': t, 'usagePriority': es.get('usage_priority'), 'emissionsPerMinute': es.get('emissions_per_minute')}
    if t == 'electric':
        dr = W(es, 'drain')
        if dr is None and ent['type'] in ('assembling-machine', 'furnace', 'rocket-silo') and e.get('energy_usage_kw'):
            dr = e['energy_usage_kw'] * 1000 / 30           # engine default drain for crafting machines
        out['drain'] = dr
        out['bufferCapacity'] = W(es, 'buffer_capacity')
        out['inputFlowLimit'] = W(es, 'input_flow_limit')
        out['outputFlowLimit'] = W(es, 'output_flow_limit')
    elif t == 'burner':
        out['fuelCategories'] = [es.get('fuel_category', 'chemical')]
        out['fuelSlots'] = es.get('fuel_inventory_size', 1)
        out['effectivity'] = es.get('effectivity', 1)
    elif t == 'heat':
        out['bufferCapacity'] = None
    return drop_none(out)

def mined(e):
    m = e.get('minable') or {}
    if m.get('results'):
        return [{'id': snake(x['name']), 'amount': x.get('amount', 1)} for x in m['results']]
    if m.get('result'):
        return [{'id': snake(m['result']), 'amount': m.get('count', 1)}]
    return []

entities = []
for eid, e in D['entities'].items():
    t = e['type']
    kind = KIND.get(t, 'other')
    ent = {'id': eid, 'name': e['name'], 'kind': kind, 'size': e['size'] if e['size'] != [0, 0] else [1, 1],
           'maxHealth': float(e.get('max_health', 0)), 'mineTime': float((e.get('minable') or {}).get('mining_time', 0)),
           'minedResults': mined(e), 'phase': phase(e['phase']), 'nextUpgrade': e.get('next_upgrade'),
           'fastReplaceGroup': snake(e.get('fast_replaceable_group'))}
    if eid == 'offshore_pump':
        ent['size'] = [1, 1]          # logical footprint: one land tile; the tile in front (north) must be water
    es = energy_source(e, {'type': t})
    if es:
        ent['energySource'] = es
    eu = W(e, 'energy_usage') or W(e, 'energy_usage_per_tick') or W(e, 'active_energy_usage') if t != 'rocket-silo' else W(e, 'energy_usage')
    if eu is not None and t not in ('boiler', 'generator'):
        ent['energyUsage'] = eu
    ms = (e.get('module_specification') or {}).get('module_slots')
    if ms:
        ent['moduleSlots'] = ms
        ae = e.get('allowed_effects')
        ent['allowedEffects'] = ae if isinstance(ae, list) else ALL_EFFECTS
    elif t in ('lab',) and ms:
        pass
    # ---- kind-specific blocks
    if t in ('assembling-machine', 'furnace', 'rocket-silo'):
        fbs = e.get('fluid_boxes')
        off = None
        boxes = []
        if isinstance(fbs, dict):
            off = bool(fbs.get('off_when_no_fluid_recipe')) or None
            boxes = [v for k, v in sorted(fbs.items()) if isinstance(v, dict)]
        elif isinstance(fbs, list):
            boxes = [v for v in fbs if isinstance(v, dict)]
        ent['crafting'] = drop_none({'speed': e['crafting_speed'], 'categories': e['crafting_categories'],
                                     'fixedRecipe': e.get('fixed_recipe'), 'fluidBoxesOffWhenNoFluidRecipe': off})
        if boxes:
            ent['fluidBoxes'] = [fluidbox(b, 'input') for b in boxes]
    if t in ('transport-belt', 'underground-belt', 'splitter'):
        ent['belt'] = drop_none({'speed': int(round(e['speed'] * 256)), 'undergroundMaxDistance': e.get('max_distance') if t == 'underground-belt' else None})
    if t == 'inserter':
        pu, dr = e['pickup_position'], e['insert_position']
        ent['inserter'] = {'rotationSpeed': e['rotation_speed'], 'extensionSpeed': e['extension_speed'],
                           'pickup': {'x': float(pu[0]), 'y': float(-pu[1])}, 'drop': {'x': float(dr[0]), 'y': float(-dr[1])},
                           'isStack': bool(e.get('stack')), 'filterSlots': e.get('filter_count', 0),
                           'energyPerMovement': e['energy_per_movement_kj'] * 1000, 'energyPerRotation': e['energy_per_rotation_kj'] * 1000}
    if t == 'mining-drill':
        v = e['vector_to_place_result']
        ent['drill'] = {'miningSpeed': e['mining_speed'], 'areaSize': int(round(e['resource_searching_radius'] * 2)),
                        'resourceCategories': e['resource_categories'], 'outputVector': {'x': float(v[0]), 'y': float(v[1])}}
        fb = []
        if e.get('input_fluid_box'):
            fb.append(fluidbox(e['input_fluid_box'], 'input-output'))
        if e.get('output_fluid_box'):
            fb.append(fluidbox(e['output_fluid_box'], 'output'))
        if fb:
            ent['fluidBoxes'] = fb
    if t in ('container', 'logistic-container'):
        ent['container'] = {'slots': e['inventory_size']}
    if t == 'lab':
        ent['lab'] = {'speed': e['researching_speed'], 'inputs': [d for d in (snake(x) for x in e['inputs'])]}
    if t == 'electric-pole':
        ent['pole'] = {'wireReach': e['maximum_wire_distance'], 'supplyAreaDistance': e['supply_area_distance'], 'maxConnections': 5}
    if t == 'generator':
        hc = D['fluids']['steam']['heat_capacity_kj'] * 1000
        maxp = e['fluid_usage_per_tick'] * 60 * (e['maximum_temperature'] - 15) * hc * e['effectivity']
        ent['generator'] = {'fluidUsagePerTick': e['fluid_usage_per_tick'], 'maximumTemperature': e['maximum_temperature'],
                            'effectivity': e['effectivity'], 'maxPowerOutput': round(maxp, 6)}
        ent['fluidBoxes'] = [fluidbox(e['fluid_box'], 'input-output')]
    if t == 'boiler':
        ent['boiler'] = {'targetTemperature': e['target_temperature'], 'energyConsumption': W(e, 'energy_consumption')}
        ent['fluidBoxes'] = [fluidbox(e['fluid_box'], 'input-output'), fluidbox(e['output_fluid_box'], 'output')]
    if t == 'solar-panel':
        ent['solar'] = {'production': W(e, 'production')}
    if t == 'accumulator':
        a = e['energy_source']
        ent['accumulator'] = {'capacity': W(a, 'buffer_capacity'), 'inputFlowLimit': W(a, 'input_flow_limit'), 'outputFlowLimit': W(a, 'output_flow_limit')}
    if t == 'pump':
        ent['pump'] = {'pumpingSpeed': e['pumping_speed']}
        ent['fluidBoxes'] = [fluidbox(e['fluid_box'], 'none')]
    if t == 'offshore-pump':
        ent['offshorePump'] = {'pumpingSpeed': e['pumping_speed'], 'fluid': snake(e['fluid'])}
        ent['fluidBoxes'] = [fluidbox(e['fluid_box'], 'output')]
    if t in ('pipe', 'pipe-to-ground', 'storage-tank'):
        ent['fluidBoxes'] = [fluidbox(e['fluid_box'], 'none')]
    if t == 'beacon':
        ent['beacon'] = {'distributionEffectivity': e['distribution_effectivity'], 'supplyAreaDistance': int(e['supply_area_distance'])}
    if t == 'radar':
        ent['radar'] = {'nearbyChunkRadius': e['max_distance_of_nearby_sector_revealed'], 'scanChunkRadius': e['max_distance_of_sector_revealed'],
                        'energyPerSector': W(e, 'energy_per_sector')}
    if t == 'rocket-silo':
        ent['rocketSilo'] = {'rocketPartsRequired': e['rocket_parts_required'], 'activeEnergyUsage': W(e, 'active_energy_usage')}
    # ---- rotatable / placement
    rot = kind in ROTATABLE_KINDS or eid in ROTATABLE_OTHER
    if kind == 'assemblingMachine' and ent.get('fluidBoxes'):
        rot = True
    ent['rotatable'] = rot
    if kind == 'offshorePump':
        ent['placement'] = 'shoreline'
    elif kind == 'miningDrill':
        ent['placement'] = 'resource'
    entities.append(drop_none(ent))

# natural entities (trees & rocks), phase mvp
NAT = D['natural']
def tree(id_, name, src):
    n = NAT[src]
    return {'id': id_, 'name': name, 'kind': 'tree', 'size': [1, 1], 'maxHealth': float(n['max_health']), 'mineTime': n['mining_time'],
            'minedResults': n['results'], 'phase': 'mvp', 'rotatable': False}
entities += [tree('tree_01', 'Tree', 'tree-01'), tree('tree_02', 'Tree', 'tree-02'), tree('tree_03', 'Tree', 'tree-03'),
             tree('dead_tree', 'Dead tree', 'dead-grey-trunk')]
rb, rh = NAT['rock-big'], NAT['rock-huge']
entities.append({'id': 'big_rock', 'name': 'Big rock', 'kind': 'rock', 'size': rb['size'], 'maxHealth': float(rb['max_health']),
                 'mineTime': rb['mining_time'], 'minedResults': [{'id': 'stone', 'amount': 20}], 'phase': 'mvp', 'rotatable': False})
# 1.1 huge rock yields a random 24–50 of each; Gearforge uses the fixed minimum (24 stone + 24 coal).
entities.append({'id': 'huge_rock', 'name': 'Huge rock', 'kind': 'rock', 'size': rh['size'], 'maxHealth': float(rh['max_health']),
                 'mineTime': rh['mining_time'], 'minedResults': [{'id': 'stone', 'amount': 24}, {'id': 'coal', 'amount': 24}],
                 'phase': 'mvp', 'rotatable': False})

# ------------------------------------------------------------------------------------------- tiles
TILE_SRC = [('grass_1', 'Grass', 'grass-1'), ('grass_2', 'Dry grass', 'grass-2'), ('dirt', 'Dirt', 'dirt-4'),
            ('sand', 'Sand', 'sand-1'), ('red_desert', 'Red desert', 'red-desert-0'), ('water', 'Water', 'water'),
            ('deep_water', 'Deep water', 'deepwater'), ('stone_path', 'Stone path', 'stone-path'), ('concrete', 'Concrete', 'concrete'),
            ('hazard_concrete', 'Hazard concrete', 'hazard-concrete-left'), ('refined_concrete', 'Refined concrete', 'refined-concrete'),
            ('refined_hazard_concrete', 'Refined hazard concrete', 'refined-hazard-concrete-left'), ('landfill', 'Landfill', 'landfill')]
PLAYER_TILES = {'stone_path', 'concrete', 'hazard_concrete', 'refined_concrete', 'refined_hazard_concrete', 'landfill'}
tiles = []
for tid, name, src in TILE_SRC:
    t = D['tiles'][src]
    tiles.append(drop_none({'id': tid, 'name': name, 'walkingSpeedModifier': float(t['walking_speed_modifier']),
                            'isWater': t['is_water'], 'buildable': not t['is_water'], 'mapColor': t['map_color'],
                            'minedItem': t['mined_item'], 'playerPlaced': tid in PLAYER_TILES}))

# ------------------------------------------------------------------------------------------- resources
resources = []
for rid, r in D['resources'].items():
    m = r['minable']
    if m.get('results'):
        x = m['results'][0]
        res, is_fluid, amt = snake(x['name']), x.get('type') == 'fluid', x.get('amount') or x.get('amount_max')
    else:
        res, is_fluid, amt = snake(m['result']), False, m.get('count', 1)
    e = {'id': rid, 'name': r['name'], 'category': r.get('category', 'basic-solid'), 'miningTime': m['mining_time'],
         'result': res, 'resultIsFluid': is_fluid, 'resultAmount': amt, 'infinite': bool(r.get('infinite')),
         'mapColor': r['map_color']}
    if r.get('infinite'):
        e.update({'minimum': r['minimum'], 'normal': r['normal'], 'infiniteDepletionAmount': r.get('infinite_depletion_amount', 10)})
    if m.get('required_fluid'):
        e['requiredFluid'] = snake(m['required_fluid'])
        e['fluidAmount'] = m['fluid_amount'] / 10.0      # 1.1 fluid_amount is per 10 mined items → 1 acid per ore
    resources.append(e)

# ------------------------------------------------------------------------------------------- item groups
GROUP_NAMES = {'logistics': 'Logistics', 'production': 'Production', 'intermediate_products': 'Intermediate products', 'combat': 'Combat'}
used_sub = {i['subgroup'] for i in items} | {r['subgroup'] for r in recipes if r.get('subgroup')}
item_groups = []
for gidn, gname in GROUP_NAMES.items():
    subs = sorted((s for s, sg in D['item_subgroups'].items() if sg['group'] == gidn and s in used_sub),
                  key=lambda s: (D['item_subgroups'][s]['order'] or '', s))
    item_groups.append({'id': gidn, 'name': gname, 'order': D['item_groups'][gidn]['order'], 'subgroups': subs})
grouped = {s for g in item_groups for s in g['subgroups']}
stray = sorted({i['subgroup'] for i in items} - grouped)
assert not stray, f'items in subgroups outside the 4 crafting groups: {stray}'

# ------------------------------------------------------------------------------------------- write
def sort_by_id(lst):
    return sorted(lst, key=lambda x: x['id'])

out = {'version': 1, 'items': sort_by_id(items), 'fluids': sort_by_id(fluids), 'recipes': sort_by_id(recipes),
       'technologies': sort_by_id(techs), 'entities': sort_by_id(entities), 'tiles': tiles, 'resources': sort_by_id(resources),
       'itemGroups': item_groups}

# reference sanity (mirrors PrototypeDB validation)
ent_ids = {e['id'] for e in entities}; tile_ids = {t['id'] for t in tiles}; rec_ids = {r['id'] for r in recipes}
fl_ids = {f['id'] for f in fluids}
for r in recipes:
    for c in r['ingredients'] + r['results']:
        assert c['id'] in (fl_ids if c['type'] == 'fluid' else item_ids), (r['id'], c)
for i in items:
    assert i.get('placeResult') is None or i['placeResult'] in ent_ids, i
    assert i.get('placeAsTile') is None or i['placeAsTile'] in tile_ids, i
    assert i.get('burntResult') is None or i['burntResult'] in item_ids, i
for t in techs:
    for p in t['prerequisites']:
        assert p in tech_ids, (t['id'], p)
    for e in t['effects']:
        assert e['type'] != 'unlock-recipe' or e['recipe'] in rec_ids, (t['id'], e)
    for g in t['ingredients']:
        assert g['id'] in item_ids, (t['id'], g)
for e in entities:
    for m in e['minedResults']:
        assert m['id'] in item_ids, (e['id'], m)
    assert e.get('nextUpgrade') is None or e['nextUpgrade'] in ent_ids, e['id']
    for i in (e.get('lab') or {}).get('inputs', []):
        assert i in item_ids, (e['id'], i)

os.makedirs(os.path.dirname(OUT), exist_ok=True)
with open(OUT, 'w') as f:
    json.dump(out, f, indent=2, sort_keys=True)
    f.write('\n')
print({k: len(v) for k, v in out.items() if isinstance(v, list)})
