// Gearforge — FactoryCore
// Beacons and module effect aggregation (05_mechanics §10).
// Owner: Production engineer. STUB.

public final class BeaconSystem: EntitySystem {
    public unowned let world: World
    public init(world: World) { self.world = world }

    /// Sum of beacon effects (already × distribution effectivity) applying to entity `e`.
    public func beaconEffects(on e: Int32) -> ModuleEffects { ModuleEffects() }
    public func modules(of e: Int32) -> Inventory? { nil }
    public func insertModule(_ e: Int32, item: Int) -> Bool { false }
    public func removeModule(_ e: Int32, slot: Int) -> ItemStack? { nil }

    public func entityAdded(_ e: Int32) {}
    public func entityRemoved(_ e: Int32) {}
    public func update() {}
    public func serialize(to w: inout BinaryWriter) {}
    public func deserialize(from r: inout BinaryReader) throws {}
}
