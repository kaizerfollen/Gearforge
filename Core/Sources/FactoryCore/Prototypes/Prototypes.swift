// Gearforge — FactoryCore
// Prototype (static game data) definitions. Loaded from Resources/GameData.json (camelCase keys).
// Owner: Lead (schema) + Lead Game Designer (data). Units: seconds, watts (W), joules (J), tiles.
// String ids are snake_case and stable; at load time PrototypeDB resolves them to dense Int indices which
// all hot simulation code uses.

public struct GameDataFile: Codable {
    public var version: Int
    public var items: [ItemProto]
    public var fluids: [FluidProto]
    public var recipes: [RecipeProto]
    public var technologies: [TechProto]
    public var entities: [EntityProto]
    public var tiles: [TileProto]
    public var resources: [ResourceProto]
    public var itemGroups: [ItemGroupProto]
}

/// Display grouping for crafting/inventory UI (Logistics / Production / Intermediates / Combat).
public struct ItemGroupProto: Codable {
    public var id: String
    public var name: String
    public var order: String
    /// Ordered subgroup ids belonging to this group.
    public var subgroups: [String]
}

public enum ItemKind: String, Codable {
    case item, module, tool /* research cards */, ammo, armor, gun, capsule, repairTool, other
}

public struct ModuleEffects: Codable, Equatable {
    public var speed: Double = 0
    public var productivity: Double = 0
    public var consumption: Double = 0
    public var pollution: Double = 0
    public init(speed: Double = 0, productivity: Double = 0, consumption: Double = 0, pollution: Double = 0) {
        self.speed = speed; self.productivity = productivity; self.consumption = consumption; self.pollution = pollution
    }
    public static func + (a: ModuleEffects, b: ModuleEffects) -> ModuleEffects {
        ModuleEffects(speed: a.speed + b.speed, productivity: a.productivity + b.productivity,
                      consumption: a.consumption + b.consumption, pollution: a.pollution + b.pollution)
    }
    public static func * (a: ModuleEffects, s: Double) -> ModuleEffects {
        ModuleEffects(speed: a.speed * s, productivity: a.productivity * s, consumption: a.consumption * s, pollution: a.pollution * s)
    }
    /// Speed multiplier with the 1.1 floor of 20%.
    public var speedMultiplier: Double { max(0.2, 1 + speed) }
    public var consumptionMultiplier: Double { max(0.2, 1 + consumption) }
    public var productivityBonus: Double { max(0, productivity) }
}

public struct ItemProto: Codable {
    public var id: String
    public var name: String
    public var kind: ItemKind
    public var subgroup: String
    public var order: String
    public var stackSize: Int
    /// Fuel energy in joules (nil = not a fuel).
    public var fuelValue: Double?
    public var fuelCategory: String?          // "chemical", "nuclear"
    public var burntResult: String?
    public var placeResult: String?           // entity id
    public var placeAsTile: String?           // tile id (concrete, landfill...)
    public var module: ModuleEffects?
    public var moduleCategory: String?        // "speed" | "productivity" | "efficiency"
    public var moduleTier: Int?
    public var rocketLaunchProducts: [ItemAmount]?
    /// "mvp", "combat", "trains", "robots", "nuclear", "circuits"
    public var phase: String
}

public struct FluidProto: Codable {
    public var id: String
    public var name: String
    public var defaultTemperature: Double
    public var maxTemperature: Double
    /// Joules per unit per °C.
    public var heatCapacity: Double
    public var color: [Double]                // r,g,b 0...1
    public var fuelValue: Double?
    public var phase: String
}

public struct ItemAmount: Codable, Equatable, Sendable {
    public var id: String
    public var amount: Double
    public init(id: String, amount: Double) { self.id = id; self.amount = amount }
}

/// Recipe ingredient or product. `type` is "item" or "fluid".
public struct RecipeComponent: Codable, Equatable {
    public var type: String
    public var id: String
    public var amount: Double
    /// Products only: chance of producing (uranium processing).
    public var probability: Double?
    public var isFluid: Bool { type == "fluid" }
}

public struct RecipeProto: Codable {
    public var id: String
    public var name: String
    /// crafting, advanced-crafting, crafting-with-fluid, smelting, chemistry, oil-processing, centrifuging, rocket-building
    public var category: String
    /// Crafting time (seconds at speed 1).
    public var time: Double
    public var ingredients: [RecipeComponent]
    public var results: [RecipeComponent]
    public var mainProduct: String?
    public var enabledAtStart: Bool
    public var handcraftable: Bool
    public var allowProductivity: Bool
    public var hidden: Bool
    public var subgroup: String?
    public var order: String?
    public var phase: String
}

public struct TechEffect: Codable, Equatable {
    /// "unlock-recipe" or a modifier kind: laboratory-speed, inserter-stack-size-bonus,
    /// stack-inserter-capacity-bonus, mining-drill-productivity-bonus, character-mining-speed,
    /// character-inventory-slots-bonus, worker-robot-speed, worker-robot-storage, train-braking-force-bonus, ...
    public var type: String
    public var recipe: String?
    public var modifier: Double?
}

public struct TechProto: Codable {
    public var id: String
    public var name: String
    public var prerequisites: [String]
    public var effects: [TechEffect]
    /// Fixed unit count, or nil when `countFormula` is used.
    public var count: Int?
    /// Formula in L (level), e.g. "2500*(L-3)" or "2^(L-6)*1000". Operators + - * / ^ and parentheses.
    public var countFormula: String?
    public var ingredients: [ItemAmount]
    /// Seconds per unit.
    public var time: Double
    /// nil = single level. Otherwise the max level number (Int.max encoded as -1 = infinite).
    public var maxLevel: Int?
    /// For leveled series ("mining_productivity_4"): the first level number this tech represents.
    public var level: Int?
    public var upgrade: Bool
    public var order: String?
    public var phase: String
    public var isInfinite: Bool { maxLevel == -1 }
}

public enum EntityKind: String, Codable, CaseIterable, Sendable {
    case transportBelt, undergroundBelt, splitter
    case inserter
    case container
    case miningDrill
    case furnace              // crafting machine that auto-selects smelting recipes
    case assemblingMachine    // assemblers, chemical plant, refinery, centrifuge (recipe chosen by player)
    case rocketSilo
    case lab
    case boiler, generator, solarPanel, accumulator
    case electricPole
    case pipe, pipeToGround, pump, offshorePump, storageTank
    case beacon, radar, lamp
    case wall, gate, turret
    case tree, rock           // natural, mined by hand for loot
    case character
    case other
}

public struct EnergySourceProto: Codable {
    /// "electric" | "burner" | "void" | "heat"
    public var type: String
    /// Constant electric drain in W.
    public var drain: Double?
    /// "secondary-input" (default consumers), "primary-input", "secondary-output" (generators), "tertiary" (accumulator), "solar"
    public var usagePriority: String?
    public var fuelCategories: [String]?
    public var fuelSlots: Int?
    public var effectivity: Double?
    public var bufferCapacity: Double?        // J
    public var inputFlowLimit: Double?        // W
    public var outputFlowLimit: Double?       // W
    public var emissionsPerMinute: Double?
}

public struct CraftingProto: Codable {
    public var speed: Double
    public var categories: [String]
    public var fixedRecipe: String?
    /// Assembler 2/3: fluid boxes only connect when the recipe uses fluids.
    public var fluidBoxesOffWhenNoFluidRecipe: Bool?
}

public struct BeltProto: Codable {
    /// Speed in 1/256-tile positions per tick (yellow 8, red 16, blue 24).
    public var speed: Int
    /// Underground belts only: max tile distance between entrance and exit (5/7/9).
    public var undergroundMaxDistance: Int?
}

public struct InserterProto: Codable {
    /// Turns per tick (1 turn = 360°).
    public var rotationSpeed: Double
    /// Tiles per tick.
    public var extensionSpeed: Double
    /// Pickup / drop points relative to the entity centre for direction `.north`.
    /// CONVENTION: an entity's direction is the direction items move. A north-facing inserter picks up from the
    /// south and drops to the north: pickup (0, 1), drop (0, -1.2). (1.1 raw data has y negated.)
    public var pickup: Vec2
    public var drop: Vec2
    public var isStack: Bool
    public var filterSlots: Int
    public var energyPerMovement: Double      // J
    public var energyPerRotation: Double      // J
}

public struct DrillProto: Codable {
    public var miningSpeed: Double
    /// Mining area side length in tiles (burner 2, electric 5, pumpjack 1). Centred on the entity.
    public var areaSize: Int
    public var resourceCategories: [String]
    /// Output point relative to entity centre for a north-facing drill.
    public var outputVector: Vec2
}

public struct ContainerProto: Codable { public var slots: Int }

public struct LabProto: Codable {
    public var speed: Double
    /// Item ids of accepted research cards.
    public var inputs: [String]
}

public struct PoleProto: Codable {
    public var wireReach: Double
    /// Supply area half-width measured from the pole centre (small 2.5 → 5×5 area).
    public var supplyAreaDistance: Double
    public var maxConnections: Int
}

public struct GeneratorProto: Codable {
    /// Steam units consumed per tick at full output.
    public var fluidUsagePerTick: Double
    public var maximumTemperature: Double
    public var effectivity: Double
    /// Computed max power in W (fluidUsagePerTick × 60 × (maxTemp − 15) × heatCapacity × effectivity).
    public var maxPowerOutput: Double
}

public struct BoilerProto: Codable {
    public var targetTemperature: Double
    /// Burner consumption at full load in W.
    public var energyConsumption: Double
}

public struct SolarProto: Codable { public var production: Double }

public struct AccumulatorProto: Codable {
    public var capacity: Double               // J
    public var inputFlowLimit: Double         // W
    public var outputFlowLimit: Double        // W
}

public struct PumpProto: Codable { public var pumpingSpeed: Double }        // units per tick

public struct OffshorePumpProto: Codable {
    public var pumpingSpeed: Double                                           // units per tick
    public var fluid: String
}

public struct FluidConnectionProto: Codable {
    /// Neighbour point relative to entity centre (north-facing), e.g. (0,-2) for the tile just north of a 3×3.
    public var position: Vec2
    /// "input" | "output" | "input-output"
    public var type: String
    /// Underground pipe connection (pipe-to-ground) with max distance.
    public var undergroundMaxDistance: Int?
}

public struct FluidBoxProto: Codable {
    public var volume: Double
    /// "input" | "output" | "input-output" | "none"
    public var productionType: String
    public var filter: String?
    public var minimumTemperature: Double?
    public var connections: [FluidConnectionProto]
}

public struct BeaconProto: Codable {
    public var distributionEffectivity: Double
    /// Range in tiles beyond the beacon's edge (3 → 9×9 area for a 3×3 beacon).
    public var supplyAreaDistance: Int
}

public struct RadarProto: Codable {
    public var nearbyChunkRadius: Int
    public var scanChunkRadius: Int
    public var energyPerSector: Double        // J
}

public struct RocketSiloProto: Codable {
    public var rocketPartsRequired: Int
    public var activeEnergyUsage: Double      // W
}

public struct EntityProto: Codable {
    public var id: String
    public var name: String
    public var kind: EntityKind
    /// Footprint in tiles for direction north: [width, height].
    public var size: [Int]
    public var maxHealth: Double
    /// Hand-mining (pick-up) time in seconds.
    public var mineTime: Double
    /// Item(s) obtained when mined. For buildings = their item; trees/rocks = loot.
    public var minedResults: [ItemAmount]
    public var phase: String
    public var nextUpgrade: String?
    public var fastReplaceGroup: String?
    public var energySource: EnergySourceProto?
    /// Working power usage in W (crafting machines, drills, labs, beacons, radar, lamps, pumps).
    public var energyUsage: Double?
    public var moduleSlots: Int?
    /// Allowed module effects: subset of ["speed","productivity","consumption","pollution"].
    public var allowedEffects: [String]?
    public var crafting: CraftingProto?
    public var belt: BeltProto?
    public var inserter: InserterProto?
    public var drill: DrillProto?
    public var container: ContainerProto?
    public var lab: LabProto?
    public var pole: PoleProto?
    public var generator: GeneratorProto?
    public var boiler: BoilerProto?
    public var solar: SolarProto?
    public var accumulator: AccumulatorProto?
    public var pump: PumpProto?
    public var offshorePump: OffshorePumpProto?
    public var fluidBoxes: [FluidBoxProto]?
    public var beacon: BeaconProto?
    public var radar: RadarProto?
    public var rocketSilo: RocketSiloProto?
    /// Whether the entity can be rotated by the player.
    public var rotatable: Bool
    /// Placement restriction: "none" | "shoreline" (offshore pump) | "resource" (drills need resource under area).
    public var placement: String?

    public var width: Int { size[0] }
    public var height: Int { size[1] }
}

public struct TileProto: Codable {
    public var id: String
    public var name: String
    public var walkingSpeedModifier: Double
    public var isWater: Bool
    public var buildable: Bool
    public var mapColor: [Double]
    /// Item returned when the player removes a placed tile (concrete etc.).
    public var minedItem: String?
    /// True for player-placeable floor tiles.
    public var playerPlaced: Bool
}

public struct ResourceProto: Codable {
    public var id: String
    public var name: String
    /// "basic-solid" | "basic-fluid"
    public var category: String
    public var miningTime: Double
    /// Item id (solid) or fluid id (crude oil).
    public var result: String
    public var resultIsFluid: Bool
    /// Units produced per mining cycle (oil: 10 at 100% yield).
    public var resultAmount: Double
    public var infinite: Bool
    public var minimum: Int?
    public var normal: Int?
    public var infiniteDepletionAmount: Int?
    public var requiredFluid: String?
    public var fluidAmount: Double?
    public var mapColor: [Double]
}
