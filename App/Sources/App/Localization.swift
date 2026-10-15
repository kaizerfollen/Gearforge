// Gearforge — localization (GDD §10 "string tables from day 1"). Languages: English (base) and Russian.
//
// Two tables, both under App/Resources/<lang>.lproj/:
//   Localizable.strings — UI text. Key = the English text (SwiftUI `Text("literal")` looks these up by itself;
//                         interpolated literals use format keys such as "Researching %@"). Code paths that carry a
//                         plain `String` go through `L(_:)` / `LF(_:_:)`.
//   GameData.strings    — names of game content: item.<id>, entity.<id>, recipe.<id>, tech.<id>, fluid.<id>,
//                         group.<id>, tile.<id>, resource.<id>, level.<L>.title|subtitle|teaches,
//                         objective.<L>.<n>.title|hint. Missing keys fall back to the English name in GameData.json.
// The language follows the device / per-app language setting (iOS Settings → Gearforge → Language).

import Foundation
import FactoryCore

/// Localized UI string (key = English text). Unknown keys are returned unchanged.
func L(_ key: String) -> String {
    NSLocalizedString(key, tableName: nil, bundle: .main, value: key, comment: "")
}

/// Localized format string (key = English format, e.g. "Out of %@"), then formatted.
func LF(_ key: String, _ args: CVarArg...) -> String {
    String(format: L(key), arguments: args)
}

/// Localized names of game content.
enum Names {
    private static let missing = "\u{1}"
    nonisolated(unsafe) private static var cache: [String: String] = [:]

    static func lookup(_ key: String, _ fallback: String) -> String {
        if let c = cache[key] { return c }
        let v = Bundle.main.localizedString(forKey: key, value: missing, table: "GameData")
        let r = v == missing ? fallback : v
        cache[key] = r
        return r
    }

    static func item(_ db: PrototypeDB, _ i: Int) -> String {
        guard i >= 0 && i < db.items.count else { return "" }
        return lookup("item.\(db.items[i].id)", db.items[i].name)
    }
    static func entity(_ db: PrototypeDB, _ e: Int) -> String {
        guard e >= 0 && e < db.entities.count else { return "" }
        let p = db.entities[e]
        // Most entities share their placing item's name.
        let item = db.entityItem[e]
        return lookup("entity.\(p.id)", item >= 0 ? self.item(db, item) : p.name)
    }
    static func recipe(_ db: PrototypeDB, _ r: Int) -> String {
        guard r >= 0 && r < db.recipes.count else { return "" }
        let rp = db.recipes[r]
        let main = db.resolvedRecipes[r].itemResults.first?.index
        let fallback = (main != nil && db.items[main!].name == rp.name) ? item(db, main!) : rp.name
        return lookup("recipe.\(rp.id)", fallback)
    }
    static func tech(_ db: PrototypeDB, _ t: Int) -> String {
        guard t >= 0 && t < db.technologies.count else { return "" }
        return lookup("tech.\(db.technologies[t].id)", db.technologies[t].name)
    }
    static func fluid(_ db: PrototypeDB, _ f: Int) -> String {
        guard f >= 0 && f < db.fluids.count else { return "" }
        return lookup("fluid.\(db.fluids[f].id)", db.fluids[f].name)
    }
    static func group(_ g: ItemGroupProto) -> String { lookup("group.\(g.id)", g.name) }

    static func levelTitle(_ l: LevelDefinition) -> String { lookup("level.\(l.id).title", l.title) }
    static func levelSubtitle(_ l: LevelDefinition) -> String { lookup("level.\(l.id).subtitle", l.subtitle) }
    static func levelTeaches(_ l: LevelDefinition) -> String { lookup("level.\(l.id).teaches", l.teaches) }
    static func objectiveTitle(_ levelID: String?, _ o: Objective) -> String {
        guard let id = levelID else { return L(o.title) }
        return lookup("objective.\(id).\(o.id).title", o.title)
    }
    static func objectiveHint(_ levelID: String?, _ o: Objective) -> String? {
        guard let h = o.hint else { return nil }
        guard let id = levelID else { return L(h) }
        return lookup("objective.\(id).\(o.id).hint", h)
    }
}

extension PrototypeDB {
    func itemName(_ i: Int) -> String { Names.item(self, i) }
    func entityName(_ e: Int) -> String { Names.entity(self, e) }
    func recipeName(_ r: Int) -> String { Names.recipe(self, r) }
    func techName(_ t: Int) -> String { Names.tech(self, t) }
    func fluidName(_ f: Int) -> String { Names.fluid(self, f) }
}
