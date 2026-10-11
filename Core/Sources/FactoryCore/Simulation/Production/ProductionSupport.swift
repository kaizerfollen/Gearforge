// Gearforge — FactoryCore
// Shared helpers for the production systems (crafting, mining, labs, beacons): module rules, fluid access seam,
// insertion-limit formulas and binary (de)serialization of struct-of-arrays component storage.
// Owner: Production engineer.

// MARK: - Module effects

/// Bitmask of module effects an entity accepts (from `EntityProto.allowedEffects`).
/// 1.1 rule: crafting machines without `allowed_effects` accept no effects — this is why assembler 1 and the burner
/// furnaces can neither hold modules nor be affected by beacons.
public struct EffectMask: OptionSet, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    public static let speed = EffectMask(rawValue: 1 << 0)
    public static let productivity = EffectMask(rawValue: 1 << 1)
    public static let consumption = EffectMask(rawValue: 1 << 2)
    public static let pollution = EffectMask(rawValue: 1 << 3)
    public static let all: EffectMask = [.speed, .productivity, .consumption, .pollution]

    public init(_ names: [String]?) {
        var m: EffectMask = []
        for n in names ?? [] {
            switch n {
            case "speed": m.insert(.speed)
            case "productivity": m.insert(.productivity)
            case "consumption": m.insert(.consumption)
            case "pollution": m.insert(.pollution)
            default: break
            }
        }
        self = m
    }
}

public enum ModuleRules {
    /// Zeroes the components of `e` that `mask` does not allow.
    @inlinable public static func filter(_ e: ModuleEffects, _ mask: EffectMask) -> ModuleEffects {
        ModuleEffects(speed: mask.contains(.speed) ? e.speed : 0,
                      productivity: mask.contains(.productivity) ? e.productivity : 0,
                      consumption: mask.contains(.consumption) ? e.consumption : 0,
                      pollution: mask.contains(.pollution) ? e.pollution : 0)
    }

    /// Whether module item `item` may be placed in an entity accepting `mask` (every non-zero effect must be allowed).
    public static func moduleAllowed(_ item: Int, mask: EffectMask, db: PrototypeDB) -> Bool {
        guard item >= 0, item < db.items.count else { return false }
        let p = db.items[item]
        guard p.kind == .module, let m = p.module else { return false }
        if m.speed != 0 && !mask.contains(.speed) { return false }
        if m.productivity != 0 && !mask.contains(.productivity) { return false }
        if m.consumption != 0 && !mask.contains(.consumption) { return false }
        if m.pollution != 0 && !mask.contains(.pollution) { return false }
        return true
    }

    /// Whether `item` is a module with a productivity effect.
    public static func isProductivityModule(_ item: Int, db: PrototypeDB) -> Bool {
        guard item >= 0, item < db.items.count, let m = db.items[item].module else { return false }
        return m.productivity != 0
    }

    /// Sum of the effects of the modules in a module inventory.
    public static func sum(_ inv: Inventory, db: PrototypeDB) -> ModuleEffects {
        var e = ModuleEffects()
        for s in inv.slots where !s.isEmpty {
            if let m = db.items[Int(s.item)].module { e = e + m * Double(s.count) }
        }
        return e
    }

    /// Puts one module into the first free slot. Returns false if the inventory is full.
    static func insert(_ item: Int, into inv: inout Inventory) -> Bool {
        for i in 0..<inv.slots.count where inv.slots[i].isEmpty {
            inv.slots[i] = ItemStack(item: item, count: 1)
            return true
        }
        return false
    }

    /// Removes the module in `slot`.
    static func remove(slot: Int, from inv: inout Inventory) -> ItemStack? {
        guard slot >= 0, slot < inv.slots.count, !inv.slots[slot].isEmpty else { return nil }
        let s = inv.slots[slot]
        inv.slots[slot] = .empty
        return s
    }

    /// Removes and returns every productivity module (recipe changed to a non-whitelisted one).
    static func ejectProductivity(from inv: inout Inventory, db: PrototypeDB) -> [ItemStack] {
        var out: [ItemStack] = []
        for i in 0..<inv.slots.count where !inv.slots[i].isEmpty && isProductivityModule(Int(inv.slots[i].item), db: db) {
            out.append(inv.slots[i])
            inv.slots[i] = .empty
        }
        return out
    }
}

// MARK: - Insertion limits (05_mechanics §2.4)

public enum InsertionLimits {
    /// Seconds of one basic-inserter swing used by the 1.1 auto-insert formula.
    public static let swingSeconds = 1.166
    /// Automated fuel limit for burner entities (boiler, burner drill, stone/steel furnace, burner inserter).
    public static let fuelLimit = 5

    /// Crafts worth of ingredients an automated source may fill: clamp(1 + ceil(1.166 × speed / time), 2, 100).
    @inlinable public static func crafts(effectiveSpeed: Double, recipeTime: Double) -> Int {
        guard recipeTime > 0, effectiveSpeed > 0 else { return 2 }
        let x = (swingSeconds * effectiveSpeed / recipeTime - 1e-9).rounded(.up)
        return min(100, max(2, 1 + Int(min(x, 1000))))
    }

    /// Research units worth of cards an automated source may fill: clamp(1 + ceil(1.166 / unit_time_eff), 2, 100).
    @inlinable public static func labUnits(effectiveUnitTime: Double) -> Int {
        guard effectiveUnitTime > 0 else { return 100 }
        let x = (swingSeconds / effectiveUnitTime - 1e-9).rounded(.up)
        return min(100, max(2, 1 + Int(min(x, 1000))))
    }
}

// MARK: - Fluid access seam

/// The subset of the FluidSystem box API production machines use. Production systems talk to fluids only through
/// this protocol so unit tests can substitute an in-memory fake until the real fluid system is merged.
public protocol ProductionFluidAccess: AnyObject {
    func fluid(_ e: Int32, box: Int) -> Int
    func amount(_ e: Int32, box: Int) -> Double
    func capacity(_ e: Int32, box: Int) -> Double
    @discardableResult func add(_ e: Int32, box: Int, fluid: Int, amount: Double, temperature: Double) -> Double
    @discardableResult func remove(_ e: Int32, box: Int, amount: Double) -> Double
    func setFilter(_ e: Int32, box: Int, fluid: Int)
}

extension FluidSystem: ProductionFluidAccess {}

// MARK: - Burner helpers

enum ProdBurner {
    /// Fuel categories accepted by a burner prototype (default chemical).
    static func categories(_ p: EntityProto) -> [String] { p.energySource?.fuelCategories ?? ["chemical"] }

    static func fuelCount(_ b: BurnerEnergy) -> Int {
        var n = 0
        for s in b.fuel.slots where !s.isEmpty { n += Int(s.count) }
        return n
    }

    /// How many fuel items the burner accepts from `source` (automated sources are limited to 5 items in total).
    static func acceptFuel(_ b: BurnerEnergy, item: Int, count: Int, source: ItemTransferSource, db: PrototypeDB) -> Int {
        let room = b.fuel.canInsert(item: item, count: count, stackSize: db.items[item].stackSize)
        if source == .player { return max(0, room) }
        return max(0, min(room, InsertionLimits.fuelLimit - fuelCount(b)))
    }
}

// MARK: - Struct-of-arrays persistence helpers

enum ProdIO {
    static func write(_ a: [Int32], _ w: inout BinaryWriter) { w.writeVarInt(a.count); for v in a { w.write(v) } }
    static func write(_ a: [UInt8], _ w: inout BinaryWriter) { w.writeVarInt(a.count); w.writeRaw(a) }
    static func write(_ a: [Bool], _ w: inout BinaryWriter) { w.writeVarInt(a.count); for v in a { w.write(v) } }
    static func write(_ a: [Double], _ w: inout BinaryWriter) { w.writeVarInt(a.count); for v in a { w.write(v) } }
    static func write(_ a: [Inventory], _ w: inout BinaryWriter) { w.writeVarInt(a.count); for v in a { v.serialize(to: &w) } }
    static func write(_ a: [BurnerEnergy], _ w: inout BinaryWriter) { w.writeVarInt(a.count); for v in a { v.serialize(to: &w) } }

    static func count(_ r: inout BinaryReader, expect: Int? = nil) throws -> Int {
        let n = try r.readVarInt()
        if let e = expect, e != n { throw BinaryCodingError.invalidValue("array length \(n) != \(e)") }
        if n > r.remaining * 8 + 64 { throw BinaryCodingError.invalidValue("array count \(n) exceeds data") }
        return n
    }
    static func readInt32s(_ r: inout BinaryReader, expect: Int? = nil) throws -> [Int32] {
        let n = try count(&r, expect: expect); var a: [Int32] = []; a.reserveCapacity(n)
        for _ in 0..<n { a.append(try r.read(Int32.self)) }
        return a
    }
    static func readBytes(_ r: inout BinaryReader, expect: Int? = nil) throws -> [UInt8] {
        let n = try count(&r, expect: expect)
        return try r.readRaw(n)
    }
    static func readBools(_ r: inout BinaryReader, expect: Int? = nil) throws -> [Bool] {
        let n = try count(&r, expect: expect); var a: [Bool] = []; a.reserveCapacity(n)
        for _ in 0..<n { a.append(try r.readBool()) }
        return a
    }
    static func readDoubles(_ r: inout BinaryReader, expect: Int? = nil) throws -> [Double] {
        let n = try count(&r, expect: expect); var a: [Double] = []; a.reserveCapacity(n)
        for _ in 0..<n { a.append(try r.readDouble()) }
        return a
    }
    static func readInventories(_ r: inout BinaryReader, expect: Int? = nil) throws -> [Inventory] {
        let n = try count(&r, expect: expect); var a: [Inventory] = []; a.reserveCapacity(n)
        for _ in 0..<n { a.append(try Inventory(from: &r)) }
        return a
    }
    static func readBurners(_ r: inout BinaryReader, expect: Int? = nil) throws -> [BurnerEnergy] {
        let n = try count(&r, expect: expect); var a: [BurnerEnergy] = []; a.reserveCapacity(n)
        for _ in 0..<n { a.append(try BurnerEnergy(from: &r)) }
        return a
    }
    static func checkVersion(_ r: inout BinaryReader, _ v: UInt8) throws {
        let got = try r.read(UInt8.self)
        if got != v { throw BinaryCodingError.unsupportedVersion(Int(got)) }
    }
}

// MARK: - Array helpers

enum ProdArray {
    @inline(__always) static func swapRemove<T>(_ a: inout [T], _ i: Int) {
        let last = a.count - 1
        if i != last { a.swapAt(i, last) }
        a.removeLast()
    }

    /// Swap-remove for a strided block array (component `i` owns `a[i*stride ..< (i+1)*stride]`).
    @inline(__always) static func swapRemoveBlock<T>(_ a: inout [T], _ i: Int, stride: Int) {
        guard stride > 0 else { return }
        let last = a.count / stride - 1
        if i != last {
            for k in 0..<stride { a[i * stride + k] = a[last * stride + k] }
        }
        a.removeLast(stride)
    }

    /// Splits (item, count) into stack-size sized stacks.
    static func stacks(item: Int, count: Int, db: PrototypeDB) -> [ItemStack] {
        guard item >= 0, count > 0 else { return [] }
        let ss = max(1, db.items[item].stackSize)
        var out: [ItemStack] = []
        var n = count
        while n > 0 { let k = min(n, ss); out.append(ItemStack(item: item, count: k)); n -= k }
        return out
    }
}
