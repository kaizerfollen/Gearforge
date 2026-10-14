// SwiftUI stub — containers and controls.

// MARK: - Stacks & grids

public struct VStack<Content: View>: View {
    public typealias Body = Never
    public var body: Never { _stub() }
    public init(alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) { _stub() }
}
public struct HStack<Content: View>: View {
    public typealias Body = Never
    public var body: Never { _stub() }
    public init(alignment: VerticalAlignment = .center, spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) { _stub() }
}
public struct ZStack<Content: View>: View {
    public typealias Body = Never
    public var body: Never { _stub() }
    public init(alignment: Alignment = .center, @ViewBuilder content: () -> Content) { _stub() }
}
public struct LazyVStack<Content: View>: View {
    public typealias Body = Never
    public var body: Never { _stub() }
    public init(alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil,
                pinnedViews: PinnedScrollableViews = .init(), @ViewBuilder content: () -> Content) { _stub() }
}
public struct LazyHStack<Content: View>: View {
    public typealias Body = Never
    public var body: Never { _stub() }
    public init(alignment: VerticalAlignment = .center, spacing: CGFloat? = nil,
                pinnedViews: PinnedScrollableViews = .init(), @ViewBuilder content: () -> Content) { _stub() }
}
public struct LazyVGrid<Content: View>: View {
    public typealias Body = Never
    public var body: Never { _stub() }
    public init(columns: [GridItem], alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil,
                pinnedViews: PinnedScrollableViews = .init(), @ViewBuilder content: () -> Content) { _stub() }
}
public struct LazyHGrid<Content: View>: View {
    public typealias Body = Never
    public var body: Never { _stub() }
    public init(rows: [GridItem], alignment: VerticalAlignment = .center, spacing: CGFloat? = nil,
                pinnedViews: PinnedScrollableViews = .init(), @ViewBuilder content: () -> Content) { _stub() }
}
public struct Grid<Content: View>: View {
    public typealias Body = Never
    public var body: Never { _stub() }
    public init(alignment: Alignment = .center, horizontalSpacing: CGFloat? = nil, verticalSpacing: CGFloat? = nil,
                @ViewBuilder content: () -> Content) { _stub() }
}
public struct GridRow<Content: View>: View {
    public typealias Body = Never
    public var body: Never { _stub() }
    public init(alignment: VerticalAlignment? = nil, @ViewBuilder content: () -> Content) { _stub() }
}

public struct Spacer: View {
    public typealias Body = Never
    public var body: Never { _stub() }
    public var minLength: CGFloat?
    public init(minLength: CGFloat? = nil) { self.minLength = minLength }
}
public struct Divider: View {
    public typealias Body = Never
    public var body: Never { _stub() }
    public init() {}
}

public struct GeometryReader<Content: View>: View {
    public typealias Body = Never
    public var body: Never { _stub() }
    public var content: (GeometryProxy) -> Content
    public init(@ViewBuilder content: @escaping (GeometryProxy) -> Content) { self.content = content }
}

// MARK: - Scrolling

public struct ScrollView<Content: View>: View {
    public typealias Body = Never
    public var body: Never { _stub() }
    public init(_ axes: Axis.Set = .vertical, showsIndicators: Bool = true, @ViewBuilder content: () -> Content) { _stub() }
}

public struct ScrollViewProxy {
    public func scrollTo<ID: Hashable>(_ id: ID, anchor: UnitPoint? = nil) { _stub() }
}
public struct ScrollViewReader<Content: View>: View {
    public typealias Body = Never
    public var body: Never { _stub() }
    public init(@ViewBuilder content: @escaping (ScrollViewProxy) -> Content) { _stub() }
}

// MARK: - ForEach / List / Section

public struct ForEach<Data: RandomAccessCollection, ID: Hashable, Content> {
    public var data: Data
    public var content: (Data.Element) -> Content
}
extension ForEach: View where Content: View {
    public typealias Body = Never
    public var body: Never { _stub() }
}
extension ForEach where ID == Data.Element.ID, Content: View, Data.Element: Identifiable {
    public init(_ data: Data, @ViewBuilder content: @escaping (Data.Element) -> Content) { _stub() }
}
extension ForEach where Content: View {
    public init(_ data: Data, id: KeyPath<Data.Element, ID>, @ViewBuilder content: @escaping (Data.Element) -> Content) { _stub() }
    public init<C>(_ data: Binding<C>, @ViewBuilder content: @escaping (Binding<C.Element>) -> Content)
        where Data == LazyMapSequence<C.Indices, (C.Index, ID)>, ID == C.Element.ID, C: MutableCollection,
              C: RandomAccessCollection, C.Element: Identifiable, C.Index: Hashable { _stub() }
    public init<C>(_ data: Binding<C>, id: KeyPath<C.Element, ID>,
                   @ViewBuilder content: @escaping (Binding<C.Element>) -> Content)
        where Data == LazyMapSequence<C.Indices, (C.Index, ID)>, C: MutableCollection, C: RandomAccessCollection,
              C.Index: Hashable { _stub() }
}
extension ForEach where Data == Range<Int>, ID == Int, Content: View {
    public init(_ data: Range<Int>, @ViewBuilder content: @escaping (Int) -> Content) { _stub() }
}

public struct List<SelectionValue: Hashable, Content: View>: View {
    public typealias Body = Never
    public var body: Never { _stub() }
    public init(selection: Binding<SelectionValue?>?, @ViewBuilder content: () -> Content) { _stub() }
    public init(selection: Binding<Set<SelectionValue>>?, @ViewBuilder content: () -> Content) { _stub() }
}
extension List where SelectionValue == Never {
    public init(@ViewBuilder content: () -> Content) { _stub() }
    public init<Data, RowContent>(_ data: Data, @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent)
        where Content == ForEach<Data, Data.Element.ID, RowContent>, Data: RandomAccessCollection, RowContent: View,
              Data.Element: Identifiable { _stub() }
    public init<Data, ID, RowContent>(_ data: Data, id: KeyPath<Data.Element, ID>,
                                      @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent)
        where Content == ForEach<Data, ID, RowContent>, Data: RandomAccessCollection, ID: Hashable, RowContent: View { _stub() }
}

public struct Section<Parent, Content, Footer> {}
extension Section: View where Parent: View, Content: View, Footer: View {
    public typealias Body = Never
    public var body: Never { _stub() }
    public init(@ViewBuilder content: () -> Content, @ViewBuilder header: () -> Parent, @ViewBuilder footer: () -> Footer) { _stub() }
    public init(header: Parent, footer: Footer, @ViewBuilder content: () -> Content) { _stub() }
}
extension Section where Parent: View, Content: View, Footer == EmptyView {
    public init(@ViewBuilder content: () -> Content, @ViewBuilder header: () -> Parent) { _stub() }
    public init(header: Parent, @ViewBuilder content: () -> Content) { _stub() }
}
extension Section where Parent == EmptyView, Content: View, Footer: View {
    public init(@ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer) { _stub() }
    public init(footer: Footer, @ViewBuilder content: () -> Content) { _stub() }
}
extension Section where Parent == EmptyView, Content: View, Footer == EmptyView {
    public init(@ViewBuilder content: () -> Content) { _stub() }
}
extension Section where Parent == Text, Content: View, Footer == EmptyView {
    public init(_ titleKey: LocalizedStringKey, @ViewBuilder content: () -> Content) { _stub() }
    @_disfavoredOverload public init<S: StringProtocol>(_ title: S, @ViewBuilder content: () -> Content) { _stub() }
}

// MARK: - Label

public struct Label<Title: View, Icon: View>: View {
    public typealias Body = Never
    public var body: Never { _stub() }
    public init(@ViewBuilder title: () -> Title, @ViewBuilder icon: () -> Icon) { _stub() }
}
extension Label where Title == Text, Icon == Image {
    public init(_ titleKey: LocalizedStringKey, image name: String) { _stub() }
    public init(_ titleKey: LocalizedStringKey, systemImage name: String) { _stub() }
    @_disfavoredOverload public init<S: StringProtocol>(_ title: S, image name: String) { _stub() }
    @_disfavoredOverload public init<S: StringProtocol>(_ title: S, systemImage name: String) { _stub() }
}

// MARK: - Button & styles

public struct ButtonRole: Equatable, Sendable {
    public static let destructive = ButtonRole(), cancel = ButtonRole()
    public static func == (a: Self, b: Self) -> Bool { _stub() }
}

public struct Button<Label: View>: View {
    public typealias Body = Never
    public var body: Never { _stub() }
    public init(action: @escaping @MainActor () -> Void, @ViewBuilder label: () -> Label) { _stub() }
    public init(role: ButtonRole?, action: @escaping @MainActor () -> Void, @ViewBuilder label: () -> Label) { _stub() }
}
extension Button where Label == Text {
    public init(_ titleKey: LocalizedStringKey, action: @escaping @MainActor () -> Void) { _stub() }
    @_disfavoredOverload public init<S: StringProtocol>(_ title: S, action: @escaping @MainActor () -> Void) { _stub() }
    public init(_ titleKey: LocalizedStringKey, role: ButtonRole?, action: @escaping @MainActor () -> Void) { _stub() }
    @_disfavoredOverload public init<S: StringProtocol>(_ title: S, role: ButtonRole?, action: @escaping @MainActor () -> Void) { _stub() }
}
extension Button where Label == SwiftUI.Label<Text, Image> {
    public init(_ titleKey: LocalizedStringKey, systemImage: String, action: @escaping @MainActor () -> Void) { _stub() }
    @_disfavoredOverload public init<S: StringProtocol>(_ title: S, systemImage: String, action: @escaping @MainActor () -> Void) { _stub() }
}

public struct ButtonStyleConfiguration {
    public struct Label: View {
        public typealias Body = Never
        public var body: Never { _stub() }
    }
    public let role: ButtonRole?
    public let label: ButtonStyleConfiguration.Label
    public let isPressed: Bool
}

@MainActor @preconcurrency
public protocol ButtonStyle {
    associatedtype Body: View
    typealias Configuration = ButtonStyleConfiguration
    @ViewBuilder @MainActor @preconcurrency func makeBody(configuration: Self.Configuration) -> Self.Body
}

public struct PrimitiveButtonStyleConfiguration {
    public struct Label: View {
        public typealias Body = Never
        public var body: Never { _stub() }
    }
    public let role: ButtonRole?
    public let label: PrimitiveButtonStyleConfiguration.Label
    public func trigger() { _stub() }
}

@MainActor @preconcurrency
public protocol PrimitiveButtonStyle {
    associatedtype Body: View
    typealias Configuration = PrimitiveButtonStyleConfiguration
    @ViewBuilder @MainActor @preconcurrency func makeBody(configuration: Self.Configuration) -> Self.Body
}

public struct PlainButtonStyle: PrimitiveButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View { configuration.label }
}
public struct BorderlessButtonStyle: PrimitiveButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View { configuration.label }
}
public struct BorderedButtonStyle: PrimitiveButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View { configuration.label }
}
public struct BorderedProminentButtonStyle: PrimitiveButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View { configuration.label }
}
public struct DefaultButtonStyle: PrimitiveButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View { configuration.label }
}
extension PrimitiveButtonStyle where Self == PlainButtonStyle { public static var plain: PlainButtonStyle { PlainButtonStyle() } }
extension PrimitiveButtonStyle where Self == BorderlessButtonStyle { public static var borderless: BorderlessButtonStyle { BorderlessButtonStyle() } }
extension PrimitiveButtonStyle where Self == BorderedButtonStyle { public static var bordered: BorderedButtonStyle { BorderedButtonStyle() } }
extension PrimitiveButtonStyle where Self == BorderedProminentButtonStyle {
    public static var borderedProminent: BorderedProminentButtonStyle { BorderedProminentButtonStyle() }
}
extension PrimitiveButtonStyle where Self == DefaultButtonStyle { public static var automatic: DefaultButtonStyle { DefaultButtonStyle() } }

extension View {
    public func buttonStyle<S: ButtonStyle>(_ style: S) -> some View { _modified() }
    public func buttonStyle<S: PrimitiveButtonStyle>(_ style: S) -> some View { _modified() }
}

// MARK: - Toggle / Slider / Stepper / Picker / ProgressView / TextField

public struct Toggle<Label: View>: View {
    public typealias Body = Never
    public var body: Never { _stub() }
    public init(isOn: Binding<Bool>, @ViewBuilder label: () -> Label) { _stub() }
}
extension Toggle where Label == Text {
    public init(_ titleKey: LocalizedStringKey, isOn: Binding<Bool>) { _stub() }
    @_disfavoredOverload public init<S: StringProtocol>(_ title: S, isOn: Binding<Bool>) { _stub() }
}

public struct Slider<Label: View, ValueLabel: View>: View {
    public typealias Body = Never
    public var body: Never { _stub() }
}
extension Slider where Label == EmptyView, ValueLabel == EmptyView {
    public init<V: BinaryFloatingPoint>(value: Binding<V>, in bounds: ClosedRange<V> = 0...1,
                                        onEditingChanged: @escaping (Bool) -> Void = { _ in }) where V.Stride: BinaryFloatingPoint { _stub() }
    public init<V: BinaryFloatingPoint>(value: Binding<V>, in bounds: ClosedRange<V>, step: V.Stride = 1,
                                        onEditingChanged: @escaping (Bool) -> Void = { _ in }) where V.Stride: BinaryFloatingPoint { _stub() }
}
extension Slider where ValueLabel == EmptyView {
    public init<V: BinaryFloatingPoint>(value: Binding<V>, in bounds: ClosedRange<V> = 0...1, @ViewBuilder label: () -> Label,
                                        onEditingChanged: @escaping (Bool) -> Void = { _ in }) where V.Stride: BinaryFloatingPoint { _stub() }
}

public struct Stepper<Label: View>: View {
    public typealias Body = Never
    public var body: Never { _stub() }
    public init(@ViewBuilder label: () -> Label, onIncrement: (() -> Void)?, onDecrement: (() -> Void)?,
                onEditingChanged: @escaping (Bool) -> Void = { _ in }) { _stub() }
    public init<V: Strideable>(value: Binding<V>, in bounds: ClosedRange<V>, step: V.Stride = 1,
                               @ViewBuilder label: () -> Label, onEditingChanged: @escaping (Bool) -> Void = { _ in }) { _stub() }
    public init<V: Strideable>(value: Binding<V>, step: V.Stride = 1, @ViewBuilder label: () -> Label,
                               onEditingChanged: @escaping (Bool) -> Void = { _ in }) { _stub() }
}
extension Stepper where Label == Text {
    public init(_ titleKey: LocalizedStringKey, onIncrement: (() -> Void)?, onDecrement: (() -> Void)?,
                onEditingChanged: @escaping (Bool) -> Void = { _ in }) { _stub() }
    public init<V: Strideable>(_ titleKey: LocalizedStringKey, value: Binding<V>, in bounds: ClosedRange<V>, step: V.Stride = 1,
                               onEditingChanged: @escaping (Bool) -> Void = { _ in }) { _stub() }
    public init<V: Strideable>(_ titleKey: LocalizedStringKey, value: Binding<V>, step: V.Stride = 1,
                               onEditingChanged: @escaping (Bool) -> Void = { _ in }) { _stub() }
    @_disfavoredOverload
    public init<S: StringProtocol, V: Strideable>(_ title: S, value: Binding<V>, in bounds: ClosedRange<V>, step: V.Stride = 1,
                                                  onEditingChanged: @escaping (Bool) -> Void = { _ in }) { _stub() }
    @_disfavoredOverload
    public init<S: StringProtocol, V: Strideable>(_ title: S, value: Binding<V>, step: V.Stride = 1,
                                                  onEditingChanged: @escaping (Bool) -> Void = { _ in }) { _stub() }
}

public struct Picker<Label: View, SelectionValue: Hashable, Content: View>: View {
    public typealias Body = Never
    public var body: Never { _stub() }
    public init(selection: Binding<SelectionValue>, @ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) { _stub() }
}
extension Picker where Label == Text {
    public init(_ titleKey: LocalizedStringKey, selection: Binding<SelectionValue>, @ViewBuilder content: () -> Content) { _stub() }
    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, selection: Binding<SelectionValue>, @ViewBuilder content: () -> Content) { _stub() }
}

@MainActor @preconcurrency public protocol PickerStyle {}
public struct DefaultPickerStyle: PickerStyle { public init() {} }
public struct SegmentedPickerStyle: PickerStyle { public init() {} }
public struct MenuPickerStyle: PickerStyle { public init() {} }
public struct WheelPickerStyle: PickerStyle { public init() {} }
public struct InlinePickerStyle: PickerStyle { public init() {} }
extension PickerStyle where Self == DefaultPickerStyle { public static var automatic: DefaultPickerStyle { .init() } }
extension PickerStyle where Self == SegmentedPickerStyle { public static var segmented: SegmentedPickerStyle { .init() } }
extension PickerStyle where Self == MenuPickerStyle { public static var menu: MenuPickerStyle { .init() } }
extension PickerStyle where Self == WheelPickerStyle { public static var wheel: WheelPickerStyle { .init() } }
extension PickerStyle where Self == InlinePickerStyle { public static var inline: InlinePickerStyle { .init() } }
extension View {
    public func pickerStyle<S: PickerStyle>(_ style: S) -> some View { _modified() }
    public func tag<V: Hashable>(_ tag: V) -> some View { _modified() }
}

public struct ProgressView<Label: View, CurrentValueLabel: View>: View {
    public typealias Body = Never
    public var body: Never { _stub() }
}
extension ProgressView where CurrentValueLabel == EmptyView {
    public init() where Label == EmptyView { _stub() }
    public init(_ titleKey: LocalizedStringKey) where Label == Text { _stub() }
    public init<V: BinaryFloatingPoint>(value: V?, total: V = 1.0) where Label == EmptyView { _stub() }
    public init<V: BinaryFloatingPoint>(_ titleKey: LocalizedStringKey, value: V?, total: V = 1.0) where Label == Text { _stub() }
    @_disfavoredOverload
    public init<S: StringProtocol, V: BinaryFloatingPoint>(_ title: S, value: V?, total: V = 1.0) where Label == Text { _stub() }
}
@MainActor @preconcurrency public protocol ProgressViewStyle {}
public struct LinearProgressViewStyle: ProgressViewStyle { public init() {} }
public struct CircularProgressViewStyle: ProgressViewStyle { public init() {} }
extension ProgressViewStyle where Self == LinearProgressViewStyle { public static var linear: LinearProgressViewStyle { .init() } }
extension ProgressViewStyle where Self == CircularProgressViewStyle { public static var circular: CircularProgressViewStyle { .init() } }
extension View {
    public func progressViewStyle<S: ProgressViewStyle>(_ style: S) -> some View { _modified() }
}

public struct TextField<Label: View>: View {
    public typealias Body = Never
    public var body: Never { _stub() }
}
extension TextField where Label == Text {
    public init(_ titleKey: LocalizedStringKey, text: Binding<String>) { _stub() }
    public init(_ titleKey: LocalizedStringKey, text: Binding<String>, prompt: Text?) { _stub() }
    @_disfavoredOverload public init<S: StringProtocol>(_ title: S, text: Binding<String>) { _stub() }
}
@MainActor @preconcurrency public protocol TextFieldStyle {}
public struct RoundedBorderTextFieldStyle: TextFieldStyle { public init() {} }
public struct PlainTextFieldStyle: TextFieldStyle { public init() {} }
extension TextFieldStyle where Self == RoundedBorderTextFieldStyle { public static var roundedBorder: RoundedBorderTextFieldStyle { .init() } }
extension TextFieldStyle where Self == PlainTextFieldStyle { public static var plain: PlainTextFieldStyle { .init() } }
extension View {
    public func textFieldStyle<S: TextFieldStyle>(_ style: S) -> some View { _modified() }
}

// MARK: - Navigation

public struct NavigationPath: Equatable {
    public init() {}
    public var count: Int { _stub() }
    public var isEmpty: Bool { _stub() }
    public mutating func append<V: Hashable>(_ value: V) { _stub() }
    public mutating func removeLast(_ k: Int = 1) { _stub() }
}

public struct NavigationStack<Data, Root: View>: View {
    public typealias Body = Never
    public var body: Never { _stub() }
    public init(@ViewBuilder root: () -> Root) where Data == NavigationPath { _stub() }
    public init(path: Binding<NavigationPath>, @ViewBuilder root: () -> Root) where Data == NavigationPath { _stub() }
    public init(path: Binding<Data>, @ViewBuilder root: () -> Root)
        where Data: MutableCollection, Data: RandomAccessCollection, Data: RangeReplaceableCollection,
              Data.Element: Hashable { _stub() }
}

public struct NavigationLink<Label: View, Destination: View>: View {
    public typealias Body = Never
    public var body: Never { _stub() }
    public init(@ViewBuilder destination: () -> Destination, @ViewBuilder label: () -> Label) { _stub() }
    public init<P: Hashable>(value: P?, @ViewBuilder label: () -> Label) where Destination == Never { _stub() }
}
extension NavigationLink where Label == Text {
    public init(_ titleKey: LocalizedStringKey, @ViewBuilder destination: () -> Destination) { _stub() }
    @_disfavoredOverload public init<S: StringProtocol>(_ title: S, @ViewBuilder destination: () -> Destination) { _stub() }
    public init<P: Hashable>(_ titleKey: LocalizedStringKey, value: P?) where Destination == Never { _stub() }
}

public enum NavigationBarItem {
    public enum TitleDisplayMode: Sendable { case automatic, inline, large }
}

extension View {
    public func navigationTitle(_ title: Text) -> some View { _modified() }
    public func navigationTitle(_ titleKey: LocalizedStringKey) -> some View { _modified() }
    @_disfavoredOverload public func navigationTitle<S: StringProtocol>(_ title: S) -> some View { _modified() }
    public func navigationBarTitleDisplayMode(_ displayMode: NavigationBarItem.TitleDisplayMode) -> some View { _modified() }
    public func navigationBarBackButtonHidden(_ hidesBackButton: Bool = true) -> some View { _modified() }
    public func navigationDestination<D: Hashable, C: View>(for data: D.Type,
                                                            @ViewBuilder destination: @escaping (D) -> C) -> some View { _modified() }
    public func navigationDestination<V: View>(isPresented: Binding<Bool>, @ViewBuilder destination: () -> V) -> some View { _modified() }
    public func toolbar<Content: View>(@ViewBuilder content: () -> Content) -> some View { _modified() }
    public func toolbar(_ visibility: Visibility, for bars: ToolbarPlacement...) -> some View { _modified() }
}
public struct ToolbarPlacement {
    public static let automatic = ToolbarPlacement(), navigationBar = ToolbarPlacement(), tabBar = ToolbarPlacement()
}

// MARK: - TimelineView

public protocol TimelineSchedule {}
public struct AnimationTimelineSchedule: TimelineSchedule {
    public init(minimumInterval: Double? = nil, paused: Bool = false) {}
}
public struct PeriodicTimelineSchedule: TimelineSchedule {
    public init(from startDate: Date, by interval: TimeInterval) {}
}
extension TimelineSchedule where Self == AnimationTimelineSchedule {
    public static var animation: AnimationTimelineSchedule { .init() }
    public static func animation(minimumInterval: Double? = nil, paused: Bool = false) -> AnimationTimelineSchedule { .init() }
}
extension TimelineSchedule where Self == PeriodicTimelineSchedule {
    public static func periodic(from startDate: Date, by interval: TimeInterval) -> PeriodicTimelineSchedule { .init(from: startDate, by: interval) }
}

public struct TimelineViewDefaultContext {
    public enum Cadence: Comparable, Sendable { case live, seconds, minutes }
    public let date: Date
    public let cadence: Cadence
}

public struct TimelineView<Schedule: TimelineSchedule, Content> {
    public typealias Context = TimelineViewDefaultContext
}
extension TimelineView: View where Content: View {
    public typealias Body = Never
    public var body: Never { _stub() }
    public init(_ schedule: Schedule, @ViewBuilder content: @escaping (TimelineViewDefaultContext) -> Content) { _stub() }
}

public struct ViewThatFits<Content: View>: View {
    public typealias Body = Never
    public var body: Never { _stub() }
    public init(in axes: Axis.Set = [.horizontal, .vertical], @ViewBuilder content: () -> Content) { _stub() }
}
