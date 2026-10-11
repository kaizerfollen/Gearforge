// Gearforge — App / Rendering
// Coordinate conversion and small numeric helpers shared by the renderer and the input controller.
// Pure Swift (Foundation + FactoryCore only) so it can be type-checked/tested off-device.
// Owner: Rendering engineer.
//
// Conventions
//  - World space: tile units, x east, y SOUTH (FactoryCore). Tile (tx,ty) covers [tx,tx+1)×[ty,ty+1).
//  - Scene space: SpriteKit points, x east, y NORTH (up). 1 tile = 64 points (= sprite pixels at 1x).
//  - Conversion is ONLY done through `SceneMath` so the y flip lives in one place.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import FactoryCore

public enum SceneMath {
    /// Scene points per world tile.
    public static let tile: CGFloat = 64
    public static let tileD: Double = 64

    // MARK: World <-> scene

    /// World position (tile units, y south) -> scene point (y up).
    @inline(__always)
    public static func scenePoint(_ v: Vec2) -> CGPoint {
        CGPoint(x: CGFloat(v.x * tileD), y: CGFloat(-v.y * tileD))
    }

    @inline(__always)
    public static func scenePoint(x: Double, y: Double) -> CGPoint {
        CGPoint(x: CGFloat(x * tileD), y: CGFloat(-y * tileD))
    }

    /// Scene point -> world position (tile units).
    @inline(__always)
    public static func worldPoint(_ p: CGPoint) -> Vec2 {
        Vec2(Double(p.x) / tileD, -Double(p.y) / tileD)
    }

    /// Scene point -> tile containing it.
    @inline(__always)
    public static func tile(at p: CGPoint) -> TilePos {
        worldPoint(p).tile
    }

    /// Centre of a tile in scene space.
    @inline(__always)
    public static func center(of t: TilePos) -> CGPoint {
        scenePoint(x: Double(t.x) + 0.5, y: Double(t.y) + 0.5)
    }

    /// Centre of a tile rect (entity footprint) in scene space.
    @inline(__always)
    public static func center(of r: TileRect) -> CGPoint {
        scenePoint(x: Double(r.x) + Double(r.w) * 0.5, y: Double(r.y) + Double(r.h) * 0.5)
    }

    /// Scene-space rectangle of a tile rect.
    public static func sceneRect(_ r: TileRect) -> CGRect {
        CGRect(x: CGFloat(r.x) * tile, y: -CGFloat(r.maxY) * tile, width: CGFloat(r.w) * tile, height: CGFloat(r.h) * tile)
    }

    /// Smallest tile rect covering a scene-space rectangle.
    public static func tileRect(covering r: CGRect) -> TileRect {
        let x0 = Int32((Double(r.minX) / tileD).rounded(.down))
        let x1 = Int32((Double(r.maxX) / tileD).rounded(.up))
        // scene maxY is the northern (smallest world y) edge
        let y0 = Int32((-Double(r.maxY) / tileD).rounded(.down))
        let y1 = Int32((-Double(r.minY) / tileD).rounded(.up))
        return TileRect(x: x0, y: y0, w: max(0, x1 - x0), h: max(0, y1 - y0))
    }

    /// Chunk range (inclusive) covering a tile rect.
    public static func chunkRange(_ r: TileRect) -> (x0: Int32, y0: Int32, x1: Int32, y1: Int32) {
        let a = TilePos(r.x, r.y).chunk
        let b = TilePos(r.maxX - 1, r.maxY - 1).chunk
        return (a.x, a.y, b.x, b.y)
    }

    /// Tile rect of a chunk.
    @inline(__always)
    public static func chunkTileRect(_ c: ChunkPos) -> TileRect {
        let o = c.originTile
        return TileRect(x: o.x, y: o.y, w: Int32(chunkSize), h: Int32(chunkSize))
    }

    // MARK: Direction

    /// SpriteKit zRotation (radians, counter-clockwise positive) for a sprite drawn facing north.
    @inline(__always)
    public static func rotation(for d: Direction) -> CGFloat {
        switch d {
        case .north: return 0
        case .east: return -.pi / 2
        case .south: return .pi
        case .west: return .pi / 2
        }
    }

    /// 8-way facing index (0 = north, clockwise: 1 NE, 2 E, 3 SE, 4 S, 5 SW, 6 W, 7 NW) from a world vector (y south).
    public static func facing8(_ v: Vec2) -> Int {
        // angle measured clockwise from north, in world space (y south => north is -y)
        let a = atan2(v.x, -v.y)                       // -pi...pi, 0 = north, +pi/2 = east
        var idx = Int((a / (.pi / 4)).rounded())       // -4...4
        if idx < 0 { idx += 8 }
        return idx & 7
    }

    /// Direction closest to a world vector.
    public static func direction4(_ v: Vec2) -> Direction {
        if abs(v.x) >= abs(v.y) { return v.x >= 0 ? .east : .west }
        return v.y >= 0 ? .south : .north
    }

    // MARK: Depth

    /// zPosition for an object whose southern (bottom) edge is at world y `bottomY`, within a band [base, base+range).
    /// Objects further south draw on top. `mapHalfHeight` is surface.height/2.
    @inline(__always)
    public static func depth(bottomY: Double, base: CGFloat, range: CGFloat, mapHalfHeight: Double) -> CGFloat {
        let span = max(1, mapHalfHeight * 2 + 16)
        let t = (bottomY + mapHalfHeight + 8) / span                 // 0...1
        return base + range * CGFloat(min(max(t, 0), 0.9999))
    }

    // MARK: Zoom

    /// GDD §4.2: zoom 1× = 32 screen points per tile. Scene uses 64 points per tile, so camera scale = 2 / zoom.
    public static let basePointsPerTile: Double = 32
    public static func cameraScale(forZoom z: Double) -> CGFloat { CGFloat(tileD / (basePointsPerTile * z)) }
    public static func zoom(forCameraScale s: CGFloat) -> Double { tileD / (basePointsPerTile * Double(s)) }

    /// Exponential smoothing factor for a damping rate `k` (1/s) over `dt` seconds.
    @inline(__always)
    public static func damp(_ k: Double, _ dt: Double) -> Double { 1 - exp(-k * dt) }

    /// Cheap deterministic hash of a tile position (terrain variant selection).
    @inline(__always)
    public static func hash(_ x: Int32, _ y: Int32) -> UInt32 {
        var h = UInt32(bitPattern: x) &* 0x9E37_79B1
        h ^= UInt32(bitPattern: y) &* 0x85EB_CA77
        h ^= h >> 15
        h = h &* 0xC2B2_AE3D
        h ^= h >> 13
        return h
    }
}

/// Belt tiers used for sprite names.
public enum BeltTier: Int, CaseIterable, Sendable {
    case basic = 0, fast = 1, express = 2
    public var name: String {
        switch self { case .basic: return "basic"; case .fast: return "fast"; case .express: return "express" }
    }
    /// Tier from a belt-family prototype id (transport_belt / fast_* / express_*).
    public static func of(protoID id: String) -> BeltTier {
        if id.hasPrefix("express") { return .express }
        if id.hasPrefix("fast") { return .fast }
        return .basic
    }
}

/// Wall-clock helpers for frame statistics (FPS/UPS meters).
public struct RateMeter: Sendable {
    public private(set) var rate: Int = 0
    private var count = 0
    private var elapsed = 0.0
    public init() {}
    /// Adds `n` events over `dt` seconds; returns true when the published rate changed (once per second).
    public mutating func add(_ n: Int, dt: Double) -> Bool {
        count += n
        elapsed += dt
        guard elapsed >= 1 else { return false }
        let r = Int((Double(count) / elapsed).rounded())
        count = 0
        elapsed = 0
        let changed = r != rate
        rate = r
        return changed
    }
}
