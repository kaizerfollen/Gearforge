// API stub of Apple's SwiftUI (subset) for the Linux typecheck harness — core protocols, ViewBuilder and the
// data-flow property wrappers. Signatures mirror the iOS 17/18 SDK (Xcode 15/16). `View`, `App`, `Scene` are
// `@MainActor @preconcurrency` as in the iOS 18 SDK.
@_exported import Foundation
@_exported import CoreGraphics
@_exported import UIKit
@_exported import Combine
@_exported import Observation

@inline(never) func _stub() -> Never { fatalError("SwiftUI stub: typecheck only") }

// MARK: - View

@MainActor @preconcurrency
public protocol View {
    associatedtype Body: View
    @ViewBuilder @MainActor @preconcurrency var body: Self.Body { get }
}

extension Never: View {
    public typealias Body = Never
    public var body: Never { _stub() }
}

extension Optional: View where Wrapped: View {
    public typealias Body = Never
    public var body: Never { _stub() }
}

public struct EmptyView: View {
    public typealias Body = Never
    public init() {}
    public var body: Never { _stub() }
}

public struct TupleView<T>: View {
    public typealias Body = Never
    public var value: T
    public init(_ value: T) { self.value = value }
    public var body: Never { _stub() }
}

public struct _ConditionalContent<TrueContent, FalseContent>: View where TrueContent: View, FalseContent: View {
    public typealias Body = Never
    public var body: Never { _stub() }
}

public struct AnyView: View {
    public typealias Body = Never
    public init<V: View>(_ view: V) { _stub() }
    public init<V: View>(erasing view: V) { _stub() }
    public var body: Never { _stub() }
}

public struct Group<Content> {
    public init() { _stub() }
}
extension Group: View where Content: View {
    public typealias Body = Never
    public init(@ViewBuilder content: () -> Content) { _stub() }
    public var body: Never { _stub() }
}

@resultBuilder
public struct ViewBuilder {
    public static func buildExpression<Content: View>(_ content: Content) -> Content { content }
    public static func buildBlock() -> EmptyView { EmptyView() }
    public static func buildBlock<Content: View>(_ content: Content) -> Content { content }
    public static func buildBlock<each Content: View>(_ content: repeat each Content) -> TupleView<(repeat each Content)> {
        TupleView((repeat each content))
    }
    public static func buildIf<Content: View>(_ content: Content?) -> Content? { content }
    public static func buildEither<TrueContent: View, FalseContent: View>(first: TrueContent)
        -> _ConditionalContent<TrueContent, FalseContent> { _stub() }
    public static func buildEither<TrueContent: View, FalseContent: View>(second: FalseContent)
        -> _ConditionalContent<TrueContent, FalseContent> { _stub() }
    public static func buildLimitedAvailability<Content: View>(_ content: Content) -> AnyView { _stub() }
}

// MARK: - ViewModifier

@MainActor @preconcurrency
public protocol ViewModifier {
    associatedtype Body: View
    typealias Content = _ViewModifier_Content<Self>
    @ViewBuilder @MainActor @preconcurrency func body(content: Self.Content) -> Self.Body
}

public struct _ViewModifier_Content<Modifier: ViewModifier>: View {
    public typealias Body = Never
    public var body: Never { _stub() }
}

public struct EmptyModifier: ViewModifier {
    public static let identity = EmptyModifier()
    public init() {}
    public func body(content: Content) -> Content { content }
}

public struct ModifiedContent<Content, Modifier> {
    public var content: Content
    public var modifier: Modifier
    public init(content: Content, modifier: Modifier) { self.content = content; self.modifier = modifier }
}
extension ModifiedContent: View where Content: View, Modifier: ViewModifier {
    public typealias Body = Never
    public var body: Never { _stub() }
}
extension ModifiedContent: ViewModifier where Content: ViewModifier, Modifier: ViewModifier {
    public func body(content: _ViewModifier_Content<ModifiedContent<Content, Modifier>>) -> Never { _stub() }
}

extension View {
    public func modifier<T>(_ modifier: T) -> ModifiedContent<Self, T> { ModifiedContent(content: self, modifier: modifier) }
}
extension ViewModifier {
    public func concat<T>(_ modifier: T) -> ModifiedContent<Self, T> { _stub() }
}

/// Every stub modifier returns this; the real SDK returns assorted opaque `some View` types.
extension View {
    @inline(__always) func _modified() -> ModifiedContent<Self, EmptyModifier> {
        ModifiedContent(content: self, modifier: EmptyModifier())
    }
}

// MARK: - DynamicProperty & property wrappers

public protocol DynamicProperty {
    mutating func update()
}
extension DynamicProperty {
    public mutating func update() {}
}

@propertyWrapper
public struct State<Value>: DynamicProperty {
    public init(wrappedValue value: Value) { _stub() }
    public init(initialValue value: Value) { _stub() }
    public var wrappedValue: Value { get { _stub() } nonmutating set { _stub() } }
    public var projectedValue: Binding<Value> { _stub() }
}
extension State where Value: ExpressibleByNilLiteral {
    public init() { _stub() }
}

@propertyWrapper @dynamicMemberLookup
public struct Binding<Value> {
    public var transaction: Transaction { get { _stub() } set { _stub() } }
    public init(get: @escaping () -> Value, set: @escaping (Value) -> Void) { _stub() }
    public init(get: @escaping () -> Value, set: @escaping (Value, Transaction) -> Void) { _stub() }
    public init(projectedValue: Binding<Value>) { _stub() }
    public init<V>(_ base: Binding<V>) where Value == V? { _stub() }
    public init?(_ base: Binding<Value?>) { _stub() }
    public init<V: Hashable>(_ base: Binding<V>) where Value == AnyHashable { _stub() }
    public static func constant(_ value: Value) -> Binding<Value> { _stub() }
    public var wrappedValue: Value { get { _stub() } nonmutating set { _stub() } }
    public var projectedValue: Binding<Value> { _stub() }
    public subscript<Subject>(dynamicMember keyPath: WritableKeyPath<Value, Subject>) -> Binding<Subject> { _stub() }
    public func transaction(_ transaction: Transaction) -> Binding<Value> { _stub() }
    public func animation(_ animation: Animation? = .default) -> Binding<Value> { _stub() }
}
extension Binding: Identifiable where Value: Identifiable {
    public var id: Value.ID { _stub() }
}
extension Binding: DynamicProperty {}

@propertyWrapper @dynamicMemberLookup
public struct Bindable<Value> {
    public var wrappedValue: Value
    public var projectedValue: Bindable<Value> { _stub() }
    @available(*, unavailable, message: "The wrapped value must be an object that conforms to Observable")
    public init(wrappedValue: Value) { _stub() }
    @available(*, unavailable, message: "The wrapped value must be an object that conforms to Observable")
    public init(projectedValue: Bindable<Value>) { _stub() }
    public subscript<Subject>(dynamicMember keyPath: ReferenceWritableKeyPath<Value, Subject>) -> Binding<Subject>
        where Value: AnyObject { _stub() }
}
extension Bindable where Value: AnyObject, Value: Observable {
    public init(wrappedValue: Value) { _stub() }
    public init(_ wrappedValue: Value) { _stub() }
    public init(projectedValue: Bindable<Value>) { _stub() }
}
extension Bindable: Identifiable where Value: Identifiable {
    public var id: Value.ID { _stub() }
}
extension Bindable: DynamicProperty {}

@propertyWrapper
public struct StateObject<ObjectType: ObservableObject>: DynamicProperty {
    public init(wrappedValue thunk: @autoclosure @escaping () -> ObjectType) { _stub() }
    public var wrappedValue: ObjectType { _stub() }
    public var projectedValue: ObservedObject<ObjectType>.Wrapper { _stub() }
}

@propertyWrapper
public struct ObservedObject<ObjectType: ObservableObject>: DynamicProperty {
    @dynamicMemberLookup
    public struct Wrapper {
        public subscript<Subject>(dynamicMember keyPath: ReferenceWritableKeyPath<ObjectType, Subject>) -> Binding<Subject> { _stub() }
    }
    public init(initialValue: ObjectType) { _stub() }
    public init(wrappedValue: ObjectType) { _stub() }
    public var wrappedValue: ObjectType
    public var projectedValue: ObservedObject<ObjectType>.Wrapper { _stub() }
}

@propertyWrapper
public struct EnvironmentObject<ObjectType: ObservableObject>: DynamicProperty {
    @dynamicMemberLookup
    public struct Wrapper {
        public subscript<Subject>(dynamicMember keyPath: ReferenceWritableKeyPath<ObjectType, Subject>) -> Binding<Subject> { _stub() }
    }
    public init() { _stub() }
    public var wrappedValue: ObjectType { _stub() }
    public var projectedValue: EnvironmentObject<ObjectType>.Wrapper { _stub() }
}

@propertyWrapper
public struct Environment<Value>: DynamicProperty {
    public init(_ keyPath: KeyPath<EnvironmentValues, Value>) { _stub() }
    public var wrappedValue: Value { _stub() }
}
extension Environment where Value: AnyObject, Value: Observable {
    public init(_ objectType: Value.Type) { _stub() }
}
extension Environment {
    public init<T>(_ objectType: T.Type) where Value == T?, T: AnyObject, T: Observable { _stub() }
}

@propertyWrapper
public struct GestureState<Value>: DynamicProperty {
    public init(wrappedValue: Value) { _stub() }
    public init(initialValue: Value) { _stub() }
    public init(wrappedValue: Value, resetTransaction: Transaction) { _stub() }
    public var wrappedValue: Value { _stub() }
    public var projectedValue: GestureState<Value> { _stub() }
}
extension GestureState where Value: ExpressibleByNilLiteral {
    public init(resetTransaction: Transaction = Transaction()) { _stub() }
}

@propertyWrapper
public struct AppStorage<Value>: DynamicProperty {
    init(_stubOnly: Void) { _stub() }
    public var wrappedValue: Value { get { _stub() } nonmutating set { _stub() } }
    public var projectedValue: Binding<Value> { _stub() }
}
extension AppStorage {
    public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) where Value == Bool { _stub() }
    public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) where Value == Int { _stub() }
    public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) where Value == Double { _stub() }
    public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) where Value == String { _stub() }
    public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) where Value == URL { _stub() }
    public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) where Value == Data { _stub() }
    public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil)
        where Value: RawRepresentable, Value.RawValue == Int { _stub() }
    public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil)
        where Value: RawRepresentable, Value.RawValue == String { _stub() }
}

// MARK: - Environment

public protocol EnvironmentKey {
    associatedtype Value
    static var defaultValue: Self.Value { get }
}

public struct EnvironmentValues: CustomStringConvertible {
    public init() { _stub() }
    public subscript<K: EnvironmentKey>(key: K.Type) -> K.Value { get { _stub() } set { _stub() } }
    public var description: String { _stub() }

    public var scenePhase: ScenePhase { get { _stub() } set { _stub() } }
    public var dismiss: DismissAction { _stub() }
    public var openURL: OpenURLAction { get { _stub() } set { _stub() } }
    public var colorScheme: ColorScheme { get { _stub() } set { _stub() } }
    public var horizontalSizeClass: UserInterfaceSizeClass? { get { _stub() } set { _stub() } }
    public var verticalSizeClass: UserInterfaceSizeClass? { get { _stub() } set { _stub() } }
    public var displayScale: CGFloat { get { _stub() } set { _stub() } }
    public var pixelLength: CGFloat { _stub() }
    public var locale: Locale { get { _stub() } set { _stub() } }
    public var isEnabled: Bool { get { _stub() } set { _stub() } }
    public var isPresented: Bool { _stub() }
    public var layoutDirection: LayoutDirection { get { _stub() } set { _stub() } }
    public var accessibilityReduceMotion: Bool { _stub() }
}

public enum ScenePhase: Comparable, Hashable, Sendable { case background, inactive, active }
public enum ColorScheme: CaseIterable, Hashable, Sendable { case light, dark }
public enum UserInterfaceSizeClass: Hashable, Sendable { case compact, regular }
public enum LayoutDirection: Hashable, CaseIterable, Sendable { case leftToRight, rightToLeft }

@MainActor @preconcurrency
public struct DismissAction {
    public func callAsFunction() { _stub() }
}

@MainActor @preconcurrency
public struct OpenURLAction {
    public func callAsFunction(_ url: URL) { _stub() }
}

extension View {
    public func environment<V>(_ keyPath: WritableKeyPath<EnvironmentValues, V>, _ value: V) -> some View { _modified() }
    public func environment<T: AnyObject & Observable>(_ object: T?) -> some View { _modified() }
    public func environmentObject<T: ObservableObject>(_ object: T) -> some View { _modified() }
    public func transformEnvironment<V>(_ keyPath: WritableKeyPath<EnvironmentValues, V>,
                                        transform: @escaping (inout V) -> Void) -> some View { _modified() }
}

// MARK: - Transaction

public struct Transaction {
    public init() { _stub() }
    public init(animation: Animation?) { _stub() }
    public var animation: Animation? { get { _stub() } set { _stub() } }
    public var disablesAnimations: Bool { get { _stub() } set { _stub() } }
}

public func withTransaction<Result>(_ transaction: Transaction, _ body: () throws -> Result) rethrows -> Result { _stub() }

// MARK: - Previews (the #Preview macro cannot be stubbed; guard it with `#if !GEARFORGE_TYPECHECK`)

@MainActor @preconcurrency
public protocol PreviewProvider {
    associatedtype Previews: View
    @ViewBuilder @MainActor @preconcurrency static var previews: Self.Previews { get }
}
