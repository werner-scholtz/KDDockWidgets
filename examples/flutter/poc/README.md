# poc

Flutter POC for KDDockWidgets.

This POC requires Flutter's `main` branch. It depends on Flutter's
experimental windowing APIs and internal `_window.dart` surface, so it should
not be run against stable or beta SDKs.

See also [PLATFORM_CAPABILITIES.md](PLATFORM_CAPABILITIES.md) for a quick
cross-platform behavior matrix and [ARCHITECTURE.md](ARCHITECTURE.md) for the
current runtime/native control path.

See also [MACOS.md](MACOS.md) for the current macOS runner,
bootstrap, and native drag/docking findings.

See also [WAYLAND.md](WAYLAND.md) for the result of the
Wayland live tear-off investigation that was intentionally removed from the
runtime code after the POC reached the public GTK/Flutter API boundary.

See also [WINDOWS.md](WINDOWS.md) for the current Windows
native whole-window docking path and [X11.md](X11.md) for the
current upstream X11 blocker findings.

This example exercises the current native multi-window proxy-drag architecture
around Flutter's experimental `WindowRegistry` / `RegularWindowController` API.

It keeps the drag interaction rooted in the source window and uses a platform
native bridge to supply cross-window hover, drag completion, and whole-window
docking signals back into the existing Dart docking controller.

Detached windows render the same dock surface, but cross-window reattach still
depends on the frontend supplying a real target-window routing signal. The
example does not guess across windows from synthetic Dart-side window geometry.

## Why this shape

The experimental multi-window Flutter API is promising, but platform behavior
is still meaningfully different.

The current POC shape is:

- keep the model and docking policy in Dart
- use platform-native bridges for cross-window targeting and drag completion
- create or attach real Flutter windows according to each platform's proven
  capabilities

On Wayland there is an extra constraint for this spike: Dart-side positions are
window-local, and Flutter does not expose enough cross-window state to compare
those coordinates as if they were desktop-global. Because of that, this example
does not treat window rectangles reported from Dart as a trustworthy
cross-window drop mechanism.

## Requirements

- Flutter `main` branch
- `fvm`
- Linux, Windows, or macOS desktop target
- Flutter windowing enabled via `fvm flutter config --enable-windowing`

This example uses `package:flutter/src/widgets/_window.dart`, so it is pinned to
Flutter `main` via the local `.fvmrc` file.

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
- Use `Dock Back` or close the detached window to reattach the tab.

## Explicit non-goals

- Live handoff of the active drag to a newly created native window on
  Linux/Wayland through public Flutter/GTK APIs.
- General native drag-and-drop outside this Flutter multi-window process.
- Trusting synthetic Dart-side window geometry as a cross-window drop source on
  Wayland.
- Affinity routing or multi-main-window policies.
- Any claim that Wayland detachable-window dragging is solved.
