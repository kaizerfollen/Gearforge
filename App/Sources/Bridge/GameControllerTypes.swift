// Gearforge — App / Bridge
// Value types published by GameController for the SwiftUI HUD. Pure Swift (no UIKit) — all Equatable so SwiftUI
// only re-renders when something actually changed. Owner: Rendering engineer (UI engineer consumes).

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import FactoryCore

/// Current interaction mode (GDD §4.1).
public enum InteractionMode: Equatable {
    case explore
    case build(item: Int)          // item with a place result or tile
    case remove
    case paste
    case map

    public var isBuild: Bool { if case .build = self { return true }; return false }
    public var buildItem: Int? { if case .build(let i) = self { return i }; return nil }
}

/// Lightweight snapshot for the HUD, refreshed at ~10 Hz (assigned only when it changed).
public struct HUDState: Equatable {
    public var powerSatisfaction: Double = 1      // network under the character
    /// False when no electric network is near the character (hide the ⚡ readout).
    public var powerNearby: Bool = false
    public var researchTech: Int = -1
    public var researchProgress: Double = 0
    public var craftQueue: [CraftQueueEntryView] = []
    /// Recent alert messages from `WorldEvent.alert` (newest last, max 8).
    public var alerts: [String] = []
    /// Aggregated machine warnings (no fuel / no power / output full ...) from a background scan of all entities.
    public var statusAlerts: [StatusAlert] = []
    public var objectiveTitle: String? = nil
    public var objectiveProgress: String? = nil
    public var fps: Int = 0
    public var ups: Int = 0
    /// Game time (ticks) — for clocks/ETA.
    public var tick: UInt64 = 0
    /// 0...1 daylight (night tint indicator).
    public var daylight: Double = 1
    public var canUndo: Bool = false
    public var canRedo: Bool = false
    /// Hand-mining progress ring 0...1 (nil = not mining).
    public var handMiningProgress: Double? = nil
    public init() {}
}

public struct CraftQueueEntryView: Equatable, Identifiable {
    public var id: Int
    public var recipe: Int
    public var count: Int
    public var progress: Double
    public init(id: Int, recipe: Int, count: Int, progress: Double) {
        self.id = id; self.recipe = recipe; self.count = count; self.progress = progress
    }
}

/// Count of entities currently showing a warning status (HUD ⚠ panel). `example` lets the UI jump to one.
public struct StatusAlert: Equatable, Identifiable {
    public var id: UInt8 { status.rawValue }
    public var status: EntityStatus
    public var count: Int
    public var example: EntityHandle?
    public var text: String { EntityQuery.text(status) }
    public init(status: EntityStatus, count: Int, example: EntityHandle?) {
        self.status = status; self.count = count; self.example = example
    }
}

/// Info card for the selected entity (GDD §4.3), refreshed at ~10 Hz.
public struct SelectedInfo: Equatable {
    public var handle: EntityHandle
    public var proto: Int
    public var protoID: String
    public var name: String
    public var kind: EntityKind
    public var isGhost: Bool
    public var status: EntityStatus?
    public var statusText: String?
    /// Recipe index (-1 none) and its display name.
    public var recipe: Int
    public var recipeName: String?
    /// Crafting / mining / research progress 0...1 (nil when not applicable).
    public var progress: Double?
    /// Satisfaction of the entity's electric network (nil = not electric).
    public var power: Double?
    /// Fuel item currently burning / first fuel stack (nil = not a burner).
    public var fuelItem: Int?
    public var fuelCount: Int?
    public var health: Double
    public var maxHealth: Double
    /// Within the 10-tile reach (or casual reach): the entity screen can be opened.
    public var inReach: Bool
    public var direction: Direction
}

/// Actions offered by the long-press radial menu (GDD §4.3).
public enum RadialAction: String, CaseIterable, Identifiable, Sendable {
    case open, rotate, pipette, copySettings, pasteSettings, takeAll, remove, pickUpItems
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .open: return "Open"
        case .rotate: return "Rotate"
        case .pipette: return "Pipette"
        case .copySettings: return "Copy settings"
        case .pasteSettings: return "Paste settings"
        case .takeAll: return "Take all"
        case .remove: return "Remove"
        case .pickUpItems: return "Pick up items"
        }
    }
}

/// Request for the UI to show the radial menu at `screenPoint` (SKView / SwiftUI coordinates of the game view).
public struct RadialMenuRequest: Equatable, Identifiable {
    public var id: Int
    public var handle: EntityHandle
    public var screenPoint: CGPoint
    public var actions: [RadialAction]
}

/// Area removal that exceeds the confirmation threshold (GDD §4.5): UI shows "Remove N entities?".
public struct AreaRemovalRequest: Equatable, Identifiable {
    public var id: Int
    public var rect: TileRect
    public var count: Int
}

/// Transient notifications for toasts / banners.
public struct GameNotification: Equatable, Identifiable {
    public enum Kind: Equatable {
        case researchFinished(tech: Int)
        case researchStarted(tech: Int)
        case recipeUnlocked(recipe: Int)
        case objectiveCompleted(id: Int)
        case levelCompleted
        case rocketLaunched(withSatellite: Bool)
        case alert(String)
        case saved(slot: String)
        case saveFailed(String)
        case placementFailed(PlacementError)
    }
    public var id: Int
    public var kind: Kind
    public var message: String
    /// Game tick when posted.
    public var tick: UInt64
}

/// Ghost hint shown above the build preview (GDD §4.4).
public struct PlacementHint: Equatable {
    public enum Validity: Equatable { case valid, ghost, invalid }
    public var validity: Validity
    public var text: String?
    /// Number of entities a drag would place.
    public var count: Int
}
