// Gearforge — FactoryCore
// Transport belts, underground belts and splitters simulated as transport lines (05_mechanics §1).
// Owner: Logistics engineer.
//
// Model
// -----
// Every belt-like tile (transport belt, underground entrance/exit, each half of a splitter) is a `BeltTile`.
// Chains of tiles that continue into each other (straight, curves, underground pairs) are merged into
// `BeltLine`s of at most `maxLineTiles` tiles of one speed tier. Each line has two `BeltLane`s.
// A lane stores its items as gaps ordered back → front (last element = front item):
//   gaps[i] = distance (1/256 tile) from item i to the item in front of it, or to the line end for the front item.
// Per tick only one gap changes ("head-gap" algorithm): the front gap while the lane flows, or the first
// compressible gap (> 64) while the front is blocked. Cost is O(lanes), not O(items).
// Topology is rebuilt lazily (whole network) after belt placement/removal/rotation; items are preserved.

import Foundation

public enum BeltShape: UInt8, Sendable { case straight, curveLeft, curveRight, undergroundEntrance, undergroundExit, splitter }

public struct SplitterSettings: Equatable, Sendable {
    /// -1 none, 0 left, 1 right
    public var inputPriority: Int8 = -1
    public var outputPriority: Int8 = -1
    /// Filter item (requires outputPriority set), -1 none.
    public var filter: Int32 = -1
    public init() {}
}

/// Minimum distance between two items in a lane (0.25 tile).
@usableFromInline let beltItemSpacing: Int32 = 64
/// Lane lengths (1/256 tile).
@usableFromInline let laneStraight: Int32 = 256
@usableFromInline let laneCurveInner: Int32 = 106
@usableFromInline let laneCurveOuter: Int32 = 295

enum BeltTileKind: UInt8 { case belt = 0, undergroundIn, undergroundOut, splitterLeft, splitterRight }

/// Where a lane's front item goes when it reaches the end of its line.
enum LaneOutput: Equatable {
    case none
    /// Insert into `line`'s lane `lane` at distance-from-end `dist` (continuation: dist = target lane length).
    case line(Int32, UInt8, Int32)
    /// Pulled by a splitter node from input side `side`.
    case splitter(Int32, UInt8)
}

final class BeltLane {
    var length: Int32 = 0
    var gaps: [Int32] = []
    var items: [Int32] = []
    /// Sum of gaps = distance of the back-most item from the line end.
    var backDist: Int32 = 0
    /// Cached search start for the first compressible gap; Int.max = unknown, -1 = fully compressed.
    var compressIdx: Int = .max
    var output: LaneOutput = .none

    @inline(__always) var count: Int { items.count }

    @inline(__always) func invalidate() { compressIdx = .max }

    /// Inserts `item` at distance `d` from the line end if spacing allows.
    func insert(_ item: Int32, at d: Int32) -> Bool {
        guard d >= 0, d <= length else { return false }
        let n = items.count
        if n == 0 {
            gaps.append(d); items.append(item); backDist = d; invalidate(); return true
        }
        // Fast path: behind every item.
        if d >= backDist {
            guard d - backDist >= beltItemSpacing else { return false }
            gaps.insert(d - backDist, at: 0); items.insert(item, at: 0); backDist = d; invalidate(); return true
        }
        // Walk from the front: find first item (from front) whose distance exceeds d.
        var acc: Int32 = 0
        var i = n - 1
        var frontDist: Int32 = -1          // distance of the item in front of the insertion point (-1 = none)
        while i >= 0 {
            let di = acc + gaps[i]
            if di > d {
                // insert between item i (behind, distance di) and item i+1 (front, distance acc)
                if di - d < beltItemSpacing { return false }
                if frontDist >= 0 && d - frontDist < beltItemSpacing { return false }
                let newGap = frontDist >= 0 ? d - frontDist : d
                gaps[i] = di - d
                gaps.insert(newGap, at: i + 1)
                items.insert(item, at: i + 1)
                invalidate()
                return true
            }
            acc = di; frontDist = di
            i -= 1
        }
        return false // unreachable (fast path covers d >= backDist)
    }

    /// Removes item at index i; returns the item.
    @discardableResult
    func remove(at i: Int) -> Int32 {
        let it = items[i]
        if i == 0 {
            backDist -= gaps[0]
            if items.count > 1 { /* next back-most keeps its gap */ }
        } else {
            gaps[i - 1] += gaps[i]
        }
        gaps.remove(at: i); items.remove(at: i)
        if items.isEmpty { backDist = 0 }
        invalidate()
        return it
    }

    /// Index of the first item (searching from the front) whose distance lies in [lo, hi) and matches `pred`.
    func find(lo: Int32, hi: Int32, _ pred: (Int32) -> Bool) -> Int? {
        var acc: Int32 = 0
        var i = items.count - 1
        while i >= 0 {
            acc += gaps[i]
            if acc >= hi { return nil }
            if acc >= lo && pred(items[i]) { return i }
            i -= 1
        }
        return nil
    }

    /// Advances the lane by `speed`. Returns true if the front item is at the end (caller tries the output).
    @inline(__always) func advance(_ speed: Int32) -> Bool {
        let f = items.count - 1
        if f < 0 { return false }
        let g = gaps[f]
        if g > 0 {
            let m = g < speed ? g : speed
            gaps[f] = g - m; backDist -= m
            return gaps[f] == 0
        }
        return true
    }

    /// Front is blocked: close the first compressible gap behind it.
    @inline(__always) func compress(_ speed: Int32) {
        if compressIdx < 0 { return }
        var k = min(compressIdx, items.count - 2)
        while k >= 0 {
            let g = gaps[k]
            if g > beltItemSpacing {
                let m = min(speed, g - beltItemSpacing)
                gaps[k] = g - m; backDist -= m
                compressIdx = k
                return
            }
            k -= 1
        }
        compressIdx = -1
    }
}

final class BeltLine {
    let lanes: [BeltLane] = [BeltLane(), BeltLane()]
    /// Tile indices back → front.
    var tiles: [Int32] = []
    var speed: Int32 = 8
    var bounds = TileRect(x: 0, y: 0, w: 0, h: 0)
}

struct BeltTile {
    var entity: Int32 = -1
    var kind: BeltTileKind = .belt
    var pos = TilePos(0, 0)
    var dir: Direction = .north
    /// Direction items travel when entering (≠ dir for curves).
    var inDir: Direction = .north
    var speed: Int32 = 8
    var proto: Int32 = -1
    var shape: BeltShape = .straight
    // Derived by topology build:
    var line: Int32 = -1
    var endDist: (Int32, Int32) = (0, 0)   // distance from line end to this tile's front edge, per lane
    var len: (Int32, Int32) = (256, 256)
    /// Underground: index of the paired tile (-1 none). Distance in tiles for entrances.
    var pair: Int32 = -1
    var pairDistance: Int32 = 0

    @inline(__always) func endDist(_ lane: Int) -> Int32 { lane == 0 ? endDist.0 : endDist.1 }
    @inline(__always) func len(_ lane: Int) -> Int32 { lane == 0 ? len.0 : len.1 }
    var isAlive: Bool { entity >= 0 }
}

struct SplitterNode {
    var entity: Int32
    /// Tile index of left/right half.
    var half: (Int32, Int32)
    /// Input lanes [side*2 + lane] → (line, lane) or -1.
    var inLine: [Int32] = [-1, -1, -1, -1]
    var inputNext: [UInt8] = [0, 0]
    var outputNext: [UInt8] = [0, 0]
}

public final class BeltSystem: EntitySystem {
    public unowned let world: World
    public init(world: World) { self.world = world }

    static let maxLineTiles = 16

    var tiles: [BeltTile] = []
    private var freeTiles: [Int32] = []
    /// Per-entity extra state (indexed by first tile index): underground mode & splitter settings.
    var undergroundIsEntrance: [Bool] = []
    var splitterSettingsByTile: [SplitterSettings] = []

    var lines: [BeltLine] = []
    var splitters: [SplitterNode] = []
    private var splitterOfTile: [Int32] = []
    private var dirty = true
    /// Items waiting to be placed by the next rebuild: tile, lane, exact distance from the tile's front end in lane
    /// units (`within`, -1 = unknown → use `frac`, only for saves written before belt save v2), item.
    private var pendingItems: [(tile: Int32, lane: UInt8, frac: Float, within: Int32, item: Int32)] = []
    /// Items that could not be re-placed after a topology rebuild (should be ~never).
    public private(set) var lostItems: Int = 0

    private var beltProto: [Int32: BeltProto] = [:]

    public func setUp() {}

    // MARK: Entity lifecycle

    private func allocTile() -> Int32 {
        if let i = freeTiles.popLast() { return i }
        tiles.append(BeltTile())
        undergroundIsEntrance.append(true)
        splitterSettingsByTile.append(SplitterSettings())
        return Int32(tiles.count - 1)
    }

    private func speedOf(_ proto: Int) -> Int32 { Int32(world.db.entities[proto].belt?.speed ?? 8) }

    public func entityAdded(_ e: Int32) {
        let rec = world.entities[e]
        let proto = Int(rec.proto)
        let speed = speedOf(proto)
        switch rec.kind {
        case .transportBelt, .undergroundBelt:
            let t = allocTile()
            tiles[Int(t)] = BeltTile(entity: e, kind: .belt, pos: rec.origin, dir: rec.direction, inDir: rec.direction,
                                     speed: speed, proto: Int32(proto))
            if rec.kind == .undergroundBelt {
                tiles[Int(t)].kind = .undergroundIn
                undergroundIsEntrance[Int(t)] = !shouldBecomeExit(proto: proto, at: rec.origin, dir: rec.direction)
            }
            world.entities.setComponent(e, t)
        case .splitter:
            let a = allocTile(), b = allocTile()
            let (l, r) = splitterHalves(rec)
            tiles[Int(a)] = BeltTile(entity: e, kind: .splitterLeft, pos: l, dir: rec.direction, inDir: rec.direction,
                                     speed: speed, proto: Int32(proto), shape: .splitter)
            tiles[Int(b)] = BeltTile(entity: e, kind: .splitterRight, pos: r, dir: rec.direction, inDir: rec.direction,
                                     speed: speed, proto: Int32(proto), shape: .splitter)
            splitterSettingsByTile[Int(a)] = SplitterSettings()
            world.entities.setComponent(e, a)
            // second half index stored implicitly: we keep it in a lookup
            splitterSecond[a] = b
        default:
            return
        }
        dirty = true
    }

    /// Splitter first-half tile → second-half tile.
    private var splitterSecond: [Int32: Int32] = [:]

    private func tileIndices(of e: Int32) -> [Int32] {
        let c = world.entities[e].component
        guard c >= 0 else { return [] }
        if world.entities[e].kind == .splitter, let b = splitterSecond[c] { return [c, b] }
        return [c]
    }

    public func entityRemoved(_ e: Int32) {
        for t in tileIndices(of: e) {
            tiles[Int(t)] = BeltTile()
            splitterSecond[t] = nil
            freeTiles.append(t)
        }
        world.entities.setComponent(e, -1)
        dirty = true
    }

    public func entityRotated(_ e: Int32) {
        let rec = world.entities[e]
        if rec.kind == .splitter {
            let ts = tileIndices(of: e)
            let (l, r) = splitterHalves(rec)
            if ts.count == 2 {
                tiles[Int(ts[0])].pos = l; tiles[Int(ts[0])].dir = rec.direction; tiles[Int(ts[0])].inDir = rec.direction
                tiles[Int(ts[1])].pos = r; tiles[Int(ts[1])].dir = rec.direction; tiles[Int(ts[1])].inDir = rec.direction
            }
        } else if let t = tileIndices(of: e).first {
            tiles[Int(t)].dir = rec.direction
            tiles[Int(t)].inDir = rec.direction
        }
        dirty = true
    }

    /// Left/right half tiles of a splitter (relative to its direction).
    private func splitterHalves(_ rec: EntityRecord) -> (TilePos, TilePos) {
        let c = rec.center
        let l = rec.direction.counterClockwise.vector, r = rec.direction.clockwise.vector
        let lp = Vec2(c.x + Double(l.x) * 0.5, c.y + Double(l.y) * 0.5)
        let rp = Vec2(c.x + Double(r.x) * 0.5, c.y + Double(r.y) * 0.5)
        return (TilePos(Int32(lp.x.rounded(.down)), Int32(lp.y.rounded(.down))),
                TilePos(Int32(rp.x.rounded(.down)), Int32(rp.y.rounded(.down))))
    }

    /// An underground placed in front of an unpaired entrance (same tier/direction, within range) becomes its exit.
    private func shouldBecomeExit(proto: Int, at p: TilePos, dir: Direction) -> Bool {
        let maxD = Int32(world.db.entities[proto].belt?.undergroundMaxDistance ?? 5)
        var k: Int32 = 1
        while k <= maxD {
            let q = p.offset(dir.opposite, k)
            if let o = world.entity(at: q), world.entities[o].kind == .undergroundBelt,
               Int(world.entities[o].proto) == proto, world.entities[o].direction == dir {
                let c = world.entities[o].component
                guard c >= 0 else { return false }
                if !undergroundIsEntrance[Int(c)] { return false }       // nearer exit blocks
                // entrance: is it already paired with something nearer?
                let entranceP = q
                var j: Int32 = 1
                while j < k {
                    let r = entranceP.offset(dir, j)
                    if let x = world.entity(at: r), world.entities[x].kind == .undergroundBelt,
                       Int(world.entities[x].proto) == proto, world.entities[x].direction == dir { return false }
                    j += 1
                }
                return true
            }
            k += 1
        }
        return false
    }

    /// Sets whether an underground belt is an entrance (true) or exit.
    public func setUndergroundMode(_ e: Int32, entrance: Bool) {
        guard let t = tileIndices(of: e).first else { return }
        undergroundIsEntrance[Int(t)] = entrance
        dirty = true
    }
    public func isUndergroundEntrance(_ e: Int32) -> Bool {
        guard let t = tileIndices(of: e).first else { return true }
        return undergroundIsEntrance[Int(t)]
    }

    public func neighborhoodChanged(_ rect: TileRect) {}

    public func takeContents(_ e: Int32) -> [ItemStack] {
        ensureTopology()
        var out: [ItemStack] = []
        for t in tileIndices(of: e) { removeAllItems(onTile: t, into: &out) }
        return out
    }

    // MARK: Topology

    @inline(__always) func ensureTopology() { if dirty { rebuild() } }

    private func rebuild() {
        dirty = false
        // 1. Save items as (tile, lane, fraction along tile from the back).
        var saved = pendingItems
        pendingItems = []
        for line in lines {
            for l in 0..<2 {
                let lane = line.lanes[l]
                if lane.count == 0 { continue }
                var j = line.tiles.count - 1
                var segFront: Int32 = 0
                var acc: Int32 = 0
                var i = lane.count - 1
                while i >= 0 {
                    acc += lane.gaps[i]
                    while j > 0 && acc >= segFront + tileLen(line.tiles[j], l) { segFront += tileLen(line.tiles[j], l); j -= 1 }
                    let t = line.tiles[j]
                    let len = tileLen(t, l)
                    let frac = 1 - Float(acc - segFront) / Float(max(1, len))
                    saved.append((t, UInt8(l), max(0, min(1, frac)), acc - segFront, lane.items[i]))
                    i -= 1
                }
            }
        }
        lines.removeAll(keepingCapacity: true)
        splitters.removeAll(keepingCapacity: true)

        let n = tiles.count
        // 2. Tile map
        var map: [TilePos: Int32] = [:]
        map.reserveCapacity(n)
        for i in 0..<n where tiles[i].isAlive {
            map[tiles[i].pos] = Int32(i)
            tiles[i].line = -1
            tiles[i].pair = -1
            tiles[i].pairDistance = 0
            tiles[i].inDir = tiles[i].dir
            switch tiles[i].kind {
            case .belt: tiles[i].shape = .straight
            case .undergroundIn, .undergroundOut:
                let ent = undergroundIsEntrance[i]
                tiles[i].kind = ent ? .undergroundIn : .undergroundOut
                tiles[i].shape = ent ? .undergroundEntrance : .undergroundExit
            case .splitterLeft, .splitterRight: tiles[i].shape = .splitter
            }
        }
        @inline(__always) func outputsToFront(_ t: BeltTile) -> Bool { t.kind != .undergroundIn }

        // 3. Underground pairing
        for i in 0..<n where tiles[i].isAlive && tiles[i].kind == .undergroundIn {
            let t = tiles[i]
            let maxD = Int32(world.db.entities[Int(t.proto)].belt?.undergroundMaxDistance ?? 5)
            var k: Int32 = 1
            while k <= maxD {
                if let o = map[t.pos.offset(t.dir, k)] {
                    let u = tiles[Int(o)]
                    if (u.kind == .undergroundIn || u.kind == .undergroundOut) && u.proto == t.proto && u.dir == t.dir {
                        if u.kind == .undergroundOut && u.pair < 0 {
                            tiles[i].pair = o; tiles[i].pairDistance = k
                            tiles[Int(o)].pair = Int32(i); tiles[Int(o)].pairDistance = k
                        }
                        break
                    }
                }
                k += 1
            }
        }

        // 4. Curves
        for i in 0..<n where tiles[i].isAlive && tiles[i].kind == .belt {
            let t = tiles[i]
            var behind = false
            if let b = map[t.pos.offset(t.dir.opposite)], outputsToFront(tiles[Int(b)]), tiles[Int(b)].dir == t.dir { behind = true }
            if behind { continue }
            var sideFeeder: Direction? = nil
            var sides = 0
            for s in [t.dir.clockwise, t.dir.counterClockwise] {
                if let f = map[t.pos.offset(s)], outputsToFront(tiles[Int(f)]), tiles[Int(f)].dir == s.opposite {
                    sides += 1; sideFeeder = s.opposite
                }
            }
            if sides == 1, let inDir = sideFeeder {
                tiles[i].inDir = inDir
                tiles[i].shape = (t.dir == inDir.counterClockwise) ? .curveLeft : .curveRight
            }
        }

        // 5. Lane lengths per tile
        for i in 0..<n where tiles[i].isAlive {
            switch tiles[i].shape {
            case .curveLeft: tiles[i].len = (laneCurveInner, laneCurveOuter)
            case .curveRight: tiles[i].len = (laneCurveOuter, laneCurveInner)
            case .undergroundEntrance:
                let extra = tiles[i].pair >= 0 ? (tiles[i].pairDistance - 1) * laneStraight : 0
                tiles[i].len = (laneStraight + extra, laneStraight + extra)
            default: tiles[i].len = (laneStraight, laneStraight)
            }
        }

        // 6. Next links
        enum Next { case none, cont(Int32), side(Int32, UInt8, Int8), splitterIn(Int32) }   // side: (target, nearLane, onlyFeederLane or -1)
        var next = [Next](repeating: .none, count: n)
        var prev = [Int32](repeating: -1, count: n)
        for i in 0..<n where tiles[i].isAlive {
            let t = tiles[i]
            if t.kind == .undergroundIn {
                if t.pair >= 0 { next[i] = .cont(t.pair); prev[Int(t.pair)] = Int32(i) }
                continue
            }
            guard let f = map[t.pos.offset(t.dir)] else { continue }
            let u = tiles[Int(f)]
            if u.dir == t.dir.opposite { continue }
            switch u.kind {
            case .belt:
                if u.dir == t.dir || u.inDir == t.dir {
                    next[i] = .cont(f); prev[Int(f)] = Int32(i)
                } else {
                    next[i] = .side(f, nearLane(of: u, fromDir: t.dir), -1)
                }
            case .undergroundIn:
                if u.dir == t.dir { next[i] = .cont(f); prev[Int(f)] = Int32(i) }
                else { next[i] = .side(f, nearLane(of: u, fromDir: t.dir), openFeederLane(feeder: t, target: u)) }
            case .undergroundOut:
                if u.dir != t.dir { next[i] = .side(f, nearLane(of: u, fromDir: t.dir), openFeederLane(feeder: t, target: u)) }
            case .splitterLeft, .splitterRight:
                if u.dir == t.dir { next[i] = .splitterIn(f) }
            }
        }

        // 7. Build lines from heads
        var visited = [Bool](repeating: false, count: n)
        var lineHead: [Int32] = []
        func walk(from head: Int32) {
            var queue: [Int32] = [head]
            while let h = queue.popLast() {
                if visited[Int(h)] { continue }
                let line = BeltLine()
                line.speed = tiles[Int(h)].speed
                let li = Int32(lines.count)
                lines.append(line)
                var cur = h
                while true {
                    visited[Int(cur)] = true
                    tiles[Int(cur)].line = li
                    line.tiles.append(cur)
                    guard case .cont(let nx) = next[Int(cur)], !visited[Int(nx)] else { break }
                    let isSplitterHalf = tiles[Int(nx)].kind == .splitterLeft || tiles[Int(nx)].kind == .splitterRight
                    if tiles[Int(nx)].speed != line.speed || line.tiles.count >= Self.maxLineTiles || isSplitterHalf {
                        queue.append(nx); break
                    }
                    cur = nx
                }
                lineHead.append(h)
            }
        }
        for i in 0..<n where tiles[i].isAlive && prev[i] < 0 { walk(from: Int32(i)) }
        for i in 0..<n where tiles[i].isAlive && !visited[i] { walk(from: Int32(i)) }   // loops

        // 8. Distances & bounds
        for line in lines {
            var d0: Int32 = 0, d1: Int32 = 0
            var minX = Int32.max, minY = Int32.max, maxX = Int32.min, maxY = Int32.min
            for t in line.tiles.reversed() {
                tiles[Int(t)].endDist = (d0, d1)
                d0 += tiles[Int(t)].len.0; d1 += tiles[Int(t)].len.1
                let p = tiles[Int(t)].pos
                minX = min(minX, p.x); minY = min(minY, p.y); maxX = max(maxX, p.x); maxY = max(maxY, p.y)
                if tiles[Int(t)].kind == .undergroundIn, tiles[Int(t)].pair >= 0 {
                    let q = tiles[Int(tiles[Int(t)].pair)].pos
                    minX = min(minX, q.x); minY = min(minY, q.y); maxX = max(maxX, q.x); maxY = max(maxY, q.y)
                }
            }
            line.lanes[0].length = d0; line.lanes[1].length = d1
            line.bounds = TileRect(x: minX, y: minY, w: maxX - minX + 1, h: maxY - minY + 1)
        }

        // 9. Splitter nodes
        splitterOfTile = [Int32](repeating: -1, count: n)
        for i in 0..<n where tiles[i].isAlive && tiles[i].kind == .splitterLeft {
            let a = Int32(i)
            guard let b = splitterSecond[a] else { continue }
            splitterOfTile[i] = Int32(splitters.count)
            splitterOfTile[Int(b)] = Int32(splitters.count)
            splitters.append(SplitterNode(entity: tiles[i].entity, half: (a, b)))
        }

        // 10. Lane outputs
        for (li, line) in lines.enumerated() {
            let front = Int(line.tiles.last!)
            for l in 0..<2 {
                let lane = line.lanes[l]
                switch next[front] {
                case .none: lane.output = .none
                case .cont(let u):
                    let tl = lines[Int(tiles[Int(u)].line)]
                    lane.output = .line(tiles[Int(u)].line, UInt8(l), tl.lanes[l].length)
                case .side(let u, let near, let only):
                    if only >= 0 && Int(only) != l { lane.output = .none; break }
                    let ut = tiles[Int(u)]
                    let dist = ut.endDist(Int(near)) + ut.len(Int(near)) / 2
                    lane.output = .line(ut.line, near, dist)
                case .splitterIn(let u):
                    let node = splitterOfTile[Int(u)]
                    let side: UInt8 = tiles[Int(u)].kind == .splitterLeft ? 0 : 1
                    lane.output = .splitter(node, side)
                    if node >= 0 { splitters[Int(node)].inLine[Int(side) * 2 + l] = Int32(li) }
                }
            }
        }

        // 11. Re-place items
        for s in saved {
            let t = Int(s.tile)
            guard t < tiles.count, tiles[t].isAlive, tiles[t].line >= 0 else { lostItems += 1; continue }
            let l = Int(s.lane)
            let lane = lines[Int(tiles[t].line)].lanes[l]
            let len = tiles[t].len(l)
            let base = tiles[t].endDist(l)
            // exact position (QA BUG 14): integer offset; the float fraction only for old saves
            let d = base + (s.within >= 0 ? min(s.within, len) : Int32((1 - s.frac) * Float(len)))
            if lane.insert(s.item, at: min(d, lane.length)) { continue }
            // search nearby free spot within the tile
            var placed = false
            var off: Int32 = 8
            while off <= len && !placed {
                if lane.insert(s.item, at: min(lane.length, d + off)) { placed = true; break }
                if d - off >= base, lane.insert(s.item, at: d - off) { placed = true; break }
                off += 8
            }
            if !placed { lostItems += 1 }
        }
    }

    @inline(__always) private func tileLen(_ t: Int32, _ lane: Int) -> Int32 { tiles[Int(t)].len(lane) }

    /// Lane of `target` on the side a feeder travelling `fromDir` arrives from.
    private func nearLane(of target: BeltTile, fromDir: Direction) -> UInt8 {
        // feeder sits at target.pos - fromDir; target's left lane is on target.dir.counterClockwise side.
        return fromDir.opposite == target.dir.counterClockwise ? 0 : 1
    }

    /// Sideloading onto an underground: only the feeder lane above the open half of the tile passes (05 §1.3).
    private func openFeederLane(feeder: BeltTile, target: BeltTile) -> Int8 {
        let openSide = target.kind == .undergroundIn ? target.dir.opposite : target.dir
        // feeder's left lane lies on feeder.dir.counterClockwise side
        return feeder.dir.counterClockwise == openSide ? 0 : 1
    }

    // MARK: Tick

    public func update() {
        ensureTopology()
        for line in lines {
            let sp = line.speed
            for l in 0..<2 {
                let lane = line.lanes[l]
                if lane.count == 0 { continue }
                if lane.advance(sp) {
                    if !tryOutput(lane) { lane.compress(sp) }
                }
            }
        }
        for i in splitters.indices { updateSplitter(i) }
    }

    /// Moves the front item of `lane` (at the end) to its output. Returns true on success.
    @inline(__always) private func tryOutput(_ lane: BeltLane) -> Bool {
        switch lane.output {
        case .line(let li, let tl, let dist):
            let target = lines[Int(li)].lanes[Int(tl)]
            let f = lane.count - 1
            if target.insert(lane.items[f], at: dist) { lane.remove(at: f); return true }
            return false
        default:
            return false
        }
    }

    private func updateSplitter(_ si: Int) {
        var node = splitters[si]
        let settings = splitterSettingsByTile[Int(node.half.0)]
        let outLines = (tiles[Int(node.half.0)].line, tiles[Int(node.half.1)].line)
        for l in 0..<2 {
            var order: [Int] = []
            if settings.inputPriority >= 0 { let p = Int(settings.inputPriority); order = [p, 1 - p] }
            else { let p = Int(node.inputNext[l]); order = [p, 1 - p] }
            for side in order {
                let li = node.inLine[side * 2 + l]
                guard li >= 0 else { continue }
                let lane = lines[Int(li)].lanes[l]
                let f = lane.count - 1
                guard f >= 0, lane.gaps[f] == 0 else { continue }
                let item = lane.items[f]
                var candidates: [Int] = []
                if settings.filter >= 0 {
                    let fs = settings.outputPriority >= 0 ? Int(settings.outputPriority) : 0
                    candidates = [item == settings.filter ? fs : 1 - fs]
                } else if settings.outputPriority >= 0 {
                    let p = Int(settings.outputPriority); candidates = [p, 1 - p]
                } else {
                    let p = Int(node.outputNext[l]); candidates = [p, 1 - p]
                }
                for o in candidates {
                    let ol = o == 0 ? outLines.0 : outLines.1
                    guard ol >= 0 else { continue }
                    let target = lines[Int(ol)].lanes[l]
                    if target.insert(item, at: target.length) {
                        lane.remove(at: f)
                        if settings.filter < 0 && settings.outputPriority < 0 { node.outputNext[l] = UInt8(1 - o) }
                        if settings.inputPriority < 0 { node.inputNext[l] = UInt8(1 - side) }
                        break
                    }
                }
            }
        }
        splitters[si] = node
    }

    // MARK: API for inserters / drills / player

    @inline(__always) private func tileIndex(_ e: Int32) -> Int32? {
        let rec = world.entities[e]
        guard rec.isAlive else { return nil }
        switch rec.kind {
        case .transportBelt, .undergroundBelt, .splitter: break
        default: return nil
        }
        let c = rec.component
        return c >= 0 ? c : nil
    }

    /// Visible pick/insert range of a tile lane as distance-from-end [lo, hi).
    @inline(__always) private func range(_ t: Int32, _ lane: Int) -> (Int32, Int32) {
        let tile = tiles[Int(t)]
        let lo = tile.endDist(lane)
        var hi = lo + tile.len(lane)
        if tile.kind == .undergroundIn { hi = lo + tile.len(lane); return (hi - laneStraight / 2, hi) }   // back half only
        if tile.kind == .undergroundOut { return (lo, lo + laneStraight / 2) }                           // front half only
        _ = hi
        return (lo, lo + tile.len(lane))
    }

    /// Lane 0 = left, 1 = right (relative to belt direction).
    /// Tries to put an item on belt entity `e` at lane/position (position in 1/256 tile along the tile, 0...255).
    /// Returns true if inserted (needs a gap of 64 positions).
    public func insertItem(_ e: Int32, lane: Int, position: Int, item: Int) -> Bool {
        ensureTopology()
        guard let t = tileIndex(e), tiles[Int(t)].line >= 0 else { return false }
        let tile = tiles[Int(t)]
        let len = tile.len(lane)
        let d = tile.endDist(lane) + Int32((255 - max(0, min(255, position))) * Int(len) / 256)
        return lines[Int(tile.line)].lanes[lane].insert(Int32(item), at: d)
    }

    /// Can an item be inserted there right now?
    public func canInsert(_ e: Int32, lane: Int, position: Int) -> Bool {
        ensureTopology()
        guard let t = tileIndex(e), tiles[Int(t)].line >= 0 else { return false }
        let tile = tiles[Int(t)]
        let ln = lines[Int(tile.line)].lanes[lane]
        let d = tile.endDist(lane) + Int32((255 - max(0, min(255, position))) * Int(tile.len(lane)) / 256)
        if d > ln.length || d < 0 { return false }
        var acc: Int32 = 0
        var i = ln.count - 1
        while i >= 0 {
            acc += ln.gaps[i]
            if abs(acc - d) < beltItemSpacing { return false }
            if acc > d + beltItemSpacing { break }
            i -= 1
        }
        return true
    }

    /// Picks up one item from tile `e` (prefers `preferredLane`) matching `filter`. Returns the item or -1.
    public func pickItem(_ e: Int32, preferredLane: Int, filter: (Int) -> Bool) -> Int {
        ensureTopology()
        guard let t0 = tileIndex(e) else { return -1 }
        var ts = [t0]
        if world.entities[e].kind == .splitter, let b = splitterSecond[t0] { ts.append(b) }
        for t in ts {
            let tile = tiles[Int(t)]
            guard tile.line >= 0 else { continue }
            for l in [preferredLane, 1 - preferredLane] {
                let lane = lines[Int(tile.line)].lanes[l]
                if lane.count == 0 { continue }
                let (lo, hi) = range(t, l)
                if let i = lane.find(lo: lo, hi: hi, { filter(Int($0)) }) { return Int(lane.remove(at: i)) }
            }
        }
        return -1
    }

    /// Lane an inserter dropping from direction `from` should use (far lane rule, 05 §1.6).
    public func dropLane(_ e: Int32, inserterDirection: Direction) -> Int {
        let rec = world.entities[e]
        let b = rec.direction
        if inserterDirection == b.counterClockwise { return 0 }
        if inserterDirection == b.clockwise { return 1 }
        return 1
    }

    /// Lane nearest to a point inside the tile (player placing an item on a belt).
    public func nearestLane(_ e: Int32, point: Vec2) -> Int {
        let rec = world.entities[e]
        let c = rec.center
        let l = rec.direction.counterClockwise.vector
        let dot = (point.x - c.x) * Double(l.x) + (point.y - c.y) * Double(l.y)
        return dot >= 0 ? 0 : 1
    }

    // MARK: Rendering API

    /// Calls `body(item, x, y)` for every belt item whose world position lies in `rect` (tile units, item centre).
    public func forEachItem(in rect: TileRect, _ body: (Int, Double, Double) -> Void) {
        ensureTopology()
        let rx0 = Double(rect.x), ry0 = Double(rect.y), rx1 = Double(rect.maxX), ry1 = Double(rect.maxY)
        for line in lines where line.bounds.intersects(rect) {
            for l in 0..<2 {
                let lane = line.lanes[l]
                if lane.count == 0 { continue }
                var j = line.tiles.count - 1
                var segFront: Int32 = 0
                var acc: Int32 = 0
                var i = lane.count - 1
                while i >= 0 {
                    acc += lane.gaps[i]
                    while j > 0 && acc >= segFront + tileLen(line.tiles[j], l) { segFront += tileLen(line.tiles[j], l); j -= 1 }
                    let t = tiles[Int(line.tiles[j])]
                    let len = t.len(l)
                    let along = len - (acc - segFront)                // distance from tile back
                    if let p = position(of: t, lane: l, along: along) {
                        if p.x >= rx0 && p.x < rx1 && p.y >= ry0 && p.y < ry1 { body(Int(lane.items[i]), p.x, p.y) }
                    }
                    i -= 1
                }
            }
        }
    }

    /// World position of a point `along` (1/256 tile from the tile back) on a lane, or nil if hidden (underground).
    func position(of t: BeltTile, lane: Int, along: Int32) -> Vec2? {
        var f: Double
        switch t.kind {
        case .undergroundIn:
            if along > laneStraight / 2 { return nil }
            f = Double(along) / Double(laneStraight)
        case .undergroundOut:
            if along < laneStraight / 2 { return nil }
            f = Double(along) / Double(laneStraight)
        default:
            f = Double(along) / Double(max(1, t.len(lane)))
        }
        f = max(0, min(1, f))
        let cx = Double(t.pos.x) + 0.5, cy = Double(t.pos.y) + 0.5
        let o = lane == 0 ? 0.25 : -0.25
        if t.shape == .curveLeft || t.shape == .curveRight {
            let inV = t.inDir.vector, outV = t.dir.vector
            let lat = t.inDir.counterClockwise.vector
            let latX = Double(lat.x) * o, latY = Double(lat.y) * o
            let px = cx - Double(inV.x) * 0.5 + Double(outV.x) * 0.5
            let py = cy - Double(inV.y) * 0.5 + Double(outV.y) * 0.5
            let r = 0.5 - (latX * Double(outV.x) + latY * Double(outV.y))
            let th = f * Double.pi / 2
            let c = cos(th), s = sin(th)
            return Vec2(px + (-Double(outV.x) * c + Double(inV.x) * s) * r,
                        py + (-Double(outV.y) * c + Double(inV.y) * s) * r)
        }
        let v = t.dir.vector, lat = t.dir.counterClockwise.vector
        return Vec2(cx + Double(v.x) * (f - 0.5) + Double(lat.x) * o, cy + Double(v.y) * (f - 0.5) + Double(lat.y) * o)
    }

    /// Animation phase offset for belt textures (positions moved since start, per tier speed).
    public func animationPhase(speed: Int) -> Int { Int(world.tick &* UInt64(speed) % 256) }

    /// Shape for rendering: straight / curve-left / curve-right; underground in/out; splitter.
    public func shape(of e: Int32) -> BeltShape {
        ensureTopology()
        guard let t = tileIndex(e) else { return .straight }
        return tiles[Int(t)].shape
    }

    /// Direction items enter the tile (≠ entity direction on curves).
    public func inputDirection(of e: Int32) -> Direction {
        ensureTopology()
        guard let t = tileIndex(e) else { return world.entities[e].direction }
        return tiles[Int(t)].inDir
    }

    /// Items currently on the entity's tile(s), both lanes.
    public func items(on e: Int32) -> [ItemStack] {
        ensureTopology()
        guard let t0 = tileIndex(e) else { return [] }
        var counts: [Int32: Int32] = [:]
        var order: [Int32] = []
        var ts = [t0]
        if world.entities[e].kind == .splitter, let b = splitterSecond[t0] { ts.append(b) }
        for t in ts {
            let tile = tiles[Int(t)]
            guard tile.line >= 0 else { continue }
            for l in 0..<2 {
                let lane = lines[Int(tile.line)].lanes[l]
                let lo = tile.endDist(l), hi = lo + tile.len(l)
                var acc: Int32 = 0
                var i = lane.count - 1
                while i >= 0 {
                    acc += lane.gaps[i]
                    if acc >= hi { break }
                    if acc >= lo {
                        let it = lane.items[i]
                        if counts[it] == nil { order.append(it) }
                        counts[it, default: 0] += 1
                    }
                    i -= 1
                }
            }
        }
        return order.map { ItemStack(item: $0, count: counts[$0]!) }
    }

    /// Total items on all belts (stats/tests).
    public var totalItemCount: Int {
        ensureTopology()
        return lines.reduce(0) { $0 + $1.lanes[0].count + $1.lanes[1].count }
    }

    /// Removes every item on the entity's tiles (player "pick up items from belt").
    public func removeAllItems(on e: Int32) -> [ItemStack] {
        ensureTopology()
        var out: [ItemStack] = []
        for t in tileIndices(of: e) { removeAllItems(onTile: t, into: &out) }
        return out
    }

    private func removeAllItems(onTile t: Int32, into out: inout [ItemStack]) {
        let tile = tiles[Int(t)]
        guard tile.line >= 0, Int(tile.line) < lines.count else { return }
        for l in 0..<2 {
            let lane = lines[Int(tile.line)].lanes[l]
            let lo = tile.endDist(l), hi = lo + tile.len(l)
            var acc: Int32 = 0
            var i = lane.count - 1
            var toRemove: [Int] = []
            while i >= 0 {
                acc += lane.gaps[i]
                if acc >= hi { break }
                if acc >= lo { toRemove.append(i) }
                i -= 1
            }
            // indices are descending; removing in that order keeps lower indices valid
            for idx in toRemove {
                let it = lane.remove(at: idx)
                if let k = out.firstIndex(where: { $0.item == it }) { out[k].count += 1 } else { out.append(ItemStack(item: it, count: 1)) }
            }
        }
    }

    // MARK: Splitter settings (UI)

    public func splitterSettings(_ e: Int32) -> SplitterSettings {
        guard let t = tileIndex(e) else { return SplitterSettings() }
        return splitterSettingsByTile[Int(t)]
    }
    public func setSplitterSettings(_ e: Int32, _ s: SplitterSettings) {
        guard let t = tileIndex(e), world.entities[e].kind == .splitter else { return }
        splitterSettingsByTile[Int(t)] = s
    }

    // MARK: Persistence

    public func serialize(to w: inout BinaryWriter) {
        ensureTopology()
        w.write(UInt8(2)) // version 2: item positions as exact integer offsets
        w.writeVarInt(tiles.count)
        for i in tiles.indices {
            let t = tiles[i]
            w.write(t.entity)
            w.write(t.kind.rawValue)
            w.write(t.pos)
            w.write(t.dir.rawValue)
            w.write(t.speed)
            w.write(t.proto)
            w.write(undergroundIsEntrance[i])
            let s = splitterSettingsByTile[i]
            w.write(s.inputPriority); w.write(s.outputPriority); w.write(s.filter)
        }
        w.writeVarInt(splitterSecond.count)
        for (a, b) in splitterSecond.sorted(by: { $0.key < $1.key }) { w.write(a); w.write(b) }
        // items
        var saved: [(Int32, UInt8, Int32, Int32)] = []
        for line in lines {
            for l in 0..<2 {
                let lane = line.lanes[l]
                var j = line.tiles.count - 1
                var segFront: Int32 = 0
                var acc: Int32 = 0
                var i = lane.count - 1
                while i >= 0 {
                    acc += lane.gaps[i]
                    while j > 0 && acc >= segFront + tileLen(line.tiles[j], l) { segFront += tileLen(line.tiles[j], l); j -= 1 }
                    let t = line.tiles[j]
                    let len = tileLen(t, l)
                    _ = len
                    saved.append((t, UInt8(l), acc - segFront, lane.items[i]))
                    i -= 1
                }
            }
        }
        w.writeVarInt(saved.count)
        for s in saved { w.write(s.0); w.write(s.1); w.write(s.2); w.write(s.3) }
        w.write(UInt64(lostItems))
    }

    public func deserialize(from r: inout BinaryReader) throws {
        let version = try r.read(UInt8.self)
        let n = try r.readVarInt()
        tiles = []; undergroundIsEntrance = []; splitterSettingsByTile = []; freeTiles = []
        tiles.reserveCapacity(n)
        for i in 0..<n {
            var t = BeltTile()
            t.entity = try r.read(Int32.self)
            t.kind = BeltTileKind(rawValue: try r.read(UInt8.self)) ?? .belt
            t.pos = try r.readTilePos()
            t.dir = Direction(rawValue: try r.read(UInt8.self)) ?? .north
            t.inDir = t.dir
            t.speed = try r.read(Int32.self)
            t.proto = try r.read(Int32.self)
            tiles.append(t)
            undergroundIsEntrance.append(try r.readBool())
            var s = SplitterSettings()
            s.inputPriority = try r.read(Int8.self); s.outputPriority = try r.read(Int8.self); s.filter = try r.read(Int32.self)
            splitterSettingsByTile.append(s)
            if t.entity < 0 { freeTiles.append(Int32(i)) }
        }
        splitterSecond = [:]
        let ns = try r.readVarInt()
        for _ in 0..<ns { let a = try r.read(Int32.self); let b = try r.read(Int32.self); splitterSecond[a] = b }
        let ni = try r.readVarInt()
        pendingItems = []
        pendingItems.reserveCapacity(ni)
        for _ in 0..<ni {
            let t = try r.read(Int32.self); let l = try r.read(UInt8.self)
            if version >= 2 {
                let within = try r.read(Int32.self); let it = try r.read(Int32.self)
                pendingItems.append((t, l, 0, max(0, within), it))
            } else {
                let f = try r.readFloat(); let it = try r.read(Int32.self)
                pendingItems.append((t, l, f, -1, it))
            }
        }
        lostItems = Int(try r.read(UInt64.self))
        lines = []
        dirty = true
    }

    public func didLoad() { ensureTopology() }
}

