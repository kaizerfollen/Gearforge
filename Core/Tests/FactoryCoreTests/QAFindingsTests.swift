// Gearforge — QA findings: one repro per open bug. EVERY test here FAILS on the current code (da78b27) and should
// pass once the bug is fixed. Details, severity and suspected cause: docs/team/qa.md.
// Crash repros run the command in a forked child (QA.survives) so a trap does not take the test process down.

import XCTest
@testable import FactoryCore

final class QAFindingsTests: XCTestCase {

    // MARK: Crashes on invalid input

    /// BUG 1 (Medium, crash): any entity-id command with an id outside the entity table traps
    /// (`EntityStore.subscript` is an unchecked array access and `World.execute` never range-checks).
    func testBUG_1_outOfRangeEntityIdCrashes() {
        let cmds: [(String, PlayerCommand)] = [
            ("remove", .remove(entity: 9999)), ("remove -1", .remove(entity: -1)), ("rotate", .rotate(entity: 9999, clockwise: true)),
            ("setRecipe", .setRecipe(entity: 9999, recipe: 0)), ("takeAll", .takeAll(entity: 9999)),
            ("pickUpBeltItems", .pickUpBeltItems(entity: 9999)), ("launchRocket", .launchRocket(entity: 9999)),
            ("setInserterFilter", .setInserterFilter(entity: 9999, slot: 0, item: 0)),
            ("transferToEntity", .transferToEntity(entity: 9999, item: 0, count: 1)),
        ]
        for (name, cmd) in cmds {
            XCTAssertTrue(QA.survives {
                let w = TestWorld.make(size: 16)
                _ = w.execute(cmd)
            }, "\(name) with an out-of-range entity id must fail cleanly, not crash")
        }
    }

    /// BUG 2 (Medium, crash): out-of-range item / prototype ids trap instead of failing:
    /// `.buildGhost` (db.entities[proto] in footprint), `.transferFromEntity` (stackSize(item)), `.placeTiles`
    /// (db.itemPlaceTile[item]).
    func testBUG_2_outOfRangeItemOrPrototypeIdCrashes() {
        let cases: [(String, (World) -> Void)] = [
            ("buildGhost proto 9999", { w in _ = w.execute(.buildGhost(entityProto: 9999, origin: TilePos(3, 3), direction: .north)) }),
            ("buildGhost proto -1", { w in _ = w.execute(.buildGhost(entityProto: -1, origin: TilePos(3, 3), direction: .north)) }),
            ("transferFromEntity item 9999", { w in
                let c = w.place("wooden_chest", 4, 4); _ = w.execute(.transferFromEntity(entity: c, item: 9999, count: 5)) }),
            ("transferFromEntity item -1", { w in
                let c = w.place("wooden_chest", 4, 4); _ = w.execute(.transferFromEntity(entity: c, item: -1, count: 5)) }),
            ("placeTiles item 9999", { w in _ = w.execute(.placeTiles(item: 9999, tiles: [TilePos(3, 3)])) }),
            ("placeTiles item -1", { w in _ = w.execute(.placeTiles(item: -1, tiles: [TilePos(3, 3)])) }),
        ]
        for (name, body) in cases {
            XCTAssertTrue(QA.survives {
                let w = TestWorld.make(size: 16)
                w.player.position = Vec2(5, 5)
                body(w)
            }, "\(name) must fail cleanly, not crash")
        }
    }

    /// BUG 3 (Medium, exploit + crash): `.pickUpBeltItems` on a NON-belt entity uses that entity's component index
    /// as a belt-tile index (BeltSystem.tileIndices has no kind check), so it removes items from an unrelated belt
    /// anywhere on the map — or traps when the index exceeds the belt tile table.
    func testBUG_3_pickUpBeltItemsOnNonBeltStealsFromRemoteBelt() {
        let w = TestWorld.make(size: 64)
        w.player.position = Vec2(5, 5)
        let far = w.place("transport_belt", 50, 50, .east)                 // belt tile component 0, far out of reach
        XCTAssertTrue(w.belts.insertItem(far, lane: 0, position: 0, item: w.item("iron_plate")))
        w.step(1)
        let chest = w.place("wooden_chest", 6, 6)                          // container component 0, in reach
        let r = w.execute(.pickUpBeltItems(entity: chest))
        XCTAssertFalse(r.isOK, "a chest is not a belt")
        XCTAssertEqual(w.belts.totalItemCount, 1, "the remote belt must keep its item")
        XCTAssertEqual(w.player.count(of: w.item("iron_plate")), 0)
        XCTAssertTrue(QA.survives {
            let v = TestWorld.make(size: 16)
            v.player.position = Vec2(5, 5)
            let c = v.place("wooden_chest", 4, 4)                           // no belts at all
            _ = v.execute(.pickUpBeltItems(entity: c))
        }, "pickUpBeltItems on a chest with no belts in the world must not crash")
    }

    // MARK: Exploits / rule bypasses

    /// BUG 4 (Medium; High once blueprints/ghosts reach the UI): `.buildGhost` and `pasteBlueprint` validate only
    /// `canPlace` (bounds/occupied/water), and `Character.autoBuildGhosts` builds ghosts with the same check. Shoreline,
    /// drill-resource and fluid-mixing rules are bypassed: an offshore pump placed as a ghost on dry land is
    /// auto-built and produces infinite water anywhere.
    func testBUG_4_ghostBypassesPlacementRules() {
        let w = TestWorld.make(size: 32)
        w.player.position = Vec2(10.5, 10.5)
        let pumpItem = w.item("offshore_pump")
        w.player.give(pumpItem, 1)
        XCTAssertEqual(w.execute(.build(item: pumpItem, origin: TilePos(12, 12), direction: .north)), .failed(.needsShoreline))
        let g = w.execute(.buildGhost(entityProto: w.proto("offshore_pump"), origin: TilePos(12, 12), direction: .north))
        w.step(61)
        var water = 0.0
        w.entities.forEachLive { e, r in if r.kind == .offshorePump && !r.flags.contains(.ghost) { water += w.fluids.amount(e, box: 0) } }
        XCTAssertTrue(g == .failed(.needsShoreline) || water == 0, "inland offshore pump must not be buildable via a ghost (got \(g), water \(water))")
        XCTAssertEqual(w.player.count(of: pumpItem), 1, "the pump item must stay in the inventory")
    }

    /// BUG 5 (Medium, item loss): fast-replace with a full inventory destroys the replaced entity's item
    /// (`pl.give(oldItem, 1)` result ignored in Commands.build fast-replace branch; no spill).
    func testBUG_5_fastReplaceWithFullInventoryDestroysOldItem() {
        let w = TestWorld.make(size: 32)
        w.player.position = Vec2(10.5, 10.5)
        w.place("transport_belt", 10, 12, .east)
        let tb = w.item("transport_belt"), fb = w.item("fast_transport_belt")
        w.player.give(fb, 10)
        for _ in 0..<79 { w.player.give(tb, 100) }                   // every other slot: a full stack of belts
        let before = (QA.itemCensus(w)[tb] ?? 0) + 1                    // + the placed belt
        XCTAssertTrue(w.execute(.build(item: fb, origin: TilePos(10, 12), direction: .east)).isOK)
        XCTAssertEqual(QA.itemCensus(w)[tb] ?? 0, before, "replaced belt must end up in the inventory or on the ground")
    }

    /// BUG 6 (Medium, item loss): when a chain-craft group finishes, leftover intermediates (e.g. the 4th copper
    /// cable of an electronic circuit) are given with the result ignored — destroyed if the inventory is full
    /// (Character.updateCrafting "group finished" branch).
    func testBUG_6_chainCraftExcessIntermediateLostWhenInventoryFull() {
        let w = TestWorld.make(size: 16)
        let cu = w.item("copper_plate"), fe = w.item("iron_plate"), circ = w.item("electronic_circuit")
        let cable = w.item("copper_cable"), stone = w.item("stone")
        w.player.give(circ, 1)                     // circuit stack with room → the final product always fits
        w.player.give(cu, 2); w.player.give(fe, 1)
        XCTAssertTrue(w.execute(.craft(recipe: w.db.recipe("electronic_circuit"), count: 1)).isOK)  // crafts 4 cables, uses 3
        while w.player.give(stone, 50) > 0 {}
        w.step(600)
        XCTAssertEqual(w.player.count(of: circ), 2)
        XCTAssertEqual(QA.itemCensus(w)[cable] ?? 0, 1, "the spare cable must be kept (inventory or ground)")
    }

    /// BUG 7 (Medium, item loss): removing an entity with a full inventory spills the rest on the ground, but
    /// `GroundItems.spill` returns what did not fit and Commands.remove ignores it — in a built-up area (8 items per
    /// free tile, radius 12) almost the whole content of a chest is destroyed.
    func testBUG_7_removeWithFullInventoryDestroysUnspillableItems() {
        let w = TestWorld.make(size: 64)
        w.player.position = Vec2(30.5, 30.5)
        let fe = w.item("iron_plate")
        let chest = w.place("steel_chest", 30, 30)
        _ = w.containers.insert(chest, item: fe, count: 4800, source: .player)
        for y in 15...45 { for x in 15...45 where !(x == 30 && y == 30) { w.place("stone_wall", x, y) } }
        while w.player.give(w.item("stone"), 50) > 0 {}
        let r = w.execute(.remove(entity: chest))
        let kept = (QA.itemCensus(w)[fe] ?? 0)
        XCTAssertTrue(!r.isOK || kept == 4800, "remove must refuse (inventory full) or keep every plate; kept \(kept) of 4800")
    }

    /// BUG 8 (Medium): undo history breaks after one undo. Undoing a removal re-creates the entity with a new
    /// generation, so the older `.built(handle)` entry no longer resolves: the next undo fails AND is discarded.
    /// Same for redo. (Commands.undo/redo store EntityHandles that go stale on re-creation.)
    func testBUG_8_undoChainBreaksAfterUndoRecreatesEntity() {
        let w = TestWorld.make(size: 32)
        w.player.position = Vec2(10.5, 10.5)
        let tb = w.item("transport_belt")
        w.player.give(tb, 5)
        XCTAssertTrue(w.execute(.build(item: tb, origin: TilePos(10, 12), direction: .east)).isOK)
        XCTAssertTrue(w.execute(.remove(entity: w.entity(at: TilePos(10, 12))!)).isOK)
        XCTAssertTrue(w.undo().isOK, "undo remove → belt back")
        XCTAssertTrue(w.undo().isOK, "undo build → belt gone")
        XCTAssertNil(w.entity(at: TilePos(10, 12)))
        XCTAssertEqual(w.player.count(of: tb), 5)
    }

    /// BUG 9 (Medium): the fluid-mixing guard is skipped for fast-replace (`placementError(... ignoring:)` only runs
    /// wouldMixFluids when `ignoring == nil`). Replacing a water pipe with a pipe-to-ground whose underground partner
    /// carries steam merges both into one segment and silently deletes one fluid.
    func testBUG_9_fastReplaceBypassesFluidMixingGuard() {
        let w = TestWorld.make(size: 32)
        w.player.position = Vec2(10.5, 7.5)
        let water = w.db.fluid("water"), steam = w.db.fluid("steam")
        let wp = w.place("pipe", 10, 4)
        w.place("pipe", 10, 5)
        w.place("pipe_to_ground", 10, 9, .south)
        let sp = w.place("pipe", 10, 10)
        w.fluids.add(wp, box: 0, fluid: water, amount: 150, temperature: 15)
        w.fluids.add(sp, box: 0, fluid: steam, amount: 150, temperature: 165)
        w.step(1)
        let p2g = w.item("pipe_to_ground")
        w.player.give(p2g, 1)
        let r = w.execute(.build(item: p2g, origin: TilePos(10, 5), direction: .north))
        w.step(2)
        XCTAssertTrue(r == .failed(.wouldMixFluids) || (w.fluids.fluid(wp, box: 0) == water && w.fluids.fluid(sp, box: 0) == steam),
                      "fast-replace must not connect water and steam (got \(r); fluids now \(w.fluids.fluid(wp, box: 0)) / \(w.fluids.fluid(sp, box: 0)))")
    }

    /// BUG 10 (Medium, exploit): machine-configuration commands have no reach check. `.setRecipe` refunds the
    /// machine's buffers into the player inventory, so the player can pull items out of any assembler on the map
    /// (likewise `.removeModule` / `.insertModule`).
    func testBUG_10_setRecipePullsItemsFromOutOfReachMachine() {
        let w = TestWorld.make(size: 64)
        w.player.position = Vec2(5.5, 5.5)
        let am = w.place("assembling_machine_1", 50, 50)
        _ = w.crafting.setRecipe(am, w.db.recipe("iron_gear_wheel"))
        _ = w.crafting.insert(am, item: w.item("iron_plate"), count: 50, source: .player)
        let r = w.execute(.setRecipe(entity: am, recipe: -1))
        XCTAssertEqual(r, .failed(.outOfReach))
        XCTAssertEqual(w.player.count(of: w.item("iron_plate")), 0, "items 45 tiles away must not teleport into the inventory")
    }

    // MARK: Character

    /// BUG 11 (Low/Medium): `.walkAndMine` returns .ok but never mines when the nearest standing tile is the one the
    /// character is already on while its (off-centre) position is still out of reach: findPath returns [] for
    /// target == start, walk() succeeds with an empty path, and updatePendingMine drops the target on the next tick.
    /// In the app the long-press shows "mining" forever (GameView sets holding = true).
    func testBUG_11_walkAndMineOkButNeverMinesWhenOffCentre() {
        let w = TestWorld.make(size: 32)
        w.surface.setResource(at: TilePos(10, 10), w.db.resource("iron_ore"), amount: 50)
        w.player.position = Vec2(12.99, 12.99)                 // 2.81 tiles from the ore tile (reach 2.7)
        let r = w.execute(.walkAndMine(TilePos(10, 10)))
        w.step(300)
        XCTAssertTrue(!r.isOK || w.player.count(of: w.item("iron_ore")) > 0, "walkAndMine reported \(r) but mined nothing")
    }

    /// BUG 12 (Low): building over a ghost of the same entity removes the ghost first; if the build then fails for
    /// another reason (no resource under a drill, fluid mix…) the ghost and its settings are gone.
    func testBUG_12_failedBuildOverGhostDestroysGhost() {
        let w = TestWorld.make(size: 32)
        w.player.position = Vec2(10.5, 10.5)
        let d = w.proto("electric_mining_drill")
        XCTAssertTrue(w.execute(.buildGhost(entityProto: d, origin: TilePos(10, 12), direction: .north)).isOK)
        w.player.give(w.item("electric_mining_drill"), 1)
        XCTAssertEqual(w.execute(.build(item: w.item("electric_mining_drill"), origin: TilePos(10, 12), direction: .north)),
                       .failed(.noResourceUnderDrill))
        let g = w.entity(at: TilePos(10, 12))
        XCTAssertTrue(g.map { w.entities[$0].flags.contains(.ghost) } ?? false, "the ghost must survive a failed build")
    }

    // MARK: Fluids / save-load determinism

    /// BUG 13 (Low): fluid is created from nothing when a fluid entity is removed and another fluid entity is built
    /// before the next fluid update. unregisterEndpointIfNeeded frees the box but leaves it in the stale segment's
    /// `members`; the new entity reuses the box index and rebuild() step 1 hands it a share of the old segment.
    func testBUG_13_fluidCreatedWhenRemoveAndBuildBeforeNextTick() {
        let w = TestWorld.make(size: 32)
        var pipes: [Int32] = []
        for x in 3...12 { pipes.append(w.place("pipe", x, 5)) }
        let water = w.db.fluid("water")
        w.fluids.add(pipes[0], box: 0, fluid: water, amount: 700, temperature: 15)
        w.step(1)
        w.removeEntity(pipes[2])                                  // 700 → 630 left in the network
        let iso = w.place("pipe", 20, 20)                         // unconnected pipe, same tick
        w.step(1)
        var total = 0.0
        for (i, p) in pipes.enumerated() where i != 2 { total += w.fluids.amount(p, box: 0) }
        total += w.fluids.amount(iso, box: 0)
        XCTAssertEqual(w.fluids.amount(iso, box: 0), 0, "an unconnected new pipe must be empty")
        XCTAssertLessThanOrEqual(total, 630 + 1e-6, "no fluid may be created")
    }

    /// BUG 14 (Low): belt item positions are saved as Float fractions of a tile and restored with truncation, so on
    /// curves (lane length not a power of two) items come back up to 1/256 tile off — the loaded game diverges from
    /// the saved one (here for ~100 ticks until the lanes compress). Also makes every topology rebuild nudge items.
    func testBUG_14_beltItemPositionsNotRestoredExactlyOnLoad() throws {
        let w = QA.closedLoop()
        w.step(777)
        let (b, _) = try WorldCodec.decode(WorldCodec.encode(w))
        func positions(_ x: World) -> [String] {
            var out: [String] = []
            x.belts.forEachItem(in: TileRect(x: 0, y: 0, w: 32, h: 32)) { i, px, py in out.append("\(i)@\(px),\(py)") }
            return out
        }
        XCTAssertEqual(positions(w), positions(b), "belt items must be exactly where they were saved")
    }

    /// BUG 15 (Low): tap-to-walk path and pending walk-and-mine target are not saved (Character.serialize), so an
    /// autosave during a walk makes the loaded game diverge (the character stops where the save was taken).
    func testBUG_15_walkPathNotSaved() throws {
        let w = TestWorld.make(size: 32)
        w.player.position = Vec2(3.5, 3.5)
        XCTAssertTrue(w.execute(.walkTo(TilePos(25, 25))).isOK)
        w.step(10)
        let (b, _) = try WorldCodec.decode(WorldCodec.encode(w))
        w.step(100); b.step(100)
        XCTAssertEqual(b.player.position, w.player.position, "loaded game must continue the walk")
    }
}
