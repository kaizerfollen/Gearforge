// SwiftUI stub — ShapeStyle, gradients, Shape & built-in shapes, Path.

// MARK: - ShapeStyle

public protocol ShapeStyle: Sendable {}

extension ShapeStyle {
    public func opacity(_ opacity: Double) -> some ShapeStyle { AnyShapeStyle(self) }
}

public struct AnyShapeStyle: ShapeStyle {
    public init<S: ShapeStyle>(_ style: S) { _stub() }
}

public struct ForegroundStyle: ShapeStyle {
    public init() {}
}
extension ShapeStyle where Self == ForegroundStyle {
    public static var foreground: ForegroundStyle { ForegroundStyle() }
}

public struct HierarchicalShapeStyle: ShapeStyle {
    public static let primary = HierarchicalShapeStyle(), secondary = HierarchicalShapeStyle(),
                      tertiary = HierarchicalShapeStyle(), quaternary = HierarchicalShapeStyle()
}
extension ShapeStyle where Self == HierarchicalShapeStyle {
    public static var primary: HierarchicalShapeStyle { _stub() }
    public static var secondary: HierarchicalShapeStyle { _stub() }
    public static var tertiary: HierarchicalShapeStyle { _stub() }
    public static var quaternary: HierarchicalShapeStyle { _stub() }
}

public struct TintShapeStyle: ShapeStyle { public init() {} }
extension ShapeStyle where Self == TintShapeStyle {
    public static var tint: TintShapeStyle { _stub() }
}

public struct Material: ShapeStyle {
    public static let regular = Material(), thick = Material(), thin = Material(), ultraThin = Material(),
                      ultraThick = Material(), bar = Material()
}
extension ShapeStyle where Self == Material {
    public static var regularMaterial: Material { _stub() }
    public static var thickMaterial: Material { _stub() }
    public static var thinMaterial: Material { _stub() }
    public static var ultraThinMaterial: Material { _stub() }
    public static var ultraThickMaterial: Material { _stub() }
    public static var bar: Material { _stub() }
}

extension Color: ShapeStyle {}
extension Color: View {
    public typealias Body = Never
    public var body: Never { _stub() }
}
extension ShapeStyle where Self == Color {
    public static var black: Color { _stub() }
    public static var white: Color { _stub() }
    public static var gray: Color { _stub() }
    public static var red: Color { _stub() }
    public static var green: Color { _stub() }
    public static var blue: Color { _stub() }
    public static var orange: Color { _stub() }
    public static var yellow: Color { _stub() }
    public static var pink: Color { _stub() }
    public static var purple: Color { _stub() }
    public static var clear: Color { _stub() }
    public static var mint: Color { _stub() }
    public static var teal: Color { _stub() }
    public static var cyan: Color { _stub() }
    public static var indigo: Color { _stub() }
    public static var brown: Color { _stub() }
}

// MARK: - Gradients

public struct Gradient: Hashable, Sendable {
    public struct Stop: Hashable, Sendable {
        public var color: Color
        public var location: CGFloat
        public init(color: Color, location: CGFloat) { self.color = color; self.location = location }
    }
    public var stops: [Gradient.Stop]
    public init(stops: [Gradient.Stop]) { self.stops = stops }
    public init(colors: [Color]) { _stub() }
}

public struct AnyGradient: Hashable, ShapeStyle {
    public init(_ gradient: Gradient) { _stub() }
}

public struct LinearGradient: ShapeStyle, View {
    public typealias Body = Never
    public var body: Never { _stub() }
    public init(gradient: Gradient, startPoint: UnitPoint, endPoint: UnitPoint) { _stub() }
    public init(colors: [Color], startPoint: UnitPoint, endPoint: UnitPoint) { _stub() }
    public init(stops: [Gradient.Stop], startPoint: UnitPoint, endPoint: UnitPoint) { _stub() }
}

public struct RadialGradient: ShapeStyle, View {
    public typealias Body = Never
    public var body: Never { _stub() }
    public init(gradient: Gradient, center: UnitPoint, startRadius: CGFloat, endRadius: CGFloat) { _stub() }
    public init(colors: [Color], center: UnitPoint, startRadius: CGFloat, endRadius: CGFloat) { _stub() }
    public init(stops: [Gradient.Stop], center: UnitPoint, startRadius: CGFloat, endRadius: CGFloat) { _stub() }
}

public struct AngularGradient: ShapeStyle, View {
    public typealias Body = Never
    public var body: Never { _stub() }
    public init(gradient: Gradient, center: UnitPoint, startAngle: Angle = .zero, endAngle: Angle = .zero) { _stub() }
    public init(colors: [Color], center: UnitPoint, startAngle: Angle, endAngle: Angle) { _stub() }
}

// MARK: - Stroke / fill styles

public struct StrokeStyle: Equatable, Sendable {
    public var lineWidth: CGFloat
    public var lineCap: CGLineCap
    public var lineJoin: CGLineJoin
    public var miterLimit: CGFloat
    public var dash: [CGFloat]
    public var dashPhase: CGFloat
    public init(lineWidth: CGFloat = 1, lineCap: CGLineCap = .butt, lineJoin: CGLineJoin = .miter,
                miterLimit: CGFloat = 10, dash: [CGFloat] = [CGFloat](), dashPhase: CGFloat = 0) {
        self.lineWidth = lineWidth; self.lineCap = lineCap; self.lineJoin = lineJoin
        self.miterLimit = miterLimit; self.dash = dash; self.dashPhase = dashPhase
    }
}

public struct FillStyle: Equatable, Sendable {
    public var isEOFilled: Bool
    public var isAntialiased: Bool
    public init(eoFill: Bool = false, antialiased: Bool = true) { isEOFilled = eoFill; isAntialiased = antialiased }
}

// MARK: - Shape

public protocol Animatable {}

public protocol Shape: Sendable, Animatable, View {
    func path(in rect: CGRect) -> Path
}

public protocol InsettableShape: Shape {
    associatedtype InsetShape: InsettableShape
    func inset(by amount: CGFloat) -> Self.InsetShape
}

public struct _ShapeView<Content: Shape, Style: ShapeStyle>: View {
    public typealias Body = Never
    public var body: Never { _stub() }
}

public struct _StrokedShape<S: Shape>: Shape {
    public func path(in rect: CGRect) -> Path { _stub() }
}
public struct _TrimmedShape<S: Shape>: Shape {
    public func path(in rect: CGRect) -> Path { _stub() }
}
public struct OffsetShape<Content: Shape>: Shape {
    public func path(in rect: CGRect) -> Path { _stub() }
}
public struct ScaledShape<Content: Shape>: Shape {
    public func path(in rect: CGRect) -> Path { _stub() }
}
public struct RotatedShape<Content: Shape>: Shape {
    public func path(in rect: CGRect) -> Path { _stub() }
}
public struct _InsetShape<Content: Shape>: InsettableShape {
    public func path(in rect: CGRect) -> Path { _stub() }
    public func inset(by amount: CGFloat) -> _InsetShape<Content> { _stub() }
}

extension Shape {
    public var body: _ShapeView<Self, ForegroundStyle> { _stub() }

    public func fill<S: ShapeStyle>(_ content: S = .foreground, style: FillStyle = FillStyle()) -> _ShapeView<Self, S> { _stub() }
    public func stroke<S: ShapeStyle>(_ content: S, style: StrokeStyle, antialiased: Bool = true) -> some View { fill(content) }
    public func stroke<S: ShapeStyle>(_ content: S, lineWidth: CGFloat = 1, antialiased: Bool = true) -> some View { fill(content) }
    public func stroke(style: StrokeStyle) -> some Shape { _StrokedShape<Self>() }
    public func stroke(lineWidth: CGFloat = 1) -> some Shape { _StrokedShape<Self>() }
    public func trim(from startFraction: CGFloat = 0, to endFraction: CGFloat = 1) -> some Shape { _TrimmedShape<Self>() }
    public func offset(_ offset: CGSize) -> OffsetShape<Self> { _stub() }
    public func offset(x: CGFloat = 0, y: CGFloat = 0) -> OffsetShape<Self> { _stub() }
    public func scale(_ scale: CGFloat, anchor: UnitPoint = .center) -> ScaledShape<Self> { _stub() }
    public func scale(x: CGFloat = 1, y: CGFloat = 1, anchor: UnitPoint = .center) -> ScaledShape<Self> { _stub() }
    public func rotation(_ angle: Angle, anchor: UnitPoint = .center) -> RotatedShape<Self> { _stub() }
}

extension InsettableShape {
    public func strokeBorder<S: ShapeStyle>(_ content: S, lineWidth: CGFloat = 1, antialiased: Bool = true) -> some View { fill(content) }
    public func strokeBorder<S: ShapeStyle>(_ content: S, style: StrokeStyle, antialiased: Bool = true) -> some View { fill(content) }
    public func strokeBorder(lineWidth: CGFloat = 1, antialiased: Bool = true) -> some View { fill() }
    public func strokeBorder(style: StrokeStyle, antialiased: Bool = true) -> some View { fill() }
}

public struct Rectangle: InsettableShape {
    public init() {}
    public func path(in rect: CGRect) -> Path { _stub() }
    public func inset(by amount: CGFloat) -> _InsetShape<Rectangle> { _stub() }
}

public struct RoundedRectangle: InsettableShape {
    public var cornerSize: CGSize
    public var style: RoundedCornerStyle
    public init(cornerSize: CGSize, style: RoundedCornerStyle = .continuous) { self.cornerSize = cornerSize; self.style = style }
    public init(cornerRadius: CGFloat, style: RoundedCornerStyle = .continuous) {
        self.cornerSize = CGSize(width: cornerRadius, height: cornerRadius); self.style = style
    }
    public func path(in rect: CGRect) -> Path { _stub() }
    public func inset(by amount: CGFloat) -> _InsetShape<RoundedRectangle> { _stub() }
}

public struct Circle: InsettableShape {
    public init() {}
    public func path(in rect: CGRect) -> Path { _stub() }
    public func inset(by amount: CGFloat) -> _InsetShape<Circle> { _stub() }
}

public struct Ellipse: InsettableShape {
    public init() {}
    public func path(in rect: CGRect) -> Path { _stub() }
    public func inset(by amount: CGFloat) -> _InsetShape<Ellipse> { _stub() }
}

public struct Capsule: InsettableShape {
    public var style: RoundedCornerStyle
    public init(style: RoundedCornerStyle = .continuous) { self.style = style }
    public func path(in rect: CGRect) -> Path { _stub() }
    public func inset(by amount: CGFloat) -> _InsetShape<Capsule> { _stub() }
}

extension Shape where Self == Rectangle { public static var rect: Rectangle { Rectangle() } }
extension Shape where Self == Circle { public static var circle: Circle { Circle() } }
extension Shape where Self == Capsule { public static var capsule: Capsule { Capsule() } }
extension Shape where Self == Ellipse { public static var ellipse: Ellipse { Ellipse() } }
extension Shape where Self == RoundedRectangle {
    public static func rect(cornerRadius: CGFloat, style: RoundedCornerStyle = .continuous) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: style)
    }
}

// MARK: - Path

public struct Path: Shape, Equatable {
    public init() {}
    public init(_ path: CGPath) { _stub() }
    public init(_ path: CGMutablePath) { _stub() }
    public init(_ rect: CGRect) { _stub() }
    public init(roundedRect rect: CGRect, cornerSize: CGSize, style: RoundedCornerStyle = .continuous) { _stub() }
    public init(roundedRect rect: CGRect, cornerRadius: CGFloat, style: RoundedCornerStyle = .continuous) { _stub() }
    public init(ellipseIn rect: CGRect) { _stub() }
    public init(_ callback: (inout Path) -> ()) { _stub() }

    public func path(in rect: CGRect) -> Path { _stub() }
    public var cgPath: CGPath { _stub() }
    public var isEmpty: Bool { _stub() }
    public var boundingRect: CGRect { _stub() }
    public var currentPoint: CGPoint? { _stub() }
    public func contains(_ p: CGPoint, eoFill: Bool = false) -> Bool { _stub() }
    public func applying(_ transform: CGAffineTransform) -> Path { _stub() }
    public func offsetBy(dx: CGFloat, dy: CGFloat) -> Path { _stub() }

    public mutating func move(to end: CGPoint) { _stub() }
    public mutating func addLine(to end: CGPoint) { _stub() }
    public mutating func addQuadCurve(to end: CGPoint, control: CGPoint) { _stub() }
    public mutating func addCurve(to end: CGPoint, control1: CGPoint, control2: CGPoint) { _stub() }
    public mutating func closeSubpath() { _stub() }
    public mutating func addRect(_ rect: CGRect, transform: CGAffineTransform = .identity) { _stub() }
    public mutating func addRoundedRect(in rect: CGRect, cornerSize: CGSize, style: RoundedCornerStyle = .continuous,
                                        transform: CGAffineTransform = .identity) { _stub() }
    public mutating func addEllipse(in rect: CGRect, transform: CGAffineTransform = .identity) { _stub() }
    public mutating func addRects(_ rects: [CGRect], transform: CGAffineTransform = .identity) { _stub() }
    public mutating func addLines(_ lines: [CGPoint]) { _stub() }
    public mutating func addArc(center: CGPoint, radius: CGFloat, startAngle: Angle, endAngle: Angle, clockwise: Bool,
                                transform: CGAffineTransform = .identity) { _stub() }
    public mutating func addPath(_ path: Path, transform: CGAffineTransform = .identity) { _stub() }
}
