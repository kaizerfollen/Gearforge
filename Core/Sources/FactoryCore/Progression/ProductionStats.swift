// Gearforge — FactoryCore
// Production/consumption statistics per item & fluid over 1m / 10m / 1h / 10h windows, plus lifetime totals,
// and power production/consumption. Owner: Progression engineer. STUB.

public final class ProductionStats {
    public unowned let world: World
    public init(world: World) { self.world = world }
    public func setUp() {}

    /// Called by machines/handcrafting/mining when items are produced (crafted, mined, smelted).
    public func produced(item: Int, count: Int) {}
    /// Called when items are consumed as ingredients (crafting start, lab unit start, rocket part).
    public func consumed(item: Int, count: Int) {}
    public func producedFluid(_ fluid: Int, amount: Double) {}
    public func consumedFluid(_ fluid: Int, amount: Double) {}
    public func totalProduced(item: Int) -> Int { 0 }

    public func update() {}
    public func serialize(to w: inout BinaryWriter) {}
    public func deserialize(from r: inout BinaryReader) throws {}
}
