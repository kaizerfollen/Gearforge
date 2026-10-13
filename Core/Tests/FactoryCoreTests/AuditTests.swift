// Gearforge — audit tests: mechanics that were not covered by the first test pass (oil chain, beacons,
// research queue / infinite research, long-handed inserter, radar/lamp power, fluid recipes in assemblers).

import XCTest
@testable import FactoryCore

final class AuditTests: XCTestCase {

    func testPumpjackFeedsRefineryThroughPipes() {
        let w = TestWorld.make()
        w.cheatInfinitePower = true
        let oil = w.db.resource("crude_oil")
        w.surface.setResource(at: TilePos(11, 21), oil, amount: 300_000)      // centre tile of the pumpjack
        let pj = w.place("pumpjack", 10, 20, .north)                            // output at centre + (1,-2) → (12,19)
        for y in stride(from: 19, through: 15, by: -1) { w.place("pipe", 12, y) }
        // refinery 5×5 facing north: inputs at centre + (±1, 3) → place so input (-1,3)… simpler: rotate so inputs face the pipe.
        let ref = w.place("oil_refinery", 11, 10, .north)                       // centre (13.5,12.5): input (+1,3) → (14,15)? use pipe bend
        w.place("pipe", 13, 15); w.place("pipe", 14, 15)
        XCTAssertTrue(w.crafting.setRecipe(ref, w.db.recipe("basic_oil_processing")).isEmpty)
        w.step(60 * 30)
        let made = w.stats.totalProduced(fluid: w.db.fluid("petroleum_gas"))
        XCTAssertGreaterThan(w.stats.totalProduced(fluid: w.db.fluid("crude_oil")), 100, "pumpjack produces crude")
        XCTAssertGreaterThan(made, 0, "refinery makes petroleum gas from piped crude")
        _ = pj
    }

    func testChemicalPlantMakesPlasticFromGas() {
        let w = TestWorld.make()
        w.cheatInfinitePower = true
        let cp = w.place("chemical_plant", 10, 10)
        _ = w.crafting.setRecipe(cp, w.db.recipe("plastic_bar"))
        _ = w.crafting.insert(cp, item: w.item("coal"), count: 10, source: .player)
        // fill the gas input box directly
        let gas = w.db.fluid("petroleum_gas")
        var added = 0.0
        for b in 0..<w.fluids.boxCount(cp) { added += w.fluids.add(cp, box: b, fluid: gas, amount: 500, temperature: 25) }
        XCTAssertGreaterThan(added, 0, "chemical plant input accepts petroleum gas")
        w.step(60 * 5)
        let plastic = w.crafting.outputSlots(of: cp).first { Int($0.item) == w.item("plastic_bar") }?.count ?? 0
        XCTAssertGreaterThan(plastic, 0)
    }

    func testBeaconSpeedsUpAssembler() {
        let w = TestWorld.make()
        w.cheatInfinitePower = true
        let a = w.place("assembling_machine_2", 10, 10)
        _ = w.crafting.setRecipe(a, w.db.recipe("iron_gear_wheel"))
        let base = w.crafting.craftingSpeed(of: a)
        let b = w.place("beacon", 13, 10)
        XCTAssertTrue(w.beacons.insertModule(b, item: w.item("speed_module")))
        XCTAssertTrue(w.beacons.insertModule(b, item: w.item("speed_module")))
        w.step(2)
        XCTAssertEqual(w.crafting.craftingSpeed(of: a), base * 1.2, accuracy: 1e-6, "2 speed modules × 20 % × 0.5 efficiency = +20 %")
    }

    func testResearchQueueAndInfiniteResearch() {
        let w = TestWorld.make()
        let r = w.research!
        let auto = w.db.tech("automation"), logi = w.db.tech("logistics")
        r.setCurrent(auto); r.enqueue(logi)
        XCTAssertEqual(r.queue, [auto, logi])
        r.addProgress(units: Double(r.unitCount(of: auto)))
        XCTAssertTrue(r.isResearched(auto))
        XCTAssertEqual(r.current, logi, "queue advances")
        let mp = w.db.tech("mining_productivity_4")
        XCTAssertTrue(w.db.technologies[mp].isInfinite)
        let c1 = r.unitCount(of: mp)
        r.forceResearch(mp)
        XCTAssertGreaterThan(r.unitCount(of: mp), c1, "infinite tech cost grows per level")
    }

    func testLongHandedInserterReachesTwoTiles() {
        let w = TestWorld.make()
        w.cheatInfinitePower = true
        let src = w.place("iron_chest", 5, 7)
        w.place("long_handed_inserter", 5, 5, .north)
        let dst = w.place("iron_chest", 5, 3)
        _ = w.containers.insert(src, item: w.item("iron_plate"), count: 10, source: .player)
        w.step(600)
        XCTAssertGreaterThan(w.containers.inventory(of: dst)!.count(of: w.item("iron_plate")), 5)
    }

    func testAssembler2FluidRecipe() {
        // e.g. sulfuric acid / lubricant are chem-plant; assembler 2 with fluid: "engine" none — use any crafting-with-fluid recipe
        let w = TestWorld.make()
        w.cheatInfinitePower = true
        guard let r = w.db.recipes.indices.first(where: { w.db.recipes[$0].category == "crafting-with-fluid" && w.db.recipes[$0].phase == "mvp" }) else { return }
        let a = w.place("assembling_machine_2", 10, 10)
        XCTAssertTrue(w.crafting.setRecipe(a, r).isEmpty)
        let rr = w.db.resolvedRecipes[r]
        for ing in rr.itemIngredients { _ = w.crafting.insert(a, item: ing.index, count: Int(ing.amount) * 5, source: .player) }
        for ing in rr.fluidIngredients { _ = w.fluids.add(a, box: 0, fluid: ing.index, amount: ing.amount * 5, temperature: 25) }
        w.step(60 * 30)
        XCTAssertGreaterThan(w.crafting.outputSlots(of: a).reduce(0) { $0 + Int($1.count) }, 0, "\(w.db.recipes[r].id) crafts with fluid")
    }
}
