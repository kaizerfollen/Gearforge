// Gearforge — independent QA regression coverage (owner: QA).
// Every test in this file PASSES on the current code; failing repros of open bugs live in QAFindingsTests.swift.

import XCTest
import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif
@testable import FactoryCore

// MARK: - Shared QA helpers

enum QA {
    /// Runs `body` in a forked child process and reports whether it finished without trapping.
    /// Lets a test assert "this command must not crash" without taking the whole test process down.
    static func survives(_ body: () -> Void) -> Bool {
        fflush(stdout); fflush(stderr)
        let pid = fork()
        if pid == 0 {
            setenv("SWIFT_BACKTRACE", "enable=no", 1)
            // silence the child's crash report
            let devnull = open("/dev/null", O_WRONLY)
            if devnull >= 0 { dup2(devnull, 2) }
            body()
            _exit(0)
        }
        var status: Int32 = 0
        _ = waitpid(pid, &status, 0)
        let signaled = (status & 0x7f) != 0
        let code = (status >> 8) & 0xff
        return !signaled && code == 0
    }

    /// Payload sections (tag → bytes) of an encoded world, for pinpointing save/load divergence.
    static func sections(_ bytes: [UInt8]) -> [(String, [UInt8])] {
        var r = BinaryReader(bytes)
        var out: [(String, [UInt8])] = []
        do {
            _ = try r.read(UInt8.self); _ = try r.read(UInt32.self); _ = try r.read(UInt32.self); _ = try r.read(UInt32.self)
            while !r.isAtEnd {
                let (tag, sub) = try r.readSection()
                var s = sub
                let name = String(bytes: [UInt8(tag & 0xff), UInt8((tag >> 8) & 0xff), UInt8((tag >> 16) & 0xff)], encoding: .ascii) ?? "?"
                let idx = tag >> 24
                out.append((name + (name == "SYS" ? "\(Int(idx) - 0x30)" : String(UnicodeScalar(UInt8(idx)))), (try? s.readRaw(s.remaining)) ?? []))
            }
        } catch { out.append(("ERR", [])) }
        return out
    }

    /// Names of the payload sections that differ between two worlds.
    static func differingSections(_ a: World, _ b: World) -> [String] {
        let sa = sections(WorldCodec.encode(a)), sb = sections(WorldCodec.encode(b))
        var diff: [String] = []
        for (x, y) in zip(sa, sb) where x.0 != y.0 || x.1 != y.1 { diff.append(x.0) }
        if sa.count != sb.count { diff.append("count") }
        return diff
    }

    /// Every item held by containers, belt lanes, inserter hands, the player's inventory + craft pools and the
    /// ground — summed per item (machine internals are not included; use it on logistics-only setups).
    static func itemCensus(_ w: World, includePlayer: Bool = true) -> [Int: Int] {
        var m: [Int: Int] = [:]
        func add(_ s: ItemStack) { if !s.isEmpty { m[Int(s.item), default: 0] += Int(s.count) } }
        w.entities.forEachLive { e, r in
            guard !r.flags.contains(.ghost) else { return }
            switch r.kind {
            case .container: for s in w.containers.inventory(of: e)!.slots { add(s) }
            case .inserter: add(w.inserters.heldStack(of: e))
            default: break
            }
        }
        // belts: per-entity lists miss items in hidden underground sections, so count the lines directly
        w.belts.ensureTopology()
        for line in w.belts.lines { for l in 0..<2 { let lane = line.lanes[l]; for i in 0..<lane.count { add(ItemStack(item: lane.items[i], count: 1)) } } }
        if includePlayer {
            for s in w.player.inventory.slots { add(s) }
            for g in w.player.craftGroups { for (k, v) in g.pool { m[Int(k), default: 0] += Int(v) } }
        }
        w.ground.forEach(in: TileRect(x: -10_000, y: -10_000, w: 20_000, h: 20_000)) { _, stacks in for s in stacks { add(s) } }
        return m.filter { $0.value != 0 }
    }

    @discardableResult
    static func place(_ w: World, _ id: String, _ x: Int, _ y: Int, _ d: Direction = .north,
                      file: StaticString = #filePath, line: UInt = #line) -> Int32 {
        let p = w.proto(id)
        if let err = w.canPlace(proto: p, origin: TilePos(x, y), direction: d) {
            XCTFail("cannot place \(id) at \(x),\(y): \(err)", file: file, line: line)
            return -1
        }
        return w.createEntity(proto: p, origin: TilePos(x, y), direction: d)
    }

    /// Mixed factory touching every simulated system (see QA report §1).
    static func mixedFactory() -> GameSession {
        let w = TestWorld.make(size: 56, seed: 99)
        let water = w.db.tile("water")
        for y in 0..<56 { for x in 0..<2 { w.surface.setTile(at: TilePos(x, y), water) } }
        // steam power
        place(w, "offshore_pump", 2, 15, .west); place(w, "pipe", 3, 15)
        let boiler = place(w, "boiler", 4, 14, .north)
        place(w, "steam_engine", 4, 9, .north); place(w, "steam_engine", 4, 4, .north)
        _ = w.power.insert(boiler, item: w.item("coal"), count: 50, source: .player)
        place(w, "small_electric_pole", 7, 10)
        place(w, "accumulator", 10, 4)
        place(w, "solar_panel", 12, 4)
        // ore → electric drill → belt → underground → splitter → two lanes → furnaces → chests
        let ore = w.db.resource("iron_ore")
        TileRect(x: 14, y: 20, w: 6, h: 6).forEach { w.surface.setResource(at: $0, ore, amount: 2000) }
        let drill = place(w, "electric_mining_drill", 15, 21, .north)          // outputs to (16,20)
        place(w, "transport_belt", 16, 20, .east); place(w, "transport_belt", 17, 20, .east)
        let ugIn = place(w, "underground_belt", 18, 20, .east)
        let ugOut = place(w, "underground_belt", 21, 20, .east)
        w.belts.setUndergroundMode(ugIn, entrance: true); w.belts.setUndergroundMode(ugOut, entrance: false)
        place(w, "transport_belt", 22, 20, .east)
        let sp = place(w, "splitter", 23, 20, .east)
        var ss = SplitterSettings(); ss.outputPriority = 1
        w.belts.setSplitterSettings(sp, ss)
        for x in 24...30 { place(w, "transport_belt", x, 20, .east); place(w, "transport_belt", x, 21, .east) }
        place(w, "inserter", 27, 19, .north)
        let f1 = place(w, "stone_furnace", 27, 17)
        place(w, "inserter", 29, 17, .east); place(w, "iron_chest", 30, 17)
        place(w, "fast_inserter", 27, 22, .south)
        let f2 = place(w, "stone_furnace", 27, 23)
        place(w, "long_handed_inserter", 29, 23, .east); place(w, "wooden_chest", 31, 23)
        place(w, "small_electric_pole", 26, 19); place(w, "small_electric_pole", 26, 22)
        for f in [f1, f2] { _ = w.crafting.insert(f, item: w.item("coal"), count: 20, source: .player) }
        _ = w.mining.insertModule(drill, item: w.item("speed_module"))
        // assembler with modules + beacon
        let asm = place(w, "assembling_machine_2", 34, 9)
        _ = w.crafting.setRecipe(asm, w.db.recipe("iron_gear_wheel"))
        _ = w.crafting.insertModule(asm, item: w.item("speed_module"))
        _ = w.crafting.insert(asm, item: w.item("iron_plate"), count: 200, source: .player)
        let beacon = place(w, "beacon", 34, 5)
        _ = w.beacons.insertModule(beacon, item: w.item("speed_module"))
        place(w, "inserter", 37, 10, .east); place(w, "iron_chest", 38, 10)
        // lab researching
        let lab = place(w, "lab", 40, 14)
        w.research.setCurrent(w.db.tech("automation"))
        _ = w.labs.insert(lab, item: w.item("mechanics_card"), count: 10, source: .player)
        // burner inserter between chests, burner drill dropping coal on the ground
        let c1 = place(w, "wooden_chest", 20, 30); place(w, "burner_inserter", 21, 30, .east); place(w, "wooden_chest", 22, 30)
        _ = w.containers.insert(c1, item: w.item("coal"), count: 40, source: .player)
        let coal = w.db.resource("coal")
        TileRect(x: 14, y: 30, w: 2, h: 2).forEach { w.surface.setResource(at: $0, coal, amount: 300) }
        let bd = place(w, "burner_mining_drill", 14, 30, .east)
        _ = w.mining.insert(bd, item: w.item("coal"), count: 5, source: .player)
        // pump → tank
        place(w, "offshore_pump", 2, 36, .west); place(w, "pipe", 3, 36)
        place(w, "pump", 4, 36, .east)
        place(w, "pipe", 6, 36); place(w, "pipe", 7, 36); place(w, "pipe", 7, 35)
        place(w, "storage_tank", 8, 35)
        // poles everywhere free
        for y in stride(from: 2, through: 44, by: 6) { for x in stride(from: 8, through: 44, by: 6) {
            let p = w.proto("medium_electric_pole")
            if w.canPlace(proto: p, origin: TilePos(x, y), direction: .north) == nil { w.createEntity(proto: p, origin: TilePos(x, y), direction: .north) }
        } }
        // ghost with settings + items on the ground
        let g = w.createEntity(proto: w.proto("assembling_machine_1"), origin: TilePos(44, 24), direction: .north, flags: [.playerBuilt, .ghost])
        var gs = GhostSettings(); gs.recipe = "iron_gear_wheel"
        w.setGhostSettings(gs, for: g)
        _ = w.ground.add(item: w.item("iron_plate"), count: 5, at: TilePos(20, 40))
        // player: hand-mining ore and crafting
        w.player.position = Vec2(18.5, 26.5)
        w.player.giveStartingKit()
        w.player.give(w.item("copper_plate"), 20)
        _ = w.execute(.craft(recipe: w.db.recipe("electronic_circuit"), count: 2))
        _ = w.execute(.startMining(TilePos(18, 25)))
        return GameSession(world: w, mode: .freeplay)
    }
}

extension QA {
    /// Closed logistics loop: belt ring with a splitter (+ side-loading return), an underground pair, and five
    /// inserters of four types moving items chest ↔ belt. Infinite power. Nothing enters or leaves the system.
    static func closedLoop() -> World {
        let w = TestWorld.make(size: 32)
        w.cheatInfinitePower = true
        for x in 5...13 where x != 9 { w.place("transport_belt", x, 5, .east) }
        w.place("splitter", 9, 5, .east)
        w.place("transport_belt", 10, 6, .east); w.place("transport_belt", 11, 6, .north)
        w.place("transport_belt", 14, 5, .south)
        let ui = w.place("underground_belt", 14, 6, .south), uo = w.place("underground_belt", 14, 9, .south)
        w.belts.setUndergroundMode(ui, entrance: true); w.belts.setUndergroundMode(uo, entrance: false)
        for x in 6...14 { w.place("transport_belt", x, 10, .west) }
        w.place("transport_belt", 5, 10, .north)
        for y in 6...9 { w.place("transport_belt", 5, y, .north) }
        let a = w.place("wooden_chest", 7, 3); w.place("inserter", 7, 4, .south)
        let b = w.place("wooden_chest", 7, 7); w.place("fast_inserter", 7, 6, .north)
        w.place("wooden_chest", 12, 3); w.place("stack_inserter", 12, 4, .north)
        w.place("wooden_chest", 12, 8); w.place("inserter", 12, 9, .north)
        w.place("long_handed_inserter", 10, 8, .north)
        _ = w.containers.insert(a, item: w.item("iron_plate"), count: 200, source: .player)
        _ = w.containers.insert(b, item: w.item("copper_plate"), count: 100, source: .player)
        return w
    }
}

final class QATests: XCTestCase {

    // MARK: 1. Save → load → continue

    /// Mixed factory (steam + solar + accumulator, belts/underground/splitter, 5 inserter types mid-swing, electric +
    /// burner drills with a module, furnaces mid-craft, assembler with module + beacon, lab researching, pump → tank,
    /// ground items, a ghost with settings, the player hand-mining and hand-crafting). After a load the re-encoded
    /// state must stay byte-identical to the original at every checkpoint.
    func testMixedFactorySaveLoadContinuesBitIdentically() throws {
        let a = QA.mixedFactory()
        a.run(ticks: 900)
        let b = try GameSession.decode(payload: a.encodePayload())
        // NB: right after load the fluid section is not byte-identical (segment → box re-split rounding, see
        // docs/team/qa.md "observations"); it re-converges on the first tick, so compare from +1.
        for n in [1, 60, 600, 1500] {
            a.run(ticks: n); b.run(ticks: n)
            XCTAssertEqual(QA.differingSections(a.world, b.world), [], "state after continuing +\(n) ticks (t=\(a.world.tick))")
        }
        let w = a.world
        XCTAssertGreaterThan(w.stats.totalProduced(item: w.item("iron_ore")), 10, "drill ran")
        XCTAssertGreaterThan(w.stats.totalProduced(item: w.item("iron_plate")), 2, "furnaces ran")
        XCTAssertGreaterThan(w.stats.totalProduced(item: w.item("iron_gear_wheel")), 5, "assembler ran")
        XCTAssertGreaterThan(w.research.progressUnits(of: w.db.tech("automation")), 0, "lab researched")
        XCTAssertGreaterThan(w.player.count(of: w.item("iron_ore")), 0, "player hand-mined")
    }

    func testClosedLoopSaveLoadContinuesIdentically() throws {
        let w = QA.closedLoop()
        w.step(777)
        let (b, _) = try WorldCodec.decode(WorldCodec.encode(w))
        b.cheatInfinitePower = true          // test-only flag, intentionally not saved
        // Belt item positions drift by 1/256 tile on load (QAFindingsTests.testBUG_14), so only conservation is
        // asserted here, plus full convergence once the lanes have compressed.
        for n in [1, 120, 900] {
            w.step(n); b.step(n)
            XCTAssertEqual(QA.itemCensus(w), QA.itemCensus(b), "+\(n)")
        }
        XCTAssertEqual(QA.differingSections(w, b), [], "converged")
    }

    // MARK: 2. Undo / redo, fast replace

    func testBuildRotateRemoveUndoRedoConservesItems() {
        let w = TestWorld.make(size: 32)
        w.player.position = Vec2(10.5, 10.5)
        let tb = w.item("transport_belt")
        w.player.give(tb, 5)
        let start = QA.itemCensus(w)
        XCTAssertTrue(w.execute(.build(item: tb, origin: TilePos(10, 12), direction: .east)).isOK)
        let e = w.entity(at: TilePos(10, 12))!
        XCTAssertTrue(w.execute(.rotate(entity: e, clockwise: true)).isOK)
        XCTAssertTrue(w.execute(.remove(entity: e)).isOK)
        XCTAssertTrue(w.undo().isOK, "undo remove")
        let back = w.entity(at: TilePos(10, 12))
        XCTAssertNotNil(back)
        if let b = back { XCTAssertEqual(w.entities[b].direction, .south, "undo restores the rotated direction") }
        XCTAssertTrue(w.redo().isOK, "redo remove")
        XCTAssertNil(w.entity(at: TilePos(10, 12)))
        // whatever further undo/redo do, no item is created or destroyed
        for _ in 0..<3 { _ = w.undo() }
        for _ in 0..<3 { _ = w.redo() }
        XCTAssertEqual(QA.itemCensus(w), start)
    }

    func testFastReplaceBeltsWithItemsConservesEverything() {
        let w = TestWorld.make(size: 32)
        w.cheatInfinitePower = true
        w.player.position = Vec2(10.5, 10.5)
        for x in 5...15 { w.place("transport_belt", x, 12, .east) }
        let src = w.place("wooden_chest", 3, 12); w.place("inserter", 4, 12, .east)
        _ = w.containers.insert(src, item: w.item("iron_plate"), count: 50, source: .player)
        w.step(400)
        XCTAssertGreaterThan(w.belts.totalItemCount, 3)
        let fb = w.item("fast_transport_belt"), tb = w.item("transport_belt"), fe = w.item("iron_plate")
        w.player.give(fb, 20)
        let before = QA.itemCensus(w)
        for x in 6...14 { XCTAssertTrue(w.execute(.build(item: fb, origin: TilePos(Int32(x), 12), direction: .east)).isOK) }
        let after = QA.itemCensus(w)
        XCTAssertEqual(after[fe], before[fe], "plates on the replaced belts are conserved")
        XCTAssertEqual(after[tb] ?? 0, (before[tb] ?? 0) + 9, "old belts returned")
        XCTAssertEqual(after[fb] ?? 0, (before[fb] ?? 0) - 9, "new belts consumed")
        XCTAssertEqual(w.entities[w.entity(at: TilePos(10, 12))!].proto, Int32(w.proto("fast_transport_belt")))
        XCTAssertEqual(w.entities[w.entity(at: TilePos(10, 12))!].direction, .east)
    }

    // MARK: 3. Item conservation

    func testClosedLoopConservesItemCount() {
        let w = QA.closedLoop()
        let start = QA.itemCensus(w, includePlayer: false)
        XCTAssertEqual(start.values.reduce(0, +), 300)
        var moved = false
        for _ in 0..<20 {
            w.step(300)
            XCTAssertEqual(QA.itemCensus(w, includePlayer: false), start, "t=\(w.tick)")
            if w.belts.totalItemCount > 0 { moved = true }
        }
        XCTAssertTrue(moved, "items actually circulated")
        let taken = w.containers.inventory(of: w.entity(at: TilePos(12, 3))!)!.contents().reduce(0) { $0 + $1.count }
        XCTAssertGreaterThan(taken, 0, "stack inserter took items off the loop")
    }

    // MARK: 4. Invalid commands fail cleanly (inputs that do NOT crash today)

    func testInvalidCommandsFailCleanly() {
        let w = TestWorld.make(size: 32)
        w.player.position = Vec2(10.5, 10.5)
        let chestItem = w.item("wooden_chest")
        w.player.give(chestItem, 5)
        // removed entities
        let dead = w.place("wooden_chest", 12, 12); w.removeEntity(dead)
        let deadBelt = w.place("transport_belt", 13, 12); w.removeEntity(deadBelt)
        let deadIns = w.place("filter_inserter", 14, 12); w.removeEntity(deadIns)
        for cmd: PlayerCommand in [.remove(entity: dead), .rotate(entity: dead, clockwise: true), .takeAll(entity: dead),
                                   .transferToEntity(entity: dead, item: chestItem, count: 1),
                                   .transferFromEntity(entity: dead, item: chestItem, count: 1),
                                   .setRecipe(entity: dead, recipe: 0), .pickUpBeltItems(entity: deadBelt),
                                   .setChestBar(entity: dead, bar: 2), .pasteSettings(from: dead, to: dead)] {
            XCTAssertFalse(w.execute(cmd).isOK, "\(cmd) on a removed entity must fail")
        }
        _ = w.execute(.setInserterFilter(entity: deadIns, slot: 0, item: 1))
        _ = w.execute(.removeModule(entity: dead, slot: 0))
        // zero / negative counts
        let c = w.place("wooden_chest", 11, 12)
        XCTAssertEqual(w.execute(.transferToEntity(entity: c, item: chestItem, count: 0)), .failed(.notInInventory))
        XCTAssertEqual(w.execute(.transferToEntity(entity: c, item: chestItem, count: -5)), .failed(.notInInventory))
        XCTAssertFalse(w.execute(.transferFromEntity(entity: c, item: chestItem, count: -5)).isOK)
        XCTAssertFalse(w.execute(.craft(recipe: w.db.recipe("iron_gear_wheel"), count: 0)).isOK)
        XCTAssertFalse(w.execute(.craft(recipe: w.db.recipe("iron_gear_wheel"), count: -3)).isOK)
        XCTAssertFalse(w.execute(.craft(recipe: -1, count: 1)).isOK)
        XCTAssertFalse(w.execute(.cancelCraft(queueIndex: -1)).isOK)
        XCTAssertFalse(w.execute(.cancelCraft(queueIndex: 99)).isOK)
        XCTAssertEqual(w.player.count(of: chestItem), 5)
        // out of bounds / unreachable tiles
        XCTAssertFalse(w.execute(.build(item: chestItem, origin: TilePos(100_000, 100_000), direction: .north)).isOK)
        XCTAssertFalse(w.execute(.buildGhost(entityProto: w.proto("wooden_chest"), origin: TilePos(100_000, 0), direction: .north)).isOK)
        XCTAssertFalse(w.execute(.startMining(TilePos(-100_000, 5))).isOK)
        XCTAssertFalse(w.execute(.pickUpGround(TilePos(-100_000, 5))).isOK)
        XCTAssertFalse(w.execute(.walkTo(TilePos(100_000, 100_000))).isOK)
        XCTAssertFalse(w.execute(.walkAndMine(TilePos(100_000, -100_000))).isOK)
        XCTAssertFalse(w.execute(.removeArea(TileRect(x: 1_000_000, y: 0, w: 4, h: 4), kinds: nil)).isOK)
        // placement rules
        w.surface.setTile(at: TilePos(9, 14), w.db.tile("water"))
        XCTAssertEqual(w.execute(.build(item: chestItem, origin: TilePos(9, 14), direction: .north)), .failed(.water))
        XCTAssertEqual(w.execute(.build(item: chestItem, origin: TilePos(11, 12), direction: .north)), .failed(.blocked))
        w.player.give(w.item("electric_mining_drill"), 1)
        XCTAssertEqual(w.execute(.build(item: w.item("electric_mining_drill"), origin: TilePos(6, 6), direction: .north)), .failed(.noResourceUnderDrill))
        w.player.give(w.item("offshore_pump"), 1)
        XCTAssertEqual(w.execute(.build(item: w.item("offshore_pump"), origin: TilePos(13, 8), direction: .north)), .failed(.needsShoreline))
        let ore = w.db.resource("iron_ore")
        w.surface.setResource(at: TilePos(8, 8), ore, amount: 10)
        XCTAssertTrue(w.execute(.build(item: chestItem, origin: TilePos(8, 8), direction: .north)).isOK, "chests may sit on ore")
        XCTAssertEqual(w.execute(.build(item: chestItem, origin: TilePos(40, 40), direction: .north)), .failed(.outOfReach))
        XCTAssertEqual(w.execute(.build(item: w.item("iron_chest"), origin: TilePos(10, 8), direction: .north)), .failed(.notInInventory))
        // research gating
        let am = w.place("assembling_machine_1", 14, 14)
        let locked = w.db.recipes.indices.first { !w.research.isRecipeUnlocked($0) && w.db.canCraft(entity: w.proto("assembling_machine_1"), recipe: $0) }
        XCTAssertNotNil(locked)
        if let r = locked {
            XCTAssertEqual(w.execute(.setRecipe(entity: am, recipe: r)), .failed(.notResearched))
            XCTAssertFalse(w.execute(.craft(recipe: r, count: 1)).isOK)
        }
        XCTAssertEqual(w.execute(.setRecipe(entity: c, recipe: w.db.recipe("iron_gear_wheel"))), .failed(.notAllowed), "chest has no recipe")
        w.step(10)
    }

    // MARK: 5. Hand crafting

    private func rawValue(_ w: World) -> (iron: Double, copper: Double) {
        var f = 0.0, c = 0.0
        for (k, v) in QA.itemCensus(w) {
            let n = Double(v)
            switch w.db.items[k].id {
            case "iron_plate": f += n
            case "copper_plate": c += n
            case "iron_gear_wheel": f += 2 * n
            case "copper_cable": c += 0.5 * n
            case "electronic_circuit": f += n; c += 1.5 * n
            case "inserter": f += 4 * n; c += 1.5 * n
            default: break
            }
        }
        return (f, c)
    }

    func testHandCraftChainCancelMidwayRefundsExactly() {
        let w = TestWorld.make(size: 16)
        w.player.give(w.item("iron_plate"), 40); w.player.give(w.item("copper_plate"), 20)
        let r0 = rawValue(w)
        XCTAssertTrue(w.execute(.craft(recipe: w.db.recipe("inserter"), count: 3)).isOK)
        XCTAssertTrue(w.execute(.craft(recipe: w.db.recipe("iron_gear_wheel"), count: 4)).isOK)
        for k in [1, 17, 31, 45, 61, 75] {
            w.step(k)
            let r = rawValue(w)
            XCTAssertEqual(r.iron, r0.iron, accuracy: 1e-9); XCTAssertEqual(r.copper, r0.copper, accuracy: 1e-9)
        }
        XCTAssertTrue(w.player.craftQueue.contains { $0.isIntermediate }, "cancelling mid-chain")
        XCTAssertTrue(w.execute(.cancelCraft(queueIndex: 0)).isOK)
        XCTAssertTrue(w.execute(.cancelCraft(queueIndex: 0)).isOK)
        XCTAssertTrue(w.player.craftQueue.isEmpty)
        let r = rawValue(w)
        XCTAssertEqual(r.iron, r0.iron, accuracy: 1e-9); XCTAssertEqual(r.copper, r0.copper, accuracy: 1e-9)
    }

    func testHandCraftCancelWithFullInventorySpillsInsteadOfLosing() {
        let w = TestWorld.make(size: 16)
        let fe = w.item("iron_plate")
        w.player.give(fe, 100)
        XCTAssertTrue(w.execute(.craft(recipe: w.db.recipe("iron_chest"), count: 10)).isOK)
        while w.player.give(w.item("stone"), 50) > 0 {}
        XCTAssertTrue(w.execute(.cancelCraft(queueIndex: 0)).isOK)
        XCTAssertEqual(QA.itemCensus(w)[fe], 100)
    }

    func testHandCraftPausesWhenFullAndResumes() {
        let w = TestWorld.make(size: 16)
        let fe = w.item("iron_plate"), gear = w.item("iron_gear_wheel"), stone = w.item("stone")
        w.player.give(fe, 4)
        XCTAssertTrue(w.execute(.craft(recipe: w.db.recipe("iron_gear_wheel"), count: 2)).isOK)
        while w.player.give(stone, 50) > 0 {}
        w.step(300)
        XCTAssertEqual(w.player.count(of: gear), 0)
        XCTAssertEqual(w.player.craftQueue.first?.count, 2, "paused, nothing lost")
        w.player.inventory.remove(item: stone, count: 50)
        w.step(300)
        XCTAssertEqual(w.player.count(of: gear), 2)
        XCTAssertTrue(w.player.craftQueue.isEmpty)
    }

    // MARK: 6. Power

    func testAccumulatorCarriesNightAndPoleRemovalSplitsNetwork() {
        let w = TestWorld.make(size: 48)
        w.place("solar_panel", 2, 2)
        let acc = w.place("accumulator", 6, 2)
        w.place("small_electric_pole", 5, 4); w.place("small_electric_pole", 10, 4); w.place("small_electric_pole", 15, 4)
        let lamp = w.place("small_lamp", 16, 5)
        w.place("small_electric_pole", 20, 4)
        let ins = w.place("inserter", 21, 5)
        w.step(6000)
        XCTAssertEqual(w.power.accumulatorCharge(of: acc), 5_000_000, accuracy: 1, "charged during the day")
        XCTAssertEqual(w.power.networkID(of: lamp), w.power.networkID(of: ins))
        w.step(12_500 - 6000)
        XCTAssertEqual(w.daylight, 0)
        let c1 = w.power.accumulatorCharge(of: acc)
        w.step(600)
        XCTAssertLessThan(w.power.accumulatorCharge(of: acc), c1, "discharging at night")
        XCTAssertEqual(w.power.satisfaction(of: lamp), 1, accuracy: 1e-9, "lamp powered by the accumulator")
        w.removeEntity(w.entity(at: TilePos(15, 4))!)
        w.step(2)
        XCTAssertNotEqual(w.power.networkID(of: lamp), w.power.networkID(of: ins))
        XCTAssertEqual(w.power.satisfaction(of: ins), 0, "cut-off side has no generator")
    }

    // MARK: 7. Fluids

    func testFluidPipeRemovalNeverCreatesFluidAndPumpIsOneWay() {
        let w = TestWorld.make(size: 32)
        var pipes: [Int32] = []
        for x in 3...12 { pipes.append(w.place("pipe", x, 5)) }
        let water = w.db.fluid("water")
        XCTAssertEqual(w.fluids.add(pipes[0], box: 0, fluid: water, amount: 700, temperature: 15), 700)
        w.step(1)
        func total() -> Double { pipes.filter { w.entities[$0].isAlive }.reduce(0) { $0 + w.fluids.amount($1, box: 0) } }
        XCTAssertEqual(total(), 700, accuracy: 1e-6)
        w.removeEntity(pipes[5])
        w.step(1)
        XCTAssertLessThanOrEqual(total(), 700 + 1e-6)
        XCTAssertGreaterThanOrEqual(total(), 600 - 1e-6, "only the removed pipe's share is lost")
        pipes[5] = w.place("pipe", 8, 5)
        w.step(5)
        XCTAssertLessThanOrEqual(total(), 700 + 1e-6)
        // mixing guard on normal placement
        let steamPipe = w.place("pipe", 14, 5)
        w.fluids.add(steamPipe, box: 0, fluid: w.db.fluid("steam"), amount: 50, temperature: 165)
        w.step(1)
        XCTAssertEqual(w.placementError(proto: w.proto("pipe"), origin: TilePos(13, 5), direction: .north), .wouldMixFluids)
        // pump: east-facing moves west → east only
        let v = TestWorld.make(size: 32)
        v.cheatInfinitePower = true
        let a = v.place("pipe", 3, 5); v.place("pump", 4, 5, .east); let b = v.place("pipe", 6, 5)
        v.fluids.add(b, box: 0, fluid: water, amount: 100, temperature: 15)
        v.step(30)
        XCTAssertEqual(v.fluids.amount(a, box: 0), 0, "no backflow")
        XCTAssertEqual(v.fluids.remove(b, box: 0, amount: 100), 100)
        v.fluids.add(a, box: 0, fluid: water, amount: 100, temperature: 15)
        v.step(30)
        XCTAssertEqual(v.fluids.amount(a, box: 0), 0, accuracy: 1e-6, "pumped forward")
        XCTAssertEqual(v.fluids.amount(b, box: 0), 100, accuracy: 1e-6)
    }

    // MARK: 8. Character mining / walking

    func testHandMiningDepletesTileAndDrillExhaustsExactly() {
        let w = TestWorld.make(size: 32)
        let ore = w.db.resource("iron_ore")
        w.surface.setResource(at: TilePos(10, 10), ore, amount: 3)
        w.player.position = Vec2(11.5, 11.5)
        XCTAssertTrue(w.execute(.startMining(TilePos(10, 10))).isOK)
        w.step(60 * 20)
        XCTAssertEqual(w.player.count(of: w.item("iron_ore")), 3)
        XCTAssertEqual(w.surface.resource(at: TilePos(10, 10)).0, -1, "tile depleted")
        XCTAssertNil(w.player.miningTarget, "mining stops on depletion")
        XCTAssertEqual(w.execute(.startMining(TilePos(10, 10))), .failed(.nothingThere))
        w.cheatInfinitePower = true
        TileRect(x: 20, y: 20, w: 3, h: 3).forEach { w.surface.setResource(at: $0, ore, amount: 2) }
        w.place("electric_mining_drill", 20, 20, .north)
        let ch = w.place("wooden_chest", 21, 19)
        w.step(60 * 60)
        XCTAssertEqual(w.containers.inventory(of: ch)!.count(of: w.item("iron_ore")), 18, "9 tiles × 2 ore, nothing more")
    }

    func testWalkToUnreachableIslandFailsCleanly() {
        let w = TestWorld.make(size: 32)
        let ore = w.db.resource("iron_ore")
        TileRect(x: 18, y: 18, w: 5, h: 5).forEach { w.surface.setTile(at: $0, w.db.tile("water")) }
        w.surface.setTile(at: TilePos(20, 20), w.db.tile("grass_1"))
        w.surface.setResource(at: TilePos(20, 20), ore, amount: 5)
        w.player.position = Vec2(5.5, 5.5)
        XCTAssertEqual(w.execute(.walkAndMine(TilePos(20, 20))), .failed(.outOfReach))
        XCTAssertFalse(w.execute(.walkTo(TilePos(20, 20))).isOK)
        XCTAssertFalse(w.player.isWalkingPath)
        w.step(60)
        XCTAssertEqual(w.player.position, Vec2(5.5, 5.5))
    }
}
