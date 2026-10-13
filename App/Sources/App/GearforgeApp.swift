// Gearforge — App
// Placeholder entry point (platform bootstrap). Owner: Lead — replace ContentView with the real root view.

import SwiftUI
import SpriteKit
import FactoryCore

@main
struct GearforgeApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @State private var scene: SKScene = {
        let scene = SKScene(size: CGSize(width: 1024, height: 768))
        scene.scaleMode = .resizeFill
        scene.backgroundColor = .black
        return scene
    }()

    var body: some View {
        ZStack(alignment: .topLeading) {
            SpriteView(scene: scene, options: [.ignoresSiblingOrder])
                .ignoresSafeArea()
            Text("FactoryCore items: \(PrototypeDB.shared.items.count)")
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .padding(8)
        }
        .statusBarHidden()
    }
}
