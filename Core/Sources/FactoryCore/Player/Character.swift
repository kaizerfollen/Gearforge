// Gearforge — FactoryCore
// The Engineer: position/movement, inventory (80 + bonus slots), handcrafting queue with chain crafting, hand mining,
// reach checks, quickbar. Owner: Gameplay engineer. STUB.

public final class Character {
    public unowned let world: World
    public init(world: World) { self.world = world }
    public func setUp() {}

    public var position: Vec2 = .zero
    public var inventory = Inventory(size: 80)
    /// Movement input set by the UI each frame: unit vector (or zero). Applied in update() at running speed.
    public var moveInput: Vec2 = .zero

    public func update() {}
    public func serialize(to w: inout BinaryWriter) {}
    public func deserialize(from r: inout BinaryReader) throws {}
}
