// Gearforge — App / Rendering
// Single-finger touch interpretation (GDD §4.2–4.5): floating joystick zone, tap, double-tap, long-press (350 ms),
// drag. Multi-finger gestures (pinch / two-finger pan / twist / two-finger tap) are UIKit recognizers in
// InputController; this state machine only sees touches the recognizers did not claim.
// Pure Swift (Foundation only) so it can be tested off-device. All points are in SKView/UIKit coordinates (y down).
// Owner: Rendering engineer.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

public enum GestureEvent: Equatable, Sendable {
    /// Joystick appeared at `origin` (base centre).
    case joystickBegan(origin: CGPoint)
    /// Analog stick vector in screen space (x right, y DOWN), magnitude 0...1 after the dead zone.
    /// Because world y also grows south, it maps 1:1 to `Character.moveInput`.
    case joystickMoved(dx: Double, dy: Double, origin: CGPoint, knob: CGPoint)
    case joystickEnded
    case tap(CGPoint)
    /// Second tap of a double tap (the first tap was already delivered as `.tap`).
    case doubleTap(CGPoint)
    case longPressBegan(CGPoint)
    case longPressMoved(CGPoint)
    case longPressEnded(CGPoint)
    case dragBegan(start: CGPoint, current: CGPoint)
    case dragMoved(CGPoint)
    case dragEnded(CGPoint)
    /// The world touch was cancelled (e.g. a pinch started): discard any preview.
    case worldTouchCancelled
}

public struct GestureConfig: Equatable, Sendable {
    public var viewSize: CGSize = CGSize(width: 844, height: 390)
    public var joystickEnabled = true
    /// Fraction of the screen width (from the left, or the right when left-handed) that spawns the joystick.
    public var joystickZoneFraction: CGFloat = 0.35
    public var leftHanded = false
    public var joystickFloating = true
    /// Base radius in points (full deflection).
    public var joystickRadius: CGFloat = 60
    public var deadZone: Double = 0.10
    public var tapSlop: CGFloat = 12
    public var longPressDuration: Double = 0.35
    public var doubleTapInterval: Double = 0.30
    public var doubleTapSlop: CGFloat = 40
    /// A joystick touch released this quickly without moving counts as a tap.
    public var joystickTapDuration: Double = 0.22
    public init() {}

    public func inJoystickZone(_ p: CGPoint) -> Bool {
        guard joystickEnabled else { return false }
        let zone = viewSize.width * joystickZoneFraction
        return leftHanded ? p.x > viewSize.width - zone : p.x < zone
    }

    /// Fixed-joystick base position (when `joystickFloating == false`).
    public var fixedOrigin: CGPoint {
        let inset = joystickRadius + 40
        return CGPoint(x: leftHanded ? viewSize.width - inset : inset, y: viewSize.height - inset)
    }
}

public struct GestureInterpreter: Sendable {
    public var config = GestureConfig()

    private struct Joy { var id: Int; var origin: CGPoint; var start: CGPoint; var startTime: Double; var moved: Bool }
    private enum WorldState { case pending, dragging, longPress }
    private struct WorldTouch { var id: Int; var start: CGPoint; var current: CGPoint; var startTime: Double; var state: WorldState }

    private var joy: Joy?
    private var world: WorldTouch?
    private var lastTapTime: Double = -10
    private var lastTapPoint: CGPoint = .zero

    public init() {}

    public var joystickActive: Bool { joy != nil }
    public var worldTouchActive: Bool { world != nil }
    public var isDragging: Bool { world?.state == .dragging }

    // MARK: Input

    public mutating func began(id: Int, at p: CGPoint, time: Double) -> [GestureEvent] {
        if joy == nil && config.inJoystickZone(p) {
            let origin = config.joystickFloating ? p : config.fixedOrigin
            joy = Joy(id: id, origin: origin, start: p, startTime: time, moved: false)
            var ev: [GestureEvent] = [.joystickBegan(origin: origin)]
            if !config.joystickFloating { ev.append(joystickVector(knobAt: p)) }
            return ev
        }
        guard world == nil else { return [] }            // ignore extra fingers (recognizers handle 2-finger)
        world = WorldTouch(id: id, start: p, current: p, startTime: time, state: .pending)
        return []
    }

    public mutating func moved(id: Int, to p: CGPoint, time: Double) -> [GestureEvent] {
        if var j = joy, j.id == id {
            if distance(p, j.start) > config.tapSlop { j.moved = true }
            // Floating stick: drag the base along when the finger leaves the radius.
            if config.joystickFloating {
                let d = distance(p, j.origin)
                if d > config.joystickRadius {
                    let k = (d - config.joystickRadius) / d
                    j.origin = CGPoint(x: j.origin.x + (p.x - j.origin.x) * k, y: j.origin.y + (p.y - j.origin.y) * k)
                }
            }
            joy = j
            return [joystickVector(knobAt: p)]
        }
        guard var w = world, w.id == id else { return [] }
        w.current = p
        var out: [GestureEvent] = []
        switch w.state {
        case .pending:
            if distance(p, w.start) > config.tapSlop {
                w.state = .dragging
                out.append(.dragBegan(start: w.start, current: p))
            }
        case .dragging:
            out.append(.dragMoved(p))
        case .longPress:
            out.append(.longPressMoved(p))
        }
        world = w
        return out
    }

    public mutating func ended(id: Int, at p: CGPoint, time: Double) -> [GestureEvent] {
        if let j = joy, j.id == id {
            joy = nil
            var out: [GestureEvent] = [.joystickEnded]
            if !j.moved && time - j.startTime <= config.joystickTapDuration { out.append(contentsOf: registerTap(p, time: time)) }
            return out
        }
        guard let w = world, w.id == id else { return [] }
        world = nil
        switch w.state {
        case .pending:
            if time - w.startTime >= config.longPressDuration {
                // Released exactly at the threshold before tick() fired: treat as a (short) long press.
                return [.longPressBegan(w.start), .longPressEnded(p)]
            }
            return registerTap(p, time: time)
        case .dragging: return [.dragEnded(p)]
        case .longPress: return [.longPressEnded(p)]
        }
    }

    public mutating func cancelled(id: Int) -> [GestureEvent] {
        if let j = joy, j.id == id { joy = nil; return [.joystickEnded] }
        guard let w = world, w.id == id else { return [] }
        world = nil
        return w.state == .longPress ? [.longPressEnded(w.current), .worldTouchCancelled] : [.worldTouchCancelled]
    }

    /// Cancels everything (scene disappeared, mode change...).
    public mutating func cancelAll() -> [GestureEvent] {
        var out: [GestureEvent] = []
        if joy != nil { joy = nil; out.append(.joystickEnded) }
        if let w = world {
            world = nil
            if w.state == .longPress { out.append(.longPressEnded(w.current)) }
            out.append(.worldTouchCancelled)
        }
        return out
    }

    /// Call once per frame: detects long presses of a stationary finger.
    public mutating func tick(time: Double) -> [GestureEvent] {
        guard var w = world, w.state == .pending, time - w.startTime >= config.longPressDuration else { return [] }
        w.state = .longPress
        world = w
        return [.longPressBegan(w.start)]
    }

    // MARK: Helpers

    private mutating func registerTap(_ p: CGPoint, time: Double) -> [GestureEvent] {
        if time - lastTapTime <= config.doubleTapInterval && distance(p, lastTapPoint) <= config.doubleTapSlop {
            lastTapTime = -10
            return [.tap(p), .doubleTap(p)]
        }
        lastTapTime = time
        lastTapPoint = p
        return [.tap(p)]
    }

    private func joystickVector(knobAt p: CGPoint) -> GestureEvent {
        guard let j = joy else { return .joystickMoved(dx: 0, dy: 0, origin: .zero, knob: .zero) }
        let dx = Double(p.x - j.origin.x), dy = Double(p.y - j.origin.y)
        let len = (dx * dx + dy * dy).squareRoot()
        let r = Double(config.joystickRadius)
        let mag = min(1, len / r)
        let knob: CGPoint
        if len > r { knob = CGPoint(x: j.origin.x + CGFloat(dx / len * r), y: j.origin.y + CGFloat(dy / len * r)) }
        else { knob = p }
        guard len > 0.0001, mag > config.deadZone else { return .joystickMoved(dx: 0, dy: 0, origin: j.origin, knob: knob) }
        let m = (mag - config.deadZone) / (1 - config.deadZone)
        return .joystickMoved(dx: dx / len * m, dy: dy / len * m, origin: j.origin, knob: knob)
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x, dy = a.y - b.y
        return (dx * dx + dy * dy).squareRoot()
    }
}
