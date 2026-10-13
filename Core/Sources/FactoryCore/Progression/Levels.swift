// Gearforge — FactoryCore
// Campaign levels & Freeplay definitions, objectives and their tracker (GDD §7, §8).
// Owner: Progression engineer.

import Foundation

public enum ObjectiveKind: Codable, Equatable, Sendable {
    case produceItem(item: String, count: Int, byMachinesOnly: Bool)
    case handMine(item: String, count: Int)
    case craftItem(item: String, count: Int)
    case research(tech: String)
    case buildEntity(entity: String, count: Int)
    case entitiesWorking(entity: String?, count: Int, sustainSeconds: Int)
    case productionRate(item: String, perMinute: Double, sustainSeconds: Int)
    case powerCapacity(watts: Double)
    case launchRocket(withSatellite: Bool)
    case custom(id: String)
}

public struct Objective: Codable, Equatable, Sendable {
    public var id: Int
    public var title: String
    public var kind: ObjectiveKind
    /// Hint bubble text (tutorial levels).
    public var hint: String?
    public init(id: Int, title: String, kind: ObjectiveKind, hint: String? = nil) {
        self.id = id; self.title = title; self.kind = kind; self.hint = hint
    }
}

public struct LevelDefinition: Codable, Equatable, Sendable, Identifiable {
    public var id: String              // "L1"
    public var title: String           // "Landfall"
    public var subtitle: String
    public var teaches: String
    public var settings: WorldSettings
    public var startingItems: [ItemAmount]
    /// Techs researched at start.
    public var researched: [String]
    /// If non-nil, only these techs (plus researched) are available.
    public var availableTechs: [String]?
    public var researchEnabled: Bool
    public var objectives: [Objective]
    /// All of these objective ids must be complete to win.
    public var victoryObjectives: [Int]
    public var parSeconds: Int
    public var goldSeconds: Int
    /// The level starts with a pre-built factory near spawn (PrebuiltFactory, GDD §7 "pre-built").
    public var prebuilt: Bool = false
    public init(id: String, title: String, subtitle: String, teaches: String, settings: WorldSettings,
                startingItems: [ItemAmount], researched: [String], availableTechs: [String]?, researchEnabled: Bool,
                objectives: [Objective], victoryObjectives: [Int], parSeconds: Int, goldSeconds: Int, prebuilt: Bool = false) {
        self.id = id; self.title = title; self.subtitle = subtitle; self.teaches = teaches; self.settings = settings
        self.startingItems = startingItems; self.researched = researched; self.availableTechs = availableTechs
        self.researchEnabled = researchEnabled; self.objectives = objectives; self.victoryObjectives = victoryObjectives
        self.parSeconds = parSeconds; self.goldSeconds = goldSeconds; self.prebuilt = prebuilt
    }
}

extension LevelDefinition {
    /// Custom decoding so saves written before `prebuilt` existed still load (missing key → false).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decode(String.self, forKey: .id), title: try c.decode(String.self, forKey: .title),
                  subtitle: try c.decode(String.self, forKey: .subtitle), teaches: try c.decode(String.self, forKey: .teaches),
                  settings: try c.decode(WorldSettings.self, forKey: .settings),
                  startingItems: try c.decode([ItemAmount].self, forKey: .startingItems),
                  researched: try c.decode([String].self, forKey: .researched),
                  availableTechs: try c.decodeIfPresent([String].self, forKey: .availableTechs),
                  researchEnabled: try c.decode(Bool.self, forKey: .researchEnabled),
                  objectives: try c.decode([Objective].self, forKey: .objectives),
                  victoryObjectives: try c.decode([Int].self, forKey: .victoryObjectives),
                  parSeconds: try c.decode(Int.self, forKey: .parSeconds), goldSeconds: try c.decode(Int.self, forKey: .goldSeconds),
                  prebuilt: try c.decodeIfPresent(Bool.self, forKey: .prebuilt) ?? false)
    }
}

public enum Campaign {
    /// Stable 64-bit seed from a level seed string (FNV-1a).
    public static func seed(_ s: String) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        for b in s.utf8 { h ^= UInt64(b); h = h &* 0x100000001b3 }
        return h
    }

    static func settings(_ seedName: String, size: Int, richness: Double = 1, techPrice: Double = 1) -> WorldSettings {
        var w = WorldSettings()
        w.seed = seed(seedName)
        w.width = size; w.height = size
        w.techPriceMultiplier = techPrice
        for r in ["iron_ore", "copper_ore", "coal", "stone", "crude_oil"] {
            w.resourceSettings[r] = ResourceGenSetting(frequency: 1, size: 1, richness: richness)
        }
        w.peaceful = true
        return w
    }

    static func items(_ list: [(String, Double)]) -> [ItemAmount] { list.map { ItemAmount(id: $0.0, amount: $0.1) } }

    static let rTechs = ["automation", "logistics", "electronics", "optics", "steel_processing", "fast_inserter", "steel_axe", "motion_card"]
    static let t2 = ["automation_2", "logistics_2", "engine", "fluid_handling", "advanced_material_processing",
                     "electric_energy_distribution_1", "toolbelt", "research_speed_1", "research_speed_2", "stack_inserter",
                     "inserter_capacity_bonus_1", "inserter_capacity_bonus_2", "landfill", "modules", "speed_module",
                     "efficiency_module", "productivity_module", "solar_energy", "electric_energy_accumulators", "battery",
                     "concrete", "mining_productivity_1"]
    static let t3 = ["oil_processing", "plastics", "sulfur_processing", "advanced_electronics", "reaction_card", "flammables", "railway"]
    static let l6Techs = ["advanced_oil_processing", "lubricant", "electric_engine", "speed_module_2", "productivity_module_2",
                          "efficiency_module_2", "electric_energy_distribution_2", "advanced_material_processing_2",
                          "research_speed_3", "inserter_capacity_bonus_3", "coal_liquefaction"]
    static let l7Techs = ["fabrication_card", "systems_card", "effect_transmission", "automation_3", "logistics_3",
                          "advanced_electronics_2", "low_density_structure", "rocket_fuel", "robotics", "speed_module_3",
                          "productivity_module_3", "efficiency_module_3", "research_speed_4", "research_speed_5", "research_speed_6",
                          "inserter_capacity_bonus_4", "inserter_capacity_bonus_5", "inserter_capacity_bonus_6",
                          "inserter_capacity_bonus_7", "mining_productivity_2", "mining_productivity_3", "rocket_control_unit"]

    static let l2Kit: [(String, Double)] = [("iron_plate", 60), ("copper_plate", 30), ("coal", 50), ("burner_mining_drill", 8),
                                            ("stone_furnace", 6), ("wooden_chest", 2), ("burner_inserter", 10)]
    static let l3Kit: [(String, Double)] = [("iron_plate", 200), ("copper_plate", 100), ("coal", 200), ("transport_belt", 100),
        ("underground_belt", 20), ("splitter", 10), ("inserter", 40), ("burner_inserter", 10), ("electric_mining_drill", 20),
        ("stone_furnace", 24), ("assembling_machine_1", 10), ("small_electric_pole", 50), ("offshore_pump", 1), ("boiler", 4),
        ("steam_engine", 8), ("lab", 10), ("iron_chest", 20)]
    static let l4Kit: [(String, Double)] = [("iron_plate", 400), ("copper_plate", 200), ("steel_plate", 200), ("transport_belt", 400),
        ("underground_belt", 40), ("splitter", 20), ("inserter", 100), ("long_handed_inserter", 20), ("fast_inserter", 20),
        ("electric_mining_drill", 30), ("stone_furnace", 48), ("assembling_machine_1", 20), ("small_electric_pole", 100),
        ("offshore_pump", 2), ("boiler", 10), ("steam_engine", 20), ("lab", 10)]
    static let l5Kit: [(String, Double)] = [("steel_plate", 300), ("iron_plate", 600), ("copper_plate", 400), ("transport_belt", 600),
        ("underground_belt", 60), ("splitter", 30), ("inserter", 150), ("fast_inserter", 40), ("electric_mining_drill", 40),
        ("steel_furnace", 48), ("assembling_machine_2", 30), ("medium_electric_pole", 100), ("big_electric_pole", 50),
        ("pipe", 200), ("pipe_to_ground", 40), ("storage_tank", 4), ("offshore_pump", 2), ("boiler", 20), ("steam_engine", 40), ("lab", 10)]
    static let l6Kit: [(String, Double)] = l5Kit + [("oil_refinery", 10), ("chemical_plant", 20), ("pumpjack", 10), ("pump", 20),
        ("solar_panel", 200), ("accumulator", 160), ("concrete", 1000)]
    static let l7Kit: [(String, Double)] = l6Kit + [("beacon", 40), ("speed_module", 100), ("productivity_module", 100),
        ("electric_furnace", 40), ("assembling_machine_3", 20)]
    static let l8Kit: [(String, Double)] = l7Kit + [("concrete", 1000), ("steel_plate", 1000)]

    static func o(_ id: Int, _ title: String, _ k: ObjectiveKind, _ hint: String? = nil) -> Objective {
        Objective(id: id, title: title, kind: k, hint: hint)
    }

    /// The eight campaign levels (GDD §7).
    public static let levels: [LevelDefinition] = [
        LevelDefinition(
            id: "L1", title: "Landfall", subtitle: "Burner age",
            teaches: "Moving, hand mining, crafting, burner drills, furnaces, fuel, chests",
            settings: settings("GF-L1", size: 160), startingItems: items([("iron_plate", 8), ("wood", 10), ("burner_mining_drill", 1), ("stone_furnace", 1)]),
            researched: [], availableTechs: [], researchEnabled: false,
            objectives: [
                o(1, "Hand-mine 10 stone", .handMine(item: "stone", count: 10), "Press and hold on a stone patch to mine it."),
                o(2, "Hand-mine 10 coal", .handMine(item: "coal", count: 10), "Coal is fuel for burner machines."),
                o(3, "Build a burner drill and a furnace", .buildEntity(entity: "burner_mining_drill", count: 1), "Place the drill on iron ore and the furnace in front of it."),
                o(4, "Smelt 50 iron plates", .produceItem(item: "iron_plate", count: 50, byMachinesOnly: false)),
                o(5, "Craft 4 burner mining drills", .craftItem(item: "burner_mining_drill", count: 4), "Crafting automatically makes the gears and furnaces you need."),
                o(6, "Smelt 50 copper plates", .produceItem(item: "copper_plate", count: 50, byMachinesOnly: false)),
                o(7, "Have 10 burner drills running", .entitiesWorking(entity: "burner_mining_drill", count: 10, sustainSeconds: 5)),
                o(8, "Produce 300 iron plates", .produceItem(item: "iron_plate", count: 300, byMachinesOnly: false)),
                o(9, "Produce 150 copper plates", .produceItem(item: "copper_plate", count: 150, byMachinesOnly: false)),
            ],
            victoryObjectives: [7, 8, 9], parSeconds: 25 * 60, goldSeconds: 15 * 60),
        LevelDefinition(
            id: "L2", title: "First Light", subtitle: "Steam power & research",
            teaches: "Offshore pump, boiler, steam engines, poles, labs, research, electric drills, inserters, first assembler",
            settings: settings("GF-L2", size: 192), startingItems: items(l2Kit),
            researched: [], availableTechs: ["automation", "logistics", "electronics", "optics", "steel_processing", "fast_inserter", "steel_axe"], researchEnabled: true,
            objectives: [
                o(1, "Build an offshore pump, boiler and 2 steam engines", .buildEntity(entity: "steam_engine", count: 2), "Place the offshore pump at the water's edge, then the boiler and engines."),
                o(2, "Generate electricity (900 kW capacity)", .powerCapacity(watts: 900_000)),
                o(3, "Build a lab", .buildEntity(entity: "lab", count: 1)),
                o(4, "Research Automation", .research(tech: "automation"), "Put Mechanics cards into the lab and pick a technology."),
                o(5, "Place 4 electric mining drills", .buildEntity(entity: "electric_mining_drill", count: 4)),
                o(6, "Build an assembling machine", .buildEntity(entity: "assembling_machine", count: 1)),
                o(7, "Research Logistics", .research(tech: "logistics")),
                o(8, "Research Electronics", .research(tech: "electronics")),
                o(9, "Produce 200 Mechanics cards by machines", .produceItem(item: "mechanics_card", count: 200, byMachinesOnly: true)),
            ],
            victoryObjectives: [4, 7, 8, 9], parSeconds: 40 * 60, goldSeconds: 25 * 60),
        LevelDefinition(
            id: "L3", title: "Assembly Line", subtitle: "Automation at scale",
            teaches: "Belts, lanes, sideloading, undergrounds, splitters, smelting columns, ratios, steel",
            settings: settings("GF-L3", size: 256), startingItems: items(l3Kit),
            researched: ["automation", "logistics"], availableTechs: rTechs, researchEnabled: true,
            objectives: [
                o(1, "Build 12 stone furnaces", .buildEntity(entity: "stone_furnace", count: 12), "Feed a column of furnaces from one ore belt."),
                o(2, "Research Steel processing", .research(tech: "steel_processing")),
                o(3, "Smelt 50 steel plates", .produceItem(item: "steel_plate", count: 50, byMachinesOnly: true)),
                o(4, "Produce 200 electronic circuits", .produceItem(item: "electronic_circuit", count: 200, byMachinesOnly: true), "Ratio: 3 cable assemblers feed 2 circuit assemblers."),
                o(5, "Research Fast inserter", .research(tech: "fast_inserter")),
                o(6, "Research Motion cards", .research(tech: "motion_card")),
                o(7, "Run 20 assemblers at once", .entitiesWorking(entity: "assembling_machine", count: 20, sustainSeconds: 10)),
                o(8, "Produce 1000 electronic circuits", .produceItem(item: "electronic_circuit", count: 1000, byMachinesOnly: true)),
            ],
            victoryObjectives: [7, 8], parSeconds: 60 * 60, goldSeconds: 40 * 60),
        LevelDefinition(
            id: "L4", title: "Motion", subtitle: "Logistics & Motion cards",
            teaches: "Motion cards, main bus, rates, steel furnaces, engines, fluid handling, power expansion",
            settings: settings("GF-L4", size: 320, techPrice: 0.75), startingItems: items(l4Kit),
            researched: rTechs, availableTechs: t2, researchEnabled: true,
            objectives: [
                o(1, "Produce 100 Motion cards by machines", .produceItem(item: "motion_card", count: 100, byMachinesOnly: true)),
                o(2, "Research Automation 2", .research(tech: "automation_2")),
                o(3, "Research Logistics 2", .research(tech: "logistics_2")),
                o(4, "Research Steel furnaces", .research(tech: "advanced_material_processing")),
                o(5, "Research Engine", .research(tech: "engine")),
                o(6, "Research Fluid handling", .research(tech: "fluid_handling")),
                o(7, "Expand power to 10 MW", .powerCapacity(watts: 10_000_000)),
                o(8, "Sustain 30 Mechanics cards/min", .productionRate(item: "mechanics_card", perMinute: 30, sustainSeconds: 300)),
                o(9, "Sustain 30 Motion cards/min", .productionRate(item: "motion_card", perMinute: 30, sustainSeconds: 300)),
                o(10, "Produce 500 Motion cards", .produceItem(item: "motion_card", count: 500, byMachinesOnly: true)),
            ],
            victoryObjectives: [8, 9, 10], parSeconds: 75 * 60, goldSeconds: 50 * 60),
        LevelDefinition(
            id: "L5", title: "Black Gold", subtitle: "Oil",
            teaches: "Pumpjacks, oil processing, chemical plants, plastic, sulfur, advanced circuits, Reaction cards",
            settings: settings("GF-L5", size: 384, techPrice: 0.6), startingItems: items(l5Kit),
            researched: rTechs + t2.filter { !["solar_energy", "electric_energy_accumulators", "concrete", "landfill", "modules", "speed_module", "efficiency_module", "productivity_module", "battery"].contains($0) },
            availableTechs: t3 + ["battery", "solar_energy", "electric_energy_accumulators", "concrete", "landfill", "modules", "speed_module", "efficiency_module", "productivity_module"],
            researchEnabled: true,
            objectives: [
                o(1, "Build 4 pumpjacks", .buildEntity(entity: "pumpjack", count: 4)),
                o(2, "Build an oil refinery", .buildEntity(entity: "oil_refinery", count: 1)),
                o(3, "Make plastic", .produceItem(item: "plastic_bar", count: 1, byMachinesOnly: true)),
                o(4, "Make sulfur", .produceItem(item: "sulfur", count: 1, byMachinesOnly: true)),
                o(5, "Automate advanced circuits", .produceItem(item: "advanced_circuit", count: 50, byMachinesOnly: true)),
                o(6, "Research Reaction cards", .research(tech: "reaction_card")),
                o(7, "Produce 300 Reaction cards", .produceItem(item: "reaction_card", count: 300, byMachinesOnly: true)),
                o(8, "Produce 500 plastic bars", .produceItem(item: "plastic_bar", count: 500, byMachinesOnly: true)),
            ],
            victoryObjectives: [7, 8], parSeconds: 90 * 60, goldSeconds: 60 * 60, prebuilt: true),
        LevelDefinition(
            id: "L6", title: "Refinement", subtitle: "Advanced oil, modules, solar",
            teaches: "Advanced oil processing, cracking, lubricant, electric engines, modules, solar + accumulators",
            settings: settings("GF-L6", size: 448, techPrice: 0.5), startingItems: items(l6Kit),
            researched: rTechs + t2 + t3, availableTechs: l6Techs + ["research_speed_2", "mining_productivity_1", "inserter_capacity_bonus_1", "inserter_capacity_bonus_2", "stack_inserter"],
            researchEnabled: true,
            objectives: [
                o(1, "Research Advanced oil processing", .research(tech: "advanced_oil_processing")),
                o(2, "Make lubricant-powered electric engines", .produceItem(item: "electric_engine_unit", count: 50, byMachinesOnly: true)),
                o(3, "Build a solar field (100 panels)", .buildEntity(entity: "solar_panel", count: 100)),
                o(4, "Store energy (80 accumulators)", .buildEntity(entity: "accumulator", count: 80)),
                o(5, "Produce 50 speed modules", .produceItem(item: "speed_module", count: 50, byMachinesOnly: true)),
                o(6, "Produce 50 productivity modules", .produceItem(item: "productivity_module", count: 50, byMachinesOnly: true)),
            ],
            victoryObjectives: [3, 4, 5, 6], parSeconds: 100 * 60, goldSeconds: 70 * 60, prebuilt: true),
        LevelDefinition(
            id: "L7", title: "Industrial Scale", subtitle: "Fabrication & Systems cards",
            teaches: "Electric furnaces, assembler 3, beacons, productivity, processing units, LDS, robot frames",
            settings: settings("GF-L7", size: 512, techPrice: 0.5), startingItems: items(l7Kit),
            researched: rTechs + t2 + t3 + l6Techs, availableTechs: l7Techs, researchEnabled: true,
            objectives: [
                o(1, "Automate processing units", .produceItem(item: "processing_unit", count: 50, byMachinesOnly: true)),
                o(2, "Build 8 beacons", .buildEntity(entity: "beacon", count: 8)),
                o(3, "Research Rocket fuel", .research(tech: "rocket_fuel")),
                o(4, "Research Low density structure", .research(tech: "low_density_structure")),
                o(5, "Produce 500 Fabrication cards", .produceItem(item: "fabrication_card", count: 500, byMachinesOnly: true)),
                o(6, "Produce 500 Systems cards", .produceItem(item: "systems_card", count: 500, byMachinesOnly: true)),
                o(7, "Research Rocket control unit", .research(tech: "rocket_control_unit")),
            ],
            victoryObjectives: [5, 6, 7], parSeconds: 150 * 60, goldSeconds: 100 * 60, prebuilt: true),
        LevelDefinition(
            id: "L8", title: "Countdown", subtitle: "Rocket",
            teaches: "Rocket silo, rocket parts, satellite, launch",
            settings: settings("GF-L8", size: 640, techPrice: 0.5), startingItems: items(l8Kit),
            researched: rTechs + t2 + t3 + l6Techs + l7Techs, availableTechs: ["rocket_silo", "orbital_card"], researchEnabled: true,
            objectives: [
                o(1, "Research Rocket silo", .research(tech: "rocket_silo")),
                o(2, "Build the rocket silo", .buildEntity(entity: "rocket_silo", count: 1)),
                o(3, "Complete 100 rocket parts", .produceItem(item: "rocket_part", count: 100, byMachinesOnly: true)),
                o(4, "Launch the rocket", .launchRocket(withSatellite: false)),
                o(5, "Launch a satellite (★★★)", .launchRocket(withSatellite: true)),
            ],
            victoryObjectives: [4], parSeconds: 180 * 60, goldSeconds: 120 * 60, prebuilt: true),
    ]

    public static func level(_ id: String) -> LevelDefinition? { levels.first { $0.id == id } }
}

// MARK: - Campaign progress (stars, best times, unlocks) — stored separately from saves.

public struct CampaignProgress: Codable, Equatable, Sendable {
    public struct Entry: Codable, Equatable, Sendable { public var stars: Int; public var bestSeconds: Double }
    public var levels: [String: Entry] = [:]
    public var freeplayOrbitalBadge = false
    public init() {}

    public func isUnlocked(_ id: String) -> Bool {
        guard let i = Campaign.levels.firstIndex(where: { $0.id == id }) else { return false }
        if i == 0 { return true }
        return levels[Campaign.levels[i - 1].id] != nil
    }

    public mutating func record(level id: String, stars: Int, seconds: Double) {
        var e = levels[id] ?? Entry(stars: 0, bestSeconds: .infinity)
        e.stars = max(e.stars, stars)
        e.bestSeconds = min(e.bestSeconds, seconds)
        levels[id] = e
        if id == Campaign.levels.last?.id { freeplayOrbitalBadge = true }
    }

    public static func load(from url: URL) -> CampaignProgress {
        guard let d = try? Data(contentsOf: url), let p = try? JSONDecoder().decode(CampaignProgress.self, from: d) else { return CampaignProgress() }
        return p
    }
    public func save(to url: URL) throws {
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }
}
