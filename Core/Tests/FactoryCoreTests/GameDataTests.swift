// Gearforge — FactoryCore tests
// Sanity checks for the generated Resources/GameData.json (docs/research/tools/gen_gamedata.py).
// Reference values come from Factorio 1.1.110 (see docs/research/01–05).

import XCTest
@testable import FactoryCore

final class GameDataTests: XCTestCase {
    static let db: PrototypeDB = {
        do { return try PrototypeDB.loadBundled() } catch { fatalError("GameData failed to load: \(error)") }
    }()
    var db: PrototypeDB { Self.db }

    private func entity(_ id: String, file: StaticString = #filePath, line: UInt = #line) -> EntityProto {
        let i = db.entity(id)
        XCTAssertGreaterThanOrEqual(i, 0, "missing entity \(id)", file: file, line: line)
        return db.entities[max(i, 0)]
    }
    private func tech(_ id: String) -> TechProto { db.technologies[db.tech(id)] }
    private func isMVP(_ phase: String) -> Bool { phase == "mvp" }

    // MARK: Counts & loading

    func testLoadsAndCounts() {
        XCTAssertEqual(db.data.version, 1)
        XCTAssertEqual(db.items.count, 200)
        XCTAssertEqual(db.fluids.count, 8)
        XCTAssertEqual(db.recipes.count, 208)
        XCTAssertEqual(db.technologies.count, 192)
        XCTAssertEqual(db.entities.count, 92)          // 85 placeable + character + 4 trees + 2 rocks
        XCTAssertEqual(db.tiles.count, 13)
        XCTAssertEqual(db.resources.count, 6)
        XCTAssertEqual(db.data.itemGroups.map(\.id), ["logistics", "production", "intermediate_products", "combat"])
        let phases = Set(db.items.map(\.phase) + db.recipes.map(\.phase) + db.technologies.map(\.phase) + db.entities.map(\.phase))
        XCTAssertTrue(phases.isSubset(of: ["mvp", "combat", "trains", "robots", "nuclear", "circuits"]), "\(phases)")
    }

    func testEveryItemSubgroupIsInAGroup() {
        let subs = Set(db.data.itemGroups.flatMap(\.subgroups))
        for it in db.items { XCTAssertTrue(subs.contains(it.subgroup), "\(it.id) subgroup \(it.subgroup)") }
    }

    // MARK: Logistics numbers

    func testBelts() {
        XCTAssertEqual(entity("transport_belt").belt?.speed, 8)
        XCTAssertEqual(entity("fast_transport_belt").belt?.speed, 16)
        XCTAssertEqual(entity("express_transport_belt").belt?.speed, 24)
        XCTAssertEqual(entity("underground_belt").belt?.undergroundMaxDistance, 5)
        XCTAssertEqual(entity("fast_underground_belt").belt?.undergroundMaxDistance, 7)
        XCTAssertEqual(entity("express_underground_belt").belt?.undergroundMaxDistance, 9)
        XCTAssertEqual(entity("splitter").size, [2, 1])
        XCTAssertEqual(entity("transport_belt").nextUpgrade, "fast_transport_belt")
        // 8 positions/tick, 64 positions spacing → 7.5 items/s per lane
        XCTAssertEqual(Double(entity("transport_belt").belt!.speed) * 60 / 64, 7.5)
    }

    func testInserters() {
        func cycleTicks(_ id: String) -> Int {
            let r = entity(id).inserter!.rotationSpeed
            return 2 * Int((0.5 / r).rounded(.up))
        }
        XCTAssertEqual(cycleTicks("burner_inserter"), 100)       // 0.60 items/s
        XCTAssertEqual(cycleTicks("inserter"), 72)               // 0.83 items/s
        XCTAssertEqual(cycleTicks("long_handed_inserter"), 50)   // 1.20 items/s
        XCTAssertEqual(cycleTicks("fast_inserter"), 26)          // 2.31 items/s
        let ins = entity("inserter").inserter!
        XCTAssertEqual(ins.pickup, Vec2(0, 1))
        XCTAssertEqual(ins.drop, Vec2(0, -1.2))
        XCTAssertEqual(entity("long_handed_inserter").inserter!.pickup, Vec2(0, 2))
        XCTAssertEqual(entity("long_handed_inserter").inserter!.drop.y, -2.2, accuracy: 1e-9)
        XCTAssertTrue(entity("stack_inserter").inserter!.isStack)
        XCTAssertEqual(entity("filter_inserter").inserter!.filterSlots, 5)
        XCTAssertEqual(entity("inserter").energySource?.drain ?? 0, 400, accuracy: 1e-9)
        XCTAssertEqual(entity("burner_inserter").energySource?.type, "burner")
    }

    // MARK: Production numbers

    func testCraftingMachines() {
        let a1 = entity("assembling_machine_1")
        XCTAssertEqual(a1.crafting?.speed, 0.5)
        XCTAssertEqual(a1.energyUsage ?? 0, 75_000, accuracy: 1e-6)
        XCTAssertEqual(a1.energySource?.drain ?? 0, 2_500, accuracy: 1e-6)
        XCTAssertNil(a1.moduleSlots)
        XCTAssertFalse(a1.crafting!.categories.contains("crafting-with-fluid"))
        let a2 = entity("assembling_machine_2")
        XCTAssertEqual(a2.crafting?.speed, 0.75)
        XCTAssertEqual(a2.crafting?.fluidBoxesOffWhenNoFluidRecipe, true)
        XCTAssertEqual(a2.fluidBoxes?.count, 2)
        XCTAssertEqual(a2.moduleSlots, 2)
        XCTAssertEqual(entity("assembling_machine_3").crafting?.speed, 1.25)
        XCTAssertEqual(entity("assembling_machine_3").moduleSlots, 4)
        XCTAssertEqual(entity("stone_furnace").crafting?.speed, 1)
        XCTAssertEqual(entity("stone_furnace").energySource?.type, "burner")
        XCTAssertEqual(entity("electric_furnace").crafting?.speed, 2)
        XCTAssertEqual(entity("oil_refinery").fluidBoxes?.count, 5)
        XCTAssertEqual(entity("chemical_plant").fluidBoxes?.count, 4)
        XCTAssertEqual(entity("rocket_silo").crafting?.fixedRecipe, "rocket_part")
        XCTAssertEqual(entity("rocket_silo").rocketSilo?.rocketPartsRequired, 100)
        XCTAssertEqual(entity("beacon").beacon?.distributionEffectivity, 0.5)
        XCTAssertEqual(Set(entity("beacon").allowedEffects ?? []), Set(["consumption", "speed", "pollution"]))
        let lab = entity("lab").lab!
        XCTAssertEqual(lab.inputs, ["mechanics_card", "motion_card", "defense_card", "reaction_card",
                                    "fabrication_card", "systems_card", "orbital_card"])
        for i in lab.inputs { XCTAssertEqual(db.items[db.item(i)].kind, .tool) }
    }

    func testDrills() {
        let e = entity("electric_mining_drill")
        XCTAssertEqual(e.drill?.miningSpeed, 0.5)
        XCTAssertEqual(e.drill?.areaSize, 5)
        XCTAssertEqual(e.drill?.outputVector, Vec2(0, -1.85))
        XCTAssertEqual(e.placement, "resource")
        XCTAssertEqual(entity("burner_mining_drill").drill?.areaSize, 2)
        XCTAssertEqual(entity("pumpjack").drill?.areaSize, 1)
        XCTAssertEqual(entity("pumpjack").drill?.resourceCategories, ["basic-fluid"])
    }

    func testPower() {
        let se = entity("steam_engine").generator!
        XCTAssertEqual(se.maxPowerOutput, 900_000, accuracy: 1e-6)
        XCTAssertEqual(entity("steam_turbine").generator!.maxPowerOutput, 5_820_000, accuracy: 1e-6)
        let b = entity("boiler").boiler!
        XCTAssertEqual(b.energyConsumption, 1_800_000, accuracy: 1e-6)
        XCTAssertEqual(b.targetTemperature, 165)
        // boiler output exactly feeds two steam engines: 1.8 MW / ((165-15) × 200 J) = 60 steam/s
        let steamHC = db.fluids[db.fluid("steam")].heatCapacity
        XCTAssertEqual(b.energyConsumption / ((b.targetTemperature - 15) * steamHC), 2 * se.fluidUsagePerTick * 60, accuracy: 1e-9)
        XCTAssertEqual(entity("offshore_pump").offshorePump?.pumpingSpeed, 20)
        XCTAssertEqual(entity("offshore_pump").placement, "shoreline")
        XCTAssertEqual(entity("solar_panel").solar?.production ?? 0, 60_000, accuracy: 1e-6)
        XCTAssertEqual(entity("accumulator").accumulator?.capacity ?? 0, 5_000_000, accuracy: 1e-6)
        XCTAssertEqual(entity("small_electric_pole").pole?.supplyAreaDistance, 2.5)
        XCTAssertEqual(entity("small_electric_pole").pole?.wireReach, 7.5)
        XCTAssertEqual(entity("substation").pole?.supplyAreaDistance, 9)
        XCTAssertEqual(entity("storage_tank").fluidBoxes?.first?.volume, 25_000)
        let ptg = entity("pipe_to_ground").fluidBoxes!.first!
        XCTAssertEqual(ptg.connections.compactMap(\.undergroundMaxDistance), [10])
    }

    func testItemsFluidsResources() {
        let coal = db.items[db.item("coal")]
        XCTAssertEqual(coal.fuelValue ?? 0, 4_000_000, accuracy: 1e-6)
        XCTAssertEqual(coal.stackSize, 50)
        XCTAssertEqual(db.items[db.item("iron_plate")].stackSize, 100)
        XCTAssertEqual(db.items[db.item("satellite")].rocketLaunchProducts, [ItemAmount(id: "orbital_card", amount: 1000)])
        let p3 = db.items[db.item("productivity_module_3")]
        XCTAssertEqual(p3.module, ModuleEffects(speed: -0.15, productivity: 0.1, consumption: 0.8, pollution: 0.1))
        XCTAssertEqual(db.items[db.item("efficiency_module")].moduleCategory, "efficiency")
        XCTAssertEqual(db.fluids[db.fluid("steam")].heatCapacity, 200)
        let crude = db.resources[db.resource("crude_oil")]
        XCTAssertTrue(crude.resultIsFluid && crude.infinite)
        XCTAssertEqual(crude.result, "crude_oil")
        XCTAssertEqual(crude.resultAmount, 10)
        XCTAssertEqual(crude.minimum, 60_000)
        XCTAssertEqual(crude.normal, 300_000)
        XCTAssertEqual(crude.infiniteDepletionAmount, 10)
        let u = db.resources[db.resource("uranium_ore")]
        XCTAssertEqual(u.requiredFluid, "sulfuric_acid")
        XCTAssertEqual(u.fluidAmount, 1)
        XCTAssertEqual(u.miningTime, 2)
        XCTAssertTrue(db.tiles[db.tile("water")].isWater)
        XCTAssertFalse(db.tiles[db.tile("water")].buildable)
        XCTAssertTrue(db.tiles[db.tile("landfill")].buildable)
        XCTAssertEqual(db.tiles[db.tile("concrete")].walkingSpeedModifier, 1.4)
        XCTAssertEqual(db.tiles[db.tile("concrete")].minedItem, "concrete")
        XCTAssertEqual(db.items[db.item("stone_brick")].placeAsTile, "stone_path")
        XCTAssertEqual(entity("tree_01").minedResults, [ItemAmount(id: "wood", amount: 4)])
        XCTAssertEqual(entity("big_rock").minedResults, [ItemAmount(id: "stone", amount: 20)])
        XCTAssertEqual(entity("character").kind, .character)
    }

    func testRecipes() {
        let gear = db.recipes[db.recipe("iron_gear_wheel")]
        XCTAssertEqual(gear.time, 0.5)
        XCTAssertEqual(gear.ingredients, [RecipeComponent(type: "item", id: "iron_plate", amount: 2, probability: nil)])
        XCTAssertTrue(gear.enabledAtStart && gear.handcraftable && gear.allowProductivity)
        let red = db.recipes[db.recipe("mechanics_card")]
        XCTAssertEqual(red.time, 5)
        let u = db.recipes[db.recipe("uranium_processing")]
        XCTAssertEqual(u.results.compactMap(\.probability), [0.007, 0.993])
        XCTAssertEqual(db.recipes[db.recipe("steel_plate")].time, 16)    // normal mode
        XCTAssertEqual(db.recipes[db.recipe("engine_unit")].category, "advanced-crafting")
        XCTAssertFalse(db.recipes[db.recipe("engine_unit")].handcraftable)
        XCTAssertEqual(db.recipes.filter(\.allowProductivity).count, 43)
        // furnace auto-recipe lookup
        let smelt = db.categoryIndex["smelting"]!
        XCTAssertEqual(db.furnaceRecipeByInput[smelt]?[db.item("iron_ore")], db.recipe("iron_plate"))
    }

    // MARK: Phase consistency

    func testEveryMVPRecipeHasAnMVPMachineOrIsHandcraftable() {
        let mvpEntities = db.entities.indices.filter { isMVP(db.entities[$0].phase) }
        for (ri, r) in db.recipes.enumerated() where isMVP(r.phase) {
            let ok = r.handcraftable || mvpEntities.contains { db.canCraft(entity: $0, recipe: ri) }
            XCTAssertTrue(ok, "MVP recipe \(r.id) (\(r.category)) has no MVP machine")
        }
    }

    func testEveryMVPRecipeIsObtainableInMVP() {
        for (ri, r) in db.recipes.enumerated() where isMVP(r.phase) && !r.enabledAtStart {
            let byMVP = db.recipeUnlockedBy[ri].contains { isMVP(db.technologies[$0].phase) }
            XCTAssertTrue(byMVP, "MVP recipe \(r.id) is not unlocked by any MVP tech")
        }
        for r in db.recipes where isMVP(r.phase) {
            for c in r.ingredients where !c.isFluid {
                XCTAssertTrue(isMVP(db.items[db.item(c.id)].phase), "MVP recipe \(r.id) uses non-MVP item \(c.id)")
            }
        }
    }

    func testMVPTechPrerequisitesAreMVP() {
        for t in db.technologies where isMVP(t.phase) {
            for p in t.prerequisites {
                XCTAssertTrue(isMVP(tech(p).phase), "MVP tech \(t.id) requires non-MVP \(p) (\(tech(p).phase))")
            }
            for ing in t.ingredients {
                XCTAssertNotEqual(ing.id, "defense_card", "MVP tech \(t.id) needs defense cards")
            }
        }
        // rocket prerequisites that belong to later phases are researchable in MVP
        XCTAssertEqual(tech("railway").phase, "mvp")
        XCTAssertEqual(tech("robotics").phase, "mvp")
    }

    func testTechnologyLevels() {
        let mp = tech("mining_productivity_4")
        XCTAssertEqual(mp.level, 4)
        XCTAssertTrue(mp.isInfinite)
        XCTAssertEqual(mp.countFormula, "2500*(L-3)")
        XCTAssertEqual(tech("follower_robot_count_7").countFormula, "100*(L-6)+900")
        XCTAssertEqual(tech("research_speed_3").level, 3)
        XCTAssertEqual(tech("rocket_silo").count, 1000)
        XCTAssertEqual(tech("rocket_silo").ingredients.count, 5)
        let allowed = Set("0123456789L+-*/^().")
        for t in db.technologies {
            XCTAssertTrue((t.count != nil) != (t.countFormula != nil), "\(t.id) needs exactly one of count/countFormula")
            if let f = t.countFormula { XCTAssertTrue(Set(f).isSubset(of: allowed), "\(t.id): \(f)") }
        }
        XCTAssertEqual(db.technologies.filter(\.isInfinite).count, 9)
    }

    /// Simulated MVP progression: start recipes + raw resources, research MVP techs whose cards are producible,
    /// until a fixpoint. The rocket (and the satellite → orbital cards) must be reachable.
    func testRocketReachableInMVP() {
        var items = Set(["iron_ore", "copper_ore", "coal", "stone", "wood"])
        var fluids = Set(["water", "crude_oil"])          // offshore pump / pumpjack
        var researched = Set<String>()
        var changed = true
        func machineAvailable(_ ri: Int) -> Bool {
            if db.recipes[ri].handcraftable { return true }
            return db.entities.indices.contains { e in
                isMVP(db.entities[e].phase) && db.canCraft(entity: e, recipe: ri) && db.entityItem[e] >= 0
                    && items.contains(db.items[db.entityItem[e]].id)
            }
        }
        while changed {
            changed = false
            for (ri, r) in db.recipes.enumerated() where isMVP(r.phase) {
                let unlocked = r.enabledAtStart || db.recipeUnlockedBy[ri].contains { researched.contains(db.technologies[$0].id) }
                guard unlocked else { continue }
                let have = r.ingredients.allSatisfy { $0.isFluid ? fluids.contains($0.id) : items.contains($0.id) }
                guard have, machineAvailable(ri) else { continue }
                for c in r.results {
                    if c.isFluid { if fluids.insert(c.id).inserted { changed = true } }
                    else if items.insert(c.id).inserted { changed = true }
                }
            }
            if items.contains("steam_engine") || items.contains("boiler") { if fluids.insert("steam").inserted { changed = true } }
            for it in db.items where items.contains(it.id) {
                for p in it.rocketLaunchProducts ?? [] where items.contains("rocket_silo") && items.contains("rocket_part") {
                    if items.insert(p.id).inserted { changed = true }
                }
            }
            for t in db.technologies where isMVP(t.phase) && !researched.contains(t.id) {
                if t.prerequisites.allSatisfy(researched.contains) && t.ingredients.allSatisfy({ items.contains($0.id) }) {
                    researched.insert(t.id); changed = true
                }
            }
        }
        XCTAssertTrue(researched.contains("rocket_silo"))
        XCTAssertTrue(items.contains("rocket_part"))
        XCTAssertTrue(items.contains("satellite"))
        XCTAssertTrue(items.contains("orbital_card"))
        XCTAssertTrue(researched.contains("mining_productivity_4"))
        let mvpTechs = Set(db.technologies.filter { isMVP($0.phase) }.map(\.id))
        XCTAssertEqual(researched, mvpTechs, "unreachable MVP techs: \(mvpTechs.subtracting(researched).sorted())")
    }
}
