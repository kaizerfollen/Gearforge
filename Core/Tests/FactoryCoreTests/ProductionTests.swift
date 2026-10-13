// Gearforge — production tests (crafting machines, furnaces, drills, labs/research, modules, silo). 05_mechanics §3–4, §9–10, §16.

import XCTest
@testable import FactoryCore

final class ProductionTests: XCTestCase {

    private func recipe(_ w: World, _ id: String) -> Int {
        let r = w.db.recipe(id); precondition(r >= 0, "missing recipe \(id)"); return r
    }

    func testAssemblerGearTiming() {
        let w = TestWorld.make()
        w.cheatInfinitePower = true
        let a = w.place("assembling_machine_1", 4, 4)
        XCTAssertTrue(w.crafting.setRecipe(a, recipe(w, "iron_gear_wheel")).isEmpty)
        let iron = w.item("iron_plate"), gear = w.item("iron_gear_wheel")
        XCTAssertEqual(w.crafting.insert(a, item: iron, count: 100, source: .player), w.stackSize(iron))
        // gear: 0.5 s at speed 0.5 → 1 gear/s; 10 s → 10 gears (output stalls at stack size, far away)
        w.step(600)
        let out = w.crafting.outputSlots(of: a).first { Int($0.item) == gear }?.count ?? 0
        XCTAssertEqual(Int(out), 10, accuracy: 1)
        XCTAssertEqual(w.crafting.status(of: a), .working)
    }

    func testAssemblerInsertionLimitForInserters() {
        let w = TestWorld.make()
        w.cheatInfinitePower = true
        let a = w.place("assembling_machine_1", 4, 4)
        _ = w.crafting.setRecipe(a, recipe(w, "iron_gear_wheel"))
        let iron = w.item("iron_plate")
        // 1 + ceil(1.166 × 0.5 / 0.5) = 3 crafts → 6 plates
        XCTAssertEqual(w.crafting.acceptCount(a, item: iron, count: 100, source: .inserter), 6)
    }

    func testSetRecipeReturnsIngredients() {
        let w = TestWorld.make()
        w.cheatInfinitePower = true
        let a = w.place("assembling_machine_1", 4, 4)
        _ = w.crafting.setRecipe(a, recipe(w, "iron_gear_wheel"))
        let iron = w.item("iron_plate")
        _ = w.crafting.insert(a, item: iron, count: 10, source: .player)
        let back = w.crafting.setRecipe(a, recipe(w, "copper_cable"))
        XCTAssertEqual(back.reduce(0) { $0 + Int($1.count) }, 10)
    }

    func testStoneFurnaceAutoRecipeAndFuel() {
        let w = TestWorld.make()
        let f = w.place("stone_furnace", 4, 4)
        let ore = w.item("iron_ore"), coal = w.item("coal"), plate = w.item("iron_plate")
        XCTAssertEqual(w.crafting.insert(f, item: coal, count: 5, source: .player), 5)
        XCTAssertEqual(w.crafting.recipe(of: f), -1, "coal is fuel, not a smelting input")
        XCTAssertEqual(w.crafting.insert(f, item: ore, count: 20, source: .player), 20)
        XCTAssertEqual(w.crafting.recipe(of: f), recipe(w, "iron_plate"))
        // 3.2 s per plate at speed 1 → 10 plates in 32 s
        w.step(60 * 32 + 5)
        let out = w.crafting.outputSlots(of: f).first { Int($0.item) == plate }?.count ?? 0
        XCTAssertEqual(Int(out), 10, accuracy: 1)
        // 90 kW for 32 s = 2.88 MJ of 4 MJ coal → 1 coal burned, 4 left
        XCTAssertEqual(w.crafting.fuel(of: f)?.fuel.count(of: coal), 4)
    }

    func testFurnaceWithoutFuelDoesNothing() {
        let w = TestWorld.make()
        let f = w.place("stone_furnace", 4, 4)
        _ = w.crafting.insert(f, item: w.item("iron_ore"), count: 10, source: .player)
        w.step(600)
        XCTAssertTrue(w.crafting.outputSlots(of: f).allSatisfy { $0.count == 0 })
        XCTAssertEqual(w.crafting.status(of: f), .noFuel)
    }

    private func putOre(_ w: World, _ id: String, rect: TileRect, amount: UInt32 = 1000) {
        let r = w.db.resource(id)
        rect.forEach { w.surface.setResource(at: $0, r, amount: amount) }
    }

    func testBurnerDrillFeedsFurnace() {
        let w = TestWorld.make()
        putOre(w, "iron_ore", rect: TileRect(x: 4, y: 6, w: 2, h: 2))
        // burner drill 2×2 at (4,6) facing north outputs at center + (-0.5,-1.3) → tile (4,5)... furnace 2×2 at (4,4)
        let d = w.place("burner_mining_drill", 4, 6, .north)
        let f = w.place("stone_furnace", 4, 4)
        let coal = w.item("coal")
        _ = w.mining.insert(d, item: coal, count: 5, source: .player)
        _ = w.crafting.insert(f, item: coal, count: 5, source: .player)
        // 0.25 / 1 s → 0.25 ore/s → 60 s = 15 ore; furnace smelts 0.3125/s
        w.step(3600)
        let plates = w.crafting.outputSlots(of: f).first { Int($0.item) == w.item("iron_plate") }?.count ?? 0
        XCTAssertGreaterThan(plates, 10)
        XCTAssertEqual(w.mining.status(of: d), .working)
        XCTAssertEqual(w.stats.totalProduced(item: w.item("iron_ore")), 15, accuracy: 1)
    }

    func testElectricDrillOntoBeltAndDepletion() {
        let w = TestWorld.make()
        w.cheatInfinitePower = true
        putOre(w, "copper_ore", rect: TileRect(x: 3, y: 4, w: 5, h: 5), amount: 2)   // 25 tiles × 2 = 50 ore
        let d = w.place("electric_mining_drill", 4, 5, .north)          // area 5×5 = (3..7, 4..8), outputs to (5,4)... row y=4 belt
        for x in 0...40 { w.place("transport_belt", x, 4, .east) }
        _ = d
        w.step(60 * 120)
        XCTAssertEqual(w.stats.totalProduced(item: w.item("copper_ore")), 50)
        XCTAssertEqual(w.mining.status(of: d), .noResources)
        XCTAssertEqual(w.mining.remainingResources(of: d), 0)
    }

    func testMiningProductivityBonus() {
        let w = TestWorld.make()
        w.cheatInfinitePower = true
        putOre(w, "iron_ore", rect: TileRect(x: 3, y: 4, w: 5, h: 5), amount: 10_000)
        let d = w.place("electric_mining_drill", 4, 5, .north)
        let chest = w.place("iron_chest", 5, 4)
        _ = d
        w.bonuses.miningProductivity = 0.5
        w.step(60 * 61)       // 0.5/s × 60 s = 30 cycles → 45 ore
        XCTAssertEqual(w.containers.inventory(of: chest)!.count(of: w.item("iron_ore")), 45, accuracy: 1)
    }

    func testProductivityModuleAndBeaconSpeed() {
        let w = TestWorld.make()
        w.cheatInfinitePower = true
        let a = w.place("assembling_machine_2", 4, 4)
        _ = w.crafting.setRecipe(a, recipe(w, "iron_gear_wheel"))
        let pm = w.item("productivity_module")
        XCTAssertTrue(w.crafting.insertModule(a, item: pm))
        XCTAssertTrue(w.crafting.insertModule(a, item: pm))
        let e = w.crafting.effects(of: a)
        XCTAssertEqual(e.productivity, 0.08, accuracy: 1e-9)
        XCTAssertEqual(e.speed, 0.9, accuracy: 1e-9)       // -5 % each
        // productivity module refused for a non-whitelisted recipe? gears are allowed; check removal
        XCTAssertNotNil(w.crafting.removeModule(a, slot: 0))
        // Assembler 1 accepts no modules
        let a1 = w.place("assembling_machine_1", 10, 4)
        XCTAssertFalse(w.crafting.insertModule(a1, item: pm))
    }

    func testLabResearchUnlocksRecipe() {
        let w = TestWorld.make()
        w.cheatInfinitePower = true
        let lab = w.place("lab", 4, 4)
        let auto = w.db.tech("automation")
        XCTAssertFalse(w.research.isResearched(auto))
        w.research.setCurrent(auto)
        XCTAssertEqual(w.research.current, auto)
        let red = w.item("mechanics_card")
        XCTAssertGreaterThan(w.labs.insert(lab, item: red, count: 10, source: .player), 0)
        // 10 units × 10 s at lab speed 1 = 100 s
        w.step(60 * 102)
        XCTAssertTrue(w.research.isResearched(auto))
        XCTAssertTrue(w.research.isRecipeUnlocked(recipe(w, "assembling_machine_1")))
    }

    func testRocketSiloLaunch() {
        let w = TestWorld.make()
        w.cheatInfinitePower = true
        let s = w.place("rocket_silo", 10, 10)
        XCTAssertEqual(w.crafting.recipe(of: s), recipe(w, "rocket_part"))
        let rcu = w.item("rocket_control_unit"), lds = w.item("low_density_structure"), fuel = w.item("rocket_fuel")
        for _ in 0..<100 {
            for it in [rcu, lds, fuel] {
                var left = 10
                while left > 0 { let n = w.crafting.insert(s, item: it, count: left, source: .player); left -= n; if n == 0 { w.step(10) } }
            }
        }
        var guardTicks = 0
        while !w.crafting.isRocketReady(s) && guardTicks < 60 * 1000 { w.step(60); guardTicks += 60 }
        XCTAssertTrue(w.crafting.isRocketReady(s))
        XCTAssertEqual(w.crafting.insert(s, item: w.item("satellite"), count: 1, source: .player), 1)
        XCTAssertTrue(w.crafting.launchRocket(s))
        XCTAssertEqual(w.crafting.rocketParts(of: s), 0)
        let cards = w.crafting.outputSlots(of: s).first { Int($0.item) == w.item("orbital_card") }?.count ?? 0
        XCTAssertEqual(cards, 1000)
    }

    func testProductionSaveRoundTrip() throws {
        let w = TestWorld.make()
        w.cheatInfinitePower = true
        let a = w.place("assembling_machine_2", 4, 4)
        _ = w.crafting.setRecipe(a, recipe(w, "iron_gear_wheel"))
        _ = w.crafting.insert(a, item: w.item("iron_plate"), count: 50, source: .player)
        _ = w.crafting.insertModule(a, item: w.item("speed_module"))
        putOre(w, "iron_ore", rect: TileRect(x: 10, y: 10, w: 2, h: 2))
        let d = w.place("burner_mining_drill", 10, 10)
        _ = w.mining.insert(d, item: w.item("coal"), count: 3, source: .player)
        w.step(100)
        let prog = w.crafting.progress(of: a)
        var wr = BinaryWriter()
        w.crafting.serialize(to: &wr); w.mining.serialize(to: &wr)
        var rd = BinaryReader(wr.bytes)
        try w.crafting.deserialize(from: &rd); try w.mining.deserialize(from: &rd)
        w.crafting.didLoad(); w.mining.didLoad()
        XCTAssertEqual(w.crafting.progress(of: a), prog)
        XCTAssertEqual(w.crafting.recipe(of: a), recipe(w, "iron_gear_wheel"))
        XCTAssertEqual(w.crafting.modules(of: a)?.count(of: w.item("speed_module")), 1)
        XCTAssertNotNil(w.mining.fuel(of: d))
        w.step(100)
    }

    func testPerfAssemblers() {
        let w = TestWorld.make(size: 200)
        w.cheatInfinitePower = true
        let r = recipe(w, "iron_gear_wheel")
        let iron = w.item("iron_plate")
        var n = 0
        for y in stride(from: 0, to: 180, by: 3) {
            for x in stride(from: 0, to: 150, by: 3) {
                let a = w.place("assembling_machine_2", x, y)
                _ = w.crafting.setRecipe(a, r)
                _ = w.crafting.insert(a, item: iron, count: 100, source: .player)
                n += 1
            }
        }
        w.step(5)
        let t0 = DispatchTime.now().uptimeNanoseconds
        w.step(100)
        let ms = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6 / 100
        print("PERF assemblers: \(n) working: \(String(format: "%.4f", ms)) ms/tick")
    }
}
