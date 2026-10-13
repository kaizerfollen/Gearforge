// API stub of Apple's simd module (subset) for the Linux typecheck harness. SIMD2/3/4 themselves are standard
// library types; this adds the C-style typealiases and the free functions of <simd/geometry.h> & <simd/common.h>.
// The real module declares concrete overloads per vector type; these generic versions accept the same calls
// for floating-point vectors.

@inline(never) func _stub() -> Never { fatalError("simd stub: typecheck only") }

public typealias simd_float2 = SIMD2<Float>
public typealias simd_float3 = SIMD3<Float>
public typealias simd_float4 = SIMD4<Float>
public typealias simd_double2 = SIMD2<Double>
public typealias simd_double3 = SIMD3<Double>
public typealias simd_double4 = SIMD4<Double>
public typealias simd_int2 = SIMD2<Int32>
public typealias simd_int3 = SIMD3<Int32>
public typealias simd_int4 = SIMD4<Int32>
public typealias simd_uint2 = SIMD2<UInt32>
public typealias vector_float2 = simd_float2
public typealias vector_float3 = simd_float3
public typealias vector_float4 = simd_float4
public typealias vector_double2 = simd_double2
public typealias vector_int2 = simd_int2

public func length<V: SIMD>(_ x: V) -> V.Scalar where V.Scalar: BinaryFloatingPoint { _stub() }
public func length_squared<V: SIMD>(_ x: V) -> V.Scalar where V.Scalar: BinaryFloatingPoint { _stub() }
public func distance<V: SIMD>(_ x: V, _ y: V) -> V.Scalar where V.Scalar: BinaryFloatingPoint { _stub() }
public func distance_squared<V: SIMD>(_ x: V, _ y: V) -> V.Scalar where V.Scalar: BinaryFloatingPoint { _stub() }
public func normalize<V: SIMD>(_ x: V) -> V where V.Scalar: BinaryFloatingPoint { _stub() }
public func dot<V: SIMD>(_ x: V, _ y: V) -> V.Scalar where V.Scalar: BinaryFloatingPoint { _stub() }
public func cross(_ x: SIMD3<Float>, _ y: SIMD3<Float>) -> SIMD3<Float> { _stub() }
public func cross(_ x: SIMD3<Double>, _ y: SIMD3<Double>) -> SIMD3<Double> { _stub() }
public func mix<V: SIMD>(_ x: V, _ y: V, t: V.Scalar) -> V where V.Scalar: BinaryFloatingPoint { _stub() }
public func mix<V: SIMD>(_ x: V, _ y: V, t: V) -> V where V.Scalar: BinaryFloatingPoint { _stub() }
public func clamp<V: SIMD>(_ x: V, min: V.Scalar, max: V.Scalar) -> V where V.Scalar: BinaryFloatingPoint { _stub() }
public func clamp<V: SIMD>(_ x: V, min: V, max: V) -> V where V.Scalar: BinaryFloatingPoint { _stub() }
public func abs<V: SIMD>(_ x: V) -> V where V.Scalar: BinaryFloatingPoint { _stub() }
public func floor<V: SIMD>(_ x: V) -> V where V.Scalar: BinaryFloatingPoint { _stub() }
public func ceil<V: SIMD>(_ x: V) -> V where V.Scalar: BinaryFloatingPoint { _stub() }
public func round<V: SIMD>(_ x: V) -> V where V.Scalar: BinaryFloatingPoint { _stub() }

public func simd_length<V: SIMD>(_ x: V) -> V.Scalar where V.Scalar: BinaryFloatingPoint { _stub() }
public func simd_length_squared<V: SIMD>(_ x: V) -> V.Scalar where V.Scalar: BinaryFloatingPoint { _stub() }
public func simd_distance<V: SIMD>(_ x: V, _ y: V) -> V.Scalar where V.Scalar: BinaryFloatingPoint { _stub() }
public func simd_distance_squared<V: SIMD>(_ x: V, _ y: V) -> V.Scalar where V.Scalar: BinaryFloatingPoint { _stub() }
public func simd_normalize<V: SIMD>(_ x: V) -> V where V.Scalar: BinaryFloatingPoint { _stub() }
public func simd_dot<V: SIMD>(_ x: V, _ y: V) -> V.Scalar where V.Scalar: BinaryFloatingPoint { _stub() }
public func simd_mix<V: SIMD>(_ x: V, _ y: V, _ t: V) -> V where V.Scalar: BinaryFloatingPoint { _stub() }
public func simd_clamp<V: SIMD>(_ x: V, _ min: V, _ max: V) -> V where V.Scalar: BinaryFloatingPoint { _stub() }
public func simd_min<V: SIMD>(_ x: V, _ y: V) -> V where V.Scalar: Comparable { _stub() }
public func simd_max<V: SIMD>(_ x: V, _ y: V) -> V where V.Scalar: Comparable { _stub() }
