// Gearforge — FactoryCore
// Mining drills (burner, electric) and pumpjacks; resource depletion; output to belt/entity/ground.
// Owner: Production engineer. STUB.

public final class MiningSystem: EntitySystem, ItemEndpoint {
    public unowned let world: World
    public init(world: World) { self.world = world }

    public func progress(of e: Int32) -> Double { 0 }
    public func status(of e: Int32) -> EntityStatus { .idle }
    public func isWorking(_ e: Int32) -> Bool { false }
    public func fuel(of e: Int32) -> BurnerEnergy? { nil }
    public func modules(of e: Int32) -> Inventory? { nil }
    public func insertModule(_ e: Int32, item: Int) -> Bool { false }
    public func removeModule(_ e: Int32, slot: Int) -> ItemStack? { nil }
    /// Remaining resource amount in the drill's area (UI).
    public func remainingResources(of e: Int32) -> Int { 0 }

    /// Placement helper: does the drill's mining area at this position contain a resource it can mine?
    public func hasMinableResource(proto: Int, origin: TilePos, direction: Direction) -> Bool { true }

    public func entityAdded(_ e: Int32) {}
    public func entityRemoved(_ e: Int32) {}
    public func update() {}
    public func serialize(to w: inout BinaryWriter) {}
    public func deserialize(from r: inout BinaryReader) throws {}

    // ItemEndpoint: burner drill fuel slot only
    public func acceptCount(_ e: Int32, item: Int, count: Int, source: ItemTransferSource) -> Int { 0 }
    public func insert(_ e: Int32, item: Int, count: Int, source: ItemTransferSource) -> Int { 0 }
    public func peekExtract(_ e: Int32, source: ItemTransferSource, filter: (Int) -> Bool) -> ItemStack? { nil }
    public func extract(_ e: Int32, item: Int, count: Int, source: ItemTransferSource) -> Int { 0 }
}
