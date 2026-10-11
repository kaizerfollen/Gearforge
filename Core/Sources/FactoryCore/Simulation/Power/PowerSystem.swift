// Gearforge — FactoryCore
// Electric networks: poles (wiring + supply areas), generators (steam engine/turbine), solar, accumulators, boilers.
// Owner: Energy engineer. STUB — replace the bodies; keep the public API (other teams call it).

public final class PowerSystem: EntitySystem, ItemEndpoint {
    public unowned let world: World
    public init(world: World) { self.world = world }

    // MARK: API used by every electric consumer (crafting, mining, labs, inserters, beacons, pumps, radar...)

    /// Registers `e` as an electric endpoint if its prototype has an electric energy source and it is not a pole.
    /// Called by World.createEntity for every non-ghost entity. Sets record.powerSlot.
    public func registerEndpointIfNeeded(_ e: Int32) {}
    public func unregisterEndpointIfNeeded(_ e: Int32) {}

    /// Satisfaction (0...1) of the network the entity is connected to, solved at the start of this tick.
    /// 0 when unconnected. Consumers multiply their speed by this.
    public func satisfaction(of e: Int32) -> Double { 1 }

    /// Consumer request for NEXT tick in joules (drain + working usage × consumption multiplier) / 60.
    public func request(_ e: Int32, joules: Double) {}

    /// Network id for UI (power graph, satisfaction in HUD) or -1.
    public func networkID(of e: Int32) -> Int { -1 }

    // MARK: EntitySystem
    public func entityAdded(_ e: Int32) {}
    public func entityRemoved(_ e: Int32) {}
    public func update() {}
    public func serialize(to w: inout BinaryWriter) {}
    public func deserialize(from r: inout BinaryReader) throws {}

    // MARK: ItemEndpoint (boiler fuel)
    public func acceptCount(_ e: Int32, item: Int, count: Int, source: ItemTransferSource) -> Int { 0 }
    public func insert(_ e: Int32, item: Int, count: Int, source: ItemTransferSource) -> Int { 0 }
    public func peekExtract(_ e: Int32, source: ItemTransferSource, filter: (Int) -> Bool) -> ItemStack? { nil }
    public func extract(_ e: Int32, item: Int, count: Int, source: ItemTransferSource) -> Int { 0 }
}
