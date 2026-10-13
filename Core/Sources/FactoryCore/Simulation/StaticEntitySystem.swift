// Gearforge — FactoryCore
// Entities with little or no simulation: trees, rocks, walls, gates, radar (charting), lamps, turrets (inert in MVP),
// and "other" later-phase entities. Owner: Gameplay engineer.
// Electric statics (lamps, radar) draw their working power every tick so they show up in the power graph.

public final class StaticEntitySystem: EntitySystem {
    public unowned let world: World
    public init(world: World) { self.world = world }

    private var electric: [Int32] = []
    private var usage: [Double] = []

    public func entityAdded(_ e: Int32) {
        let p = world.db.entities[Int(world.entities[e].proto)]
        if p.energySource?.type == "electric" {
            electric.append(e)
            usage.append(((p.energyUsage ?? 0) + (p.energySource?.drain ?? 0)) / 60)
        }
    }

    public func entityRemoved(_ e: Int32) {
        if let i = electric.firstIndex(of: e) { electric.remove(at: i); usage.remove(at: i) }
    }

    /// Lamp is lit at night when powered.
    public func isLampOn(_ e: Int32) -> Bool {
        world.daylight < 0.5 && world.power.satisfaction(of: e) > 0
    }

    public func update() {
        let power = world.power!
        for i in electric.indices { power.request(electric[i], joules: usage[i]) }
    }

    public func serialize(to w: inout BinaryWriter) { w.write(UInt8(1)) }
    public func deserialize(from r: inout BinaryReader) throws {
        _ = try r.read(UInt8.self)
        electric = []; usage = []
    }
    public func didLoad() {
        world.entities.forEachLive { e, rec in
            guard world.system(for: rec.kind) === self, !rec.flags.contains(.ghost) else { return }
            entityAdded(e)
        }
    }
}
