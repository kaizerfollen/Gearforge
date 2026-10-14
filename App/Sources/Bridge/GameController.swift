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

enum InteractionMode: Equatable { case explore, build, remove, copy, paste }

enum GamePanel: Equatable, Identifiable {
    case inventory
    case entity(EntityHandle)
    case research
    case stats
    case pause
    case map
    var id: String {
        switch self {
        case .inventory: return "inventory"
        case .entity(let h): return "entity-\(h.index)-\(h.generation)"
        case .research: return "research"
        case .stats: return "stats"
        case .pause: return "pause"
        case .map: return "map"
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
    /// Tutorial hint for the first active objective that has one (and was not dismissed).
    var hint: String? = nil
    var hintObjective: Int = -1
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
    /// Objective ids whose tutorial hint the player closed (this session only).
    @ObservationIgnored var dismissedHints: Set<Int> = []
    @ObservationIgnored private var minimapTimer: Double = 1
    /// Minimap around the character (1 px per tile, `minimapRadius` tiles each way), refreshed twice a second.
    var minimap: CGImage? = nil
    static let minimapRadius: Int32 = 48
    /// Whole-map image for the map screen (refreshed every second while open) and its tile origin / scale.
    var mapImage: CGImage? = nil
    var mapOrigin = TilePos(0, 0)
    var mapStep: Int32 = 1
    @ObservationIgnored private var inventoryHash = 0
    @ObservationIgnored var onLevelCompleted: ((Int, Double) -> Void)?

    var mode: InteractionMode = .explore
    /// Copy/paste area (GDD §4.6): last copied area, its rotation (quarter turns) and the copy-rect being dragged.
    var clipboard: Blueprint? = nil
    var pasteRotation = 0
    @ObservationIgnored var copyStart: TilePos? = nil
    @ObservationIgnored var copyEnd: TilePos? = nil
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
            case .researchFinished(let t): show(LF("Research complete: %@", world.db.techName(t))); haptic(.success)
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
        minimapTimer += dt
        if minimapTimer >= (panel == .map ? 1.0 : 0.5) {
            minimapTimer = 0
            if panel == .map { refreshMapImage() } else { refreshMinimap() }
        }
        if toast != nil { toastTimer -= dt; if toastTimer <= 0 { toast = nil } }
        if session.autosaveDue && settings.autosaveMinutes > 0 { autosave() }
    }

    // MARK: Map

    func refreshMinimap() {
        let r = Self.minimapRadius
        let c = world.player.position.tile
        let n = Int(r * 2)
        minimap = Self.image(rgba: world.mapRGBA(x0: c.x - r, y0: c.y - r, w: n, h: n), w: n, h: n)
    }

    func refreshMapImage() {
        let b = world.surface.bounds
        let step = max(1, (max(b.w, b.h) + 511) / 512)
        let w = Int(b.w / step), h = Int(b.h / step)
        mapOrigin = TilePos(b.x, b.y)
        mapStep = step
        mapImage = Self.image(rgba: world.mapRGBA(x0: b.x, y0: b.y, w: w, h: h, step: step), w: w, h: h)
    }

    func openMap() {
        refreshMapImage()
        minimapTimer = 0
        panel = .map
    }

    /// Save thumbnail: 16:9 map snapshot around the character (96×54 tiles, 2 px per tile), PNG. ~1 ms.
    func thumbnailPNG() -> Data? {
        let w = 96, h = 54
        let c = world.player.position.tile
        let rgba = world.mapRGBA(x0: c.x - Int32(w / 2), y0: c.y - Int32(h / 2), w: w, h: h)
        var big = [UInt8](repeating: 0, count: w * h * 16)          // 2× nearest-neighbour upscale
        for y in 0..<(h * 2) { for x in 0..<(w * 2) {
            let s = ((y / 2) * w + x / 2) * 4, d = (y * w * 2 + x) * 4
            big[d] = rgba[s]; big[d + 1] = rgba[s + 1]; big[d + 2] = rgba[s + 2]; big[d + 3] = 255
        } }
        // Character marker.
        for dy in -2...2 { for dx in -2...2 where dx * dx + dy * dy <= 5 {
            let x = w + dx, y = h + dy, d = (y * w * 2 + x) * 4
            big[d] = 255; big[d + 1] = 160; big[d + 2] = 60
        } }
        guard let img = Self.image(rgba: big, w: w * 2, h: h * 2) else { return nil }
        return UIImage(cgImage: img).pngData()
    }

    static func image(rgba: [UInt8], w: Int, h: Int) -> CGImage? {
        guard w > 0, h > 0, let provider = CGDataProvider(data: Data(rgba) as CFData) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
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
            h.researchName = w.db.techName(cur)
            h.researchIcon = w.db.technologies[cur].id
            h.researchProgress = w.research.progress(of: cur)
        }
        h.craftQueue = Array(pl.craftQueue.prefix(6))
        h.objectives = session.objectives.active.map { o in
            let s = session.objectives.states[o.id] ?? ObjectiveTracker.State()
            let detail = s.target > 1 ? "\(Int(s.current.rounded(.down)))/\(Int(s.target))" : ""
            return ObjectiveLine(id: o.id, title: Names.objectiveTitle(session.level?.id, o), fraction: s.fraction, detail: detail)
        }
        if settings.tutorialHints, let o = session.objectives.active.first(where: { $0.hint != nil && !dismissedHints.contains($0.id) }) {
            h.hint = Names.objectiveHint(session.level?.id, o)
            h.hintObjective = o.id
        }
        h.levelCompleted = session.objectives.levelCompleted
        h.stars = session.objectives.stars
        if let sh = selected, let e = w.entities.resolve(sh) {
            let rec = w.entities[e]
            h.selectedName = w.db.entityName(Int(rec.proto))
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
        toast = L(message)
        toastTimer = 2.5
    }

    // MARK: Interaction

    /// Top-left origin for a prototype whose footprint is centred on the touched tile.
    func buildOrigin(proto: Int, tile: TilePos) -> TilePos {
        let (w, h) = world.footprint(proto, buildDirection)
        let base = TilePos(tile.x - Int32((w - 1) / 2), tile.y - Int32((h - 1) / 2))
        return snappedOrigin(proto: proto, base: base)
    }

    /// Mobile placement assist: a furnace / assembler / chest / lab dropped next to a mining drill shifts by at most
    /// one tile so that it covers the drill's output point (a fingertip is wider than a tile). No shift when the
    /// base position already covers an output or no shifted position is valid.
    private func snappedOrigin(proto: Int, base: TilePos) -> TilePos {
        let w = world
        switch w.db.entities[proto].kind {
        case .furnace, .assemblingMachine, .container, .lab: break
        default: return base
        }
        let (fw, fh) = w.footprint(proto, buildDirection)
        let search = TileRect(x: base.x - 4, y: base.y - 4, w: Int32(fw) + 8, h: Int32(fh) + 8)
        var outputs: [TilePos] = []
        for e in w.entities(in: search) {
            let rec = w.entities[e]
            guard rec.kind == .miningDrill, !rec.flags.contains(.ghost) else { continue }
            if let o = w.ioPoints(proto: Int(rec.proto), origin: TilePos(rec.rect.x, rec.rect.y), dir: rec.direction).output {
                outputs.append(o.tile)
            }
        }
        if outputs.isEmpty { return base }
        func covers(_ o: TilePos) -> Bool {
            let r = TileRect(x: o.x, y: o.y, w: Int32(fw), h: Int32(fh))
            return outputs.contains { r.contains($0) }
        }
        if covers(base) { return base }
        var best: TilePos? = nil
        for dy in -1...1 { for dx in -1...1 where dx != 0 || dy != 0 {
            let o = TilePos(base.x + Int32(dx), base.y + Int32(dy))
            guard covers(o), w.placementError(proto: proto, origin: o, direction: buildDirection) == nil else { continue }
            if best == nil || abs(dx) + abs(dy) < abs(best!.x - base.x) + abs(best!.y - base.y) { best = o }
        } }
        return best ?? base
    }

    func selectBuildItem(_ item: Int) {
        guard item >= 0, world.db.itemPlaceResult[item] >= 0 || world.db.itemPlaceTile[item] >= 0 else { return }
        buildItem = item
        mode = .build
        addToQuickbar(item)
        haptic(.light)
    }

    func cancelMode() { mode = .explore; buildItem = -1; previewTile = nil; copyStart = nil; copyEnd = nil }

    // MARK: Copy / paste area

    func beginCopy() { cancelMode(); mode = .copy; haptic(.light) }

    /// Normalized rect between two tiles (inclusive).
    static func rect(_ a: TilePos, _ b: TilePos) -> TileRect {
        TileRect(x: min(a.x, b.x), y: min(a.y, b.y), w: abs(a.x - b.x) + 1, h: abs(a.y - b.y) + 1)
    }

    /// Finishes a copy drag: captures the area and switches to paste mode.
    func finishCopy() {
        defer { copyStart = nil; copyEnd = nil }
        guard let a = copyStart, let b = copyEnd else { return }
        let bp = world.captureBlueprint(Self.rect(a, b))
        guard !bp.isEmpty else { show(L("Nothing to copy here")); mode = .explore; return }
        clipboard = bp
        pasteRotation = 0
        mode = .paste
        previewTile = nil
        show(LF("Copied %@ buildings — tap to place", "\(bp.entries.count)"))
        haptic(.medium)
    }

    /// The clipboard with the current rotation applied.
    var pasteBlueprint: Blueprint? { clipboard.map { $0.rotated(pasteRotation, db: world.db) } }

    /// Top-left of the paste so the blueprint is centred on the touched tile.
    func pasteOrigin(_ tile: TilePos) -> TilePos? {
        guard let bp = pasteBlueprint else { return nil }
        return TilePos(tile.x - (bp.width - 1) / 2, tile.y - (bp.height - 1) / 2)
    }

    func rotatePaste() { pasteRotation = (pasteRotation + 1) % 4; haptic(.light) }

    func beginPaste() {
        guard clipboard != nil else { beginCopy(); return }
        cancelMode(); mode = .paste
    }

    /// Places ghosts of the clipboard at the touched tile; the character builds them from the inventory.
    func paste(at tile: TilePos) {
        guard let bp = pasteBlueprint, let o = pasteOrigin(tile) else { return }
        let r = execute(.pasteBlueprint(bp, origin: o))
        guard r.isOK else { return }
        haptic(.medium)
        // tell the player what is missing
        let need = bp.requiredItems(db: world.db)
        let missing = need.filter { world.player.count(of: $0.key) < $0.value }
        if let m = missing.first {
            show(LF("Ghosts placed — missing %@", "\(Names.item(world.db, m.key)) ×\(m.value - world.player.count(of: m.key))"))
        } else {
            show(L("Ghosts placed — walk close to build them"))
        }
    }

    /// Picks up the items lying on a tile (explore tap).
    @discardableResult
    func pickUpGround(at tile: TilePos) -> Bool {
        guard world.ground.count(at: tile) > 0 else { return false }
        let r = execute(.pickUpGround(tile), silent: true)
        if r.isOK { haptic(.light) } else if case .failed(.outOfReach) = r { _ = walkTo(tile) }
        return true
    }

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
        if world.player.count(of: buildItem) == 0 && ok {
            show(LF("Out of %@", db.itemName(buildItem)))
            cancelMode()          // nothing left to place: leave build mode (no stale red preview)
        }
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
    /// Hold-to-mine: mines at once when in reach, otherwise walks into reach first.
    func walkAndMine(at tile: TilePos) -> Bool {
        execute(.walkAndMine(tile), silent: true).isOK
    }
    /// Tap-to-walk (A* path, cancelled by the joystick).
    func walkTo(_ tile: TilePos) -> Bool {
        let r = execute(.walkTo(tile), silent: true)
        if !r.isOK { show("Can't get there") }
        return r.isOK
    }
    func stopMining() { world.player.stopMining(); world.player.cancelWalk() }

    /// Pipette: select the item that builds this entity.
    func pipette(_ e: Int32) {
        guard world.entities.isLive(e) else { return }
        let item = world.db.entityItem[Int(world.entities[e].proto)]
        guard item >= 0 else { return }
        buildDirection = world.entities[e].direction
        if world.player.count(of: item) > 0 { selectBuildItem(item) } else { show(LF("No %@ in inventory", world.db.itemName(item))) }
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
            try saveManager.save(session, slot: slot, displayName: name ?? slot, thumbnailPNG: thumbnailPNG())
            show("Saved")
        } catch { show(LF("Save failed: %@", "\(error)")) }
    }

    func autosave() {
        do { try saveManager.autosave(session, slots: settings.autosaveSlots, thumbnailPNG: thumbnailPNG()); show("Autosaved") }
        catch { session.didAutosave(); show("Autosave failed") }
    }

    /// Background save — must be fast (called when the app leaves the foreground).
    func backgroundSave() {
        _ = try? saveManager.save(session, slot: SaveManager.backgroundSlot, displayName: "Last session", thumbnailPNG: thumbnailPNG())
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
