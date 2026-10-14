// Gearforge — Codex (GDD §5.1): browse every item and fluid with stats generated from GameData: recipes that make it
// and use it (with ingredients, time and machines), the building it places, fuel value, stack size and the
// technology that unlocks it. Opened from the pause menu and the inventory panel.

import SwiftUI
import FactoryCore

struct CodexPanel: View {
    @Bindable var controller: GameController
    @State private var group = 0
    @State private var selected: Int? = nil
    @State private var query = ""

    private var db: PrototypeDB { controller.world.db }
    private var groups: [ItemGroupProto] { db.data.itemGroups.filter { $0.id != "combat" } }

    var body: some View {
        PanelChrome(title: "Codex", onClose: { controller.panel = nil }) {
            HStack(alignment: .top, spacing: 0) {
                browser.frame(width: 430)
                Divider().background(Color.white.opacity(0.1))
                ScrollView {
                    if let i = selected { detail(i) } else {
                        Text("Pick an item to see how it is made and used").foregroundStyle(Theme.textDim).padding(20)
                    }
                }
            }
        }
        .frame(maxWidth: 1060, maxHeight: 620)
        .padding(16)
    }

    // MARK: Browser

    private func items() -> [Int] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let mvp = db.items.indices.filter { db.items[$0].phase == "mvp" }
        if !q.isEmpty {
            return mvp.filter { db.itemName($0).lowercased().contains(q) || db.items[$0].id.contains(q) }
        }
        guard group < groups.count else { return [] }
        let subs = groups[group].subgroups
        return mvp.filter { subs.contains(db.items[$0].subgroup) }
            .sorted { (subs.firstIndex(of: db.items[$0].subgroup) ?? 0, db.items[$0].order) < (subs.firstIndex(of: db.items[$1].subgroup) ?? 0, db.items[$1].order) }
    }

    private var browser: some View {
        // 8 × 44 + 7 × 4 = 380 pt fits the 430 pt browser minus its 2 × 12 pt padding (9 columns overflowed by 22 pt)
        let cols = Array(repeating: GridItem(.fixed(44), spacing: 4), count: 8)
        return VStack(alignment: .leading, spacing: 8) {
            TextField("Search", text: $query).textFieldStyle(.roundedBorder)
            if query.isEmpty {
                HStack(spacing: 6) {
                    ForEach(Array(groups.enumerated()), id: \.offset) { i, g in
                        Button { group = i } label: {
                            Text(Names.group(g)).font(.caption.bold()).lineLimit(1)
                                .padding(.horizontal, 8).padding(.vertical, 5)
                                .foregroundStyle(group == i ? Color.black : Theme.text)
                                .background(Capsule().fill(group == i ? Theme.accent : Theme.panelLight))
                        }.buttonStyle(.plain)
                    }
                }
            }
            ScrollView {
                LazyVGrid(columns: cols, spacing: 4) {
                    ForEach(items(), id: \.self) { i in
                        SlotView(highlighted: selected == i, size: 44) { ItemIcon(item: i, db: db, size: 34) }
                            .onTapGesture { selected = i }
                    }
                }
            }
        }
        .padding(12)
    }

    // MARK: Detail

    @ViewBuilder private func detail(_ i: Int) -> some View {
        let it = db.items[i]
        let w = controller.world
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ItemIcon(item: i, db: db, size: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text(db.itemName(i)).font(.title3.bold()).foregroundStyle(Theme.text)
                    Text(LF("Stack size %@", "\(it.stackSize)")).font(.caption).foregroundStyle(Theme.textDim)
                    if let fv = it.fuelValue, fv > 0 {
                        Text(LF("Fuel value %@", formatJoules(fv))).font(.caption).foregroundStyle(Theme.textDim)
                    }
                    if w.player.count(of: i) > 0 {
                        Text(LF("In inventory: %@", "\(w.player.count(of: i))")).font(.caption).foregroundStyle(Theme.accent)
                    }
                }
            }
            let place = db.itemPlaceResult[i]
            if place >= 0 { buildingStats(place) }

            let makers = db.recipesProducing[i].filter { !db.recipes[$0].hidden || db.recipes[$0].id == "rocket_part" }
            if !makers.isEmpty {
                section("Made by")
                ForEach(makers, id: \.self) { r in recipeRow(r) }
            } else if db.resources.contains(where: { $0.result == it.id }) {
                section("Made by")
                Text("Mined from resource patches (hand or drills)").font(.caption).foregroundStyle(Theme.text)
            }

            let uses = db.recipes.indices.filter { r in
                db.recipes[r].phase == "mvp" && !db.recipes[r].hidden && db.resolvedRecipes[r].itemIngredients.contains { $0.index == i }
            }
            if !uses.isEmpty {
                section("Used in")
                let cols = Array(repeating: GridItem(.fixed(40), spacing: 4), count: 8)
                LazyVGrid(columns: cols, alignment: .leading, spacing: 4) {
                    ForEach(uses, id: \.self) { r in
                        Image(uiImage: SpriteCatalog.shared.recipeIcon(r, db: db)).resizable().frame(width: 34, height: 34)
                            .onTapGesture { if let res = db.resolvedRecipes[r].itemResults.first { selected = res.index } }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func section(_ title: String) -> some View {
        Text(L(title).uppercased()).font(.caption.bold()).foregroundStyle(Theme.accent).padding(.top, 4)
    }

    private func recipeRow(_ r: Int) -> some View {
        let rr = db.resolvedRecipes[r]
        let rp = db.recipes[r]
        let research = controller.world.research!
        let machines = db.entities.indices.filter { e in
            db.entities[e].phase == "mvp" && db.entityItem[e] >= 0 && db.canCraft(entity: e, recipe: r)
        }
        let tech = db.recipeUnlockedBy[r].first
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ForEach(Array(rr.itemIngredients.enumerated()), id: \.offset) { _, ing in
                    ItemIcon(item: ing.index, db: db, count: Int(ing.amount), size: 28).onTapGesture { selected = ing.index }
                }
                ForEach(Array(rr.fluidIngredients.enumerated()), id: \.offset) { _, f in
                    Image(uiImage: SpriteCatalog.shared.fluidIcon(f.index, db: db)).resizable().frame(width: 28, height: 28)
                    Text(verbatim: "\(Int(f.amount))").font(.caption2).foregroundStyle(Theme.textDim)
                }
                Text("→").foregroundStyle(Theme.textDim)
                ForEach(Array(rr.itemResults.enumerated()), id: \.offset) { _, res in
                    ItemIcon(item: res.index, db: db, count: Int(res.amount), size: 28)
                }
                ForEach(Array(rr.fluidResults.enumerated()), id: \.offset) { _, f in
                    Image(uiImage: SpriteCatalog.shared.fluidIcon(f.index, db: db)).resizable().frame(width: 28, height: 28)
                }
                Spacer()
                Text(LF("%@ s", String(format: "%.1f", rp.time))).font(.caption).monospacedDigit().foregroundStyle(Theme.textDim)
            }
            HStack(spacing: 4) {
                if rp.handcraftable { Text("By hand ·").font(.caption2).foregroundStyle(Theme.textDim) }
                ForEach(machines.prefix(6), id: \.self) { e in
                    ItemIcon(item: db.entityItem[e], db: db, size: 22)
                }
                Spacer()
                if let t = tech {
                    let done = research.isResearched(t)
                    Text(done ? LF("Unlocked by %@", db.techName(t)) : LF("Needs research: %@", db.techName(t)))
                        .font(.caption2).foregroundStyle(done ? Theme.textDim : Theme.warn)
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.panelLight))
    }

    @ViewBuilder private func buildingStats(_ e: Int) -> some View {
        let p = db.entities[e]
        VStack(alignment: .leading, spacing: 3) {
            Text(LF("Building · %@×%@ tiles", "\(p.width)", "\(p.height)")).font(.caption).foregroundStyle(Theme.text)
            if let c = p.crafting { Text(LF("Crafting speed %@", String(format: "%.2f", c.speed))).font(.caption).foregroundStyle(Theme.textDim) }
            if let d = p.drill { Text(LF("Mining speed %@", String(format: "%.2f", d.miningSpeed))).font(.caption).foregroundStyle(Theme.textDim) }
            if let b = p.belt, p.kind == .transportBelt {
                Text(LF("Throughput %@ items/s", String(format: "%.1f", Double(b.speed) * 60 / 32))).font(.caption).foregroundStyle(Theme.textDim)
            }
            if let u = p.energyUsage, u > 0 { Text(LF("Power use %@", formatWatts(u))).font(.caption).foregroundStyle(Theme.textDim) }
            if let g = p.generator { Text(LF("Max output %@", formatWatts(g.maxPowerOutput))).font(.caption).foregroundStyle(Theme.textDim) }
            if let s = p.solar { Text(LF("Peak output %@", formatWatts(s.production))).font(.caption).foregroundStyle(Theme.textDim) }
            if let m = p.moduleSlots, m > 0 { Text(LF("Module slots %@", "\(m)")).font(.caption).foregroundStyle(Theme.textDim) }
            if let c = p.container { Text(LF("Slots %@", "\(c.slots)")).font(.caption).foregroundStyle(Theme.textDim) }
        }
    }

    private func formatJoules(_ j: Double) -> String {
        j >= 1e6 ? LF("%@ MJ", String(format: "%.1f", j / 1e6)) : LF("%@ kJ", String(format: "%.0f", j / 1e3))
    }
}
