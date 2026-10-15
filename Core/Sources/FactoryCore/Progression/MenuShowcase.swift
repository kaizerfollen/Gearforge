// Gearforge — FactoryCore
// Main-menu background: a small, dense, always-running factory diorama (mining → smelting → belts → inserters →
// assembling → research, plus steam power fed by oil → solid fuel). The app renders it behind the menu with the
// normal renderer and pans the camera through `waypoints`.
// Layout, rates and how to tweak it: docs/team/designer.md ("Main-menu showcase"). Owner: Game designer.

import Foundation

public enum MenuShowcase {

    public struct Showcase {
        public let world: World
        /// Camera waypoints in world tile coordinates; the app pans slowly through them in a loop.
        public let waypoints: [Vec2]
        /// Suggested camera zoom (scene uses 32 pt per tile at zoom 1; an iPhone in landscape shows ~874×402 pt).
        public let zoom: Double
    }

    /// Placement report of the last build (tests / debugging).
    public struct Report: Sendable {
        /// World tile of the factory rectangle's top-left corner (local (minX, 0)).
        public var origin: TilePos
        public var size: (w: Int, h: Int)
        /// Entities placed by the stamper (excludes trees outside the factory).
        public var placed: Int
        /// Placement problems; empty when the layout is valid.
        public var failures: [String]
        public var rect: TileRect { TileRect(origin: origin, w: size.w, h: size.h) }
    }

    // MARK: Tunables

    /// Factory footprint in tiles: local x in minX..<(minX + width), y in 0..<height.
    static let minX = -4
    static let width = 53
    static let height = 34
    /// Map seed and size (multiple of 32; the surface is centred on (0,0)).
    static let seed: UInt64 = 0x6D65_6E75   // "menu"
    static let mapSide = 128
    /// Research the labs work on. Its price is multiplied by `techPrice` so it never completes.
    static let research = "logistics_2"
    static let techPrice = 1000.0
    /// Ore per tile: effectively infinite (each drill mines ~0.5 ore/s).
    static let oreAmount: UInt32 = 1_000_000_000
    /// Crude well amount: 300 000 = 100 % yield (10 crude/s). 175 % gives ≈ 0.39 solid fuel/s ≈ 4.7 MW, a bit below
    /// the factory's ≈ 5.2 MW draw, so the fuel line is always hungry (never "output full") while all six engines
    /// run; `cheatInfinitePower` covers the small shortfall so no machine ever shows low power.
    static let crudeAmount: UInt32 = 525_000
    static let assembler = "assembling_machine_2"
    static let scienceAssembler = "assembling_machine_3"

    // MARK: Entry points

    /// Builds the showcase world. Deterministic, fast, never fails (a placement problem only drops that entity).
    public static func make() -> Showcase { build().showcase }

    /// Builds the world and returns the placement report as well.
    static func build() -> (showcase: Showcase, report: Report) {
        var settings = WorldSettings()
        settings.seed = seed
        settings.width = mapSide
        settings.height = mapSide
        settings.treeCoverage = 0.3
        settings.rocks = false
        settings.waterCoverage = 0
        settings.dayNight = "perpetual_day"
        settings.techPriceMultiplier = techPrice
        // no natural ore, oil or starting lake: the factory brings its own, nothing is cut off at the cleared edge
        settings.layout = MapLayoutOverride(startingPatches: [], oilFields: [], lakeDistance: 10_000, regularResources: false)
        let world = World(settings: settings)
        world.recordsEvents = false
        world.cheatInfinitePower = true
        // generate the whole (small) map now, so the first ticks (the character charts 5×5 chunks) do not stutter
        let half = mapSide / 2
        for cy in stride(from: -half, to: half, by: 32) { for cx in stride(from: -half, to: half, by: 32) { _ = world.surface.chunk(at: TilePos(cx, cy)) } }

        let s = PrebuiltFactory.Stamper(world: world, origin: origin)
        clear(s, margin: 2)
        iron(s)
        copper(s)
        assembly(s)
        steel(s)
        labs(s)
        steam(s)
        oil(s)
        landmarks(s)
        startResearch(world)
        prime(s)
        // the engineer stands between the chemical plant and the silo, admiring the factory
        world.player.position = Vec2(Double(origin.x) + 25.5, Double(origin.y) + 21.5)

        let report = Report(origin: s.at(minX, 0), size: (width, height), placed: s.placed, failures: s.failures)
        func wp(_ x: Double, _ y: Double) -> Vec2 { Vec2(Double(origin.x) + x, Double(origin.y) + y) }
        let showcase = Showcase(world: world,
                                waypoints: [wp(16, 9), wp(29, 9), wp(29, 25), wp(16, 25)],
                                zoom: 0.7)
        return (showcase, report)
    }

    /// World tile of local (0,0): the factory rectangle is centred on spawn.
    static let origin = TilePos(-minX - width / 2, -height / 2)

    // MARK: Helpers

    /// Grass over the factory rectangle plus a margin; removes trees and natural resources there.
    static func clear(_ s: PrebuiltFactory.Stamper, margin m: Int) {
        let world = s.world
        let grass = world.db.tile("grass_1")
        TileRect(origin: s.at(minX - m, -m), w: width + 2 * m, h: height + 2 * m).forEach { q in
            _ = world.surface.chunk(at: q)
            if let e = world.entity(at: q) { world.removeEntity(e) }
            world.surface.setTile(at: q, grass)
            world.surface.setResource(at: q, -1, amount: 0)
        }
    }

    /// Deterministic 0..<1 hash of a local tile (organic edges for ore patches and ponds).
    static func noise(_ x: Int, _ y: Int, _ salt: UInt64) -> Double {
        var h = UInt64(bitPattern: Int64(x &* 73_856_093 ^ y &* 19_349_663)) ^ (salt &* 0x9E37_79B9_7F4A_7C15)
        h ^= h >> 33; h = h &* 0xFF51_AFD7_ED55_8CCD; h ^= h >> 33; h = h &* 0xC4CE_B9FE_1A85_EC53; h ^= h >> 33
        return Double(h >> 11) / Double(1 << 53)
    }

    /// Ore patch: the core rectangle is always filled (drills need it), a one-tile ring around it is ragged.
    static func orePatch(_ s: PrebuiltFactory.Stamper, _ resource: String, x: Int, y: Int, w: Int, h: Int, salt: UInt64) {
        let r = s.world.db.resource(resource)
        guard r >= 0 else { s.failures.append("unknown resource \(resource)"); return }
        for yy in (y - 1)...(y + h) {
            for xx in (x - 1)...(x + w) {
                let core = xx >= x && xx < x + w && yy >= y && yy < y + h
                if core || noise(xx, yy, salt) < 0.55 { s.resource(xx, yy, r, oreAmount) }
            }
        }
    }

    static func belt(_ s: PrebuiltFactory.Stamper, _ x: Int, _ y: Int, _ d: Direction) { s.place("transport_belt", x, y, d) }

    /// Straight belt run from (x0,y0) to (x1,y1) inclusive (horizontal or vertical), every tile facing `d`.
    static func run(_ s: PrebuiltFactory.Stamper, _ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, _ d: Direction) {
        for y in min(y0, y1)...max(y0, y1) { for x in min(x0, x1)...max(x0, x1) { belt(s, x, y, d) } }
    }

    /// Splitter with an output priority (0 = left side relative to its direction).
    @discardableResult
    static func splitter(_ s: PrebuiltFactory.Stamper, _ x: Int, _ y: Int, _ d: Direction, priority: Int8) -> Int32? {
        guard let e = s.place("splitter", x, y, d) else { return nil }
        var ss = SplitterSettings()
        ss.outputPriority = priority
        s.world.belts.setSplitterSettings(e, ss)
        return e
    }

    // MARK: Modules (local coordinates; y grows south)

    /// Iron: six drills on both sides of the ore belt (y6) → four electric furnaces (speed modules) → plate belt
    /// (y0) east to the assembly rows.
    ///
    ///     y0   . . . . . . . . . . . . = = = = = = = = = = = = = = = = = ...    plate belt → row A
    ///     y1   . . . . . . . . . . . . . f . . f . . f . . f . . . . . .        f = fast inserters
    ///     y2   . . . P . . . . P . . . [FUR] [FUR] [FUR] [FUR] . . P            electric furnaces
    ///     y3   D D D D D D D D D . . . [   ] [   ] [   ] [   ]                  D = drills facing south
    ///     y5   D D D D D D D D D . . . . f . . f . . f . . f . .
    ///     y6   = = = = = = = = = = = = = = = = = = = = = = = = .                ore belt (east)
    ///     y7   D D D D D D D D D . P . . . P . . . . P . . . P                  D = drills facing north
    static func iron(_ s: PrebuiltFactory.Stamper) {
        orePatch(s, "iron_ore", x: -4, y: 2, w: 11, h: 9, salt: 1)
        let speed = s.world.db.item("speed_module")
        for x in [-3, 0, 3] {
            for (y, d) in [(3, Direction.south), (7, Direction.north)] {
                guard let e = s.place("electric_mining_drill", x, y, d) else { continue }
                // one drill gets a speed module: 3.1 ore/s, a little above what the assembly rows use (≈ 3.0)
                if x == -3 && y == 3 { _ = s.world.mining.insertModule(e, item: speed) }
            }
        }
        run(s, -3, 6, 19, 6, .east)
        for x in [8, 11, 14, 17] {
            if let f = s.place("electric_furnace", x, 2) {
                for _ in 0..<2 { _ = s.world.crafting.insertModule(f, item: speed) }
            }
            s.place("fast_inserter", x + 1, 5, .north)
            s.place("fast_inserter", x + 1, 1, .north)
        }
        run(s, 8, 0, 23, 0, .east)
        // power: poles above / below the drills, over the furnaces, a row under the ore belt
        for x in [-1, 5] { s.pole(x, 2); s.pole(x, 10) }
        s.pole(7, 4)
        s.pole(11, 1); s.pole(17, 1); s.pole(22, 3)
        for x in [7, 11, 16, 21] { s.pole(x, 7) }
    }

    /// Copper: two drill → furnace pairs (drills feed the furnaces directly) → plate belt (y12) → priority splitter
    /// → up along x23 onto the start of the products bus (y6), where every copper user picks it up.
    ///
    ///     y6   . . . . . . . . . . . . . . . . . . . . . . . + = = =    products bus starts with copper
    ///     y7   . . . . . . . . . . . . . . . . . . . . . . . ^
    ///     y12  . . . . . . . . = = = = = = = = = = = = = = S ^          plate belt → splitter (22)
    ///     y13  . . . . . . . . . o . . o . . . . . . . . . S v          o = output inserters, v overflow
    ///     y14  . . . . . . . . [FUR] [FUR] P . . . . . . . . v
    ///     y17  . . . . . . . . [DRL] [DRL] . . . . . . . . . i C        drills facing north into the furnaces
    static func copper(_ s: PrebuiltFactory.Stamper) {
        orePatch(s, "copper_ore", x: 7, y: 17, w: 7, h: 3, salt: 2)
        for x in [8, 11] {
            s.place("electric_mining_drill", x, 17, .north)
            s.place("electric_furnace", x, 14)
            s.place("inserter", x + 1, 13, .north)
        }
        run(s, 8, 12, 21, 12, .east)
        splitter(s, 22, 12, .east, priority: 0)
        run(s, 23, 7, 23, 12, .north)
        belt(s, 23, 6, .east)
        belt(s, 23, 13, .south); belt(s, 23, 14, .south)
        s.place("inserter", 23, 15, .south)
        s.place("steel_chest", 23, 16)
        s.pole(14, 15)
        s.pole(14, 11)
        s.pole(7, 15)
        s.pole(22, 15)
        s.pole(22, 9)
    }

    /// Two assembler rows around the products bus (y6, east, then south along x48 to the labs). Everything a
    /// machine makes goes onto the bus with a fast inserter, so no machine ever waits on its output; cable goes
    /// straight into the circuit assembler.
    ///
    ///          x24       x30       x36       x42
    ///     y0   = = = = = = = = = = S = = = = = = =          iron plates; priority splitter at x34 (overflow ↓)
    ///     y1   i i i . . . . P . i S v . i . . . i .        iron → row A
    ///     y2  [GEAR]P[CABL]f[CIRC]v[INS ]P[BELT]            row A (gear assembler is an assembling machine 1)
    ///     y5   . . f . . i i . P . f u i i f . i . f        f = onto the bus, i = from it, u = underground
    ///     y6   = = = = = = = = = = = = = = = = = = = = = = = = +   products bus: copper, gears, circuits,
    ///     y7   f . i . i . f . . . . u . . . . f . i . f . i . |   inserters, belts, red and green cards
    ///     y8  [RED ]P[RED ][STL]i v P . [GRN ]P[GRN ]           |   row B (+ the steel furnace, see `steel`)
    static func assembly(_ s: PrebuiltFactory.Stamper) {
        let a = assembler, sci = scienceAssembler
        // iron main line; the priority splitter keeps INS / BELT fed and sends surplus down to the steel furnace
        run(s, 24, 0, 33, 0, .east)
        splitter(s, 34, 0, .east, priority: 0)
        run(s, 35, 0, 41, 0, .east)
        // row A
        // assembling machine 1: its craft speed caps gears at 1/s (2 iron/s), so it cannot starve the rest of the line
        s.machine("assembling_machine_1", 24, 2, recipe: "iron_gear_wheel")
        for x in 24...26 { s.place("inserter", x, 1, .south) }
        s.place("fast_inserter", 26, 5, .south)
        s.machine(a, 28, 2, recipe: "copper_cable")
        s.place("inserter", 29, 5, .north); s.place("inserter", 30, 5, .north)   // copper, after both red cells
        s.place("fast_inserter", 31, 3, .east)
        s.machine(a, 32, 2, recipe: "electronic_circuit")
        s.place("inserter", 33, 1, .south)
        s.place("fast_inserter", 34, 5, .south)
        s.machine(a, 36, 2, recipe: "inserter")
        s.place("inserter", 37, 1, .south)
        s.place("inserter", 36, 5, .north); s.place("inserter", 37, 5, .north)
        s.place("fast_inserter", 38, 5, .south)
        s.machine(a, 40, 2, recipe: "transport_belt")
        s.place("inserter", 41, 1, .south)
        s.place("inserter", 40, 5, .north)
        s.place("fast_inserter", 42, 5, .south)
        // products bus
        run(s, 24, 6, 47, 6, .east)
        // row B
        // red: one assembler 3 + one assembler 2 = 0.4 cards/s, matching the gear and copper budget
        s.machine(sci, 24, 8, recipe: "mechanics_card")
        s.place("inserter", 26, 7, .south)               // copper + gears
        s.place("fast_inserter", 24, 7, .north)          // cards out
        s.machine(a, 28, 8, recipe: "mechanics_card")
        s.place("inserter", 28, 7, .south)
        s.place("fast_inserter", 30, 7, .north)
        let speed = s.world.db.item("speed_module")
        for x in [40, 44] {
            if let g = s.machine(sci, x, 8, recipe: "motion_card") { _ = s.world.crafting.insertModule(g, item: speed) }
            s.place("inserter", x + 2, 7, .south)        // inserters + belts
            s.place("fast_inserter", x, 7, .north)       // cards out
        }
        // power
        for x in [27, 39] { s.pole(x, 3) }
        s.pole(31, 1)
        s.pole(27, 9); s.pole(43, 9)
        s.pole(47, 5)
    }

    /// Iron surplus: the splitter's overflow runs down a gap in row A, under the products bus (underground pair) and
    /// into an electric furnace making steel; steel goes into a chest. Only used when the iron line is full.
    ///
    ///     y0   = = S = =        priority splitter (main line east, overflow south)
    ///     y1   . . . v .
    ///     y5   . . . u .        u = underground belt under the products bus (y6)
    ///     y7   . . . u .
    ///     y8  [STL] i v P       STL = electric furnace (steel), i = inserter (west)
    ///     y11  . i .            output inserter → steel chest (y12)
    static func steel(_ s: PrebuiltFactory.Stamper) {
        run(s, 35, 1, 35, 4, .south)
        if let e = s.place("underground_belt", 35, 5, .south) { s.world.belts.setUndergroundMode(e, entrance: true) }
        if let e = s.place("underground_belt", 35, 7, .south) { s.world.belts.setUndergroundMode(e, entrance: false) }
        run(s, 35, 8, 35, 10, .south)
        s.place("inserter", 34, 9, .west)
        s.place("electric_furnace", 31, 8)
        s.place("inserter", 32, 11, .south)
        s.place("steel_chest", 32, 12)
        s.pole(36, 9); s.pole(35, 11); s.pole(32, 5)
    }

    /// Products belt down to the lab row (y17, west): 4 + 4 labs, then a three-chest store for whatever is left.
    ///
    ///     y13   C . [LAB] P [LAB] P [LAB] P [LAB] P |      C = store chests
    ///     y16   f . . i . . . i . . . i . . . i . . |      f/i = fast inserter / lab inserters
    ///     y17   C f = = = = = = = = = = = = = = = = +      lab belt (west)
    ///     y18   f . . i . . . i . . . i . . . i . .
    ///     y19   C . [LAB] . [LAB] . [LAB] . [LAB]
    static func labs(_ s: PrebuiltFactory.Stamper) {
        run(s, 48, 6, 48, 16, .south)
        run(s, 30, 17, 48, 17, .west)
        for lx in [32, 36, 40, 44] {
            s.place("lab", lx, 13)
            s.place("inserter", lx + 1, 16, .north)
            s.place("lab", lx, 19)
            s.place("inserter", lx + 1, 18, .south)
            s.pole(lx + 3, 16)
        }
        // store at the belt end (x30)
        s.place("fast_inserter", 29, 17, .west); s.place("steel_chest", 28, 17)
        s.place("fast_inserter", 30, 16, .north); s.place("steel_chest", 30, 15)
        s.place("fast_inserter", 30, 18, .south); s.place("steel_chest", 30, 19)
        s.pole(29, 16)
    }

    /// Steam power: pond → offshore pump → 3 boilers → 6 steam engines; boilers burn solid fuel from the oil block.
    ///
    ///     y20  ~ ~ ~ . P [E][E][E] P      E = steam engines (3×5, two per boiler column)
    ///     y30  ~ ~ ~ . . [B][B][B] .      B = boilers
    ///     y31  ~ ~ ~ o - [B][B][B] .      o = offshore pump, - pipe
    ///     y32  ~ ~ ~ . . . i . . i . . i  i = fuel inserters
    ///     y33  ~ ~ ~ . . . = = = = = = = = <   solid-fuel belt (west)
    static func steam(_ s: PrebuiltFactory.Stamper) {
        let water = s.world.db.tile("water")
        for y in 19...(height + 1) {
            for x in -5...3 {
                let edge = x == 3 ? (y >= 22 && y <= 27 && noise(x, y, 3) < 0.6) : (x == -5 || y == 19 ? noise(x, y, 4) < 0.5 : true)
                if edge && !(x == 3 && y >= 29) { s.world.surface.setTile(at: s.at(x, y), water) }
            }
        }
        s.place("offshore_pump", 3, 31, .west)
        s.place("pipe", 4, 31)
        let fuel = s.world.db.item("solid_fuel")
        for x in [5, 8, 11] {
            if let b = s.place("boiler", x, 30, .north) { _ = s.world.power.insert(b, item: fuel, count: 20, source: .player) }
            s.place("steam_engine", x, 25, .north)
            s.place("steam_engine", x, 20, .north)
            s.place("inserter", x + 1, 32, .north)
        }
        run(s, 6, 33, 13, 33, .west)
        s.pole(4, 23); s.pole(4, 28); s.pole(14, 21); s.pole(7, 19)
        s.pole(5, 32); s.pole(11, 32)
    }

    /// Oil: pumpjack on a crude well → refinery (basic) → petroleum gas → chemical plant (solid fuel) → belt that
    /// ducks under the gas pipe (underground pair) and runs to the boilers.
    ///
    ///     y20  . . . . . | - . .          | gas pipe, - into the chemical plant
    ///     y21  . . . . . | [CHM]           CHM = chemical plant (solid fuel)
    ///     y24  . . . . . | . i .           i = output inserter
    ///     y25  v < < < u | u <             u = underground belt pair under the pipe
    ///     y26  v [ REFINERY ] .
    ///     y31  v [PJ ] . . .               PJ = pumpjack on the crude well
    ///     y33  < . . . . . .
    static func oil(_ s: PrebuiltFactory.Stamper) {
        let crude = s.world.db.resource("crude_oil")
        s.resource(16, 32, crude, crudeAmount)
        s.machine("oil_refinery", 16, 26, recipe: "basic_oil_processing")
        s.place("pumpjack", 15, 31, .north)
        for y in 20...25 { s.place("pipe", 20, y) }
        s.place("pipe", 21, 20)
        s.machine("chemical_plant", 21, 21, recipe: "solid_fuel_from_petroleum_gas")
        s.place("inserter", 22, 24, .south)
        belt(s, 22, 25, .west)
        if let e = s.place("underground_belt", 21, 25, .west) { s.world.belts.setUndergroundMode(e, entrance: true) }
        if let e = s.place("underground_belt", 19, 25, .west) { s.world.belts.setUndergroundMode(e, entrance: false) }
        run(s, 15, 25, 18, 25, .west)
        belt(s, 14, 25, .south)
        run(s, 14, 26, 14, 32, .south)
        belt(s, 14, 33, .west)
        s.pole(19, 31); s.pole(24, 24); s.pole(21, 30)
    }

    /// Landmarks south of the labs: the rocket silo (the goal of the game) and a small solar + accumulator field.
    static func landmarks(_ s: PrebuiltFactory.Stamper) {
        s.place("rocket_silo", 25, 23)
        s.pole(34, 24)
        for (x, y) in [(36, 23), (39, 23), (42, 23), (36, 27), (39, 27), (42, 27)] { s.place("solar_panel", x, y) }
        for (x, y) in [(46, 23), (46, 25), (46, 27), (46, 29)] { s.place("accumulator", x, y) }
        s.pole(39, 26); s.pole(45, 26)
    }

    /// Pre-loads belts and machines so the very first frame already looks like a running factory (the simulation
    /// is not run here: building must stay fast). Leftovers simply flow to the store chests.
    static func prime(_ s: PrebuiltFactory.Stamper) {
        let w = s.world, db = w.db
        func item(_ id: String) -> Int { db.item(id) }
        /// Puts `perLane` items on each lane of every belt tile in the run, cycling through `items`.
        func fill(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, _ items: [[String]], perLane: Int = 2) {
            var k = 0
            for y in min(y0, y1)...max(y0, y1) {
                for x in min(x0, x1)...max(x0, x1) {
                    guard let e = w.entity(at: s.at(x, y)), w.entities[e].kind == .transportBelt else { continue }
                    for lane in 0..<2 {
                        let pick = items[lane % items.count]
                        for j in 0..<perLane {
                            _ = w.belts.insertItem(e, lane: lane, position: 32 + j * 256 / perLane, item: item(pick[k % pick.count]))
                            k += 1
                        }
                    }
                }
            }
        }
        fill(-3, 6, 19, 6, [["iron_ore"]], perLane: 1)
        fill(8, 0, 21, 0, [["iron_plate"]], perLane: 1)
        fill(35, 1, 35, 4, [["iron_plate"]], perLane: 1)
        fill(22, 0, 41, 0, [["iron_plate"]], perLane: 3)
        fill(8, 12, 21, 12, [["copper_plate"]], perLane: 1)
        fill(23, 6, 23, 12, [["copper_plate"]], perLane: 1)
        fill(24, 6, 47, 6, [["copper_plate", "mechanics_card"], ["iron_gear_wheel", "electronic_circuit", "inserter", "transport_belt"]], perLane: 1)
        fill(48, 6, 48, 16, [["mechanics_card", "motion_card"]], perLane: 1)
        fill(31, 17, 48, 17, [["mechanics_card", "motion_card"]], perLane: 1)
        fill(14, 25, 14, 33, [["solid_fuel"]], perLane: 1)
        fill(6, 33, 13, 33, [["solid_fuel"]], perLane: 2)
        // machines: a few crafts' worth of ingredients, ore in the furnaces, cards in the labs
        let red = item("mechanics_card"), green = item("motion_card")
        w.entities.forEachLive { e, rec in
            guard rec.flags.contains(.playerBuilt) else { return }
            switch rec.kind {
            case .assemblingMachine:
                let r = w.crafting.recipe(of: e)
                guard r >= 0 else { return }
                for ing in db.resolvedRecipes[r].itemIngredients {
                    _ = w.crafting.insert(e, item: ing.index, count: Int(ing.amount * 3), source: .player)
                }
            case .furnace:
                let lx = Int(rec.origin.x - s.origin.x), ly = Int(rec.origin.y - s.origin.y)
                let p = lx >= 30 ? "iron_plate" : (ly < 10 ? "iron_ore" : "copper_ore")   // steel furnace / iron / copper
                _ = w.crafting.insert(e, item: item(p), count: 10, source: .player)
            case .lab:
                _ = w.labs.insert(e, item: red, count: 3, source: .player)
                _ = w.labs.insert(e, item: green, count: 3, source: .player)
            default: break
            }
        }
    }

    /// Unlocks the early techs and starts a red + green research whose price is scaled so it never finishes.
    static func startResearch(_ world: World) {
        let r = world.research!
        r.forceResearch(ids: ["automation", "logistics", "electronics", "optics", "motion_card", "steel_processing",
                              "fast_inserter", "automation_2", "research_speed_1"])
        r.setCurrent(world.db.tech(research))
    }
}
