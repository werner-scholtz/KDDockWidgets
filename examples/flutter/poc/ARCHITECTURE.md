# Architecture

Date: 2026-05-27

This note describes the control path for the Flutter multi-window POC. It
focuses on where the Dart controller/runtime layer meets the native
per-platform drag bridges.

## Why this shape

The experimental Flutter multi-window API is promising, but platform behavior
still differs a lot.

The POC keeps most policy in one place and asks each native bridge for the
signals Flutter does not expose consistently:

- keep the model and docking policy in Dart
- use platform-native bridges for cross-window targeting and drag completion
- create or attach real Flutter windows according to each platform's proven
   capabilities

Wayland is the main reason this stays explicit. Dart-side positions are
window-local, meaning relative to one window. Flutter does not expose enough
reliable cross-window state to treat those coordinates as desktop-global, so
the POC does not infer cross-window drops from Dart-side window geometry.

## Main Pieces

- `lib/src/dock_controller.dart` owns the docking model and high-level drag
  state.
- `lib/src/dock_runtime.dart` owns native window creation, native window
  registration, and synchronization between the model and Flutter's windowing
  API.
- `lib/src/native_dock_drag.dart` owns the platform capability surface,
  method-channel event handling, and the transition from Dart drag state to
  platform-native drag tracking.
- `lib/src/experimental_window_api.dart` and its per-platform backends expose
  native window handles for Flutter-created windows.
- The Linux, Windows, and macOS runner bridges expose the
  `KddwDockDragBridge_*` surface consumed by the Dart FFI backends.

## Root Window Registration

The root window's native handle is not always available synchronously at
startup.

The runtime therefore uses two registration paths in
`lib/src/dock_runtime.dart`:

- If the root window is owned by a Dart `ExperimentalWindowController`, it is
  registered after a frame with `_registerWindowAfterFrame(...)`.
- If the root window is bootstrap-owned by the platform path, the runtime asks
  the native bridge for `mainWindowHandle` and retries registration after frame
  until the handle becomes available or the retry budget is exhausted.

This delay is intentional. It avoids binding native drag tracking before
Flutter's window and controller pair is fully set up.

## Tab Tear-Off Path

The same-app tear-off path is:

1. Dart starts drag state in `DockController.beginDockedTabDrag(...)`.
2. `NativeDockDragCoordinator.startDrag(...)` asks the active platform bridge
   to begin native tracking.
3. The native bridge emits `dragHover` and `dragLeave` while the pointer moves
   across already registered windows.
4. Dart updates hover state through `DockController.updateHoveredDockTarget(...)`.
5. If the drag crosses the detach threshold, the controller creates a detached
   window model entry.
6. `DockRuntimeCoordinator.syncDetachedNativeWindows(...)` decides whether the
   real Flutter window should be created immediately or deferred until drop,
   based on `supportsLiveDetachedWindowDuringDrag`.
7. If the platform supports live detached follow, the runtime creates the real
   detached Flutter window during the drag and then calls
   `attachDragWindow(...)` once that window has been registered natively.
8. On mouse release, the native bridge emits `dragEnded`, which flows back into
   `DockRuntimeCoordinator._handleNativeDragFinished()` and then into
   `DockController.endDockedTabDrag()`.

## Whole-Window Docking Path

The whole-window docking path reuses the same model-level target/docking logic,
but it is started by a different native signal:

1. The native bridge detects a detached-window move gesture that should be
   treated as docking.
2. The bridge emits `windowHeaderDragStarted`.
3. Dart enters whole-window drag state through
   `DockController.beginWindowHeaderDrag(...)`.
4. The native bridge continues emitting hover updates while the window moves.
5. The bridge emits `windowHeaderDragEnded` with the final dock target, if any.
6. Dart completes the operation through
   `DockRuntimeCoordinator._handleWindowHeaderDragFinished()` and
   `DockController.endWindowHeaderDrag(...)`.

The exact gesture differs by platform:

- Windows uses native title-bar move-loop observation.
- macOS uses native event monitoring around AppKit window moves.
- Wayland uses a dedicated fallback header dock region rather than title-bar
  parity behavior.

## Runtime Gates

The runtime avoids hard-coding platform names into the tab tear-off flow.
Instead it asks the native backend for the pieces that change window creation
or registration:

- `supportsLiveDetachedWindowDuringDrag`
- `mainWindowHandle`

Whole-window docking is event-driven rather than controlled by a separate
Dart-side capability switch. When a platform bridge can detect a detached-
window docking gesture, it emits `windowHeaderDragStarted` /
`windowHeaderDragEnded` and the existing Dart docking model completes the
operation.

## Files To Read Together

The most useful files to read together are:

- `lib/src/dock_controller.dart`
- `lib/src/dock_runtime.dart`
- `lib/src/native_dock_drag.dart`
- `lib/src/experimental_window_api.dart`
- `windows/runner/dock_drag_bridge.cpp`
- `macos/Runner/dock_drag_bridge.mm`
- `linux/runner/dock_drag_bridge.cc`

Together these files define the boundary between the Dart model and the
platform-native drag and move tracking paths.