// Gearforge — FactoryCore
// Electric networks: poles (wiring + supply areas), generators (steam engine/turbine), solar, accumulators, boilers.
// Owner: Energy engineer. (05_mechanics §5, §8)
//
// - Poles auto-wire to up to 5 nearest poles within the smaller wire reach. Networks = connected pole groups.
// - Electric entities are endpoints; an endpoint belongs to the first network whose pole supply area overlaps it.
// - Consumers call `request(e, joules:)` during tick T for tick T+1; `update()` (first system each tick) solves every
//   network: solar → steam → accumulator discharge, primary-input consumers first; surplus charges accumulators.
//   Satisfaction σ = served / requested.
// - Boilers (burner) turn water into 165 °C steam (60/s at 1.8 MW); steam engines burn steam for the power they deliver.

public final class PowerSystem: EntitySystem, ItemEndpoint {
    public unowned let world: World
    public init(world: World) { self.world = world }

    enum EPClass: UInt8 { case consumerSecondary = 0, consumerPrimary, solar, steam, accumulator }

    struct Endpoint {
        var entity: Int32 = -1
        var cls: EPClass = .consumerSecondary
        var network: Int32 = -1
        var request: Double = 0           // this tick (J)
        var nextRequest: Double = 0       // accumulated during this tick for the next
        var stored: Double = 0            // accumulators
        var produced: Double = 0          // last tick (J), generators/solar/accumulator discharge
        // cached prototype data
        var proto: Int32 = -1
        var solarJ: Double = 0            // per tick at full daylight
        var accCap: Double = 0
        var accIn: Double = 0             // per tick
        var accOut: Double = 0
        var genMaxJ: Double = 0
        var genUsage: Double = 0
        var genMaxT: Double = 165
        var genEff: Double = 1
    }

    private func cache(_ ep: inout Endpoint) {
        let p = world.db.entities[Int(world.entities[ep.entity].proto)]
        ep.proto = world.entities[ep.entity].proto
        ep.solarJ = (p.solar?.production ?? 0) / 60
        ep.accCap = p.accumulator?.capacity ?? 5e6
        ep.accIn = (p.accumulator?.inputFlowLimit ?? 3e5) / 60
        ep.accOut = (p.accumulator?.outputFlowLimit ?? 3e5) / 60
        if let g = p.generator {
            ep.genMaxJ = g.maxPowerOutput / 60; ep.genUsage = g.fluidUsagePerTick
            ep.genMaxT = g.maximumTemperature; ep.genEff = g.effectivity
        }
    }

    struct Pole {
        var entity: Int32 = -1
        var center = Vec2.zero
        var reach: Double = 7.5
        var supply: Double = 2.5
        var maxConnections = 5
        var wires: [Int32] = []           // other pole indices
        var network: Int32 = -1
    }

    struct Boiler {
        var entity: Int32 = -1
        var burner = BurnerEnergy(slots: 1)
        var working = false
    }

    public struct NetworkStats: Sendable {
        public var satisfaction: Double = 0
        public var demandW: Double = 0
        public var productionW: Double = 0
        public var capacityW: Double = 0
        public var accumulatorCharge: Double = 0
        public var accumulatorCapacity: Double = 0
    }

    var endpoints: [Endpoint] = []
    private var freeEndpoints: [Int32] = []
    var poles: [Pole] = []
    private var freePoles: [Int32] = []
    var boilers: [Boiler] = []
    private var freeBoilers: [Int32] = []

    private var networkSatisfaction: [Double] = []
    private var networkSatisfactionPrimary: [Double] = []
    public private(set) var networkStats: [NetworkStats] = []
    private var dirty = true
    private var networkCount = 0

    // MARK: API used by every electric consumer

    /// Registers `e` as an electric endpoint if its prototype has an electric energy source and it is not a pole.
    public func registerEndpointIfNeeded(_ e: Int32) {
        let rec = world.entities[e]
        let p = world.db.entities[Int(rec.proto)]
        guard let es = p.energySource, es.type == "electric", rec.kind != .electricPole else { return }
        var ep = Endpoint()
        ep.entity = e
        switch es.usagePriority ?? "secondary-input" {
        case "solar": ep.cls = .solar
        case "secondary-output", "primary-output": ep.cls = .steam
        case "tertiary": ep.cls = .accumulator
        case "primary-input": ep.cls = .consumerPrimary
        default: ep.cls = .consumerSecondary
        }
        cache(&ep)
        let slot: Int32
        if let f = freeEndpoints.popLast() { slot = f; endpoints[Int(f)] = ep } else { slot = Int32(endpoints.count); endpoints.append(ep) }
        world.entities.setPowerSlot(e, slot)
        dirty = true
    }

    public func unregisterEndpointIfNeeded(_ e: Int32) {
        let s = world.entities[e].powerSlot
        guard s >= 0, Int(s) < endpoints.count else { return }
        endpoints[Int(s)] = Endpoint()
        freeEndpoints.append(s)
        world.entities.setPowerSlot(e, -1)
        dirty = true
    }

    /// Satisfaction (0...1) of the network the entity is connected to, solved at the start of this tick.
    /// 0 when unconnected. Consumers multiply their speed by this.
    @inline(__always) public func satisfaction(of e: Int32) -> Double {
        if world.cheatInfinitePower { return 1 }
        let s = world.entities[e].powerSlot
        guard s >= 0 else { return 0 }
        let n = endpoints[Int(s)].network
        guard n >= 0, Int(n) < networkSatisfaction.count else { return 0 }
        return endpoints[Int(s)].cls == .consumerPrimary ? networkSatisfactionPrimary[Int(n)] : networkSatisfaction[Int(n)]
    }

    /// Consumer request for NEXT tick in joules (drain + working usage × consumption multiplier) / 60.
    @inline(__always) public func request(_ e: Int32, joules: Double) {
        let s = world.entities[e].powerSlot
        guard s >= 0 else { return }
        endpoints[Int(s)].nextRequest += joules
    }

    /// Network id for UI (power graph, satisfaction in HUD) or -1.
    public func networkID(of e: Int32) -> Int {
        ensureTopology()
        let rec = world.entities[e]
        if rec.kind == .electricPole, rec.component >= 0 { return Int(poles[Int(rec.component)].network) }
        let s = rec.powerSlot
        return s >= 0 ? Int(endpoints[Int(s)].network) : -1
    }

    public func stats(network: Int) -> NetworkStats? {
        network >= 0 && network < networkStats.count ? networkStats[network] : nil
    }

    /// Network covering a world point (HUD: power of the network the character stands in).
    public func network(at p: Vec2) -> Int {
        ensureTopology()
        for pole in poles where pole.entity >= 0 {
            if abs(p.x - pole.center.x) <= pole.supply && abs(p.y - pole.center.y) <= pole.supply { return Int(pole.network) }
        }
        return -1
    }

    /// Copper wires (pole centre pairs) intersecting `rect`, each once.
    public func wires(in rect: TileRect) -> [(Vec2, Vec2)] {
        ensureTopology()
        let r = rect.expanded(by: 32)
        var out: [(Vec2, Vec2)] = []
        for (i, p) in poles.enumerated() where p.entity >= 0 && r.contains(p.center.tile) {
            for j in p.wires where Int(j) > i || !r.contains(poles[Int(j)].center.tile) { out.append((p.center, poles[Int(j)].center)) }
        }
        return out
    }

    /// Supply area of a pole (tiles), for the build overlay.
    public func supplyArea(of e: Int32) -> TileRect? {
        let rec = world.entities[e]
        guard rec.kind == .electricPole, let pp = world.db.entities[Int(rec.proto)].pole else { return nil }
        let c = rec.center
        let d = pp.supplyAreaDistance
        return TileRect(x: Int32((c.x - d).rounded(.down)), y: Int32((c.y - d).rounded(.down)),
                        w: Int32((2 * d).rounded(.up)), h: Int32((2 * d).rounded(.up)))
    }

    /// Accumulator charge (J) for UI.
    public func accumulatorCharge(of e: Int32) -> Double {
        let s = world.entities[e].powerSlot
        return s >= 0 ? endpoints[Int(s)].stored : 0
    }
    /// Power produced last tick (W) by a generator / solar panel / accumulator.
    public func powerOutput(of e: Int32) -> Double {
        let s = world.entities[e].powerSlot
        return s >= 0 ? endpoints[Int(s)].produced * Double(ticksPerSecond) : 0
    }
    public func boilerFuel(of e: Int32) -> BurnerEnergy? {
        guard let b = boilerIndex(e) else { return nil }
        return boilers[b].burner
    }
    public func isBoilerWorking(_ e: Int32) -> Bool { boilerIndex(e).map { boilers[$0].working } ?? false }
    /// Pole wire endpoints (other pole entities) for UI.
    public func wiredPoles(of e: Int32) -> [Int32] {
        let rec = world.entities[e]
        guard rec.kind == .electricPole, rec.component >= 0 else { return [] }
        return poles[Int(rec.component)].wires.map { poles[Int($0)].entity }
    }

    // MARK: EntitySystem

    public func entityAdded(_ e: Int32) {
        let rec = world.entities[e]
        let p = world.db.entities[Int(rec.proto)]
        switch rec.kind {
        case .electricPole:
            guard let pp = p.pole else { return }
            var pole = Pole()
            pole.entity = e
            pole.center = rec.center
            pole.reach = pp.wireReach
            pole.supply = pp.supplyAreaDistance
            pole.maxConnections = pp.maxConnections
            let idx: Int32
            if let f = freePoles.popLast() { idx = f; poles[Int(f)] = pole } else { idx = Int32(poles.count); poles.append(pole) }
            world.entities.setComponent(e, idx)
            autoWire(Int(idx))
            dirty = true
        case .boiler:
            var b = Boiler()
            b.entity = e
            b.burner = BurnerEnergy(slots: p.energySource?.fuelSlots ?? 1, effectivity: p.energySource?.effectivity ?? 1)
            let idx: Int32
            if let f = freeBoilers.popLast() { idx = f; boilers[Int(f)] = b } else { idx = Int32(boilers.count); boilers.append(b) }
            world.entities.setComponent(e, idx)
        default:
            break   // generators/solar/accumulators are endpoints only
        }
    }

    private func autoWire(_ i: Int) {
        var cands: [(Double, Int)] = []
        for (j, q) in poles.enumerated() where j != i && q.entity >= 0 {
            let d = poles[i].center.distance(to: q.center)
            if d <= min(poles[i].reach, q.reach) + 1e-9 && q.wires.count < q.maxConnections { cands.append((d, j)) }
        }
        cands.sort { $0.0 < $1.0 || ($0.0 == $1.0 && $0.1 < $1.1) }
        for (_, j) in cands where poles[i].wires.count < poles[i].maxConnections {
            // skip if j is already connected (through a common neighbour) to avoid triangles
            let shared = poles[i].wires.contains { poles[Int($0)].wires.contains(Int32(j)) }
            if shared { continue }
            poles[i].wires.append(Int32(j))
            poles[j].wires.append(Int32(i))
        }
    }

    public func entityRemoved(_ e: Int32) {
        let rec = world.entities[e]
        let c = rec.component
        switch rec.kind {
        case .electricPole:
            guard c >= 0 else { return }
            for j in poles[Int(c)].wires { poles[Int(j)].wires.removeAll { $0 == c } }
            poles[Int(c)] = Pole()
            freePoles.append(c)
            dirty = true
        case .boiler:
            guard c >= 0 else { return }
            boilers[Int(c)] = Boiler()
            freeBoilers.append(c)
        default: break
        }
        world.entities.setComponent(e, -1)
    }

    public func entityRotated(_ e: Int32) {}
    public func neighborhoodChanged(_ rect: TileRect) {}

    public func takeContents(_ e: Int32) -> [ItemStack] {
        guard let b = boilerIndex(e) else { return [] }
        let out = boilers[b].burner.fuel.contents().map { ItemStack(item: $0.item, count: $0.count) }
        boilers[b].burner.fuel = Inventory(size: boilers[b].burner.fuel.size)
        return out
    }

    @inline(__always) private func boilerIndex(_ e: Int32) -> Int? {
        let rec = world.entities[e]
        guard rec.kind == .boiler, rec.component >= 0, Int(rec.component) < boilers.count, boilers[Int(rec.component)].entity == e else { return nil }
        return Int(rec.component)
    }

    // MARK: Topology

    @inline(__always) private func ensureTopology() { if dirty { rebuild() } }

    private func rebuild() {
        dirty = false
        // networks from wires
        for i in poles.indices { poles[i].network = -1 }
        var n: Int32 = 0
        for i in poles.indices where poles[i].entity >= 0 && poles[i].network < 0 {
            var stack = [i]
            poles[i].network = n
            while let x = stack.popLast() {
                for j in poles[x].wires where poles[Int(j)].network < 0 { poles[Int(j)].network = n; stack.append(Int(j)) }
            }
            n += 1
        }
        networkCount = Int(n)
        // spatial index of poles by chunk
        var byChunk: [ChunkPos: [Int]] = [:]
        for (i, p) in poles.enumerated() where p.entity >= 0 { byChunk[p.center.tile.chunk, default: []].append(i) }
        for k in endpoints.indices where endpoints[k].entity >= 0 {
            let r = world.entities[endpoints[k].entity].rect
            endpoints[k].network = -1
            let c0 = TilePos(r.x - 10, r.y - 10).chunk, c1 = TilePos(r.maxX + 10, r.maxY + 10).chunk
            var best: Int = .max
            var cy = c0.y
            while cy <= c1.y {
                var cx = c0.x
                while cx <= c1.x {
                    for pi in byChunk[ChunkPos(cx, cy)] ?? [] where pi < best {
                        let p = poles[pi]
                        let sx0 = p.center.x - p.supply, sx1 = p.center.x + p.supply
                        let sy0 = p.center.y - p.supply, sy1 = p.center.y + p.supply
                        if Double(r.x) < sx1 && Double(r.maxX) > sx0 && Double(r.y) < sy1 && Double(r.maxY) > sy0 { best = pi }
                    }
                    cx += 1
                }
                cy += 1
            }
            if best != .max { endpoints[k].network = poles[best].network }
        }
        networkSatisfaction = Array(repeating: 0, count: networkCount)
        networkSatisfactionPrimary = Array(repeating: 0, count: networkCount)
        networkStats = Array(repeating: NetworkStats(), count: networkCount)
    }

    // MARK: Tick

    public func update() {
        ensureTopology()
        updateBoilers()
        let nc = networkCount
        if nc == 0 {
            for k in endpoints.indices { endpoints[k].request = endpoints[k].nextRequest; endpoints[k].nextRequest = 0 }
            return
        }
        var d1 = [Double](repeating: 0, count: nc), d2 = d1, solar = d1, steam = d1, accOut = d1, accIn = d1, accStored = d1, accCap = d1
        let daylight = world.daylight
        // Gather
        for k in endpoints.indices where endpoints[k].entity >= 0 {
            endpoints[k].request = endpoints[k].nextRequest
            endpoints[k].nextRequest = 0
            endpoints[k].produced = 0
            let n = Int(endpoints[k].network)
            guard n >= 0 else { continue }
            switch endpoints[k].cls {
            case .consumerSecondary: d2[n] += endpoints[k].request
            case .consumerPrimary: d1[n] += endpoints[k].request
            case .solar: solar[n] += endpoints[k].solarJ * daylight
            case .steam: steam[n] += steamAvailable(k)
            case .accumulator:
                accOut[n] += min(endpoints[k].accOut, endpoints[k].stored)
                accIn[n] += min(endpoints[k].accIn, endpoints[k].accCap - endpoints[k].stored)
                accStored[n] += endpoints[k].stored
                accCap[n] += endpoints[k].accCap
            }
        }
        // Solve
        var fSteam = [Double](repeating: 0, count: nc), fAccOut = fSteam, fAccIn = fSteam, fSolar = fSteam
        for n in 0..<nc {
            let demand = d1[n] + d2[n]
            let gen = solar[n] + steam[n]
            var served: Double
            if gen >= demand {
                served = demand
                let surplus = gen - demand
                let charge = min(surplus, accIn[n])
                fAccIn[n] = accIn[n] > 0 ? charge / accIn[n] : 0
                let used = demand + charge
                let fromSolar = min(used, solar[n])
                fSolar[n] = solar[n] > 0 ? fromSolar / solar[n] : 0
                fSteam[n] = steam[n] > 0 ? (used - fromSolar) / steam[n] : 0
            } else {
                fSolar[n] = solar[n] > 0 ? 1 : 0
                fSteam[n] = steam[n] > 0 ? 1 : 0
                let discharge = min(demand - gen, accOut[n])
                fAccOut[n] = accOut[n] > 0 ? discharge / accOut[n] : 0
                served = gen + discharge
            }
            let s1 = d1[n] > 0 ? min(1, served / d1[n]) : 1
            let rest = max(0, served - d1[n])
            let s2 = d2[n] > 0 ? min(1, rest / d2[n]) : 1
            networkSatisfactionPrimary[n] = s1
            networkSatisfaction[n] = s2
            networkStats[n] = NetworkStats(satisfaction: demand > 0 ? served / demand : 1,
                                           demandW: demand * 60, productionW: served * 60 + fAccIn[n] * accIn[n] * 60,
                                           capacityW: (solar[n] + steam[n] + accOut[n]) * 60,
                                           accumulatorCharge: accStored[n], accumulatorCapacity: accCap[n])
        }
        // Apply to producers / accumulators / consumers (stats)
        let stats = world.stats!
        for k in endpoints.indices where endpoints[k].entity >= 0 {
            let n = Int(endpoints[k].network)
            guard n >= 0 else { continue }
            let proto = Int(endpoints[k].proto)
            switch endpoints[k].cls {
            case .solar:
                let j = endpoints[k].solarJ * daylight * fSolar[n]
                endpoints[k].produced = j
                if j > 0 { stats.producedPower(entityProto: proto, joules: j) }
            case .steam:
                let j = steamAvailable(k) * fSteam[n]
                if j > 0 { consumeSteam(k, joules: j); endpoints[k].produced = j; stats.producedPower(entityProto: proto, joules: j) }
            case .accumulator:
                if fAccOut[n] > 0 {
                    let j = min(endpoints[k].accOut, endpoints[k].stored) * fAccOut[n]
                    endpoints[k].stored -= j; endpoints[k].produced = j
                } else if fAccIn[n] > 0 {
                    endpoints[k].stored += min(endpoints[k].accIn, endpoints[k].accCap - endpoints[k].stored) * fAccIn[n]
                }
            case .consumerSecondary, .consumerPrimary:
                let s = endpoints[k].cls == .consumerPrimary ? networkSatisfactionPrimary[n] : networkSatisfaction[n]
                let j = endpoints[k].request * s
                if j > 0 { stats.consumedPower(entityProto: proto, joules: j) }
            }
        }
    }

    /// Energy (J) a steam generator can deliver this tick from the steam in its box.
    private func steamAvailable(_ k: Int) -> Double {
        let e = endpoints[k].entity
        let fluids = world.fluids!
        let amt = fluids.amount(e, box: 0)
        guard amt > 0 else { return 0 }
        let t = min(fluids.temperature(e, box: 0), endpoints[k].genMaxT)
        let perUnit = max(0, t - 15) * 200 * endpoints[k].genEff
        return min(endpoints[k].genMaxJ, min(amt, endpoints[k].genUsage) * perUnit)
    }

    private func consumeSteam(_ k: Int, joules: Double) {
        let e = endpoints[k].entity
        let fluids = world.fluids!
        let t = min(fluids.temperature(e, box: 0), endpoints[k].genMaxT)
        let perUnit = max(1e-9, (t - 15) * 200 * endpoints[k].genEff)
        fluids.remove(e, box: 0, amount: joules / perUnit)
    }

    private func updateBoilers() {
        let db = world.db
        let fluids = world.fluids!
        for i in boilers.indices where boilers[i].entity >= 0 {
            let e = boilers[i].entity
            let p = db.entities[Int(world.entities[e].proto)]
            guard let bp = p.boiler else { continue }
            boilers[i].working = false
            let water = fluids.amount(e, box: 0)
            let steamSpace = fluids.capacity(e, box: 1) - fluids.amount(e, box: 1)
            let perUnit = (bp.targetTemperature - 15) * 200          // J per steam unit
            let maxUnits = bp.energyConsumption / 60 / perUnit       // 1 unit/tick
            let units = min(maxUnits, water, steamSpace)
            guard units > 1e-6 else { continue }
            let need = units * perUnit
            let frac = boilers[i].burner.draw(need, db: db)
            guard frac > 0 else { continue }
            let made = units * frac
            fluids.remove(e, box: 0, amount: made)
            fluids.add(e, box: 1, fluid: db.fluid("steam"), amount: made, temperature: bp.targetTemperature)
            boilers[i].working = true
        }
    }

    // MARK: Persistence

    public func serialize(to w: inout BinaryWriter) {
        w.write(UInt8(1))
        w.writeVarInt(endpoints.count)
        for ep in endpoints { w.write(ep.entity); w.write(ep.cls.rawValue); w.write(ep.nextRequest); w.write(ep.stored) }
        w.writeVarInt(poles.count)
        for p in poles { w.write(p.entity); w.writeArray(p.wires) { $0.write($1) } }
        w.writeVarInt(boilers.count)
        for b in boilers { w.write(b.entity); if b.entity >= 0 { b.burner.serialize(to: &w) } }
    }

    public func deserialize(from r: inout BinaryReader) throws {
        _ = try r.read(UInt8.self)
        endpoints = []; freeEndpoints = []
        let ne = try r.readVarInt()
        for i in 0..<ne {
            var ep = Endpoint()
            ep.entity = try r.read(Int32.self)
            ep.cls = EPClass(rawValue: try r.read(UInt8.self)) ?? .consumerSecondary
            ep.nextRequest = try r.readDouble(); ep.stored = try r.readDouble()
            endpoints.append(ep)
            if ep.entity < 0 { freeEndpoints.append(Int32(i)) }
        }
        poles = []; freePoles = []
        let np = try r.readVarInt()
        for i in 0..<np {
            var p = Pole()
            p.entity = try r.read(Int32.self)
            p.wires = try r.readArray { try $0.read(Int32.self) }
            poles.append(p)
            if p.entity < 0 { freePoles.append(Int32(i)) }
        }
        boilers = []; freeBoilers = []
        let nb = try r.readVarInt()
        for i in 0..<nb {
            var b = Boiler()
            b.entity = try r.read(Int32.self)
            if b.entity >= 0 { b.burner = try BurnerEnergy(from: &r) } else { freeBoilers.append(Int32(i)) }
            boilers.append(b)
        }
        dirty = true
    }

    public func didLoad() {
        for k in endpoints.indices where endpoints[k].entity >= 0 { cache(&endpoints[k]) }
        for i in poles.indices where poles[i].entity >= 0 {
            let rec = world.entities[poles[i].entity]
            if let pp = world.db.entities[Int(rec.proto)].pole {
                poles[i].center = rec.center; poles[i].reach = pp.wireReach
                poles[i].supply = pp.supplyAreaDistance; poles[i].maxConnections = pp.maxConnections
            }
        }
        dirty = true
        ensureTopology()
    }

    // MARK: ItemEndpoint (boiler fuel)

    public func acceptCount(_ e: Int32, item: Int, count: Int, source: ItemTransferSource) -> Int {
        guard let b = boilerIndex(e), BurnerEnergy.isFuel(item, db: world.db) else { return 0 }
        let room = boilers[b].burner.fuel.canInsert(item: item, count: count, stackSize: world.stackSize(item))
        if source == .player { return room }
        return max(0, min(room, 5 - boilers[b].burner.fuel.count(of: item)))
    }
    public func insert(_ e: Int32, item: Int, count: Int, source: ItemTransferSource) -> Int {
        let n = acceptCount(e, item: item, count: count, source: source)
        guard n > 0, let b = boilerIndex(e) else { return 0 }
        return boilers[b].burner.fuel.insert(item: item, count: n, stackSize: world.stackSize(item))
    }
    public func peekExtract(_ e: Int32, source: ItemTransferSource, filter: (Int) -> Bool) -> ItemStack? {
        guard source == .player, let b = boilerIndex(e) else { return nil }
        for s in boilers[b].burner.fuel.slots where !s.isEmpty && filter(Int(s.item)) { return s }
        return nil
    }
    public func extract(_ e: Int32, item: Int, count: Int, source: ItemTransferSource) -> Int {
        guard source == .player, let b = boilerIndex(e) else { return 0 }
        return boilers[b].burner.fuel.remove(item: item, count: count)
    }
}
