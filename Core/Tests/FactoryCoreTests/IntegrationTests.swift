// Gearforge — end-to-end "first minutes" playthrough on a real generated freeplay map, driven only through
// PlayerCommands (what the UI does).

import XCTest
@testable import FactoryCore

final class IntegrationTests: XCTestCase {

    private func nearest(_ w: World, _ resource: String, from p: TilePos, radius: Int32 = 90) -> TilePos? {
        let r = w.db.resource(resource)
        var best: (TilePos, Int32)? = nil
        var y = p.y - radius
        while y <= p.y + radius {
            var x = p.x - radius
            while x <= p.x + radius {
                let t = TilePos(x, y)
                _ = w.surface.chunk(at: t)
                if w.surface.resource(at: t).0 == r && w.entity(at: t) == nil {
                    let d = abs(x - p.x) + abs(y - p.y)
                    if best == nil || d < best!.1 { best = (t, d) }
                }
                x += 1
            }
            y += 1
        }
        return best?.0
    }

    func testFirstMinutesOfFreeplay() throws {
        var s = WorldSettings(); s.seed = 2024; s.width = 512; s.height = 512
        let session = GameSession.newFreeplay(settings: s)
        let w = session.world
        let pl = w.player!
        let spawn = pl.position.tile
        XCTAssertEqual(pl.count(of: w.item("burner_mining_drill")), 1)

        // 1. hand-mine 5 stone and 10 coal
        for (res, n) in [("stone", 5), ("coal", 10)] {
            let t = try XCTUnwrap(nearest(w, res, from: spawn), "no \(res) near spawn")
            pl.position = Vec2(Double(t.x) + 0.5, Double(t.y) + 1.6)
            XCTAssertTrue(w.execute(.startMining(t)).isOK, "mine \(res)")
            session.run(ticks: n * 125)
            w.execute(.stopMining)
            XCTAssertGreaterThanOrEqual(pl.count(of: w.item(res)), n, res)
        }
        // 2. craft a second stone furnace (5 stone)
        XCTAssertTrue(w.execute(.craft(recipe: w.db.recipe("stone_furnace"), count: 1)).isOK)
        session.run(ticks: 60 * 1)
        XCTAssertEqual(pl.count(of: w.item("stone_furnace")), 2)

        // 3. burner drill on iron, furnace in front of its output
        let iron = try XCTUnwrap(nearest(w, "iron_ore", from: spawn), "no iron near spawn")
        pl.position = Vec2(Double(iron.x) + 3.5, Double(iron.y) + 0.5)
        var placed: TilePos? = nil
        search: for dy in Int32(0)...6 {
            for dx in Int32(0)...6 {
                let o = TilePos(iron.x + dx - 3, iron.y + dy - 3)
                if w.execute(.build(item: w.item("burner_mining_drill"), origin: o, direction: .north)).isOK { placed = o; break search }
            }
        }
        let drillOrigin = try XCTUnwrap(placed, "could not place burner drill on iron")
        let drill = w.entity(at: drillOrigin)!
        // drill outputs at centre + (-0.5, -1.3) → tile (origin.x, origin.y - 1); furnace 2×2 whose footprint covers it
        let furnaceOrigin = TilePos(drillOrigin.x - 1, drillOrigin.y - 2)
        // clear trees/rocks if any
        for e in w.entities(in: TileRect(origin: furnaceOrigin, w: 2, h: 2)) where !w.entities[e].flags.contains(.playerBuilt) { w.removeEntity(e) }
        XCTAssertTrue(w.execute(.build(item: w.item("stone_furnace"), origin: furnaceOrigin, direction: .north)).isOK, "furnace")
        let furnace = w.entity(at: furnaceOrigin)!
        XCTAssertTrue(w.execute(.transferToEntity(entity: drill, item: w.item("coal"), count: 5)).isOK)
        XCTAssertTrue(w.execute(.transferToEntity(entity: furnace, item: w.item("coal"), count: 5)).isOK)

        // 4. two minutes later: iron plates
        session.run(ticks: 60 * 120)
        let plates = w.crafting.outputSlots(of: furnace).first { Int($0.item) == w.item("iron_plate") }?.count ?? 0
        XCTAssertGreaterThan(plates, 15, "burner drill → furnace produces plates")
        XCTAssertTrue(w.execute(.takeAll(entity: furnace)).isOK)
        XCTAssertGreaterThan(pl.count(of: w.item("iron_plate")), 15)

        // 5. save → load keeps it all
        let b = try GameSession.decode(payload: session.encodePayload())
        XCTAssertEqual(b.world.player.count(of: w.item("iron_plate")), pl.count(of: w.item("iron_plate")))
        XCTAssertEqual(b.world.entities.liveCount, w.entities.liveCount)
    }
}
