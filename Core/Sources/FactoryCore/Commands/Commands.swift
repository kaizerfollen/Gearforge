// Gearforge — FactoryCore
// Every player action goes through `World.execute(_:)`. Validation (reach, inventory, placement rules, fast-replace),
// item accounting and undo records live here. Owner: Gameplay engineer. Keep case names stable (UI uses them).

public enum PlacementError: Error, Equatable, Sendable {
    case outOfBounds, blocked, water, needsShoreline, noResourceUnderDrill, outOfReach, notInInventory
    case wouldMixFluids, notResearched, invalidTile, cannotRotate, nothingThere, inventoryFull, notAllowed
    case custom(String)

    /// Short player-facing reason (GDD §4.4 red ghost text).
    public var message: String {
        switch self {
        case .outOfBounds: return "Outside the map"
        case .blocked: return "Blocked"
        case .water: return "Can't build on water"
        case .needsShoreline: return "Needs water edge"
        case .noResourceUnderDrill: return "No resource under drill"
        case .outOfReach: return "Out of reach"
        case .notInInventory: return "Not in inventory"
        case .wouldMixFluids: return "Would mix fluids"
        case .notResearched: return "Not researched"
        case .invalidTile: return "Invalid tile"
        case .cannotRotate: return "Can't rotate"
        case .nothingThere: return "Nothing there"
        case .inventoryFull: return "Inventory full"
        case .notAllowed: return "Not allowed"
        case .custom(let s): return s
        }
    }
}

public enum PlayerCommand: Sendable {
    // Building
    case build(item: Int, origin: TilePos, direction: Direction)
    case buildGhost(entityProto: Int, origin: TilePos, direction: Direction)
    case placeTiles(item: Int, tiles: [TilePos])
    case remove(entity: Int32)
    case removeArea(TileRect, kinds: Set<EntityKind>?)
    case rotate(entity: Int32, clockwise: Bool)
    // Machine configuration
    case setRecipe(entity: Int32, recipe: Int)
    case insertModule(entity: Int32, item: Int)
    case removeModule(entity: Int32, slot: Int)
    case setInserterFilter(entity: Int32, slot: Int, item: Int)
    case setSplitter(entity: Int32, settings: SplitterSettings)
    case setChestBar(entity: Int32, bar: Int?)
    case pasteSettings(from: Int32, to: Int32)
    case launchRocket(entity: Int32)
    // Item transfer between player and an entity
    case transferToEntity(entity: Int32, item: Int, count: Int)
    case transferFromEntity(entity: Int32, item: Int, count: Int)
    case takeAll(entity: Int32)
    case pickUpBeltItems(entity: Int32)
    /// Pick up the items lying on a tile (within reach).
    case pickUpGround(TilePos)
    /// Copy/paste area: place ghosts of a blueprint with its top-left at `origin`.
    case pasteBlueprint(Blueprint, origin: TilePos)
    // Character
    case craft(recipe: Int, count: Int)
    case cancelCraft(queueIndex: Int)
    case startMining(TilePos)
    case stopMining
    case sortInventory
    // Research
    case setResearch(tech: Int)
    case enqueueResearch(tech: Int)
    case dequeueResearch(tech: Int)
}

public enum CommandResult: Equatable, Sendable {
    case ok
    case failed(PlacementError)
    public var isOK: Bool { if case .ok = self { return true }; return false }
}

/// Undoable build/remove actions (GDD §4.4: last 50).
enum UndoAction {
    case built(EntityHandle, proto: Int, origin: TilePos, direction: Direction)
    case removed(proto: Int, origin: TilePos, direction: Direction, recipe: Int)
}

public extension World {

    // MARK: Placement validation

    /// Validates placing entity prototype `proto` at `origin`. nil = OK. Does not check reach/inventory.
    func canPlace(proto: Int, origin: TilePos, direction: Direction) -> PlacementError? {
        let (w, h) = footprint(proto, direction)
        let rect = TileRect(origin: origin, w: w, h: h)
        var err: PlacementError?
        rect.forEach { p in
            if err != nil { return }
            if !surface.isInBounds(p) { err = .outOfBounds; return }
            if surface.occupant(at: p) >= 0 { err = .blocked; return }
            let t = surface.tile(at: p)
            if t >= 0 && db.tiles[t].isWater { err = .water }
        }
        return err
    }

    /// Full rule set for building (GDD §4.4 reasons): tiles, special placement rules, fluid mixing.
    /// `ignoring` lets fast-replace validate against the footprint of the entity being replaced.
    func placementError(proto: Int, origin: TilePos, direction: Direction, ignoring: Int32? = nil) -> PlacementError? {
        let p = db.entities[proto]
        let (w, h) = footprint(proto, direction)
        let rect = TileRect(origin: origin, w: w, h: h)
        var err: PlacementError?
        rect.forEach { q in
            if err != nil { return }
            if !surface.isInBounds(q) { err = .outOfBounds; return }
            let occ = surface.occupant(at: q)
            if occ >= 0 && occ != (ignoring ?? -2) { err = .blocked; return }
            let t = surface.tile(at: q)
            if t >= 0 && db.tiles[t].isWater { err = .water }
        }
        if let e = err { return e }
        if p.placement == "shoreline" || p.kind == .offshorePump {
            // the tile opposite the output connection must be water
            let back = direction.rotate(TilePos(0, -1))
            let t = surface.tile(at: origin + back)
            if t < 0 || !db.tiles[t].isWater { return .needsShoreline }
        }
        if p.kind == .miningDrill && !mining.hasResource(proto: proto, origin: origin, direction: direction) {
            return .noResourceUnderDrill
        }
        if p.fluidBoxes != nil && ignoring == nil && fluids.wouldMixFluids(proto: proto, origin: origin, direction: direction) {
            return .wouldMixFluids
        }
        return nil
    }

    // MARK: Execute

    /// Executes a player command.
    @discardableResult
    func execute(_ cmd: PlayerCommand) -> CommandResult {
        let pl = player!
        switch cmd {
        case .build(let item, let origin, let dir):
            return build(item: item, origin: origin, direction: dir, recordUndo: true)

        case .buildGhost(let proto, let origin, let dir):
            if let e = canPlace(proto: proto, origin: origin, direction: dir) { return .failed(e) }
            createEntity(proto: proto, origin: origin, direction: dir, flags: [.playerBuilt, .ghost])
            return .ok

        case .placeTiles(let item, let tiles):
            let tile = db.itemPlaceTile[item]
            guard tile >= 0 else { return .failed(.invalidTile) }
            let isLandfill = db.items[item].id == "landfill"
            var placed = 0
            for p in tiles {
                guard pl.count(of: item) > 0 else { break }
                guard surface.isInBounds(p), pl.canReach(TileRect(origin: p, w: 1, h: 1)) else { continue }
                let cur = surface.tile(at: p)
                let curWater = cur >= 0 && db.tiles[cur].isWater
                if isLandfill != curWater { continue }
                if cur == tile { continue }
                // returning a previously placed floor tile
                if cur >= 0, let mined = db.tiles[cur].minedItem { pl.give(db.item(mined), 1) }
                surface.setTile(at: p, tile)
                pl.inventory.remove(item: item, count: 1)
                emit(.tilesChanged(p.chunk))
                placed += 1
            }
            return placed > 0 ? .ok : .failed(.invalidTile)

        case .remove(let e):
            return remove(entity: e, recordUndo: true)

        case .removeArea(let rect, let kinds):
            var removed = 0
            for e in entities(in: rect) {
                let rec = entities[e]
                guard rec.isAlive, rec.flags.contains(.playerBuilt) else { continue }
                if let k = kinds, !k.contains(rec.kind) { continue }
                if remove(entity: e, recordUndo: true).isOK { removed += 1 }
            }
            return removed > 0 ? .ok : .failed(.nothingThere)

        case .rotate(let e, let cw):
            let rec = entities[e]
            guard rec.isAlive, rec.flags.contains(.playerBuilt) else { return .failed(.nothingThere) }
            let p = db.entities[Int(rec.proto)]
            guard p.rotatable else { return .failed(.cannotRotate) }
            let nd = cw ? rec.direction.clockwise : rec.direction.counterClockwise
            let (w, h) = footprint(Int(rec.proto), nd)
            if w != Int(rec.w) || h != Int(rec.h) {
                // non-square: rotated footprint (same origin) must be free except for itself
                var blocked = false
                TileRect(origin: rec.origin, w: w, h: h).forEach { q in
                    let o = surface.occupant(at: q)
                    if !surface.isInBounds(q) || (o >= 0 && o != e) { blocked = true }
                }
                if blocked { return .failed(.cannotRotate) }
            }
            rotateEntity(e, to: nd)
            return .ok

        case .setRecipe(let e, let r):
            guard entities[e].isAlive else { return .failed(.nothingThere) }
            if r >= 0 {
                guard research.isRecipeUnlocked(r) else { return .failed(.notResearched) }
                guard db.canCraft(entity: Int(entities[e].proto), recipe: r) else { return .failed(.notAllowed) }
            }
            for s in crafting.setRecipe(e, r) { giveOrAlert(s) }
            return .ok

        case .insertModule(let e, let item):
            guard pl.count(of: item) > 0 else { return .failed(.notInInventory) }
            let ok: Bool
            switch entities[e].kind {
            case .assemblingMachine, .furnace, .rocketSilo: ok = crafting.insertModule(e, item: item)
            case .miningDrill: ok = mining.insertModule(e, item: item)
            case .lab: ok = labs.insertModule(e, item: item)
            case .beacon: ok = beacons.insertModule(e, item: item)
            default: ok = false
            }
            guard ok else { return .failed(.notAllowed) }
            pl.inventory.remove(item: item, count: 1)
            return .ok

        case .removeModule(let e, let slot):
            let s: ItemStack?
            switch entities[e].kind {
            case .assemblingMachine, .furnace, .rocketSilo: s = crafting.removeModule(e, slot: slot)
            case .miningDrill: s = mining.removeModule(e, slot: slot)
            case .lab: s = labs.removeModule(e, slot: slot)
            case .beacon: s = beacons.removeModule(e, slot: slot)
            default: s = nil
            }
            guard let st = s else { return .failed(.nothingThere) }
            giveOrAlert(st)
            return .ok

        case .setInserterFilter(let e, let slot, let item):
            guard entities[e].kind == .inserter else { return .failed(.notAllowed) }
            inserters.setFilter(e, slot: slot, item: item)
            return .ok

        case .setSplitter(let e, let s):
            guard entities[e].kind == .splitter else { return .failed(.notAllowed) }
            belts.setSplitterSettings(e, s)
            return .ok

        case .setChestBar(let e, let bar):
            guard entities[e].kind == .container else { return .failed(.notAllowed) }
            containers.setBar(e, bar)
            return .ok

        case .pasteSettings(let from, let to):
            let a = entities[from], b = entities[to]
            guard a.isAlive, b.isAlive else { return .failed(.nothingThere) }
            switch (a.kind, b.kind) {
            case (.assemblingMachine, .assemblingMachine), (.furnace, .furnace):
                let r = crafting.recipe(of: from)
                if r >= 0 && db.canCraft(entity: Int(b.proto), recipe: r) { for s in crafting.setRecipe(to, r) { giveOrAlert(s) } }
            case (.inserter, .inserter):
                for (i, f) in inserters.filters(of: from).enumerated() { inserters.setFilter(to, slot: i, item: f) }
            case (.splitter, .splitter):
                belts.setSplitterSettings(to, belts.splitterSettings(from))
            case (.container, .container):
                containers.setBar(to, containers.bar(of: from))
            default:
                return .failed(.notAllowed)
            }
            return .ok

        case .launchRocket(let e):
            return crafting.launchRocket(e) ? .ok : .failed(.notAllowed)

        case .transferToEntity(let e, let item, let count):
            guard entities[e].isAlive else { return .failed(.nothingThere) }
            guard pl.canReach(entities[e].rect) else { return .failed(.outOfReach) }
            let n = min(count, pl.count(of: item))
            guard n > 0 else { return .failed(.notInInventory) }
            let ins = insert(e, item: item, count: n, source: .player)
            guard ins > 0 else { return .failed(.notAllowed) }
            pl.inventory.remove(item: item, count: ins)
            return .ok

        case .transferFromEntity(let e, let item, let count):
            guard entities[e].isAlive else { return .failed(.nothingThere) }
            guard pl.canReach(entities[e].rect) else { return .failed(.outOfReach) }
            let room = pl.inventory.canInsert(item: item, count: count, stackSize: stackSize(item))
            guard room > 0 else { return .failed(.inventoryFull) }
            var got = extract(e, item: item, count: room, source: .player)
            if got == 0 && (entities[e].kind == .assemblingMachine || entities[e].kind == .furnace) {
                got = crafting.extractIngredient(e, item: item, count: room)
            }
            guard got > 0 else { return .failed(.nothingThere) }
            pl.give(item, got)
            return .ok

        case .takeAll(let e):
            guard entities[e].isAlive else { return .failed(.nothingThere) }
            guard pl.canReach(entities[e].rect) else { return .failed(.outOfReach) }
            var moved = 0
            var guardCount = 0
            while let s = peekExtract(e, source: .player), guardCount < 200 {
                guardCount += 1
                let room = pl.inventory.canInsert(item: Int(s.item), count: Int(s.count), stackSize: stackSize(Int(s.item)))
                if room <= 0 { break }
                let got = extract(e, item: Int(s.item), count: room, source: .player)
                if got <= 0 { break }
                pl.give(Int(s.item), got)
                moved += got
            }
            return moved > 0 ? .ok : .failed(.nothingThere)

        case .pickUpBeltItems(let e):
            guard pl.canReach(entities[e].rect) else { return .failed(.outOfReach) }
            let items = belts.removeAllItems(on: e)
            guard !items.isEmpty else { return .failed(.nothingThere) }
            for s in items { giveOrAlert(s) }
            return .ok

        case .pasteBlueprint(let bp, let origin):
            return pasteBlueprint(bp, at: origin) > 0 ? .ok : .failed(.blocked)

        case .pickUpGround(let p):
            guard pl.canReach(TileRect(origin: p, w: 1, h: 1)) else { return .failed(.outOfReach) }
            return pl.pickUpGround(p) > 0 ? .ok : .failed(.nothingThere)

        case .craft(let r, let count):
            guard pl.canHandcraft(r) else { return .failed(.notResearched) }
            return pl.queueCraft(r, count: count) ? .ok : .failed(.notInInventory)

        case .cancelCraft(let i):
            return pl.cancelCraft(group: i) ? .ok : .failed(.nothingThere)

        case .startMining(let p):
            if let e = pl.startMining(p) { return .failed(e) }
            return .ok

        case .stopMining:
            pl.stopMining()
            return .ok

        case .sortInventory:
            let order = db.items.indices.sorted { (db.items[$0].subgroup, db.items[$0].order) < (db.items[$1].subgroup, db.items[$1].order) }
            var rank = [Int](repeating: 0, count: db.items.count)
            for (i, it) in order.enumerated() { rank[it] = i }
            pl.inventory.sort(stackSize: { self.stackSize($0) }, order: { rank[$0] < rank[$1] })
            return .ok

        case .setResearch(let t):
            research.setCurrent(t)
            return research.current == t ? .ok : .failed(.notAllowed)
        case .enqueueResearch(let t):
            research.enqueue(t)
            return .ok
        case .dequeueResearch(let t):
            research.dequeue(t)
            return .ok
        }
    }

    // MARK: Undo / redo

    var canUndo: Bool { !player.undoStack.isEmpty }
    var canRedo: Bool { !player.redoStack.isEmpty }

    @discardableResult
    func undo() -> CommandResult {
        guard let a = player.undoStack.popLast() else { return .failed(.nothingThere) }
        switch a {
        case .built(let h, let proto, let origin, let dir):
            guard let e = entities.resolve(h) else { return .failed(.nothingThere) }
            let recipe = crafting.recipe(of: e)
            let r = remove(entity: e, recordUndo: false)
            if r.isOK { player.redoStack.append(.removed(proto: proto, origin: origin, direction: dir, recipe: recipe)) }
            return r
        case .removed(let proto, let origin, let dir, let recipe):
            let item = db.entityItem[proto]
            let r = build(item: item, origin: origin, direction: dir, recordUndo: false)
            if r.isOK, let e = entity(at: origin) {
                if recipe >= 0 { for s in crafting.setRecipe(e, recipe) { giveOrAlert(s) } }
                player.redoStack.append(.built(entities.handle(e), proto: proto, origin: origin, direction: dir))
            }
            return r
        }
    }

    @discardableResult
    func redo() -> CommandResult {
        guard let a = player.redoStack.popLast() else { return .failed(.nothingThere) }
        switch a {
        case .built(let h, let proto, let origin, let dir):
            guard let e = entities.resolve(h) else { return .failed(.nothingThere) }
            let recipe = crafting.recipe(of: e)
            let r = remove(entity: e, recordUndo: false)
            if r.isOK { pushUndo(.removed(proto: proto, origin: origin, direction: dir, recipe: recipe), clearRedo: false) }
            return r
        case .removed(let proto, let origin, let dir, let recipe):
            let r = build(item: db.entityItem[proto], origin: origin, direction: dir, recordUndo: false)
            if r.isOK, let e = entity(at: origin) {
                if recipe >= 0 { for s in crafting.setRecipe(e, recipe) { giveOrAlert(s) } }
                pushUndo(.built(entities.handle(e), proto: proto, origin: origin, direction: dir), clearRedo: false)
            }
            return r
        }
    }

    internal func pushUndo(_ a: UndoAction, clearRedo: Bool = true) {
        player.undoStack.append(a)
        if player.undoStack.count > 50 { player.undoStack.removeFirst(player.undoStack.count - 50) }
        if clearRedo { player.redoStack.removeAll() }
    }

    // MARK: Helpers

    private func giveOrAlert(_ s: ItemStack) {
        guard !s.isEmpty else { return }
        let fit = player.give(Int(s.item), Int(s.count))
        if fit < Int(s.count) { ground.spill([ItemStack(item: s.item, count: s.count - Int32(fit))], near: player.position) }
    }

    /// Fast-replace target: a single entity exactly under the footprint, same replace group, different prototype or
    /// direction (GDD §9.1).
    private func fastReplaceTarget(proto: Int, origin: TilePos, direction: Direction) -> Int32? {
        let p = db.entities[proto]
        guard let group = p.fastReplaceGroup else { return nil }
        let (w, h) = footprint(proto, direction)
        let rect = TileRect(origin: origin, w: w, h: h)
        let under = entities(in: rect)
        guard under.count == 1 else { return nil }
        let o = under[0]
        let rec = entities[o]
        guard rec.flags.contains(.playerBuilt), !rec.flags.contains(.ghost), rec.rect == rect else { return nil }
        let op = db.entities[Int(rec.proto)]
        guard op.fastReplaceGroup == group, Int(rec.proto) != proto || rec.direction != direction else { return nil }
        return o
    }

    private func build(item: Int, origin: TilePos, direction: Direction, recordUndo: Bool) -> CommandResult {
        guard item >= 0, item < db.items.count else { return .failed(.notAllowed) }
        let proto = db.itemPlaceResult[item]
        guard proto >= 0 else { return .failed(.notAllowed) }
        let pl = player!
        guard pl.count(of: item) > 0 else { return .failed(.notInInventory) }
        let (w, h) = footprint(proto, direction)
        let rect = TileRect(origin: origin, w: w, h: h)
        guard pl.canReach(rect) else { return .failed(.outOfReach) }
        let dir = db.entities[proto].rotatable ? direction : .north

        // Fast replace / upgrade in place
        if let old = fastReplaceTarget(proto: proto, origin: origin, direction: dir) {
            if let e = placementError(proto: proto, origin: origin, direction: dir, ignoring: old) { return .failed(e) }
            let orec = entities[old]
            let recipe = crafting.recipe(of: old)
            let filters = orec.kind == .inserter ? inserters.filters(of: old) : []
            let chestContents = orec.kind == .container ? containers.inventory(of: old)?.contents() ?? [] : []
            let bar = orec.kind == .container ? containers.bar(of: old) : nil
            let oldProto = Int(orec.proto)
            let contents = removeEntity(old)
            let oldItem = db.entityItem[oldProto]
            pl.inventory.remove(item: item, count: 1)
            if oldItem >= 0 { pl.give(oldItem, 1) }
            let e = createEntity(proto: proto, origin: origin, direction: dir)
            if recipe >= 0 && entities[e].kind != .furnace { _ = crafting.setRecipe(e, recipe) }
            for (i, f) in filters.enumerated() { inserters.setFilter(e, slot: i, item: f) }
            if entities[e].kind == .container {
                containers.setBar(e, bar)
                for (it, n) in chestContents {
                    let ins = containers.insert(e, item: it, count: n, source: .player)
                    if ins < n { pl.give(it, n - ins) }
                }
                // chest contents were returned by removeEntity → do not give them twice
                for s in contents where chestContents.contains(where: { $0.item == Int(s.item) }) { _ = s }
            } else {
                for s in contents { giveOrAlert(s) }
            }
            if recordUndo { pushUndo(.built(entities.handle(e), proto: proto, origin: origin, direction: dir)) }
            return .ok
        }

        if let e = placementError(proto: proto, origin: origin, direction: dir) {
            // building over a ghost of the same entity replaces the ghost
            if e == .blocked, let g = entity(at: origin), entities[g].flags.contains(.ghost), Int(entities[g].proto) == proto {
                let gs = takeGhostSettings(g)
                removeEntity(g)
                let r = build(item: item, origin: origin, direction: dir, recordUndo: recordUndo)
                if r.isOK, let s = gs, let n = entity(at: origin) { for st in apply(s, to: n) { giveOrAlert(st) } }
                return r
            }
            return .failed(e)
        }
        pl.inventory.remove(item: item, count: 1)
        let e = createEntity(proto: proto, origin: origin, direction: dir)
        ground.clear(entities[e].rect)
        if recordUndo { pushUndo(.built(entities.handle(e), proto: proto, origin: origin, direction: dir)) }
        return .ok
    }

    private func remove(entity e: Int32, recordUndo: Bool) -> CommandResult {
        let rec = entities[e]
        guard rec.isAlive else { return .failed(.nothingThere) }
        guard rec.flags.contains(.playerBuilt) else { return .failed(.notAllowed) }   // trees/rocks: hand mining
        let pl = player!
        if rec.flags.contains(.ghost) { removeEntity(e); return .ok }
        guard pl.canReach(rec.rect) else { return .failed(.outOfReach) }
        let proto = Int(rec.proto)
        // capacity check: contents + the entity item must fit
        let item = db.entityItem[proto]
        let recipe = crafting.recipe(of: e)
        let contents = removeEntity(e)
        var all = contents
        if item >= 0 { all.append(ItemStack(item: item, count: 1)) }
        var spill: [ItemStack] = []
        for s in all where !s.isEmpty {
            let fit = pl.give(Int(s.item), Int(s.count))
            if fit < Int(s.count) { spill.append(ItemStack(item: s.item, count: s.count - Int32(fit))) }
        }
        if !spill.isEmpty { ground.spill(spill, near: rec.rect.center); emit(.alert("Inventory full — items dropped on the ground")) }
        if recordUndo { pushUndo(.removed(proto: proto, origin: rec.origin, direction: rec.direction, recipe: recipe)) }
        return .ok
    }
}
