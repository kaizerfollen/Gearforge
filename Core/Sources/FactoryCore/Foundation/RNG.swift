// Gearforge — FactoryCore
// Deterministic RNG. Never use SystemRandomNumberGenerator inside the simulation.

/// xoshiro256** — fast, deterministic, serializable.
public struct DeterministicRNG: RandomNumberGenerator, Sendable {
    public private(set) var s0: UInt64, s1: UInt64, s2: UInt64, s3: UInt64

    public init(seed: UInt64) {
        var sm = SplitMix64(state: seed)
        s0 = sm.next(); s1 = sm.next(); s2 = sm.next(); s3 = sm.next()
        if s0 | s1 | s2 | s3 == 0 { s0 = 0x9E3779B97F4A7C15 }
    }

    public init(state: (UInt64, UInt64, UInt64, UInt64)) {
        (s0, s1, s2, s3) = state
    }

    public var state: (UInt64, UInt64, UInt64, UInt64) { (s0, s1, s2, s3) }

    @inlinable static func rotl(_ x: UInt64, _ k: UInt64) -> UInt64 { (x << k) | (x >> (64 - k)) }

    public mutating func next() -> UInt64 {
        let result = DeterministicRNG.rotl(s1 &* 5, 7) &* 9
        let t = s1 << 17
        s2 ^= s0; s3 ^= s1; s1 ^= s2; s0 ^= s3; s2 ^= t
        s3 = DeterministicRNG.rotl(s3, 45)
        return result
    }

    /// Uniform double in [0, 1).
    public mutating func nextUnit() -> Double { Double(next() >> 11) * (1.0 / 9007199254740992.0) }
}

public struct SplitMix64: Sendable {
    public var state: UInt64
    public init(state: UInt64) { self.state = state }
    public mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

/// Stable 64-bit hash of a string (FNV-1a). Used to turn level seeds like "GF-L1" into numbers.
public func stableHash(_ s: String) -> UInt64 {
    var h: UInt64 = 0xcbf29ce484222325
    for b in s.utf8 { h ^= UInt64(b); h = h &* 0x100000001b3 }
    return h
}
