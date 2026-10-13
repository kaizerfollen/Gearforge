// Gearforge — energy tests (electric networks, steam power, solar, accumulators, fluids). 05_mechanics §5, §7, §8.

import XCTest
@testable import FactoryCore

final class EnergyTests: XCTestCase {

    /// Water column x = 0...1, y = 0...39.
    private func addWater(_ w: World) {
        let water = w.db.tile("water")
        for y in 0..<40 { for x in 0...1 { w.surface.setTile(at: TilePos(x, y), water) } }
    }

    /// offshore pump (2,15)→pipe (3,15)→boiler (4,14)→engine (4,9)→engine (4,4); pole at (7,10).
    @discardableResult
    private func steamPlant(_ w: World) -> (boiler: Int32, engines: [Int32], pole: Int32) {
        addWater(w)
        w.place("offshore_pump", 2, 15, .west)
        w.place("pipe", 3, 15)
        let boiler = w.place("boiler", 4, 14, .north)
        let e1 = w.place("steam_engine", 4, 9, .north)
        let e2 = w.place("steam_engine", 4, 4, .north)
        let pole = w.place("small_electric_pole", 7, 10)
        XCTAssertEqual(w.power.insert(boiler, item: w.item("coal"), count: 50, source: .player), 50)
        return (boiler, [e1, e2], pole)
    }

    func testSteamPlantPowersLab() {
        let w = TestWorld.make()
        let plant = steamPlant(w)
        let lab = w.place("lab", 8, 10)
        w.research.setCurrent(w.db.tech("automation"))
        _ = w.labs.insert(lab, item: w.item("mechanics_card"), count: 10, source: .player)
        w.step(600)
        XCTAssertTrue(w.power.isBoilerWorking(plant.boiler) || w.fluids.amount(plant.engines[0], box: 0) > 0)
        XCTAssertEqual(w.power.satisfaction(of: lab), 1, accuracy: 1e-9)
        XCTAssertEqual(w.power.networkID(of: lab), w.power.networkID(of: plant.engines[0]))
        XCTAssertGreaterThan(w.research.progress(of: w.db.tech("automation")), 0.03)
    }

    func testSteamPlantDelivers1_8MWAndBrownsOutWhenOverloaded() {
        let w = TestWorld.make()
        let plant = steamPlant(w)
        // 12 assembler 3 = 4.5 MW working demand
        let r = w.db.recipe("iron_gear_wheel")
        var asms: [Int32] = []
        for i in 0..<12 {
            let a = w.place("assembling_machine_3", 9 + (i % 4) * 3, 2 + (i / 4) * 3)
            _ = w.crafting.setRecipe(a, r)
            _ = w.crafting.insert(a, item: w.item("iron_plate"), count: 100, source: .player)
            asms.append(a)
        }
        // poles to connect the assembler block
        for (x, y) in [(12, 5), (18, 5), (12, 9), (18, 9), (24, 5)] { w.place("medium_electric_pole", x, y) }
        w.step(600)
        let net = w.power.networkID(of: asms[0])
        XCTAssertGreaterThanOrEqual(net, 0)
        XCTAssertEqual(net, w.power.networkID(of: plant.engines[0]), "assemblers must be on the plant network")
        let st = w.power.stats(network: net)!
        XCTAssertEqual(st.productionW, 1_800_000, accuracy: 60_000, "1 boiler + 2 engines = 1.8 MW")
        XCTAssertLessThan(w.power.satisfaction(of: asms[0]), 0.6)
        XCTAssertGreaterThan(w.power.satisfaction(of: asms[0]), 0.2)
    }

    func testUnconnectedConsumerHasNoPower() {
        let w = TestWorld.make()
        let a = w.place("assembling_machine_1", 30, 30)
        w.step(5)
        XCTAssertEqual(w.power.satisfaction(of: a), 0)
        XCTAssertEqual(w.power.networkID(of: a), -1)
    }

    func testPoleNetworkSplitsWhenPoleRemoved() {
        let w = TestWorld.make()
        let p1 = w.place("small_electric_pole", 0, 20), p2 = w.place("small_electric_pole", 6, 20), p3 = w.place("small_electric_pole", 12, 20)
        XCTAssertEqual(w.power.wiredPoles(of: p1), [p2])
        XCTAssertEqual(Set(w.power.wiredPoles(of: p2)), [p1, p3])
        XCTAssertEqual(w.power.networkID(of: p1), w.power.networkID(of: p3))
        w.removeEntity(p2)
        XCTAssertNotEqual(w.power.networkID(of: p1), w.power.networkID(of: p3))
    }

    func testSolarAndAccumulator() {
        let w = TestWorld.make()
        let panel = w.place("solar_panel", 0, 0)
        let acc = w.place("accumulator", 3, 0)
        w.place("medium_electric_pole", 5, 1)
        let lamp = w.place("lab", 6, 0)   // 60 kW consumer when researching
        _ = lamp
        w.step(60)
        XCTAssertEqual(w.daylight, 1)
        XCTAssertEqual(w.power.powerOutput(of: panel), 60_000, accuracy: 1, "idle lab drains little; surplus charges the accumulator")
        XCTAssertGreaterThan(w.power.accumulatorCharge(of: acc), 0)
        // Night: daylight 0 at 50 % of the day → accumulator discharges
        w.step(12_500)
        XCTAssertEqual(w.daylight, 0, accuracy: 0.01)
        let before = w.power.accumulatorCharge(of: acc)
        w.research.setCurrent(w.db.tech("automation"))
        _ = w.labs.insert(lamp, item: w.item("mechanics_card"), count: 10, source: .player)
        w.step(120)
        XCTAssertLessThan(w.power.accumulatorCharge(of: acc), before)
        XCTAssertEqual(w.power.satisfaction(of: lamp), 1, accuracy: 1e-9)
    }

    // MARK: Fluids

    func testOffshorePumpFillsTankThroughPipes() {
        let w = TestWorld.make()
        addWater(w)
        w.place("offshore_pump", 2, 15, .west)
        for x in 3...8 { w.place("pipe", x, 15) }
        // tank 3×3 connections at (-1,-2),(2,1),(1,2),(-2,-1) relative to centre: place so (-2,-1) neighbour = pipe (8,15)
        let tank = w.place("storage_tank", 9, 15)
        w.step(600)
        let c = w.fluids.segmentContents(of: tank)!
        XCTAssertEqual(c.fluid, w.db.fluid("water"))
        XCTAssertEqual(c.amount, 600 * 20, accuracy: 300, "offshore pump delivers 1200/s")
    }

    func testPipeToGroundPairs() {
        let w = TestWorld.make()
        addWater(w)
        w.place("offshore_pump", 2, 15, .west)
        w.place("pipe_to_ground", 3, 15, .west)   // above-ground faces west (pump), underground goes east
        w.place("wooden_chest", 5, 15)
        w.place("pipe_to_ground", 8, 15, .east)
        let end = w.place("pipe", 9, 15)
        w.step(120)
        XCTAssertEqual(w.fluids.fill(of: end).fluid, w.db.fluid("water"))
    }

    func testPumpMovesOneWay() {
        let w = TestWorld.make()
        addWater(w)
        w.place("offshore_pump", 2, 15, .west)
        w.place("pipe", 3, 15)
        w.place("pump", 4, 15, .east)        // 1×2 rotated east: 2×1 from (4,15) to (5,15); input west, output east
        let out = w.place("pipe", 6, 15)
        w.place("small_electric_pole", 4, 16)
        w.cheatInfinitePower = true
        w.step(120)
        XCTAssertEqual(w.fluids.fill(of: out).fluid, w.db.fluid("water"))
        XCTAssertGreaterThan(w.fluids.fill(of: out).fraction, 0.5)
    }

    func testFluidMixingIsPrevented() {
        let w = TestWorld.make()
        let plant = steamPlant(w)
        _ = plant
        w.step(300)
        // a pipe at (3,13) would touch nothing; one bridging the water pipe (3,15) and the steam engine side is checked:
        // steam segment touches tile (7,11) east of engine 1? engines connect only at their ends, so test via the water pipe:
        w.place("pipe", 3, 14)                    // joins the water segment
        XCTAssertFalse(w.fluids.wouldMixFluids(proto: w.proto("pipe"), origin: TilePos(3, 13), direction: .north))
        // pipe next to boiler steam output tile (5,13) is inside engine 1; a pipe between the water pipe (3,14) and a steam
        // pipe: build a steam pipe from engine 2's top end (5,3) and test a pipe that would touch both segments.
        w.place("pipe", 5, 3)
        w.place("pipe", 4, 3)
        w.place("pipe", 3, 3)
        for y in 4...12 { if w.canPlace(proto: w.proto("pipe"), origin: TilePos(2, y), direction: .north) == nil { w.place("pipe", 2, y) } }
        // (2,13) would connect water (3,13)? no — (3,13) is empty. Check pipe at (3,13): neighbours (3,14) water, (2,13) none.
        w.place("pipe", 2, 13)                    // steam column down to (2,13)
        w.step(60)
        XCTAssertTrue(w.fluids.wouldMixFluids(proto: w.proto("pipe"), origin: TilePos(3, 13), direction: .north),
                      "a pipe joining the water and steam segments must be rejected")
    }

    func testEnergySaveRoundTrip() throws {
        let w = TestWorld.make()
        let plant = steamPlant(w)
        w.step(300)
        let steamBefore = w.fluids.amount(plant.engines[0], box: 0)
        var wr = BinaryWriter()
        w.power.serialize(to: &wr); w.fluids.serialize(to: &wr)
        var rd = BinaryReader(wr.bytes)
        try w.power.deserialize(from: &rd); try w.fluids.deserialize(from: &rd)
        w.power.didLoad(); w.fluids.didLoad()
        XCTAssertEqual(w.fluids.amount(plant.engines[0], box: 0), steamBefore, accuracy: 1e-6)
        XCTAssertNotNil(w.power.boilerFuel(of: plant.boiler))
        w.step(60)
        XCTAssertTrue(w.power.isBoilerWorking(plant.boiler) || w.fluids.amount(plant.engines[0], box: 0) > 0)
    }

    func testPerfPower() {
        let w = TestWorld.make(size: 220)
        w.cheatInfinitePower = false
        // 40×50 grid of small poles every 5 tiles + inserters as consumers between them
        var consumers = 0
        for gy in 0..<40 {
            for gx in 0..<40 {
                w.place("small_electric_pole", gx * 5, gy * 5)
                for k in 1...3 { w.place("inserter", gx * 5 + k, gy * 5); consumers += 1 }
            }
        }
        w.place("solar_panel", 201, 0)
        w.step(5)
        let t0 = DispatchTime.now().uptimeNanoseconds
        w.step(100)
        let ms = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6 / 100
        print("PERF power: 1600 poles + \(consumers) inserters: \(String(format: "%.4f", ms)) ms/tick")
    }
}
