// SwiftUI stub — View modifiers (layout, appearance, lifecycle, presentation). The real SDK returns assorted opaque
// types; every stub returns `some View` backed by ModifiedContent, except where the SDK returns a concrete type
// that callers rely on (Text/Image/Shape modifiers live with those types).

extension View {
    // MARK: Frame & layout
    @available(*, deprecated, message: "Please pass one or more parameters.")
    public func frame() -> some View { _modified() }
    public func frame(width: CGFloat? = nil, height: CGFloat? = nil, alignment: Alignment = .center) -> some View { _modified() }
    public func frame(minWidth: CGFloat? = nil, idealWidth: CGFloat? = nil, maxWidth: CGFloat? = nil,
                      minHeight: CGFloat? = nil, idealHeight: CGFloat? = nil, maxHeight: CGFloat? = nil,
                      alignment: Alignment = .center) -> some View { _modified() }
    public func padding(_ insets: EdgeInsets) -> some View { _modified() }
    public func padding(_ edges: Edge.Set = .all, _ length: CGFloat? = nil) -> some View { _modified() }
    public func padding(_ length: CGFloat) -> some View { _modified() }
    public func offset(_ offset: CGSize) -> some View { _modified() }
    public func offset(x: CGFloat = 0, y: CGFloat = 0) -> some View { _modified() }
    public func position(_ position: CGPoint) -> some View { _modified() }
    public func position(x: CGFloat = 0, y: CGFloat = 0) -> some View { _modified() }
    public func fixedSize() -> some View { _modified() }
    public func fixedSize(horizontal: Bool, vertical: Bool) -> some View { _modified() }
    public func aspectRatio(_ aspectRatio: CGFloat? = nil, contentMode: ContentMode) -> some View { _modified() }
    public func aspectRatio(_ aspectRatio: CGSize, contentMode: ContentMode) -> some View { _modified() }
    public func scaledToFit() -> some View { _modified() }
    public func scaledToFill() -> some View { _modified() }
    public func layoutPriority(_ value: Double) -> some View { _modified() }
    public func zIndex(_ value: Double) -> some View { _modified() }
    public func id<ID: Hashable>(_ id: ID) -> some View { _modified() }
    public func coordinateSpace<T: Hashable>(name: T) -> some View { _modified() }
    public func ignoresSafeArea(_ regions: SafeAreaRegions = .all, edges: Edge.Set = .all) -> some View { _modified() }
    public func safeAreaInset<V: View>(edge: VerticalEdge, alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil,
                                       @ViewBuilder content: () -> V) -> some View { _modified() }
    public func safeAreaInset<V: View>(edge: HorizontalEdge, alignment: VerticalAlignment = .center, spacing: CGFloat? = nil,
                                       @ViewBuilder content: () -> V) -> some View { _modified() }
    public func safeAreaPadding(_ edges: Edge.Set = .all, _ length: CGFloat? = nil) -> some View { _modified() }

    // MARK: Background / overlay / clipping
    public func background<S: ShapeStyle>(_ style: S, ignoresSafeAreaEdges edges: Edge.Set = .all) -> some View { _modified() }
    public func background<V: View>(alignment: Alignment = .center, @ViewBuilder content: () -> V) -> some View { _modified() }
    public func background(ignoresSafeAreaEdges edges: Edge.Set = .all) -> some View { _modified() }
    public func background<S: ShapeStyle, T: Shape>(_ style: S, in shape: T, fillStyle: FillStyle = FillStyle()) -> some View { _modified() }
    public func background<S: Shape>(in shape: S, fillStyle: FillStyle = FillStyle()) -> some View { _modified() }
    @_disfavoredOverload
    public func background<Background: View>(_ background: Background, alignment: Alignment = .center) -> some View { _modified() }
    public func overlay<V: View>(alignment: Alignment = .center, @ViewBuilder content: () -> V) -> some View { _modified() }
    public func overlay<S: ShapeStyle>(_ style: S, ignoresSafeAreaEdges edges: Edge.Set = .all) -> some View { _modified() }
    public func overlay<S: ShapeStyle, T: Shape>(_ style: S, in shape: T, fillStyle: FillStyle = FillStyle()) -> some View { _modified() }
    @_disfavoredOverload
    public func overlay<Overlay: View>(_ overlay: Overlay, alignment: Alignment = .center) -> some View { _modified() }
    public func border<S: ShapeStyle>(_ content: S, width: CGFloat = 1) -> some View { _modified() }
    public func cornerRadius(_ radius: CGFloat, antialiased: Bool = true) -> some View { _modified() }
    public func clipShape<S: Shape>(_ shape: S, style: FillStyle = FillStyle()) -> some View { _modified() }
    public func clipped(antialiased: Bool = false) -> some View { _modified() }
    public func mask<Mask: View>(alignment: Alignment = .center, @ViewBuilder _ mask: () -> Mask) -> some View { _modified() }
    public func contentShape<S: Shape>(_ shape: S, eoFill: Bool = false) -> some View { _modified() }

    // MARK: Appearance
    public func foregroundColor(_ color: Color?) -> some View { _modified() }
    public func foregroundStyle<S: ShapeStyle>(_ style: S) -> some View { _modified() }
    public func foregroundStyle<S1: ShapeStyle, S2: ShapeStyle>(_ primary: S1, _ secondary: S2) -> some View { _modified() }
    public func tint(_ tint: Color?) -> some View { _modified() }
    public func tint<S: ShapeStyle>(_ tint: S?) -> some View { _modified() }
    public func accentColor(_ accentColor: Color?) -> some View { _modified() }
    public func opacity(_ opacity: Double) -> some View { _modified() }
    public func shadow(color: Color = Color(.sRGBLinear, white: 0, opacity: 0.33), radius: CGFloat,
                       x: CGFloat = 0, y: CGFloat = 0) -> some View { _modified() }
    public func blur(radius: CGFloat, opaque: Bool = false) -> some View { _modified() }
    public func brightness(_ amount: Double) -> some View { _modified() }
    public func contrast(_ amount: Double) -> some View { _modified() }
    public func saturation(_ amount: Double) -> some View { _modified() }
    public func grayscale(_ amount: Double) -> some View { _modified() }
    public func colorMultiply(_ color: Color) -> some View { _modified() }
    public func colorInvert() -> some View { _modified() }
    public func hueRotation(_ angle: Angle) -> some View { _modified() }
    public func blendMode(_ blendMode: BlendMode) -> some View { _modified() }
    public func compositingGroup() -> some View { _modified() }
    public func drawingGroup(opaque: Bool = false, colorMode: ColorRenderingMode = .nonLinear) -> some View { _modified() }
    public func scaleEffect(_ scale: CGSize, anchor: UnitPoint = .center) -> some View { _modified() }
    public func scaleEffect(_ s: CGFloat, anchor: UnitPoint = .center) -> some View { _modified() }
    public func scaleEffect(x: CGFloat = 1.0, y: CGFloat = 1.0, anchor: UnitPoint = .center) -> some View { _modified() }
    public func rotationEffect(_ angle: Angle, anchor: UnitPoint = .center) -> some View { _modified() }
    public func rotation3DEffect(_ angle: Angle, axis: (x: CGFloat, y: CGFloat, z: CGFloat), anchor: UnitPoint = .center,
                                 anchorZ: CGFloat = 0, perspective: CGFloat = 1) -> some View { _modified() }
    public func hidden() -> some View { _modified() }
    public func preferredColorScheme(_ colorScheme: ColorScheme?) -> some View { _modified() }

    // MARK: Text-related (environment-propagating)
    public func font(_ font: Font?) -> some View { _modified() }
    public func fontWeight(_ weight: Font.Weight?) -> some View { _modified() }
    public func fontDesign(_ design: Font.Design?) -> some View { _modified() }
    public func bold(_ isActive: Bool = true) -> some View { _modified() }
    public func italic(_ isActive: Bool = true) -> some View { _modified() }
    public func monospacedDigit() -> some View { _modified() }
    public func monospaced(_ isActive: Bool = true) -> some View { _modified() }
    public func lineLimit(_ number: Int?) -> some View { _modified() }
    public func lineLimit(_ limit: ClosedRange<Int>) -> some View { _modified() }
    public func lineSpacing(_ lineSpacing: CGFloat) -> some View { _modified() }
    public func multilineTextAlignment(_ alignment: TextAlignment) -> some View { _modified() }
    public func minimumScaleFactor(_ factor: CGFloat) -> some View { _modified() }
    public func truncationMode(_ mode: Text.TruncationMode) -> some View { _modified() }
    public func textCase(_ textCase: Text.Case?) -> some View { _modified() }
    public func kerning(_ kerning: CGFloat) -> some View { _modified() }
    public func tracking(_ tracking: CGFloat) -> some View { _modified() }
    public func labelsHidden() -> some View { _modified() }

    // MARK: Interaction
    public func disabled(_ disabled: Bool) -> some View { _modified() }
    public func allowsHitTesting(_ enabled: Bool) -> some View { _modified() }

    // MARK: Lifecycle
    public func onAppear(perform action: (() -> Void)? = nil) -> some View { _modified() }
    public func onDisappear(perform action: (() -> Void)? = nil) -> some View { _modified() }
    @available(*, deprecated, message: "(iOS 17) Use `onChange` with a two or zero parameter action closure instead.")
    public func onChange<V: Equatable>(of value: V, perform action: @escaping (_ newValue: V) -> Void) -> some View { _modified() }
    public func onChange<V: Equatable>(of value: V, initial: Bool = false,
                                       _ action: @escaping (_ oldValue: V, _ newValue: V) -> Void) -> some View { _modified() }
    public func onChange<V: Equatable>(of value: V, initial: Bool = false, _ action: @escaping () -> Void) -> some View { _modified() }
    public func task(priority: TaskPriority = .userInitiated,
                     @_inheritActorContext _ action: @escaping @Sendable () async -> Void) -> some View { _modified() }
    public func task<T: Equatable>(id value: T, priority: TaskPriority = .userInitiated,
                                   @_inheritActorContext _ action: @escaping @Sendable () async -> Void) -> some View { _modified() }
    public func onReceive<P: Publisher>(_ publisher: P, perform action: @escaping (P.Output) -> Void) -> some View
        where P.Failure == Never { _modified() }

    // MARK: System chrome
    public func statusBarHidden(_ hidden: Bool = true) -> some View { _modified() }
    public func persistentSystemOverlays(_ visibility: Visibility) -> some View { _modified() }
    public func defersSystemGestures(on edges: Edge.Set) -> some View { _modified() }

    // MARK: Accessibility
    public func accessibilityLabel(_ label: Text) -> some View { _modified() }
    public func accessibilityLabel(_ labelKey: LocalizedStringKey) -> some View { _modified() }
    @_disfavoredOverload public func accessibilityLabel<S: StringProtocol>(_ label: S) -> some View { _modified() }
    public func accessibilityHidden(_ hidden: Bool) -> some View { _modified() }

    // MARK: Presentation
    public func sheet<Content: View>(isPresented: Binding<Bool>, onDismiss: (() -> Void)? = nil,
                                     @ViewBuilder content: @escaping () -> Content) -> some View { _modified() }
    public func sheet<Item: Identifiable, Content: View>(item: Binding<Item?>, onDismiss: (() -> Void)? = nil,
                                                         @ViewBuilder content: @escaping (Item) -> Content) -> some View { _modified() }
    public func fullScreenCover<Content: View>(isPresented: Binding<Bool>, onDismiss: (() -> Void)? = nil,
                                               @ViewBuilder content: @escaping () -> Content) -> some View { _modified() }
    public func fullScreenCover<Item: Identifiable, Content: View>(item: Binding<Item?>, onDismiss: (() -> Void)? = nil,
                                                                   @ViewBuilder content: @escaping (Item) -> Content) -> some View { _modified() }
    public func popover<Content: View>(isPresented: Binding<Bool>, attachmentAnchor: PopoverAttachmentAnchor = .rect(.bounds),
                                       arrowEdge: Edge = .top, @ViewBuilder content: @escaping () -> Content) -> some View { _modified() }
    public func presentationDetents(_ detents: Set<PresentationDetent>) -> some View { _modified() }
    public func presentationDragIndicator(_ visibility: Visibility) -> some View { _modified() }
    public func presentationBackground<S: ShapeStyle>(_ style: S) -> some View { _modified() }
    public func interactiveDismissDisabled(_ isDisabled: Bool = true) -> some View { _modified() }

    public func alert<A: View>(_ titleKey: LocalizedStringKey, isPresented: Binding<Bool>,
                               @ViewBuilder actions: () -> A) -> some View { _modified() }
    @_disfavoredOverload
    public func alert<S: StringProtocol, A: View>(_ title: S, isPresented: Binding<Bool>,
                                                  @ViewBuilder actions: () -> A) -> some View { _modified() }
    public func alert<A: View>(_ title: Text, isPresented: Binding<Bool>, @ViewBuilder actions: () -> A) -> some View { _modified() }
    public func alert<A: View, M: View>(_ titleKey: LocalizedStringKey, isPresented: Binding<Bool>,
                                        @ViewBuilder actions: () -> A, @ViewBuilder message: () -> M) -> some View { _modified() }
    @_disfavoredOverload
    public func alert<S: StringProtocol, A: View, M: View>(_ title: S, isPresented: Binding<Bool>,
                                                           @ViewBuilder actions: () -> A,
                                                           @ViewBuilder message: () -> M) -> some View { _modified() }
    public func alert<A: View, M: View>(_ title: Text, isPresented: Binding<Bool>, @ViewBuilder actions: () -> A,
                                        @ViewBuilder message: () -> M) -> some View { _modified() }
    public func confirmationDialog<A: View>(_ titleKey: LocalizedStringKey, isPresented: Binding<Bool>,
                                            titleVisibility: Visibility = .automatic,
                                            @ViewBuilder actions: () -> A) -> some View { _modified() }
    public func confirmationDialog<A: View, M: View>(_ titleKey: LocalizedStringKey, isPresented: Binding<Bool>,
                                                     titleVisibility: Visibility = .automatic, @ViewBuilder actions: () -> A,
                                                     @ViewBuilder message: () -> M) -> some View { _modified() }

    // MARK: Haptics (iOS 17)
    public func sensoryFeedback<T: Equatable>(_ feedback: SensoryFeedback, trigger: T) -> some View { _modified() }
    public func sensoryFeedback<T: Equatable>(_ feedback: SensoryFeedback, trigger: T,
                                              condition: @escaping (_ oldValue: T, _ newValue: T) -> Bool) -> some View { _modified() }
}

extension Text {
    public enum TruncationMode: Hashable, Sendable { case head, tail, middle }
}

public enum ColorRenderingMode: Hashable, Sendable { case nonLinear, linear, extendedLinear }

public enum PopoverAttachmentAnchor {
    case rect(Anchor<CGRect>.Source)
    case point(UnitPoint)
}
public struct Anchor<Value> {
    public struct Source {
        public static var bounds: Anchor<CGRect>.Source { _stub() }
    }
}

public struct PresentationDetent: Hashable, Sendable {
    public static let medium = PresentationDetent(), large = PresentationDetent()
    public static func fraction(_ fraction: CGFloat) -> PresentationDetent { _stub() }
    public static func height(_ height: CGFloat) -> PresentationDetent { _stub() }
}

public struct SensoryFeedback: Equatable, Sendable {
    public static let success = SensoryFeedback(), warning = SensoryFeedback(), error = SensoryFeedback(),
                      selection = SensoryFeedback(), increase = SensoryFeedback(), decrease = SensoryFeedback(),
                      start = SensoryFeedback(), stop = SensoryFeedback(), alignment = SensoryFeedback(),
                      levelChange = SensoryFeedback(), impact = SensoryFeedback()
    public enum Weight: Equatable, Sendable { case light, medium, heavy }
    public enum Flexibility: Equatable, Sendable { case rigid, solid, soft }
    public static func impact(weight: SensoryFeedback.Weight = .medium, intensity: Double = 1.0) -> SensoryFeedback { _stub() }
    public static func impact(flexibility: SensoryFeedback.Flexibility, intensity: Double = 1.0) -> SensoryFeedback { _stub() }
}
