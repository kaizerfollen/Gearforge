# QA report — independent test pass (master @ da78b27)

Owner: QA. Scope: FactoryCore simulation and commands (run on Linux), plus a read-only review of the app bridge and game view.

- `Core/Tests/FactoryCoreTests/QATests.swift`: 13 regression tests. **All pass.**
- `Core/Tests/FactoryCoreTests/QAFindingsTests.swift`: 15 repro tests, `testBUG_<n>_…`. **Each one fails on the current code** and should pass once its bug is fixed.
- Full suite without the findings: `swift test --skip QAFindingsTests` gives 137 tests and 0 failures. To list the open bugs, run `swift test --filter QAFindingsTests`.
- Crash repros run the command in a forked child process (`QA.survives`), so a trap is reported as a failed assertion and does not abort the test run.

## Summary

| # | Area | Tests added (QATests) | Bugs found |
|---|------|----------------------|------------|
| 1 | Save → load → continue | `testMixedFactorySaveLoadContinuesBitIdentically`, `testClosedLoopSaveLoadContinuesIdentically` | BUG 14, BUG 15 (Low) |
| 2 | Undo/redo, fast replace | `testBuildRotateRemoveUndoRedoConservesItems`, `testFastReplaceBeltsWithItemsConservesEverything` | BUG 5, BUG 8 (Medium) |
| 3 | Item conservation | `testClosedLoopConservesItemCount` | BUG 7 (Medium) |
| 4 | Invalid commands | `testInvalidCommandsFailCleanly` | BUG 1, BUG 2, BUG 3, BUG 10 (Medium); BUG 4 (Medium, High once ghosts reach the UI); BUG 12 (Low) |
| 5 | Hand crafting | `testHandCraftChainCancelMidwayRefundsExactly`, `testHandCraftCancelWithFullInventorySpillsInsteadOfLosing`, `testHandCraftPausesWhenFullAndResumes` | BUG 6 (Medium) |
| 6 | Power | `testAccumulatorCarriesNightAndPoleRemovalSplitsNetwork` | none |
| 7 | Fluids | `testFluidPipeRemovalNeverCreatesFluidAndPumpIsOneWay` | BUG 9 (Medium), BUG 13 (Low) |
| 8 | Character | `testHandMiningDepletesTileAndDrillExhaustsExactly`, `testWalkToUnreachableIslandFailsCleanly` | BUG 11 (Low/Medium) |
| 9 | App review | read-only | A1–A6 below |

**Totals:** 15 Core bugs: 0 Critical, 0 High, 10 Medium, 5 Low. BUG 4 becomes High once ghosts or blueprints reach the UI. There are also 6 app-review notes, one of them a possible crash (A1).

## Bugs

Severity scale:
- **High:** crash or exploit that a player can reach today.
- **Medium:** crash or exploit reachable only through the Core API or a rare UI sequence, or items/fluid silently lost.
- **Low:** divergence or annoyance.

| Bug | Sev | Repro test | What happens | Suspected cause |
|-----|-----|-----------|--------------|-----------------|
| 1 | Medium (crash) | `testBUG_1_outOfRangeEntityIdCrashes` | Any entity command with an id outside the entity table traps, e.g. `.remove(entity: 9999)` or `-1`. The same happens with `rotate`, `setRecipe`, `takeAll`, `pickUpBeltItems`, `launchRocket`, `setInserterFilter` and `transferToEntity`. | `World/Entities.swift:58`: unchecked `records[Int(i)]`. `Commands/Commands.swift:140`: `execute` never range-checks ids. |
| 2 | Medium (crash) | `testBUG_2_outOfRangeItemOrPrototypeIdCrashes` | An out-of-range item or prototype id traps in `.buildGhost` (proto 9999 / -1), `.transferFromEntity` (item 9999 / -1) and `.placeTiles` (item 9999 / -1). | `Commands.swift:146–147`: `canPlace` calls `footprint`, which indexes `db.entities[proto]`. `Commands.swift:289`: `stackSize(item)`. `Commands.swift:152`: `db.itemPlaceTile[item]`. |
| 3 | Medium (exploit + crash) | `testBUG_3_pickUpBeltItemsOnNonBeltStealsFromRemoteBelt` | `.pickUpBeltItems` on a chest in reach takes the items off an unrelated belt 45 tiles away. With no belts in the world it traps. The UI only calls it on belts, so the bug is reachable through the API only. | `Simulation/Logistics/BeltSystem.swift:267`: `tileIndices(of:)` treats any entity's `component` as a belt-tile index, with no kind or alive check. `Commands.swift:315` does not check the kind either. |
| 4 | Medium (High once ghosts or blueprints reach the UI) | `testBUG_4_ghostBypassesPlacementRules` | Ghost placement and blueprint paste only check `canPlace` (bounds, occupied, water), and auto-build uses the same check. As a result:<br>• An offshore pump placed as a ghost on dry land is auto-built and pumps water anywhere.<br>• A drill can be built with no resource under it.<br>• Fluid-mixing placements are allowed. | `Commands.swift:146–149`; `Commands/Blueprints.swift:211`; `Player/Character.swift:436`. All three should call `placementError`. |
| 5 | Medium (item loss) | `testBUG_5_fastReplaceWithFullInventoryDestroysOldItem` | Fast-replacing belts with a full inventory deletes the replaced belt item: belt count goes 7901 → 7900 and nothing is spilled. | `Commands.swift:469`: `pl.give(oldItem, 1)` ignores its return value; it should go through `giveOrAlert`. |
| 6 | Medium (item loss) | `testBUG_6_chainCraftExcessIntermediateLostWhenInventoryFull` | When a chain-craft group finishes, spare intermediates (e.g. the 4th copper cable of an electronic circuit) are deleted if the inventory is full. | `Player/Character.swift:261`: `give` result ignored, no ground spill. Also, iterating the `pool` Dictionary makes slot order depend on hash order. |
| 7 | Medium (item loss) | `testBUG_7_removeWithFullInventoryDestroysUnspillableItems` | Removing a full steel chest (4800 plates) with a full inventory in a built-up area keeps only 8 plates; 4792 are destroyed. | `Commands.swift:525`: the return value of `ground.spill(...)` (items not placed) is ignored. Either refuse the removal or keep the items. `giveOrAlert` has the same issue. |
| 8 | Medium | `testBUG_8_undoChainBreaksAfterUndoRecreatesEntity` | Build, remove, undo (OK), undo again: the second undo fails with `nothingThere`, its entry is discarded, and the belt stays. Redo behaves the same way. | `Commands.swift:379/400`: undo entries store an `EntityHandle`. Re-creating the entity bumps its generation, so older `.built(h)` entries no longer resolve. Store origin + proto, or rewrite the handles on re-create. |
| 9 | Medium | `testBUG_9_fastReplaceBypassesFluidMixingGuard` | Fast-replacing a water pipe with a pipe-to-ground whose underground partner carries steam merges both into one segment, and one fluid silently disappears. | `Commands.swift:130`: `wouldMixFluids` is skipped whenever `ignoring != nil`. |
| 10 | Medium (exploit) | `testBUG_10_setRecipePullsItemsFromOutOfReachMachine` | `.setRecipe(-1)` on an assembler 45 tiles away refunds its 50 plates into the inventory. `.insertModule` and `.removeModule` work at any distance too. In the app the entity panel stays usable after walking away. | `Commands.swift:204/213/227`: no `canReach` check. (`transferTo/From` do check reach.) |
| 11 | Low/Medium | `testBUG_11_walkAndMineOkButNeverMinesWhenOffCentre` | `.walkAndMine` returns `.ok` but never mines when the best standing tile is the character's own tile and the character is off-centre (2.81 tiles away, reach is 2.7). In the app, GameView sets `holding = true` and shows mining that never happens. | `Player/Pathfinding.swift:43`: `target == start` returns `[]`. `Character.swift:336` then sets `pendingMine`, and `Character.swift:350` drops it on the next tick because no path is active. |
| 12 | Low | `testBUG_12_failedBuildOverGhostDestroysGhost` | Building over a ghost whose build then fails (drill with no resource) removes the ghost and its settings. | `Commands.swift:491–492`: the ghost is removed before the build is validated. |
| 13 | Low | `testBUG_13_fluidCreatedWhenRemoveAndBuildBeforeNextTick` | Removing a pipe (700 → 630 left) and then building an unconnected pipe before the next tick gives the new pipe 70 units: 70 created from nothing. This needs two commands within one tick, so it is rare in the UI. | `Simulation/Fluids/FluidSystem.swift:108`: the freed box stays in the stale segment's `members`. The reused box index then gets a share in `rebuild()` step 1 (line 252). |
| 14 | Low | `testBUG_14_beltItemPositionsNotRestoredExactlyOnLoad` | After loading, belt items on curves come back up to 1/256 tile off, so the loaded game diverges from the saved one for about 100 ticks. Each topology rebuild also nudges items. | `BeltSystem.swift:961` saves a `Float` fraction of the tile; line 579 restores it with truncation. Save the integer distance instead. |
| 15 | Low | `testBUG_15_walkPathNotSaved` | `walkPath` and `pendingMine` are not saved, so an autosave during tap-to-walk makes the loaded character stop. The code comment says this is intentional, but it is a save/load divergence. | `Player/Character.swift:447` (`serialize`). |

## Observations (no failing test)

- **Fluid section right after load.** The fluid payload is not byte-identical immediately after a load: segment → box re-split rounding (`FluidSystem.swift` serialize / rebuild). It converges on the first tick; the mixed-factory test therefore compares from +1.
- **Belt section re-encode.** The belt payload re-encodes differently right after load (consequence of BUG 14).
- **Slow failure on unreachable targets.** `walkTo` / `walkAndMine` towards an unreachable target (an island) spends about 150 ms per call in a debug build: A* expands up to 30 000 nodes with Dictionary bookkeeping. In release on device this may still cause a frame hitch. Consider a smaller node budget or a reachability flood-fill cache.
- **`belts.items(on:)` misses items.** It does not count an item sitting exactly on a tile boundary, nor items inside the hidden underground section. Counts in the entity panel can be one short. Conservation itself holds: `totalItemCount` is correct.
- **Behaviour checked and correct:**
  - closed logistics loop (splitter, underground, 5 inserters of 4 types) conserves items for 6000 ticks;
  - fast-replacing belts that carry items conserves them;
  - hand-craft refunds are exact in raw-material terms at every point of the chain;
  - accumulator carries a lamp through the night;
  - removing a pole splits the network;
  - pump is one-way;
  - pipe removal never creates fluid (outside BUG 13);
  - hand mining depletes a tile and stops;
  - a drill exhausts exactly (9 tiles × 2 ore = 18 ore).
- **Mixed-factory determinism.** Save → load → continue of the mixed factory (steam, solar, accumulator, underground and splitter, 6 inserter types mid-swing, two drill types with a module, furnaces mid-craft, assembler with module and beacon, lab, pump and tank, ghost with settings, ground items, hand-mining and hand-crafting player) stays byte-identical across 2100 ticks.

## App review (read-only; not compiled or run)

| # | Risk | Location | Note |
|---|------|----------|------|
| A1 | Crash | `App/Sources/UI/GameView.swift:22, 142, 189–199` and `App/Sources/Bridge/GameController.swift:414–415` | The long-press context menu stores a raw `Int32` entity index, not an `EntityHandle`. `world` is `@ObservationIgnored`, so the menu does not re-render when the entity dies. If the entity is removed while the menu is open (HUD undo, remove-mode drag), **Pipette** calls `world.db.entityItem[Int(world.entities[e].proto)]` with `proto == -1`, which is an index out of range and crashes. If the slot is reused, **Rotate** and **Remove** act on a different entity. Fix: store a handle and resolve it in each button. |
| A2 | Wrong entity | `App/Sources/UI/EntityPanel.swift:53` | `pipette(e)` from the entity panel has the same raw-index pattern. The panel resolves its handle at render time, so the risk is lower. |
| A3 | State bug | `App/Sources/Bridge/GameController.swift:362–367` | Drag-building belts re-orients the belt under the drag start (up to 4 rotations), even if it was an existing belt that is part of another line. These rotations are not recorded for undo. |
| A4 | UX / state | `App/Sources/UI/GameView.swift:136–147` | `holding = controller.walkAndMine(...)` trusts `.ok`, so with BUG 11 the UI shows mining progress that never comes. |
| A5 | Exploit surface | `App/Sources/UI/EntityPanel.swift:319, 353, 383` | Module insert/remove and recipe changes go through commands with no reach check (BUG 10). The panel stays open while the character walks away. |
| A6 | Minor | `App/Sources/Bridge/GameController.swift:202, 433` | `w.player!` / `world.player!` force-unwraps. They are safe while `World.init` always creates the player, but a nil player would crash. |

There are no `try!`, `as!` or unchecked `.first!` uses in `GameController.swift` or `GameView.swift`. Array subscripts on `db.*` arrays are guarded by `>= 0` checks except in A1.
