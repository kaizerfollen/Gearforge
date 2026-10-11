// Gearforge — FactoryCore
// Crafting machines: assemblers 1-3, chemical plant, oil refinery, centrifuge, furnaces (auto recipe), rocket silo.
// Owner: Production engineer. STUB — replace the bodies; keep the public API.

public final class CraftingSystem: EntitySystem, ItemEndpoint {
    public unowned let world: World
    public init(world: World) { self.world = world }

    // MARK: API used by UI / commands
    /// Current recipe (or -1).
    public func recipe(of e: Int32) -> Int { -1 }
    /// Sets the recipe; returns items that must be given back to the player (ingredients/results/prod modules).
    public func setRecipe(_ e: Int32, _ recipe: Int) -> [ItemStack] { [] }
    public func progress(of e: Int32) -> Double { 0 }
    public func productivityBar(of e: Int32) -> Double { 0 }
    public func status(of e: Int32) -> EntityStatus { .idle }
    public func isWorking(_ e: Int32) -> Bool { false }
    public func inputSlots(of e: Int32) -> [ItemStack] { [] }
    public func outputSlots(of e: Int32) -> [ItemStack] { [] }
    public func fuel(of e: Int32) -> BurnerEnergy? { nil }
    public func modules(of e: Int32) -> Inventory? { nil }
    /// Player inserts/removes a module (validates allowed effects & recipe productivity whitelist).
    public func insertModule(_ e: Int32, item: Int) -> Bool { false }
    public func removeModule(_ e: Int32, slot: Int) -> ItemStack? { nil }
    /// Rocket silo: parts done, rocket ready, launch.
    public func rocketParts(of e: Int32) -> Int { 0 }
    public func launchRocket(_ e: Int32) -> Bool { false }

    // MARK: EntitySystem
    public func entityAdded(_ e: Int32) {}
    public func entityRemoved(_ e: Int32) {}
    public func update() {}
    public func serialize(to w: inout BinaryWriter) {}
    public func deserialize(from r: inout BinaryReader) throws {}

    // MARK: ItemEndpoint
    public func acceptCount(_ e: Int32, item: Int, count: Int, source: ItemTransferSource) -> Int { 0 }
    public func insert(_ e: Int32, item: Int, count: Int, source: ItemTransferSource) -> Int { 0 }
    public func peekExtract(_ e: Int32, source: ItemTransferSource, filter: (Int) -> Bool) -> ItemStack? { nil }
    public func extract(_ e: Int32, item: Int, count: Int, source: ItemTransferSource) -> Int { 0 }
}
