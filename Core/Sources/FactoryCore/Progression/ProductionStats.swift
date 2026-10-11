// Gearforge — FactoryCore
// Production/consumption statistics per item, fluid and power source over 1 min / 10 min / 1 h / 10 h windows, plus
// lifetime totals (machine vs. handcraft vs. hand-mining split) and rocket launches. Owner: Progression engineer.
//
// Hot path (`produced`, `consumed`, …) is two array writes: a lifetime counter and a pending accumulator.
// Every `baseBucketTicks` (30) ticks the pending values are folded into one ring buffer per window. Each window has
// `samplesPerWindow` (120) buckets: 1 min → 0.5 s buckets, 10 min → 5 s, 1 h → 30 s, 10 h → 5 min. Memory is
// series × 4 windows × 120 × 4 bytes ≈ 1.2 MB for the full MVP data set; saves store only non-zero series.
//
// CALLER CONTRACT (exactly one call per produced item):
//  • machines (assemblers, furnaces, drills, pumpjacks, silo, offshore pumps …) → `produced` / `producedFluid`
//  • player handcrafting → `producedByHand`
//  • player hand mining (resources, trees, rocks) → `producedByHandMining`
//  • ingredients consumed by machines, labs, handcrafting → `consumed` / `consumedFluid`
//  • rocket launches are counted by GameSession from `WorldEvent.rocketLaunched` — the silo only emits the event.

/// Statistics time windows offered by the production stats screen (GDD §5.1).
public enum StatsWindow: Int, CaseIterable, Codable, Sendable {
    case oneMinute = 0, tenMinutes, oneHour, tenHours

    /// Window length in seconds.
    public var seconds: Int {
        switch self {
        case .oneMinute: return 60
        case .tenMinutes: return 600
        case .oneHour: return 3_600
        case .tenHours: return 36_000
        }
    }
    /// Ticks covered by one sample bucket.
    public var bucketTicks: Int { seconds * ticksPerSecond / ProductionStats.samplesPerWindow }
    public var bucketSeconds: Double { Double(bucketTicks) / Double(ticksPerSecond) }
    public var label: String {
        switch self {
        case .oneMinute: return "1m"
        case .tenMinutes: return "10m"
        case .oneHour: return "1h"
        case .tenHours: return "10h"
        }
    }
}

/// Direction of a statistic.
public enum StatsFlow: Int, Sendable { case produced = 0, consumed = 1 }

/// What a statistics series measures.
public enum StatSubject: Hashable, Sendable {
    case item(ItemIndex)
    case fluid(FluidIndex)
    /// Electric energy (joules) by entity prototype: production for generators/solar/accumulators, consumption
    /// for consumers.
    case power(EntityProtoIndex)
}

/// One row of a "top producers/consumers" query.
public struct StatEntry: Equatable, Sendable {
    public var subject: StatSubject
    /// Total amount within the window (items, fluid units or joules).
    public var amount: Double
    /// Same amount as a per-minute rate.
    public var perMinute: Double
}

public final class ProductionStats {
    public unowned let world: World

    /// Buckets per window (graph resolution).
    public static let samplesPerWindow = 120
    /// Pending values are folded into the windows every this many ticks (= the 1-minute window's bucket).
    public static let baseBucketTicks = 30

    // Dimensions (from the prototype DB).
    public let itemCount: Int
    public let fluidCount: Int
    public let entityCount: Int
    let seriesCount: Int

    // Lifetime totals.
    private(set) var machineProduced: [Int64]
    private(set) var handCrafted: [Int64]
    private(set) var handMined: [Int64]
    private(set) var itemsConsumed: [Int64]
    private(set) var fluidProducedTotal: [Double]
    private(set) var fluidConsumedTotal: [Double]
    private(set) var powerProducedTotal: [Double]
    private(set) var powerConsumedTotal: [Double]
    public private(set) var rocketsLaunched: Int = 0
    public private(set) var rocketsLaunchedWithSatellite: Int = 0

    /// Accumulates since the last fold (series-indexed).
    private var pending: [Double]
    /// Rings: window → series-major [series * samples + slot]. The slot at `heads[w]` is the bucket being filled.
    private var rings: [[Float]]
    private var heads: [Int]
    /// Completed buckets per window (≤ samples − 1), for "not enough history yet".
    private var filled: [Int]

    public init(world: World) {
        self.world = world
        itemCount = world.db.items.count
        fluidCount = world.db.fluids.count
        entityCount = world.db.entities.count
        seriesCount = 2 * (itemCount + fluidCount + entityCount)
        machineProduced = Array(repeating: 0, count: itemCount)
        handCrafted = machineProduced
        handMined = machineProduced
        itemsConsumed = machineProduced
        fluidProducedTotal = Array(repeating: 0, count: fluidCount)
        fluidConsumedTotal = fluidProducedTotal
        powerProducedTotal = Array(repeating: 0, count: entityCount)
        powerConsumedTotal = powerProducedTotal
        pending = Array(repeating: 0, count: seriesCount)
        let ringLen = seriesCount * ProductionStats.samplesPerWindow
        rings = StatsWindow.allCases.map { _ in Array(repeating: 0, count: ringLen) }
        heads = Array(repeating: 0, count: StatsWindow.allCases.count)
        filled = heads
    }

    public func setUp() {}

    // MARK: Series indexing

    @inline(__always) func series(_ s: StatSubject, _ f: StatsFlow) -> Int? {
        switch s {
        case .item(let i): return i >= 0 && i < itemCount ? i * 2 + f.rawValue : nil
        case .fluid(let i): return i >= 0 && i < fluidCount ? (itemCount + i) * 2 + f.rawValue : nil
        case .power(let i): return i >= 0 && i < entityCount ? (itemCount + fluidCount + i) * 2 + f.rawValue : nil
        }
    }

    // MARK: Recording (hot path)

    /// Items produced by a machine (crafted, smelted, mined by a drill, launched-rocket products).
    public func produced(item: Int, count: Int) {
        guard item >= 0, item < itemCount, count > 0 else { return }
        machineProduced[item] &+= Int64(count)
        pending[item &* 2] += Double(count)
    }

    /// Items produced by the player's handcrafting (excluded from "by machines" objectives).
    public func producedByHand(item: Int, count: Int) {
        guard item >= 0, item < itemCount, count > 0 else { return }
        handCrafted[item] &+= Int64(count)
        pending[item &* 2] += Double(count)
    }

    /// Items obtained by the player's hand mining (ores, stone, coal, wood, rock loot).
    public func producedByHandMining(item: Int, count: Int) {
        guard item >= 0, item < itemCount, count > 0 else { return }
        handMined[item] &+= Int64(count)
        pending[item &* 2] += Double(count)
    }

    /// Items consumed as ingredients (crafting start, lab unit start, rocket part, fuel burnt).
    public func consumed(item: Int, count: Int) {
        guard item >= 0, item < itemCount, count > 0 else { return }
        itemsConsumed[item] &+= Int64(count)
        pending[item &* 2 &+ 1] += Double(count)
    }

    public func producedFluid(_ fluid: Int, amount: Double) {
        guard fluid >= 0, fluid < fluidCount, amount > 0, amount.isFinite else { return }
        fluidProducedTotal[fluid] += amount
        pending[(itemCount &+ fluid) &* 2] += amount
    }

    public func consumedFluid(_ fluid: Int, amount: Double) {
        guard fluid >= 0, fluid < fluidCount, amount > 0, amount.isFinite else { return }
        fluidConsumedTotal[fluid] += amount
        pending[(itemCount &+ fluid) &* 2 &+ 1] += amount
    }

    /// Electric energy produced this tick by entities of a prototype (generators, solar, accumulator discharge).
    public func producedPower(entityProto: Int, joules: Double) {
        guard entityProto >= 0, entityProto < entityCount, joules > 0, joules.isFinite else { return }
        powerProducedTotal[entityProto] += joules
        pending[(itemCount &+ fluidCount &+ entityProto) &* 2] += joules
    }

    /// Electric energy consumed this tick by entities of a prototype.
    public func consumedPower(entityProto: Int, joules: Double) {
        guard entityProto >= 0, entityProto < entityCount, joules > 0, joules.isFinite else { return }
        powerConsumedTotal[entityProto] += joules
        pending[(itemCount &+ fluidCount &+ entityProto) &* 2 &+ 1] += joules
    }

    /// Counts a rocket launch. Called by GameSession when it sees `WorldEvent.rocketLaunched`.
    public func recordRocketLaunch(withSatellite: Bool) {
        rocketsLaunched += 1
        if withSatellite { rocketsLaunchedWithSatellite += 1 }
    }

    // MARK: Lifetime queries

    /// Total produced from all sources (machines + handcraft + hand mining).
    public func totalProduced(item: Int) -> Int {
        guard item >= 0, item < itemCount else { return 0 }
        return Int(machineProduced[item] &+ handCrafted[item] &+ handMined[item])
    }
    public func producedByMachines(item: Int) -> Int { item >= 0 && item < itemCount ? Int(machineProduced[item]) : 0 }
    public func handCraftedCount(item: Int) -> Int { item >= 0 && item < itemCount ? Int(handCrafted[item]) : 0 }
    public func handMinedCount(item: Int) -> Int { item >= 0 && item < itemCount ? Int(handMined[item]) : 0 }
    public func totalConsumed(item: Int) -> Int { item >= 0 && item < itemCount ? Int(itemsConsumed[item]) : 0 }
    public func totalProduced(fluid: Int) -> Double { fluid >= 0 && fluid < fluidCount ? fluidProducedTotal[fluid] : 0 }
    public func totalConsumed(fluid: Int) -> Double { fluid >= 0 && fluid < fluidCount ? fluidConsumedTotal[fluid] : 0 }
    public func totalPowerProduced(entityProto: Int) -> Double {
        entityProto >= 0 && entityProto < entityCount ? powerProducedTotal[entityProto] : 0
    }
    public func totalPowerConsumed(entityProto: Int) -> Double {
        entityProto >= 0 && entityProto < entityCount ? powerConsumedTotal[entityProto] : 0
    }

    // MARK: Window queries

    /// Sample values (amount per bucket), oldest → newest; the last element is the bucket currently being filled.
    /// Always `samplesPerWindow` long (zeros before history exists).
    public func samples(_ subject: StatSubject, _ flow: StatsFlow, window: StatsWindow) -> [Double] {
        guard let s = series(subject, flow) else { return Array(repeating: 0, count: Self.samplesPerWindow) }
        let n = Self.samplesPerWindow, w = window.rawValue, head = heads[w], base = s * n
        var out = [Double](repeating: 0, count: n)
        rings[w].withUnsafeBufferPointer { r in
            for k in 0..<n { out[k] = Double(r[base + (head + 1 + k) % n]) }
        }
        return out
    }

    /// Samples converted to per-minute rates (what the stats graph plots).
    public func seriesPerMinute(_ subject: StatSubject, _ flow: StatsFlow, window: StatsWindow) -> [Double] {
        let k = 60 / window.bucketSeconds
        return samples(subject, flow, window: window).map { $0 * k }
    }

    /// Total amount within the window (all buckets incl. the current partial one).
    public func total(_ subject: StatSubject, _ flow: StatsFlow, window: StatsWindow) -> Double {
        guard let s = series(subject, flow) else { return 0 }
        let n = Self.samplesPerWindow, base = s * n
        var sum: Double = 0
        rings[window.rawValue].withUnsafeBufferPointer { r in for k in 0..<n { sum += Double(r[base + k]) } }
        return sum
    }

    /// Average per-minute rate over the window.
    public func ratePerMinute(_ subject: StatSubject, _ flow: StatsFlow, window: StatsWindow) -> Double {
        total(subject, flow, window: window) / (Double(window.seconds) / 60)
    }

    /// Rolling 60 s production of an item (all sources) = items per minute. Used by rate objectives.
    public func rollingPerMinute(item: Int) -> Double { total(.item(item), .produced, window: .oneMinute) }
    public func rollingPerMinute(fluid: Int) -> Double { total(.fluid(fluid), .produced, window: .oneMinute) }

    /// Seconds of history available in a window (for graph axis labels before the window is full).
    public func historySeconds(window: StatsWindow) -> Double {
        Double(filled[window.rawValue]) * window.bucketSeconds
    }

    /// Top subjects by amount in a window, descending (ties by subject order). `kinds` filters items/fluids/power.
    public func top(_ flow: StatsFlow, window: StatsWindow, limit: Int = 10,
                    items: Bool = true, fluids: Bool = true, power: Bool = false) -> [StatEntry] {
        var out: [StatEntry] = []
        let minutes = Double(window.seconds) / 60
        func consider(_ subj: StatSubject) {
            let t = total(subj, flow, window: window)
            if t > 0 { out.append(StatEntry(subject: subj, amount: t, perMinute: t / minutes)) }
        }
        if items { for i in 0..<itemCount { consider(.item(i)) } }
        if fluids { for f in 0..<fluidCount { consider(.fluid(f)) } }
        if power { for e in 0..<entityCount { consider(.power(e)) } }
        out.sort { $0.amount > $1.amount }       // stable: insertion order breaks ties
        return Array(out.prefix(max(0, limit)))
    }

    // MARK: Tick

    public func update() {
        // world.tick is the tick being completed (incremented after stats.update in World.step).
        let t = Int(truncatingIfNeeded: world.tick &+ 1)
        guard t % Self.baseBucketTicks == 0 else { return }
        fold(completedTick: t)
    }

    /// Folds pending values into every window's current bucket; advances heads whose bucket completed.
    private func fold(completedTick t: Int) {
        let n = Self.samplesPerWindow
        for w in 0..<rings.count {
            let head = heads[w]
            rings[w].withUnsafeMutableBufferPointer { r in
                pending.withUnsafeBufferPointer { p in
                    for s in 0..<seriesCount where p[s] != 0 { r[s * n + head] += Float(p[s]) }
                }
            }
            let bt = StatsWindow(rawValue: w)!.bucketTicks
            if t % bt == 0 {
                let next = (head + 1) % n
                rings[w].withUnsafeMutableBufferPointer { r in for s in 0..<seriesCount { r[s * n + next] = 0 } }
                heads[w] = next
                filled[w] = min(filled[w] + 1, n - 1)
            }
        }
        for s in 0..<seriesCount where pending[s] != 0 { pending[s] = 0 }
    }

    // MARK: Persistence

    private static let layoutVersion: UInt8 = 1

    public func serialize(to w: inout BinaryWriter) {
        w.write(Self.layoutVersion)
        w.writeVarInt(itemCount); w.writeVarInt(fluidCount); w.writeVarInt(entityCount)
        w.writePODArray(machineProduced)
        w.writePODArray(handCrafted)
        w.writePODArray(handMined)
        w.writePODArray(itemsConsumed)
        w.writePODArray(fluidProducedTotal.map(\.bitPattern))
        w.writePODArray(fluidConsumedTotal.map(\.bitPattern))
        w.writePODArray(powerProducedTotal.map(\.bitPattern))
        w.writePODArray(powerConsumedTotal.map(\.bitPattern))
        w.writeVarInt(rocketsLaunched)
        w.writeVarInt(rocketsLaunchedWithSatellite)
        // Pending (sparse).
        let pendingNZ = (0..<seriesCount).filter { pending[$0] != 0 }
        w.writeVarInt(pendingNZ.count)
        for s in pendingNZ { w.writeVarInt(s); w.write(pending[s]) }
        // Rings (sparse by series).
        let n = Self.samplesPerWindow
        w.writeVarInt(n)
        w.writeVarInt(rings.count)
        for wi in 0..<rings.count {
            w.writeVarInt(heads[wi]); w.writeVarInt(filled[wi])
            var nz: [Int] = []
            rings[wi].withUnsafeBufferPointer { r in
                for s in 0..<seriesCount {
                    var any = false
                    for k in 0..<n where r[s * n + k] != 0 { any = true; break }
                    if any { nz.append(s) }
                }
            }
            w.writeVarInt(nz.count)
            for s in nz {
                w.writeVarInt(s)
                w.writeFloatArrayRaw(rings[wi], from: s * n, count: n)
            }
        }
    }

    public func deserialize(from r: inout BinaryReader) throws {
        let v = try r.read(UInt8.self)
        guard v >= 1 else { throw BinaryCodingError.invalidValue("stats version \(v)") }
        let ic = try r.readVarInt(), fc = try r.readVarInt(), ec = try r.readVarInt()
        // Prototype tables may only grow by appending (checked by WorldCodec), so saved arrays are prefixes.
        guard ic <= itemCount, fc <= fluidCount, ec <= entityCount else {
            throw BinaryCodingError.invalidValue("stats dimensions exceed game data")
        }
        func prefix<T>(_ saved: [T], into dst: inout [T]) { for i in 0..<saved.count { dst[i] = saved[i] } }
        prefix(try r.readPODArray(Int64.self, expectedCount: ic), into: &machineProduced)
        prefix(try r.readPODArray(Int64.self, expectedCount: ic), into: &handCrafted)
        prefix(try r.readPODArray(Int64.self, expectedCount: ic), into: &handMined)
        prefix(try r.readPODArray(Int64.self, expectedCount: ic), into: &itemsConsumed)
        prefix(try r.readPODArray(UInt64.self, expectedCount: fc).map(Double.init(bitPattern:)), into: &fluidProducedTotal)
        prefix(try r.readPODArray(UInt64.self, expectedCount: fc).map(Double.init(bitPattern:)), into: &fluidConsumedTotal)
        prefix(try r.readPODArray(UInt64.self, expectedCount: ec).map(Double.init(bitPattern:)), into: &powerProducedTotal)
        prefix(try r.readPODArray(UInt64.self, expectedCount: ec).map(Double.init(bitPattern:)), into: &powerConsumedTotal)
        rocketsLaunched = try r.readVarInt()
        rocketsLaunchedWithSatellite = try r.readVarInt()

        // Saved series index → current series index (layout: items, fluids, power; 2 flows each).
        func remap(_ s: Int) throws -> Int {
            let sub = s / 2, flow = s % 2
            if sub < ic { return sub * 2 + flow }
            if sub < ic + fc { return (itemCount + sub - ic) * 2 + flow }
            if sub < ic + fc + ec { return (itemCount + fluidCount + sub - ic - fc) * 2 + flow }
            throw BinaryCodingError.invalidValue("stats series \(s)")
        }
        let savedSeries = 2 * (ic + fc + ec)
        for i in 0..<seriesCount { pending[i] = 0 }
        let pc = try r.readVarInt()
        guard pc <= savedSeries else { throw BinaryCodingError.invalidValue("stats pending count") }
        for _ in 0..<pc { let s = try remap(try r.readVarInt()); pending[s] = try r.readDouble() }

        let n = try r.readVarInt()
        let windows = try r.readVarInt()
        guard windows <= 64 else { throw BinaryCodingError.invalidValue("stats windows \(windows)") }
        let compatible = n == Self.samplesPerWindow
        for w in 0..<rings.count { for i in rings[w].indices { rings[w][i] = 0 }; heads[w] = 0; filled[w] = 0 }
        for wi in 0..<windows {
            let head = try r.readVarInt(), fill = try r.readVarInt()
            let count = try r.readVarInt()
            guard count <= savedSeries else { throw BinaryCodingError.invalidValue("stats ring count") }
            let use = compatible && wi < rings.count && head < n
            if use { heads[wi] = head; filled[wi] = min(fill, n - 1) }
            for _ in 0..<count {
                let s = try remap(try r.readVarInt())
                let vals = try r.readPODElements(UInt32.self, count: n)
                if use { for k in 0..<n { rings[wi][s * n + k] = Float(bitPattern: vals[k]) } }
            }
        }
    }
}

extension BinaryWriter {
    /// Writes `count` floats from `a[from...]` raw (no count prefix).
    mutating func writeFloatArrayRaw(_ a: [Float], from: Int, count: Int) {
        if hostIsLittleEndian {
            a.withUnsafeBytes { raw in
                bytes.append(contentsOf: UnsafeRawBufferPointer(rebasing: raw[(from * 4)..<((from + count) * 4)]))
            }
        } else {
            for k in from..<(from + count) { write(a[k].bitPattern) }
        }
    }
}
