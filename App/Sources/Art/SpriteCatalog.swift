// Gearforge — App
// Texture lookup for SpriteKit and SwiftUI. Names follow docs/art/ART_BIBLE.md (sprite_manifest.json lists them all).
// Missing names never crash: a generated placeholder (magenta checker) is returned and logged once.

import Foundation
import SpriteKit
import UIKit
import FactoryCore

@MainActor
final class SpriteCatalog {
    static let shared = SpriteCatalog()

    private let atlas = SKTextureAtlas(named: "Sprites")
    private var cache: [String: SKTexture] = [:]
    private var imageCache: [String: UIImage] = [:]
    private(set) var names: Set<String> = []
    private var placeholder: SKTexture?

    private init() {
        for n in atlas.textureNames { names.insert((n as NSString).deletingPathExtension) }
        if names.isEmpty, let url = Bundle.main.url(forResource: "sprite_manifest", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            names = Set(obj.keys)
        }
    }

    func has(_ name: String) -> Bool { names.contains(name) }

    /// SpriteKit texture by sprite name.
    func texture(_ name: String) -> SKTexture {
        if let t = cache[name] { return t }
        let t: SKTexture
        if names.isEmpty || names.contains(name) {
            t = atlas.textureNamed(name)
        } else {
            t = placeholderTexture()
        }
        t.filteringMode = .linear
        cache[name] = t
        return t
    }

    /// First existing name of the candidates (falls back to the last).
    func texture(firstOf candidates: [String]) -> SKTexture {
        for c in candidates where has(c) { return texture(c) }
        return texture(candidates.last ?? "")
    }

    func preload(_ done: @escaping () -> Void) {
        atlas.preload { DispatchQueue.main.async { done() } }
    }

    private func placeholderTexture() -> SKTexture {
        if let p = placeholder { return p }
        let r = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16))
        let img = r.image { ctx in
            UIColor(red: 1, green: 0, blue: 1, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
            UIColor.black.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
            ctx.fill(CGRect(x: 8, y: 8, width: 8, height: 8))
        }
        let t = SKTexture(image: img)
        placeholder = t
        return t
    }

    /// UIImage for SwiftUI (`Image(uiImage:)`), e.g. item icons.
    func image(_ name: String) -> UIImage {
        if let i = imageCache[name] { return i }
        let img = UIImage(cgImage: texture(name).cgImage())
        imageCache[name] = img
        return img
    }

    // MARK: Convenience names

    func itemIcon(_ item: Int, db: PrototypeDB) -> UIImage {
        guard item >= 0 && item < db.items.count else { return image("ui_cross") }
        return image("i_\(db.items[item].id)")
    }
    func fluidIcon(_ fluid: Int, db: PrototypeDB) -> UIImage {
        guard fluid >= 0 && fluid < db.fluids.count else { return image("ui_cross") }
        return image("f_\(db.fluids[fluid].id)")
    }
    func recipeIcon(_ recipe: Int, db: PrototypeDB) -> UIImage {
        let r = db.resolvedRecipes[recipe]
        if let it = r.itemResults.first { return itemIcon(it.index, db: db) }
        if let fl = r.fluidResults.first { return fluidIcon(fl.index, db: db) }
        return image("ui_craft")
    }
    func techIcon(_ tech: Int, db: PrototypeDB) -> UIImage {
        let t = db.technologies[tech]
        // icon: first unlocked recipe's product, else the first ingredient card
        for e in t.effects where e.type == "unlock-recipe" {
            if let r = e.recipe, db.recipe(r) >= 0 { return recipeIcon(db.recipe(r), db: db) }
        }
        if let c = t.ingredients.last { return itemIcon(db.item(c.id), db: db) }
        return image("ui_research")
    }
}

/// Sprite name helpers shared by the renderer.
enum SpriteNames {
    static func dirSuffix(_ d: Direction) -> String {
        switch d { case .north: return "n"; case .east: return "e"; case .south: return "s"; case .west: return "w" }
    }
}
