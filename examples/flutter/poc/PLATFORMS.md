# Platform Support

Date: 2026-05-27

Current Flutter POC behavior by desktop platform, and the platform-specific
findings behind it. For the control-path design see `ARCHITECTURE.md`.

## Capability matrix

| Platform | Launches | Extra Windows | Live Detached Follow | Whole-Window Dock Gesture | Notes |
| --- | --- | --- | --- | --- | --- |
| Windows | Yes | Yes | Yes | Yes, native title bar | Closest to feature parity |
| macOS | Yes | Yes | Yes, first-pass | Yes, first-pass native title bar | Needs revalidation on a real Mac |
| Linux/Wayland | Yes | Yes | No | Yes, fallback header region | Ordinary title-bar drag only moves the window |
| Linux/X11 | Blocked upstream | Not reliable | Intended hook exists | Not a validation target | Flutter multi-window launch blocked upstream |

Windows is the reference platform. Treat macOS as first-pass until re-tested on
real hardware. Wayland uses a fallback dock gesture, not title-bar parity. X11
is blocked upstream, so it is not a useful signal about docking behavior.

## Windows

The runner subclasses registered native windows and watches the native move
loop:

- `WM_NCLBUTTONDOWN` on `HTCAPTION` marks a pending whole-window header drag
- `WM_ENTERSIZEMOVE` starts the drag session
- `WM_MOVING` updates hovered dock targets during the move loop
- `WM_EXITSIZEMOVE` ends the session and emits the final dock target

It supports native tab-drag docking, live detached-window follow during
tear-off, and whole-window docking via `windowHeaderDragStarted` /
`windowHeaderDragEnded`. Target detection uses cursor position and moving-rect
overlap scoring, with the active mode selectable from Dart.

Code: `windows/runner/dock_drag_bridge.{cpp,h}`,
`lib/src/native_dock_drag/native_dock_drag_windows.dart`.

## macOS

The bridge does not use a system drag-and-drop session. It watches native
events around the existing Dart docking model: it starts a native drag on
mouse-drag, tracks the cursor across registered windows, can attach a new
detached window to the active drag so it follows the cursor, and emits
hover and `dragEnded` events. Title-bar docking detects native window moves and
emits `windowHeaderDragStarted` / `windowHeaderDragEnded`. It exposes the
`NSWindow` handle so macOS reuses the same registration path as Linux and
Windows.

Bootstrap gotchas found along the way:

- The default runner template creates a `FlutterViewController` immediately,
  which breaks Flutter's rule that multiview must be enabled before any
  `FlutterViewController` attaches. The runner uses an explicit shared
  `FlutterEngine` instead.
- Use `runWidget(...)`, not `runApp(...)`, and let Dart create the first window
  through the experimental windowing API, matching Flutter's
  `multiple_windows` example. A nib-owned main window gave a black window.
- `MainFlutterWindow.awakeFromNib()` can run before
  `applicationDidFinishLaunching()`, so an engine initialized only there is too
  late. The POC no longer uses a nib-owned window, but the ordering still
  matters for future changes.

First-pass caveats: revalidate on a real Mac. Title-bar docking watches native
moves rather than integrating with AppKit, and tab tear-off is same-process
only, not a general macOS drag-and-drop.

Code: `macos/Runner/AppDelegate.swift`, `macos/Runner/dock_drag_bridge.{mm,h}`,
`lib/src/native_dock_drag/native_dock_drag_macos.dart`,
`lib/src/experimental_window_api/experimental_window_api_macos.dart`.

## Linux / Wayland

Live tear-off (handing an active drag to a newly created window while the
pointer is down) is not possible through public Flutter/GTK APIs. The runner
can start the drag and create the detached window, but it cannot get that
window's `xdg_toplevel` to attach it to an `xdg_toplevel_drag_v1`. A workaround
using `gdk_wayland_window_set_use_custom_surface()`, where the client owns its
own `xdg_toplevel`, did make a window follow the pointer, but the compositor
then grabs the pointer, the originating `FlutterView` never gets the pointer-up
that ends its gesture, and the source window freezes. Fixing that needs the
engine to deliver a pointer-cancel and re-sync input around an external drag,
which an app cannot do.

We asked the Flutter team to expose the toplevel in
[flutter/flutter#187837](https://github.com/flutter/flutter/issues/187837).
Their answer (robert-ancell, Flutter Linux platform):

> This is a known limitation we have using GTK - we cannot get access to the
> `xdg_toplevel` object that GTK is using. This is something we are thinking
> about longer term, though is not something that can be easily resolved. In
> terms of doing drag and drop you will need to use the existing GTK APIs for
> this currently.

That experiment was removed. The POC uses the supported GTK path:

- new tear-offs use deferred detach: the real window is created on release,
  when the drag ends outside any dock target
- ordinary title-bar dragging just moves the window
- whole-window docking of an already detached window starts from an explicit
  header-bar dock region, reusing the same-app GTK drag/drop routing and the
  Dart docking model, with cursor-based hover targeting against registered
  windows

The full title bar is deliberately not the dock gesture, since that would
conflict with ordinary native window movement.

Code: `linux/runner/dock_drag_bridge.cc` (shared GTK logic),
`linux/runner/dock_drag_bridge_wayland.cc`.

## Linux / X11

X11 is blocked upstream, not by POC code. Flutter's `RegularWindowController`
crashes on X11 with a `GLX BadAccess` error before docking behavior comes into
play, tracked as
[flutter/flutter#186577](https://github.com/flutter/flutter/issues/186577)
(still open, triaged by the Linux team). The bundled `examples/multiple_windows`
sample fails the same way.

The runner keeps an X11-specific path for detached-window follow
(`linux/runner/dock_drag_bridge_x11.cc`) alongside the shared GTK bridge, ready
for when the upstream launch path is stable. Once #186577 is fixed, re-test tab
dragging, detached-window follow, and title-bar movement on X11.
