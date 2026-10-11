// Gearforge — FactoryCore
// Coordinate-hashed noise for deterministic, order-independent map generation.
// Every function here is pure: the value at a point depends only on (seed, coordinates). There is no shared mutable
// RNG, so chunks generate identically regardless of the order in which they are requested.
// Owner: Gameplay engineer.

import Foundation

/// Pure hashing / noise helpers used by `MapGenerator`.
public enum MapNoise {

    // MARK: Hashing

    /// SplitMix64 finaliser — a high-quality 64-bit mixer.
    @inline(__always)
    public static func mix(_ v: UInt64) -> UInt64 {
        var z = v
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Hash of an integer lattice point under a seed.
    @inline(__always)
    public static func hash(_ x: Int, _ y: Int, _ seed: UInt64) -> UInt64 {
        let hx = UInt64(bitPattern: Int64(x)) &* 0x9E37_79B9_7F4A_7C15
        let hy = UInt64(bitPattern: Int64(y)) &* 0xC2B2_AE3D_27D4_EB4F
        return mix(seed ^ hx ^ (hy &+ 0x1656_67B1_9E37_79F9))
    }

    /// Derives an independent sub-seed (e.g. one per noise layer or per resource).
    @inline(__always)
    public static func subSeed(_ seed: UInt64, _ salt: UInt64) -> UInt64 {
        mix(seed &+ salt &* 0x9E37_79B9_7F4A_7C15)
    }

    /// Uniform double in [0, 1) from a hash.
    @inline(__always)
    public static func unit(_ h: UInt64) -> Double { Double(h >> 11) * (1.0 / 9_007_199_254_740_992.0) }

    /// Uniform double in [0, 1) for a lattice point.
    @inline(__always)
    public static func unit(_ x: Int, _ y: Int, _ seed: UInt64) -> Double { unit(hash(x, y, seed)) }

    // MARK: Gradient noise

    /// 16 unit gradient directions.
    @usableFromInline static let gradX: [Double] = (0..<16).map { cos(Double($0) * .pi / 8) }
    @usableFromInline static let gradY: [Double] = (0..<16).map { sin(Double($0) * .pi / 8) }

    @inline(__always)
    static func fade(_ t: Double) -> Double { t * t * t * (t * (t * 6 - 15) + 10) }

    /// 2D gradient (Perlin-style) noise, roughly in [-1, 1], zero at lattice points.
    @inline(__always)
    public static func gradient(_ x: Double, _ y: Double, _ seed: UInt64) -> Double {
        let fx0 = x.rounded(.down), fy0 = y.rounded(.down)
        let ix = Int(fx0), iy = Int(fy0)
        let dx = x - fx0, dy = y - fy0
        @inline(__always) func dot(_ cx: Int, _ cy: Int, _ ox: Double, _ oy: Double) -> Double {
            let g = Int(hash(cx, cy, seed) & 15)
            return gradX[g] * ox + gradY[g] * oy
        }
        let n00 = dot(ix, iy, dx, dy)
        let n10 = dot(ix + 1, iy, dx - 1, dy)
        let n01 = dot(ix, iy + 1, dx, dy - 1)
        let n11 = dot(ix + 1, iy + 1, dx - 1, dy - 1)
        let u = fade(dx), v = fade(dy)
        let a = n00 + (n10 - n00) * u
        let b = n01 + (n11 - n01) * u
        return (a + (b - a) * v) * 1.414
    }

    /// Fractal Brownian motion of gradient noise. `frequency` in cycles per tile. Result roughly in [-1, 1]
    /// (standard deviation ≈ 0.2 for 3–4 octaves).
    @inline(__always)
    public static func fbm(_ x: Double, _ y: Double, frequency: Double, octaves: Int, seed: UInt64,
                           lacunarity: Double = 2, gain: Double = 0.5) -> Double {
        var sum = 0.0, amp = 1.0, norm = 0.0, f = frequency
        var s = seed
        for _ in 0..<octaves {
            sum += amp * gradient(x * f, y * f, s)
            norm += amp
            amp *= gain
            f *= lacunarity
            s = s &+ 0x632B_E59B_D9B4_E019
        }
        return sum / norm
    }
}
