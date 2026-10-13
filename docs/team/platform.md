# Platform / build — Gearforge iOS

Owner: iOS Platform / Build Engineer. Covers the Xcode project, the Linux typecheck harness, and how the client
builds and runs the game.

## 1. Running the game on the Mac (client)

Requirements: **Xcode 15 or newer** (Xcode 16 recommended), iOS 17+ simulator or device.

1. Unpack the checkpoint (or `git clone` the bundle) anywhere, keep the folder structure intact
   (`App/` and `Core/` must stay siblings — the app links the local package `../Core`).
2. Open **`App/Gearforge.xcodeproj`** (double-click, or `open App/Gearforge.xcodeproj`).
   Xcode resolves the local Swift package *GearforgeCore* automatically (shown under "Package Dependencies").
3. Select the **Gearforge** project in the navigator → target **Gearforge** → **Signing & Capabilities** →
   *Team*: pick your Apple ID / team. (Signing is *Automatic*; the bundle id is `com.gearforge.game` — if Xcode
   says it is taken, change it to something unique like `com.<yourname>.gearforge`.)
4. In the toolbar choose the **Gearforge** scheme and an **iPhone or iPad simulator** (or a connected device;
   first device run: enable Developer Mode on the device and trust the developer certificate under
   Settings → General → VPN & Device Management).
5. **Run** (⌘R). The game launches in landscape, full screen, status bar hidden.

Release build: Product → Scheme → Edit Scheme → Run → Build Configuration = Release (or Product → Archive).
Release uses `-O` with whole-module optimization.

## 2. The Xcode project is generated

`App/Gearforge.xcodeproj` is written by **`tools/ios/gen_xcodeproj.py`** (pure Python 3, no XcodeGen, no Xcode).
The script is the source of truth; it scans the tree at generation time:

| Input | Becomes |
|---|---|
| every `App/Sources/**/*.swift` | Sources phase; Xcode groups mirror the folders (App, UI, Bridge, Rendering, Art, …) |
| `App/Resources/*.atlas` | folder reference of type `folder.skatlas` → Xcode compiles a SpriteKit texture atlas (`SKTextureAtlas(named: "Sprites")`) |
| `App/Resources/*.xcassets` | asset catalog (an `Assets.xcassets` with an empty `AppIcon` set is created if missing) |
| `App/Resources/**/*.json` (+ audio `.caf/.wav/.m4a/.mp3/.aif`, fonts `.ttf/.otf`) | Copy Bundle Resources |
| `../Core` | `XCLocalSwiftPackageReference` + product `FactoryCore` linked into the app |

Regenerate (Linux or Mac):

```sh
python3 tools/ios/gen_xcodeproj.py          # writes project.pbxproj + shared scheme, validates first
python3 tools/ios/gen_xcodeproj.py --check  # exit 1 if the committed project is stale (CI/checkpoint)
python3 tools/ios/pbxproj_validate.py App/Gearforge.xcodeproj/project.pbxproj   # standalone validation
```

* Output is deterministic (object ids = sha1 of stable keys), so re-running without file changes rewrites
  byte-identical files ("unchanged"); adding a file only adds lines.
* **When new Swift files or resources appear, the project must be regenerated** — otherwise Xcode silently does not
  compile them. The lead re-runs the generator before every checkpoint (`tools/checkpoint.sh` does it
  automatically and warns if the result is uncommitted). On the Mac the client can either re-run the script or
  use Xcode's *File → Add Files to "Gearforge"…* — but the next regeneration overwrites manual project edits,
  so permanent build-setting changes go into `gen_xcodeproj.py`.
* The validator parses the OpenStep plist fully and checks: every referenced id exists and has the right `isa`;
  every `PBXBuildFile` has a valid fileRef/productRef and sits in exactly one phase; every file reference is in
  exactly one group; no orphans/cycles; package product linked in Frameworks; every group path resolves on disk;
  every `.swift` under `App/Sources` is compiled.

Key build settings (target): iOS 17.0, Swift 5 language mode (`SWIFT_VERSION = 5.0`), iPhone + iPad
(`TARGETED_DEVICE_FAMILY = 1,2`), landscape left/right only (iPhone and iPad), `UIRequiresFullScreen`,
`UIStatusBarHidden`, generated Info.plist (display name *Gearforge*, launch screen + scene manifest generated),
`AppIcon` asset, automatic signing with an empty team.

## 3. Typechecking the app on Linux

```sh
tools/ios-typecheck/run.sh          # exit 1 + compiler diagnostics on failure
```

Compiles a fresh copy of `App/Sources/**` against API stubs of SwiftUI, SpriteKit, UIKit, Combine, CoreGraphics
and simd plus the real FactoryCore. See `tools/ios-typecheck/README.md` for coverage, limitations and the rule for
extending stubs (mirror the real Apple signature exactly). App code can exclude un-stubbable bits with
`#if !GEARFORGE_TYPECHECK` (e.g. `#Preview`). Guard `Compression` with `#if canImport(Compression)`.

Recommended pre-checkpoint sequence for the lead:

```sh
(cd Core && swift build && swift test)
tools/ios-typecheck/run.sh
python3 tools/ios/gen_xcodeproj.py && git add -A && git commit -m "..."
tools/checkpoint.sh
```

## 4. Known risks

* **Never built in real Xcode from this environment.** The pbxproj follows Xcode 15's format (objectVersion 60,
  `XCLocalSwiftPackageReference`) and passes a strict structural validator, but the first open on the Mac is the
  real test. If Xcode refuses the project, the fallback is: File → New → Project (iOS App, SwiftUI) → drag
  `App/Sources`, `App/Resources` in → File → Add Package Dependencies → Add Local… → `Core`; report the error so the
  generator can be fixed.
* **The typecheck harness is not the iOS SDK**: availability (iOS 17 vs 18), some overload resolution and
  concurrency diagnostics differ; unstubbed APIs produce false errors. A green harness strongly reduces but does
  not eliminate Xcode compile errors.
* **Swift 6 compiler in Xcode 16, Swift 5 mode**: concurrency checks are mostly warnings; the SDK marks
  UIKit/SpriteKit node classes `@MainActor`. Keep scene/node code on the main actor.
* **AppIcon is empty** (builds fine for development; App Store submission needs a 1024×1024 icon in
  `App/Resources/Assets.xcassets/AppIcon.appiconset`).
* **Bundle id / signing**: `com.gearforge.game` may be registered by someone else; the client changes it locally
  (or we change `BUNDLE_ID` in the generator).
* **Local package path**: moving `App/` without `Core/` breaks the package reference.
* **Status at hand-off of this change**: `tools/ios-typecheck/run.sh` currently reports pre-existing errors in
  `App/Sources/Bridge` (duplicate `InteractionMode`/`HUDState`/`CraftQueueEntryView` declarations in
  `GameController.swift` and `GameControllerTypes.swift`; `CoreAdapters.swift` calls
  `MiningSystem.hasMinableResource`, which FactoryCore does not have). These would fail the Xcode build too and
  need fixing by the Bridge owner. `App/Sources/App/GearforgeApp.swift` typechecks cleanly on its own.
