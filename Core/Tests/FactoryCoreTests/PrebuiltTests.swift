// Gearforge — pre-built campaign factories (L5–L8): layout validity, power, sustained card production, save/load.

import XCTest
@testable import FactoryCore

final class PrebuiltTests: XCTestCase {

    /// Layout of each level stamps without a single placement failure.
    func testLayoutsPlaceCleanly() {
        for id in ["L5", "L6", "L7", "L8"] {
            let level = Campaign.level(id)!
            XCTAssertTrue(level.prebuilt, "\(id) is marked prebuilt")
            let w = World(settings: level.settings)
            let r = PrebuiltFactory.build(levelID: id, in: w, near: w.mapGen.spawnPosition)!
            XCTAssertEqual(r.failures, [], "\(id) placement failures")
            let spawn = w.mapGen.spawnPosition
            let d = max(max(Int(r.rect.x) - Int(spawn.x), Int(spawn.x) - Int(r.rect.maxX) + 1),
                        max(Int(r.rect.y) - Int(spawn.y), Int(spawn.y) - Int(r.rect.maxY) + 1))
            XCTAssertGreaterThanOrEqual(d, 15, "\(id) factory keeps clear of spawn")
            XCTAssertLessThanOrEqual(d, 40, "\(id) factory is near spawn")
        }
        XCTAssertNil(PrebuiltFactory.build(levelID: "L1", in: TestWorld.make(), near: TilePos(0, 0)))
        XCTAssertFalse(Campaign.level("L4")!.prebuilt)
    }

    func testLevelDefinitionDecodesWithoutPrebuiltKey() throws {
        let l = Campaign.level("L6")!
        let data = try JSONEncoder().encode(l)
        XCTAssertEqual(try JSONDecoder().decode(LevelDefinition.self, from: data), l)
        var obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        obj.removeValue(forKey: "prebuilt")
        let old = try JSONDecoder().decode(LevelDefinition.self, from: try JSONSerialization.data(withJSONObject: obj))
        XCTAssertFalse(old.prebuilt)
        XCTAssertEqual(old.id, "L6")
    }

    func testL5RedGreen() throws { try check("L5", cards: ["mechanics_card": 20, "motion_card": 20]) }
    func testL6RedGreenBlueBasicOil() throws {
        try check("L6", cards: ["mechanics_card": 20, "motion_card": 20, "reaction_card": 5], fluids: ["petroleum_gas"])
    }
    func testL7RedGreenBlueAdvancedOil() throws {
        try check("L7", cards: ["mechanics_card": 20, "motion_card": 20, "reaction_card": 5], fluids: ["petroleum_gas", "heavy_oil", "light_oil"])
    }
    func testL8AllFiveCards() throws {
        try check("L8", cards: ["mechanics_card": 30, "motion_card": 30, "reaction_card": 8, "fabrication_card": 12, "systems_card": 12],
                  fluids: ["petroleum_gas"], warmupSeconds: 75, windowSeconds: 120)
    }

    /// Opt-in profile (GF_LONGRUN=1 swift test -c release --filter testLongRunProfile): 90 game minutes per level,
    /// rates per 10-minute window — shows how long the supply chests last.
    func testLongRunProfile() {
        guard ProcessInfo.processInfo.environment["GF_LONGRUN"] != nil else { return }
        let cards = ["mechanics_card", "motion_card", "reaction_card", "fabrication_card", "systems_card"]
        for id in ["L5", "L6", "L7", "L8"] {
            let s = GameSession.newCampaign(level: Campaign.level(id)!)
            let w = s.world
            var prev = cards.map { w.stats.producedByMachines(item: w.item($0)) }
            for m in stride(from: 10, through: 90, by: 10) {
                s.run(ticks: 600 * 60)
                let now = cards.map { w.stats.producedByMachines(item: w.item($0)) }
                var line = "LONG \(id) t=\(m)min:"
                for (i, c) in cards.enumerated() where now[i] > 0 { line += " \(c.prefix(4)) \(Double(now[i] - prev[i]) / 10)/min" }
                var sat = 0.0, dem = 0.0
                for st in w.power.networkStats { if st.demandW > dem { dem = st.demandW; sat = st.satisfaction } }
                line += " | \(String(format: "%.1f", dem / 1e6)) MW sat \(String(format: "%.2f", sat))"
                print(line)
                prev = now
            }
        }
    }

    // MARK: Helpers

    /// Creates the campaign session, warms up, then measures card production by machines over a window.
    private func check(_ id: String, cards: [String: Double], fluids: [String] = [],
                       warmupSeconds: Int = 90, windowSeconds: Int = 150) throws {
        let s = GameSession.newCampaign(level: Campaign.level(id)!)
        let w = s.world
        // find the plant network via a steam engine
        var engine: Int32 = -1
        w.entities.forEachLive { e, r in if engine < 0 && w.db.entities[Int(r.proto)].id == "steam_engine" { engine = e } }
        XCTAssertGreaterThanOrEqual(engine, 0, "\(id): steam block exists")
        s.run(ticks: warmupSeconds * 60)
        let before = cards.keys.map { (k: $0, v: w.stats.producedByMachines(item: w.item($0))) }
        s.run(ticks: windowSeconds * 60)
        let net = w.power.networkID(of: engine)
        XCTAssertGreaterThanOrEqual(net, 0)
        let st = w.power.stats(network: net)!
        XCTAssertGreaterThanOrEqual(st.satisfaction, 0.9, "\(id): power satisfaction \(st.satisfaction)")
        // every powered machine is on the plant network
        var off: [String] = []
        w.entities.forEachLive { e, r in
            switch r.kind {
            case .assemblingMachine, .lab, .inserter, .miningDrill, .furnace, .generator:
                if w.power.networkID(of: e) != net { off.append("\(w.db.entities[Int(r.proto)].id)@\(r.origin)") }
            default: break
            }
        }
        XCTAssertEqual(off, [], "\(id): machines not on the plant network")
        var line = "PREBUILT \(id): \(String(format: "%.1f", st.demandW / 1e6)) MW demand / \(String(format: "%.1f", st.capacityW / 1e6)) MW capacity, sat \(String(format: "%.2f", st.satisfaction))"
        for b in before {
            let made = Double(w.stats.producedByMachines(item: w.item(b.k)) - b.v)
            let perMin = made / (Double(windowSeconds) / 60)
            line += ", \(b.k) \(String(format: "%.1f", perMin))/min"
            XCTAssertGreaterThanOrEqual(perMin, cards[b.k]!, "\(id): \(b.k) rate")
        }
        print(line)
        for f in fluids {
            XCTAssertGreaterThan(w.stats.totalProduced(fluid: w.db.fluid(f)), 0, "\(id): \(f) produced")
        }
        // the game still saves and loads
        let b = try GameSession.decode(payload: s.encodePayload())
        XCTAssertEqual(b.world.entities.liveCount, w.entities.liveCount)
        XCTAssertEqual(b.level?.prebuilt, true)
        b.run(ticks: 60)
    }
}
