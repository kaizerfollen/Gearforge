#!/usr/bin/env python3
"""Generate docs/research/01_items.md from raw.json (Factorio 1.1.110)."""
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
from gf_common import *

raw = load_raw(sys.argv[1])
OUT = sys.argv[2]
items = all_items(raw)
groups = raw['item-group']
subgroups = raw['item-subgroup']

# entity name -> prototype type
ent_type = {}
for t, protos in raw.items():
    for n, p in protos.items():
        if isinstance(p, dict) and p.get('minable') is not None or t in ('straight-rail', 'curved-rail'):
            ent_type.setdefault(n, t)

# recipes producing each item (normal mode)
produced_by = {}
for rn, r in raw['recipe'].items():
    rr = r.get('normal') or r
    res = ingr_list(rr.get('results')) if rr.get('results') else ([{'name': rr['result'], 'amount': rr.get('result_count', 1)}] if rr.get('result') else [])
    for x in res:
        produced_by.setdefault(x['name'], []).append(rn)

def sortkey(n, p):
    sg = subgroups.get(p.get('subgroup', 'other'), {'group': 'other', 'order': 'z'})
    g = groups.get(sg['group'], {'order': 'z'})
    return (g.get('order', 'z'), sg.get('order', 'z'), p.get('order', 'z'), n)

PTYPE_NOTE = {'tool': 'science pack (research ingredient)', 'ammo': 'ammo', 'gun': 'weapon', 'armor': 'armor',
              'capsule': 'capsule (usable)', 'module': 'module', 'repair-tool': 'repair tool',
              'item-with-entity-data': 'vehicle item', 'rail-planner': 'rail planner'}

rows_by_group = {}
excluded = []
for n, p in sorted(items.items(), key=lambda kv: sortkey(*kv)):
    ptype = p['type']
    if n in EDITOR_ONLY or ('hidden' in (p.get('flags') or []) and n != 'rocket-part'):
        excluded.append((n, ptype, p))
        continue
    sg = p.get('subgroup', 'other')
    grp = subgroups.get(sg, {}).get('group', 'other')
    notes = []
    if PTYPE_NOTE.get(ptype):
        notes.append(PTYPE_NOTE[ptype])
    if p.get('fuel_category'):
        notes.append(f"fuel category: {p['fuel_category']}")
    if p.get('fuel_acceleration_multiplier'):
        notes.append(f"vehicle accel x{num(p['fuel_acceleration_multiplier'])}")
    if p.get('fuel_top_speed_multiplier'):
        notes.append(f"vehicle top speed x{num(p['fuel_top_speed_multiplier'])}")
    if p.get('burnt_result'):
        notes.append(f"burnt result: {gid(p['burnt_result'])}")
    if p.get('rocket_launch_product'):
        rl = p['rocket_launch_product']
        notes.append(f"rocket launch product: {rl[1]} x {gid(rl[0])}")
    if p.get('place_as_tile'):
        t = p['place_as_tile']
        notes.append(f"places tile '{t['result']}' " + ('on WATER only (turns water into land)' if 'ground-tile' in t.get('condition', []) else 'on land only (blocked by water)'))
    if ptype == 'module':
        e = p['effect']
        notes.append('effects: ' + ', '.join(f"{k} {'+' if v['bonus'] >= 0 else ''}{num(v['bonus'] * 100)}%" for k, v in sorted(e.items())))
        if p.get('limitation'):
            notes.append('intermediate-only (see module limitation list in 05_mechanics)')
    if ptype == 'ammo' and p.get('magazine_size'):
        notes.append(f"magazine size {p['magazine_size']}")
    if ptype == 'armor':
        notes.append(f"inventory bonus +{p.get('inventory_size_bonus', 0)}; grid {p.get('equipment_grid', '-')}")
    if p.get('placed_as_equipment_result'):
        notes.append(f"equipment: {gid(p['placed_as_equipment_result'])}")
    if ptype == 'repair-tool':
        notes.append(f"speed {p.get('speed')}, durability {p.get('durability')}")
    if n == 'rocket-part':
        notes.append('hidden item: exists only inside the rocket silo (100 parts = 1 rocket)')
    if n == 'radar':
        notes.append('menu group is combat but radar is MVP (map reveal)')
    if not produced_by.get(n):
        notes.append('not craftable (raw / mined / launch product)')
    pr = p.get('place_result')
    ph = item_phase(raw, n)
    rows_by_group.setdefault(grp, []).append([
        gid(n), display(n), f"{grp}/{sg}", p.get('stack_size', '-'),
        num(mj(p['fuel_value'])) if p.get('fuel_value') else '-',
        gid(pr) if pr else ('tile:' + p['place_as_tile']['result'] if p.get('place_as_tile') else '-'),
        ph, '; '.join(notes), n,
    ])

# ---- Fluids
fluid_rows = []
for n, f in sorted(raw['fluid'].items(), key=lambda kv: kv[1].get('order', '')):
    if n in EDITOR_ONLY:
        continue
    c = f.get('base_color', {})
    hexc = '#%02x%02x%02x' % tuple(int(round(min(1, c.get(k, 0)) * 255)) for k in ('r', 'g', 'b'))
    fluid_rows.append([gid(n), display(n), num(f['default_temperature']), num(f.get('max_temperature', f['default_temperature'])),
                       num(energy_j(f['heat_capacity'].replace('KJ', 'kJ')) / 1000), num(mj(f['fuel_value'])) if f.get('fuel_value') else '-',
                       'yes' if f.get('auto_barrel', True) else 'no', hexc, phase_of(n), n])

GROUP_TITLES = [('intermediate-products', 'Intermediate products & raw resources'), ('logistics', 'Logistics'),
                ('production', 'Production'), ('combat', 'Combat (combat phase)'), ('other', 'Other')]

lines = []
lines.append('# 01 — Items & Fluids (Gearforge base set)\n')
lines.append('Source: Factorio 1.1.110 base-game prototype data (wube/factorio-data tag `1.1.110`, `base/prototypes/item.lua`, `fluid.lua`, `equipment.lua`, entity files), extracted programmatically by `docs/research/tools/gen_items.py`. Numbers are exact copies of the 1.1 prototype values (normal mode). Names: Gearforge ids are snake_case; branded names were replaced (see "Renames" below).\n')
lines.append('## Conventions\n')
lines.append('- **id** – Gearforge internal id (snake_case). **F1.1 name** – original prototype name, kept only for traceability (do not ship it).')
lines.append('- **group/subgroup** – crafting-menu tab / row. Group order (tabs): logistics, production, intermediate-products, combat. Within a table rows are already in in-game menu order (group order → subgroup order → item order).')
lines.append('- **stack** – stack size. **fuel MJ** – fuel value in megajoules (chemical fuel unless noted). **places** – entity id placed by the item (or `tile:<name>`).')
lines.append('- **phase** – `mvp` = in first release; `mvp*` = item needed in MVP as an ingredient although its main feature is later; `combat`, `trains`, `robots`, `nuclear`, `circuit` = later phases (see GDD §Phases).')
lines.append('- Science packs are called **cards** in Gearforge. Science-pack durability (1.0) is dropped: 1 card = 1 research unit ingredient.\n')
lines.append('## Renames (branded / lore names → Gearforge)\n')
rn_rows = [[k, v[0], v[1]] for k, v in RENAME.items() if '@' not in k]
lines.append(md_table(['F1.1 name', 'Gearforge id', 'Display name'], rn_rows))
lines.append('')

total = 0
for g, title in GROUP_TITLES:
    rows = rows_by_group.get(g, [])
    if not rows:
        continue
    total += len(rows)
    lines.append(f'## {title} ({len(rows)})\n')
    lines.append(md_table(['id', 'display name', 'group/subgroup', 'stack', 'fuel MJ', 'places', 'phase', 'notes', 'F1.1 name'], rows))
    lines.append('')

lines.append(f'## Fluids ({len(fluid_rows)})\n')
lines.append('Fluids are not items: they live in fluid boxes (pipes/tanks/machines) and are measured in units. Barrels (50 units per barrel) carry fluids as items. Temperature in °C; heat capacity in kJ per unit per °C (relevant for steam: energy = units × (T − 15) × 0.2 kJ). No base fluid has a fuel value in 1.1 (fluid fuel is only modded).\n')
lines.append(md_table(['id', 'display name', 'default °C', 'max °C', 'heat cap kJ/°C', 'fuel MJ', 'barrelable', 'colour', 'phase', 'F1.1 name'], fluid_rows))
lines.append('')
lines.append('Fluid temperature notes: steam from a **boiler** is 165 °C; steam from a **heat exchanger** is 500 °C. A steam engine accepts up to 165 °C steam, a steam turbine up to 500 °C (engines/turbines fed hotter steam do not gain power beyond their maximum temperature).\n')

lines.append(f'## Raw resources (map resources)\n')
res_rows = []
for n, r in sorted(raw['resource'].items()):
    m = r.get('minable', {})
    results = ingr_list(m.get('results')) if m.get('results') else [{'name': m.get('result'), 'amount': m.get('count', 1), 'type': 'item'}]
    res_rows.append([gid(n), display(n), r.get('category', 'basic-solid'), num(m.get('mining_time')),
                     ', '.join(f"{x.get('amount', x.get('amount_min'))} x {gid(x['name'])}" + (' (fluid)' if x.get('type') == 'fluid' else '') for x in results),
                     gid(m['required_fluid']) + f" x{num(m.get('fluid_amount'))} per 10 cycles" if m.get('required_fluid') else '-',
                     'yes' if r.get('infinite') else 'no',
                     (f"min {r.get('minimum')}, normal {r.get('normal')}, infinite_depletion {r.get('infinite_depletion_amount')}" if r.get('infinite') else '-'),
                     phase_of(n)])
lines.append(md_table(['resource id', 'name', 'resource category', 'mining time', 'yield per cycle', 'required fluid', 'infinite', 'infinite params', 'phase'], res_rows))
lines.append('\nNote: `fluid_amount` in the prototype is per 10 mining cycles in 1.1 convention — uranium ore needs **1 sulfuric acid per ore** in practice (fluid_amount 10 ⇒ 10 units per 10 ores). Crude oil: yield `amount` is 10 per cycle at 100% yield (300 000 = 100%); see 05_mechanics §Mining for pumpjack yield formula. Trees (wood: 4 per tree, mining time 0.55 for most tree types) and rocks (stone/coal) are minable world objects: see 05_mechanics §Resource generation.\n')

lines.append(f'## Excluded / not shipped ({len(excluded)})\n')
lines.append('Editor/debug/hidden items and blueprint-family tools. Blueprints, deconstruction & upgrade planners are re-specified as UI features in the GDD (not as items).\n')
lines.append(md_table(['F1.1 name', 'type', 'reason'], [[n, t, 'blueprint-family tool → UI feature' if t in ('blueprint', 'blueprint-book', 'deconstruction-item', 'upgrade-item', 'copy-paste-tool') else ('vehicle-mounted weapon (internal to vehicle; combat phase)' if t == 'gun' else ('hidden in 1.1 base (editor only); possible later QoL item' if 'loader' in n else 'editor/debug/hidden'))] for n, t, p in excluded]))
lines.append('')
lines.append(f'**Totals:** {total} shippable items (all phases) + {len(fluid_rows)} fluids; {len(excluded)} excluded.\n')

with open(OUT, 'w') as f:
    f.write('\n'.join(lines))
print('items', total, 'fluids', len(fluid_rows), 'excluded', len(excluded))
