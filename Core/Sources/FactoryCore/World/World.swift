// Gearforge — FactoryCore
// The World: owns the surface, entity table, every simulation system and the fixed-step tick loop.
// Owner: Lead. Teams may add small, clearly-scoped helpers in extensions in their own files instead of editing here.

import Foundation

public enum WorldEvent: Sendable {
    case entityAdded(Int32)
    case entityRemoved(EntityHandle, proto: Int, origin: TilePos, direction: Direction)
    /// Visual state changed in a way the renderer can't infer from per-frame queries (recipe set, rotated, upgraded).
    case entityChanged(Int32)
    case tilesChanged(ChunkPos)
    case chunkGenerated(ChunkPos)
    /// A chunk became visible on the map (character proximity or radar).
    case chunkCharted(ChunkPos)
    case researchStarted(TechIndex)
    case researchFinished(TechIndex)
    case recipeUnlocked(RecipeIndex)
    case craftFinished(item: Int, count: Int)
    case rocketLaunched(withSatellite: Bool)
    case objectiveCompleted(Int)
    case levelCompleted
    case alert(String)
}

/// Force-wide bonuses from research (05_mechanics §2.2, §4.1, §9). Updated by the research system.
public struct ForceBonuses: Equatable, Sendable {
    public var inserterStackBonus: Int = 0          // non-stack inserters
    public var stackInserterBonus: Int = 0          // stack inserters
    public var miningProductivity: Double = 0       // +0.1 per level
    public var labSpeed: Double = 0                 // +0.2... cumulative
    public var characterMiningSpeed: Double = 0     // steel axe +1.0
    public var characterInventoryBonus: Int = 0     // toolbelt +10
    public var workerRobotSpeed: Double = 0
    public var workerRobotStorage: Int = 0
    public var trainBrakingForce: Double = 0
    public init() {}
}

/// Map/world creation settings (stored in the save).
public struct WorldSettings: Codable, Equatable, Sendable {
    public var seed: UInt64 = 1
    public var width: Int = 512
    public var height: Int = 512
    /// Per-resource map-gen multipliers keyed by resource id: (frequency, size, richness).
    public var resourceSettings: [String: ResourceGenSetting] = [:]
    public var startingAreaScale: Double = 1
    public var waterCoverage: Double = 1
    public var waterScale: Double = 1
    public var treeCoverage: Double = 1
    public var rocks: Bool = true
    public var techPriceMultiplier: Double = 1
    /// "normal" | "perpetual_day" | "long_nights"
    public var dayNight: String = "normal"
    public var peaceful: Bool = true
    public var casualReach: Bool = false
    public var researchQueue: Bool = true
    /// "standard" | "extended"
    public var startingKit: String = "standard"
    /// Campaign override of the guaranteed starting layout (closer patches on tutorial levels). Saved with the
    /// settings so chunks generated after a load match a fresh game.
    public var layout: MapLayoutOverride? = nil
    public init() {}
}

public struct ResourceGenSetting: Codable, Equatable, Sendable {
    public var frequency: Double = 1
    public var size: Double = 1
    public var richness: Double = 1
    public init(frequency: Double = 1, size: Double = 1, richness: Double = 1) {
        self.frequency = frequency; self.size = size; self.richness = richness
    }
}

public final class World {
    public let db: PrototypeDB
    public let settings: WorldSettings
    public let surface: Surface
    public let entities = EntityStore()

    public internal(set) var tick: UInt64 = 0
    public var rng: DeterministicRNG
    public var bonuses = ForceBonuses()
    /// Events produced since the last `drainEvents()` (renderer/UI consume these each frame).
    public private(set) var events: [WorldEvent] = []
    /// When false, events are not recorded (headless tests/benchmarks).
    public var recordsEvents = true
    /// TEST/DEBUG ONLY: every electric consumer is fully satisfied without poles/generators (PowerSystem honours it).
    /// Lets system tests run without building a power plant. Never set in real games.
    public var cheatInfinitePower = false

    // MARK: Systems (update order = declaration order in step())
    public private(set) var power: PowerSystem!
    public private(set) var fluids: FluidSystem!
    public private(set) var mining: MiningSystem!
    public private(set) var crafting: CraftingSystem!
    public private(set) var labs: LabSystem!
    public private(set) var beacons: BeaconSystem!
    public private(set) var inserters: InserterSystem!
    public private(set) var belts: BeltSystem!
    public private(set) var containers: ContainerSystem!
    public private(set) var statics: StaticEntitySystem!
    // Non-entity subsystems
    public private(set) var research: ResearchManager!
    public private(set) var player: Character!
    public private(set) var stats: ProductionStats!
    public private(set) var mapGen: MapGenerator!
    /// Items lying on the ground.
    public private(set) var ground: GroundItems!
    /// Pollution statistic (no diffusion in MVP).
    public private(set) var pollution: PollutionStats!
    /// Settings waiting on ghosts (entity index → (generation, settings)); applied when the ghost is built.
    internal var ghostSettings: [Int32: (UInt32, GhostSettings)] = [:]

    /// All entity systems in update order.
    public private(set) var systems: [EntitySystem] = []
    private var systemByKind: [EntityKind: EntitySystem] = [:]
    private var endpointByKind: [EntityKind: ItemEndpoint] = [:]

    public init(db: PrototypeDB = .shared, settings: WorldSettings) {
        self.db = db
        self.settings = settings
        self.surface = Surface(width: settings.width, height: settings.height)
        self.rng = DeterministicRNG(seed: settings.seed ^ 0xA5A5_5A5A_1234_5678)

        power = PowerSystem(world: self)
        fluids = FluidSystem(world: self)
        mining = MiningSystem(world: self)
        crafting = CraftingSystem(world: self)
        labs = LabSystem(world: self)
        beacons = BeaconSystem(world: self)
        inserters = InserterSystem(world: self)
        belts = BeltSystem(world: self)
        containers = ContainerSystem(world: self)
        statics = StaticEntitySystem(world: self)
        research = ResearchManager(world: self)
        player = Character(world: self)
        stats = ProductionStats(world: self)
        mapGen = MapGenerator(world: self)
        if let layout = settings.layout { mapGen.configure(layout) }
        ground = GroundItems(world: self)
        pollution = PollutionStats(world: self)

        systems = [power, fluids, mining, crafting, labs, beacons, inserters, belts, containers, statics]

        func own(_ s: EntitySystem, _ kinds: [EntityKind]) { for k in kinds { systemByKind[k] = s } }
        own(belts, [.transportBelt, .undergroundBelt, .splitter])
        own(inserters, [.inserter])
        own(containers, [.container])
        own(mining, [.miningDrill])
        own(crafting, [.furnace, .assemblingMachine, .rocketSilo])
        own(labs, [.lab])
        own(power, [.boiler, .generator, .solarPanel, .accumulator, .electricPole])
        own(fluids, [.pipe, .pipeToGround, .pump, .offshorePump, .storageTank])
        own(beacons, [.beacon])
        own(statics, [.radar, .lamp, .wall, .gate, .turret, .tree, .rock, .character, .other])

        func endpoint(_ s: ItemEndpoint, _ kinds: [EntityKind]) { for k in kinds { endpointByKind[k] = s } }
        endpoint(containers, [.container])
        endpoint(crafting, [.furnace, .assemblingMachine, .rocketSilo])
        endpoint(labs, [.lab])
        endpoint(mining, [.miningDrill])         // burner drill fuel slot
        endpoint(power, [.boiler])               // boiler fuel slot
        endpoint(inserters, [.inserter])         // burner inserter fuel slot

        surface.generator = { [unowned self] c in self.mapGen.generateChunk(c) }
        surface.postGenerate = { [unowned self] ch in
            self.mapGen.populateChunk(ch)
            self.emit(.chunkGenerated(ch.pos))
        }
        for s in systems { s.setUp() }
        research.setUp()
        player.setUp()
        stats.setUp()
    }

    public func system(for kind: EntityKind) -> EntitySystem? { systemByKind[kind] }
    public func itemEndpoint(for kind: EntityKind) -> ItemEndpoint? { endpointByKind[kind] }

    // MARK: Tick

    /// Advances the simulation by exactly one tick (1/60 s).
    public func step() {
        power.update()       // solves networks using consumer requests made during the previous tick
        fluids.update()
        mining.update()
        crafting.update()
        labs.update()
        beacons.update()
        inserters.update()
        belts.update()
        containers.update()
        statics.update()
        research.update()
        player.update()
        stats.update()
        if tick % 60 == 59 { pollution.sample() }
        tick &+= 1
    }

    /// Advance `n` ticks.
    public func step(_ n: Int) { for _ in 0..<n { step() } }

    // MARK: Events

    public func emit(_ e: WorldEvent) { if recordsEvents { events.append(e) } }
    public func drainEvents() -> [WorldEvent] { let e = events; events.removeAll(keepingCapacity: true); return e }

    // MARK: Time of day

    /// 0...1 fraction of the day (0 = noon). Day length 25 000 ticks (05 §5.5).
    public var dayTime: Double {
        if settings.dayNight == "perpetual_day" { return 0 }
        let len: UInt64 = settings.dayNight == "long_nights" ? 37_500 : 25_000
        return Double(tick % len) / Double(len)
    }

    /// Solar multiplier 0...1 for the current time of day.
    public var daylight: Double {
        let t = dayTime
        if settings.dayNight == "perpetual_day" { return 1 }
        switch t {
        case ..<0.25: return 1
        case ..<0.45: return 1 - (t - 0.25) / 0.2
        case ..<0.55: return 0
        case ..<0.75: return (t - 0.55) / 0.2
        default: return 1
        }
    }

    // MARK: Spatial queries

    /// Footprint (w,h) of an entity prototype in a direction.
    /// Build-overlay points for a prototype placed at `origin` facing `dir` (world coordinates, tile units):
    /// mining drill → output point; inserter → pickup and drop points. Used by the build preview so the player
    /// sees where items will go before placing.
    public func ioPoints(proto: Int, origin: TilePos, dir: Direction) -> (input: Vec2?, output: Vec2?) {
        let p = db.entities[proto]
        let (fw, fh) = footprint(proto, dir)
        let c = Vec2(Double(origin.x) + Double(fw) / 2, Double(origin.y) + Double(fh) / 2)
        if let ins = p.inserter { return (c + dir.rotate(ins.pickup), c + dir.rotate(ins.drop)) }
        if let d = p.drill { return (nil, c + dir.rotate(d.outputVector)) }
        return (nil, nil)
    }

    public func footprint(_ proto: Int, _ dir: Direction) -> (w: Int, h: Int) {
        let p = db.entities[proto]
        return dir.isHorizontal ? (p.height, p.width) : (p.width, p.height)
    }

    /// Entity occupying a tile (raw index) or nil.
    @inlinable public func entity(at p: TilePos) -> Int32? {
        let e = surface.occupant(at: p)
        return e >= 0 ? e : nil
    }

    /// Entities overlapping a rect (each once), in deterministic order.
    public func entities(in rect: TileRect) -> [Int32] {
        var out: [Int32] = []
        var seen = Set<Int32>()
        // Entities are at most 9×9; scan chunks whose origin lists might contain overlapping entities.
        let pad: Int32 = 9
        let r = rect.expanded(by: pad)
        let c0 = TilePos(r.x, r.y).chunk, c1 = TilePos(r.maxX - 1, r.maxY - 1).chunk
        var cy = c0.y
        while cy <= c1.y {
            var cx = c0.x
            while cx <= c1.x {
                if let ch = surface.existingChunk(ChunkPos(cx, cy)) {
                    for e in ch.entities where entities[e].rect.intersects(rect) && seen.insert(e).inserted { out.append(e) }
                }
                cx += 1
            }
            cy += 1
        }
        return out
    }

    // MARK: Low-level entity lifecycle (NO validation — use Commands for player actions)

    /// Creates an entity and registers it with its system. Caller must have validated placement.
    @discardableResult
    public func createEntity(proto: Int, origin: TilePos, direction: Direction, flags: EntityFlags = [.playerBuilt]) -> Int32 {
        let p = db.entities[proto]
        let (w, h) = footprint(proto, direction)
        let e = entities.allocate(proto: proto, kind: p.kind, origin: origin, w: w, h: h, direction: direction,
                                  flags: flags, health: Float(p.maxHealth))
        let rect = entities[e].rect
        rect.forEach { surface.setOccupant(at: $0, e) }
        surface.chunk(at: origin)?.entities.append(e)
        if !flags.contains(.ghost) {
            systemByKind[p.kind]?.entityAdded(e)
            // Electric entities other than poles/generators register as power endpoints.
            power.registerEndpointIfNeeded(e)
            fluids.registerEndpointIfNeeded(e)
        }
        notifyNeighborhood(rect)
        emit(.entityAdded(e))
        return e
    }

    /// Removes an entity, returning the items it held (not including the entity item itself).
    @discardableResult
    public func removeEntity(_ e: Int32) -> [ItemStack] {
        let rec = entities[e]
        guard rec.isAlive else { return [] }
        var contents: [ItemStack] = []
        if !rec.flags.contains(.ghost) {
            let sys = systemByKind[rec.kind]
            contents = sys?.takeContents(e) ?? []
            fluids.unregisterEndpointIfNeeded(e)
            power.unregisterEndpointIfNeeded(e)
            sys?.entityRemoved(e)
        }
        let rect = rec.rect
        rect.forEach { if surface.occupant(at: $0) == e { surface.setOccupant(at: $0, -1) } }
        if let ch = surface.chunk(at: rec.origin), let i = ch.entities.firstIndex(of: e) { ch.entities.remove(at: i) }
        let handle = entities.handle(e)
        entities.free(e)
        notifyNeighborhood(rect)
        emit(.entityRemoved(handle, proto: Int(rec.proto), origin: rec.origin, direction: rec.direction))
        return contents
    }

    /// Rotates an entity in place (square footprints, or non-square if the rotated footprint is free — caller validates).
    public func rotateEntity(_ e: Int32, to dir: Direction) {
        let rec = entities[e]
        let (w, h) = footprint(Int(rec.proto), dir)
        let oldRect = rec.rect
        if Int(rec.w) != w || Int(rec.h) != h {
            oldRect.forEach { if surface.occupant(at: $0) == e { surface.setOccupant(at: $0, -1) } }
        }
        entities.update(e) { $0.direction = dir; $0.w = Int16(w); $0.h = Int16(h) }
        let newRect = entities[e].rect
        newRect.forEach { surface.setOccupant(at: $0, e) }
        if !rec.flags.contains(.ghost) {
            systemByKind[rec.kind]?.entityRotated(e)
            fluids.endpointRotated(e)
        }
        notifyNeighborhood(TileRect(x: min(oldRect.x, newRect.x), y: min(oldRect.y, newRect.y),
                                    w: max(oldRect.maxX, newRect.maxX) - min(oldRect.x, newRect.x),
                                    h: max(oldRect.maxY, newRect.maxY) - min(oldRect.y, newRect.y)))
        emit(.entityChanged(e))
    }

    public func notifyNeighborhood(_ rect: TileRect) {
        let r = rect.expanded(by: 1)
        for s in systems { s.neighborhoodChanged(r) }
    }

    // MARK: Item routing helpers (used by inserters, drills, player)

    public func acceptCount(_ e: Int32, item: Int, count: Int, source: ItemTransferSource) -> Int {
        let rec = entities[e]
        guard rec.isAlive, !rec.flags.contains(.ghost), let ep = endpointByKind[rec.kind] else { return 0 }
        return ep.acceptCount(e, item: item, count: count, source: source)
    }
    public func insert(_ e: Int32, item: Int, count: Int, source: ItemTransferSource) -> Int {
        let rec = entities[e]
        guard rec.isAlive, !rec.flags.contains(.ghost), let ep = endpointByKind[rec.kind] else { return 0 }
        return ep.insert(e, item: item, count: count, source: source)
    }
    public func peekExtract(_ e: Int32, source: ItemTransferSource, filter: (Int) -> Bool = { _ in true }) -> ItemStack? {
        let rec = entities[e]
        guard rec.isAlive, !rec.flags.contains(.ghost), let ep = endpointByKind[rec.kind] else { return nil }
        return ep.peekExtract(e, source: source, filter: filter)
    }
    public func extract(_ e: Int32, item: Int, count: Int, source: ItemTransferSource) -> Int {
        let rec = entities[e]
        guard rec.isAlive, !rec.flags.contains(.ghost), let ep = endpointByKind[rec.kind] else { return 0 }
        return ep.extract(e, item: item, count: count, source: source)
    }

    public func stackSize(_ item: Int) -> Int { db.items[item].stackSize }
}
