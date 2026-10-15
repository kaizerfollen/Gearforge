// Gearforge — FactoryCore
// Tile map: chunks of 32×32 tiles holding terrain, resources and entity occupancy.
// Owner: Lead (structure). Map generation lives in World/MapGen (Systems engineer).

public final class Chunk {
    public let pos: ChunkPos
    /// Terrain tile prototype index per tile (row-major, 32×32).
    public var tiles: [UInt8]
    /// Resource prototype index + 1 per tile (0 = no resource).
    public var resource: [UInt8]
    /// Remaining resource amount per tile (for infinite resources: current yield amount).
    public var resourceAmount: [UInt32]
    /// Entity occupying each tile (EntityID raw index) or -1.
    public var occupancy: [Int32]
    /// Entities whose *origin* (top-left tile) lies in this chunk. Used for spatial queries & rendering.
    public var entities: [Int32] = []
    /// Explored / charted (fog of war for the map view).
    public var charted: Bool = false
    /// Incremented whenever tiles/resources change (renderer cache invalidation).
    public var revision: UInt32 = 0

    public init(pos: ChunkPos, fillTile: UInt8) {
        self.pos = pos
        let n = chunkSize * chunkSize
        tiles = Array(repeating: fillTile, count: n)
        resource = Array(repeating: 0, count: n)
        resourceAmount = Array(repeating: 0, count: n)
        occupancy = Array(repeating: -1, count: n)
    }
}

public final class Surface {
    /// Map size in tiles. Valid tiles: x in [-width/2, width/2), y in [-height/2, height/2).
    public let width: Int
    public let height: Int
    public let chunksX: Int
    public let chunksY: Int
    /// Chunk storage, row-major over chunk coordinates offset by (chunksX/2, chunksY/2). nil = not generated yet.
    public private(set) var chunks: [Chunk?]
    /// Called to generate a chunk on first access (installed by MapGenerator).
    public var generator: ((ChunkPos) -> Chunk)?
    /// Called right after a freshly generated chunk is installed (spawn trees/rocks as entities here; the chunk is
    /// already accessible so entity creation inside it does not recurse into generation).
    public var postGenerate: ((Chunk) -> Void)?
    public let bounds: TileRect

    public init(width: Int, height: Int) {
        precondition(width % chunkSize == 0 && height % chunkSize == 0, "map size must be a multiple of 32")
        self.width = width; self.height = height
        chunksX = width / chunkSize; chunksY = height / chunkSize
        chunks = Array(repeating: nil, count: chunksX * chunksY)
        // Bounds = exactly the tiles the chunk grid covers. With an odd chunk count (L1: 160 = 5 chunks) the old
        // centred bounds (-80..<80) included 16 columns no chunk backs (black void you could walk into) and left out
        // 16 that a chunk does back; chunk slots run from -(chunks/2), so the bounds start there too.
        bounds = TileRect(x: Int32(-(chunksX / 2) * chunkSize), y: Int32(-(chunksY / 2) * chunkSize),
                          w: Int32(width), h: Int32(height))
    }

    @inlinable public func isInBounds(_ p: TilePos) -> Bool { bounds.contains(p) }

    @inline(__always) func chunkSlot(_ c: ChunkPos) -> Int? {
        let ix = Int(c.x) + chunksX / 2, iy = Int(c.y) + chunksY / 2
        guard ix >= 0, iy >= 0, ix < chunksX, iy < chunksY else { return nil }
        return iy * chunksX + ix
    }

    /// Returns the chunk, generating it if needed. nil if outside the map.
    public func chunk(_ c: ChunkPos) -> Chunk? {
        guard let slot = chunkSlot(c) else { return nil }
        if let ch = chunks[slot] { return ch }
        guard let gen = generator else { return nil }
        let ch = gen(c)
        chunks[slot] = ch
        postGenerate?(ch)
        return ch
    }

    /// Returns the chunk only if already generated (never triggers generation; safe for rendering queries).
    public func existingChunk(_ c: ChunkPos) -> Chunk? {
        guard let slot = chunkSlot(c) else { return nil }
        return chunks[slot]
    }

    /// Installs a chunk (used by save loading and map generation).
    public func setChunk(_ ch: Chunk) {
        guard let slot = chunkSlot(ch.pos) else { return }
        chunks[slot] = ch
    }

    public var generatedChunks: [Chunk] { chunks.compactMap { $0 } }

    /// Drops every generated chunk. Used by save loading to reset a freshly constructed World (whose setUp may have
    /// generated chunks around spawn) before installing the saved chunks with `setChunk`. [Progression, additive]
    public func removeAllChunks() {
        for i in chunks.indices { chunks[i] = nil }
    }

    @inlinable public func chunk(at p: TilePos) -> Chunk? { chunk(p.chunk) }

    // MARK: Tile accessors (generate on demand)

    public func tile(at p: TilePos) -> TileIndex {
        guard let ch = chunk(at: p) else { return -1 }
        return Int(ch.tiles[p.localIndex])
    }
    public func setTile(at p: TilePos, _ t: TileIndex) {
        guard let ch = chunk(at: p) else { return }
        ch.tiles[p.localIndex] = UInt8(t); ch.revision &+= 1
    }
    /// Resource index at tile (or -1) and amount.
    public func resource(at p: TilePos) -> (ResourceIndex, UInt32) {
        guard let ch = chunk(at: p) else { return (-1, 0) }
        let i = p.localIndex
        return (Int(ch.resource[i]) - 1, ch.resourceAmount[i])
    }
    /// Resource patch around `p`: tiles of the same resource connected (4-neighbour) to it, and their total amount.
    /// Stops after `limit` tiles (`complete == false`), so the cost stays bounded for huge patches.
    public func resourcePatch(at p: TilePos, limit: Int = 6000) -> (resource: ResourceIndex, tiles: Int, total: Int, complete: Bool) {
        let (r, a) = resource(at: p)
        guard r >= 0, a > 0 else { return (-1, 0, 0, true) }
        var seen: Set<TilePos> = [p]
        var stack = [p]
        var total = 0
        while let t = stack.popLast() {
            total += Int(resource(at: t).1)
            if seen.count >= limit { return (r, seen.count, total, false) }
            for n in [TilePos(t.x + 1, t.y), TilePos(t.x - 1, t.y), TilePos(t.x, t.y + 1), TilePos(t.x, t.y - 1)]
            where !seen.contains(n) && isInBounds(n) {
                let (rn, an) = resource(at: n)
                if rn == r && an > 0 { seen.insert(n); stack.append(n) }
            }
        }
        return (r, seen.count, total, true)
    }

    public func setResource(at p: TilePos, _ r: ResourceIndex, amount: UInt32) {
        guard let ch = chunk(at: p) else { return }
        let i = p.localIndex
        ch.resource[i] = r < 0 || amount == 0 ? 0 : UInt8(r + 1)
        ch.resourceAmount[i] = r < 0 ? 0 : amount
        ch.revision &+= 1
    }
    /// Entity raw index occupying the tile, or -1.
    @inlinable public func occupant(at p: TilePos) -> Int32 {
        guard let ch = chunk(at: p) else { return -1 }
        return ch.occupancy[p.localIndex]
    }
    public func setOccupant(at p: TilePos, _ e: Int32) {
        guard let ch = chunk(at: p) else { return }
        ch.occupancy[p.localIndex] = e
    }
}
