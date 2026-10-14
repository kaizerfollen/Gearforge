// Gearforge — HUD overlay (GDD §5): power + time, objectives, research bar, mode buttons, quickbar, craft queue,
// joystick, selection card, toasts.

import SwiftUI
import FactoryCore

struct HUDView: View {
    @Bindable var model: AppModel
    @Bindable var controller: GameController

    var body: some View {
        let hud = controller.hud
        let db = controller.world.db
        ZStack {
            // Top bar
            VStack {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        statusChip(hud)
                        if !hud.objectives.isEmpty { objectives(hud) }
                        if !hud.selectedName.isEmpty { selectionCard(hud, db) }
                    }
                    .frame(width: 250, alignment: .leading)
                    Spacer()
                    researchBar(hud)
                    Spacer()
                    HStack(alignment: .top, spacing: 8) {
                        MinimapView(controller: controller)
                        HUDButton(glyph: "ui_altmode", active: controller.altMode, size: 44) { controller.altMode.toggle() }
                        HUDButton(glyph: "ui_stats", size: 44) { controller.panel = .stats }
                        HUDButton(glyph: "ui_pause", size: 44) { controller.panel = .pause }
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 16).padding(.top, 10)

            // Right column: modes
            HStack {
                Spacer()
                VStack(spacing: 10) {
                    Spacer()
                    HUDButton(glyph: "ui_build", active: controller.mode == .build) {
                        if controller.mode == .build { controller.cancelMode() } else { controller.panel = .inventory }
                    }
                    HUDButton(glyph: "ui_remove", active: controller.mode == .remove) {
                        controller.mode = controller.mode == .remove ? .explore : .remove
                    }
                    if controller.mode == .build {
                        HUDButton(glyph: "ui_rotate") { controller.rotateBuild() }
                    }
                    HStack(spacing: 8) {
                        HUDButton(glyph: "ui_undo", size: 44) { controller.undo() }.opacity(hud.canUndo ? 1 : 0.4)
                        HUDButton(glyph: "ui_redo", size: 44) { controller.redo() }.opacity(hud.canRedo ? 1 : 0.4)
                    }
                    HUDButton(glyph: "ui_inventory", size: 60) { controller.panel = .inventory }
                }
                .padding(.trailing, 16).padding(.bottom, 16)
            }

            // Bottom: craft queue + quickbar
            VStack(spacing: 6) {
                Spacer()
                if let t = controller.toast {
                    Text(t).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Capsule().fill(Color.black.opacity(0.7)))
                }
                if !hud.buildReason.isEmpty && controller.mode == .build {
                    Text(hud.buildReason).font(.caption.bold()).foregroundStyle(Theme.bad)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(Color.black.opacity(0.6)))
                }
                if hud.miningProgress >= 0 {
                    BarView(fraction: hud.miningProgress, color: Theme.good, height: 8).frame(width: 160)
                }
                if !hud.craftQueue.isEmpty { craftQueue(hud, db) }
                quickbar(hud, db)
            }
            .padding(.bottom, 10)

            // Joystick (bottom-left)
            VStack {
                Spacer()
                HStack {
                    JoystickView { v in
                        controller.world.player.moveInput = Vec2(Double(v.dx), Double(v.dy))
                        if v.dx != 0 || v.dy != 0 { controller.cameraFollowsPlayer = true }
                    }
                    .frame(width: 180, height: 180)
                    .padding(.leading, 20).padding(.bottom, 16)
                    Spacer()
                }
            }

            if !controller.cameraFollowsPlayer {
                VStack {
                    Spacer().frame(height: 70)
                    Button { controller.cameraFollowsPlayer = true } label: {
                        Text("⊙ Recenter").font(.callout.bold()).foregroundStyle(.white)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Capsule().fill(Color.black.opacity(0.6)))
                    }.buttonStyle(.plain)
                    Spacer()
                }
            }
        }
    }

    // MARK: Pieces

    private func statusChip(_ hud: HUDState) -> some View {
        HStack(spacing: 8) {
            SpriteImage(name: "ui_power", size: 18)
            if hud.powerSatisfaction >= 0 {
                Text("\(Int(hud.powerSatisfaction * 100))%").font(.caption.bold()).monospacedDigit()
                    .foregroundStyle(Theme.powerColor(hud.powerSatisfaction))
            } else {
                Text("—").font(.caption.bold()).foregroundStyle(Theme.textDim)
            }
            Text(hud.gameTime).font(.caption).monospacedDigit().foregroundStyle(Theme.textDim)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Capsule().fill(Color.black.opacity(0.55)))
    }

    private func objectives(_ hud: HUDState) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(hud.objectives) { o in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(o.title).font(.caption.bold()).foregroundStyle(Theme.text).lineLimit(2)
                        Spacer()
                        if !o.detail.isEmpty { Text(o.detail).font(.caption2).monospacedDigit().foregroundStyle(Theme.textDim) }
                    }
                    BarView(fraction: o.fraction, height: 4)
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.55)))
    }

    private func selectionCard(_ hud: HUDState, _ db: PrototypeDB) -> some View {
        Button {
            if let h = controller.selected { controller.openEntity(h) }
        } label: {
            HStack(spacing: 8) {
                if !hud.selectedRecipeIcon.isEmpty { SpriteImage(name: "i_\(hud.selectedRecipeIcon)", size: 30) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(hud.selectedName).font(.caption.bold()).foregroundStyle(Theme.text)
                    if let s = hud.selectedStatus { Text(s.label).font(.caption2).foregroundStyle(s.color) }
                    if hud.selectedProgress > 0 { BarView(fraction: hud.selectedProgress, height: 3).frame(width: 120) }
                }
                Spacer()
                Text("Open ›").font(.caption2).foregroundStyle(Theme.accent)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.6)))
        }
        .buttonStyle(.plain)
    }

    private func researchBar(_ hud: HUDState) -> some View {
        Button { controller.panel = .research } label: {
            HStack(spacing: 8) {
                SpriteImage(name: "ui_research", size: 20)
                if hud.researchName.isEmpty {
                    Text("Choose research").font(.caption.bold()).foregroundStyle(Theme.warn)
                } else {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(hud.researchName).font(.caption.bold()).foregroundStyle(Theme.text)
                        BarView(fraction: hud.researchProgress, height: 4).frame(width: 160)
                    }
                    Text("\(Int(hud.researchProgress * 100))%").font(.caption2).monospacedDigit().foregroundStyle(Theme.textDim)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(Color.black.opacity(0.55)))
        }
        .buttonStyle(.plain)
        .opacity(controller.world.research.researchEnabled ? 1 : 0)
    }

    private func craftQueue(_ hud: HUDState, _ db: PrototypeDB) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(hud.craftQueue.enumerated()), id: \.offset) { i, q in
                ZStack(alignment: .bottom) {
                    Image(uiImage: SpriteCatalog.shared.recipeIcon(q.recipe, db: db)).resizable().frame(width: 30, height: 30)
                        .opacity(q.isIntermediate ? 0.7 : 1)
                    Text("\(q.count)").font(.system(size: 10, weight: .bold)).foregroundStyle(.white).offset(y: 8)
                    if i == 0 { BarView(fraction: q.progress, color: Theme.good, height: 3).frame(width: 30).offset(y: 12) }
                }
                .onTapGesture { controller.execute(.cancelCraft(queueIndex: q.group)) }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Capsule().fill(Color.black.opacity(0.5)))
    }

    private func quickbar(_ hud: HUDState, _ db: PrototypeDB) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<10, id: \.self) { i in
                let item = controller.quickbarItem(i)
                let count = hud.quickbarCounts[i]
                Button {
                    if item >= 0 {
                        if controller.mode == .build && controller.buildItem == item { controller.cancelMode() }
                        else if count > 0 { controller.selectBuildItem(item) }
                        else { controller.show("No \(db.items[item].name) — craft some first") }
                    }
                } label: {
                    SlotView(highlighted: controller.mode == .build && controller.buildItem == item && item >= 0, size: 48) {
                        if item >= 0 { ItemIcon(item: item, db: db, count: count, size: 36).opacity(count > 0 ? 1 : 0.35) }
                    }
                }
                .buttonStyle(.plain)
            }
            Button { controller.quickbarPage = 1 - controller.quickbarPage } label: {
                Text("\(controller.quickbarPage + 1)").font(.caption.bold()).foregroundStyle(Theme.textDim)
                    .frame(width: 22, height: 48)
            }.buttonStyle(.plain)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.45)))
    }
}

// MARK: - Joystick

struct JoystickView: View {
    let onChange: (CGVector) -> Void
    @State private var knob: CGSize = .zero
    @State private var active = false
    private let radius: CGFloat = 60

    var body: some View {
        ZStack {
            Circle().fill(Color.black.opacity(active ? 0.35 : 0.2)).frame(width: radius * 2, height: radius * 2)
            Circle().stroke(Color.white.opacity(0.25), lineWidth: 2).frame(width: radius * 2, height: radius * 2)
            Circle().fill(Color.white.opacity(active ? 0.6 : 0.35)).frame(width: 52, height: 52).offset(knob)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { v in
                    active = true
                    var dx = v.translation.width, dy = v.translation.height
                    let len = (dx * dx + dy * dy).squareRoot()
                    if len > radius { dx = dx / len * radius; dy = dy / len * radius }
                    knob = CGSize(width: dx, height: dy)
                    let n = min(1, len / radius)
                    if n < 0.12 { onChange(CGVector(dx: 0, dy: 0)); return }       // dead zone
                    onChange(CGVector(dx: dx / max(len, 1) * n, dy: dy / max(len, 1) * n))
                }
                .onEnded { _ in
                    active = false
                    knob = .zero
                    onChange(CGVector(dx: 0, dy: 0))
                }
        )
    }
}


// MARK: - Minimap

struct MinimapView: View {
    @Bindable var controller: GameController
    var size: CGFloat = 96
    var body: some View {
        Button { controller.openMap() } label: {
            ZStack {
                Rectangle().fill(Color.black)
                if let img = controller.minimap {
                    Image(img, scale: 1, label: Text("Minimap")).interpolation(.none).resizable()
                }
                Circle().fill(Color.white).frame(width: 7, height: 7)
                    .overlay(Circle().stroke(Color.black, lineWidth: 1.5))
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
