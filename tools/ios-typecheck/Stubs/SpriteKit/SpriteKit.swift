// API stub of Apple's SpriteKit (subset) for the Linux typecheck harness. Signatures mirror the iOS 17/18 SDK.
// On iOS SKNode inherits from UIResponder, so every node class is main-actor isolated (preconcurrency).
// Designated vs. convenience initializers follow the SDK exactly: subclasses of SKSpriteNode must call
// super.init(texture:color:size:); a subclass that adds a designated init must implement init?(coder:).
@_exported import Foundation
@_exported import CoreGraphics
@_exported import UIKit
import SwiftUI

@inline(never) func _stub() -> Never { fatalError("SpriteKit stub: typecheck only") }

public typealias SKColor = UIColor

// MARK: - Enums

public enum SKBlendMode: Int, Sendable { case alpha = 0, add, subtract, multiply, multiplyX2, screen, replace, multiplyAlpha }
public enum SKSceneScaleMode: Int, Sendable { case fill = 0, aspectFill, aspectFit, resizeFill }
public enum SKTextureFilteringMode: Int, Sendable { case nearest = 0, linear }
public enum SKLabelHorizontalAlignmentMode: Int, Sendable { case center = 0, left, right }
public enum SKLabelVerticalAlignmentMode: Int, Sendable { case baseline = 0, center, top, bottom }
public enum SKActionTimingMode: Int, Sendable { case linear = 0, easeIn, easeOut, easeInEaseOut }
public enum SKTransitionDirection: Int, Sendable { case up = 0, down, right, left }

// MARK: - SKNode

@MainActor @preconcurrency
open class SKNode: UIResponder {
    public override init() { _stub() }
    public required init?(coder aDecoder: NSCoder) { _stub() }
    public convenience init?(fileNamed filename: String) { _stub() }

    open var frame: CGRect { _stub() }
    open func calculateAccumulatedFrame() -> CGRect { _stub() }

    open var position: CGPoint { get { _stub() } set { _stub() } }
    open var zPosition: CGFloat { get { _stub() } set { _stub() } }
    open var zRotation: CGFloat { get { _stub() } set { _stub() } }
    open var xScale: CGFloat { get { _stub() } set { _stub() } }
    open var yScale: CGFloat { get { _stub() } set { _stub() } }
    open func setScale(_ scale: CGFloat) { _stub() }
    open var speed: CGFloat { get { _stub() } set { _stub() } }
    open var alpha: CGFloat { get { _stub() } set { _stub() } }
    open var isPaused: Bool { get { _stub() } set { _stub() } }
    open var isHidden: Bool { get { _stub() } set { _stub() } }
    open var isUserInteractionEnabled: Bool { get { _stub() } set { _stub() } }
    open var name: String? { get { _stub() } set { _stub() } }
    open var userData: NSMutableDictionary? { get { _stub() } set { _stub() } }

    open var parent: SKNode? { _stub() }
    open var children: [SKNode] { _stub() }
    open var scene: SKScene? { _stub() }
    open func inParentHierarchy(_ parent: SKNode) -> Bool { _stub() }

    open func addChild(_ node: SKNode) { _stub() }
    open func insertChild(_ node: SKNode, at index: Int) { _stub() }
    open func removeChildren(in nodes: [SKNode]) { _stub() }
    open func removeAllChildren() { _stub() }
    open func removeFromParent() { _stub() }
    open func move(toParent parent: SKNode) { _stub() }
    open func childNode(withName name: String) -> SKNode? { _stub() }
    open func enumerateChildNodes(withName name: String,
                                  using block: (SKNode, UnsafeMutablePointer<ObjCBool>) -> Void) { _stub() }
    open subscript(name: String) -> [SKNode] { _stub() }

    open func run(_ action: SKAction) { _stub() }
    open func run(_ action: SKAction, completion block: @escaping @MainActor @Sendable () -> Void) { _stub() }
    open func run(_ action: SKAction, withKey key: String) { _stub() }
    open func run(_ action: SKAction) async { _stub() }
    open func hasActions() -> Bool { _stub() }
    open func action(forKey key: String) -> SKAction? { _stub() }
    open func removeAction(forKey key: String) { _stub() }
    open func removeAllActions() { _stub() }

    open func contains(_ p: CGPoint) -> Bool { _stub() }
    open func atPoint(_ p: CGPoint) -> SKNode { _stub() }
    open func nodes(at p: CGPoint) -> [SKNode] { _stub() }
    open func convert(_ point: CGPoint, from node: SKNode) -> CGPoint { _stub() }
    open func convert(_ point: CGPoint, to node: SKNode) -> CGPoint { _stub() }
    open func intersects(_ node: SKNode) -> Bool { _stub() }
    open func isEqual(to node: SKNode) -> Bool { _stub() }
}

extension UITouch {
    public func location(in node: SKNode) -> CGPoint { _stub() }
    public func previousLocation(in node: SKNode) -> CGPoint { _stub() }
}

// MARK: - Scene / view / camera

@MainActor @preconcurrency
public protocol SKSceneDelegate: NSObjectProtocol {
    func update(_ currentTime: TimeInterval, for scene: SKScene)
    func didEvaluateActions(for scene: SKScene)
    func didFinishUpdate(for scene: SKScene)
}

@MainActor @preconcurrency
open class SKEffectNode: SKNode {
    open var shouldRasterize: Bool { get { _stub() } set { _stub() } }
    open var shouldEnableEffects: Bool { get { _stub() } set { _stub() } }
    open var blendMode: SKBlendMode { get { _stub() } set { _stub() } }
}

@MainActor @preconcurrency
open class SKScene: SKEffectNode {
    public init(size: CGSize) { _stub() }
    public override init() { _stub() }
    public required init?(coder aDecoder: NSCoder) { _stub() }

    open func sceneDidLoad() { _stub() }
    open func didMove(to view: SKView) { _stub() }
    open func willMove(from view: SKView) { _stub() }
    open func didChangeSize(_ oldSize: CGSize) { _stub() }
    open func update(_ currentTime: TimeInterval) { _stub() }
    open func didEvaluateActions() { _stub() }
    open func didSimulatePhysics() { _stub() }
    open func didApplyConstraints() { _stub() }
    open func didFinishUpdate() { _stub() }

    open var size: CGSize { get { _stub() } set { _stub() } }
    open var scaleMode: SKSceneScaleMode { get { _stub() } set { _stub() } }
    weak open var camera: SKCameraNode? { get { _stub() } set { _stub() } }
    open var backgroundColor: UIColor { get { _stub() } set { _stub() } }
    open var anchorPoint: CGPoint { get { _stub() } set { _stub() } }
    weak open var delegate: SKSceneDelegate? { get { _stub() } set { _stub() } }
    weak open var view: SKView? { _stub() }

    open func convertPoint(fromView point: CGPoint) -> CGPoint { _stub() }
    open func convertPoint(toView point: CGPoint) -> CGPoint { _stub() }
}

@MainActor @preconcurrency
open class SKCameraNode: SKNode {
    open func contains(_ node: SKNode) -> Bool { _stub() }
    open func containedNodeSet() -> Set<SKNode> { _stub() }
}

@MainActor @preconcurrency
open class SKView: UIView {
    open var isPaused: Bool { get { _stub() } set { _stub() } }
    open var showsFPS: Bool { get { _stub() } set { _stub() } }
    open var showsDrawCount: Bool { get { _stub() } set { _stub() } }
    open var showsNodeCount: Bool { get { _stub() } set { _stub() } }
    open var showsQuadCount: Bool { get { _stub() } set { _stub() } }
    open var showsPhysics: Bool { get { _stub() } set { _stub() } }
    open var isAsynchronous: Bool { get { _stub() } set { _stub() } }
    open var allowsTransparency: Bool { get { _stub() } set { _stub() } }
    open var ignoresSiblingOrder: Bool { get { _stub() } set { _stub() } }
    open var shouldCullNonVisibleNodes: Bool { get { _stub() } set { _stub() } }
    open var preferredFramesPerSecond: Int { get { _stub() } set { _stub() } }
    open var scene: SKScene? { _stub() }

    open func presentScene(_ scene: SKScene?) { _stub() }
    open func presentScene(_ scene: SKScene, transition: SKTransition) { _stub() }
    open func texture(from node: SKNode) -> SKTexture? { _stub() }
    open func texture(from node: SKNode, crop: CGRect) -> SKTexture? { _stub() }
    open func convert(_ point: CGPoint, to scene: SKScene) -> CGPoint { _stub() }
    open func convert(_ point: CGPoint, from scene: SKScene) -> CGPoint { _stub() }
}

open class SKTransition: NSObject {
    open class func crossFade(withDuration sec: TimeInterval) -> SKTransition { _stub() }
    open class func fade(withDuration sec: TimeInterval) -> SKTransition { _stub() }
    open class func fade(with color: UIColor, duration sec: TimeInterval) -> SKTransition { _stub() }
    open class func push(with direction: SKTransitionDirection, duration sec: TimeInterval) -> SKTransition { _stub() }
    open var pausesIncomingScene: Bool { get { _stub() } set { _stub() } }
    open var pausesOutgoingScene: Bool { get { _stub() } set { _stub() } }
}

// MARK: - Drawing nodes

@MainActor @preconcurrency
open class SKSpriteNode: SKNode {
    public init(texture: SKTexture?, color: UIColor, size: CGSize) { _stub() }
    public convenience init(texture: SKTexture?) { _stub() }
    public convenience init(texture: SKTexture?, size: CGSize) { _stub() }
    public convenience init(color: UIColor, size: CGSize) { _stub() }
    public convenience init(imageNamed name: String) { _stub() }
    public convenience init(imageNamed name: String, normalMapped generateNormalMap: Bool) { _stub() }
    public override init() { _stub() }
    public required init?(coder aDecoder: NSCoder) { _stub() }

    open var texture: SKTexture? { get { _stub() } set { _stub() } }
    open var size: CGSize { get { _stub() } set { _stub() } }
    open func scale(to size: CGSize) { _stub() }
    open var anchorPoint: CGPoint { get { _stub() } set { _stub() } }
    open var centerRect: CGRect { get { _stub() } set { _stub() } }
    open var color: UIColor { get { _stub() } set { _stub() } }
    open var colorBlendFactor: CGFloat { get { _stub() } set { _stub() } }
    open var blendMode: SKBlendMode { get { _stub() } set { _stub() } }
}

@MainActor @preconcurrency
open class SKShapeNode: SKNode {
    public convenience init(path: CGPath) { _stub() }
    public convenience init(path: CGPath, centered: Bool) { _stub() }
    public convenience init(rect: CGRect) { _stub() }
    public convenience init(rectOf size: CGSize) { _stub() }
    public convenience init(rect: CGRect, cornerRadius: CGFloat) { _stub() }
    public convenience init(rectOf size: CGSize, cornerRadius: CGFloat) { _stub() }
    public convenience init(circleOfRadius radius: CGFloat) { _stub() }
    public convenience init(ellipseIn rect: CGRect) { _stub() }
    public convenience init(ellipseOf size: CGSize) { _stub() }
    public convenience init(points: UnsafeMutablePointer<CGPoint>, count numPoints: Int) { _stub() }
    public override init() { _stub() }
    public required init?(coder aDecoder: NSCoder) { _stub() }

    open var path: CGPath? { get { _stub() } set { _stub() } }
    open var strokeColor: UIColor { get { _stub() } set { _stub() } }
    open var fillColor: UIColor { get { _stub() } set { _stub() } }
    open var blendMode: SKBlendMode { get { _stub() } set { _stub() } }
    open var isAntialiased: Bool { get { _stub() } set { _stub() } }
    open var lineWidth: CGFloat { get { _stub() } set { _stub() } }
    open var glowWidth: CGFloat { get { _stub() } set { _stub() } }
    open var lineCap: CGLineCap { get { _stub() } set { _stub() } }
    open var lineJoin: CGLineJoin { get { _stub() } set { _stub() } }
    open var fillTexture: SKTexture? { get { _stub() } set { _stub() } }
    open var strokeTexture: SKTexture? { get { _stub() } set { _stub() } }
    open var lineLength: CGFloat { _stub() }
}

@MainActor @preconcurrency
open class SKLabelNode: SKNode {
    public convenience init(text: String?) { _stub() }
    public convenience init(attributedText: NSAttributedString?) { _stub() }
    public convenience init(fontNamed fontName: String?) { _stub() }
    public override init() { _stub() }
    public required init?(coder aDecoder: NSCoder) { _stub() }

    open var text: String? { get { _stub() } set { _stub() } }
    open var attributedText: NSAttributedString? { get { _stub() } set { _stub() } }
    open var fontName: String? { get { _stub() } set { _stub() } }
    open var fontSize: CGFloat { get { _stub() } set { _stub() } }
    open var fontColor: UIColor? { get { _stub() } set { _stub() } }
    open var color: UIColor? { get { _stub() } set { _stub() } }
    open var colorBlendFactor: CGFloat { get { _stub() } set { _stub() } }
    open var blendMode: SKBlendMode { get { _stub() } set { _stub() } }
    open var horizontalAlignmentMode: SKLabelHorizontalAlignmentMode { get { _stub() } set { _stub() } }
    open var verticalAlignmentMode: SKLabelVerticalAlignmentMode { get { _stub() } set { _stub() } }
    open var numberOfLines: Int { get { _stub() } set { _stub() } }
    open var preferredMaxLayoutWidth: CGFloat { get { _stub() } set { _stub() } }
    open var lineBreakMode: NSLineBreakMode { get { _stub() } set { _stub() } }
}

public enum NSLineBreakMode: Int, Sendable {
    case byWordWrapping = 0, byCharWrapping, byClipping, byTruncatingHead, byTruncatingTail, byTruncatingMiddle
}

@MainActor @preconcurrency
open class SKCropNode: SKNode {
    open var maskNode: SKNode? { get { _stub() } set { _stub() } }
}

// MARK: - Textures

open class SKTexture: NSObject, @unchecked Sendable {
    public override init() { _stub() }
    public required init?(coder aDecoder: NSCoder) { _stub() }
    public convenience init(imageNamed name: String) { _stub() }
    public convenience init(rect: CGRect, in texture: SKTexture) { _stub() }
    public convenience init(cgImage image: CGImage) { _stub() }
    public convenience init(image: UIImage) { _stub() }
    public convenience init(data pixelData: Data, size: CGSize) { _stub() }
    public convenience init(data pixelData: Data, size: CGSize, flipped: Bool) { _stub() }
    public convenience init(data pixelData: Data, size: CGSize, rowLength: UInt32, alignment: UInt32) { _stub() }

    open func textureRect() -> CGRect { _stub() }
    open func size() -> CGSize { _stub() }
    open var filteringMode: SKTextureFilteringMode { get { _stub() } set { _stub() } }
    open var usesMipmaps: Bool { get { _stub() } set { _stub() } }
    open func cgImage() -> CGImage { _stub() }
    open func preload(completionHandler: @escaping @Sendable () -> Void) { _stub() }
    open func preload() async { _stub() }
    open class func preload(_ textures: [SKTexture], withCompletionHandler completionHandler: @escaping @Sendable () -> Void) { _stub() }
    open class func preload(_ textures: [SKTexture]) async { _stub() }
}

open class SKTextureAtlas: NSObject, @unchecked Sendable {
    public convenience init(named name: String) { _stub() }
    public convenience init(dictionary properties: [String: Any]) { _stub() }
    public override init() { _stub() }
    public required init?(coder aDecoder: NSCoder) { _stub() }

    open func textureNamed(_ name: String) -> SKTexture { _stub() }
    open var textureNames: [String] { _stub() }
    open func preload(completionHandler: @escaping @Sendable () -> Void) { _stub() }
    open func preload() async { _stub() }
    open class func preloadTextureAtlases(_ textureAtlases: [SKTextureAtlas],
                                          withCompletionHandler completionHandler: @escaping @Sendable () -> Void) { _stub() }
    open class func preloadTextureAtlases(_ textureAtlases: [SKTextureAtlas]) async { _stub() }
    open class func preloadTextureAtlasesNamed(_ atlasNames: [String],
                                               withCompletionHandler completionHandler: @escaping @Sendable (Error?, [SKTextureAtlas]) -> Void) { _stub() }
}

// MARK: - Actions

open class SKAction: NSObject, @unchecked Sendable {
    public override init() { _stub() }
    public required init?(coder aDecoder: NSCoder) { _stub() }

    open var duration: TimeInterval { get { _stub() } set { _stub() } }
    open var timingMode: SKActionTimingMode { get { _stub() } set { _stub() } }
    open var timingFunction: (Float) -> Float { get { _stub() } set { _stub() } }
    open var speed: CGFloat { get { _stub() } set { _stub() } }
    open func reversed() -> SKAction { _stub() }

    open class func move(by delta: CGVector, duration: TimeInterval) -> SKAction { _stub() }
    open class func moveBy(x deltaX: CGFloat, y deltaY: CGFloat, duration: TimeInterval) -> SKAction { _stub() }
    open class func move(to location: CGPoint, duration: TimeInterval) -> SKAction { _stub() }
    open class func moveTo(x: CGFloat, duration: TimeInterval) -> SKAction { _stub() }
    open class func moveTo(y: CGFloat, duration: TimeInterval) -> SKAction { _stub() }
    open class func rotate(byAngle radians: CGFloat, duration: TimeInterval) -> SKAction { _stub() }
    open class func rotate(toAngle radians: CGFloat, duration: TimeInterval) -> SKAction { _stub() }
    open class func rotate(toAngle radians: CGFloat, duration: TimeInterval, shortestUnitArc: Bool) -> SKAction { _stub() }
    open class func scale(by scale: CGFloat, duration: TimeInterval) -> SKAction { _stub() }
    open class func scale(to scale: CGFloat, duration: TimeInterval) -> SKAction { _stub() }
    open class func scale(to size: CGSize, duration: TimeInterval) -> SKAction { _stub() }
    open class func scaleX(to xScale: CGFloat, y yScale: CGFloat, duration: TimeInterval) -> SKAction { _stub() }
    open class func scaleX(by xScale: CGFloat, y yScale: CGFloat, duration: TimeInterval) -> SKAction { _stub() }
    open class func fadeIn(withDuration duration: TimeInterval) -> SKAction { _stub() }
    open class func fadeOut(withDuration duration: TimeInterval) -> SKAction { _stub() }
    open class func fadeAlpha(by factor: CGFloat, duration: TimeInterval) -> SKAction { _stub() }
    open class func fadeAlpha(to alpha: CGFloat, duration: TimeInterval) -> SKAction { _stub() }
    open class func hide() -> SKAction { _stub() }
    open class func unhide() -> SKAction { _stub() }
    open class func resize(toWidth width: CGFloat, height: CGFloat, duration: TimeInterval) -> SKAction { _stub() }
    open class func setTexture(_ texture: SKTexture) -> SKAction { _stub() }
    open class func setTexture(_ texture: SKTexture, resize: Bool) -> SKAction { _stub() }
    open class func animate(with textures: [SKTexture], timePerFrame sec: TimeInterval) -> SKAction { _stub() }
    open class func animate(with textures: [SKTexture], timePerFrame sec: TimeInterval, resize: Bool,
                            restore: Bool) -> SKAction { _stub() }
    open class func colorize(with color: UIColor, colorBlendFactor: CGFloat, duration sec: TimeInterval) -> SKAction { _stub() }
    open class func colorize(withColorBlendFactor colorBlendFactor: CGFloat, duration sec: TimeInterval) -> SKAction { _stub() }
    open class func playSoundFileNamed(_ soundFile: String, waitForCompletion wait: Bool) -> SKAction { _stub() }
    open class func sequence(_ actions: [SKAction]) -> SKAction { _stub() }
    open class func group(_ actions: [SKAction]) -> SKAction { _stub() }
    open class func `repeat`(_ action: SKAction, count: Int) -> SKAction { _stub() }
    open class func repeatForever(_ action: SKAction) -> SKAction { _stub() }
    open class func wait(forDuration duration: TimeInterval) -> SKAction { _stub() }
    open class func wait(forDuration duration: TimeInterval, withRange durationRange: TimeInterval) -> SKAction { _stub() }
    open class func removeFromParent() -> SKAction { _stub() }
    open class func run(_ block: @escaping @Sendable () -> Void) -> SKAction { _stub() }
    open class func run(_ block: @escaping @Sendable () -> Void, queue: DispatchQueue) -> SKAction { _stub() }
    open class func customAction(withDuration duration: TimeInterval,
                                 actionBlock block: @escaping (SKNode, CGFloat) -> Void) -> SKAction { _stub() }
}

// MARK: - SpriteView (SwiftUI ↔ SpriteKit cross-import overlay on Apple platforms)

public struct SpriteView: View {
    public struct Options: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let allowsTransparency = Options(rawValue: 1 << 1)
        public static let ignoresSiblingOrder = Options(rawValue: 1 << 2)
        public static let shouldCullNonVisibleNodes = Options(rawValue: 1 << 3)
    }
    public struct DebugOptions: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let showsDrawCount = DebugOptions(rawValue: 1 << 1)
        public static let showsFields = DebugOptions(rawValue: 1 << 2)
        public static let showsFPS = DebugOptions(rawValue: 1 << 3)
        public static let showsNodeCount = DebugOptions(rawValue: 1 << 4)
        public static let showsPhysics = DebugOptions(rawValue: 1 << 5)
        public static let showsQuadCount = DebugOptions(rawValue: 1 << 6)
    }

    public init(scene: SKScene, transition: SKTransition? = nil, isPaused: Bool = false, preferredFramesPerSecond: Int = 60,
                options: SpriteView.Options = [], debugOptions: SpriteView.DebugOptions = [],
                shouldRender: @escaping (TimeInterval) -> Bool = { _ in true }) { _stub() }

    public typealias Body = Never
    public var body: Never { _stub() }
}
