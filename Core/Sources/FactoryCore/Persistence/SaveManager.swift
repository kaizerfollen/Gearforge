// Gearforge — FactoryCore
// Save slots: named manual saves, rotating autosaves, background save, metadata listing without loading the world,
// atomic writes, crash-recovery marker (GDD §11). Owner: Progression engineer.

import Foundation

public struct SaveMetadata: Codable, Equatable, Sendable, Identifiable {
    public var id: String { slot }
    public var slot: String                 // file stem, e.g. "My factory", "autosave_1", "background"
    public var displayName: String
    public var mode: GameMode
    public var levelTitle: String?
    public var playTimeSeconds: Double
    public var gameTick: UInt64
    public var savedAt: Date
    public var isAutosave: Bool
    public var formatVersion: Int
    public var thumbnailPNG: Data?
    public var mapWidth: Int = 0
    public var mapHeight: Int = 0
    public var seed: UInt64 = 0
}

/// Optional compression hook supplied by the app (LZFSE on Apple platforms).
public protocol SaveCompressor: Sendable {
    func compress(_ bytes: [UInt8]) -> [UInt8]
    func decompress(_ bytes: [UInt8]) throws -> [UInt8]
}

public final class SaveManager {
    public let directory: URL
    public var compressor: SaveCompressor?
    public static let fileExtension = "gfsave"
    public static let backgroundSlot = "background"
    private var lockURL: URL { directory.appendingPathComponent(".session.lock") }

    public init(directory: URL, compressor: SaveCompressor? = nil) {
        self.directory = directory
        self.compressor = compressor
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Thumbnail PNG of a save slot (nil if none) — reads only the file header sections.
    public func thumbnail(slot: String) -> Data? {
        (try? SaveFile.readMetadata(at: url(for: slot), slot: slot, includeThumbnail: true))?.thumbnailPNG
    }

    public func url(for slot: String) -> URL { directory.appendingPathComponent(slot).appendingPathExtension(Self.fileExtension) }

    /// Valid manual slot name: non-empty, no path separators, ≤ 64 characters.
    public static func isValidName(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces)
        return !t.isEmpty && t.count <= 64 && !t.contains("/") && !t.contains("\\") && !t.hasPrefix(".") && !t.contains(":")
    }

    /// All saves, newest first (metadata only — fast).
    public func listSaves(includeThumbnails: Bool = false) -> [SaveMetadata] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        var out: [SaveMetadata] = []
        for f in files where f.pathExtension == Self.fileExtension {
            let slot = f.deletingPathExtension().lastPathComponent
            if let m = try? SaveFile.readMetadata(at: f, slot: slot, includeThumbnail: includeThumbnails) { out.append(m) }
        }
        return out.sorted { $0.savedAt > $1.savedAt }
    }

    public var mostRecent: SaveMetadata? { listSaves().first }

    /// Serializes on the calling thread (main), returning bytes that can be written from any thread.
    public func snapshot(_ session: GameSession, slot: String, displayName: String? = nil, isAutosave: Bool = false,
                         thumbnailPNG: Data? = nil) -> (SaveMetadata, [UInt8]) {
        let meta = session.makeMetadata(slot: slot, displayName: displayName ?? slot, isAutosave: isAutosave, thumbnail: thumbnailPNG)
        return (meta, SaveFile.assemble(metadata: meta, worldPayload: session.encodePayload(), compressor: compressor))
    }

    /// Atomic file write (temp + rename). Safe to call from a background thread.
    public func write(_ bytes: [UInt8], slot: String) throws {
        do { try Data(bytes).write(to: url(for: slot), options: .atomic) } catch { throw SaveError.io("\(error)") }
    }

    @discardableResult
    public func save(_ session: GameSession, slot: String, displayName: String? = nil, thumbnailPNG: Data? = nil) throws -> SaveMetadata {
        guard slot == Self.backgroundSlot || slot.hasPrefix("autosave_") || Self.isValidName(slot) else { throw SaveError.invalidName(slot) }
        let (meta, bytes) = snapshot(session, slot: slot, displayName: displayName, isAutosave: slot.hasPrefix("autosave_"), thumbnailPNG: thumbnailPNG)
        try write(bytes, slot: slot)
        return meta
    }

    public func load(slot: String) throws -> GameSession {
        try GameSession.load(from: url(for: slot), compressor: compressor)
    }

    /// Rotating autosave: writes to the first missing `autosave_k` (k = 1...slots) or the oldest one.
    @discardableResult
    public func autosave(_ session: GameSession, slots: Int, thumbnailPNG: Data? = nil) throws -> SaveMetadata {
        let slot = nextAutosaveSlot(slots: slots)
        let m = try save(session, slot: slot, displayName: "Autosave", thumbnailPNG: thumbnailPNG)
        session.didAutosave()
        return m
    }

    public func nextAutosaveSlot(slots: Int) -> String {
        let n = max(1, slots)
        var oldest: (String, Date)? = nil
        for k in 1...n {
            let s = "autosave_\(k)"
            guard let m = try? SaveFile.readMetadata(at: url(for: s), slot: s, includeThumbnail: false) else { return s }
            if oldest == nil || m.savedAt < oldest!.1 { oldest = (s, m.savedAt) }
        }
        return oldest?.0 ?? "autosave_1"
    }

    public func delete(slot: String) throws {
        do { try FileManager.default.removeItem(at: url(for: slot)) } catch { throw SaveError.notFound(slot) }
    }

    public func rename(slot: String, to newName: String) throws {
        guard Self.isValidName(newName) else { throw SaveError.invalidName(newName) }
        guard !FileManager.default.fileExists(atPath: url(for: newName).path) else { throw SaveError.slotExists(newName) }
        do { try FileManager.default.moveItem(at: url(for: slot), to: url(for: newName)) } catch { throw SaveError.notFound(slot) }
    }

    public func duplicate(slot: String, as newSlot: String) throws {
        guard Self.isValidName(newSlot) else { throw SaveError.invalidName(newSlot) }
        guard !FileManager.default.fileExists(atPath: url(for: newSlot).path) else { throw SaveError.slotExists(newSlot) }
        do { try FileManager.default.copyItem(at: url(for: slot), to: url(for: newSlot)) } catch { throw SaveError.notFound(slot) }
    }

    // MARK: Crash recovery

    /// Call when a game session starts. If the previous session never ended cleanly, returns true.
    @discardableResult
    public func markSessionStarted() -> Bool {
        let unclean = FileManager.default.fileExists(atPath: lockURL.path)
        try? Data().write(to: lockURL)
        return unclean
    }
    /// Call after a clean save on exit / background.
    public func markSessionEnded() { try? FileManager.default.removeItem(at: lockURL) }
    public var hadUncleanExit: Bool { FileManager.default.fileExists(atPath: lockURL.path) }
}
