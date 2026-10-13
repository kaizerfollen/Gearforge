// Gearforge — FactoryCore
// Pre-built starting factories for campaign levels L5–L8 (GDD §7 "pre-built" rows).
// The factory is stamped from code "modules" (steam block, science cells, blue module, oil block, lab row) into a
// cleared rectangle 15+ tiles from spawn. Supply chests are pre-stocked with a finite amount of plates /
// intermediates so the factory runs for a good while (≈ 45–60 game minutes) and then needs the player.
// Layouts and rates: docs/team/designer.md. Owner: Game designer.

import Foundation

public enum PrebuiltFactory {

    /// Result of stamping a factory (for tests / debugging).
    public struct Report: Sendable {
        /// Top-left tile of the factory rectangle (world coordinates).
        public var origin: TilePos
        public var size: (w: Int, h: Int)
        public var placed: Int
        /// Placement problems (empty when the layout is valid).
        public var failures: [String]
        /// Entities of interest.
        public var engines: [Int32] = []
        public var labs: [Int32] = []
        public var storeChests: [Int32] = []
        public var rect: TileRect { TileRect(origin: origin, w: size.w, h: size.h) }
    }

    enum Oil: Sendable { case none, basic, advanced }

    struct Plan: Sendable {
        var boilers: Int
        var red: Int, green: Int, purple: Int, yellow: Int
        var blue: Int
        var oil: Oil
        var labs: Int
        var assembler: String
        /// Supply chests hold enough for this many game minutes at full speed (capped by chest size).
        var minutes: Double
        var coalPerBoiler: Int
        var crudeAmount: UInt32
        var cells: Int { red + green + purple + yellow }
    }

    static func plan(for levelID: String) -> Plan? {
        switch levelID {
        case "L5": return Plan(boilers: 11, red: 3, green: 4, purple: 0, yellow: 0, blue: 0, oil: .none, labs: 10,
                               assembler: "assembling_machine_2", minutes: 60, coalPerBoiler: 800, crudeAmount: 0)
        case "L6": return Plan(boilers: 12, red: 3, green: 4, purple: 0, yellow: 0, blue: 2, oil: .basic, labs: 10,
                               assembler: "assembling_machine_2", minutes: 60, coalPerBoiler: 900, crudeAmount: 600_000)
        case "L7": return Plan(boilers: 12, red: 3, green: 4, purple: 0, yellow: 0, blue: 2, oil: .advanced, labs: 10,
                               assembler: "assembling_machine_2", minutes: 60, coalPerBoiler: 900, crudeAmount: 600_000)
        case "L8": return Plan(boilers: 16, red: 3, green: 4, purple: 2, yellow: 2, blue: 2, oil: .advanced, labs: 10,
                               assembler: "assembling_machine_3", minutes: 45, coalPerBoiler: 1200, crudeAmount: 750_000)
        default: return nil
        }
    }

    // MARK: Layout constants (factory-local coordinates, y grows south)

    /// Row of the science belt.
    static let beltY = 12
    /// Top row of the science cells (above the belt).
    static let cellY = 2
    /// Top row of the blue modules (below the belt).
    static let blueY = 14
    static let cellWidth = 5
    static let blueWidth = 16

    static func scienceX(_ p: Plan) -> Int { 7 + 3 * p.boilers }
    static func blueX(_ p: Plan) -> Int { scienceX(p) + 12 }
    static func labX(_ p: Plan) -> Int {
        var x = scienceX(p) + cellWidth * p.cells
        if p.blue > 0 { x = max(x, blueX(p) + blueWidth * p.blue - 1) }
        return x + 1
    }
    static func beltEndX(_ p: Plan) -> Int { labX(p) + 4 * (p.labs / 2) }
    static func size(_ p: Plan) -> (w: Int, h: Int) {
        (beltEndX(p) + 4, p.blue > 0 ? blueY + 21 : 21)
    }

    // MARK: Entry point

    /// Clears an area 15+ tiles from `spawn` and stamps the level's pre-built factory. No-op for levels without one.
    @discardableResult
    public static func build(levelID: String, in world: World, near spawn: TilePos) -> Report? {
        guard let p = plan(for: levelID) else { return nil }
        let (w, h) = size(p)
        let origin = chooseOrigin(world: world, spawn: spawn, w: w, h: h)
        let s = Stamper(world: world, origin: origin)
        s.clear(w: w, h: h)
        var report = Report(origin: origin, size: (w, h), placed: 0, failures: [])
        report.engines = steamBlock(s, boilers: p.boilers, coal: p.coalPerBoiler)
        let sx = scienceX(p)
        let speed = world.db.entities[world.db.entity(p.assembler)].crafting?.speed ?? 0.75
        // science cells above the belt
        var i = 0
        func cells(_ n: Int, a: String, b: String) {
            for _ in 0..<n {
                scienceCell(s, x: sx + cellWidth * i, y: cellY, machine: p.assembler, speed: speed, recipeA: a, recipeB: b, minutes: p.minutes)
                i += 1
            }
        }
        cells(p.red, a: "iron_gear_wheel", b: "mechanics_card")
        cells(p.green, a: "inserter", b: "motion_card")
        cells(p.purple, a: "rail", b: "fabrication_card")
        cells(p.yellow, a: "flying_robot_frame", b: "systems_card")
        // blue modules + oil block below the belt
        if p.blue > 0 {
            let bx = blueX(p)
            for k in 0..<p.blue {
                blueModule(s, x: bx + blueWidth * k, y: blueY, machine: p.assembler, speed: speed, minutes: p.minutes)
            }
            // petroleum header joining the refinery gas output to every module
            for x in (bx - 2)...(bx + blueWidth * (p.blue - 1) + 8) { s.place("pipe", x, blueY + 9) }
            oilBlock(s, bx: bx, by: blueY, mode: p.oil, crude: p.crudeAmount)
        }
        // science belt, labs and the card store at its end
        let xL = labX(p), xe = beltEndX(p)
        for x in sx...xe { s.place("transport_belt", x, beltY, .east) }
        // pole run along the row above the belt between the last cell and the lab row
        let lastCellPole = sx + cellWidth * (p.cells - 1) + 3
        var px = lastCellPole + 7
        while px < xL + 3 - 1 { s.pole(px, beltY - 1); px += 7 }
        report.labs = labRow(s, x: xL, pairs: p.labs / 2)
        report.storeChests = [
            s.place("steel_chest", xe + 2, beltY), s.place("steel_chest", xe, beltY - 2), s.place("steel_chest", xe, beltY + 2),
        ].compactMap { $0 }
        s.place("fast_inserter", xe + 1, beltY, .east)
        s.place("fast_inserter", xe, beltY - 1, .north)
        s.place("fast_inserter", xe, beltY + 1, .south)
        s.pole(xe + 2, beltY - 1)
        report.placed = s.placed
        report.failures = s.failures
        return report
    }

    /// Picks the side of spawn (E, S, W, N) whose rectangle covers the fewest resource / water tiles.
    static func chooseOrigin(world: World, spawn: TilePos, w: Int, h: Int) -> TilePos {
        let gap = 15
        let sxp = Int(spawn.x), syp = Int(spawn.y)
        let cands = [TilePos(sxp + gap, syp - h / 2), TilePos(sxp - w / 2, syp + gap),
                     TilePos(sxp - gap - w, syp - h / 2), TilePos(sxp - w / 2, syp - gap - h)]
        var best: (Int, TilePos)? = nil
        for o in cands {
            let r = TileRect(origin: o, w: w, h: h).expanded(by: 2)
            guard world.surface.isInBounds(TilePos(r.x, r.y)), world.surface.isInBounds(TilePos(r.maxX - 1, r.maxY - 1)) else { continue }
            var score = 0
            r.forEach { q in
                _ = world.surface.chunk(at: q)
                if world.surface.resource(at: q).0 >= 0 { score += 1 }
                let t = world.surface.tile(at: q)
                if t >= 0 && world.db.tiles[t].isWater { score += 2 }
            }
            if best == nil || score < best!.0 { best = (score, o) }
        }
        return best?.1 ?? cands[0]
    }

    // MARK: Modules

    /// Steam power: offshore pump → N boilers in a row → 2N steam engines (columns north of each boiler);
    /// each boiler is fed coal by an inserter from its own chest. 1.8 MW per boiler.
    ///
    ///     y 3  P . . . . . P . . .        P = medium pole
    ///     y 4  . . . E E E E E E . .      E = steam engine (3×5, two per column)
    ///     y14  ~ ~ o - B B B B B B P      ~ water, o offshore pump, - pipe, B boiler (3×2)
    ///     y16  P . . . . i . . i . P      i = inserter (north, into boiler)
    ///     y17  . . . . . C . . C .        C = coal chest
    static func steamBlock(_ s: Stamper, boilers n: Int, coal: Int) -> [Int32] {
        s.water(x: 0, y: 10, w: 2, h: 10)
        s.place("offshore_pump", 2, 15, .west)
        s.place("pipe", 3, 15)
        var engines: [Int32] = []
        let coalItem = s.world.db.item("coal")
        for i in 0..<n {
            let x = 4 + 3 * i
            if let b = s.place("boiler", x, 14, .north) { _ = s.world.power.insert(b, item: coalItem, count: 50, source: .player) }
            if let e = s.place("steam_engine", x, 9, .north) { engines.append(e) }
            if let e = s.place("steam_engine", x, 4, .north) { engines.append(e) }
            s.place("inserter", x + 1, 16, .north)
            s.chest("iron_chest", x + 1, 17, [(coalItem, coal)])
        }
        let right = 4 + 3 * n
        for x in stride(from: 5, through: right - 1, by: 6) { s.pole(x, 3) }
        for x in stride(from: 4, through: right - 1, by: 6) { s.pole(x, 16) }   // covers lower engines, inserters, chests
        for y in [3, 10, 16] { s.pole(right, y) }
        return engines
    }

    /// A two-stage science cell (5 wide × 10 high) dropping cards onto the belt below it:
    ///
    ///     y0   . A . . .      A = supply chest for stage A (plates / intermediates)
    ///     y1   . i . . .      i = fast inserter (south)
    ///     y2  [ asm A ] i A2  intermediate assembler (gears, inserters, rails, robot frames); A2 = overflow chest
    ///     y3  [ asm A ] P .
    ///     y4  [ asm A ] . .
    ///     y5   . i . . .
    ///     y6  [ asm B ] j T3  (T2/T3 only when T overflows one chest)
    ///     y7  [ asm B ] j T   j = fast inserter (west) from supply chest T
    ///     y8  [ asm B ] j T2
    ///     y9   . o . P .      o = inserter (south) onto the belt
    ///     y10  = = = = =      science belt (east)
    static func scienceCell(_ s: Stamper, x: Int, y: Int, machine: String, speed: Double,
                            recipeA: String, recipeB: String, minutes: Double) {
        let db = s.world.db
        let rb = db.resolvedRecipes[db.recipe(recipeB)]
        let bCrafts = minutes * 60 * speed / rb.time
        var stockA: [(Int, Int)] = [], stockT: [(Int, Int)] = []
        let ra: ResolvedRecipe? = db.resolvedRecipes[db.recipe(recipeA)]
        for ing in rb.itemIngredients {
            let need = ing.amount * bCrafts
            if let ra = ra, ra.itemResults.first?.index == ing.index {
                let aCrafts = need / (ra.itemResults.first?.amount ?? 1)
                for ai in ra.itemIngredients { stockA.append((ai.index, Int((ai.amount * aCrafts).rounded(.up)))) }
            } else {
                stockT.append((ing.index, Int(need.rounded(.up))))
            }
        }
        // stage A: main chest above, overflow chest east of the assembler
        let packsA = s.pack(stockA, maxChests: 2)
        for (j, items) in packsA.enumerated() {
            if j == 0 { s.chest("steel_chest", x + 1, y, items); s.place("fast_inserter", x + 1, y + 1, .south) }
            else { s.chest("steel_chest", x + 4, y + 2, items); s.place("fast_inserter", x + 3, y + 2, .west) }
        }
        s.machine(machine, x, y + 2, recipe: recipeA)
        s.place("fast_inserter", x + 1, y + 5, .south)
        s.machine(machine, x, y + 6, recipe: recipeB)
        // stage B extras: up to three chests east of the science assembler
        let slotsT = [(y + 7), (y + 8), (y + 6)]
        for (j, items) in s.pack(stockT, maxChests: 3).enumerated() {
            s.place("fast_inserter", x + 3, slotsT[j], .west)
            s.chest("steel_chest", x + 4, slotsT[j], items)
        }
        s.place("fast_inserter", x + 1, y + 9, .south)
        s.pole(x + 3, y + 3)
        s.pole(x + 3, y + 9)
    }

    /// Reaction-card module (15 wide), below the belt; petroleum arrives on the header at y+9, water from a pond:
    ///
    ///     y-2  = = = = = = = = = o = = = = =    science belt; o = blue output inserter at y-1
    ///     y0  [CP ] i [AC ] i [BLU] i [ENG]     CP = chem plant (plastic, facing south), AC = advanced circuits
    ///     y3   c . | . i . . . i . P i .        c/i = inserters, | petroleum pipe
    ///     y4   C . | . S . . [CPs] . S ~ ~      S = supply chests, CPs = chem plant (sulfur, facing south)
    ///     y7   . . | . . . . . | . - w ~ ~      w = offshore pump, - water pipe
    ///     y9   = = + = = = = = +                petroleum header
    static func blueModule(_ s: Stamper, x bx: Int, y by: Int, machine: String, speed: Double, minutes: Double) {
        let db = s.world.db
        let blueCrafts = minutes * 60 * speed / db.resolvedRecipes[db.recipe("reaction_card")].time
        let ac = blueCrafts * 3, engines = blueCrafts * 2
        func n(_ v: Double) -> Int { Int(v.rounded(.up)) }
        // machines in a row (top at by)
        s.machine("chemical_plant", bx, by, dir: .south, recipe: "plastic_bar")
        s.place("fast_inserter", bx + 3, by + 1, .east)
        s.machine(machine, bx + 4, by, recipe: "advanced_circuit")
        s.place("fast_inserter", bx + 7, by + 1, .east)
        s.machine(machine, bx + 8, by, recipe: "reaction_card")
        s.place("fast_inserter", bx + 11, by + 1, .west)
        s.machine(machine, bx + 12, by, recipe: "engine_unit")
        s.place("fast_inserter", bx + 9, by - 1, .north)              // cards onto the belt
        // feeds from below
        s.place("inserter", bx, by + 3, .north)                        // coal → plastic
        s.chest("steel_chest", bx, by + 4, [(db.item("coal"), n(ac))])
        s.place("fast_inserter", bx + 5, by + 3, .north)               // circuits + cable → AC
        s.chest("steel_chest", bx + 5, by + 4, [(db.item("electronic_circuit"), n(ac * 2)), (db.item("copper_cable"), n(ac * 4))])
        s.place("fast_inserter", bx + 9, by + 3, .north)               // sulfur → blue
        s.machine("chemical_plant", bx + 8, by + 4, dir: .south, recipe: "sulfur")
        s.place("fast_inserter", bx + 13, by + 3, .north)              // steel + gears + pipes → engines
        s.chest("steel_chest", bx + 13, by + 4, [(db.item("steel_plate"), n(engines)), (db.item("iron_gear_wheel"), n(engines)),
                                                 (db.item("pipe"), n(engines * 2))])
        // petroleum: plastic column + sulfur column down to the header (y+9)
        for y in (by + 3)...(by + 8) { s.place("pipe", bx + 2, y) }
        for y in (by + 7)...(by + 8) { s.place("pipe", bx + 8, y) }
        // water for sulfur: pond east of the module, pump facing east, one pipe into the plant
        s.water(x: bx + 12, y: by + 5, w: 3, h: 4)
        s.place("pipe", bx + 10, by + 7)
        s.place("offshore_pump", bx + 11, by + 7, .east)
        // power
        s.pole(bx + 3, by + 3)
        s.pole(bx + 7, by - 1)
        s.pole(bx + 11, by + 3)
    }

    /// Pumpjack (on a crude well placed here) → oil refinery → gas into the header at (bx-2, by+9).
    /// Basic: the pumpjack feeds the refinery directly. Advanced: water from a pond, heavy & light oil into
    /// storage tanks (25 000 each) — the player is expected to add cracking.
    static func oilBlock(_ s: Stamper, bx: Int, by: Int, mode: Oil, crude: UInt32) {
        let rx = bx - 6, ry = by + 11
        let oil = s.world.db.resource("crude_oil")
        if mode == .advanced {
            s.resource(rx + 2, ry + 7, oil, crude)
            s.machine("oil_refinery", rx, ry, recipe: "advanced_oil_processing")
            s.place("pumpjack", rx + 1, ry + 6, .north)
            s.place("pipe", rx + 3, ry + 5)                              // crude → box 1
            // water → box 0
            s.water(x: bx - 12, y: by + 14, w: 4, h: 5)
            for x in (rx - 1)...(rx + 1) { s.place("pipe", x, ry + 5) }
            s.place("offshore_pump", rx - 2, ry + 5, .west)
            // heavy oil → tank west
            s.place("pipe", rx, ry - 1); s.place("pipe", rx - 1, ry - 1)
            s.place("storage_tank", bx - 10, by + 8)
            // light oil → tank north-west
            for (x, y) in [(rx + 2, ry - 1), (rx + 2, ry - 2), (rx + 2, ry - 3), (rx + 1, ry - 3), (rx, ry - 3), (rx - 1, ry - 3),
                           (rx - 1, ry - 4), (rx - 1, ry - 5)] { s.place("pipe", x, y) }
            s.place("storage_tank", bx - 9, by + 3)
        } else {
            s.resource(rx, ry + 6, oil, crude)
            s.machine("oil_refinery", rx, ry, recipe: "basic_oil_processing")
            s.place("pumpjack", rx - 1, ry + 5, .north)
        }
        s.place("pipe", rx + 4, ry - 1)                                  // gas → header
        s.pole(bx, by + 7)
        s.pole(bx - 1, by + 12)
        s.pole(bx - 2, by + 17)
    }

    /// Labs on both sides of the belt (pairs every 4 tiles), each fed by an inserter from the belt.
    static func labRow(_ s: Stamper, x: Int, pairs: Int) -> [Int32] {
        var labs: [Int32] = []
        for p in 0..<pairs {
            let lx = x + 4 * p
            if let l = s.place("lab", lx, beltY - 4) { labs.append(l) }
            s.place("inserter", lx + 1, beltY - 1, .north)
            if let l = s.place("lab", lx, beltY + 2) { labs.append(l) }
            s.place("inserter", lx + 1, beltY + 1, .south)
            s.pole(lx + 3, beltY - 1)
        }
        return labs
    }

    // MARK: Stamper

    /// Places entities in factory-local coordinates, validating each placement.
    final class Stamper {
        let world: World
        let origin: TilePos
        var placed = 0
        var failures: [String] = []
        init(world: World, origin: TilePos) { self.world = world; self.origin = origin }

        func at(_ x: Int, _ y: Int) -> TilePos { TilePos(Int(origin.x) + x, Int(origin.y) + y) }

        func clear(w: Int, h: Int) {
            let grass = world.db.tile("grass_1")
            TileRect(origin: at(-1, -1), w: w + 2, h: h + 2).forEach { q in
                _ = world.surface.chunk(at: q)
                if let e = world.entity(at: q) { world.removeEntity(e) }
                world.surface.setTile(at: q, grass)
                world.surface.setResource(at: q, -1, amount: 0)
            }
        }

        func water(x: Int, y: Int, w: Int, h: Int) {
            let water = world.db.tile("water")
            for yy in y..<(y + h) { for xx in x..<(x + w) { world.surface.setTile(at: at(xx, yy), water) } }
        }

        func resource(_ x: Int, _ y: Int, _ r: Int, _ amount: UInt32) { world.surface.setResource(at: at(x, y), r, amount: amount) }

        @discardableResult
        func place(_ id: String, _ x: Int, _ y: Int, _ dir: Direction = .north) -> Int32? {
            let p = world.db.entity(id)
            guard p >= 0 else { failures.append("unknown entity \(id)"); return nil }
            let o = at(x, y)
            if let err = world.placementError(proto: p, origin: o, direction: dir) {
                failures.append("\(id) at local (\(x),\(y)): \(err)")
                return nil
            }
            placed += 1
            return world.createEntity(proto: p, origin: o, direction: dir)
        }

        func pole(_ x: Int, _ y: Int) { place("medium_electric_pole", x, y) }

        /// Splits a stock list over at most `maxChests` steel chests (48 slots each), scaling everything down
        /// proportionally when it would not fit (so a supply line simply runs for fewer minutes).
        func pack(_ items: [(Int, Int)], maxChests: Int, slotsPerChest: Int = 48) -> [[(Int, Int)]] {
            let items = items.filter { $0.0 >= 0 && $0.1 > 0 }
            guard !items.isEmpty else { return [] }
            func slots(_ l: [(Int, Int)]) -> Int { l.reduce(0) { $0 + ($1.1 + world.stackSize($1.0) - 1) / world.stackSize($1.0) } }
            var list = items
            let cap = maxChests * slotsPerChest
            if slots(list) > cap {
                var f = Double(cap) / Double(slots(list))
                repeat {
                    list = items.map { ($0.0, max(1, Int(Double($0.1) * f))) }
                    f *= 0.97
                } while slots(list) > cap
            }
            var out: [[(Int, Int)]] = [[]]
            var free = slotsPerChest
            for (item, count) in list {
                var left = count
                let stack = world.stackSize(item)
                while left > 0 {
                    if free == 0 { out.append([]); free = slotsPerChest }
                    let n = min(left, free * stack)
                    out[out.count - 1].append((item, n))
                    free -= (n + stack - 1) / stack
                    left -= n
                }
            }
            return out
        }

        @discardableResult
        func machine(_ id: String, _ x: Int, _ y: Int, dir: Direction = .north, recipe: String) -> Int32? {
            guard let e = place(id, x, y, dir) else { return nil }
            let r = world.db.recipe(recipe)
            if r < 0 { failures.append("unknown recipe \(recipe)"); return e }
            _ = world.crafting.setRecipe(e, r)
            return e
        }

        @discardableResult
        func chest(_ id: String, _ x: Int, _ y: Int, _ items: [(Int, Int)]) -> Int32? {
            guard let e = place(id, x, y) else { return nil }
            for (item, count) in items where item >= 0 && count > 0 {
                let got = world.containers.insert(e, item: item, count: count, source: .player)
                if got < count { failures.append("chest at local (\(x),\(y)) full: \(got)/\(count) of \(world.db.items[item].id)") }
            }
            return e
        }
    }
}
