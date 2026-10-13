// Gearforge — FactoryCore
// Map charting / fog of war (GDD §5.1 Map: "radar-revealed areas only"). A chunk is charted when the character has
// been near it or a powered radar has scanned it. Charting a far chunk generates it (exploration).
// Owner: Lead.

public extension World {
    /// Chunks around the character that are always charted (radius in chunks).
    static let characterChartRadius: Int32 = 2

    /// Marks a chunk charted (generating it if needed). Returns true if it was newly charted.
    @discardableResult
    func chart(_ c: ChunkPos) -> Bool {
        guard let ch = surface.chunk(c), !ch.charted else { return false }
        ch.charted = true
        emit(.chunkCharted(c))
        return true
    }

    /// Charts every chunk within `radius` chunks of `center` (square).
    func chartArea(around center: ChunkPos, radius: Int32) {
        var y = center.y - radius
        while y <= center.y + radius {
            var x = center.x - radius
            while x <= center.x + radius { chart(ChunkPos(x, y)); x += 1 }
            y += 1
        }
    }

    func isCharted(_ c: ChunkPos) -> Bool { surface.existingChunk(c)?.charted ?? false }

    /// Number of charted chunks (stats/UI).
    var chartedChunkCount: Int { surface.generatedChunks.reduce(0) { $0 + ($1.charted ? 1 : 0) } }

    /// Minimap colour of a tile (RGB 0...1): entity > resource > terrain. Uncharted → black.
    func mapColor(at p: TilePos) -> (Double, Double, Double) {
        guard let ch = surface.existingChunk(p.chunk), ch.charted else { return (0, 0, 0) }
        if let e = entity(at: p) {
            let r = entities[e]
            switch r.kind {
            case .tree: return (0.16, 0.32, 0.14)
            case .rock: return (0.45, 0.42, 0.38)
            case .transportBelt, .undergroundBelt, .splitter: return (0.85, 0.7, 0.2)
            case .pipe, .pipeToGround, .storageTank, .pump: return (0.3, 0.45, 0.75)
            case .electricPole: return (0.6, 0.55, 0.4)
            default: return (0.55, 0.6, 0.65)
            }
        }
        let i = p.localIndex
        let res = Int(ch.resource[i]) - 1
        if res >= 0 {
            let c = db.resources[res].mapColor
            if c.count >= 3 { return (c[0], c[1], c[2]) }
        }
        let t = Int(ch.tiles[i])
        if t < db.tiles.count {
            let c = db.tiles[t].mapColor
            if c.count >= 3 { return (c[0], c[1], c[2]) }
        }
        return (0.2, 0.2, 0.2)
    }
}
