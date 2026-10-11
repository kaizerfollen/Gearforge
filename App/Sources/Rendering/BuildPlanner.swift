// Gearforge — App / Rendering
// Pure placement planning for the touch build tools (GDD §4.4): entity origin under the finger, 4-connected drag
// paths, belt directions + automatic underground insertion, pole spacing, rows, tile brushes, pipe connection masks.
// Foundation + FactoryCore only (type-checkable off-device). Owner: Rendering engineer.

import Foundation
import FactoryCore

/// One planned placement produced by a drag tool.
public struct PlannedPlacement: Equatable, Sendable {
    public enum Role: Equatable, Sendable { case normal, undergroundEntrance, undergroundExit }
    /// Item used to place it (the item the player has selected, or the matching underground item).
    public var item: Int
    /// Entity prototype placed.
    public var proto: Int
    public var origin: TilePos
    public var direction: Direction
    public var role: Role = .normal
    /// False when the planner already knows this spot is unbuildable (shown red, skipped on commit).
    public var plannedValid: Bool = true

    public init(item: Int, proto: Int, origin: TilePos, direction: Direction, role: Role = .normal, plannedValid: Bool = true) {
        self.item = item; self.proto = proto; self.origin = origin; self.direction = direction
        self.role = role; self.plannedValid = plannedValid
    }
}

/// A 4-connected tile path that follows the finger. Backtracking over the previous tile removes the last step;
/// re-entering an earlier tile truncates the path there (a belt can't occupy a tile twice).
public struct DragPath: Equatable, Sendable {
    public private(set) var tiles: [TilePos] = []
    public var maxLength = 512

    public init() {}
    public init(start: TilePos) { tiles = [start] }

    public var last: TilePos? { tiles.last }
    public var isEmpty: Bool { tiles.isEmpty }

    /// Extends the path toward tile `t`, inserting intermediate tiles for fast finger movement.
    /// Returns true if the path changed.
    @discardableResult
    public mutating func extend(to t: TilePos) -> Bool {
        guard let start = tiles.last else { tiles = [t]; return true }
        if t == start { return false }
        let before = tiles
        var guardSteps = 0
        while let cur = tiles.last, cur != t, guardSteps < 4096 {
            guardSteps += 1
            let dx = Int(t.x) - Int(cur.x), dy = Int(t.y) - Int(cur.y)
            // Prefer continuing along the current heading on ties to keep long straight runs.
            var stepX: Bool
            if abs(dx) != abs(dy) { stepX = abs(dx) > abs(dy) }
            else if tiles.count >= 2 { stepX = tiles[tiles.count - 1].y == tiles[tiles.count - 2].y }
            else { stepX = true }
            if dx == 0 { stepX = false }
            if dy == 0 { stepX = true }
            let next = stepX ? TilePos(cur.x + (dx > 0 ? 1 : -1), cur.y) : TilePos(cur.x, cur.y + (dy > 0 ? 1 : -1))
            if let k = tiles.firstIndex(of: next) {
                tiles.removeSubrange((k + 1)...)            // backtrack / loop: truncate
            } else {
                if tiles.count >= maxLength { break }
                tiles.append(next)
            }
        }
        return tiles != before
    }

    /// Direction each tile should face: toward the next tile; the last tile keeps the previous heading.
    /// A single-tile path uses `fallback`.
    public func directions(fallback: Direction) -> [Direction] {
        guard tiles.count > 1 else { return tiles.isEmpty ? [] : [fallback] }
        var out: [Direction] = []
        out.reserveCapacity(tiles.count)
        for i in 0..<(tiles.count - 1) { out.append(BuildPlanner.step(from: tiles[i], to: tiles[i + 1]) ?? fallback) }
        out.append(out.last ?? fallback)
        return out
    }
}

public enum BuildPlanner {
    /// Max placements a single drag may produce (preview pool size / command burst limit).
    public static let maxPlacements = 200

    /// Origin (top-left tile) of a w×h footprint whose centre is nearest to world point `p`.
    public static func origin(w: Int, h: Int, at p: Vec2) -> TilePos {
        TilePos(Int32((p.x - Double(w) / 2 + 0.5).rounded(.down)), Int32((p.y - Double(h) / 2 + 0.5).rounded(.down)))
    }

    /// Direction of a unit step between adjacent tiles (nil if not adjacent).
    public static func step(from a: TilePos, to b: TilePos) -> Direction? {
        switch (b.x - a.x, b.y - a.y) {
        case (0, -1): return .north
        case (1, 0): return .east
        case (0, 1): return .south
        case (-1, 0): return .west
        default: return nil
        }
    }

    // MARK: Belts

    /// Belt placements along a path. Tiles whose `isBlocked` is true (non-belt obstacle / water) are bridged by an
    /// underground pair when `underground` is given (entrance on the last free tile before the obstacle, exit on the
    /// first free tile after it, within `maxDistance` and on a straight run). Otherwise they are marked invalid.
    /// `existingSame` returns true when an identical belt (same proto, same direction) already stands there; such
    /// tiles are skipped (joining existing belts).
    public static func beltPlacements(path: DragPath, fallbackDirection: Direction, item: Int, proto: Int,
                                      underground: (item: Int, proto: Int, maxDistance: Int)?,
                                      isBlocked: (TilePos) -> Bool,
                                      existingSame: (TilePos, Direction) -> Bool) -> [PlannedPlacement] {
        let tiles = path.tiles
        let dirs = path.directions(fallback: fallbackDirection)
        var out: [PlannedPlacement] = []
        out.reserveCapacity(min(tiles.count, maxPlacements))
        var i = 0
        while i < tiles.count && out.count < maxPlacements {
            if !isBlocked(tiles[i]) {
                if !existingSame(tiles[i], dirs[i]) {
                    out.append(PlannedPlacement(item: item, proto: proto, origin: tiles[i], direction: dirs[i]))
                }
                i += 1
                continue
            }
            // Run of blocked tiles [i, j)
            var j = i
            while j < tiles.count && isBlocked(tiles[j]) { j += 1 }
            let runDir = dirs[i]
            var bridged = false
            if let ug = underground, i >= 1, j < tiles.count {
                let straight = (i - 1..<j).allSatisfy { dirs[$0] == runDir } && dirs[j] == runDir
                let distance = j - (i - 1)
                if straight && distance <= ug.maxDistance {
                    // Replace the belt planned on the entrance tile (if any) with the underground entrance.
                    if let lastIdx = out.indices.last, out[lastIdx].origin == tiles[i - 1] { out.removeLast() }
                    out.append(PlannedPlacement(item: ug.item, proto: ug.proto, origin: tiles[i - 1], direction: runDir,
                                                role: .undergroundEntrance))
                    out.append(PlannedPlacement(item: ug.item, proto: ug.proto, origin: tiles[j], direction: runDir,
                                                role: .undergroundExit))
                    bridged = true
                    i = j + 1
                }
            }
            if !bridged {
                for k in i..<j where out.count < maxPlacements {
                    out.append(PlannedPlacement(item: item, proto: proto, origin: tiles[k], direction: dirs[k], plannedValid: false))
                }
                i = j
            }
        }
        return out
    }

    // MARK: Poles

    /// Indices into `path.tiles` where poles go: the first free tile, then greedily the farthest free tile still
    /// within `reach` of the previous pole — but only once the path actually extends beyond the reach (Factorio-style
    /// drag). `isFree(tile)` checks the pole footprint at that origin.
    public static func polePlacementIndices(path: DragPath, reach: Double, isFree: (TilePos) -> Bool) -> [Int] {
        let t = path.tiles
        guard !t.isEmpty else { return [] }
        guard let first = t.firstIndex(where: isFree) else { return [] }
        var out = [first]
        var last = first
        let r2 = reach * reach
        func d2(_ a: TilePos, _ b: TilePos) -> Double {
            let dx = Double(a.x - b.x), dy = Double(a.y - b.y)
            return dx * dx + dy * dy
        }
        while out.count < maxPlacements {
            // farthest index within reach
            var j = last
            while j + 1 < t.count && d2(t[last], t[j + 1]) <= r2 { j += 1 }
            if j + 1 >= t.count { break }                  // path doesn't extend beyond reach yet
            var k = j
            while k > last && !isFree(t[k]) { k -= 1 }
            if k == last {
                // Everything within reach is blocked: skip ahead to the next free tile (gap in the line).
                guard let n = t[(j + 1)...].firstIndex(where: isFree) else { break }
                k = n
            }
            out.append(k)
            last = k
        }
        return out
    }

    // MARK: Rows

    /// Origins of a gap-free row of w×h entities from `start` (origin of the first) toward world point `p`, along the
    /// dominant axis.
    public static func rowOrigins(start: TilePos, w: Int, h: Int, toward p: Vec2) -> [TilePos] {
        let cx = Double(start.x) + Double(w) / 2, cy = Double(start.y) + Double(h) / 2
        let dx = p.x - cx, dy = p.y - cy
        var out: [TilePos] = [start]
        if abs(dx) >= abs(dy) {
            let n = min(maxPlacements - 1, Int((abs(dx) / Double(w)).rounded()))
            let s: Int32 = dx >= 0 ? 1 : -1
            if n > 0 { for k in 1...n { out.append(TilePos(start.x + s * Int32(k * w), start.y)) } }
        } else {
            let n = min(maxPlacements - 1, Int((abs(dy) / Double(h)).rounded()))
            let s: Int32 = dy >= 0 ? 1 : -1
            if n > 0 { for k in 1...n { out.append(TilePos(start.x, start.y + s * Int32(k * h))) } }
        }
        return out
    }

    // MARK: Tiles

    /// Square brush of `size` (1/3/5) centred on `t`.
    public static func brush(at t: TilePos, size: Int) -> [TilePos] {
        let r = Int32(max(0, (size - 1) / 2))
        var out: [TilePos] = []
        out.reserveCapacity((2 * Int(r) + 1) * (2 * Int(r) + 1))
        var y = t.y - r
        while y <= t.y + r { var x = t.x - r; while x <= t.x + r { out.append(TilePos(x, y)); x += 1 }; y += 1 }
        return out
    }

    // MARK: Pipes

    /// Tiles an entity's (non-underground) fluid connections point at, in world space.
    public static func fluidConnectionTargets(proto p: EntityProto, rect: TileRect, direction: Direction) -> [TilePos] {
        guard let boxes = p.fluidBoxes else { return [] }
        var out: [TilePos] = []
        let c = rect.center
        for b in boxes {
            for conn in b.connections where conn.undergroundMaxDistance == nil {
                let v = direction.rotate(conn.position)
                out.append(Vec2(c.x + v.x, c.y + v.y).tile)
            }
        }
        return out
    }

    /// Connection mask for a pipe at `t` (bit 0 = N, 1 = E, 2 = S, 3 = W). `neighborTargets(n)` returns the tiles
    /// the entity standing on tile `n` connects to (empty if none / not a fluid entity).
    public static func pipeMask(at t: TilePos, neighborTargets: (TilePos) -> [TilePos]) -> Int {
        var m = 0
        for (bit, d) in [Direction.north, .east, .south, .west].enumerated() {
            let n = t.offset(d)
            if neighborTargets(n).contains(t) { m |= 1 << bit }
        }
        return m
    }

    // MARK: Reach

    /// Distance from a point to the nearest point of a tile rect (Factorio reach is measured to the entity box).
    public static func distance(from p: Vec2, to r: TileRect) -> Double {
        let cx = min(max(p.x, Double(r.x)), Double(r.maxX))
        let cy = min(max(p.y, Double(r.y)), Double(r.maxY))
        let dx = p.x - cx, dy = p.y - cy
        return (dx * dx + dy * dy).squareRoot()
    }
}
