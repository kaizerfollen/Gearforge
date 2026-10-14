// Gearforge — FactoryCore
// Entity table. Entities are rows in a dense array; per-kind state lives in the owning system's component arrays
// (struct-of-arrays style). EntityRecord.component is the index into the owning system's storage; systems that
// swap-remove components MUST update the moved entity's `component` field.
// Owner: Lead. Additive changes only (coordinate via the lead).

/// Stable handle for UI/renderer references. `index` is reused after removal; `generation` detects staleness.
public struct EntityHandle: Hashable, Codable, Sendable {
    public var index: Int32
    public var generation: UInt32
    public init(index: Int32, generation: UInt32) { self.index = index; self.generation = generation }
}

public struct EntityFlags: OptionSet, Sendable {
    public let rawValue: UInt16
    public init(rawValue: UInt16) { self.rawValue = rawValue }
    /// Placed by the player (vs natural trees/rocks).
    public static let playerBuilt = EntityFlags(rawValue: 1 << 0)
    /// Ghost (planned building, not yet constructed). Ghosts occupy tiles but are not simulated.
    public static let ghost = EntityFlags(rawValue: 1 << 1)
    /// Marked for deconstruction.
    public static let toDeconstruct = EntityFlags(rawValue: 1 << 2)
}

public struct EntityRecord {
    /// Prototype index, or -1 when the slot is free.
    public var proto: Int32
    public var kind: EntityKind
    /// Top-left tile of the footprint.
    public var origin: TilePos
    /// Rotated footprint size.
    public var w: Int16
    public var h: Int16
    public var direction: Direction
    public var flags: EntityFlags
    /// Index into the owning system's component storage (-1 = none).
    public var component: Int32
    /// Index into PowerSystem endpoint storage (-1 = not electric).
    public var powerSlot: Int32
    /// Index into FluidSystem endpoint storage (-1 = no fluid boxes).
    public var fluidSlot: Int32
    public var generation: UInt32
    public var health: Float

    @inlinable public var isAlive: Bool { proto >= 0 }
    @inlinable public var rect: TileRect { TileRect(x: origin.x, y: origin.y, w: Int32(w), h: Int32(h)) }
    @inlinable public var center: Vec2 { Vec2(Double(origin.x) + Double(w) / 2, Double(origin.y) + Double(h) / 2) }
}

public final class EntityStore {
    public private(set) var records: [EntityRecord] = []
    private var freeList: [Int32] = []
    public private(set) var liveCount: Int = 0

    public init() { records.reserveCapacity(4096) }

    @inlinable public subscript(_ i: Int32) -> EntityRecord {
        get { records[Int(i)] }
    }

    public func update(_ i: Int32, _ body: (inout EntityRecord) -> Void) { body(&records[Int(i)]) }
    public func setComponent(_ i: Int32, _ c: Int32) { records[Int(i)].component = c }
    public func setPowerSlot(_ i: Int32, _ c: Int32) { records[Int(i)].powerSlot = c }
    public func setFluidSlot(_ i: Int32, _ c: Int32) { records[Int(i)].fluidSlot = c }

    public func allocate(proto: Int, kind: EntityKind, origin: TilePos, w: Int, h: Int, direction: Direction,
                         flags: EntityFlags, health: Float) -> Int32 {
        let rec = EntityRecord(proto: Int32(proto), kind: kind, origin: origin, w: Int16(w), h: Int16(h),
                               direction: direction, flags: flags, component: -1, powerSlot: -1, fluidSlot: -1,
                               generation: 0, health: health)
        liveCount += 1
        if let i = freeList.popLast() {
            let gen = records[Int(i)].generation &+ 1
            records[Int(i)] = rec
            records[Int(i)].generation = gen
            return i
        }
        records.append(rec)
        return Int32(records.count - 1)
    }

    public func free(_ i: Int32) {
        records[Int(i)].proto = -1
        records[Int(i)].component = -1
        records[Int(i)].powerSlot = -1
        records[Int(i)].fluidSlot = -1
        freeList.append(i)
        liveCount -= 1
    }

    /// True when `i` indexes a live entity (safe to subscript). Commands validate ids with this.
    @inlinable public func isLive(_ i: Int32) -> Bool { i >= 0 && Int(i) < records.count && records[Int(i)].isAlive }

    public func handle(_ i: Int32) -> EntityHandle { EntityHandle(index: i, generation: records[Int(i)].generation) }

    /// Resolve a handle; nil if the entity was removed.
    public func resolve(_ h: EntityHandle) -> Int32? {
        guard h.index >= 0, Int(h.index) < records.count else { return nil }
        let r = records[Int(h.index)]
        return r.isAlive && r.generation == h.generation ? h.index : nil
    }

    /// Iterate live entities in creation-slot order (deterministic).
    public func forEachLive(_ body: (Int32, EntityRecord) -> Void) {
        for i in 0..<records.count where records[i].proto >= 0 { body(Int32(i), records[i]) }
    }

    // MARK: Persistence support

    /// Raw restore (save loading). Rebuilds the free list.
    public func restore(records: [EntityRecord]) {
        self.records = records
        freeList = []
        liveCount = 0
        for i in stride(from: records.count - 1, through: 0, by: -1) {
            if records[i].proto < 0 { freeList.append(Int32(i)) } else { liveCount += 1 }
        }
    }
}
