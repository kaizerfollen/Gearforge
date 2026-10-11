# 05 — Simulation Mechanics Specification

Audience: simulation engineers (FactoryCore), QA. Everything here is the behaviour Gearforge must reproduce. Numbers come from Factorio 1.1.110 prototype data (see 01–04) unless marked **(wiki)** = wiki.factorio.com, **(derived)** = computed from prototype values, or **(unverified)** = from memory/secondary source; QA should validate unverified items against a 1.1 reference save before locking. Where Gearforge intentionally deviates from 1.1 the rule is marked **[GF]**.

Global constants:

| constant | value |
|---|---|
| simulation rate | 60 ticks per second (UPS). All per-tick values assume 60 UPS. |
| tile | 1×1 world unit; chunk = 32×32 tiles |
| belt sub-position | 1/256 tile (integer math recommended everywhere on belts) |
| day length | 25 000 ticks (416.7 s) (unverified, 1.1 default `ticks_per_day`) |
| research queue | enabled (1.1 map setting `research_queue_setting = always`) |
| tech price multiplier | 1 (freeplay setting can change it) |

---

## 1. Transport belts

### 1.1 Geometry & speed
- Each belt tile has **2 lanes** (left/right relative to belt direction). Each lane of a straight tile is **256 positions** long.
- Minimum distance between consecutive items in one lane = **64 positions** (0.25 tile) ⇒ **4 items per lane per tile, 8 per tile**, independent of item type.
- Belt speed in positions/tick: yellow **8**, red **16**, blue **24** (= prototype speed 0.03125/0.0625/0.09375 tiles/tick × 256).
- Throughput per lane = 60 × speed / 64 = **7.5 / 15 / 22.5 items/s**; full belt = **15 / 30 / 45 items/s**.
- Curves: inner lane length **106** positions, outer lane **295** positions (wiki). Both lanes move at the same position speed, so items on the inner lane exit first; throughput and density are unchanged.
- Items are logically on exactly one tile at any moment (needed for inserter pickup and splitter/underground handoff).

### 1.2 Belt simulation model [GF recommended]
- Simulate belts as **transport lines**: maximal chains of connected belt tiles (straight, curve, underground pair, splitter in/out lanes) merged into one lane array per lane. Store items as a list of (gap-to-previous, item id). Each tick, only the **first gap** of a moving segment changes ("head-gap" algorithm) ⇒ O(1) per moving line per tick, not per item. This is how Factorio achieves belt UPS and is essential on mobile.
- A lane stops moving when its front item reaches the end of the line and the next line/entity cannot accept it. Compression: items close gaps until 64 apart; a gap < 64 is never created except where items are inserted at a gap ≥ 64.
- Belts consume no power and have no idle cost; a fully stopped line is put to sleep until its output end changes.

### 1.3 Joining belts
- **Straight continuation**: belt A feeding the back of belt B (same orientation or B turns) keeps lanes (left→left, right→right). If B is a curve it bends both lanes.
- A belt tile becomes a **curve** automatically when it has exactly one input belt coming from its side and none from behind (1.1 rule). With inputs from both sides (and none from behind) it stays straight and both are **sideloads**.
- **Sideloading**: belt A pointing into the side of belt B transfers **both lanes of A onto the single near lane of B** (the B lane on the side A comes from). Lane A-left and A-right merge alternately when there is room; the far lane of B is untouched. Insert point is early or late on the tile: sideload distance on a straight belt = **188** positions from tile start for the "early" half / **68** for the "late" half (wiki).
- **Sideloading onto an underground belt** (entrance or exit tile, from the side): only the half of the tile that is open belt accepts items, so only **one lane** of the feeding belt is transferred (the other is blocked by the hood). Classic "lane filter" trick — must be reproduced. (unverified exact lane: the feeding lane that lands on the open half; QA confirm with 1.1)
- Belt ending with no continuation: items stop at the end of the tile (lane blocked). Items are not dropped on the ground.

### 1.4 Underground belts
- Pair = entrance + exit of the same tier facing the same direction, max tile offset = `max_distance` **5 / 7 / 9** (gap 4 / 6 / 8 tiles). The entrance links to the **nearest** matching exit within range in its direction; other belts/undergrounds in between are ignored, except that a nearer matching-tier underground in the same direction would pair first.
- Each underground tile lane is 256 positions; the hidden section acts as normal belt of the same speed (items keep spacing).
- Lane behaviour: lanes preserved. An underground entrance accepts items only from the back (and sideload rule above).

### 1.5 Splitters
- 2×1 entity with 2 input belts and 2 output belts; lanes preserved (input left lane → output left lanes).
- **Default**: each lane is distributed **alternately 1:1** between the two outputs; if one output is blocked everything goes to the other. Inputs are drawn equally (alternate) from both inputs.
- **Input priority (left/right)**: take from the priority input first; the other input is used only when the priority one has no item available.
- **Output priority (left/right)**: send to the priority output; overflow to the other only when the priority output is blocked.
- **Filter** (one item type): matching items go to the selected output side; all other items to the other side. If the filtered side is blocked, matching items wait (they never go to the other side); non-matching items also never go to the filtered side.
- Splitter lane lengths: input 128 positions (+ up to 51 positions of hidden buffer), output 128 positions (wiki).

### 1.6 Items on belts by other actors
- **Inserter drop**: onto the **far lane** relative to the inserter (drop point is 0.2 tile past the tile centre). If the belt runs parallel to the inserter direction, the item goes onto the right-hand lane (belt perspective) (wiki). An inserter only drops when there is a gap ≥ 64 positions at its drop point on that lane; it enlarges a small gap by holding upstream items (i.e. items behind wait) — Gearforge may simplify to "wait for gap" [GF].
- **Drill output** onto a belt: inserted at the drill's drop vector position (lane = whichever lane the point lies in). Waits for a gap.
- **Player**: tapping a belt with an item in hand places the item onto the belt lane nearest the tap point.
- **Picking items up from belts by the player** (F-key equivalent): GDD — long-press a belt with empty hand picks up items on that tile (QoL).

---

## 2. Inserters

### 2.1 Motion
- Arm state = (angle, extension). Rotation speed in turns/tick and extension speed in tiles/tick from 03_entities. The hand moves angle and extension simultaneously; a movement segment ends when both reach target.
- Pickup at the tile behind (distance 1, or 2 for long-handed), drop 1.2 tiles (2.2 long) ahead.
- **Chest-to-chest cycle** = pickup swing + drop swing; each half-turn takes `ceil(0.5 / rotation_speed)` ticks (derived; matches 1.1 published values):

| inserter | half-turn ticks | cycle ticks | items/s at hand size 1 | at max bonus |
|---|---|---|---|---|
| burner_inserter | 50 | 100 | 0.60 | 1.80 (hand 3) |
| inserter | 36 | 72 | 0.83 | 2.50 (hand 3) |
| long_handed_inserter | 25 | 50 | 1.20 | 3.60 (hand 3) |
| fast_inserter / filter_inserter | 13 | 26 | 2.31 | 6.92 (hand 3) |
| stack_inserter / stack_filter_inserter | 13 | 26 | 2.31 | 27.69 (hand 12) |

- From/to belts throughput is lower (must wait for items / gaps). Gearforge reproduces it emergently; no table is required. QA reference (unverified, 1.1 wiki): fast inserter belt→chest ≈ 2.3 items/s on any belt at hand 1.

### 2.2 Hand size (stack bonus)
- Base hand size = 1 for every inserter.
- Non-stack inserters: +1 from `inserter_capacity_bonus_2`, +1 from `inserter_capacity_bonus_7` ⇒ **max 3**.
- Stack inserters: +1 `stack_inserter` tech, +1 each from capacity bonus 1–4, +2 each from 5–7 ⇒ **max 12** (1+1+4+6).
- Stack inserters only grab a single item type per swing.
- From chests/machines the inserter grabs up to hand size in one tick. From belts it picks items one by one as they pass its pickup tile until the hand is full; it leaves early if the target only needs fewer items (crafting machine insertion limit reached) (unverified detail).

### 2.3 Pickup rules
- Picks only items that the target can accept now (respects target insertion limits, filters, fuel/ammo slots). Never picks for a ghost/unpowered-absent target. If target is a belt or ground, picks anything (filtered inserters: whitelist).
- From belts: picks items that are on the pickup tile. Lane preference: perpendicular belt → nearest lane first, falls back to far lane; parallel/curve → left lane (belt perspective) first (wiki).
- From crafting machines: takes from **output** slots only (never ingredients or fuel). From furnaces: output only (and burnt result, e.g. depleted fuel cells from reactors).
- From labs: takes science cards (lab chaining) — lab-to-lab transfer allowed.
- From burner entities' burnt-result inventory (reactor) yes.

### 2.4 Insertion rules & limits (into machines)
Inserters automatically put items into the right inventory (ingredient / fuel / module? no – modules are never auto-inserted / ammo).

| target | items | auto-insertion limit |
|---|---|---|
| assembler / chemical plant / refinery / centrifuge / furnace | recipe ingredients | `amount × clamp(1 + ceil(1.166 × effective_speed / recipe_time), 2, 100)` crafts worth, per ingredient (wiki formula; 1.166 s ≈ one basic-inserter swing). e.g. gear (0.5 s) in assembler 1 (speed 0.5): 1+ceil(1.166×0.5/0.5)=3 crafts ⇒ 6 iron plates. |
| furnace (no recipe yet) | any smeltable item | furnace picks recipe from first inserted item; same limit thereafter |
| lab | cards needed by current research | `clamp(1 + ceil(1.166 / unit_time_effective), 2, 100)` units worth |
| boiler, burner drill, stone/steel furnace, burner inserter, reactor | fuel | **5** items (wiki; unverified for 1.1 but use it) |
| rocket silo | rocket part ingredients like assembler; satellite into rocket inventory (1) | — |
| chest / belt / ground | anything | until full (ground: 1 item per tile) |

- Inserters with hand size > 1, or several inserters, can overshoot the limit by up to one hand (allowed).
- Furnace auto-recipe: the furnace keeps its current recipe while it has ingredients or results inside; once input and output are empty it accepts a new smeltable item.

### 2.5 Burner inserter
- Burner energy source (chemical fuel, 1 slot). When it has no fuel and its hand holds fuel, or it picks up fuel, it **refuels itself first** (takes 1 fuel item into its own fuel slot) before delivering ("burner leech" of items in hand). `allow_burner_leech` (taking fuel out of another entity's fuel slot) is **false** in 1.1 base — do not implement.
- Initial placement: a burner inserter has a small starting energy so it can grab its first fuel (unverified) [GF: give 1 swing of energy on placement].

### 2.6 Power
- Electric inserters: draw `drain` permanently; while moving draw `(rotation_speed × energy_per_rotation + extension_speed × energy_per_movement) × 60` kW (03_entities "max kW"). Under brownout they move slower proportionally (§5.4).

---

## 3. Crafting machines (assemblers, furnaces, chemical plant, refinery, centrifuge, rocket silo)

### 3.1 Crafting progress
- Effective speed `s = crafting_speed × max(0.2, 1 + Σspeed_bonus) × electric_satisfaction` (burner: × 1 when fuelled, 0 when not).
- Craft duration (seconds) = `recipe.energy_required / s`. Progress per tick = `s / (60 × energy_required)`.
- A craft **starts** only when (a) all ingredients present, (b) the results of one craft fit in the output slots (see 3.3), (c) energy available. Ingredients are **removed at craft start**. Results are added when progress reaches 1.
- 1.1 discards leftover progress at craft completion (crafts effectively round up to whole ticks) (unverified). **[GF]**: carry leftover progress into the next craft so ratios are exact (simpler for ratio calculators; UPS-neutral).
- Max 1 craft completion per machine per tick (cap extremely fast recipes; irrelevant with base values except heavily-beaconed gears).

### 3.2 Inputs
- Each ingredient has its own input slot; no stack-size cap on input slots for automated insertion (limit is the insertion rule in 2.4). Player can manually insert up to a stack per slot.
- Fluid ingredients: machine's input fluid box (see §7). Assembler 2/3 have **one** fluid input + **one** fluid output box which are only connected while a fluid recipe is selected.
- Changing the recipe returns all ingredients/results to the player's inventory (or spills on ground if full) [GF: spill into a temporary "returned items" chest if inventory full].

### 3.3 Output stall
- Each result has an output slot capped at the item's **stack size**. A craft will not start if `current + result_amount > stack_size` for any item result (unverified exact; behaviour: assembler with no output extraction stops when output reaches one full stack, e.g. 100 gears).
- Fluid results: craft does not start if the output fluid box cannot take the full result (output must be drained by pipes).
- Multi-result recipes (advanced oil processing) stall if **any** output is full ⇒ classic "petroleum backs up" mechanic; must reproduce.

### 3.4 Productivity bar
- Total productivity `p = Σ module productivity` (≥0; from modules only — beacons cannot carry productivity) (+ mining productivity research for drills only).
- After each completed craft, `bar += p`; while `bar ≥ 1`: produce one extra full set of results (no ingredients consumed) and `bar -= 1`. The bar is shown under the progress bar in the machine UI.
- Productivity is allowed only on the 43 recipes in the 1.1 whitelist (02_recipes "prod" column; `productivity-module.limitation`): smelting (iron, copper, steel, stone brick), oil processing (basic, advanced, coal liquefaction) & cracking, solid fuel ×3, sulfuric acid, sulfur, lubricant, plastic, empty barrel, copper cable, iron stick, gear, electronic/advanced circuit, processing unit, engine & electric engine unit, battery, explosives, flying robot frame, low density structure, rocket fuel, rocket control unit, rocket part, uranium processing, uranium fuel cell, enrichment, nuclear fuel reprocessing, nuclear fuel, all six craftable science cards (mechanics, motion, defense, reaction, fabrication, systems). Not allowed: buildings, modules, equipment, ammo, barrel fill/empty, landfill, concrete, rails, satellite.

### 3.5 Energy
- Electric: working draw `energy_usage × max(0.2, 1 + Σconsumption_bonus)` + permanent `drain` (energy_usage/30 for crafting machines when not explicit).
- Burner: fuel buffer; consumption `energy_usage / effectivity` while working; nothing when idle (no drain).
- Pollution per minute (`emissions_per_minute`) × (1 + Σpollution, min 0.2) × consumption multiplier — optional system (§13).

### 3.6 Furnaces
- Smelting recipes: iron ore→iron plate (3.2 s), copper ore→copper plate (3.2 s), stone×2→stone brick (3.2 s), iron plate×5→steel (16 s). Recipe auto-selected (2.4). Steel needs 5 plates; furnace input limit uses steel recipe values.
- Stone furnace 90 kW burner, speed 1; steel furnace 90 kW, speed 2; electric furnace 180 kW (+6 kW drain), speed 2, 2 module slots.

---

## 4. Mining

### 4.1 Rates
- Drill mining rate (items/s) = `mining_speed × s_mod × (1 + productivity) / resource.mining_time`, where `s_mod = max(0.2, 1 + Σmodule speed)` × satisfaction (electric) and productivity = modules + mining productivity research (+10%/level).
- Base: burner drill 0.25/s on ore/coal/stone; electric drill 0.5/s (uranium 0.25/s); mining time is 1 s for iron/copper/coal/stone, 2 s for uranium.
- Mining productivity research applies to **all drills including pumpjacks** (bonus bar per mined item); not to hand mining.

### 4.2 Area and output
- Mining area square centred on drill: burner 2×2 (exactly its footprint), electric 5×5, pumpjack 1×1 (the single oil tile under its centre).
- A drill can be placed only if its area contains at least one tile of a resource it can mine.
- Each cycle the drill mines from one resource tile in its area (round-robin / any; 1.1 picks tiles in a fixed order — implementation choice [GF: iterate tiles in area in fixed order, skip empty]). If the area holds mixed ores the output is mixed.
- Output: placed at `vector_to_place_result` (front edge of drill, rotated with direction): onto a belt (lane by position), into any entity with an inventory there (chest, furnace input, another burner drill's fuel slot if fuel, assembler ingredient), or onto the ground (one item; the drill waits until the item is removed). Burner drill feeding coal into another burner drill's fuel slot is a classic pattern — must work.
- Drill stops (status "out of resources") when all tiles in area are depleted; electric drill keeps its drain.

### 4.3 Depletion
- Solid resources: each mined item (excluding productivity bonus items) subtracts 1 from the tile's amount; tile removed at 0. Productivity bonus output does not deplete.
- **Crude oil (infinite resource)**: tile amount `A` (normal = 300 000 ⇒ 100% yield). Pumpjack output per cycle = `10 × A / 300 000` crude oil units (i.e. 10/s at 100%). Each cycle reduces A by `infinite_depletion_amount = 10` until `minimum = 60 000` (20% yield floor ⇒ 2 oil/s per pumpjack forever). Modules/beacons/prod apply.
- **Uranium ore** requires **sulfuric acid**: prototype `fluid_amount = 10` is per 10 ores ⇒ **1 acid per uranium ore** (wiki: "10 sulfuric acid per 10 ore mined"; productivity bonus ore consumes no acid). Electric drill has an input fluid box (capacity 200 (unverified)) with pipe connections on 3 sides (left, right, back); it stops if acid is missing.

### 4.4 Hand mining (character)
- Rate = `0.5 × (1 + character mining speed bonus [steel axe +100%]) / mining_time` per item ⇒ ore 2 s/item, 1 s with steel axe; trees 0.55/0.5 = 1.1 s; big rock 4 s (20 stone).
- The character can mine a resource tile/tree/rock within **2.7** tiles (reach_resource_distance) **[GF: mobile — tap-and-hold on resource within 2.7 tiles, or auto-walk to it]**. Entities (player-built) can be picked up within reach distance 10; picking up a building takes its `mining_time` / 0.5 (≤ 0.6 s) — **[GF]** make player-building pickup instant (keep hand-mining time only for resources/trees/rocks).
- Hand mining a resource tile depletes 1 per item; produces items into inventory; stops if inventory full.

---

## 5. Electric network

### 5.1 Topology
- A network = poles connected by copper wire (auto-wired on placement: connect to nearest poles within the smaller wire reach of the two, max **5 connections** per pole, never forming a triangle of 3 mutually connected poles) (wiki). Manual wiring/unwiring via pole UI [GF].
- An entity is connected to a network if any tile of its collision box overlaps any pole's supply area. If it overlaps several networks it is connected to **all** of them (1.1: it draws from whichever... keep simple [GF]: assign the entity to the first network found; poles in overlapping supply areas but not wired are separate networks).
- Each network is solved independently once per tick.

### 5.2 Producer/consumer classes (1.1 `usage_priority`)
| class | entities |
|---|---|
| solar (highest-priority producer) | solar panel |
| secondary-output (steam) | steam engine, steam turbine |
| tertiary (storage) | accumulator |
| primary-input (served first) | rocket silo, laser turret (combat) |
| secondary-input (normal consumers) | assemblers, furnaces, drills, inserters, labs, beacons, radar, lamps, pumps, roboports, chemical plant, refinery, centrifuge |

### 5.3 Per-tick solve (derived from 1.1 behaviour)
1. Demand `D1` = Σ primary-input requests, `D2` = Σ secondary-input requests. Each consumer requests `drain + (working ? usage : 0)` for this tick (energy units: kW / 60 = kJ/tick), plus buffer refill for buffered consumers (roboport, accumulators not included).
2. Supply order: solar `S` (= Σ panel output at current daylight) → steam `G` (= Σ min(max_power, power available from steam in fluid box)) → accumulators `A` (= Σ min(300 kW, stored)).
3. Serve D1 first, then D2. Use solar fully first, then steam (each generator throttled proportionally: all engines/turbines share the remaining demand equally as fraction of their max), then accumulator discharge (equal share).
4. Satisfaction `σ = min(1, served / requested)` for each priority class. Every consumer receives `σ × request`.
5. Surplus (solar + steam capacity unused) charges accumulators up to 300 kW each (steam engines only burn steam for what is actually used: unused capacity consumes no steam ⇒ boilers throttle).
6. Steam generators consume steam proportional to the power they produce: steam engine 30 units/s at 900 kW at 165 °C (energy per unit = (T−15)×0.2 kJ).

### 5.4 Brownout
- Electric machines' speed scales linearly with satisfaction σ (crafting, mining, research, inserter arm speed, pump speed, radar scan, beacon still transmits full effect? — 1.1: beacons with low power reduce their effect proportionally (unverified); [GF]: beacon effect × σ).
- Drain is part of the request, so idle machines still draw drain under brownout.
- UI: power pole/entity shows satisfaction bar (green ≥100%, yellow 50–99%, red <50%) and "Low power" icon blinking on entities below 100%.

### 5.5 Solar & day/night
- Day cycle 25 000 ticks (unverified 1.1 default). Daylight phases as fraction of day (unverified, 1.1 defaults): full daylight 0.75→0.25 (50%), dusk 0.25→0.45 (linear down to 0), night 0.45→0.55 (0), dawn 0.55→0.75 (linear up). Solar output = 60 kW × daylight ⇒ average **42 kW** (70%).
- Classic ratio **25 panels : 21 accumulators** (0.84 per panel; wiki gives 0.84672 per panel). 1 MW constant ≈ 23.8 panels + 20 accumulators.
- [GF option] "Perpetual day" world setting for casual players.

### 5.6 Accumulator
- 5 MJ buffer, charge/discharge ≤ 300 kW each. Discharges only when solar+steam can't meet demand; charges only from surplus.

---

## 6. Burner energy & fuel
- Burner entity has `fuel_inventory_size` slots (1 for most, 3 for locomotive) and an internal heat buffer. When the buffer is empty and the entity needs energy, it consumes one fuel item: buffer += fuel_value × effectivity (effectivity 1 for all base burners except car 0.6, tank 0.9... vehicles later).
- Consumption while working = energy_usage (burner drill 150 kW, stone/steel furnace 90 kW, boiler 1.8 MW, burner inserter per movement).
- Fuel values: wood 2 MJ, coal 4 MJ, solid fuel 12 MJ, rocket fuel 100 MJ, nuclear fuel 1.21 GJ (chemical); uranium fuel cell 8 GJ (nuclear only, reactor).
- Burn durations (derived): coal in stone furnace 44.4 s; in burner drill 26.7 s; in boiler 2.22 s.
- Burnt result: uranium fuel cell → depleted fuel cell into burnt-result slot (reactor). Reactor stops when burnt slot is full.
- Inserters treat the fuel slot as a separate target (2.4).

---

## 7. Fluid system

### 7.1 Factorio 1.1 model (for reference)
- Every entity with fluids has one or more **fluid boxes**: volume = base_area × 100 × height (pipe 100, pipe-to-ground 100, storage tank 25 000, boiler 200 in/200 out, steam engine 200, pump 400, offshore pump 100, assembler/chem plant/refinery input 1000, outputs 100–1000; see 03).
- Per tick, fluid flows between connected adjacent boxes driven by the difference in fill level ("pressure"), with a momentum term (previous flow) and per-connection caps. Consequence: throughput falls with pipeline length. Max flow vs number of pipe segments between pumps (wiki, 1.x):

| pipes between pumps | max flow units/s |
|---|---|
| 0 (pump→pump, tank→pump) | 12 000 |
| 1 | 6 000 |
| 2 | 3 000 |
| 3 | 2 250 |
| 7 | 1 500 |
| 12 | 1 285 |
| 17 | 1 200 |
| 20 | 1 169 |
| 30 | 1 112 |
| 50 | 1 067 |
| 100 | 1 033 |
| 150 | 1 022 |
| 200 | 1 004 |
| 261 | 800 |
| 300 | 707 |
| 400 | 546 |
| 500 | 445 |
| 1000 | 230 |

  (pipe-to-ground pair counts as 2 pipes.) Cost: every box simulated every tick — expensive.

### 7.2 Gearforge model: Factorio 2.0-style **segments** [GF — recommended]
- **Segment** = maximal set of connected pipes, pipe-to-grounds and storage tanks carrying one fluid (pumps, machines, boilers, offshore pumps are *not* part of a segment; they are endpoints). A segment stores a single `(fluid, amount, capacity, temperature)` where capacity = Σ member volumes. Rebuild segments only on build/remove events (union-find).
- Flow inside a segment is instantaneous (no per-pipe simulation).
- Each endpoint connection (machine fluid box ↔ segment) transfers per tick up to the **per-connection cap 100 units/tick (6 000/s)** (wiki 2.0: "theoretical 6000/s, ~4200/s in practice"):
  - Producers (offshore pump 20/tick, boiler steam out, pumpjack, refinery/chem outputs) push into the segment while it has space.
  - Consumers (machine inputs, boilers' water in, steam engines) pull from the segment while they need fluid; when demand exceeds supply, distribute the available amount **proportionally to each consumer's request** (2.0 behaviour: equal share among unblocked sockets).
  - Pump = directional link between two segments, moving up to 200 units/tick (12 000/s) from input segment to output segment, limited by output space; only when powered (× satisfaction).
- Segment size limit: a segment may not exceed **320 tiles in extent (10×10 chunks)** — 2.0 makes oversized segments stop flowing; [GF]: show an "add a pump" warning instead.
- Mixing: forbid building a pipe/connection that would join segments with different fluids (show red ghost + reason). Empty segments take the fluid of the first input. A segment can be flushed (UI button) to empty it.
- Temperature: segment temperature = amount-weighted average on merge; only matters for water/steam (boiler steam 165 °C, exchanger 500 °C). Steam engine produces power proportional to min(T,165)−15; turbine min(T,500)−15.
- Removing a pipe splits the segment; contents are distributed to the new segments proportionally to their capacity.
- Benefits: O(segments + endpoints) per tick; deterministic; predictable throughput (no length falloff) — strongly preferred for mobile UPS and for player understanding.

### 7.3 Fluid-specific entities
- Offshore pump: 1200 water/s, no power, placed on shoreline.
- Boiler: water in (pass-through 2 connections), steam out (1 connection); burns fuel only when it can output steam.
- Underground pipe: max offset 10 tiles (9-tile gap).
- Storage tank 3×3, 25 000 units, 4 connections (2 orientations).
- Barrels: 50 units per barrel (fill/empty recipes in assembler 2/3, 0.2 s).

---

## 8. Boilers & steam power
- Boiler converts water (15 °C) to steam at 165 °C: steam/s = 1800 kW / ((165 − 15) × 0.2 kJ) = **60/s** at full load. Consumes fuel in proportion to steam produced (throttles when engines don't need steam).
- Steam engine: up to 30 steam/s ⇒ 900 kW. Turbine: up to 60 steam/s at 500 °C ⇒ 5.82 MW.
- Layout ratio: 1 offshore pump (1200/s) : 20 boilers (20 × 60 = 1200 water/s) : 40 engines (36 MW).
- Nuclear (later phase): reactor 40 MW heat, max 1000 °C; neighbour bonus +100% per adjacent **operating** reactor (heat connections aligned). Output = 40 MW × (1 + number of working neighbours). Examples: 1 reactor 40 MW; 2 in a row 2×80 = 160 MW; 2×2 block (each has 2 neighbours) 4×120 = 480 MW; 2×4 block 1120 MW. Heat exchanger needs ≥ 500 °C; heat pipes transfer heat by temperature gradient (heat model spec deferred to nuclear phase).

---

## 9. Labs & research
- One active technology per force. Research queue (up to 7 entries [GF], reorderable). Switching research keeps partial progress on the old tech (1.1).
- Each lab works on the current tech if it contains ≥1 of every card type the tech's unit requires. A lab starts a **unit** by consuming one set of the unit's cards (1 of each listed card × amount) **[GF: card durability dropped — consume at unit start]**, then progresses for `unit_time / (lab_speed × (1 + lab_speed_bonus) × max(0.2, 1 + Σmodule_speed) × σ)` seconds. Lab speed bonus (research) and module speed are **multiplicative** (wiki).
- Productivity modules in labs: the 1.1 lab prototype has no `allowed_effects` restriction (default = all effects), so productivity modules are accepted; each finished unit adds the productivity bonus to the bar; at bar ≥ 1 one extra unit of progress is granted (bar mechanics for labs unverified; QA). [GF] allow.
- Total research progress across labs: the tech completes when Σ completed units ≥ count. Units in progress when the tech completes are lost (1.1 refunds nothing; [GF]: in-progress cards are refunded — avoid waste).
- Labs pass cards to adjacent labs via inserters (2.3).
- Lab speed bonus levels: research_speed_1..6 = +20, +30, +40, +50, +50, +60 % (total +250%).
- Infinite techs: cost per formula (04); research continues level after level automatically if queued.

---

## 10. Modules & beacons
- Module values (1.1):

| module | speed | productivity | consumption | pollution |
|---|---|---|---|---|
| speed_module 1/2/3 | +20/+30/+50 % | – | +50/+60/+70 % | – |
| efficiency_module 1/2/3 | – | – | −30/−40/−50 % | – |
| productivity_module 1/2/3 | −5/−10/−15 % | +4/+6/+10 % | +40/+60/+80 % | +5/+7/+10 % |

- Effects are **additive** across all modules in the machine plus all beacons affecting it: `E_x = Σ_machine module_x + Σ_beacons (0.5 × Σ beacon module_x)` (distribution effectivity 0.5, **no diminishing returns** in 1.1 — 2.0 introduced √n scaling; keep 1.1).
- Caps: speed multiplier `max(0.2, 1 + E_speed)`; consumption multiplier `max(0.2, 1 + E_consumption)` (efficiency can reduce power to 20% min); pollution multiplier `max(0.2, 1 + E_pollution)`; productivity `max(0, E_prod)`.
- Beacon: 3×3, 480 kW, 2 module slots, accepts speed & efficiency modules only (no productivity). Affects every machine whose collision box overlaps the 9×9 area centred on the beacon (supply_area_distance 3 from its edge). A machine can be affected by any number of beacons.
- Productivity modules only in machines running whitelisted recipes (3.4); inserting into a machine with a non-whitelisted recipe is refused (and changing recipe to a non-whitelisted one ejects prod modules).
- Mining drills (3 slots electric, 2 pumpjack), furnaces (electric 2), assemblers (2/3: 2/4), chemical plant 3, refinery 3, centrifuge 2, lab 2, rocket silo 4, beacon 2.
- Modules are inserted manually (player) only in MVP (no inserter auto-insertion of modules).

---

## 11. Handcrafting
- Character crafting categories: `crafting` only and no fluids. Crafting speed 1.0 (recipe time in seconds).
- Queue: FIFO list of (recipe, count). Ingredients are removed from inventory **when queued**; cancelling refunds them (intermediates already crafted are refunded as intermediates, not uncrafted).
- **Auto-intermediate crafting**: if the player lacks an ingredient that is itself handcraftable and its raw materials are available, the needed intermediates are queued first automatically (recursive). The UI shows craftable count including chain-crafting. Non-handcraftable ingredients (e.g. plates, plastic, engine unit — engine is `advanced-crafting`) must already be in inventory.
- Crafting pauses if the result can't fit into the inventory.
- [GF] UI amounts: tap = 1, long-press = 5, "max" button = all; queue panel with per-entry cancel.

---

## 12. Character
- Movement 0.15 tiles/tick (9 tiles/s) × tile speed modifier (concrete 1.4, refined concrete 1.5, stone path 1.3). Collision box 0.4×0.4.
- Reach 10 (open/insert/build), resource reach 2.7, pickup items on ground within 1 (auto-loot 2). Inventory 80 slots (+10 toolbelt). Mining speed 0.5.
- Build distance 10. [GF] On mobile the build radius is shown as a faint circle in build mode; placing beyond it creates a **ghost** that the character builds automatically when it walks within reach (if the item is in inventory) — see GDD §Controls.
- Health 250, regen 0.15/tick after 600 ticks out of combat — only relevant in combat phase.

---

## 13. Pollution (optional; recommended OFF in MVP)
- Each entity emits `emissions_per_minute` (03 tables) × modifiers into its chunk. Per 64 ticks: chunks with > 15 pollution diffuse 2% to each of 4 neighbours; tiles absorb (grass 7.5e-6/tick per tile, desert 6.6e-6, sand 5.8e-6, water 5e-6, concrete 0); trees absorb (−0.001/s typical) and are damaged above 60.
- Pollution only matters for enemies (attack waves) and visuals. **MVP: compute total pollution/min statistic only** (no diffusion map). Full system in combat phase.

---

## 14. Resource generation (map gen)
- Resources: iron, copper, coal, stone (solid, `basic-solid`), crude oil (fluid, `basic-fluid`), uranium (solid, needs acid). 1.1 autoplace parameters (core/lualib/resource-autoplace.lua + resources.lua):

| resource | base_density | spots/km² | starting-area patch | rq factor (regular / start) | notes |
|---|---|---|---|---|---|
| iron_ore | 10 | 2.5 | yes | 1.10 / 1.5 | |
| copper_ore | 8 | 2.5 | yes | 1.10 / 1.2 | |
| coal | 8 | 2.5 | yes | 1.0 / 1.1 | |
| stone | 4 | 2.5 | yes | 1.0 / 1.1 | |
| crude_oil | 8.2 | 1.8 | no | 1.0 | spots of 1–? single-tile wells; additional_richness 220 000 per well |
| uranium_ore | 0.9 | 1.25 | no | 1.0 | random spot size min 2 |

- Starting area: guaranteed one patch each of iron, copper, coal, stone within a radius of **120 tiles** of spawn (`starting_resource_placement_radius`), no oil/uranium; always a lake near spawn; no cliffs. Regular patches fade in from 120 to 420 tiles (fade-in distance 300). Patch quantity (density) grows linearly with distance: ×2 at 1300 tiles beyond the fade-in, after which richness keeps growing instead of size. Patch radius ≤ 32 tiles.
- Map-gen sliders (Freeplay): frequency, size, richness multipliers per resource (1.1 range 1/6 (17%) … 6 (600%)); richness multiplies amount per tile.
- **[GF] mobile generation**: maps are finite (see GDD sizes). Generate with deterministic seeded noise; guarantee start patches with these target amounts at default settings (unverified targets, tuned for 1.1-like feel): iron 400–600k total, copper 300–450k, coal 300–450k, stone 150–250k, all within 30–90 tiles of spawn, plus 1 water lake within 40 tiles; first oil field (4–8 wells, 200–500% yield each) at 150–300 tiles; uranium 300–600 tiles.
- Trees (wood 4, mining 0.55 s) and rocks (big rock 20 stone; huge rock 24–50 stone + 24–50 coal) scattered; give players an early stone/coal source.

---

## 15. Logistic robots & roboports (later phase summary)
- Roboport 4×4: logistics area 50×50, construction area 110×110; 7 robot slots, 7 repair slots; 4 charging pads at 1 MW each; buffer 100 MJ, input 5 MW; idle 50 kW.
- Robots: logistic 0.05 tiles/tick (3 t/s), construction 0.06 (3.6 t/s); battery 1.5 MJ; 3 kW hover + 5 kJ/tile; payload 1 (+1 per worker robot storage level, max 4); speed bonus techs +35/40/45/55/65/65 % then infinite +65%/level. Out of energy → 20% speed; seek charge at < 20% battery.
- Chests: passive provider (supplies on request), active provider (pushes out to storage), storage (sink), requester (requests items), buffer (requester that also supplies). Logistic network = union of roboport logistic areas connected by overlapping.
- Construction robots build ghosts / deconstruct marked entities / repair. Personal roboport (armor grid) — combat/equipment phase.
- Implementation note: robot movement is straight-line flight; can be simulated analytically (start/end time) without per-tick position updates (UPS).

---

## 16. Rocket launch & victory
- Rocket silo (9×9, 250 kW idle + 3990 kW active, crafting speed 1, 4 module slots) crafts `rocket_part` (3 s; 10 rocket control unit + 10 low density structure + 10 rocket fuel each). **100 parts = 1 rocket** ⇒ per rocket: 1000 RCU, 1000 LDS, 1000 rocket fuel; base build time 300 s + launch cycle.
- When 100 parts are done, the rocket rises (preparation ≈ 890 ticks (wiki)); insert a satellite (optional in 1.1) into the rocket inventory; press **Launch** (or auto-launch toggle). Launch animation ≈ 1162 ticks, door reset ≈ 368 ticks (wiki, 2.0 base-game figures; unverified for 1.1).
- Satellite payload returns **1000 orbital cards** into the silo result slot (inserter-extractable) at launch.
- **Victory (1.1)**: the first rocket launch, with or without satellite, wins the game (campaign final level victory). Freeplay continues afterwards.

---

## 17. Trains (later phase summary)
- Rail grid 2×2; straight rail 2×2, curved rail on a larger footprint. Locomotive 2×6 (joint 4 / connection 3), 600 kW burner (3 fuel slots), max 1.2 tiles/tick (259.2 km/h), weight 2000, braking force 10; cargo wagon 40 slots, weight 1000; fluid wagon 25 000 units (1.1; 2.0 = 50 000).
- Fuel modifiers: solid fuel accel ×1.2 top ×1.05; rocket fuel accel ×1.8 top ×1.15; nuclear fuel accel ×2.5 top ×1.15 (01_items).
- Signals: block signals & chain signals, block reservation, train stops & schedules. Full spec deferred to trains phase.

---

## 18. Determinism & performance notes for FactoryCore
- Fixed-step 60 Hz simulation, decoupled from rendering; all logic integer or fixed-point where possible (belts integer 1/256; energy in J as Int64 or Double with deterministic order).
- Entity update order deterministic (by creation id). Sleep/wake: inactive entities (full output, no input, no power) are removed from the active list until a neighbour event.
- Electric networks, fluid segments and belt transport lines are each solved as aggregates, not per entity.
- Target: 5 000 active entities at 60 UPS on A15-class devices; degrade gracefully (simulation slowdown, never desync) beyond that.
