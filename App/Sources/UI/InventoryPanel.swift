// Gearforge — inventory + handcrafting panel (GDD §5.1).

import SwiftUI
import FactoryCore

struct InventoryPanel: View {
    @Bindable var controller: GameController
    @State private var group = 0
    @State private var craftable: [Int: Int] = [:]
    @State private var selectedRecipe: Int? = nil
    /// Narrow screens: 1 = crafting, 0 = inventory.
    @State private var compactTab = 1
    private let geoPadding: CGFloat = 12

    private var db: PrototypeDB { controller.world.db }

    var body: some View {
        GeometryReader { geo in
            PanelChrome(title: "Inventory & crafting", onClose: { controller.panel = nil }) {
                if geo.size.width >= 980 {
                    // iPad / large screens: both side by side
                    HStack(alignment: .top, spacing: 0) {
                        inventoryGrid.frame(width: 470)
                        Divider().background(Color.white.opacity(0.1))
                        crafting
                    }
                } else {
                    // iPhone: one at a time, full width
                    VStack(spacing: 0) {
                        Picker("View", selection: $compactTab) {
                            Text("Crafting").tag(1)
                            Text("Inventory").tag(0)
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 14).padding(.top, 8)
                        Group { if compactTab == 0 { inventoryGrid } else { crafting } }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                }
            }
            .panelFrame(maxWidth: 1060, maxHeight: 600, margin: 0)
        }
        .padding(geoPadding)
        .onAppear(perform: recompute)
        .onChange(of: controller.hud.inventoryRevision) { _, _ in recompute() }
        .onChange(of: group) { _, _ in recompute() }      // counts are computed per tab
    }

    // MARK: Inventory

    private var inventoryGrid: some View {
        let inv = controller.world.player.inventory
        let cols = [GridItem(.adaptive(minimum: 44, maximum: 44), spacing: 4)]
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Inventory").font(.headline).foregroundStyle(Theme.text)
                Spacer()
                Button("Codex") { controller.panel = .codex }.buttonStyle(.bordered)
                    .lineLimit(1)
                Button("Sort") { controller.execute(.sortInventory) }.buttonStyle(.bordered).tint(Theme.accent)
            }
            ScrollView {
                LazyVGrid(columns: cols, spacing: 4) {
                    ForEach(0..<inv.size, id: \.self) { i in
                        let s = inv.slots[i]
                        SlotView(size: 44) {
                            if !s.isEmpty { ItemIcon(item: Int(s.item), db: db, count: Int(s.count), size: 34) }
                        }
                        .onTapGesture { tapSlot(s) }
                    }
                }
            }
            Text("Tap a building to place it.").font(.caption).foregroundStyle(Theme.textDim)
        }
        .padding(14)
    }

    private func tapSlot(_ s: ItemStack) {
        guard !s.isEmpty else { return }
        let item = Int(s.item)
        if db.itemPlaceResult[item] >= 0 || db.itemPlaceTile[item] >= 0 {
            controller.selectBuildItem(item)
            controller.panel = nil
        } else {
            controller.show(db.itemName(item))
        }
    }

    // MARK: Crafting

    private var groups: [ItemGroupProto] { db.data.itemGroups.filter { $0.id != "combat" } }

    /// Visible handcraft recipes of the selected group, by subgroup rows.
    private func rows() -> [(String, [Int])] {
        guard group < groups.count else { return [] }
        let g = groups[group]
        var bySub: [String: [Int]] = [:]
        for (ri, r) in db.recipes.enumerated() where r.handcraftable && !r.hidden && r.phase == "mvp" {
            let sub = r.subgroup ?? db.resolvedRecipes[ri].itemResults.first.map { db.items[$0.index].subgroup } ?? ""
            guard g.subgroups.contains(sub) else { continue }
            guard controller.world.research.isRecipeUnlocked(ri) else { continue }
            bySub[sub, default: []].append(ri)
        }
        return g.subgroups.compactMap { s in
            guard let list = bySub[s], !list.isEmpty else { return nil }
            return (s, list.sorted { (db.recipes[$0].order ?? "") < (db.recipes[$1].order ?? "") })
        }
    }

    private var crafting: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ForEach(Array(groups.enumerated()), id: \.offset) { i, g in
                    Button { group = i } label: {
                        Text(Names.group(g)).font(.caption.bold()).lineLimit(1)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .foregroundStyle(group == i ? Color.black : Theme.text)
                            .background(Capsule().fill(group == i ? Theme.accent : Theme.panelLight))
                    }.buttonStyle(.plain)
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(rows(), id: \.0) { _, recipes in
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 4) {
                                ForEach(recipes, id: \.self) { r in recipeButton(r) }
                            }
                        }
                    }
                }
            }
            if let r = selectedRecipe { recipeDetail(r) }
        }
        .padding(14)
    }

    private func recipeButton(_ r: Int) -> some View {
        let n = craftable[r] ?? 0
        return SlotView(highlighted: selectedRecipe == r, size: 48) {
            ZStack(alignment: .bottomTrailing) {
                Image(uiImage: SpriteCatalog.shared.recipeIcon(r, db: db)).resizable().frame(width: 36, height: 36)
                    .opacity(n > 0 ? 1 : 0.35)
                if n > 0 {
                    Text("\(n)").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                        .shadow(color: .black, radius: 1).offset(x: 2, y: 2)
                }
            }
        }
        .onTapGesture {
            selectedRecipe = r
            if n > 0 { controller.execute(.craft(recipe: r, count: 1)) }
        }
        .onLongPressGesture(minimumDuration: 0.4) {
            selectedRecipe = r
            if n > 0 { controller.execute(.craft(recipe: r, count: min(5, n))) }
        }
    }

    private func recipeDetail(_ r: Int) -> some View {
        let rr = db.resolvedRecipes[r]
        let n = craftable[r] ?? 0
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(db.recipeName(r)).font(.headline).foregroundStyle(Theme.text)
                Spacer()
                Text(LF("%@ s", String(format: "%.1f", db.recipes[r].time))).font(.caption).foregroundStyle(Theme.textDim)
            }
            HStack(spacing: 10) {
                ForEach(Array(rr.itemIngredients.enumerated()), id: \.offset) { _, ing in
                    HStack(spacing: 3) {
                        ItemIcon(item: ing.index, db: db, size: 26)
                        Text("×\(Int(ing.amount))").font(.caption).foregroundStyle(
                            controller.world.player.count(of: ing.index) >= Int(ing.amount) ? Theme.text : Theme.warn)
                    }
                }
                Spacer()
                Button("×5") { controller.execute(.craft(recipe: r, count: min(5, n))) }.buttonStyle(.bordered).disabled(n == 0)
                Button(LF("Max (%@)", "\(n)")) { controller.execute(.craft(recipe: r, count: n)) }.buttonStyle(.borderedProminent).tint(Theme.accent).disabled(n == 0)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.panelLight))
    }

    private func recompute() {
        var m: [Int: Int] = [:]
        let pl = controller.world.player!
        for (_, list) in rows() { for r in list { m[r] = pl.craftableCount(r) } }
        craftable = m
    }
}
