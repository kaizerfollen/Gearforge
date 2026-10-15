// Gearforge — main-menu showcase factory: clean placement, everything animated after a minute, still running
// (and never "output full") after ten minutes.

import XCTest
@testable import FactoryCore

final class MenuShowcaseTests: XCTestCase {

    func testPlacesCleanlyAndIsSmall() {
        let t0 = Date()
        let (sc, r) = MenuShowcase.build()
        let ms = Date().timeIntervalSince(t0) * 1000
        XCTAssertEqual(r.failures, [], "placement failures")
        XCTAssertLessThan(r.placed, 400, "entity budget")
        XCTAssertGreaterThanOrEqual(sc.waypoints.count, 2)
        XCTAssertTrue((0.5...1.0).contains(sc.zoom))
        // waypoints stay inside the factory rectangle
        for p in sc.waypoints { XCTAssertTrue(r.rect.contains(p.tile), "waypoint \(p) outside \(r.rect)") }
        // every electric machine is on one network with the steam engines
        let w = sc.world
        var engine: Int32 = -1
        w.entities.forEachLive { e, rec in if engine < 0 && rec.kind == .generator { engine = e } }
        XCTAssertGreaterThanOrEqual(engine, 0, "steam block exists")
        let t1 = Date()
        w.step()
        let firstStepMs = Date().timeIntervalSince(t1) * 1000
        let t2 = Date()
        w.step(60)
        print("SHOWCASE first tick \(Int(firstStepMs)) ms, next 60 ticks \(Int(Date().timeIntervalSince(t2) * 1000)) ms")
        let net = w.power.networkID(of: engine)
        var off: [String] = []
        w.entities.forEachLive { e, rec in
            switch rec.kind {
            case .assemblingMachine, .furnace, .lab, .inserter, .miningDrill, .generator, .rocketSilo, .solarPanel, .accumulator:
                if w.power.networkID(of: e) != net { off.append("\(w.db.entities[Int(rec.proto)].id)@\(rec.origin)") }
            default: break
            }
        }
        XCTAssertEqual(off, [], "machines off the plant network")
        XCTAssertGreaterThanOrEqual(w.research.current, 0, "a research is running")
        print("SHOWCASE: \(r.placed) entities placed (\(w.entities.liveCount) incl. trees), origin \(r.origin), built in \(Int(ms)) ms")
        if ProcessInfo.processInfo.environment["GF_SHOWCASE_DUMP"] != nil { print(Self.dump(w, r.rect)) }
    }

    func testRunsAfterOneMinuteAndTenMinutes() {
        let (sc, r) = MenuShowcase.build()
        let w = sc.world
        let research0 = w.research.progressUnits(of: w.research.current)
        w.step(50 * 60)
        check(w, r, label: "1 min", minAssemblers: 7)
        let card0 = cards(w)
        w.step(9 * 60 * 60)
        check(w, r, label: "10 min")
        let card1 = cards(w)
        XCTAssertGreaterThan(card1.red, card0.red + 50, "red cards keep coming")
        XCTAssertGreaterThan(card1.green, card0.green + 50, "green cards keep coming")
        XCTAssertGreaterThan(w.research.progressUnits(of: w.research.current), research0 + 50, "research progresses")
        XCTAssertGreaterThanOrEqual(w.research.current, 0, "research never completes")
        if ProcessInfo.processInfo.environment["GF_SHOWCASE_DUMP"] != nil { print(Self.dump(w, r.rect)) }
        if ProcessInfo.processInfo.environment["GF_SHOWCASE_DIAG"] != nil { Self.diag(w, r) }
    }

    /// Opt-in tuning output (GF_SHOWCASE_DIAG=1): rates per minute, power, every machine / inserter / chest / lab.
    static func diag(_ w: World, _ r: MenuShowcase.Report) {
        let mins = Double(w.tick) / 3600
        var line = "DIAG rates/min over \(mins) min:"
        for id in ["iron_ore", "copper_ore", "iron_plate", "copper_plate", "iron_gear_wheel", "copper_cable", "electronic_circuit", "inserter", "transport_belt", "mechanics_card", "motion_card", "solid_fuel"] {
            line += " \(id) \(Int(Double(w.stats.producedByMachines(item: w.item(id))) / mins))"
        }
        print(line)
        for st in w.power.networkStats where st.demandW > 0 { print("DIAG power demand \(Int(st.demandW / 1000)) kW, capacity \(Int(st.capacityW / 1000)) kW, sat \(st.satisfaction)") }
        w.entities.forEachLive { e, rec in
            let id = w.db.entities[Int(rec.proto)].id
            let lx = Int(rec.origin.x - r.origin.x), ly = Int(rec.origin.y - r.origin.y)
            func st(_ l: [ItemStack]) -> String { l.map { "\(w.db.items[Int($0.item)].id)x\($0.count)" }.joined(separator: ",") }
            switch rec.kind {
            case .assemblingMachine, .furnace:
                let rc = w.crafting.recipe(of: e)
                print("DIAG \(id) (\(lx),\(ly)) \(rc >= 0 ? w.db.recipes[rc].id : "-") \(w.crafting.status(of: e)) in[\(st(w.crafting.inputSlots(of: e)))] out[\(st(w.crafting.outputSlots(of: e)))]")
            case .inserter:
                let h = w.inserters.heldStack(of: e)
                print("DIAG \(id) (\(lx),\(ly)) \(rec.direction) \(w.inserters.status(of: e)) held \(h.count > 0 ? w.db.items[Int(h.item)].id : "-")")
            case .container:
                print("DIAG chest (\(lx),\(ly)) \(w.containers.inventory(of: e).map { $0.contents().map { "\(w.db.items[$0.item].id)x\($0.count)" }.joined(separator: ",") } ?? "")")
            case .lab:
                print("DIAG lab (\(lx),\(ly)) \(w.labs.status(of: e)) \(w.labs.cards(of: e).map { $0.contents().map { "\(w.db.items[$0.item].id)x\($0.count)" }.joined(separator: ",") } ?? "")")
            default: break
            }
        }
    }

    /// Opt-in endurance profile: GF_SHOWCASE_LONG=<minutes> swift test --filter testLongRun
    func testLongRun() {
        guard let m = ProcessInfo.processInfo.environment["GF_SHOWCASE_LONG"].flatMap(Int.init) else { return }
        let (sc, r) = MenuShowcase.build()
        let w = sc.world
        for minute in stride(from: 10, through: m, by: 10) {
            w.step(10 * 60 * 60)
            check(w, r, label: "\(minute) min")
            if ProcessInfo.processInfo.environment["GF_SHOWCASE_DIAG"] != nil { Self.diag(w, r) }
        }
    }

    func testDeterministic() {
        let a = MenuShowcase.make(), b = MenuShowcase.make()
        XCTAssertEqual(a.waypoints, b.waypoints)
        XCTAssertEqual(a.world.entities.liveCount, b.world.entities.liveCount)
        a.world.step(600); b.world.step(600)
        XCTAssertEqual(cards(a.world).red, cards(b.world).red)
        XCTAssertEqual(a.world.stats.producedByMachines(item: a.world.item("iron_plate")),
                       b.world.stats.producedByMachines(item: b.world.item("iron_plate")))
    }

    // MARK: Helpers

    private func cards(_ w: World) -> (red: Int, green: Int) {
        (Int(w.stats.producedByMachines(item: w.item("mechanics_card"))), Int(w.stats.producedByMachines(item: w.item("motion_card"))))
    }

    /// Samples machine states every 10 ticks for 10 s: counts machines that worked at least once, flags any that
    /// showed a status the renderer draws an icon for (output full, no power, no fuel, ...).
    private func check(_ w: World, _ r: MenuShowcase.Report, label: String, minAssemblers: Int = 10) {
        var worked: [EntityKind: Set<Int32>] = [:], total: [EntityKind: Int] = [:]
        var icons: [String: Int] = [:]
        w.entities.forEachLive { _, rec in total[rec.kind, default: 0] += 1 }
        for _ in 0..<60 {
            w.step(10)
            w.entities.forEachLive { e, rec in
                var working = false
                var st: EntityStatus? = nil
                switch rec.kind {
                case .assemblingMachine, .furnace: working = w.crafting.isWorking(e); st = w.crafting.status(of: e)
                case .miningDrill: working = w.mining.isWorking(e); st = w.mining.status(of: e)
                case .lab: working = w.labs.isWorking(e); st = w.labs.status(of: e)
                case .boiler: working = w.power.isBoilerWorking(e)
                case .generator: working = w.power.powerOutput(of: e) > 1
                default: return
                }
                if working { worked[rec.kind, default: []].insert(e) }
                switch st {
                case .outputFull?, .noPower?, .lowPower?, .noFuel?, .noResources?, .noRecipe?:
                    icons["\(w.db.entities[Int(rec.proto)].id)@\(rec.origin) \(st!)", default: 0] += 1
                default: break
                }
            }
        }
        var items = 0
        w.belts.forEachItem(in: r.rect) { _, _, _ in items += 1 }
        func n(_ k: EntityKind) -> Int { worked[k]?.count ?? 0 }
        print("SHOWCASE \(label): belt items \(items); working drills \(n(.miningDrill))/\(total[.miningDrill] ?? 0), "
              + "furnaces \(n(.furnace))/\(total[.furnace] ?? 0), assemblers \(n(.assemblingMachine))/\(total[.assemblingMachine] ?? 0), "
              + "labs \(n(.lab))/\(total[.lab] ?? 0), boilers \(n(.boiler)), engines \(n(.generator)); icons \(icons)")
        XCTAssertGreaterThan(items, 150, "\(label): belts carry items")
        XCTAssertGreaterThanOrEqual(n(.miningDrill), 6, "\(label): drills working")
        XCTAssertGreaterThanOrEqual(n(.furnace), 5, "\(label): furnaces working")
        XCTAssertGreaterThanOrEqual(n(.assemblingMachine), minAssemblers, "\(label): assemblers working")
        XCTAssertGreaterThanOrEqual(n(.lab), 6, "\(label): labs working")
        XCTAssertGreaterThanOrEqual(n(.boiler), 1, "\(label): boilers burning")
        XCTAssertGreaterThanOrEqual(n(.generator), 2, "\(label): engines running")
        XCTAssertEqual(icons, [:], "\(label): machines showing a status icon")
    }

    /// ASCII map of the factory (GF_SHOWCASE_DUMP=1): one letter per entity kind, ore as , / water as ~.
    static func dump(_ w: World, _ rect: TileRect) -> String {
        var out = ""
        let r = rect.expanded(by: 3)
        var y = r.y
        while y < r.maxY {
            var line = String(format: "%3d ", Int(y - rect.y))
            var x = r.x
            while x < r.maxX {
                let p = TilePos(x, y)
                var ch: Swift.Character = "."
                if let e = w.entity(at: p) {
                    let rec = w.entities[e]
                    let id = w.db.entities[Int(rec.proto)].id
                    switch rec.kind {
                    case .transportBelt:
                        switch rec.direction { case .east: ch = ">"; case .west: ch = "<"; case .north: ch = "^"; case .south: ch = "v" }
                    case .undergroundBelt: ch = "u"
                    case .splitter: ch = "S"
                    case .inserter: ch = id == "fast_inserter" ? "f" : "i"
                    case .electricPole: ch = "P"
                    case .container: ch = "C"
                    case .miningDrill: ch = id == "pumpjack" ? "J" : "D"
                    case .furnace: ch = "F"
                    case .assemblingMachine: ch = id == "chemical_plant" ? "H" : (id == "oil_refinery" ? "R" : "A")
                    case .lab: ch = "L"
                    case .boiler: ch = "B"
                    case .generator: ch = "E"
                    case .pipe, .pipeToGround: ch = "-"
                    case .offshorePump: ch = "o"
                    case .rocketSilo: ch = "#"
                    case .solarPanel: ch = "="
                    case .accumulator: ch = "a"
                    case .tree: ch = "T"
                    default: ch = "?"
                    }
                } else {
                    let t = w.surface.tile(at: p)
                    if t >= 0 && w.db.tiles[t].isWater { ch = "~" }
                    else if w.surface.resource(at: p).0 >= 0 { ch = "," }
                }
                line.append(ch)
                x += 1
            }
            out += line + "\n"
            y += 1
        }
        return out
    }
}
