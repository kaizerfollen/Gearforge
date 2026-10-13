// Gearforge — FactoryCore
// World payload of a save file: a list of tagged sections (ARCHITECTURE §5).
//   SETT settings (JSON) · CORE tick/rng/bonuses · SURF generated chunks · ENTS entity records ·
//   SYS<n> each entity system in `world.systems` order · RSCH research · CHAR character · STAT statistics
// The session (mode, play time, objectives) is appended by GameSession as section SESS.
// Owner: Progression engineer.

import Foundation

public enum WorldCodec {
    public static let payloadVersion: UInt8 = 1

    // MARK: Encode

    public static func encode(_ world: World, extra: [(UInt32, [UInt8])] = []) -> [UInt8] {
        var w = BinaryWriter(reserve: 1 << 20)
        w.write(payloadVersion)
        w.write(UInt32(world.db.items.count)); w.write(UInt32(world.db.entities.count)); w.write(UInt32(world.db.recipes.count))
        w.writeSection(tag: fourCC("SETT")) { s in
            let json = (try? JSONEncoder().encode(world.settings)) ?? Data()
            s.writeBytes([UInt8](json))
        }
        w.writeSection(tag: fourCC("CORE")) { s in
            s.write(world.tick)
            let st = world.rng.state
            s.write(st.0); s.write(st.1); s.write(st.2); s.write(st.3)
            let b = world.bonuses
            s.write(Int64(b.inserterStackBonus)); s.write(Int64(b.stackInserterBonus)); s.write(b.miningProductivity)
            s.write(b.labSpeed); s.write(b.characterMiningSpeed); s.write(Int64(b.characterInventoryBonus))
            s.write(b.workerRobotSpeed); s.write(Int64(b.workerRobotStorage)); s.write(b.trainBrakingForce)
        }
        w.writeSection(tag: fourCC("SURF")) { s in
            let chunks = world.surface.generatedChunks
            s.writeVarInt(chunks.count)
            for ch in chunks {
                s.write(ch.pos.x); s.write(ch.pos.y)
                s.write(ch.charted)
                s.writeCompactPODArray(ch.tiles)
                s.writeCompactPODArray(ch.resource)
                s.writeCompactPODArray(ch.resourceAmount)
            }
        }
        w.writeSection(tag: fourCC("ENTS")) { s in
            let recs = world.entities.records
            s.writeVarInt(recs.count)
            for r in recs {
                s.write(r.proto)
                guard r.proto >= 0 else { s.write(r.generation); continue }
                s.write(r.origin); s.write(r.w); s.write(r.h); s.write(r.direction.rawValue); s.write(r.flags.rawValue)
                s.write(r.component); s.write(r.powerSlot); s.write(r.fluidSlot); s.write(r.generation); s.write(r.health)
            }
        }
        for (i, sys) in world.systems.enumerated() {
            w.writeSection(tag: fourCC("SYS0") &+ UInt32(i) << 24) { s in sys.serialize(to: &s) }
        }
        w.writeSection(tag: fourCC("RSCH")) { s in world.research.serialize(to: &s) }
        w.writeSection(tag: fourCC("CHAR")) { s in world.player.serialize(to: &s) }
        w.writeSection(tag: fourCC("STAT")) { s in world.stats.serialize(to: &s) }
        w.writeSection(tag: fourCC("GRND")) { s in world.ground.serialize(to: &s) }
        w.writeSection(tag: fourCC("POLL")) { s in world.pollution.serialize(to: &s) }
        for (tag, bytes) in extra { w.writeSection(tag: tag) { $0.writeRaw(bytes) } }
        return w.bytes
    }

    // MARK: Decode

    /// Rebuilds a World from a payload. Returns the world and any unknown/extra sections (e.g. SESS).
    public static func decode(_ bytes: [UInt8], db: PrototypeDB = .shared) throws -> (World, [UInt32: BinaryReader]) {
        var r = BinaryReader(bytes)
        let v = try r.read(UInt8.self)
        guard v >= 1 && v <= payloadVersion else { throw SaveError.unsupportedVersion(file: Int(v), reader: Int(payloadVersion)) }
        let ni = Int(try r.read(UInt32.self)), ne = Int(try r.read(UInt32.self)), nr = Int(try r.read(UInt32.self))
        guard ni == db.items.count, ne == db.entities.count, nr == db.recipes.count else {
            throw SaveError.incompatibleGameData("items \(ni)/\(db.items.count), entities \(ne)/\(db.entities.count), recipes \(nr)/\(db.recipes.count)")
        }
        var sections: [UInt32: BinaryReader] = [:]
        var order: [UInt32] = []
        while !r.isAtEnd {
            let (tag, sub) = try r.readSection()
            sections[tag] = sub
            order.append(tag)
        }
        func section(_ name: StaticString) throws -> BinaryReader {
            guard let s = sections[fourCC(name)] else { throw SaveError.missingSection("\(name)") }
            return s
        }
        // settings → world
        var sett = try section("SETT")
        let settings = try JSONDecoder().decode(WorldSettings.self, from: Data(try sett.readBytes()))
        let world = World(db: db, settings: settings)
        let recordEvents = world.recordsEvents
        world.recordsEvents = false

        var core = try section("CORE")
        world.tick = try core.read(UInt64.self)
        world.rng = DeterministicRNG(state: (try core.read(UInt64.self), try core.read(UInt64.self), try core.read(UInt64.self), try core.read(UInt64.self)))
        var b = ForceBonuses()
        b.inserterStackBonus = Int(try core.read(Int64.self)); b.stackInserterBonus = Int(try core.read(Int64.self))
        b.miningProductivity = try core.readDouble(); b.labSpeed = try core.readDouble()
        b.characterMiningSpeed = try core.readDouble(); b.characterInventoryBonus = Int(try core.read(Int64.self))
        b.workerRobotSpeed = try core.readDouble(); b.workerRobotStorage = Int(try core.read(Int64.self))
        b.trainBrakingForce = try core.readDouble()
        world.bonuses = b

        var surf = try section("SURF")
        let n = chunkSize * chunkSize
        let nc = try surf.readVarInt()
        for _ in 0..<nc {
            let pos = ChunkPos(try surf.read(Int32.self), try surf.read(Int32.self))
            let ch = Chunk(pos: pos, fillTile: 0)
            ch.charted = try surf.readBool()
            ch.tiles = try surf.readCompactPODArray(UInt8.self, expectedCount: n)
            ch.resource = try surf.readCompactPODArray(UInt8.self, expectedCount: n)
            ch.resourceAmount = try surf.readCompactPODArray(UInt32.self, expectedCount: n)
            world.surface.setChunk(ch)
        }

        var ents = try section("ENTS")
        let count = try ents.readVarInt()
        var recs: [EntityRecord] = []
        recs.reserveCapacity(count)
        for _ in 0..<count {
            let proto = try ents.read(Int32.self)
            if proto < 0 {
                let gen = try ents.read(UInt32.self)
                recs.append(EntityRecord(proto: -1, kind: .other, origin: TilePos(0, 0), w: 0, h: 0, direction: .north,
                                         flags: [], component: -1, powerSlot: -1, fluidSlot: -1, generation: gen, health: 0))
                continue
            }
            guard Int(proto) < db.entities.count else { throw SaveError.corruptSection("ENTS", "proto \(proto)") }
            let origin = try ents.readTilePos()
            let w = try ents.read(Int16.self), h = try ents.read(Int16.self)
            let dir = Direction(rawValue: try ents.read(UInt8.self)) ?? .north
            let flags = EntityFlags(rawValue: try ents.read(UInt16.self))
            let comp = try ents.read(Int32.self), ps = try ents.read(Int32.self), fs = try ents.read(Int32.self)
            let gen = try ents.read(UInt32.self), hp = try ents.readFloat()
            recs.append(EntityRecord(proto: proto, kind: db.entities[Int(proto)].kind, origin: origin, w: w, h: h, direction: dir,
                                     flags: flags, component: comp, powerSlot: ps, fluidSlot: fs, generation: gen, health: hp))
        }
        world.entities.restore(records: recs)
        // occupancy + chunk entity lists
        for i in 0..<recs.count where recs[i].proto >= 0 {
            let e = Int32(i)
            recs[i].rect.forEach { world.surface.setOccupant(at: $0, e) }
            world.surface.existingChunk(recs[i].origin.chunk)?.entities.append(e)
        }

        for (i, sys) in world.systems.enumerated() {
            guard var s = sections[fourCC("SYS0") &+ UInt32(i) << 24] else { throw SaveError.missingSection("SYS\(i)") }
            do { try sys.deserialize(from: &s) } catch { throw SaveError.corruptSection("SYS\(i)", "\(error)") }
        }
        var rs = try section("RSCH"); try world.research.deserialize(from: &rs)
        var cs = try section("CHAR"); try world.player.deserialize(from: &cs)
        var st = try section("STAT"); try world.stats.deserialize(from: &st)
        if var g = sections[fourCC("GRND")] { try world.ground.deserialize(from: &g) }
        if var pl = sections[fourCC("POLL")] { try world.pollution.deserialize(from: &pl) }
        for sys in world.systems { sys.didLoad() }
        world.recordsEvents = recordEvents
        let known: Set<UInt32> = Set(["SETT", "CORE", "SURF", "ENTS", "RSCH", "CHAR", "STAT", "GRND", "POLL"].map { fourCCDynamic($0) })
            .union((0..<world.systems.count).map { fourCC("SYS0") &+ UInt32($0) << 24 })
        var extra: [UInt32: BinaryReader] = [:]
        for t in order where !known.contains(t) { extra[t] = sections[t] }
        return (world, extra)
    }

    static func fourCCDynamic(_ s: String) -> UInt32 {
        var v: UInt32 = 0
        for (i, c) in s.utf8.prefix(4).enumerated() { v |= UInt32(c) << (8 * UInt32(i)) }
        return v
    }
}
