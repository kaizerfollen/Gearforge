// Gearforge — research (tech tree), production statistics, pause menu.

import SwiftUI
import FactoryCore

struct ResearchPanel: View {
    @Bindable var controller: GameController
    @State private var filter = 0      // 0 available, 1 researched, 2 all
    @State private var selected: Int? = nil
    @Environment(\.verticalSizeClass) private var vClass
    /// iPhone in landscape: narrower detail column, tighter padding.
    private var compact: Bool { vClass == .compact }

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
        // as many 72 pt columns as the width allows (5 on an iPhone in landscape, 8+ on iPad)
        let cols = [GridItem(.adaptive(minimum: 72, maximum: 84), spacing: 8)]
        let shown = selected ?? r.current
        return PanelChrome(title: "Research", onClose: { controller.panel = nil }) {
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    FitPicker("Filter", selection: $filter, options: [("Available", 0), ("Researched", 1), ("All", 2)])
                        .frame(maxWidth: 360)
                    if !r.queue.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                Text("Queue").font(.caption).foregroundStyle(Theme.textDim)
                                ForEach(r.queue, id: \.self) { t in
                                    Image(uiImage: SpriteCatalog.shared.techIcon(t, db: db)).resizable().frame(width: 32, height: 32)
                                        .onTapGesture { controller.execute(.dequeueResearch(tech: t)) }
                                }
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
                                    Text(db.techName(t)).font(.system(size: 9)).foregroundStyle(Theme.textDim).lineLimit(2)
                                        .multilineTextAlignment(.center).frame(width: 72, height: 24)
                                }
                                .onTapGesture { selected = t }
                            }
                        }
                        if techs.isEmpty {
                            Text("Nothing here yet").font(.caption).foregroundStyle(Theme.textDim).padding(.top, 20)
                        }
                    }
                }
                .padding(compact ? 10 : 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                Divider().background(Color.white.opacity(0.1))
                VStack(alignment: .leading, spacing: 8) {
                    ScrollView { detail(shown) }.scrollBounceBehavior(.basedOnSize)
                    actions(shown)
                }
                .padding(compact ? 10 : 14)
                .frame(width: compact ? 250 : 320)
            }
        }
        .panelFrame(maxWidth: 1020, maxHeight: 620)
    }

    @ViewBuilder private func actions(_ t: Int) -> some View {
        let db = controller.world.db, r = controller.world.research!
        if t >= 0 && (!r.isResearched(t) || db.technologies[t].isInfinite) {
            VStack(spacing: 6) {
                Button { controller.execute(.setResearch(tech: t)) } label: {
                    Text("Research now").frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent).tint(Theme.accent)
                Button { controller.execute(.enqueueResearch(tech: t)) } label: {
                    Text("Add to queue").frame(maxWidth: .infinity)
                }.buttonStyle(.bordered)
            }
        }
    }

    @ViewBuilder private func detail(_ t: Int) -> some View {
        let w = controller.world, db = w.db, r = w.research!
        if t >= 0 {
            let tp = db.technologies[t]
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(uiImage: SpriteCatalog.shared.techIcon(t, db: db)).resizable().frame(width: 52, height: 52)
                    VStack(alignment: .leading) {
                        Text(db.techName(t) + (tp.maxLevel != nil && tp.maxLevel != 1 ? " \(r.level(of: t))" : "")).font(.headline).foregroundStyle(Theme.text)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(r.isResearched(t) ? "Researched" : (r.isAvailable(t) ? "Available" : "Locked")).font(.caption)
                            .foregroundStyle(r.isResearched(t) ? Theme.good : (r.isAvailable(t) ? Theme.accent : Theme.textDim))
                    }
                }
                HStack(spacing: 6) {
                    Text("\(r.unitCount(of: t)) ×").font(.caption).foregroundStyle(Theme.text)
                    ForEach(Array(tp.ingredients.enumerated()), id: \.offset) { _, ing in ItemIcon(item: db.item(ing.id), db: db, size: 24) }
                    Text(LF("%@ s", String(format: "%.0f", tp.time))).font(.caption).foregroundStyle(Theme.textDim)
                }
                if r.progress(of: t) > 0 && !r.isResearched(t) { BarView(fraction: r.progress(of: t), height: 6) }
                if !db.techPrereqs[t].isEmpty {
                    Text("Requires").font(.caption).foregroundStyle(Theme.textDim)
                    iconWrap(db.techPrereqs[t]) { p in
                        Image(uiImage: SpriteCatalog.shared.techIcon(p, db: db)).resizable().frame(width: 28, height: 28)
                            .opacity(r.isResearched(p) ? 1 : 0.5)
                            .onTapGesture { selected = p }
                    }
                }
                let unlocks = db.techUnlocks[t]
                if !unlocks.isEmpty {
                    Text("Unlocks").font(.caption).foregroundStyle(Theme.textDim)
                    iconWrap(unlocks) { u in Image(uiImage: SpriteCatalog.shared.recipeIcon(u, db: db)).resizable().frame(width: 28, height: 28) }
                }
                ForEach(Array(tp.effects.filter { $0.type != "unlock-recipe" }.enumerated()), id: \.offset) { _, ef in
                    Text(verbatim: "• \(effectText(ef))").font(.caption).foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text("Pick a technology").foregroundStyle(Theme.textDim).frame(maxWidth: .infinity)
        }
    }

    /// Icons that wrap onto more lines instead of running off the column.
    private func iconWrap<V: View>(_ ids: [Int], @ViewBuilder _ icon: @escaping (Int) -> V) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 28, maximum: 28), spacing: 4)], alignment: .leading, spacing: 4) {
            ForEach(ids, id: \.self) { icon($0) }
        }
    }

    private func effectText(_ e: TechEffect) -> String {
        let m = e.modifier ?? 0
        switch e.type {
        case "mining-drill-productivity-bonus": return LF("Mining productivity +%@%%", "\(Int((m * 100).rounded()))")
        case "laboratory-speed": return LF("Lab speed +%@%%", "\(Int((m * 100).rounded()))")
        case "inserter-stack-size-bonus": return LF("Inserter hand size +%@", "\(Int(m))")
        case "stack-inserter-capacity-bonus": return LF("Stack inserter hand size +%@", "\(Int(m))")
        case "character-mining-speed": return LF("Hand mining speed +%@%%", "\(Int((m * 100).rounded()))")
        case "character-inventory-slots-bonus": return LF("Inventory +%@ slots", "\(Int(m))")
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
                FitPicker("Window", selection: $window, options: StatsWindow.allCases.map { (L($0.label), $0) })
                    .frame(maxWidth: 360)
                ScrollView {
                    HStack(alignment: .top, spacing: 16) {
                        column("Produced / min", produced, db)
                        column("Consumed / min", consumed, db)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(LF("Rockets launched: %@", "\(st.rocketsLaunched)")).foregroundStyle(Theme.text)
                            let pol = controller.world.pollution!
                            Text("Pollution").font(.caption).foregroundStyle(Theme.textDim).padding(.top, 6)
                            Text(LF("%@ / min · total %@", "\(Int(pol.perMinute.rounded()))", "\(Int(pol.total.rounded()))")).foregroundStyle(Theme.text)
                            ForEach(pol.bySource.sorted { $0.value > $1.value }.prefix(4), id: \.key) { kv in
                                HStack(spacing: 6) {
                                    SpriteImage(name: "i_\(db.items[max(0, db.entityItem[kv.key])].id)", size: 18)
                                    Text(LF("%@ / min", String(format: "%.1f", kv.value))).font(.caption).foregroundStyle(Theme.textDim)
                                }
                            }
                            let net = controller.world.power.network(at: controller.world.player.position)
                            if net >= 0, let ps = controller.world.power.stats(network: net) {
                                Text("Power here").font(.caption).foregroundStyle(Theme.textDim)
                                Text("\(formatWatts(ps.demandW)) / \(formatWatts(ps.capacityW))").foregroundStyle(Theme.text)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .padding(14)
        }
        .panelFrame(maxWidth: 900, maxHeight: 600)
    }

    private func column(_ title: String, _ rows: [StatEntry], _ db: PrototypeDB) -> some View {
        let maxV = rows.first?.perMinute ?? 1
        return VStack(alignment: .leading, spacing: 5) {
            Text(LocalizedStringKey(title)).font(.caption.bold()).foregroundStyle(Theme.accent)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                HStack(spacing: 6) {
                    switch r.subject {
                    case .item(let i): ItemIcon(item: i, db: db, size: 24)
                    case .fluid(let f): Image(uiImage: SpriteCatalog.shared.fluidIcon(f, db: db)).resizable().frame(width: 24, height: 24)
                    default: EmptyView()
                    }
                    BarView(fraction: r.perMinute / max(maxV, 1e-9), height: 6).frame(minWidth: 30, maxWidth: 120)
                    Text(String(format: r.perMinute >= 100 ? "%.0f" : "%.1f", r.perMinute)).font(.caption).monospacedDigit().foregroundStyle(Theme.text)
                        .fixedSize()
                }
            }
            if rows.isEmpty { Text("Nothing yet").font(.caption).foregroundStyle(Theme.textDim) }
        }
        .frame(maxWidth: 240, alignment: .leading)
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
                if let l = controller.session.level { Text(verbatim: "\(l.id) · \(Names.levelTitle(l))").foregroundStyle(Theme.textDim) }
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
                MenuButton(title: "Codex") { controller.panel = .codex }
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
