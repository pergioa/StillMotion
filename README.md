# StillMotion

StillMotion is a native macOS 14+ menu-bar utility that loops a chosen local video on each display behind Finder desktop icons and freezes every current frame while a full-screen application is visible.

## Architecture

- `AppModel` owns persisted user intent and applies a single `PlaybackPolicy` to all displays.
- `MediaImportService` validates AVFoundation playability and video tracks, enforces the 1 GB limit, and safely persists an independent video assignment for each display UUID.
- `WallpaperCoordinator` maintains one low-level borderless window and one muted `AVQueuePlayer`/`AVPlayerLooper` per `NSScreen`. It also applies a cached still frame from each video as that display's system wallpaper so Mission Control, Show Desktop, and Space animations use matching imagery.
- `FullScreenDetector` combines workspace and display notifications with a 1 second polling fallback. It classifies visible layer-0 Core Graphics windows against full `CGDisplayBounds` values.
- `SystemActivityObserver` pauses playback for sleep, display sleep, and inactive login sessions.

## Public API limitation

macOS does not expose a public API for enumerating windows in inactive Spaces. StillMotion only inspects the on-screen windows in currently visible Spaces. It detects a full-screen app on any connected display while that app's Space is visible, but intentionally does not use private CGS/Spaces APIs to inspect hidden Spaces.

macOS also does not include third-party desktop windows in every system transition. StillMotion uses the public `NSWorkspace` desktop-image API to synchronize a representative still frame; video remains live on the desktop but may appear frozen during system-owned animations.

## Build

Open `StillMotion.xcodeproj`, select the `StillMotion` scheme, and run. The app is sandboxed, uses the user-selected read-only file entitlement, and has `LSUIElement` enabled so it does not appear in the Dock.

Command-line validation with full Xcode:

```sh
xcodebuild -project StillMotion.xcodeproj -scheme StillMotion -destination 'platform=macOS' build test
```

When full Xcode is unavailable, the same logic can be checked with the Swift command-line toolchain:

```sh
swift run StillMotionLogicChecks
```
