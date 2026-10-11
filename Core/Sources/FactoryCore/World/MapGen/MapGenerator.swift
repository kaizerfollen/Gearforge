// Gearforge — FactoryCore
// Deterministic chunk generation: terrain, water, resource patches (guaranteed starting area), trees, rocks
// (05_mechanics §14, GDD §8). Owner: Gameplay engineer.
//
// Design
// - Every chunk is a pure function of (seed, chunk coordinates, WorldSettings, layout override). All randomness is
//   coordinate-hashed (`MapNoise`); there is no shared RNG, so chunks are identical regardless of generation order.
// - The guaranteed starting layout (lake, four starting patches, first oil field) is computed once in `init` /
//   `configure(_:)` from the seed. Starting patches are numerically integrated so their totals hit the target exactly.
// - Regular patches come from a jittered cell grid per resource (one candidate spot per cell); only the cells that
//   can touch a chunk are evaluated, so the per-chunk cost is constant.
//
// [GF] deviations (finite mobile maps): regular patches start at 130 tiles (×starting area) instead of fading in from
// 120–420, and spot density is 3× the 1.1 spots/km² so Small/Medium maps still have expansion patches.

import Foundation

public final class MapGenerator {
    public unowned let world: World
    public let settings: WorldSettings
    public let seed: UInt64

    // MARK: Tunables

    /// No trees/rocks within this radius of spawn (tiles).
    public static let spawnClearRadius = 8.0
    /// No water within this radius of spawn (tiles).
    public static let spawnDryRadius = 12.0
    /// Starting patches: every tile lies within [min, max] tiles of spawn (× starting area scale).
    public static let startingPatchMinDistance = 30.0
    public static let startingPatchMaxDistance = 90.0
    /// Default starting patch totals (05 §14 [GF] target ranges: iron 400–600k, copper 300–450k, coal 300–450k,
    /// stone 150–250k — we use the middle of each range) and nominal average density per tile.
    public static let startingTotals: [(id: String, total: Double, density: Double)] = [
        ("iron_ore", 500_000, 900), ("copper_ore", 375_000, 850), ("coal", 375_000, 850), ("stone", 200_000, 750),
    ]
    /// Regular patch parameters: base total at the fade-in distance and radius range (before the size setting).
    static let regularPatchParams: [(id: String, spotsPerKm2: Double, total: Double, rMin: Double, rMax: Double, minDist: Double)] = [
        ("iron_ore", 2.5, 600_000, 13, 20, 0), ("copper_ore", 2.5, 500_000, 13, 19, 0),
        ("coal", 2.5, 450_000, 12, 18, 0), ("stone", 2.5, 250_000, 10, 15, 0),
        ("uranium_ore", 1.25, 100_000, 6, 10, 300),
    ]
    public static let regularPatchStartDistance = 130.0
    public static let finiteMapSpotMultiplier = 3.0
    /// Richness grows linearly with distance: ×2 at 1300 tiles beyond the regular start distance (05 §14).
    public static let richnessDoublingDistance = 1300.0
    /// Crude oil: 100 % yield amount and regular field parameters.
    public static let oilNormalAmount = 300_000.0
    public static let oilSpotsPerKm2 = 1.8
    public static let oilRegularMinDistance = 300.0
    /// Fraction of the map covered by lakes at waterCoverage = 1.
    public static let baseWaterFraction = 0.07

    // MARK: Resolved prototype indices

    let tGrass1: UInt8, tGrass2: UInt8, tDirt: UInt8, tSand: UInt8, tRedDesert: UInt8, tWater: UInt8, tDeepWater: UInt8
    let rOil: ResourceIndex
    let treeProtos: [Int]           // tree_01, tree_02, tree_03
    let deadTreeProto: Int
    let bigRockProto: Int
    let hugeRockProto: Int

    // MARK: Noise seeds

    let seedWater: UInt64, seedLake: UInt64, seedMoist: UInt64, seedArid: UInt64, seedDetail: UInt64
    let seedForest: UInt64, seedTreePlace: UInt64, seedRock: UInt64, seedLayout: UInt64

    // MARK: Water thresholds

    let waterEnabled: Bool
    let waterFrequency: Double
    let waterThreshold: Double
    let deepThreshold: Double

    // MARK: Layout (computed from the seed)

    public private(set) var layoutOverride: MapLayoutOverride?
    /// Guaranteed starting patches (exact totals).
    public private(set) var startingPatches: [ResourcePatch] = []
    /// Guaranteed oil wells (first field / campaign fields). Regular fields are generated per cell.
    public private(set) var fixedOilWells: [OilWell] = []
    /// Starting lake centre (tile units) and nominal radius.
    public private(set) var lakeCenter: Vec2 = .zero
    public private(set) var lakeRadius: Double = 0
    private var regularEnabled = true
    /// Circles where noise water is suppressed (spawn, starting patches, fixed wells): (cx, cy, r).
    private var protectedCircles: [(Double, Double, Double)] = []
    /// Per-resource regular patch config resolved against settings: (resource, cell size, offsetX, offsetY, params idx).
    private var regularResources: [(resource: ResourceIndex, cell: Double, ox: Double, oy: Double, param: Int, seed: UInt64,
                                     size: Double, richness: Double)] = []
    private var oilCell: Double = 0
    private var oilSize: Double = 1
    private var oilRichness: Double = 1

    /// Spawn tile (the character starts at its centre). No water at, and no trees/rocks near, this tile.
    public var spawnPosition: TilePos { TilePos(0, 0) }

    public init(world: World) {
        self.world = world
        self.settings = world.settings
        self.seed = MapNoise.mix(world.settings.seed ^ 0x6D61_7067_656E_0001)
        let db = world.db
        func tile(_ id: String) -> UInt8 { UInt8(max(0, db.tile(id))) }
        tGrass1 = tile("grass_1"); tGrass2 = tile("grass_2"); tDirt = tile("dirt"); tSand = tile("sand")
        tRedDesert = tile("red_desert"); tWater = tile("water"); tDeepWater = tile("deep_water")
        rOil = db.resource("crude_oil")
        treeProtos = ["tree_01", "tree_02", "tree_03"].map { db.entity($0) }.filter { $0 >= 0 }
        deadTreeProto = db.entity("dead_tree")
        bigRockProto = db.entity("big_rock")
        hugeRockProto = db.entity("huge_rock")

        seedWater = MapNoise.subSeed(seed, 1); seedLake = MapNoise.subSeed(seed, 2)
        seedMoist = MapNoise.subSeed(seed, 3); seedArid = MapNoise.subSeed(seed, 4)
        seedDetail = MapNoise.subSeed(seed, 5); seedForest = MapNoise.subSeed(seed, 6)
        seedTreePlace = MapNoise.subSeed(seed, 7); seedRock = MapNoise.subSeed(seed, 8)
        seedLayout = MapNoise.subSeed(seed, 9)

        let cov = max(0, settings.waterCoverage)
        waterEnabled = cov > 0
        waterFrequency = 1 / (110 * max(0.25, settings.waterScale))
        let frac = min(0.5, Self.baseWaterFraction * cov)
        waterThreshold = Self.fbmQuantile(frac)
        deepThreshold = Self.fbmQuantile(frac * 0.3)
        computeLayout()
    }

    /// Installs a campaign layout override and recomputes the guaranteed layout. Must be called before any chunk is
    /// generated (chunks already generated keep their old content).
    public func configure(_ override: MapLayoutOverride?) {
        layoutOverride = override
        computeLayout()
    }

    // MARK: Water threshold calibration

    /// Approximate value below which a fraction `f` of 4-octave `fbm` samples fall. The distribution is close to
    /// normal with σ ≈ `fbmSigma` (measured over 10⁶ samples; see GameplayMapGenTests.testWaterCoverageScales).
    static let fbmSigma = 0.235
    static func fbmQuantile(_ f: Double) -> Double {
        if f <= 0 { return -10 }
        return fbmSigma * inverseNormalCDF(f)
    }

    /// Acklam's rational approximation of the standard normal quantile (|error| < 1.2e-9).
    static func inverseNormalCDF(_ p: Double) -> Double {
        let a = [-3.969683028665376e+01, 2.209460984245205e+02, -2.759285104469687e+02, 1.383577518672690e+02,
                 -3.066479806614716e+01, 2.506628277459239e+00]
        let b = [-5.447609879822406e+01, 1.615858368580409e+02, -1.556989798598866e+02, 6.680131188771972e+01,
                 -1.328068155288572e+01]
        let c = [-7.784894002430293e-03, -3.223964580411365e-01, -2.400758277161838e+00, -2.549732539343734e+00,
                 4.374664141464968e+00, 2.938163982698783e+00]
        let d = [7.784695709041462e-03, 3.224671290700398e-01, 2.445134137142996e+00, 3.754408661907416e+00]
        let pl = 0.02425
        let p = min(max(p, 1e-12), 1 - 1e-12)
        if p < pl {
            let q = (-2 * log(p)).squareRoot()
            return (((((c[0]*q+c[1])*q+c[2])*q+c[3])*q+c[4])*q+c[5]) / ((((d[0]*q+d[1])*q+d[2])*q+d[3])*q+1)
        } else if p <= 1 - pl {
            let q = p - 0.5, r = q * q
            return (((((a[0]*r+a[1])*r+a[2])*r+a[3])*r+a[4])*r+a[5])*q / (((((b[0]*r+b[1])*r+b[2])*r+b[3])*r+b[4])*r+1)
        } else {
            let q = (-2 * log(1 - p)).squareRoot()
            return -(((((c[0]*q+c[1])*q+c[2])*q+c[3])*q+c[4])*q+c[5]) / ((((d[0]*q+d[1])*q+d[2])*q+d[3])*q+1)
        }
    }

    // MARK: Layout

    private func resourceSetting(_ id: String) -> ResourceGenSetting { settings.resourceSettings[id] ?? ResourceGenSetting() }

    private func layoutUnit(_ salt: Int) -> Double { MapNoise.unit(salt, 0x5EED, seedLayout) }

    /// Largest distance from spawn that keeps a disc of radius `r` inside the map with a small margin.
    private func maxCentreDistance(radius r: Double) -> Double {
        let half = Double(min(world.surface.width, world.surface.height)) / 2
        return max(0, half - r * (1 + ResourcePatch.distortion) - 2)
    }

    private func computeLayout() {
        let ov = layoutOverride
        let scale = max(0.25, settings.startingAreaScale)
        regularEnabled = ov?.regularResources ?? true
        let theta0 = layoutUnit(1) * 2 * Double.pi
        let slot = 2 * Double.pi / 5

        // Starting lake: 22–28 tiles from spawn, radius 5.5–8.5 → nearest water ≤ 25 tiles, never within 11 tiles.
        let lakeAngle = theta0 + (layoutUnit(2) - 0.5) * 0.35
        lakeRadius = 5.5 + 3 * layoutUnit(3)
        let lakeDist = ov?.lakeDistance ?? (22 + 6 * layoutUnit(4))
        lakeCenter = Vec2(0.5 + cos(lakeAngle) * lakeDist, 0.5 + sin(lakeAngle) * lakeDist)

        // Starting patches.
        var specs: [(res: ResourceIndex, total: Double, dist: Double?, angle: Double?, radius: Double?, density: Double)] = []
        if let custom = ov?.startingPatches {
            for s in custom {
                let r = world.db.resource(s.resource)
                guard r >= 0 else { continue }
                specs.append((r, Double(s.total), s.distance, s.angleDegrees.map { $0 * .pi / 180 }, s.radius, 850))
            }
        } else {
            for t in Self.startingTotals {
                let r = world.db.resource(t.id)
                guard r >= 0 else { continue }
                let rs = resourceSetting(t.id)
                let total = t.total * max(0, rs.size) * max(0, rs.richness)
                guard total > 0 else { continue }
                // Size scales the area; the average density is fixed so richness raises per-tile amounts.
                let r0 = (t.total * max(0, rs.size) / (Double.pi * t.density * ResourcePatch.meanProfile / 0.65)).squareRoot()
                specs.append((r, total, nil, nil, min(22, max(4, r0)), t.density))
            }
        }
        startingPatches = []
        protectedCircles = [(0.5, 0.5, Self.spawnDryRadius)]
        for (k, s) in specs.enumerated() {
            let radius = s.radius ?? min(22, max(3, (s.total / (Double.pi * s.density * ResourcePatch.meanProfile / 0.65)).squareRoot()))
            let reach = radius * (1 + ResourcePatch.distortion)
            let angle = s.angle ?? (theta0 + Double(k + 1) * slot + (layoutUnit(10 + k) - 0.5) * 0.35)
            var dist: Double
            if let d = s.dist {
                dist = d
            } else {
                let lo = Self.startingPatchMinDistance * scale + reach + 1
                let hi = Self.startingPatchMaxDistance * scale - reach - 1
                dist = lo <= hi ? lo + (hi - lo) * layoutUnit(20 + k) : (lo + hi) / 2
            }
            dist = min(dist, maxCentreDistance(radius: radius))
            let cx = 0.5 + cos(angle) * dist, cy = 0.5 + sin(angle) * dist
            let patch = makeExactPatch(resource: s.res, cx: cx, cy: cy, radius: radius, total: s.total,
                                       shapeSeed: MapNoise.subSeed(seedLayout, UInt64(100 + k)))
            startingPatches.append(patch)
            protectedCircles.append((cx, cy, reach + 3))
        }

        // Guaranteed oil fields.
        fixedOilWells = []
        let oilSet = resourceSetting("crude_oil")
        let fields: [OilFieldSpec]
        if let custom = ov?.oilFields {
            fields = custom
        } else if oilSet.frequency > 0 && oilSet.size > 0 && rOil >= 0 {
            let wells = min(16, max(1, Int((4 + 5 * layoutUnit(30)).rounded(.down) * 1)))
            fields = [OilFieldSpec(minDistance: 150, maxDistance: 300, angleDegrees: nil,
                                   wells: max(1, Int((Double(wells) * oilSet.size).rounded())),
                                   minYield: 2 * oilSet.richness, maxYield: 5 * oilSet.richness)]
        } else {
            fields = []
        }
        for (k, f) in fields.enumerated() where rOil >= 0 {
            let angle = f.angleDegrees.map { $0 * .pi / 180 } ?? layoutUnit(40 + k) * 2 * .pi
            let fieldRadius = 3 + 1.2 * Double(f.wells)
            let maxD = maxCentreDistance(radius: fieldRadius)
            let lo = min(f.minDistance, maxD), hi = min(max(f.maxDistance, f.minDistance), maxD)
            let dist = lo + (hi - lo) * layoutUnit(50 + k)
            let centre = Vec2(0.5 + cos(angle) * dist, 0.5 + sin(angle) * dist)
            let wells = oilField(centre: centre, count: f.wells, minYield: f.minYield, maxYield: f.maxYield,
                                 seed: MapNoise.subSeed(seedLayout, UInt64(200 + k)))
            fixedOilWells.append(contentsOf: wells)
        }
        for w in fixedOilWells { protectedCircles.append((Double(w.pos.x) + 0.5, Double(w.pos.y) + 0.5, 4)) }

        // Regular resources.
        regularResources = []
        for (pi, p) in Self.regularPatchParams.enumerated() {
            let r = world.db.resource(p.id)
            let rs = resourceSetting(p.id)
            guard r >= 0, rs.frequency > 0, rs.size > 0, rs.richness > 0 else { continue }
            let spots = p.spotsPerKm2 * Self.finiteMapSpotMultiplier * rs.frequency
            let cell = (1_000_000 / spots).squareRoot()
            let rseed = MapNoise.subSeed(seed, UInt64(1000 + pi))
            regularResources.append((r, cell, MapNoise.unit(1, 2, rseed) * cell, MapNoise.unit(3, 4, rseed) * cell, pi, rseed,
                                     rs.size, rs.richness))
        }
        oilSize = max(0, oilSet.size)
        oilRichness = max(0, oilSet.richness)
        oilCell = oilSet.frequency > 0 && rOil >= 0
            ? (1_000_000 / (Self.oilSpotsPerKm2 * Self.finiteMapSpotMultiplier * oilSet.frequency)).squareRoot() : 0
    }

    /// Builds a patch whose rounded per-tile amounts sum to `total` (in-bounds tiles only).
    private func makeExactPatch(resource: ResourceIndex, cx: Double, cy: Double, radius: Double, total: Double,
                                shapeSeed: UInt64) -> ResourcePatch {
        var p = ResourcePatch(resource: resource, cx: cx, cy: cy, radius: radius, peak: 1, shapeSeed: shapeSeed, isStarting: true)
        let b = world.surface.bounds
        var profiles: [Double] = []
        var y = max(p.minY, Int(b.y))
        while y < min(p.maxY, Int(b.maxY)) {
            var x = max(p.minX, Int(b.x))
            while x < min(p.maxX, Int(b.maxX)) {
                let s = ResourcePatch.profile(p.normalizedDistance(Double(x) + 0.5, Double(y) + 0.5))
                if s > 0 { profiles.append(s) }
                x += 1
            }
            y += 1
        }
        let sum = profiles.reduce(0, +)
        guard sum > 0 else { return p }
        p.peak = total / sum
        // One correction pass for rounding.
        let rounded = profiles.reduce(0.0) { $0 + Double(p.amount(profile: $1)) }
        if rounded > 0 { p.peak *= total / rounded }
        return p
    }

    /// Places `count` single-tile wells in a cluster around `centre`, at least 3 tiles apart (Chebyshev) so 3×3
    /// pumpjacks fit on every well.
    private func oilField(centre: Vec2, count: Int, minYield: Double, maxYield: Double, seed s: UInt64) -> [OilWell] {
        var wells: [OilWell] = []
        let spread = 2.5 + 1.1 * Double(count)
        var attempt = 0
        while wells.count < count && attempt < count * 40 {
            let a = MapNoise.unit(attempt, 1, s) * 2 * .pi
            let r = MapNoise.unit(attempt, 2, s).squareRoot() * spread
            let pos = TilePos(Int32((centre.x + cos(a) * r).rounded(.down)), Int32((centre.y + sin(a) * r).rounded(.down)))
            attempt += 1
            guard world.surface.isInBounds(pos) else { continue }
            if wells.contains(where: { max(abs($0.pos.x - pos.x), abs($0.pos.y - pos.y)) < 3 }) { continue }
            let yield = minYield + (maxYield - minYield) * MapNoise.unit(attempt, 3, s)
            let amount = UInt32(min(Double(UInt32.max), max(1, (yield * Self.oilNormalAmount).rounded())))
            wells.append(OilWell(pos: pos, amount: amount))
        }
        return wells
    }

    // MARK: Regular patches (per cell, pure)

    @inline(__always)
    private func distanceFromSpawn(_ x: Double, _ y: Double) -> Double {
        let dx = x - 0.5, dy = y - 0.5
        return (dx * dx + dy * dy).squareRoot()
    }

    /// Regular patches that can touch the tile rect [x0, x1) × [y0, y1).
    func regularPatches(minX x0: Int, minY y0: Int, maxX x1: Int, maxY y1: Int) -> [ResourcePatch] {
        guard regularEnabled else { return [] }
        var out: [ResourcePatch] = []
        let scale = max(0.25, settings.startingAreaScale)
        let margin = 32 * (1 + ResourcePatch.distortion) + 2
        for rr in regularResources {
            let p = Self.regularPatchParams[rr.param]
            let cs = rr.cell
            let i0 = Int(((Double(x0) - margin - rr.ox) / cs).rounded(.down))
            let i1 = Int(((Double(x1) + margin - rr.ox) / cs).rounded(.down))
            let j0 = Int(((Double(y0) - margin - rr.oy) / cs).rounded(.down))
            let j1 = Int(((Double(y1) + margin - rr.oy) / cs).rounded(.down))
            guard i0 <= i1, j0 <= j1 else { continue }
            for j in j0...j1 {
                for i in i0...i1 {
                    let h = MapNoise.hash(i, j, rr.seed)
                    guard MapNoise.unit(h) < 0.85 else { continue }
                    let cx = rr.ox + (Double(i) + 0.15 + 0.7 * MapNoise.unit(i, j &+ 7919, rr.seed)) * cs
                    let cy = rr.oy + (Double(j) + 0.15 + 0.7 * MapNoise.unit(i &+ 104_729, j, rr.seed)) * cs
                    let dist = distanceFromSpawn(cx, cy)
                    let start = max(Self.regularPatchStartDistance * scale, p.minDist)
                    // Patches near the starting area are smaller (fade-in over 300 tiles).
                    let fade = min(1, max(0.5, 0.5 + 0.5 * (dist - start) / 300))
                    let radius = min(32, (p.rMin + (p.rMax - p.rMin) * MapNoise.unit(i, j, rr.seed ^ 0xA11CE))
                                     * rr.size.squareRoot() * fade)
                    guard dist - radius * (1 + ResourcePatch.distortion) >= start else { continue }
                    let richness = 1 + max(0, dist - start) / Self.richnessDoublingDistance
                    let total = p.total * rr.size * fade * fade * rr.richness * richness
                    let peak = total / (Double.pi * radius * radius * ResourcePatch.meanProfile)
                    let patch = ResourcePatch(resource: rr.resource, cx: cx, cy: cy, radius: radius, peak: peak,
                                              shapeSeed: MapNoise.subSeed(rr.seed, h), isStarting: false)
                    if patch.overlaps(minX: x0, minY: y0, maxX: x1, maxY: y1) { out.append(patch) }
                }
            }
        }
        return out
    }

    /// Oil wells (fixed + regular fields) inside the tile rect.
    func oilWells(minX x0: Int, minY y0: Int, maxX x1: Int, maxY y1: Int) -> [OilWell] {
        var out: [OilWell] = []
        for w in fixedOilWells where Int(w.pos.x) >= x0 && Int(w.pos.x) < x1 && Int(w.pos.y) >= y0 && Int(w.pos.y) < y1 {
            out.append(w)
        }
        guard regularEnabled, oilCell > 0 else { return out }
        let s = MapNoise.subSeed(seed, 2000)
        let ox = MapNoise.unit(5, 6, s) * oilCell, oy = MapNoise.unit(7, 8, s) * oilCell
        let margin = 16.0
        let i0 = Int(((Double(x0) - margin - ox) / oilCell).rounded(.down)), i1 = Int(((Double(x1) + margin - ox) / oilCell).rounded(.down))
        let j0 = Int(((Double(y0) - margin - oy) / oilCell).rounded(.down)), j1 = Int(((Double(y1) + margin - oy) / oilCell).rounded(.down))
        guard i0 <= i1, j0 <= j1 else { return out }
        for j in j0...j1 {
            for i in i0...i1 {
                let h = MapNoise.hash(i, j, s)
                guard MapNoise.unit(h) < 0.8 else { continue }
                let cx = ox + (Double(i) + 0.2 + 0.6 * MapNoise.unit(i, j &+ 31, s)) * oilCell
                let cy = oy + (Double(j) + 0.2 + 0.6 * MapNoise.unit(i &+ 37, j, s)) * oilCell
                let dist = distanceFromSpawn(cx, cy)
                guard dist >= Self.oilRegularMinDistance + 12 else { continue }
                let count = max(1, Int(((3 + 5 * MapNoise.unit(i, j, s ^ 0x0111)) * oilSize).rounded(.down)))
                let richness = (1 + max(0, dist - Self.oilRegularMinDistance) / Self.richnessDoublingDistance) * oilRichness
                for w in oilField(centre: Vec2(cx, cy), count: count, minYield: 1 * richness, maxYield: 3 * richness,
                                  seed: MapNoise.subSeed(s, h))
                where Int(w.pos.x) >= x0 && Int(w.pos.x) < x1 && Int(w.pos.y) >= y0 && Int(w.pos.y) < y1 {
                    out.append(w)
                }
            }
        }
        return out
    }

    // MARK: Chunk generation

    /// Generates terrain and resources for a chunk. Pure in (seed, settings, override, chunk position).
    public func generateChunk(_ c: ChunkPos) -> Chunk {
        let ch = Chunk(pos: c, fillTile: tGrass1)
        let x0 = Int(c.x) << chunkShift, y0 = Int(c.y) << chunkShift
        let x1 = x0 + chunkSize, y1 = y0 + chunkSize

        var patches = startingPatches.filter { $0.overlaps(minX: x0, minY: y0, maxX: x1, maxY: y1) }
        patches.append(contentsOf: regularPatches(minX: x0, minY: y0, maxX: x1, maxY: y1))
        let wells = rOil >= 0 ? oilWells(minX: x0 - 4, minY: y0 - 4, maxX: x1 + 4, maxY: y1 + 4) : []
        var guards = protectedCircles.filter { (cx, cy, r) in
            cx + r > Double(x0) && cx - r < Double(x1) && cy + r > Double(y0) && cy - r < Double(y1)
        }
        for w in wells { guards.append((Double(w.pos.x) + 0.5, Double(w.pos.y) + 0.5, 4)) }
        let lakeReach = lakeRadius * 1.3 + 1
        let lakeNear = lakeCenter.x + lakeReach > Double(x0) && lakeCenter.x - lakeReach < Double(x1)
            && lakeCenter.y + lakeReach > Double(y0) && lakeCenter.y - lakeReach < Double(y1)

        ch.tiles.withUnsafeMutableBufferPointer { tiles in
        ch.resource.withUnsafeMutableBufferPointer { res in
        ch.resourceAmount.withUnsafeMutableBufferPointer { amt in
            for ly in 0..<chunkSize {
                let y = y0 + ly
                let py = Double(y) + 0.5
                for lx in 0..<chunkSize {
                    let x = x0 + lx
                    let px = Double(x) + 0.5
                    let i = ly << chunkShift | lx

                    // Water: starting lake blob, then noise lakes outside protected circles.
                    var water = false, deep = false
                    if lakeNear {
                        let dx = px - lakeCenter.x, dy = py - lakeCenter.y
                        let d = (dx * dx + dy * dy).squareRoot()
                        if d < lakeReach {
                            let ld = d / (lakeRadius * (1 + 0.25 * MapNoise.gradient(px / 7, py / 7, seedLake)))
                            if ld < 1 { water = true; deep = ld < 0.45 && lakeRadius >= 7 }
                        }
                    }
                    var v = 1.0
                    if !water && waterEnabled {
                        var guarded = false
                        for (gx, gy, gr) in guards {
                            let dx = px - gx, dy = py - gy
                            if dx * dx + dy * dy < gr * gr { guarded = true; break }
                        }
                        if !guarded {
                            v = MapNoise.fbm(px, py, frequency: waterFrequency, octaves: 4, seed: seedWater)
                            if v < waterThreshold { water = true; deep = v < deepThreshold }
                        }
                    }
                    if water {
                        tiles[i] = deep ? tDeepWater : tWater
                        continue
                    }
                    tiles[i] = biome(px, py, lakeValue: v)

                    // Resources (never under water).
                    var bestStrength = 0.0, bestPatch = -1, bestProfile = 0.0
                    for (k, p) in patches.enumerated()
                    where x >= p.minX && x < p.maxX && y >= p.minY && y < p.maxY {
                        let dn = p.normalizedDistance(px, py)
                        if dn < 1 && 1 - dn > bestStrength {
                            bestStrength = 1 - dn; bestPatch = k; bestProfile = ResourcePatch.profile(dn)
                        }
                    }
                    if bestPatch >= 0 {
                        let p = patches[bestPatch]
                        res[i] = UInt8(p.resource + 1)
                        amt[i] = p.amount(profile: bestProfile)
                    }
                    for w in wells where Int(w.pos.x) == x && Int(w.pos.y) == y {
                        res[i] = UInt8(rOil + 1)
                        amt[i] = w.amount
                    }
                }
            }
        }
        }
        }
        return ch
    }

    /// Land biome for a tile. `lakeValue` is the noise-water value (1 when not evaluated) used for beaches.
    @inline(__always)
    private func biome(_ px: Double, _ py: Double, lakeValue v: Double) -> UInt8 {
        if v < waterThreshold + 0.02 { return tSand }      // beach
        let m = MapNoise.fbm(px, py, frequency: 1.0 / 200, octaves: 3, seed: seedMoist)
            + 0.12 * MapNoise.fbm(px, py, frequency: 1.0 / 24, octaves: 2, seed: seedDetail)
        if m > 0.03 { return tGrass1 }
        if m > -0.09 { return tGrass2 }
        if m > -0.2 { return tDirt }
        return MapNoise.fbm(px, py, frequency: 1.0 / 260, octaves: 2, seed: seedArid) > 0 ? tRedDesert : tSand
    }

    // MARK: Natural entities

    /// Spawns natural entities (trees, rocks) for a freshly installed chunk via `world.createEntity(flags: [])`.
    /// Depends only on the chunk's own (pure) tiles and resources plus coordinate hashes, and every footprint lies
    /// inside the chunk, so the result is independent of generation order.
    public func populateChunk(_ ch: Chunk) {
        let x0 = Int(ch.pos.x) << chunkShift, y0 = Int(ch.pos.y) << chunkShift
        let db = world.db
        let clear2 = Self.spawnClearRadius * Self.spawnClearRadius

        @inline(__always) func isFreeLand(_ lx: Int, _ ly: Int) -> Bool {
            let i = ly << chunkShift | lx
            let x = x0 + lx, y = y0 + ly
            guard ch.occupancy[i] < 0, ch.resource[i] == 0, !db.tiles[Int(ch.tiles[i])].isWater else { return false }
            guard world.surface.isInBounds(TilePos(x, y)) else { return false }
            let dx = Double(x) + 0.5 - 0.5, dy = Double(y) + 0.5 - 0.5
            return dx * dx + dy * dy >= clear2
        }

        // Rocks first (multi-tile, must fit entirely inside this chunk).
        if settings.rocks {
            for (proto, size, chance) in [(hugeRockProto, 3, 1.0 / 4500), (bigRockProto, 2, 1.0 / 1500)] where proto >= 0 {
                for ly in 0...(chunkSize - size) {
                    for lx in 0...(chunkSize - size) {
                        let t = ch.tiles[ly << chunkShift | lx]
                        let mult = t == tDirt || t == tRedDesert || t == tSand ? 1.6 : (t == tGrass1 ? 0.6 : 1.0)
                        guard MapNoise.unit(x0 + lx, y0 + ly, seedRock &+ UInt64(size)) < chance * mult else { continue }
                        var ok = true
                        for dy in 0..<size where ok { for dx in 0..<size where ok { ok = isFreeLand(lx + dx, ly + dy) } }
                        if ok { world.createEntity(proto: proto, origin: TilePos(x0 + lx, y0 + ly), direction: .north, flags: []) }
                    }
                }
            }
        }

        // Trees: clumpy forests (fBm) weighted by biome, plus sparse scatter.
        let coverage = max(0, settings.treeCoverage)
        guard coverage > 0, !treeProtos.isEmpty else { return }
        for ly in 0..<chunkSize {
            for lx in 0..<chunkSize {
                let t = ch.tiles[ly << chunkShift | lx]
                let base: Double
                switch t {
                case tGrass1: base = 1.0
                case tGrass2: base = 0.55
                case tDirt: base = 0.3
                case tSand: base = 0.06
                case tRedDesert: base = 0.04
                default: base = 0
                }
                guard base > 0 else { continue }
                let x = x0 + lx, y = y0 + ly
                let roll = MapNoise.unit(x, y, seedTreePlace)
                // Cheap early-out: the maximum possible probability.
                guard roll < (0.42 + 0.012) * base * coverage else { continue }
                let forest = MapNoise.fbm(Double(x) + 0.5, Double(y) + 0.5, frequency: 1.0 / 64, octaves: 3, seed: seedForest)
                let p = (min(0.42, max(0, (forest + 0.02) * 1.1)) + 0.012) * base * coverage
                guard roll < p, isFreeLand(lx, ly) else { continue }
                let pick = MapNoise.hash(x, y, seedTreePlace ^ 0x7EE)
                let dry = t == tSand || t == tRedDesert || t == tDirt
                let proto: Int
                if deadTreeProto >= 0 && (dry ? pick & 1 == 0 : pick % 23 == 0) {
                    proto = deadTreeProto
                } else {
                    proto = treeProtos[Int((pick >> 8) % UInt64(treeProtos.count))]
                }
                world.createEntity(proto: proto, origin: TilePos(x, y), direction: .north, flags: [])
            }
        }
    }

    // MARK: Queries

    /// Total resource amount per resource index inside `rect` (generates chunks as needed).
    public func resourceSummary(in rect: TileRect) -> [ResourceIndex: Int] {
        var out: [ResourceIndex: Int] = [:]
        rect.forEach { p in
            let (r, a) = world.surface.resource(at: p)
            if r >= 0 { out[r, default: 0] += Int(a) }
        }
        return out
    }

    /// `resourceSummary(in:)` keyed by resource id.
    public func resourceSummaryByID(in rect: TileRect) -> [String: Int] {
        var out: [String: Int] = [:]
        for (r, a) in resourceSummary(in: rect) { out[world.db.resources[r].id] = a }
        return out
    }
}
