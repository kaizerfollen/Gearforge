// API stub of Apple's Combine (subset) for the Linux typecheck harness. Signatures mirror the iOS 17/18 SDK.
// The real Publisher/Subscriber machinery is reduced to the declarations app code calls; `receive(subscriber:)`
// and Subscriber are omitted (app code should never implement a custom Publisher).
import Foundation

@inline(never) func _stub() -> Never { fatalError("Combine stub: typecheck only") }

public protocol Publisher<Output, Failure> {
    associatedtype Output
    associatedtype Failure: Error
}

public protocol Cancellable {
    func cancel()
}

public final class AnyCancellable: Cancellable, Hashable {
    public init(_ cancel: @escaping () -> Void) { _stub() }
    public init<C: Cancellable>(_ canceller: C) { _stub() }
    public func cancel() { _stub() }
    public func store<C: RangeReplaceableCollection>(in collection: inout C) where C.Element == AnyCancellable { _stub() }
    public func store(in set: inout Set<AnyCancellable>) { _stub() }
    public static func == (lhs: AnyCancellable, rhs: AnyCancellable) -> Bool { _stub() }
    public func hash(into hasher: inout Hasher) { _stub() }
}

extension Cancellable {
    public func store<C: RangeReplaceableCollection>(in collection: inout C) where C.Element == AnyCancellable { _stub() }
    public func store(in set: inout Set<AnyCancellable>) { _stub() }
}

public enum Subscribers {
    public enum Completion<Failure: Error> {
        case finished
        case failure(Failure)
    }
}

public protocol Subject<Output, Failure>: AnyObject, Publisher {
    func send(_ value: Output)
    func send(completion: Subscribers.Completion<Failure>)
}
extension Subject where Output == Void {
    public func send() { _stub() }
}

public final class PassthroughSubject<Output, Failure: Error>: Subject {
    public init() { _stub() }
    public func send(_ input: Output) { _stub() }
    public func send(completion: Subscribers.Completion<Failure>) { _stub() }
}

public final class CurrentValueSubject<Output, Failure: Error>: Subject {
    public init(_ value: Output) { _stub() }
    public var value: Output { get { _stub() } set { _stub() } }
    public func send(_ input: Output) { _stub() }
    public func send(completion: Subscribers.Completion<Failure>) { _stub() }
}

public struct AnyPublisher<Output, Failure: Error>: Publisher {
    public init<P: Publisher>(_ publisher: P) where Output == P.Output, Failure == P.Failure { _stub() }
}

public struct Just<Output>: Publisher {
    public typealias Failure = Never
    public init(_ output: Output) { _stub() }
}

public protocol ConnectablePublisher<Output, Failure>: Publisher {
    func connect() -> Cancellable
}
extension ConnectablePublisher {
    public func autoconnect() -> Publishers.Autoconnect<Self> { _stub() }
}

public protocol Scheduler {
    associatedtype SchedulerOptions
}
extension DispatchQueue: Scheduler {
    public struct SchedulerOptions {}
}
extension RunLoop: Scheduler {
    public struct SchedulerOptions {}
}
extension OperationQueue: Scheduler {
    public struct SchedulerOptions {}
}

public enum Publishers {
    public struct Map<Upstream: Publisher, Output>: Publisher {
        public typealias Failure = Upstream.Failure
    }
    public struct CompactMap<Upstream: Publisher, Output>: Publisher {
        public typealias Failure = Upstream.Failure
    }
    public struct Filter<Upstream: Publisher>: Publisher {
        public typealias Output = Upstream.Output
        public typealias Failure = Upstream.Failure
    }
    public struct RemoveDuplicates<Upstream: Publisher>: Publisher {
        public typealias Output = Upstream.Output
        public typealias Failure = Upstream.Failure
    }
    public struct ReceiveOn<Upstream: Publisher, Context: Scheduler>: Publisher {
        public typealias Output = Upstream.Output
        public typealias Failure = Upstream.Failure
    }
    public final class Autoconnect<Upstream: ConnectablePublisher>: Publisher {
        public typealias Output = Upstream.Output
        public typealias Failure = Upstream.Failure
        init() { _stub() }
    }
}

extension Publisher {
    public func map<T>(_ transform: @escaping (Output) -> T) -> Publishers.Map<Self, T> { _stub() }
    public func compactMap<T>(_ transform: @escaping (Output) -> T?) -> Publishers.CompactMap<Self, T> { _stub() }
    public func filter(_ isIncluded: @escaping (Output) -> Bool) -> Publishers.Filter<Self> { _stub() }
    public func receive<S: Scheduler>(on scheduler: S, options: S.SchedulerOptions? = nil)
        -> Publishers.ReceiveOn<Self, S> { _stub() }
    public func eraseToAnyPublisher() -> AnyPublisher<Output, Failure> { _stub() }
    public func sink(receiveCompletion: @escaping (Subscribers.Completion<Failure>) -> Void,
                     receiveValue: @escaping (Output) -> Void) -> AnyCancellable { _stub() }
}
extension Publisher where Output: Equatable {
    public func removeDuplicates() -> Publishers.RemoveDuplicates<Self> { _stub() }
}
extension Publisher where Failure == Never {
    public func sink(receiveValue: @escaping (Output) -> Void) -> AnyCancellable { _stub() }
    public func assign<Root>(to keyPath: ReferenceWritableKeyPath<Root, Output>, on object: Root) -> AnyCancellable { _stub() }
    public func assign(to published: inout Published<Output>.Publisher) { _stub() }
}

// MARK: - ObservableObject / @Published

public final class ObservableObjectPublisher: Publisher {
    public typealias Output = Void
    public typealias Failure = Never
    public init() { _stub() }
    public func send() { _stub() }
}

public protocol ObservableObject: AnyObject {
    associatedtype ObjectWillChangePublisher: Publisher = ObservableObjectPublisher
        where ObjectWillChangePublisher.Failure == Never
    var objectWillChange: ObjectWillChangePublisher { get }
}
extension ObservableObject where ObjectWillChangePublisher == ObservableObjectPublisher {
    public var objectWillChange: ObservableObjectPublisher { _stub() }
}

@propertyWrapper
public struct Published<Value> {
    public init(wrappedValue: Value) { _stub() }
    public init(initialValue: Value) { _stub() }

    public struct Publisher: Combine.Publisher {
        public typealias Output = Value
        public typealias Failure = Never
    }

    @available(*, unavailable, message: "@Published is only available on properties of classes")
    public var wrappedValue: Value { get { _stub() } set { _stub() } }

    public var projectedValue: Published<Value>.Publisher { mutating get { _stub() } set { _stub() } }

    public static subscript<EnclosingSelf: AnyObject>(
        _enclosingInstance object: EnclosingSelf,
        wrapped wrappedKeyPath: ReferenceWritableKeyPath<EnclosingSelf, Value>,
        storage storageKeyPath: ReferenceWritableKeyPath<EnclosingSelf, Published<Value>>
    ) -> Value {
        get { _stub() }
        set { _stub() }
    }
}

// MARK: - Foundation publishers (declared in Foundation's Combine overlay on Apple platforms)

extension NotificationCenter {
    public struct Publisher: Combine.Publisher {
        public typealias Output = Notification
        public typealias Failure = Never
        public init(center: NotificationCenter, name: Notification.Name, object: AnyObject? = nil) { _stub() }
    }
    public func publisher(for name: Notification.Name, object: AnyObject? = nil) -> NotificationCenter.Publisher { _stub() }
}

extension Timer {
    public final class TimerPublisher: ConnectablePublisher {
        public typealias Output = Date
        public typealias Failure = Never
        public init(interval: TimeInterval, tolerance: TimeInterval? = nil, runLoop: RunLoop, mode: RunLoop.Mode,
                    options: RunLoop.SchedulerOptions? = nil) { _stub() }
        public func connect() -> Cancellable { _stub() }
    }
    public static func publish(every interval: TimeInterval, tolerance: TimeInterval? = nil, on runLoop: RunLoop,
                               in mode: RunLoop.Mode, options: RunLoop.SchedulerOptions? = nil)
        -> Timer.TimerPublisher { _stub() }
}
