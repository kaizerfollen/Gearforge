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
}
