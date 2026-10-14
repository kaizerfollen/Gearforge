// Gearforge — main menu, new game (campaign + freeplay), load game, settings.

import SwiftUI
import FactoryCore

struct MainMenuView: View {
    @Bindable var model: AppModel
    @Environment(\.verticalSizeClass) private var vClass

    var body: some View {
        let compact = vClass == .compact
        HStack(spacing: compact ? 24 : 40) {
            VStack(alignment: .leading, spacing: 8) {
                SpriteImage(name: "i_assembling_machine_2", size: compact ? 72 : 96)
                Text("GEARFORGE").font(.system(size: compact ? 44 : 54, weight: .heavy, design: .rounded)).foregroundStyle(Theme.accent)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text("Build. Automate. Launch.").font(.title3).foregroundStyle(Theme.textDim)
                    .lineLimit(2).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: 360, alignment: .leading)
            ScrollView {
            VStack(spacing: compact ? 10 : 12) {
                if model.offerRecovery {
                    MenuButton(title: "Restore last session", subtitle: "The game was closed unexpectedly") {
                        model.load(slot: SaveManager.backgroundSlot)
                    }
                }
                MenuButton(title: "Continue", subtitle: model.saves.first.map { "\(L($0.displayName)) · \(formatPlayTime($0.playTimeSeconds))" },
                           enabled: model.canContinue) { model.continueLatest() }
                MenuButton(title: "New Game") { model.screen = .newGame }
                MenuButton(title: "Load Game", enabled: model.canContinue) { model.refreshSaves(); model.screen = .load }
                MenuButton(title: "Settings") { model.screen = .settings }
            }
            .padding(.vertical, 8)
            }
            .scrollBounceBehavior(.basedOnSize)
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, compact ? 20 : 40).padding(.vertical, compact ? 8 : 40)
    }
}

func formatPlayTime(_ s: Double) -> String {
    let m = Int(s) / 60
    return m >= 60 ? LF("%@ h %@ min", "\(m / 60)", "\(m % 60)") : LF("%@ min", "\(m)")
}

// MARK: - New game

struct NewGameView: View {
    @Bindable var model: AppModel
    @State private var tab = 0
    @State private var seedText = String(UInt32.random(in: 1...UInt32.max))
    @State private var sizeIndex = 1
    @State private var richness = 1.0
    @State private var techPrice = 1.0
    @State private var extendedKit = false
    @State private var casualReach = false
    @State private var perpetualDay = false
    @State private var trees = 1.0

    private let sizes = [256, 512, 1024, 2048]

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button { model.screen = .menu } label: { SpriteImage(name: "ui_close", size: 30) }.buttonStyle(.plain)
                Spacer()
                Picker("Mode", selection: $tab) {
                    Text("Campaign").tag(0)
                    Text("Freeplay").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 320)
                Spacer()
                Color.clear.frame(width: 30, height: 30)
            }
            if tab == 0 { campaign } else { freeplay }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: 1000)
    }

    private var campaign: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(Campaign.levels) { l in
                    let unlocked = model.progress.isUnlocked(l.id)
                    let entry = model.progress.levels[l.id]
                    Button { if unlocked { model.startCampaign(l) } } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(l.id).font(.caption.bold()).foregroundStyle(Theme.accent)
                                Spacer()
                                HStack(spacing: 2) {
                                    ForEach(0..<3, id: \.self) { i in
                                        Text("★").foregroundStyle(i < (entry?.stars ?? 0) ? Theme.accent : Color.white.opacity(0.2))
                                    }
                                }
                            }
                            Text(Names.levelTitle(l)).font(.system(size: 22, weight: .bold, design: .rounded)).foregroundStyle(Theme.text)
                            Text(Names.levelSubtitle(l)).font(.subheadline).foregroundStyle(Theme.textDim)
                            Text(Names.levelTeaches(l)).font(.caption).foregroundStyle(Theme.textDim).lineLimit(4)
                            Spacer()
                            HStack {
                                Text(LF("Par %@ min", "\(l.parSeconds / 60)")).font(.caption2)
                                Spacer()
                                if let b = entry?.bestSeconds, b.isFinite { Text(LF("Best %@ min", "\(Int(b) / 60)")).font(.caption2) }
                            }.foregroundStyle(Theme.textDim)
                        }
                        .padding(14)
                        .frame(width: 210, height: 240)
                        .background(RoundedRectangle(cornerRadius: 14).fill(unlocked ? Theme.panelLight : Theme.panel))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(unlocked ? Theme.accent.opacity(0.5) : Color.clear, lineWidth: 1))
                        .overlay(alignment: .bottomTrailing) {
                            if !unlocked { Image(systemName: "lock.fill").font(.title3).foregroundStyle(Theme.textDim).padding(14) }
                        }
                        .opacity(unlocked ? 1 : 0.6)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 8)
        }
    }

    private var freeplay: some View {
        HStack(alignment: .top, spacing: 20) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    row("Seed") { TextField("Seed", text: $seedText).textFieldStyle(.roundedBorder).frame(maxWidth: 220) }
                    row("Map size") {
                        FitPicker("Map size", selection: $sizeIndex, options: [("Small", 0), ("Medium", 1), ("Large", 2), ("Huge", 3)])
                    }
                    row("Resource richness") { slider($richness, 0.5...3, fmt: "%.0f%%", scale: 100) }
                    row("Tech price") {
                        FitPicker("Tech price", selection: $techPrice, options: [("×0.5", 0.5), ("×1", 1.0), ("×2", 2.0), ("×4", 4.0)])
                    }
                    row("Trees") { slider($trees, 0...2, fmt: "%.0f%%", scale: 100) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            VStack(alignment: .leading, spacing: 12) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Extended starting kit", isOn: $extendedKit)
                        Toggle("Casual reach (build anywhere on screen)", isOn: $casualReach)
                        Toggle("Perpetual day", isOn: $perpetualDay)
                    }
                    .tint(Theme.accent)
                }
                .scrollBounceBehavior(.basedOnSize)
                Button { model.startFreeplay(makeSettings()) } label: {
                    Text("Start Freeplay").font(.system(size: 18, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .foregroundStyle(Theme.text)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.panelLight))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.accent.opacity(0.6), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            .frame(minWidth: 220, maxWidth: 340)
        }
        .foregroundStyle(Theme.text)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.panel))
    }

    /// Label on its own line above the control, so long (Russian) labels never push controls off screen.
    private func row<C: View>(_ title: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(LocalizedStringKey(title)).font(.subheadline).foregroundStyle(Theme.textDim)
            c()
        }
    }

    private func slider(_ v: Binding<Double>, _ r: ClosedRange<Double>, fmt: String, scale: Double) -> some View {
        HStack {
            Slider(value: v, in: r).frame(maxWidth: 300)
            Text(String(format: fmt, v.wrappedValue * scale)).monospacedDigit().frame(width: 60, alignment: .trailing)
        }
    }

    private func makeSettings() -> WorldSettings {
        var s = WorldSettings()
        s.seed = UInt64(seedText.filter(\.isNumber)) ?? UInt64(UInt32.random(in: 1...UInt32.max))
        s.width = sizes[sizeIndex]; s.height = sizes[sizeIndex]
        for r in ["iron_ore", "copper_ore", "coal", "stone", "crude_oil"] {
            s.resourceSettings[r] = ResourceGenSetting(frequency: 1, size: 1, richness: richness)
        }
        s.techPriceMultiplier = techPrice
        s.treeCoverage = trees
        s.startingKit = extendedKit ? "extended" : "standard"
        s.casualReach = casualReach
        s.dayNight = perpetualDay ? "perpetual_day" : "normal"
        return s
    }
}

// MARK: - Load game

struct LoadGameView: View {
    @Bindable var model: AppModel
    @State private var confirmDelete: SaveMetadata?
    @State private var renaming: SaveMetadata?
    @State private var newName = ""

    var body: some View {
        PanelChrome(title: "Load game", onClose: { model.screen = .menu }) {
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(model.saves) { m in
                        HStack(spacing: 14) {
                            SaveThumbnail(model: model, slot: m.slot)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(L(m.displayName)).font(.headline).foregroundStyle(Theme.text)
                                    .lineLimit(1).minimumScaleFactor(0.7)
                                Text(describe(m)).font(.caption).foregroundStyle(Theme.textDim).lineLimit(2)
                            }
                            Spacer()
                            Text(m.savedAt, style: .relative).font(.caption).foregroundStyle(Theme.textDim)
                            Button("Load") { model.load(slot: m.slot) }.buttonStyle(.borderedProminent).tint(Theme.accent)
                            Button { newName = L(m.displayName); renaming = m } label: { Text("Rename").font(.caption) }.buttonStyle(.bordered)
                            Button { confirmDelete = m } label: { SpriteImage(name: "ui_remove", size: 24) }.buttonStyle(.plain)
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.panelLight))
                    }
                    if model.saves.isEmpty { Text("No saves yet").foregroundStyle(Theme.textDim).padding() }
                }
                .padding(16)
            }
        }
        .panelFrame(maxWidth: 760, maxHeight: 560)
        .alert("Rename save", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Save name", text: $newName)
            Button("Rename") {
                if let m = renaming {
                    do { try model.saveManager.rename(slot: m.slot, to: newName); model.refreshSaves() }
                    catch { model.errorMessage = L("Can't rename: use a new, non-empty name without / or :") }
                }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .confirmationDialog("Delete save?", isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } })) {
            Button("Delete", role: .destructive) {
                if let m = confirmDelete { try? model.saveManager.delete(slot: m.slot); model.refreshSaves() }
                confirmDelete = nil
            }
        }
    }

    private func describe(_ m: SaveMetadata) -> String {
        var s: String
        switch m.mode {
        case .freeplay: s = L("Freeplay")
        case .campaign(let id): s = L("Campaign") + " · " + (Campaign.levels.first { $0.id == id }.map(Names.levelTitle) ?? m.levelTitle ?? "")
        }
        s += " · \(formatPlayTime(m.playTimeSeconds)) · \(m.mapWidth)×\(m.mapHeight)"
        if m.isAutosave { s += " · " + L("autosave") }
        return s
    }
}

// MARK: - Settings

struct SettingsView: View {
    @Bindable var model: AppModel
    var onClose: (() -> Void)? = nil

    var body: some View {
        PanelChrome(title: "Settings", onClose: { if let c = onClose { c() } else { model.screen = .menu } }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    section("Gameplay") {
                        FitPicker("Autosave", selection: $model.settings.autosaveMinutes,
                                  options: [("Off", 0), ("2 min", 2), ("5 min", 5), ("10 min", 10), ("15 min", 15)])
                        Stepper(LF("Autosave slots: %@", "\(model.settings.autosaveSlots)"), value: $model.settings.autosaveSlots, in: 1...5)
                        Toggle("Auto-build ghosts in reach", isOn: $model.settings.autoBuildGhosts)
                    }
                    section("Controls") {
                        Toggle("Long-press empty ground to walk there", isOn: $model.settings.tapToWalk)
                        Toggle("Confirm placement with a second tap", isOn: $model.settings.confirmPlacement)
                    }
                    section("Interface") {
                        Toggle("Alt-mode (recipe icons on machines)", isOn: $model.settings.altMode)
                        Toggle("Show reach circle", isOn: $model.settings.showReachCircle)
                        Toggle("Haptics", isOn: $model.settings.haptics)
                        Toggle("Left-handed layout", isOn: $model.settings.leftHanded)
                        Toggle("Tutorial hints", isOn: $model.settings.tutorialHints)
                        HStack {
                            Text("Interface size")
                            Slider(value: $model.settings.uiScale, in: 0.8...1.4, step: 0.1)
                            Text(verbatim: "\(Int((model.settings.uiScale * 100).rounded()))%").monospacedDigit().frame(width: 52)
                        }
                        FitPicker("Grid", selection: $model.settings.showGrid,
                                  options: [("Grid off", "off"), ("Grid when building", "build"), ("Grid always", "always")])
                    }
                    section("Accessibility") {
                        Picker("Colour-blind palette", selection: $model.settings.colorblindMode) {
                            Text("Standard").tag("off"); Text("Deuteranopia").tag("deuteranopia")
                            Text("Protanopia").tag("protanopia"); Text("Tritanopia").tag("tritanopia")
                        }.pickerStyle(.menu)
                        Toggle("Reduce motion (no belt / machine animation)", isOn: $model.settings.reduceMotion)
                    }
                    section("Graphics & performance") {
                        Toggle("Day/night lighting", isOn: $model.settings.dayNightLighting)
                        FitPicker("Frame rate", selection: $model.settings.frameRateCap, options: [("30", 30), ("60", 60), ("120", 120)])
                        Toggle("Battery saver (30 FPS rendering)", isOn: $model.settings.batterySaver)
                        Toggle("Show FPS", isOn: $model.settings.showFPS)
                    }
                    section("Audio") {
                        HStack { Text("Master"); Slider(value: $model.settings.masterVolume, in: 0...1) }
                        HStack { Text("Music"); Slider(value: $model.settings.musicVolume, in: 0...1) }
                        HStack { Text("Sound effects"); Slider(value: $model.settings.sfxVolume, in: 0...1) }
                    }
                    Text("Gearforge · original factory game · no ads, no tracking").font(.caption).foregroundStyle(Theme.textDim)
                }
                .padding(20)
                .foregroundStyle(Theme.text)
            }
        }
        .panelFrame(maxWidth: 680, maxHeight: 560)
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L(title).uppercased()).font(.caption.bold()).foregroundStyle(Theme.accent)
            c()
        }
    }
}


/// Save-slot thumbnail (map snapshot stored in the save's THMB section), loaded lazily per row.
struct SaveThumbnail: View {
    let model: AppModel
    let slot: String
    @State private var image: UIImage? = nil
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.5))
            if let img = image { Image(uiImage: img).interpolation(.none).resizable().clipShape(RoundedRectangle(cornerRadius: 6)) }
        }
        .frame(width: 96, height: 54)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.15), lineWidth: 1))
        .onAppear {
            if image == nil, let png = model.saveManager.thumbnail(slot: slot) { image = UIImage(data: png) }
        }
    }
}
