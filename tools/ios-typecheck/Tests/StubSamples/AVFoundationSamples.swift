// Realistic AVFoundation usage: regression test for Stubs/AVFoundation (typecheck only, never run).
import Foundation
import AVFoundation

@MainActor
final class AVFoundationSample {
    let engine = AVAudioEngine()
    let player = AVAudioPlayerNode()
    let mixer = AVAudioMixerNode()

    func build(url: URL) throws {
        let file = try AVAudioFile(forReading: url)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))
        else { return }
        try file.read(into: buffer)
        engine.attach(mixer)
        engine.attach(player)
        engine.connect(mixer, to: engine.mainMixerNode, format: nil)
        engine.connect(player, to: mixer, format: buffer.format)
        mixer.outputVolume = 0.5
        player.volume = 0.8
        player.pan = -0.3
        player.scheduleBuffer(buffer, at: nil, options: [.loops], completionHandler: nil)
        player.scheduleBuffer(buffer) { print("done") }
        let fmt = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)
        _ = (fmt?.sampleRate, fmt?.channelCount, buffer.frameLength, file.fileFormat.sampleRate)
        engine.prepare()
        try engine.start()
        if engine.isRunning { player.play() }
        player.pause(); player.stop(); engine.pause(); engine.stop()
        let t = AVAudioTime(sampleTime: 0, atRate: 44_100)
        player.play(at: t)
        _ = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { _ in }
    }

    func session() throws {
        let s = AVAudioSession.sharedInstance()
        try s.setCategory(.ambient, mode: .default, options: [])
        try s.setCategory(.playback, options: [.mixWithOthers, .duckOthers])
        try s.setActive(true)
        try s.setActive(false, options: .notifyOthersOnDeactivation)
        _ = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            if let type = raw.flatMap(AVAudioSession.InterruptionType.init(rawValue:)), type == .ended {
                let opts = AVAudioSession.InterruptionOptions(rawValue: note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
                _ = opts.contains(.shouldResume)
            }
        }
    }
}
