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
