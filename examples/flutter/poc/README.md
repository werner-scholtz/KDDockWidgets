# poc

Flutter POC for KDDockWidgets.

This POC requires Flutter's `master` branch. It depends on Flutter's
experimental windowing APIs and internal `_window.dart` surface, so it should
not be run against stable or beta SDKs.

This example exercises the current native multi-window drag architecture around
Flutter's experimental `WindowRegistry` / `RegularWindowController` API.

It keeps the drag interaction rooted in the source window and uses a platform
native bridge to supply cross-window hover, drag completion, and whole-window
docking signals back into the existing Dart docking controller.

Detached windows render the same dock surface, but cross-window reattach still
depends on the frontend supplying a real target-window routing signal. The
example does not guess across windows from synthetic Dart-side window geometry.

## Quick Navigation

- [PLATFORM_CAPABILITIES.md](PLATFORM_CAPABILITIES.md) is the current feature
  matrix by platform.
- [ARCHITECTURE.md](ARCHITECTURE.md) describes the Dart/runtime/native control
  path.
- [WINDOWS.md](WINDOWS.md), [MACOS.md](MACOS.md), [WAYLAND.md](WAYLAND.md), and
  [X11.md](X11.md) contain platform-specific findings and verification notes.

## Requirements

- Flutter `master` branch
- `fvm`
- Linux, Windows, or macOS desktop target
- Flutter windowing enabled via `fvm flutter config --enable-windowing`

This example uses `package:flutter/src/widgets/_window.dart`, so it is pinned to
Flutter `master` via the local `.fvmrc` file.

## Run

```bash
cd examples/flutter/poc
fvm flutter pub get
fvm flutter config --enable-windowing
fvm flutter run -d linux

# or on Windows
fvm flutter run -d windows

# or on macOS
fvm flutter run -d macos
```

## Validate

```bash
cd examples/flutter/poc
fvm flutter test
fvm flutter analyze
```

## Current scope

- On Windows, crossing the detach threshold can create the real detached native
  window during the live drag and keep it following the cursor.
- On macOS, the runner now follows the same broad architecture and includes a
  first-pass native path for live detached-window follow and whole-window
  title-bar docking.
- On Linux/Wayland, new tear-offs still use the safer deferred-detach path and
  whole-window docking uses a fallback header-region gesture instead of title-
  bar parity behavior.
- On Linux/X11, the current multi-window validation path appears blocked
  upstream in Flutter, so X11 should not presently be treated as the main
  behavior signal for this POC.
- Drag a docked tab far enough to start a proxy drag.
- Release outside every dock to create a real secondary window on all supported
  targets, whether that window is materialized during the drag or at drop time.
- Move a tab into another existing window when the frontend can route a real
  target-window hover or drop signal.
- Use `Dock Back` or close the detached window to return that window's tabs to
  the main window.

## Explicit non-goals

- Live handoff of the active drag to a newly created native window on
  Linux/Wayland through public Flutter/GTK APIs.
- General native drag-and-drop outside this Flutter multi-window process.
- Trusting synthetic Dart-side window geometry as a cross-window drop source on
  Wayland.
- Affinity routing or multi-main-window policies.
- Any claim that Wayland detachable-window dragging is solved.
