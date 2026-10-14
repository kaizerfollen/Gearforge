// Gearforge — QA S9: copy/paste (natural obstacles, rotation), save rename. See docs/team/qa_s9.md.

import XCTest
@testable import FactoryCore

final class QAS9Tests: XCTestCase {

    private func natural(_ w: World, _ id: String, _ x: Int, _ y: Int) -> Int32 {
        let e = w.place(id, x, y)
        w.entities.update(e) { $0.flags = [] }
        return e
    }

    // S9-1: a paste that can't be built anyway (water / no ore) must not destroy the trees in the way,
    // and the preview must not show it as valid.

    func testPasteDoesNotHarvestTreesWhenWaterStillBlocks() {
        let w = TestWorld.make()
        w.place("stone_furnace", 1, 1)                                  // 2×2
        let bp = w.captureBlueprint(TileRect(x: 0, y: 0, w: 4, h: 4))
        XCTAssertEqual(bp.entries.count, 1)
        let tree = natural(w, "tree_01", 20, 20)
        w.surface.setTile(at: TilePos(21, 21), w.db.tile("water"))
        XCTAssertFalse(w.blueprintPreview(bp, at: TilePos(20, 20)).first!.ok, "water under the footprint → red")
        XCTAssertEqual(w.pasteBlueprint(bp, at: TilePos(20, 20)), 0)
        XCTAssertTrue(w.entities[tree].isAlive, "tree not cut down for a ghost that was never placed")
        XCTAssertEqual(w.player.count(of: w.item("wood")), 0)
    }

    func testPasteDoesNotHarvestTreesWhenDrillHasNoOre() {
        let w = TestWorld.make()
        let iron = w.db.resource("iron_ore")
        TileRect(x: 1, y: 1, w: 2, h: 2).forEach { w.surface.setResource(at: $0, iron, amount: 100) }
        w.place("burner_mining_drill", 1, 1)
        let bp = w.captureBlueprint(TileRect(x: 0, y: 0, w: 4, h: 4))
        XCTAssertEqual(bp.entries.count, 1)
        let tree = natural(w, "tree_01", 30, 30)                       // no ore at 30,30
        XCTAssertFalse(w.blueprintPreview(bp, at: TilePos(30, 30)).first!.ok)
        XCTAssertEqual(w.pasteBlueprint(bp, at: TilePos(30, 30)), 0)
        XCTAssertTrue(w.entities[tree].isAlive)
    }

    func testPasteStillClearsTreesWhenTheGhostFits() {
        let w = TestWorld.make()
        w.place("stone_furnace", 1, 1)
        let bp = w.captureBlueprint(TileRect(x: 0, y: 0, w: 4, h: 4))
        let t1 = w.entities.handle(natural(w, "tree_01", 20, 20))
        let t2 = w.entities.handle(natural(w, "tree_01", 21, 21))
        XCTAssertTrue(w.blueprintPreview(bp, at: TilePos(20, 20)).first!.ok)
        XCTAssertEqual(w.pasteBlueprint(bp, at: TilePos(20, 20)), 1)
        XCTAssertNil(w.entities.resolve(t1)); XCTAssertNil(w.entities.resolve(t2))
        XCTAssertEqual(w.player.count(of: w.item("wood")), 8)
    }

    // Rotation regression: every rotated entry stays inside the rotated bounds, nothing overlaps, 4 turns = identity.

    func testRotatedBlueprintStaysInBoundsAndPastes() {
        let w = TestWorld.make()
        w.place("transport_belt", 1, 1, .east)
        w.place("splitter", 2, 1, .east)                                // 1×2 when facing east
        w.place("stone_furnace", 4, 1)
        w.place("inserter", 6, 2, .west)
        let bp = w.captureBlueprint(TileRect(x: 0, y: 0, w: 10, h: 10))
        XCTAssertEqual(bp.entries.count, 4)
        XCTAssertEqual(bp.rotated(4, db: w.db), bp)
        XCTAssertEqual(bp.rotated(-1, db: w.db), bp.rotated(3, db: w.db))
        for q in 0..<4 {
            let r = bp.rotated(q, db: w.db)
            var used = Set<TilePos>()
            for e in r.entries {
                let (fw, fh) = w.footprint(w.db.entity(e.entity), e.direction)
                TileRect(origin: TilePos(e.dx, e.dy), w: fw, h: fh).forEach { p in
                    XCTAssertTrue(p.x >= 0 && p.y >= 0 && p.x < r.width && p.y < r.height, "q=\(q) \(e.entity) out of bounds")
                    XCTAssertTrue(used.insert(p).inserted, "q=\(q) overlap at \(p)")
                }
            }
            let origin = TilePos(Int32(12 + q * 12), 20)
            XCTAssertEqual(w.pasteBlueprint(r, at: origin), 4, "rotation \(q) pastes completely")
        }
    }

    // S9-2: renaming a save to a reserved slot name lets autosave / background save overwrite it later.

    func testRenameRejectsReservedSlotNames() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gf-s9-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let sm = SaveManager(directory: dir)
        let s = GameSession(world: TestWorld.make(), mode: .freeplay)
        try sm.save(s, slot: "Mine")
        for bad in ["background", "autosave_1", "autosave_exit", " autosave_2 "] {
            XCTAssertThrowsError(try sm.rename(slot: "Mine", to: bad), bad)
        }
        XCTAssertEqual(sm.listSaves().map(\.slot), ["Mine"], "original untouched")
        try sm.rename(slot: "Mine", to: "My autosave_1 copy")
        XCTAssertEqual(sm.listSaves().map(\.slot), ["My autosave_1 copy"])
    }
}
