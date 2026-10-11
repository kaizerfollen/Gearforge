// Gearforge — FactoryCore
// Chests (wooden/iron/steel; logistic chests later). Owner: Logistics engineer. STUB.

public final class ContainerSystem: EntitySystem, ItemEndpoint {
    public unowned let world: World
    public init(world: World) { self.world = world }

    public func inventory(of e: Int32) -> Inventory? { nil }
    /// Direct mutation for player UI transfers.
    public func withInventory<R>(_ e: Int32, _ body: (inout Inventory) -> R) -> R? { nil }

    public func entityAdded(_ e: Int32) {}
    public func entityRemoved(_ e: Int32) {}
    public func update() {}
    public func serialize(to w: inout BinaryWriter) {}
    public func deserialize(from r: inout BinaryReader) throws {}

    public func acceptCount(_ e: Int32, item: Int, count: Int, source: ItemTransferSource) -> Int { 0 }
    public func insert(_ e: Int32, item: Int, count: Int, source: ItemTransferSource) -> Int { 0 }
    public func peekExtract(_ e: Int32, source: ItemTransferSource, filter: (Int) -> Bool) -> ItemStack? { nil }
    public func extract(_ e: Int32, item: Int, count: Int, source: ItemTransferSource) -> Int { 0 }
}
