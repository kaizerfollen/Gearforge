// Gearforge — App
// The single bridge between SwiftUI (HUD/screens), SpriteKit (GameScene) and FactoryCore.
// Owner: Rendering engineer (implementation). UI engineer consumes the published state & methods below.
// SKELETON — signatures agreed by Lead; extend freely but do not rename what is here.

import Foundation
import Observation
import FactoryCore

/// Current interaction mode (GDD §4.1).
public enum InteractionMode: Equatable {
    case explore
    case build(item: Int)          // item with a place result or tile
    case remove
    case paste
    case map
}

/// Lightweight snapshot for the HUD, refreshed at ~10 Hz.
public struct HUDState: Equatable {
    public var powerSatisfaction: Double = 1      // network under the character
    public var researchTech: Int = -1
    public var researchProgress: Double = 0
    public var craftQueue: [CraftQueueEntryView] = []
    public var alerts: [String] = []
    public var objectiveTitle: String? = nil
    public var objectiveProgress: String? = nil
    public var fps: Int = 0
    public var ups: Int = 0
    public init() {}
}

public struct CraftQueueEntryView: Equatable, Identifiable {
    public var id: Int
    public var recipe: Int
    public var count: Int
    public var progress: Double
}

@MainActor
@Observable
public final class GameController {
    public private(set) var session: GameSession
    public var world: World { session.world }

    // Interaction state
    public var mode: InteractionMode = .explore
    public var buildDirection: Direction = .north
    public var selected: EntityHandle? = nil
    /// Entity whose screen is open (inventory/machine GUI), if any.
    public var openedEntity: EntityHandle? = nil
    /// Quickbar: 2 pages × 10 slots of item indices (-1 empty).
    public var quickbar: [Int] = Array(repeating: -1, count: 20)
    public var quickbarPage: Int = 0
    public var hud = HUDState()
    /// Incremented whenever player inventory/crafting changed (UI refresh trigger).
    public var inventoryRevision: Int = 0
    public var lastError: PlacementError? = nil

    public init(session: GameSession) {
        self.session = session
    }

    /// Called by GameScene every frame with the real frame delta. Advances the simulation and refreshes HUD state.
    public func frame(dt: Double) {
        session.advance(realSeconds: dt)
    }

    /// Executes a player command and records any error for the UI.
    @discardableResult
    public func execute(_ cmd: PlayerCommand) -> CommandResult {
        let r = world.execute(cmd)
        if case .failed(let e) = r { lastError = e } else { lastError = nil }
        inventoryRevision &+= 1
        return r
    }
}
