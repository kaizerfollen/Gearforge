// Gearforge — FactoryCore
// Fluid boxes and Factorio-2.0-style pipe segments (05_mechanics §7.2): pipes, pipe-to-ground, pumps, offshore
// pumps, storage tanks; plus fluid boxes of machines (assemblers, chem plants, refineries, boilers, engines, drills).
// Owner: Energy engineer. STUB — replace the bodies; keep the public API.

public final class FluidSystem: EntitySystem {
    public unowned let world: World
    public init(world: World) { self.world = world }

    /// Creates fluid boxes for any entity whose prototype has `fluidBoxes` (machines, boilers, engines, pipes...).
    public func registerEndpointIfNeeded(_ e: Int32) {}
    public func unregisterEndpointIfNeeded(_ e: Int32) {}
    public func endpointRotated(_ e: Int32) {}

    // MARK: Fluid box API for machines (box index = index in prototype.fluidBoxes)
    public func boxCount(_ e: Int32) -> Int { 0 }
    /// Fluid index in the box, or -1 if empty.
    public func fluid(_ e: Int32, box: Int) -> Int { -1 }
    public func amount(_ e: Int32, box: Int) -> Double { 0 }
    public func capacity(_ e: Int32, box: Int) -> Double { 0 }
    public func temperature(_ e: Int32, box: Int) -> Double { 15 }
    /// Adds fluid; returns the amount accepted.
    @discardableResult public func add(_ e: Int32, box: Int, fluid: Int, amount: Double, temperature: Double) -> Double { 0 }
    /// Removes fluid; returns the amount removed.
    @discardableResult public func remove(_ e: Int32, box: Int, amount: Double) -> Double { 0 }
    /// Sets the filter (fluid index or -1) of a machine box, e.g. when an assembler recipe changes.
    public func setFilter(_ e: Int32, box: Int, fluid: Int) {}

    // MARK: EntitySystem
    public func entityAdded(_ e: Int32) {}
    public func entityRemoved(_ e: Int32) {}
    public func update() {}
    public func serialize(to w: inout BinaryWriter) {}
    public func deserialize(from r: inout BinaryReader) throws {}
}
