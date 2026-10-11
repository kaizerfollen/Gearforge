// Gearforge — App / Rendering
// Pure pixel composition for baked terrain chunks and map-mode chunk images. Runs on a background queue:
// everything here is value types / immutable data (no SpriteKit, no UIKit).
// Pixel format: RGBA8 premultiplied, packed little-endian as R | G<<8 | B<<16 | A<<24, i.e. memory bytes R,G,B,A
// (= CGImageAlphaInfo.premultipliedLast with default byte order). Row 0 = northern-most row (top of the image).
// Owner: Rendering engineer.

import Foundation
import FactoryCore

public enum PixelColor {
    @inline(__always)
    public static func pack(r: UInt8, g: UInt8, b: UInt8, a: UInt8 = 255) -> UInt32 {
        UInt32(r) | UInt32(g) << 8 | UInt32(b) << 16 | UInt32(a) << 24
    }
    /// From a 0...1 RGB array (prototype mapColor), opaque.
    public static func from(_ c: [Double], brightness: Double = 1) -> UInt32 {
        func ch(_ i: Int) -> UInt8 {
            let v = (i < c.count ? c[i] : 0) * brightness
            return UInt8(max(0, min(255, (v * 255).rounded())))
        }
        return pack(r: ch(0), g: ch(1), b: ch(2))
    }
    @inline(__always)
    public static func scale(_ c: UInt32, _ f: Double) -> UInt32 {
        func s(_ shift: UInt32) -> UInt32 { UInt32(max(0, min(255, (Double((c >> shift) & 0xFF) * f).rounded()))) << shift }
        return s(0) | s(8) | s(16) | (c & 0xFF00_0000)
    }
    /// Premultiplied source-over.
    @inline(__always)
    public static func over(_ s: UInt32, _ d: UInt32) -> UInt32 {
        let sa = s >> 24
        if sa == 255 { return s }
        if sa == 0 { return d }
        let inv = 255 - sa
        @inline(__always) func ch(_ shift: UInt32) -> UInt32 {
            let v = ((s >> shift) & 0xFF) + (((d >> shift) & 0xFF) * inv + 127) / 255
            return min(255, v) << shift
        }
        return ch(0) | ch(8) | ch(16) | ch(24)
    }
}

/// Immutable copy of the chunk data a bake needs (taken on the main thread, consumed on the bake queue).
public struct ChunkSnapshot: Sendable {
    public var pos: ChunkPos
    public var revision: UInt32
    public var tiles: [UInt8]
    public var resource: [UInt8]
    public var resourceAmount: [UInt32]
    public init(pos: ChunkPos, revision: UInt32, tiles: [UInt8], resource: [UInt8], resourceAmount: [UInt32]) {
        self.pos = pos; self.revision = revision; self.tiles = tiles; self.resource = resource
        self.resourceAmount = resourceAmount
    }
}

/// Source pixels for one level of detail (pixels per tile). Built once on the main thread, then read-only.
public final class TerrainPalette: @unchecked Sendable {
    public let ppt: Int
    /// [tileIndex][variant] -> ppt*ppt pixels. Empty variant list = use `tileColors` with per-tile noise.
    public let tileVariants: [[[UInt32]]]
    public let tileColors: [UInt32]
    /// [resourceIndex][stage] -> ppt*ppt pixels (with alpha). Empty = draw a coloured dot pattern.
    public let oreStages: [[[UInt32]]]
    public let oreColors: [UInt32]
    public let oreInfinite: [Bool]

    public init(ppt: Int, tileVariants: [[[UInt32]]], tileColors: [UInt32], oreStages: [[[UInt32]]], oreColors: [UInt32],
                oreInfinite: [Bool]) {
        self.ppt = ppt; self.tileVariants = tileVariants; self.tileColors = tileColors
        self.oreStages = oreStages; self.oreColors = oreColors; self.oreInfinite = oreInfinite
    }
}

public enum TerrainBaker {
    /// Amount thresholds for the 8 visual ore stages (stage k shown when amount >= thresholds[k]).
    public static let stageThresholds: [UInt32] = [1, 120, 300, 600, 1_000, 1_800, 3_500, 7_000]

    /// Visual ore stage 0..<stageCount for an amount.
    @inline(__always)
    public static func oreStage(amount: UInt32, stageCount: Int, infinite: Bool) -> Int {
        guard stageCount > 1, !infinite else { return 0 }
        var s8 = 0
        for (k, t) in stageThresholds.enumerated() where amount >= t { s8 = k }
        return min(stageCount - 1, s8 * stageCount / stageThresholds.count)
    }

    /// Per-tile visual signature (tile index, ore stage) — a re-bake is only needed when this changes, even if the
    /// chunk revision moved (drills deplete ore every few ticks but stages change rarely).
    public static func signature(_ s: ChunkSnapshot, palette: TerrainPalette) -> [UInt16] {
        let n = chunkSize * chunkSize
        var out = [UInt16](repeating: 0, count: n)
        for i in 0..<n {
            let r = Int(s.resource[i]) - 1
            var stage = 0xFF
            if r >= 0 {
                let count = r < palette.oreStages.count ? max(1, palette.oreStages[r].count) : 1
                let inf = r < palette.oreInfinite.count ? palette.oreInfinite[r] : false
                stage = (r << 4) | oreStage(amount: s.resourceAmount[i], stageCount: count, infinite: inf)
            }
            out[i] = UInt16(s.tiles[i]) << 8 | UInt16(stage & 0xFF)
        }
        return out
    }

    /// Bakes a full chunk: (32*ppt)² pixels, row 0 = north.
    public static func bake(_ s: ChunkSnapshot, palette: TerrainPalette) -> [UInt32] {
        let ppt = palette.ppt
        let side = chunkSize * ppt
        var out = [UInt32](repeating: 0xFF00_0000, count: side * side)
        let origin = s.pos.originTile
        out.withUnsafeMutableBufferPointer { dst in
            guard let base = dst.baseAddress else { return }
            for ty in 0..<chunkSize {
                for tx in 0..<chunkSize {
                    let i = ty * chunkSize + tx
                    let wx = origin.x + Int32(tx), wy = origin.y + Int32(ty)
                    let h = SceneMath.hash(wx, wy)
                    let t = Int(s.tiles[i])
                    let px0 = tx * ppt, py0 = ty * ppt
                    // Terrain
                    if t < palette.tileVariants.count, !palette.tileVariants[t].isEmpty {
                        let vars = palette.tileVariants[t]
                        let src = vars[Int(h % UInt32(vars.count))]
                        src.withUnsafeBufferPointer { sp in
                            guard let sb = sp.baseAddress else { return }
                            for row in 0..<ppt {
                                (base + (py0 + row) * side + px0).update(from: sb + row * ppt, count: ppt)
                            }
                        }
                    } else {
                        let c0 = t < palette.tileColors.count ? palette.tileColors[t] : 0xFF20_4020
                        let c = PixelColor.scale(c0, 0.94 + Double(h & 0xFF) / 255 * 0.12)
                        for row in 0..<ppt {
                            let p = base + (py0 + row) * side + px0
                            p.update(repeating: c, count: ppt)
                        }
                    }
                    // Resource overlay
                    let r = Int(s.resource[i]) - 1
                    guard r >= 0 else { continue }
                    let inf = r < palette.oreInfinite.count ? palette.oreInfinite[r] : false
                    if r < palette.oreStages.count, !palette.oreStages[r].isEmpty {
                        let stages = palette.oreStages[r]
                        let src = stages[oreStage(amount: s.resourceAmount[i], stageCount: stages.count, infinite: inf)]
                        // Mirror horizontally on odd hashes for variety.
                        let flip = (h >> 9) & 1 == 1
                        for row in 0..<ppt {
                            let drow = base + (py0 + row) * side + px0
                            let srow = row * ppt
                            for col in 0..<ppt {
                                let sc = src[srow + (flip ? ppt - 1 - col : col)]
                                if sc >> 24 != 0 { drow[col] = PixelColor.over(sc, drow[col]) }
                            }
                        }
                    } else {
                        // Fallback: a few ore "nuggets" in the resource colour, count by stage.
                        let col = r < palette.oreColors.count ? palette.oreColors[r] : 0xFF80_8080
                        let stage = oreStage(amount: s.resourceAmount[i], stageCount: 8, infinite: inf)
                        let nuggets = inf ? 1 : 1 + stage / 2
                        let ns = max(1, ppt / 5)
                        var hh = h
                        for _ in 0..<nuggets {
                            hh = hh &* 1_103_515_245 &+ 12_345
                            let nx = Int((hh >> 8) % UInt32(max(1, ppt - ns))), ny = Int((hh >> 20) % UInt32(max(1, ppt - ns)))
                            for yy in 0..<ns { (base + (py0 + ny + yy) * side + px0 + nx).update(repeating: col, count: ns) }
                        }
                    }
                }
            }
        }
        return out
    }

    /// Map-mode chunk image: 1 pixel per tile (32×32), row 0 = north. `entityColor` gives a colour for an occupied
    /// tile (nil = show terrain).
    public static func mapPixels(_ s: ChunkSnapshot, occupancy: [Int32], palette: TerrainPalette,
                                 entityColor: (Int32) -> UInt32?) -> [UInt32] {
        let n = chunkSize * chunkSize
        var out = [UInt32](repeating: 0xFF00_0000, count: n)
        for i in 0..<n {
            let e = i < occupancy.count ? occupancy[i] : -1
            if e >= 0, let c = entityColor(e) { out[i] = c; continue }
            let r = Int(s.resource[i]) - 1
            if r >= 0 && r < palette.oreColors.count { out[i] = palette.oreColors[r]; continue }
            let t = Int(s.tiles[i])
            out[i] = t < palette.tileColors.count ? palette.tileColors[t] : 0xFF20_4020
        }
        return out
    }
}
