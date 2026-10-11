// Gearforge — FactoryCore
// Force research state: researched techs, levels of infinite techs, current research + queue, unlocked recipes,
// bonuses (World.bonuses). Owner: Production engineer. STUB.

public final class ResearchManager {
    public unowned let world: World
    public init(world: World) { self.world = world }
    public func setUp() {}

    public func isResearched(_ t: Int) -> Bool { false }
    public func isRecipeUnlocked(_ r: Int) -> Bool { world.db.recipes[r].enabledAtStart }
    /// Technologies whose prerequisites are all researched and that are not yet researched.
    public func isAvailable(_ t: Int) -> Bool { false }
    public var current: Int { -1 }
    public var queue: [Int] { [] }
    /// Progress 0...1 of a technology (current level for infinite techs).
    public func progress(of t: Int) -> Double { 0 }
    /// Units required for the current level (applies tech price multiplier).
    public func unitCount(of t: Int) -> Int { 0 }
    public func level(of t: Int) -> Int { 0 }
    public func setCurrent(_ t: Int) {}
    public func enqueue(_ t: Int) {}
    public func dequeue(_ t: Int) {}
    /// Instantly researches a tech (scenarios / cheats) and applies its effects.
    public func forceResearch(_ t: Int) {}
    /// Called by labs: adds research progress in units to the current tech.
    public func addProgress(units: Double) {}

    public func update() {}
    public func serialize(to w: inout BinaryWriter) {}
    public func deserialize(from r: inout BinaryReader) throws {}
}
