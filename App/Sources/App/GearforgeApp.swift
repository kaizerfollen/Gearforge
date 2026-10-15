// Gearforge — App entry point.

import SwiftUI
import FactoryCore
import SpriteKit

@main
struct GearforgeApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .preferredColorScheme(.dark)
                .statusBarHidden(true)
                .persistentSystemOverlays(.hidden)
        }
        .onChange(of: scenePhase) { _, phase in
            model.scenePhaseChanged(phase)
        }
    }
}

struct RootView: View {
    @Bindable var model: AppModel

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if model.screen != .game, let s = model.menuScene {
                // live factory behind the menus, darkened so the buttons stay readable
                SpriteView(scene: s, preferredFramesPerSecond: 30)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                LinearGradient(colors: [Color.black.opacity(0.58), Color.black.opacity(0.8)],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
            switch model.screen {
            case .menu:
                MainMenuView(model: model)
            case .newGame:
                NewGameView(model: model)
            case .load:
                LoadGameView(model: model)
            case .settings:
                SettingsView(model: model)
            case .guide:
                GuidePanel(onClose: { model.screen = .settings })
            case .loading(let text):
                LoadingView(text: text)
            case .game:
                if let c = model.controller { GameView(model: model, controller: c) }
            }
        }
        .onAppear { model.prepareMenuBackground() }
        .onChange(of: model.screen) { _, s in if s != .game { model.prepareMenuBackground() } }
        .alert("Gearforge", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

struct LoadingView: View {
    let text: String
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text(LocalizedStringKey(text)).font(.headline).foregroundStyle(Theme.text)
        }
    }
}
