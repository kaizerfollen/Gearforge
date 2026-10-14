// Gearforge — map screen (GDD §5.1 "Map"): the whole charted map, pinch to zoom, drag to pan, tap to walk there.
// Uncharted areas are black; the radar and the character's surroundings reveal the map.

import SwiftUI
import FactoryCore

struct MapPanel: View {
    @Bindable var controller: GameController
    @State private var zoom: CGFloat = 2
    @State private var zoomStart: CGFloat = 2
    @State private var pan: CGSize = .zero
    @State private var panStart: CGSize = .zero

    var body: some View {
        PanelChrome(title: "Map", onClose: { controller.panel = nil }) {
            GeometryReader { geo in
                let w = controller.world
                let b = w.surface.bounds
                let base = min(geo.size.width / CGFloat(b.w), geo.size.height / CGFloat(b.h))   // points per tile at zoom 1
                let k = base * zoom
                let pp = w.player.position
                // Map centred on the character, then offset by the pan.
                let cx = geo.size.width / 2 + pan.width, cy = geo.size.height / 2 + pan.height
                let originX = cx - CGFloat(pp.x - Double(b.x)) * k
                let originY = cy - CGFloat(pp.y - Double(b.y)) * k
                // `.position` (not `.offset`) so the oversized map image never grows the ZStack.
                ZStack {
                    Color.black
                    if let img = controller.mapImage {
                        Image(img, scale: 1, label: Text("Map")).interpolation(.none).resizable()
                            .frame(width: CGFloat(b.w) * k, height: CGFloat(b.h) * k)
                            .position(x: originX + CGFloat(b.w) * k / 2, y: originY + CGFloat(b.h) * k / 2)
                    }
                    Circle().fill(Theme.accent).frame(width: 10, height: 10)
                        .overlay(Circle().stroke(Color.black, lineWidth: 2))
                        .position(x: cx, y: cy)
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 4)
                        .onChanged { v in pan = CGSize(width: panStart.width + v.translation.width, height: panStart.height + v.translation.height) }
                        .onEnded { _ in panStart = pan }
                )
                .simultaneousGesture(
                    MagnifyGesture()
                        .onChanged { v in zoom = min(12, max(0.5, zoomStart * v.magnification)) }
                        .onEnded { _ in zoomStart = zoom }
                )
                .simultaneousGesture(
                    SpatialTapGesture().onEnded { v in
                        let tx = Double((v.location.x - originX) / k) + Double(b.x)
                        let ty = Double((v.location.y - originY) / k) + Double(b.y)
                        let t = TilePos(Int32(floor(tx)), Int32(floor(ty)))
                        if w.isCharted(t.chunk), controller.walkTo(t) { controller.panel = nil }
                    }
                )
                .overlay(alignment: .bottomTrailing) {
                    HStack(spacing: 8) {
                        Button { zoom = max(0.5, zoom / 1.5); zoomStart = zoom } label: { Image(systemName: "minus.magnifyingglass") }
                        Button { zoom = min(12, zoom * 1.5); zoomStart = zoom } label: { Image(systemName: "plus.magnifyingglass") }
                        Button { pan = .zero; panStart = .zero } label: { Image(systemName: "location.fill") }
                    }
                    .font(.title3).foregroundStyle(Theme.text)
                    .padding(10).background(Capsule().fill(Color.black.opacity(0.6))).padding(10)
                }
                .overlay(alignment: .bottomLeading) {
                    Text("Tap to walk there · pinch to zoom").font(.caption).foregroundStyle(Theme.textDim)
                        .padding(8).background(Capsule().fill(Color.black.opacity(0.5))).padding(10)
                }
            }
        }
        .panelFrame(maxWidth: 900, maxHeight: 700)
    }
}
