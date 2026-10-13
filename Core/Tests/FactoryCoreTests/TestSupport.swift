// Gearforge — shared test helpers.

import XCTest
@testable import FactoryCore

enum TestWorld {
    /// Small world whose area [0, size) × [0, size) is flat grass with no trees/rocks/entities.
    static func make(size: Int = 64, seed: UInt64 = 7) -> World {
        var s = WorldSettings()
        s.seed = seed
        let side = max(64, ((size * 2) + 31) / 32 * 32)
        s.width = side; s.height = side   // surface is centred on (0,0); multiple of 32
        s.treeCoverage = 0
        s.rocks = false
        let w = World(settings: s)
        w.recordsEvents = false
        let grass = w.db.tile("grass_1")
        for y in 0..<size {
            for x in 0..<size {
                let p = TilePos(x, y)
                _ = w.surface.chunk(at: p)
                if let e = w.entity(at: p) { w.removeEntity(e) }
                w.surface.setTile(at: p, grass)
                w.surface.setResource(at: p, -1, amount: 0)
            }
        }
        return w
    }
}

extension World {
    func proto(_ id: String) -> Int {
        let p = db.entity(id)
        precondition(p >= 0, "missing entity \(id)")
        return p
    }
    @discardableResult
    func place(_ id: String, _ x: Int, _ y: Int, _ d: Direction = .north) -> Int32 {
        let p = proto(id)
        precondition(canPlace(proto: p, origin: TilePos(x, y), direction: d) == nil, "cannot place \(id) at \(x),\(y)")
        return createEntity(proto: p, origin: TilePos(x, y), direction: d)
    }
    func item(_ id: String) -> Int {
        let i = db.item(id)
        precondition(i >= 0, "missing item \(id)")
        return i
    }
}
