// Gearforge — FactoryCore
// A running game: world + mode (campaign level / freeplay) + objective state + play time. The app talks to this.
// Fixed-timestep driver, save/load, autosave scheduling. Owner: Progression engineer. STUB — keep the public API.

import Foundation

public enum GameMode: Codable, Equatable, Sendable {
    case campaign(levelID: String)
    case freeplay
}

public final class GameSession {
    public let world: World
    public let mode: GameMode
    /// Real seconds played (for save metadata).
    public private(set) var playTime: Double = 0
    public var isPaused = false
    /// Simulation speed multiplier (1 = 60 UPS).
    public var speed: Double = 1

    public init(world: World, mode: GameMode) {
        self.world = world
        self.mode = mode
    }

    /// Creates a new freeplay game.
    public static func newFreeplay(settings: WorldSettings) -> GameSession {
        GameSession(world: World(settings: settings), mode: .freeplay)
    }

    /// Creates a new campaign game for a level.
    public static func newCampaign(level: LevelDefinition) -> GameSession {
        GameSession(world: World(settings: level.settings), mode: .campaign(levelID: level.id))
    }

    /// Advances the simulation by real time `dt` seconds using a fixed 60 Hz step; runs at most `maxTicks` ticks
    /// (prevents spiral of death). Returns ticks run.
    @discardableResult
    public func advance(realSeconds dt: Double, maxTicks: Int = 4) -> Int { 0 }
}
