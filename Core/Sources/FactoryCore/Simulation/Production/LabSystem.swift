// Gearforge — FactoryCore
// Labs consume research cards to progress the current technology (05_mechanics §9).
// Owner: Production engineer.
//
// - A lab researches the force's current tech when it holds ≥ amount of every card the tech's unit needs.
// - [GF] one full set of cards is consumed when a unit STARTS (no card durability). Progress per tick =
//   lab_speed × (1 + lab speed research bonus) × max(0.2, 1 + Σspeed) × σ / (60 × unit_time); research bonus and
//   module speed are multiplicative (wiki). Finished units call `world.research.addProgress(units:)`.
// - Productivity (modules) fills a bonus bar; at ≥ 1 an extra unit of progress is granted.
// - If the current tech changes, an in-progress unit's cards are put back into the lab. [GF] when a tech
//   completes, units still in progress for it are refunded the same way (no waste).
// - Labs are item endpoints: automated sources insert only cards the current tech needs, up to
//   amount × clamp(1 + ceil(1.166 / unit_time_eff), 2, 100); the player may insert up to a stack of any lab card.
//   Inserters can extract cards (lab chaining).
// - Labs that cannot start a unit sleep until a card is inserted or the research changes.

public final class LabSystem: EntitySystem, ItemEndpoint {
    public unowned let world: World
    public init(world: World) { self.world = world }

    // MARK: Prototype data

    private struct LabKind {
        var proto: Int
        var inputs: [Int]              // card items in slot order
        var slotOfItem: [Int32]        // item -> slot (-1)
        var speed: Double
        var mask: EffectMask
        var moduleSlots: Int
        var electric: Bool
        var usagePerTick: Double
        var drainPerTick: Double
    }
    private var kinds: [LabKind] = []
    private var kindOfProto: [Int32] = []
    /// Card slots per lab (max inputs over all lab prototypes).
    private var stride = 0

    // MARK: Components (struct of arrays)

    private var entity: [Int32] = []
    private var kindIndex: [Int32] = []
    private var cards: [Int32] = []              // stride
    private var unitTech: [Int32] = []           // tech of the unit in progress, -1 none
    private var progress: [Double] = []
    private var prodBar: [Double] = []
    private var statusRaw: [UInt8] = []
    private var sleeping: [Bool] = []
    private var working: [Bool] = []
    private var modulesInv: [Inventory] = []
    private var speedMult: [Double] = []
    private var prodBonus: [Double] = []
    private var consMult: [Double] = []
    private var effectsRev: [UInt64] = []

    // Current-tech cache: per lab kind, slot per unit ingredient (-1 = this lab cannot take that card).
    private var cachedTech = -2
    private var curSlots: [[Int]] = []
    private var curAmounts: [Int32] = []
    private var curInvTime = 0.0
    private var curTime = 0.0

    private var power: PowerSystem!
    private var beacons: BeaconSystem!
    private var research: ResearchManager!
    private var stats: ProductionStats!

    public func setUp() {
        power = world.power; beacons = world.beacons; research = world.research; stats = world.stats
        let db = world.db
        kindOfProto = Array(repeating: -1, count: db.entities.count)
        for (pi, p) in db.entities.enumerated() where p.kind == .lab {
            let inputs = (p.lab?.inputs ?? []).map { db.item($0) }.filter { $0 >= 0 }
            var slotOf = Array(repeating: Int32(-1), count: db.items.count)
            for (s, it) in inputs.enumerated() { slotOf[it] = Int32(s) }
            let electric = p.energySource?.type == "electric"
            kindOfProto[pi] = Int32(kinds.count)
            kinds.append(LabKind(proto: pi, inputs: inputs, slotOfItem: slotOf, speed: p.lab?.speed ?? 1,
                                 mask: EffectMask(p.allowedEffects), moduleSlots: p.moduleSlots ?? 0,
                                 electric: electric,
                                 usagePerTick: (p.energyUsage ?? 0) / Double(ticksPerSecond),
                                 drainPerTick: (p.energySource?.drain ?? 0) / Double(ticksPerSecond)))
            stride = max(stride, inputs.count)
        }
    }

    @inline(__always) private func comp(_ e: Int32) -> Int {
        guard e >= 0, Int(e) < world.entities.records.count else { return -1 }
        let rec = world.entities[e]
        guard rec.isAlive, rec.kind == .lab else { return -1 }
        let c = Int(rec.component)
        return c >= 0 && c < entity.count && entity[c] == e ? c : -1
    }

    @inline(__always) private func activeTech() -> Int {
        research.researchEnabled ? research.current : -1
    }

    private func ensureCache(_ tech: Int) {
        guard tech != cachedTech else { return }
        cachedTech = tech
        guard tech >= 0 else { curSlots = []; curAmounts = []; curInvTime = 0; curTime = 0; return }
        let items = research.unitItems[tech]
        curAmounts = research.unitAmounts[tech].map { Int32($0) }
        curSlots = kinds.map { k in items.map { Int(k.slotOfItem[$0]) } }
        curTime = max(1e-9, research.unitTime(of: tech))
        curInvTime = 1 / (Double(ticksPerSecond) * curTime)
    }

    // MARK: Public API (UI)

    public func status(of e: Int32) -> EntityStatus {
        let c = comp(e)
        return c >= 0 ? EntityStatus(rawValue: statusRaw[c]) ?? .idle : .idle
    }
    public func isWorking(_ e: Int32) -> Bool { let c = comp(e); return c >= 0 && working[c] }
    /// Progress 0...1 of the unit in progress.
    public func progress(of e: Int32) -> Double { let c = comp(e); return c >= 0 ? progress[c] : 0 }
    public func productivityBar(of e: Int32) -> Double { let c = comp(e); return c >= 0 ? prodBar[c] : 0 }
    /// Card slots (one per lab input, in prototype order) as an inventory snapshot.
    public func cards(of e: Int32) -> Inventory? {
        let c = comp(e)
        guard c >= 0 else { return nil }
        let k = kinds[Int(kindIndex[c])]
        var inv = Inventory(size: k.inputs.count)
        for (s, it) in k.inputs.enumerated() where cards[c * stride + s] > 0 {
            inv.slots[s] = ItemStack(item: Int32(it), count: cards[c * stride + s])
        }
        return inv
    }
    public func modules(of e: Int32) -> Inventory? { let c = comp(e); return c >= 0 ? modulesInv[c] : nil }
    /// Total module + beacon effects currently applied (UI).
    public func effects(of e: Int32) -> ModuleEffects {
        let c = comp(e)
        guard c >= 0 else { return ModuleEffects() }
        return currentEffects(c)
    }
    /// Research speed multiplier of the lab right now (lab speed × research bonus × modules, without σ).
    public func researchSpeed(of e: Int32) -> Double {
        let c = comp(e)
        guard c >= 0 else { return 0 }
        refreshEffectsIfNeeded(c, beacons.revision)
        return kinds[Int(kindIndex[c])].speed * (1 + world.bonuses.labSpeed) * speedMult[c]
    }

    public func canInsertModule(_ e: Int32, item: Int) -> Bool {
        let c = comp(e)
        guard c >= 0 else { return false }
        let k = kinds[Int(kindIndex[c])]
        return ModuleRules.moduleAllowed(item, mask: k.mask, db: world.db) && modulesInv[c].slots.contains { $0.isEmpty }
    }
    public func insertModule(_ e: Int32, item: Int) -> Bool {
        guard canInsertModule(e, item: item) else { return false }
        let c = comp(e)
        guard ModuleRules.insert(item, into: &modulesInv[c]) else { return false }
        effectsRev[c] = .max
        wake(c)
        return true
    }
    public func removeModule(_ e: Int32, slot: Int) -> ItemStack? {
        let c = comp(e)
        guard c >= 0, let s = ModuleRules.remove(slot: slot, from: &modulesInv[c]) else { return nil }
        effectsRev[c] = .max
        wake(c)
        return s
    }

    // MARK: Hooks from ResearchManager

    /// The current research (or research enabled state) changed: wake all labs.
    public func researchChanged() {
        cachedTech = -2
        for c in 0..<entity.count { sleeping[c] = false }
    }

    /// [GF] Refund the cards of units still in progress for the completed tech.
    public func techCompleted(_ t: Int) {
        for c in 0..<entity.count where unitTech[c] == Int32(t) { refundUnit(c) }
        researchChanged()
    }

    // MARK: EntitySystem

    public func entityAdded(_ e: Int32) {
        let p = Int(world.entities[e].proto)
        let ki = kindOfProto[p]
        guard ki >= 0 else { return }
        let k = kinds[Int(ki)]
        let c = entity.count
        entity.append(e)
        kindIndex.append(ki)
        cards.append(contentsOf: repeatElement(0, count: stride))
        unitTech.append(-1)
        progress.append(0)
        prodBar.append(0)
        statusRaw.append(EntityStatus.noInput.rawValue)
        sleeping.append(false)
        working.append(false)
        modulesInv.append(Inventory(size: k.moduleSlots))
        speedMult.append(1); prodBonus.append(0); consMult.append(1)
        effectsRev.append(.max)
        world.entities.setComponent(e, Int32(c))
    }

    public func entityRemoved(_ e: Int32) {
        let c = comp(e)
        guard c >= 0 else { return }
        let last = entity.count - 1
        ProdArray.swapRemove(&entity, c)
        ProdArray.swapRemove(&kindIndex, c)
        ProdArray.swapRemoveBlock(&cards, c, stride: stride)
        ProdArray.swapRemove(&unitTech, c)
        ProdArray.swapRemove(&progress, c)
        ProdArray.swapRemove(&prodBar, c)
        ProdArray.swapRemove(&statusRaw, c)
        ProdArray.swapRemove(&sleeping, c)
        ProdArray.swapRemove(&working, c)
        ProdArray.swapRemove(&modulesInv, c)
        ProdArray.swapRemove(&speedMult, c)
        ProdArray.swapRemove(&prodBonus, c)
        ProdArray.swapRemove(&consMult, c)
        ProdArray.swapRemove(&effectsRev, c)
        if c != last { world.entities.setComponent(entity[c], Int32(c)) }
    }

    public func takeContents(_ e: Int32) -> [ItemStack] {
        let c = comp(e)
        guard c >= 0 else { return [] }
        if unitTech[c] >= 0 { refundUnit(c) }
        var out: [ItemStack] = []
        let k = kinds[Int(kindIndex[c])]
        for (s, it) in k.inputs.enumerated() where cards[c * stride + s] > 0 {
            out += ProdArray.stacks(item: it, count: Int(cards[c * stride + s]), db: world.db)
            cards[c * stride + s] = 0
        }
        out += modulesInv[c].slots.filter { !$0.isEmpty }
        modulesInv[c] = Inventory(size: modulesInv[c].size)
        return out
    }

    public func update() {
        let n = entity.count
        guard n > 0 else { return }
        let power = self.power!
        let rev = beacons.revision
        for c in 0..<n {
            let e = entity[c]
            let k = Int(kindIndex[c])
            let electric = kinds[k].electric
            if sleeping[c] {
                working[c] = false
                if electric && kinds[k].drainPerTick > 0 { power.request(e, joules: kinds[k].drainPerTick) }
                continue
            }
            if effectsRev[c] != rev { refreshEffectsIfNeeded(c, rev) }
            let sigma = electric ? power.satisfaction(of: e) : 1
            step(c, kind: k, sigma: sigma)
            if electric {
                let busy = unitTech[c] >= 0
                power.request(e, joules: kinds[k].drainPerTick + (busy ? kinds[k].usagePerTick * consMult[c] : 0))
            }
        }
    }

    // MARK: Simulation

    private func step(_ c: Int, kind k: Int, sigma: Double) {
        working[c] = false
        let tech = activeTech()
        if unitTech[c] >= 0 && Int(unitTech[c]) != tech { refundUnit(c) }
        if unitTech[c] < 0 && !tryStartUnit(c, kind: k, tech: tech, sigma: sigma) { return }
        if sigma <= 0 { statusRaw[c] = EntityStatus.noPower.rawValue; return }
        ensureCache(tech)
        let speed = kinds[k].speed * (1 + world.bonuses.labSpeed) * speedMult[c] * sigma
        progress[c] += speed * curInvTime
        working[c] = true
        statusRaw[c] = (sigma < 1 ? EntityStatus.lowPower : EntityStatus.working).rawValue
        guard progress[c] >= 1 else { return }
        let leftover = progress[c] - 1
        progress[c] = 0
        var units = 1.0
        if prodBonus[c] > 0 {
            prodBar[c] += prodBonus[c]
            if prodBar[c] >= 1 { prodBar[c] -= 1; units += 1 }
        }
        unitTech[c] = -1
        research.addProgress(units: units)
        // [GF] carry leftover progress into the next unit if it can start this tick (≤ 1 completion per tick).
        let now = activeTech()
        if now == tech && tryStartUnit(c, kind: k, tech: now, sigma: sigma) {
            progress[c] = min(leftover, 0.999_999)
        }
    }

    private func tryStartUnit(_ c: Int, kind k: Int, tech: Int, sigma: Double) -> Bool {
        if tech < 0 {
            statusRaw[c] = EntityStatus.noResearch.rawValue
            sleeping[c] = true
            return false
        }
        ensureCache(tech)
        let slots = curSlots[k]
        let base = c * stride
        for (j, s) in slots.enumerated() {
            if s < 0 {      // this lab type cannot take one of the cards
                statusRaw[c] = EntityStatus.noResearch.rawValue
                sleeping[c] = true
                return false
            }
            if cards[base + s] < curAmounts[j] {
                statusRaw[c] = EntityStatus.noInput.rawValue
                sleeping[c] = true
                return false
            }
        }
        if sigma <= 0 { statusRaw[c] = EntityStatus.noPower.rawValue; return false }
        let items = research.unitItems[tech]
        for (j, s) in slots.enumerated() {
            cards[base + s] -= curAmounts[j]
            stats.consumed(item: items[j], count: Int(curAmounts[j]))
        }
        unitTech[c] = Int32(tech)
        return true
    }

    /// Puts the cards of the unit in progress back into the lab's slots.
    private func refundUnit(_ c: Int) {
        let t = Int(unitTech[c])
        unitTech[c] = -1
        progress[c] = 0
        guard t >= 0 else { return }
        let k = kinds[Int(kindIndex[c])]
        let items = research.unitItems[t], amounts = research.unitAmounts[t]
        for (j, it) in items.enumerated() {
            let s = Int(k.slotOfItem[it])
            if s >= 0 { cards[c * stride + s] += Int32(amounts[j]) }
        }
        sleeping[c] = false
    }

    @inline(__always) private func wake(_ c: Int) { sleeping[c] = false }

    private func currentEffects(_ c: Int) -> ModuleEffects {
        let k = kinds[Int(kindIndex[c])]
        var eff = ModuleRules.sum(modulesInv[c], db: world.db)
        if !k.mask.isEmpty { eff = eff + ModuleRules.filter(beacons.beaconEffects(on: entity[c]), k.mask) }
        return ModuleRules.filter(eff, k.mask)
    }

    private func refreshEffectsIfNeeded(_ c: Int, _ rev: UInt64) {
        guard effectsRev[c] != rev else { return }
        let eff = currentEffects(c)
        speedMult[c] = eff.speedMultiplier
        prodBonus[c] = eff.productivityBonus
        consMult[c] = eff.consumptionMultiplier
        effectsRev[c] = rev
    }

    // MARK: ItemEndpoint

    private func slot(_ c: Int, _ item: Int) -> Int {
        guard item >= 0 else { return -1 }
        let k = kinds[Int(kindIndex[c])]
        return item < k.slotOfItem.count ? Int(k.slotOfItem[item]) : -1
    }

    public func acceptCount(_ e: Int32, item: Int, count: Int, source: ItemTransferSource) -> Int {
        let c = comp(e)
        guard c >= 0, count > 0 else { return 0 }
        let s = slot(c, item)
        guard s >= 0 else { return 0 }
        let cur = Int(cards[c * stride + s])
        if source == .player { return max(0, min(count, world.stackSize(item) - cur)) }
        let tech = activeTech()
        guard tech >= 0 else { return 0 }
        let items = research.unitItems[tech]
        guard let j = items.firstIndex(of: item) else { return 0 }
        refreshEffectsIfNeeded(c, beacons.revision)
        let k = kinds[Int(kindIndex[c])]
        let speed = k.speed * (1 + world.bonuses.labSpeed) * speedMult[c]
        let unitTimeEff = research.unitTime(of: tech) / max(1e-9, speed)
        let limit = research.unitAmounts[tech][j] * InsertionLimits.labUnits(effectiveUnitTime: unitTimeEff)
        return max(0, min(count, limit - cur))
    }

    public func insert(_ e: Int32, item: Int, count: Int, source: ItemTransferSource) -> Int {
        let n = acceptCount(e, item: item, count: count, source: source)
        guard n > 0 else { return 0 }
        let c = comp(e)
        cards[c * stride + slot(c, item)] += Int32(n)
        wake(c)
        return n
    }

    public func peekExtract(_ e: Int32, source: ItemTransferSource, filter: (Int) -> Bool) -> ItemStack? {
        let c = comp(e)
        guard c >= 0 else { return nil }
        let k = kinds[Int(kindIndex[c])]
        for (s, it) in k.inputs.enumerated() where cards[c * stride + s] > 0 && filter(it) {
            return ItemStack(item: Int32(it), count: cards[c * stride + s])
        }
        return nil
    }

    public func extract(_ e: Int32, item: Int, count: Int, source: ItemTransferSource) -> Int {
        let c = comp(e)
        guard c >= 0, count > 0 else { return 0 }
        let s = slot(c, item)
        guard s >= 0 else { return 0 }
        let n = min(count, Int(cards[c * stride + s]))
        cards[c * stride + s] -= Int32(n)
        return n
    }

    // MARK: Persistence

    private static let version: UInt8 = 1

    public func serialize(to w: inout BinaryWriter) {
        w.write(Self.version)
        w.writeVarInt(stride)
        ProdIO.write(entity, &w)
        ProdIO.write(cards, &w)
        ProdIO.write(unitTech, &w)
        ProdIO.write(progress, &w)
        ProdIO.write(prodBar, &w)
        ProdIO.write(statusRaw, &w)
        ProdIO.write(sleeping, &w)
        ProdIO.write(modulesInv, &w)
    }

    public func deserialize(from r: inout BinaryReader) throws {
        try ProdIO.checkVersion(&r, Self.version)
        let savedStride = try r.readVarInt()
        guard savedStride == stride else { throw BinaryCodingError.invalidValue("lab card slots \(savedStride) != \(stride)") }
        entity = try ProdIO.readInt32s(&r)
        let n = entity.count
        cards = try ProdIO.readInt32s(&r, expect: n * stride)
        unitTech = try ProdIO.readInt32s(&r, expect: n)
        progress = try ProdIO.readDoubles(&r, expect: n)
        prodBar = try ProdIO.readDoubles(&r, expect: n)
        statusRaw = try ProdIO.readBytes(&r, expect: n)
        sleeping = try ProdIO.readBools(&r, expect: n)
        modulesInv = try ProdIO.readInventories(&r, expect: n)
        kindIndex = entity.map { kindOfProto[Int(world.entities[$0].proto)] }
        working = Array(repeating: false, count: n)
        speedMult = Array(repeating: 1, count: n)
        prodBonus = Array(repeating: 0, count: n)
        consMult = Array(repeating: 1, count: n)
        effectsRev = Array(repeating: .max, count: n)
        cachedTech = -2
    }
}
