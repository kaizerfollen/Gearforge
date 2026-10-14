// Gearforge — the in-game screen: SpriteView + touch layer + HUD + panels (GDD §4, §5).

import SwiftUI
import SpriteKit
import FactoryCore

struct GameView: View {
    @Bindable var model: AppModel
    @Bindable var controller: GameController

    // touch state
    @State private var touchStart: CGPoint? = nil
    @State private var touchStartTime = Date()
    @State private var lastTile: TilePos? = nil
    @State private var dragging = false
    @State private var holding = false
    @State private var lastDrag: CGPoint = .zero
    @State private var zoomStart: CGFloat = 1
    @State private var contextMenu: ContextMenuState? = nil
    @State private var touchID = 0
    /// Paste mode: true when the touch started on the tile already previewed (second tap places).
    @State private var pasteArmed = false
    /// Build mode with "confirm placement": the touch started on the tile already previewed.
    @State private var buildArmed = false

    /// Holds a generation-checked handle: the entity may be removed (undo, mining…) while the menu is open (QA A1).
    struct ContextMenuState: Equatable { var handle: EntityHandle; var point: CGPoint }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let scene = model.scene {
                    SpriteView(scene: scene, preferredFramesPerSecond: model.settings.batterySaver ? 30 : model.settings.frameRateCap,
                               options: [.ignoresSiblingOrder], debugOptions: model.settings.showFPS ? [.showsFPS, .showsNodeCount] : [])
                        .ignoresSafeArea()
                }
                touchLayer
                HUDView(model: model, controller: controller)          // respects the safe area (notch / Dynamic Island)
                if let cm = contextMenu { contextMenuView(cm, in: geo.size).ignoresSafeArea() }   // touch points are screen-based
                panelOverlay
                if controller.showVictory { VictoryView(model: model, controller: controller) }
            }
        }
    }

    // MARK: Touch layer

    private var touchLayer: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { v in touchChanged(v) }
                    .onEnded { v in touchEnded(v) }
            )
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { v in
                        if !holding { model.scene?.zoom = zoomStart * v.magnification }
                        dragging = true
                    }
                    .onEnded { _ in zoomStart = model.scene?.zoom ?? 1 }
            )
            .ignoresSafeArea()
    }

    private func tile(_ p: CGPoint) -> TilePos? { model.scene?.tile(atView: p) }

    private func touchChanged(_ v: DragGesture.Value) {
        guard let scene = model.scene else { return }
        contextMenu = nil
        if touchStart == nil {
            touchStart = v.startLocation
            touchStartTime = Date()
            dragging = false
            holding = false
            lastDrag = v.startLocation
            lastTile = tile(v.startLocation)
            touchID += 1
            let id = touchID
            if controller.mode == .build {
                buildArmed = lastTile != nil && controller.previewTile == lastTile
                controller.previewTile = lastTile
            }
            if controller.mode == .paste {
                pasteArmed = lastTile != nil && controller.previewTile == lastTile
                controller.previewTile = lastTile
            }
            if controller.mode == .explore {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { longPressFired(id: id, at: v.startLocation) }
            }
            return
        }
        let moved = hypot(v.location.x - v.startLocation.x, v.location.y - v.startLocation.y)
        if moved > 12 { dragging = true }
        guard let t = tile(v.location) else { return }
        switch controller.mode {
        case .explore:
            if holding { return }
            if dragging {
                // pan the camera
                let dx = Double(v.location.x - lastDrag.x), dy = Double(v.location.y - lastDrag.y)
                let k = Double(scene.S * scene.zoom)
                controller.cameraFollowsPlayer = false
                scene.cameraCenter = Vec2(scene.cameraCenter.x - dx / k, scene.cameraCenter.y - dy / k)
            }
        case .build:
            controller.previewTile = t
            if dragging, let lt = lastTile, lt != t {
                for step in path(from: lt, to: t) { controller.buildLine(from: step.0, to: step.1) }
            }
        case .remove:
            if dragging, lastTile != t { controller.remove(at: t, silent: true) }
        case .copy:
            if controller.copyStart == nil { controller.copyStart = lastTile ?? t }
            controller.copyEnd = t
        case .paste:
            if dragging { controller.previewTile = t; pasteArmed = false }
        }
        lastTile = t
        lastDrag = v.location
    }

    private func touchEnded(_ v: DragGesture.Value) {
        defer { touchStart = nil; dragging = false; lastTile = nil; touchID += 1 }
        if holding { holding = false; controller.stopMining(); return }
        if controller.mode == .copy {
            if let t = tile(v.location) {
                if controller.copyStart == nil { controller.copyStart = t }
                controller.copyEnd = t
            }
            controller.finishCopy()
            return
        }
        if controller.mode == .paste, dragging { return }      // drag only moves the preview
        guard !dragging, let t = tile(v.location) else { return }
        switch controller.mode {
        case .explore:
            if let e = controller.world.entity(at: t), controller.world.entities[e].kind != .character {
                let rec = controller.world.entities[e]
                if rec.kind == .tree || rec.kind == .rock {
                    controller.show("Hold to chop")
                } else {
                    controller.tapEntity(e)
                }
            } else if controller.pickUpGround(at: t) {
                controller.selected = nil
            } else {
                controller.selected = nil
                if controller.world.surface.resource(at: t).1 > 0 { controller.show("Hold to mine") }
            }
        case .build:
            if controller.settings.confirmPlacement && !buildArmed {
                controller.previewTile = t          // first tap: show the ghost; second tap on the same tile builds
            } else {
                controller.previewTile = t
                controller.build(at: t)
            }
            buildArmed = false
        case .remove:
            controller.remove(at: t)
        case .paste:
            if pasteArmed && controller.previewTile == t { controller.paste(at: t) } else { controller.previewTile = t }
            pasteArmed = false
        case .copy:
            break
        }
    }

    private func longPressFired(id: Int, at p: CGPoint) {
        guard id == touchID, touchStart != nil, !dragging, controller.mode == .explore, let t = tile(p) else { return }
        let w = controller.world
        if let e = w.entity(at: t) {
            let k = w.entities[e].kind
            if k == .tree || k == .rock {
                holding = controller.walkAndMine(at: t)
                if !holding { controller.show("Can't get there") }
            } else if w.entities[e].flags.contains(.playerBuilt) {
                contextMenu = ContextMenuState(handle: w.entities.handle(e), point: p)
                controller.haptic(.medium)
                touchStart = nil
            }
        } else if let r = nearestMineable(t) {
            holding = controller.walkAndMine(at: r)
            if !holding { controller.show("Can't get there") }
        } else if controller.settings.tapToWalk, controller.walkTo(t) {
            // Long-press on empty ground: walk there (A*); lifting the finger does not cancel it.
            controller.cameraFollowsPlayer = true
            controller.haptic(.light)
        }
    }

    /// The touched tile if it holds a minable resource, else the nearest one in the 8 neighbours
    /// (ore sprites leave visual gaps at patch edges, so a near miss still mines).
    private func nearestMineable(_ t: TilePos) -> TilePos? {
        let s = controller.world.surface
        func ok(_ p: TilePos) -> Bool {
            let (r, a) = s.resource(at: p)
            return r >= 0 && a > 0 && !controller.world.db.resources[r].resultIsFluid
        }
        if ok(t) { return t }
        for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, 1), (1, -1), (-1, -1)] {
            let p = TilePos(t.x + Int32(dx), t.y + Int32(dy))
            if ok(p) { return p }
        }
        return nil
    }

    /// 4-connected path between two tiles (so fast drags don't skip belt tiles).
    private func path(from a: TilePos, to b: TilePos) -> [(TilePos, TilePos)] {
        var out: [(TilePos, TilePos)] = []
        var cur = a
        var guardN = 0
        while cur != b && guardN < 64 {
            guardN += 1
            var nx = cur
            if abs(b.x - cur.x) >= abs(b.y - cur.y) { nx.x += b.x > cur.x ? 1 : -1 } else { nx.y += b.y > cur.y ? 1 : -1 }
            out.append((cur, nx))
            cur = nx
        }
        return out
    }

    // MARK: Context menu (long-press)

    private func contextMenuView(_ cm: ContextMenuState, in size: CGSize) -> some View {
        let w = controller.world
        let live = w.entities.resolve(cm.handle)
        return VStack(spacing: 6) {
            if let e = live {
                Text(w.db.entityName(Int(w.entities[e].proto))).font(.caption.bold()).foregroundStyle(Theme.text)
                HStack(spacing: 8) {
                    HUDButton(glyph: "ui_inventory", size: 46) { controller.openEntity(cm.handle); contextMenu = nil }
                    HUDButton(glyph: "ui_rotate", size: 46) {
                        if let e = w.entities.resolve(cm.handle) { controller.execute(.rotate(entity: e, clockwise: true)) }
                        contextMenu = nil
                    }
                    HUDButton(glyph: "ui_pipette", size: 46) {
                        if let e = w.entities.resolve(cm.handle) { controller.pipette(e) }
                        contextMenu = nil
                    }
                    HUDButton(glyph: "ui_remove", size: 46) {
                        if let e = w.entities.resolve(cm.handle) { controller.execute(.remove(entity: e)) }
                        contextMenu = nil
                    }
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.75)))
        .position(x: min(max(cm.point.x, 140), size.width - 140), y: max(cm.point.y - 70, 60))
    }

    // MARK: Panels

    @ViewBuilder private var panelOverlay: some View {
        if let p = controller.panel {
            ZStack {
                Color.black.opacity(p == .pause ? 0.55 : 0.25).ignoresSafeArea()
                    .onTapGesture { if p != .pause { controller.panel = nil } }
                switch p {
                case .inventory: InventoryPanel(controller: controller)
                case .entity(let h): EntityPanel(controller: controller, handle: h)
                case .research: ResearchPanel(controller: controller)
                case .stats: StatsPanel(controller: controller)
                case .pause: PauseMenu(model: model, controller: controller)
                case .map: MapPanel(controller: controller)
                case .codex: CodexPanel(controller: controller)
                }
            }
        }
    }
}

// MARK: - Victory

struct VictoryView: View {
    @Bindable var model: AppModel
    @Bindable var controller: GameController
    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(spacing: 16) {
                Text(controller.session.mode == .freeplay ? "Rocket launched!" : "Level complete!")
                    .font(.system(size: 40, weight: .heavy, design: .rounded)).foregroundStyle(Theme.accent)
                if controller.session.mode != .freeplay {
                    HStack(spacing: 6) {
                        ForEach(0..<3, id: \.self) { i in
                            Text("★").font(.system(size: 44)).foregroundStyle(i < controller.hud.stars ? Theme.accent : Color.white.opacity(0.2))
                        }
                    }
                    Text(LF("Time %@", "\(controller.hud.gameTime)")).foregroundStyle(Theme.text)
                }
                HStack(spacing: 12) {
                    MenuButton(title: "Keep playing") { controller.showVictory = false }
                    MenuButton(title: "Main menu") { model.quitToMenu(save: true) }
                }
            }
            .padding(30)
            .background(RoundedRectangle(cornerRadius: 18).fill(Theme.panel))
        }
    }
}
