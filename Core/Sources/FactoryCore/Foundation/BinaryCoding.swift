// Gearforge — FactoryCore
// Compact little-endian binary serialization used by the save system.
// Every system serializes its own state through BinaryWriter/BinaryReader (see SaveFormat in Persistence/).

import Foundation

public enum BinaryCodingError: Error, CustomStringConvertible {
    case unexpectedEnd(at: Int, need: Int)
    case invalidValue(String)
    case badMagic
    case unsupportedVersion(Int)

    public var description: String {
        switch self {
        case .unexpectedEnd(let at, let need): return "Unexpected end of data at \(at) (need \(need) bytes)"
        case .invalidValue(let s): return "Invalid value: \(s)"
        case .badMagic: return "Not a Gearforge save file"
        case .unsupportedVersion(let v): return "Unsupported save version \(v)"
        }
    }
}

public struct BinaryWriter {
    public var bytes: [UInt8] = []
    public init(reserve: Int = 1 << 16) { bytes.reserveCapacity(reserve) }

    @inlinable public mutating func write<T: FixedWidthInteger>(_ v: T) {
        withUnsafeBytes(of: v.littleEndian) { bytes.append(contentsOf: $0) }
    }
    public mutating func write(_ v: Bool) { bytes.append(v ? 1 : 0) }
    public mutating func write(_ v: Double) { write(v.bitPattern) }
    public mutating func write(_ v: Float) { write(v.bitPattern) }
    public mutating func write(_ s: String) {
        let u = Array(s.utf8)
        writeVarInt(u.count)
        bytes.append(contentsOf: u)
    }
    public mutating func write(_ p: TilePos) { write(p.x); write(p.y) }
    public mutating func write(_ v: Vec2) { write(v.x); write(v.y) }
    public mutating func writeBytes(_ b: [UInt8]) { writeVarInt(b.count); bytes.append(contentsOf: b) }
    public mutating func writeRaw(_ b: [UInt8]) { bytes.append(contentsOf: b) }

    /// LEB128 unsigned var-int (for counts and small numbers).
    public mutating func writeVarInt(_ v: Int) {
        precondition(v >= 0)
        var x = UInt64(v)
        repeat {
            var byte = UInt8(x & 0x7F)
            x >>= 7
            if x != 0 { byte |= 0x80 }
            bytes.append(byte)
        } while x != 0
    }

    public mutating func writeArray<T>(_ a: [T], _ body: (inout BinaryWriter, T) -> Void) {
        writeVarInt(a.count)
        for e in a { body(&self, e) }
    }

    /// Writes a length-prefixed section so readers can skip unknown sections (forward compatibility).
    public mutating func writeSection(tag: UInt32, _ body: (inout BinaryWriter) -> Void) {
        write(tag)
        var inner = BinaryWriter(reserve: 1024)
        body(&inner)
        write(UInt32(inner.bytes.count))
        bytes.append(contentsOf: inner.bytes)
    }

    public var data: Data { Data(bytes) }
}

public struct BinaryReader {
    public let bytes: [UInt8]
    public private(set) var offset: Int = 0

    public init(_ bytes: [UInt8]) { self.bytes = bytes }
    public init(_ data: Data) { self.bytes = [UInt8](data) }

    public var isAtEnd: Bool { offset >= bytes.count }
    public var remaining: Int { bytes.count - offset }

    @inline(__always) mutating func need(_ n: Int) throws {
        if offset + n > bytes.count { throw BinaryCodingError.unexpectedEnd(at: offset, need: n) }
    }

    public mutating func read<T: FixedWidthInteger>(_: T.Type = T.self) throws -> T {
        let n = MemoryLayout<T>.size
        try need(n)
        var v: T = 0
        for i in 0..<n { v |= T(truncatingIfNeeded: bytes[offset + i]) << (8 * i) }
        offset += n
        return v
    }
    public mutating func readBool() throws -> Bool { try read(UInt8.self) != 0 }
    public mutating func readDouble() throws -> Double { Double(bitPattern: try read(UInt64.self)) }
    public mutating func readFloat() throws -> Float { Float(bitPattern: try read(UInt32.self)) }
    public mutating func readString() throws -> String {
        let n = try readVarInt()
        try need(n)
        let s = String(decoding: bytes[offset..<offset + n], as: UTF8.self)
        offset += n
        return s
    }
    public mutating func readTilePos() throws -> TilePos { TilePos(try read(Int32.self), try read(Int32.self)) }
    public mutating func readVec2() throws -> Vec2 { Vec2(try readDouble(), try readDouble()) }
    public mutating func readBytes() throws -> [UInt8] {
        let n = try readVarInt()
        try need(n)
        let b = Array(bytes[offset..<offset + n])
        offset += n
        return b
    }
    public mutating func readRaw(_ n: Int) throws -> [UInt8] {
        try need(n)
        let b = Array(bytes[offset..<offset + n]); offset += n; return b
    }
    public mutating func readVarInt() throws -> Int {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while true {
            let b = try read(UInt8.self)
            result |= UInt64(b & 0x7F) << shift
            if b & 0x80 == 0 { break }
            shift += 7
            if shift > 63 { throw BinaryCodingError.invalidValue("varint overflow") }
        }
        return Int(result)
    }
    public mutating func readArray<T>(_ body: (inout BinaryReader) throws -> T) throws -> [T] {
        let n = try readVarInt()
        if n > remaining { throw BinaryCodingError.invalidValue("array count \(n) exceeds data") }
        var out: [T] = []
        out.reserveCapacity(n)
        for _ in 0..<n { out.append(try body(&self)) }
        return out
    }
    /// Reads a section written by `writeSection`. Returns (tag, sub-reader).
    public mutating func readSection() throws -> (tag: UInt32, reader: BinaryReader) {
        let tag = try read(UInt32.self)
        let len = Int(try read(UInt32.self))
        try need(len)
        let sub = BinaryReader(Array(bytes[offset..<offset + len]))
        offset += len
        return (tag, sub)
    }
}

/// Types that save/load themselves in binary form.
public protocol BinarySerializable {
    func serialize(to w: inout BinaryWriter)
    init(from r: inout BinaryReader) throws
}
