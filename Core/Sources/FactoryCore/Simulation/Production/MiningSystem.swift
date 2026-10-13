// Gearforge — FactoryCore
// Mining drills (burner 2×2, electric 3×3 / area 5×5) and pumpjacks (05_mechanics §4).
// Owner: Production engineer.
//
// Rate: mining_speed / mining_time results per second (× speed modules × power). One resource tile is mined per cycle,
// tiles are visited round-robin in a fixed order (deterministic). Output goes to the tile at the drill's output vector:
// a belt (inserted at that point), or any item endpoint (chest, furnace, another drill's fuel slot...). A drill whose
// output is blocked holds the result and sleeps until it can drop it.

public final class MiningSystem: EntitySystem, ItemEndpoint {
    public unowned let world: World
    public init(world: World) { self.world = world }

    struct Drill {
        var entity: Int32 = -1
        var proto: Int32 = -1
        var miningSpeed: Double = 0.5
        var electric = false
        var drainPerTick: Double = 0
        var usagePerTick: Double = 0
        var mask: EffectMask = []
        var fluidOutput = false
        var tiles: [TilePos] = []
        var cursor: Int = 0
        var progress: Double = 0
        var prodBar: Double = 0
        var pendingItem: Int32 = -1
        var pendingCount: Int32 = 0
        var output = Vec2.zero
        var burner: BurnerEnergy? = nil
        var modules = Inventory(size: 0)
        var status: EntityStatus = .working
        var wakeTick: UInt64 = 0
        var effectsKey: Int = -1
        var speedMult: Double = 1
        var consMult: Double = 1
        var prodBonus: Double = 0
        var working = false
    }

    var drills: [Drill] = []
    private var free: [Int32] = []
    private var effectsRevision = 0
    static let recheckTicks: UInt64 = 30

    @inline(__always) private func comp(_ e: Int32) -> Int? {
        let c = world.entities[e].component
        return c >= 0 && Int(c) < drills.count && drills[Int(c)].entity == e ? Int(c) : nil
    }

    // MARK: Public API

    public func status(of e: Int32) -> EntityStatus { comp(e).map { drills[$0].status } ?? .idle }
    public func isWorking(_ e: Int32) -> Bool { comp(e).map { drills[$0].working } ?? false }
    public func progress(of e: Int32) -> Double { comp(e).map { drills[$0].progress } ?? 0 }
    public func productivityBar(of e: Int32) -> Double { comp(e).map { drills[$0].prodBar } ?? 0 }
    public func fuel(of e: Int32) -> BurnerEnergy? { comp(e).flatMap { drills[$0].burner } }
    public func modules(of e: Int32) -> Inventory? { comp(e).flatMap { drills[$0].modules.size > 0 ? drills[$0].modules : nil } }
    /// Output point (world tile coords) for build overlays.
    public func outputPoint(of e: Int32) -> Vec2? { comp(e).map { drills[$0].output } }
    /// Resource amount left under the drill.
    public func remainingResources(of e: Int32) -> Int {
        guard let c = comp(e) else { return 0 }
        return drills[c].tiles.reduce(0) { $0 + Int(world.surface.resource(at: $1).1) }
    }
    /// Mining area (world tiles) for a prototype placed at origin/direction — for the build preview.
    public func miningArea(proto: Int, origin: TilePos, direction: Direction) -> TileRect {
        let (w, h) = world.footprint(proto, direction)
        let size = world.db.entities[proto].drill?.areaSize ?? w
        let cx = Double(origin.x) + Double(w) / 2, cy = Double(origin.y) + Double(h) / 2
        let x0 = Int32((cx - Double(size) / 2).rounded(.down)), y0 = Int32((cy - Double(size) / 2).rounded(.down))
        return TileRect(x: x0, y: y0, w: Int32(size), h: Int32(size))
    }
    /// True if any compatible resource lies in the drill's area (placement rule "drill needs resource").
    public func hasResource(proto: Int, origin: TilePos, direction: Direction) -> Bool {
        let cats = world.db.entities[proto].drill?.resourceCategories ?? []
        var found = false
        miningArea(proto: proto, origin: origin, direction: direction).forEach { p in
            if found { return }
            let (r, a) = world.surface.resource(at: p)
            if r >= 0 && a > 0 && cats.contains(world.db.resources[r].category) { found = true }
        }
        return found
    }

    public func insertModule(_ e: Int32, item: Int) -> Bool {
        guard let c = comp(e), drills[c].modules.size > 0,
              ModuleRules.moduleAllowed(item, mask: drills[c].mask, db: world.db),
              ModuleRules.insert(item, into: &drills[c].modules) else { return false }
        effectsRevision &+= 1
        drills[c].wakeTick = 0
        return true
    }
    public func removeModule(_ e: Int32, slot: Int) -> ItemStack? {
        guard let c = comp(e) else { return nil }
        let s = ModuleRules.remove(slot: slot, from: &drills[c].modules)
        effectsRevision &+= 1
        return s
    }

    // MARK: Lifecycle

    private func scanTiles(_ c: Int) {
        let e = drills[c].entity
        let rec = world.entities[e]
        let p = world.db.entities[Int(rec.proto)]
        let cats = p.drill?.resourceCategories ?? []
        var out: [TilePos] = []
        miningArea(proto: Int(rec.proto), origin: rec.origin, direction: rec.direction).forEach { q in
            let (r, a) = world.surface.resource(at: q)
            if r >= 0 && a > 0 && cats.contains(world.db.resources[r].category) { out.append(q) }
        }
        drills[c].tiles = out
        drills[c].cursor = 0
        drills[c].output = rec.center + rec.direction.rotate(p.drill?.outputVector ?? Vec2(0, -1))
    }

    public func entityAdded(_ e: Int32) {
        let rec = world.entities[e]
        let p = world.db.entities[Int(rec.proto)]
        guard let dp = p.drill else { return }
        var d = Drill()
        d.entity = e
        d.proto = rec.proto
        d.miningSpeed = dp.miningSpeed
        d.electric = p.energySource?.type == "electric"
        let usage = p.energyUsage ?? 0
        d.usagePerTick = usage / 60
        d.drainPerTick = d.electric ? (p.energySource?.drain ?? 0) / 60 : 0
        d.mask = EffectMask(p.allowedEffects)
        d.modules = Inventory(size: p.moduleSlots ?? 0)
        d.fluidOutput = dp.resourceCategories.contains("basic-fluid")
        if p.energySource?.type == "burner" {
            d.burner = BurnerEnergy(slots: p.energySource?.fuelSlots ?? 1, effectivity: p.energySource?.effectivity ?? 1)
        }
        let c: Int32
        if let f = free.popLast() { c = f; drills[Int(f)] = d } else { c = Int32(drills.count); drills.append(d) }
        world.entities.setComponent(e, c)
        scanTiles(Int(c))
    }

    public func entityRemoved(_ e: Int32) {
        guard let c = comp(e) else { return }
        drills[c] = Drill()
        free.append(Int32(c))
        world.entities.setComponent(e, -1)
    }

    public func entityRotated(_ e: Int32) {
        guard let c = comp(e) else { return }
        scanTiles(c)
        drills[c].wakeTick = 0
    }

    public func neighborhoodChanged(_ rect: TileRect) {
        effectsRevision &+= 1
        for i in drills.indices where drills[i].entity >= 0 && rect.contains(drills[i].output.tile) { drills[i].wakeTick = 0 }
    }

    public func takeContents(_ e: Int32) -> [ItemStack] {
        guard let c = comp(e) else { return [] }
        var out: [ItemStack] = []
        if drills[c].pendingCount > 0 { out.append(ItemStack(item: drills[c].pendingItem, count: drills[c].pendingCount)) }
        drills[c].pendingCount = 0
        out += drills[c].modules.contents().map { ItemStack(item: $0.item, count: $0.count) }
        drills[c].modules = Inventory(size: drills[c].modules.size)
        if let b = drills[c].burner {
            out += b.fuel.contents().map { ItemStack(item: $0.item, count: $0.count) }
            drills[c].burner!.fuel = Inventory(size: b.fuel.size)
        }
        return out
    }

    // MARK: Effects

    private func refreshEffects(_ c: Int) {
        let key = effectsRevision &* 1_000_003 &+ Int(truncatingIfNeeded: world.beacons?.revision ?? 0)
        guard drills[c].effectsKey != key else { return }
        drills[c].effectsKey = key
        var eff = ModuleRules.sum(drills[c].modules, db: world.db)
        if drills[c].mask.rawValue != 0, let b = world.beacons { eff = eff + b.beaconEffects(on: drills[c].entity) }
        eff = ModuleRules.filter(eff, drills[c].mask)
        drills[c].speedMult = eff.speedMultiplier
        drills[c].consMult = eff.consumptionMultiplier
        drills[c].prodBonus = eff.productivityBonus
    }

    // MARK: Tick

    public func update() {
        let tick = world.tick
        let power = world.power!
        for c in drills.indices where drills[c].entity >= 0 {
            if tick < drills[c].wakeTick {
                drills[c].working = false
                if drills[c].electric { power.request(drills[c].entity, joules: drills[c].drainPerTick) }
                continue
            }
            step(c, tick: tick, power: power)
        }
    }

    private func sleep(_ c: Int, _ s: EntityStatus, _ tick: UInt64, _ power: PowerSystem) {
        drills[c].status = s
        drills[c].working = false
        drills[c].wakeTick = tick + Self.recheckTicks
        if drills[c].electric { power.request(drills[c].entity, joules: drills[c].drainPerTick) }
    }

    private func step(_ c: Int, tick: UInt64, power: PowerSystem) {
        let e = drills[c].entity
        // Deliver held output first.
        if drills[c].pendingCount > 0 {
            if !deliver(c) { sleep(c, .outputFull, tick, power); drills[c].wakeTick = tick + 4; return }
        }
        // Find a tile with resources.
        var tries = 0
        while !drills[c].tiles.isEmpty && tries < drills[c].tiles.count {
            let p = drills[c].tiles[drills[c].cursor % drills[c].tiles.count]
            if world.surface.resource(at: p).1 > 0 { break }
            drills[c].tiles.remove(at: drills[c].cursor % drills[c].tiles.count)
            tries += 1
        }
        guard !drills[c].tiles.isEmpty else { sleep(c, .noResources, tick, power); drills[c].wakeTick = .max; return }
        refreshEffects(c)

        var sigma: Double = 1
        if drills[c].electric {
            sigma = power.satisfaction(of: e)
            power.request(e, joules: drills[c].drainPerTick + drills[c].usagePerTick * drills[c].consMult)
            if sigma <= 0 { drills[c].status = .noPower; drills[c].working = false; return }
        } else if drills[c].burner != nil {
            sigma = drills[c].burner!.draw(drills[c].usagePerTick * drills[c].consMult, db: world.db)
            if sigma <= 0 { sleep(c, .noFuel, tick, power); drills[c].wakeTick = tick + 15; return }
        }
        let idx = drills[c].cursor % drills[c].tiles.count
        let p = drills[c].tiles[idx]
        let (rIdx, amount) = world.surface.resource(at: p)
        let res = world.db.resources[rIdx]
        drills[c].working = true
        drills[c].status = sigma < 1 && drills[c].electric ? .lowPower : .working
        drills[c].progress += drills[c].miningSpeed * drills[c].speedMult * sigma / (res.miningTime * Double(ticksPerSecond))
        guard drills[c].progress >= 1 else { return }
        drills[c].progress -= 1

        var times = 1
        let prod = drills[c].prodBonus + world.bonuses.miningProductivity
        if prod > 0 {
            drills[c].prodBar += prod
            while drills[c].prodBar >= 1 { drills[c].prodBar -= 1; times += 1 }
        }
        if res.resultIsFluid {
            // pumpjack: yield = amount / normal (min 20 %)
            let normal = Double(res.normal ?? 300_000)
            let yieldF = max(Double(res.minimum ?? 60_000) / normal, Double(amount) / normal)
            let fluid = world.db.fluid(res.result)
            let amt = res.resultAmount * yieldF * Double(times)
            let added = world.fluids.add(e, box: 0, fluid: fluid, amount: amt, temperature: world.db.fluids[max(0, fluid)].defaultTemperature)
            if added > 0 { world.stats.producedFluid(fluid, amount: added) }
            if !res.infinite {
                world.surface.setResource(at: p, rIdx, amount: amount > 1 ? amount - 1 : 0)
            }
        } else {
            let item = world.db.item(res.result)
            drills[c].pendingItem = Int32(item)
            drills[c].pendingCount = Int32(Int(res.resultAmount) * times)
            world.stats.produced(item: item, count: Int(drills[c].pendingCount))
            // deplete 1 unit per cycle (productivity results are free)
            let left = amount - 1
            world.surface.setResource(at: p, left > 0 ? rIdx : -1, amount: left)
            if left == 0 {
                world.emit(.tilesChanged(p.chunk))
                drills[c].tiles.remove(at: idx)
            } else {
                drills[c].cursor = (idx + 1) % max(1, drills[c].tiles.count)
            }
            _ = deliver(c)
        }
    }

    /// Tries to drop the pending output. Returns true when nothing is left pending.
    private func deliver(_ c: Int) -> Bool {
        let item = Int(drills[c].pendingItem)
        let t = drills[c].output.tile
        guard let target = world.entity(at: t), target != drills[c].entity else {
            // nothing in front: drop one item on the ground if the tile is empty (then block, like 1.1)
            if world.ground.count(at: t) == 0 && world.ground.add(item: item, count: 1, at: t) == 1 { drills[c].pendingCount -= 1 }
            return drills[c].pendingCount <= 0
        }
        let kind = world.entities[target].kind
        if kind == .transportBelt || kind == .undergroundBelt || kind == .splitter {
            let lane = world.belts.nearestLane(target, point: drills[c].output)
            // position along the tile from the drop point
            let rec = world.entities[target]
            let v = rec.direction.vector
            let along = (drills[c].output.x - rec.center.x) * Double(v.x) + (drills[c].output.y - rec.center.y) * Double(v.y)
            let pos = Int(max(0, min(255, (along + 0.5) * 256)))
            while drills[c].pendingCount > 0 {
                if world.belts.insertItem(target, lane: lane, position: pos, item: item) { drills[c].pendingCount -= 1 } else { break }
            }
        } else {
            let n = world.insert(target, item: item, count: Int(drills[c].pendingCount), source: .drill)
            drills[c].pendingCount -= Int32(n)
        }
        return drills[c].pendingCount <= 0
    }

    // MARK: Persistence

    public func serialize(to w: inout BinaryWriter) {
        w.write(UInt8(1))
        w.writeVarInt(drills.count)
        for d in drills {
            w.write(d.entity)
            guard d.entity >= 0 else { continue }
            w.write(d.cursor); w.write(d.progress); w.write(d.prodBar)
            w.write(d.pendingItem); w.write(d.pendingCount)
            w.write(d.burner != nil); d.burner?.serialize(to: &w)
            d.modules.serialize(to: &w)
            w.write(d.status.rawValue)
        }
    }

    public func deserialize(from r: inout BinaryReader) throws {
        _ = try r.read(UInt8.self)
        let n = try r.readVarInt()
        drills = []; free = []
        for i in 0..<n {
            let e = try r.read(Int32.self)
            if e < 0 { drills.append(Drill()); free.append(Int32(i)); continue }
            var d = Drill()
            d.entity = e
            d.cursor = try r.read(Int.self); d.progress = try r.readDouble(); d.prodBar = try r.readDouble()
            d.pendingItem = try r.read(Int32.self); d.pendingCount = try r.read(Int32.self)
            if try r.readBool() { d.burner = try BurnerEnergy(from: &r) }
            d.modules = try Inventory(from: &r)
            d.status = EntityStatus(rawValue: try r.read(UInt8.self)) ?? .working
            drills.append(d)
        }
    }

    public func didLoad() {
        for c in drills.indices where drills[c].entity >= 0 {
            let e = drills[c].entity
            let rec = world.entities[e]
            let p = world.db.entities[Int(rec.proto)]
            drills[c].proto = rec.proto
            drills[c].miningSpeed = p.drill?.miningSpeed ?? 0.5
            drills[c].electric = p.energySource?.type == "electric"
            drills[c].usagePerTick = (p.energyUsage ?? 0) / 60
            drills[c].drainPerTick = drills[c].electric ? (p.energySource?.drain ?? 0) / 60 : 0
            drills[c].mask = EffectMask(p.allowedEffects)
            drills[c].fluidOutput = p.drill?.resourceCategories.contains("basic-fluid") ?? false
            let cursor = drills[c].cursor
            scanTiles(c)
            drills[c].cursor = cursor
        }
        effectsRevision &+= 1
    }

    // MARK: ItemEndpoint (burner fuel; drills never give items to inserters)

    public func acceptCount(_ e: Int32, item: Int, count: Int, source: ItemTransferSource) -> Int {
        guard let c = comp(e), let b = drills[c].burner, BurnerEnergy.isFuel(item, db: world.db) else { return 0 }
        return ProdBurner.acceptFuel(b, item: item, count: count, source: source, db: world.db)
    }
    public func insert(_ e: Int32, item: Int, count: Int, source: ItemTransferSource) -> Int {
        let n = acceptCount(e, item: item, count: count, source: source)
        guard n > 0, let c = comp(e) else { return 0 }
        drills[c].burner!.fuel.insert(item: item, count: n, stackSize: world.stackSize(item))
        drills[c].wakeTick = 0
        return n
    }
    public func peekExtract(_ e: Int32, source: ItemTransferSource, filter: (Int) -> Bool) -> ItemStack? {
        guard source == .player, let c = comp(e), let b = drills[c].burner else { return nil }
        for s in b.fuel.slots where !s.isEmpty && filter(Int(s.item)) { return s }
        return nil
    }
    public func extract(_ e: Int32, item: Int, count: Int, source: ItemTransferSource) -> Int {
        guard source == .player, let c = comp(e), drills[c].burner != nil else { return 0 }
        return drills[c].burner!.fuel.remove(item: item, count: count)
    }
}
