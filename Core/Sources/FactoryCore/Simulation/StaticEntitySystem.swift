// Gearforge — FactoryCore
// Entities with little or no simulation: trees, rocks, walls, gates, radar (charting), lamps, turrets (inert in MVP),
// and "other" later-phase entities. Owner: Gameplay engineer.

public final class StaticEntitySystem: EntitySystem {
    public unowned let world: World
    public init(world: World) { self.world = world }

    public func entityAdded(_ e: Int32) {}
    public func entityRemoved(_ e: Int32) {}
    public func update() {}
    public func serialize(to w: inout BinaryWriter) {}
    public func deserialize(from r: inout BinaryReader) throws {}
}
