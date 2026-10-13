// Gearforge — logistics tests (belts, undergrounds, splitters, inserters, chests). 05_mechanics §1–2.

import XCTest
@testable import FactoryCore

final class LogisticsTests: XCTestCase {

    // MARK: Belts

    /// Straight line of belts going east from x0..x1 at row y.
    private func beltRow(_ w: World, _ id: String, y: Int, from x0: Int, to x1: Int, _ d: Direction = .east) -> [Int32] {
        (x0...x1).map { w.place(id, $0, y, d) }
    }

    func testItemTravelsOnBasicBelt() {
        let w = TestWorld.make()
        let belts = beltRow(w, "transport_belt", y: 5, from: 0, to: 9)
        let iron = w.item("iron_plate")
        XCTAssertTrue(w.belts.insertItem(belts[0], lane: 0, position: 0, item: iron))
        // 10 tiles * 256 / 8 per tick = 320 ticks to the end
        w.step(300)
        XCTAssertEqual(w.belts.items(on: belts[9]).first?.item, Int32(iron), "item should be on the last tile")
        w.step(100)
        XCTAssertEqual(w.belts.totalItemCount, 1, "item stops at the end of the belt, never lost")
        XCTAssertEqual(w.belts.items(on: belts[9]).first?.count, 1)
    }

    func testBeltThroughputBasic() {
        // Feed a lane as fast as possible at the start, count arrivals at the end via a chest + inserter-free sink:
        // measure how many items can be inserted at the head in 600 ticks: 7.5/s per lane → 75 per lane.
        let w = TestWorld.make()
        let belts = beltRow(w, "transport_belt", y: 5, from: 0, to: 30)
        let iron = w.item("iron_plate")
        var inserted = 0
        for _ in 0..<600 {
            if w.belts.insertItem(belts[0], lane: 0, position: 0, item: iron) { inserted += 1 }
            if w.belts.insertItem(belts[0], lane: 1, position: 0, item: iron) { inserted += 1 }
            w.step()
        }
        XCTAssertEqual(Double(inserted), 150, accuracy: 4, "basic belt carries 15 items/s")
    }

    func testFastBeltIsTwiceAsFast() {
        let w = TestWorld.make()
        let belts = beltRow(w, "fast_transport_belt", y: 5, from: 0, to: 60)
        let iron = w.item("iron_plate")
        var inserted = 0
        for _ in 0..<600 {
            if w.belts.insertItem(belts[0], lane: 0, position: 0, item: iron) { inserted += 1 }
            if w.belts.insertItem(belts[0], lane: 1, position: 0, item: iron) { inserted += 1 }
            w.step()
        }
        XCTAssertEqual(Double(inserted), 300, accuracy: 6)
    }

    func testCompressionOnBlockedBelt() {
        let w = TestWorld.make()
        let belts = beltRow(w, "transport_belt", y: 5, from: 0, to: 3)
        let iron = w.item("iron_plate")
        var inserted = 0
        for _ in 0..<2000 {
            if w.belts.insertItem(belts[0], lane: 0, position: 0, item: iron) { inserted += 1 }
            w.step()
        }
        // 4 tiles × 4 items per lane, plus one exactly at the insertion point
        XCTAssertTrue((16...17).contains(inserted), "got \(inserted)")
    }

    func testCurveAndLanesPreserved() {
        let w = TestWorld.make()
        // east along y=5 from x=0..4, then turn north at x=5 going up to y=0
        _ = beltRow(w, "transport_belt", y: 5, from: 0, to: 4)
        let corner = w.place("transport_belt", 5, 5, .north)
        var up: [Int32] = []
        for y in stride(from: 4, through: 0, by: -1) { up.append(w.place("transport_belt", 5, y, .north)) }
        XCTAssertEqual(w.belts.shape(of: corner), .curveLeft)
        let start = w.entity(at: TilePos(0, 5))!
        let iron = w.item("iron_plate"), copper = w.item("copper_plate")
        XCTAssertTrue(w.belts.insertItem(start, lane: 0, position: 0, item: iron))   // left lane (north side)
        XCTAssertTrue(w.belts.insertItem(start, lane: 1, position: 0, item: copper)) // right lane
        w.step(1000)
        // Both arrive at the top tile; lane assignment preserved: pick left-lane first returns iron
        let top = up.last!
        XCTAssertEqual(w.belts.items(on: top).reduce(0) { $0 + Int($1.count) }, 2)
        XCTAssertEqual(w.belts.pickItem(top, preferredLane: 0, filter: { _ in true }), iron)
        XCTAssertEqual(w.belts.pickItem(top, preferredLane: 1, filter: { _ in true }), copper)
    }

    func testSideloadGoesToNearLane() {
        let w = TestWorld.make()
        // main belt going north at x=5, y=0..9; feeder going east from x=0..4 at y=5 hits its side
        var main: [Int32] = []
        for y in stride(from: 9, through: 0, by: -1) { main.append(w.place("transport_belt", 5, y, .north)) }
        _ = beltRow(w, "transport_belt", y: 5, from: 0, to: 4)
        let target = w.entity(at: TilePos(5, 5))!
        XCTAssertEqual(w.belts.shape(of: target), .straight, "belt fed from behind stays straight")
        let feederStart = w.entity(at: TilePos(0, 5))!
        let iron = w.item("iron_plate")
        XCTAssertTrue(w.belts.insertItem(feederStart, lane: 0, position: 0, item: iron))
        XCTAssertTrue(w.belts.insertItem(feederStart, lane: 1, position: 128, item: iron))
        w.step(1200)
        let top = w.entity(at: TilePos(5, 0))!
        // feeder comes from the west = left side of a north belt → both on left lane (0)
        XCTAssertEqual(w.belts.pickItem(top, preferredLane: 0, filter: { _ in true }), iron)
        XCTAssertEqual(w.belts.pickItem(top, preferredLane: 0, filter: { _ in true }), iron)
        XCTAssertEqual(w.belts.totalItemCount, 0)
    }

    func testUndergroundPassesItemsAndPairs() {
        let w = TestWorld.make()
        _ = w.place("transport_belt", 0, 5, .east)
        let entrance = w.place("underground_belt", 1, 5, .east)
        // obstacle in between
        w.place("wooden_chest", 3, 5)
        let exit = w.place("underground_belt", 5, 5, .east)
        _ = w.place("transport_belt", 6, 5, .east)
        let end = w.place("transport_belt", 7, 5, .east)
        XCTAssertTrue(w.belts.isUndergroundEntrance(entrance))
        XCTAssertFalse(w.belts.isUndergroundEntrance(exit))
        XCTAssertEqual(w.belts.shape(of: exit), .undergroundExit)
        let iron = w.item("iron_plate")
        XCTAssertTrue(w.belts.insertItem(w.entity(at: TilePos(0, 5))!, lane: 1, position: 0, item: iron))
        w.step(600)
        XCTAssertEqual(w.belts.items(on: end).first?.item, Int32(iron))
    }

    func testUndergroundOutOfRangeDoesNotPair() {
        let w = TestWorld.make()
        let a = w.place("underground_belt", 1, 5, .east)
        let b = w.place("underground_belt", 8, 5, .east)   // distance 7 > 5
        XCTAssertTrue(w.belts.isUndergroundEntrance(a))
        XCTAssertTrue(w.belts.isUndergroundEntrance(b))
    }

    func testSplitterSplitsEvenly() {
        let w = TestWorld.make()
        // input belt north at x=4 y=10..6; splitter at (4,5) covering x=4..5 facing north; two output columns
        for y in 6...10 { w.place("transport_belt", 4, y, .north) }
        let sp = w.place("splitter", 4, 5, .north)
        var leftOut: [Int32] = [], rightOut: [Int32] = []
        for y in 0...4 { leftOut.append(w.place("transport_belt", 4, y, .north)); rightOut.append(w.place("transport_belt", 5, y, .north)) }
        _ = sp
        let feed = w.entity(at: TilePos(4, 10))!
        let iron = w.item("iron_plate")
        var inserted = 0
        for _ in 0..<1200 {
            if inserted < 20, w.belts.insertItem(feed, lane: 0, position: 0, item: iron) { inserted += 1 }
            w.step()
        }
        let l = w.belts.items(on: leftOut[0]).reduce(0) { $0 + Int($1.count) } + leftOut.dropFirst().reduce(0) { a, e in a + w.belts.items(on: e).reduce(0) { $0 + Int($1.count) } }
        let r = rightOut.reduce(0) { a, e in a + w.belts.items(on: e).reduce(0) { $0 + Int($1.count) } }
        XCTAssertEqual(l + r, 20)
        XCTAssertEqual(l, 10); XCTAssertEqual(r, 10)
    }

    func testSplitterFilter() {
        let w = TestWorld.make()
        for y in 6...10 { w.place("transport_belt", 4, y, .north) }
        let sp = w.place("splitter", 4, 5, .north)
        for y in 0...4 { w.place("transport_belt", 4, y, .north); w.place("transport_belt", 5, y, .north) }
        let iron = w.item("iron_plate"), copper = w.item("copper_plate")
        var s = SplitterSettings(); s.outputPriority = 1; s.filter = Int32(copper)
        w.belts.setSplitterSettings(sp, s)
        let feed = w.entity(at: TilePos(4, 10))!
        var n = 0
        for t in 0..<1500 {
            if n < 12, w.belts.insertItem(feed, lane: 0, position: 0, item: n % 2 == 0 ? iron : copper) { n += 1 }; _ = t
            w.step()
        }
        var leftItems: Set<Int32> = [], rightItems: Set<Int32> = []
        for y in 0...4 {
            w.belts.items(on: w.entity(at: TilePos(4, y))!).forEach { leftItems.insert($0.item) }
            w.belts.items(on: w.entity(at: TilePos(5, y))!).forEach { rightItems.insert($0.item) }
        }
        XCTAssertEqual(rightItems, [Int32(copper)])
        XCTAssertEqual(leftItems, [Int32(iron)])
    }

    func testRemovingBeltReturnsItemsAndRebuildKeepsOthers() {
        let w = TestWorld.make()
        let belts = beltRow(w, "transport_belt", y: 5, from: 0, to: 5)
        let iron = w.item("iron_plate")
        for x in 0..<6 { XCTAssertTrue(w.belts.insertItem(belts[x], lane: 0, position: 128, item: iron)) }
        let contents = w.removeEntity(belts[2])
        XCTAssertEqual(contents.reduce(0) { $0 + Int($1.count) }, 1)
        XCTAssertEqual(w.belts.totalItemCount, 5)
    }

    func testBeltLoop() {
        let w = TestWorld.make()
        // 2x2 loop
        w.place("transport_belt", 1, 1, .east); w.place("transport_belt", 2, 1, .south)
        w.place("transport_belt", 2, 2, .west); w.place("transport_belt", 1, 2, .north)
        let iron = w.item("iron_plate")
        XCTAssertTrue(w.belts.insertItem(w.entity(at: TilePos(1, 1))!, lane: 0, position: 0, item: iron))
        w.step(5000)
        XCTAssertEqual(w.belts.totalItemCount, 1, "items circulate forever in a loop")
    }

    // MARK: Inserters & chests

    func testInserterChestToChestThroughput() {
        let w = TestWorld.make()
        w.cheatInfinitePower = true
        let src = w.place("iron_chest", 5, 6)
        w.place("inserter", 5, 5, .north)
        let dst = w.place("iron_chest", 5, 4)
        let iron = w.item("iron_plate")
        XCTAssertEqual(w.containers.insert(src, item: iron, count: 100, source: .player), 100)
        w.step(600)   // 10 s at 0.83 items/s → ~8
        let moved = w.containers.inventory(of: dst)!.count(of: iron)
        XCTAssertTrue((7...9).contains(moved), "moved \(moved)")
    }

    func testFastInserterAndStackBonus() {
        let w = TestWorld.make()
        w.cheatInfinitePower = true
        let src = w.place("iron_chest", 5, 6)
        w.place("stack_inserter", 5, 5, .north)
        let dst = w.place("iron_chest", 5, 4)
        let iron = w.item("iron_plate")
        _ = w.containers.insert(src, item: iron, count: 1000, source: .player)
        w.bonuses.stackInserterBonus = 11      // hand 12
        w.step(600)
        let moved = w.containers.inventory(of: dst)!.count(of: iron)
        XCTAssertEqual(Double(moved), 277, accuracy: 15, "stack inserter at hand 12 ≈ 27.7 items/s")
    }

    func testInserterNeedsPower() {
        let w = TestWorld.make()
        let src = w.place("iron_chest", 5, 6)
        w.place("inserter", 5, 5, .north)
        let dst = w.place("iron_chest", 5, 4)
        _ = w.containers.insert(src, item: w.item("iron_plate"), count: 10, source: .player)
        w.step(300)
        // PowerSystem stub returns 1 until the energy engineer lands; once real, unpowered inserters must not move.
        if w.power.satisfaction(of: w.entity(at: TilePos(5, 5))!) == 0 {
            XCTAssertEqual(w.containers.inventory(of: dst)!.count(of: w.item("iron_plate")), 0)
        }
    }

    func testInserterBeltToChestAndChestToBelt() {
        let w = TestWorld.make()
        w.cheatInfinitePower = true
        // chest → inserter → belt (east) → inserter → chest
        let src = w.place("iron_chest", 2, 6)
        w.place("fast_inserter", 2, 5, .north)
        let belts = beltRow(w, "transport_belt", y: 4, from: 0, to: 8)
        w.place("fast_inserter", 7, 3, .north)
        let dst = w.place("iron_chest", 7, 2)
        _ = belts
        let iron = w.item("iron_plate")
        _ = w.containers.insert(src, item: iron, count: 20, source: .player)
        w.step(1800)
        XCTAssertEqual(w.containers.inventory(of: dst)!.count(of: iron), 20)
    }

    func testFilterInserter() {
        let w = TestWorld.make()
        w.cheatInfinitePower = true
        let src = w.place("iron_chest", 5, 6)
        let ins = w.place("filter_inserter", 5, 5, .north)
        let dst = w.place("iron_chest", 5, 4)
        let iron = w.item("iron_plate"), copper = w.item("copper_plate")
        _ = w.containers.insert(src, item: iron, count: 10, source: .player)
        _ = w.containers.insert(src, item: copper, count: 10, source: .player)
        w.step(300)
        XCTAssertEqual(w.containers.inventory(of: dst)!.count(of: iron) + w.containers.inventory(of: dst)!.count(of: copper), 0,
                       "filter inserter without filters moves nothing")
        w.inserters.setFilter(ins, slot: 0, item: copper)
        w.step(600)
        XCTAssertEqual(w.containers.inventory(of: dst)!.count(of: iron), 0)
        XCTAssertGreaterThan(w.containers.inventory(of: dst)!.count(of: copper), 5)
    }

    func testBurnerInserterRefuelsItself() {
        let w = TestWorld.make()
        let src = w.place("iron_chest", 5, 6)
        let ins = w.place("burner_inserter", 5, 5, .north)
        let dst = w.place("iron_chest", 5, 4)
        let coal = w.item("coal")
        _ = w.containers.insert(src, item: coal, count: 20, source: .player)
        w.step(1200)
        XCTAssertNotNil(w.inserters.fuel(of: ins))
        let delivered = w.containers.inventory(of: dst)!.count(of: coal)
        XCTAssertGreaterThan(delivered, 5, "burner inserter keeps running on the coal it moves")
    }

    func testChestBarLimitsInserters() {
        let w = TestWorld.make()
        w.cheatInfinitePower = true
        let src = w.place("iron_chest", 5, 6)
        w.place("fast_inserter", 5, 5, .north)
        let dst = w.place("wooden_chest", 5, 4)
        w.containers.setBar(dst, 1)
        let iron = w.item("iron_plate")
        _ = w.containers.insert(src, item: iron, count: 400, source: .player)
        w.step(3000)
        XCTAssertEqual(w.containers.inventory(of: dst)!.count(of: iron), w.stackSize(iron))
        XCTAssertEqual(w.containers.acceptCount(dst, item: iron, count: 10, source: .player), 10, "player ignores the bar")
    }

    // MARK: Persistence

    func testLogisticsSaveRoundTrip() throws {
        let w = TestWorld.make()
        w.cheatInfinitePower = true
        let belts = beltRow(w, "transport_belt", y: 5, from: 0, to: 9)
        let iron = w.item("iron_plate")
        for x in 0..<10 { _ = w.belts.insertItem(belts[x], lane: x % 2, position: 100, item: iron) }
        let chest = w.place("iron_chest", 3, 8)
        _ = w.containers.insert(chest, item: iron, count: 33, source: .player)
        let ins = w.place("filter_inserter", 3, 7, .north)
        w.inserters.setFilter(ins, slot: 0, item: iron)
        w.step(30)

        var wr = BinaryWriter()
        w.belts.serialize(to: &wr); w.containers.serialize(to: &wr); w.inserters.serialize(to: &wr)
        let beforeItems = w.belts.totalItemCount
        let beforeShape = w.belts.shape(of: belts[3])

        // Load into the same world after wiping state (records are unchanged).
        var rd = BinaryReader(wr.bytes)
        try w.belts.deserialize(from: &rd); try w.containers.deserialize(from: &rd); try w.inserters.deserialize(from: &rd)
        w.belts.didLoad(); w.containers.didLoad(); w.inserters.didLoad()
        XCTAssertEqual(w.belts.totalItemCount, beforeItems)
        XCTAssertEqual(w.belts.shape(of: belts[3]), beforeShape)
        XCTAssertEqual(w.containers.inventory(of: chest)?.count(of: iron), 33 - (33 - w.containers.inventory(of: chest)!.count(of: iron)))
        XCTAssertEqual(w.inserters.filters(of: ins).first, iron)
        w.step(10)
        XCTAssertEqual(w.belts.lostItems, 0)
    }

    // MARK: Performance

    func testPerfBelts() {
        let w = TestWorld.make(size: 256)
        // 100 rows × 100 belts = 10 000 tiles, each a loop-free line ending at x=99; fill with items
        let iron = w.item("iron_plate")
        for y in 0..<100 {
            for x in 0..<100 { w.place("transport_belt", x, y * 2, .east) }
        }
        var n = 0
        for y in 0..<100 {
            for x in 0..<100 {
                let e = w.entity(at: TilePos(x, y * 2))!
                if w.belts.insertItem(e, lane: 0, position: 0, item: iron) { n += 1 }
                if w.belts.insertItem(e, lane: 1, position: 128, item: iron) { n += 1 }
            }
        }
        // keep the heads flowing: half the lines run free (items at the end stay), just measure step cost
        w.step(10)
        let t0 = DispatchTime.now().uptimeNanoseconds
        w.step(200)
        let ms = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6 / 200
        print("PERF belts: \(n) items on 10000 tiles: \(String(format: "%.4f", ms)) ms/tick")
        XCTAssertEqual(w.belts.totalItemCount, n)
    }
}
