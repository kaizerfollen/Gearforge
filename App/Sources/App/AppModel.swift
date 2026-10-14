// Gearforge — App model: navigation, saves, settings, campaign progress, lifecycle (pause & background save).

import Foundation
import Observation
import SwiftUI
import FactoryCore

enum AppScreen: Equatable {
    case menu, newGame, load, settings, game
    case loading(String)
}

@MainActor
@Observable
final class AppModel {
    var screen: AppScreen = .menu
    var controller: GameController?
    var errorMessage: String?
    var settings: GameSettings { didSet { saveSettings() } }
    var progress: CampaignProgress
    var saves: [SaveMetadata] = []
    /// Previous session ended without a clean save → offer the background save.
    var offerRecovery = false

    @ObservationIgnored let saveManager: SaveManager
    @ObservationIgnored private let settingsURL: URL
    @ObservationIgnored private let progressURL: URL
    @ObservationIgnored var scene: GameScene?

    init() {
        let support = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        let dir = support.appendingPathComponent("Gearforge", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        saveManager = SaveManager(directory: dir.appendingPathComponent("Saves", isDirectory: true), compressor: makeCompressor())
        settingsURL = dir.appendingPathComponent("settings.json")
        progressURL = dir.appendingPathComponent("campaign.json")
        settings = (try? JSONDecoder().decode(GameSettings.self, from: Data(contentsOf: settingsURL))) ?? GameSettings()
        progress = CampaignProgress.load(from: progressURL)
        offerRecovery = saveManager.hadUncleanExit && FileManager.default.fileExists(atPath: saveManager.url(for: SaveManager.backgroundSlot).path)
        refreshSaves()
    }

    private func saveSettings() {
        if let d = try? JSONEncoder().encode(settings) { try? d.write(to: settingsURL, options: .atomic) }
        controller?.settings = settings
    }

    func refreshSaves() { saves = saveManager.listSaves() }

    var canContinue: Bool { !saves.isEmpty }

    // MARK: Starting games

    func startFreeplay(_ ws: WorldSettings) {
        start(label: "Generating world…") { GameSession.newFreeplay(settings: ws) }
    }

    func startCampaign(_ level: LevelDefinition) {
        start(label: LF("Landing on %@…", Names.levelTitle(level))) { GameSession.newCampaign(level: level) }
    }

    func continueLatest() {
        guard let m = saveManager.mostRecent else { return }
        load(slot: m.slot)
    }

    func load(slot: String) {
        start(label: "Loading…") { [saveManager] in try saveManager.load(slot: slot) }
    }

    private func start(label: String, _ make: @escaping () throws -> GameSession) {
        screen = .loading(label)
        // let the loading screen render first
        DispatchQueue.main.async {
            do {
                let session = try make()
                self.begin(session)
            } catch {
                self.errorMessage = "\(error)"
                self.screen = .menu
            }
        }
    }

    private func begin(_ session: GameSession) {
        let c = GameController(session: session, saveManager: saveManager, settings: settings)
        c.onLevelCompleted = { [weak self] stars, seconds in
            guard let self, case .campaign(let id) = session.mode else { return }
            self.progress.record(level: id, stars: stars, seconds: seconds)
            try? self.progress.save(to: self.progressURL)
        }
        controller = c
        let s = GameScene(size: CGSize(width: 1024, height: 768))
        s.controller = c
        scene = s
        saveManager.markSessionStarted()
        offerRecovery = false
        screen = .game
    }

    func quitToMenu(save: Bool) {
        if save, let c = controller { c.save(slot: "autosave_exit", name: "Last exit") }
        saveManager.markSessionEnded()
        controller = nil
        scene = nil
        refreshSaves()
        screen = .menu
    }

    // MARK: Lifecycle

    func scenePhaseChanged(_ phase: ScenePhase) {
        guard let c = controller else { return }
        switch phase {
        case .background:
            c.backgroundSave()
            saveManager.markSessionEnded()
        case .inactive:
            c.session.isPaused = true
        case .active:
            saveManager.markSessionStarted()
        @unknown default:
            break
        }
    }
}
