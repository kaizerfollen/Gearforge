// Gearforge — FactoryCore
// The Engineer: position/movement, inventory (80 + bonus slots), handcrafting queue with chain crafting, hand mining,
// reach checks, quickbar. Owner: Gameplay engineer. (05_mechanics §4.4, §11, §12)

public struct CraftQueueEntry: Sendable, Equatable {
    public var recipe: Int
    public var count: Int
    /// 0...1 progress of the unit currently being crafted (only for the first job of the queue).
    public var progress: Double
    /// Auto-queued intermediate.
    public var isIntermediate: Bool
    /// Group index (pass to `.cancelCraft(queueIndex:)`).
    public var group: Int
}

public final class Character {
    public unowned let world: World
    public init(world: World) { self.world = world }

    // MARK: Constants (05 §12)
    public static let runSpeed = 0.15                  // tiles per tick
    public static let buildReach = 10.0
    public static let resourceReach = 2.7
    public static let baseMiningSpeed = 0.5
    public static let baseInventory = 80
    static let halfBox = 0.2

    public var position: Vec2 = .zero
    public var inventory = Inventory(size: Character.baseInventory)
    /// Movement input set by the UI each frame: unit vector (or zero). Applied in update() at running speed.
    public var moveInput: Vec2 = .zero
    /// Last movement direction (for the sprite).
    public private(set) var facing: Direction = .south
    public private(set) var isMoving = false
    /// Quickbar: 2 pages × 10 item filters (-1 empty).
    public var quickbar: [Int32] = Array(repeating: -1, count: 20)

    // MARK: Crafting state
    struct CraftJob { var recipe: Int32; var remaining: Int32; var progress: Double; var intermediate: Bool }
    struct CraftGroup { var jobs: [CraftJob]; var pool: [Int32: Int32] }
    var craftGroups: [CraftGroup] = []

    // MARK: Mining state
    public enum MiningTarget: Equatable, Sendable { case tile(TilePos), entity(Int32) }
    public private(set) var miningTarget: MiningTarget? = nil
    public private(set) var miningProgress: Double = 0

    // MARK: Undo
    var undoStack: [UndoAction] = []
    var redoStack: [UndoAction] = []

    public func setUp() {
        let s = world.mapGen.spawnPosition
        position = Vec2(Double(s.x) + 0.5, Double(s.y) + 0.5)
    }

    /// Gives the starting kit from world settings (GDD §8). Call once for a new freeplay game.
    public func giveStartingKit() {
        var kit: [(String, Int)] = [("iron_plate", 8), ("wood", 10), ("burner_mining_drill", 1), ("stone_furnace", 1)]
        if world.settings.startingKit == "extended" {
            kit += [("burner_mining_drill", 4), ("stone_furnace", 4), ("coal", 50), ("iron_plate", 100)]
        }
        for (id, n) in kit { give(world.db.item(id), n) }
    }

    /// Adds items to the inventory; returns how many fit.
    @discardableResult
    public func give(_ item: Int, _ count: Int) -> Int {
        guard item >= 0, count > 0 else { return 0 }
        return inventory.insert(item: item, count: count, stackSize: world.stackSize(item))
    }

    public func count(of item: Int) -> Int { inventory.count(of: item) }

    /// Keeps inventory size in sync with the toolbelt bonus.
    private func syncInventorySize() {
        let want = Self.baseInventory + world.bonuses.characterInventoryBonus
        if inventory.size < want { inventory.slots += Array(repeating: .empty, count: want - inventory.size) }
    }

    // MARK: Reach

    /// Distance from the character to the nearest point of a rect.
    public func distance(to r: TileRect) -> Double {
        let nx = max(Double(r.x), min(position.x, Double(r.maxX)))
        let ny = max(Double(r.y), min(position.y, Double(r.maxY)))
        return Vec2(nx, ny).distance(to: position)
    }
    public func canReach(_ r: TileRect, reach: Double = Character.buildReach) -> Bool {
        world.settings.casualReach || distance(to: r) <= reach
    }

    // MARK: Tick

    public func update() {
        syncInventorySize()
        move()
        updateCrafting()
        updateMining()
        if world.tick % 30 == 0 { autoBuildGhosts() }
        if world.tick % 10 == 0, !world.ground.isEmpty { autoLoot() }
    }

    private func walkable(_ p: Vec2) -> Bool {
        let h = Self.halfBox
        for (dx, dy) in [(-h, -h), (h, -h), (-h, h), (h, h)] {
            let t = Vec2(p.x + dx, p.y + dy).tile
            if !world.surface.isInBounds(t) { return false }
            let tile = world.surface.tile(at: t)
            if tile >= 0 && world.db.tiles[tile].isWater { return false }
            if let e = world.entity(at: t) {
                let r = world.entities[e]
                if r.flags.contains(.ghost) { continue }
                switch r.kind {
                case .transportBelt, .undergroundBelt, .splitter, .electricPole: continue   // walk over belts / past small poles
                default: return false
                }
            }
        }
        return true
    }

    private func move() {
        let len = moveInput.length
        guard len > 1e-6 else { isMoving = false; return }
        let dir = Vec2(moveInput.x / max(1, len), moveInput.y / max(1, len))
        let t = world.surface.tile(at: position.tile)
        let mod = t >= 0 ? world.db.tiles[t].walkingSpeedModifier : 1
        let step = dir * (Self.runSpeed * mod)
        var p = position
        if walkable(Vec2(p.x + step.x, p.y)) { p.x += step.x }
        if walkable(Vec2(p.x, p.y + step.y)) { p.y += step.y }
        isMoving = p != position
        position = p
        if abs(dir.x) > abs(dir.y) { facing = dir.x > 0 ? .east : .west } else { facing = dir.y > 0 ? .south : .north }
    }

    // MARK: Handcrafting

    /// Whether the player may hand-craft recipe `r` at all (unlocked + handcraftable).
    public func canHandcraft(_ r: Int) -> Bool {
        guard r >= 0 && r < world.db.recipes.count else { return false }
        let rp = world.db.recipes[r]
        return rp.handcraftable && !rp.hidden && world.research.isRecipeUnlocked(r)
    }

    /// Handcraft recipe producing `item`, preferring the recipe whose main/first product is the item.
    private func handRecipe(for item: Int) -> Int? {
        for r in world.db.recipesProducing[item] where canHandcraft(r) {
            let res = world.db.resolvedRecipes[r].itemResults
            if res.first?.index == item { return r }
        }
        return nil
    }

    /// Plans crafting `count` of recipe `r` from `avail`. Appends jobs (deepest first) and consumes from `avail`.
    /// Returns false if impossible. `raw` collects items taken from the inventory.
    private func plan(_ r: Int, _ count: Int, avail: inout [Int: Int], jobs: inout [CraftJob], raw: inout [Int: Int],
                      intermediate: Bool, depth: Int = 0) -> Bool {
        guard depth < 8, canHandcraft(r) else { return false }
        let rr = world.db.resolvedRecipes[r]
        if !rr.fluidIngredients.isEmpty { return false }
        for ing in rr.itemIngredients {
            let need = Int(ing.amount) * count
            let have = avail[ing.index] ?? 0
            if have >= need {
                avail[ing.index] = have - need
                raw[ing.index, default: 0] += need
                continue
            }
            // take what we have, craft the rest
            if have > 0 { raw[ing.index, default: 0] += have }
            avail[ing.index] = 0
            let missing = need - have
            guard let sub = handRecipe(for: ing.index) else { return false }
            let per = Int(world.db.resolvedRecipes[sub].itemResults.first { $0.index == ing.index }?.amount ?? 1)
            let crafts = (missing + per - 1) / per
            if !plan(sub, crafts, avail: &avail, jobs: &jobs, raw: &raw, intermediate: true, depth: depth + 1) { return false }
            // excess intermediate stays available
            avail[ing.index, default: 0] += crafts * per - missing
        }
        jobs.append(CraftJob(recipe: Int32(r), remaining: Int32(count), progress: 0, intermediate: intermediate))
        return true
    }

    private func inventoryCounts() -> [Int: Int] {
        var m: [Int: Int] = [:]
        for s in inventory.slots where !s.isEmpty { m[Int(s.item), default: 0] += Int(s.count) }
        return m
    }

    /// How many of recipe `r` can be crafted now, including chain crafting (capped at 1000).
    public func craftableCount(_ r: Int) -> Int {
        guard canHandcraft(r) else { return 0 }
        let inv = inventoryCounts()
        func ok(_ n: Int) -> Bool {
            var a = inv; var j: [CraftJob] = []; var raw: [Int: Int] = [:]
            return plan(r, n, avail: &a, jobs: &j, raw: &raw, intermediate: false)
        }
        if !ok(1) { return 0 }
        var lo = 1, hi = 2
        while hi <= 1000 && ok(hi) { lo = hi; hi *= 2 }
        hi = min(hi, 1001)
        while hi - lo > 1 { let m = (lo + hi) / 2; if ok(m) { lo = m } else { hi = m } }
        return lo
    }

    /// Queues `count` crafts of `r` (with automatic intermediates). Ingredients are removed now.
    @discardableResult
    public func queueCraft(_ r: Int, count: Int) -> Bool {
        guard count > 0 else { return false }
        var avail = inventoryCounts()
        var jobs: [CraftJob] = []
        var raw: [Int: Int] = [:]
        guard plan(r, count, avail: &avail, jobs: &jobs, raw: &raw, intermediate: false) else { return false }
        var pool: [Int32: Int32] = [:]
        for (item, n) in raw where n > 0 {
            inventory.remove(item: item, count: n)
            pool[Int32(item), default: 0] += Int32(n)
        }
        craftGroups.append(CraftGroup(jobs: jobs, pool: pool))
        return true
    }

    /// Cancels a queued group; refunds its pool (raw ingredients and finished intermediates).
    @discardableResult
    public func cancelCraft(group: Int) -> Bool {
        guard group >= 0 && group < craftGroups.count else { return false }
        let g = craftGroups.remove(at: group)
        for (item, n) in g.pool where n > 0 {
            let fit = give(Int(item), Int(n))
            if fit < Int(n) { world.ground.spill([ItemStack(item: item, count: n - Int32(fit))], near: position) }
        }
        return true
    }

    public var craftQueue: [CraftQueueEntry] {
        var out: [CraftQueueEntry] = []
        for (gi, g) in craftGroups.enumerated() {
            for j in g.jobs where j.remaining > 0 {
                out.append(CraftQueueEntry(recipe: Int(j.recipe), count: Int(j.remaining), progress: j.progress,
                                           isIntermediate: j.intermediate, group: gi))
            }
        }
        return out
    }

    private func updateCrafting() {
        guard !craftGroups.isEmpty else { return }
        var g = craftGroups[0]
        guard let ji = g.jobs.firstIndex(where: { $0.remaining > 0 }) else {
            // group finished: leftover pool (excess intermediates) → inventory
            for (item, n) in g.pool where n > 0 { give(Int(item), Int(n)) }
            craftGroups.removeFirst()
            return
        }
        let r = Int(g.jobs[ji].recipe)
        let rr = world.db.resolvedRecipes[r]
        g.jobs[ji].progress += 1 / (rr.time * Double(ticksPerSecond))
        if g.jobs[ji].progress >= 1 {
            // results
            let final = !g.jobs[ji].intermediate
            if final {
                for res in rr.itemResults where inventory.canInsert(item: res.index, count: Int(res.amount), stackSize: world.stackSize(res.index)) < Int(res.amount) {
                    g.jobs[ji].progress = 1      // pause until room
                    craftGroups[0] = g
                    return
                }
            }
            for ing in rr.itemIngredients {
                g.pool[Int32(ing.index), default: 0] -= Int32(ing.amount)
                world.stats.consumed(item: ing.index, count: Int(ing.amount))
            }
            for res in rr.itemResults {
                let n = Int(res.amount)
                world.stats.producedByHand(item: res.index, count: n)
                if final { give(res.index, n); world.emit(.craftFinished(item: res.index, count: n)) }
                else { g.pool[Int32(res.index), default: 0] += Int32(n) }
            }
            g.jobs[ji].progress = 0
            g.jobs[ji].remaining -= 1
        }
        craftGroups[0] = g
    }

    // MARK: Hand mining

    /// Starts mining the tree/rock or resource at `p`. Returns an error if out of reach / nothing to mine.
    public func startMining(_ p: TilePos) -> PlacementError? {
        if let e = world.entity(at: p) {
            let rec = world.entities[e]
            guard rec.kind == .tree || rec.kind == .rock else { return .notAllowed }
            guard distance(to: rec.rect) <= Self.resourceReach || world.settings.casualReach else { return .outOfReach }
            if miningTarget != .entity(e) { miningTarget = .entity(e); miningProgress = 0 }
            return nil
        }
        let (r, a) = world.surface.resource(at: p)
        guard r >= 0, a > 0, !world.db.resources[r].resultIsFluid else { return .nothingThere }
        guard distance(to: TileRect(origin: p, w: 1, h: 1)) <= Self.resourceReach || world.settings.casualReach else { return .outOfReach }
        if miningTarget != .tile(p) { miningTarget = .tile(p); miningProgress = 0 }
        return nil
    }

    public func stopMining() { miningTarget = nil; miningProgress = 0 }

    private func updateMining() {
        guard let t = miningTarget else { return }
        let speed = Self.baseMiningSpeed * (1 + world.bonuses.characterMiningSpeed)
        switch t {
        case .entity(let e):
            let rec = world.entities[e]
            guard rec.isAlive, rec.kind == .tree || rec.kind == .rock, canReach(rec.rect, reach: Self.resourceReach) else { stopMining(); return }
            let p = world.db.entities[Int(rec.proto)]
            miningProgress += speed / (max(0.1, p.mineTime) * Double(ticksPerSecond))
            guard miningProgress >= 1 else { return }
            let loot = p.minedResults.map { (world.db.item($0.id), Int($0.amount)) }
            for (item, n) in loot where item >= 0 {
                if inventory.canInsert(item: item, count: n, stackSize: world.stackSize(item)) < n { miningProgress = 1; return }
            }
            for (item, n) in loot where item >= 0 { give(item, n); world.stats.producedByHandMining(item: item, count: n) }
            world.removeEntity(e)
            stopMining()
        case .tile(let p):
            let (r, a) = world.surface.resource(at: p)
            guard r >= 0, a > 0, canReach(TileRect(origin: p, w: 1, h: 1), reach: Self.resourceReach) else { stopMining(); return }
            let res = world.db.resources[r]
            miningProgress += speed / (res.miningTime * Double(ticksPerSecond))
            guard miningProgress >= 1 else { return }
            let item = world.db.item(res.result)
            if inventory.canInsert(item: item, count: 1, stackSize: world.stackSize(item)) < 1 { miningProgress = 1; return }
            miningProgress -= 1
            give(item, 1)
            world.stats.producedByHandMining(item: item, count: 1)
            if !res.infinite {
                let left = a - 1
                world.surface.setResource(at: p, left > 0 ? r : -1, amount: left)
                if left == 0 { world.emit(.tilesChanged(p.chunk)); stopMining() }
            }
        }
    }

    // MARK: Ground items

    /// Picks up items lying within `GroundItems.autoLootRadius` (what fits).
    private func autoLoot() {
        let r = GroundItems.autoLootRadius
        let x0 = Int32((position.x - r).rounded(.down)), x1 = Int32((position.x + r).rounded(.down))
        let y0 = Int32((position.y - r).rounded(.down)), y1 = Int32((position.y + r).rounded(.down))
        var y = y0
        while y <= y1 {
            var x = x0
            while x <= x1 { pickUpGround(TilePos(x, y)); x += 1 }
            y += 1
        }
    }

    /// Moves ground items on a tile into the inventory (what fits). Returns the number picked up.
    @discardableResult
    public func pickUpGround(_ p: TilePos) -> Int {
        let stacks = world.ground.items(at: p)
        guard !stacks.isEmpty else { return 0 }
        var got = 0
        for s in stacks {
            let fit = inventory.canInsert(item: Int(s.item), count: Int(s.count), stackSize: world.stackSize(Int(s.item)))
            guard fit > 0 else { continue }
            var taken = 0
            while taken < fit, world.ground.takeOne(at: p, filter: { $0 == Int(s.item) }) >= 0 { taken += 1 }
            give(Int(s.item), taken)
            got += taken
        }
        return got
    }

    // MARK: Ghosts

    /// Builds ghosts within reach whose item is in the inventory (GDD §4.4 "auto-build ghosts in reach").
    private func autoBuildGhosts() {
        let reach = Int32(Self.buildReach) + 1
        let p = position.tile
        let rect = TileRect(x: p.x - reach, y: p.y - reach, w: reach * 2 + 1, h: reach * 2 + 1)
        for e in world.entities(in: rect) {
            let rec = world.entities[e]
            guard rec.isAlive, rec.flags.contains(.ghost), canReach(rec.rect) else { continue }
            let item = world.db.entityItem[Int(rec.proto)]
            guard item >= 0, count(of: item) > 0 else { continue }
            let proto = Int(rec.proto), origin = rec.origin, dir = rec.direction
            world.removeEntity(e)
            if world.canPlace(proto: proto, origin: origin, direction: dir) == nil {
                inventory.remove(item: item, count: 1)
                world.createEntity(proto: proto, origin: origin, direction: dir)
            }
        }
    }

    // MARK: Persistence

    public func serialize(to w: inout BinaryWriter) {
        w.write(UInt8(1))
        w.write(position)
        inventory.serialize(to: &w)
        w.writeArray(quickbar) { $0.write($1) }
        w.write(facing.rawValue)
        w.writeVarInt(craftGroups.count)
        for g in craftGroups {
            w.writeVarInt(g.jobs.count)
            for j in g.jobs { w.write(j.recipe); w.write(j.remaining); w.write(j.progress); w.write(j.intermediate) }
            let pool = g.pool.sorted { $0.key < $1.key }
            w.writeVarInt(pool.count)
            for (k, v) in pool { w.write(k); w.write(v) }
        }
        switch miningTarget {
        case nil: w.write(UInt8(0))
        case .tile(let p)?: w.write(UInt8(1)); w.write(p)
        case .entity(let e)?: w.write(UInt8(2)); w.write(e)
        }
        w.write(miningProgress)
    }

    public func deserialize(from r: inout BinaryReader) throws {
        _ = try r.read(UInt8.self)
        position = try r.readVec2()
        inventory = try Inventory(from: &r)
        quickbar = try r.readArray { try $0.read(Int32.self) }
        facing = Direction(rawValue: try r.read(UInt8.self)) ?? .south
        craftGroups = []
        let ng = try r.readVarInt()
        for _ in 0..<ng {
            var jobs: [CraftJob] = []
            let nj = try r.readVarInt()
            for _ in 0..<nj {
                jobs.append(CraftJob(recipe: try r.read(Int32.self), remaining: try r.read(Int32.self),
                                     progress: try r.readDouble(), intermediate: try r.readBool()))
            }
            var pool: [Int32: Int32] = [:]
            let np = try r.readVarInt()
            for _ in 0..<np { let k = try r.read(Int32.self); pool[k] = try r.read(Int32.self) }
            craftGroups.append(CraftGroup(jobs: jobs, pool: pool))
        }
        switch try r.read(UInt8.self) {
        case 1: miningTarget = .tile(try r.readTilePos())
        case 2: miningTarget = .entity(try r.read(Int32.self))
        default: miningTarget = nil
        }
        miningProgress = try r.readDouble()
        undoStack = []; redoStack = []
    }
}
