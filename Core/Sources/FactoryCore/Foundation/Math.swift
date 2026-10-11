// Gearforge — FactoryCore
// Basic geometry types. Owner: Lead (shared). Additive changes only.

/// Simulation ticks per second. All per-tick values assume this rate.
public let ticksPerSecond: Int = 60
public let chunkSize: Int = 32
public let chunkShift: Int = 5
public let chunkMask: Int = 31

/// Integer tile coordinate. World origin (0,0) is the map centre; x grows east, y grows south.
public struct TilePos: Hashable, Codable, Sendable, CustomStringConvertible {
    public var x: Int32
    public var y: Int32
    @inlinable public init(_ x: Int32, _ y: Int32) { self.x = x; self.y = y }
    @inlinable public init(_ x: Int, _ y: Int) { self.x = Int32(x); self.y = Int32(y) }
    @inlinable public static func + (a: TilePos, b: TilePos) -> TilePos { TilePos(a.x &+ b.x, a.y &+ b.y) }
    @inlinable public static func - (a: TilePos, b: TilePos) -> TilePos { TilePos(a.x &- b.x, a.y &- b.y) }
    @inlinable public func offset(_ d: Direction, _ n: Int32 = 1) -> TilePos {
        let v = d.vector
        return TilePos(x &+ v.x &* n, y &+ v.y &* n)
    }
    public var description: String { "(\(x),\(y))" }
    @inlinable public var chunk: ChunkPos { ChunkPos(Int32(Int(x) >> chunkShift), Int32(Int(y) >> chunkShift)) }
    @inlinable public var localIndex: Int { (Int(y) & chunkMask) << chunkShift | (Int(x) & chunkMask) }
}

public struct ChunkPos: Hashable, Codable, Sendable {
    public var x: Int32
    public var y: Int32
    @inlinable public init(_ x: Int32, _ y: Int32) { self.x = x; self.y = y }
    @inlinable public var originTile: TilePos { TilePos(x << Int32(chunkShift), y << Int32(chunkShift)) }
}

/// Four-way direction. Raw values are stable (saved to disk).
public enum Direction: UInt8, Codable, CaseIterable, Sendable {
    case north = 0, east = 1, south = 2, west = 3

    @inlinable public var vector: TilePos {
        switch self {
        case .north: return TilePos(0, -1)
        case .east: return TilePos(1, 0)
        case .south: return TilePos(0, 1)
        case .west: return TilePos(-1, 0)
        }
    }
    @inlinable public var opposite: Direction { Direction(rawValue: (rawValue + 2) & 3)! }
    @inlinable public var clockwise: Direction { Direction(rawValue: (rawValue + 1) & 3)! }
    @inlinable public var counterClockwise: Direction { Direction(rawValue: (rawValue + 3) & 3)! }
    @inlinable public var isHorizontal: Bool { self == .east || self == .west }

    /// Rotate a vector given in "north-facing" prototype space into this direction.
    @inlinable public func rotate(_ v: Vec2) -> Vec2 {
        switch self {
        case .north: return v
        case .east: return Vec2(-v.y, v.x)
        case .south: return Vec2(-v.x, -v.y)
        case .west: return Vec2(v.y, -v.x)
        }
    }
    @inlinable public func rotate(_ v: TilePos) -> TilePos {
        switch self {
        case .north: return v
        case .east: return TilePos(-v.y, v.x)
        case .south: return TilePos(-v.x, -v.y)
        case .west: return TilePos(v.y, -v.x)
        }
    }
}

/// Continuous 2D vector in tile units (used for character, inserter arms, rendering hints).
public struct Vec2: Hashable, Codable, Sendable {
    public var x: Double
    public var y: Double
    @inlinable public init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
    public static let zero = Vec2(0, 0)
    @inlinable public static func + (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x + b.x, a.y + b.y) }
    @inlinable public static func - (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x - b.x, a.y - b.y) }
    @inlinable public static func * (a: Vec2, s: Double) -> Vec2 { Vec2(a.x * s, a.y * s) }
    @inlinable public var length: Double { (x * x + y * y).squareRoot() }
    @inlinable public func distance(to o: Vec2) -> Double { (self - o).length }
    @inlinable public var tile: TilePos { TilePos(Int32(x.rounded(.down)), Int32(y.rounded(.down))) }
}

/// Axis-aligned integer tile rectangle, half-open: [x, x+w) × [y, y+h).
public struct TileRect: Hashable, Codable, Sendable {
    public var x: Int32, y: Int32, w: Int32, h: Int32
    @inlinable public init(x: Int32, y: Int32, w: Int32, h: Int32) { self.x = x; self.y = y; self.w = w; self.h = h }
    @inlinable public init(origin: TilePos, w: Int, h: Int) { self.init(x: origin.x, y: origin.y, w: Int32(w), h: Int32(h)) }
    @inlinable public var maxX: Int32 { x + w }
    @inlinable public var maxY: Int32 { y + h }
    @inlinable public var center: Vec2 { Vec2(Double(x) + Double(w) / 2, Double(y) + Double(h) / 2) }
    @inlinable public func contains(_ p: TilePos) -> Bool { p.x >= x && p.y >= y && p.x < maxX && p.y < maxY }
    @inlinable public func intersects(_ o: TileRect) -> Bool { x < o.maxX && o.x < maxX && y < o.maxY && o.y < maxY }
    @inlinable public func expanded(by n: Int32) -> TileRect { TileRect(x: x - n, y: y - n, w: w + 2 * n, h: h + 2 * n) }
    /// Iterate every tile in the rect, row-major.
    @inlinable public func forEach(_ body: (TilePos) throws -> Void) rethrows {
        var yy = y
        while yy < maxY { var xx = x; while xx < maxX { try body(TilePos(xx, yy)); xx += 1 }; yy += 1 }
    }
}
