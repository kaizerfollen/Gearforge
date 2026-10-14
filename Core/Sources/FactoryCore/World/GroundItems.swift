// Gearforge — FactoryCore
// Items lying on the ground (Factorio "item-on-ground"): spilled when the player's inventory is full, dropped by
// inserters/drills with nothing in front of them, picked up by the player (auto-loot nearby / explicit pickup) and by
// inserters whose pickup tile is empty. Stored sparsely per tile. Owner: Lead.

public final class GroundItems {
    public unowned let world: World
    init(world: World) { self.world = world }

    /// Max items lying on one tile (spill spreads over neighbouring tiles beyond this).
    public static let perTile = 8
    /// Auto-loot radius around the character (tiles).
    public static let autoLootRadius = 1.5

    private(set) var tiles: [TilePos: [ItemStack]] = [:]
    /// Total item count on the ground (stats / UI).
    public private(set) var totalCount = 0
    /// Bumped on every change (renderer re-sync).
    public private(set) var revision = 0

    public var isEmpty: Bool { tiles.isEmpty }

    public func items(at p: TilePos) -> [ItemStack] { tiles[p] ?? [] }
    public func count(at p: TilePos) -> Int { (tiles[p] ?? []).reduce(0) { $0 + Int($1.count) } }

    /// Can items be put on this tile (land, in bounds, no solid entity)?
    public func canHold(_ p: TilePos) -> Bool {
        guard world.surface.isInBounds(p) else { return false }
        let t = world.surface.tile(at: p)
        if t >= 0 && world.db.tiles[t].isWater { return false }
        if let e = world.entity(at: p) {
            let k = world.entities[e].kind
            if !(world.entities[e].flags.contains(.ghost) || k == .tree) { return false }
        }
        return true
    }

    /// Adds up to `count` items on one tile (respecting `perTile`); returns how many were placed.
    @discardableResult
    public func add(item: Int, count: Int, at p: TilePos) -> Int {
        guard count > 0, item >= 0, canHold(p) else { return 0 }
        let room = Self.perTile - self.count(at: p)
        let n = min(room, count)
        guard n > 0 else { return 0 }
        var list = tiles[p] ?? []
        if let i = list.firstIndex(where: { Int($0.item) == item }) { list[i].count += Int32(n) } else { list.append(ItemStack(item: item, count: n)) }
        tiles[p] = list
        totalCount += n
        revision &+= 1
        return n
    }

    /// Spills stacks around a point, spiralling outwards (radius ≤ 12). Returns items that could not be placed.
    @discardableResult
    public func spill(_ stacks: [ItemStack], near pos: Vec2) -> Int {
        var pending = stacks.filter { !$0.isEmpty }
        guard !pending.isEmpty else { return 0 }
        let c = pos.tile
        var r: Int32 = 0
        while r <= 12 && !pending.isEmpty {
            for p in ring(c, r) where !pending.isEmpty {
                guard canHold(p) else { continue }
                var i = 0
                while i < pending.count {
                    let placed = add(item: Int(pending[i].item), count: Int(pending[i].count), at: p)
                    pending[i].count -= Int32(placed)
                    if pending[i].count <= 0 { pending.remove(at: i) } else { i += 1 }
                    if count(at: p) >= Self.perTile { break }
                }
            }
            r += 1
        }
        let lost = pending.reduce(0) { $0 + Int($1.count) }
        if lost > 0 { world.emit(.alert("Items lost — no room on the ground")) }
        return lost
    }

    /// Tiles at Chebyshev distance exactly r, in deterministic order.
    private func ring(_ c: TilePos, _ r: Int32) -> [TilePos] {
        if r == 0 { return [c] }
        var out: [TilePos] = []
        for x in (c.x - r)...(c.x + r) { out.append(TilePos(x, c.y - r)); out.append(TilePos(x, c.y + r)) }
        for y in (c.y - r + 1)...(c.y + r - 1) { out.append(TilePos(c.x - r, y)); out.append(TilePos(c.x + r, y)) }
        return out
    }

    /// Takes one item matching `filter` from a tile (inserter pickup). Returns the item or -1.
    public func takeOne(at p: TilePos, filter: (Int) -> Bool) -> Int {
        guard var list = tiles[p] else { return -1 }
        for i in list.indices where filter(Int(list[i].item)) {
            let it = Int(list[i].item)
            list[i].count -= 1
            if list[i].count <= 0 { list.remove(at: i) }
            tiles[p] = list.isEmpty ? nil : list
            totalCount -= 1
            revision &+= 1
            return it
        }
        return -1
    }

    /// Removes and returns everything on a tile.
    public func takeAll(at p: TilePos) -> [ItemStack] {
        guard let list = tiles.removeValue(forKey: p) else { return [] }
        totalCount -= list.reduce(0) { $0 + Int($1.count) }
        revision &+= 1
        return list
    }

    /// Moves items lying inside `rect` out of the way (building over them): into the player's inventory, the rest
    /// spilled around the rect.
    public func clear(_ rect: TileRect) {
        guard !tiles.isEmpty else { return }
        var leftovers: [ItemStack] = []
        rect.forEach { p in
            for s in takeAll(at: p) {
                let fit = world.player.give(Int(s.item), Int(s.count))
                if fit < Int(s.count) { leftovers.append(ItemStack(item: s.item, count: s.count - Int32(fit))) }
            }
        }
        if !leftovers.isEmpty { spill(leftovers, near: Vec2(Double(rect.maxX) + 0.5, Double(rect.maxY) + 0.5)) }
    }

    /// Items in a rect, sorted (renderer).
    public func forEach(in rect: TileRect, _ body: (TilePos, [ItemStack]) -> Void) {
        if Int(rect.w) * Int(rect.h) < tiles.count {
            rect.forEach { p in if let l = tiles[p] { body(p, l) } }
        } else {
            for (p, l) in tiles where rect.contains(p) { body(p, l) }
        }
    }

    // MARK: Persistence

    func serialize(to w: inout BinaryWriter) {
        w.write(UInt8(1))
        let keys = tiles.keys.sorted { ($0.y, $0.x) < ($1.y, $1.x) }
        w.writeVarInt(keys.count)
        for k in keys {
            w.write(k)
            let l = tiles[k]!
            w.writeVarInt(l.count)
            for s in l { w.write(s.item); w.write(s.count) }
        }
    }

    func deserialize(from r: inout BinaryReader) throws {
        _ = try r.read(UInt8.self)
        tiles = [:]; totalCount = 0
        let n = try r.readVarInt()
        for _ in 0..<n {
            let p = try r.readTilePos()
            let m = try r.readVarInt()
            var l: [ItemStack] = []
            for _ in 0..<m {
                let s = ItemStack(item: try r.read(Int32.self), count: try r.read(Int32.self))
                l.append(s); totalCount += Int(s.count)
            }
            tiles[p] = l
        }
        revision &+= 1
    }
}
