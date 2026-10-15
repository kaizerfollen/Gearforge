// Gearforge — guided tutorial overlay: a pulsing frame + arrow on the element to tap (HUD buttons, quickbar slots,
// panel items — found through `.tutorialAnchor(id)`), an arrow at the screen edge pointing to world targets that are
// off screen (the ground marker itself is drawn by GameScene), and the step card with Next / Skip.
// Script and completion rules: FactoryCore/Progression/Tutorial.swift; design notes: docs/TUTORIAL.md.

import SwiftUI
import FactoryCore

struct TutorialAnchors: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] { [:] }
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// Marks a view as something the tutorial can point at.
    func tutorialAnchor(_ id: String) -> some View {
        anchorPreference(key: TutorialAnchors.self, value: .bounds) { [id: $0] }
    }
}

struct TutorialOverlay: View {
    @Bindable var controller: GameController
    let scene: GameScene?
    let anchors: [String: Anchor<CGRect>]
    @State private var pulse = false

    var body: some View {
        GeometryReader { proxy in
            if let h = controller.tutorialHint {
                let _ = controller.hud          // refresh with the HUD (camera moves, panels open)
                ZStack(alignment: .topLeading) {
                    highlight(h, proxy)
                    card(h, proxy)
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            }
        }
        .onAppear { withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { pulse = true } }
    }

    // MARK: Highlight

    @ViewBuilder private func highlight(_ h: TutorialHint, _ proxy: GeometryProxy) -> some View {
        switch h.target {
        case .none:
            EmptyView()
        case .hud(let ids):
            if let id = ids.first(where: { anchors[$0] != nil }), let a = anchors[id] {
                ring(proxy[a], proxy)
            }
        case .tiles(let r):
            if let s = scene, let vr = s.viewRect(forTiles: r) {
                let g = proxy.frame(in: .global)
                let rect = vr.offsetBy(dx: -g.minX, dy: -g.minY)
                let inside = CGRect(origin: .zero, size: proxy.size).insetBy(dx: 30, dy: 30)
                if !inside.intersects(rect) { edgeArrow(toward: CGPoint(x: rect.midX, y: rect.midY), proxy) }
            }
        }
    }

    private func ring(_ r: CGRect, _ proxy: GeometryProxy) -> some View {
        let pad: CGFloat = 6
        let frame = r.insetBy(dx: -pad, dy: -pad)
        // arrow above the element, or below it when the element is near the top edge
        let below = frame.minY < 70
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.accent, lineWidth: 3)
                .shadow(color: Theme.accent.opacity(0.8), radius: 8)
                .frame(width: frame.width, height: frame.height)
                .scaleEffect(pulse ? 1.08 : 0.97)
                .position(x: frame.midX, y: frame.midY)
            Image(systemName: below ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Theme.accent)
                .shadow(color: .black.opacity(0.6), radius: 2)
                .position(x: frame.midX, y: below ? frame.maxY + 18 + (pulse ? 6 : 0) : frame.minY - 18 - (pulse ? 6 : 0))
        }
        .allowsHitTesting(false)
    }

    private func edgeArrow(toward p: CGPoint, _ proxy: GeometryProxy) -> some View {
        let c = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
        let dx = p.x - c.x, dy = p.y - c.y
        let angle = atan2(dy, dx)
        // clamp to an ellipse inside the screen
        let rx = proxy.size.width / 2 - 50, ry = proxy.size.height / 2 - 50
        let t = 1 / max(abs(cos(angle)) / rx, abs(sin(angle)) / ry)
        let pos = CGPoint(x: c.x + cos(angle) * t, y: c.y + sin(angle) * t)
        return Image(systemName: "arrow.right.circle.fill")
            .font(.system(size: 40, weight: .bold))
            .foregroundStyle(Theme.accent)
            .background(Circle().fill(Color.black.opacity(0.5)).padding(2))
            .rotationEffect(.radians(Double(angle)))
            .scaleEffect(pulse ? 1.1 : 0.95)
            .position(pos)
            .allowsHitTesting(false)
    }

    // MARK: Card

    private func card(_ h: TutorialHint, _ proxy: GeometryProxy) -> some View {
        let panelOpen = controller.panel != nil
        let width = min(430, proxy.size.width - 260)
        let text = h.args.isEmpty ? L(h.text) : String(format: L(h.text), arguments: h.args.map { $0 as CVarArg })
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "graduationcap.fill").foregroundStyle(Theme.accent)
                Text("Tutorial").font(.caption.bold()).foregroundStyle(Theme.accent)
                Text(verbatim: "\(h.stepIndex + 1)/\(h.stepCount)").font(.caption).monospacedDigit().foregroundStyle(Theme.textDim)
                Spacer()
                if !h.isLast {
                    Button { controller.skipTutorial() } label: { Text("Skip tutorial").font(.caption) }
                        .buttonStyle(.plain).foregroundStyle(Theme.textDim)
                }
            }
            Text(text).font(.callout).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
            if h.needsNext {
                HStack {
                    Spacer()
                    Button { controller.tutorialNext() } label: {
                        Text(h.isLast ? "Got it" : "Next").font(.callout.bold()).padding(.horizontal, 10)
                    }
                    .buttonStyle(.borderedProminent).tint(Theme.accent)
                }
            }
        }
        .padding(12)
        .frame(width: max(260, width), alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.panel.opacity(0.96)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.accent.opacity(0.7), lineWidth: 1.5))
        .shadow(color: .black.opacity(0.5), radius: 10)
        .position(x: proxy.size.width / 2, y: cardY(h, proxy, panelOpen: panelOpen))
    }

    /// Under the top bar in the middle, unless that would cover what the player must tap; with a panel open at the
    /// bottom so the panel stays readable.
    private func cardY(_ h: TutorialHint, _ proxy: GeometryProxy, panelOpen: Bool) -> CGFloat {
        let top: CGFloat = 128, bottom = proxy.size.height - 132
        if panelOpen { return proxy.size.height - 62 }
        let topBand = CGRect(x: proxy.size.width / 2 - 230, y: 60, width: 460, height: 140)
        switch h.target {
        case .hud(let ids):
            if let id = ids.first(where: { anchors[$0] != nil }), let a = anchors[id], proxy[a].intersects(topBand) { return bottom }
        case .tiles(let r):
            if let s = scene, let vr = s.viewRect(forTiles: r) {
                let g = proxy.frame(in: .global)
                if vr.offsetBy(dx: -g.minX, dy: -g.minY).intersects(topBand) { return bottom }
            }
        case .none: break
        }
        return top
    }
}
