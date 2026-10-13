// Gearforge — FactoryCore
// Crafting machines: assemblers 1-3, chemical plant, oil refinery, centrifuge, furnaces (auto recipe), rocket silo.
// Owner: Production engineer.
//
// One `Machine` struct per entity (dense array + free list). Ingredient/result buffers are counts aligned to the
// resolved recipe's item ingredients/results. Machines sleep while they cannot start a craft (no input / output full /
// no recipe / no fuel) and are woken by item endpoint traffic, recipe changes, module changes or a periodic recheck.

public final class CraftingSystem: EntitySystem, ItemEndpoint {
    public unowned let world: World
    public init(world: World) { self.world = world }

    struct Kind {
        var speed: Double
        var electric: Bool
        var burner: Bool
        var drainPerTick: Double
        var usagePerTick: Double          // J per tick at 100 %
        var mask: EffectMask
        var moduleSlots: Int
        var isFurnace: Bool
        var isSilo: Bool
        var fixedRecipe: Int
        var siloParts: Int
    }
    private var kindInBoxes: [[Int]] = []
    private var kindOutBoxes: [[Int]] = []

    struct Machine {
        var entity: Int32 = -1
        var kind: Int32 = -1
        var recipe: Int32 = -1
        var crafting = false
        var progress: Double = 0
        var prodBar: Double = 0
        var inCount: [Int32] = []
        var outCount: [Int32] = []
        var burner: BurnerEnergy? = nil
        var modules = Inventory(size: 0)
        var status: EntityStatus = .noRecipe
        var sleeping = false
        var wakeTick: UInt64 = 0
        var effectsRev: Int = -1
        var speedMult: Double = 1
        var consMult: Double = 1
        var prodBonus: Double = 0
        // rocket silo
        var rocketParts: Int32 = 0
        var rocketInv = Inventory(size: 0)      // satellite slot
        var extraOut = Inventory(size: 0)       // launch products (orbital cards)
        var working = false
        var carry: Double = 0
        var craftTicksInv: Double = 0
    }

    var machines: [Machine] = []
    private var free: [Int32] = []
    private var kinds: [Kind] = []
    private var kindOfProto: [Int32] = []
    /// Bumped whenever module/beacon configuration may have changed (effects recomputed lazily).
    private var effectsRevision = 0
    static let recheckTicks: UInt64 = 30

    public func setUp() {
        let db = world.db
        kindOfProto = Array(repeating: -1, count: db.entities.count)
        for (i, p) in db.entities.enumerated() {
            guard let c = p.crafting, p.kind == .assemblingMachine || p.kind == .furnace || p.kind == .rocketSilo else { continue }
            let electric = p.energySource?.type == "electric"
            let usage = p.energyUsage ?? 0
            let drain = electric ? (p.energySource?.drain ?? usage / 30) : 0
            var inB: [Int] = [], outB: [Int] = []
            for (bi, b) in (p.fluidBoxes ?? []).enumerated() {
                if b.productionType == "output" { outB.append(bi) } else if b.productionType != "none" { inB.append(bi) }
            }
            let fixed = c.fixedRecipe.map { db.recipe($0) } ?? -1
            kindOfProto[i] = Int32(kinds.count)
            kinds.append(Kind(speed: c.speed, electric: electric, burner: p.energySource?.type == "burner",
                              drainPerTick: drain / 60, usagePerTick: usage / 60,
                              mask: EffectMask(p.allowedEffects), moduleSlots: p.moduleSlots ?? 0,
                              isFurnace: p.kind == .furnace, isSilo: p.kind == .rocketSilo, fixedRecipe: fixed,
                              siloParts: p.rocketSilo?.rocketPartsRequired ?? 100))
            kindInBoxes.append(inB); kindOutBoxes.append(outB)
        }
    }

    @inline(__always) private func comp(_ e: Int32) -> Int? {
        let c = world.entities[e].component
        return c >= 0 && Int(c) < machines.count && machines[Int(c)].entity == e ? Int(c) : nil
    }
    @inline(__always) private func wake(_ c: Int) { machines[c].sleeping = false; machines[c].wakeTick = 0 }

    // MARK: API used by UI / commands

    /// Current recipe (or -1).
    public func recipe(of e: Int32) -> Int { comp(e).map { Int(machines[$0].recipe) } ?? -1 }

    /// Sets the recipe; returns items that must be given back to the player (ingredients/results/prod modules).
    public func setRecipe(_ e: Int32, _ recipe: Int) -> [ItemStack] {
        guard let c = comp(e) else { return [] }
        let k = kinds[Int(machines[c].kind)]
        if recipe >= 0 && !world.db.canCraft(entity: Int(world.entities[e].proto), recipe: recipe) { return [] }
        if k.fixedRecipe >= 0 && recipe != k.fixedRecipe { return [] }
        if Int(machines[c].recipe) == recipe { return [] }
        var out = flushBuffers(c)
        machines[c].recipe = Int32(recipe)
        allocBuffers(c)
        if recipe >= 0 && !world.db.recipes[recipe].allowProductivity {
            out += ModuleRules.ejectProductivity(from: &machines[c].modules, db: world.db)
            machines[c].effectsRev = -1
        }
        configureFluidFilters(c)
        wake(c)
        world.emit(.entityChanged(e))
        return out
    }

    public func progress(of e: Int32) -> Double { comp(e).map { machines[$0].progress } ?? 0 }
    public func productivityBar(of e: Int32) -> Double { comp(e).map { machines[$0].prodBar } ?? 0 }
    public func status(of e: Int32) -> EntityStatus { comp(e).map { machines[$0].status } ?? .idle }
    public func isWorking(_ e: Int32) -> Bool { comp(e).map { machines[$0].working } ?? false }

    public func inputSlots(of e: Int32) -> [ItemStack] {
        guard let c = comp(e), machines[c].recipe >= 0 else { return [] }
        let r = world.db.resolvedRecipes[Int(machines[c].recipe)]
        return zip(r.itemIngredients, machines[c].inCount).map { ItemStack(item: $0.0.index, count: Int($0.1)) }
    }
    public func outputSlots(of e: Int32) -> [ItemStack] {
        guard let c = comp(e) else { return [] }
        var out: [ItemStack] = []
        if machines[c].recipe >= 0 && !kinds[Int(machines[c].kind)].isSilo {
            let r = world.db.resolvedRecipes[Int(machines[c].recipe)]
            out = zip(r.itemResults, machines[c].outCount).map { ItemStack(item: $0.0.index, count: Int($0.1)) }
        }
        out += machines[c].extraOut.slots.filter { !$0.isEmpty }
        return out
    }
    public func fuel(of e: Int32) -> BurnerEnergy? { comp(e).flatMap { machines[$0].burner } }
    public func modules(of e: Int32) -> Inventory? {
        guard let c = comp(e), kinds[Int(machines[c].kind)].moduleSlots > 0 else { return nil }
        return machines[c].modules
    }
    /// Effective crafting speed including modules/beacons (UI).
    public func craftingSpeed(of e: Int32) -> Double {
        guard let c = comp(e) else { return 0 }
        refreshEffects(c)
        return kinds[Int(machines[c].kind)].speed * machines[c].speedMult
    }
    public func effects(of e: Int32) -> (speed: Double, consumption: Double, productivity: Double) {
        guard let c = comp(e) else { return (1, 1, 0) }
        refreshEffects(c)
        return (machines[c].speedMult, machines[c].consMult, machines[c].prodBonus)
    }

    /// Player inserts a module (validates allowed effects & recipe productivity whitelist).
    public func insertModule(_ e: Int32, item: Int) -> Bool {
        guard let c = comp(e) else { return false }
        let k = kinds[Int(machines[c].kind)]
        guard k.moduleSlots > 0, ModuleRules.moduleAllowed(item, mask: k.mask, db: world.db) else { return false }
        if ModuleRules.isProductivityModule(item, db: world.db), machines[c].recipe >= 0,
           !world.db.recipes[Int(machines[c].recipe)].allowProductivity { return false }
        guard ModuleRules.insert(item, into: &machines[c].modules) else { return false }
        machines[c].effectsRev = -1
        wake(c)
        return true
    }
    public func removeModule(_ e: Int32, slot: Int) -> ItemStack? {
        guard let c = comp(e) else { return nil }
        let s = ModuleRules.remove(slot: slot, from: &machines[c].modules)
        machines[c].effectsRev = -1
        wake(c)
        return s
    }

    /// Rocket silo: parts done, rocket ready, launch.
    public func rocketParts(of e: Int32) -> Int { comp(e).map { Int(machines[$0].rocketParts) } ?? 0 }
    public func isRocketReady(_ e: Int32) -> Bool {
        guard let c = comp(e) else { return false }
        let k = kinds[Int(machines[c].kind)]
        return k.isSilo && Int(machines[c].rocketParts) >= k.siloParts
    }
    /// Rocket payload inventory (satellite).
    public func rocketInventory(of e: Int32) -> Inventory? { comp(e).map { machines[$0].rocketInv } }
    public func launchRocket(_ e: Int32) -> Bool {
        guard let c = comp(e), isRocketReady(e) else { return false }
        machines[c].rocketParts = 0
        var withSatellite = false
        if let s = machines[c].rocketInv.firstStack() {
            withSatellite = true
            machines[c].rocketInv.remove(item: Int(s.item), count: 1)
            for p in world.db.items[Int(s.item)].rocketLaunchProducts ?? [] {
                let it = world.db.item(p.id)
                if it >= 0 {
                    machines[c].extraOut.insert(item: it, count: Int(p.amount), stackSize: max(world.stackSize(it), Int(p.amount)))
                    world.stats.produced(item: it, count: Int(p.amount))
                }
            }
        }
        world.stats.recordRocketLaunch(withSatellite: withSatellite)
        world.emit(.rocketLaunched(withSatellite: withSatellite))
        wake(c)
        return true
    }

    // MARK: Buffers

    private func allocBuffers(_ c: Int) {
        if machines[c].recipe < 0 { machines[c].inCount = []; machines[c].outCount = []; return }
        let r = world.db.resolvedRecipes[Int(machines[c].recipe)]
        machines[c].inCount = Array(repeating: 0, count: r.itemIngredients.count)
        machines[c].outCount = Array(repeating: 0, count: r.itemResults.count)
        machines[c].progress = 0
        machines[c].crafting = false
    }

    /// Returns ingredients (incl. those consumed by an in-progress craft) and results as stacks; clears buffers.
    private func flushBuffers(_ c: Int) -> [ItemStack] {
        guard machines[c].recipe >= 0 else { return [] }
        let r = world.db.resolvedRecipes[Int(machines[c].recipe)]
        var out: [ItemStack] = []
        for (i, ing) in r.itemIngredients.enumerated() {
            var n = Int(machines[c].inCount[i])
            if machines[c].crafting { n += Int(ing.amount) }
            if n > 0 { out.append(ItemStack(item: ing.index, count: n)) }
        }
        for (i, res) in r.itemResults.enumerated() where machines[c].outCount[i] > 0 {
            out.append(ItemStack(item: res.index, count: Int(machines[c].outCount[i])))
        }
        machines[c].crafting = false
        machines[c].progress = 0
        for i in machines[c].inCount.indices { machines[c].inCount[i] = 0 }
        for i in machines[c].outCount.indices { machines[c].outCount[i] = 0 }
        return out
    }

    private func configureFluidFilters(_ c: Int) {
        let inBoxes = kindInBoxes[Int(machines[c].kind)], outBoxes = kindOutBoxes[Int(machines[c].kind)]
        guard !inBoxes.isEmpty || !outBoxes.isEmpty else { return }
        let e = machines[c].entity
        let r: ResolvedRecipe? = machines[c].recipe >= 0 ? world.db.resolvedRecipes[Int(machines[c].recipe)] : nil
        for (j, b) in inBoxes.enumerated() {
            let f = r.flatMap { j < $0.fluidIngredients.count ? $0.fluidIngredients[j].index : nil } ?? -1
            world.fluids.setFilter(e, box: b, fluid: f)
        }
        for (j, b) in outBoxes.enumerated() {
            let f = r.flatMap { j < $0.fluidResults.count ? $0.fluidResults[j].index : nil } ?? -1
            world.fluids.setFilter(e, box: b, fluid: f)
        }
    }

    // MARK: Effects

    private func refreshEffects(_ c: Int) {
        let key = effectsRevision &* 1_000_003 &+ Int(truncatingIfNeeded: world.beacons?.revision ?? 0)
        guard machines[c].effectsRev != key else { return }
        machines[c].effectsRev = key
        let k = kinds[Int(machines[c].kind)]
        var eff = ModuleRules.sum(machines[c].modules, db: world.db)
        if k.mask.rawValue != 0, let b = world.beacons { eff = eff + b.beaconEffects(on: machines[c].entity) }
        eff = ModuleRules.filter(eff, k.mask)
        var prod = eff.productivityBonus
        if machines[c].recipe >= 0 && !world.db.recipes[Int(machines[c].recipe)].allowProductivity { prod = 0 }
        machines[c].speedMult = eff.speedMultiplier
        machines[c].consMult = eff.consumptionMultiplier
        machines[c].prodBonus = prod
    }

    /// Called by BeaconSystem / module changes: effects are recomputed lazily.
    public func invalidateEffects() { effectsRevision &+= 1 }

    // MARK: EntitySystem

    public func entityAdded(_ e: Int32) {
        let rec = world.entities[e]
        let kIdx = kindOfProto[Int(rec.proto)]
        guard kIdx >= 0 else { return }
        let k = kinds[Int(kIdx)]
        let p = world.db.entities[Int(rec.proto)]
        var m = Machine()
        m.entity = e
        m.kind = kIdx
        m.modules = Inventory(size: k.moduleSlots)
        if k.burner { m.burner = BurnerEnergy(slots: p.energySource?.fuelSlots ?? 1, effectivity: p.energySource?.effectivity ?? 1) }
        if k.isSilo { m.rocketInv = Inventory(size: 1); m.extraOut = Inventory(size: 1) }
        let c: Int32
        if let f = free.popLast() { c = f; machines[Int(f)] = m } else { c = Int32(machines.count); machines.append(m) }
        world.entities.setComponent(e, c)
        if k.fixedRecipe >= 0 {
            machines[Int(c)].recipe = Int32(k.fixedRecipe)
            allocBuffers(Int(c))
        }
        invalidateEffects()
    }

    public func entityRemoved(_ e: Int32) {
        guard let c = comp(e) else { return }
        machines[c] = Machine()
        free.append(Int32(c))
        world.entities.setComponent(e, -1)
    }

    public func neighborhoodChanged(_ rect: TileRect) {
        // Beacons placed/removed nearby change effects; output targets may appear.
        invalidateEffects()
    }

    public func takeContents(_ e: Int32) -> [ItemStack] {
        guard let c = comp(e) else { return [] }
        var out = flushBuffers(c)
        out += machines[c].modules.contents().map { ItemStack(item: $0.item, count: $0.count) }
        machines[c].modules = Inventory(size: machines[c].modules.size)
        if let b = machines[c].burner {
            out += b.fuel.contents().map { ItemStack(item: $0.item, count: $0.count) }
            machines[c].burner!.fuel = Inventory(size: b.fuel.size)
        }
        out += machines[c].rocketInv.contents().map { ItemStack(item: $0.item, count: $0.count) }
        out += machines[c].extraOut.contents().map { ItemStack(item: $0.item, count: $0.count) }
        return out
    }

    // MARK: Tick

    public func update() {
        let tick = world.tick
        let power = world.power!
        for c in machines.indices where machines[c].entity >= 0 {
            let k = kinds[Int(machines[c].kind)]
            if machines[c].sleeping && tick < machines[c].wakeTick {
                machines[c].working = false
                if k.electric { power.request(machines[c].entity, joules: k.drainPerTick) }
                continue
            }
            step(c, k, tick: tick, power: power)
        }
    }

    private func sleep(_ c: Int, _ status: EntityStatus, tick: UInt64) {
        machines[c].status = status
        machines[c].sleeping = true
        machines[c].wakeTick = tick + Self.recheckTicks
        machines[c].working = false
    }

    private func step(_ c: Int, _ k: Kind, tick: UInt64, power: PowerSystem) {
        let e = machines[c].entity
        guard machines[c].recipe >= 0 else {
            if k.electric { power.request(e, joules: k.drainPerTick) }
            sleep(c, .noRecipe, tick: tick); return
        }
        refreshEffects(c)

        if !machines[c].crafting {
            let r = world.db.resolvedRecipes[Int(machines[c].recipe)]
            let inBoxes = kindInBoxes[Int(machines[c].kind)]
            if k.electric { power.request(e, joules: k.drainPerTick) }
            if k.isSilo && Int(machines[c].rocketParts) >= k.siloParts { sleep(c, .idle, tick: tick); return }
            if let st = startBlocker(c, k, r) { sleep(c, st, tick: tick); return }
            // consume ingredients
            for (i, ing) in r.itemIngredients.enumerated() {
                machines[c].inCount[i] -= Int32(ing.amount)
                world.stats.consumed(item: ing.index, count: Int(ing.amount))
            }
            for (j, ing) in r.fluidIngredients.enumerated() where j < inBoxes.count {
                world.fluids.remove(e, box: inBoxes[j], amount: ing.amount)
                world.stats.consumedFluid(ing.index, amount: ing.amount)
            }
            machines[c].crafting = true
            machines[c].sleeping = false
            machines[c].progress = machines[c].carry
            machines[c].carry = 0
            machines[c].craftTicksInv = 1 / (r.time * Double(ticksPerSecond))
        }

        // energy
        var sigma: Double
        if k.electric {
            sigma = power.satisfaction(of: e)
            power.request(e, joules: k.drainPerTick + k.usagePerTick * machines[c].consMult)
            if sigma <= 0 { machines[c].status = .noPower; machines[c].working = false; return }
        } else if k.burner {
            sigma = machines[c].burner!.draw(k.usagePerTick * machines[c].consMult, db: world.db)
            if sigma <= 0 { machines[c].status = .noFuel; machines[c].working = false; return }
        } else { sigma = 1 }

        machines[c].working = true
        machines[c].status = sigma < 1 && k.electric ? .lowPower : .working
        machines[c].progress += k.speed * machines[c].speedMult * sigma * machines[c].craftTicksInv
        guard machines[c].progress >= 1 else { return }
        let r = world.db.resolvedRecipes[Int(machines[c].recipe)]
        let outBoxes = kindOutBoxes[Int(machines[c].kind)]

        // finish
        let leftover = machines[c].progress - 1
        machines[c].progress = 0
        machines[c].crafting = false
        var times = 1
        if machines[c].prodBonus > 0 {
            machines[c].prodBar += machines[c].prodBonus
            if machines[c].prodBar >= 1 { machines[c].prodBar -= 1; times += 1 }
        }
        if k.isSilo {
            machines[c].rocketParts += Int32(times)
            world.stats.produced(item: r.itemResults.first?.index ?? -1, count: times)
        } else {
            for (i, res) in r.itemResults.enumerated() {
                var n = Int(res.amount) * times
                if res.probability < 1 {
                    n = 0
                    for _ in 0..<(Int(res.amount) * times) where world.rng.nextUnit() < res.probability { n += 1 }
                }
                machines[c].outCount[i] += Int32(n)
                world.stats.produced(item: res.index, count: n)
            }
            for (j, res) in r.fluidResults.enumerated() where j < outBoxes.count {
                let amt = res.amount * Double(times)
                world.fluids.add(e, box: outBoxes[j], fluid: res.index, amount: amt, temperature: world.db.fluids[res.index].defaultTemperature)
                world.stats.producedFluid(res.index, amount: amt)
            }
        }
        // [GF] carry leftover progress into the next craft (05 §3.1); applied when the next craft starts.
        machines[c].carry = min(max(0, leftover), 0.999_999)
    }

    /// Why a craft cannot start now (nil = can start).
    private func startBlocker(_ c: Int, _ k: Kind, _ r: ResolvedRecipe) -> EntityStatus? {
        let inBoxes = kindInBoxes[Int(machines[c].kind)], outBoxes = kindOutBoxes[Int(machines[c].kind)]
        for (i, ing) in r.itemIngredients.enumerated() where machines[c].inCount[i] < Int32(ing.amount) { return .noInput }
        for (j, ing) in r.fluidIngredients.enumerated() {
            guard j < inBoxes.count else { return .noFluid }
            if world.fluids.amount(machines[c].entity, box: inBoxes[j]) + 1e-9 < ing.amount { return .noFluid }
        }
        if !k.isSilo {
            for (i, res) in r.itemResults.enumerated() {
                let limit = max(world.stackSize(res.index), Int(res.amount) * 2)
                if Int(machines[c].outCount[i]) + Int(res.amount) > limit { return .outputFull }
            }
            for (j, res) in r.fluidResults.enumerated() where j < outBoxes.count {
                let e = machines[c].entity
                if world.fluids.capacity(e, box: outBoxes[j]) > 0 &&
                    world.fluids.amount(e, box: outBoxes[j]) + res.amount > world.fluids.capacity(e, box: outBoxes[j]) + 1e-9 {
                    return .fluidFull
                }
            }
        }
        if let b = machines[c].burner, !b.hasEnergy { return .noFuel }
        return nil
    }

    // MARK: Persistence

    public func serialize(to w: inout BinaryWriter) {
        w.write(UInt8(1))
        w.writeVarInt(machines.count)
        for m in machines {
            w.write(m.entity)
            guard m.entity >= 0 else { continue }
            w.write(m.kind); w.write(m.recipe); w.write(m.crafting); w.write(m.progress); w.write(m.prodBar)
            w.writeArray(m.inCount) { $0.write($1) }
            w.writeArray(m.outCount) { $0.write($1) }
            w.write(m.burner != nil); m.burner?.serialize(to: &w)
            m.modules.serialize(to: &w)
            w.write(m.rocketParts)
            m.rocketInv.serialize(to: &w)
            m.extraOut.serialize(to: &w)
            w.write(m.status.rawValue)
        }
    }

    public func deserialize(from r: inout BinaryReader) throws {
        _ = try r.read(UInt8.self)
        let n = try r.readVarInt()
        machines = []; free = []
        machines.reserveCapacity(n)
        for i in 0..<n {
            var m = Machine()
            m.entity = try r.read(Int32.self)
            if m.entity < 0 { machines.append(m); free.append(Int32(i)); continue }
            m.kind = try r.read(Int32.self); m.recipe = try r.read(Int32.self); m.crafting = try r.readBool()
            m.progress = try r.readDouble(); m.prodBar = try r.readDouble()
            m.inCount = try r.readArray { try $0.read(Int32.self) }
            m.outCount = try r.readArray { try $0.read(Int32.self) }
            if try r.readBool() { m.burner = try BurnerEnergy(from: &r) }
            m.modules = try Inventory(from: &r)
            m.rocketParts = try r.read(Int32.self)
            m.rocketInv = try Inventory(from: &r)
            m.extraOut = try Inventory(from: &r)
            m.status = EntityStatus(rawValue: try r.read(UInt8.self)) ?? .idle
            machines.append(m)
        }
        invalidateEffects()
    }

    public func didLoad() {
        for c in machines.indices where machines[c].entity >= 0 {
            configureFluidFilters(c)
            if machines[c].recipe >= 0 {
                machines[c].craftTicksInv = 1 / (world.db.recipes[Int(machines[c].recipe)].time * Double(ticksPerSecond))
            }
        }
    }

    // MARK: ItemEndpoint

    /// Ingredient index of `item` in the current recipe (or nil).
    @inline(__always) private func ingredientIndex(_ c: Int, _ item: Int) -> Int? {
        guard machines[c].recipe >= 0 else { return nil }
        let r = world.db.resolvedRecipes[Int(machines[c].recipe)]
        for (i, ing) in r.itemIngredients.enumerated() where ing.index == item { return i }
        return nil
    }

    private func furnaceRecipe(for item: Int, _ c: Int) -> Int? {
        let proto = Int(world.entities[machines[c].entity].proto)
        for cat in world.db.entityCategories[proto] {
            if let r = world.db.furnaceRecipeByInput[cat]?[item] { return r }
        }
        return nil
    }

    private func ingredientLimit(_ c: Int, _ i: Int, source: ItemTransferSource) -> Int {
        let r = world.db.resolvedRecipes[Int(machines[c].recipe)]
        let ing = r.itemIngredients[i]
        if source == .player { return max(world.stackSize(ing.index), Int(ing.amount)) }
        let k = kinds[Int(machines[c].kind)]
        let crafts = InsertionLimits.crafts(effectiveSpeed: k.speed * machines[c].speedMult, recipeTime: r.time)
        return Int(ing.amount) * crafts
    }

    public func acceptCount(_ e: Int32, item: Int, count: Int, source: ItemTransferSource) -> Int {
        guard let c = comp(e) else { return 0 }
        let k = kinds[Int(machines[c].kind)]
        // furnace auto-recipe: empty furnace accepts any smeltable input
        if k.isFurnace, furnaceIsEmpty(c), let _ = furnaceRecipe(for: item, c), ingredientIndex(c, item) == nil {
            if let b = machines[c].burner, BurnerEnergy.isFuel(item, db: world.db), ProdBurner.acceptFuel(b, item: item, count: count, source: source, db: world.db) > 0 {
                // coal etc. is fuel first
            } else {
                return min(count, source == .player ? world.stackSize(item) : 2)
            }
        }
        if let i = ingredientIndex(c, item) {
            let limit = ingredientLimit(c, i, source: source)
            return max(0, min(count, limit - Int(machines[c].inCount[i])))
        }
        if let b = machines[c].burner, BurnerEnergy.isFuel(item, db: world.db) {
            return ProdBurner.acceptFuel(b, item: item, count: count, source: source, db: world.db)
        }
        if k.isSilo, world.db.items[item].rocketLaunchProducts != nil {
            return machines[c].rocketInv.canInsert(item: item, count: min(count, 1), stackSize: 1)
        }
        return 0
    }

    private func furnaceIsEmpty(_ c: Int) -> Bool {
        if machines[c].recipe < 0 { return true }
        if machines[c].crafting { return false }
        return machines[c].inCount.allSatisfy { $0 == 0 } && machines[c].outCount.allSatisfy { $0 == 0 }
    }

    public func insert(_ e: Int32, item: Int, count: Int, source: ItemTransferSource) -> Int {
        let n = acceptCount(e, item: item, count: count, source: source)
        guard n > 0, let c = comp(e) else { return 0 }
        let k = kinds[Int(machines[c].kind)]
        if k.isFurnace, ingredientIndex(c, item) == nil, furnaceIsEmpty(c), let r = furnaceRecipe(for: item, c),
           !(machines[c].burner != nil && BurnerEnergy.isFuel(item, db: world.db)) {
            machines[c].recipe = Int32(r)
            allocBuffers(c)
            world.emit(.entityChanged(e))
        }
        if let i = ingredientIndex(c, item) {
            machines[c].inCount[i] += Int32(n)
        } else if machines[c].burner != nil, BurnerEnergy.isFuel(item, db: world.db) {
            machines[c].burner!.fuel.insert(item: item, count: n, stackSize: world.stackSize(item))
        } else if k.isSilo {
            machines[c].rocketInv.insert(item: item, count: n, stackSize: 1)
        } else { return 0 }
        wake(c)
        return n
    }

    public func peekExtract(_ e: Int32, source: ItemTransferSource, filter: (Int) -> Bool) -> ItemStack? {
        guard let c = comp(e) else { return nil }
        if machines[c].recipe >= 0 && !kinds[Int(machines[c].kind)].isSilo {
            let r = world.db.resolvedRecipes[Int(machines[c].recipe)]
            for (i, res) in r.itemResults.enumerated() where machines[c].outCount[i] > 0 && filter(res.index) {
                return ItemStack(item: res.index, count: Int(machines[c].outCount[i]))
            }
        }
        for s in machines[c].extraOut.slots where !s.isEmpty && filter(Int(s.item)) { return s }
        if source == .player, let b = machines[c].burner {
            for s in b.fuel.slots where !s.isEmpty && filter(Int(s.item)) { return s }
        }
        return nil
    }

    public func extract(_ e: Int32, item: Int, count: Int, source: ItemTransferSource) -> Int {
        guard let c = comp(e) else { return 0 }
        var left = count
        if machines[c].recipe >= 0 && !kinds[Int(machines[c].kind)].isSilo {
            let r = world.db.resolvedRecipes[Int(machines[c].recipe)]
            for (i, res) in r.itemResults.enumerated() where res.index == item && left > 0 {
                let t = min(left, Int(machines[c].outCount[i]))
                machines[c].outCount[i] -= Int32(t); left -= t
            }
        }
        if left > 0 { left -= machines[c].extraOut.remove(item: item, count: left) }
        if left > 0, source == .player, machines[c].burner != nil { left -= machines[c].burner!.fuel.remove(item: item, count: left) }
        if left < count { wake(c) }
        return count - left
    }

    /// Player: take ingredients back (entity screen).
    public func extractIngredient(_ e: Int32, item: Int, count: Int) -> Int {
        guard let c = comp(e), let i = ingredientIndex(c, item) else { return 0 }
        let t = min(count, Int(machines[c].inCount[i]))
        machines[c].inCount[i] -= Int32(t)
        return t
    }
}
