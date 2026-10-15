// Gearforge — HUD overlay (GDD §5): power + time, objectives, research bar, mode buttons, quickbar, craft queue,
// joystick, selection card, toasts.

import SwiftUI
import FactoryCore

struct HUDView: View {
    @Bindable var model: AppModel
    @Bindable var controller: GameController

    private var leftHanded: Bool { controller.settings.leftHanded }
    @Environment(\.verticalSizeClass) private var vClass
    /// iPhone in landscape (~750 × 370 pt inside the safe area): narrower info column, smaller joystick area and
    /// the quickbar laid out between the joystick and the mode buttons instead of under them.
    private var compact: Bool { vClass == .compact }
    private var joystickSide: CGFloat { compact ? 150 : 180 }
    /// Width the mode-button column takes at the screen edge (2 × 52 pt buttons + gap + edge padding, scaled).
    private var modeColumnWidth: CGFloat { (48 + 8 + 48) * Theme.uiScale + 16 }

    var body: some View {
        let hud = controller.hud
        let db = controller.world.db
        ZStack {
            // Top bar
            VStack {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        statusChip(hud)
                        if let t = controller.tutorialHint, controller.panel == nil {
                            TutorialCard(controller: controller, hint: t)       // guided tutorial replaces the goals list
                        } else if !hud.objectives.isEmpty { objectives(hud) }
                        if let hint = hud.hint, controller.tutorialHint == nil, hud.selectedName.isEmpty { hintBubble(hint, hud.hintObjective) }
                        if !hud.selectedName.isEmpty { selectionCard(hud, db) }
                    }
                    .frame(width: compact ? (controller.tutorialHint != nil ? 250 : 210) : 280, alignment: .leading)
                    .tutorialAnchor("objectives")
                    Spacer(minLength: 8)
                    researchBar(hud).layoutPriority(-1).tutorialAnchor("research")
                    Spacer(minLength: 8)
                    HStack(alignment: .top, spacing: 8) {
                        MinimapView(controller: controller).tutorialAnchor("minimap")
                        Button { controller.panel = .guide } label: {
                            Text(verbatim: "?").font(.system(size: 22 * Theme.uiScale, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .frame(width: 44 * Theme.uiScale, height: 44 * Theme.uiScale)
                                .background(Circle().fill(Color.black.opacity(0.55)))
                                .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("How to play"))
                        HUDButton(glyph: "ui_altmode", active: controller.altMode, size: 44) { controller.altMode.toggle() }
                        HUDButton(glyph: "ui_stats", size: 44) { controller.panel = .stats }
                        HUDButton(glyph: "ui_pause", size: 44) { controller.panel = .pause }
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 16).padding(.top, 10)

            // Mode column (right; left in the left-handed layout)
            HStack {
                if !leftHanded { Spacer() }
                VStack(spacing: 8) {
                    Spacer()
                    // compact 2-column grid so the column fits an iPhone in landscape
                    HStack(spacing: 8) {
                        HUDButton(glyph: "ui_build", active: controller.mode == .build, size: 48) {
                            if controller.mode == .build { controller.cancelMode() } else { controller.panel = .inventory }
                        }
                        .tutorialAnchor("build")
                        HUDButton(glyph: "ui_remove", active: controller.mode == .remove, size: 48) {
                            controller.mode = controller.mode == .remove ? .explore : .remove
                        }
                    }
                    HStack(spacing: 8) {
                        HUDButton(glyph: "ui_copy", active: controller.mode == .copy, size: 44) {
                            if controller.mode == .copy { controller.cancelMode() } else { controller.beginCopy() }
                        }
                        HUDButton(glyph: "ui_paste", active: controller.mode == .paste, size: 44) {
                            if controller.mode == .paste { controller.cancelMode() } else { controller.beginPaste() }
                        }
                        .opacity(controller.clipboard == nil ? 0.4 : 1)
                    }
                    HStack(spacing: 8) {
                        if controller.mode == .build || controller.mode == .paste {
                            HUDButton(glyph: "ui_rotate", size: 44) {
                                if controller.mode == .paste { controller.rotatePaste() } else { controller.rotateBuild() }
                            }
                        } else {
                            HUDButton(glyph: "ui_undo", size: 44) { controller.undo() }.opacity(hud.canUndo ? 1 : 0.4)
                        }
                        HUDButton(glyph: "ui_redo", size: 44) { controller.redo() }.opacity(hud.canRedo ? 1 : 0.4)
                    }
                    HUDButton(glyph: "ui_inventory", size: 56) { controller.panel = .inventory }.tutorialAnchor("inventory")
                }
                .padding(leftHanded ? .leading : .trailing, 16).padding(.bottom, 16)
                if leftHanded { Spacer() }
            }

            // Bottom: craft queue + quickbar
            VStack(spacing: 6) {
                Spacer()
                if let t = controller.toast {
                    Text(t).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Capsule().fill(Color.black.opacity(0.7)))
                }
                if controller.mode == .copy || controller.mode == .paste {
                    Text(controller.mode == .copy ? L("Drag over buildings to copy them") : L("Tap a spot to preview, tap again to place"))
                        .font(.caption.bold()).foregroundStyle(Theme.accent)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(Color.black.opacity(0.6)))
                }
                if !hud.buildReason.isEmpty && controller.mode == .build {
                    Text(L(hud.buildReason)).font(.caption.bold()).foregroundStyle(Theme.bad)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(Color.black.opacity(0.6)))
                }
                if hud.miningProgress >= 0 {
                    BarView(fraction: hud.miningProgress, color: Theme.good, height: 8).frame(width: 160)
                }
                if !hud.craftQueue.isEmpty { craftQueue(hud, db) }
                ViewThatFits(in: .horizontal) {
                    quickbar(hud, db)
                    ScrollView(.horizontal, showsIndicators: false) { quickbar(hud, db) }
                }
            }
            .padding(.bottom, 10)
            // keep the bottom bar clear of the joystick and the mode column on narrow screens
            .padding(.leading, compact ? (leftHanded ? modeColumnWidth : joystickSide + 8) : 0)
            .padding(.trailing, compact ? (leftHanded ? joystickSide + 8 : modeColumnWidth) : 0)

            // Joystick (bottom-left; bottom-right in the left-handed layout)
            VStack {
                Spacer()
                HStack {
                    if leftHanded { Spacer() }
                    JoystickView { v in
                        controller.world.player.moveInput = Vec2(Double(v.dx), Double(v.dy))
                        if v.dx != 0 || v.dy != 0 { controller.cameraFollowsPlayer = true }
                    }
                    .frame(width: joystickSide, height: joystickSide)
                    .tutorialAnchor("joystick")
                    .padding(leftHanded ? .trailing : .leading, compact ? 8 : 20).padding(.bottom, compact ? 6 : 16)
                    if !leftHanded { Spacer() }
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

    private func hintBubble(_ text: String, _ objective: Int) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lightbulb.fill").foregroundStyle(Theme.accent).font(.caption)
            Text(text).font(.caption).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button { controller.dismissedHints.insert(objective); controller.refreshHUD() } label: {
                Image(systemName: "xmark").font(.caption2.bold()).foregroundStyle(Theme.textDim)
            }.buttonStyle(.plain)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.accent.opacity(0.18)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.accent.opacity(0.5), lineWidth: 1))
    }

    private func selectionCard(_ hud: HUDState, _ db: PrototypeDB) -> some View {
        Button {
            if let h = controller.selected { controller.openEntity(h) }
        } label: {
            HStack(spacing: 8) {
                if !hud.selectedRecipeIcon.isEmpty { SpriteImage(name: "i_\(hud.selectedRecipeIcon)", size: 30) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(hud.selectedName).font(.caption.bold()).foregroundStyle(Theme.text).lineLimit(2)
                    if let s = hud.selectedStatus { Text(L(s.label)).font(.caption2).foregroundStyle(s.color).lineLimit(1) }
                    if hud.selectedProgress > 0 { BarView(fraction: hud.selectedProgress, height: 3).frame(maxWidth: 120) }
                }
                Spacer(minLength: 4)
                Text("Open ›").font(.caption2).foregroundStyle(Theme.accent).fixedSize()
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
                        .lineLimit(2).multilineTextAlignment(.leading).minimumScaleFactor(0.85)
                } else {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(hud.researchName).font(.caption.bold()).foregroundStyle(Theme.text).lineLimit(1).minimumScaleFactor(0.8)
                        BarView(fraction: hud.researchProgress, height: 4).frame(minWidth: 50, maxWidth: 160)
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
        let slot: CGFloat = compact ? 40 : 48
        return HStack(spacing: compact ? 3 : 4) {
            ForEach(0..<10, id: \.self) { i in
                let item = controller.quickbarItem(i)
                let count = hud.quickbarCounts[i]
                Button {
                    if item >= 0 {
                        if controller.mode == .build && controller.buildItem == item { controller.cancelMode() }
                        else if count > 0 { controller.selectBuildItem(item) }
                        else { controller.show(LF("No %@ — craft some first", db.itemName(item))) }
                    }
                } label: {
                    SlotView(highlighted: controller.mode == .build && controller.buildItem == item && item >= 0, size: slot) {
                        if item >= 0 { ItemIcon(item: item, db: db, count: count, size: slot * 0.75).opacity(count > 0 ? 1 : 0.35) }
                    }
                }
                .buttonStyle(.plain)
                .tutorialAnchor("quickbar.\(i)")
            }
            Button { controller.quickbarPage = 1 - controller.quickbarPage } label: {
                Text("\(controller.quickbarPage + 1)").font(.caption.bold()).foregroundStyle(Theme.textDim)
                    .frame(width: 22, height: slot)
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
