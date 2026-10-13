// Gearforge — FactoryCore
// Inserters (burner, basic, long-handed, fast, filter, stack, stack filter) (05_mechanics §2).
// Owner: Logistics engineer.
//
// State machine: pickup → swing to drop → drop → swing back. A half swing takes ceil(0.5 / rotationSpeed) ticks
// at full energy (matches the 1.1 chest-to-chest table). Idle inserters sleep (re-check every `idleRecheck` ticks
// for entity sources, every tick for belt sources) so a waiting inserter costs almost nothing.

import Foundation

public final class InserterSystem: EntitySystem, ItemEndpoint {
    public unowned let world: World
    public init(world: World) { self.world = world }

    enum Phase: UInt8 { case pickup = 0, toDrop, drop, toPickup }

    struct Comp {
        var entity: Int32 = -1
        var proto: Int32 = -1
        var phase: Phase = .pickup
        var progress: Double = 0          // ticks of swing done
        var halfTicks: Double = 36
        var handItem: Int32 = -1
        var handCount: Int32 = 0
        var filters: [Int32] = []
        var burner: BurnerEnergy? = nil
        var wakeTick: UInt64 = 0
        var status: EntityStatus = .waitingForSource
        var isStack = false
        var pickup = Vec2.zero            // world coords
        var drop = Vec2.zero
        var center = Vec2.zero
        var movingJoulesPerTick: Double = 0
        var drainJoulesPerTick: Double = 0
        var beltTicksWaited: Int32 = 0
    }

    var comps: [Comp] = []
    private var free: [Int32] = []
    static let idleRecheck: UInt64 = 8
    /// Fuel items a burner inserter (or any fuel target) accepts from inserters.
    static let fuelInsertLimit = 5

    @inline(__always) private func comp(_ e: Int32) -> Int? {
        let c = world.entities[e].component
        return c >= 0 && Int(c) < comps.count && comps[Int(c)].entity == e ? Int(c) : nil
    }

    // MARK: Public API

    /// Hand position (world tile units) for rendering, and held stack.
    public func handPosition(of e: Int32) -> Vec2 {
        guard let c = comp(e) else { return world.entities[e].center }
        let k = comps[c]
        let a = k.pickup - k.center, b = k.drop - k.center
        let ra = a.length, rb = b.length
        let angA = atan2(a.y, a.x)
        let t: Double
        switch k.phase {
        case .pickup: return k.pickup
        case .drop: return k.drop
        case .toDrop: t = min(1, k.progress / k.halfTicks)
        case .toPickup: t = 1 - min(1, k.progress / k.halfTicks)
        }
        let ang = angA + Double.pi * t
        let r = ra + (rb - ra) * t
        return Vec2(k.center.x + cos(ang) * r, k.center.y + sin(ang) * r)
    }

    public func heldStack(of e: Int32) -> ItemStack {
        guard let c = comp(e) else { return .empty }
        return comps[c].handCount > 0 ? ItemStack(item: comps[c].handItem, count: comps[c].handCount) : .empty
    }
    public func status(of e: Int32) -> EntityStatus { comp(e).map { comps[$0].status } ?? .idle }
    public func filters(of e: Int32) -> [Int] { comp(e).map { comps[$0].filters.map(Int.init) } ?? [] }
    public func setFilter(_ e: Int32, slot: Int, item: Int) {
        guard let c = comp(e), slot >= 0, slot < comps[c].filters.count else { return }
        comps[c].filters[slot] = Int32(item)
        comps[c].wakeTick = 0
    }
    public func fuel(of e: Int32) -> BurnerEnergy? { comp(e).flatMap { comps[$0].burner } }
    /// Current hand capacity including research bonuses.
    public func handSize(of e: Int32) -> Int { comp(e).map { handSize(comps[$0]) } ?? 1 }
    /// World-space pickup and drop points (for build-mode overlays).
    public func pickupDropPoints(of e: Int32) -> (pickup: Vec2, drop: Vec2)? {
        guard let c = comp(e) else { return nil }
        return (comps[c].pickup, comps[c].drop)
    }

    @inline(__always) private func handSize(_ k: Comp) -> Int {
        1 + (k.isStack ? world.bonuses.stackInserterBonus : world.bonuses.inserterStackBonus)
    }

    // MARK: Lifecycle

    private func configure(_ k: inout Comp, _ e: Int32) {
        let rec = world.entities[e]
        let p = world.db.entities[Int(rec.proto)]
        guard let ins = p.inserter else { return }
        k.center = rec.center
        k.pickup = k.center + rec.direction.rotate(ins.pickup)
        k.drop = k.center + rec.direction.rotate(ins.drop)
        k.halfTicks = max(1, (0.5 / ins.rotationSpeed).rounded(.up))
        k.isStack = ins.isStack
        k.movingJoulesPerTick = ins.rotationSpeed * ins.energyPerRotation + ins.extensionSpeed * ins.energyPerMovement
        k.drainJoulesPerTick = (p.energySource?.drain ?? 0) / Double(ticksPerSecond)
    }

    public func entityAdded(_ e: Int32) {
        let rec = world.entities[e]
        let p = world.db.entities[Int(rec.proto)]
        guard let ins = p.inserter else { return }
        var k = Comp()
        k.entity = e
        k.proto = rec.proto
        k.filters = Array(repeating: -1, count: ins.filterSlots)
        if p.energySource?.type == "burner" {
            var b = BurnerEnergy(slots: p.energySource?.fuelSlots ?? 1, effectivity: p.energySource?.effectivity ?? 1)
            // [GF] one swing of energy on placement so it can grab its first fuel (05 §2.5)
            let halfTicks = max(1, (0.5 / ins.rotationSpeed).rounded(.up))
            b.remaining = (ins.rotationSpeed * ins.energyPerRotation + ins.extensionSpeed * ins.energyPerMovement) * halfTicks * 2
            k.burner = b
        }
        configure(&k, e)
        let c: Int32
        if let f = free.popLast() { c = f; comps[Int(f)] = k } else { c = Int32(comps.count); comps.append(k) }
        world.entities.setComponent(e, c)
    }

    public func entityRemoved(_ e: Int32) {
        guard let c = comp(e) else { return }
        comps[c] = Comp()
        free.append(Int32(c))
        world.entities.setComponent(e, -1)
    }

    public func entityRotated(_ e: Int32) {
        guard let c = comp(e) else { return }
        configure(&comps[c], e)
        comps[c].wakeTick = 0
    }

    public func neighborhoodChanged(_ rect: TileRect) {
        // Wake inserters whose pickup/drop tiles are inside the changed area (cheap: only on build events).
        for i in comps.indices where comps[i].entity >= 0 {
            let p = comps[i].pickup.tile, d = comps[i].drop.tile
            if rect.contains(p) || rect.contains(d) { comps[i].wakeTick = 0 }
        }
    }

    public func takeContents(_ e: Int32) -> [ItemStack] {
        guard let c = comp(e) else { return [] }
        var out: [ItemStack] = []
        if comps[c].handCount > 0 { out.append(ItemStack(item: comps[c].handItem, count: comps[c].handCount)) }
        comps[c].handCount = 0; comps[c].handItem = -1
        if let b = comps[c].burner {
            out += b.fuel.contents().map { ItemStack(item: $0.item, count: $0.count) }
            comps[c].burner!.fuel = Inventory(size: b.fuel.size)
        }
        return out
    }

    // MARK: Tick

    public func update() {
        let tick = world.tick
        let power = world.power!
        for i in comps.indices {
            if comps[i].entity < 0 { continue }
            step(i, tick: tick, power: power)
        }
    }

    @inline(__always) private func isBelt(_ e: Int32) -> Bool {
        switch world.entities[e].kind {
        case .transportBelt, .undergroundBelt, .splitter: return true
        default: return false
        }
    }

    private func step(_ i: Int, tick: UInt64, power: PowerSystem) {
        let e = comps[i].entity
        let moving = comps[i].phase == .toDrop || comps[i].phase == .toPickup

        // Energy
        var speed: Double = 1
        if comps[i].burner != nil {
            if moving {
                // refuel from hand if empty
                refuelFromHand(i)
                speed = comps[i].burner!.draw(comps[i].movingJoulesPerTick, db: world.db)
                if speed <= 0 { comps[i].status = .noFuel; return }
            }
        } else {
            speed = power.satisfaction(of: e)
            power.request(e, joules: comps[i].drainJoulesPerTick + (moving ? comps[i].movingJoulesPerTick : 0))
            if moving && speed <= 0 { comps[i].status = .noPower; return }
        }

        switch comps[i].phase {
        case .toDrop:
            comps[i].progress += speed
            comps[i].status = .working
            if comps[i].progress >= comps[i].halfTicks {
                comps[i].progress = 0; comps[i].phase = .drop; comps[i].wakeTick = 0
                doDrop(i, tick: tick)          // arrive and act in the same tick (cycle = 2 half swings)
            }
        case .toPickup:
            comps[i].progress += speed
            comps[i].status = .working
            if comps[i].progress >= comps[i].halfTicks {
                comps[i].progress = 0; comps[i].phase = .pickup; comps[i].wakeTick = 0
                doPickup(i, tick: tick)
            }
        case .pickup:
            if tick < comps[i].wakeTick { return }
            doPickup(i, tick: tick)
        case .drop:
            if tick < comps[i].wakeTick { return }
            doDrop(i, tick: tick)
        }
    }

    private func refuelFromHand(_ i: Int) {
        guard var b = comps[i].burner, b.remaining <= 0, b.fuel.isEmpty, comps[i].handCount > 0 else { return }
        let item = Int(comps[i].handItem)
        guard BurnerEnergy.isFuel(item, db: world.db) else { return }
        b.fuel.insert(item: item, count: 1, stackSize: world.stackSize(item))
        comps[i].handCount -= 1
        if comps[i].handCount == 0 { comps[i].handItem = -1 }
        comps[i].burner = b
    }

    @inline(__always) private func filterAllows(_ k: Comp, _ item: Int) -> Bool {
        if k.filters.isEmpty { return true }
        for f in k.filters where Int(f) == item { return true }
        return false
    }

    private func doPickup(_ i: Int, tick: UInt64) {
        let k = comps[i]
        // Burner inserter with empty fuel picks fuel for itself first (handled on move via refuelFromHand).
        guard let dst = world.entity(at: k.drop.tile) else {
            comps[i].status = .waitingForTarget; comps[i].wakeTick = tick + Self.idleRecheck; return
        }
        guard let src = world.entity(at: k.pickup.tile), src != k.entity else {
            comps[i].status = .waitingForSource; comps[i].wakeTick = tick + Self.idleRecheck; return
        }
        let dstIsBelt = isBelt(dst)
        let hand = handSize(k)
        let needsSelfFuel = k.burner.map { $0.remaining <= 0 && $0.fuel.isEmpty } ?? false

        // Predicate: item the target accepts now (and the filter allows).
        let accept: (Int) -> Bool = { [world] item in
            if needsSelfFuel && BurnerEnergy.isFuel(item, db: world.db) { return true }
            guard self.filterAllows(k, item) else { return false }
            if dstIsBelt { return true }
            return world.acceptCount(dst, item: item, count: 1, source: .inserter) > 0
        }

        if isBelt(src) {
            // pick one item per tick while available, same type, until the hand is full
            let pref = 0
            if k.handCount > 0 {
                let want = Int(k.handItem)
                let got = world.belts.pickItem(src, preferredLane: pref, filter: { $0 == want })
                if got >= 0 { comps[i].handCount += 1 }
                if got < 0 || Int(comps[i].handCount) >= hand || !targetWantsMore(dst, dstIsBelt, want, Int(comps[i].handCount)) {
                    startSwing(i, to: .toDrop)
                }
                return
            }
            let got = world.belts.pickItem(src, preferredLane: pref, filter: accept)
            if got >= 0 {
                comps[i].handItem = Int32(got); comps[i].handCount = 1
                if hand <= 1 || !targetWantsMore(dst, dstIsBelt, got, 1) { startSwing(i, to: .toDrop) }
                comps[i].status = .working
            } else {
                comps[i].status = .waitingForSource
                comps[i].wakeTick = tick + 1
            }
            return
        }

        // Entity source
        guard let stack = world.peekExtract(src, source: .inserter, filter: accept) else {
            comps[i].status = .waitingForSource; comps[i].wakeTick = tick + Self.idleRecheck; return
        }
        let item = Int(stack.item)
        var n = min(hand, Int(stack.count))
        if !dstIsBelt && !(needsSelfFuel && BurnerEnergy.isFuel(item, db: world.db)) {
            n = min(n, max(1, world.acceptCount(dst, item: item, count: hand, source: .inserter)))
        }
        let took = world.extract(src, item: item, count: n, source: .inserter)
        if took <= 0 { comps[i].status = .waitingForSource; comps[i].wakeTick = tick + Self.idleRecheck; return }
        comps[i].handItem = Int32(item); comps[i].handCount = Int32(took)
        comps[i].status = .working
        startSwing(i, to: .toDrop)
    }

    @inline(__always) private func targetWantsMore(_ dst: Int32, _ dstIsBelt: Bool, _ item: Int, _ have: Int) -> Bool {
        if dstIsBelt { return true }
        return world.acceptCount(dst, item: item, count: have + 1, source: .inserter) > have
    }

    private func startSwing(_ i: Int, to phase: Phase) {
        comps[i].phase = phase
        comps[i].progress = 0
    }

    private func doDrop(_ i: Int, tick: UInt64) {
        refuelFromHand(i)
        let k = comps[i]
        if k.handCount <= 0 { comps[i].handItem = -1; startSwing(i, to: .toPickup); return }
        guard let dst = world.entity(at: k.drop.tile) else {
            comps[i].status = .waitingForTarget; comps[i].wakeTick = tick + Self.idleRecheck; return
        }
        let item = Int(k.handItem)
        if isBelt(dst) {
            let dir = world.entities[k.entity].direction
            let lane = world.belts.dropLane(dst, inserterDirection: dir)
            if world.belts.insertItem(dst, lane: lane, position: 128, item: item) {
                comps[i].handCount -= 1
            } else {
                comps[i].status = .waitingForTarget
                comps[i].wakeTick = tick + 1
                return
            }
        } else {
            let n = world.insert(dst, item: item, count: Int(k.handCount), source: .inserter)
            comps[i].handCount -= Int32(n)
            if comps[i].handCount > 0 {
                comps[i].status = .waitingForTarget
                comps[i].wakeTick = tick + (n > 0 ? 1 : Self.idleRecheck)
                return
            }
        }
        if comps[i].handCount <= 0 {
            comps[i].handCount = 0; comps[i].handItem = -1
            comps[i].status = .working
            startSwing(i, to: .toPickup)
        }
    }

    // MARK: Persistence

    public func serialize(to w: inout BinaryWriter) {
        w.write(UInt8(1))
        w.writeVarInt(comps.count)
        for k in comps {
            w.write(k.entity)
            guard k.entity >= 0 else { continue }
            w.write(k.proto)
            w.write(k.phase.rawValue)
            w.write(k.progress)
            w.write(k.handItem); w.write(k.handCount)
            w.writeArray(k.filters) { $0.write($1) }
            w.write(k.burner != nil)
            k.burner?.serialize(to: &w)
            w.write(k.wakeTick)
            w.write(k.status.rawValue)
        }
    }

    public func deserialize(from r: inout BinaryReader) throws {
        _ = try r.read(UInt8.self)
        let n = try r.readVarInt()
        comps = []; free = []
        comps.reserveCapacity(n)
        for i in 0..<n {
            var k = Comp()
            k.entity = try r.read(Int32.self)
            if k.entity < 0 { comps.append(k); free.append(Int32(i)); continue }
            k.proto = try r.read(Int32.self)
            k.phase = Phase(rawValue: try r.read(UInt8.self)) ?? .pickup
            k.progress = try r.readDouble()
            k.handItem = try r.read(Int32.self); k.handCount = try r.read(Int32.self)
            k.filters = try r.readArray { try $0.read(Int32.self) }
            if try r.readBool() { k.burner = try BurnerEnergy(from: &r) }
            k.wakeTick = try r.read(UInt64.self)
            k.status = EntityStatus(rawValue: try r.read(UInt8.self)) ?? .idle
            comps.append(k)
        }
    }

    public func didLoad() {
        for i in comps.indices where comps[i].entity >= 0 { configure(&comps[i], comps[i].entity) }
    }

    // MARK: ItemEndpoint (burner inserter fuel)

    public func acceptCount(_ e: Int32, item: Int, count: Int, source: ItemTransferSource) -> Int {
        guard let c = comp(e), let b = comps[c].burner, BurnerEnergy.isFuel(item, db: world.db) else { return 0 }
        let ss = world.stackSize(item)
        var room = b.fuel.canInsert(item: item, count: count, stackSize: ss)
        if source != .player { room = min(room, max(0, Self.fuelInsertLimit - b.fuel.count(of: item))) }
        return room
    }
    public func insert(_ e: Int32, item: Int, count: Int, source: ItemTransferSource) -> Int {
        let n = acceptCount(e, item: item, count: count, source: source)
        guard n > 0, let c = comp(e) else { return 0 }
        return comps[c].burner!.fuel.insert(item: item, count: n, stackSize: world.stackSize(item))
    }
    public func peekExtract(_ e: Int32, source: ItemTransferSource, filter: (Int) -> Bool) -> ItemStack? {
        // Fuel is never taken out by automation; the player may take it back.
        guard source == .player, let c = comp(e), let b = comps[c].burner else { return nil }
        for st in b.fuel.slots where !st.isEmpty && filter(Int(st.item)) { return st }
        return nil
    }
    public func extract(_ e: Int32, item: Int, count: Int, source: ItemTransferSource) -> Int {
        guard source == .player, let c = comp(e), comps[c].burner != nil else { return 0 }
        return comps[c].burner!.fuel.remove(item: item, count: count)
    }
}
