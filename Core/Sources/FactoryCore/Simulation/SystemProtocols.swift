// Gearforge — FactoryCore
// Contracts between World and the simulation systems, and between systems.
// Owner: Lead. Changing a protocol requirement needs lead sign-off (other teams code against these).

/// A simulation system that owns the components of one or more entity kinds.
///
/// Lifecycle for an entity of an owned kind:
///  1. World allocates the EntityRecord, writes occupancy, then calls `entityAdded(e)`. The system creates its
///     component and stores its index with `world.entities.setComponent(e, idx)`.
///  2. Every tick `update()` runs (systems run in the fixed order defined in `World.step()`).
///  3. On removal World calls `entityRemoved(e)` BEFORE clearing occupancy and freeing the record. The system must
///     return any items it holds via `world.spill(...)`/caller-provided sink (see `takeContents`) and drop its component.
///     When swap-removing, update the moved entity's component index.
///
/// After any build/remove/rotate, World calls `neighborhoodChanged(_:)` on every system with the affected rect
/// expanded by 1 tile, so systems can refresh cached topology (belt lines, pipe segments, pole wiring, inserter targets).
public protocol EntitySystem: AnyObject {
    /// Called once after World construction (all systems exist) to resolve prototype indices etc.
    func setUp()
    func entityAdded(_ e: Int32)
    func entityRemoved(_ e: Int32)
    /// The entity was rotated in place (record.direction already updated).
    func entityRotated(_ e: Int32)
    func neighborhoodChanged(_ rect: TileRect)
    func update()
    /// Items held by the entity (inventories, belt items, hand contents) — moved to the player when it is picked up.
    /// Called right before `entityRemoved`. The system should clear what it returns.
    func takeContents(_ e: Int32) -> [ItemStack]
    /// Save this system's state. Component arrays must be written such that `deserialize` reproduces the exact
    /// component indices recorded in EntityRecords (simplest: write arrays verbatim).
    func serialize(to w: inout BinaryWriter)
    func deserialize(from r: inout BinaryReader) throws
    /// Called after every system has been deserialized: rebuild derived/cached data (lines, networks, segments).
    func didLoad()
}

public extension EntitySystem {
    func setUp() {}
    func entityRotated(_ e: Int32) {}
    func neighborhoodChanged(_ rect: TileRect) {}
    func takeContents(_ e: Int32) -> [ItemStack] { [] }
    func didLoad() {}
}

/// Who is inserting/extracting. Automated sources respect insertion limits (05_mechanics §2.4) and chest bars.
public enum ItemTransferSource: Sendable {
    case inserter
    case drill
    case player
}

/// Implemented by every system whose entities hold items that inserters, drills and the player can access.
/// World routes calls by EntityKind (see `World.itemEndpoint(for:)`).
public protocol ItemEndpoint: AnyObject {
    /// How many of `item` the entity would accept right now (≤ count). Must not mutate.
    func acceptCount(_ e: Int32, item: Int, count: Int, source: ItemTransferSource) -> Int
    /// Inserts up to `count`; returns the number inserted.
    func insert(_ e: Int32, item: Int, count: Int, source: ItemTransferSource) -> Int
    /// The stack an automated extractor may take next (machines: outputs only), optionally filtered.
    /// Return nil if nothing is available. Must not mutate.
    func peekExtract(_ e: Int32, source: ItemTransferSource, filter: (Int) -> Bool) -> ItemStack?
    /// Removes up to `count` of `item` from the extractable inventories; returns the number removed.
    func extract(_ e: Int32, item: Int, count: Int, source: ItemTransferSource) -> Int
}

/// Implemented by systems that expose a per-entity status for UI/alerts.
public enum EntityStatus: UInt8, Sendable {
    case working, idle, noInput, outputFull, noPower, lowPower, noFuel, noRecipe, noResources, noResearch
    case waitingForSource, waitingForTarget, disabled, noFluid, fluidFull, noModules
}
