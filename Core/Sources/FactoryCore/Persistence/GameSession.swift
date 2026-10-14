// Gearforge — FactoryCore
// A running game: world + mode (campaign level / freeplay) + objective state + play time. The app talks to this.
// Fixed-timestep driver, save/load, autosave scheduling. Owner: Progression engineer.

import Foundation

public enum GameMode: Codable, Equatable, Sendable {
    case campaign(levelID: String)
    case freeplay
}

public final class GameSession {
    public let world: World
    public let mode: GameMode
    /// Real seconds played (for save metadata).
    public private(set) var playTime: Double = 0
    public var isPaused = false
    /// Simulation speed multiplier (1 = 60 UPS).
    public var speed: Double = 1
    /// Campaign level (nil in freeplay).
    public private(set) var level: LevelDefinition?
    public let objectives: ObjectiveTracker
    /// Autosave interval in game seconds (0 = off). Set from GameSettings by the app.
    public var autosaveIntervalSeconds: Double = 300
    /// Set when an autosave is due; the app performs the save and calls `didAutosave()`.
    public private(set) var autosaveDue = false
    private var lastAutosaveTick: UInt64 = 0
    private var accumulator: Double = 0
    /// True once the first rocket was launched in freeplay (victory screen shown once).
    public var victoryShown = false

    public init(world: World, mode: GameMode, level: LevelDefinition? = nil) {
        self.world = world
        self.mode = mode
        self.level = level
        self.objectives = ObjectiveTracker(world: world, level: level)
        lastAutosaveTick = world.tick
    }

    /// Creates a new freeplay game.
    public static func newFreeplay(settings: WorldSettings) -> GameSession {
        let w = World(settings: settings)
        w.player.giveStartingKit()
        return GameSession(world: w, mode: .freeplay)
    }

    /// Creates a new campaign game for a level.
    public static func newCampaign(level: LevelDefinition) -> GameSession {
        let w = World(settings: level.settings)
        for it in level.startingItems { w.player.give(w.db.item(it.id), Int(it.amount)) }
        w.research.forceResearch(ids: level.researched)
        if let avail = level.availableTechs {
            w.research.allowedTechs = Set((avail + level.researched).map { w.db.tech($0) }.filter { $0 >= 0 })
        }
        w.research.researchEnabled = level.researchEnabled
        if level.prebuilt { PrebuiltFactory.build(levelID: level.id, in: w, near: w.mapGen.spawnPosition) }
        return GameSession(world: w, mode: .campaign(levelID: level.id), level: level)
    }

    /// Game seconds elapsed (tick / 60) — campaign par/gold times use game time.
    public var gameSeconds: Double { Double(world.tick) / Double(ticksPerSecond) }

    /// Advances the simulation by real time `dt` seconds using a fixed 60 Hz step; runs at most `maxTicks` ticks
    /// (prevents spiral of death). Returns ticks run.
    @discardableResult
    public func advance(realSeconds dt: Double, maxTicks: Int = 4) -> Int {
        guard !isPaused, dt > 0 else { return 0 }
        playTime += dt
        accumulator += dt * speed * Double(ticksPerSecond)
        var n = 0
        while accumulator >= 1 && n < maxTicks {
            world.step()
            accumulator -= 1
            n += 1
            if world.tick % 30 == 0 { objectives.evaluate() }
        }
        if accumulator > Double(maxTicks) { accumulator = Double(maxTicks) }   // drop excess (device too slow)
        if autosaveIntervalSeconds > 0 && Double(world.tick &- lastAutosaveTick) >= autosaveIntervalSeconds * Double(ticksPerSecond) {
            autosaveDue = true
        }
        return n
    }

    /// Steps exactly `ticks` ticks (tests, fast-forward).
    public func run(ticks: Int) {
        for _ in 0..<ticks {
            world.step()
            if world.tick % 30 == 0 { objectives.evaluate() }
        }
    }

    public func didAutosave() { autosaveDue = false; lastAutosaveTick = world.tick }

    // MARK: Persistence

    /// Full payload (world + session section) for SaveFile.assemble.
    public func encodePayload() -> [UInt8] {
        var s = BinaryWriter()
        s.write(UInt8(1))
        SaveFile.encodeMode(mode, into: &s)
        s.write(playTime)
        s.write(level != nil)
        if let l = level { s.writeBytes([UInt8]((try? WorldCodec.jsonEncoder.encode(l)) ?? Data())) }
        objectives.serialize(to: &s)
        s.write(victoryShown)
        s.write(lastAutosaveTick)
        return WorldCodec.encode(world, extra: [(fourCC("SESS"), s.bytes)])
    }

    public static func decode(payload: [UInt8], db: PrototypeDB = .shared) throws -> GameSession {
        let (world, extra) = try WorldCodec.decode(payload, db: db)
        guard var s = extra[fourCC("SESS")] else {
            return GameSession(world: world, mode: .freeplay)
        }
        _ = try s.read(UInt8.self)
        let mode = try SaveFile.decodeMode(&s)
        let play = try s.readDouble()
        var level: LevelDefinition? = nil
        if try s.readBool() { level = try JSONDecoder().decode(LevelDefinition.self, from: Data(try s.readBytes())) }
        let session = GameSession(world: world, mode: mode, level: level)
        session.playTime = play
        try session.objectives.deserialize(from: &s)
        session.victoryShown = try s.readBool()
        session.lastAutosaveTick = try s.read(UInt64.self)
        if let l = level, let allowed = l.availableTechs {
            world.research.allowedTechs = Set((allowed + l.researched).map { world.db.tech($0) }.filter { $0 >= 0 })
            world.research.researchEnabled = l.researchEnabled
        }
        return session
    }

    /// Convenience: write to / read from a file URL (atomic).
    public func save(to url: URL, displayName: String, compressor: SaveCompressor? = nil, thumbnailPNG: Data? = nil) throws {
        let meta = makeMetadata(slot: url.deletingPathExtension().lastPathComponent, displayName: displayName,
                                isAutosave: false, thumbnail: thumbnailPNG)
        let bytes = SaveFile.assemble(metadata: meta, worldPayload: encodePayload(), compressor: compressor)
        do { try Data(bytes).write(to: url, options: .atomic) } catch { throw SaveError.io("\(error)") }
    }

    public static func load(from url: URL, compressor: SaveCompressor? = nil) throws -> GameSession {
        let data: Data
        do { data = try Data(contentsOf: url) } catch { throw SaveError.notFound(url.lastPathComponent) }
        let parsed = try SaveFile.parse([UInt8](data), slot: url.deletingPathExtension().lastPathComponent)
        return try decode(payload: try SaveFile.worldPayload(parsed, compressor: compressor))
    }

    func makeMetadata(slot: String, displayName: String, isAutosave: Bool, thumbnail: Data?) -> SaveMetadata {
        SaveMetadata(slot: slot, displayName: displayName, mode: mode, levelTitle: level?.title,
                     playTimeSeconds: playTime, gameTick: world.tick, savedAt: Date(), isAutosave: isAutosave,
                     formatVersion: SaveFile.formatVersion, thumbnailPNG: thumbnail,
                     mapWidth: world.settings.width, mapHeight: world.settings.height, seed: world.settings.seed)
    }
}

// MARK: - Objectives

/// Evaluates campaign objectives cheaply (every 30 ticks). GDD §7 common rules.
public final class ObjectiveTracker {
    public unowned let world: World
    public let level: LevelDefinition?

    public struct State: Equatable, Sendable {
        public var completed = false
        public var current: Double = 0        // progress value (count, rate...)
        public var target: Double = 1
        public var sustained: Double = 0      // seconds the condition has held
        public var fraction: Double { target > 0 ? min(1, current / target) : (completed ? 1 : 0) }
        public init() {}
    }

    public private(set) var states: [Int: State] = [:]
    public private(set) var levelCompleted = false
    public private(set) var completionSeconds: Double? = nil

    init(world: World, level: LevelDefinition?) {
        self.world = world
        self.level = level
        for o in level?.objectives ?? [] { states[o.id] = State() }
    }

    /// Objectives shown in the tracker: the first two incomplete ones, in order.
    public var active: [Objective] {
        Array((level?.objectives ?? []).filter { states[$0.id]?.completed != true }.prefix(2))
    }

    /// Stars for the level (0 until complete): ★ complete, ★★ under par, ★★★ under gold.
    public var stars: Int {
        guard let l = level, let t = completionSeconds else { return 0 }
        if t <= Double(l.goldSeconds) { return 3 }
        if t <= Double(l.parSeconds) { return 2 }
        return 1
    }

    public func evaluate() {
        guard let l = level, !levelCompleted else { return }
        let dt = 30.0 / Double(ticksPerSecond)
        for o in l.objectives {
            var s = states[o.id] ?? State()
            if s.completed { continue }
            let (cur, target, holds, sustainNeeded) = measure(o.kind)
            s.current = cur; s.target = target
            if holds { s.sustained += dt } else { s.sustained = 0 }
            if holds && s.sustained + 1e-9 >= Double(sustainNeeded) {
                s.completed = true
                world.emit(.objectiveCompleted(o.id))
            }
            states[o.id] = s
        }
        if l.victoryObjectives.allSatisfy({ states[$0]?.completed == true }) {
            levelCompleted = true
            completionSeconds = Double(world.tick) / Double(ticksPerSecond)
            world.emit(.levelCompleted)
        }
    }

    /// (current, target, condition holds, seconds it must be sustained)
    private func measure(_ k: ObjectiveKind) -> (Double, Double, Bool, Int) {
        let db = world.db, st = world.stats!
        switch k {
        case .produceItem(let id, let count, let byMachines):
            let i = db.item(id)
            let v = Double(byMachines ? st.producedByMachines(item: i) : st.totalProduced(item: i))
            return (v, Double(count), v >= Double(count), 0)
        case .handMine(let id, let count):
            let v = Double(st.handMinedCount(item: db.item(id)))
            return (v, Double(count), v >= Double(count), 0)
        case .craftItem(let id, let count):
            let v = Double(st.handCraftedCount(item: db.item(id)))
            return (v, Double(count), v >= Double(count), 0)
        case .research(let id):
            let ok = world.research.isResearched(db.tech(id))
            return (ok ? 1 : 0, 1, ok, 0)
        case .buildEntity(let id, let count):
            var n = 0
            world.entities.forEachLive { _, r in
                if !r.flags.contains(.ghost) && db.entities[Int(r.proto)].id.hasPrefix(id) { n += 1 }
            }
            return (Double(n), Double(count), n >= count, 0)
        case .entitiesWorking(let id, let count, let sustain):
            var n = 0
            world.entities.forEachLive { e, r in
                guard !r.flags.contains(.ghost) else { return }
                if let id = id, !db.entities[Int(r.proto)].id.hasPrefix(id) { return }
                switch r.kind {
                case .assemblingMachine, .furnace, .rocketSilo: if world.crafting.isWorking(e) { n += 1 }
                case .miningDrill: if world.mining.isWorking(e) { n += 1 }
                case .lab: if world.labs.isWorking(e) { n += 1 }
                default: break
                }
            }
            return (Double(n), Double(count), n >= count, sustain)
        case .productionRate(let id, let perMinute, let sustain):
            let v = st.rollingPerMinute(item: db.item(id))
            return (v, perMinute, v >= perMinute, sustain)
        case .powerCapacity(let watts):
            var best = 0.0
            for s in world.power.networkStats { best = max(best, s.capacityW) }
            return (best, watts, best >= watts, 0)
        case .launchRocket(let sat):
            let v = sat ? st.rocketsLaunchedWithSatellite : st.rocketsLaunched
            return (Double(v), 1, v >= 1, 0)
        case .custom:
            return (0, 1, false, 0)
        }
    }

    func serialize(to w: inout BinaryWriter) {
        w.write(levelCompleted)
        w.write(completionSeconds ?? -1)
        let ids = states.keys.sorted()
        w.writeVarInt(ids.count)
        for id in ids {
            let s = states[id]!
            w.write(Int32(id)); w.write(s.completed); w.write(s.current); w.write(s.target); w.write(s.sustained)
        }
    }

    func deserialize(from r: inout BinaryReader) throws {
        levelCompleted = try r.readBool()
        let c = try r.readDouble()
        completionSeconds = c >= 0 ? c : nil
        let n = try r.readVarInt()
        for _ in 0..<n {
            let id = Int(try r.read(Int32.self))
            var s = State()
            s.completed = try r.readBool(); s.current = try r.readDouble(); s.target = try r.readDouble(); s.sustained = try r.readDouble()
            states[id] = s
        }
    }
}
