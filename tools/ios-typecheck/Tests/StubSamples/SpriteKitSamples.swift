// Sample usage of the SpriteKit / UIKit / CoreGraphics / Combine / simd stubs, written against the iOS 17 SDK.
import SpriteKit
import UIKit
import Combine
import simd
import SwiftUI

final class SampleScene: SKScene {
    private let world = SKNode()
    private let cam = SKCameraNode()
    private var lastTime: TimeInterval = 0
    private let atlas = SKTextureAtlas(named: "Sprites")

    override init(size: CGSize) {
        super.init(size: size)
        scaleMode = .resizeFill
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        backgroundColor = SKColor(red: 0.1, green: 0.12, blue: 0.1, alpha: 1)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMove(to view: SKView) {
        view.preferredFramesPerSecond = 60
        view.ignoresSiblingOrder = true
        view.showsFPS = true
        addChild(world)
        addChild(cam)
        camera = cam

        let tex = atlas.textureNamed("tile_sand_v0")
        tex.filteringMode = .nearest
        let sprite = SKSpriteNode(texture: tex, size: CGSize(width: 32, height: 32))
        sprite.position = CGPoint(x: 10, y: 20)
        sprite.zPosition = 1
        sprite.anchorPoint = .zero
        sprite.colorBlendFactor = 0.5
        sprite.color = .red
        sprite.blendMode = .alpha
        sprite.setScale(2)
        sprite.name = "tile"
        world.addChild(sprite)

        let plain = SKSpriteNode(color: .blue, size: CGSize(width: 4, height: 4))
        let named = SKSpriteNode(imageNamed: "belt")
        let fromTex = SKSpriteNode(texture: SKTexture(imageNamed: "x"))
        world.addChild(plain); world.addChild(named); world.addChild(fromTex)

        let rect = SKShapeNode(rect: CGRect(x: 0, y: 0, width: 32, height: 32), cornerRadius: 4)
        rect.strokeColor = .white
        rect.fillColor = UIColor.white.withAlphaComponent(0.2)
        rect.lineWidth = 2
        rect.glowWidth = 0
        let circle = SKShapeNode(circleOfRadius: 8)
        let path = CGMutablePath()
        path.move(to: .zero)
        path.addLine(to: CGPoint(x: 10, y: 10))
        path.addRect(CGRect(x: 0, y: 0, width: 4, height: 4))
        path.closeSubpath()
        let line = SKShapeNode(path: path)
        line.path = CGPath(rect: .zero, transform: nil)
        world.addChild(rect); world.addChild(circle); world.addChild(line)

        let label = SKLabelNode(text: "Iron 12")
        label.fontName = "Menlo-Bold"
        label.fontSize = 12
        label.fontColor = .yellow
        label.horizontalAlignmentMode = .left
        label.verticalAlignmentMode = .center
        world.addChild(label)

        let pulse = SKAction.sequence([
            .scale(to: 1.2, duration: 0.1),
            .scale(to: 1.0, duration: 0.1),
            .wait(forDuration: 0.5),
            .fadeAlpha(to: 0.5, duration: 0.2),
            .run { print("tick") },
        ])
        sprite.run(.repeatForever(pulse), withKey: "pulse")
        label.run(SKAction.sequence([.move(by: CGVector(dx: 0, dy: 20), duration: 0.5), .fadeOut(withDuration: 0.3), .removeFromParent()]))
        circle.run(.moveBy(x: 1, y: 2, duration: 0.1)) { [weak self] in self?.lastTime = 0 }
        sprite.removeAction(forKey: "pulse")
        sprite.removeAllActions()

        SKTextureAtlas.preloadTextureAtlases([atlas]) {}
        atlas.preload {}
        _ = atlas.textureNames.count
        _ = tex.size().width + tex.textureRect().minX
    }

    override func update(_ currentTime: TimeInterval) {
        let dt = lastTime == 0 ? 0 : currentTime - lastTime
        lastTime = currentTime
        cam.position.x += CGFloat(dt) * 10
        cam.setScale(max(0.5, min(cam.xScale, 4)))
        for child in world.children where child.name == "tile" {
            child.zRotation += 0.01
            child.isHidden = !child.isHidden
            child.alpha = 1
        }
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        let p = t.location(in: self)
        let inWorld = world.convert(p, from: self)
        _ = world.contains(inWorld)
        _ = nodes(at: p)
        if let v = view {
            _ = convertPoint(fromView: CGPoint(x: v.bounds.midX, y: v.bounds.midY))
        }
    }

    func bake(pixels: Data, width: Int, height: Int) -> SKTexture {
        let t = SKTexture(data: pixels, size: CGSize(width: width, height: height))
        t.filteringMode = .nearest
        return t
    }

    func bakeCG(pixels: Data, width: Int, height: Int) -> SKTexture? {
        guard let provider = CGDataProvider(data: pixels as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { return nil }
        return SKTexture(cgImage: image)
    }
}

final class TileSprite: SKSpriteNode {
    let tileID: Int
    init(tileID: Int, texture: SKTexture) {
        self.tileID = tileID
        super.init(texture: texture, color: .clear, size: texture.size())
    }
    required init?(coder aDecoder: NSCoder) { fatalError() }
}

@MainActor
final class Haptics {
    private let impact = UIImpactFeedbackGenerator(style: .light)
    private let selection = UISelectionFeedbackGenerator()
    private let notify = UINotificationFeedbackGenerator()
    private var bgTask: UIBackgroundTaskIdentifier = .invalid
    private var cancellables = Set<AnyCancellable>()

    func setUp() {
        impact.prepare()
        impact.impactOccurred()
        impact.impactOccurred(intensity: 0.5)
        selection.selectionChanged()
        notify.notificationOccurred(.success)

        NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
            .sink { [weak self] _ in self?.save() }
            .store(in: &cancellables)
        _ = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in }
        Timer.publish(every: 1.0 / 60.0, on: .main, in: .common)
            .autoconnect()
            .receive(on: DispatchQueue.main)
            .sink { _ in }
            .store(in: &cancellables)

        if UIDevice.current.userInterfaceIdiom == .pad {
            impact.impactOccurred()
        }
    }

    func save() {
        bgTask = UIApplication.shared.beginBackgroundTask { [weak self] in
            guard let self else { return }
            UIApplication.shared.endBackgroundTask(self.bgTask)
            self.bgTask = .invalid
        }
        UIApplication.shared.endBackgroundTask(bgTask)
    }

    func renderIcon() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32))
        let img = renderer.image { ctx in
            UIColor.orange.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
            ctx.cgContext.setFillColor(UIColor.black.cgColor)
            ctx.cgContext.fillEllipse(in: CGRect(x: 8, y: 8, width: 16, height: 16))
        }
        _ = img.pngData()
        _ = UIImage(named: "item_gear") ?? UIImage()
        return img
    }
}

extension UIColor {
    // App-side extension of a stubbed class.
    static let gearforgeAccent = UIColor(red: 0.9, green: 0.6, blue: 0.2, alpha: 1)
}

final class LegacyModel: ObservableObject {
    @Published var score = 0
    let tick = PassthroughSubject<Int, Never>()
}

struct SpriteHost: View {
    @StateObject private var legacy = LegacyModel()
    @State private var scene = SampleScene(size: CGSize(width: 800, height: 600))
    var body: some View {
        SpriteView(scene: scene, preferredFramesPerSecond: 60, options: [.ignoresSiblingOrder, .shouldCullNonVisibleNodes],
                   debugOptions: [.showsFPS, .showsNodeCount])
            .ignoresSafeArea()
            .onReceive(legacy.tick) { legacy.score = $0 }
            .overlay(alignment: .top) { Text("\(legacy.score)") }
    }
}

func vectorMath() -> Float {
    let a = SIMD2<Float>(1, 2), b = simd_float2(3, 4)
    let t = CGAffineTransform(translationX: 1, y: 2).scaledBy(x: 2, y: 2)
    _ = CGPoint(x: 1, y: 1).applying(t)
    _ = CGVector(dx: 1, dy: 0)
    return length(a - b) + simd_distance(a, b) + dot(normalize(a), b)
}
