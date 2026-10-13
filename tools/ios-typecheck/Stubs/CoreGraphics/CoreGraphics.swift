// API stub of Apple's CoreGraphics for the Linux typecheck harness. Signatures mirror the iOS 17/18 SDK.
// CGFloat, CGPoint, CGSize and CGRect (and their geometry helpers) come from swift-corelibs-foundation on Linux,
// so they are re-exported from Foundation instead of being redeclared here.
@_exported import Foundation

@inline(never) func _stub() -> Never { fatalError("CoreGraphics stub: typecheck only") }

// Linux has no CoreFoundation types in the public Foundation API; these aliases make `data as CFData` and
// `"name" as CFString` typecheck the way they do on Apple platforms.
public typealias CFData = NSData
public typealias CFString = NSString
public typealias CFTimeInterval = Double

// MARK: - CGVector

public struct CGVector: Equatable, Hashable, Codable, Sendable {
    public var dx: CGFloat
    public var dy: CGFloat
    public init() { dx = 0; dy = 0 }
    public init(dx: CGFloat, dy: CGFloat) { self.dx = dx; self.dy = dy }
    public init(dx: Double, dy: Double) { self.dx = CGFloat(dx); self.dy = CGFloat(dy) }
    public init(dx: Int, dy: Int) { self.dx = CGFloat(dx); self.dy = CGFloat(dy) }
    public static var zero: CGVector { CGVector() }
}

// MARK: - CGAffineTransform

public struct CGAffineTransform: Equatable, Hashable, Codable, Sendable {
    public var a: CGFloat, b: CGFloat, c: CGFloat, d: CGFloat, tx: CGFloat, ty: CGFloat
    public init() { a = 1; b = 0; c = 0; d = 1; tx = 0; ty = 0 }
    public init(a: CGFloat, b: CGFloat, c: CGFloat, d: CGFloat, tx: CGFloat, ty: CGFloat) {
        self.a = a; self.b = b; self.c = c; self.d = d; self.tx = tx; self.ty = ty
    }
    public init(translationX tx: CGFloat, y ty: CGFloat) { _stub() }
    public init(scaleX sx: CGFloat, y sy: CGFloat) { _stub() }
    public init(rotationAngle angle: CGFloat) { _stub() }
    public static var identity: CGAffineTransform { CGAffineTransform() }
    public var isIdentity: Bool { _stub() }
    public func translatedBy(x tx: CGFloat, y ty: CGFloat) -> CGAffineTransform { _stub() }
    public func scaledBy(x sx: CGFloat, y sy: CGFloat) -> CGAffineTransform { _stub() }
    public func rotated(by angle: CGFloat) -> CGAffineTransform { _stub() }
    public func inverted() -> CGAffineTransform { _stub() }
    public func concatenating(_ t2: CGAffineTransform) -> CGAffineTransform { _stub() }
}

extension CGPoint {
    public func applying(_ t: CGAffineTransform) -> CGPoint { _stub() }
}
extension CGSize {
    public func applying(_ t: CGAffineTransform) -> CGSize { _stub() }
}
extension CGRect {
    public func applying(_ t: CGAffineTransform) -> CGRect { _stub() }
}

// MARK: - Enums / option sets

public enum CGLineCap: Int32, Sendable { case butt = 0, round, square }
public enum CGLineJoin: Int32, Sendable { case miter = 0, round, bevel }
public enum CGPathFillRule: Int, Sendable { case winding = 0, evenOdd }
public enum CGInterpolationQuality: Int32, Sendable { case `default` = 0, none, low, high, medium }
public enum CGColorRenderingIntent: Int32, Sendable {
    case defaultIntent = 0, absoluteColorimetric, relativeColorimetric, perceptual, saturation
}
public enum CGBlendMode: Int32, Sendable {
    case normal = 0, multiply, screen, overlay, darken, lighten, colorDodge, colorBurn, softLight, hardLight,
         difference, exclusion, hue, saturation, color, luminosity, clear, copy, sourceIn, sourceOut, sourceAtop,
         destinationOver, destinationIn, destinationOut, destinationAtop, xor, plusDarker, plusLighter
}
public enum CGImageAlphaInfo: UInt32, Sendable {
    case none = 0, premultipliedLast, premultipliedFirst, last, first, noneSkipLast, noneSkipFirst, alphaOnly
}
public struct CGBitmapInfo: OptionSet, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public init(alpha: CGImageAlphaInfo) { self.rawValue = alpha.rawValue }
    public static let alphaInfoMask = CGBitmapInfo(rawValue: 0x1F)
    public static let floatInfoMask = CGBitmapInfo(rawValue: 0xF00)
    public static let floatComponents = CGBitmapInfo(rawValue: 1 << 8)
    public static let byteOrderMask = CGBitmapInfo(rawValue: 0x7000)
    public static let byteOrderDefault = CGBitmapInfo([])
    public static let byteOrder16Little = CGBitmapInfo(rawValue: 1 << 12)
    public static let byteOrder32Little = CGBitmapInfo(rawValue: 2 << 12)
    public static let byteOrder16Big = CGBitmapInfo(rawValue: 3 << 12)
    public static let byteOrder32Big = CGBitmapInfo(rawValue: 4 << 12)
}

// MARK: - Colors / color spaces

public final class CGColorSpace: @unchecked Sendable {
    public init?(name: CFString) { _stub() }
    public static let sRGB: CFString = "kCGColorSpaceSRGB"
    public static let linearSRGB: CFString = "kCGColorSpaceLinearSRGB"
    public static let displayP3: CFString = "kCGColorSpaceDisplayP3"
    public static let genericGrayGamma2_2: CFString = "kCGColorSpaceGenericGrayGamma2_2"
    public var numberOfComponents: Int { _stub() }
}
public func CGColorSpaceCreateDeviceRGB() -> CGColorSpace { _stub() }
public func CGColorSpaceCreateDeviceGray() -> CGColorSpace { _stub() }

public final class CGColor: @unchecked Sendable {
    public init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) { _stub() }
    public init(gray: CGFloat, alpha: CGFloat) { _stub() }
    public init?(colorSpace space: CGColorSpace, components: UnsafePointer<CGFloat>) { _stub() }
    public var alpha: CGFloat { _stub() }
    public var components: [CGFloat]? { _stub() }
    public var numberOfComponents: Int { _stub() }
    public var colorSpace: CGColorSpace? { _stub() }
    public func copy(alpha: CGFloat) -> CGColor? { _stub() }
    public static var black: CGColor { _stub() }
    public static var white: CGColor { _stub() }
    public static var clear: CGColor { _stub() }
}

// MARK: - Images

public final class CGDataProvider: @unchecked Sendable {
    public init?(data: CFData) { _stub() }
    public var data: CFData? { _stub() }
}

public final class CGImage: @unchecked Sendable {
    public init?(width: Int, height: Int, bitsPerComponent: Int, bitsPerPixel: Int, bytesPerRow: Int,
                 space: CGColorSpace, bitmapInfo: CGBitmapInfo, provider: CGDataProvider,
                 decode: UnsafePointer<CGFloat>?, shouldInterpolate: Bool, intent: CGColorRenderingIntent) { _stub() }
    public var width: Int { _stub() }
    public var height: Int { _stub() }
    public var bitsPerComponent: Int { _stub() }
    public var bitsPerPixel: Int { _stub() }
    public var bytesPerRow: Int { _stub() }
    public var alphaInfo: CGImageAlphaInfo { _stub() }
    public var bitmapInfo: CGBitmapInfo { _stub() }
    public var colorSpace: CGColorSpace? { _stub() }
    public var dataProvider: CGDataProvider? { _stub() }
    public func cropping(to rect: CGRect) -> CGImage? { _stub() }
}

// MARK: - Paths

public class CGPath: @unchecked Sendable {
    init(_stubOnly: Void) {}
    public convenience init(rect: CGRect, transform: UnsafePointer<CGAffineTransform>?) { _stub() }
    public convenience init(ellipseIn rect: CGRect, transform: UnsafePointer<CGAffineTransform>?) { _stub() }
    public convenience init(roundedRect rect: CGRect, cornerWidth: CGFloat, cornerHeight: CGFloat,
                            transform: UnsafePointer<CGAffineTransform>?) { _stub() }
    public var boundingBox: CGRect { _stub() }
    public var boundingBoxOfPath: CGRect { _stub() }
    public var currentPoint: CGPoint { _stub() }
    public var isEmpty: Bool { _stub() }
    public func copy() -> CGPath? { _stub() }
    public func mutableCopy() -> CGMutablePath? { _stub() }
    public func contains(_ point: CGPoint, using rule: CGPathFillRule = .winding,
                         transform: CGAffineTransform = .identity) -> Bool { _stub() }
}

public class CGMutablePath: CGPath, @unchecked Sendable {
    public init() { super.init(_stubOnly: ()) }
    public func move(to point: CGPoint, transform: CGAffineTransform = .identity) { _stub() }
    public func addLine(to point: CGPoint, transform: CGAffineTransform = .identity) { _stub() }
    public func addLines(between points: [CGPoint], transform: CGAffineTransform = .identity) { _stub() }
    public func addRect(_ rect: CGRect, transform: CGAffineTransform = .identity) { _stub() }
    public func addRects(_ rects: [CGRect], transform: CGAffineTransform = .identity) { _stub() }
    public func addEllipse(in rect: CGRect, transform: CGAffineTransform = .identity) { _stub() }
    public func addRoundedRect(in rect: CGRect, cornerWidth: CGFloat, cornerHeight: CGFloat,
                               transform: CGAffineTransform = .identity) { _stub() }
    public func addArc(center: CGPoint, radius: CGFloat, startAngle: CGFloat, endAngle: CGFloat, clockwise: Bool,
                       transform: CGAffineTransform = .identity) { _stub() }
    public func addArc(tangent1End: CGPoint, tangent2End: CGPoint, radius: CGFloat,
                       transform: CGAffineTransform = .identity) { _stub() }
    public func addQuadCurve(to end: CGPoint, control: CGPoint, transform: CGAffineTransform = .identity) { _stub() }
    public func addCurve(to end: CGPoint, control1: CGPoint, control2: CGPoint,
                         transform: CGAffineTransform = .identity) { _stub() }
    public func addPath(_ path: CGPath, transform: CGAffineTransform = .identity) { _stub() }
    public func closeSubpath() { _stub() }
}

// MARK: - Context

public final class CGContext: @unchecked Sendable {
    public init?(data: UnsafeMutableRawPointer?, width: Int, height: Int, bitsPerComponent: Int, bytesPerRow: Int,
                 space: CGColorSpace, bitmapInfo: UInt32) { _stub() }
    public var data: UnsafeMutableRawPointer? { _stub() }
    public var width: Int { _stub() }
    public var height: Int { _stub() }
    public var bytesPerRow: Int { _stub() }
    public var interpolationQuality: CGInterpolationQuality { get { _stub() } set { _stub() } }
    public var ctm: CGAffineTransform { _stub() }
    public func makeImage() -> CGImage? { _stub() }

    public func saveGState() { _stub() }
    public func restoreGState() { _stub() }
    public func translateBy(x tx: CGFloat, y ty: CGFloat) { _stub() }
    public func scaleBy(x sx: CGFloat, y sy: CGFloat) { _stub() }
    public func rotate(by angle: CGFloat) { _stub() }
    public func concatenate(_ transform: CGAffineTransform) { _stub() }

    public func setFillColor(_ color: CGColor) { _stub() }
    public func setFillColor(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) { _stub() }
    public func setFillColor(gray: CGFloat, alpha: CGFloat) { _stub() }
    public func setStrokeColor(_ color: CGColor) { _stub() }
    public func setStrokeColor(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) { _stub() }
    public func setLineWidth(_ width: CGFloat) { _stub() }
    public func setLineCap(_ cap: CGLineCap) { _stub() }
    public func setLineJoin(_ join: CGLineJoin) { _stub() }
    public func setLineDash(phase: CGFloat, lengths: [CGFloat]) { _stub() }
    public func setAlpha(_ alpha: CGFloat) { _stub() }
    public func setBlendMode(_ mode: CGBlendMode) { _stub() }
    public func setShouldAntialias(_ shouldAntialias: Bool) { _stub() }
    public func setAllowsAntialiasing(_ allowsAntialiasing: Bool) { _stub() }
    public func setShadow(offset: CGSize, blur: CGFloat, color: CGColor?) { _stub() }

    public func beginPath() { _stub() }
    public func move(to point: CGPoint) { _stub() }
    public func addLine(to point: CGPoint) { _stub() }
    public func addLines(between points: [CGPoint]) { _stub() }
    public func addRect(_ rect: CGRect) { _stub() }
    public func addEllipse(in rect: CGRect) { _stub() }
    public func addArc(center: CGPoint, radius: CGFloat, startAngle: CGFloat, endAngle: CGFloat,
                       clockwise: Bool) { _stub() }
    public func addQuadCurve(to end: CGPoint, control: CGPoint) { _stub() }
    public func addCurve(to end: CGPoint, control1: CGPoint, control2: CGPoint) { _stub() }
    public func addPath(_ path: CGPath) { _stub() }
    public func closePath() { _stub() }
    public func fillPath(using rule: CGPathFillRule = .winding) { _stub() }
    public func strokePath() { _stub() }
    public func drawPath(using mode: CGPathDrawingMode) { _stub() }
    public func clip(using rule: CGPathFillRule = .winding) { _stub() }
    public func clip(to rect: CGRect) { _stub() }

    public func fill(_ rect: CGRect) { _stub() }
    public func fill(_ rects: [CGRect]) { _stub() }
    public func stroke(_ rect: CGRect) { _stub() }
    public func stroke(_ rect: CGRect, width: CGFloat) { _stub() }
    public func clear(_ rect: CGRect) { _stub() }
    public func fillEllipse(in rect: CGRect) { _stub() }
    public func strokeEllipse(in rect: CGRect) { _stub() }
    public func strokeLineSegments(between points: [CGPoint]) { _stub() }
    public func draw(_ image: CGImage, in rect: CGRect, byTiling: Bool = false) { _stub() }
}

public enum CGPathDrawingMode: Int32, Sendable { case fill = 0, eoFill, stroke, fillStroke, eoFillStroke }
