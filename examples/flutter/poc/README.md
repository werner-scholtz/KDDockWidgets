# poc

Flutter POC for KDDockWidgets.

See also [MACOS_FINDINGS.md](MACOS_FINDINGS.md) for the current macOS runner,
bootstrap, and native drag/docking findings.

See also [WAYLAND_FINDINGS.md](WAYLAND_FINDINGS.md) for the result of the
Wayland live tear-off investigation that was intentionally removed from the
runtime code after the POC reached the public GTK/Flutter API boundary.

See also [WINDOWS_FINDINGS.md](WINDOWS_FINDINGS.md) for the current Windows
native whole-window docking path and [X11_FINDINGS.md](X11_FINDINGS.md) for the
current upstream X11 blocker findings.

This example exercises the current native multi-window proxy-drag architecture
around Flutter's experimental `WindowRegistry` / `RegularWindowController` API.

It keeps the drag interaction rooted in the source window, shows a local drag
proxy while the pointer is down, and creates a real native Flutter window only
when the drag ends outside the dock area.

Detached windows render the same dock surface, but cross-window reattach still
depends on the frontend supplying a real target-window routing signal. The
example does not guess across windows from synthetic Dart-side window geometry.

## Why this shape

The experimental multi-window Flutter API is promising, but the Wayland
investigation in the reference repo did not prove that a newly created top-level
window can reliably continue the same drag gesture after detachment.

That means this example intentionally does **not** try to keep a fresh native
window attached to the cursor during the active pointer sequence. Instead it
uses a safer architecture:

- drag proxy in the source window while dragging
- create the real native window on release
- rely on the compositor's normal native move behavior once the window exists

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
- Drag a docked tab far enough to start a proxy drag.
- Release outside every dock to create a real secondary window.
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
