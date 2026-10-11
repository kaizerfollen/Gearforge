// Gearforge — FactoryCore
// Item stacks and slot inventories (chests, character, machine buffers).
// Owner: Lead (shared). Additive changes only.

public struct ItemStack: Equatable, Sendable {
    public var item: Int32      // ItemIndex, -1 = empty
    public var count: Int32
    public static let empty = ItemStack(item: -1, count: 0)
    @inlinable public init(item: Int32, count: Int32) { self.item = item; self.count = count }
    @inlinable public init(item: Int, count: Int) { self.item = Int32(item); self.count = Int32(count) }
    @inlinable public var isEmpty: Bool { count <= 0 || item < 0 }
}

/// Fixed-size slot inventory with per-slot stack limits from item prototypes.
/// Value type: embed it in components; mutate in place.
public struct Inventory: Equatable, Sendable {
    public var slots: [ItemStack]
    /// Optional per-slot filters (item index or -1).
    public var filters: [Int32]?
    /// Chest "limit bar": slots at or beyond this index are not usable by automation (inserters). nil = no limit.
    public var bar: Int?

    public init(size: Int) { slots = Array(repeating: .empty, count: size) }

    public var size: Int { slots.count }
    public var isEmpty: Bool { slots.allSatisfy { $0.isEmpty } }

    public func count(of item: Int) -> Int {
        var n = 0
        for s in slots where Int(s.item) == item { n += Int(s.count) }
        return n
    }

    /// Total distinct contents (item -> count), in slot order of first appearance.
    public func contents() -> [(item: Int, count: Int)] {
        var order: [Int] = []
        var counts: [Int: Int] = [:]
        for s in slots where !s.isEmpty {
            if counts[Int(s.item)] == nil { order.append(Int(s.item)) }
            counts[Int(s.item), default: 0] += Int(s.count)
        }
        return order.map { ($0, counts[$0]!) }
    }

    @inline(__always) private func usable(_ i: Int, automated: Bool) -> Bool {
        guard automated, let b = bar else { return true }
        return i < b
    }

    @inline(__always) private func filterAllows(_ i: Int, _ item: Int) -> Bool {
        guard let f = filters else { return true }
        return f[i] < 0 || Int(f[i]) == item
    }

    /// How many of `item` could be inserted (without modifying).
    public func canInsert(item: Int, count: Int, stackSize: Int, automated: Bool = false) -> Int {
        var room = 0
        for i in 0..<slots.count where usable(i, automated: automated) && filterAllows(i, item) {
            let s = slots[i]
            if s.isEmpty { room += stackSize } else if Int(s.item) == item { room += max(0, stackSize - Int(s.count)) }
            if room >= count { return count }
        }
        return room
    }

    /// Inserts up to `count`; returns how many were inserted. Fills existing stacks first, then empty slots.
    @discardableResult
    public mutating func insert(item: Int, count: Int, stackSize: Int, automated: Bool = false) -> Int {
        var left = count
        for i in 0..<slots.count where left > 0 && usable(i, automated: automated) {
            if Int(slots[i].item) == item && slots[i].count > 0 {
                let add = min(left, stackSize - Int(slots[i].count))
                if add > 0 { slots[i].count += Int32(add); left -= add }
            }
        }
        for i in 0..<slots.count where left > 0 && usable(i, automated: automated) && filterAllows(i, item) {
            if slots[i].isEmpty {
                let add = min(left, stackSize)
                slots[i] = ItemStack(item: item, count: add)
                left -= add
            }
        }
        return count - left
    }

    /// Removes up to `count` of `item` (from the last slots first); returns how many were removed.
    @discardableResult
    public mutating func remove(item: Int, count: Int) -> Int {
        var left = count
        var i = slots.count - 1
        while i >= 0 && left > 0 {
            if Int(slots[i].item) == item && slots[i].count > 0 {
                let take = min(left, Int(slots[i].count))
                slots[i].count -= Int32(take)
                left -= take
                if slots[i].count == 0 { slots[i] = .empty }
            }
            i -= 1
        }
        return count - left
    }

    /// First non-empty stack (optionally matching a predicate), for automated extraction.
    public func firstStack(where pred: ((Int) -> Bool)? = nil) -> ItemStack? {
        for s in slots where !s.isEmpty {
            if pred == nil || pred!(Int(s.item)) { return s }
        }
        return nil
    }

    /// Sorts and merges stacks (player "sort" button).
    public mutating func sort(stackSize: (Int) -> Int, order: (Int, Int) -> Bool) {
        let c = contents().sorted { order($0.item, $1.item) }
        let size = slots.count
        slots = Array(repeating: .empty, count: size)
        var i = 0
        for (item, var n) in c {
            let ss = stackSize(item)
            while n > 0 && i < size { let k = min(n, ss); slots[i] = ItemStack(item: item, count: k); n -= k; i += 1 }
        }
    }

    public func serialize(to w: inout BinaryWriter) {
        w.writeVarInt(slots.count)
        for s in slots { w.write(s.item); w.write(s.count) }
        w.write(filters != nil)
        if let f = filters { for v in f { w.write(v) } }
        w.write(Int32(bar ?? -1))
    }

    public init(from r: inout BinaryReader) throws {
        let n = try r.readVarInt()
        var s: [ItemStack] = []
        s.reserveCapacity(n)
        for _ in 0..<n { s.append(ItemStack(item: try r.read(Int32.self), count: try r.read(Int32.self))) }
        slots = s
        if try r.readBool() {
            var f: [Int32] = []
            for _ in 0..<n { f.append(try r.read(Int32.self)) }
            filters = f
        }
        let b = try r.read(Int32.self)
        bar = b < 0 ? nil : Int(b)
    }
}
