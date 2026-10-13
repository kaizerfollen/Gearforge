// Gearforge — FactoryCore
// Pollution as a statistic only (GDD §15 / 05 §13: no diffusion map until hostiles exist). Every second the
// emissions of working entities (`energySource.emissionsPerMinute`, scaled by module consumption effect for
// crafting machines) are summed into a rolling one-minute window and a running total. Owner: Progression engineer.

public final class PollutionStats {
    public unowned let world: World
    init(world: World) { self.world = world }

    /// Pollution produced in the last 60 seconds (units per minute).
    public private(set) var perMinute: Double = 0
    /// Total pollution produced since the start.
    public private(set) var total: Double = 0
    /// Per-second samples (ring of 60).
    private var ring = [Double](repeating: 0, count: 60)
    private var head = 0
    /// Last sample split by entity prototype (UI breakdown): proto index → per-minute rate.
    public private(set) var bySource: [Int: Double] = [:]
    private var emissions: [Double] = []

    func setUp() {
        emissions = world.db.entities.map { $0.energySource?.emissionsPerMinute ?? 0 }
    }

    /// Called once per second by World.step.
    func sample() {
        if emissions.isEmpty { setUp() }
        var rate = 0.0
        var by: [Int: Double] = [:]
        world.entities.forEachLive { e, r in
            let em = emissions[Int(r.proto)]
            guard em > 0, !r.flags.contains(.ghost) else { return }
            var working = false
            var mult = 1.0
            switch r.kind {
            case .assemblingMachine, .furnace, .rocketSilo:
                working = world.crafting.isWorking(e)
                if working { mult = world.crafting.effects(of: e).consumption }
            case .miningDrill: working = world.mining.isWorking(e)
            case .boiler: working = world.power.isBoilerWorking(e)
            default: working = false
            }
            guard working else { return }
            rate += em * mult
            by[Int(r.proto), default: 0] += em * mult
        }
        let perSecond = rate / 60
        perMinute += perSecond - ring[head]
        ring[head] = perSecond
        head = (head + 1) % ring.count
        total += perSecond
        bySource = by
    }

    func serialize(to w: inout BinaryWriter) {
        w.write(UInt8(1)); w.write(perMinute); w.write(total); w.write(Int64(head))
        for v in ring { w.write(v) }
    }
    func deserialize(from r: inout BinaryReader) throws {
        _ = try r.read(UInt8.self)
        perMinute = try r.readDouble(); total = try r.readDouble(); head = Int(try r.read(Int64.self)) % 60
        for i in 0..<60 { ring[i] = try r.readDouble() }
    }
}
