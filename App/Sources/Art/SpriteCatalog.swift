// Gearforge — App
// Texture lookup for SpriteKit and SwiftUI. Owner: Technical artist.
// SKELETON — keep the public API; the renderer and UI code against it.

import SpriteKit
import UIKit

@MainActor
public final class SpriteCatalog {
    public static let shared = SpriteCatalog()

    /// SpriteKit texture by sprite name (see docs/ARCHITECTURE.md §6 naming). Never fails: returns a generated
    /// placeholder for unknown names.
    public func texture(_ name: String) -> SKTexture {
        SKTexture(imageNamed: name)
    }

    /// UIImage for SwiftUI (`Image(uiImage:)`), e.g. item icons in inventory/crafting UI.
    public func image(_ name: String) -> UIImage {
        UIImage(named: name) ?? UIImage()
    }

    public func itemIcon(_ itemID: String) -> UIImage { image("item_\(itemID)") }
    public func itemTexture(_ itemID: String) -> SKTexture { texture("item_\(itemID)") }
}
