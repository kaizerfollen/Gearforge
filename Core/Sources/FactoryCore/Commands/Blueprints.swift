// Gearforge — FactoryCore
// Copy/paste area (GDD §4.6, MVP) and the data model for the blueprint library (phase 1.1).
// A Blueprint stores entities by prototype id (stable across data versions) relative to the captured rect's top-left,
// with their settings. Pasting places ghosts; when a ghost is built (by the player or the auto-builder) its settings
// are applied. Owner: Gameplay engineer.

public struct Blueprint: Codable, Equatable, Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public var entity: String
        public var dx: Int32
        public var dy: Int32
        public var direction: Direction
        public var settings: GhostSettings
    }
    public struct TileEntry: Codable, Equatable, Sendable {
        public var tile: String
        public var dx: Int32
        public var dy: Int32
    }
    public var name: String
    public var width: Int32
    public var height: Int32
    public var entries: [Entry]
    public var tiles: [TileEntry]

    public var isEmpty: Bool { entries.isEmpty && tiles.isEmpty }

    /// Items needed to build everything in the blueprint (entity id → count / tile item → count).
    public func requiredItems(db: PrototypeDB) -> [Int: Int] {
        var m: [Int: Int] = [:]
        for e in entries {
            let p = db.entity(e.entity)
            if p >= 0, db.entityItem[p] >= 0 { m[db.entityItem[p], default: 0] += 1 }
        }
        for t in tiles {
            let ti = db.tile(t.tile)
            if ti >= 0, let mined = db.tiles[ti].minedItem { m[db.item(mined), default: 0] += 1 }
        }
        return m
    }

    /// The blueprint rotated by `quarterTurns` × 90° clockwise.
    public func rotated(_ quarterTurns: Int, db: PrototypeDB) -> Blueprint {
        var bp = self
        let q = ((quarterTurns % 4) + 4) % 4
        for _ in 0..<q { bp = bp.rotatedOnce(db: db) }
        return bp
    }

    private func rotatedOnce(db: PrototypeDB) -> Blueprint {
        var out = self
        out.width = height
        out.height = width
        out.entries = entries.map { e in
            var n = e
            let p = db.entity(e.entity)
            let rot = p >= 0 ? db.entities[p].rotatable : true
            let (w, h): (Int32, Int32) = {
                guard p >= 0 else { return (1, 1) }
                let pe = db.entities[p]
                return e.direction.isHorizontal ? (Int32(pe.height), Int32(pe.width)) : (Int32(pe.width), Int32(pe.height))
            }()
            // (x, y) in a W×H rect → (H − y − h, x) in the rotated H×W rect
            n.dx = height - e.dy - h
            n.dy = e.dx
            if rot { n.direction = e.direction.clockwise }
            else if w != h { n.direction = e.direction }    // non-rotatable non-square entities are rare (none in MVP)
            return n
        }
        out.tiles = tiles.map { t in Blueprint.TileEntry(tile: t.tile, dx: height - t.dy - 1, dy: t.dx) }
        return out
    }
}

/// Settings carried by blueprint entries and by ghosts until they are built.
public struct GhostSettings: Codable, Equatable, Sendable {
    public var recipe: String? = nil
    public var filters: [String?]? = nil
    public var splitterInput: Int8? = nil
    public var splitterOutput: Int8? = nil
    public var splitterFilter: String? = nil
    public var chestBar: Int? = nil
    public var undergroundEntrance: Bool? = nil
    public init() {}
    public var isEmpty: Bool { self == GhostSettings() }
}

public extension World {

    // MARK: Settings capture / apply

    /// Current settings of a built entity (for copy/paste and blueprints).
    func settings(of e: Int32) -> GhostSettings {
        var s = GhostSettings()
        let rec = entities[e]
        switch rec.kind {
        case .assemblingMachine, .rocketSilo:
            let r = crafting.recipe(of: e)
            if r >= 0 && rec.kind == .assemblingMachine { s.recipe = db.recipes[r].id }
        case .inserter:
            let f = inserters.filters(of: e)
            if !f.isEmpty { s.filters = f.map { $0 >= 0 ? db.items[$0].id : nil } }
        case .splitter:
            let ss = belts.splitterSettings(e)
            s.splitterInput = ss.inputPriority; s.splitterOutput = ss.outputPriority
            s.splitterFilter = ss.filter >= 0 ? db.items[Int(ss.filter)].id : nil
        case .container:
            s.chestBar = containers.bar(of: e)
        case .undergroundBelt:
            s.undergroundEntrance = belts.isUndergroundEntrance(e)
        default: break
        }
        return s
    }

    /// Applies blueprint/ghost settings to a freshly built entity. Returns items to give back (recipe change).
    @discardableResult
    func apply(_ s: GhostSettings, to e: Int32) -> [ItemStack] {
        var back: [ItemStack] = []
        let rec = entities[e]
        if let r = s.recipe, rec.kind == .assemblingMachine {
            let ri = db.recipe(r)
            if ri >= 0, research.isRecipeUnlocked(ri), db.canCraft(entity: Int(rec.proto), recipe: ri) { back += crafting.setRecipe(e, ri) }
        }
        if let f = s.filters, rec.kind == .inserter {
            for (i, id) in f.enumerated() { inserters.setFilter(e, slot: i, item: id.map { db.item($0) } ?? -1) }
        }
        if rec.kind == .splitter, s.splitterInput != nil || s.splitterOutput != nil || s.splitterFilter != nil {
            var ss = SplitterSettings()
            ss.inputPriority = s.splitterInput ?? -1
            ss.outputPriority = s.splitterOutput ?? -1
            ss.filter = Int32(s.splitterFilter.map { db.item($0) } ?? -1)
            belts.setSplitterSettings(e, ss)
        }
        if let b = s.chestBar, rec.kind == .container { containers.setBar(e, b) }
        if let u = s.undergroundEntrance, rec.kind == .undergroundBelt { belts.setUndergroundMode(e, entrance: u) }
        return back
    }

    // MARK: Ghost settings store

    internal func setGhostSettings(_ s: GhostSettings, for e: Int32) {
        if s.isEmpty { ghostSettings[e] = nil } else { ghostSettings[e] = (entities[e].generation, s) }
    }

    /// Settings attached to a ghost (removed from the store). Nil if none / stale.
    internal func takeGhostSettings(_ e: Int32) -> GhostSettings? {
        guard let (gen, s) = ghostSettings[e] else { return nil }
        ghostSettings[e] = nil
        return gen == entities[e].generation ? s : nil
    }

    /// Settings of a ghost (UI tooltip).
    func ghostSettingsPreview(_ e: Int32) -> GhostSettings? {
        guard let (gen, s) = ghostSettings[e], gen == entities[e].generation else { return nil }
        return s
    }

    // MARK: Copy / paste

    /// Captures player-built (non-ghost) entities whose origin lies in `rect`, plus player-placed floor tiles.
    func captureBlueprint(_ rect: TileRect, name: String = "Blueprint") -> Blueprint {
        var entries: [Blueprint.Entry] = []
        for e in entities(in: rect) {
            let r = entities[e]
            guard r.isAlive, r.flags.contains(.playerBuilt), !r.flags.contains(.ghost), rect.contains(r.origin) else { continue }
            entries.append(Blueprint.Entry(entity: db.entities[Int(r.proto)].id, dx: r.origin.x - rect.x, dy: r.origin.y - rect.y,
                                           direction: r.direction, settings: settings(of: e)))
        }
        entries.sort { ($0.dy, $0.dx) < ($1.dy, $1.dx) }
        var tiles: [Blueprint.TileEntry] = []
        rect.forEach { p in
            let t = surface.tile(at: p)
            if t >= 0 && db.tiles[t].playerPlaced { tiles.append(Blueprint.TileEntry(tile: db.tiles[t].id, dx: p.x - rect.x, dy: p.y - rect.y)) }
        }
        // trim to the bounding box of what was captured
        var minX = Int32.max, minY = Int32.max, maxX = Int32.min, maxY = Int32.min
        for e in entries {
            let p = db.entity(e.entity)
            let pe = db.entities[p]
            let (w, h) = e.direction.isHorizontal ? (Int32(pe.height), Int32(pe.width)) : (Int32(pe.width), Int32(pe.height))
            minX = min(minX, e.dx); minY = min(minY, e.dy); maxX = max(maxX, e.dx + w); maxY = max(maxY, e.dy + h)
        }
        for t in tiles { minX = min(minX, t.dx); minY = min(minY, t.dy); maxX = max(maxX, t.dx + 1); maxY = max(maxY, t.dy + 1) }
        guard minX != Int32.max else { return Blueprint(name: name, width: 0, height: 0, entries: [], tiles: []) }
        for i in entries.indices { entries[i].dx -= minX; entries[i].dy -= minY }
        for i in tiles.indices { tiles[i].dx -= minX; tiles[i].dy -= minY }
        return Blueprint(name: name, width: maxX - minX, height: maxY - minY, entries: entries, tiles: tiles)
    }

    /// Placement preview for the UI: each entry's prototype, origin, direction and whether a ghost can go there.
    func blueprintPreview(_ bp: Blueprint, at origin: TilePos) -> [(proto: Int, origin: TilePos, direction: Direction, ok: Bool)] {
        bp.entries.compactMap { e in
            let p = db.entity(e.entity)
            guard p >= 0 else { return nil }
            let o = TilePos(origin.x + e.dx, origin.y + e.dy)
            return (p, o, e.direction, canPlace(proto: p, origin: o, direction: e.direction) == nil)
        }
    }

    /// Places ghosts for a blueprint at `origin` (top-left). Entries that can't be placed are skipped; an identical
    /// existing entity counts as done. Returns the number of ghosts created.
    @discardableResult
    func pasteBlueprint(_ bp: Blueprint, at origin: TilePos) -> Int {
        var placed = 0
        for e in bp.entries {
            let p = db.entity(e.entity)
            guard p >= 0 else { continue }
            let o = TilePos(origin.x + e.dx, origin.y + e.dy)
            if let ex = entity(at: o), Int(entities[ex].proto) == p, entities[ex].origin == o { continue }
            guard canPlace(proto: p, origin: o, direction: e.direction) == nil else { continue }
            let g = createEntity(proto: p, origin: o, direction: e.direction, flags: [.playerBuilt, .ghost])
            setGhostSettings(e.settings, for: g)
            placed += 1
        }
        return placed
    }
}
