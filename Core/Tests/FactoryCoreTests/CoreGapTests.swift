// Gearforge — tests for the core gaps closed after the S6 audit (docs/AUDIT.md §1).

import XCTest
@testable import FactoryCore

final class CoreGapTests: XCTestCase {

    private func playerWorld() -> World {
        let w = TestWorld.make()
        w.player.position = Vec2(10.5, 10.5)
        return w
    }

    // MARK: Ground items

    func testRemovingChestWithFullInventorySpillsOnGround() {
        let w = playerWorld()
        let stone = w.item("stone")
        // fill the inventory completely
        while w.player.give(stone, 50) > 0 {}
        let chest = w.place("iron_chest", 12, 12)
        _ = w.containers.insert(chest, item: w.item("coal"), count: 100, source: .player)
        XCTAssertTrue(w.execute(.remove(entity: chest)).isOK)
        XCTAssertGreaterThan(w.ground.totalCount, 100, "coal + chest item spilled on the ground")
        // after making room, walking over the items picks them up
        w.player.inventory = Inventory(size: 80)
        w.player.position = Vec2(12.5, 12.5)
        for _ in 0..<40 {
            w.step(10)
            if w.ground.isEmpty { break }
            // walk around the spill
            if let p = w.ground.tiles.keys.min(by: { ($0.y, $0.x) < ($1.y, $1.x) }) { w.player.position = Vec2(Double(p.x) + 0.5, Double(p.y) + 0.5) }
        }
        XCTAssertTrue(w.ground.isEmpty)
        XCTAssertEqual(w.player.count(of: w.item("coal")), 100)
        XCTAssertEqual(w.player.count(of: w.item("iron_chest")), 1)
    }

    func testInserterDropsOnGroundAndPicksUpFromGround() {
        let w = TestWorld.make()
        w.cheatInfinitePower = true
        let src = w.place("iron_chest", 5, 6)
        w.place("inserter", 5, 5, .north)              // drops onto (5,4) — nothing there
        _ = w.containers.insert(src, item: w.item("iron_plate"), count: 10, source: .player)
        w.step(600)
        XCTAssertEqual(w.ground.count(at: TilePos(5, 4)), 1, "inserter puts one item on an empty tile, then waits")
        // a second inserter picking from that tile into a chest
        w.place("inserter", 5, 3, .north)
        let dst = w.place("iron_chest", 5, 2)
        w.step(600)
        XCTAssertGreaterThan(w.containers.inventory(of: dst)!.count(of: w.item("iron_plate")), 3, "items flow via the ground tile")
    }

    func testDrillWithNothingInFrontDropsOneItem() {
        let w = TestWorld.make()
        w.cheatInfinitePower = true
        TileRect(x: 3, y: 4, w: 5, h: 5).forEach { w.surface.setResource(at: $0, w.db.resource("iron_ore"), amount: 100) }
        let d = w.place("electric_mining_drill", 4, 5, .north)
        w.step(60 * 20)
        XCTAssertEqual(w.ground.count(at: TilePos(5, 4)), 1)
        XCTAssertEqual(w.mining.status(of: d), .outputFull)
    }

    func testBuildingOverGroundItemsCollectsThem() {
        let w = playerWorld()
        w.ground.add(item: w.item("coal"), count: 5, at: TilePos(12, 12))
        w.player.give(w.item("wooden_chest"), 1)
        XCTAssertTrue(w.execute(.build(item: w.item("wooden_chest"), origin: TilePos(12, 12), direction: .north)).isOK)
        XCTAssertEqual(w.ground.count(at: TilePos(12, 12)), 0)
        XCTAssertEqual(w.player.count(of: w.item("coal")), 5)
    }

    func testGroundItemsSurviveSaveLoad() throws {
        let w = playerWorld()
        w.ground.add(item: w.item("coal"), count: 3, at: TilePos(30, 30))
        let s = GameSession(world: w, mode: .freeplay)
        let b = try GameSession.decode(payload: s.encodePayload())
        XCTAssertEqual(b.world.ground.count(at: TilePos(30, 30)), 3)
    }

    // MARK: Fluids

    func testPumpjackDirectlyIntoRefineryAndPetroleumOnRightOutput() {
        let w = TestWorld.make()
        w.cheatInfinitePower = true
        w.surface.setResource(at: TilePos(11, 21), w.db.resource("crude_oil"), amount: 300_000)
        w.place("pumpjack", 10, 20, .north)                 // output neighbour (12,19)
        let ref = w.place("oil_refinery", 11, 15, .north)    // input (-1,3) → (12,20) inside the pumpjack
        _ = w.crafting.setRecipe(ref, w.db.recipe("basic_oil_processing"))
        w.step(60 * 30)
        let gas = w.db.fluid("petroleum_gas")
        XCTAssertGreaterThan(w.stats.totalProduced(fluid: gas), 0, "crude flows pumpjack → refinery without a pipe")
        // boxes 2,3,4 are the outputs (left, middle, right): petroleum must be in the right one (4)
        XCTAssertEqual(w.fluids.fluid(ref, box: 4), gas)
        XCTAssertEqual(w.fluids.fluid(ref, box: 2), -1)
    }

    func testAdvancedOilProcessingOutputsInOrder() {
        let w = TestWorld.make()
        w.cheatInfinitePower = true
        let ref = w.place("oil_refinery", 11, 15, .north)
        guard w.db.recipe("advanced_oil_processing") >= 0 else { return }
        _ = w.crafting.setRecipe(ref, w.db.recipe("advanced_oil_processing"))
        for (j, ing) in w.db.resolvedRecipes[w.db.recipe("advanced_oil_processing")].fluidIngredients.enumerated() {
            XCTAssertGreaterThan(w.fluids.add(ref, box: j, fluid: ing.index, amount: 1000, temperature: 15), 0)
        }
        w.step(60 * 10)
        XCTAssertEqual(w.fluids.fluid(ref, box: 2), w.db.fluid("heavy_oil"))
        XCTAssertEqual(w.fluids.fluid(ref, box: 3), w.db.fluid("light_oil"))
        XCTAssertEqual(w.fluids.fluid(ref, box: 4), w.db.fluid("petroleum_gas"))
    }

    // MARK: Charting

    func testCharacterChartsSurroundings() {
        let w = TestWorld.make(mapSide: 512)
        w.player.position = Vec2(10.5, 10.5)
        w.step(2)
        XCTAssertTrue(w.isCharted(TilePos(10, 10).chunk))
        XCTAssertTrue(w.isCharted(ChunkPos(2, 2)))
        XCTAssertFalse(w.isCharted(ChunkPos(6, 6)), "far chunks stay in the fog")
        let (r, g, b) = w.mapColor(at: TilePos(10, 10))
        XCTAssertGreaterThan(r + g + b, 0)
        XCTAssertEqual(w.mapColor(at: TilePos(6 * 32, 6 * 32)).0, 0)
    }

    func testRadarScansFarChunks() {
        let w = TestWorld.make(mapSide: 1024)
        w.cheatInfinitePower = true
        let radar = w.place("radar", 20, 20)
        XCTAssertTrue(w.isCharted(ChunkPos(3, 3)), "nearby radius charted on build")
        let before = w.chartedChunkCount
        w.step(60 * 34 * 3)          // 300 kW → 10 MJ per sector ≈ 33 s → 3 sectors
        XCTAssertGreaterThanOrEqual(w.chartedChunkCount - before, 3)
        XCTAssertGreaterThanOrEqual(w.statics.radarProgress(of: radar), 0)
    }

    func testChartingSurvivesSaveLoad() throws {
        let w = TestWorld.make(mapSide: 1024)
        w.cheatInfinitePower = true
        w.place("radar", 20, 20)
        w.step(60 * 40)
        let n = w.chartedChunkCount
        let b = try GameSession.decode(payload: GameSession(world: w, mode: .freeplay).encodePayload())
        XCTAssertEqual(b.world.chartedChunkCount, n)
    }

    // MARK: Pollution

    func testPollutionFromWorkingMachines() {
        let w = TestWorld.make()
        let f = w.place("stone_furnace", 10, 10)
        _ = w.crafting.insert(f, item: w.item("coal"), count: 10, source: .player)
        _ = w.crafting.insert(f, item: w.item("iron_ore"), count: 50, source: .player)
        w.step(60 * 61)
        // stone furnace 2/min while working
        XCTAssertEqual(w.pollution.perMinute, 2, accuracy: 0.2)
        XCTAssertGreaterThan(w.pollution.total, 1.5)
        let b = try? GameSession.decode(payload: GameSession(world: w, mode: .freeplay).encodePayload())
        XCTAssertEqual(b?.world.pollution.total ?? 0, w.pollution.total, accuracy: 1e-9)
    }

    // MARK: Copy / paste area

    private func buildSample(_ w: World) {
        let a = w.place("assembling_machine_2", 2, 2)
        _ = w.crafting.setRecipe(a, w.db.recipe("iron_gear_wheel"))
        let ins = w.place("filter_inserter", 5, 3, .east)
        w.inserters.setFilter(ins, slot: 0, item: w.item("iron_plate"))
        let chest = w.place("iron_chest", 6, 3)
        w.containers.setBar(chest, 4)
        w.place("transport_belt", 2, 6, .east)
        w.place("underground_belt", 3, 6, .east)
        w.place("underground_belt", 6, 6, .east)
    }

    func testCopyPasteAreaKeepsSettings() {
        let w = TestWorld.make()
        buildSample(w)
        let bp = w.captureBlueprint(TileRect(x: 0, y: 0, w: 10, h: 10))
        XCTAssertEqual(bp.entries.count, 6)
        XCTAssertEqual(bp.width, 5); XCTAssertEqual(bp.height, 5)
        let req = bp.requiredItems(db: w.db)
        XCTAssertEqual(req[w.item("underground_belt")], 2)
        // paste at (20, 20); give the player the items and stand nearby
        w.player.position = Vec2(22.5, 22.5)
        for (item, n) in req { w.player.give(item, n) }
        XCTAssertTrue(w.execute(.pasteBlueprint(bp, origin: TilePos(20, 20))).isOK)
        w.step(31)
        let a = w.entity(at: TilePos(20, 20))!
        XCTAssertFalse(w.entities[a].flags.contains(.ghost), "ghost auto-built")
        XCTAssertEqual(w.crafting.recipe(of: a), w.db.recipe("iron_gear_wheel"))
        let ins = w.entity(at: TilePos(23, 21))!
        XCTAssertEqual(w.inserters.filters(of: ins).first, w.item("iron_plate"))
        XCTAssertEqual(w.containers.bar(of: w.entity(at: TilePos(24, 21))!), 4)
        XCTAssertTrue(w.belts.isUndergroundEntrance(w.entity(at: TilePos(21, 24))!))
        XCTAssertFalse(w.belts.isUndergroundEntrance(w.entity(at: TilePos(24, 24))!))
    }

    func testRotatedBlueprint() {
        let w = TestWorld.make()
        w.place("transport_belt", 0, 0, .east)
        w.place("transport_belt", 1, 0, .east)
        w.place("transport_belt", 2, 0, .east)
        let bp = w.captureBlueprint(TileRect(x: 0, y: 0, w: 3, h: 1)).rotated(1, db: w.db)
        XCTAssertEqual(bp.width, 1); XCTAssertEqual(bp.height, 3)
        XCTAssertTrue(bp.entries.allSatisfy { $0.direction == .south })
        XCTAssertEqual(Set(bp.entries.map { $0.dy }), [0, 1, 2])
        XCTAssertEqual(w.pasteBlueprint(bp, at: TilePos(10, 10)), 3)
        XCTAssertEqual(w.entities[w.entity(at: TilePos(10, 12))!].direction, .south)
    }

    func testGhostSettingsSurviveSaveLoad() throws {
        let w = TestWorld.make()
        buildSample(w)
        let bp = w.captureBlueprint(TileRect(x: 0, y: 0, w: 10, h: 10))
        w.pasteBlueprint(bp, at: TilePos(30, 30))
        let b = try GameSession.decode(payload: GameSession(world: w, mode: .freeplay).encodePayload())
        let g = b.world.entity(at: TilePos(30, 30))!
        XCTAssertEqual(b.world.ghostSettingsPreview(g)?.recipe, "iron_gear_wheel")
    }

    // MARK: Tap-to-walk

    func testWalkAroundWall() {
        let w = playerWorld()
        w.player.position = Vec2(5.5, 10.5)
        for y in 3...17 { w.place("wooden_chest", 10, y) }        // wall of chests between start and goal
        XCTAssertTrue(w.execute(.walkTo(TilePos(15, 10))).isOK)
        var t = 0
        while w.player.isWalkingPath && t < 60 * 20 { w.step(); t += 1 }
        XCTAssertEqual(w.player.position.tile, TilePos(15, 10), "arrived around the wall")
    }

    func testWalkToBuildingStopsNextToIt() {
        let w = playerWorld()
        w.player.position = Vec2(2.5, 2.5)
        w.place("assembling_machine_1", 20, 20)
        XCTAssertTrue(w.execute(.walkTo(TilePos(21, 21))).isOK)
        w.step(60 * 10)
        XCTAssertLessThan(w.player.distance(to: TileRect(x: 20, y: 20, w: 3, h: 3)), 1.5)
    }

    func testUnreachableTarget() {
        let w = playerWorld()
        let water = w.db.tile("water")
        // island at (40,40) surrounded by water ring
        for y in 36...44 { for x in 36...44 where max(abs(x - 40), abs(y - 40)) >= 2 { w.surface.setTile(at: TilePos(x, y), water) } }
        XCTAssertEqual(w.execute(.walkTo(TilePos(40, 40))), .failed(.custom("Can't get there")))
    }

    func testJoystickCancelsPath() {
        let w = playerWorld()
        _ = w.execute(.walkTo(TilePos(40, 10)))
        w.step(10)
        w.player.moveInput = Vec2(0, 1)
        w.step(1)
        XCTAssertFalse(w.player.isWalkingPath)
        w.player.moveInput = .zero
    }
}
