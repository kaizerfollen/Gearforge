// Gearforge — shared UI style: colours, panels, buttons, item icons.

import SwiftUI
import UIKit
import FactoryCore

enum Theme {
    static let background = Color(red: 0.09, green: 0.10, blue: 0.11)
    static let panel = Color(red: 0.16, green: 0.17, blue: 0.19)
    static let panelLight = Color(red: 0.23, green: 0.24, blue: 0.27)
    static let slot = Color(red: 0.11, green: 0.12, blue: 0.13)
    static let accent = Color(red: 0.98, green: 0.62, blue: 0.20)
    static let text = Color(white: 0.92)
    static let textDim = Color(white: 0.6)
    static let warn = Color(red: 0.98, green: 0.8, blue: 0.25)

    // MARK: Accessibility (GDD §10): colour-blind palettes and HUD scale, set by AppModel from GameSettings.
    /// "off" | "deuteranopia" | "protanopia" | "tritanopia"
    nonisolated(unsafe) static var colorblind = "off"
    /// HUD scale 0.8…1.4.
    nonisolated(unsafe) static var uiScale: CGFloat = 1

    /// "OK / valid / working" and "bad / invalid / no power" as RGB, per palette. Red–green deficiencies get
    /// blue vs orange; tritanopia gets green vs magenta-red. Ghost validity also shows ✓/✕ glyphs (not colour only).
    static var goodRGB: (CGFloat, CGFloat, CGFloat) {
        switch colorblind {
        case "deuteranopia", "protanopia": return (0.25, 0.6, 1.0)
        case "tritanopia": return (0.2, 0.8, 0.45)
        default: return (0.35, 0.85, 0.4)
        }
    }
    static var badRGB: (CGFloat, CGFloat, CGFloat) {
        switch colorblind {
        case "deuteranopia", "protanopia": return (1.0, 0.55, 0.1)
        case "tritanopia": return (0.95, 0.2, 0.45)
        default: return (0.95, 0.3, 0.25)
        }
    }
    static var good: Color { let c = goodRGB; return Color(red: Double(c.0), green: Double(c.1), blue: Double(c.2)) }
    static var bad: Color { let c = badRGB; return Color(red: Double(c.0), green: Double(c.1), blue: Double(c.2)) }
    static var goodUI: UIColor { let c = goodRGB; return UIColor(red: c.0, green: c.1, blue: c.2, alpha: 1) }
    static var badUI: UIColor { let c = badRGB; return UIColor(red: c.0, green: c.1, blue: c.2, alpha: 1) }

    static func powerColor(_ s: Double) -> Color { s >= 0.999 ? good : (s >= 0.5 ? warn : bad) }
}

/// Sprite from the atlas as a SwiftUI image.
struct SpriteImage: View {
    let name: String
    var size: CGFloat = 32
    var body: some View {
        Image(uiImage: SpriteCatalog.shared.image(name))
            .resizable()
            .interpolation(.medium)
            .frame(width: size, height: size)
    }
}

/// Item icon with an optional count badge.
struct ItemIcon: View {
    let item: Int
    let db: PrototypeDB
    var count: Int? = nil
    var size: CGFloat = 40
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(uiImage: SpriteCatalog.shared.itemIcon(item, db: db))
                .resizable()
                .interpolation(.medium)
                .frame(width: size, height: size)
            if let c = count {
                Text(c >= 10_000 ? "\(c / 1000)k" : "\(c)")
                    .font(.system(size: max(9, size * 0.28), weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .shadow(color: .black, radius: 1, x: 1, y: 1)
                    .offset(x: 2, y: 2)
            }
        }
    }
}

/// Inventory-style slot background.
struct SlotView<Content: View>: View {
    var highlighted = false
    var size: CGFloat = 52
    @ViewBuilder var content: () -> Content
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(Theme.slot)
            RoundedRectangle(cornerRadius: 6).stroke(highlighted ? Theme.accent : Color(white: 0.3), lineWidth: highlighted ? 2 : 1)
            content()
        }
        .frame(width: size, height: size)
    }
}

/// Round HUD button with a sprite glyph.
struct HUDButton: View {
    let glyph: String
    var active = false
    var size: CGFloat = 52
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(active ? Theme.accent.opacity(0.9) : Color.black.opacity(0.55))
                Circle().stroke(Color.white.opacity(0.25), lineWidth: 1)
                SpriteImage(name: glyph, size: size * Theme.uiScale * 0.55)
            }
            .frame(width: size * Theme.uiScale, height: size * Theme.uiScale)
        }
        .buttonStyle(.plain)
    }
}

/// Panel chrome with a title bar and close button.
struct PanelChrome<Content: View>: View {
    let title: String
    let onClose: () -> Void
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(LocalizedStringKey(title)).font(.system(size: 18, weight: .bold, design: .rounded)).foregroundStyle(Theme.text)
                Spacer()
                Button(action: onClose) { SpriteImage(name: "ui_close", size: 26) }.buttonStyle(.plain)
                    .tutorialAnchor("panel.close")
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Theme.panelLight)
            content()
        }
        .background(Theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 18, x: 0, y: 6)
    }
}

/// Wide menu button.
struct MenuButton: View {
    let title: String
    var subtitle: String? = nil
    var enabled = true
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(LocalizedStringKey(title)).font(.system(size: 20, weight: .semibold, design: .rounded))
                if let s = subtitle { Text(L(s)).font(.caption).foregroundStyle(Theme.textDim) }
            }
            .frame(width: 300, height: subtitle == nil ? 50 : 60)
            .foregroundStyle(enabled ? Theme.text : Theme.textDim)
            .background(RoundedRectangle(cornerRadius: 12).fill(enabled ? Theme.panelLight : Theme.panel))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.accent.opacity(enabled ? 0.6 : 0.2), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

/// Segmented picker that becomes a compact menu picker when its segments don't fit the width it is given
/// (long Russian labels on an iPhone in landscape). Labels are localization keys (or already-localized text).
struct FitPicker<T: Hashable>: View {
    let title: String
    @Binding var selection: T
    let options: [(String, T)]

    init(_ title: String, selection: Binding<T>, options: [(String, T)]) {
        self.title = title
        self._selection = selection
        self.options = options
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            picker.pickerStyle(.segmented)
            picker.pickerStyle(.menu).tint(Theme.accent)
        }
    }

    private var picker: some View {
        Picker(LocalizedStringKey(title), selection: $selection) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, o in Text(LocalizedStringKey(o.0)).tag(o.1) }
        }
    }
}

extension View {
    /// Panel sizing shared by every in-game panel and menu screen: never larger than `maxWidth`×`maxHeight`,
    /// never larger than the safe area minus `margin` (iPhone in landscape: notch / Dynamic Island on one side).
    func panelFrame(maxWidth: CGFloat, maxHeight: CGFloat, margin: CGFloat = 12) -> some View {
        self.frame(maxWidth: maxWidth, maxHeight: maxHeight)
            .padding(margin)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Thin progress bar.
struct BarView: View {
    let fraction: Double
    var color: Color = Theme.accent
    var height: CGFloat = 6
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                Capsule().fill(color).frame(width: g.size.width * CGFloat(max(0, min(1, fraction))))
            }
        }
        .frame(height: height)
    }
}

extension EntityStatus {
    var label: String {
        switch self {
        case .working: return "Working"
        case .idle: return "Idle"
        case .noInput: return "Waiting for ingredients"
        case .outputFull: return "Output full"
        case .noPower: return "No power"
        case .lowPower: return "Low power"
        case .noFuel: return "No fuel"
        case .noRecipe: return "No recipe"
        case .noResources: return "No resources"
        case .noResearch: return "No research"
        case .waitingForSource: return "Waiting for source"
        case .waitingForTarget: return "Waiting for target"
        case .disabled: return "Disabled"
        case .noFluid: return "No fluid"
        case .fluidFull: return "Fluid output full"
        case .noModules: return "No modules"
        }
    }
    var color: Color {
        switch self {
        case .working: return Theme.good
        case .lowPower, .noInput, .waitingForSource, .waitingForTarget, .idle: return Theme.warn
        default: return Theme.bad
        }
    }
}

/// 1 234 / 12.3k / 4.5M — compact counts for resource amounts.
func formatCount(_ n: Int) -> String {
    if n >= 10_000_000 { return LF("%@M", String(format: "%.0f", Double(n) / 1e6)) }
    if n >= 1_000_000 { return LF("%@M", String(format: "%.1f", Double(n) / 1e6)) }
    if n >= 100_000 { return LF("%@k", String(format: "%.0f", Double(n) / 1e3)) }
    if n >= 10_000 { return LF("%@k", String(format: "%.1f", Double(n) / 1e3)) }
    return "\(n)"
}

func formatWatts(_ w: Double) -> String {
    if w >= 1e9 { return LF("%@ GW", String(format: "%.1f", w / 1e9)) }
    if w >= 1e6 { return LF("%@ MW", String(format: "%.1f", w / 1e6)) }
    if w >= 1e3 { return LF("%@ kW", String(format: "%.0f", w / 1e3)) }
    return LF("%@ W", String(format: "%.0f", w))
}
