// Gearforge — FactoryCore
// Transport belts, underground belts and splitters simulated as transport lines (05_mechanics §1).
// Owner: Logistics engineer. STUB — replace the bodies; keep the public API.

public final class BeltSystem: EntitySystem {
    public unowned let world: World
    public init(world: World) { self.world = world }

    // MARK: API for inserters / drills / player
    /// Lane 0 = left, 1 = right (relative to belt direction).
    /// Tries to put an item on belt entity `e` at lane/position (position in 1/256 tile along the tile, 0...255).
    /// Returns true if inserted (needs a gap of 64 positions).
    public func insertItem(_ e: Int32, lane: Int, position: Int, item: Int) -> Bool { false }
    /// Can an item be inserted there right now?
    public func canInsert(_ e: Int32, lane: Int, position: Int) -> Bool { false }
    /// Picks up one item from tile `e` (prefers `preferredLane`) matching `filter`. Returns the item or -1.
    public func pickItem(_ e: Int32, preferredLane: Int, filter: (Int) -> Bool) -> Int { -1 }
    /// Lane an inserter dropping from direction `from` should use (far lane rule, 05 §1.6).
    public func dropLane(_ e: Int32, inserterDirection: Direction) -> Int { 0 }

    // MARK: Rendering API
    /// Calls `body(item, x, y)` for every belt item whose world position lies in `rect` (tile units, item centre).
    public func forEachItem(in rect: TileRect, _ body: (Int, Double, Double) -> Void) {}
    /// Animation phase offset for belt textures (positions moved since start, per tier speed).
    public func animationPhase(speed: Int) -> Int { Int(world.tick &* UInt64(speed) % 256) }
    /// Shape for rendering: straight / curve-left / curve-right; underground in/out; splitter.
    public func shape(of e: Int32) -> BeltShape { .straight }
    public func items(on e: Int32) -> [ItemStack] { [] }

    // MARK: Splitter settings (UI)
    public func splitterSettings(_ e: Int32) -> SplitterSettings { SplitterSettings() }
    public func setSplitterSettings(_ e: Int32, _ s: SplitterSettings) {}

    public func entityAdded(_ e: Int32) {}
    public func entityRemoved(_ e: Int32) {}
    public func update() {}
    public func serialize(to w: inout BinaryWriter) {}
    public func deserialize(from r: inout BinaryReader) throws {}
}

public enum BeltShape: UInt8, Sendable { case straight, curveLeft, curveRight, undergroundEntrance, undergroundExit, splitter }

public struct SplitterSettings: Equatable, Sendable {
    /// -1 none, 0 left, 1 right
    public var inputPriority: Int8 = -1
    public var outputPriority: Int8 = -1
    /// Filter item (requires outputPriority set), -1 none.
    public var filter: Int32 = -1
    public init() {}
}
