// Gearforge — FactoryCore
// Force research state: researched techs, levels of infinite techs, current research + queue, unlocked recipes,
// bonuses (World.bonuses) (05_mechanics §9, 04_technologies).
// Owner: Production engineer.
//
// Model
// - Finite techs are researched once. Leveled series ("research_speed_3") are separate finite techs.
// - Infinite techs (maxLevel == -1) are never "researched"; each completed level increments `completedLevels`, the
//   current level is `tech.level + completedLevels` and the unit count comes from `countFormula` in L.
// - `queue` is the ordered research queue; `queue.first` is the current research. With the research queue
//   disabled (WorldSettings.researchQueue == false) the queue holds at most the current tech.
// - Recipe visibility: unlocked (enabledAtStart or unlocked by a researched tech) AND recipe.phase ∈ enabledPhases.
// - Bonuses are derived from the researched set and recomputed from scratch whenever it changes (and on load).

public final class ResearchManager {
    public unowned let world: World
    public init(world: World) { self.world = world }

    /// Maximum research queue length (GDD: queue ≤ 7, including the current research).
    public static let maxQueueLength = 7

    // MARK: Configuration (campaign levels / freeplay)

    /// Content phases whose recipes and technologies are available. Later-phase recipes unlocked by MVP techs
    /// (e.g. railway → locomotive) stay hidden until their phase is enabled.
    public var enabledPhases: Set<String> = ["mvp"] { didSet { rebuildPhaseCache(); world.labs?.researchChanged() } }
    /// If non-nil, only these technologies can be researched (campaign levels). Already-researched techs stay.
    public var allowedTechs: Set<Int>? { didSet { validateQueue() } }
    /// When false labs do not research and no research can be started (campaign L1).
    public var researchEnabled: Bool = true { didSet { world.labs?.researchChanged() } }

    // MARK: State

    private var researched: [Bool] = []
    private var completedLevels: [Int] = []
    /// Progress in units towards the current level of each tech (kept when switching research — 1.1 behaviour).
    private var progressUnits: [Double] = []
    private var unlockedByTech: [Bool] = []
    public private(set) var queue: [Int] = []

    // Derived caches
    private var recipePhaseEnabled: [Bool] = []
    private var techPhaseEnabled: [Bool] = []
    private var formulas: [TechFormula?] = []
    /// Per tech: card item indices and amounts per unit.
    public private(set) var unitItems: [[Int]] = []
    public private(set) var unitAmounts: [[Int]] = []

    public func setUp() {
        let db = world.db
        let nt = db.technologies.count
        researched = Array(repeating: false, count: nt)
        completedLevels = Array(repeating: 0, count: nt)
        progressUnits = Array(repeating: 0, count: nt)
        unlockedByTech = Array(repeating: false, count: db.recipes.count)
        formulas = db.technologies.map { t in t.countFormula.flatMap { TechFormula($0) } }
        unitItems = db.technologies.map { t in t.ingredients.map { db.item($0.id) } }
        unitAmounts = db.technologies.map { t in t.ingredients.map { max(1, Int($0.amount.rounded())) } }
        rebuildPhaseCache()
    }

    private func rebuildPhaseCache() {
        let db = world.db
        recipePhaseEnabled = db.recipes.map { enabledPhases.contains($0.phase) }
        techPhaseEnabled = db.technologies.map { enabledPhases.contains($0.phase) }
    }

    // MARK: Queries

    @inline(__always) private func valid(_ t: Int) -> Bool { t >= 0 && t < researched.count }

    public func isResearched(_ t: Int) -> Bool { valid(t) && researched[t] }

    public func isRecipeUnlocked(_ r: Int) -> Bool {
        guard r >= 0, r < recipePhaseEnabled.count, recipePhaseEnabled[r] else { return false }
        return world.db.recipes[r].enabledAtStart || unlockedByTech[r]
    }

    /// Technologies whose prerequisites are all researched and that are not yet researched (infinite techs stay
    /// available forever), restricted to enabled phases and `allowedTechs`.
    public func isAvailable(_ t: Int) -> Bool {
        guard valid(t), !researched[t], techPhaseEnabled[t] else { return false }
        if let allowed = allowedTechs, !allowed.contains(t) { return false }
        for p in world.db.techPrereqs[t] where !researched[p] { return false }
        return true
    }

    public var current: Int { queue.first ?? -1 }

    /// Progress 0...1 of a technology (current level for infinite techs).
    public func progress(of t: Int) -> Double {
        guard valid(t) else { return 0 }
        if researched[t] { return 1 }
        let n = unitCount(of: t)
        return n > 0 ? min(1, progressUnits[t] / Double(n)) : 0
    }

    /// Units completed towards the current level.
    public func progressUnits(of t: Int) -> Double { valid(t) ? progressUnits[t] : 0 }

    /// Units required for the current level (applies the tech price multiplier).
    public func unitCount(of t: Int) -> Int {
        guard valid(t) else { return 0 }
        let tech = world.db.technologies[t]
        let raw: Double
        if let c = tech.count { raw = Double(c) }
        else if let f = formulas[t] { raw = f.evaluate(level: Double(level(of: t))) }
        else { raw = 1 }
        let scaled = (min(raw, 1e15) * world.settings.techPriceMultiplier).rounded()
        return max(1, scaled.isFinite ? Int(scaled) : 1)
    }

    /// Level being researched (infinite: base level + completed levels; leveled finite: its level; else 1).
    public func level(of t: Int) -> Int {
        guard valid(t) else { return 0 }
        return (world.db.technologies[t].level ?? 1) + completedLevels[t]
    }

    /// Completed levels of an infinite tech (0 for finite techs).
    public func completedLevels(of t: Int) -> Int { valid(t) ? completedLevels[t] : 0 }

    /// Seconds per unit at lab speed 1.
    public func unitTime(of t: Int) -> Double { valid(t) ? world.db.technologies[t].time : 0 }

    public var researchedTechs: [Int] { researched.indices.filter { researched[$0] } }

    // MARK: Commands

    /// Makes `t` the current research (moving it to the front of the queue, enqueuing missing prerequisites first
    /// when the queue is enabled). Partial progress of the previous research is kept.
    public func setCurrent(_ t: Int) {
        guard researchEnabled, isAvailable(t) || canEnqueueWithPrereqs(t) else { return }
        let old = current
        if !world.settings.researchQueue {
            guard isAvailable(t) else { return }
            queue = [t]
        } else {
            var chain = prerequisiteChain(t)
            chain.append(t)
            queue.removeAll { chain.contains($0) }
            queue.insert(contentsOf: chain, at: 0)
            trimQueue()
        }
        if current != old { currentChanged() }
    }

    /// Appends `t` (and its missing prerequisites, in order) to the queue.
    public func enqueue(_ t: Int) {
        guard researchEnabled, valid(t) else { return }
        if !world.settings.researchQueue {
            if queue.isEmpty { setCurrent(t) }
            return
        }
        guard !queue.contains(t), canEnqueueWithPrereqs(t) else { return }
        var chain = prerequisiteChain(t).filter { !queue.contains($0) }
        chain.append(t)
        guard queue.count + chain.count <= Self.maxQueueLength else { return }
        let old = current
        queue.append(contentsOf: chain)
        if current != old { currentChanged() }
    }

    /// Removes `t` and every queued tech that depends on it.
    public func dequeue(_ t: Int) {
        guard let i = queue.firstIndex(of: t) else { return }
        let old = current
        queue.remove(at: i)
        validateQueue(notify: false)
        if current != old { currentChanged() }
    }

    /// Instantly researches a tech (scenarios / cheats) and applies its effects. Infinite techs gain one level.
    public func forceResearch(_ t: Int) {
        guard valid(t), !researched[t] else { return }
        complete(t)
    }

    /// Researches every technology in `ids` (campaign level setup). Unknown ids are ignored.
    public func forceResearch(ids: [String]) {
        for id in ids { forceResearch(world.db.tech(id)) }
    }

    /// Called by labs: adds research progress in units to the current tech.
    public func addProgress(units: Double) {
        let t = current
        guard t >= 0, units > 0 else { return }
        progressUnits[t] += units
        if progressUnits[t] + 1e-9 >= Double(unitCount(of: t)) { complete(t) }
    }

    public func update() {}

    // MARK: Internals

    /// Unresearched prerequisites of `t` in dependency order (deepest first), excluding `t`.
    private func prerequisiteChain(_ t: Int) -> [Int] {
        var order: [Int] = []
        var seen = Set<Int>()
        func visit(_ x: Int) {
            for p in world.db.techPrereqs[x] where !researched[p] && !seen.contains(p) {
                seen.insert(p)
                visit(p)
                order.append(p)
            }
        }
        visit(t)
        return order
    }

    private func canEnqueueWithPrereqs(_ t: Int) -> Bool {
        guard valid(t), !researched[t], techPhaseEnabled[t] else { return false }
        if let allowed = allowedTechs, !allowed.contains(t) { return false }
        guard world.settings.researchQueue else { return isAvailable(t) }
        for p in prerequisiteChain(t) {
            if !techPhaseEnabled[p] { return false }
            if let allowed = allowedTechs, !allowed.contains(p) { return false }
        }
        return true
    }

    private func trimQueue() {
        if queue.count > Self.maxQueueLength { queue.removeLast(queue.count - Self.maxQueueLength) }
    }

    /// Drops queue entries that are researched, not allowed, or whose prerequisites are neither researched nor
    /// earlier in the queue.
    private func validateQueue(notify: Bool = true) {
        let old = current
        var kept: [Int] = []
        for t in queue {
            guard valid(t), !researched[t], techPhaseEnabled[t] else { continue }
            if let allowed = allowedTechs, !allowed.contains(t) { continue }
            let ok = world.db.techPrereqs[t].allSatisfy { researched[$0] || kept.contains($0) }
            if ok { kept.append(t) }
        }
        queue = kept
        if notify && current != old { currentChanged() }
    }

    private func currentChanged() {
        if current >= 0 { world.emit(.researchStarted(current)) }
        world.labs?.researchChanged()
    }

    private func complete(_ t: Int) {
        let db = world.db
        let tech = db.technologies[t]
        progressUnits[t] = 0
        if tech.isInfinite {
            completedLevels[t] += 1
        } else {
            researched[t] = true
        }
        for r in db.techUnlocks[t] where !unlockedByTech[r] {
            unlockedByTech[r] = true
            if isRecipeUnlocked(r) { world.emit(.recipeUnlocked(r)) }
        }
        recomputeBonuses()
        world.labs?.techCompleted(t)
        world.emit(.researchFinished(t))
        let old = current
        // Finished finite techs leave the queue; infinite techs keep researching their next level.
        validateQueue(notify: false)
        if current != old || current == t { currentChanged() }
    }

    /// Rebuilds `world.bonuses` from the researched set and infinite levels.
    public func recomputeBonuses() {
        let db = world.db
        var b = ForceBonuses()
        for (t, tech) in db.technologies.enumerated() {
            let times = tech.isInfinite ? completedLevels[t] : (researched[t] ? 1 : 0)
            guard times > 0 else { continue }
            for e in tech.effects {
                let m = (e.modifier ?? 0) * Double(times)
                switch e.type {
                case "inserter-stack-size-bonus": b.inserterStackBonus += Int(m.rounded())
                case "stack-inserter-capacity-bonus": b.stackInserterBonus += Int(m.rounded())
                case "mining-drill-productivity-bonus": b.miningProductivity += m
                case "laboratory-speed": b.labSpeed += m
                case "character-mining-speed": b.characterMiningSpeed += m
                case "character-inventory-slots-bonus": b.characterInventoryBonus += Int(m.rounded())
                case "worker-robot-speed": b.workerRobotSpeed += m
                case "worker-robot-storage": b.workerRobotStorage += Int(m.rounded())
                case "train-braking-force-bonus": b.trainBrakingForce += m
                default: break   // combat modifiers: later phase
                }
            }
        }
        world.bonuses = b
    }

    // MARK: Persistence

    private static let version: UInt8 = 1

    public func serialize(to w: inout BinaryWriter) {
        w.write(Self.version)
        ProdIO.write(researched, &w)
        ProdIO.write(completedLevels.map { Int32($0) }, &w)
        ProdIO.write(progressUnits, &w)
        ProdIO.write(queue.map { Int32($0) }, &w)
        let phases = enabledPhases.sorted()
        w.writeVarInt(phases.count)
        for p in phases { w.write(p) }
        w.write(allowedTechs != nil)
        if let a = allowedTechs { ProdIO.write(a.sorted().map { Int32($0) }, &w) }
        w.write(researchEnabled)
    }

    public func deserialize(from r: inout BinaryReader) throws {
        try ProdIO.checkVersion(&r, Self.version)
        let nt = world.db.technologies.count
        researched = try ProdIO.readBools(&r, expect: nt)
        completedLevels = try ProdIO.readInt32s(&r, expect: nt).map { Int($0) }
        progressUnits = try ProdIO.readDoubles(&r, expect: nt)
        let savedQueue = try ProdIO.readInt32s(&r).map { Int($0) }
        var phases = Set<String>()
        for _ in 0..<(try r.readVarInt()) { phases.insert(try r.readString()) }
        queue = []
        enabledPhases = phases
        allowedTechs = try r.readBool() ? Set(try ProdIO.readInt32s(&r).map { Int($0) }) : nil
        researchEnabled = try r.readBool()
        queue = savedQueue.filter(valid)
        // Derived state
        let db = world.db
        unlockedByTech = Array(repeating: false, count: db.recipes.count)
        for t in 0..<nt where researched[t] || completedLevels[t] > 0 {
            for rr in db.techUnlocks[t] { unlockedByTech[rr] = true }
        }
        rebuildPhaseCache()
        recomputeBonuses()
    }
}
