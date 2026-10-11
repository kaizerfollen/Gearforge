# Gearforge — Game Design Document (v0.1)

Owner: Lead Game Designer. Platform: iOS / iPadOS (Swift + SpriteKit), landscape. Business model: **premium, no IAP, no ads, offline**.
Reference design: Factorio 1.1 base game (mechanics and numbers mirrored; all names, text and art original).
Companion data docs (source of truth for numbers): `docs/research/01_items.md`, `02_recipes.md`, `03_entities.md`, `04_technologies.md`, `05_mechanics.md`; machine-readable snapshot `docs/research/data/gearforge_base_1_1.json` (regenerate with `docs/research/tools/regenerate.sh`).

---

## 1. Vision & pillars

**Pitch:** Stranded engineer, alien planet, nothing but a pickaxe-equivalent and a burner drill. Build an ever-growing automated factory — mines, smelters, belts, assemblers, oil refineries — until you can launch a rocket. Factory-automation depth of the PC genre leader, rebuilt for touch.

| pillar | meaning for every decision |
|---|---|
| **Faithful depth** | Same production graph, same ratios, same throughput math as 1.1. A player's PC knowledge transfers. No "mobile-ized" shallow recipes. |
| **Touch-native building** | Drawing belts with a finger, area tools, undo, ghosts. Building must feel faster on touch than with a mouse. |
| **Calm & offline** | Peaceful by default (combat is a later, optional phase). Sessions of 5–60 min; save anywhere; background-safe. |
| **Performance is a feature** | 60 UPS simulation on A14+ for mid-size factories; aggregate simulation (transport lines, fluid segments, network solves). Never trade correctness for FPS: render can drop, simulation is deterministic. |
| **Respect the player** | Premium; no timers, no energy, no ads. Information-dense UI with alt-mode overlays. |

Original naming: science packs are **data cards**: Mechanics (red), Motion (green), Defense (black), Reaction (blue), Fabrication (purple), Systems (yellow), Orbital (white). Other renames in 01_items §Renames. Player character = "the Engineer". Planet/lore TBD by narrative (no reuse of Factorio lore).

---

## 2. Core loop

```
 explore ─► mine by hand ─► craft burner tools ─► automate a resource ─► smelt
   ▲                                                                   │
   │                                                                   ▼
 expand to new ore/oil ◄─ unlock tech ◄─ research (labs eat cards) ◄─ automate cards
   │                                                                   ▲
   └──► bottleneck appears (power / throughput / ore) ──► redesign / upgrade ┘
```

- **Minute-to-minute:** place/route belts & inserters, fix starved machines, hand-feed early buildings, craft.
- **Session (10–40 min):** finish a production line (e.g. green cards), research 2–5 techs, expand power.
- **Long arc:** tiers (burner → automation → logistics → oil → advanced → rocket); campaign levels each teach one tier; Freeplay = full arc + infinite research.
- **Feedback surfaces:** production stats graph (items/min per item), power graph, machine status icons (no input / output full / no power / no fuel / low power), research progress, objective tracker.

---

## 3. Scope & phases

| phase | content | status |
|---|---|---|
| **MVP (1.0)** | Peaceful world. All production/logistics/power/oil/modules/beacons/solar/rocket content: items marked `mvp` in 01, entities `mvp` in 03, 73 technologies (71 `mvp` + `railway` and `robotics` kept researchable because they are rocket prerequisites — they unlock only `rail` and `flying_robot_frame` in MVP) + infinite `mining_productivity`. Campaign L1–L8, Freeplay, saves, settings, stats, map, alt-mode, copy/paste area, undo. | build first |
| 1.1 "Blueprints" | Blueprint library (save area as blueprint, books), upgrade planner (tier upgrade by area), deconstruction filters, iCloud save sync. | after MVP |
| 1.2 "Robots" | Roboports, logistic & construction robots, logistic chests, personal logistics, robot techs + infinite worker robot speed. Construction robots build ghosts/blueprints. | |
| 1.3 "Rails" | Trains: rails, locomotive, cargo & fluid wagons, stations, signals, schedules, braking techs. Core stats in §13. | big feature |
| 1.4 "Circuits" | Circuit network: wires, combinators, power switch, speaker, circuit conditions on inserters/belts/pumps. | |
| 1.5 "Nuclear" | Uranium mining (sulfuric acid), centrifuge, enrichment, reactor, heat pipes, exchangers, turbines, nuclear fuel. | |
| 2.0 "Hostiles" | Enemies (biters-equivalent, original creatures), pollution diffusion & attacks, turrets, walls, weapons, ammo, armor & equipment grid, vehicles (car, tank, strider), Defense cards and all combat techs, repair packs. Optional per world. | later |

MVP counts (from generated docs): 107 MVP items (+1 `rail` mvp*) of 200; 49 MVP entity types of 85; recipes: all whose phase is `mvp`/`mvp*` in 02.

---

## 4. Controls (touch)

Landscape only (iPhone and iPad). All gestures are configurable in Settings → Controls. Left-handed mirror option.

### 4.1 Modes
The game is always in exactly one mode; the current mode is shown by the highlighted mode button (right edge).

| mode | entered by | purpose |
|---|---|---|
| **Explore** (default) | tap ✕ / back from any mode | move, select, open, mine by hand |
| **Build** | tap an item in quickbar/inventory that has a place result | place ghost-previewed entities/tiles |
| **Remove** | bulldozer button | pick up (mine) player entities by tap or area drag |
| **Paste** | after "Copy settings" or "Copy area" | stamp settings / ghosts |
| **Map** | minimap tap or pinch-out past min zoom | strategic view, pan, set pins |

### 4.2 Movement & camera
- **Virtual joystick**: floating; appears under the thumb when touching the left 35% of the screen (empty area) in Explore/Build/Remove. 8-directional analog; full deflection = character run speed (9 tiles/s × tile modifier). Dead zone 10% radius.
- **Tap-to-walk** (setting, default ON): double-tap on empty ground → character pathfinds there (A* on tile grid, avoids entities; stops when obstructed).
- **Camera** follows the character. **Pinch** zoom: 0.35× … 3× of base zoom (base = 32 px per tile at 1×, iPhone ≈ 26 tiles visible horizontally at 1×). Pinch-out below 0.35× crossfades into Map view.
- **Two-finger drag** pans the camera away from the character; a "⊙ Recenter" button appears; camera snaps back when the joystick is used.

### 4.3 Selection & interaction (Explore)
- **Tap entity** → selects it: outline + **info card** (bottom-left above quickbar): name, status icon, recipe, progress, power, fuel. Tap the card (or tap the entity again) to **open the entity screen** (needs reach 10 tiles; outside reach the card shows "Out of reach" and offers tap-to-walk).
- **Long-press entity** (350 ms) → **radial menu**: Open · Rotate · Pipette · Copy settings · Paste settings · Take all (outputs) · Remove.
- **Hand mining**: press-and-hold on a resource tile / tree / rock within 2.7 tiles (05 §4.4) → mining progress ring; continues while held. If farther, the character auto-walks into range first (setting). Dedicated **⛏ Mine** button mines the nearest minable resource in reach while held (accessibility).
- **Pick up items from belts/ground**: long-press belt with nothing selected → "Pick up items" in radial.
- **Alt-mode** toggle button (eye icon, top-right) shows recipe icons on machines, belt directions, filter icons, and inserter arrows (like Factorio alt-mode). Default on (setting).

### 4.4 Build mode
- Select an item (quickbar tap, inventory tap, or pipette). A **ghost** appears under the finger / at the last tap point, snapped to grid, tinted green (valid) / red (invalid; reason text above: "Blocked", "Needs water edge", "No resource under drill", "Out of reach", "Would mix fluids").
- **Placing single entities**: tap a tile → ghost moves there; tap the ghost (or the floating ✓ button) to place. Setting "One-tap place" (default ON for iPad, OFF for iPhone): first tap places directly.
- **Drag-to-place**: finger drag places a line of entities.
  - **Belts**: path follows the finger on a 4-connected grid, direction = drag direction, corners turn automatically, existing belts are joined; when the path crosses an obstacle the tool auto-inserts an **underground pair** if within the tier's max distance and the player has undergrounds (Factorio 2.0 "smart belt dragging" behaviour); otherwise the segment turns red.
  - **Pipes**: same path tool; auto pipe-to-ground over obstacles (max 10).
  - **Poles**: drag places poles at the maximum wire-reach spacing automatically (small 7, medium 9, big 30, substation 18 tiles), skipping blocked tiles.
  - **Other entities** (assemblers, furnaces, drills, inserters, chests, solar, tiles): drag places a row/column with no gaps (entity width spacing). Tiles (stone brick/concrete/landfill): drag paints a brush (size 1/3/5 selectable).
- **Rotate**: ⟳ button (right side, visible in Build mode) or two-finger twist on screen. Rotation is remembered per item. Drag tools set direction automatically.
- **Pipette**: long-press any existing entity while in Build/Explore → selects that item (and its recipe/filter for paste) if in inventory; if not in inventory, enters ghost mode for it.
- **Fast replace / upgrade**: placing a higher tier over a lower tier of the same replace group (belts, inserters, assemblers, furnaces, poles, chests, pipes) swaps it in place, keeping direction/recipe/contents.
- **Undo / Redo** buttons (top of build palette): last 50 build/remove actions (items returned/consumed accordingly).
- **Ghosts**: placing an item you don't have (via pipette/paste) or outside reach places a ghost; the character auto-builds ghosts within reach when it has the item (setting "Auto-build ghosts in reach", default ON). Robots (phase 1.2) build ghosts anywhere.
- **Build reach**: 10 tiles from the character (05 §12). The reach circle is drawn faintly in Build/Remove mode. Setting **"Casual reach"** (default OFF): reach = everything on screen (for players who prefer not to walk).

### 4.5 Remove mode
- Tap an entity → picked up instantly (contents → inventory; full inventory → leftovers spill into a temporary "drop box" entity on that tile).
- Drag a rectangle → removes all player entities inside (with a confirmation chip "Remove 34 entities?" if > 20). Filter chips: All / Belts / Inserters / Poles / Machines / Tiles.
- Resources/trees/rocks are never removed by this tool (use hand mining).

### 4.6 Copy / paste
- **Copy settings** (radial) → tap other entities of the same kind to paste recipe / filters / splitter priorities / chest limit / inserter filters.
- **Copy area** (MVP): Remove-mode-style rectangle with a "Copy" chip → enters Paste mode with a ghost stamp (rotatable, flippable). Placing creates ghosts the character builds from inventory. Blueprint library (named, saved stamps) is phase 1.1.

### 4.7 Other gestures & shortcuts
| action | gesture/button |
|---|---|
| Open inventory + crafting | 🎒 button (bottom-right) or swipe up from quickbar |
| Tech tree | tap research bar (top-center) |
| Production stats | 📈 in pause menu or long-press research bar |
| Map | tap minimap (top-left) or pinch-out |
| Quick-transfer stack to/from entity | in entity screen: tap a slot = move stack; long-press = move half; "All" buttons |
| Split stack | long-press in inventory → slider |
| Cancel/back | ✕ button top-left of any panel; two-finger tap = back |
| Game controller (MFi) | full support: left stick move, right stick cursor, triggers build/remove (stretch goal, MVP+) |

---

## 5. HUD layout (landscape)

```
┌──────────────────────────────────────────────────────────────────────────────┐
│[Minimap 120×120]   [Research: Automation ▓▓▓▓░░ 62% · 1:20]      ⚠ 👁  ⏸   │
│ ⚡ 92% (tap)        [Objective tracker ▸ 3/5 Build 4 electric drills]          │
│                                                                              │
│                                                                    [Build]   │
│                                                                    [Remove]  │
│                          (world view)                              [ ⟳ ]     │
│                                                                    [Undo]    │
│  (joystick zone)                                                             │
│   ◯                    [craft queue: ⚙x5 ▸ 3s]                     [⛏]      │
│[info card]   [1][2][3][4][5][6][7][8][9][0]  ‹page›                [🎒]     │
└──────────────────────────────────────────────────────────────────────────────┘
```

- Respect safe areas (Dynamic Island / home indicator). HUD scale follows Settings → UI scale (80–140%).
- **Top-left**: minimap (chunk-resolution, shows power poles/belts at zoom), under it power satisfaction of the network the character stands in (green/yellow/red).
- **Top-center**: current research (icon, name, % and ETA; tap → tech tree); campaign objective tracker (collapsible; shows current objective + progress numbers).
- **Top-right**: alerts (⚠ count: no fuel, no power, output full, ghost cannot be built, research done), alt-mode toggle, pause/menu.
- **Right edge**: mode buttons (Build, Remove, Rotate (Build only), Undo/Redo (Build/Remove only)), Mine, Inventory.
- **Bottom-center**: quickbar 10 slots × 2 pages (swipe to switch); slots can hold item filters (shows count in inventory; greyed if 0, tap = ghost mode). Craft queue strip above it.
- **Bottom-left**: info card for selection; joystick appears in the lower-left zone.
- Panels (inventory, entity screens, tech tree) open as **sheets** covering ≤ 70% width on iPad (world stays visible and running) and full-screen on iPhone; game does not pause (Settings: "Pause when menus open" option for Campaign easy mode).

### 5.1 Key screens
| screen | content |
|---|---|
| Inventory & crafting | left: 80-slot grid (+10 toolbelt), sort button, trash slot; right: crafting tabs (Logistics / Production / Intermediates / Combat (later)), recipe grid with craftable counts (incl. chain crafting), recipe tooltip (ingredients, time, made in), queue list. Tap = 1, long-press = 5, "Max". |
| Entity screen | machine: recipe selector, input/output slots, fuel slot, module slots, progress + productivity bar, status, power use. Chest: slots + limit bar. Splitter: input/output priority & filter. Inserter: filter slots (filter variants). Furnace: auto recipe display. Lab: card slots. Silo: parts progress, rocket inventory, Launch button, auto-launch toggle. |
| Tech tree | zoomable graph; filters: Available / Researched / All; tech card: cost (count × cards, time), prerequisites, unlocks; Research/Queue buttons (queue ≤ 7). |
| Production stats | items/min produced & consumed per item; ranges 1 min / 10 min / 1 h / 10 h; also power: production by source, consumption by entity type. |
| Map | full map, pan/zoom, legend toggles (ores, belts, power, pins), tap point → "Walk here" / "Pin". Radar-revealed areas only (fog of war). |
| Factoriopedia-equivalent "Codex" | browse every item/recipe/entity with stats from data (auto-generated from data tables). |

---

## 6. Progression tiers

| tier | name | key unlocks (tech ids) | cards | player goal |
|---|---|---|---|---|
| T0 | Burner | start recipes: burner drill, stone furnace, chests, belts, inserters (burner & electric), pipes, offshore pump, boiler, steam engine, small pole, lab, electric drill, gears/cable/circuits, mechanics card | – | bootstrap iron/copper/coal/stone |
| T1 | Automation | `automation`, `logistics`, `electronics`, `optics`, `steel_processing`, `fast_inserter`, `steel_axe`, `motion_card` | R | steam power, labs, assemblers, belts & undergrounds |
| T2 | Logistics | `automation_2`, `logistics_2`, `engine`, `fluid_handling`, `advanced_material_processing`, `electric_energy_distribution_1`, `toolbelt`, `research_speed_1-2`, `stack_inserter`, `inserter_capacity_bonus_1-2`, `landfill`, `modules`, `speed/efficiency/productivity_module`, `solar_energy`, `electric_energy_accumulators`, `battery`, `concrete`, `mining_productivity_1` | R G | green cards, main bus, steel furnaces, solar |
| T3 | Oil | `oil_processing`, `plastics`, `sulfur_processing`, `advanced_electronics`, `reaction_card`, `flammables`, `railway` (rail only in MVP) | R G (→B) | pumpjacks, refinery, chem plants, plastic, red circuits, blue cards |
| T4 | Advanced | `advanced_oil_processing`, `lubricant`, `electric_engine`, `robotics` (frames only), `advanced_material_processing_2`, `advanced_electronics_2`, `automation_3`, `logistics_3`, `effect_transmission`, `coal_liquefaction`, `speed_module_2`, `speed_module_3`, `productivity_module_2`, `productivity_module_3`, `efficiency_module_2`, `efficiency_module_3`, `low_density_structure`, `rocket_fuel`, `fabrication_card`, `systems_card`, `electric_energy_distribution_2`, `research_speed_3-6`, `inserter_capacity_bonus_3-7`, `mining_productivity_2-3` | R G B P Y | purple & yellow cards, beacons, processing units |
| T5 | Rocket | `rocket_control_unit`, `rocket_silo`, `orbital_card` (satellite), then infinite `mining_productivity_4`+ | R G B P Y (+W) | build silo, 100 rocket parts, launch; then infinite research |

---

## 7. Campaign

Eight hand-authored levels, each teaching one tier, each with a fixed seed, finite map, a starting kit that represents what the previous level built, and a measurable victory. Level select shows best time and stars. Levels unlock sequentially; L1–L2 have contextual tutorial prompts ("hint bubbles", dismissable, replayable from pause menu). All campaign levels are **peaceful**.

Common rules: objectives appear one or two at a time in the tracker; "produced" means counted in production statistics (any source including handcraft unless stated "by machines"); rate objectives are measured as the rolling 60 s average and must be sustained for the stated duration. Stars: ★ complete, ★★ under par time, ★★★ under gold time (game time, not real time). Campaign tech price multiplier noted per level (Freeplay default 1.0).

### L1 — "Landfall" (Burner)
| field | value |
|---|---|
| teaches | moving, hand mining, crafting & chain-crafting, burner drills, furnaces, fuel, chests |
| map | 160×160, seed `GF-L1`, grass/dirt, scattered trees & 6 big rocks near spawn |
| resources | iron 60 000 (patch r≈10, 18 tiles from spawn), copper 40 000, coal 40 000, stone 20 000; no water needed |
| starting items | 8 iron plate, 10 wood, 1 burner mining drill, 1 stone furnace |
| techs | research disabled (no labs offered); all start-enabled recipes available, crafting UI highlights burner set |
| objectives | 1) Hand-mine 10 stone and 10 coal. 2) Place the burner drill on iron and the furnace in front of it; fuel both. 3) Smelt 50 iron plates. 4) Craft 4 burner mining drills (chain-crafts gears & furnaces). 5) Build a coal pair: 2 burner drills on coal feeding each other's fuel slot + one into a chest. 6) Smelt 50 copper plates. 7) Have 10 burner drills running at once. |
| victory | produced ≥ 300 iron plate and ≥ 150 copper plate, and 10 burner drills working simultaneously |
| par / gold | 25 min / 15 min |

### L2 — "First Light" (Steam power & research)
| field | value |
|---|---|
| teaches | offshore pump → boiler → steam engine, poles & supply areas, labs, research, electric drills, inserters, first assembler |
| map | 192×192, seed `GF-L2`, lake 20–25 tiles from spawn |
| resources | iron 120 000, copper 80 000, coal 80 000, stone 40 000 |
| starting items | 60 iron plate, 30 copper plate, 50 coal, 8 burner mining drill, 6 stone furnace, 2 wooden chest, 10 burner inserter |
| techs | available: `automation`, `logistics`, `electronics`, `optics`, `steel_processing`, `fast_inserter`, `steel_axe` (R only). Price multiplier 1.0. |
| objectives | 1) Build 1 offshore pump, 1 boiler, 2 steam engines and fuel the boiler. 2) Power a lab with small electric poles. 3) Craft 10 mechanics cards and research **Automation**. 4) Place 4 electric mining drills on iron. 5) Build an assembler making gears, fed and emptied by inserters. 6) Automate mechanics cards (assembler + inserters into the lab). 7) Research **Logistics** and **Electronics**. |
| victory | 200 mechanics cards produced **by machines**; Automation, Logistics, Electronics researched |
| par / gold | 40 min / 25 min |

### L3 — "Assembly Line" (Automation at scale)
| field | value |
|---|---|
| teaches | belts, lanes, sideloading, undergrounds, splitters, smelting columns, ratios (3 cable : 2 circuit assemblers), steel |
| map | 256×256, seed `GF-L3` |
| resources | iron 300 000, copper 200 000, coal 200 000, stone 100 000, lake 30 tiles |
| starting items | 200 iron plate, 100 copper plate, 200 coal, 100 transport belt, 20 underground belt, 10 splitter, 40 inserter, 10 burner inserter, 20 electric mining drill, 24 stone furnace, 10 assembling machine 1, 50 small electric pole, 1 offshore pump, 4 boiler, 8 steam engine, 10 lab, 20 iron chest |
| pre-built | none (empty start, power site marked with a "suggested" ghost layout the player may build) |
| techs | `automation`, `logistics` pre-researched; available: all remaining R-only techs incl. `motion_card`. Price 1.0. |
| objectives | 1) Build an iron smelting column: ≥ 12 stone furnaces fed by one ore belt, plates out on one belt. 2) Same for copper (≥ 8 furnaces). 3) Research **Steel processing**, smelt 50 steel. 4) Build a circuit line: 3 cable assemblers : 2 circuit assemblers. 5) Research **Fast inserter** and **Motion cards**. |
| victory | **20 assemblers working simultaneously** (any recipes, powered, not starved for 10 s) and 1 000 electronic circuits produced |
| par / gold | 60 min / 40 min |

### L4 — "Motion" (Logistics & green cards)
| field | value |
|---|---|
| teaches | Motion (green) cards, main-bus layout, rate-based thinking, steel furnaces, engines, fluid handling, power expansion |
| map | 320×320, seed `GF-L4` |
| resources | iron 500 000 ×2 patches, copper 400 000, coal 400 000, stone 150 000 |
| starting items | 400 iron plate, 200 copper plate, 200 steel plate, 400 transport belt, 40 underground, 20 splitter, 100 inserter, 20 long-handed inserter, 20 fast inserter, 30 electric mining drill, 48 stone furnace, 20 assembling machine 1, 100 small pole, 2 offshore pump, 10 boiler, 20 steam engine, 10 lab |
| techs | all R techs researched. Available: R G techs of T2 (see §6). Price **0.75**. |
| objectives | 1) Automate Motion cards (inserters + belts). 2) Research **Automation 2**, **Logistics 2**, **Steel furnaces** (`advanced_material_processing`), **Engine**, **Fluid handling**. 3) Expand power to ≥ 10 MW capacity. |
| victory | sustain **≥ 30 mechanics + 30 motion cards per minute** for 5 minutes, and 500 motion cards produced |
| par / gold | 75 min / 50 min |

### L5 — "Black Gold" (Oil)
| field | value |
|---|---|
| teaches | pumpjacks & oil yield, basic oil processing, chemical plants, plastic, sulfur, advanced circuits, Reaction (blue) cards, fluid segments/pumps/tanks |
| map | 384×384, seed `GF-L5`; oil field of 6 wells (yield 150–300%) at 90–120 tiles NE |
| resources | iron 800 000, copper 600 000, coal 500 000, stone 200 000, crude oil 6 wells |
| starting items | 300 steel plate, 600 iron plate, 400 copper plate, 600 transport belt, 60 underground belt, 30 splitter, 150 inserter, 40 fast inserter, 40 electric mining drill, 48 steel furnace, 30 assembling machine 2, 100 medium electric pole, 50 big electric pole, 200 pipe, 40 pipe-to-ground, 4 storage tank |
| pre-built | working red+green card factory (stamped from a designer blueprint) powered by 20 MW steam |
| techs | T1–T2 researched (except oil/solar). Available: `oil_processing`, `plastics`, `sulfur_processing`, `advanced_electronics`, `battery`, `reaction_card`, `flammables`, `solar_energy`, `electric_energy_accumulators`, `concrete`, `landfill`, `modules`, module tier 1 techs. Price **0.6**. |
| objectives | 1) Build 4 pumpjacks and pipe crude to a refinery. 2) Make plastic (chemical plant). 3) Make sulfur. 4) Automate advanced circuits. 5) Research **Reaction cards** and automate them. |
| victory | 300 reaction cards and 500 plastic bars produced by machines |
| par / gold | 90 min / 60 min |

### L6 — "Refinement" (Advanced oil, modules, solar)
| field | value |
|---|---|
| teaches | advanced oil processing, cracking & petroleum back-up, lubricant, solid fuel, electric engines, modules, solar + accumulator ratio (25:21), concrete |
| map | 448×448, seed `GF-L6`; 2 oil fields |
| resources | iron 1.2 M, copper 1 M, coal 600 000, stone 300 000, crude oil 12 wells |
| starting items | L5 kit + 10 oil refinery, 20 chemical plant, 10 pumpjack, 20 pump, 200 solar panel, 160 accumulator, 1 000 concrete |
| pre-built | red/green/blue factory (basic oil processing) |
| techs | T1–T3 researched. Available: `advanced_oil_processing`, `lubricant`, `electric_engine`, `speed/productivity/efficiency_module_2`, `electric_energy_distribution_2`, `advanced_material_processing_2`, `research_speed_2-3`, `mining_productivity_1`, `inserter_capacity_bonus_1-3`, `stack_inserter`, `coal_liquefaction`. Price **0.5**. |
| objectives | 1) Switch to advanced oil processing with heavy→light and light→gas cracking so no output backs up. 2) Automate lubricant and electric engines. 3) Build a solar field with accumulators. 4) Produce speed and productivity modules. |
| victory | solar grid delivers ≥ **5 MW average over one full day/night cycle with no steam engine running** (game checks accumulators never empty below 0 while load ≥ 5 MW is attached), and 50 speed modules + 50 productivity modules produced |
| par / gold | 100 min / 70 min |

### L7 — "Industrial Scale" (Purple & yellow)
| field | value |
|---|---|
| teaches | electric furnaces, assembler 3, beacons + speed modules, productivity modules on intermediates, processing units, LDS, flying robot frames, rail as ingredient, Fabrication (purple) & Systems (yellow) cards |
| map | 512×512, seed `GF-L7` |
| resources | iron 2 M, copper 2 M, coal 1 M, stone 500 000, crude oil 16 wells |
| starting items | L6 kit + 40 beacon, 100 speed module, 100 productivity module, 40 electric furnace, 20 assembling machine 3 |
| pre-built | R/G/B factory with advanced oil processing |
| techs | T1–T3 + L6 techs researched. Available: rest of T4 (`fabrication_card`, `systems_card`, `effect_transmission`, `automation_3`, `logistics_3`, `advanced_electronics_2`, `low_density_structure`, `rocket_fuel`, `robotics`, `railway`, module tier 3, `research_speed_4-6`, `inserter_capacity_bonus_4-7`, `mining_productivity_2-3`). Price **0.5**. |
| objectives | 1) Automate processing units. 2) Automate fabrication cards (needs rail, electric furnaces, prod modules). 3) Automate systems cards (LDS, flying robot frames). 4) Build ≥ 8 beacons affecting production. 5) Research **Rocket fuel**, **Low density structure**, **Speed module 3**, **Productivity module 3**. |
| victory | 500 fabrication + 500 systems cards produced; `rocket_control_unit` researched |
| par / gold | 150 min / 100 min |

### L8 — "Countdown" (Rocket)
| field | value |
|---|---|
| teaches | rocket silo, rocket part logistics (1000 RCU, 1000 LDS, 1000 rocket fuel per rocket), satellite, launch |
| map | 640×640, seed `GF-L8` |
| resources | iron 4 M, copper 4 M, coal 2 M, stone 1 M, crude oil 24 wells (per-rocket raw cost ≈ 49k iron ore, 92.5k copper ore, 9.5k coal, ~200k petroleum gas, ~110k light oil — derived from 02) |
| starting items | L7 kit + 1 000 concrete, 1 000 steel plate |
| pre-built | full 5-card science factory (≈ 45 cards/min each) |
| techs | everything except `rocket_silo` and `orbital_card` researched. Price **0.5** (rocket silo: 500 units × 5 cards × 60 s). |
| objectives | 1) Research **Rocket silo**. 2) Build the silo. 3) Automate rocket control units, low density structures, rocket fuel into the silo. 4) Complete 100 rocket parts. 5) (Optional ★) research **Orbital cards**, craft a satellite and load it. |
| victory | **launch the rocket** (any payload). ★★★ requires a satellite launch (returns 1 000 orbital cards) under gold time. |
| par / gold | 180 min / 120 min |
| epilogue | credits; Freeplay unlock badge "Orbital"; prompt to continue in Freeplay with this map ("Continue sandbox") |

---

## 8. Freeplay

New-game screen with presets and advanced settings. All settings stored in the save.

| setting | options (default **bold**) |
|---|---|
| preset | **Default**, Rich resources (richness 200%), Marathon (tech price ×4), Rail world (later), Island, Custom |
| seed | random 32-bit (**random**), editable / copy |
| map size | Small 256×256, **Medium 512×512**, Large 1024×1024, Huge 2048×2048 (A15+/M1 devices only) |
| per resource (iron, copper, coal, stone, crude oil, uranium*) | frequency, size, richness: 17% / 33% / 50% / 75% / **100%** / 150% / 200% / 300% / 600% (1.1 slider range 1/6 … 6) |
| starting area | 50% / 75% / **100%** / 150% / 200% (scales guaranteed starting patches' radius & spawn safety ring) |
| water | coverage 0% (one starting lake still guaranteed) / 50% / **100%** / 200%; scale 50–200% |
| trees | coverage 0–200% (**100%**) |
| rocks | **on** / off |
| cliffs | phase 2.0 (off in MVP) |
| enemies | **Peaceful (none)** in MVP; phase 2.0: Off / Peaceful / Normal / Death world |
| tech price multiplier | 0.25 / 0.5 / **1** / 2 / 4 |
| day/night | **Normal (25 000 ticks)** / Perpetual day / Long nights |
| starting kit | **Standard** (8 iron plate, 10 wood, 1 burner drill, 1 stone furnace) / Extended (adds 4 burner drills, 4 stone furnaces, 50 coal, 100 iron plate) |
| research queue | **on** / off |
| casual reach | **off** / on |

*uranium appears only once the nuclear phase ships.

Freeplay victory: first rocket launch shows the victory screen ("Continue" keeps playing). Infinite research afterwards.

---

## 9. Upgrade paths

### 9.1 Entity tier chains (fast-replace in place; `next_upgrade` from 1.1 data)
| family | chain | notes |
|---|---|---|
| transport belt | transport_belt (15/s) → fast_transport_belt (30/s) → express_transport_belt (45/s) | same replace group as undergrounds/splitters |
| underground belt | underground_belt (max 5) → fast_underground_belt (7) → express_underground_belt (9) | |
| splitter | splitter → fast_splitter → express_splitter | |
| inserter | burner_inserter → inserter → fast_inserter → stack_inserter | 1.1 next_upgrade: inserter→fast→stack (burner not linked; [GF] allow burner→inserter replace) |
| filter inserters | filter_inserter → stack_filter_inserter | side-grade of fast/stack |
| long-handed | long_handed_inserter (no upgrade) | |
| mining drill | burner_mining_drill (2×2) → electric_mining_drill (3×3) | not in place (size differs); upgrade planner (1.1 phase) removes & rebuilds |
| furnace | stone_furnace → steel_furnace (2×2 burner) ; electric_furnace (3×3) | stone→steel in place |
| assembler | assembling_machine_1 → 2 → 3 | in place, keeps recipe (if category allowed) |
| electric pole | small_electric_pole → medium_electric_pole ; big_electric_pole ; substation | small→medium in place [GF] |
| chest | wooden_chest (16) → iron_chest (32) → steel_chest (48) | [GF] in-place replace keeps contents |
| pipe | pipe ↔ pipe_to_ground ↔ pump (same replace group) | |
| power | steam_engine → steam_turbine (nuclear phase) | same footprint 3×5 |
| modules | speed 1→2→3, efficiency 1→2→3, productivity 1→2→3 | swap in machine UI |
| armor (2.0) | light → heavy → modular → power → power MK2 | combat phase |
| logistic chests (1.2) | passive/active/storage/buffer/requester (side-grades) | |
| rail signals (1.3) | rail_signal ↔ rail_chain_signal | |

### 9.2 Repeatable / leveled research
| series | levels | effect | cost |
|---|---|---|---|
| research_speed | 1–6 | lab speed +20/+30/+40/+50/+50/+60 % | finite (04) |
| inserter_capacity_bonus | 1–7 | stack inserter hand → 12, other inserters → 3 | finite |
| mining_productivity | 1–3 finite, **4+ infinite** | +10 %/level | L4+: 2500×(L−3) units of R G B P Y W, 60 s |
| worker_robots_speed (1.2) | 1–5 finite, **6+ infinite** | +35/40/45/55/65 %, then +65 %/level | 1000×2^(L−6) |
| worker_robots_storage (1.2) | 1–3 | +1 cargo each | finite |
| braking_force (1.3) | 1–7 | +10 %, then +15 % each | finite |
| toolbelt | 1 | +10 inventory slots | finite |
| steel_axe | 1 | +100 % hand mining speed | finite |
| combat (2.0): physical_projectile_damage, weapon_shooting_speed, energy_weapons_damage, laser_shooting_speed, stronger_explosives, refined_flammables, follower_robot_count, artillery_shell_range, artillery_shell_speed | finite then infinite (04) | see 04 | see 04 |

Infinite techs in MVP: **mining_productivity** only (needs orbital cards ⇒ post-first-satellite). Freeplay "Infinite research" panel shows level, next cost, and cumulative bonus.

---

## 10. Settings screen

| section | settings |
|---|---|
| Graphics | Quality preset (Low / Medium / **High** / Ultra auto-detected by device); frame rate cap (30 / **60** / 120 ProMotion); render scale (75–100%); belt item rendering (**full** / simplified at far zoom); smoke & particles on/off; day/night lighting on/off; entity shadows on/off; animated water on/off |
| Interface | UI scale 80–140% (**100%**); show grid (**off** / on in build mode / always); alt-mode by default (**on**); show reach circle (**on**); tooltips delay; damage/number popups; left-handed layout; haptics (**on**); objective tracker (**on**) |
| Controls | joystick: floating/fixed, size, dead zone; tap-to-walk; one-tap place (device default); auto-walk to mine; two-finger twist rotate; casual reach (per save, shown here too); invert pan |
| Gameplay | autosave interval (off / 2 / **5** / 10 / 15 min); autosave slots (1–5, **3**); pause when menus open (campaign easy only); auto-build ghosts in reach; confirm area remove threshold (**20**) |
| Performance | simulation speed target (**60 UPS**); "Battery saver" (30 FPS render, 60 UPS sim); background behaviour (**pause & save**); max simulated entities warning; show FPS/UPS overlay (off) |
| Audio | master, music, SFX (factory ambience), UI volumes (0–100); music in background apps (mix with others) |
| Accessibility | colorblind-friendly palette (Off / Deuteranopia / Protanopia / Tritanopia — recolours ore map colours, power satisfaction, ghost valid/invalid (adds ✓/✕ glyphs), status icons use shapes not only colour); larger text; reduce motion; high-contrast belts/arrows |
| Language | English (MVP) — all strings localized through string tables from day 1 |
| About | credits, version, open-source licences, privacy (no data collected) |

---

## 11. Save system UX

- **Slots**: unlimited named manual saves (list with thumbnail, map name, play time, game time, last saved date, mode Campaign/Freeplay, level). Delete / rename / duplicate.
- **Autosave**: rotating `autosave_1..N` (N = setting, default 3) every interval (default 5 min game time); also on level objective completion.
- **Continue** button on the main menu loads the most recent save (manual or auto) of any mode.
- **Background**: on `applicationWillResignActive` pause simulation; on `didEnterBackground` write a quick save (`background.sav`) within the iOS background time budget (target < 1 s for Medium maps using incremental/chunked serialization on a background thread from a frozen snapshot); resume restores exactly. Crash recovery: if the last session ended without a clean save, offer "Restore background save".
- Saves are deterministic snapshots (simulation state + RNG seeds + map); version header for migration; compressed (LZ4/zstd). Target ≤ 20 MB for Large maps.
- iCloud sync (phase 1.1): one-way upload of manual saves + conflict prompt.
- Campaign progress (stars, best times, unlocks) stored separately from saves.

---

## 12. Audio & feel (brief)
- Ambient factory soundscape layered by nearby entity types (spatial, distance-culled); machine working loops; placement "clunk", belt hum, UI ticks; haptic tick on grid snap & placement (setting).
- Music: calm ambient tracks; adaptive intensity by factory size (later).

---

## 13. Later-phase core stats (summary; full specs when scheduled)

**Trains (1.3)** — rail grid 2×2; straight rail 2×2, curved rail; locomotive 2×6, 600 kW burner, 3 fuel slots, max 1.2 tiles/tick (259.2 km/h), weight 2000, braking force 10, air resistance 0.0075; cargo wagon 40 slots, weight 1000; fluid wagon 25 000 units (2.0: 50 000 — choose 25 000 for 1.1 parity); train stop, rail signal, chain signal; schedules (wait conditions: full/empty/time/inactivity). Techs: `railway` (loco, cargo wagon), `automated_rail_transportation` (train stop), `rail_signals`, `fluid_wagon`, `braking_force_1-7`. Note `rail` item is already in MVP (fabrication card ingredient).

**Robots (1.2)** — roboport 4×4 (logistics radius 25, construction radius 55, 4 charge pads × 1 MW, 7 robot + 7 repair slots, 100 MJ buffer, 5 MW input); logistic robot 3 t/s, construction robot 3.6 t/s, 1.5 MJ battery, payload 1–4. Five logistic chest types. Techs: `robotics` (frames; MVP), `construction_robotics`, `logistic_robotics`, `logistic_system`, `worker_robots_speed/storage`.

**Nuclear (1.5)** — uranium processing 10 ore → 0.7% U-235 / 99.3% U-238 (12 s); enrichment 40 U-235 + 5 U-238 → 41 U-235 + 2 U-238 (60 s); fuel cell 8 GJ; reactor 40 MW (+100% per neighbour); heat exchanger 10 MW → 103.09 steam/s @500 °C; turbine 5.82 MW.

**Circuits (1.4)** — combinators (1 kW), constant combinator 20 signals, wire reach 9.

**Hostiles (2.0)** — turrets (gun 18 range, laser 24, flamethrower 30, artillery 224), walls/gates 350 HP, defense cards, all military techs, pollution attacks, evolution (time 4e-6, destroy 0.002, pollution 9e-7 per unit — 1.1 map settings).

---

## 14. Monetisation
None. Premium up-front price; no IAP, no ads, no analytics beyond opt-in crash reports (Apple). Future expansions (if any) are paid DLC-free major updates (phases above are free updates).

---

## 15. Open design questions
1. Campaign pacing: tech price multipliers (0.75→0.5) and starting kits need playtesting; target total campaign ≈ 12–15 h.
2. Should Remove mode respect reach (10) by default? Proposed yes (walking matters), with Casual reach option.
3. Day/night length on mobile: keep 25 000 ticks or shorten? (Affects solar ratios; keep for parity.)
4. Pollution in MVP: proposed statistic-only (no diffusion) until enemies exist.
5. Crafting leftover-progress rounding: proposed carry-over (05 §3.1) — confirm with simulation lead.
6. Device floor: A14 (iPhone 12) for Medium maps; Huge only on A15+/M1.
