// Gearforge — App / Bridge
// Adapter points for FactoryCore APIs that other engineers are adding in parallel (undo stack, placement check,
// craft queue, hand-mining progress, pole wires, objective tracker, autosave scheduling). The app ONLY calls these
// through `CoreAdapters`, so wiring a newly landed Core API is a one-line change here (see each TODO(merge)).
// Default implementations use nothing but the stub API that exists today, so this file always compiles.
// Pure Swift (FactoryCore + Foundation). Owner: Rendering engineer.

import Foundation
import FactoryCore

public enum CoreAdapters {
    // MARK: Reach constants (05_mechanics §12)

    public static let buildReach: Double = 10
    public static let resourceReach: Double = 2.7

    // MARK: Undo / redo  (Gameplay engineer: UndoStack in Commands)

    /// TODO(merge): `world.undoStack.canUndo` (or equivalent) once Commands/UndoStack lands.
    public static func canUndo(_ world: World) -> Bool { false }
    /// TODO(merge): `world.undoStack.canRedo`.
    public static func canRedo(_ world: World) -> Bool { false }
    /// TODO(merge): `world.undo()` / `world.undoStack.undo(world)`.
    public static func undo(_ world: World) -> CommandResult { .failed(.notAllowed) }
    /// TODO(merge): `world.redo()`.
    public static func redo(_ world: World) -> CommandResult { .failed(.notAllowed) }
    /// Groups the commands of one drag into a single undo step. TODO(merge): undoStack.beginGroup()/endGroup().
    public static func beginUndoGroup(_ world: World) {}
    public static func endUndoGroup(_ world: World) {}

    // MARK: Placement validation

    /// Full placement check used for the green/red ghost (does not check reach or inventory — the caller does).
    /// TODO(merge): replace the body with `world.placementCheck(proto:origin:direction:)` when Gameplay provides it.
    public static func placementError(_ world: World, proto: Int, origin: TilePos, direction: Direction) -> PlacementError? {
        if let e = world.canPlace(proto: proto, origin: origin, direction: direction) { return e }
        let p = world.db.entities[proto]
        if p.placement == "resource" || p.kind == .miningDrill {
            if !world.mining.hasMinableResource(proto: proto, origin: origin, direction: direction) { return .noResourceUnderDrill }
        }
        if p.placement == "shoreline" || p.kind == .offshorePump {
            // Needs water on the tile "behind" the pump (opposite of its output direction).
            let (w, h) = world.footprint(proto, direction)
            let rect = TileRect(origin: origin, w: w, h: h)
            let behind = TilePos(Int32(rect.center.x.rounded(.down)), Int32(rect.center.y.rounded(.down))).offset(direction.opposite)
            let t = world.surface.existingChunk(behind.chunk) != nil ? world.surface.tile(at: behind) : -1
            if t < 0 || !world.db.tiles[t].isWater { return .needsShoreline }
        }
        if p.fluidBoxes != nil, world.fluids.wouldMixFluids(proto: proto, origin: origin, direction: direction) {
            return .wouldMixFluids
        }
        return nil
    }

    /// Tile placement validity (concrete, landfill...). TODO(merge): Gameplay `placeTiles` validation helper.
    public static func tilePlacementError(_ world: World, item: Int, tile: TilePos) -> PlacementError? {
        guard world.surface.isInBounds(tile) else { return .outOfBounds }
        let target = world.db.itemPlaceTile[item]
        guard target >= 0 else { return .invalidTile }
        let cur = world.surface.tile(at: tile)
        guard cur >= 0 else { return .outOfBounds }
        let isLandfill = world.db.tiles[target].id == "landfill"
        if world.db.tiles[cur].isWater != isLandfill { return isLandfill ? .invalidTile : .water }
        return cur == target ? .notAllowed : nil
    }

    // MARK: Character

    /// Handcraft queue for the HUD strip. TODO(merge): map `world.player.craftQueue` entries.
    public static func craftQueue(_ world: World) -> [CraftQueueEntryView] { [] }

    /// Hand-mining progress 0...1 of the current target, or nil when not mining.
    /// TODO(merge): `world.player.miningProgress` / `miningTarget`.
    public static func handMiningProgress(_ world: World) -> Double? { nil }

    /// Number of `item` in the character inventory.
    public static func inventoryCount(_ world: World, item: Int) -> Int {
        item >= 0 ? world.player.inventory.count(of: item) : 0
    }

    // MARK: Power

    /// Copper-wire neighbours of pole `e`, or nil when the PowerSystem doesn't expose wiring yet (the renderer then
    /// draws an approximation). TODO(merge): `world.power.wires(of: e)`.
    public static func wires(_ world: World, of e: Int32) -> [Int32]? { nil }

    // MARK: Progression

    /// Current objective (title, progress text) for the tracker. TODO(merge): session objective tracker API.
    public static func objective(_ session: GameSession) -> (title: String, progress: String?)? { nil }

    /// Whether the session wants an autosave now. TODO(merge): `session.autosaveDue` when Progression adds it.
    /// Fallback: every `minutes` of game time since `lastTick`.
    public static func autosaveDue(_ session: GameSession, minutes: Int, lastTick: UInt64) -> Bool {
        guard minutes > 0 else { return false }
        let interval = UInt64(minutes) * 60 * UInt64(ticksPerSecond)
        return session.world.tick &- lastTick >= interval && session.world.tick > lastTick
    }
}

/// Read-only per-entity queries routed to the owning system (status icon, info card, animation).
public enum EntityQuery {
    public static func status(_ world: World, _ e: Int32) -> EntityStatus? {
        let r = world.entities[e]
        guard r.isAlive, !r.flags.contains(.ghost) else { return nil }
        switch r.kind {
        case .furnace, .assemblingMachine, .rocketSilo: return world.crafting.status(of: e)
        case .miningDrill: return world.mining.status(of: e)
        case .lab: return world.labs.status(of: e)
        case .inserter: return world.inserters.status(of: e)
        default: return nil
        }
    }

    public static func isWorking(_ world: World, _ e: Int32) -> Bool {
        let r = world.entities[e]
        guard r.isAlive, !r.flags.contains(.ghost) else { return false }
        switch r.kind {
        case .furnace, .assemblingMachine, .rocketSilo: return world.crafting.isWorking(e)
        case .miningDrill: return world.mining.isWorking(e)
        case .lab: return world.labs.isWorking(e)
        default: return false
        }
    }

    public static func progress(_ world: World, _ e: Int32) -> Double? {
        let r = world.entities[e]
        guard r.isAlive, !r.flags.contains(.ghost) else { return nil }
        switch r.kind {
        case .furnace, .assemblingMachine, .rocketSilo: return world.crafting.progress(of: e)
        case .miningDrill: return world.mining.progress(of: e)
        case .lab: return world.labs.progress(of: e)
        default: return nil
        }
    }

    public static func recipe(_ world: World, _ e: Int32) -> Int {
        let r = world.entities[e]
        guard r.isAlive, !r.flags.contains(.ghost) else { return -1 }
        switch r.kind {
        case .furnace, .assemblingMachine, .rocketSilo: return world.crafting.recipe(of: e)
        default: return -1
        }
    }

    public static func fuel(_ world: World, _ e: Int32) -> BurnerEnergy? {
        let r = world.entities[e]
        guard r.isAlive, !r.flags.contains(.ghost) else { return nil }
        switch r.kind {
        case .furnace, .assemblingMachine, .rocketSilo: return world.crafting.fuel(of: e)
        case .miningDrill: return world.mining.fuel(of: e)
        case .inserter: return world.inserters.fuel(of: e)
        default: return nil
        }
    }

    /// Main product item of a recipe (alt-mode icon), or -1.
    public static func mainProductItem(_ world: World, recipe: Int) -> Int {
        guard recipe >= 0 && recipe < world.db.recipes.count else { return -1 }
        let rp = world.db.recipes[recipe]
        if let m = rp.mainProduct, let i = world.db.itemIndex[m] { return i }
        return world.db.resolvedRecipes[recipe].itemResults.first?.index ?? -1
    }

    /// Statuses that get a blinking warning icon over the entity (GDD §2 feedback surfaces).
    public static func isWarning(_ s: EntityStatus) -> Bool {
        switch s {
        case .noPower, .lowPower, .noFuel, .outputFull, .noInput, .noResources, .noFluid, .fluidFull: return true
        default: return false
        }
    }

    /// English status text (TODO: route through the string tables when the UI engineer adds localisation).
    public static func text(_ s: EntityStatus) -> String {
        switch s {
        case .working: return "Working"
        case .idle: return "Idle"
        case .noInput: return "No ingredients"
        case .outputFull: return "Output full"
        case .noPower: return "No power"
        case .lowPower: return "Low power"
        case .noFuel: return "No fuel"
        case .noRecipe: return "No recipe"
        case .noResources: return "No minable resources"
        case .noResearch: return "No research"
        case .waitingForSource: return "Waiting for source items"
        case .waitingForTarget: return "Waiting for space in destination"
        case .disabled: return "Disabled"
        case .noFluid: return "Missing fluid"
        case .fluidFull: return "Fluid output full"
        case .noModules: return "No modules"
        }
    }

    /// Short text for a placement error (ghost hint, GDD §4.4).
    public static func text(_ e: PlacementError) -> String {
        switch e {
        case .outOfBounds: return "Outside the map"
        case .blocked: return "Blocked"
        case .water: return "Can't build on water"
        case .needsShoreline: return "Needs water edge"
        case .noResourceUnderDrill: return "No resource under drill"
        case .outOfReach: return "Out of reach"
        case .notInInventory: return "Not in inventory"
        case .wouldMixFluids: return "Would mix fluids"
        case .notResearched: return "Not researched"
        case .invalidTile: return "Invalid tile"
        case .cannotRotate: return "Can't rotate"
        case .nothingThere: return "Nothing there"
        case .inventoryFull: return "Inventory full"
        case .notAllowed: return "Not allowed"
        case .custom(let s): return s
        }
    }
}
