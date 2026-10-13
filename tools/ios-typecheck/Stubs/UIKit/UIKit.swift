// API stub of Apple's UIKit (subset) for the Linux typecheck harness. Signatures mirror the iOS 17/18 SDK.
// Main-actor classes are `@MainActor @preconcurrency`, which is how the SDK's NS_SWIFT_UI_ACTOR imports behave
// for Swift 5 mode clients.
@_exported import Foundation
@_exported import CoreGraphics

@inline(never) func _stub() -> Never { fatalError("UIKit stub: typecheck only") }

// MARK: - Geometry helpers

public struct UIEdgeInsets: Equatable, Hashable, Sendable {
    public var top: CGFloat, left: CGFloat, bottom: CGFloat, right: CGFloat
    public init() { top = 0; left = 0; bottom = 0; right = 0 }
    public init(top: CGFloat, left: CGFloat, bottom: CGFloat, right: CGFloat) {
        self.top = top; self.left = left; self.bottom = bottom; self.right = right
    }
    public static var zero: UIEdgeInsets { UIEdgeInsets() }
}

public enum UIUserInterfaceIdiom: Int, Sendable {
    case unspecified = -1, phone = 0, pad, tv, carPlay, mac = 5, vision = 6
}

public enum UIUserInterfaceStyle: Int, Sendable { case unspecified = 0, light, dark }

// MARK: - UIColor

open class UIColor: NSObject, @unchecked Sendable {
    public init(white: CGFloat, alpha: CGFloat) { _stub() }
    public init(hue: CGFloat, saturation: CGFloat, brightness: CGFloat, alpha: CGFloat) { _stub() }
    public init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) { _stub() }
    public init(displayP3Red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) { _stub() }
    public init(cgColor: CGColor) { _stub() }
    public init(dynamicProvider: @escaping @Sendable (UITraitCollection) -> UIColor) { _stub() }
    public convenience init?(named name: String) { _stub() }

    open class var black: UIColor { _stub() }
    open class var darkGray: UIColor { _stub() }
    open class var lightGray: UIColor { _stub() }
    open class var white: UIColor { _stub() }
    open class var gray: UIColor { _stub() }
    open class var red: UIColor { _stub() }
    open class var green: UIColor { _stub() }
    open class var blue: UIColor { _stub() }
    open class var cyan: UIColor { _stub() }
    open class var yellow: UIColor { _stub() }
    open class var magenta: UIColor { _stub() }
    open class var orange: UIColor { _stub() }
    open class var purple: UIColor { _stub() }
    open class var brown: UIColor { _stub() }
    open class var clear: UIColor { _stub() }
    open class var systemRed: UIColor { _stub() }
    open class var systemGreen: UIColor { _stub() }
    open class var systemBlue: UIColor { _stub() }
    open class var systemOrange: UIColor { _stub() }
    open class var systemYellow: UIColor { _stub() }
    open class var systemPink: UIColor { _stub() }
    open class var systemPurple: UIColor { _stub() }
    open class var systemTeal: UIColor { _stub() }
    open class var systemIndigo: UIColor { _stub() }
    open class var systemBrown: UIColor { _stub() }
    open class var systemMint: UIColor { _stub() }
    open class var systemCyan: UIColor { _stub() }
    open class var systemGray: UIColor { _stub() }
    open class var systemGray2: UIColor { _stub() }
    open class var systemGray3: UIColor { _stub() }
    open class var systemGray4: UIColor { _stub() }
    open class var systemGray5: UIColor { _stub() }
    open class var systemGray6: UIColor { _stub() }
    open class var label: UIColor { _stub() }
    open class var secondaryLabel: UIColor { _stub() }
    open class var systemBackground: UIColor { _stub() }
    open class var secondarySystemBackground: UIColor { _stub() }
    open class var tintColor: UIColor { _stub() }

    open func withAlphaComponent(_ alpha: CGFloat) -> UIColor { _stub() }
    open var cgColor: CGColor { _stub() }
    open func getRed(_ red: UnsafeMutablePointer<CGFloat>?, green: UnsafeMutablePointer<CGFloat>?,
                     blue: UnsafeMutablePointer<CGFloat>?, alpha: UnsafeMutablePointer<CGFloat>?) -> Bool { _stub() }
    open func getWhite(_ white: UnsafeMutablePointer<CGFloat>?, alpha: UnsafeMutablePointer<CGFloat>?) -> Bool { _stub() }
    open func getHue(_ hue: UnsafeMutablePointer<CGFloat>?, saturation: UnsafeMutablePointer<CGFloat>?,
                     brightness: UnsafeMutablePointer<CGFloat>?, alpha: UnsafeMutablePointer<CGFloat>?) -> Bool { _stub() }
    open func resolvedColor(with traitCollection: UITraitCollection) -> UIColor { _stub() }
    open func set() { _stub() }
    open func setFill() { _stub() }
    open func setStroke() { _stub() }
}

open class UITraitCollection: NSObject, @unchecked Sendable {
    open var userInterfaceStyle: UIUserInterfaceStyle { _stub() }
    open var userInterfaceIdiom: UIUserInterfaceIdiom { _stub() }
    open var displayScale: CGFloat { _stub() }
    open class var current: UITraitCollection { _stub() }
}

// MARK: - UIFont

open class UIFont: NSObject, @unchecked Sendable {
    public struct Weight: Hashable, Sendable, RawRepresentable {
        public let rawValue: CGFloat
        public init(rawValue: CGFloat) { self.rawValue = rawValue }
        public init(_ rawValue: CGFloat) { self.rawValue = rawValue }
        public static let ultraLight = Weight(-0.8), thin = Weight(-0.6), light = Weight(-0.4),
                          regular = Weight(0), medium = Weight(0.23), semibold = Weight(0.3), bold = Weight(0.4),
                          heavy = Weight(0.56), black = Weight(0.62)
    }
    public init?(name fontName: String, size fontSize: CGFloat) { _stub() }
    open class func systemFont(ofSize fontSize: CGFloat) -> UIFont { _stub() }
    open class func systemFont(ofSize fontSize: CGFloat, weight: UIFont.Weight) -> UIFont { _stub() }
    open class func boldSystemFont(ofSize fontSize: CGFloat) -> UIFont { _stub() }
    open class func monospacedDigitSystemFont(ofSize fontSize: CGFloat, weight: UIFont.Weight) -> UIFont { _stub() }
    open class func monospacedSystemFont(ofSize fontSize: CGFloat, weight: UIFont.Weight) -> UIFont { _stub() }
    open var fontName: String { _stub() }
    open var familyName: String { _stub() }
    open var pointSize: CGFloat { _stub() }
    open var lineHeight: CGFloat { _stub() }
}

// MARK: - UIImage

open class UIImage: NSObject, @unchecked Sendable {
    public enum RenderingMode: Int, Sendable { case automatic = 0, alwaysOriginal, alwaysTemplate }
    public enum Orientation: Int, Sendable {
        case up = 0, down, left, right, upMirrored, downMirrored, leftMirrored, rightMirrored
    }

    public override init() { _stub() }
    public init?(named name: String) { _stub() }
    public init?(named name: String, in bundle: Bundle?, compatibleWith traitCollection: UITraitCollection?) { _stub() }
    public init?(systemName name: String) { _stub() }
    public init?(contentsOfFile path: String) { _stub() }
    public init?(data: Data) { _stub() }
    public init?(data: Data, scale: CGFloat) { _stub() }
    public init(cgImage: CGImage) { _stub() }
    public init(cgImage: CGImage, scale: CGFloat, orientation: UIImage.Orientation) { _stub() }

    open var size: CGSize { _stub() }
    open var scale: CGFloat { _stub() }
    open var cgImage: CGImage? { _stub() }
    open var imageOrientation: UIImage.Orientation { _stub() }
    open var renderingMode: UIImage.RenderingMode { _stub() }
    open func withRenderingMode(_ renderingMode: UIImage.RenderingMode) -> UIImage { _stub() }
    open func withTintColor(_ color: UIColor) -> UIImage { _stub() }
    open func draw(in rect: CGRect) { _stub() }
    open func draw(at point: CGPoint) { _stub() }
    public func pngData() -> Data? { _stub() }
    public func jpegData(compressionQuality: CGFloat) -> Data? { _stub() }
}

// MARK: - Responder / view / touches

@MainActor @preconcurrency
open class UIResponder: NSObject {
    public override init() { _stub() }
    open var next: UIResponder? { _stub() }
    open var canBecomeFirstResponder: Bool { _stub() }
    open func becomeFirstResponder() -> Bool { _stub() }
    open func resignFirstResponder() -> Bool { _stub() }
    open func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) { _stub() }
    open func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) { _stub() }
    open func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { _stub() }
    open func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { _stub() }
}

@MainActor @preconcurrency
open class UITouch: NSObject {
    public enum Phase: Int, Sendable { case began = 0, moved, stationary, ended, cancelled, regionEntered, regionMoved, regionExited }
    open var timestamp: TimeInterval { _stub() }
    open var phase: UITouch.Phase { _stub() }
    open var tapCount: Int { _stub() }
    open var view: UIView? { _stub() }
    open func location(in view: UIView?) -> CGPoint { _stub() }
    open func previousLocation(in view: UIView?) -> CGPoint { _stub() }
}

@MainActor @preconcurrency
open class UIEvent: NSObject {
    open var timestamp: TimeInterval { _stub() }
    open var allTouches: Set<UITouch>? { _stub() }
}

@MainActor @preconcurrency
open class UIView: UIResponder {
    public init(frame: CGRect) { _stub() }
    public required init?(coder: NSCoder) { _stub() }
    public convenience override init() { _stub() }
    open var frame: CGRect { get { _stub() } set { _stub() } }
    open var bounds: CGRect { get { _stub() } set { _stub() } }
    open var center: CGPoint { get { _stub() } set { _stub() } }
    open var backgroundColor: UIColor? { get { _stub() } set { _stub() } }
    open var alpha: CGFloat { get { _stub() } set { _stub() } }
    open var isHidden: Bool { get { _stub() } set { _stub() } }
    open var isOpaque: Bool { get { _stub() } set { _stub() } }
    open var isUserInteractionEnabled: Bool { get { _stub() } set { _stub() } }
    open var isMultipleTouchEnabled: Bool { get { _stub() } set { _stub() } }
    open var contentScaleFactor: CGFloat { get { _stub() } set { _stub() } }
    open var safeAreaInsets: UIEdgeInsets { _stub() }
    open var traitCollection: UITraitCollection { _stub() }
    open var superview: UIView? { _stub() }
    open var subviews: [UIView] { _stub() }
    open var window: UIWindow? { _stub() }
    open func addSubview(_ view: UIView) { _stub() }
    open func removeFromSuperview() { _stub() }
    open func setNeedsLayout() { _stub() }
    open func layoutSubviews() { _stub() }
    open func setNeedsDisplay() { _stub() }
}

@MainActor @preconcurrency
open class UIWindow: UIView {
    open var screen: UIScreen { _stub() }
}

// MARK: - Haptics

@MainActor @preconcurrency
open class UIFeedbackGenerator: NSObject {
    public override init() { _stub() }
    open func prepare() { _stub() }
}

@MainActor @preconcurrency
open class UIImpactFeedbackGenerator: UIFeedbackGenerator {
    public enum FeedbackStyle: Int, Sendable { case light = 0, medium, heavy, soft, rigid }
    public init(style: UIImpactFeedbackGenerator.FeedbackStyle) { _stub() }
    public override init() { _stub() }
    open func impactOccurred() { _stub() }
    open func impactOccurred(intensity: CGFloat) { _stub() }
}

@MainActor @preconcurrency
open class UISelectionFeedbackGenerator: UIFeedbackGenerator {
    open func selectionChanged() { _stub() }
}

@MainActor @preconcurrency
open class UINotificationFeedbackGenerator: UIFeedbackGenerator {
    public enum FeedbackType: Int, Sendable { case success = 0, warning, error }
    open func notificationOccurred(_ notificationType: UINotificationFeedbackGenerator.FeedbackType) { _stub() }
}

// MARK: - Application / device / screen

public struct UIBackgroundTaskIdentifier: RawRepresentable, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let invalid = UIBackgroundTaskIdentifier(rawValue: 0)
}

@MainActor @preconcurrency
open class UIApplication: UIResponder {
    public enum State: Int, Sendable { case active = 0, inactive, background }

    open class var shared: UIApplication { _stub() }
    open var applicationState: UIApplication.State { _stub() }
    open var isIdleTimerDisabled: Bool { get { _stub() } set { _stub() } }
    open var backgroundTimeRemaining: TimeInterval { _stub() }
    open var connectedScenes: Set<NSObject> { _stub() }

    open func beginBackgroundTask(expirationHandler handler: (@MainActor @Sendable () -> Void)? = nil)
        -> UIBackgroundTaskIdentifier { _stub() }
    open func beginBackgroundTask(withName taskName: String?,
                                  expirationHandler handler: (@MainActor @Sendable () -> Void)? = nil)
        -> UIBackgroundTaskIdentifier { _stub() }
    open func endBackgroundTask(_ identifier: UIBackgroundTaskIdentifier) { _stub() }
    open func open(_ url: URL, options: [UIApplication.OpenExternalURLOptionsKey: Any] = [:],
                   completionHandler completion: (@MainActor @Sendable (Bool) -> Void)? = nil) { _stub() }
    open func canOpenURL(_ url: URL) -> Bool { _stub() }

    public struct OpenExternalURLOptionsKey: Hashable, RawRepresentable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
    }

    public nonisolated static let didEnterBackgroundNotification = NSNotification.Name("UIApplicationDidEnterBackgroundNotification")
    public nonisolated static let willEnterForegroundNotification = NSNotification.Name("UIApplicationWillEnterForegroundNotification")
    public nonisolated static let didFinishLaunchingNotification = NSNotification.Name("UIApplicationDidFinishLaunchingNotification")
    public nonisolated static let didBecomeActiveNotification = NSNotification.Name("UIApplicationDidBecomeActiveNotification")
    public nonisolated static let willResignActiveNotification = NSNotification.Name("UIApplicationWillResignActiveNotification")
    public nonisolated static let didReceiveMemoryWarningNotification = NSNotification.Name("UIApplicationDidReceiveMemoryWarningNotification")
    public nonisolated static let willTerminateNotification = NSNotification.Name("UIApplicationWillTerminateNotification")
}

@MainActor @preconcurrency
open class UIDevice: NSObject {
    open class var current: UIDevice { _stub() }
    open var name: String { _stub() }
    open var model: String { _stub() }
    open var systemName: String { _stub() }
    open var systemVersion: String { _stub() }
    open var userInterfaceIdiom: UIUserInterfaceIdiom { _stub() }
    open var identifierForVendor: UUID? { _stub() }
}

@MainActor @preconcurrency
open class UIScreen: NSObject {
    @available(*, deprecated, message: "(iOS 16) Use a UIScreen instance found through context instead: i.e, view.window.windowScene.screen")
    open class var main: UIScreen { _stub() }
    open var bounds: CGRect { _stub() }
    open var nativeBounds: CGRect { _stub() }
    open var scale: CGFloat { _stub() }
    open var nativeScale: CGFloat { _stub() }
    open var maximumFramesPerSecond: Int { _stub() }
    open var traitCollection: UITraitCollection { _stub() }
}

// MARK: - Image rendering

open class UIGraphicsRendererFormat: NSObject, @unchecked Sendable {
    public override init() { _stub() }
}

open class UIGraphicsImageRendererFormat: UIGraphicsRendererFormat, @unchecked Sendable {
    public enum Range: Int, Sendable { case unspecified = -1, automatic = 0, extended, standard }
    open var scale: CGFloat { get { _stub() } set { _stub() } }
    open var opaque: Bool { get { _stub() } set { _stub() } }
    open var preferredRange: UIGraphicsImageRendererFormat.Range { get { _stub() } set { _stub() } }
    open class func `default`() -> UIGraphicsImageRendererFormat { _stub() }
    open class func preferred() -> UIGraphicsImageRendererFormat { _stub() }
}

open class UIGraphicsRendererContext: NSObject {
    open var cgContext: CGContext { _stub() }
    open func fill(_ rect: CGRect) { _stub() }
    open func fill(_ rect: CGRect, blendMode: CGBlendMode) { _stub() }
    open func stroke(_ rect: CGRect) { _stub() }
    open func stroke(_ rect: CGRect, blendMode: CGBlendMode) { _stub() }
    open func clip(to rect: CGRect) { _stub() }
}

open class UIGraphicsImageRendererContext: UIGraphicsRendererContext {
    open var currentImage: UIImage { _stub() }
    open var format: UIGraphicsImageRendererFormat { _stub() }
}

open class UIGraphicsRenderer: NSObject {
    public init(bounds: CGRect) { _stub() }
}

open class UIGraphicsImageRenderer: UIGraphicsRenderer {
    public typealias DrawingActions = (UIGraphicsImageRendererContext) -> Void
    public convenience init(size: CGSize) { _stub() }
    public init(size: CGSize, format: UIGraphicsImageRendererFormat) { _stub() }
    public init(bounds: CGRect, format: UIGraphicsImageRendererFormat) { _stub() }
    public override convenience init(bounds: CGRect) { _stub() }
    open func image(actions: (UIGraphicsImageRendererContext) -> Void) -> UIImage { _stub() }
    open func pngData(actions: (UIGraphicsImageRendererContext) -> Void) -> Data { _stub() }
    open func jpegData(withCompressionQuality compressionQuality: CGFloat,
                       actions: (UIGraphicsImageRendererContext) -> Void) -> Data { _stub() }
}
