// Gearforge — FactoryCore
// Map layout value types: resource patches, oil wells, and campaign layout overrides.
// Owner: Gameplay engineer.

import Foundation

/// A resource patch: a noise-distorted disc whose per-tile amount decreases from the centre towards the edge.
/// Pure value — the amount at a tile depends only on the patch fields and the tile coordinates.
public struct ResourcePatch: Equatable, Sendable {
    /// Resource prototype index.
    public var resource: ResourceIndex
    /// Centre in tile units (continuous).
    public var cx: Double
    public var cy: Double
    /// Nominal radius in tiles (the boundary is distorted by ±`distortion`).
    public var radius: Double
    /// Amount at the very centre. Per-tile amount = peak × (edge + (1 − edge) × (1 − dn²)).
    public var peak: Double
    public var shapeSeed: UInt64
    public var isStarting: Bool

    /// Fraction of the peak amount at the patch edge.
    public static let edgeFraction = 0.3
    /// Relative boundary distortion amplitude.
    public static let distortion = 0.3
    /// Average of the amount profile over the undistorted disc (edge + (1−edge)/2), used for analytic totals.
    public static let meanProfile = edgeFraction + (1 - edgeFraction) / 2

    /// Bounding box (inclusive min, exclusive max) of every tile the patch can cover.
    public var minX: Int { Int((cx - radius * (1 + Self.distortion) - 1).rounded(.down)) }
    public var minY: Int { Int((cy - radius * (1 + Self.distortion) - 1).rounded(.down)) }
    public var maxX: Int { Int((cx + radius * (1 + Self.distortion) + 1).rounded(.up)) }
    public var maxY: Int { Int((cy + radius * (1 + Self.distortion) + 1).rounded(.up)) }

    @inline(__always)
    public func overlaps(minX x0: Int, minY y0: Int, maxX x1: Int, maxY y1: Int) -> Bool {
        minX < x1 && x0 < maxX && minY < y1 && y0 < maxY
    }

    /// Normalised distorted distance of the tile centre from the patch centre (< 1 = inside).
    @inline(__always)
    public func normalizedDistance(_ px: Double, _ py: Double) -> Double {
        let dx = px - cx, dy = py - cy
        let d = (dx * dx + dy * dy).squareRoot()
        if d > radius * (1 + Self.distortion) { return 2 }
        let n = MapNoise.gradient(px / 9, py / 9, shapeSeed)
        return d / (radius * (1 + Self.distortion * n))
    }

    /// Profile value (0 outside, edge…1 inside) for a normalised distance.
    @inline(__always)
    public static func profile(_ dn: Double) -> Double {
        dn >= 1 ? 0 : edgeFraction + (1 - edgeFraction) * (1 - dn * dn)
    }

    /// Integer amount for a profile value (always ≥ 1 inside the patch).
    @inline(__always)
    public func amount(profile s: Double) -> UInt32 {
        UInt32(min(Double(UInt32.max), max(1, (peak * s).rounded())))
    }
}

/// A single crude-oil well tile. `amount` = yield × 300 000 (100 % yield = 300 000, 05 §4.3).
public struct OilWell: Equatable, Sendable {
    public var pos: TilePos
    public var amount: UInt32
}

/// Explicit starting patch for campaign levels.
public struct StartingPatchSpec: Codable, Equatable, Sendable {
    /// Resource id ("iron_ore", "copper_ore", "coal", "stone", "uranium_ore").
    public var resource: String
    /// Total amount over the whole patch (exact, ±rounding).
    public var total: Int
    /// Distance of the patch centre from spawn in tiles (nil = default layout distance).
    public var distance: Double?
    /// Direction from spawn in degrees (0 = east, 90 = south). nil = evenly spread around spawn.
    public var angleDegrees: Double?
    /// Nominal radius in tiles (nil = derived from the total).
    public var radius: Double?
    public init(resource: String, total: Int, distance: Double? = nil, angleDegrees: Double? = nil, radius: Double? = nil) {
        self.resource = resource; self.total = total; self.distance = distance
        self.angleDegrees = angleDegrees; self.radius = radius
    }
}

/// Explicit oil field for campaign levels.
public struct OilFieldSpec: Codable, Equatable, Sendable {
    public var minDistance: Double
    public var maxDistance: Double
    /// Direction from spawn in degrees (0 = east, 90 = south, 315 = north-east). nil = seeded random.
    public var angleDegrees: Double?
    public var wells: Int
    /// Yield range as a fraction (1.5 = 150 %).
    public var minYield: Double
    public var maxYield: Double
    public init(minDistance: Double, maxDistance: Double, angleDegrees: Double? = nil, wells: Int,
                minYield: Double, maxYield: Double) {
        self.minDistance = minDistance; self.maxDistance = maxDistance; self.angleDegrees = angleDegrees
        self.wells = wells; self.minYield = minYield; self.maxYield = maxYield
    }
}

/// Campaign override of the guaranteed starting layout. Install with `MapGenerator.configure(_:)` before any chunk
/// is generated (i.e. right after creating the World).
public struct MapLayoutOverride: Codable, Equatable, Sendable {
    /// Replaces the four default starting patches (nil = default iron/copper/coal/stone).
    public var startingPatches: [StartingPatchSpec]?
    /// Replaces the default first oil field (nil = default; [] = no guaranteed oil).
    public var oilFields: [OilFieldSpec]?
    /// Distance of the starting lake centre from spawn (nil = 22–28 tiles).
    public var lakeDistance: Double?
    /// Whether regular (non-starting) resource patches and oil fields are generated.
    public var regularResources: Bool
    public init(startingPatches: [StartingPatchSpec]? = nil, oilFields: [OilFieldSpec]? = nil,
                lakeDistance: Double? = nil, regularResources: Bool = true) {
        self.startingPatches = startingPatches; self.oilFields = oilFields
        self.lakeDistance = lakeDistance; self.regularResources = regularResources
    }
}
