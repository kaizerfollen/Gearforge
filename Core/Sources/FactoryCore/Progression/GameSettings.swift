// Gearforge — FactoryCore
// Player preferences (GDD §10) — not per-save. Persisted as JSON by SettingsStore. Owner: Progression engineer.

import Foundation

public struct GameSettings: Codable, Equatable, Sendable {
    // Graphics
    public var qualityPreset: String = "high"          // low | medium | high | ultra
    public var frameRateCap: Int = 60                  // 30 | 60 | 120
    public var dayNightLighting: Bool = true
    public var showGrid: String = "build"              // off | build | always
    public var altMode: Bool = true
    // Interface
    public var uiScale: Double = 1.0
    public var showReachCircle: Bool = true
    public var haptics: Bool = true
    public var leftHanded: Bool = false
    // Controls
    public var tapToWalk: Bool = true
    public var oneTapPlace: Bool = false               // legacy (unused) — see confirmPlacement
    /// Build mode: first tap shows the ghost, a second tap on the same spot builds (off = build on first tap).
    public var confirmPlacement: Bool = false
    public var joystickFloating: Bool = true
    // Gameplay
    public var autosaveMinutes: Int = 5                // 0 = off
    public var autosaveSlots: Int = 3
    public var autoBuildGhosts: Bool = true
    public var confirmAreaRemoveThreshold: Int = 20
    // Performance
    public var batterySaver: Bool = false
    public var showFPS: Bool = false
    // Audio
    public var masterVolume: Double = 0.8
    public var musicVolume: Double = 0.6
    public var sfxVolume: Double = 0.8
    // Accessibility
    public var colorblindMode: String = "off"          // off | deuteranopia | protanopia | tritanopia
    public var reduceMotion: Bool = false
    // Help
    public var tutorialHints: Bool = true
    public init() {}

    /// Decodes settings saved by any app version: keys missing in `data` (added later) keep their defaults,
    /// unknown keys are ignored. Returns nil only for unreadable JSON.
    public static func decodeTolerant(_ data: Data) -> GameSettings? {
        guard let saved = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let defData = try? JSONEncoder().encode(GameSettings()),
              var merged = (try? JSONSerialization.jsonObject(with: defData)) as? [String: Any] else { return nil }
        for (k, v) in saved where merged[k] != nil { merged[k] = v }
        guard let m = try? JSONSerialization.data(withJSONObject: merged) else { return nil }
        return try? JSONDecoder().decode(GameSettings.self, from: m)
    }
}

public final class SettingsStore {
    public let url: URL
    public private(set) var settings: GameSettings
    public init(url: URL) {
        self.url = url
        if let d = try? Data(contentsOf: url), let s = GameSettings.decodeTolerant(d) { settings = s }
        else { settings = GameSettings() }
    }
    public func update(_ body: (inout GameSettings) -> Void) {
        body(&settings)
        if let d = try? JSONEncoder().encode(settings) { try? d.write(to: url, options: .atomic) }
    }
}
