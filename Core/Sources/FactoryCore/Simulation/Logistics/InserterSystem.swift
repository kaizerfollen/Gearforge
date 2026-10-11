// Gearforge — FactoryCore
// Inserters (burner, basic, long-handed, fast, filter, stack, stack filter) (05_mechanics §2).
// Owner: Logistics engineer. STUB.

public final class InserterSystem: EntitySystem, ItemEndpoint {
    public unowned let world: World
    public init(world: World) { self.world = world }

    /// Hand position (world tile units) for rendering, and held stack.
    public func handPosition(of e: Int32) -> Vec2 { world.entities[e].center }
    public func heldStack(of e: Int32) -> ItemStack { .empty }
    public func status(of e: Int32) -> EntityStatus { .idle }
    public func filters(of e: Int32) -> [Int] { [] }
    public func setFilter(_ e: Int32, slot: Int, item: Int) {}
    public func fuel(of e: Int32) -> BurnerEnergy? { nil }

    public func entityAdded(_ e: Int32) {}
    public func entityRemoved(_ e: Int32) {}
    public func update() {}
    public func serialize(to w: inout BinaryWriter) {}
    public func deserialize(from r: inout BinaryReader) throws {}

    // ItemEndpoint: burner inserter fuel
    public func acceptCount(_ e: Int32, item: Int, count: Int, source: ItemTransferSource) -> Int { 0 }
    public func insert(_ e: Int32, item: Int, count: Int, source: ItemTransferSource) -> Int { 0 }
    public func peekExtract(_ e: Int32, source: ItemTransferSource, filter: (Int) -> Bool) -> ItemStack? { nil }
    public func extract(_ e: Int32, item: Int, count: Int, source: ItemTransferSource) -> Int { 0 }
}
