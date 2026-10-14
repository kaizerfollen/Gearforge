// Gearforge — progression & persistence tests (world codec, save manager, session, campaign levels, objectives).

import XCTest
@testable import FactoryCore

final class ProgressionTests: XCTestCase {

    /// A small but complete factory: steam power, burner + electric mining, belts, inserters, furnaces, assembler, lab.
    private func buildFactory() -> GameSession {
        var s = WorldSettings(); s.seed = 42; s.width = 128; s.height = 128; s.treeCoverage = 0; s.rocks = false
        let w = World(settings: s)
        let grass = w.db.tile("grass_1"), water = w.db.tile("water")
        for y in 0..<40 { for x in 0..<40 {
            let p = TilePos(x, y); _ = w.surface.chunk(at: p)
            if let e = w.entity(at: p) { w.removeEntity(e) }
            w.surface.setTile(at: p, x <= 1 ? water : grass); w.surface.setResource(at: p, -1, amount: 0)
        } }
        // steam plant (same layout as EnergyTests)
        w.place("offshore_pump", 2, 15, .west); w.place("pipe", 3, 15)
        let boiler = w.place("boiler", 4, 14, .north)
        w.place("steam_engine", 4, 9, .north); w.place("steam_engine", 4, 4, .north)
        _ = w.power.insert(boiler, item: w.item("coal"), count: 50, source: .player)
        // iron ore patch + electric drill → belt → inserter → furnace
        let ore = w.db.resource("iron_ore")
        TileRect(x: 14, y: 20, w: 5, h: 5).forEach { w.surface.setResource(at: $0, ore, amount: 500) }
        w.place("electric_mining_drill", 15, 21, .north)          // outputs to (16,20)
        for x in 12...24 { w.place("transport_belt", x, 20, .east) }
        w.place("inserter", 20, 19, .north)                      // belt (20,20) → furnace above
        let furnace = w.place("stone_furnace", 20, 17)
        _ = w.crafting.insert(furnace, item: w.item("coal"), count: 20, source: .player)
        // poles
        for (x, y) in [(7, 10), (12, 12), (17, 17), (22, 19), (18, 22)] { w.place("small_electric_pole", x, y) }
        // assembler making gears from a chest
        let a = w.place("assembling_machine_1", 26, 10)
        _ = w.crafting.setRecipe(a, w.db.recipe("iron_gear_wheel"))
        _ = w.crafting.insert(a, item: w.item("iron_plate"), count: 100, source: .player)
        w.place("medium_electric_pole", 25, 13)
        w.place("medium_electric_pole", 20, 13)
        // a lab researching
        let lab = w.place("lab", 30, 15)
        w.place("medium_electric_pole", 29, 14)
        w.research.setCurrent(w.db.tech("automation"))
        _ = w.labs.insert(lab, item: w.item("mechanics_card"), count: 10, source: .player)
        // player state
        w.player.position = Vec2(10.5, 18.5)
        w.player.giveStartingKit()
        _ = w.execute(.craft(recipe: w.db.recipe("iron_gear_wheel"), count: 3))
        return GameSession(world: w, mode: .freeplay)
    }

    /// Fingerprint of everything observable.
    private func fingerprint(_ w: World) -> [String] {
        var f: [String] = ["tick \(w.tick)", "ents \(w.entities.liveCount)", "belt \(w.belts.totalItemCount)",
                           "pos \(w.player.position)", "inv \(w.player.inventory.contents().map { "\($0.item):\($0.count)" })",
                           "queue \(w.player.craftQueue.map { "\($0.recipe)x\($0.count)" })",
                           "research \(w.research.progressUnits(of: w.db.tech("automation")))",
                           "rng \(w.rng.state.0)"]
        for id in ["iron_ore", "iron_plate", "iron_gear_wheel", "coal"] {
            let i = w.item(id); f.append("\(id) \(w.stats.totalProduced(item: i))/\(w.stats.totalConsumed(item: i))")
        }
        w.entities.forEachLive { e, r in
            switch r.kind {
            case .assemblingMachine, .furnace: f.append("m\(e) \(w.crafting.progress(of: e)) \(w.crafting.outputSlots(of: e).map { $0.count })")
            case .container: f.append("c\(e) \(w.containers.inventory(of: e)!.contents().map { $0.count })")
            case .inserter: f.append("i\(e) \(w.inserters.handPosition(of: e)) \(w.inserters.heldStack(of: e).count)")
            case .miningDrill: f.append("d\(e) \(w.mining.progress(of: e))")
            case .generator, .boiler: f.append("g\(e) \(w.fluids.amount(e, box: 0))")
            default: break
            }
        }
        return f
    }

    func testSaveLoadContinuesIdentically() throws {
        let a = buildFactory()
        a.run(ticks: 1200)
        let payload = a.encodePayload()
        let b = try GameSession.decode(payload: payload)
        XCTAssertEqual(fingerprint(a.world), fingerprint(b.world), "state right after load")
        a.run(ticks: 1800); b.run(ticks: 1800)
        XCTAssertEqual(fingerprint(a.world), fingerprint(b.world), "simulation continues identically after load")
        XCTAssertGreaterThan(a.world.stats.totalProduced(item: a.world.item("iron_ore")), 10, "factory actually ran")
    }

    func testSaveManagerSlotsAndAutosave() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gf-saves-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let sm = SaveManager(directory: dir)
        let s = buildFactory()
        s.run(ticks: 120)
        let m = try sm.save(s, slot: "My factory")
        XCTAssertEqual(m.gameTick, 120)
        XCTAssertEqual(sm.listSaves().map(\.slot), ["My factory"])
        XCTAssertEqual(sm.listSaves().first?.mapWidth, 128)
        let loaded = try sm.load(slot: "My factory")
        XCTAssertEqual(loaded.world.tick, 120)
        // autosave rotation over 3 slots
        var slots: [String] = []
        for _ in 0..<4 { slots.append(try sm.autosave(s, slots: 3).slot); Thread.sleep(forTimeInterval: 0.01) }
        XCTAssertEqual(Array(slots.prefix(3)), ["autosave_1", "autosave_2", "autosave_3"])
        XCTAssertEqual(slots[3], "autosave_1", "oldest autosave is overwritten")
        XCTAssertEqual(sm.mostRecent?.slot, "autosave_1")
        try sm.rename(slot: "My factory", to: "Base")
        try sm.duplicate(slot: "Base", as: "Base copy")
        XCTAssertThrowsError(try sm.rename(slot: "Base", to: "Base copy"))
        XCTAssertThrowsError(try sm.save(s, slot: "../evil"))
        try sm.delete(slot: "Base copy")
        XCTAssertEqual(Set(sm.listSaves().map(\.slot)), ["Base", "autosave_1", "autosave_2", "autosave_3"])
        // crash recovery marker
        XCTAssertFalse(sm.markSessionStarted())
        XCTAssertTrue(sm.markSessionStarted(), "previous session never ended cleanly")
        sm.markSessionEnded()
        XCTAssertFalse(sm.hadUncleanExit)
    }

    func testCorruptSaveIsRejected() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gf-bad-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let sm = SaveManager(directory: dir)
        let s = buildFactory()
        try sm.save(s, slot: "x")
        var bytes = [UInt8](try Data(contentsOf: sm.url(for: "x")))
        bytes[bytes.count - 100] ^= 0xFF
        try Data(bytes).write(to: sm.url(for: "x"))
        XCTAssertThrowsError(try sm.load(slot: "x")) { e in XCTAssertEqual(e as? SaveError, .checksumMismatch) }
        try Data([1, 2, 3]).write(to: sm.url(for: "y"))
        XCTAssertThrowsError(try sm.load(slot: "y"))
    }

    func testAutosaveScheduling() {
        let s = buildFactory()
        s.autosaveIntervalSeconds = 2
        XCTAssertFalse(s.autosaveDue)
        for _ in 0..<130 { s.advance(realSeconds: 1.0 / 60.0) }
        XCTAssertTrue(s.autosaveDue)
        s.didAutosave()
        XCTAssertFalse(s.autosaveDue)
    }

    func testFixedStepDoesNotSpiral() {
        let s = buildFactory()
        let n = s.advance(realSeconds: 5)        // device hitch
        XCTAssertEqual(n, 4)
        s.isPaused = true
        XCTAssertEqual(s.advance(realSeconds: 1), 0)
    }

    // MARK: Campaign

    func testLevelDefinitionsAreValid() {
        let db = PrototypeDB.shared
        XCTAssertEqual(Campaign.levels.map(\.id), ["L1", "L2", "L3", "L4", "L5", "L6", "L7", "L8"])
        for l in Campaign.levels {
            XCTAssertEqual(l.settings.width % 32, 0)
            for it in l.startingItems { XCTAssertGreaterThanOrEqual(db.item(it.id), 0, "\(l.id) item \(it.id)") }
            for t in l.researched + (l.availableTechs ?? []) { XCTAssertGreaterThanOrEqual(db.tech(t), 0, "\(l.id) tech \(t)") }
            for o in l.objectives {
                switch o.kind {
                case .produceItem(let i, _, _), .handMine(let i, _), .craftItem(let i, _), .productionRate(let i, _, _):
                    XCTAssertGreaterThanOrEqual(db.item(i), 0, "\(l.id) objective item \(i)")
                case .research(let t): XCTAssertGreaterThanOrEqual(db.tech(t), 0, "\(l.id) objective tech \(t)")
                case .buildEntity(let e, _):
                    XCTAssertTrue(db.entities.contains { $0.id.hasPrefix(e) }, "\(l.id) objective entity \(e)")
                default: break
                }
            }
            XCTAssertTrue(l.victoryObjectives.allSatisfy { v in l.objectives.contains { $0.id == v } })
            XCTAssertLessThan(l.goldSeconds, l.parSeconds)
        }
    }

    func testCampaignL1ObjectivesProgress() throws {
        let s = GameSession.newCampaign(level: Campaign.level("L1")!)
        let w = s.world
        XCTAssertEqual(w.player.count(of: w.item("burner_mining_drill")), 1)
        XCTAssertFalse(w.research.researchEnabled)
        XCTAssertEqual(s.objectives.active.map(\.id), [1, 2])
        w.stats.producedByHandMining(item: w.item("stone"), count: 10)
        s.run(ticks: 30)
        XCTAssertTrue(s.objectives.states[1]!.completed)
        XCTAssertEqual(s.objectives.active.map(\.id), [2, 3])
        // round trip keeps objective state
        let b = try GameSession.decode(payload: s.encodePayload())
        XCTAssertEqual(b.mode, .campaign(levelID: "L1"))
        XCTAssertTrue(b.objectives.states[1]!.completed)
        XCTAssertEqual(b.level?.id, "L1")
    }

    func testCampaignTechRestrictions() {
        let s = GameSession.newCampaign(level: Campaign.level("L3")!)
        let r = s.world.research!
        XCTAssertTrue(r.isResearched(s.world.db.tech("automation")))
        XCTAssertTrue(r.isAvailable(s.world.db.tech("steel_processing")))
        XCTAssertFalse(r.isAvailable(s.world.db.tech("automation_2")), "T2 tech not offered in L3")
    }

    func testCampaignProgressStore() throws {
        var p = CampaignProgress()
        XCTAssertTrue(p.isUnlocked("L1")); XCTAssertFalse(p.isUnlocked("L2"))
        p.record(level: "L1", stars: 2, seconds: 1000)
        p.record(level: "L1", stars: 1, seconds: 800)
        XCTAssertEqual(p.levels["L1"], .init(stars: 2, bestSeconds: 800))
        XCTAssertTrue(p.isUnlocked("L2"))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("gf-progress-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try p.save(to: url)
        XCTAssertEqual(CampaignProgress.load(from: url), p)
    }

    func testSaveSizeAndSpeed() throws {
        var st = WorldSettings(); st.seed = 5; st.width = 512; st.height = 512
        let w = World(settings: st)
        // generate a 256×256 area (64 chunks) like an explored mid-game map
        for cy in -4..<4 { for cx in -4..<4 { _ = w.surface.chunk(ChunkPos(Int32(cx), Int32(cy))) } }
        let s = GameSession(world: w, mode: .freeplay)
        let t0 = DispatchTime.now().uptimeNanoseconds
        let bytes = s.encodePayload()
        let t1 = DispatchTime.now().uptimeNanoseconds
        _ = try GameSession.decode(payload: bytes)
        let t2 = DispatchTime.now().uptimeNanoseconds
        print("PERF save: \(bytes.count / 1024) KB, encode \(Double(t1 - t0) / 1e6) ms, decode \(Double(t2 - t1) / 1e6) ms, entities \(w.entities.liveCount)")
        XCTAssertLessThan(bytes.count, 20 << 20)
    }

    /// Tutorial levels put every starting resource within a short walk of spawn (no map needed), and the layout
    /// override is saved so chunks generated after a load are identical.
    func testTutorialPatchesNearSpawnAndLayoutSurvivesLoad() throws {
        for (id, maxDist) in [("L1", 16.0), ("L2", 22.0)] {
            let level = Campaign.levels.first { $0.id == id }!
            let s = GameSession.newCampaign(level: level)
            let w = s.world
            for res in ["iron_ore", "copper_ore", "coal", "stone"] {
                let r = w.db.resource(res)
                var best = Double.infinity
                for y in -30...30 { for x in -30...30 {
                    let (rr, amt) = w.surface.resource(at: TilePos(Int32(x), Int32(y)))
                    if rr == r && amt > 0 { best = min(best, Double(x * x + y * y).squareRoot()) }
                } }
                XCTAssertLessThan(best, maxDist, "\(id): \(res) nearest tile \(best) from spawn")
            }
            let b = try GameSession.decode(payload: s.encodePayload())
            XCTAssertEqual(b.world.settings.layout, level.settings.layout)
            XCTAssertEqual(b.world.mapGen.startingPatches, w.mapGen.startingPatches, "\(id): layout restored after load")
        }
    }

    /// Settings written by an older version (missing newer keys, with an unknown key) keep the saved values.
    func testSettingsDecodeTolerant() {
        let old = #"{"haptics": false, "autosaveMinutes": 10, "someRemovedKey": 3}"#.data(using: .utf8)!
        let s = GameSettings.decodeTolerant(old)
        XCTAssertNotNil(s)
        XCTAssertEqual(s?.haptics, false)
        XCTAssertEqual(s?.autosaveMinutes, 10)
        XCTAssertEqual(s?.tutorialHints, true, "new key gets its default")
        XCTAssertNil(GameSettings.decodeTolerant(Data("nope".utf8)))
    }

    func testSaveThumbnailRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gf-thumb-\(UUID().uuidString)")
        let sm = SaveManager(directory: dir)
        let s = GameSession.newCampaign(level: Campaign.levels[0])
        let png = Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3, 4])
        try sm.save(s, slot: "t1", displayName: "T", thumbnailPNG: png)
        try sm.autosave(s, slots: 2, thumbnailPNG: png)
        XCTAssertEqual(sm.thumbnail(slot: "t1"), png)
        XCTAssertEqual(sm.thumbnail(slot: "autosave_1"), png)
        XCTAssertNil(sm.thumbnail(slot: "missing"))
        XCTAssertNil(sm.listSaves().first { $0.slot == "t1" }?.thumbnailPNG, "list without thumbnails stays light")
        try? FileManager.default.removeItem(at: dir)
    }
}
