// SwiftUI stub — App, Scene, WindowGroup.

@MainActor @preconcurrency
public protocol App {
    associatedtype Body: Scene
    @SceneBuilder @MainActor @preconcurrency var body: Self.Body { get }
    @MainActor @preconcurrency init()
}
extension App {
    @MainActor @preconcurrency public static func main() { _stub() }
}

@MainActor @preconcurrency
public protocol Scene {
    associatedtype Body: Scene
    @SceneBuilder @MainActor @preconcurrency var body: Self.Body { get }
}

extension Never: Scene {}

public struct _TupleScene<T>: Scene {
    public typealias Body = Never
    public var body: Never { _stub() }
}

@resultBuilder
public struct SceneBuilder {
    public static func buildExpression<Content: Scene>(_ content: Content) -> Content { content }
    public static func buildBlock<Content: Scene>(_ content: Content) -> Content { content }
    public static func buildBlock<each Content: Scene>(_ content: repeat each Content) -> _TupleScene<(repeat each Content)> { _stub() }
}

public struct WindowGroup<Content: View>: Scene {
    public typealias Body = Never
    public init(@ViewBuilder content: () -> Content) { _stub() }
    public init(id: String, @ViewBuilder content: () -> Content) { _stub() }
    public init(_ title: Text, @ViewBuilder content: () -> Content) { _stub() }
    public init(_ titleKey: LocalizedStringKey, @ViewBuilder content: () -> Content) { _stub() }
    public var body: Never { _stub() }
}

extension Scene {
    public func onChange<V: Equatable>(of value: V, initial: Bool = false,
                                       _ action: @escaping (_ oldValue: V, _ newValue: V) -> Void) -> some Scene { _stubScene() }
    public func onChange<V: Equatable>(of value: V, initial: Bool = false,
                                       _ action: @escaping () -> Void) -> some Scene { _stubScene() }
    @inline(__always) func _stubScene() -> _TupleScene<Self> { _stub() }
}
