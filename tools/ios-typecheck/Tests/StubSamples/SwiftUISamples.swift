// Sample usage of the SwiftUI stub — written the way real app code is written against the iOS 17 SDK.
// If a line here stops compiling after a stub edit, the stub drifted from the real API.
import SwiftUI
import Observation

@Observable
final class SampleModel {
    var count = 0
    var volume: Double = 0.5
    var name = ""
    var enabled = true
    var mode = 0
    var items: [SampleItem] = [SampleItem(id: 1, title: "Gear"), SampleItem(id: 2, title: "Plate")]
}

struct SampleItem: Identifiable, Hashable {
    let id: Int
    var title: String
}

struct CounterKey: EnvironmentKey {
    static let defaultValue = 0
}
extension EnvironmentValues {
    var sampleCounter: Int {
        get { self[CounterKey.self] }
        set { self[CounterKey.self] = newValue }
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct CardModifier: ViewModifier {
    var radius: CGFloat
    func body(content: Content) -> some View {
        content
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius))
    }
}

struct SampleRootView: View {
    @Bindable var model: SampleModel
    @State private var showSheet = false
    @State private var showAlert = false
    @State private var dragOffset: CGSize = .zero
    @State private var zoom: CGFloat = 1
    @State private var selected: SampleItem?
    @GestureState private var isPressing = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @Environment(\.sampleCounter) private var counter

    private let columns = [GridItem(.adaptive(minimum: 64), spacing: 8), GridItem(.fixed(40)), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ZStack(alignment: .bottomTrailing) {
                    LinearGradient(colors: [.black, Color(red: 0.1, green: 0.1, blue: 0.2)], startPoint: .top, endPoint: .bottom)
                        .ignoresSafeArea()
                    VStack(alignment: .leading, spacing: 8) {
                        header
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHGrid(rows: [GridItem(.fixed(48))], spacing: 4) {
                                ForEach(0..<10) { i in
                                    Text("\(i)").monospacedDigit()
                                }
                            }
                        }
                        ScrollView {
                            LazyVGrid(columns: columns, spacing: 8) {
                                ForEach(model.items) { item in
                                    itemCell(item)
                                }
                                ForEach(model.items, id: \.self) { item in
                                    Text(item.title).tag(item.id)
                                }
                            }
                        }
                        controls
                        if model.enabled {
                            Text("Enabled")
                        } else if model.count > 3 {
                            Image(systemName: "gearshape").imageScale(.large)
                        } else {
                            EmptyView()
                        }
                        if model.count > 0 { Spacer(minLength: 4) }
                    }
                    .frame(width: geo.size.width * 0.5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .modifier(CardModifier(radius: 12))
                    progress
                }
            }
            .navigationTitle("Factory")
        }
        .sheet(isPresented: $showSheet) { Text("Sheet") }
        .sheet(item: $selected) { item in Text(item.title) }
        .fullScreenCover(isPresented: $showSheet, onDismiss: { model.count = 0 }) { Text("Cover") }
        .alert("Reset?", isPresented: $showAlert) {
            Button("Reset", role: .destructive) { model.count = 0 }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .background { model.count += 1 }
        }
        .onChange(of: model.count) { model.enabled.toggle() }
        .onAppear { model.count += 1 }
        .onDisappear {}
        .task { await load() }
        .task(id: model.count) { await load() }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .environment(\.sampleCounter, 3)
        .environment(model)
        .animation(.easeInOut(duration: 0.2), value: model.count)
        .sensoryFeedback(.selection, trigger: model.mode)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("Count: \(model.count)").font(.headline).bold()
            Text("Vol \(model.volume, specifier: "%.1f")") + Text(" dB").foregroundColor(.gray)
            Text(verbatim: model.name).lineLimit(1).minimumScaleFactor(0.5)
            Image("item_iron_plate").resizable().interpolation(.none).renderingMode(.original).frame(width: 32, height: 32)
            Image(uiImage: UIImage()).resizable().aspectRatio(contentMode: .fit)
            Label("Settings", systemImage: "gear")
            Spacer()
            Button {
                withAnimation(.spring()) { model.count += 1 }
            } label: {
                Image(systemName: "plus.circle.fill").foregroundStyle(.white, .blue)
            }
            .buttonStyle(.plain)
            Button("Alert") { showAlert = true }.buttonStyle(.borderedProminent).tint(.orange)
            Button("Sheet", action: { showSheet = true }).buttonStyle(PressableStyle()).disabled(!model.enabled)
        }
    }

    private func itemCell(_ item: SampleItem) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.gray.opacity(0.3))
            .overlay(alignment: .bottom) { Text(item.title).font(.caption2) }
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white, lineWidth: 1))
            .frame(height: 64)
            .contentShape(Rectangle())
            .onTapGesture { selected = item }
            .onLongPressGesture(minimumDuration: 0.4) { model.count -= 1 }
            .shadow(color: .black.opacity(0.4), radius: 4, x: 0, y: 2)
    }

    private var controls: some View {
        VStack {
            Toggle("Enabled", isOn: $model.enabled)
            Slider(value: $model.volume, in: 0...1, step: 0.1)
            Stepper("Count \(model.count)", value: $model.count, in: 0...10)
            Picker("Mode", selection: $model.mode) {
                Text("Build").tag(0)
                Text("Mine").tag(1)
            }
            .pickerStyle(.segmented)
            TextField("Name", text: $model.name).textFieldStyle(.roundedBorder)
            List {
                Section(header: Text("Items")) {
                    ForEach($model.items) { $item in
                        TextField("Title", text: $item.title)
                    }
                }
                Section("More") { Divider() }
            }
            NavigationLink("Details") { Text("Details") }
        }
    }

    private var progress: some View {
        ZStack {
            Circle().stroke(lineWidth: 4).opacity(0.3)
            Circle()
                .trim(from: 0, to: 0.7)
                .stroke(Color.green, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(Angle(degrees: -90))
            Capsule().fill(.red).frame(width: 20, height: 8)
            ProgressView(value: 0.4, total: 1.0).progressViewStyle(.linear)
        }
        .frame(width: 60, height: 60)
        .offset(dragOffset)
        .scaleEffect(zoom * (isPressing ? 0.9 : 1))
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { value in dragOffset = value.translation; _ = value.location; _ = value.startLocation }
                .onEnded { _ in dragOffset = .zero }
        )
        .simultaneousGesture(MagnifyGesture().onChanged { zoom = $0.magnification })
        .gesture(LongPressGesture(minimumDuration: 0.2).updating($isPressing) { current, state, _ in state = current })
        .zIndex(1)
        .id(model.count)
        .position(x: 100, y: 100)
        .allowsHitTesting(true)
        .transition(.opacity.combined(with: .scale))
        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 1) }
    }

    private func load() async {}
}

@main
struct SampleApp: App {
    @State private var model = SampleModel()
    var body: some Scene {
        WindowGroup {
            SampleRootView(model: model)
        }
    }
}
