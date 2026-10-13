// Gearforge — gameplay tests (map gen, character, crafting queue, hand mining, commands, undo). 05 §4.4, §11, §12, §14.

import XCTest
@testable import FactoryCore

final class GameplayTests: XCTestCase {

    private func playerWorld() -> World {
        let w = TestWorld.make()
        w.player.position = Vec2(10.5, 10.5)
        return w
    }

    // MARK: Map generation

    func testMapGenIsDeterministic() {
        var s = WorldSettings(); s.seed = 1234; s.width = 256; s.height = 256
        let a = World(settings: s), b = World(settings: s)
        for p in [TilePos(0, 0), TilePos(37, -20), TilePos(-100, 90), TilePos(120, 120)] {
            _ = a.surface.chunk(at: p); _ = b.surface.chunk(at: p)
            XCTAssertEqual(a.surface.tile(at: p), b.surface.tile(at: p))
            XCTAssertEqual(a.surface.resource(at: p).0, b.surface.resource(at: p).0)
            XCTAssertEqual(a.surface.resource(at: p).1, b.surface.resource(at: p).1)
        }
        XCTAssertEqual(a.entities.liveCount, b.entities.liveCount)
    }

    func testStartingResourcesNearSpawn() {
        var s = WorldSettings(); s.seed = 99; s.width = 512; s.height = 512
        let w = World(settings: s)
        let found = w.mapGen.resourceSummaryByID(in: TileRect(x: -96, y: -96, w: 192, h: 192))
        for id in ["iron_ore", "copper_ore", "coal", "stone"] {
            XCTAssertGreaterThan(found[id] ?? 0, 1000, "starting \(id) patch near spawn")
        }
        // spawn tile must be walkable land
        let sp = w.mapGen.spawnPosition
        _ = w.surface.chunk(at: sp)
        XCTAssertFalse(w.db.tiles[w.surface.tile(at: sp)].isWater)
    }

    // MARK: Character

    func testMovementAndCollision() {
        let w = playerWorld()
        w.place("iron_chest", 12, 10)
        w.player.moveInput = Vec2(1, 0)
        w.step(60)
        XCTAssertLessThan(w.player.position.x, 12, "chest blocks the way")
        w.player.moveInput = Vec2(0, 1)
        w.step(20)
        XCTAssertGreaterThan(w.player.position.y, 12)
        w.player.moveInput = .zero
    }

    func testHandMineIronOre() {
        let w = playerWorld()
        let p = TilePos(11, 11)
        w.surface.setResource(at: p, w.db.resource("iron_ore"), amount: 3)
        XCTAssertTrue(w.execute(.startMining(p)).isOK)
        w.step(60 * 2 + 2)          // 2 s per ore
        XCTAssertEqual(w.player.count(of: w.item("iron_ore")), 1)
        w.step(60 * 4 + 4)
        XCTAssertEqual(w.player.count(of: w.item("iron_ore")), 3)
        XCTAssertEqual(w.surface.resource(at: p).1, 0)
        XCTAssertNil(w.player.miningTarget)
        XCTAssertEqual(w.execute(.startMining(TilePos(30, 30))), .failed(.nothingThere))
    }

    func testHandMineTreeOutOfReach() {
        let w = playerWorld()
        let tree = w.place("tree_01", 20, 20)
        w.entities.update(tree) { $0.flags = [] }
        XCTAssertEqual(w.execute(.startMining(TilePos(20, 20))), .failed(.outOfReach))
        w.player.position = Vec2(18.5, 20.5)
        XCTAssertTrue(w.execute(.startMining(TilePos(20, 20))).isOK)
        w.step(80)
        XCTAssertEqual(w.player.count(of: w.item("wood")), 4)
        XCTAssertNil(w.entity(at: TilePos(20, 20)))
    }

    func testChainCraftBurnerDrill() {
        let w = playerWorld()
        let drillR = w.db.recipe("burner_mining_drill")
        // burner drill: 3 gears + 1 stone furnace + 3 iron plates → needs 9 plates + 5 stone
        w.player.give(w.item("iron_plate"), 9)
        w.player.give(w.item("stone"), 5)
        XCTAssertEqual(w.player.craftableCount(drillR), 1)
        XCTAssertTrue(w.execute(.craft(recipe: drillR, count: 1)).isOK)
        XCTAssertEqual(w.player.count(of: w.item("iron_plate")), 0, "ingredients removed when queued")
        XCTAssertGreaterThan(w.player.craftQueue.count, 1, "intermediates auto-queued")
        w.step(60 * 10)
        XCTAssertEqual(w.player.count(of: w.item("burner_mining_drill")), 1)
        XCTAssertTrue(w.player.craftQueue.isEmpty)
        XCTAssertEqual(w.player.count(of: w.item("iron_gear_wheel")), 0)
    }

    func testCancelCraftRefunds() {
        let w = playerWorld()
        let gearR = w.db.recipe("iron_gear_wheel")
        w.player.give(w.item("iron_plate"), 20)
        XCTAssertTrue(w.execute(.craft(recipe: gearR, count: 10)).isOK)
        w.step(31 * 2)            // 2 gears done (0.5 s each)
        XCTAssertTrue(w.execute(.cancelCraft(queueIndex: 0)).isOK)
        let plates = w.player.count(of: w.item("iron_plate")), gears = w.player.count(of: w.item("iron_gear_wheel"))
        XCTAssertEqual(plates + gears * 2, 20, "nothing lost")
        XCTAssertGreaterThanOrEqual(gears, 1)
    }

    func testCannotCraftUnresearched() {
        let w = playerWorld()
        w.player.give(w.item("iron_plate"), 100)
        w.player.give(w.item("electronic_circuit"), 100)
        w.player.give(w.item("iron_gear_wheel"), 100)
        XCTAssertEqual(w.execute(.craft(recipe: w.db.recipe("assembling_machine_1"), count: 1)), .failed(.notResearched))
    }

    // MARK: Commands

    func testBuildRemoveUndoRedo() {
        let w = playerWorld()
        let chest = w.item("iron_chest")
        w.player.give(chest, 2)
        XCTAssertTrue(w.execute(.build(item: chest, origin: TilePos(12, 12), direction: .north)).isOK)
        XCTAssertEqual(w.player.count(of: chest), 1)
        XCTAssertEqual(w.execute(.build(item: chest, origin: TilePos(12, 12), direction: .north)), .failed(.blocked))
        XCTAssertEqual(w.execute(.build(item: chest, origin: TilePos(40, 40), direction: .north)), .failed(.outOfReach))
        let e = w.entity(at: TilePos(12, 12))!
        _ = w.containers.insert(e, item: w.item("coal"), count: 30, source: .player)
        XCTAssertTrue(w.execute(.remove(entity: e)).isOK)
        XCTAssertEqual(w.player.count(of: chest), 2)
        XCTAssertEqual(w.player.count(of: w.item("coal")), 30, "contents returned")
        XCTAssertTrue(w.undo().isOK)                 // undo remove → rebuilt
        XCTAssertNotNil(w.entity(at: TilePos(12, 12)))
        XCTAssertEqual(w.player.count(of: chest), 1)
        XCTAssertTrue(w.redo().isOK)                 // redo remove
        XCTAssertNil(w.entity(at: TilePos(12, 12)))
    }

    func testFastReplaceBeltKeepsDirection() {
        let w = playerWorld()
        w.player.give(w.item("transport_belt"), 1)
        w.player.give(w.item("fast_transport_belt"), 1)
        XCTAssertTrue(w.execute(.build(item: w.item("transport_belt"), origin: TilePos(11, 11), direction: .east)).isOK)
        XCTAssertTrue(w.execute(.build(item: w.item("fast_transport_belt"), origin: TilePos(11, 11), direction: .east)).isOK)
        let e = w.entity(at: TilePos(11, 11))!
        XCTAssertEqual(w.db.entities[Int(w.entities[e].proto)].id, "fast_transport_belt")
        XCTAssertEqual(w.entities[e].direction, .east)
        XCTAssertEqual(w.player.count(of: w.item("transport_belt")), 1, "old belt returned")
    }

    func testFastReplaceChestKeepsContents() {
        let w = playerWorld()
        w.player.give(w.item("wooden_chest"), 1); w.player.give(w.item("iron_chest"), 1)
        _ = w.execute(.build(item: w.item("wooden_chest"), origin: TilePos(11, 11), direction: .north))
        let c = w.entity(at: TilePos(11, 11))!
        _ = w.containers.insert(c, item: w.item("stone"), count: 77, source: .player)
        XCTAssertTrue(w.execute(.build(item: w.item("iron_chest"), origin: TilePos(11, 11), direction: .north)).isOK)
        let n = w.entity(at: TilePos(11, 11))!
        XCTAssertEqual(w.containers.inventory(of: n)?.count(of: w.item("stone")), 77)
        XCTAssertEqual(w.player.count(of: w.item("stone")), 0)
    }

    func testCannotBuildOnWaterAndOffshoreNeedsShore() {
        let w = playerWorld()
        let water = w.db.tile("water")
        for y in 0..<30 { w.surface.setTile(at: TilePos(5, y), water) }
        w.player.give(w.item("iron_chest"), 1); w.player.give(w.item("offshore_pump"), 1)
        XCTAssertEqual(w.execute(.build(item: w.item("iron_chest"), origin: TilePos(5, 10), direction: .north)), .failed(.water))
        XCTAssertEqual(w.execute(.build(item: w.item("offshore_pump"), origin: TilePos(10, 10), direction: .west)), .failed(.needsShoreline))
        XCTAssertTrue(w.execute(.build(item: w.item("offshore_pump"), origin: TilePos(6, 10), direction: .west)).isOK)
    }

    func testDrillNeedsResource() {
        let w = playerWorld()
        w.player.give(w.item("burner_mining_drill"), 1)
        XCTAssertEqual(w.execute(.build(item: w.item("burner_mining_drill"), origin: TilePos(11, 11), direction: .north)), .failed(.noResourceUnderDrill))
        w.surface.setResource(at: TilePos(12, 12), w.db.resource("coal"), amount: 100)
        XCTAssertTrue(w.execute(.build(item: w.item("burner_mining_drill"), origin: TilePos(11, 11), direction: .north)).isOK)
    }

    func testRotateAndTransfer() {
        let w = playerWorld()
        w.player.give(w.item("inserter"), 1)
        _ = w.execute(.build(item: w.item("inserter"), origin: TilePos(11, 11), direction: .north))
        let ins = w.entity(at: TilePos(11, 11))!
        XCTAssertTrue(w.execute(.rotate(entity: ins, clockwise: true)).isOK)
        XCTAssertEqual(w.entities[ins].direction, .east)
        w.player.give(w.item("stone_furnace"), 1); w.player.give(w.item("coal"), 10)
        _ = w.execute(.build(item: w.item("stone_furnace"), origin: TilePos(8, 8), direction: .north))
        let f = w.entity(at: TilePos(8, 8))!
        XCTAssertTrue(w.execute(.transferToEntity(entity: f, item: w.item("coal"), count: 10)).isOK)
        XCTAssertEqual(w.player.count(of: w.item("coal")), 0)
        XCTAssertTrue(w.execute(.takeAll(entity: f)).isOK)
        XCTAssertEqual(w.player.count(of: w.item("coal")), 10)
    }

    func testGhostAutoBuild() {
        let w = playerWorld()
        let p = w.proto("wooden_chest")
        XCTAssertTrue(w.execute(.buildGhost(entityProto: p, origin: TilePos(13, 13), direction: .north)).isOK)
        XCTAssertTrue(w.entities[w.entity(at: TilePos(13, 13))!].flags.contains(.ghost))
        w.player.give(w.item("wooden_chest"), 1)
        w.step(31)
        let e = w.entity(at: TilePos(13, 13))!
        XCTAssertFalse(w.entities[e].flags.contains(.ghost))
        XCTAssertEqual(w.player.count(of: w.item("wooden_chest")), 0)
    }

    func testStartingKit() {
        let w = playerWorld()
        w.player.giveStartingKit()
        XCTAssertEqual(w.player.count(of: w.item("burner_mining_drill")), 1)
        XCTAssertEqual(w.player.count(of: w.item("iron_plate")), 8)
    }

    func testCharacterSaveRoundTrip() throws {
        let w = playerWorld()
        w.player.give(w.item("iron_plate"), 50)
        _ = w.execute(.craft(recipe: w.db.recipe("iron_gear_wheel"), count: 5))
        w.step(20)
        var wr = BinaryWriter()
        w.player.serialize(to: &wr)
        let pos = w.player.position, queue = w.player.craftQueue
        var rd = BinaryReader(wr.bytes)
        try w.player.deserialize(from: &rd)
        XCTAssertEqual(w.player.position, pos)
        XCTAssertEqual(w.player.craftQueue, queue)
        w.step(60 * 3)
        XCTAssertEqual(w.player.count(of: w.item("iron_gear_wheel")), 5)
    }
}
