// Gearforge — entity screens (GDD §5.1): machines, furnaces, drills, chests, labs, boilers, generators, inserters,
// splitters, poles, solar/accumulators, beacons, silo, fluids. A player-inventory strip lets the player insert items.

import SwiftUI
import FactoryCore

struct EntityPanel: View {
    @Bindable var controller: GameController
    let handle: EntityHandle
    @State private var pickingRecipe = false
    @State private var tick = 0          // forces refresh with the HUD
    @Environment(\.verticalSizeClass) private var vClass
    /// iPhone in landscape: the player's inventory sits in a column on the right instead of a strip below,
    /// so it is visible without scrolling on a ~370 pt tall screen.
    private var compact: Bool { vClass == .compact }

    private var w: World { controller.world }
    private var db: PrototypeDB { w.db }

    var body: some View {
        let _ = controller.hud            // refresh at HUD rate
        if let e = w.entities.resolve(handle) {
            let rec = w.entities[e]
            let p = db.entities[Int(rec.proto)]
            PanelChrome(title: db.entityName(Int(rec.proto)), onClose: { controller.panel = nil }) {
                if compact {
                    HStack(alignment: .top, spacing: 0) {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 10) {
                                header(e, rec)
                                content(e, rec, p)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .scrollBounceBehavior(.basedOnSize)
                        Divider().background(Color.white.opacity(0.1))
                        inventoryColumn(e, rec)
                            .padding(10)
                            .frame(width: 236)
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            header(e, rec)
                            content(e, rec, p)
                            Divider().background(Color.white.opacity(0.1))
                            inventoryStrip(e, rec)
                        }
                        .padding(16)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
            }
            .panelFrame(maxWidth: 820, maxHeight: 620)
            .sheet(isPresented: $pickingRecipe) { RecipePicker(controller: controller, entity: e) { pickingRecipe = false } }
        }
    }

    // MARK: Header

    @ViewBuilder private func header(_ e: Int32, _ rec: EntityRecord) -> some View {
        let status = statusOf(e, rec)
        HStack(spacing: 12) {
            SpriteImage(name: "i_\(db.items[max(0, db.entityItem[Int(rec.proto)])].id)", size: 44)
            VStack(alignment: .leading, spacing: 3) {
                if let s = status { Text(L(s.label)).font(.subheadline.bold()).foregroundStyle(s.color) }
                if w.entities[e].powerSlot >= 0 {
                    let sat = w.power.satisfaction(of: e)
                    Text(LF("Power %@%%", "\(Int(sat * 100))")).font(.caption).foregroundStyle(Theme.powerColor(sat))
                }
            }
            Spacer()
            Button { controller.pipette(e); controller.panel = nil } label: { SpriteImage(name: "ui_pipette", size: 26) }.buttonStyle(.plain)
            Button { controller.execute(.rotate(entity: e, clockwise: true)) } label: { SpriteImage(name: "ui_rotate", size: 26) }.buttonStyle(.plain)
        }
    }

    private func statusOf(_ e: Int32, _ rec: EntityRecord) -> EntityStatus? {
        switch rec.kind {
        case .assemblingMachine, .furnace, .rocketSilo: return w.crafting.status(of: e)
        case .miningDrill: return w.mining.status(of: e)
        case .lab: return w.labs.status(of: e)
        case .inserter: return w.inserters.status(of: e)
        case .beacon: return w.beacons.status(of: e)
        default: return nil
        }
    }

    // MARK: Content per kind

    @ViewBuilder private func content(_ e: Int32, _ rec: EntityRecord, _ p: EntityProto) -> some View {
        switch rec.kind {
        case .assemblingMachine, .furnace, .rocketSilo: machine(e, rec, p)
        case .miningDrill: drill(e)
        case .container: chest(e)
        case .lab: lab(e)
        case .boiler: boiler(e)
        case .generator, .solarPanel, .accumulator: generator(e, rec)
        case .inserter: inserter(e, p)
        case .splitter: splitter(e)
        case .electricPole: pole(e)
        case .beacon: modulesRow(e, w.beacons.modules(of: e))
        case .pipe, .pipeToGround, .storageTank, .pump, .offshorePump: fluidInfo(e)
        case .transportBelt, .undergroundBelt:
            itemsRow("On belt", w.belts.items(on: e)) { _ in controller.execute(.pickUpBeltItems(entity: e)) }
        default: Text("No settings").foregroundStyle(Theme.textDim)
        }
    }

    @ViewBuilder private func machine(_ e: Int32, _ rec: EntityRecord, _ p: EntityProto) -> some View {
        let r = w.crafting.recipe(of: e)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                if rec.kind == .assemblingMachine {
                    Button { pickingRecipe = true } label: {
                        SlotView(highlighted: r < 0, size: 56) {
                            if r >= 0 { Image(uiImage: SpriteCatalog.shared.recipeIcon(r, db: db)).resizable().frame(width: 42, height: 42) }
                            else { Text("Recipe").font(.caption2).foregroundStyle(Theme.accent) }
                        }
                    }.buttonStyle(.plain)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(r >= 0 ? db.recipeName(r) : L("No recipe")).font(.headline).foregroundStyle(Theme.text)
                    BarView(fraction: w.crafting.progress(of: e), height: 8).frame(maxWidth: 260)
                    HStack {
                        Text(LF("Speed %@", String(format: "%.2f", w.crafting.craftingSpeed(of: e)))).font(.caption).foregroundStyle(Theme.textDim)
                        if w.crafting.effects(of: e).productivity > 0 {
                            Text("Productivity").font(.caption).foregroundStyle(Theme.accent)
                            BarView(fraction: w.crafting.productivityBar(of: e), color: Theme.good, height: 5).frame(width: 80)
                        }
                    }
                }
            }
            HStack(alignment: .top, spacing: 18) {
                itemsRow("Input", w.crafting.inputSlots(of: e)) { s in
                    controller.execute(.transferFromEntity(entity: e, item: Int(s.item), count: Int(s.count)))
                }
                Text("→").font(.title).foregroundStyle(Theme.textDim)
                itemsRow("Output", w.crafting.outputSlots(of: e)) { s in
                    controller.execute(.transferFromEntity(entity: e, item: Int(s.item), count: Int(s.count)))
                }
            }
            if let f = w.crafting.fuel(of: e) { fuelRow(e, f) }
            if w.fluids.boxCount(e) > 0 { fluidInfo(e) }
            if let m = w.crafting.modules(of: e) { modulesRow(e, m) }
            if rec.kind == .rocketSilo { silo(e) }
        }
    }

    @ViewBuilder private func silo(_ e: Int32) -> some View {
        let parts = w.crafting.rocketParts(of: e)
        HStack(spacing: 12) {
            VStack(alignment: .leading) {
                Text(LF("Rocket parts %@/100", "\(parts)")).font(.subheadline).foregroundStyle(Theme.text)
                BarView(fraction: Double(parts) / 100, color: Theme.good, height: 8).frame(maxWidth: 240)
            }
            itemsRow("Payload", w.crafting.rocketInventory(of: e)?.slots.filter { !$0.isEmpty } ?? []) { _ in }
            Button("LAUNCH") { controller.execute(.launchRocket(entity: e)) }
                .buttonStyle(.borderedProminent).tint(Theme.bad).disabled(!w.crafting.isRocketReady(e))
        }
    }

    @ViewBuilder private func drill(_ e: Int32) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            BarView(fraction: w.mining.progress(of: e), height: 8).frame(maxWidth: 260)
            Text(LF("Resources left: %@", "\(w.mining.remainingResources(of: e))")).font(.caption).foregroundStyle(Theme.textDim)
            if let f = w.mining.fuel(of: e) { fuelRow(e, f) }
            if let m = w.mining.modules(of: e) { modulesRow(e, m) }
        }
    }

    @ViewBuilder private func chest(_ e: Int32) -> some View {
        if let inv = w.containers.inventory(of: e) {
            let cols = [GridItem(.adaptive(minimum: 44, maximum: 44), spacing: 4)]
            VStack(alignment: .leading, spacing: 6) {
                LazyVGrid(columns: cols, spacing: 4) {
                    ForEach(0..<inv.size, id: \.self) { i in
                        let s = inv.slots[i]
                        SlotView(highlighted: false, size: 44) {
                            if !s.isEmpty { ItemIcon(item: Int(s.item), db: db, count: Int(s.count), size: 34) }
                            if let b = inv.bar, i >= b { Color.red.opacity(0.25) }
                        }
                        .onTapGesture {
                            if !s.isEmpty { controller.execute(.transferFromEntity(entity: e, item: Int(s.item), count: Int(s.count))) }
                        }
                    }
                }
                HStack {
                    Button("Take all") { controller.execute(.takeAll(entity: e)) }.buttonStyle(.bordered).tint(Theme.accent)
                    Spacer()
                    Stepper(LocalizedStringKey(LF("Limit: %@", inv.bar.map(String.init) ?? L("none"))), onIncrement: {
                        let b = (inv.bar ?? inv.size)
                        controller.execute(.setChestBar(entity: e, bar: b + 1 >= inv.size ? nil : b + 1))
                    }, onDecrement: {
                        controller.execute(.setChestBar(entity: e, bar: max(0, (inv.bar ?? inv.size) - 1)))
                    })
                    .frame(maxWidth: 240).foregroundStyle(Theme.text)
                }
            }
        }
    }

    @ViewBuilder private func lab(_ e: Int32) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            itemsRow("Data cards", w.labs.cards(of: e)?.slots.filter { !$0.isEmpty } ?? []) { s in
                controller.execute(.transferFromEntity(entity: e, item: Int(s.item), count: Int(s.count)))
            }
            BarView(fraction: w.labs.progress(of: e), height: 8).frame(maxWidth: 260)
            let cur = w.research.current
            Text(cur >= 0 ? LF("Researching %@", db.techName(cur)) : L("No research selected")).font(.caption).foregroundStyle(Theme.textDim)
            if let m = w.labs.modules(of: e) { modulesRow(e, m) }
        }
    }

    @ViewBuilder private func boiler(_ e: Int32) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let f = w.power.boilerFuel(of: e) { fuelRow(e, f) }
            fluidInfo(e)
        }
    }

    @ViewBuilder private func generator(_ e: Int32, _ rec: EntityRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(LF("Output: %@", "\(formatWatts(w.power.powerOutput(of: e)))")).foregroundStyle(Theme.text)
            if rec.kind == .accumulator {
                Text(LF("Charge: %@ / 5 MJ", String(format: "%.1f", w.power.accumulatorCharge(of: e) / 1e6))).foregroundStyle(Theme.textDim)
            }
            if w.fluids.boxCount(e) > 0 { fluidInfo(e) }
            networkInfo(e)
        }
    }

    @ViewBuilder private func inserter(_ e: Int32, _ p: EntityProto) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LF("Hand size: %@", "\(w.inserters.handSize(of: e))")).font(.caption).foregroundStyle(Theme.textDim)
            if let f = w.inserters.fuel(of: e) { fuelRow(e, f) }
            let filters = w.inserters.filters(of: e)
            if !filters.isEmpty {
                Text("Filters (tap an inventory item below to set the first empty filter)").font(.caption).foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    ForEach(Array(filters.enumerated()), id: \.offset) { i, f in
                        SlotView(size: 44) { if f >= 0 { ItemIcon(item: f, db: db, size: 32) } }
                            .onTapGesture { controller.execute(.setInserterFilter(entity: e, slot: i, item: -1)) }
                    }
                }
            }
        }
    }

    @ViewBuilder private func splitter(_ e: Int32) -> some View {
        let s = w.belts.splitterSettings(e)
        VStack(alignment: .leading, spacing: 10) {
            prioPicker("Input priority", s.inputPriority) { v in var n = s; n.inputPriority = v; controller.execute(.setSplitter(entity: e, settings: n)) }
            prioPicker("Output priority", s.outputPriority) { v in var n = s; n.outputPriority = v; controller.execute(.setSplitter(entity: e, settings: n)) }
            HStack {
                Text("Filter").foregroundStyle(Theme.textDim)
                SlotView(size: 44) { if s.filter >= 0 { ItemIcon(item: Int(s.filter), db: db, size: 32) } }
                    .onTapGesture { var n = s; n.filter = -1; controller.execute(.setSplitter(entity: e, settings: n)) }
                Text("tap an inventory item below to set").font(.caption2).foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func prioPicker(_ title: String, _ v: Int8, _ set: @escaping (Int8) -> Void) -> some View {
        HStack {
            Text(LocalizedStringKey(title)).frame(width: 150, alignment: .leading).foregroundStyle(Theme.textDim)
            FitPicker(title, selection: Binding(get: { v }, set: { set($0) }),
                      options: [("Left", Int8(0)), ("None", Int8(-1)), ("Right", Int8(1))])
                .frame(maxWidth: 280)
        }
    }

    @ViewBuilder private func pole(_ e: Int32) -> some View { networkInfo(e) }

    @ViewBuilder private func networkInfo(_ e: Int32) -> some View {
        let n = w.power.networkID(of: e)
        if n >= 0, let st = w.power.stats(network: n) {
            VStack(alignment: .leading, spacing: 4) {
                Text(LF("Electric network #%@", "\(n)")).font(.subheadline.bold()).foregroundStyle(Theme.text)
                Text(LF("Demand %@ · Production %@ · Capacity %@", "\(formatWatts(st.demandW))", "\(formatWatts(st.productionW))", "\(formatWatts(st.capacityW))"))
                    .font(.caption).foregroundStyle(Theme.textDim).fixedSize(horizontal: false, vertical: true)
                BarView(fraction: st.satisfaction, color: Theme.powerColor(st.satisfaction), height: 8).frame(maxWidth: 300)
                if st.accumulatorCapacity > 0 {
                    Text(LF("Accumulators %@%%", String(format: "%.0f", st.accumulatorCharge / st.accumulatorCapacity * 100))).font(.caption).foregroundStyle(Theme.textDim)
                }
            }
        } else {
            Text("Not connected to a network").font(.caption).foregroundStyle(Theme.warn)
        }
    }

    @ViewBuilder private func fluidInfo(_ e: Int32) -> some View {
        HStack(spacing: 14) {
            ForEach(0..<w.fluids.boxCount(e), id: \.self) { b in
                let f = w.fluids.fluid(e, box: b)
                VStack(spacing: 2) {
                    if f >= 0 { Image(uiImage: SpriteCatalog.shared.fluidIcon(f, db: db)).resizable().frame(width: 28, height: 28) }
                    else { Circle().stroke(Color.white.opacity(0.3)).frame(width: 28, height: 28) }
                    Text(String(format: "%.0f/%.0f", w.fluids.amount(e, box: b), w.fluids.capacity(e, box: b)))
                        .font(.caption2).monospacedDigit().foregroundStyle(Theme.textDim)
                }
            }
        }
    }

    // MARK: Rows

    private func itemsRow(_ title: String, _ stacks: [ItemStack], tap: @escaping (ItemStack) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(LocalizedStringKey(title)).font(.caption).foregroundStyle(Theme.textDim)
            HStack(spacing: 4) {
                ForEach(Array(stacks.enumerated()), id: \.offset) { _, s in
                    SlotView(size: 48) { if s.count > 0 { ItemIcon(item: Int(s.item), db: db, count: Int(s.count), size: 36) } }
                        .onTapGesture { if s.count > 0 { tap(s) } }
                }
                if stacks.isEmpty { SlotView(size: 48) { EmptyView() } }
            }
        }
    }

    private func fuelRow(_ e: Int32, _ f: BurnerEnergy) -> some View {
        HStack(spacing: 8) {
            Text("Fuel").font(.caption).foregroundStyle(Theme.textDim)
            ForEach(Array(f.fuel.slots.enumerated()), id: \.offset) { _, s in
                SlotView(size: 44) { if !s.isEmpty { ItemIcon(item: Int(s.item), db: db, count: Int(s.count), size: 32) } }
                    .onTapGesture { if !s.isEmpty { controller.execute(.transferFromEntity(entity: e, item: Int(s.item), count: Int(s.count))) } }
            }
            if f.remaining > 0 { SpriteImage(name: "status_working", size: 18) }
        }
    }

    private func modulesRow(_ e: Int32, _ inv: Inventory?) -> some View {
        HStack(spacing: 6) {
            Text("Modules").font(.caption).foregroundStyle(Theme.textDim)
            if let m = inv {
                ForEach(0..<m.size, id: \.self) { i in
                    let s = m.slots[i]
                    SlotView(size: 44) { if !s.isEmpty { ItemIcon(item: Int(s.item), db: db, size: 32) } }
                        .onTapGesture { if !s.isEmpty { controller.execute(.removeModule(entity: e, slot: i)) } }
                }
            }
        }
    }

    // MARK: Player inventory strip (insert items)

    private func inventoryStrip(_ e: Int32, _ rec: EntityRecord) -> some View {
        let items = controller.world.player.inventory.contents()
        return VStack(alignment: .leading, spacing: 4) {
            Text("Your inventory — tap to insert").font(.caption).foregroundStyle(Theme.textDim)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(items, id: \.item) { it in
                        SlotView(size: 48) { ItemIcon(item: it.item, db: db, count: it.count, size: 36) }
                            .onTapGesture { insert(it.item, it.count, e, rec) }
                    }
                }
            }
        }
    }

    private func inventoryColumn(_ e: Int32, _ rec: EntityRecord) -> some View {
        let items = controller.world.player.inventory.contents()
        return VStack(alignment: .leading, spacing: 6) {
            Text("Your inventory — tap to insert").font(.caption).foregroundStyle(Theme.textDim)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 48, maximum: 48), spacing: 4)], alignment: .leading, spacing: 4) {
                    ForEach(items, id: \.item) { it in
                        SlotView(size: 48) { ItemIcon(item: it.item, db: db, count: it.count, size: 36) }
                            .onTapGesture { insert(it.item, it.count, e, rec) }
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private func insert(_ item: Int, _ count: Int, _ e: Int32, _ rec: EntityRecord) {
        let isModule = db.items[item].kind == .module
        switch rec.kind {
        case .inserter where !w.inserters.filters(of: e).isEmpty:
            if let slot = w.inserters.filters(of: e).firstIndex(of: -1) { controller.execute(.setInserterFilter(entity: e, slot: slot, item: item)) }
            return
        case .splitter:
            var s = w.belts.splitterSettings(e); s.filter = Int32(item); if s.outputPriority < 0 { s.outputPriority = 0 }
            controller.execute(.setSplitter(entity: e, settings: s)); return
        default: break
        }
        if isModule, controller.execute(.insertModule(entity: e, item: item), silent: true).isOK { return }
        let n = min(count, db.items[item].stackSize)
        controller.execute(.transferToEntity(entity: e, item: item, count: n))
    }
}

// MARK: - Recipe picker

struct RecipePicker: View {
    @Bindable var controller: GameController
    let entity: Int32
    let done: () -> Void

    var body: some View {
        let w = controller.world, db = w.db
        let proto = Int(w.entities[entity].proto)
        let recipes = db.recipes.indices.filter { r in
            !db.recipes[r].hidden && db.recipes[r].phase == "mvp" && db.canCraft(entity: proto, recipe: r) && w.research.isRecipeUnlocked(r)
        }
        let cols = [GridItem(.adaptive(minimum: 56, maximum: 56), spacing: 6)]
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Choose recipe").font(.title3.bold())
                Spacer()
                Button("Close", action: done)
            }
            ScrollView {
                LazyVGrid(columns: cols, spacing: 6) {
                    ForEach(recipes, id: \.self) { r in
                        Button {
                            controller.execute(.setRecipe(entity: entity, recipe: r)); done()
                        } label: {
                            SlotView(size: 56) { Image(uiImage: SpriteCatalog.shared.recipeIcon(r, db: db)).resizable().frame(width: 42, height: 42) }
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(20)
        .background(Theme.panel)
        .foregroundStyle(Theme.text)
    }
}
