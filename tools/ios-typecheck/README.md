# ios-typecheck — compile App/Sources on Linux

A SwiftPM package that typechecks the iOS app sources (`App/Sources/**`) with the Linux Swift toolchain, against
hand-written **API stubs** of the Apple frameworks the app uses. It catches compile errors (typos, wrong argument
labels, missing `override`/`required init`, wrong optionality, ViewBuilder misuse, missing imports of
SpriteKit/SwiftUI, FactoryCore API drift) before the code reaches Xcode. Nothing is linked or run.

```sh
tools/ios-typecheck/run.sh             # app sources + stub samples; exit 1 on any error
tools/ios-typecheck/run.sh --app-only  # app sources only
```

Diagnostics are printed with paths rewritten to `App/Sources/...`. First build ≈ 1–2 min (FactoryCore + stubs),
incremental runs a few seconds.

## Layout

| Path | What |
|---|---|
| `Package.swift` | Stub targets + `AppTypecheck` + `StubSamples`; depends on `../../Core` (FactoryCore) |
| `Stubs/SwiftUI`, `Stubs/SpriteKit`, `Stubs/UIKit`, `Stubs/Combine`, `Stubs/CoreGraphics`, `Stubs/simd` | One module per Apple framework, named exactly like the framework |
| `Sources/AppTypecheck/` | **Generated** copy of `App/Sources/**` (refreshed by `run.sh` every run; git-ignored) — never edit |
| `Tests/StubSamples/` | Realistic usage of every stubbed API; a regression test that the stubs accept real-world code |

`AppTypecheck` is compiled with `-D GEARFORGE_TYPECHECK`, so app code can hide the few things that cannot be
stubbed:

```swift
#if !GEARFORGE_TYPECHECK
#Preview { ContentView() }          // macros need Apple's compiler plugins
#endif
```

## What comes from the Linux toolchain (verified on Swift 6.0.3)

* `Foundation` (swift-corelibs): includes `CGFloat`, `CGPoint`, `CGSize`, `CGRect` and their geometry helpers.
  **Not** included: `CGVector`, `CGAffineTransform`, `CGPath`, `CGColor`, `CGImage`, `CGContext` → stubbed in the
  `CoreGraphics` stub module.
* `Dispatch`, `Observation` (`import Observation`, the `@Observable` macro and `withObservationTracking` work).
* Not available on Linux, hence stubbed: `CoreGraphics` (module), `simd` (module; SIMD2/3/4 are stdlib), `Combine`.
* `Compression` is deliberately **not** stubbed: guard its use with `#if canImport(Compression)`; the harness then
  compiles the fallback branch.

Re-exports mirror iOS: `SwiftUI` re-exports Foundation, CoreGraphics, UIKit, Combine, Observation; `SpriteKit` and
`UIKit` re-export Foundation + CoreGraphics (SpriteKit also UIKit). `SpriteView` lives in the SpriteKit stub (on
Apple it is the SwiftUI×SpriteKit cross-import overlay), so files using it need both imports — same as on device.

## Coverage

* **SwiftUI**: App/Scene/WindowGroup, View/ViewBuilder (parameter-pack `buildBlock`, unlimited children like Xcode 15+,
  `buildIf`, `buildEither`, `buildLimitedAvailability`, `buildExpression`), ViewModifier, all common containers and
  controls (stacks, lazy stacks/grids, Grid, ScrollView(+Reader), ForEach incl. `$binding` form, List, Section,
  Button + ButtonStyle/PrimitiveButtonStyle, Toggle, Slider, Stepper, Picker, ProgressView, TextField, Label,
  NavigationStack/Link, GeometryReader, TimelineView), Text/LocalizedStringKey interpolation rules, Font, Color,
  Image, ShapeStyle/gradients/materials, Shape (Rectangle, RoundedRectangle, Circle, Ellipse, Capsule, Path),
  gestures (Drag, Tap, SpatialTap, LongPress, Magnify, MagnificationGesture, Rotate, GestureState), Animation,
  transitions, presentation (sheet, fullScreenCover, alert, confirmationDialog, popover), property wrappers
  (State, Binding, Bindable, Environment incl. `@Environment(Model.self)`, StateObject, ObservedObject,
  EnvironmentObject, AppStorage, GestureState), EnvironmentValues/EnvironmentKey, ~100 View modifiers.
* **SpriteKit**: SKNode, SKScene, SKView, SKCameraNode, SKSpriteNode, SKShapeNode, SKLabelNode, SKCropNode,
  SKEffectNode, SKTexture (incl. `init(data:size:)`, `init(cgImage:)`), SKTextureAtlas, SKAction, SKTransition,
  enums, `UITouch.location(in: SKNode)`, `SpriteView`.
* **UIKit**: UIColor, UIFont, UIImage, UIResponder/UIView/UITouch/UIEvent (minimal), feedback generators,
  UIApplication (notifications, background tasks), UIDevice, UIScreen, UIGraphicsImageRenderer.
* **CoreGraphics**: CGVector, CGAffineTransform, CGPath/CGMutablePath, CGContext, CGImage, CGColor, CGColorSpace,
  CGDataProvider, bitmap enums. `CFData`/`CFString` are aliases of `NSData`/`NSString` so `data as CFData` works.
* **Combine**: Publisher (map/filter/receive(on:)/sink/assign/removeDuplicates), AnyCancellable, subjects,
  ObservableObject/@Published (with the class-only rule), `NotificationCenter.publisher(for:)`, `Timer.publish`.

## Extending the stubs

The app failing with *"cannot find 'X' in scope"* / *"has no member"* for a real Apple API means the stub is
missing it. Add it — **the rule is: mirror the real Apple declaration exactly.**

1. Find the real declaration. On a Mac:
   `$(xcrun --sdk iphoneos --show-sdk-path)/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64-apple-ios.swiftinterface`
   (same pattern for SpriteKit/UIKit), or Apple's documentation "Declaration" box. Never invent a convenience
   overload, never loosen a type, never add a default argument the SDK does not have — a looser stub hides the
   exact errors this harness exists to catch.
2. Copy name, argument labels, generic parameters and constraints, optionality, `throws`/`async`, `@escaping`,
   `@ViewBuilder`, `@MainActor`, `mutating`/`nonmutating`, `class` vs `struct`, designated vs `convenience` init,
   `required` inits.
3. Bodies are always `{ _stub() }` (a `fatalError` that returns `Never`). View modifiers return `some View` via
   `_modified()`; only use a concrete return type where the SDK does (e.g. `Text.bold() -> Text`,
   `Image.resizable() -> Image`, `Shape.fill(...)`).
4. Classes that are main-actor in the SDK (UIResponder subclasses — so every SKNode —, UIApplication, UIDevice,
   UIScreen, feedback generators) are `@MainActor @preconcurrency`, like the SDK as seen from Swift 5 mode.
5. Where the SDK has overloads the compiler disambiguates via attributes we cannot see (e.g. old
   `background(_:alignment:)` vs `background(_:ignoresSafeAreaEdges:)`), mark the legacy one `@_disfavoredOverload`.
6. Add a line exercising the new API to `Tests/StubSamples/` and run `run.sh`.

## Limitations (what Xcode may still reject, or the harness may wrongly reject)

* **Availability is not checked**: the stubs carry no `@available(iOS …)` annotations, so an API newer than the
  iOS 17 deployment target (if one is ever added to a stub) compiles here but fails in Xcode. Keep stubs to
  iOS ≤ 17 APIs.
* Only the subset above is stubbed; real-but-unstubbed APIs fail here (false positive → extend the stub).
* Opaque result types differ (every modifier returns `ModifiedContent<Self, EmptyModifier>`), so code that names
  concrete SwiftUI modifier types, or relies on two `some View` values having the same type, may behave
  differently. Type-checker performance ("expression too complex") is not representative.
* Overload ranking and actor-isolation/Sendable diagnostics are approximations of the SDK's.
* Deprecation warnings are reproduced only for `UIScreen.main`, `onChange(of:perform:)`, `MagnificationGesture`.
* simd functions are generic over floating-point SIMD types (the SDK has concrete overloads).
* swift-corelibs Foundation differs slightly from Apple Foundation (a few APIs missing or with different
  optionality); a Foundation-only error here may not exist on Apple platforms, and vice versa.
* Resources (atlas/image names, JSON) and runtime behaviour are not checked at all.
