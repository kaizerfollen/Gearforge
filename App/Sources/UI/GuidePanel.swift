// Gearforge — "How to play" guide: the goal, first steps, controls, resources, mining, smelting, crafting, building,
// logistics, power, research, automation, campaign and saves. Opened from the main menu, the pause menu and the
// "?" HUD button; shown once automatically on the first game start (GameSettings.guideSeen).
// Every text goes through L() so tools/l10n picks it up (Russian in tools/l10n/ru.json).

import SwiftUI
import FactoryCore

enum GuideBlock {
    case text(String)
    /// Sprite + text; the part before " — " is shown in bold (the item's name).
    case item(String, String)
    case step(Int, String)
    case tip(String)
}

struct GuideSection: Identifiable {
    let id: String
    let icon: String
    let title: String
    let blocks: [GuideBlock]
}

enum GuideContent {
    static func sections() -> [GuideSection] {
        [
            GuideSection(id: "goal", icon: "i_rocket_silo", title: L("Goal of the game"), blocks: [
                .text(L("Gearforge is a game about building a factory. You start with a few items and automate everything step by step: dig ore, smelt it into plates, turn plates into parts, research new technology and, at the very end, build a rocket silo and launch a rocket.")),
                .text(L("Do things by hand only at the start. Every job you repeat — mining, smelting, crafting — can be handed over to machines: they are faster and never stop.")),
                .tip(L("The goals of the current level are listed in the top-left corner. The hint below them tells you what to do next; hints can be turned off in Settings.")),
            ]),
            GuideSection(id: "start", icon: "i_burner_mining_drill", title: L("First steps"), blocks: [
                .step(1, L("Look around: resource patches are coloured spots on the ground. Iron is blue-grey, copper is orange, coal is black, stone is beige.")),
                .step(2, L("Hold your finger on coal and on stone to mine a few pieces by hand. Hold on a tree to get wood.")),
                .step(3, L("Open the inventory (case button, bottom right) → Crafting and make a stone furnace from 5 stone.")),
                .step(4, L("Place the burner mining drill on iron ore. It drops ore in front of it (the arrow while placing) — put the stone furnace exactly there.")),
                .step(5, L("Tap the drill, tap it again to open it and insert coal from your inventory. Do the same with the furnace. Now ore turns into iron plates by itself.")),
                .step(6, L("Collect the plates from the furnace output. Craft more drills and furnaces and build the same pairs on copper and coal.")),
                .step(7, L("With enough plates craft belts and inserters, then build electricity and labs and start research — see the sections below.")),
            ]),
            GuideSection(id: "controls", icon: "ui_inventory", title: L("Controls"), blocks: [
                .text(L("Joystick (bottom left) — walk. Drag the ground with one finger to look around; «⊙ Recenter» brings the camera back. Pinch to zoom.")),
                .text(L("Tap a building to select it, tap it again to open its screen. Hold on your building for a quick menu: open, rotate, copy settings, pick up.")),
                .text(L("Hold on ore, a tree or a rock to mine it — if it is too far, the character walks there first. Hold on empty ground to walk to that spot. Tap the minimap to open the map, tap the map to walk there.")),
                .item("ui_build", L("Build — opens the inventory: pick a building and tap the ground to place it.")),
                .item("ui_remove", L("Remove — tap or drag over buildings to pick them up into the inventory.")),
                .item("ui_copy", L("Copy — drag a rectangle over buildings; Paste places the copy with all settings.")),
                .item("ui_undo", L("Undo / redo the last actions. While building this button rotates the building.")),
                .item("ui_altmode", L("Alt mode — shows recipe icons over machines.")),
                .item("ui_stats", L("Statistics — what is produced and used per minute.")),
                .item("ui_pause", L("Pause — save, settings, this guide and the Codex with every item and recipe.")),
                .text(L("The bar at the bottom holds buildings for quick access; the number on its right switches between two pages.")),
            ]),
            GuideSection(id: "resources", icon: "i_iron_ore", title: L("Resources"), blocks: [
                .item("i_iron_ore", L("Iron ore — blue-grey patches. Smelted into iron plates, the most used material.")),
                .item("i_copper_ore", L("Copper ore — orange patches. Smelted into copper plates for cables and circuits.")),
                .item("i_coal", L("Coal — black patches. Fuel for burner drills, furnaces, burner inserters and boilers.")),
                .item("i_stone", L("Stone — beige patches and rocks. Stone furnaces and stone bricks.")),
                .item("i_wood", L("Wood — from trees. Early fuel, wooden chests, small electric poles.")),
                .item("f_water", L("Water — lakes. An offshore pump on the shore supplies boilers and chemistry.")),
                .item("f_crude_oil", L("Crude oil — dark spots, extracted by a pumpjack. Refined into gas for plastic and sulfur (later levels).")),
                .tip(L("Patches run out. A drill's screen shows how much is left; look for new patches on the map.")),
            ]),
            GuideSection(id: "mining", icon: "i_electric_mining_drill", title: L("Mining"), blocks: [
                .text(L("By hand: hold on a resource tile. It is slow but free — good for the first stone, coal and wood.")),
                .item("i_burner_mining_drill", L("Burner mining drill — 2×2, mines the tiles under it and burns coal or wood. Put fuel into its fuel slot.")),
                .item("i_electric_mining_drill", L("Electric mining drill — 3×3, mines a 5×5 area, faster, runs on electricity instead of fuel.")),
                .text(L("A drill drops ore at its output (the arrow shown while placing). Put a furnace, a chest or a belt there. A burner drill on coal can feed coal straight into a neighbouring drill.")),
            ]),
            GuideSection(id: "smelting", icon: "i_stone_furnace", title: L("Smelting"), blocks: [
                .item("i_stone_furnace", L("Stone furnace — put ore and fuel in. Iron ore becomes iron plates, copper ore — copper plates, stone — bricks. The recipe is chosen automatically.")),
                .text(L("Drill → furnace is the first automation: the drill fills the furnace with ore, you only bring coal and collect plates.")),
                .tip(L("On the furnace screen tap the output slot to take everything from it.")),
            ]),
            GuideSection(id: "crafting", icon: "i_iron_gear_wheel", title: L("Crafting"), blocks: [
                .text(L("Open the inventory → Crafting. Recipes are grouped: logistics, production, intermediate products. The number on a recipe is how many you can make right now.")),
                .text(L("Tap a recipe to craft one, hold to craft five, «Max» makes as many as possible. Missing parts such as gears and cables are crafted automatically when you have the plates.")),
                .text(L("The craft queue is shown above the bottom bar; finished items go to the inventory.")),
                .tip(L("Some recipes can only be made in a machine. The Codex (pause menu) shows where every item comes from and what it is used for.")),
            ]),
            GuideSection(id: "building", icon: "ui_build", title: L("Building"), blocks: [
                .text(L("Choose a building in the inventory or on the bottom bar. The preview shows where it goes: green — it can be placed, red — not here (the reason is shown at the bottom).")),
                .text(L("Tap to place. Drag to lay a line of belts or poles. The rotate button turns the building before placing; a placed one is rotated from its quick menu.")),
                .text(L("You can only build within reach — the circle around the character. Trees and rocks under a new building are cleared.")),
                .tip(L("To confirm every placement turn on «Confirm placement with a second tap» in Settings.")),
            ]),
            GuideSection(id: "logistics", icon: "i_transport_belt", title: L("Belts and inserters"), blocks: [
                .item("i_transport_belt", L("Transport belt — moves items along its arrows. Drag to lay a line; belts turn and merge.")),
                .item("i_underground_belt", L("Underground belt — passes under other buildings: an entrance and an exit a few tiles apart.")),
                .item("i_splitter", L("Splitter — divides one belt into two or merges two into one; it can filter one item.")),
                .item("i_inserter", L("Inserter — takes items from the tile behind it and puts them on the tile in front: belt → furnace, furnace → chest, chest → machine. Needs electricity.")),
                .item("i_burner_inserter", L("Burner inserter — the same without electricity: it burns fuel and takes some for itself.")),
                .item("i_wooden_chest", L("Chest — stores items; a chest at the end of a line collects the production.")),
            ]),
            GuideSection(id: "power", icon: "i_steam_engine", title: L("Electricity"), blocks: [
                .text(L("Electric buildings — electric drills, inserters, assembling machines, labs — need a power network.")),
                .step(1, L("Offshore pump on a lake shore pumps water.")),
                .step(2, L("Boiler — burns coal and makes steam. Connect it to the pump directly or with pipes.")),
                .step(3, L("Steam engines next to the boiler turn steam into electricity; one boiler feeds two engines.")),
                .step(4, L("Small electric poles carry power: every building inside a pole's area is connected, poles link to each other with wires.")),
                .text(L("The lightning sign at the top left shows the network where you stand: a dash — no network, green 100% — enough power, yellow or red — not enough. Next to it is the time of day.")),
                .tip(L("Later: solar panels work only in daytime, accumulators store energy for the night.")),
            ]),
            GuideSection(id: "research", icon: "i_lab", title: L("Research"), blocks: [
                .text(L("Research unlocks new buildings and recipes and gives permanent upgrades: faster mining, bigger inserter hands, more inventory.")),
                .step(1, L("Craft a lab and connect it to electricity.")),
                .step(2, L("Put data cards into the lab: red mechanics cards (copper plate + gear), later green motion cards (inserter + belt) and others.")),
                .step(3, L("Tap the research bar at the top → choose a technology → «Research now». The bar shows the progress.")),
                .tip(L("Add several technologies to the queue — labs continue with the next one by themselves. Some upgrades can be researched again and again.")),
            ]),
            GuideSection(id: "automation", icon: "i_assembling_machine_1", title: L("Automation"), blocks: [
                .item("i_assembling_machine_1", L("Assembling machine — crafts by itself. Open it and choose a recipe; feed the ingredients with inserters and take the products out with inserters.")),
                .text(L("A typical first line: drills on iron → furnaces → belt with plates → inserter → assembling machine making gears → inserter → chest.")),
                .text(L("Then automate the data cards, belts and inserters — everything you used to craft by hand. The statistics show what is missing.")),
                .tip(L("Copy a working setup and paste it next to it to double the production.")),
            ]),
            GuideSection(id: "modes", icon: "ui_stats", title: L("Campaign and saves"), blocks: [
                .text(L("Campaign — 8 levels from the first drill to the rocket. Each level teaches something new; complete its goals to unlock the next one. Stars are given for speed.")),
                .text(L("Freeplay — your own map with the size, resources and research price you choose; the goal is to launch a rocket.")),
                .text(L("The game saves itself every few minutes and when you leave the app. In the pause menu enter a name and press Save to keep a separate save. «Continue» in the main menu loads the latest save, «Load game» shows them all.")),
            ]),
        ]
    }
}

struct GuidePanel: View {
    let onClose: () -> Void
    @State private var selected = 0
    @Environment(\.verticalSizeClass) private var vClass

    var body: some View {
        let sections = GuideContent.sections()
        let compact = vClass == .compact
        let current = sections[min(selected, sections.count - 1)]
        PanelChrome(title: "How to play", onClose: onClose) {
            HStack(alignment: .top, spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(sections.enumerated()), id: \.offset) { i, s in
                            Button { selected = i } label: {
                                HStack(spacing: 8) {
                                    SpriteImage(name: s.icon, size: compact ? 22 : 26)
                                    Text(s.title).font(.subheadline.weight(i == selected ? .bold : .regular))
                                        .lineLimit(2).multilineTextAlignment(.leading)
                                    Spacer(minLength: 0)
                                }
                                .foregroundStyle(i == selected ? Color.black : Theme.text)
                                .padding(.horizontal, 8).padding(.vertical, 6)
                                .background(RoundedRectangle(cornerRadius: 8).fill(i == selected ? Theme.accent : Color.clear))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(8)
                }
                .frame(width: compact ? 190 : 240)
                Divider().background(Color.white.opacity(0.1))
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 10) {
                                SpriteImage(name: current.icon, size: 36)
                                Text(current.title).font(.title3.bold()).foregroundStyle(Theme.accent)
                            }
                            ForEach(Array(current.blocks.enumerated()), id: \.offset) { _, b in block(b) }
                        }
                        .padding(compact ? 12 : 18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .id(selected)          // start each section at the top
                    HStack {
                        if selected > 0 {
                            Button { selected -= 1 } label: { Text("‹ Back") }.buttonStyle(.bordered)
                        }
                        Spacer()
                        if selected + 1 < sections.count {
                            Button { selected += 1 } label: { Text(LF("%@ ›", sections[selected + 1].title)).lineLimit(1) }
                                .buttonStyle(.borderedProminent).tint(Theme.accent)
                        } else {
                            Button(action: onClose) { Text("Got it") }.buttonStyle(.borderedProminent).tint(Theme.accent)
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Theme.panelLight.opacity(0.6))
                }
            }
        }
        .panelFrame(maxWidth: 980, maxHeight: 660)
    }

    @ViewBuilder private func block(_ b: GuideBlock) -> some View {
        switch b {
        case .text(let s):
            Text(s).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
        case .item(let icon, let s):
            HStack(alignment: .top, spacing: 10) {
                SpriteImage(name: icon, size: 32)
                itemText(s).fixedSize(horizontal: false, vertical: true)
            }
        case .step(let n, let s):
            HStack(alignment: .top, spacing: 10) {
                Text(verbatim: "\(n)").font(.callout.bold()).foregroundStyle(.black)
                    .frame(width: 26, height: 26).background(Circle().fill(Theme.accent))
                Text(s).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
            }
        case .tip(let s):
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "lightbulb.fill").foregroundStyle(Theme.accent)
                Text(s).font(.callout).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.accent.opacity(0.12)))
        }
    }

    /// "Name — description": the name in bold.
    private func itemText(_ s: String) -> Text {
        if let r = s.range(of: " — ") {
            return Text(String(s[..<r.lowerBound])).bold().foregroundColor(Theme.accent)
                + Text(String(s[r.lowerBound...])).foregroundColor(Theme.text)
        }
        return Text(s).foregroundColor(Theme.text)
    }
}
