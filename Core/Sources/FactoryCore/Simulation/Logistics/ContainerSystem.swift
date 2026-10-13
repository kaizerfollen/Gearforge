// Gearforge — FactoryCore
// Chests (wooden/iron/steel; logistic chests later). Owner: Logistics engineer.

public final class ContainerSystem: EntitySystem, ItemEndpoint {
    public unowned let world: World
    public init(world: World) { self.world = world }

    private var invs: [Inventory] = []
    private var owner: [Int32] = []
    private var free: [Int32] = []

    @inline(__always) private func comp(_ e: Int32) -> Int? {
        let c = world.entities[e].component
        return c >= 0 && Int(c) < invs.count && owner[Int(c)] == e ? Int(c) : nil
    }

    public func inventory(of e: Int32) -> Inventory? {
        guard let c = comp(e) else { return nil }
        return invs[c]
    }

    /// Direct mutation for player UI transfers.
    public func withInventory<R>(_ e: Int32, _ body: (inout Inventory) -> R) -> R? {
        guard let c = comp(e) else { return nil }
        return body(&invs[c])
    }

    /// Chest limit (bar): number of usable slots for automated insertion, nil = unlimited.
    public func setBar(_ e: Int32, _ bar: Int?) {
        guard let c = comp(e) else { return }
        invs[c].bar = bar.map { max(0, min($0, invs[c].size)) }
    }
    public func bar(of e: Int32) -> Int? { comp(e).flatMap { invs[$0].bar } }

    // MARK: EntitySystem

    public func entityAdded(_ e: Int32) {
        let slots = world.db.entities[Int(world.entities[e].proto)].container?.slots ?? 16
        let inv = Inventory(size: slots)
        let c: Int32
        if let f = free.popLast() { c = f; invs[Int(f)] = inv; owner[Int(f)] = e }
        else { c = Int32(invs.count); invs.append(inv); owner.append(e) }
        world.entities.setComponent(e, c)
    }

    public func entityRemoved(_ e: Int32) {
        guard let c = comp(e) else { return }
        invs[c] = Inventory(size: 0)
        owner[c] = -1
        free.append(Int32(c))
        world.entities.setComponent(e, -1)
    }

    public func takeContents(_ e: Int32) -> [ItemStack] {
        guard let c = comp(e) else { return [] }
        let out = invs[c].contents().map { ItemStack(item: $0.item, count: $0.count) }
        let size = invs[c].size
        let bar = invs[c].bar
        invs[c] = Inventory(size: size)
        invs[c].bar = bar
        return out
    }

    public func update() {}

    public func serialize(to w: inout BinaryWriter) {
        w.write(UInt8(1))
        w.writeVarInt(invs.count)
        for i in invs.indices {
            w.write(owner[i])
            invs[i].serialize(to: &w)
        }
    }

    public func deserialize(from r: inout BinaryReader) throws {
        _ = try r.read(UInt8.self)
        let n = try r.readVarInt()
        invs = []; owner = []; free = []
        invs.reserveCapacity(n)
        for i in 0..<n {
            let o = try r.read(Int32.self)
            owner.append(o)
            invs.append(try Inventory(from: &r))
            if o < 0 { free.append(Int32(i)) }
        }
    }

    // MARK: ItemEndpoint

    public func acceptCount(_ e: Int32, item: Int, count: Int, source: ItemTransferSource) -> Int {
        guard let c = comp(e) else { return 0 }
        return invs[c].canInsert(item: item, count: count, stackSize: world.stackSize(item), automated: source != .player)
    }

    public func insert(_ e: Int32, item: Int, count: Int, source: ItemTransferSource) -> Int {
        guard let c = comp(e) else { return 0 }
        return invs[c].insert(item: item, count: count, stackSize: world.stackSize(item), automated: source != .player)
    }

    public func peekExtract(_ e: Int32, source: ItemTransferSource, filter: (Int) -> Bool) -> ItemStack? {
        guard let c = comp(e) else { return nil }
        for s in invs[c].slots where !s.isEmpty && filter(Int(s.item)) {
            return ItemStack(item: s.item, count: Int32(invs[c].count(of: Int(s.item))))
        }
        return nil
    }

    public func extract(_ e: Int32, item: Int, count: Int, source: ItemTransferSource) -> Int {
        guard let c = comp(e) else { return 0 }
        return invs[c].remove(item: item, count: count)
    }
}
