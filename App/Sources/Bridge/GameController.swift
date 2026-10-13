// Gearforge — App
// GameController: the ONLY bridge between UI/rendering and FactoryCore. Owns the GameSession, the interaction state
// (mode, build item, direction, selection, open panel) and publishes a lightweight HUD snapshot at ~10 Hz so SwiftUI
// never re-renders at 60 Hz. The SpriteKit scene calls `frame(dt:)` every display frame.

import Foundation
import Observation
import FactoryCore
#if canImport(UIKit)
import UIKit
#endif

enum InteractionMode: Equatable { case explore, build, remove }

enum GamePanel: Equatable, Identifiable {
    case inventory
    case entity(EntityHandle)
    case research
    case stats
    case pause
    var id: String {
        switch self {
        case .inventory: return "inventory"
        case .entity(let h): return "entity-\(h.index)-\(h.generation)"
        case .research: return "research"
        case .stats: return "stats"
        case .pause: return "pause"
        }
    }
}

struct ObjectiveLine: Equatable, Identifiable {
    var id: Int
    var title: String
    var fraction: Double
    var detail: String
}

struct HUDState: Equatable {
    var powerSatisfaction: Double = -1        // -1 = no network here
    var researchName: String = ""
    var researchIcon: String = ""
    var researchProgress: Double = 0
    var craftQueue: [CraftQueueEntry] = []
    var objectives: [ObjectiveLine] = []
    var levelCompleted = false
    var stars = 0
    var selectedName: String = ""
    var selectedStatus: EntityStatus? = nil
    var selectedProgress: Double = 0
    var selectedRecipeIcon: String = ""
    var inventoryRevision = 0
    var quickbarCounts: [Int] = Array(repeating: 0, count: 10)
    var canUndo = false
    var canRedo = false
    var gameTime: String = "0:00"
    var miningProgress: Double = -1
    var buildReason: String = ""
}

@MainActor
@Observable
final class GameController {
    @ObservationIgnored let session: GameSession
    @ObservationIgnored var world: World { session.world }
    @ObservationIgnored let saveManager: SaveManager
    @ObservationIgnored var settings: GameSettings
    /// Events drained from the world this frame (the renderer consumes them in the same update).
    @ObservationIgnored private(set) var frameEvents: [WorldEvent] = []
    @ObservationIgnored private var hudTimer: Double = 0
    @ObservationIgnored private var inventoryHash = 0
    @ObservationIgnored var onLevelCompleted: ((Int, Double) -> Void)?

    var mode: InteractionMode = .explore
    var buildItem: Int = -1
    var buildDirection: Direction = .north
    var selected: EntityHandle? = nil
    var panel: GamePanel? = nil
    var hud = HUDState()
    var toast: String? = nil
    var cameraFollowsPlayer = true
    var quickbarPage = 0
    var altMode = true
    var showVictory = false

    /// Where the build preview sits (tile) — set by the scene from the last touch.
    @ObservationIgnored var previewTile: TilePos? = nil
    @ObservationIgnored private var toastTimer: Double = 0

    init(session: GameSession, saveManager: SaveManager, settings: GameSettings) {
        self.session = session
        self.saveManager = saveManager
        self.settings = settings
        self.altMode = settings.altMode
        session.autosaveIntervalSeconds = Double(settings.autosaveMinutes * 60)
        if session.world.player.quickbar.allSatisfy({ $0 < 0 }) { seedQuickbar() }
        refreshHUD()
    }

    // MARK: Frame

    func frame(dt: Double) {
        let paused = panel == .pause
        session.isPaused = paused
        session.advance(realSeconds: min(dt, 0.25))
        frameEvents = world.drainEvents()
        for e in frameEvents {
            switch e {
            case .alert(let s): show(s)
            case .researchFinished(let t): show("Research complete: \(world.db.technologies[t].name)"); haptic(.success)
            case .levelCompleted:
                showVictory = true
                onLevelCompleted?(session.objectives.stars, session.gameSeconds)
                haptic(.success)
            case .rocketLaunched:
                if session.mode == .freeplay && !session.victoryShown { session.victoryShown = true; showVictory = true }
            default: break
            }
        }
        if let h = selected, world.entities.resolve(h) == nil { selected = nil; if case .entity = panel { panel = nil } }
        hudTimer += dt
        if hudTimer >= 0.1 { hudTimer = 0; refreshHUD() }
        if toast != nil { toastTimer -= dt; if toastTimer <= 0 { toast = nil } }
        if session.autosaveDue && settings.autosaveMinutes > 0 { autosave() }
    }

    // MARK: HUD

    func refreshHUD() {
        var h = HUDState()
        let w = world
        let pl = w.player!
        let net = w.power.network(at: pl.position)
        if net >= 0, let st = w.power.stats(network: net) { h.powerSatisfaction = st.demandW > 0 ? st.satisfaction : 1 }
        let cur = w.research.current
        if cur >= 0 {
            h.researchName = w.db.technologies[cur].name
            h.researchIcon = w.db.technologies[cur].id
            h.researchProgress = w.research.progress(of: cur)
        }
        h.craftQueue = Array(pl.craftQueue.prefix(6))
        h.objectives = session.objectives.active.map { o in
            let s = session.objectives.states[o.id] ?? ObjectiveTracker.State()
            let detail = s.target > 1 ? "\(Int(s.current.rounded(.down)))/\(Int(s.target))" : ""
            return ObjectiveLine(id: o.id, title: o.title, fraction: s.fraction, detail: detail)
        }
        h.levelCompleted = session.objectives.levelCompleted
        h.stars = session.objectives.stars
        if let sh = selected, let e = w.entities.resolve(sh) {
            let rec = w.entities[e]
            h.selectedName = w.db.entities[Int(rec.proto)].name
            switch rec.kind {
            case .assemblingMachine, .furnace, .rocketSilo:
                h.selectedStatus = w.crafting.status(of: e); h.selectedProgress = w.crafting.progress(of: e)
                let r = w.crafting.recipe(of: e)
                if r >= 0, let res = w.db.resolvedRecipes[r].itemResults.first { h.selectedRecipeIcon = w.db.items[res.index].id }
            case .miningDrill: h.selectedStatus = w.mining.status(of: e); h.selectedProgress = w.mining.progress(of: e)
            case .lab: h.selectedStatus = w.labs.status(of: e); h.selectedProgress = w.labs.progress(of: e)
            case .inserter: h.selectedStatus = w.inserters.status(of: e)
            default: break
            }
        }
        var hash = 0
        for s in pl.inventory.slots where !s.isEmpty { hash = hash &* 31 &+ Int(s.item) &* 1009 &+ Int(s.count) }
        if hash != inventoryHash { inventoryHash = hash; h.inventoryRevision = hud.inventoryRevision &+ 1 } else { h.inventoryRevision = hud.inventoryRevision }
        for i in 0..<10 {
            let item = Int(pl.quickbar[quickbarPage * 10 + i])
            h.quickbarCounts[i] = item >= 0 ? pl.count(of: item) : 0
        }
        h.canUndo = w.canUndo; h.canRedo = w.canRedo
        let secs = Int(session.gameSeconds)
        h.gameTime = secs >= 3600 ? String(format: "%d:%02d:%02d", secs / 3600, secs / 60 % 60, secs % 60) : String(format: "%d:%02d", secs / 60, secs % 60)
        if pl.miningTarget != nil { h.miningProgress = pl.miningProgress }
        if mode == .build, let t = previewTile, buildItem >= 0 {
            let proto = w.db.itemPlaceResult[buildItem]
            if proto >= 0, let err = w.placementError(proto: proto, origin: buildOrigin(proto: proto, tile: t), direction: buildDirection) {
                h.buildReason = err.message
            }
        }
        if h != hud { hud = h }
    }

    // MARK: Commands

    @discardableResult
    func execute(_ cmd: PlayerCommand, silent: Bool = false) -> CommandResult {
        let r = world.execute(cmd)
        if case .failed(let e) = r, !silent { show(e.message); haptic(.error) }
        if r.isOK { hudTimer = 1 }   // refresh soon
        return r
    }

    func show(_ message: String) {
        toast = message
        toastTimer = 2.5
    }

    // MARK: Interaction

    /// Top-left origin for a prototype whose footprint is centred on the touched tile.
    func buildOrigin(proto: Int, tile: TilePos) -> TilePos {
        let (w, h) = world.footprint(proto, buildDirection)
        return TilePos(tile.x - Int32((w - 1) / 2), tile.y - Int32((h - 1) / 2))
    }

    func selectBuildItem(_ item: Int) {
        guard item >= 0, world.db.itemPlaceResult[item] >= 0 || world.db.itemPlaceTile[item] >= 0 else { return }
        buildItem = item
        mode = .build
        addToQuickbar(item)
        haptic(.light)
    }

    func cancelMode() { mode = .explore; buildItem = -1; previewTile = nil }

    func rotateBuild() {
        buildDirection = buildDirection.clockwise
        haptic(.light)
    }

    /// Places the current build item at a touched tile.
    @discardableResult
    func build(at tile: TilePos, silent: Bool = false) -> Bool {
        guard buildItem >= 0 else { return false }
        let db = world.db
        if db.itemPlaceTile[buildItem] >= 0 {
            return execute(.placeTiles(item: buildItem, tiles: [tile]), silent: silent).isOK
        }
        let proto = db.itemPlaceResult[buildItem]
        guard proto >= 0 else { return false }
        let ok = execute(.build(item: buildItem, origin: buildOrigin(proto: proto, tile: tile), direction: buildDirection), silent: silent).isOK
        if ok { haptic(.medium) }
        if world.player.count(of: buildItem) == 0 && ok { show("Out of \(db.items[buildItem].name)") }
        return ok
    }

    /// Belt/line drag: places along a path, setting belt direction from the drag direction.
    func buildLine(from a: TilePos, to b: TilePos) {
        guard buildItem >= 0 else { return }
        let dx = b.x - a.x, dy = b.y - a.y
        if dx == 0 && dy == 0 { return }
        let dir: Direction = abs(dx) >= abs(dy) ? (dx > 0 ? .east : .west) : (dy > 0 ? .south : .north)
        let proto = world.db.itemPlaceResult[buildItem]
        guard proto >= 0 else {
            if world.db.itemPlaceTile[buildItem] >= 0 { _ = execute(.placeTiles(item: buildItem, tiles: [b]), silent: true) }
            return
        }
        let kind = world.db.entities[proto].kind
        if kind == .transportBelt || kind == .pipe || kind == .inserter || kind == .undergroundBelt {
            if kind == .transportBelt {
                // re-orient the previous belt so corners form naturally
                if let prev = world.entity(at: a), world.entities[prev].kind == .transportBelt, world.entities[prev].direction != dir {
                    var tries = 0
                    while world.entities[prev].direction != dir && tries < 4 { _ = execute(.rotate(entity: prev, clockwise: true), silent: true); tries += 1 }
                }
            }
            buildDirection = world.db.entities[proto].rotatable ? dir : buildDirection
        }
        build(at: b, silent: true)
    }

    func tapEntity(_ e: Int32) {
        let h = world.entities.handle(e)
        if selected == h { openEntity(h) } else { selected = h; haptic(.light) }
        hudTimer = 1
    }

    func openEntity(_ h: EntityHandle) {
        guard let e = world.entities.resolve(h) else { return }
        let rec = world.entities[e]
        switch rec.kind {
        case .tree, .rock, .character: return
        default: break
        }
        if !world.player.canReach(rec.rect) { show("Out of reach") ; return }
        panel = .entity(h)
    }

    func remove(at tile: TilePos, silent: Bool = false) {
        guard let e = world.entity(at: tile) else { return }
        let rec = world.entities[e]
        guard rec.flags.contains(.playerBuilt) else { return }
        if execute(.remove(entity: e), silent: silent).isOK { haptic(.medium) }
    }

    func startMining(at tile: TilePos) -> Bool {
        execute(.startMining(tile), silent: true).isOK
    }
    func stopMining() { world.player.stopMining() }

    /// Pipette: select the item that builds this entity.
    func pipette(_ e: Int32) {
        let item = world.db.entityItem[Int(world.entities[e].proto)]
        guard item >= 0 else { return }
        buildDirection = world.entities[e].direction
        if world.player.count(of: item) > 0 { selectBuildItem(item) } else { show("No \(world.db.items[item].name) in inventory") }
    }

    func undo() { if world.undo().isOK { haptic(.light) } }
    func redo() { if world.redo().isOK { haptic(.light) } }

    // MARK: Quickbar

    func seedQuickbar() {
        let ids = ["transport_belt", "burner_inserter", "inserter", "small_electric_pole", "burner_mining_drill",
                   "electric_mining_drill", "stone_furnace", "assembling_machine_1", "wooden_chest", "pipe"]
        for (i, id) in ids.enumerated() { world.player.quickbar[i] = Int32(world.db.item(id)) }
    }

    func addToQuickbar(_ item: Int) {
        let pl = world.player!
        if pl.quickbar.contains(Int32(item)) { return }
        // replace the first empty, or the first slot whose item is not in the inventory
        if let i = pl.quickbar.firstIndex(of: -1) { pl.quickbar[i] = Int32(item); return }
        if let i = pl.quickbar.indices.first(where: { pl.count(of: Int(pl.quickbar[$0])) == 0 }) { pl.quickbar[i] = Int32(item) }
    }

    func quickbarItem(_ slot: Int) -> Int { Int(world.player.quickbar[quickbarPage * 10 + slot]) }

    // MARK: Saving

    func save(slot: String, name: String? = nil) {
        do {
            try saveManager.save(session, slot: slot, displayName: name ?? slot)
            show("Saved")
        } catch { show("Save failed: \(error)") }
    }

    func autosave() {
        do { try saveManager.autosave(session, slots: settings.autosaveSlots); show("Autosaved") }
        catch { session.didAutosave(); show("Autosave failed") }
    }

    /// Background save — must be fast (called when the app leaves the foreground).
    func backgroundSave() {
        try? saveManager.save(session, slot: SaveManager.backgroundSlot, displayName: "Last session")
    }

    // MARK: Haptics

    enum Haptic { case light, medium, success, error }
    func haptic(_ h: Haptic) {
        #if canImport(UIKit)
        guard settings.haptics else { return }
        switch h {
        case .light: UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .medium: UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .success: UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .error: UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
        #endif
    }
}
