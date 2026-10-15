// Gearforge — guided tutorial: the L1 script can be completed step by step, with sensible highlight targets.

import XCTest
@testable import FactoryCore

final class TutorialTests: XCTestCase {

    func testWalkthroughOnL1() throws {
        let s = GameSession.newCampaign(level: Campaign.levels[0])
        let w = s.world
        let db = w.db
        let t = Tutorial(world: w)
        var ui = TutorialUIState()

        var h = try XCTUnwrap(t.update(ui: ui))
        XCTAssertEqual(h.id, "welcome"); XCTAssertTrue(h.needsNext)
        t.next()
        h = try XCTUnwrap(t.update(ui: ui)); XCTAssertEqual(h.id, "move")
        XCTAssertEqual(h.target, .hud(["joystick"]))
        w.player.position = w.player.position + Vec2(3, 0)

        h = try XCTUnwrap(t.update(ui: ui)); XCTAssertEqual(h.id, "mineStone")
        guard case .tiles(let stoneRect) = h.target else { return XCTFail("stone not highlighted") }
        XCTAssertEqual(w.surface.resource(at: TilePos(stoneRect.x + 1, stoneRect.y + 1)).0, db.resource("stone"))
        XCTAssertEqual(h.args, ["0", "5"])
        // a panel in the way of a world step → "close it"
        XCTAssertEqual(t.update(ui: TutorialUIState(panel: "inventory"))?.target, .hud(["panel.close"]))
        w.player.give(db.item("stone"), 5)

        h = try XCTUnwrap(t.update(ui: ui)); XCTAssertEqual(h.id, "mineCoal")
        guard case .tiles(let coalRect) = h.target else { return XCTFail("coal not highlighted") }
        XCTAssertEqual(w.surface.resource(at: TilePos(coalRect.x + 1, coalRect.y + 1)).0, db.resource("coal"))
        w.player.give(db.item("coal"), 8)

        h = try XCTUnwrap(t.update(ui: ui)); XCTAssertEqual(h.id, "selectDrill")
        ui.buildItem = db.item("burner_mining_drill")
        h = try XCTUnwrap(t.update(ui: ui)); XCTAssertEqual(h.id, "placeDrill")
        guard case .tiles(let spot) = h.target else { return XCTFail("no drill spot") }
        XCTAssertLessThan(w.player.position.distance(to: spot.center), 30, "spot near the start")
        // stand next to it and build
        w.player.position = spot.center + Vec2(0, 3)
        XCTAssertTrue(w.execute(.build(item: ui.buildItem, origin: TilePos(spot.x, spot.y), direction: .north)).isOK)

        h = try XCTUnwrap(t.update(ui: ui)); XCTAssertEqual(h.id, "selectFurnace")
        ui.buildItem = db.item("stone_furnace")
        h = try XCTUnwrap(t.update(ui: ui)); XCTAssertEqual(h.id, "placeFurnace")
        guard case .tiles(let fspot) = h.target else { return XCTFail("no furnace spot") }
        XCTAssertTrue(w.execute(.build(item: ui.buildItem, origin: TilePos(fspot.x, fspot.y), direction: .north)).isOK)
        ui.buildItem = -1

        h = try XCTUnwrap(t.update(ui: ui)); XCTAssertEqual(h.id, "fuelDrill")
        let drill = try XCTUnwrap(t.drillOnIron())
        let furnace = try XCTUnwrap(t.furnaceAtOutput())
        guard case .tiles = h.target else { return XCTFail("drill not highlighted") }
        // with the drill screen open the coal in the inventory strip is highlighted
        XCTAssertEqual(t.update(ui: TutorialUIState(panel: "entity", openEntity: drill))?.target,
                       .hud(["insert.\(db.item("coal"))", "insert.\(db.item("wood"))"]))
        XCTAssertTrue(w.execute(.transferToEntity(entity: drill, item: db.item("coal"), count: 4)).isOK)

        h = try XCTUnwrap(t.update(ui: ui)); XCTAssertEqual(h.id, "fuelFurnace")
        XCTAssertTrue(w.execute(.transferToEntity(entity: furnace, item: db.item("coal"), count: 4)).isOK)

        h = try XCTUnwrap(t.update(ui: ui)); XCTAssertEqual(h.id, "waitPlates")
        var ticks = 0
        while t.update(ui: ui)?.id == "waitPlates" && ticks < 60 * 60 { w.step(); ticks += 1 }
        h = try XCTUnwrap(t.update(ui: ui)); XCTAssertEqual(h.id, "takePlates", "plates within a minute (took \(ticks) ticks)")
        let out = w.crafting.outputSlots(of: furnace).first { !$0.isEmpty }
        let plates = try XCTUnwrap(out)
        XCTAssertTrue(w.execute(.transferFromEntity(entity: furnace, item: Int(plates.item), count: Int(plates.count))).isOK)

        h = try XCTUnwrap(t.update(ui: ui)); XCTAssertEqual(h.id, "craftDrill")
        XCTAssertEqual(h.target, .hud(["inventory"]))
        if case .hud(let ids) = t.update(ui: TutorialUIState(panel: "inventory"))?.target {
            XCTAssertEqual(ids.first, "recipe.\(db.recipe("burner_mining_drill"))")
            XCTAssertEqual(ids[1], "group.1", "drills are in the Production tab")
        } else { XCTFail("recipe not highlighted") }
        XCTAssertTrue(w.execute(.craft(recipe: db.recipe("burner_mining_drill"), count: 1)).isOK)

        h = try XCTUnwrap(t.update(ui: ui)); XCTAssertEqual(h.id, "openMap")
        h = try XCTUnwrap(t.update(ui: TutorialUIState(panel: "map"))); XCTAssertEqual(h.id, "goals")
        XCTAssertTrue(h.isLast)
        t.next()
        XCTAssertNil(t.update(ui: ui))
        XCTAssertTrue(t.isFinished)
    }

    func testResumedGameSkipsDoneSteps() throws {
        let s = GameSession.newCampaign(level: Campaign.levels[0])
        let w = s.world, db = w.db
        let t0 = Tutorial(world: w)
        w.player.give(db.item("stone"), 5); w.player.give(db.item("coal"), 5)
        guard case .tiles(let spot) = t0.drillSpot().map({ TutorialTarget.tiles($0) }) ?? .none else { return XCTFail() }
        w.player.position = spot.center + Vec2(0, 3)
        XCTAssertTrue(w.execute(.build(item: db.item("burner_mining_drill"), origin: TilePos(spot.x, spot.y), direction: .north)).isOK)
        // a fresh tutorial (e.g. after loading) jumps past welcome… placeDrill once Next is pressed
        let t = Tutorial(world: w)
        XCTAssertEqual(t.update(ui: TutorialUIState())?.id, "welcome")
        t.next()
        XCTAssertEqual(t.update(ui: TutorialUIState())?.id, "selectFurnace")
    }

    func testSkip() {
        let s = GameSession.newCampaign(level: Campaign.levels[0])
        let t = Tutorial(world: s.world)
        t.skipAll()
        XCTAssertNil(t.update(ui: TutorialUIState()))
    }
}
