// Gearforge — App entry point.

import SwiftUI
import FactoryCore

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
                GuidePanel(onClose: { model.screen = .menu })
            case .loading(let text):
                LoadingView(text: text)
            case .game:
                if let c = model.controller { GameView(model: model, controller: c) }
            }
        }
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
