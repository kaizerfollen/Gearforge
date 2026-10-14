// API stub of Apple's AVFoundation / AVFAudio (subset) for the Linux typecheck harness.
// Signatures mirror the iOS 17/18 SDK (AVFAudio headers as imported into Swift): labels, optionality, `throws`,
// default arguments, and which properties are read-only. On Apple, AVFoundation re-exports AVFAudio. This
// single module plays both roles, so `import AVFoundation` and the app code see the same names.
// AVAudioSession is iOS-only (API_UNAVAILABLE(macos)). Guard its use with `#if os(iOS) || GEARFORGE_TYPECHECK`.
@_exported import Foundation

@inline(never) func _stub() -> Never { fatalError("AVFoundation stub: typecheck only") }

// MARK: - Scalar typedefs (AVAudioTypes.h)

public typealias AVAudioFramePosition = Int64
public typealias AVAudioFrameCount = UInt32
public typealias AVAudioPacketCount = UInt32
public typealias AVAudioChannelCount = UInt32
public typealias AVAudioNodeBus = Int

/// Xcode 16 SDK: `typedef void (^AVAudioNodeCompletionHandler)(void)` imported as `@Sendable`.
public typealias AVAudioNodeCompletionHandler = @Sendable () -> Void

// MARK: - Format / buffers / files

public enum AVAudioCommonFormat: UInt, Sendable {
    case otherFormat = 0, pcmFormatFloat32 = 1, pcmFormatFloat64 = 2, pcmFormatInt16 = 3, pcmFormatInt32 = 4
}

open class AVAudioFormat: NSObject {
    public init?(standardFormatWithSampleRate sampleRate: Double, channels: AVAudioChannelCount) { _stub() }
    public init?(commonFormat format: AVAudioCommonFormat, sampleRate: Double, channels: AVAudioChannelCount, interleaved: Bool) { _stub() }
    open var sampleRate: Double { _stub() }
    open var channelCount: AVAudioChannelCount { _stub() }
    open var isInterleaved: Bool { _stub() }
    open var isStandard: Bool { _stub() }
    open var commonFormat: AVAudioCommonFormat { _stub() }
}

open class AVAudioBuffer: NSObject {
    open var format: AVAudioFormat { _stub() }
}

open class AVAudioPCMBuffer: AVAudioBuffer {
    public init?(pcmFormat format: AVAudioFormat, frameCapacity: AVAudioFrameCount) { _stub() }
    open var frameCapacity: AVAudioFrameCount { _stub() }
    open var frameLength: AVAudioFrameCount { get { _stub() } set { _stub() } }
    open var stride: Int { _stub() }
    open var floatChannelData: UnsafePointer<UnsafeMutablePointer<Float>>? { _stub() }
    open var int16ChannelData: UnsafePointer<UnsafeMutablePointer<Int16>>? { _stub() }
}

open class AVAudioFile: NSObject {
    public init(forReading fileURL: URL) throws { _stub() }
    public init(forReading fileURL: URL, commonFormat format: AVAudioCommonFormat, interleaved: Bool) throws { _stub() }
    open func read(into buffer: AVAudioPCMBuffer) throws { _stub() }
    open func read(into buffer: AVAudioPCMBuffer, frameCount frames: AVAudioFrameCount) throws { _stub() }
    open var url: URL { _stub() }
    open var fileFormat: AVAudioFormat { _stub() }
    open var processingFormat: AVAudioFormat { _stub() }
    open var length: AVAudioFramePosition { _stub() }
    open var framePosition: AVAudioFramePosition { get { _stub() } set { _stub() } }
}

// MARK: - Time

open class AVAudioTime: NSObject {
    public init(sampleTime: AVAudioFramePosition, atRate sampleRate: Double) { _stub() }
    public init(hostTime: UInt64) { _stub() }
    open var sampleTime: AVAudioFramePosition { _stub() }
    open var sampleRate: Double { _stub() }
    open var hostTime: UInt64 { _stub() }
    open var isSampleTimeValid: Bool { _stub() }
    open var isHostTimeValid: Bool { _stub() }
}

// MARK: - Mixing protocols (AVAudioMixing.h)

public protocol AVAudioStereoMixing: NSObjectProtocol {
    var pan: Float { get set }
}

public protocol AVAudioMixing: AVAudioStereoMixing {
    var volume: Float { get set }
}

// MARK: - Nodes

open class AVAudioNode: NSObject {
    open func reset() { _stub() }
    open func inputFormat(forBus bus: AVAudioNodeBus) -> AVAudioFormat { _stub() }
    open func outputFormat(forBus bus: AVAudioNodeBus) -> AVAudioFormat { _stub() }
    open var engine: AVAudioEngine? { _stub() }
    open var numberOfInputs: Int { _stub() }
    open var numberOfOutputs: Int { _stub() }
    open var lastRenderTime: AVAudioTime? { _stub() }
}

open class AVAudioIONode: AVAudioNode {}
open class AVAudioOutputNode: AVAudioIONode {}

open class AVAudioMixerNode: AVAudioNode, AVAudioMixing {
    public override init() { _stub() }
    open var outputVolume: Float { get { _stub() } set { _stub() } }
    open var nextAvailableInputBus: AVAudioNodeBus { _stub() }
    // AVAudioMixing (as an input of another mixer)
    open var volume: Float { get { _stub() } set { _stub() } }
    open var pan: Float { get { _stub() } set { _stub() } }
}

public struct AVAudioPlayerNodeBufferOptions: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static var loops: AVAudioPlayerNodeBufferOptions { AVAudioPlayerNodeBufferOptions(rawValue: 1 << 0) }
    public static var interrupts: AVAudioPlayerNodeBufferOptions { AVAudioPlayerNodeBufferOptions(rawValue: 1 << 1) }
    public static var interruptsAtLoop: AVAudioPlayerNodeBufferOptions { AVAudioPlayerNodeBufferOptions(rawValue: 1 << 2) }
}

open class AVAudioPlayerNode: AVAudioNode, AVAudioMixing {
    public override init() { _stub() }
    open func scheduleBuffer(_ buffer: AVAudioPCMBuffer, completionHandler: AVAudioNodeCompletionHandler? = nil) { _stub() }
    open func scheduleBuffer(_ buffer: AVAudioPCMBuffer, at when: AVAudioTime?, options: AVAudioPlayerNodeBufferOptions = [],
                             completionHandler: AVAudioNodeCompletionHandler? = nil) { _stub() }
    open func scheduleFile(_ file: AVAudioFile, at when: AVAudioTime?, completionHandler: AVAudioNodeCompletionHandler? = nil) { _stub() }
    open func play() { _stub() }
    open func play(at when: AVAudioTime?) { _stub() }
    open func pause() { _stub() }
    open func stop() { _stub() }
    open func prepare(withFrameCount frameCount: AVAudioFrameCount) { _stub() }
    open var isPlaying: Bool { _stub() }
    open func nodeTime(forPlayerTime playerTime: AVAudioTime) -> AVAudioTime? { _stub() }
    open func playerTime(forNodeTime nodeTime: AVAudioTime) -> AVAudioTime? { _stub() }
    // AVAudioMixing
    open var volume: Float { get { _stub() } set { _stub() } }
    open var pan: Float { get { _stub() } set { _stub() } }
}

// MARK: - Engine

open class AVAudioEngine: NSObject {
    public override init() { _stub() }
    open func attach(_ node: AVAudioNode) { _stub() }
    open func detach(_ node: AVAudioNode) { _stub() }
    open func connect(_ node1: AVAudioNode, to node2: AVAudioNode, fromBus bus1: AVAudioNodeBus, toBus bus2: AVAudioNodeBus,
                      format: AVAudioFormat?) { _stub() }
    open func connect(_ node1: AVAudioNode, to node2: AVAudioNode, format: AVAudioFormat?) { _stub() }
    open func disconnectNodeInput(_ node: AVAudioNode) { _stub() }
    open func disconnectNodeOutput(_ node: AVAudioNode) { _stub() }
    open func prepare() { _stub() }
    open func start() throws { _stub() }
    open func pause() { _stub() }
    open func reset() { _stub() }
    open func stop() { _stub() }
    open var isRunning: Bool { _stub() }
    open var attachedNodes: Set<AVAudioNode> { _stub() }
    open var mainMixerNode: AVAudioMixerNode { _stub() }
    open var outputNode: AVAudioOutputNode { _stub() }
}

extension NSNotification.Name {
    /// `AVAudioEngineConfigurationChangeNotification`
    public static let AVAudioEngineConfigurationChange = NSNotification.Name("AVAudioEngineConfigurationChangeNotification")
}

// MARK: - AVAudioSession (iOS)

open class AVAudioSession: NSObject {
    open class func sharedInstance() -> AVAudioSession { _stub() }

    public struct Category: Hashable, Equatable, RawRepresentable, @unchecked Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let ambient = Category(rawValue: "AVAudioSessionCategoryAmbient")
        public static let soloAmbient = Category(rawValue: "AVAudioSessionCategorySoloAmbient")
        public static let playback = Category(rawValue: "AVAudioSessionCategoryPlayback")
        public static let record = Category(rawValue: "AVAudioSessionCategoryRecord")
        public static let playAndRecord = Category(rawValue: "AVAudioSessionCategoryPlayAndRecord")
        public static let multiRoute = Category(rawValue: "AVAudioSessionCategoryMultiRoute")
    }

    public struct Mode: Hashable, Equatable, RawRepresentable, @unchecked Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let `default` = Mode(rawValue: "AVAudioSessionModeDefault")
        public static let gameChat = Mode(rawValue: "AVAudioSessionModeGameChat")
        public static let moviePlayback = Mode(rawValue: "AVAudioSessionModeMoviePlayback")
        public static let spokenAudio = Mode(rawValue: "AVAudioSessionModeSpokenAudio")
    }

    public struct CategoryOptions: OptionSet, @unchecked Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static var mixWithOthers: CategoryOptions { CategoryOptions(rawValue: 0x1) }
        public static var duckOthers: CategoryOptions { CategoryOptions(rawValue: 0x2) }
        public static var allowBluetooth: CategoryOptions { CategoryOptions(rawValue: 0x4) }
        public static var defaultToSpeaker: CategoryOptions { CategoryOptions(rawValue: 0x8) }
        public static var interruptSpokenAudioAndMixWithOthers: CategoryOptions { CategoryOptions(rawValue: 0x11) }
        public static var allowBluetoothA2DP: CategoryOptions { CategoryOptions(rawValue: 0x20) }
        public static var allowAirPlay: CategoryOptions { CategoryOptions(rawValue: 0x40) }
    }

    public struct SetActiveOptions: OptionSet, @unchecked Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static var notifyOthersOnDeactivation: SetActiveOptions { SetActiveOptions(rawValue: 1) }
    }

    public enum InterruptionType: UInt, @unchecked Sendable {
        case began = 1
        case ended = 0
    }

    public struct InterruptionOptions: OptionSet, @unchecked Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static var shouldResume: InterruptionOptions { InterruptionOptions(rawValue: 1) }
    }

    open func setCategory(_ category: AVAudioSession.Category) throws { _stub() }
    open func setCategory(_ category: AVAudioSession.Category, options: AVAudioSession.CategoryOptions = []) throws { _stub() }
    open func setCategory(_ category: AVAudioSession.Category, mode: AVAudioSession.Mode,
                          options: AVAudioSession.CategoryOptions = []) throws { _stub() }
    open func setActive(_ active: Bool, options: AVAudioSession.SetActiveOptions = []) throws { _stub() }
    open var category: AVAudioSession.Category { _stub() }
    open var mode: AVAudioSession.Mode { _stub() }
    open var categoryOptions: AVAudioSession.CategoryOptions { _stub() }
    open var isOtherAudioPlaying: Bool { _stub() }
    open var secondaryAudioShouldBeSilencedHint: Bool { _stub() }
    open var outputVolume: Float { _stub() }
    open var sampleRate: Double { _stub() }

    public static let interruptionNotification = NSNotification.Name("AVAudioSessionInterruptionNotification")
    public static let routeChangeNotification = NSNotification.Name("AVAudioSessionRouteChangeNotification")
    public static let mediaServicesWereResetNotification = NSNotification.Name("AVAudioSessionMediaServicesWereResetNotification")
    public static let silenceSecondaryAudioHintNotification = NSNotification.Name("AVAudioSessionSilenceSecondaryAudioHintNotification")
}

public let AVAudioSessionInterruptionTypeKey: String = "AVAudioSessionInterruptionTypeKey"
public let AVAudioSessionInterruptionOptionKey: String = "AVAudioSessionInterruptionOptionKey"
public let AVAudioSessionInterruptionWasSuspendedKey: String = "AVAudioSessionInterruptionWasSuspendedKey"
