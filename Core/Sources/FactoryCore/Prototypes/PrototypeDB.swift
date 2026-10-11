// Gearforge — FactoryCore
// Resolved, index-based prototype database. Immutable after load; shared by every World.

import Foundation

/// Dense indices into PrototypeDB arrays. Plain Int for speed; -1 means "none".
public typealias ItemIndex = Int
public typealias FluidIndex = Int
public typealias RecipeIndex = Int
public typealias TechIndex = Int
public typealias EntityProtoIndex = Int
public typealias TileIndex = Int
public typealias ResourceIndex = Int

/// A resolved recipe component (item or fluid by index).
public struct ResolvedComponent: Equatable, Sendable {
    public var index: Int
    public var isFluid: Bool
    public var amount: Double
    public var probability: Double
}

public struct ResolvedRecipe: Sendable {
    public var index: RecipeIndex
    public var ingredients: [ResolvedComponent]
    public var results: [ResolvedComponent]
    public var itemIngredients: [ResolvedComponent]
    public var fluidIngredients: [ResolvedComponent]
    public var itemResults: [ResolvedComponent]
    public var fluidResults: [ResolvedComponent]
    public var categoryIndex: Int
    public var time: Double
}

public enum PrototypeError: Error, CustomStringConvertible {
    case missingResource
    case unresolved(kind: String, id: String, referencedFrom: String)
    case duplicate(kind: String, id: String)
    public var description: String {
        switch self {
        case .missingResource: return "GameData.json not found in bundle"
        case .unresolved(let k, let id, let from): return "Unresolved \(k) '\(id)' referenced from \(from)"
        case .duplicate(let k, let id): return "Duplicate \(k) id '\(id)'"
        }
    }
}

public final class PrototypeDB: @unchecked Sendable {
    public let data: GameDataFile
    public let items: [ItemProto]
    public let fluids: [FluidProto]
    public let recipes: [RecipeProto]
    public let technologies: [TechProto]
    public let entities: [EntityProto]
    public let tiles: [TileProto]
    public let resources: [ResourceProto]

    public private(set) var itemIndex: [String: ItemIndex] = [:]
    public private(set) var fluidIndex: [String: FluidIndex] = [:]
    public private(set) var recipeIndex: [String: RecipeIndex] = [:]
    public private(set) var techIndex: [String: TechIndex] = [:]
    public private(set) var entityIndex: [String: EntityProtoIndex] = [:]
    public private(set) var tileIndex: [String: TileIndex] = [:]
    public private(set) var resourceIndex: [String: ResourceIndex] = [:]
    public private(set) var categoryIndex: [String: Int] = [:]

    /// Resolved recipes (parallel to `recipes`).
    public private(set) var resolvedRecipes: [ResolvedRecipe] = []
    /// item -> entity placed by it (or -1).
    public private(set) var itemPlaceResult: [EntityProtoIndex] = []
    /// item -> tile placed by it (or -1).
    public private(set) var itemPlaceTile: [TileIndex] = []
    /// entity -> item used to place it (first matching item, or -1).
    public private(set) var entityItem: [ItemIndex] = []
    /// item -> recipes producing it.
    public private(set) var recipesProducing: [[RecipeIndex]] = []
    /// smelting input item -> furnace recipe (for auto-recipe furnaces), keyed by category index then item.
    public private(set) var furnaceRecipeByInput: [Int: [ItemIndex: RecipeIndex]] = [:]
    /// Per entity: crafting category indices it supports.
    public private(set) var entityCategories: [Set<Int>] = []
    /// tech -> prerequisite tech indices.
    public private(set) var techPrereqs: [[TechIndex]] = []
    /// tech -> unlocked recipe indices.
    public private(set) var techUnlocks: [[RecipeIndex]] = []
    /// recipe -> technologies that unlock it.
    public private(set) var recipeUnlockedBy: [[TechIndex]] = []

    public init(data: GameDataFile) throws {
        self.data = data
        items = data.items; fluids = data.fluids; recipes = data.recipes
        technologies = data.technologies; entities = data.entities; tiles = data.tiles; resources = data.resources
        try buildIndices()
    }

    /// Loads the bundled GameData.json.
    public static func loadBundled() throws -> PrototypeDB {
        guard let url = Bundle.module.url(forResource: "GameData", withExtension: "json") else {
            throw PrototypeError.missingResource
        }
        let bytes = try Data(contentsOf: url)
        let file = try JSONDecoder().decode(GameDataFile.self, from: bytes)
        return try PrototypeDB(data: file)
    }

    /// Process-wide shared instance (loaded once; prototype data is immutable).
    public static let shared: PrototypeDB = {
        do { return try loadBundled() } catch { fatalError("Failed to load game data: \(error)") }
    }()

    private func index<T>(_ arr: [T], kind: String, id: (T) -> String) throws -> [String: Int] {
        var m: [String: Int] = [:]
        m.reserveCapacity(arr.count)
        for (i, e) in arr.enumerated() {
            let k = id(e)
            if m[k] != nil { throw PrototypeError.duplicate(kind: kind, id: k) }
            m[k] = i
        }
        return m
    }

    private func buildIndices() throws {
        itemIndex = try index(items, kind: "item") { $0.id }
        fluidIndex = try index(fluids, kind: "fluid") { $0.id }
        recipeIndex = try index(recipes, kind: "recipe") { $0.id }
        techIndex = try index(technologies, kind: "technology") { $0.id }
        entityIndex = try index(entities, kind: "entity") { $0.id }
        tileIndex = try index(tiles, kind: "tile") { $0.id }
        resourceIndex = try index(resources, kind: "resource") { $0.id }

        var cats: [String: Int] = [:]
        for r in recipes where cats[r.category] == nil { cats[r.category] = cats.count }
        for e in entities { for c in e.crafting?.categories ?? [] where cats[c] == nil { cats[c] = cats.count } }
        categoryIndex = cats

        func comp(_ c: RecipeComponent, from: String) throws -> ResolvedComponent {
            if c.isFluid {
                guard let i = fluidIndex[c.id] else { throw PrototypeError.unresolved(kind: "fluid", id: c.id, referencedFrom: from) }
                return ResolvedComponent(index: i, isFluid: true, amount: c.amount, probability: c.probability ?? 1)
            } else {
                guard let i = itemIndex[c.id] else { throw PrototypeError.unresolved(kind: "item", id: c.id, referencedFrom: from) }
                return ResolvedComponent(index: i, isFluid: false, amount: c.amount, probability: c.probability ?? 1)
            }
        }

        recipesProducing = Array(repeating: [], count: items.count)
        resolvedRecipes = try recipes.enumerated().map { (i, r) in
            let ing = try r.ingredients.map { try comp($0, from: "recipe \(r.id)") }
            let res = try r.results.map { try comp($0, from: "recipe \(r.id)") }
            for c in res where !c.isFluid { recipesProducing[c.index].append(i) }
            return ResolvedRecipe(index: i, ingredients: ing, results: res,
                                  itemIngredients: ing.filter { !$0.isFluid }, fluidIngredients: ing.filter { $0.isFluid },
                                  itemResults: res.filter { !$0.isFluid }, fluidResults: res.filter { $0.isFluid },
                                  categoryIndex: cats[r.category]!, time: r.time)
        }

        itemPlaceResult = try items.map { it in
            guard let p = it.placeResult else { return -1 }
            guard let e = entityIndex[p] else { throw PrototypeError.unresolved(kind: "entity", id: p, referencedFrom: "item \(it.id)") }
            return e
        }
        itemPlaceTile = try items.map { it in
            guard let p = it.placeAsTile else { return -1 }
            guard let t = tileIndex[p] else { throw PrototypeError.unresolved(kind: "tile", id: p, referencedFrom: "item \(it.id)") }
            return t
        }
        entityItem = Array(repeating: -1, count: entities.count)
        for (i, e) in itemPlaceResult.enumerated() where e >= 0 && entityItem[e] < 0 { entityItem[e] = i }

        entityCategories = entities.map { Set(($0.crafting?.categories ?? []).compactMap { cats[$0] }) }

        for r in resolvedRecipes where recipes[r.index].category == "smelting" && r.itemIngredients.count == 1 {
            furnaceRecipeByInput[r.categoryIndex, default: [:]][r.itemIngredients[0].index] = r.index
        }

        recipeUnlockedBy = Array(repeating: [], count: recipes.count)
        techPrereqs = try technologies.map { t in
            try t.prerequisites.map { p in
                guard let i = techIndex[p] else { throw PrototypeError.unresolved(kind: "technology", id: p, referencedFrom: "tech \(t.id)") }
                return i
            }
        }
        techUnlocks = try technologies.enumerated().map { (ti, t) in
            try t.effects.compactMap { e -> Int? in
                guard e.type == "unlock-recipe", let rid = e.recipe else { return nil }
                guard let ri = recipeIndex[rid] else { throw PrototypeError.unresolved(kind: "recipe", id: rid, referencedFrom: "tech \(t.id)") }
                recipeUnlockedBy[ri].append(ti)
                return ri
            }
        }

        // Validate remaining references.
        for t in technologies {
            for ing in t.ingredients where itemIndex[ing.id] == nil {
                throw PrototypeError.unresolved(kind: "item", id: ing.id, referencedFrom: "tech \(t.id)")
            }
        }
        for e in entities {
            for m in e.minedResults where itemIndex[m.id] == nil {
                throw PrototypeError.unresolved(kind: "item", id: m.id, referencedFrom: "entity \(e.id)")
            }
            if let f = e.crafting?.fixedRecipe, recipeIndex[f] == nil {
                throw PrototypeError.unresolved(kind: "recipe", id: f, referencedFrom: "entity \(e.id)")
            }
            if let u = e.nextUpgrade, entityIndex[u] == nil {
                throw PrototypeError.unresolved(kind: "entity", id: u, referencedFrom: "entity \(e.id) nextUpgrade")
            }
        }
        for r in resources {
            if r.resultIsFluid ? fluidIndex[r.result] == nil : itemIndex[r.result] == nil {
                throw PrototypeError.unresolved(kind: r.resultIsFluid ? "fluid" : "item", id: r.result, referencedFrom: "resource \(r.id)")
            }
        }
    }

    // MARK: Convenience lookups (not for hot loops)

    public func item(_ id: String) -> ItemIndex { itemIndex[id] ?? -1 }
    public func fluid(_ id: String) -> FluidIndex { fluidIndex[id] ?? -1 }
    public func recipe(_ id: String) -> RecipeIndex { recipeIndex[id] ?? -1 }
    public func tech(_ id: String) -> TechIndex { techIndex[id] ?? -1 }
    public func entity(_ id: String) -> EntityProtoIndex { entityIndex[id] ?? -1 }
    public func tile(_ id: String) -> TileIndex { tileIndex[id] ?? -1 }
    public func resource(_ id: String) -> ResourceIndex { resourceIndex[id] ?? -1 }

    /// Whether entity `e` can craft recipe `r` (category match).
    public func canCraft(entity e: EntityProtoIndex, recipe r: RecipeIndex) -> Bool {
        entityCategories[e].contains(resolvedRecipes[r].categoryIndex)
    }
}
