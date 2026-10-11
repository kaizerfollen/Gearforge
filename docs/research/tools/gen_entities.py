#!/usr/bin/env python3
"""Generate docs/research/03_entities.md from raw.json (Factorio 1.1.110)."""
import sys, os, math
sys.path.insert(0, os.path.dirname(__file__))
from gf_common import *

raw = load_raw(sys.argv[1])
OUT = sys.argv[2]
items = all_items(raw)
placeable = {p.get('place_result') for p in items.values() if p.get('place_result')}
placeable |= {'straight-rail', 'curved-rail'}

def P(t, n):
    return raw[t][n]

def size(p):
    s = box_size(p.get('collision_box'))
    if not s or s == (0, 0):
        return '-'
    return f'{s[0]}x{s[1]}'

def es(p):
    e = p.get('energy_source') or {}
    return e.get('type', 'none')

def drain_kw(p, ptype):
    e = p.get('energy_source') or {}
    if e.get('type') != 'electric':
        return None
    if e.get('drain'):
        return kw(e['drain'])
    if ptype in ('assembling-machine', 'furnace', 'rocket-silo') and p.get('energy_usage'):
        return kw(p['energy_usage']) / 30.0  # engine default for crafting machines
    return 0.0

def emissions(p):
    e = p.get('energy_source') or {}
    return e.get('emissions_per_minute')

def mining_time(p):
    return (p.get('minable') or {}).get('mining_time')

def modules(p):
    return (p.get('module_specification') or {}).get('module_slots', 0)

def fluidbox_volume(fb):
    if not fb:
        return None
    return fb.get('base_area', 1) * 100 * fb.get('height', 1)

def base_cols(n, p, ptype):
    return [gid(n), display(n), size(p), p.get('max_health', '-'), num(mining_time(p))]

BASE_H = ['id', 'name', 'size', 'health', 'mine s']

sections = []  # (title, intro, headers, rows)
covered = set()

def add(title, intro, headers, rows, names):
    sections.append((title, intro, headers, rows))
    covered.update(names)

# ---------------------------------------------------------------- Belts
rows, names = [], []
for t in ('transport-belt', 'underground-belt', 'splitter'):
    for n, p in sorted(raw[t].items(), key=lambda kv: kv[1]['speed']):
        if n not in placeable:
            continue
        sp = p['speed']
        rows.append(base_cols(n, p, t) + [t, num(sp, 6), num(sp * 480), num(sp * 60, 4), p.get('max_distance', '-') if t == 'underground-belt' else '-',
                                          gid(p['next_upgrade']) if p.get('next_upgrade') else '-', phase_of(n, t)])
        names.append(n)
add('Transport belts, undergrounds, splitters',
    'Belt throughput = speed (tiles/tick) × 480 items/s for a full belt (2 lanes × 4 items per tile per lane × 60 ticks). Items per lane per tile = 4 (item spacing 0.25 tile = 64/256). Underground `max_distance` = tile offset between entrance and exit, so a yellow pair can bridge 4 tiles of gap (5 − 1). Splitter is 2×1, same speed as its belt tier. No energy.',
    BASE_H + ['type', 'speed tiles/tick', 'items/s (both lanes)', 'item travel tiles/s', 'UG max distance', 'upgrades to', 'phase'], rows, names)

# ---------------------------------------------------------------- Inserters
rows, names = [], []
for n, p in sorted(raw['inserter'].items(), key=lambda kv: kv[1]['rotation_speed']):
    if n not in placeable:
        continue
    rs = p['rotation_speed']
    half_turn_ticks = 0.5 / rs
    e = p.get('energy_source', {})
    pick = p['pickup_position']; ins = p['insert_position']
    pd = math.hypot(*pick); idist = math.hypot(*ins)
    rows.append(base_cols(n, p, 'inserter') + [es(p), num(rs, 4), num(rs * 360, 3), num(half_turn_ticks, 2), num(p['extension_speed'], 4),
                                               f'{num(pick[0])},{num(pick[1])}', f'{num(ins[0])},{num(ins[1])}',
                                               num(kw(p.get('energy_per_movement'))), num(kw(p.get('energy_per_rotation'))),
                                               num(drain_kw(p, 'inserter')) if e.get('type') == 'electric' else '-',
                                               num((rs * kw(p['energy_per_rotation']) + p['extension_speed'] * kw(p['energy_per_movement'])) * 60 + (drain_kw(p, 'inserter') or 0), 1),
                                               'yes' if p.get('stack') else 'no', p.get('filter_count', 0),
                                               'yes' if p.get('allow_burner_leech') else 'no',
                                               gid(p['next_upgrade']) if p.get('next_upgrade') else '-', phase_of(n)])
    names.append(n)
add('Inserters',
    '`rotation_speed` is in turns per tick (1 turn = 360°); half-turn ticks = time for the 180° swing chest→chest. `extension_speed` in tiles/tick. Pickup/insert vectors are relative to the inserter centre for a north-facing inserter (y negative = north/"behind"): it picks up from the tile behind (y = −1 or −2) and drops 1.2 / 2.2 tiles ahead (the 0.2 overshoot means it drops onto the **far lane** of a belt). Energy per movement/rotation in kJ (consumed per tick-segment of motion; electric inserters draw from buffer). Stack inserters move up to the stack-inserter capacity (1 + bonuses, max 12) per swing; normal inserters 1 + non-stack bonus (max 3). Base hand size for all inserters is 1 item. Max kW = (rotation_speed × kJ/rot + extension_speed × kJ/move) × 60 + drain (matches 1.1 tooltips: inserter 13.6, fast 46.7, stack 133, burner 94.2 kW fuel). Chest-to-chest throughput: see 05_mechanics §Inserters.',
    BASE_H + ['energy', 'rot turns/tick', 'deg/tick', 'half-turn ticks', 'ext tiles/tick', 'pickup pos', 'drop pos', 'kJ/move', 'kJ/rot', 'drain kW', 'max kW', 'stack', 'filter slots', 'burner leech', 'upgrades to', 'phase'], rows, names)

# ---------------------------------------------------------------- Containers
rows, names = [], []
for t in ('container', 'logistic-container'):
    for n, p in sorted(raw[t].items(), key=lambda kv: kv[1].get('inventory_size', 0)):
        if n not in placeable:
            continue
        rows.append(base_cols(n, p, t) + [p.get('inventory_size'), p.get('logistic_mode', '-'), p.get('max_logistic_slots', '-') if p.get('logistic_mode') in ('requester', 'buffer', 'storage') else '-',
                                          gid(p['next_upgrade']) if p.get('next_upgrade') else '-', phase_of(n)])
        names.append(n)
add('Chests (containers)', 'Inventory size in slots. All chests are 1×1, no energy. Chests support a "limit bar" (red X restricting usable slots) — keep for MVP (simple slider).',
    BASE_H + ['slots', 'logistic mode', 'logistic slots', 'upgrades to', 'phase'], rows, names)

# ---------------------------------------------------------------- Pipes / fluid logistics
rows, names = [], []
for n, p in [('pipe', P('pipe', 'pipe')), ('pipe-to-ground', P('pipe-to-ground', 'pipe-to-ground')), ('pump', P('pump', 'pump')),
             ('offshore-pump', P('offshore-pump', 'offshore-pump')), ('storage-tank', P('storage-tank', 'storage-tank'))]:
    t = p['type']
    fb = p.get('fluid_box')
    ug = '-'
    if t == 'pipe-to-ground':
        for c in fb['pipe_connections']:
            if c.get('max_underground_distance'):
                ug = c['max_underground_distance']
    rate = '-'
    if t == 'pump':
        rate = f"{num(p['pumping_speed'] * 60)} units/s"
    if t == 'offshore-pump':
        rate = f"{num(p['pumping_speed'] * 60)} water/s"
    rows.append(base_cols(n, p, t) + [es(p), num(kw(p.get('energy_usage'))) if p.get('energy_usage') else '0', num(fluidbox_volume(fb)), ug, rate, phase_of(n)])
    names.append(n)
add('Fluid logistics', 'Fluid box capacity (units) = base_area × 100 (1.1 model). Pipe-to-ground `max_underground_distance` 10 = tile offset between the pair (9 tiles gap). Offshore pump needs no power in 1.1 and outputs 1200 water/s; it must be placed on a shoreline (water tile under its front, land behind). Pump: 1×2, directional, electric, 12 000 units/s max (actual flow limited by the pipe network).',
    BASE_H + ['energy', 'power kW', 'fluid capacity', 'UG distance', 'rate', 'phase'], rows, names)

# ---------------------------------------------------------------- Electric poles
rows, names = [], []
for n, p in sorted(raw['electric-pole'].items(), key=lambda kv: kv[1]['supply_area_distance']):
    if n not in placeable:
        continue
    sad = p['supply_area_distance']
    rows.append(base_cols(n, p, 'electric-pole') + [num(p['maximum_wire_distance']), num(sad), f'{num(sad * 2)}x{num(sad * 2)}', phase_of(n)])
    names.append(n)
add('Electric poles', 'Wire reach = max distance (tiles, centre to centre) to connect copper wire to another pole (the connection uses the minimum of the two poles\' reaches). Supply area = square of side 2 × supply_area_distance centred on the pole; any entity whose collision box overlaps the area is powered. Each pole can hold up to 5 copper-wire connections (auto-connect picks nearest).',
    BASE_H + ['wire reach', 'supply_area_distance', 'supply area tiles', 'phase'], rows, names)

# ---------------------------------------------------------------- Power production
rows, names = [], []
b = P('boiler', 'boiler')
bp = kw(b['energy_consumption'])
rows.append(base_cols('boiler', b, 'boiler') + ['burner (chemical)', f"{num(bp)} kW fuel in, effectivity {b['energy_source']['effectivity']}",
            f"water→steam {b['target_temperature']}°C; {num(bp / ((b['target_temperature'] - 15) * 0.2))} steam/s; fuel slots {b['energy_source']['fuel_inventory_size']}; water box {num(fluidbox_volume(b['fluid_box']))}, steam box {num(fluidbox_volume(b['output_fluid_box']))}; pollution {b['energy_source'].get('emissions_per_minute')}/min", phase_of('boiler')])
names.append('boiler')
for n in ('steam-engine', 'steam-turbine'):
    g = P('generator', n)
    maxp = g['fluid_usage_per_tick'] * 60 * (g['maximum_temperature'] - 15) * 0.2 * g['effectivity']
    rows.append(base_cols(n, g, 'generator') + ['electric out (secondary-output)', f"max {num(maxp)} kW",
                f"steam use {num(g['fluid_usage_per_tick'] * 60)}/s at ≤{g['maximum_temperature']}°C (min {g['fluid_box'].get('minimum_temperature')}°C), effectivity {g['effectivity']}; fluid box {num(fluidbox_volume(g['fluid_box']))}", phase_of(n)])
    names.append(n)
s = P('solar-panel', 'solar-panel')
rows.append(base_cols('solar-panel', s, 'solar-panel') + ['electric out (primary-output)', f"peak {num(kw(s['production']))} kW", 'daylight only; average 70% of peak over a day/night cycle (42 kW)', phase_of('solar-panel')])
names.append('solar-panel')
a = P('accumulator', 'accumulator')
ae = a['energy_source']
rows.append(base_cols('accumulator', a, 'accumulator') + ['electric (tertiary)', f"buffer {num(mj(ae['buffer_capacity']))} MJ",
            f"charge ≤{num(kw(ae['input_flow_limit']))} kW, discharge ≤{num(kw(ae['output_flow_limit']))} kW", phase_of('accumulator')])
names.append('accumulator')
r = P('reactor', 'nuclear-reactor')
hb = r['heat_buffer']
rows.append(base_cols('nuclear-reactor', r, 'reactor') + ['burner (nuclear) → heat', f"{num(mj(r['consumption']))} MW",
            f"neighbour bonus +{num(r['neighbour_bonus'] * 100)}% per adjacent working reactor; heat buffer max {hb['max_temperature']}°C, specific heat {num(mj(hb['specific_heat']))} MJ/°C, max transfer {num(mj(hb['max_transfer']) / 1000)} GW; fuel slots {r['energy_source']['fuel_inventory_size']}, burnt slots {r['energy_source'].get('burnt_inventory_size')}; heat connections {len(hb['connections'])} (3 per side)", phase_of('nuclear-reactor')])
names.append('nuclear-reactor')
hx = P('boiler', 'heat-exchanger')
hxp = kw(hx['energy_consumption'])
rows.append(base_cols('heat-exchanger', hx, 'boiler') + ['heat → steam', f"{num(hxp / 1000)} MW",
            f"steam {hx['target_temperature']}°C; {num(hxp / ((hx['target_temperature'] - 15) * 0.2), 2)} steam/s; works when heat ≥ {hx['energy_source']['min_working_temperature']}°C; specific heat {num(mj(hx['energy_source']['specific_heat']))} MJ/°C", phase_of('heat-exchanger')])
names.append('heat-exchanger')
hp = P('heat-pipe', 'heat-pipe')
rows.append(base_cols('heat-pipe', hp, 'heat-pipe') + ['heat', '-', f"specific heat {num(mj(hp['heat_buffer']['specific_heat']))} MJ/°C, max {hp['heat_buffer']['max_temperature']}°C, max transfer {num(mj(hp['heat_buffer']['max_transfer']) / 1000)} GW", phase_of('heat-pipe')])
names.append('heat-pipe')
add('Power production & storage',
    'Steam energy: 1 unit of steam heated from 15 °C to T °C carries (T − 15) × 0.2 kJ. Boiler: 1.8 MW of fuel → 60 steam/s @165 °C, exactly enough for 2 steam engines (2 × 30/s). Classic ratio 1 offshore pump : 20 boilers : 40 engines. Heat exchanger: 10 MW → 103.09 steam/s @500 °C; steam turbine uses 60/s → 5.82 MW, so 1 reactor (40 MW, no bonus) ≈ 4 exchangers ≈ 7 turbines; 2×2 reactor block (160 MW base → 480 MW with bonuses) feeds 48 exchangers / 83 turbines.',
    BASE_H + ['energy role', 'power', 'details', 'phase'], rows, names)

# ---------------------------------------------------------------- Mining drills
rows, names = [], []
for n, p in sorted(raw['mining-drill'].items(), key=lambda kv: kv[1]['mining_speed']):
    if n not in placeable:
        continue
    r = p['resource_searching_radius']
    side = int(round(r * 2))
    e = p['energy_source']
    vtp = p.get('vector_to_place_result')
    fluid = 'yes (input fluid box for e.g. sulfuric acid)' if p.get('input_fluid_box') else 'no'
    rows.append(base_cols(n, p, 'mining-drill') + [es(p) + (f" ({e.get('fuel_category')})" if e.get('type') == 'burner' else ''),
                num(kw(p['energy_usage'])), num(p['mining_speed']), f'{side}x{side}', ', '.join(p['resource_categories']), modules(p),
                f'{num(vtp[0])},{num(vtp[1])}' if vtp else '-', fluid, emissions(p), gid(p['next_upgrade']) if p.get('next_upgrade') else '-', phase_of(n)])
    names.append(n)
add('Mining drills', 'Mining rate (items/s) = mining_speed × (1 + mining productivity bonus) / mining_time of the resource (all ores 1 s, uranium 2 s); i.e. electric drill on iron = 0.5 ore/s, burner drill = 0.25 ore/s. Mining area is a square centred on the drill. `vector_to_place_result` = drop point for a north-facing drill (just in front of the drill edge): output onto belt/chest/ground/entity there. Pumpjack output is fluid (see 05_mechanics §Mining for oil yield). Burner drill and burner energy: see 05_mechanics. Pollution in /min.',
    BASE_H + ['energy', 'power kW', 'mining speed', 'area', 'resource categories', 'modules', 'drop vector', 'fluid input', 'pollution/min', 'upgrades to', 'phase'], rows, names)

# ---------------------------------------------------------------- Crafting machines
rows, names = [], []
for t in ('furnace', 'assembling-machine'):
    for n, p in sorted(raw[t].items(), key=lambda kv: (items.get(kv[0], {}).get('subgroup', ''), items.get(kv[0], {}).get('order', ''))):
        if n not in placeable:
            continue
        e = p['energy_source']
        fbs = p.get('fluid_boxes') or []
        if isinstance(fbs, dict):
            fbs = [v for k, v in fbs.items() if isinstance(v, dict)]
        fin = sum(1 for f in fbs if isinstance(f, dict) and f.get('production_type') == 'input')
        fout = sum(1 for f in fbs if isinstance(f, dict) and f.get('production_type') == 'output')
        vin = sorted({num(fluidbox_volume(f)) for f in fbs if isinstance(f, dict) and f.get('production_type') == 'input'})
        vout = sorted({num(fluidbox_volume(f)) for f in fbs if isinstance(f, dict) and f.get('production_type') == 'output'})
        fvol = f"in {'/'.join(vin) or '-'}, out {'/'.join(vout) or '-'} units each"
        rows.append(base_cols(n, p, t) + [t, es(p) + (f" ({e.get('fuel_category')})" if e.get('type') == 'burner' else ''), num(kw(p['energy_usage'])),
                    num(drain_kw(p, t), 3) if e.get('type') == 'electric' else '-', num(p['crafting_speed']), ', '.join(p['crafting_categories']),
                    modules(p), ', '.join(p.get('allowed_effects') or ['consumption', 'speed', 'productivity', 'pollution']) if modules(p) else '-',
                    f'{fin} in / {fout} out' + (f' (vol {fvol})' if fbs else ''), emissions(p), gid(p['next_upgrade']) if p.get('next_upgrade') else '-', phase_of(n)])
        names.append(n)
add('Crafting machines (furnaces, assemblers, refinery, chemical plant, centrifuge)',
    'Power kW = consumption while working (`energy_usage`); electric machines also draw `drain` permanently (engine default for crafting machines = energy_usage / 30) — max total draw = power + drain. Burner machines have 1 fuel slot. Fluid boxes: count of input/output boxes; assembler 2/3 have 1 input + 1 output box that is only active when a fluid recipe is set (pipe connections otherwise hidden). Allowed effects for all machines with module slots: consumption, speed, productivity, pollution.',
    BASE_H + ['type', 'energy', 'power kW', 'drain kW', 'crafting speed', 'categories', 'modules', 'allowed effects', 'fluid boxes', 'pollution/min', 'upgrades to', 'phase'], rows, names)

# ---------------------------------------------------------------- Labs, beacons, silo
rows, names = [], []
l = P('lab', 'lab')
rows.append(base_cols('lab', l, 'lab') + [num(kw(l['energy_usage'])), f"research speed {l['researching_speed']}; modules {modules(l)}; accepts {', '.join(gid(i) for i in l['inputs'])} (7 input slots)", phase_of('lab')])
names.append('lab')
bc = P('beacon', 'beacon')
rows.append(base_cols('beacon', bc, 'beacon') + [num(kw(bc['energy_usage'])), f"modules {modules(bc)}; distribution effectivity {bc['distribution_effectivity']}; supply_area_distance {bc['supply_area_distance']} → affects machines overlapping the 9×9 area centred on the beacon (3 + 2×3); allowed effects {', '.join(bc['allowed_effects'])} (no productivity)", phase_of('beacon')])
names.append('beacon')
rs = P('rocket-silo', 'rocket-silo')
rocket = raw['rocket-silo-rocket']['rocket-silo-rocket']
rows.append(base_cols('rocket-silo', rs, 'rocket-silo') + [f"{num(kw(rs['energy_usage']))} idle + {num(kw(rs['active_energy_usage']))} while building/launching",
            f"crafting speed {rs['crafting_speed']}, fixed recipe rocket_part, {rs['rocket_parts_required']} parts per rocket, modules {modules(rs)} (all effects), rocket inventory 1 slot (satellite), result inventory {rs.get('rocket_result_inventory_size')} slot; door_opening_speed {num(rs.get('door_opening_speed'), 6)}/tick, rocket rising_speed {num(rocket.get('rising_speed'), 6)}, engine_starting_speed {num(rocket.get('engine_starting_speed'), 6)}, flying_speed {num(rocket.get('flying_speed'), 6)}, flying_acceleration {num(rocket.get('flying_acceleration'), 6)}", phase_of('rocket-silo')])
names.append('rocket-silo')
add('Labs, beacons, rocket silo', 'Labs consume science cards at the tech\'s "time per unit" / (lab speed × (1 + lab speed bonus) × (1 + module speed)). Beacon: each module\'s effect × 0.5 is transmitted to every machine in range (stacking with other beacons).',
    BASE_H + ['power kW', 'details', 'phase'], rows, names)

# ---------------------------------------------------------------- Radar, lamp, roboport, robots
rows, names = [], []
rd = P('radar', 'radar')
rows.append(base_cols('radar', rd, 'radar') + [num(kw(rd['energy_usage'])), f"long-range scan: 1 sector (chunk 32×32) per {num(mj(rd['energy_per_sector']))} MJ (= {num(mj(rd['energy_per_sector']) * 1000 / kw(rd['energy_usage']), 2)} s at full power) within {rd['max_distance_of_sector_revealed']} chunks; continuous reveal of nearby {rd['max_distance_of_nearby_sector_revealed']} chunks radius (7×7 chunks) using {num(kw(rd['energy_per_nearby_scan']))} kJ per nearby scan", phase_of('radar')])
names.append('radar')
lp = P('lamp', 'small-lamp')
rows.append(base_cols('small-lamp', lp, 'lamp') + [num(kw(lp['energy_usage_per_tick'])), 'turns on automatically at dusk (darkness ≥ 0.3); circuit-controllable later', phase_of('small-lamp')])
names.append('small-lamp')
rp = P('roboport', 'roboport')
rpe = rp['energy_source']
rows.append(base_cols('roboport', rp, 'roboport') + [f"{num(kw(rp['energy_usage']))} idle; charging {num(kw(rp['charging_energy']))} per robot (4 charge pads)",
            f"logistics radius {rp['logistics_radius']} (→ {rp['logistics_radius'] * 2}×{rp['logistics_radius'] * 2} area), construction radius {rp['construction_radius']} (→ {rp['construction_radius'] * 2}×{rp['construction_radius'] * 2}); robot slots {rp['robot_slots_count']}, repair-pack slots {rp['material_slots_count']}; buffer {num(mj(rpe['buffer_capacity']))} MJ, input ≤{num(kw(rpe['input_flow_limit']) / 1000)} MW; charges robots only when buffer ≥ {num(mj(rp['recharge_minimum']))} MJ", phase_of('roboport')])
names.append('roboport')
for t, n in (('logistic-robot', 'logistic-robot'), ('construction-robot', 'construction-robot')):
    p = P(t, n)
    rows.append(base_cols(n, p, t) + [f"{num(kw(p['energy_per_tick']) * 60)} kW hover + {num(kw(p['energy_per_move']))} kJ per tile moved",
                f"speed {p['speed']} tiles/tick ({num(p['speed'] * 60)} tiles/s); battery {num(mj(p['max_energy']))} MJ; payload {p['max_payload_size']}; out of energy speed ×{p['speed_multiplier_when_out_of_energy']}; seeks charge below {num(p.get('min_to_charge', 0.2) * 100)}%, leaves at {num(p.get('max_to_charge', 0.95) * 100)}%", phase_of(n)])
    names.append(n)
add('Radar, lamp, roboport, robots', None, BASE_H + ['power', 'details', 'phase'], rows, names)

# ---------------------------------------------------------------- Circuit network (later phase)
rows, names = [], []
for t in ('arithmetic-combinator', 'decider-combinator', 'constant-combinator', 'power-switch', 'programmable-speaker'):
    for n, p in raw[t].items():
        if n not in placeable:
            continue
        pw = p.get('active_energy_usage') or p.get('energy_usage_per_tick') or p.get('power_on_animation') and None
        rows.append(base_cols(n, p, t) + [t, num(kw(p['active_energy_usage'])) if p.get('active_energy_usage') else (num(kw(p['energy_usage_per_tick'])) if p.get('energy_usage_per_tick') else '0'),
                    p.get('item_slot_count', '-'), phase_of(n)])
        names.append(n)
add('Circuit network (later phase)', 'Wire reach for red/green wire: 9 tiles (circuit_wire_max_distance) for most entities, 10 for combinators (unverified). Spec deferred to circuit phase.',
    BASE_H + ['type', 'power kW', 'signal slots', 'phase'], rows, names)

# ---------------------------------------------------------------- Trains (later phase)
rows, names = [], []
loco = P('locomotive', 'locomotive')
rows.append(base_cols('locomotive', loco, 'locomotive') + ['burner (chemical), 3 fuel slots', f"max power {num(kw(loco['max_power']))} kW; max speed {loco['max_speed']} tiles/tick ({num(loco['max_speed'] * 216, 1)} km/h); weight {loco['weight']}; braking force {loco['braking_force']}; friction {loco['friction_force']}; air resistance {loco['air_resistance']}; reversing power modifier {loco['reversing_power_modifier']}; joint distance {loco['joint_distance']}, connection distance {loco['connection_distance']}", 'trains'])
names.append('locomotive')
for t, n in (('cargo-wagon', 'cargo-wagon'), ('fluid-wagon', 'fluid-wagon'), ('artillery-wagon', 'artillery-wagon')):
    p = P(t, n)
    cap = f"inventory {p['inventory_size']} slots" if p.get('inventory_size') else (f"capacity {p['capacity']} fluid units" if p.get('capacity') else 'artillery')
    rows.append(base_cols(n, p, t) + ['none', f"{cap}; max speed {p['max_speed']} tiles/tick; weight {p['weight']}; braking force {p['braking_force']}; friction {p['friction_force']}; air resistance {p['air_resistance']}", 'combat' if 'artillery' in n else 'trains'])
    names.append(n)
for t, n in (('train-stop', 'train-stop'), ('rail-signal', 'rail-signal'), ('rail-chain-signal', 'rail-chain-signal'), ('straight-rail', 'straight-rail'), ('curved-rail', 'curved-rail')):
    p = P(t, n)
    rows.append(base_cols(n, p, t) + ['none', '', 'trains'])
    names.append(n)
add('Trains (later phase)', 'Rails: straight rail is 2×2 tiles, curved rail spans an 8×4-ish footprint (placed by rail planner, 1.1 rail grid is 2×2). Train physics summary in 05_mechanics §Trains.',
    BASE_H + ['energy', 'stats', 'phase'], rows, names)

# ---------------------------------------------------------------- Vehicles (combat / later)
rows, names = [], []
for t, n in (('car', 'car'), ('car', 'tank'), ('spider-vehicle', 'spidertron')):
    p = P(t, n)
    e = dict(p.get('burner') or p.get('energy_source') or {})
    if p.get('burner'):
        e.setdefault('type', 'burner (chemical)')
    stats = []
    for k in ('consumption', 'braking_power', 'braking_force', 'friction', 'weight', 'rotation_speed', 'inventory_size', 'effectivity', 'movement_energy_consumption', 'chain_shooting_cooldown_modifier', 'height'):
        if p.get(k) is not None:
            stats.append(f"{k} {p[k]}")
    rows.append(base_cols(n, p, t) + [e.get('type', '-'), '; '.join(stats), 'combat'])
    names.append(n)
add('Vehicles (later / combat phase)', None, BASE_H + ['energy', 'stats', 'phase'], rows, names)

# ---------------------------------------------------------------- Combat structures
rows, names = [], []
for t in ('ammo-turret', 'electric-turret', 'fluid-turret', 'artillery-turret', 'wall', 'gate', 'land-mine'):
    for n, p in raw[t].items():
        if n not in placeable:
            continue
        ap = p.get('attack_parameters') or (raw['gun'][p['gun']]['attack_parameters'] if p.get('gun') else {})
        det = []
        if ap:
            det.append(f"range {ap.get('range')}")
            if ap.get('min_range'):
                det.append(f"min range {ap['min_range']}")
            det.append(f"cooldown {ap.get('cooldown')} ticks ({num(60 / ap['cooldown'], 2)} shots/s)" if ap.get('cooldown') else '')
            if ap.get('ammo_category'):
                det.append(f"ammo {ap['ammo_category']}")
            if ap.get('damage_modifier'):
                det.append(f"damage ×{ap['damage_modifier']}")
        if p.get('inventory_size'):
            det.append(f"ammo slots {p['inventory_size']}")
        if p.get('energy_source', {}).get('buffer_capacity'):
            det.append(f"buffer {p['energy_source']['buffer_capacity']}, input {p['energy_source'].get('input_flow_limit')}")
        if p.get('rotation_speed'):
            det.append(f"rotation {p['rotation_speed']} turns/tick")
        if t == 'land-mine':
            det.append(f"trigger radius {p.get('trigger_radius')}, arming {p.get('timeout') or 120} ticks")
        rows.append(base_cols(n, p, t) + [t, '; '.join(x for x in det if x), 'combat'])
        names.append(n)
add('Combat structures (combat phase)', 'Detailed damage formulas deferred to the combat phase design doc.', BASE_H + ['type', 'stats', 'phase'], rows, names)

# ---------------------------------------------------------------- World objects (trees, rocks, fish)
rows = []
rock_names = [n for n, p in raw.get('simple-entity', {}).items() if p.get('minable') and (p['minable'].get('results') or p['minable'].get('result'))]
for n in sorted(rock_names):
    p = raw['simple-entity'][n]
    m = p['minable']
    res = ingr_list(m.get('results')) if m.get('results') else [{'name': m['result'], 'amount': m.get('count', 1)}]
    rows.append([n, size(p), num(m.get('mining_time')), ', '.join(f"{x.get('amount') or str(x.get('amount_min')) + '-' + str(x.get('amount_max'))} {gid(x['name'])}" for x in res)])
tree_sample = {}
for n, p in raw.get('tree', {}).items():
    m = p.get('minable') or {}
    key = (m.get('mining_time'), m.get('count'), m.get('result'))
    tree_sample.setdefault(key, []).append(n)
for (mt, c, r), ns in tree_sample.items():
    rows.append([f"trees ({len(ns)} variants: {', '.join(sorted(ns)[:4])}...)", '1x1 (approx)', num(mt), f"{c} {gid(r) if r else '-'}"])
fish = raw['fish']['fish']
rows.append(['fish (in water)', '-', num(fish['minable']['mining_time']), f"{fish['minable']['count']} raw_fish"])
sections.append(('World objects (minable, not placeable)', 'Hand-mined by the character (mining time / character mining speed 0.5 → e.g. tree 0.55/0.5 = 1.1 s). Rocks are the early stone (and some coal) source.', ['entity', 'size', 'mining time', 'yields'], rows))

# ---------------------------------------------------------------- Character
c = raw['character']['character']
crow = [
    ['max health', c['max_health']], ['healing per tick (out of combat)', c['healing_per_tick']],
    ['ticks to stay in combat', c['ticks_to_stay_in_combat']],
    ['running speed (tiles/tick)', f"{c['running_speed']} → {num(c['running_speed'] * 60)} tiles/s"],
    ['reach distance (interact/open/insert)', c['reach_distance']], ['build distance', c['build_distance']],
    ['reach resource distance (hand mining)', c['reach_resource_distance']], ['drop item distance', c['drop_item_distance']],
    ['item pickup distance (from ground, F key)', c['item_pickup_distance']], ['loot pickup distance (auto)', c['loot_pickup_distance']],
    ['enter vehicle distance', c['enter_vehicle_distance']],
    ['main inventory slots', c['inventory_size']], ['crafting categories', ', '.join(c['crafting_categories'])],
    ['crafting speed', '1 (engine default; modified by force manual-crafting-speed modifier)'],
    ['mining speed', f"{c['mining_speed']} (hand mining time = entity mining_time / 0.5; e.g. ore 2 s per ore)"],
    ['mining categories', ', '.join(c['mining_categories'])],
    ['collision box', f"{c['collision_box']} (0.4×0.4 tiles)"],
    ['guns/ammo slots', '3 / 3 (combat phase)'], ['trash slots', 'logistics phase (robots)'],
    ['toolbelt', 'Tech `toolbelt` adds +10 main inventory slots'],
]
sections.append(('Character (Engineer)', 'From `character` prototype. Movement speed is further multiplied by the tile walking_speed_modifier (stone path 1.3, concrete & hazard concrete 1.4, refined concrete 1.5; shallow water 0.8, mud water 0.7) and by exoskeleton equipment (combat phase).', ['stat', 'value'], crow))

# ---------------------------------------------------------------- Coverage check
uncovered = sorted(placeable - covered - EDITOR_ONLY)

lines = ['# 03 — Entities (Gearforge base set)\n']
lines.append('Source: Factorio 1.1.110 prototypes (`base/prototypes/entity/*.lua`), generated by `docs/research/tools/gen_entities.py`. 1 tick = 1/60 s (game runs at 60 UPS). Sizes are tile footprints derived from collision boxes. "mine s" = time to pick the entity up by hand (mining_time; picking up player-built entities is near-instant in practice, see GDD). Health is used only in the combat phase (nothing can damage entities in the peaceful MVP).\n')
total = 0
for title, intro, headers, rws in sections:
    lines.append(f'## {title} ({len(rws)})\n')
    if intro:
        lines.append(intro + '\n')
    lines.append(md_table(headers, rws))
    lines.append('')
    if title not in ('Character (Engineer)', 'World objects (minable, not placeable)'):
        total += len(rws)
lines.append('## Tiles placed by items\n')
tiles = raw['tile']
trows = []
for n in ('stone-path', 'concrete', 'hazard-concrete-left', 'refined-concrete', 'refined-hazard-concrete-left', 'landfill', 'water', 'deepwater', 'water-shallow', 'water-mud'):
    t = tiles[n]
    trows.append([n, num(t.get('walking_speed_modifier', 1)), num(t.get('vehicle_friction_modifier', 1)), gid(t['minable']['result']) if t.get('minable') else '-', 'water' if 'water-tile' in (t.get('collision_mask') or []) else 'ground'])
lines.append(md_table(['tile', 'walking speed ×', 'vehicle friction ×', 'mined back to', 'kind'], trows))
lines.append('\nOther ground tiles (grass/dirt/sand/desert) have walking speed ×1.0. Tiles do not affect belts or machines.\n')
lines.append(f'**Totals:** {total} placeable entities documented (all phases).' + (f' Not covered: {", ".join(uncovered)}' if uncovered else ' Coverage check: every placeable entity in 1.1 base (excluding editor-only) is listed.'))
with open(OUT, 'w') as f:
    f.write('\n'.join(lines) + '\n')
print('entities', total, 'uncovered', uncovered)
