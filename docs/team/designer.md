# Game Designer: pre-built campaign factories (L5–L8)

GDD §7 says L5–L8 start with a working factory. The factory is generated in code by
`Core/Sources/FactoryCore/Progression/Prebuilt.swift` (`PrebuiltFactory.build(levelID:in:near:)`).
`GameSession.newCampaign` calls it when `LevelDefinition.prebuilt` is true. That flag is set on L5–L8, and a level
that was saved without the key decodes it as `false`. Tests are in `Core/Tests/FactoryCoreTests/PrebuiltTests.swift`.

## How the factory is placed

* The factory needs a rectangle of about 110–135 × 21–35 tiles, depending on the level. It goes on one side of
  spawn (east, south, west or north) with a gap of 15 tiles. The side chosen is the one whose rectangle covers the
  fewest resource and water tiles, so the starting ore patches are left alone where possible.
* Inside the rectangle, every tile is set to `grass_1`. Trees and rocks are removed and resources are cleared. Then
  the stamper adds the ponds for the offshore pumps and the crude wells for the pumpjacks.
* Every placement goes through `World.placementError` (the full build rules, including shoreline, resource and
  fluid mixing). Any failure is listed in `Report.failures`, and the tests require that list to be empty.
* Everything is stamped from module functions that use factory-local coordinates. The per-level counts are in
  `PrebuiltFactory.plan(for:)`.

## Levels

The table shows what each level gets. The rates were measured by simulation (`testLongRunProfile`, 90 game minutes, release build).

| Level | Power | Science (machine) | Oil | Labs | Measured cards/min | Runs for |
|---|---|---|---|---|---|---|
| L5 | 11 boilers / 22 engines = **19.8 MW** (demand 1.1 MW) | 3 red + 4 green cells (asm 2) | none | 10 | red 27, green 30 | 60 min |
| L6 | 12 / 24 = 21.6 MW (demand 2.6 MW) | L5 + 2 blue modules (asm 2) | **basic**: pumpjack → refinery → plastic + sulfur | 10 | red 27, green 30, blue 7.5 | 60 min |
| L7 | 12 / 24 = 21.6 MW (demand 2.6 MW) | same as L6 | **advanced**: water + crude, heavy and light oil into tanks | 10 | red 27, green 30, blue 7.5 | 60 min |
| L8 | 16 / 32 = 28.8 MW (demand ≈ 8.5 MW) | 3 red, 4 green, 2 blue, 2 purple, 2 yellow (asm 3) | advanced | 10 | red 45, green 50, blue 12.5, purple 21.6, yellow 21.6 | 45 min |

The CI tests run each level for 1.5 min of warm-up and then a 2–2.5 min window. They check:

* power satisfaction is at least 0.9;
* every engine, assembler, lab, inserter and drill is on the plant network;
* card rates meet the floors: L5 red and green ≥ 20/min, L6 and L7 add blue ≥ 5/min, L8 has red and green ≥ 30, blue ≥ 8, purple and yellow ≥ 12;
* petroleum (and heavy and light oil on L7) is actually produced;
* the session survives `encodePayload` / `decode` and keeps running.

Each level test takes 10–17 s in a debug build.

When the supply chests run dry, the lines stop. If no research was running, the belt-end store (3 × 48 × 200 = 28 800
cards) then holds about 3 400 cards (L5) to 6 800 cards (L8). From then on the player has to feed the lines from real mining and smelting.

## Modules (ASCII, local coordinates, y grows south)

### Steam block (`steamBlock`, N boilers)
```
y 3   P . . . . P . . . . . P          P = medium pole (rows y3 and y16, plus a column at the right edge)
y 4   . . . E E E E E E E E E          E = steam engine 3×5, two per boiler column (y4–8 and y9–13)
y14   ~ ~ o - B B B B B B B B P        ~ water, o offshore pump (west), - pipe, B boiler 3×2 (water chains through)
y16   . . . . P i . . i . P i          i = inserter feeding coal into its boiler
y17   . . . . . C . . C . . C          C = iron chest with 800–1200 coal (+50 pre-loaded in every boiler)
```
Each boiler with its two engines gives 1.8 MW. The pole row at y16 is what powers the lower engines.

### Science cell (`scienceCell`, 5 wide; red, green, purple, yellow)
```
y0    . A . . .     A  = supply chest (stage A ingredients)
y1    . i . . .     i  = fast inserter
y2   [asm A] i A2   stage A: gears (red), inserters (green), rails (purple), robot frames (yellow); A2 = overflow chest
y3   [asm A] P .
y4   [asm A] . .
y5    . i . . .
y6   [asm B] j T3   stage B: the science card; T/T2/T3 = supply chests for the other ingredients
y7   [asm B] j T
y8   [asm B] j T2
y9    . o . P .     o = inserter onto the belt
y10   = = = = =     science belt (east)
```
Chest contents are computed from the recipes for `minutes` of full-speed running. If they would overflow the
chests, everything is scaled down together.

| Cell | Assembler A (automated) | Chest A | Chest T |
|---|---|---|---|
| red | iron gear wheel | iron plate | copper plate |
| green | inserter | circuits, gears, iron plate | transport belt |
| purple | rail | stone, iron stick, steel | electric furnace, productivity module |
| yellow | flying robot frame | electric engine, battery, steel, circuits | low density structure, processing unit |

### Blue module (`blueModule`, 16 wide, below the belt)
```
y-2   = = = = = = = = = = = = = = =    science belt (cards come up through the inserter at y-1)
y0   [CP ] i [AC ] i [BLU] i [ENG]     CP = chem plant (plastic, facing south), AC = adv. circuits, ENG = engine units
y3    c . | P i . . . i . . P i .      c = coal inserter, | petroleum pipe, P = poles (plus one at x+7,y-1)
y4    C . | . S . . [CPs] . . S ~      C = coal, S = circuits+cable / steel+gears+pipes, CPs = chem plant (sulfur)
y7    . . | . . . . . | . - w ~ ~      w = offshore pump (east) into a pond; - = water pipe into the sulfur plant
y9    = = + = = = = = +                petroleum header (shared by all modules, fed by the refinery)
```
One blue assembler is fed by one AC assembler, one engine assembler and the sulfur plant (direct insertion).
That gives 3.75 cards/min with asm 2 and 6.25 cards/min with asm 3 per module.

### Oil block (`oilBlock`, west of the first blue module)
```
basic (L6):      refinery 5×5 (basic oil processing) fed directly by a pumpjack on a placed crude well (200 % yield)
                 gas output → pipe → header
advanced (L7/8): pumpjack → pipe → refinery box 1; offshore pump + pond → refinery box 0 (water)
                 heavy oil → storage tank (west), light oil → storage tank (north-west), gas → header
```

### Lab row and card store (`labRow`)
```
y8   [LAB] P [LAB] P ...   . C          labs above and below the belt in pairs every 4 tiles
y11   . i . . . i . .  .   . f          i = inserter belt → lab
y12   = = = = = = = = ...  = f C        end of the belt: 3 fast inserters → 3 steel chests (the card store)
y13   . i . . . i . .  .   . f
y14  [LAB]   [LAB]   ...   . C
```
The belt carries all card types mixed together. Lab inserters only take cards for the current research. Anything
else goes to the store at the belt end, so the lines never stall while no research is selected.

## Automated vs fed from chests

* **Fully automated:** steam power (coal comes from chests), oil (pumpjacks on wells placed under them, refinery,
  chemical plants for plastic and sulfur), the stage-A intermediates listed above, every science assembler, and the
  belt → labs → store chain.
* **Fed from chests (finite):** all plates, circuits, copper cable, steel, pipes, transport belts, coal, and the
  high-tier intermediates for purple and yellow (furnaces, prod modules, LDS, processing units, electric engines,
  batteries). There is no mining or smelting in the pre-built factory. Connecting real ore → plates → this factory
  is the player's first job.

## Known limitations

* L8 reaches the GDD's "≈ 45 cards/min each" only for red (45) and green (50). Blue (12.5), purple and yellow (21.6)
  run lower to keep the layout small (about 135 × 35 tiles).
* L7 follows GDD §7, so its pre-built factory is R/G/B with advanced oil. Purple and yellow are deliberately left for
  the player because they are L7's objectives. All five cards are pre-built only in L8.
* Heavy and light oil (L7/L8) go into storage tanks and are not cracked. At the measured draw, the light-oil tank fills
  after about 110 min on L7 and about 55 min on L8. After that the refinery stops and blue production halts until the
  player adds cracking or uses up the light oil.
* With no research running, the labs consume nothing. Cards collect in the three store chests, which have far more room than the supply chests can fill.
* No modules or beacons are pre-installed.
* The cleared rectangle can still clip the edge of an ore patch or lake, because the side of spawn with the
  lowest score is chosen but not guaranteed to be empty.
* Medium poles auto-wire with at most 5 connections each. Connectivity is checked by the tests, not enforced by the
  stamper.

# Main-menu showcase factory

`Core/Sources/FactoryCore/Progression/MenuShowcase.swift`: `MenuShowcase.make()` returns the world drawn,
darkened, behind the main menu, plus the camera waypoints and zoom. Tests are in
`Core/Tests/FactoryCoreTests/MenuShowcaseTests.swift`. The factory is a small diorama of the whole game:
mining → smelting → belts → inserters → assembling → research, with steam power fed by oil.

## World

* The map is 128 × 128 (seed `0x6D656E75`), with trees at 0.3, no rocks, no lakes and perpetual day. A
  `MapLayoutOverride` turns off the starting patches, the oil fields, the starting lake and regular resources.
  The factory brings its own ore, crude well and pond, so nothing natural is cut off at the edge of the cleared area.
* The factory is 53 × 34 tiles, centred on spawn. Every tile in it, plus a 2-tile margin, is set to grass.
  All 16 chunks are generated inside `make()`, so the first tick does not stall: the character charts 5 × 5
  chunks around itself.
* Every entity is placed by `PrebuiltFactory.Stamper` with the full build rules (`World.placementError`). The test
  requires the failure list to be empty, and every powered machine to be on the steam engines' network.
* `world.cheatInfinitePower = true`. The steam block is real: oil → solid fuel → 3 boilers → 6 engines carry most of
  the ≈ 5.2 MW load. The cheat covers the last ≈ 10 %, so no machine can ever show "low power".
* `world.recordsEvents = false`. The renderer builds views by scanning the visible rectangle, and an undrained event
  queue would grow forever.
* Research: `logistics_2`, with `techPriceMultiplier = 1000`, so it never finishes (≈ 100 000 units). The early techs
  plus `research_speed_1` are force-researched.
* The character stands at local (25.5, 21.5), between the chemical plant and the silo.

## Layout (local coordinates: x −4…48, y 0…33)

```
     x-4  0         10        20        30        40      48
y0   ............>>>>>>>>>>>>>>>>>>>>>>>>>>S>>>>>>>.......   iron plates → row A (priority splitter at x34)
y1   ,,,,...,,.,..f.Pf..f.Pf.....iii....P.iSv.i...i.......
y2   ,,,P,,,,,P,,FFFFFFFFFFFF....AAA.AAA.AAAvAAA.AAA......   row A: gears(asm1) cable circuits inserters belts
y3   ,DDDDDDDDD,,FFFFFFFFFFFF..P.AAAPAAAfAAAvAAAPAAA......
y4   ,DDDDDDDDD,PFFFFFFFFFFFF....AAA.AAA.AAAvAAA.AAA......
y5   ,DDDDDDDDD,..f..f..f..f.......f..ii.P.fuiif.i.f....P.
y6   ,>>>>>>>>>>>>>>>>>>>>>>>...>>>>>>>>>>>>>>>>>>>>>>>>>v   iron ore belt | products bus (east, then south)
y7   ,DDDDDDDDD,P...P....P....P.^f.i.i.f....u....f.i.f.i.v
y8   ,DDDDDDDDD,................^AAA.AAAFFF.v....AAA.AAA.v   row B: red red | steel furnace | green green
y9   ,DDDDDDDDD,...............P^AAAPAAAFFFivP...AAAPAAA.v
y10  ,,,P,,,,,P,,...............^AAA.AAAFFF.v....AAA.AAA.v
y11  ,,,,.,..,.,.......P........^........i..P............v
y12  ............>>>>>>>>>>>>>>S^........C...............v   copper plates → splitter → up x23 onto the bus
y13  .............i..i.........Sv........LLL.LLL.LLL.LLL.v
y14  ............FFFFFF.........v........LLL.LLL.LLL.LLL.v   copper furnaces fed directly by the drills below
y15  ...........PFFFFFFP.......Pi......C.LLL.LLL.LLL.LLL.v
y16  ...........,FFFFFF.........C.....Pf..i.P.i.P.i.P.i.Pv
y17  ...........,DDDDDD..............Cf<<<<<<<<<<<<<<<<<<<   lab belt (west) → 3-chest store
y18  ..........,,DDDDDD................f..i...i...i...i...
y19  .~.~.~.....PDDDDDD................C.LLL.LLL.LLL.LLL..   8 labs
y20  ~~~~~~~..EEEEEEEEE......--..........LLL.LLL.LLL.LLL..
y21  ~~~~~~~..EEEEEEEEEP.....-HHH........LLL.LLL.LLL.LLL..   chemical plant (solid fuel)
y22  ~~~~~~~~.EEEEEEEEE......-HHH.........................
y23  ~~~~~~~~PEEEEEEEEE......-HHH.#########..=========.aa.   rocket silo, solar panels, accumulators
y24  ~~~~~~~..EEEEEEEEE......-.i.P#########P.=========.aa.
y25  ~~~~~~~~.EEEEEEEEEv<<<<u-u<..#########..=========.aa.   fuel belt ducks under the gas pipe
y26  ~~~~~~~..EEEEEEEEEv.RRRRR....#########.....P.....Paa.
y27  ~~~~~~~~.EEEEEEEEEv.RRRRR....#########..=========.aa.   oil refinery (basic)
y28  ~~~~~~~.PEEEEEEEEEv.RRRRR....#########..=========.aa.
y29  ~~~~~~~..EEEEEEEEEv.RRRRR....#########..=========.aa.
y30  ~~~~~~~..BBBBBBBBBv.RRRRRP...#########............aa.   3 boilers
y31  ~~~~~~~o-BBBBBBBBBvJJJ.P.....#########...............   offshore pump, pumpjack
y32  ~~~~~~~..Pi..i.Pi.vJJJ...............................
y33  ~~~~~~~...<<<<<<<<<JJJ...............................   solid fuel → boilers
```
Legend: `> < ^ v` belts, `u` underground belt, `S` splitter, `i`/`f` inserter / fast inserter, `P` medium pole,
`D` drill, `F` electric furnace, `A` assembler, `L` lab, `C` chest, `E` steam engine, `B` boiler, `o` offshore pump,
`-` pipe, `R` refinery, `H` chemical plant, `J` pumpjack, `#` silo, `=` solar panel, `a` accumulator,
`,` ore, `~` water. Regenerate this map with `GF_SHOWCASE_DUMP=1 swift test --filter MenuShowcaseTests`.

## How the factory flows

Measured from minute 10 to minute 120 (`GF_SHOWCASE_LONG=120`):

| Stage | Machines | Rate |
|---|---|---|
| Iron ore | 6 drills (one with a speed module) | 3.1/s |
| Iron plates | 4 electric furnaces (2 speed modules each) | 3.1/s |
| Copper | 2 drill → furnace pairs | 1.0/s |
| Gears | assembling machine 1, 3 iron inserters | 1.0/s |
| Cable → circuits | cable asm 2 → (direct insertion) → circuit asm 2 | 1.2 cable/s → 0.4 circuits/s |
| Inserters / belts | asm 2 each | 0.4/s / 0.38/s |
| Red cards | asm 3 + asm 2 | 0.38/s |
| Green cards | 2 × asm 3 with a speed module | 0.33/s |
| Labs | 8, lab speed 1.2, 30 s units | consume 0.32/s of each card |
| Solid fuel | pumpjack (175 % well) → refinery → chemical plant | 0.39/s ≈ 4.7 MW |

The renderer draws an icon for "output full", "no power" and similar states, so the design rule is that no
machine is ever blocked. Machines may only be starved, which shows no icon. Five things make this hold:

* **Every product goes onto a belt through a fast inserter.** Machines are limited by their input inserters, not
  by their output.
* **One products bus.** It carries copper, gears, circuits, inserters, belts and both cards. It ends in a 3-chest
  store, so it always moves.
* **Bus order sets who goes first.** Both red assemblers take copper before the cable assembler does. The belt
  assembler is last in line for gears.
* **The gear assembler is an assembling machine 1.** Its crafting speed caps it at 1 gear/s (2 iron/s), so it
  cannot take the whole iron line.
* **Priority splitters on both plate lines.** The main line has priority. Iron surplus runs down a gap in row A,
  under the bus through an underground pair, into an electric furnace that makes steel. The copper splitter's
  overflow goes into a chest and is almost never used.

The fuel line runs a little hungry (fuel ≈ 4.7 MW against a ≈ 5.2 MW draw). This keeps solid fuel from backing
up into the chemical plant, while all 3 boilers and 6 engines keep running.

**Endurance.** Nothing runs out: ore is 10⁹ per tile and the crude well is infinite. Only the sinks fill:

* the steel chest takes about 80 steel per hour, which is about 60 h of room;
* the store takes about 7 slots per hour of surplus red cards, belts, inserters and green cards. Its 144 slots
  last about 18 h.

The test checks 1 and 10 minutes. The opt-in long run has been checked to 2 h with no icons. `make()` builds a
fresh world every time, so the menu starts from the primed state each time.

**Priming.** `prime()` loads the factory at build time, so the first frame already looks busy. It puts items on
every belt, ore in the furnaces, a few crafts of ingredients in each assembler, cards in the labs and solid fuel
on the fuel belt. The simulation is not run inside `make()`.

## Camera

* The waypoints are local (16, 9) → (29, 9) → (29, 25) → (16, 25) → back to the start, a loop around the
  rectangle. The tests convert them to world coordinates.
* The zoom is 0.7. At that zoom an iPhone in landscape shows about 39 × 18 tiles, so the loop covers the whole
  53 × 34 factory: mining and smelting top left, assembly top right, power and oil bottom left, labs and silo
  bottom right.
* An iPad shows about 53 × 37 tiles and sees nearly everything at once.

## Cost

* 332 placed entities, plus about 390 trees on the rest of the map.
* `make()` takes 140–210 ms in a Linux debug build. That includes generating the whole map.
* The first tick takes about 2 ms, then about 0.6–0.8 ms per tick in a debug build.

## How to tweak

* **Tunables** are at the top of `MenuShowcase`: `research`, `techPrice`, `crudeAmount` (fuel versus the ≈ 5.2 MW
  draw: more crude backs up the chemical plant, less crude stops some engines), `assembler` and
  `scienceAssembler`, `seed`, `mapSide`.
* **Modules** are `iron`, `copper`, `assembly`, `steel`, `labs`, `steam`, `oil` and `landmarks`. Each one has an
  ASCII sketch in its doc comment, and all of them use local coordinates.
* **After any change**, run `swift test --filter MenuShowcaseTests`. It fails on any placement failure, on a machine
  off the network, and on any status icon during a 10-second sample at 1 min and at 10 min. It also asserts that
  belts carry more than 150 items and sets minimum counts of working drills, furnaces, assemblers, labs, boilers
  and engines.
* `GF_SHOWCASE_DIAG=1` prints rates per minute, power, every machine's input and output slots, and what is in each
  chest.
* `GF_SHOWCASE_LONG=<minutes>` runs the endurance profile.
* **Moving a consumer along the bus changes who gets served first.** Check the store's contents in the diagnostics.
  A fast-growing stack means waste. A machine at "output full" means a producer is faster than everything
  downstream of it.
