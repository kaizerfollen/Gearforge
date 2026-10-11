"""Shared helpers for generating Gearforge research docs from Factorio 1.1.110 prototype data.

Source of truth: wube/factorio-data tag 1.1.110 (base + core), loaded with tools/load_data.py
(lupa / Lua 5.2 sandbox emulating the data stage) into raw.json.

All Gearforge ids are snake_case. Factorio names map 1:1 (hyphen -> underscore) except for the
RENAME table below (branded names / science packs / lore names).
"""
import json, re, os

# --------------------------------------------------------------------------------------------
# Naming
# --------------------------------------------------------------------------------------------
# factorio name -> (gearforge id, display name)
RENAME = {
    # Science packs -> "data cards" (colour coding preserved)
    'automation-science-pack': ('mechanics_card', 'Mechanics card (red)'),
    'logistic-science-pack':   ('motion_card', 'Motion card (green)'),
    'military-science-pack':   ('defense_card', 'Defense card (black)'),
    'chemical-science-pack':   ('reaction_card', 'Reaction card (blue)'),
    'production-science-pack': ('fabrication_card', 'Fabrication card (purple)'),
    'utility-science-pack':    ('systems_card', 'Systems card (yellow)'),
    'space-science-pack':      ('orbital_card', 'Orbital card (white)'),
    # Branded / lore-ish names
    'kovarex-enrichment-process': ('uranium_enrichment', 'Uranium enrichment process'),
    'spidertron': ('strider', 'Strider'),
    'spidertron-remote': ('strider_remote', 'Strider remote'),
    'spidertron-rocket-launcher-1': ('strider_rocket_launcher_1', 'Strider rocket launcher 1'),
    'spidertron-rocket-launcher-2': ('strider_rocket_launcher_2', 'Strider rocket launcher 2'),
    'spidertron-rocket-launcher-3': ('strider_rocket_launcher_3', 'Strider rocket launcher 3'),
    'spidertron-rocket-launcher-4': ('strider_rocket_launcher_4', 'Strider rocket launcher 4'),
    'spidertron-leg-1': ('strider_leg_1', 'Strider leg'),
    'effectivity-module': ('efficiency_module', 'Efficiency module'),
    'effectivity-module-2': ('efficiency_module_2', 'Efficiency module 2'),
    'effectivity-module-3': ('efficiency_module_3', 'Efficiency module 3'),
    'used-up-uranium-fuel-cell': ('depleted_uranium_fuel_cell', 'Depleted uranium fuel cell'),
    'fusion-reactor-equipment': ('portable_fusion_reactor', 'Portable fusion reactor'),
    'logistic-chest-active-provider': ('active_provider_chest', 'Active provider chest'),
    'logistic-chest-passive-provider': ('passive_provider_chest', 'Passive provider chest'),
    'logistic-chest-storage': ('storage_chest', 'Storage chest'),
    'logistic-chest-buffer': ('buffer_chest', 'Buffer chest'),
    'logistic-chest-requester': ('requester_chest', 'Requester chest'),
    'character': ('character', 'Engineer (player character)'),
    # Technologies with branded names
    'logistic-science-pack@tech': ('motion_card', 'Motion card'),
}

DISPLAY_OVERRIDES = {
    'uranium-235': 'Uranium-235', 'uranium-238': 'Uranium-238',
    'big-electric-pole': 'Big electric pole', 'small-lamp': 'Lamp',
    'stone-wall': 'Stone wall', 'rail': 'Rail', 'straight-rail': 'Rail (straight)', 'curved-rail': 'Rail (curved)',
    'artillery-wagon': 'Artillery wagon', 'cargo-wagon': 'Cargo wagon', 'fluid-wagon': 'Fluid wagon',
    'power-armor-mk2': 'Power armor MK2', 'energy-shield-mk2-equipment': 'Energy shield MK2',
    'battery-mk2-equipment': 'Personal battery MK2', 'battery-equipment': 'Personal battery',
    'personal-roboport-mk2-equipment': 'Personal roboport MK2', 'personal-roboport-equipment': 'Personal roboport',
    'solar-panel-equipment': 'Portable solar panel', 'night-vision-equipment': 'Nightvision',
    'belt-immunity-equipment': 'Belt immunity equipment', 'exoskeleton-equipment': 'Exoskeleton',
    'personal-laser-defense-equipment': 'Personal laser defense', 'discharge-defense-equipment': 'Discharge defense',
    'energy-shield-equipment': 'Energy shield', 'land-mine': 'Land mine', 'firearm-magazine': 'Firearm magazine',
    'piercing-rounds-magazine': 'Piercing rounds magazine', 'uranium-rounds-magazine': 'Uranium rounds magazine',
    'pumpjack': 'Pumpjack', 'lab': 'Lab', 'iron-stick': 'Iron stick', 'tank': 'Tank', 'car': 'Car',
    'stack-inserter': 'Stack inserter', 'stack-filter-inserter': 'Stack filter inserter',
    'crude-oil': 'Crude oil', 'water': 'Water', 'steam': 'Steam',
}

def gid(fname, kind=None):
    """Factorio prototype name -> Gearforge id."""
    if kind and f'{fname}@{kind}' in RENAME:
        return RENAME[f'{fname}@{kind}'][0]
    if fname in RENAME:
        return RENAME[fname][0]
    # technologies named after science packs
    for k, (i, _) in RENAME.items():
        if fname == k:
            return i
    return fname.replace('-', '_')

def display(fname, kind=None):
    if kind and f'{fname}@{kind}' in RENAME:
        return RENAME[f'{fname}@{kind}'][1]
    if fname in RENAME:
        return RENAME[fname][1]
    if fname in DISPLAY_OVERRIDES:
        return DISPLAY_OVERRIDES[fname]
    s = fname.replace('-', ' ')
    s = re.sub(r'(\D) (\d)$', r'\1 \2', s)
    return s[0].upper() + s[1:]

# Tech display names (science pack techs + branded)
TECH_RENAME = {
    'logistic-science-pack': ('motion_card', 'Motion cards'),
    'military-science-pack': ('defense_card', 'Defense cards'),
    'chemical-science-pack': ('reaction_card', 'Reaction cards'),
    'production-science-pack': ('fabrication_card', 'Fabrication cards'),
    'utility-science-pack': ('systems_card', 'Systems cards'),
    'space-science-pack': ('orbital_card', 'Orbital cards'),
    'kovarex-enrichment-process': ('uranium_enrichment', 'Uranium enrichment process'),
    'spidertron': ('strider', 'Strider'),
    'effectivity-module': ('efficiency_module', 'Efficiency module'),
    'effectivity-module-2': ('efficiency_module_2', 'Efficiency module 2'),
    'effectivity-module-3': ('efficiency_module_3', 'Efficiency module 3'),
    'fusion-reactor-equipment': ('portable_fusion_reactor', 'Portable fusion reactor'),
}

def tech_id(fname):
    if fname in TECH_RENAME:
        return TECH_RENAME[fname][0]
    return fname.replace('-', '_')

def tech_display(fname):
    if fname in TECH_RENAME:
        return TECH_RENAME[fname][1]
    s = fname.replace('-', ' ')
    return s[0].upper() + s[1:]

# --------------------------------------------------------------------------------------------
# Phase tagging (MVP vs later)
# --------------------------------------------------------------------------------------------
EDITOR_ONLY = {
    'coin', 'item-unknown', 'player-port', 'electric-energy-interface', 'heat-interface', 'infinity-chest',
    'infinity-pipe', 'linked-belt', 'linked-chest', 'simple-entity-with-force', 'simple-entity-with-owner',
    'selection-tool', 'item-with-inventory', 'item-with-label', 'item-with-tags', 'dummy-steel-axe',
    'fluid-unknown', 'burner-generator', 'loader', 'fast-loader', 'express-loader', 'copy-paste-tool',
    'cut-paste-tool', 'blueprint', 'blueprint-book', 'deconstruction-planner', 'upgrade-planner',
}
NUCLEAR = {
    'uranium-ore', 'uranium-235', 'uranium-238', 'uranium-fuel-cell', 'used-up-uranium-fuel-cell', 'nuclear-fuel',
    'centrifuge', 'nuclear-reactor', 'heat-exchanger', 'heat-pipe', 'steam-turbine', 'uranium-processing',
    'kovarex-enrichment-process', 'nuclear-fuel-reprocessing', 'nuclear-power',
}
ROBOTS = {
    'roboport', 'logistic-robot', 'construction-robot', 'logistic-chest-active-provider',
    'logistic-chest-passive-provider', 'logistic-chest-storage', 'logistic-chest-buffer', 'logistic-chest-requester',
    'robotics', 'construction-robotics', 'logistic-robotics', 'logistic-system',
}
TRAINS = {
    'locomotive', 'cargo-wagon', 'fluid-wagon', 'artillery-wagon', 'train-stop', 'rail-signal', 'rail-chain-signal',
    'straight-rail', 'curved-rail', 'railway', 'automated-rail-transportation', 'rail-signals', 'fluid-wagon',
    'braking-force-1', 'braking-force-2', 'braking-force-3', 'braking-force-4', 'braking-force-5',
    'braking-force-6', 'braking-force-7',
}
CIRCUIT = {
    'arithmetic-combinator', 'decider-combinator', 'constant-combinator', 'red-wire', 'green-wire', 'power-switch',
    'programmable-speaker', 'circuit-network',
}
COMBAT_TYPES = {'ammo', 'gun', 'armor', 'capsule', 'ammo-turret', 'electric-turret', 'fluid-turret', 'artillery-turret',
                'wall', 'gate', 'land-mine', 'car', 'spider-vehicle', 'combat-robot', 'unit', 'unit-spawner', 'turret',
                'active-defense-equipment', 'battery-equipment', 'belt-immunity-equipment', 'energy-shield-equipment',
                'generator-equipment', 'movement-bonus-equipment', 'night-vision-equipment', 'roboport-equipment',
                'solar-panel-equipment', 'repair-tool', 'spidertron-remote'}
COMBAT_NAMES = {'military-science-pack', 'stone-wall', 'gate', 'repair-pack', 'cliff-explosives', 'explosives',
                'land-mine', 'tank', 'car', 'spidertron'}

def phase_of(fname, ptype=None, extra_combat=False):
    if fname in EDITOR_ONLY:
        return 'excluded'
    if fname in NUCLEAR:
        return 'nuclear'
    if fname in ROBOTS:
        return 'robots'
    if fname in TRAINS or (ptype in ('locomotive', 'cargo-wagon', 'fluid-wagon', 'artillery-wagon')):
        return 'trains'
    if fname in CIRCUIT:
        return 'circuit'
    if fname == 'rail':
        return 'mvp*'  # needed as ingredient of fabrication card even though trains are later
    if ptype in COMBAT_TYPES or fname in COMBAT_NAMES or fname.endswith('-equipment') or extra_combat:
        return 'combat'
    return 'mvp'

# --------------------------------------------------------------------------------------------
# Value parsing
# --------------------------------------------------------------------------------------------
_UNITS = {'': 1, 'k': 1e3, 'K': 1e3, 'M': 1e6, 'G': 1e9, 'T': 1e12, 'P': 1e15}

def energy_j(s):
    """'5kJ' -> 5000.0 ; '90kW' -> 90000.0 (W) ; returns None for None."""
    if s is None:
        return None
    if isinstance(s, (int, float)):
        return float(s)
    m = re.match(r'^\s*([0-9.]+)\s*([kKMGTP]?)([JW])\s*$', s)
    if not m:
        raise ValueError(s)
    return float(m.group(1)) * _UNITS[m.group(2)]

def fmt(x, nd=4):
    if x is None:
        return '-'
    if isinstance(x, bool):
        return 'yes' if x else 'no'
    if isinstance(x, float):
        if x == int(x):
            return str(int(x))
        return ('%.' + str(nd) + 'f') % x if abs(x) < 1e6 else '%g' % x
    return str(x)

def num(x, nd=4):
    s = fmt(x, nd)
    if '.' in s:
        s = s.rstrip('0').rstrip('.')
    return s

def kw(s):
    v = energy_j(s)
    return None if v is None else v / 1000.0

def mj(s):
    v = energy_j(s)
    return None if v is None else v / 1e6

def box_size(cb):
    if not cb:
        return None
    (x1, y1), (x2, y2) = cb
    import math
    return (int(math.ceil(round(x2 - x1, 2))), int(math.ceil(round(y2 - y1, 2))))

def load_raw(path=None):
    path = path or os.environ.get('GF_RAW_JSON')
    with open(path) as f:
        return json.load(f)

ITEM_TYPES = ['item', 'tool', 'ammo', 'gun', 'armor', 'capsule', 'module', 'repair-tool', 'item-with-entity-data',
              'rail-planner', 'blueprint', 'mining-tool', 'selection-tool', 'item-with-inventory', 'item-with-label',
              'item-with-tags', 'spidertron-remote', 'copy-paste-tool', 'deconstruction-item', 'upgrade-item',
              'blueprint-book']

def all_items(raw):
    out = {}
    for t in ITEM_TYPES:
        for n, v in raw.get(t, {}).items():
            out[n] = v
    return out

def md_table(headers, rows):
    def esc(c):
        return str(c).replace('|', '\\|').replace('\n', ' ')
    lines = ['| ' + ' | '.join(headers) + ' |', '|' + '|'.join(['---'] * len(headers)) + '|']
    for r in rows:
        lines.append('| ' + ' | '.join(esc(c) for c in r) + ' |')
    return '\n'.join(lines)

def ingr_list(lst):
    """Normalise Factorio ingredient/result lists into [(type,name,amount,extra)]."""
    out = []
    for e in lst or []:
        if isinstance(e, list):
            out.append({'type': 'item', 'name': e[0], 'amount': e[1]})
        else:
            d = dict(e)
            d.setdefault('type', 'item')
            out.append(d)
    return out


# --------------------------------------------------------------------------------------------
# Technology phase tagging
# --------------------------------------------------------------------------------------------
def _techdata(t):
    d = dict(t)
    if t.get('normal'):
        d.update(t['normal'])
    return d

def rocket_closure(raw):
    T = raw['technology']
    acc = {'rocket-silo'}
    stack = ['rocket-silo']
    while stack:
        n = stack.pop()
        for p in _techdata(T[n]).get('prerequisites') or []:
            if p not in acc:
                acc.add(p); stack.append(p)
    return acc

_ENT_TYPE_CACHE = {}
def _entity_type(raw, name):
    if not _ENT_TYPE_CACHE:
        for tt, protos in raw.items():
            if tt in ITEM_TYPES or tt in ('recipe', 'technology', 'fluid', 'item-subgroup', 'item-group'):
                continue
            for pn, pp in protos.items():
                if isinstance(pp, dict):
                    _ENT_TYPE_CACHE.setdefault(pn, tt)
    return _ENT_TYPE_CACHE.get(name)

ORDER_PHASES = ['combat', 'trains', 'robots', 'nuclear', 'circuit']

def _raw_tech_phase(raw, n):
    T = raw['technology']
    t = _techdata(T[n])
    packs = [(i[0] if isinstance(i, list) else i['name']) for i in t['unit']['ingredients']]
    if 'military-science-pack' in packs:
        return 'combat'
    ph = phase_of(n)
    if ph != 'mvp':
        return ph
    eff = t.get('effects') or []
    items = all_items(raw)
    sub = set()
    for e in eff:
        if e['type'] != 'unlock-recipe':
            continue
        rr = raw['recipe'][e['recipe']]
        rr = rr.get('normal') or rr
        res = ingr_list(rr.get('results')) if rr.get('results') else [{'name': rr['result']}]
        for x in res:
            it = items.get(x['name'], {})
            pp = phase_of(x['name'], it.get('type'))
            if it.get('place_result'):
                pp2 = phase_of(it['place_result'], _entity_type(raw, it['place_result']))
                if pp2 != 'mvp':
                    pp = pp2
            sub.add(pp)
    mods = {e['type'] for e in eff if e['type'] != 'unlock-recipe'}
    if mods & {'ammo-damage', 'gun-speed', 'turret-attack', 'maximum-following-robots-count', 'artillery-range'}:
        sub.add('combat')
    if mods & {'worker-robot-speed', 'worker-robot-storage', 'worker-robot-battery', 'character-logistic-requests',
               'character-logistic-trash-slots', 'ghost-time-to-live'}:
        sub.add('robots')
    if mods & {'train-braking-force-bonus'}:
        sub.add('trains')
    if mods - {'ammo-damage', 'gun-speed', 'turret-attack', 'maximum-following-robots-count', 'artillery-range',
               'worker-robot-speed', 'worker-robot-storage', 'worker-robot-battery', 'character-logistic-requests',
               'character-logistic-trash-slots', 'ghost-time-to-live', 'train-braking-force-bonus'}:
        sub.add('mvp')
    if not sub:
        return None  # no effects: decided by dependents
    if 'mvp' in sub or 'mvp*' in sub:
        return 'mvp'
    return next(o for o in ORDER_PHASES if o in sub)

def tech_phase_of(raw, n, rocket_req=None):
    T = raw['technology']
    rocket_req = rocket_req if rocket_req is not None else rocket_closure(raw)
    ph = _raw_tech_phase(raw, n)
    if ph is None:
        kids = [k for k, t in T.items() if n in (_techdata(t).get('prerequisites') or [])]
        kp = {tech_phase_of(raw, k, rocket_req).split(' ')[0] for k in kids}
        ph = 'mvp' if ('mvp' in kp or not kp) else next((o for o in ORDER_PHASES if o in kp), 'mvp')
    if n in rocket_req and ph != 'mvp':
        return ph + ' (needed for rocket → keep researchable in MVP)'
    return ph

# --------------------------------------------------------------------------------------------
# Item / recipe phase tagging (single source used by all generators)
# --------------------------------------------------------------------------------------------
PHASE_ORDER = ['excluded', 'combat', 'trains', 'robots', 'nuclear', 'circuit', 'mvp*', 'mvp']

def item_phase(raw, n):
    """Phase of an item or fluid: own phase, or the phase of the entity it places if that is later."""
    if n in raw.get('fluid', {}):
        return phase_of(n)
    it = all_items(raw).get(n, {})
    ph = phase_of(n, it.get('type'))
    pr = it.get('place_result')
    if ph == 'mvp' and pr:
        p2 = phase_of(pr, _entity_type(raw, pr))
        if p2 != 'mvp':
            ph = p2
    return ph

def recipe_phase(raw, n):
    r = raw['recipe'][n]
    rr = dict(r)
    if r.get('normal'):
        rr.update(r['normal'])
    res = ingr_list(rr['results']) if rr.get('results') else [{'name': rr['result']}]
    phs = {item_phase(raw, x['name']) for x in res} | {phase_of(n)}
    for tn, t in raw['technology'].items():
        t = _techdata(t)
        if any(e.get('type') == 'unlock-recipe' and e.get('recipe') == n for e in t.get('effects') or []):
            if any((i[0] if isinstance(i, list) else i['name']) == 'military-science-pack' for i in t['unit']['ingredients']):
                phs.add('combat')
    if n == 'rail':
        return 'mvp*'
    return next(p for p in PHASE_ORDER if p in phs)

def gamedata_phase(ph):
    """Normalise doc phase labels to GameData phase strings."""
    ph = ph.split(' ')[0] if '(needed for rocket' not in ph else 'mvp'
    return {'mvp*': 'mvp', 'circuit': 'circuits'}.get(ph, ph)
