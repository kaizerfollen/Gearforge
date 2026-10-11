// Gearforge — FactoryCore
// Campaign levels & Freeplay definitions, objectives and their tracker (GDD §7, §8).
// Owner: Progression engineer. STUB — keep public types (UI uses them).

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
    public init(id: String, title: String, subtitle: String, teaches: String, settings: WorldSettings,
                startingItems: [ItemAmount], researched: [String], availableTechs: [String]?, researchEnabled: Bool,
                objectives: [Objective], victoryObjectives: [Int], parSeconds: Int, goldSeconds: Int) {
        self.id = id; self.title = title; self.subtitle = subtitle; self.teaches = teaches; self.settings = settings
        self.startingItems = startingItems; self.researched = researched; self.availableTechs = availableTechs
        self.researchEnabled = researchEnabled; self.objectives = objectives; self.victoryObjectives = victoryObjectives
        self.parSeconds = parSeconds; self.goldSeconds = goldSeconds
    }
}

public enum Campaign {
    /// The eight campaign levels (GDD §7). STUB: Progression engineer fills these in.
    public static let levels: [LevelDefinition] = []
}
