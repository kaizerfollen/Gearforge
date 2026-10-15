// Gearforge — guided first tutorial (level L1, or "Tutorial" in the main menu).
// One step at a time. Each step names what to highlight — a HUD/panel element by anchor id, or world tiles — and
// is completed by checking the world (inventory, placed entities, fuel, plates) plus a small UI snapshot (build item,
// open panel). Steps already satisfied are skipped, so a resumed save or an eager player never gets stuck.
// Texts are English localisation keys; the app translates them (tools/l10n). Design notes: docs/TUTORIAL.md.

import Foundation

public enum TutorialTarget: Equatable, Sendable {
    case none
    /// Anchor ids of HUD / panel elements, in order of preference (the first one on screen is highlighted).
    case hud([String])
    /// World tiles to highlight (a pulsing frame on the ground; an arrow at the screen edge when off screen).
    case tiles(TileRect)
}

/// What the app tells the tutorial about its UI each update.
public struct TutorialUIState: Sendable, Equatable {
    /// Item selected for building (-1 when not in build mode).
    public var buildItem: Int = -1
    /// Open panel: "", "inventory", "entity", "map", "research", "stats", "pause", "codex", "guide".
    public var panel: String = ""
    /// Entity whose screen is open (-1 = none).
    public var openEntity: Int32 = -1
    public init(buildItem: Int = -1, panel: String = "", openEntity: Int32 = -1) {
        self.buildItem = buildItem; self.panel = panel; self.openEntity = openEntity
    }
}

public struct TutorialHint: Equatable, Sendable {
    public var stepIndex: Int
    public var stepCount: Int
    public var id: String
    /// English text (localisation key); `%@` placeholders are filled from `args`.
    public var text: String
    public var args: [String]
    public var target: TutorialTarget
    /// Wait for the player to press "Next" (no action to detect).
    public var needsNext: Bool
    /// Last step ("Got it" ends the tutorial).
    public var isLast: Bool
}

public final class Tutorial {
    public enum Step: String, CaseIterable, Sendable {
        case welcome, move, mineStone, mineCoal, selectDrill, placeDrill, selectFurnace, placeFurnace,
             fuelDrill, fuelFurnace, waitPlates, takePlates, craftDrill, openMap, goals
    }

    public static let stoneGoal = 5
    public static let coalGoal = 5

    public private(set) var index = 0
    public var isFinished: Bool { index >= Step.allCases.count }
    public var current: Step? { isFinished ? nil : Step.allCases[index] }

    unowned let world: World
    private let startPos: Vec2
    private var acknowledged = Set<Step>()
    private var platesBaseline: Int?

    // prototypes / items used by the script
    private let drillProto: Int, furnaceProto: Int
    private let drillItem: Int, furnaceItem: Int, stoneItem: Int, coalItem: Int, plateItem: Int
    private let ironRes: Int, stoneRes: Int, coalRes: Int
    private let drillRecipe: Int

    public init(world: World) {
        self.world = world
        startPos = world.player.position
        let db = world.db
        drillProto = db.entity("burner_mining_drill"); furnaceProto = db.entity("stone_furnace")
        drillItem = db.item("burner_mining_drill"); furnaceItem = db.item("stone_furnace")
        stoneItem = db.item("stone"); coalItem = db.item("coal"); plateItem = db.item("iron_plate")
        ironRes = db.resource("iron_ore"); stoneRes = db.resource("stone"); coalRes = db.resource("coal")
        drillRecipe = db.recipe("burner_mining_drill")
    }

    /// "Next" on steps that wait for it.
    public func next() {
        guard let s = current else { return }
        acknowledged.insert(s)
    }

    public func skipAll() { index = Step.allCases.count }

    /// Skips every completed step and returns the hint for the current one (nil when the tutorial is over).
    public func update(ui: TutorialUIState) -> TutorialHint? {
        while let s = current, isDone(s, ui) {
            index += 1
            if current == .takePlates { platesBaseline = world.player.count(of: plateItem) }
        }
        guard let s = current else { return nil }
        if s == .takePlates && platesBaseline == nil { platesBaseline = world.player.count(of: plateItem) }
        var h = hint(s, ui)
        h.stepIndex = index; h.stepCount = Step.allCases.count
        return h
    }

    // MARK: Completion

    private func isDone(_ s: Step, _ ui: TutorialUIState) -> Bool {
        let pl = world.player!
        switch s {
        case .welcome, .goals: return acknowledged.contains(s)
        case .move: return pl.position.distance(to: startPos) > 2.5 || pl.count(of: stoneItem) > 0 || drillOnIron() != nil
        case .mineStone: return pl.count(of: stoneItem) >= Self.stoneGoal || drillOnIron() != nil
        case .mineCoal: return pl.count(of: coalItem) >= Self.coalGoal || drillOnIron() != nil
        case .selectDrill: return ui.buildItem == drillItem || drillOnIron() != nil
        case .placeDrill: return drillOnIron() != nil
        case .selectFurnace: return ui.buildItem == furnaceItem || furnaceAtOutput() != nil
        case .placeFurnace: return furnaceAtOutput() != nil
        case .fuelDrill: return drillOnIron().map { hasFuel(world.mining.fuel(of: $0)) } ?? false
        case .fuelFurnace: return furnaceAtOutput().map { hasFuel(world.crafting.fuel(of: $0)) } ?? false
        case .waitPlates:
            guard let f = furnaceAtOutput() else { return false }
            return world.crafting.outputSlots(of: f).contains { Int($0.item) == plateItem && $0.count > 0 }
                || world.stats.totalProduced(item: plateItem) > 0
        case .takePlates: return pl.count(of: plateItem) > (platesBaseline ?? Int.max)
        case .craftDrill:
            return pl.craftQueue.contains { $0.recipe == drillRecipe } || pl.count(of: drillItem) > 0
                || playerEntities(drillProto).count >= 2
        case .openMap: return ui.panel == "map"
        }
    }

    private func hasFuel(_ b: BurnerEnergy?) -> Bool {
        guard let b else { return false }
        return b.remaining > 0 || b.fuel.slots.contains { !$0.isEmpty }
    }

    // MARK: Hints

    private func hint(_ s: Step, _ ui: TutorialUIState) -> TutorialHint {
        func h(_ text: String, _ target: TutorialTarget, args: [String] = [], next: Bool = false, last: Bool = false) -> TutorialHint {
            TutorialHint(stepIndex: 0, stepCount: 0, id: s.rawValue, text: text, args: args, target: target,
                         needsNext: next, isLast: last)
        }
        let pl = world.player!
        // A panel in the way of a world step: ask to close it first.
        let worldStep: Set<Step> = [.move, .mineStone, .mineCoal, .placeDrill, .placeFurnace]
        if worldStep.contains(s) && !ui.panel.isEmpty {
            return h("Close this window to continue (✕ in its corner).", .hud(["panel.close"]))
        }
        switch s {
        case .welcome:
            return h("Welcome! This short tutorial shows where to tap and what to do first: mine, build a drill and a furnace, get iron plates. You can skip it at any time.", .none, next: true)
        case .move:
            return h("Move the joystick to walk. Drag the ground with one finger to look around.", .hud(["joystick"]))
        case .mineStone:
            let have = pl.count(of: stoneItem)
            return h("Stone is the beige patch. Hold your finger on the highlighted stone until you have %@ of %@.",
                     nearestResource(stoneRes).map { .tiles($0) } ?? .none, args: ["\(have)", "\(Self.stoneGoal)"])
        case .mineCoal:
            let have = pl.count(of: coalItem)
            return h("Coal is the black patch — it is fuel. Hold your finger on it until you have %@ of %@.",
                     nearestResource(coalRes).map { .tiles($0) } ?? .none, args: ["\(have)", "\(Self.coalGoal)"])
        case .selectDrill:
            return h("Pick the burner mining drill on the bottom bar.", .hud(quickbarAnchors(drillItem) + ["build"]))
        case .placeDrill:
            if ui.buildItem != drillItem {
                return h("Pick the burner mining drill on the bottom bar.", .hud(quickbarAnchors(drillItem) + ["build"]))
            }
            if let wrong = playerEntities(drillProto).first {
                return h("This drill is not on iron ore. Hold your finger on it and pick it up, then place it on the highlighted spot.",
                         .tiles(world.entities[wrong].rect))
            }
            return h("Tap the highlighted spot on the iron ore (blue-grey) to place the drill. The orange dot shows where it drops the ore.",
                     drillSpot().map { .tiles($0) } ?? .none)
        case .selectFurnace:
            return h("Now pick the stone furnace on the bottom bar.", .hud(quickbarAnchors(furnaceItem) + ["build"]))
        case .placeFurnace:
            if ui.buildItem != furnaceItem {
                return h("Now pick the stone furnace on the bottom bar.", .hud(quickbarAnchors(furnaceItem) + ["build"]))
            }
            return h("Place the furnace on the highlighted tiles — right where the drill drops its ore.",
                     furnaceSpot().map { .tiles($0) } ?? .none)
        case .fuelDrill:
            guard let d = drillOnIron() else { return h("Place the drill first.", .none) }
            if ui.panel == "entity" && ui.openEntity == d {
                return h("Tap the coal in your inventory to put it into the drill's fuel slot.", .hud(["insert.\(coalItem)"]))
            }
            return h("The drill needs fuel. Tap the drill twice to open it.", .tiles(world.entities[d].rect))
        case .fuelFurnace:
            guard let f = furnaceAtOutput() else { return h("Place the furnace first.", .none) }
            if ui.panel == "entity" && ui.openEntity == f {
                return h("Tap the coal in your inventory to put it into the furnace.", .hud(["insert.\(coalItem)"]))
            }
            if !ui.panel.isEmpty { return h("Close this window and tap the furnace twice.", .hud(["panel.close"])) }
            return h("The furnace needs fuel too. Tap the furnace twice to open it.", .tiles(world.entities[f].rect))
        case .waitPlates:
            let t: TutorialTarget = furnaceAtOutput().map { .tiles(world.entities[$0].rect) } ?? .none
            return h("The drill mines ore and the furnace smelts it into iron plates. Wait a few seconds…", t)
        case .takePlates:
            guard let f = furnaceAtOutput() else { return h("Place the furnace first.", .none) }
            if ui.panel == "entity" && ui.openEntity == f {
                return h("Tap the iron plates in the output slot to take them.", .hud(["output.0"]))
            }
            if !ui.panel.isEmpty { return h("Close this window and tap the furnace twice.", .hud(["panel.close"])) }
            return h("Iron plates are ready. Tap the furnace twice to open it.", .tiles(world.entities[f].rect))
        case .craftDrill:
            if ui.panel != "inventory" {
                if !ui.panel.isEmpty { return h("Close this window, then open the inventory.", .hud(["panel.close"])) }
                return h("Now craft a second drill. Open the inventory.", .hud(["inventory"]))
            }
            return h("Tap the burner mining drill recipe. The gears and the furnace it needs are made automatically from your plates and stone.",
                     .hud(["recipe.\(drillRecipe)", "group.\(craftGroup(of: drillRecipe))", "tab.crafting"]))
        case .openMap:
            if !ui.panel.isEmpty && ui.panel != "map" {
                return h("Close this window, then tap the minimap.", .hud(["panel.close"]))
            }
            return h("Explore! Tap the minimap to open the map. Dark areas are unexplored — walk there to reveal new ore patches.",
                     .hud(["minimap"]))
        case .goals:
            return h("Great start! Next, follow the goals in the top-left corner: more drills on iron, copper and coal. Tap «?» at any time for the full guide.",
                     .none, next: true, last: true)
        }
    }

    // MARK: World queries

    private func playerEntities(_ proto: Int) -> [Int32] {
        var out: [Int32] = []
        for (i, r) in world.entities.records.enumerated() where r.isAlive && Int(r.proto) == proto
            && r.flags.contains(.playerBuilt) && !r.flags.contains(.ghost) {
            out.append(Int32(i))
        }
        return out
    }

    /// The player's burner drill that stands on iron ore.
    public func drillOnIron() -> Int32? {
        playerEntities(drillProto).first { e in
            var onIron = false
            world.entities[e].rect.forEach { p in if world.surface.resource(at: p).0 == ironRes { onIron = true } }
            return onIron
        }
    }

    private func drillOutputTile(_ d: Int32) -> TilePos? { world.mining.outputPoint(of: d)?.tile }

    /// A stone furnace covering the drill's output tile.
    public func furnaceAtOutput() -> Int32? {
        guard let d = drillOnIron(), let out = drillOutputTile(d) else { return nil }
        return playerEntities(furnaceProto).first { world.entities[$0].rect.contains(out) }
    }

    /// Nearest tile of a resource around the player, highlighted with its neighbours. Tiles below the character cost
    /// extra: the joystick and the bottom bar cover the lower part of the screen.
    private func nearestResource(_ res: Int) -> TileRect? {
        guard res >= 0 else { return nil }
        let c = world.player.position.tile
        var best: TilePos?, bestD = Int.max
        for dy in -40...40 {
            for dx in -40...40 {
                let d = dx * dx + dy * dy + max(0, dy + 2) * 12
                guard d < bestD else { continue }
                let p = TilePos(c.x + Int32(dx), c.y + Int32(dy))
                guard world.surface.isInBounds(p) else { continue }
                if world.surface.resource(at: p).0 == res, world.entity(at: p) == nil { best = p; bestD = d }
            }
        }
        return best.map { TileRect(x: $0.x - 1, y: $0.y - 1, w: 3, h: 3) }
    }

    /// Best 2×2 spot fully on iron ore near the player where the drill can be placed.
    public func drillSpot() -> TileRect? {
        guard drillProto >= 0, ironRes >= 0 else { return nil }
        let c = world.player.position.tile
        var best: TileRect?, bestD = Int.max
        for dy in -30...30 {
            for dx in -30...30 {
                let d = dx * dx + dy * dy
                guard d < bestD else { continue }
                let o = TilePos(c.x + Int32(dx), c.y + Int32(dy))
                guard world.surface.isInBounds(o) else { continue }
                var ok = true
                for yy in 0..<2 where ok { for xx in 0..<2 where ok {
                    ok = world.surface.resource(at: TilePos(o.x + Int32(xx), o.y + Int32(yy))).0 == ironRes
                } }
                guard ok, world.canPlace(proto: drillProto, origin: o, direction: .north) == nil else { continue }
                // the furnace must fit in front of it as well
                guard furnaceOrigin(forDrillAt: o) != nil else { continue }
                best = TileRect(x: o.x, y: o.y, w: 2, h: 2); bestD = d
            }
        }
        return best
    }

    private func furnaceOrigin(forDrillAt o: TilePos) -> TilePos? {
        guard let out = world.ioPoints(proto: drillProto, origin: o, dir: .north).output?.tile else { return nil }
        let drill = TileRect(x: o.x, y: o.y, w: 2, h: 2)
        return furnaceOrigin(covering: out, avoiding: drill)
    }

    private func furnaceOrigin(covering out: TilePos, avoiding drill: TileRect) -> TilePos? {
        let (fw, fh) = world.footprint(furnaceProto, .north)
        for dy in 0..<fh {
            for dx in 0..<fw {
                let o = TilePos(out.x - Int32(dx), out.y - Int32(dy))
                let r = TileRect(origin: o, w: fw, h: fh)
                if !r.intersects(drill) && world.canPlace(proto: furnaceProto, origin: o, direction: .north) == nil { return o }
            }
        }
        return nil
    }

    /// Where the furnace goes: covering the placed drill's output tile.
    public func furnaceSpot() -> TileRect? {
        guard let d = drillOnIron(), let out = drillOutputTile(d) else { return nil }
        guard let o = furnaceOrigin(covering: out, avoiding: world.entities[d].rect) else { return nil }
        let (fw, fh) = world.footprint(furnaceProto, .north)
        return TileRect(origin: o, w: fw, h: fh)
    }

    private func quickbarAnchors(_ item: Int) -> [String] {
        let qb = world.player.quickbar
        var out: [String] = []
        for i in 0..<min(10, qb.count) where Int(qb[i]) == item { out.append("quickbar.\(i)") }
        return out
    }

    /// Index of the crafting tab (item group without "combat") holding a recipe's result.
    private func craftGroup(of r: Int) -> Int {
        let db = world.db
        guard r >= 0 else { return 0 }
        let groups = db.data.itemGroups.filter { $0.id != "combat" }
        let sub = db.recipes[r].subgroup ?? db.resolvedRecipes[r].itemResults.first.map { db.items[$0.index].subgroup } ?? ""
        return groups.firstIndex { $0.subgroups.contains(sub) } ?? 0
    }
}
