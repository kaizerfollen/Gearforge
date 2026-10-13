// SwiftUI stub — geometry & layout value types.

public struct Angle: Hashable, Comparable, Sendable {
    public var radians: Double
    public var degrees: Double { get { radians * 180 / .pi } set { radians = newValue * .pi / 180 } }
    public init() { radians = 0 }
    public init(radians: Double) { self.radians = radians }
    public init(degrees: Double) { self.radians = degrees * .pi / 180 }
    public static func radians(_ radians: Double) -> Angle { Angle(radians: radians) }
    public static func degrees(_ degrees: Double) -> Angle { Angle(degrees: degrees) }
    public static var zero: Angle { Angle() }
    public static func < (lhs: Angle, rhs: Angle) -> Bool { lhs.radians < rhs.radians }
    public static func + (lhs: Angle, rhs: Angle) -> Angle { Angle(radians: lhs.radians + rhs.radians) }
    public static func - (lhs: Angle, rhs: Angle) -> Angle { Angle(radians: lhs.radians - rhs.radians) }
    public static prefix func - (a: Angle) -> Angle { Angle(radians: -a.radians) }
    public static func * (lhs: Angle, rhs: Double) -> Angle { Angle(radians: lhs.radians * rhs) }
    public static func / (lhs: Angle, rhs: Double) -> Angle { Angle(radians: lhs.radians / rhs) }
    public static func += (lhs: inout Angle, rhs: Angle) { lhs.radians += rhs.radians }
    public static func -= (lhs: inout Angle, rhs: Angle) { lhs.radians -= rhs.radians }
}

public struct UnitPoint: Hashable, Sendable {
    public var x: CGFloat
    public var y: CGFloat
    public init() { x = 0; y = 0 }
    public init(x: CGFloat, y: CGFloat) { self.x = x; self.y = y }
    public static let zero = UnitPoint(x: 0, y: 0)
    public static let center = UnitPoint(x: 0.5, y: 0.5)
    public static let leading = UnitPoint(x: 0, y: 0.5)
    public static let trailing = UnitPoint(x: 1, y: 0.5)
    public static let top = UnitPoint(x: 0.5, y: 0)
    public static let bottom = UnitPoint(x: 0.5, y: 1)
    public static let topLeading = UnitPoint(x: 0, y: 0)
    public static let topTrailing = UnitPoint(x: 1, y: 0)
    public static let bottomLeading = UnitPoint(x: 0, y: 1)
    public static let bottomTrailing = UnitPoint(x: 1, y: 1)
}

public struct HorizontalAlignment: Equatable, Sendable {
    public static let leading = HorizontalAlignment()
    public static let center = HorizontalAlignment()
    public static let trailing = HorizontalAlignment()
    public static func == (a: Self, b: Self) -> Bool { _stub() }
}
public struct VerticalAlignment: Equatable, Sendable {
    public static let top = VerticalAlignment()
    public static let center = VerticalAlignment()
    public static let bottom = VerticalAlignment()
    public static let firstTextBaseline = VerticalAlignment()
    public static let lastTextBaseline = VerticalAlignment()
    public static func == (a: Self, b: Self) -> Bool { _stub() }
}
public struct Alignment: Equatable, Sendable {
    public var horizontal: HorizontalAlignment
    public var vertical: VerticalAlignment
    public init(horizontal: HorizontalAlignment, vertical: VerticalAlignment) {
        self.horizontal = horizontal; self.vertical = vertical
    }
    public static let center = Alignment(horizontal: .center, vertical: .center)
    public static let leading = Alignment(horizontal: .leading, vertical: .center)
    public static let trailing = Alignment(horizontal: .trailing, vertical: .center)
    public static let top = Alignment(horizontal: .center, vertical: .top)
    public static let bottom = Alignment(horizontal: .center, vertical: .bottom)
    public static let topLeading = Alignment(horizontal: .leading, vertical: .top)
    public static let topTrailing = Alignment(horizontal: .trailing, vertical: .top)
    public static let bottomLeading = Alignment(horizontal: .leading, vertical: .bottom)
    public static let bottomTrailing = Alignment(horizontal: .trailing, vertical: .bottom)
}

public enum TextAlignment: Hashable, CaseIterable, Sendable { case leading, center, trailing }
public enum ContentMode: Hashable, CaseIterable, Sendable { case fit, fill }

public enum Edge: Int8, CaseIterable, Hashable, Sendable {
    case top, leading, bottom, trailing
    public struct Set: OptionSet, Sendable {
        public let rawValue: Int8
        public init(rawValue: Int8) { self.rawValue = rawValue }
        public init(_ e: Edge) { self.rawValue = 1 << e.rawValue }
        public static let top = Set(.top)
        public static let leading = Set(.leading)
        public static let bottom = Set(.bottom)
        public static let trailing = Set(.trailing)
        public static let all: Set = [.top, .leading, .bottom, .trailing]
        public static let horizontal: Set = [.leading, .trailing]
        public static let vertical: Set = [.top, .bottom]
    }
}
public enum VerticalEdge: Int8, Hashable, CaseIterable, Sendable { case top, bottom }
public enum HorizontalEdge: Int8, Hashable, CaseIterable, Sendable { case leading, trailing }

public struct EdgeInsets: Equatable, Sendable {
    public var top: CGFloat, leading: CGFloat, bottom: CGFloat, trailing: CGFloat
    public init(top: CGFloat, leading: CGFloat, bottom: CGFloat, trailing: CGFloat) {
        self.top = top; self.leading = leading; self.bottom = bottom; self.trailing = trailing
    }
    public init() { top = 0; leading = 0; bottom = 0; trailing = 0 }
}

public enum Axis: Int8, CaseIterable, Hashable, Sendable {
    case horizontal, vertical
    public struct Set: OptionSet, Sendable {
        public let rawValue: Int8
        public init(rawValue: Int8) { self.rawValue = rawValue }
        public static let horizontal = Set(rawValue: 1)
        public static let vertical = Set(rawValue: 2)
    }
}

public struct SafeAreaRegions: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let container = SafeAreaRegions(rawValue: 1)
    public static let keyboard = SafeAreaRegions(rawValue: 2)
    public static let all: SafeAreaRegions = [.container, .keyboard]
}

public enum Visibility: Hashable, CaseIterable, Sendable { case automatic, visible, hidden }

public enum CoordinateSpace: Hashable {
    case global
    case local
    case named(AnyHashable)
}

public struct GeometryProxy {
    public var size: CGSize { _stub() }
    public var safeAreaInsets: EdgeInsets { _stub() }
    public func frame(in coordinateSpace: CoordinateSpace) -> CGRect { _stub() }
}

public struct PinnedScrollableViews: OptionSet, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let sectionHeaders = PinnedScrollableViews(rawValue: 1)
    public static let sectionFooters = PinnedScrollableViews(rawValue: 2)
}

public struct GridItem: Sendable {
    public enum Size: Sendable {
        case fixed(CGFloat)
        case flexible(minimum: CGFloat = 10, maximum: CGFloat = .infinity)
        case adaptive(minimum: CGFloat, maximum: CGFloat = .infinity)
    }
    public var size: GridItem.Size
    public var spacing: CGFloat?
    public var alignment: Alignment?
    public init(_ size: GridItem.Size = .flexible(), spacing: CGFloat? = nil, alignment: Alignment? = nil) {
        self.size = size; self.spacing = spacing; self.alignment = alignment
    }
}

public enum BlendMode: Sendable {
    case normal, multiply, screen, overlay, darken, lighten, colorDodge, colorBurn, softLight, hardLight,
         difference, exclusion, hue, saturation, color, luminosity, sourceAtop, destinationOver, destinationOut,
         plusDarker, plusLighter
}

public enum RoundedCornerStyle: Hashable, Sendable { case circular, continuous }
