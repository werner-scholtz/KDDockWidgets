# poc

Flutter POC for KDDockWidgets.

This POC needs a Flutter `master` build. It uses Flutter's experimental
windowing APIs and the internal `_window.dart` file, so do not run it against
stable or beta SDKs.

Those internal APIs change often, so `.fvmrc` pins one known-good master commit
instead of the floating `master` channel. That keeps the POC building as master
moves on. To move to a newer master, install that commit and re-verify (see
"Updating the pinned SDK" below).

This example exercises the native multi-window drag setup built on Flutter's
experimental `WindowRegistry` / `RegularWindowController` API.

The drag stays rooted in the source window. A platform-native bridge sends
cross-window hover, drag completion, and whole-window docking signals back into
the existing Dart docking controller.

Detached windows render the same dock surface, but reattaching across windows
still needs the frontend to supply a real target-window routing signal. The
example does not guess across windows from Dart-side window geometry.

## Quick Navigation

- [PLATFORMS.md](PLATFORMS.md) is the per-platform capability matrix and
  findings.
- [ARCHITECTURE.md](ARCHITECTURE.md) describes the Dart/runtime/native control
  path.

## Requirements

- A Flutter `master` build, pinned to an exact commit in `.fvmrc`
- `fvm`
- Linux, Windows, or macOS desktop target
- Flutter windowing enabled via `fvm flutter config --enable-windowing`

This example uses `package:flutter/src/widgets/_window.dart`, so `.fvmrc` pins a
specific Flutter `master` commit. Running `fvm flutter` in this directory uses
that commit automatically.

## Updating the pinned SDK

To move to a newer master (for a new windowing API or a fix), repin and
re-verify:

```bash
cd examples/flutter/poc
fvm use <master-commit-sha>   # updates .fvmrc and installs that SDK
fvm flutter pub get
fvm flutter analyze           # expect: No issues found
fvm flutter test              # expect: all tests pass
```

If the new master renamed a windowing API, `analyze` points at the exact call
site to update (for example, `RegularWindowController` once renamed its
`preferredSize` argument to `size`).

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

Per-platform behavior differs. See [PLATFORMS.md](PLATFORMS.md) for the matrix
and details. What you can do in the demo:

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
