// Gearforge — FactoryCore
// Tap-to-walk (GDD §4.2): A* on the tile grid (8-connected, no corner cutting), bounded search, then the character
// follows the waypoints at running speed. Joystick input cancels the path. Owner: Gameplay engineer.

public extension Character {

    /// Whether the character may stand on this tile (land, no solid entity).
    func isWalkableTile(_ p: TilePos) -> Bool {
        guard world.surface.isInBounds(p) else { return false }
        let t = world.surface.tile(at: p)
        if t >= 0 && world.db.tiles[t].isWater { return false }
        if let e = world.entity(at: p) {
            let r = world.entities[e]
            if r.flags.contains(.ghost) { return true }
            switch r.kind {
            case .transportBelt, .undergroundBelt, .splitter, .electricPole: return true
            default: return false
            }
        }
        return true
    }

    /// Finds a path to `goal` (or the nearest walkable tile next to it, e.g. when tapping a building).
    /// Returns waypoints (tile centres) excluding the start, or nil if unreachable within `maxNodes`.
    func findPath(to goal: TilePos, maxNodes: Int = 30_000) -> [TilePos]? {
        let start = position.tile
        var target = goal
        if !isWalkableTile(goal) {
            // nearest walkable neighbour of the goal (ring 1…3), closest to the character
            var best: (TilePos, Double)? = nil
            for r in Int32(1)...3 {
                for dy in -r...r { for dx in -r...r where max(abs(dx), abs(dy)) == r {
                    let p = TilePos(goal.x + dx, goal.y + dy)
                    guard isWalkableTile(p) else { continue }
                    let d = Vec2(Double(p.x) + 0.5, Double(p.y) + 0.5).distance(to: position)
                    if best == nil || d < best!.1 { best = (p, d) }
                } }
                if best != nil { break }
            }
            guard let b = best else { return nil }
            target = b.0
        }
        if target == start { return [] }
        if abs(target.x - start.x) > 300 || abs(target.y - start.y) > 300 { return nil }

        // A* with a binary heap keyed by f = g + h (octile distance, costs ×10/×14)
        func h(_ p: TilePos) -> Int {
            let dx = Int(abs(p.x - target.x)), dy = Int(abs(p.y - target.y))
            return 10 * max(dx, dy) + 4 * min(dx, dy)
        }
        var gScore: [TilePos: Int] = [start: 0]
        var came: [TilePos: TilePos] = [:]
        var heap: [(f: Int, p: TilePos)] = [(h(start), start)]
        func push(_ e: (f: Int, p: TilePos)) {
            heap.append(e); var i = heap.count - 1
            while i > 0 { let pa = (i - 1) / 2; if heap[pa].f <= heap[i].f { break }; heap.swapAt(pa, i); i = pa }
        }
        func pop() -> (f: Int, p: TilePos) {
            let top = heap[0]; let last = heap.removeLast()
            if !heap.isEmpty {
                heap[0] = last; var i = 0
                while true {
                    let l = 2 * i + 1, r = l + 1; var m = i
                    if l < heap.count && heap[l].f < heap[m].f { m = l }
                    if r < heap.count && heap[r].f < heap[m].f { m = r }
                    if m == i { break }; heap.swapAt(i, m); i = m
                }
            }
            return top
        }
        var expanded = 0
        let dirs: [(Int32, Int32, Int)] = [(1, 0, 10), (-1, 0, 10), (0, 1, 10), (0, -1, 10), (1, 1, 14), (1, -1, 14), (-1, 1, 14), (-1, -1, 14)]
        while !heap.isEmpty && expanded < maxNodes {
            let cur = pop().p
            if cur == target {
                var path: [TilePos] = [cur]
                var c = cur
                while let p = came[c], p != start { path.append(p); c = p }
                return path.reversed()
            }
            expanded += 1
            let g = gScore[cur] ?? .max
            for (dx, dy, cost) in dirs {
                let n = TilePos(cur.x + dx, cur.y + dy)
                guard isWalkableTile(n) else { continue }
                if dx != 0 && dy != 0 && (!isWalkableTile(TilePos(cur.x + dx, cur.y)) || !isWalkableTile(TilePos(cur.x, cur.y + dy))) { continue }
                let ng = g + cost
                if ng < (gScore[n] ?? .max) {
                    gScore[n] = ng; came[n] = cur
                    push((ng + h(n), n))
                }
            }
        }
        return nil
    }

    /// Starts walking to a tile. Returns false if no path exists.
    @discardableResult
    func walk(to goal: TilePos) -> Bool {
        guard let p = findPath(to: goal) else { walkPath = []; return false }
        walkPath = p
        return true
    }

    var isWalkingPath: Bool { !walkPath.isEmpty }
    func cancelWalk() { walkPath = [] }

    /// Movement input derived from the current path (called by `move()` when there is no joystick input).
    internal func pathSteering() -> Vec2? {
        while let next = walkPath.first {
            let c = Vec2(Double(next.x) + 0.5, Double(next.y) + 0.5)
            let d = c - position
            if d.length < 0.2 { walkPath.removeFirst(); continue }
            return Vec2(d.x / d.length, d.y / d.length)
        }
        return nil
    }
}
