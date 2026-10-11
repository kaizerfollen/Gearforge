// Gearforge — FactoryCore
// Save slots on disk: manual saves, rotating autosaves, background quick-save; metadata listing without loading.
// Owner: Progression engineer. STUB — keep the public API (the app calls it).

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
}

/// Optional compression hook supplied by the app (LZFSE on Apple platforms).
public protocol SaveCompressor: Sendable {
    func compress(_ bytes: [UInt8]) -> [UInt8]
    func decompress(_ bytes: [UInt8]) throws -> [UInt8]
}

public final class SaveManager {
    public let directory: URL
    public var compressor: SaveCompressor?

    public init(directory: URL, compressor: SaveCompressor? = nil) {
        self.directory = directory
        self.compressor = compressor
    }

    public func listSaves() -> [SaveMetadata] { [] }
    public var mostRecent: SaveMetadata? { listSaves().max { $0.savedAt < $1.savedAt } }
    @discardableResult
    public func save(_ session: GameSession, slot: String, displayName: String? = nil, thumbnailPNG: Data? = nil) throws -> SaveMetadata {
        throw BinaryCodingError.invalidValue("not implemented")
    }
    public func load(slot: String) throws -> GameSession { throw BinaryCodingError.invalidValue("not implemented") }
    /// Writes the next rotating autosave slot (autosave_1...N).
    @discardableResult
    public func autosave(_ session: GameSession, slots: Int) throws -> SaveMetadata { throw BinaryCodingError.invalidValue("not implemented") }
    public func delete(slot: String) throws {}
    public func rename(slot: String, to newName: String) throws {}
    public func duplicate(slot: String, as newSlot: String) throws {}
}
