// SwiftUI stub — gestures, animation, transitions.

// MARK: - Gesture

@MainActor @preconcurrency
public protocol Gesture<Value> {
    associatedtype Value
    associatedtype Body: Gesture
    var body: Self.Body { get }
}
extension Never: Gesture {
    public typealias Value = Never
}

public struct GestureMask: OptionSet, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let none = GestureMask([])
    public static let gesture = GestureMask(rawValue: 1)
    public static let subviews = GestureMask(rawValue: 2)
    public static let all: GestureMask = [.gesture, .subviews]
}

public struct _ChangedGesture<Content: Gesture>: Gesture {
    public typealias Value = Content.Value
    public typealias Body = Never
    public var body: Never { _stub() }
}
public struct _EndedGesture<Content: Gesture>: Gesture {
    public typealias Value = Content.Value
    public typealias Body = Never
    public var body: Never { _stub() }
}
public struct _MapGesture<Content: Gesture, Value>: Gesture {
    public typealias Body = Never
    public var body: Never { _stub() }
}
public struct GestureStateGesture<Base: Gesture, State>: Gesture {
    public typealias Value = Base.Value
    public typealias Body = Never
    public var body: Never { _stub() }
}
public struct SimultaneousGesture<First: Gesture, Second: Gesture>: Gesture {
    public struct Value {
        public var first: First.Value?
        public var second: Second.Value?
    }
    public typealias Body = Never
    public var body: Never { _stub() }
}
public struct SequenceGesture<First: Gesture, Second: Gesture>: Gesture {
    public enum Value {
        case first(First.Value)
        case second(First.Value, Second.Value?)
    }
    public typealias Body = Never
    public var body: Never { _stub() }
}
public struct ExclusiveGesture<First: Gesture, Second: Gesture>: Gesture {
    public enum Value {
        case first(First.Value)
        case second(Second.Value)
    }
    public typealias Body = Never
    public var body: Never { _stub() }
}

extension Gesture where Value: Equatable {
    public func onChanged(_ action: @escaping (Self.Value) -> Void) -> _ChangedGesture<Self> { _stub() }
}
extension Gesture {
    public func onEnded(_ action: @escaping (Self.Value) -> Void) -> _EndedGesture<Self> { _stub() }
    public func map<T>(_ body: @escaping (Self.Value) -> T) -> _MapGesture<Self, T> { _stub() }
    public func updating<State>(_ state: GestureState<State>,
                                body: @escaping (Self.Value, inout State, inout Transaction) -> Void) -> GestureStateGesture<Self, State> { _stub() }
    public func simultaneously<Other: Gesture>(with other: Other) -> SimultaneousGesture<Self, Other> { _stub() }
    public func sequenced<Other: Gesture>(before other: Other) -> SequenceGesture<Self, Other> { _stub() }
    public func exclusively<Other: Gesture>(before other: Other) -> ExclusiveGesture<Self, Other> { _stub() }
}

public struct DragGesture: Gesture {
    public struct Value: Equatable, Sendable {
        public var time: Date
        public var location: CGPoint
        public var startLocation: CGPoint
        public var translation: CGSize { _stub() }
        public var velocity: CGSize { _stub() }
        public var predictedEndLocation: CGPoint { _stub() }
        public var predictedEndTranslation: CGSize { _stub() }
    }
    public typealias Body = Never
    public var body: Never { _stub() }
    public var minimumDistance: CGFloat
    public var coordinateSpace: CoordinateSpace
    public init(minimumDistance: CGFloat = 10, coordinateSpace: CoordinateSpace = .local) {
        self.minimumDistance = minimumDistance; self.coordinateSpace = coordinateSpace
    }
}

public struct TapGesture: Gesture {
    public typealias Value = Void
    public typealias Body = Never
    public var body: Never { _stub() }
    public var count: Int
    public init(count: Int = 1) { self.count = count }
}

public struct SpatialTapGesture: Gesture {
    public struct Value: Equatable, Sendable {
        public var location: CGPoint
    }
    public typealias Body = Never
    public var body: Never { _stub() }
    public init(count: Int = 1, coordinateSpace: CoordinateSpace = .local) { _stub() }
}

public struct LongPressGesture: Gesture {
    public typealias Value = Bool
    public typealias Body = Never
    public var body: Never { _stub() }
    public var minimumDuration: Double
    public var maximumDistance: CGFloat
    public init(minimumDuration: Double = 0.5, maximumDistance: CGFloat = 10) {
        self.minimumDuration = minimumDuration; self.maximumDistance = maximumDistance
    }
}

@available(*, deprecated, message: "(iOS 17) renamed to MagnifyGesture")
public struct MagnificationGesture: Gesture {
    public typealias Value = CGFloat
    public typealias Body = Never
    public var body: Never { _stub() }
    public var minimumScaleDelta: CGFloat
    public init(minimumScaleDelta: CGFloat = 0.01) { self.minimumScaleDelta = minimumScaleDelta }
}

public struct MagnifyGesture: Gesture {
    public struct Value: Equatable, Sendable {
        public var time: Date
        public var magnification: CGFloat
        public var velocity: CGFloat
        public var startAnchor: UnitPoint
        public var startLocation: CGPoint
    }
    public typealias Body = Never
    public var body: Never { _stub() }
    public var minimumScaleDelta: CGFloat
    public init(minimumScaleDelta: CGFloat = 0.01) { self.minimumScaleDelta = minimumScaleDelta }
}

public struct RotateGesture: Gesture {
    public struct Value: Equatable, Sendable {
        public var time: Date
        public var rotation: Angle
        public var velocity: Angle
        public var startAnchor: UnitPoint
        public var startLocation: CGPoint
    }
    public typealias Body = Never
    public var body: Never { _stub() }
    public init(minimumAngleDelta: Angle = .degrees(1)) { _stub() }
}

extension View {
    public func gesture<T: Gesture>(_ gesture: T, including mask: GestureMask = .all) -> some View { _modified() }
    public func simultaneousGesture<T: Gesture>(_ gesture: T, including mask: GestureMask = .all) -> some View { _modified() }
    public func highPriorityGesture<T: Gesture>(_ gesture: T, including mask: GestureMask = .all) -> some View { _modified() }
    public func onTapGesture(count: Int = 1, perform action: @escaping () -> Void) -> some View { _modified() }
    public func onTapGesture(count: Int = 1, coordinateSpace: CoordinateSpace = .local,
                             perform action: @escaping (CGPoint) -> Void) -> some View { _modified() }
    public func onLongPressGesture(minimumDuration: Double = 0.5, maximumDistance: CGFloat = 10,
                                   perform action: @escaping () -> Void,
                                   onPressingChanged: ((Bool) -> Void)? = nil) -> some View { _modified() }
}

// MARK: - Animation

public struct Animation: Equatable, Sendable {
    public static func == (lhs: Animation, rhs: Animation) -> Bool { _stub() }

    public static let `default` = Animation()
    public static var linear: Animation { _stub() }
    public static var easeIn: Animation { _stub() }
    public static var easeOut: Animation { _stub() }
    public static var easeInOut: Animation { _stub() }
    public static var spring: Animation { _stub() }
    public static var interactiveSpring: Animation { _stub() }
    public static var bouncy: Animation { _stub() }
    public static var smooth: Animation { _stub() }
    public static var snappy: Animation { _stub() }

    public static func linear(duration: TimeInterval) -> Animation { _stub() }
    public static func easeIn(duration: TimeInterval) -> Animation { _stub() }
    public static func easeOut(duration: TimeInterval) -> Animation { _stub() }
    public static func easeInOut(duration: TimeInterval) -> Animation { _stub() }
    public static func timingCurve(_ p1x: Double, _ p1y: Double, _ p2x: Double, _ p2y: Double,
                                   duration: TimeInterval = 0.35) -> Animation { _stub() }
    public static func spring(duration: TimeInterval = 0.5, bounce: Double = 0.0, blendDuration: Double = 0) -> Animation { _stub() }
    @_disfavoredOverload
    public static func spring(response: Double = 0.5, dampingFraction: Double = 0.825, blendDuration: TimeInterval = 0) -> Animation { _stub() }
    public static func interactiveSpring(response: Double = 0.15, dampingFraction: Double = 0.86,
                                         blendDuration: TimeInterval = 0.25) -> Animation { _stub() }
    public static func bouncy(duration: TimeInterval = 0.5, extraBounce: Double = 0.0) -> Animation { _stub() }
    public static func smooth(duration: TimeInterval = 0.5, extraBounce: Double = 0.0) -> Animation { _stub() }
    public static func snappy(duration: TimeInterval = 0.5, extraBounce: Double = 0.0) -> Animation { _stub() }

    public func delay(_ delay: TimeInterval) -> Animation { _stub() }
    public func speed(_ speed: Double) -> Animation { _stub() }
    public func repeatCount(_ repeatCount: Int, autoreverses: Bool = true) -> Animation { _stub() }
    public func repeatForever(autoreverses: Bool = true) -> Animation { _stub() }
}

public func withAnimation<Result>(_ animation: Animation? = .default, _ body: () throws -> Result) rethrows -> Result { _stub() }
public func withAnimation<Result>(_ animation: Animation? = .default, completionCriteria: AnimationCompletionCriteria = .logicallyComplete,
                                  _ body: () throws -> Result, completion: @escaping () -> Void) rethrows -> Result { _stub() }

public struct AnimationCompletionCriteria: Hashable, Sendable {
    public static let logicallyComplete = AnimationCompletionCriteria(), removed = AnimationCompletionCriteria()
}

extension View {
    public func animation<V: Equatable>(_ animation: Animation?, value: V) -> some View { _modified() }
    public func animation<V: View>(_ animation: Animation?, @ViewBuilder body: (PlaceholderContentView<Self>) -> V) -> some View { _modified() }
    public func transition(_ t: AnyTransition) -> some View { _modified() }
    public func contentTransition(_ transition: ContentTransition) -> some View { _modified() }
}

public struct PlaceholderContentView<Value>: View {
    public typealias Body = Never
    public var body: Never { _stub() }
}

public struct ContentTransition: Equatable, Sendable {
    public static let identity = ContentTransition(), opacity = ContentTransition(), interpolate = ContentTransition()
    public static func numericText(countsDown: Bool = false) -> ContentTransition { _stub() }
}

public struct AnyTransition {
    public static let identity = AnyTransition(), opacity = AnyTransition(), scale = AnyTransition(),
                      slide = AnyTransition()
    public static func scale(scale: CGFloat, anchor: UnitPoint = .center) -> AnyTransition { _stub() }
    public static func move(edge: Edge) -> AnyTransition { _stub() }
    public static func push(from edge: Edge) -> AnyTransition { _stub() }
    public static func offset(_ offset: CGSize) -> AnyTransition { _stub() }
    public static func offset(x: CGFloat = 0, y: CGFloat = 0) -> AnyTransition { _stub() }
    public static func asymmetric(insertion: AnyTransition, removal: AnyTransition) -> AnyTransition { _stub() }
    public func combined(with other: AnyTransition) -> AnyTransition { _stub() }
    public func animation(_ animation: Animation?) -> AnyTransition { _stub() }
}
