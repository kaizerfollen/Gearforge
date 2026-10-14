// Gearforge — main menu, new game (campaign + freeplay), load game, settings.

import SwiftUI
import FactoryCore

struct MainMenuView: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: 40) {
            VStack(alignment: .leading, spacing: 8) {
                SpriteImage(name: "i_assembling_machine_2", size: 96)
                Text("GEARFORGE").font(.system(size: 54, weight: .heavy, design: .rounded)).foregroundStyle(Theme.accent)
                Text("Build. Automate. Launch.").font(.title3).foregroundStyle(Theme.textDim)
            }
            VStack(spacing: 12) {
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
        }
        .padding(40)
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
        VStack(spacing: 16) {
            HStack {
                Button { model.screen = .menu } label: { SpriteImage(name: "ui_close", size: 30) }.buttonStyle(.plain)
                Spacer()
                Picker("Mode", selection: $tab) {
                    Text("Campaign").tag(0)
                    Text("Freeplay").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 320)
                Spacer()
                Color.clear.frame(width: 30, height: 30)
            }
            if tab == 0 { campaign } else { freeplay }
        }
        .padding(24)
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
                        .padding(16)
                        .frame(width: 220, height: 260)
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
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 14) {
                row("Seed") { TextField("Seed", text: $seedText).textFieldStyle(.roundedBorder).frame(width: 180) }
                row("Map size") {
                    Picker("Size", selection: $sizeIndex) {
                        Text("Small").tag(0); Text("Medium").tag(1); Text("Large").tag(2); Text("Huge").tag(3)
                    }.pickerStyle(.segmented).frame(width: 320)
                }
                row("Resource richness") { slider($richness, 0.5...3, fmt: "%.0f%%", scale: 100) }
                row("Tech price") {
                    Picker("Tech price", selection: $techPrice) {
                        Text("×0.5").tag(0.5); Text("×1").tag(1.0); Text("×2").tag(2.0); Text("×4").tag(4.0)
                    }.pickerStyle(.segmented).frame(width: 320)
                }
                row("Trees") { slider($trees, 0...2, fmt: "%.0f%%", scale: 100) }
            }
            VStack(alignment: .leading, spacing: 14) {
                Toggle("Extended starting kit", isOn: $extendedKit)
                Toggle("Casual reach (build anywhere on screen)", isOn: $casualReach)
                Toggle("Perpetual day", isOn: $perpetualDay)
                Spacer()
                MenuButton(title: "Start Freeplay") { model.startFreeplay(makeSettings()) }
            }
            .frame(width: 340)
        }
        .foregroundStyle(Theme.text)
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.panel))
    }

    private func row<C: View>(_ title: String, @ViewBuilder _ c: () -> C) -> some View {
        HStack {
            Text(LocalizedStringKey(title)).frame(width: 170, alignment: .leading).foregroundStyle(Theme.textDim)
            c()
        }
    }

    private func slider(_ v: Binding<Double>, _ r: ClosedRange<Double>, fmt: String, scale: Double) -> some View {
        HStack {
            Slider(value: v, in: r).frame(width: 240)
            Text(String(format: fmt, v.wrappedValue * scale)).monospacedDigit().frame(width: 60)
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

    var body: some View {
        PanelChrome(title: "Load game", onClose: { model.screen = .menu }) {
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(model.saves) { m in
                        HStack(spacing: 14) {
                            SaveThumbnail(model: model, slot: m.slot)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(L(m.displayName)).font(.headline).foregroundStyle(Theme.text)
                                Text(describe(m)).font(.caption).foregroundStyle(Theme.textDim)
                            }
                            Spacer()
                            Text(m.savedAt, style: .relative).font(.caption).foregroundStyle(Theme.textDim)
                            Button("Load") { model.load(slot: m.slot) }.buttonStyle(.borderedProminent).tint(Theme.accent)
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
        .frame(maxWidth: 760, maxHeight: 520)
        .padding(30)
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
                        Picker("Autosave", selection: $model.settings.autosaveMinutes) {
                            Text("Off").tag(0); Text("2 min").tag(2); Text("5 min").tag(5); Text("10 min").tag(10); Text("15 min").tag(15)
                        }.pickerStyle(.segmented)
                        Stepper(LF("Autosave slots: %@", "\(model.settings.autosaveSlots)"), value: $model.settings.autosaveSlots, in: 1...5)
                        Toggle("Auto-build ghosts in reach", isOn: $model.settings.autoBuildGhosts)
                    }
                    section("Interface") {
                        Toggle("Alt-mode (recipe icons on machines)", isOn: $model.settings.altMode)
                        Toggle("Show reach circle", isOn: $model.settings.showReachCircle)
                        Toggle("Haptics", isOn: $model.settings.haptics)
                        Toggle("Left-handed layout", isOn: $model.settings.leftHanded)
                        Toggle("Tutorial hints", isOn: $model.settings.tutorialHints)
                    }
                    section("Graphics & performance") {
                        Toggle("Day/night lighting", isOn: $model.settings.dayNightLighting)
                        Picker("Frame rate", selection: $model.settings.frameRateCap) {
                            Text("30").tag(30); Text("60").tag(60); Text("120").tag(120)
                        }.pickerStyle(.segmented)
                        Toggle("Battery saver (30 FPS rendering)", isOn: $model.settings.batterySaver)
                        Toggle("Show FPS", isOn: $model.settings.showFPS)
                    }
                    section("Audio") {
                        HStack { Text("Master"); Slider(value: $model.settings.masterVolume, in: 0...1) }
                    }
                    Text("Gearforge · original factory game · no ads, no tracking").font(.caption).foregroundStyle(Theme.textDim)
                }
                .padding(20)
                .foregroundStyle(Theme.text)
            }
        }
        .frame(maxWidth: 680, maxHeight: 560)
        .padding(30)
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
