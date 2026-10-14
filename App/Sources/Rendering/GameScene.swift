// Gearforge — App
// SpriteKit world renderer. Reads FactoryCore state after each simulation step; never mutates the world.
// - Terrain: one SKTileMapNode per generated chunk (ground) + one for ore overlays; textures shared from the atlas.
// - Entities: pooled nodes only for entities inside the camera rect (+margin), synced at 5 Hz and on world events.
// - Belt items / inserter arms / character: updated every frame for the visible area only.
// World tile (x, y) with y pointing south maps to scene point (x·S, −y·S).

import Foundation
import SpriteKit
import UIKit
import FactoryCore

@MainActor
final class GameScene: SKScene {
    weak var controller: GameController?
    let S: CGFloat = 32                         // scene points per tile
    private let cam = SKCameraNode()
    private let terrainLayer = SKNode()
    private let entityLayer = SKNode()
    private let itemLayer = SKNode()
    private let overlayLayer = SKNode()
    private let wireNode = SKShapeNode()
    private let nightNode = SKSpriteNode(color: .black, size: CGSize(width: 10, height: 10))
    private let characterNode = SKSpriteNode()
    private let previewNode = SKSpriteNode()
    /// Build preview markers: where an inserter picks up (green ring) and where a drill/inserter drops (orange dot).
    private let ioInNode = SKShapeNode(circleOfRadius: 5)
    private let ioOutNode = SKShapeNode(circleOfRadius: 6)
    private let selectionNode = SKShapeNode(rect: CGRect(x: 0, y: 0, width: 32, height: 32), cornerRadius: 3)
    private let reachNode = SKShapeNode(circleOfRadius: 320)
    /// Copy-area rectangle and paste preview (GDD §4.6).
    private let copyRectNode = SKShapeNode()
    /// ✓ / ✕ next to the build ghost in colour-blind modes (validity not shown by colour alone).
    private let validityLabel = SKLabelNode(text: "")
    /// Tile grid (Settings → show grid: off / build / always).
    private let gridNode = SKShapeNode()
    /// Diagnostics (Settings → Show FPS): terrain state of the chunk under the camera centre.
    private let debugLabel = SKLabelNode(text: "")
    private var debugTimer: Double = 0
    private var debugRebakes = 0
    private var gridKey = ""
    private var pastePool: [SKSpriteNode] = []
    /// Paste preview cache: recomputed when the origin/rotation/clipboard changes or every 15 ticks (not per frame).
    private var pasteKey: Int? = nil
    private var pasteTick: UInt64 = 0
    private var groundZoom: CGFloat = 0
    private var appliedReduceMotion = false
    /// Items lying on the ground (re-synced when GroundItems.revision or the view changes).
    private var groundPool: [SKSpriteNode] = []
    private var groundRevision = -1
    private var groundCenter = TilePos(Int32.max, 0)

    private var chunkNodes: [ChunkPos: (ground: SKTileMapNode, ore: SKTileMapNode)] = [:]
    private var tileGroups: [Int: [SKTileGroup]] = [:]          // tile index → variants
    private var oreGroups: [Int: [SKTileGroup]] = [:]           // resource index → 8 stages
    private var tileSet: SKTileSet?

    private var views: [Int32: EntityView] = [:]
    private var itemPool: [SKSpriteNode] = []
    private var lastTime: TimeInterval = 0
    private var syncTimer: Double = 1
    private var stateTimer: Double = 1
    private var wireTimer: Double = 1
    private var lastSyncCenter = TilePos(Int32.max, 0)
    private var walkPhase: Double = 0
    /// Inserter hand positions at the previous state refresh (an inserter whose hand moved is "working" for audio).
    private var lastHandPos: [Int32: Vec2] = [:]

    /// Zoom factor: 1 = 32 points per tile; clamped 0.35…3 (GDD §4.2).
    var zoom: CGFloat = 1 { didSet { zoom = max(0.35, min(3, zoom)); cam.setScale(1 / zoom) } }
    /// Camera centre in tile coordinates.
    var cameraCenter = Vec2(0, 0)

    final class EntityView {
        let node: SKSpriteNode
        var generation: UInt32
        var proto: Int32
        var kind: EntityKind
        var spriteKey = ""
        var animating = false
        var arm: SKSpriteNode?
        var hand: SKSpriteNode?
        var status: SKSpriteNode?
        var recipeIcon: SKSpriteNode?
        var ghost = false
        init(node: SKSpriteNode, generation: UInt32, proto: Int32, kind: EntityKind) {
            self.node = node; self.generation = generation; self.proto = proto; self.kind = kind
        }
    }

    // MARK: Setup

    override func didMove(to view: SKView) {
        backgroundColor = UIColor(red: 0.12, green: 0.14, blue: 0.12, alpha: 1)
        scaleMode = .resizeFill
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        addChild(cam)
        camera = cam
        terrainLayer.zPosition = 0
        entityLayer.zPosition = 10
        itemLayer.zPosition = 20
        overlayLayer.zPosition = 40
        for n in [terrainLayer, entityLayer, itemLayer, overlayLayer] { addChild(n) }
        wireNode.strokeColor = UIColor(red: 0.85, green: 0.5, blue: 0.25, alpha: 0.85)
        wireNode.lineWidth = 1.5
        wireNode.zPosition = 30
        addChild(wireNode)
        characterNode.zPosition = 25
        characterNode.size = CGSize(width: S * 0.9, height: S * 1.2)
        characterNode.anchorPoint = CGPoint(x: 0.5, y: 0.25)
        addChild(characterNode)
        previewNode.alpha = 0.6
        previewNode.zPosition = 41
        previewNode.colorBlendFactor = 0.45
        overlayLayer.addChild(previewNode)
        ioInNode.strokeColor = UIColor(red: 0.3, green: 1, blue: 0.4, alpha: 0.95)
        ioInNode.lineWidth = 2
        ioInNode.fillColor = .clear
        ioInNode.zPosition = 42
        ioOutNode.fillColor = UIColor(red: 1, green: 0.62, blue: 0.2, alpha: 0.95)
        ioOutNode.strokeColor = UIColor(white: 0, alpha: 0.6)
        ioOutNode.lineWidth = 1.5
        ioOutNode.zPosition = 42
        ioInNode.isHidden = true; ioOutNode.isHidden = true
        overlayLayer.addChild(ioInNode)
        overlayLayer.addChild(ioOutNode)
        selectionNode.strokeColor = UIColor(red: 1, green: 0.8, blue: 0.2, alpha: 1)
        selectionNode.lineWidth = 2
        selectionNode.fillColor = .clear
        selectionNode.isHidden = true
        overlayLayer.addChild(selectionNode)
        reachNode.strokeColor = UIColor(white: 1, alpha: 0.18)
        reachNode.lineWidth = 1.5
        reachNode.fillColor = .clear
        reachNode.isHidden = true
        overlayLayer.addChild(reachNode)
        copyRectNode.strokeColor = UIColor(red: 0.35, green: 0.8, blue: 1, alpha: 1)
        copyRectNode.fillColor = UIColor(red: 0.35, green: 0.8, blue: 1, alpha: 0.15)
        copyRectNode.lineWidth = 2
        copyRectNode.zPosition = 43
        copyRectNode.isHidden = true
        overlayLayer.addChild(copyRectNode)
        validityLabel.fontName = "HelveticaNeue-Bold"
        validityLabel.fontSize = 20
        validityLabel.zPosition = 45
        validityLabel.verticalAlignmentMode = .center
        validityLabel.isHidden = true
        overlayLayer.addChild(validityLabel)
        gridNode.strokeColor = UIColor(white: 1, alpha: 0.10)
        gridNode.lineWidth = 1
        gridNode.zPosition = 5
        gridNode.isHidden = true
        addChild(gridNode)
        nightNode.zPosition = 100
        nightNode.alpha = 0
        cam.addChild(nightNode)
        debugLabel.fontName = "Menlo"
        debugLabel.fontSize = 11
        debugLabel.fontColor = .yellow
        debugLabel.numberOfLines = 0
        debugLabel.horizontalAlignmentMode = .left
        debugLabel.verticalAlignmentMode = .top
        debugLabel.zPosition = 200
        debugLabel.isHidden = true
        cam.addChild(debugLabel)
        buildTileSet()
        zoom = 1
        if let c = controller { cameraCenter = c.world.player.position }
    }

    override func didChangeSize(_ oldSize: CGSize) {
        nightNode.size = CGSize(width: size.width * 4, height: size.height * 4)
    }

    private func buildTileSet() {
        guard let w = controller?.world else { return }
        let cat = SpriteCatalog.shared
        var groups: [SKTileGroup] = []
        let tsz = CGSize(width: S, height: S)
        for (i, t) in w.db.tiles.enumerated() {
            var vs: [SKTileGroup] = []
            for v in 0..<4 {
                let name = "tile_\(t.id)_v\(v)"
                guard cat.has(name) || v == 0 else { continue }
                let def = SKTileDefinition(texture: cat.texture(firstOf: [name, "tile_grass_1_v0"]), size: tsz)
                let g = SKTileGroup(tileDefinition: def)
                vs.append(g); groups.append(g)
            }
            tileGroups[i] = vs
        }
        for (ri, r) in w.db.resources.enumerated() {
            var vs: [SKTileGroup] = []
            for st in 0..<8 {
                let name = r.resultIsFluid ? "ore_\(r.id)" : "ore_\(r.id)_\(st)"
                let def = SKTileDefinition(texture: cat.texture(firstOf: [name, "ore_iron_ore_\(st)"]), size: tsz)
                let g = SKTileGroup(tileDefinition: def)
                vs.append(g); groups.append(g)
            }
            oreGroups[ri] = vs
        }
        tileSet = SKTileSet(tileGroups: groups)
    }

    // MARK: Coordinates

    @inline(__always) func scenePoint(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: CGFloat(x) * S, y: -CGFloat(y) * S) }
    @inline(__always) func worldPoint(_ p: CGPoint) -> Vec2 { Vec2(Double(p.x / S), Double(-p.y / S)) }

    /// Tile under a point given in SpriteView (SwiftUI) coordinates.
    func tile(atView p: CGPoint) -> TilePos { worldPoint(atView: p).tile }
    func worldPoint(atView p: CGPoint) -> Vec2 {
        let scenePt = convertPoint(fromView: p)
        return worldPoint(scenePt)
    }

    /// Visible tile rect (with margin).
    func visibleRect(margin: Int32 = 2) -> TileRect {
        let halfW = Double(size.width / zoom / S) / 2 + Double(margin)
        let halfH = Double(size.height / zoom / S) / 2 + Double(margin)
        let x0 = Int32((cameraCenter.x - halfW).rounded(.down)), y0 = Int32((cameraCenter.y - halfH).rounded(.down))
        return TileRect(x: x0, y: y0, w: Int32(halfW * 2) + 2, h: Int32(halfH * 2) + 2)
    }

    // MARK: Frame

    override func update(_ currentTime: TimeInterval) {
        guard let c = controller else { return }
        let dt = lastTime == 0 ? 1.0 / 60 : min(0.25, currentTime - lastTime)
        lastTime = currentTime
        c.frame(dt: dt)
        let w = c.world
        if c.cameraFollowsPlayer { cameraCenter = w.player.position }
        cam.position = scenePoint(cameraCenter.x, cameraCenter.y)

        handleEvents(c.frameEvents, w)
        syncTimer += dt; stateTimer += dt; wireTimer += dt
        let center = cameraCenter.tile
        if syncTimer > 0.2 || abs(center.x - lastSyncCenter.x) > 3 || abs(center.y - lastSyncCenter.y) > 3 {
            syncTimer = 0; lastSyncCenter = center
            syncChunks(w); syncEntities(w)
        }
        if stateTimer > 0.25 { stateTimer = 0; refreshStates(w, c) }
        if wireTimer > 0.5 { wireTimer = 0; updateWires(w) }
        updateInserters(w)
        updateBeltItems(w)
        updateGroundItems(w)
        updateCharacter(w, dt: dt)
        updateOverlay(w, c)
        updateCopyPaste(w, c)
        updateGrid(c)
        debugTimer += dt
        if c.settings.showFPS, debugTimer > 0.5 { debugTimer = 0; updateDebug(w) }
        else if !c.settings.showFPS { debugLabel.isHidden = true }
        let night = c.settings.dayNightLighting ? (1 - w.daylight) * 0.55 : 0
        nightNode.alpha = CGFloat(night)
    }

    // MARK: Events

    private func handleEvents(_ events: [WorldEvent], _ w: World) {
        guard !events.isEmpty else { return }
        let vis = visibleRect(margin: 6)
        var pipesDirty = false
        for e in events {
            switch e {
            case .entityAdded(let id):
                let rec = w.entities[id]
                if rec.isAlive && rec.rect.intersects(vis) { makeView(id, w) }
                if rec.kind == .pipe || rec.kind == .pipeToGround || w.entities[id].fluidSlot >= 0 { pipesDirty = true }
                if rec.kind == .transportBelt || rec.kind == .undergroundBelt || rec.kind == .splitter { refreshBeltsNear(rec.rect, w) }
            case .entityRemoved(let h, _, let origin, _):
                if let v = views[h.index], v.generation == h.generation { discard(v); views[h.index] = nil }
                pipesDirty = true
                refreshBeltsNear(TileRect(origin: origin, w: 3, h: 3).expanded(by: 1), w)
            case .entityChanged(let id):
                if let v = views[id] { configure(v, id, w, force: true) }
            case .tilesChanged(let cp), .chunkGenerated(let cp):
                if let n = chunkNodes[cp] { n.ground.removeFromParent(); n.ore.removeFromParent(); chunkNodes[cp] = nil }
                syncTimer = 1          // re-bake in this same frame (sync runs right after the events), no blank frames
            default: break
            }
        }
        if pipesDirty { for (id, v) in views where v.kind == .pipe { configure(v, id, w, force: true) } }
        if pipesDirty { wireTimer = 1 }
    }

    private func refreshBeltsNear(_ r: TileRect, _ w: World) {
        let rr = r.expanded(by: 1)
        for id in w.entities(in: rr) { if let v = views[id] { configure(v, id, w, force: true) } }
    }

    private func updateDebug(_ w: World) {
        let t = cameraCenter.tile, cp = t.chunk
        var lines = ["cam \(t.x),\(t.y) chunk \(cp.x),\(cp.y) zoom \(String(format: "%.2f", zoom)) size \(Int(size.width))x\(Int(size.height))"]
        let vis = visibleRect(margin: 8)
        lines.append("vis \(vis.x),\(vis.y) \(vis.w)x\(vis.h) nodes \(chunkNodes.count) terrainKids \(terrainLayer.children.count)")
        if let ch = w.surface.existingChunk(cp) {
            let mid = Int(ch.tiles[16 * 32 + 16])
            lines.append("chunk ok charted=\(ch.charted) midTile=\(mid) groups=\(tileGroups[mid]?.count ?? -1)")
        } else { lines.append("chunk MISSING") }
        if let n = chunkNodes[cp] {
            let g = n.ground
            let tg = g.tileGroup(atColumn: 16, row: 15)
            lines.append("node parent=\(g.parent != nil) pos=\(Int(g.position.x)),\(Int(g.position.y)) hidden=\(g.isHidden) a=\(g.alpha) z=\(g.zPosition)")
            lines.append("cols=\(g.numberOfColumns) group=\(tg != nil) tex=\(tg?.rules.first?.tileDefinitions.first?.textures.first.map { "\(Int($0.size().width))" } ?? "nil")")
            let f = g.frame
            lines.append("frame \(Int(f.minX)),\(Int(f.minY)) \(Int(f.width))x\(Int(f.height)) kids=\(g.children.count) ore kids=\(n.ore.children.count)")
            debugRebakes += 1
            if debugRebakes % 6 == 0, let ch = w.surface.existingChunk(cp), let ts = tileSet {
                n.ground.removeFromParent(); n.ore.removeFromParent()
                chunkNodes[cp] = bakeChunk(ch, ts, w)
                lines.append("REBAKED this chunk")
            }
        } else { lines.append("node NONE for chunk") }
        if let v = view {
            let p = convertPoint(toView: cam.position)
            lines.append("view \(Int(v.bounds.width))x\(Int(v.bounds.height)) camInView \(Int(p.x)),\(Int(p.y)) camScale \(cam.xScale) scaleMode \(scaleMode.rawValue)")
        }
        debugLabel.text = lines.joined(separator: "\n")
        debugLabel.position = CGPoint(x: -size.width / 2 + 12, y: size.height / 2 - 90)
        debugLabel.isHidden = false
    }

    // MARK: Terrain

    private func syncChunks(_ w: World) {
        guard let ts = tileSet else { return }
        let vis = visibleRect(margin: 8)
        let c0 = TilePos(vis.x, vis.y).chunk, c1 = TilePos(vis.maxX, vis.maxY).chunk
        var wanted = Set<ChunkPos>()
        var cy = c0.y
        while cy <= c1.y {
            var cx = c0.x
            while cx <= c1.x {
                let cp = ChunkPos(cx, cy)
                if let ch = w.surface.chunk(cp) {          // generates on demand (exploration)
                    wanted.insert(cp)
                    if chunkNodes[cp] == nil { chunkNodes[cp] = bakeChunk(ch, ts, w) }
                }
                cx += 1
            }
            cy += 1
        }
        for (cp, n) in chunkNodes where !wanted.contains(cp) {
            n.ground.removeFromParent(); n.ore.removeFromParent(); chunkNodes[cp] = nil
        }
    }

    private func bakeChunk(_ ch: Chunk, _ ts: SKTileSet, _ w: World) -> (SKTileMapNode, SKTileMapNode) {
        let n = chunkSize
        let ground = SKTileMapNode(tileSet: ts, columns: n, rows: n, tileSize: CGSize(width: S, height: S))
        let ore = SKTileMapNode(tileSet: ts, columns: n, rows: n, tileSize: CGSize(width: S, height: S))
        ground.enableAutomapping = false; ore.enableAutomapping = false
        let origin = ch.pos.originTile
        for ly in 0..<n {
            for lx in 0..<n {
                let i = ly * n + lx
                let row = n - 1 - ly
                let t = Int(ch.tiles[i])
                if let vs = tileGroups[t], !vs.isEmpty {
                    let hx = (Int(origin.x) + lx) &* 73856093 ^ (Int(origin.y) + ly) &* 19349663
                    ground.setTileGroup(vs[abs(hx) % vs.count], forColumn: lx, row: row)
                }
                let r = Int(ch.resource[i]) - 1
                if r >= 0, let os = oreGroups[r] {
                    let amt = Double(ch.resourceAmount[i])
                    let stage = w.db.resources[r].resultIsFluid ? 0 : min(7, Int(log2(max(1, amt / 25))))
                    ore.setTileGroup(os[stage], forColumn: lx, row: row)
                }
            }
        }
        // SKTileMapNode is centred on its position
        let cx = Double(origin.x) + Double(n) / 2, cy = Double(origin.y) + Double(n) / 2
        ground.position = scenePoint(cx, cy); ore.position = ground.position
        ground.zPosition = 0; ore.zPosition = 1
        terrainLayer.addChild(ground); terrainLayer.addChild(ore)
        return (ground, ore)
    }

    // MARK: Entities

    private func syncEntities(_ w: World) {
        let vis = visibleRect(margin: 4)
        let ids = w.entities(in: vis)
        var keep = Set<Int32>()
        keep.reserveCapacity(ids.count)
        for id in ids {
            keep.insert(id)
            let rec = w.entities[id]
            if let v = views[id] {
                if v.generation != rec.generation || v.proto != rec.proto { discard(v); views[id] = nil; makeView(id, w) }
            } else { makeView(id, w) }
        }
        for (id, v) in views where !keep.contains(id) { discard(v); views[id] = nil }
    }

    private func discard(_ v: EntityView) {
        v.node.removeFromParent(); v.arm?.removeFromParent(); v.hand?.removeFromParent()
    }

    private func makeView(_ id: Int32, _ w: World) {
        let rec = w.entities[id]
        guard rec.isAlive, rec.kind != .character else { return }
        let node = SKSpriteNode()
        let v = EntityView(node: node, generation: rec.generation, proto: rec.proto, kind: rec.kind)
        switch rec.kind {
        case .transportBelt, .undergroundBelt, .splitter, .pipe, .pipeToGround: node.zPosition = 1
        case .inserter: node.zPosition = 3
        case .electricPole: node.zPosition = 6
        case .tree, .rock: node.zPosition = 7
        default: node.zPosition = 2
        }
        views[id] = v
        entityLayer.addChild(node)
        configure(v, id, w, force: true)
    }

    private func spriteName(_ id: Int32, _ rec: EntityRecord, _ p: EntityProto, _ w: World) -> [String] {
        let d = SpriteNames.dirSuffix(rec.direction)
        switch rec.kind {
        case .transportBelt:
            let shape: String
            switch w.belts.shape(of: id) {
            case .curveLeft: shape = "curve_l"
            case .curveRight: shape = "curve_r"
            default: shape = "straight"
            }
            return ["belt_\(p.id)_\(shape)_\(d)_f0", "e_\(p.id)"]
        case .undergroundBelt:
            let io = w.belts.isUndergroundEntrance(id) ? "in" : "out"
            return ["e_\(p.id)_\(io)_\(d)", "e_\(p.id)"]
        case .pipe:
            return ["pipe_\(w.fluids.pipeConnections(of: id))", "e_pipe"]
        case .inserter:
            return ["ins_\(p.id)_base", "e_\(p.id)"]
        default:
            return ["e_\(p.id)_\(d)", "e_\(p.id)"]
        }
    }

    private func configure(_ v: EntityView, _ id: Int32, _ w: World, force: Bool) {
        let rec = w.entities[id]
        guard rec.isAlive else { return }
        let p = w.db.entities[Int(rec.proto)]
        let names = spriteName(id, rec, p, w)
        let key = names.first { SpriteCatalog.shared.has($0) } ?? names[names.count - 1]
        let node = v.node
        let r = rec.rect
        node.size = CGSize(width: CGFloat(r.w) * S, height: CGFloat(r.h) * S)
        node.position = scenePoint(r.center.x, r.center.y)
        if force || key != v.spriteKey {
            v.spriteKey = key
            node.removeAllActions(); v.animating = false
            node.texture = SpriteCatalog.shared.texture(key)
            if rec.kind == .transportBelt { startBeltAnimation(v, p, base: key) }
        }
        v.ghost = rec.flags.contains(.ghost)
        node.alpha = v.ghost ? 0.45 : 1
        node.color = UIColor(red: 0.4, green: 0.7, blue: 1, alpha: 1)
        node.colorBlendFactor = v.ghost ? 0.6 : 0
        if rec.kind == .inserter && v.arm == nil {
            let arm = SKSpriteNode(texture: SpriteCatalog.shared.texture(firstOf: ["ins_\(p.id)_arm", "ins_inserter_arm"]))
            arm.anchorPoint = CGPoint(x: 0, y: 0.5)
            arm.zPosition = 26
            let hand = SKSpriteNode(texture: SpriteCatalog.shared.texture(firstOf: ["ins_\(p.id)_hand", "ins_inserter_hand"]))
            hand.size = CGSize(width: S * 0.4, height: S * 0.4)
            hand.zPosition = 27
            itemLayer.addChild(arm); itemLayer.addChild(hand)
            v.arm = arm; v.hand = hand
        }
    }

    private func setValidityGlyph(_ ok: Bool, at p: CGPoint, size: CGSize) {
        guard Theme.colorblind != "off" else { validityLabel.isHidden = true; return }
        validityLabel.text = ok ? "✓" : "✕"
        validityLabel.fontColor = ok ? Theme.goodUI : Theme.badUI
        validityLabel.position = CGPoint(x: p.x + size.width / 2 + 8, y: p.y + size.height / 2 + 8)
        validityLabel.isHidden = false
    }

    /// Grid lines over the visible area, rebuilt only when the camera crosses a tile or the zoom changes.
    private func updateGrid(_ c: GameController) {
        let mode = c.settings.showGrid
        let show = (mode == "always" || (mode == "build" && c.mode != .explore)) && zoom >= 0.6
        gridNode.isHidden = !show
        guard show else { return }
        let r = visibleRect(margin: 1)
        let key = "\(r.x),\(r.y),\(r.w),\(r.h)"
        guard key != gridKey else { return }
        gridKey = key
        let path = CGMutablePath()
        for x in r.x...r.maxX {
            path.move(to: CGPoint(x: CGFloat(x) * S, y: -CGFloat(r.y) * S))
            path.addLine(to: CGPoint(x: CGFloat(x) * S, y: -CGFloat(r.maxY) * S))
        }
        for y in r.y...r.maxY {
            path.move(to: CGPoint(x: CGFloat(r.x) * S, y: -CGFloat(y) * S))
            path.addLine(to: CGPoint(x: CGFloat(r.maxX) * S, y: -CGFloat(y) * S))
        }
        gridNode.path = path
    }

    private func startBeltAnimation(_ v: EntityView, _ p: EntityProto, base: String) {
        guard base.hasSuffix("_f0"), controller?.settings.reduceMotion != true else { return }
        let stem = String(base.dropLast(3))
        let frames = (0..<8).map { SpriteCatalog.shared.texture(firstOf: ["\(stem)_f\($0)", base]) }
        let speed = Double(p.belt?.speed ?? 8)          // positions per tick; 8 frames per tile (256 positions)
        let tpf = 32.0 / speed / 60.0
        v.node.run(SKAction.repeatForever(SKAction.animate(with: frames, timePerFrame: tpf)))
        v.animating = true
    }

    /// Working animation, status icons, alt-mode recipe icons (4 Hz).
    private func refreshStates(_ w: World, _ c: GameController) {
        if c.settings.reduceMotion != appliedReduceMotion {
            // Settings → Reduce motion changed mid-game: belt animations are only (re)started when a view is
            // created, so restart / stop the ones already on screen (machines follow via setWorking).
            appliedReduceMotion = c.settings.reduceMotion
            for (_, v) in views where v.kind == .transportBelt && !v.spriteKey.isEmpty {
                v.node.removeAllActions(); v.animating = false
                v.node.texture = SpriteCatalog.shared.texture(v.spriteKey)
                startBeltAnimation(v, w.db.entities[Int(v.proto)], base: v.spriteKey)
            }
        }
        let vis = visibleRect(margin: 3)
        var sounds: [(kind: AudioManager.LoopKind, x: Double, y: Double)] = []
        var inserterSounds: [(kind: AudioManager.LoopKind, x: Double, y: Double)] = []
        var handPos: [Int32: Vec2] = [:]
        for (id, v) in views where !v.ghost {
            let rec = w.entities[id]
            guard rec.isAlive else { continue }
            var working = false
            var status: EntityStatus? = nil
            switch rec.kind {
            case .assemblingMachine, .furnace, .rocketSilo:
                working = w.crafting.isWorking(id); status = w.crafting.status(of: id)
            case .miningDrill: working = w.mining.isWorking(id); status = w.mining.status(of: id)
            case .lab: working = w.labs.isWorking(id); status = w.labs.status(of: id)
            case .boiler: working = w.power.isBoilerWorking(id)
            case .generator: working = w.power.powerOutput(of: id) > 1
            case .inserter:
                status = w.inserters.status(of: id)
                let hp = w.inserters.handPosition(of: id)
                handPos[id] = hp
                if let old = lastHandPos[id], abs(old.x - hp.x) + abs(old.y - hp.y) > 0.01 { working = true }
            default: continue
            }
            if rec.kind != .inserter && rec.kind != .transportBelt {
                setWorking(v, rec, w, working)
            }
            if working, vis.contains(rec.center.tile), let kind = loopKind(rec, w) {
                let p = rec.center
                if kind == .inserter { inserterSounds.append((kind, p.x, p.y)) } else { sounds.append((kind, p.x, p.y)) }
            }
            setStatusIcon(v, status, rec)
            if c.altMode && (rec.kind == .assemblingMachine || rec.kind == .furnace) {
                let r = w.crafting.recipe(of: id)
                if r >= 0 {
                    if v.recipeIcon == nil {
                        let n = SKSpriteNode(); n.zPosition = 1; n.size = CGSize(width: S * 1.1, height: S * 1.1)
                        v.node.addChild(n); v.recipeIcon = n
                    }
                    v.recipeIcon?.texture = SKTexture(image: SpriteCatalog.shared.recipeIcon(r, db: w.db))
                    v.recipeIcon?.isHidden = false
                } else { v.recipeIcon?.isHidden = true }
            } else { v.recipeIcon?.isHidden = true }
        }
        lastHandPos = handPos
        if c.panel == .pause {
            // simulation paused: machines keep their last "working" state, so fade the factory out explicitly
            AudioManager.shared.updateAmbience(listener: (w.player.position.x, w.player.position.y), sources: [])
        } else {
            updateAmbience(w, sounds: sounds, inserters: inserterSounds, visible: vis)
        }
    }

    // MARK: Ambience

    private func loopKind(_ rec: EntityRecord, _ w: World) -> AudioManager.LoopKind? {
        switch rec.kind {
        case .assemblingMachine: return .assembler
        case .furnace: return .furnace
        case .miningDrill: return w.db.entities[Int(rec.proto)].id == "pumpjack" ? .pumpjack : .drill
        case .generator: return .steamEngine
        case .boiler: return .boiler
        case .lab: return .lab
        case .inserter: return .inserter
        default: return nil
        }
    }

    /// Feeds the working machines in view (plus the 12 nearest belt tiles carrying items, 8 nearest moving
    /// inserters) to the audio engine, with the character as the listener.
    private func updateAmbience(_ w: World, sounds: [(kind: AudioManager.LoopKind, x: Double, y: Double)],
                                inserters: [(kind: AudioManager.LoopKind, x: Double, y: Double)], visible: TileRect) {
        let me = w.player.position
        func d2(_ x: Double, _ y: Double) -> Double { (x - me.x) * (x - me.x) + (y - me.y) * (y - me.y) }
        var all = sounds
        all += inserters.sorted { d2($0.x, $0.y) < d2($1.x, $1.y) }.prefix(8)
        var beltTiles = Set<TilePos>()
        w.belts.forEachItem(in: visible) { _, x, y in
            beltTiles.insert(TilePos(Int32(x.rounded(.down)), Int32(y.rounded(.down))))
        }
        let belts = beltTiles.map { (x: Double($0.x) + 0.5, y: Double($0.y) + 0.5) }
            .sorted { d2($0.x, $0.y) < d2($1.x, $1.y) }.prefix(12)
        for b in belts { all.append((.belt, b.x, b.y)) }
        AudioManager.shared.updateAmbience(listener: (me.x, me.y), sources: all)
    }

    private func setWorking(_ v: EntityView, _ rec: EntityRecord, _ w: World, _ working: Bool) {
        let working = working && controller?.settings.reduceMotion != true      // Settings → Reduce motion
        guard working != v.animating else { return }
        let base = v.spriteKey
        if working {
            let frames = (0..<4).compactMap { k -> SKTexture? in
                let n = "\(base)_w\(k)"
                return SpriteCatalog.shared.has(n) ? SpriteCatalog.shared.texture(n) : nil
            }
            guard !frames.isEmpty else { v.animating = true; return }
            v.node.run(SKAction.repeatForever(SKAction.animate(with: frames, timePerFrame: 0.12)), withKey: "work")
        } else {
            v.node.removeAction(forKey: "work")
            v.node.texture = SpriteCatalog.shared.texture(base)
        }
        v.animating = working
    }

    private func setStatusIcon(_ v: EntityView, _ s: EntityStatus?, _ rec: EntityRecord) {
        var name: String? = nil
        switch s {
        case .noPower?: name = "status_no_power"
        case .lowPower?: name = "status_low_power"
        case .noFuel?: name = "status_no_fuel"
        case .outputFull?: name = rec.kind == .inserter ? nil : "status_output_full"
        case .noResources?: name = "status_no_resources"
        case .noRecipe?: name = rec.kind == .assemblingMachine ? "status_no_recipe" : nil
        default: name = nil
        }
        if let n = name {
            if v.status == nil {
                let sp = SKSpriteNode(); sp.zPosition = 5
                sp.size = CGSize(width: S * 0.55, height: S * 0.55)
                v.node.addChild(sp); v.status = sp
            }
            let sz = v.node.size
            v.status?.position = CGPoint(x: sz.width / 2 - S * 0.3, y: sz.height / 2 - S * 0.3)
            v.status?.texture = SpriteCatalog.shared.texture(n)
            v.status?.isHidden = false
        } else { v.status?.isHidden = true }
    }

    // MARK: Per-frame dynamic parts

    private func updateInserters(_ w: World) {
        for (id, v) in views where v.kind == .inserter {
            guard let arm = v.arm, let hand = v.hand, !v.ghost else { v.arm?.isHidden = true; v.hand?.isHidden = true; continue }
            let rec = w.entities[id]
            guard rec.isAlive else { continue }
            let c = rec.center
            let hp = w.inserters.handPosition(of: id)
            let base = scenePoint(c.x, c.y), tip = scenePoint(hp.x, hp.y)
            let dx = tip.x - base.x, dy = tip.y - base.y
            let len = max(4, (dx * dx + dy * dy).squareRoot())
            arm.isHidden = false; hand.isHidden = false
            arm.position = base
            arm.size = CGSize(width: len, height: S * 0.22)
            arm.zRotation = atan2(dy, dx)
            hand.position = tip
            hand.zRotation = arm.zRotation
            let held = w.inserters.heldStack(of: id)
            if !held.isEmpty {
                if hand.children.isEmpty {
                    let it = SKSpriteNode(); it.size = CGSize(width: S * 0.35, height: S * 0.35); it.zPosition = 1
                    hand.addChild(it)
                }
                (hand.children.first as? SKSpriteNode)?.texture = SpriteCatalog.shared.texture("i_\(w.db.items[Int(held.item)].id)")
                hand.children.first?.isHidden = false
            } else { hand.children.first?.isHidden = true }
        }
    }

    /// Items on the ground: up to 4 icons per tile in a 2×2 pattern.
    private func updateGroundItems(_ w: World) {
        let center = cameraCenter.tile
        let moved = abs(center.x - groundCenter.x) > 2 || abs(center.y - groundCenter.y) > 2
            || abs(zoom - groundZoom) > 0.05            // zooming out reveals tiles outside the last synced rect
        guard w.ground.revision != groundRevision || moved else { return }
        groundRevision = w.ground.revision; groundCenter = center; groundZoom = zoom
        var used = 0
        let isz = CGSize(width: S * 0.4, height: S * 0.4)
        let offs: [(Double, Double)] = [(0.3, 0.3), (0.7, 0.35), (0.35, 0.72), (0.7, 0.7)]
        w.ground.forEach(in: visibleRect(margin: 2)) { p, stacks in
            var k = 0
            for s in stacks {
                for _ in 0..<min(Int(s.count), 4 - k) {
                    let n: SKSpriteNode
                    if used < groundPool.count { n = groundPool[used] } else {
                        n = SKSpriteNode(); n.size = isz; n.zPosition = 19; itemLayer.addChild(n); groundPool.append(n)
                    }
                    n.isHidden = false
                    n.texture = SpriteCatalog.shared.texture("i_\(w.db.items[Int(s.item)].id)")
                    n.position = scenePoint(Double(p.x) + offs[k].0, Double(p.y) + offs[k].1)
                    used += 1; k += 1
                }
                if k >= 4 { break }
            }
        }
        var i = used
        while i < groundPool.count && !groundPool[i].isHidden { groundPool[i].isHidden = true; i += 1 }
    }

    /// Copy rectangle while dragging; translucent ghost preview of the clipboard in paste mode.
    private func updateCopyPaste(_ w: World, _ c: GameController) {
        if c.mode == .copy, let a = c.copyStart, let b = c.copyEnd {
            let r = GameController.rect(a, b)
            copyRectNode.path = CGPath(rect: CGRect(x: 0, y: 0, width: CGFloat(r.w) * S, height: CGFloat(r.h) * S), transform: nil)
            copyRectNode.position = CGPoint(x: CGFloat(r.x) * S, y: -CGFloat(r.maxY) * S)
            copyRectNode.isHidden = false
        } else { copyRectNode.isHidden = true }

        guard c.mode == .paste, let t = c.previewTile, let bp = c.pasteBlueprint, let o = c.pasteOrigin(t) else {
            pasteKey = nil
            var i = 0
            while i < pastePool.count && !pastePool[i].isHidden { pastePool[i].isHidden = true; i += 1 }
            return
        }
        var h = Hasher()
        h.combine(o.x); h.combine(o.y); h.combine(c.pasteRotation); h.combine(c.clipboardVersion); h.combine(Theme.colorblind)
        let key = h.finalize()
        guard key != pasteKey || w.tick &- pasteTick >= 15 || w.tick < pasteTick else { return }
        pasteKey = key; pasteTick = w.tick
        var used = 0
        for e in w.blueprintPreview(bp, at: o) {
            let p = w.db.entities[e.proto]
            let d = SpriteNames.dirSuffix(e.direction)
            var names = ["e_\(p.id)_\(d)", "e_\(p.id)"]
            if p.kind == .transportBelt { names.insert("belt_\(p.id)_straight_\(d)_f0", at: 0) }
            if p.kind == .inserter { names.insert("ins_\(p.id)_base", at: 0) }
            if p.kind == .pipe { names.insert("pipe_0", at: 0) }
            let n: SKSpriteNode
            if used < pastePool.count { n = pastePool[used] } else {
                n = SKSpriteNode(); n.alpha = 0.55; n.colorBlendFactor = 0.5; n.zPosition = 44
                overlayLayer.addChild(n); pastePool.append(n)
            }
            let (fw, fh) = w.footprint(e.proto, e.direction)
            n.texture = SpriteCatalog.shared.texture(firstOf: names)
            n.size = CGSize(width: CGFloat(fw) * S, height: CGFloat(fh) * S)
            n.position = scenePoint(Double(e.origin.x) + Double(fw) / 2, Double(e.origin.y) + Double(fh) / 2)
            n.color = e.ok ? (Theme.colorblind == "off" ? UIColor(red: 0.35, green: 0.8, blue: 1, alpha: 1) : Theme.goodUI) : Theme.badUI
            n.isHidden = false
            used += 1
        }
        var i = used
        while i < pastePool.count && !pastePool[i].isHidden { pastePool[i].isHidden = true; i += 1 }
    }

    private func updateBeltItems(_ w: World) {
        var used = 0
        if zoom >= 0.45 {
            let vis = visibleRect(margin: 1)
            let db = w.db
            let isz = CGSize(width: S * 0.42, height: S * 0.42)
            w.belts.forEachItem(in: vis) { item, x, y in
                let n: SKSpriteNode
                if used < itemPool.count { n = itemPool[used] } else {
                    n = SKSpriteNode(); n.size = isz; n.zPosition = 21; itemLayer.addChild(n); itemPool.append(n)
                }
                n.isHidden = false
                n.position = scenePoint(x, y)
                let tex = SpriteCatalog.shared.texture("i_\(db.items[item].id)")
                if n.texture !== tex { n.texture = tex }
                used += 1
            }
        }
        var i = used
        while i < itemPool.count && !itemPool[i].isHidden { itemPool[i].isHidden = true; i += 1 }
    }

    private func updateCharacter(_ w: World, dt: Double) {
        let pl = w.player!
        characterNode.position = scenePoint(pl.position.x, pl.position.y)
        let d = SpriteNames.dirSuffix(pl.facing)
        if pl.isMoving {
            walkPhase += dt * 8
            let f = Int(walkPhase) % 4
            characterNode.texture = SpriteCatalog.shared.texture(firstOf: ["char_\(d)_f\(f)", "char_s_idle"])
        } else {
            characterNode.texture = SpriteCatalog.shared.texture(firstOf: ["char_\(d)_idle", "char_s_idle"])
        }
    }

    private func updateWires(_ w: World) {
        let path = CGMutablePath()
        for (a, b) in w.power.wires(in: visibleRect(margin: 4)) {
            path.move(to: scenePoint(a.x, a.y - 0.35))
            path.addLine(to: scenePoint(b.x, b.y - 0.35))
        }
        wireNode.path = path
    }

    private func updateOverlay(_ w: World, _ c: GameController) {
        // selection
        if let h = c.selected, let e = w.entities.resolve(h) {
            let r = w.entities[e].rect
            selectionNode.isHidden = false
            selectionNode.path = CGPath(roundedRect: CGRect(x: 0, y: 0, width: CGFloat(r.w) * S, height: CGFloat(r.h) * S),
                                        cornerWidth: 3, cornerHeight: 3, transform: nil)
            selectionNode.position = CGPoint(x: CGFloat(r.x) * S, y: -CGFloat(r.maxY) * S)
        } else { selectionNode.isHidden = true }
        // reach circle + build preview
        let showReach = c.mode != .explore && c.settings.showReachCircle && !w.settings.casualReach
        reachNode.isHidden = !showReach
        if showReach {
            reachNode.position = scenePoint(w.player.position.x, w.player.position.y)
            reachNode.setScale(CGFloat(Character.buildReach) * S / 320)
        }
        if c.mode == .build, c.buildItem >= 0, let t = c.previewTile {
            let proto = w.db.itemPlaceResult[c.buildItem]
            if proto >= 0 {
                let origin = c.buildOrigin(proto: proto, tile: t)
                let (fw, fh) = w.footprint(proto, c.buildDirection)
                let p = w.db.entities[proto]
                let d = SpriteNames.dirSuffix(c.buildDirection)
                var names = ["e_\(p.id)_\(d)", "e_\(p.id)"]
                if p.kind == .transportBelt { names.insert("belt_\(p.id)_straight_\(d)_f0", at: 0) }
                if p.kind == .inserter { names.insert("ins_\(p.id)_base", at: 0) }
                if p.kind == .undergroundBelt { names.insert("e_\(p.id)_in_\(d)", at: 0) }
                previewNode.texture = SpriteCatalog.shared.texture(firstOf: names)
                previewNode.size = CGSize(width: CGFloat(fw) * S, height: CGFloat(fh) * S)
                previewNode.position = scenePoint(Double(origin.x) + Double(fw) / 2, Double(origin.y) + Double(fh) / 2)
                let ok = w.placementError(proto: proto, origin: origin, direction: c.buildDirection) == nil
                    || isFastReplace(w, proto, origin, c.buildDirection)
                previewNode.color = ok ? Theme.goodUI : Theme.badUI
                setValidityGlyph(ok, at: previewNode.position, size: previewNode.size)
                previewNode.isHidden = false
                let io = w.ioPoints(proto: proto, origin: origin, dir: c.buildDirection)
                if let i = io.input { ioInNode.position = scenePoint(i.x, i.y); ioInNode.isHidden = false } else { ioInNode.isHidden = true }
                if let o = io.output { ioOutNode.position = scenePoint(o.x, o.y); ioOutNode.isHidden = false } else { ioOutNode.isHidden = true }
                ioInNode.setScale(S / 32); ioOutNode.setScale(S / 32)
            } else if w.db.itemPlaceTile[c.buildItem] >= 0 {
                previewNode.texture = SpriteCatalog.shared.texture("tile_\(w.db.tiles[w.db.itemPlaceTile[c.buildItem]].id)_v0")
                previewNode.size = CGSize(width: S, height: S)
                previewNode.position = scenePoint(Double(t.x) + 0.5, Double(t.y) + 0.5)
                previewNode.color = Theme.goodUI
                previewNode.isHidden = false
                // floor tiles have no validity/IO markers: don't leave the last entity preview's ones behind
                validityLabel.isHidden = true; ioInNode.isHidden = true; ioOutNode.isHidden = true
            }
        } else { previewNode.isHidden = true }
        if previewNode.isHidden || c.mode != .build { validityLabel.isHidden = true }
        if previewNode.isHidden || c.mode != .build { ioInNode.isHidden = true; ioOutNode.isHidden = true }
    }

    private func isFastReplace(_ w: World, _ proto: Int, _ origin: TilePos, _ dir: Direction) -> Bool {
        guard let g = w.db.entities[proto].fastReplaceGroup, let e = w.entity(at: origin) else { return false }
        let rec = w.entities[e]
        return w.db.entities[Int(rec.proto)].fastReplaceGroup == g && rec.origin == origin
    }
}

