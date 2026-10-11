// Gearforge — FactoryCore
// Beacons and module effect aggregation (05_mechanics §10).
// Owner: Production engineer.
//
// - A beacon (3×3, 2 slots, speed/efficiency modules only) transmits Σ(module effects) × distribution
//   effectivity (0.5) to every machine whose footprint overlaps its supply area (beacon rect expanded by
//   supplyAreaDistance = 3 → 9×9). Effects of several beacons add up (1.1: no diminishing returns).
// - [GF] the transmitted effect is scaled by the beacon's electric satisfaction σ.
// - Cached per affected entity in a dense array indexed by entity id. Two dirty levels:
//     topology (beacon → targets lists; rebuilt after build/remove/rotate in range),
//     values (re-accumulated from the cached target lists after module or σ changes; no allocation).
// - `revision` increments whenever any cached value may have changed; consumers (crafting, mining, labs) compare
//   it to their per-machine stamp and refresh their effect caches lazily.

public final class BeaconSystem: EntitySystem {
    public unowned let world: World
    public init(world: World) { self.world = world }

    // Component storage (struct of arrays)
    private var entity: [Int32] = []
    private var modulesInv: [Inventory] = []
    /// Σ module effects × distribution effectivity (unscaled by σ).
    private var contribution: [ModuleEffects] = []
    /// σ used in the last value accumulation.
    private var appliedSigma: [Double] = []
    private var targets: [[Int32]] = []
    /// Constant electric request per tick (J).
    private var usage: [Double] = []

    /// Per entity id: accumulated beacon effects.
    private var effectsByEntity: [ModuleEffects] = []
    private var touched: [Int32] = []
    private var topologyDirty = false
    private var valuesDirty = false
    private var rev: UInt64 = 1

    private var power: PowerSystem!

    public func setUp() { power = world.power }

    /// Changes whenever any beacon effect may have changed (always fresh — rebuilds lazily).
    public var revision: UInt64 { refreshIfNeeded(); return rev }

    @inline(__always) private func comp(_ e: Int32) -> Int {
        let rec = world.entities[e]
        guard rec.isAlive, rec.kind == .beacon else { return -1 }
        let c = Int(rec.component)
        return c >= 0 && c < entity.count && entity[c] == e ? c : -1
    }

    // MARK: Public API

    /// Sum of beacon effects (already × distribution effectivity and × beacon σ) applying to entity `e`.
    /// Consumers must still filter by their own allowed effects.
    public func beaconEffects(on e: Int32) -> ModuleEffects {
        refreshIfNeeded()
        let i = Int(e)
        return i >= 0 && i < effectsByEntity.count ? effectsByEntity[i] : ModuleEffects()
    }

    public func modules(of e: Int32) -> Inventory? {
        let c = comp(e)
        return c >= 0 ? modulesInv[c] : nil
    }

    /// Whether `item` can go into beacon `e` right now (module with allowed effects and a free slot).
    public func canInsertModule(_ e: Int32, item: Int) -> Bool {
        let c = comp(e)
        guard c >= 0 else { return false }
        let p = world.db.entities[Int(world.entities[e].proto)]
        guard ModuleRules.moduleAllowed(item, mask: EffectMask(p.allowedEffects), db: world.db) else { return false }
        return modulesInv[c].slots.contains { $0.isEmpty }
    }

    public func insertModule(_ e: Int32, item: Int) -> Bool {
        guard canInsertModule(e, item: item) else { return false }
        let c = comp(e)
        guard ModuleRules.insert(item, into: &modulesInv[c]) else { return false }
        modulesChanged(c)
        return true
    }

    public func removeModule(_ e: Int32, slot: Int) -> ItemStack? {
        let c = comp(e)
        guard c >= 0, let s = ModuleRules.remove(slot: slot, from: &modulesInv[c]) else { return nil }
        modulesChanged(c)
        return s
    }

    public func status(of e: Int32) -> EntityStatus {
        let c = comp(e)
        guard c >= 0 else { return .idle }
        if modulesInv[c].isEmpty { return .noModules }
        let s = power.satisfaction(of: e)
        return s <= 0 ? .noPower : (s < 1 ? .lowPower : .working)
    }

    public func isWorking(_ e: Int32) -> Bool {
        let c = comp(e)
        return c >= 0 && !modulesInv[c].isEmpty && power.satisfaction(of: e) > 0
    }

    /// Entities currently affected by beacon `e` (UI highlight).
    public func affectedEntities(of e: Int32) -> [Int32] {
        refreshIfNeeded()
        let c = comp(e)
        return c >= 0 ? targets[c] : []
    }

    // MARK: EntitySystem

    public func entityAdded(_ e: Int32) {
        let p = world.db.entities[Int(world.entities[e].proto)]
        let c = entity.count
        entity.append(e)
        modulesInv.append(Inventory(size: p.moduleSlots ?? 0))
        contribution.append(ModuleEffects())
        appliedSigma.append(1)
        targets.append([])
        usage.append(Self.usagePerTick(p))
        world.entities.setComponent(e, Int32(c))
        topologyDirty = true
    }

    public func entityRemoved(_ e: Int32) {
        let c = comp(e)
        guard c >= 0 else { return }
        let last = entity.count - 1
        ProdArray.swapRemove(&entity, c)
        ProdArray.swapRemove(&modulesInv, c)
        ProdArray.swapRemove(&contribution, c)
        ProdArray.swapRemove(&appliedSigma, c)
        ProdArray.swapRemove(&targets, c)
        ProdArray.swapRemove(&usage, c)
        if c != last { world.entities.setComponent(entity[c], Int32(c)) }
        topologyDirty = true
    }

    public func entityRotated(_ e: Int32) { topologyDirty = true }

    public func neighborhoodChanged(_ rect: TileRect) {
        if topologyDirty || entity.isEmpty { return }
        for c in 0..<entity.count where supplyRect(c).intersects(rect) {
            topologyDirty = true
            return
        }
    }

    public func takeContents(_ e: Int32) -> [ItemStack] {
        let c = comp(e)
        guard c >= 0 else { return [] }
        let out = modulesInv[c].slots.filter { !$0.isEmpty }
        if !out.isEmpty {
            modulesInv[c] = Inventory(size: modulesInv[c].size)
            modulesChanged(c)
        }
        return out
    }

    public func update() {
        let n = entity.count
        guard n > 0 else { return }
        let power = self.power!
        for c in 0..<n {
            let e = entity[c]
            let s = power.satisfaction(of: e)
            if s != appliedSigma[c] && !(contribution[c] == ModuleEffects()) { valuesDirty = true }
            appliedSigma[c] = s
            // Beacons draw their full energy usage permanently (1.1).
            power.request(e, joules: usage[c])
        }
    }

    private static func usagePerTick(_ p: EntityProto) -> Double {
        return ((p.energyUsage ?? 0) + (p.energySource?.drain ?? 0)) / Double(ticksPerSecond)
    }

    // MARK: Cache maintenance

    private func supplyRect(_ c: Int) -> TileRect {
        let rec = world.entities[entity[c]]
        let d = Int32(world.db.entities[Int(rec.proto)].beacon?.supplyAreaDistance ?? 3)
        return rec.rect.expanded(by: d)
    }

    private func modulesChanged(_ c: Int) {
        let p = world.db.entities[Int(world.entities[entity[c]].proto)]
        let eff = p.beacon?.distributionEffectivity ?? 0.5
        contribution[c] = ModuleRules.sum(modulesInv[c], db: world.db) * eff
        valuesDirty = true
    }

    /// Whether entity kind/prototype can receive beacon effects.
    private func receivesEffects(_ e: Int32) -> Bool {
        let rec = world.entities[e]
        switch rec.kind {
        case .assemblingMachine, .furnace, .rocketSilo, .miningDrill, .lab:
            return !(world.db.entities[Int(rec.proto)].allowedEffects ?? []).isEmpty
        default:
            return false
        }
    }

    private func refreshIfNeeded() {
        if topologyDirty {
            topologyDirty = false
            for c in 0..<entity.count {
                targets[c] = world.entities(in: supplyRect(c)).filter { receivesEffects($0) }
            }
            valuesDirty = true
        }
        if valuesDirty {
            valuesDirty = false
            for e in touched where Int(e) < effectsByEntity.count { effectsByEntity[Int(e)] = ModuleEffects() }
            touched.removeAll(keepingCapacity: true)
            let needed = world.entities.records.count
            if effectsByEntity.count < needed {
                effectsByEntity.append(contentsOf: repeatElement(ModuleEffects(), count: needed - effectsByEntity.count))
            }
            for c in 0..<entity.count {
                let contrib = contribution[c]
                if contrib == ModuleEffects() { continue }
                let scaled = contrib * appliedSigma[c]
                for t in targets[c] {
                    let i = Int(t)
                    if effectsByEntity[i] == ModuleEffects() { touched.append(t) }
                    effectsByEntity[i] = effectsByEntity[i] + scaled
                }
            }
            rev &+= 1
        }
    }

    // MARK: Persistence

    private static let version: UInt8 = 1

    public func serialize(to w: inout BinaryWriter) {
        w.write(Self.version)
        ProdIO.write(entity, &w)
        ProdIO.write(modulesInv, &w)
        ProdIO.write(appliedSigma, &w)
    }

    public func deserialize(from r: inout BinaryReader) throws {
        try ProdIO.checkVersion(&r, Self.version)
        entity = try ProdIO.readInt32s(&r)
        let n = entity.count
        modulesInv = try ProdIO.readInventories(&r, expect: n)
        appliedSigma = try ProdIO.readDoubles(&r, expect: n)
        contribution = Array(repeating: ModuleEffects(), count: n)
        usage = entity.map { Self.usagePerTick(world.db.entities[Int(world.entities[$0].proto)]) }
        targets = Array(repeating: [], count: n)
        effectsByEntity = []
        touched = []
    }

    public func didLoad() {
        for c in 0..<entity.count { modulesChanged(c) }
        topologyDirty = true
    }
}
