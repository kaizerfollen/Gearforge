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

    /// RGBA8 pixels (premultiplied-free, alpha 255) for the map area starting at tile (`x0`, `y0`), `w`×`h` pixels,
    /// one pixel per `step`×`step` tiles (top-left sample). Same colours as `mapColor`; uncharted / out of map → black.
    /// Bulk path for the minimap and the map screen (chunk lookups cached along each row).
    func mapRGBA(x0: Int32, y0: Int32, w: Int, h: Int, step: Int32 = 1) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: w * h * 4)
        for i in 0..<(w * h) { out[i * 4 + 3] = 255 }
        func u8(_ v: Double) -> UInt8 { UInt8(max(0, min(255, (v * 255).rounded()))) }
        func rgb(_ c: [Double]) -> (UInt8, UInt8, UInt8)? { c.count >= 3 ? (u8(c[0]), u8(c[1]), u8(c[2])) : nil }
        let tileC = db.tiles.map { rgb($0.mapColor) ?? (51, 51, 51) }
        let resC = db.resources.map { rgb($0.mapColor) }
        for py in 0..<h {
            let ty = y0 + Int32(py) * step
            var lastPos: ChunkPos? = nil
            var lastChunk: Chunk? = nil
            for px in 0..<w {
                let p = TilePos(x0 + Int32(px) * step, ty)
                let cp = p.chunk
                if cp != lastPos { lastPos = cp; lastChunk = surface.existingChunk(cp) }
                guard let ch = lastChunk, ch.charted else { continue }
                let c: (UInt8, UInt8, UInt8)
                if entity(at: p) != nil {
                    let m = mapColor(at: p)
                    c = (u8(m.0), u8(m.1), u8(m.2))
                } else {
                    let li = p.localIndex
                    let res = Int(ch.resource[li]) - 1
                    if res >= 0, let rc = resC[res] { c = rc }
                    else { let t = Int(ch.tiles[li]); c = t < tileC.count ? tileC[t] : (51, 51, 51) }
                }
                let o = (py * w + px) * 4
                out[o] = c.0; out[o + 1] = c.1; out[o + 2] = c.2
            }
        }
        return out
    }
}
