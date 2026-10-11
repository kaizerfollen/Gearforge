// Gearforge — FactoryCore
// Burner energy source shared by burner drills, stone/steel furnaces, burner inserters and boilers.
// Owner: Energy engineer (may extend; keep the API used by other systems stable).

public struct BurnerEnergy: Equatable, Sendable {
    /// Fuel slots.
    public var fuel: Inventory
    /// Energy left from the fuel item currently burning (J).
    public var remaining: Double = 0
    /// Item currently burning (for UI flame / burnt result), -1 if none.
    public var burningItem: Int32 = -1
    public var effectivity: Double = 1

    public init(slots: Int, effectivity: Double = 1) {
        fuel = Inventory(size: slots)
        self.effectivity = effectivity
    }

    public var hasEnergy: Bool { remaining > 0 || !fuel.isEmpty }

    /// Draws up to `joules`. Consumes fuel items as needed. Returns the fraction (0...1) of the request satisfied.
    public mutating func draw(_ joules: Double, db: PrototypeDB) -> Double {
        if joules <= 0 { return 1 }
        var need = joules
        while need > 0 {
            if remaining >= need { remaining -= need; return 1 }
            need -= remaining
            remaining = 0
            guard let s = fuel.firstStack(), let fv = db.items[Int(s.item)].fuelValue, fv > 0 else {
                burningItem = -1
                return 1 - need / joules
            }
            fuel.remove(item: Int(s.item), count: 1)
            remaining = fv * effectivity
            burningItem = s.item
        }
        return 1
    }

    /// Whether `item` is a valid fuel for this burner (chemical fuels).
    public static func isFuel(_ item: Int, db: PrototypeDB, categories: [String] = ["chemical"]) -> Bool {
        let p = db.items[item]
        guard let fv = p.fuelValue, fv > 0, let c = p.fuelCategory else { return false }
        return categories.contains(c)
    }

    public func serialize(to w: inout BinaryWriter) {
        fuel.serialize(to: &w); w.write(remaining); w.write(burningItem); w.write(effectivity)
    }
    public init(from r: inout BinaryReader) throws {
        fuel = try Inventory(from: &r); remaining = try r.readDouble(); burningItem = try r.read(Int32.self)
        effectivity = try r.readDouble()
    }
}
