// Gearforge — FactoryCore
// Labs consume research cards to progress the current technology (05_mechanics §9).
// Owner: Production engineer. STUB.

public final class LabSystem: EntitySystem, ItemEndpoint {
    public unowned let world: World
    public init(world: World) { self.world = world }

    public func status(of e: Int32) -> EntityStatus { .idle }
    public func isWorking(_ e: Int32) -> Bool { false }
    public func progress(of e: Int32) -> Double { 0 }
    public func cards(of e: Int32) -> Inventory? { nil }
    public func modules(of e: Int32) -> Inventory? { nil }
    public func insertModule(_ e: Int32, item: Int) -> Bool { false }
    public func removeModule(_ e: Int32, slot: Int) -> ItemStack? { nil }

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
