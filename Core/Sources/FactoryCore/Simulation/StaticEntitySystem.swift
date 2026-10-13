// Gearforge — FactoryCore
// Entities with little or no simulation: trees, rocks, walls, gates, radar (charting), lamps, turrets (inert in MVP),
// and "other" later-phase entities. Owner: Gameplay engineer.
// Electric statics (lamps, radar) draw their working power every tick so they show up in the power graph.
// Radar: keeps `nearbyChunkRadius` charted while powered and scans one far chunk (within `scanChunkRadius`) per
// `energyPerSector` joules received, spiralling outwards (05/GDD map rules).

public final class StaticEntitySystem: EntitySystem {
    public unowned let world: World
    public init(world: World) { self.world = world }

    private var electric: [Int32] = []
    private var usage: [Double] = []

    struct Radar {
        var entity: Int32
        var energy: Double = 0
        var scanIndex: Int = 0
    }
    private var radars: [Radar] = []
    /// Spiral offsets (ring order) per scan radius, cached.
    private var spiralCache: [Int32: [ChunkPos]] = [:]

    public func entityAdded(_ e: Int32) {
        let p = world.db.entities[Int(world.entities[e].proto)]
        if p.energySource?.type == "electric" {
            electric.append(e)
            usage.append(((p.energyUsage ?? 0) + (p.energySource?.drain ?? 0)) / 60)
        }
        if p.radar != nil && !radars.contains(where: { $0.entity == e }) {
            radars.append(Radar(entity: e))
            // a freshly built radar immediately reveals its nearby area
            world.chartArea(around: world.entities[e].origin.chunk, radius: Int32(p.radar!.nearbyChunkRadius))
        }
    }

    public func entityRemoved(_ e: Int32) {
        if let i = electric.firstIndex(of: e) { electric.remove(at: i); usage.remove(at: i) }
        radars.removeAll { $0.entity == e }
    }

    /// Lamp is lit at night when powered.
    public func isLampOn(_ e: Int32) -> Bool {
        world.daylight < 0.5 && world.power.satisfaction(of: e) > 0
    }

    /// Radar scan progress 0...1 towards the next sector (UI).
    public func radarProgress(of e: Int32) -> Double {
        guard let r = radars.first(where: { $0.entity == e }),
              let rp = world.db.entities[Int(world.entities[e].proto)].radar else { return 0 }
        return min(1, r.energy / rp.energyPerSector)
    }

    public func update() {
        let power = world.power!
        for i in electric.indices { power.request(electric[i], joules: usage[i]) }
        guard !radars.isEmpty else { return }
        let tick = world.tick
        for i in radars.indices {
            let e = radars[i].entity
            let p = world.db.entities[Int(world.entities[e].proto)]
            guard let rp = p.radar else { continue }
            let sigma = power.satisfaction(of: e)
            guard sigma > 0 else { continue }
            radars[i].energy += sigma * (p.energyUsage ?? 0) / 60
            let center = world.entities[e].origin.chunk
            if tick % 120 == 0 { world.chartArea(around: center, radius: Int32(rp.nearbyChunkRadius)) }
            if radars[i].energy >= rp.energyPerSector {
                radars[i].energy -= rp.energyPerSector
                let spiral = spiral(radius: Int32(rp.scanChunkRadius), skip: Int32(rp.nearbyChunkRadius))
                guard !spiral.isEmpty else { continue }
                // next uncharted chunk in the spiral (wraps around once everything is charted)
                var tries = 0
                while tries < spiral.count {
                    let off = spiral[radars[i].scanIndex % spiral.count]
                    radars[i].scanIndex = (radars[i].scanIndex + 1) % spiral.count
                    tries += 1
                    let c = ChunkPos(center.x + off.x, center.y + off.y)
                    if world.surface.chunk(c) != nil && world.chart(c) { break }
                }
            }
        }
    }

    private func spiral(radius: Int32, skip: Int32) -> [ChunkPos] {
        if let s = spiralCache[radius &* 100 &+ skip] { return s }
        var out: [ChunkPos] = []
        var r = skip + 1
        while r <= radius {
            for x in -r...r { out.append(ChunkPos(x, -r)) }
            for y in (-r + 1)...r { out.append(ChunkPos(r, y)) }
            for x in stride(from: r - 1, through: -r, by: -1) { out.append(ChunkPos(x, r)) }
            for y in stride(from: r - 1, through: -r + 1, by: -1) { out.append(ChunkPos(-r, y)) }
            r += 1
        }
        spiralCache[radius &* 100 &+ skip] = out
        return out
    }

    public func serialize(to w: inout BinaryWriter) {
        w.write(UInt8(2))
        w.writeVarInt(radars.count)
        for r in radars { w.write(r.entity); w.write(r.energy); w.write(Int64(r.scanIndex)) }
    }
    public func deserialize(from r: inout BinaryReader) throws {
        let v = try r.read(UInt8.self)
        electric = []; usage = []; radars = []
        if v >= 2 {
            let n = try r.readVarInt()
            for _ in 0..<n {
                radars.append(Radar(entity: try r.read(Int32.self), energy: try r.readDouble(), scanIndex: Int(try r.read(Int64.self))))
            }
        }
    }
    public func didLoad() {
        let saved = radars
        radars = []
        world.entities.forEachLive { e, rec in
            guard world.system(for: rec.kind) === self, !rec.flags.contains(.ghost) else { return }
            let p = world.db.entities[Int(rec.proto)]
            if p.energySource?.type == "electric" {
                electric.append(e)
                usage.append(((p.energyUsage ?? 0) + (p.energySource?.drain ?? 0)) / 60)
            }
            if p.radar != nil { radars.append(saved.first { $0.entity == e } ?? Radar(entity: e)) }
        }
    }
}
