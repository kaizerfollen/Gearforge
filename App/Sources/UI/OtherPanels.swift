// Gearforge — research (tech tree), production statistics, pause menu.

import SwiftUI
import FactoryCore

struct ResearchPanel: View {
    @Bindable var controller: GameController
    @State private var filter = 0      // 0 available, 1 researched, 2 all
    @State private var selected: Int? = nil

    var body: some View {
        let _ = controller.hud
        let w = controller.world, db = w.db, r = w.research!
        let techs = db.technologies.indices.filter { t in
            let ph = db.technologies[t].phase
            guard ph == "mvp" else { return false }
            switch filter {
            case 0: return r.isAvailable(t) && !r.isResearched(t)
            case 1: return r.isResearched(t)
            default: return true
            }
        }.sorted { (db.technologies[$0].order ?? db.technologies[$0].id) < (db.technologies[$1].order ?? db.technologies[$1].id) }
        let cols = Array(repeating: GridItem(.fixed(72), spacing: 8), count: 8)
        return PanelChrome(title: "Research", onClose: { controller.panel = nil }) {
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Filter", selection: $filter) {
                        Text("Available").tag(0); Text("Researched").tag(1); Text("All").tag(2)
                    }.pickerStyle(.segmented).frame(width: 360)
                    if !r.queue.isEmpty {
                        HStack(spacing: 6) {
                            Text("Queue").font(.caption).foregroundStyle(Theme.textDim)
                            ForEach(r.queue, id: \.self) { t in
                                Image(uiImage: SpriteCatalog.shared.techIcon(t, db: db)).resizable().frame(width: 32, height: 32)
                                    .onTapGesture { controller.execute(.dequeueResearch(tech: t)) }
                            }
                        }
                    }
                    ScrollView {
                        LazyVGrid(columns: cols, spacing: 8) {
                            ForEach(techs, id: \.self) { t in
                                let done = r.isResearched(t)
                                VStack(spacing: 2) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 8).fill(done ? Theme.good.opacity(0.25) : (r.current == t ? Theme.accent.opacity(0.35) : Theme.slot))
                                        Image(uiImage: SpriteCatalog.shared.techIcon(t, db: db)).resizable().frame(width: 44, height: 44)
                                            .opacity(r.isAvailable(t) || done ? 1 : 0.35)
                                    }
                                    .frame(width: 64, height: 64)
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected == t ? Theme.accent : Color.clear, lineWidth: 2))
                                    Text(db.technologies[t].name).font(.system(size: 9)).foregroundStyle(Theme.textDim).lineLimit(2)
                                        .multilineTextAlignment(.center).frame(width: 72, height: 24)
                                }
                                .onTapGesture { selected = t }
                            }
                        }
                    }
                }
                .padding(14)
                .frame(width: 640)
                Divider().background(Color.white.opacity(0.1))
                detail(selected ?? r.current)
                    .padding(14)
            }
        }
        .frame(maxWidth: 1020, maxHeight: 620)
        .padding(20)
    }

    @ViewBuilder private func detail(_ t: Int) -> some View {
        let w = controller.world, db = w.db, r = w.research!
        if t >= 0 {
            let tp = db.technologies[t]
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(uiImage: SpriteCatalog.shared.techIcon(t, db: db)).resizable().frame(width: 52, height: 52)
                    VStack(alignment: .leading) {
                        Text(tp.name + (tp.maxLevel != nil && tp.maxLevel != 1 ? " \(r.level(of: t))" : "")).font(.headline).foregroundStyle(Theme.text)
                        Text(r.isResearched(t) ? "Researched" : (r.isAvailable(t) ? "Available" : "Locked")).font(.caption)
                            .foregroundStyle(r.isResearched(t) ? Theme.good : (r.isAvailable(t) ? Theme.accent : Theme.textDim))
                    }
                }
                HStack(spacing: 6) {
                    Text("\(r.unitCount(of: t)) ×").font(.caption).foregroundStyle(Theme.text)
                    ForEach(Array(tp.ingredients.enumerated()), id: \.offset) { _, ing in ItemIcon(item: db.item(ing.id), db: db, size: 24) }
                    Text(String(format: "%.0f s", tp.time)).font(.caption).foregroundStyle(Theme.textDim)
                }
                if r.progress(of: t) > 0 && !r.isResearched(t) { BarView(fraction: r.progress(of: t), height: 6).frame(width: 260) }
                if !db.techPrereqs[t].isEmpty {
                    Text("Requires").font(.caption).foregroundStyle(Theme.textDim)
                    HStack(spacing: 4) {
                        ForEach(db.techPrereqs[t], id: \.self) { p in
                            Image(uiImage: SpriteCatalog.shared.techIcon(p, db: db)).resizable().frame(width: 28, height: 28)
                                .opacity(r.isResearched(p) ? 1 : 0.5)
                                .onTapGesture { selected = p }
                        }
                    }
                }
                let unlocks = db.techUnlocks[t]
                if !unlocks.isEmpty {
                    Text("Unlocks").font(.caption).foregroundStyle(Theme.textDim)
                    HStack(spacing: 4) {
                        ForEach(unlocks, id: \.self) { u in Image(uiImage: SpriteCatalog.shared.recipeIcon(u, db: db)).resizable().frame(width: 28, height: 28) }
                    }
                }
                ForEach(Array(tp.effects.filter { $0.type != "unlock-recipe" }.enumerated()), id: \.offset) { _, ef in
                    Text("• \(effectText(ef))").font(.caption).foregroundStyle(Theme.text)
                }
                Spacer()
                if !r.isResearched(t) || tp.isInfinite {
                    HStack {
                        Button("Research now") { controller.execute(.setResearch(tech: t)) }.buttonStyle(.borderedProminent).tint(Theme.accent)
                        Button("Add to queue") { controller.execute(.enqueueResearch(tech: t)) }.buttonStyle(.bordered)
                    }
                }
            }
            .frame(width: 300, alignment: .leading)
        } else {
            Text("Pick a technology").foregroundStyle(Theme.textDim).frame(width: 300)
        }
    }

    private func effectText(_ e: TechEffect) -> String {
        let m = e.modifier ?? 0
        switch e.type {
        case "mining-drill-productivity-bonus": return String(format: "Mining productivity +%.0f%%", m * 100)
        case "laboratory-speed": return String(format: "Lab speed +%.0f%%", m * 100)
        case "inserter-stack-size-bonus": return "Inserter hand size +\(Int(m))"
        case "stack-inserter-capacity-bonus": return "Stack inserter hand size +\(Int(m))"
        case "character-mining-speed": return String(format: "Hand mining speed +%.0f%%", m * 100)
        case "character-inventory-slots-bonus": return "Inventory +\(Int(m)) slots"
        default: return e.type.replacingOccurrences(of: "-", with: " ")
        }
    }
}

// MARK: - Production statistics

struct StatsPanel: View {
    @Bindable var controller: GameController
    @State private var window = StatsWindow.tenMinutes

    var body: some View {
        let _ = controller.hud
        let st = controller.world.stats!, db = controller.world.db
        let produced = st.top(.produced, window: window, limit: 14)
        let consumed = st.top(.consumed, window: window, limit: 14)
        return PanelChrome(title: "Production", onClose: { controller.panel = nil }) {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Window", selection: $window) {
                    ForEach(StatsWindow.allCases, id: \.self) { w in Text(w.label).tag(w) }
                }.pickerStyle(.segmented).frame(width: 300)
                HStack(alignment: .top, spacing: 30) {
                    column("Produced / min", produced, db)
                    column("Consumed / min", consumed, db)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Rockets launched: \(st.rocketsLaunched)").foregroundStyle(Theme.text)
                        let pol = controller.world.pollution!
                        Text("Pollution").font(.caption).foregroundStyle(Theme.textDim).padding(.top, 6)
                        Text("\(Int(pol.perMinute.rounded())) / min · total \(Int(pol.total.rounded()))").foregroundStyle(Theme.text)
                        ForEach(pol.bySource.sorted { $0.value > $1.value }.prefix(4), id: \.key) { kv in
                            HStack(spacing: 6) {
                                SpriteImage(name: "i_\(db.items[max(0, db.entityItem[kv.key])].id)", size: 18)
                                Text(String(format: "%.1f / min", kv.value)).font(.caption).foregroundStyle(Theme.textDim)
                            }
                        }
                        let net = controller.world.power.network(at: controller.world.player.position)
                        if net >= 0, let ps = controller.world.power.stats(network: net) {
                            Text("Power here").font(.caption).foregroundStyle(Theme.textDim)
                            Text("\(formatWatts(ps.demandW)) / \(formatWatts(ps.capacityW))").foregroundStyle(Theme.text)
                        }
                    }
                }
            }
            .padding(16)
        }
        .frame(maxWidth: 900, maxHeight: 600)
        .padding(20)
    }

    private func column(_ title: String, _ rows: [StatEntry], _ db: PrototypeDB) -> some View {
        let maxV = rows.first?.perMinute ?? 1
        return VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption.bold()).foregroundStyle(Theme.accent)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                HStack(spacing: 6) {
                    switch r.subject {
                    case .item(let i): ItemIcon(item: i, db: db, size: 24)
                    case .fluid(let f): Image(uiImage: SpriteCatalog.shared.fluidIcon(f, db: db)).resizable().frame(width: 24, height: 24)
                    default: EmptyView()
                    }
                    BarView(fraction: r.perMinute / max(maxV, 1e-9), height: 6).frame(width: 120)
                    Text(String(format: r.perMinute >= 100 ? "%.0f" : "%.1f", r.perMinute)).font(.caption).monospacedDigit().foregroundStyle(Theme.text)
                }
            }
            if rows.isEmpty { Text("Nothing yet").font(.caption).foregroundStyle(Theme.textDim) }
        }
        .frame(width: 240, alignment: .leading)
    }
}

// MARK: - Pause menu

struct PauseMenu: View {
    @Bindable var model: AppModel
    @Bindable var controller: GameController
    @State private var saveName = ""
    @State private var showSettings = false

    var body: some View {
        if showSettings {
            SettingsView(model: model, onClose: { showSettings = false })
        } else {
            ScrollView {
            VStack(spacing: 10) {
                Text("Paused").font(.system(size: 28, weight: .heavy, design: .rounded)).foregroundStyle(Theme.accent)
                if let l = controller.session.level { Text("\(l.id) · \(l.title)").foregroundStyle(Theme.textDim) }
                MenuButton(title: "Resume") { controller.panel = nil }
                HStack {
                    TextField("Save name", text: $saveName).textFieldStyle(.roundedBorder).frame(width: 190)
                    Button("Save") {
                        let n = saveName.trimmingCharacters(in: .whitespaces)
                        controller.save(slot: n.isEmpty ? "Quicksave" : n, name: n.isEmpty ? "Quicksave" : n)
                        model.refreshSaves()
                    }.buttonStyle(.borderedProminent).tint(Theme.accent)
                }
                MenuButton(title: "Production stats") { controller.panel = .stats }
                MenuButton(title: "Settings") { showSettings = true }
                MenuButton(title: "Save & quit to menu") { model.quitToMenu(save: true) }
            }
            .padding(22)
            }
            .scrollBounceBehavior(.basedOnSize)
            .fixedSize(horizontal: true, vertical: false)
            .background(RoundedRectangle(cornerRadius: 18).fill(Theme.panel))
            .padding(.vertical, 12)
        }
    }
}
