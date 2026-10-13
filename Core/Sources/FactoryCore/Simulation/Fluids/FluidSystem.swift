// Gearforge — FactoryCore
// Fluid boxes and Factorio-2.0-style pipe segments (05_mechanics §7.2): pipes, pipe-to-ground, pumps, offshore
// pumps, storage tanks; plus fluid boxes of machines (assemblers, chem plants, refineries, boilers, engines, drills).
// Owner: Energy engineer.
//
// Model
// -----
// Every entity with `fluidBoxes` gets one `FBox` per prototype box. Boxes of type "none" / "input-output" (pipes,
// tanks, boiler water pass-through, steam engines) are **members**: connected members form a `Segment` that stores
// one (fluid, amount, capacity, temperature) — flow inside a segment is instantaneous. Boxes of type "input" /
// "output" (machine inputs/outputs, boiler steam out, offshore pump, pumpjack) are **endpoints** with their own
// storage that exchange up to `connectionFlowPerTick` with the adjacent segment each tick. Pumps move fluid between
// the segment behind and the segment in front. Topology is rebuilt lazily after build/remove/rotate.

public final class FluidSystem: EntitySystem {
    public unowned let world: World
    public init(world: World) { self.world = world }

    /// Per-connection transfer cap (6 000/s).
    public static let connectionFlowPerTick: Double = 100

    enum BoxType: UInt8 { case none = 0, input, output, inputOutput }

    struct FBox {
        var entity: Int32 = -1
        var index: Int32 = 0
        var type: BoxType = .none
        var volume: Double = 100
        var filter: Int32 = -1
        var fluid: Int32 = -1
        var amount: Double = 0
        var temperature: Double = 15
        var segment: Int32 = -1
        var isMember: Bool { type == .none || type == .inputOutput }
    }

    struct Segment {
        var fluid: Int32 = -1
        var filter: Int32 = -1
        var amount: Double = 0
        var capacity: Double = 0
        var temperature: Double = 15
        var members: [Int32] = []
        var space: Double { max(0, capacity - amount) }
    }

    struct EndpointLink { var box: Int32; var segment: Int32 }
    struct PumpLink { var entity: Int32; var box: Int32; var from: Int32; var to: Int32 }

    var boxes: [FBox] = []
    private var freeBoxes: [Int32] = []
    /// fluidSlot → box indices of that entity.
    var entityBoxes: [[Int32]] = []
    private var freeSlots: [Int32] = []

    var segments: [Segment] = []
    private var endpointLinks: [EndpointLink] = []
    private var pumpLinks: [PumpLink] = []
    private var segmentOfBoxCache: [Int32] = []
    private var dirty = true

    // MARK: Registration

    /// Creates fluid boxes for any entity whose prototype has `fluidBoxes` (machines, boilers, engines, pipes...).
    public func registerEndpointIfNeeded(_ e: Int32) {
        let rec = world.entities[e]
        let p = world.db.entities[Int(rec.proto)]
        guard let fbs = p.fluidBoxes, !fbs.isEmpty else { return }
        var ids: [Int32] = []
        for (i, fb) in fbs.enumerated() {
            var b = FBox()
            b.entity = e
            b.index = Int32(i)
            switch fb.productionType {
            case "input": b.type = .input
            case "output": b.type = .output
            case "input-output": b.type = .inputOutput
            default: b.type = .none
            }
            if rec.kind == .pump { b.type = .input }          // pumps are links, never segment members
            b.volume = fb.volume
            b.filter = fb.filter.map { Int32(world.db.fluid($0)) } ?? -1
            let id: Int32
            if let f = freeBoxes.popLast() { id = f; boxes[Int(f)] = b } else { id = Int32(boxes.count); boxes.append(b) }
            ids.append(id)
        }
        let slot: Int32
        if let f = freeSlots.popLast() { slot = f; entityBoxes[Int(f)] = ids } else { slot = Int32(entityBoxes.count); entityBoxes.append(ids) }
        world.entities.setFluidSlot(e, slot)
        dirty = true
    }

    public func unregisterEndpointIfNeeded(_ e: Int32) {
        let slot = world.entities[e].fluidSlot
        guard slot >= 0, Int(slot) < entityBoxes.count else { return }
        ensureTopology()
        // Remove this entity's share from its segments so the rest keep their contents.
        for b in entityBoxes[Int(slot)] {
            let s = boxes[Int(b)].segment
            if boxes[Int(b)].isMember && s >= 0 {
                let share = segments[Int(s)].capacity > 0 ? segments[Int(s)].amount * boxes[Int(b)].volume / segments[Int(s)].capacity : 0
                segments[Int(s)].amount -= share
                segments[Int(s)].capacity -= boxes[Int(b)].volume
            }
            boxes[Int(b)] = FBox()
            freeBoxes.append(b)
        }
        entityBoxes[Int(slot)] = []
        freeSlots.append(slot)
        world.entities.setFluidSlot(e, -1)
        dirty = true
    }

    public func endpointRotated(_ e: Int32) { if world.entities[e].fluidSlot >= 0 { dirty = true } }

    @inline(__always) private func boxID(_ e: Int32, _ box: Int) -> Int? {
        let slot = world.entities[e].fluidSlot
        guard slot >= 0, Int(slot) < entityBoxes.count else { return nil }
        let ids = entityBoxes[Int(slot)]
        return box >= 0 && box < ids.count ? Int(ids[box]) : nil
    }

    // MARK: Fluid box API for machines (box index = index in prototype.fluidBoxes)

    public func boxCount(_ e: Int32) -> Int {
        let slot = world.entities[e].fluidSlot
        return slot >= 0 && Int(slot) < entityBoxes.count ? entityBoxes[Int(slot)].count : 0
    }

    /// Fluid index in the box, or -1 if empty.
    public func fluid(_ e: Int32, box: Int) -> Int {
        ensureTopology()
        guard let b = boxID(e, box) else { return -1 }
        if boxes[b].isMember, boxes[b].segment >= 0 {
            let s = segments[Int(boxes[b].segment)]
            return s.amount > 1e-9 ? Int(s.fluid) : -1
        }
        return boxes[b].amount > 1e-9 ? Int(boxes[b].fluid) : -1
    }

    public func amount(_ e: Int32, box: Int) -> Double {
        ensureTopology()
        guard let b = boxID(e, box) else { return 0 }
        if boxes[b].isMember, boxes[b].segment >= 0 {
            let s = segments[Int(boxes[b].segment)]
            return s.capacity > 0 ? s.amount * boxes[b].volume / s.capacity : 0
        }
        return boxes[b].amount
    }

    public func capacity(_ e: Int32, box: Int) -> Double {
        guard let b = boxID(e, box) else { return 0 }
        return boxes[b].volume
    }

    public func temperature(_ e: Int32, box: Int) -> Double {
        ensureTopology()
        guard let b = boxID(e, box) else { return 15 }
        if boxes[b].isMember, boxes[b].segment >= 0 { return segments[Int(boxes[b].segment)].temperature }
        return boxes[b].temperature
    }

    /// Whole-segment contents behind a member box (UI: pipe tooltip).
    public func segmentContents(of e: Int32) -> (fluid: Int, amount: Double, capacity: Double)? {
        ensureTopology()
        guard let b = boxID(e, 0), boxes[b].segment >= 0 else { return nil }
        let s = segments[Int(boxes[b].segment)]
        return (s.amount > 1e-9 ? Int(s.fluid) : -1, s.amount, s.capacity)
    }

    /// Adds fluid; returns the amount accepted.
    @discardableResult public func add(_ e: Int32, box: Int, fluid: Int, amount: Double, temperature: Double) -> Double {
        ensureTopology()
        guard amount > 0, fluid >= 0, let b = boxID(e, box) else { return 0 }
        if boxes[b].isMember, boxes[b].segment >= 0 {
            return addToSegment(Int(boxes[b].segment), fluid: Int32(fluid), amount: amount, temperature: temperature)
        }
        if boxes[b].filter >= 0 && Int(boxes[b].filter) != fluid { return 0 }
        if boxes[b].amount > 1e-9 && Int(boxes[b].fluid) != fluid { return 0 }
        let a = min(amount, max(0, boxes[b].volume - boxes[b].amount))
        guard a > 0 else { return 0 }
        boxes[b].temperature = mix(boxes[b].amount, boxes[b].temperature, a, temperature)
        boxes[b].amount += a
        boxes[b].fluid = Int32(fluid)
        return a
    }

    /// Removes fluid; returns the amount removed.
    @discardableResult public func remove(_ e: Int32, box: Int, amount: Double) -> Double {
        ensureTopology()
        guard amount > 0, let b = boxID(e, box) else { return 0 }
        if boxes[b].isMember, boxes[b].segment >= 0 {
            let s = Int(boxes[b].segment)
            let a = min(amount, segments[s].amount)
            segments[s].amount -= a
            return a
        }
        let a = min(amount, boxes[b].amount)
        boxes[b].amount -= a
        return a
    }

    /// Sets the filter (fluid index or -1) of a machine box, e.g. when an assembler recipe changes.
    public func setFilter(_ e: Int32, box: Int, fluid: Int) {
        guard let b = boxID(e, box) else { return }
        boxes[b].filter = Int32(fluid)
        if fluid >= 0 && boxes[b].amount > 0 && Int(boxes[b].fluid) != fluid && !boxes[b].isMember {
            boxes[b].amount = 0   // wrong fluid is voided on recipe change [GF]
        }
    }

    @inline(__always) private func mix(_ a1: Double, _ t1: Double, _ a2: Double, _ t2: Double) -> Double {
        let s = a1 + a2
        return s > 0 ? (a1 * t1 + a2 * t2) / s : t2
    }

    private func addToSegment(_ s: Int, fluid: Int32, amount: Double, temperature: Double) -> Double {
        if segments[s].filter >= 0 && segments[s].filter != fluid { return 0 }
        if segments[s].amount > 1e-9 && segments[s].fluid != fluid { return 0 }
        let a = min(amount, segments[s].space)
        guard a > 0 else { return 0 }
        segments[s].temperature = mix(segments[s].amount, segments[s].temperature, a, temperature)
        segments[s].amount += a
        segments[s].fluid = fluid
        return a
    }

    // MARK: Topology

    @inline(__always) func ensureTopology() { if dirty { rebuild() } }

    /// World tiles of a box's connections: (neighbour tile, own tile, connection type, isUnderground).
    private func connections(proto: Int, origin: TilePos, direction: Direction, box: Int) -> [(TilePos, String, Bool)] {
        let p = world.db.entities[proto]
        guard let fbs = p.fluidBoxes, box < fbs.count else { return [] }
        let (w, h) = world.footprint(proto, direction)
        let cx = Double(origin.x) + Double(w) / 2, cy = Double(origin.y) + Double(h) / 2
        var out: [(TilePos, String, Bool)] = []
        for (ci, c) in fbs[box].connections.enumerated() {
            let v = direction.rotate(c.position)
            let n = TilePos(Int32((cx + v.x).rounded(.down)), Int32((cy + v.y).rounded(.down)))
            let underground = p.kind == .pipeToGround && ci == 1
            out.append((n, c.type, underground))
        }
        return out
    }

    private func rebuild() {
        dirty = false
        // 1. Push segment contents back to member boxes.
        for s in segments where s.capacity > 0 {
            for m in s.members where boxes[Int(m)].entity >= 0 {
                boxes[Int(m)].amount = s.amount * boxes[Int(m)].volume / s.capacity
                boxes[Int(m)].fluid = s.fluid
                boxes[Int(m)].temperature = s.temperature
            }
        }
        segments.removeAll(keepingCapacity: true)
        endpointLinks.removeAll(keepingCapacity: true)
        pumpLinks.removeAll(keepingCapacity: true)
        let n = boxes.count
        var parent = Array(0..<n)
        func find(_ x: Int) -> Int { var x = x; while parent[x] != x { parent[x] = parent[parent[x]]; x = parent[x] }; return x }
        func union(_ a: Int, _ b: Int) { let ra = find(a), rb = find(b); if ra != rb { parent[max(ra, rb)] = min(ra, rb) } }

        // 2. Links between boxes
        var links: [(Int, Int)] = []
        var pumpSides: [Int: (from: Int, to: Int)] = [:]      // pump box → (input neighbour box, output neighbour box)
        for b in 0..<n where boxes[b].entity >= 0 {
            let e = boxes[b].entity
            let rec = world.entities[e]
            for (nt, ctype, underground) in connections(proto: Int(rec.proto), origin: rec.origin, direction: rec.direction, box: Int(boxes[b].index)) {
                var otherBox: Int? = nil
                if underground {
                    otherBox = undergroundPartner(of: e)
                } else if let o = world.entity(at: nt), o != e, world.entities[o].fluidSlot >= 0 {
                    let orec = world.entities[o]
                    // find a box of o whose connection points back into e's footprint, adjacent to nt
                    for (bi, ob) in entityBoxes[Int(orec.fluidSlot)].enumerated() {
                        for (nt2, _, ug2) in connections(proto: Int(orec.proto), origin: orec.origin, direction: orec.direction, box: bi) where !ug2 {
                            if rec.rect.contains(nt2) && abs(nt2.x - nt.x) + abs(nt2.y - nt.y) == 1 { otherBox = Int(ob) }
                        }
                    }
                }
                guard let ob = otherBox else { continue }
                if rec.kind == .pump {
                    var sides = pumpSides[b] ?? (-1, -1)
                    if ctype == "output" { sides.to = ob } else { sides.from = ob }
                    pumpSides[b] = sides
                    continue
                }
                if world.entities[boxes[ob].entity].kind == .pump { continue }
                links.append((b, ob))
            }
        }
        for (a, b) in links where boxes[a].isMember && boxes[b].isMember { union(a, b) }

        // 3. Segments
        var segOfRoot = [Int32](repeating: -1, count: n)
        for b in 0..<n where boxes[b].entity >= 0 {
            if !boxes[b].isMember { boxes[b].segment = -1; continue }
            let r = find(b)
            if segOfRoot[r] < 0 { segOfRoot[r] = Int32(segments.count); segments.append(Segment()) }
            let s = Int(segOfRoot[r])
            boxes[b].segment = Int32(s)
            segments[s].members.append(Int32(b))
            segments[s].capacity += boxes[b].volume
            if boxes[b].filter >= 0 { segments[s].filter = boxes[b].filter }
            if boxes[b].amount > 1e-9 {
                if segments[s].amount <= 1e-9 || segments[s].fluid == boxes[b].fluid {
                    segments[s].temperature = mix(segments[s].amount, segments[s].temperature, boxes[b].amount, boxes[b].temperature)
                    segments[s].amount += boxes[b].amount
                    segments[s].fluid = boxes[b].fluid
                }
            }
        }
        for s in segments.indices { segments[s].amount = min(segments[s].amount, segments[s].capacity) }

        // 4. Endpoint ↔ segment links (deduplicated)
        var seen = Set<Int64>()
        for (a, b) in links {
            let (ep, mem) = boxes[a].isMember ? (b, a) : (a, b)
            guard !boxes[ep].isMember, boxes[mem].isMember else { continue }
            let key = Int64(ep) << 32 | Int64(boxes[mem].segment)
            if seen.insert(key).inserted { endpointLinks.append(EndpointLink(box: Int32(ep), segment: boxes[mem].segment)) }
        }
        endpointLinks.sort { $0.box < $1.box }
        // 5. Pumps
        for (pb, sides) in pumpSides.sorted(by: { $0.key < $1.key }) {
            let from = sides.from >= 0 && boxes[sides.from].isMember ? boxes[sides.from].segment : -1
            let to = sides.to >= 0 && boxes[sides.to].isMember ? boxes[sides.to].segment : -1
            if from >= 0 && to >= 0 && from != to { pumpLinks.append(PumpLink(entity: boxes[pb].entity, box: Int32(pb), from: from, to: to)) }
        }
    }

    /// Partner of a pipe-to-ground (facing opposite direction, within 10 tiles behind it).
    private func undergroundPartner(of e: Int32) -> Int? {
        let rec = world.entities[e]
        let back = rec.direction.opposite
        var k: Int32 = 1
        while k <= 10 {
            if let o = world.entity(at: rec.origin.offset(back, k)), world.entities[o].kind == .pipeToGround, world.entities[o].proto == rec.proto {
                if world.entities[o].direction == back, world.entities[o].fluidSlot >= 0 {
                    return Int(entityBoxes[Int(world.entities[o].fluidSlot)][0])
                }
                if world.entities[o].direction == rec.direction { return nil }
            }
            k += 1
        }
        return nil
    }

    // MARK: Placement helpers (used by Commands)

    /// True if placing `proto` at origin/direction would connect fluid boxes holding different fluids.
    public func wouldMixFluids(proto: Int, origin: TilePos, direction: Direction) -> Bool {
        ensureTopology()
        let p = world.db.entities[proto]
        guard let fbs = p.fluidBoxes else { return false }
        let (w, h) = world.footprint(proto, direction)
        let rect = TileRect(origin: origin, w: w, h: h)
        for bi in fbs.indices {
            var fluids = Set<Int32>()
            if let f = fbs[bi].filter { fluids.insert(Int32(world.db.fluid(f))) }
            for (nt, _, ug) in connections(proto: proto, origin: origin, direction: direction, box: bi) where !ug {
                guard let o = world.entity(at: nt), world.entities[o].fluidSlot >= 0 else { continue }
                let orec = world.entities[o]
                for (obi, ob) in entityBoxes[Int(orec.fluidSlot)].enumerated() {
                    let faces = connections(proto: Int(orec.proto), origin: orec.origin, direction: orec.direction, box: obi)
                        .contains { !$0.2 && rect.contains($0.0) && abs($0.0.x - nt.x) + abs($0.0.y - nt.y) == 1 }
                    guard faces else { continue }
                    let box = boxes[Int(ob)]
                    if box.isMember, box.segment >= 0 {
                        let s = segments[Int(box.segment)]
                        if s.amount > 1e-9 { fluids.insert(s.fluid) } else if s.filter >= 0 { fluids.insert(s.filter) }
                    } else if box.amount > 1e-9 { fluids.insert(box.fluid) } else if box.filter >= 0 { fluids.insert(box.filter) }
                }
            }
            if fluids.count > 1 && (p.kind == .pipe || p.kind == .pipeToGround || p.kind == .storageTank || fbs[bi].productionType == "input-output" || fbs[bi].productionType == "none") {
                return true
            }
        }
        return false
    }

    /// For renderers: fill of the segment/box an entity belongs to (fluid index or -1, fraction 0...1).
    public func fill(of e: Int32) -> (fluid: Int, fraction: Double) {
        ensureTopology()
        guard let b = boxID(e, 0) else { return (-1, 0) }
        if boxes[b].isMember, boxes[b].segment >= 0 {
            let s = segments[Int(boxes[b].segment)]
            return (s.amount > 1e-9 ? Int(s.fluid) : -1, s.capacity > 0 ? s.amount / s.capacity : 0)
        }
        return (boxes[b].amount > 1e-9 ? Int(boxes[b].fluid) : -1, boxes[b].volume > 0 ? boxes[b].amount / boxes[b].volume : 0)
    }

    /// Which of the 4 sides of a pipe tile have a connected neighbour (bitmask N=1,E=2,S=4,W=8) — sprite selection.
    public func pipeConnections(of e: Int32) -> UInt8 {
        let rec = world.entities[e]
        guard rec.fluidSlot >= 0 else { return 0 }
        var mask: UInt8 = 0
        for (nt, _, ug) in connections(proto: Int(rec.proto), origin: rec.origin, direction: rec.direction, box: 0) where !ug {
            guard let o = world.entity(at: nt), o != e, world.entities[o].fluidSlot >= 0 else { continue }
            let orec = world.entities[o]
            var back = false
            for bi in 0..<entityBoxes[Int(orec.fluidSlot)].count {
                for (nt2, _, ug2) in connections(proto: Int(orec.proto), origin: orec.origin, direction: orec.direction, box: bi) where !ug2 {
                    if rec.rect.contains(nt2) { back = true }
                }
            }
            guard back else { continue }
            let dx = nt.x - rec.origin.x, dy = nt.y - rec.origin.y
            if dy < 0 { mask |= 1 } else if dx > 0 { mask |= 2 } else if dy > 0 { mask |= 4 } else if dx < 0 { mask |= 8 }
        }
        return mask
    }

    // MARK: EntitySystem (owns pipes, pipe-to-ground, pumps, offshore pumps, tanks)

    public func entityAdded(_ e: Int32) {}
    public func entityRemoved(_ e: Int32) {}

    public func update() {
        ensureTopology()
        let db = world.db
        // Offshore pumps produce into their own output box.
        for b in boxes.indices where boxes[b].entity >= 0 && boxes[b].type == .output {
            let rec = world.entities[boxes[b].entity]
            if rec.kind == .offshorePump, let op = db.entities[Int(rec.proto)].offshorePump {
                let water = Int32(db.fluid(op.fluid))
                let a = min(op.pumpingSpeed, boxes[b].volume - boxes[b].amount)
                if a > 0 {
                    boxes[b].amount += a; boxes[b].fluid = water; boxes[b].temperature = db.fluids[Int(water)].defaultTemperature
                    world.stats.producedFluid(Int(water), amount: a)
                }
            }
        }
        // Outputs push into segments.
        for l in endpointLinks where boxes[Int(l.box)].type == .output {
            let b = Int(l.box)
            guard boxes[b].amount > 1e-9 else { continue }
            let a = addToSegment(Int(l.segment), fluid: boxes[b].fluid, amount: min(boxes[b].amount, Self.connectionFlowPerTick), temperature: boxes[b].temperature)
            boxes[b].amount -= a
        }
        // Pumps
        let power = world.power!
        for p in pumpLinks {
            let sigma = power.satisfaction(of: p.entity)
            let usage = (db.entities[Int(world.entities[p.entity].proto)].energyUsage ?? 0) / 60
            let drain = (db.entities[Int(world.entities[p.entity].proto)].energySource?.drain ?? 0) / 60
            let from = Int(p.from), to = Int(p.to)
            let speed = db.entities[Int(world.entities[p.entity].proto)].pump?.pumpingSpeed ?? 200
            var moved = 0.0
            if sigma > 0 && segments[from].amount > 1e-9 {
                let want = min(speed * sigma, segments[from].amount)
                moved = addToSegment(to, fluid: segments[from].fluid, amount: want, temperature: segments[from].temperature)
                segments[from].amount -= moved
            }
            power.request(p.entity, joules: drain + (moved > 0 ? usage : 0))
        }
        // Inputs pull from segments, proportionally when the segment can't satisfy everyone.
        var demand = [Double](repeating: 0, count: segments.count)
        for l in endpointLinks where boxes[Int(l.box)].type == .input {
            let b = boxes[Int(l.box)]
            let s = segments[Int(l.segment)]
            guard s.amount > 1e-9, b.filter < 0 || b.filter == s.fluid, b.amount <= 1e-9 || b.fluid == s.fluid else { continue }
            demand[Int(l.segment)] += min(Self.connectionFlowPerTick, b.volume - b.amount)
        }
        for l in endpointLinks where boxes[Int(l.box)].type == .input {
            let bi = Int(l.box), si = Int(l.segment)
            let s = segments[si]
            guard demand[si] > 0, s.amount > 1e-9 else { continue }
            let b = boxes[bi]
            guard b.filter < 0 || b.filter == s.fluid, b.amount <= 1e-9 || b.fluid == s.fluid else { continue }
            let want = min(Self.connectionFlowPerTick, b.volume - b.amount)
            guard want > 0 else { continue }
            let share = s.amount >= demand[si] ? want : want * s.amount / demand[si]
            let a = min(share, segments[si].amount)
            boxes[bi].temperature = mix(b.amount, b.temperature, a, s.temperature)
            boxes[bi].amount += a
            boxes[bi].fluid = s.fluid
            segments[si].amount -= a
        }
        for s in segments.indices where segments[s].amount < 1e-9 { segments[s].amount = 0 }
    }

    // MARK: Persistence

    public func serialize(to w: inout BinaryWriter) {
        ensureTopology()
        // push segment contents to members so boxes carry the truth
        for s in segments where s.capacity > 0 {
            for m in s.members where boxes[Int(m)].entity >= 0 {
                boxes[Int(m)].amount = s.amount * boxes[Int(m)].volume / s.capacity
                boxes[Int(m)].fluid = s.fluid
                boxes[Int(m)].temperature = s.temperature
            }
        }
        w.write(UInt8(1))
        w.writeVarInt(boxes.count)
        for b in boxes {
            w.write(b.entity); w.write(b.index); w.write(b.type.rawValue); w.write(b.volume)
            w.write(b.filter); w.write(b.fluid); w.write(b.amount); w.write(b.temperature)
        }
        w.writeVarInt(entityBoxes.count)
        for ids in entityBoxes { w.writeArray(ids) { $0.write($1) } }
    }

    public func deserialize(from r: inout BinaryReader) throws {
        _ = try r.read(UInt8.self)
        let n = try r.readVarInt()
        boxes = []; freeBoxes = []
        for i in 0..<n {
            var b = FBox()
            b.entity = try r.read(Int32.self); b.index = try r.read(Int32.self)
            b.type = BoxType(rawValue: try r.read(UInt8.self)) ?? .none
            b.volume = try r.readDouble(); b.filter = try r.read(Int32.self); b.fluid = try r.read(Int32.self)
            b.amount = try r.readDouble(); b.temperature = try r.readDouble()
            boxes.append(b)
            if b.entity < 0 { freeBoxes.append(Int32(i)) }
        }
        let m = try r.readVarInt()
        entityBoxes = []; freeSlots = []
        for i in 0..<m {
            let ids = try r.readArray { try $0.read(Int32.self) }
            entityBoxes.append(ids)
            if ids.isEmpty { freeSlots.append(Int32(i)) }
        }
        segments = []
        dirty = true
    }

    public func didLoad() { ensureTopology() }
}
