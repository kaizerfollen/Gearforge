// Gearforge — FactoryCore
// Bulk (memcpy-speed) array helpers on top of BinaryWriter/BinaryReader, plus CRC-32 and four-character section
// tags. Used by the save format for large raw arrays (chunk tiles, entity record columns, statistics rings).
// Owner: Progression engineer.

import Foundation

/// True on every platform Gearforge ships on (arm64 / x86_64). Big-endian hosts take the slow, portable path.
@usableFromInline let hostIsLittleEndian: Bool = 1.littleEndian == 1

/// Packs a four-character ASCII code ("SURF") into a little-endian UInt32 section tag.
@inlinable public func fourCC(_ s: StaticString) -> UInt32 {
    precondition(s.utf8CodeUnitCount == 4, "section tags are exactly four ASCII characters")
    let p = s.utf8Start
    return UInt32(p[0]) | UInt32(p[1]) << 8 | UInt32(p[2]) << 16 | UInt32(p[3]) << 24
}

/// Human-readable form of a section tag (diagnostics / error messages).
public func fourCCString(_ tag: UInt32) -> String {
    let b = [UInt8(tag & 0xFF), UInt8(tag >> 8 & 0xFF), UInt8(tag >> 16 & 0xFF), UInt8(tag >> 24 & 0xFF)]
    if b.allSatisfy({ $0 >= 0x20 && $0 < 0x7F }) { return String(decoding: b, as: UTF8.self) }
    return String(format: "0x%08X", tag)
}

public extension BinaryWriter {
    /// Writes a var-int count followed by the raw little-endian elements.
    mutating func writePODArray<T: FixedWidthInteger>(_ a: [T]) {
        writeVarInt(a.count)
        writePODElements(a)
    }

    /// Writes the raw little-endian elements without a count (caller knows the length).
    mutating func writePODElements<T: FixedWidthInteger>(_ a: [T]) {
        if hostIsLittleEndian {
            a.withUnsafeBytes { bytes.append(contentsOf: $0) }
        } else {
            for v in a { write(v) }
        }
    }

    /// Writes a Float array as raw IEEE-754 bit patterns (count-prefixed).
    mutating func writeFloatArray(_ a: [Float]) {
        writeVarInt(a.count)
        if hostIsLittleEndian {
            a.withUnsafeBytes { bytes.append(contentsOf: $0) }
        } else {
            for v in a { write(v.bitPattern) }
        }
    }

    /// Writes an array that is often uniform (all one value) compactly: tag 0 = uniform value, tag 1 = raw.
    /// Used for chunk layers (resources are mostly empty, occupancy mostly -1).
    mutating func writeCompactPODArray<T: FixedWidthInteger>(_ a: [T]) {
        writeVarInt(a.count)
        if let first = a.first, a.allSatisfy({ $0 == first }) {
            write(UInt8(0)); write(first)
        } else {
            write(UInt8(1)); writePODElements(a)
        }
    }
}

public extension BinaryReader {
    /// Reads `count` raw little-endian elements (no count prefix). Throws on truncation.
    mutating func readPODElements<T: FixedWidthInteger>(_: T.Type, count n: Int) throws -> [T] {
        let size = MemoryLayout<T>.size
        guard n >= 0, n <= remaining / size else {
            throw BinaryCodingError.unexpectedEnd(at: offset, need: n &* size)
        }
        if n == 0 { return [] }
        let raw = try readRaw(n * size)
        var out = [T](repeating: 0, count: n)
        out.withUnsafeMutableBytes { dst in raw.withUnsafeBytes { src in dst.copyMemory(from: src) } }
        if !hostIsLittleEndian { for i in 0..<n { out[i] = T(littleEndian: out[i]) } }
        return out
    }

    /// Reads an array written by `writePODArray`. When `expectedCount` is given, any other length throws.
    mutating func readPODArray<T: FixedWidthInteger>(_ t: T.Type, expectedCount: Int? = nil) throws -> [T] {
        let n = try readVarInt()
        if let e = expectedCount, n != e { throw BinaryCodingError.invalidValue("array length \(n), expected \(e)") }
        return try readPODElements(t, count: n)
    }

    mutating func readFloatArray(expectedCount: Int? = nil) throws -> [Float] {
        let bits = try readPODArray(UInt32.self, expectedCount: expectedCount)
        return bits.map { Float(bitPattern: $0) }
    }

    /// Reads an array written by `writeCompactPODArray`.
    mutating func readCompactPODArray<T: FixedWidthInteger>(_ t: T.Type, expectedCount: Int? = nil) throws -> [T] {
        let n = try readVarInt()
        if let e = expectedCount, n != e { throw BinaryCodingError.invalidValue("array length \(n), expected \(e)") }
        switch try read(UInt8.self) {
        case 0:
            let v = try read(T.self)
            guard n <= 1 << 24 else { throw BinaryCodingError.invalidValue("uniform array too large (\(n))") }
            return [T](repeating: v, count: n)
        case 1:
            return try readPODElements(t, count: n)
        case let m:
            throw BinaryCodingError.invalidValue("unknown array encoding \(m)")
        }
    }

    /// Reads a string, rejecting absurd lengths (corrupt data) before allocating.
    mutating func readBoundedString(maxBytes: Int = 1 << 20) throws -> String {
        let s = try readString()
        if s.utf8.count > maxBytes { throw BinaryCodingError.invalidValue("string too long") }
        return s
    }
}

/// CRC-32 (IEEE 802.3, reflected, poly 0xEDB88320) — slicing-by-8 for throughput on multi-MB save payloads.
public enum CRC32 {
    private static let tables: [[UInt32]] = {
        var t = [[UInt32]](repeating: [UInt32](repeating: 0, count: 256), count: 8)
        for i in 0..<256 {
            var c = UInt32(i)
            for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
            t[0][i] = c
        }
        for i in 0..<256 {
            for k in 1..<8 { t[k][i] = (t[k - 1][i] >> 8) ^ t[0][Int(t[k - 1][i] & 0xFF)] }
        }
        return t
    }()
    private static let flat: [UInt32] = tables.flatMap { $0 }

    public static func checksum(_ bytes: [UInt8]) -> UInt32 {
        bytes.withUnsafeBufferPointer { checksum($0) }
    }

    public static func checksum(_ buf: UnsafeBufferPointer<UInt8>) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        flat.withUnsafeBufferPointer { t in
            var i = 0
            let n = buf.count
            while i + 8 <= n {
                let one = (UInt32(buf[i]) | UInt32(buf[i + 1]) << 8 | UInt32(buf[i + 2]) << 16 | UInt32(buf[i + 3]) << 24) ^ crc
                let two = UInt32(buf[i + 4]) | UInt32(buf[i + 5]) << 8 | UInt32(buf[i + 6]) << 16 | UInt32(buf[i + 7]) << 24
                crc = t[7 * 256 + Int(one & 0xFF)] ^ t[6 * 256 + Int((one >> 8) & 0xFF)]
                    ^ t[5 * 256 + Int((one >> 16) & 0xFF)] ^ t[4 * 256 + Int(one >> 24)]
                    ^ t[3 * 256 + Int(two & 0xFF)] ^ t[2 * 256 + Int((two >> 8) & 0xFF)]
                    ^ t[1 * 256 + Int((two >> 16) & 0xFF)] ^ t[Int(two >> 24)]
                i += 8
            }
            while i < n {
                crc = t[Int((crc ^ UInt32(buf[i])) & 0xFF)] ^ (crc >> 8)
                i += 1
            }
        }
        return crc ^ 0xFFFF_FFFF
    }
}
