// Gearforge — FactoryCore
// On-disk save file container (docs/team/progression.md §File format):
//
//   offset 0   "GFSV"                       magic
//          4   UInt32 formatVersion         version of the writer
//          8   UInt32 minReaderVersion      oldest reader that can load this file (additive changes keep it at 1)
//         12   UInt32 flags                 reserved (0)
//         16   section META                 SaveMetadata (no thumbnail) — read by listSaves()
//              section THMB  (optional)     thumbnail PNG bytes
//              section WRLD                 encoding u8 | rawLength u64 | crc32 u32 | stored payload
//              ...unknown sections are skipped
//
// Each section = tag u32 (four ASCII chars) | length u32 | body. The world payload (see WorldCodec) is itself a
// list of sections, so newer versions can add/skip data without breaking older readers.
// Owner: Progression engineer.

import Foundation

/// Errors thrown by the save system. Loading never traps on bad data — it throws one of these.
public enum SaveError: Error, Equatable, CustomStringConvertible {
    case notFound(String)
    case slotExists(String)
    case invalidName(String)
    case badMagic
    case unsupportedVersion(file: Int, reader: Int)
    case truncated(String)
    case checksumMismatch
    case missingSection(String)
    case corruptSection(String, String)
    case compressorRequired
    case decompressionFailed(String)
    case incompatibleGameData(String)
    case io(String)

    public var description: String {
        switch self {
        case .notFound(let s): return "Save '\(s)' not found"
        case .slotExists(let s): return "A save named '\(s)' already exists"
        case .invalidName(let s): return "Invalid save name '\(s)'"
        case .badMagic: return "Not a Gearforge save file"
        case .unsupportedVersion(let f, let r): return "Save needs a newer game version (file v\(f), this game reads v\(r))"
        case .truncated(let s): return "Save file is truncated (\(s))"
        case .checksumMismatch: return "Save file is corrupted (checksum mismatch)"
        case .missingSection(let s): return "Save file is missing section \(s)"
        case .corruptSection(let s, let why): return "Save section \(s) is corrupted: \(why)"
        case .compressorRequired: return "Save is compressed but no decompressor is available"
        case .decompressionFailed(let s): return "Save decompression failed: \(s)"
        case .incompatibleGameData(let s): return "Save was made with incompatible game data: \(s)"
        case .io(let s): return "File error: \(s)"
        }
    }
}

/// Parsed file header + sections (world payload still in stored — possibly compressed — form).
public struct ParsedSaveFile {
    public var formatVersion: Int
    public var minReaderVersion: Int
    public var metadata: SaveMetadata
    public var worldEncoding: UInt8
    public var worldRawLength: Int
    public var worldCRC: UInt32
    public var worldStored: [UInt8]
}

public enum SaveFile {
    public static let magic: [UInt8] = Array("GFSV".utf8)
    /// Current writer version. Bump when the layout changes; keep `minReaderVersion` unless old readers would
    /// misinterpret the file (they skip unknown sections, so additive changes don't need a bump of it).
    public static let formatVersion = 1
    public static let minReaderVersion = 1
    static let headerSize = 16
    /// Sanity caps so corrupt length fields can't make us allocate gigabytes.
    static let maxMetadataBytes = 1 << 20
    static let maxThumbnailBytes = 16 << 20

    static let tagMeta = fourCC("META")
    static let tagThumb = fourCC("THMB")
    static let tagWorld = fourCC("WRLD")

    public enum WorldEncoding: UInt8 { case raw = 0, compressed = 1 }

    // MARK: Writing

    /// Builds a complete save file from a world payload (see `WorldCodec.encode`). Applies the compressor (if any)
    /// to the world payload only, and checksums the stored bytes. Pure function: safe on any thread.
    public static func assemble(metadata: SaveMetadata, worldPayload: [UInt8], compressor: SaveCompressor?) -> [UInt8] {
        var stored = worldPayload
        var encoding = WorldEncoding.raw
        if let c = compressor {
            let packed = c.compress(worldPayload)
            if !packed.isEmpty, packed.count < worldPayload.count { stored = packed; encoding = .compressed }
        }
        let crc = CRC32.checksum(stored)
        var w = BinaryWriter(reserve: stored.count + 4096 + (metadata.thumbnailPNG?.count ?? 0))
        w.writeRaw(magic)
        w.write(UInt32(formatVersion))
        w.write(UInt32(minReaderVersion))
        w.write(UInt32(0))
        w.writeSection(tag: tagMeta) { encodeMetadata(metadata, into: &$0) }
        if let png = metadata.thumbnailPNG, !png.isEmpty {
            w.writeSection(tag: tagThumb) { $0.writeRaw([UInt8](png)) }
        }
        // WRLD is written by hand (not writeSection) to avoid copying a multi-MB payload through a temp writer.
        w.write(tagWorld)
        w.write(UInt32(1 + 8 + 4 + stored.count))
        w.write(encoding.rawValue)
        w.write(UInt64(worldPayload.count))
        w.write(crc)
        w.writeRaw(stored)
        return w.bytes
    }

    static func encodeMetadata(_ m: SaveMetadata, into w: inout BinaryWriter) {
        w.write(UInt8(1))                       // metadata layout version (append fields; never reorder)
        w.write(m.displayName)
        encodeMode(m.mode, into: &w)
        w.write(m.levelTitle != nil)
        if let t = m.levelTitle { w.write(t) }
        w.write(m.playTimeSeconds)
        w.write(m.gameTick)
        w.write(m.savedAt.timeIntervalSince1970)
        w.write(m.isAutosave)
        w.write(Int32(clamping: m.mapWidth))
        w.write(Int32(clamping: m.mapHeight))
        w.write(m.seed)
    }

    static func decodeMetadata(_ r: inout BinaryReader, slot: String, formatVersion: Int) throws -> SaveMetadata {
        let v = try r.read(UInt8.self)
        guard v >= 1 else { throw SaveError.corruptSection("META", "version \(v)") }
        let name = try r.readBoundedString(maxBytes: 4096)
        let mode = try decodeMode(&r)
        let title: String? = try r.readBool() ? try r.readBoundedString(maxBytes: 4096) : nil
        let play = try r.readDouble()
        let tick = try r.read(UInt64.self)
        let saved = try r.readDouble()
        let auto = try r.readBool()
        let mw = Int(try r.read(Int32.self)), mh = Int(try r.read(Int32.self))
        let seed = try r.read(UInt64.self)
        guard play.isFinite, saved.isFinite else { throw SaveError.corruptSection("META", "non-finite time") }
        return SaveMetadata(slot: slot, displayName: name, mode: mode, levelTitle: title, playTimeSeconds: play,
                            gameTick: tick, savedAt: Date(timeIntervalSince1970: saved), isAutosave: auto,
                            formatVersion: formatVersion, thumbnailPNG: nil, mapWidth: mw, mapHeight: mh, seed: seed)
    }

    static func encodeMode(_ m: GameMode, into w: inout BinaryWriter) {
        switch m {
        case .freeplay: w.write(UInt8(0))
        case .campaign(let id): w.write(UInt8(1)); w.write(id)
        }
    }

    static func decodeMode(_ r: inout BinaryReader) throws -> GameMode {
        switch try r.read(UInt8.self) {
        case 0: return .freeplay
        case 1: return .campaign(levelID: try r.readBoundedString(maxBytes: 256))
        case let k: throw BinaryCodingError.invalidValue("game mode \(k)")
        }
    }

    // MARK: Reading

    static func checkHeader(_ bytes: ArraySlice<UInt8>) throws -> (version: Int, minReader: Int) {
        guard bytes.count >= headerSize else {
            if bytes.count >= 4, Array(bytes.prefix(4)) != magic { throw SaveError.badMagic }
            throw SaveError.truncated("header")
        }
        guard Array(bytes.prefix(4)) == magic else { throw SaveError.badMagic }
        var r = BinaryReader(Array(bytes.prefix(headerSize)))
        _ = try r.readRaw(4)
        let version = Int(try r.read(UInt32.self))
        let minReader = Int(try r.read(UInt32.self))
        guard minReader <= formatVersion else { throw SaveError.unsupportedVersion(file: version, reader: formatVersion) }
        return (version, minReader)
    }

    /// Parses a complete save file in memory. Verifies structure; does not decompress or checksum the payload.
    public static func parse(_ bytes: [UInt8], slot: String) throws -> ParsedSaveFile {
        let (version, minReader) = try checkHeader(bytes[...])
        var r = BinaryReader(bytes)
        _ = try r.readRaw(headerSize)
        var meta: SaveMetadata?
        var thumb: Data?
        while !r.isAtEnd {
            guard r.remaining >= 8 else { throw SaveError.truncated("section header") }
            let tag = try r.read(UInt32.self)
            let len = Int(try r.read(UInt32.self))
            guard len <= r.remaining else { throw SaveError.truncated("section \(fourCCString(tag))") }
            switch tag {
            case tagMeta:
                var sub = BinaryReader(try r.readRaw(len))
                do { meta = try decodeMetadata(&sub, slot: slot, formatVersion: version) }
                catch let e as SaveError { throw e }
                catch { throw SaveError.corruptSection("META", "\(error)") }
            case tagThumb:
                thumb = Data(try r.readRaw(len))
            case tagWorld:
                guard var m = meta else { throw SaveError.missingSection("META") }
                guard len >= 13 else { throw SaveError.corruptSection("WRLD", "too short") }
                let enc = try r.read(UInt8.self)
                let rawLen = try r.read(UInt64.self)
                let crc = try r.read(UInt32.self)
                let stored = try r.readRaw(len - 13)
                guard rawLen <= UInt64(Int32.max) else { throw SaveError.corruptSection("WRLD", "length \(rawLen)") }
                m.thumbnailPNG = thumb
                return ParsedSaveFile(formatVersion: version, minReaderVersion: minReader, metadata: m,
                                      worldEncoding: enc, worldRawLength: Int(rawLen), worldCRC: crc, worldStored: stored)
            default:
                _ = try r.readRaw(len)      // unknown section from a newer version: skip
            }
        }
        if meta == nil { throw SaveError.missingSection("META") }
        throw SaveError.missingSection("WRLD")
    }

    /// Verifies the checksum and returns the decompressed world payload.
    public static func worldPayload(_ p: ParsedSaveFile, compressor: SaveCompressor?) throws -> [UInt8] {
        guard CRC32.checksum(p.worldStored) == p.worldCRC else { throw SaveError.checksumMismatch }
        switch WorldEncoding(rawValue: p.worldEncoding) {
        case .raw?:
            guard p.worldStored.count == p.worldRawLength else { throw SaveError.corruptSection("WRLD", "length mismatch") }
            return p.worldStored
        case .compressed?:
            guard let c = compressor else { throw SaveError.compressorRequired }
            let out: [UInt8]
            do { out = try c.decompress(p.worldStored) } catch { throw SaveError.decompressionFailed("\(error)") }
            guard out.count == p.worldRawLength else { throw SaveError.decompressionFailed("length mismatch") }
            return out
        case nil:
            throw SaveError.corruptSection("WRLD", "unknown encoding \(p.worldEncoding)")
        }
    }

    /// Reads only the header + metadata (+ thumbnail) from disk — never the world payload. Used by listSaves().
    public static func readMetadata(at url: URL, slot: String, includeThumbnail: Bool) throws -> SaveMetadata {
        let fh: FileHandle
        do { fh = try FileHandle(forReadingFrom: url) } catch { throw SaveError.notFound(slot) }
        defer { try? fh.close() }
        func read(_ n: Int, _ what: String) throws -> [UInt8] {
            guard let d = try fh.read(upToCount: n), d.count == n else { throw SaveError.truncated(what) }
            return [UInt8](d)
        }
        let head = try read(headerSize, "header")
        let (version, _) = try checkHeader(head[...])
        var offset = UInt64(headerSize)
        var meta: SaveMetadata?
        for _ in 0..<16 {                       // META/THMB come first; stop at WRLD
            var hr = BinaryReader(try read(8, "section header"))
            let tag = try hr.read(UInt32.self)
            let len = Int(try hr.read(UInt32.self))
            offset += 8
            switch tag {
            case tagMeta:
                guard len <= maxMetadataBytes else { throw SaveError.corruptSection("META", "length \(len)") }
                var r = BinaryReader(try read(len, "metadata"))
                do { meta = try decodeMetadata(&r, slot: slot, formatVersion: version) }
                catch let e as SaveError { throw e }
                catch { throw SaveError.corruptSection("META", "\(error)") }
            case tagThumb where includeThumbnail:
                guard len <= maxThumbnailBytes else { throw SaveError.corruptSection("THMB", "length \(len)") }
                meta?.thumbnailPNG = Data(try read(len, "thumbnail"))
            case tagWorld:
                guard let m = meta else { throw SaveError.missingSection("META") }
                return m
            default:
                break
            }
            offset += UInt64(len)
            try fh.seek(toOffset: offset)
        }
        guard let m = meta else { throw SaveError.missingSection("META") }
        return m
    }
}
