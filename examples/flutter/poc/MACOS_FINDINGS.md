# macOS Findings

Date: 2026-05-27

This note captures the current macOS status for the Flutter POC in this
directory and the main platform-specific findings that shaped the current
implementation.

## Current Status

The Flutter POC now launches on macOS with Flutter's experimental windowing
enabled and can create and manage real detached windows through the same Dart
windowing layer used on the other desktop targets.

The current macOS branch state includes a native drag bridge for:

- registering Flutter-created `NSWindow` instances with the runner
- routing tab-drag hover updates across already registered windows
- exposing the main macOS window handle back to Dart for root-window
  registration
- a first native implementation for live detached-window follow during tab
  tear-off
- a first native implementation for detached-window title-bar docking gestures

Basic launch and multi-window bootstrap were validated during implementation.
The richer native drag behavior landed after that and should still be treated
as a first-pass macOS implementation until it is revalidated on a real Mac.

## Main Platform Findings

### 1. The default macOS Flutter template bootstrap was not sufficient

The default macOS runner template eagerly creates a `FlutterViewController`,
which conflicts with Flutter's multiview invariant when windowing is enabled.

The key engine rule that mattered here was:

- multiview must be enabled before any `FlutterViewController` is attached to
  the engine

That required the macOS runner to move away from the default template shape and
use an explicit shared `FlutterEngine` for the POC bootstrap.

### 2. A nib-owned main Flutter window caused the wrong startup model

An early macOS runner variant kept the template-style `MainFlutterWindow` nib
and attached the first Flutter view there. That got past the original crash,
but it produced a black window and still did not match Flutter's own
multi-window example.

The working direction was to align macOS with Flutter's `multiple_windows`
example more closely:

- use `runWidget(...)` on macOS instead of `runApp(...)`
- let Dart create the first regular window through the experimental windowing
  API
- keep the runner focused on engine/bootstrap and native drag plumbing rather
  than owning the first Flutter content window

### 3. `awakeFromNib()` can run before `applicationDidFinishLaunching()`

During the intermediate nib-based bootstrap attempt, macOS showed that
`MainFlutterWindow.awakeFromNib()` could run before the app delegate finished
its launch callback. That meant a shared engine initialized only in
`applicationDidFinishLaunching()` was too late for window bootstrap.

Even though the current POC no longer uses a nib-owned main Flutter window,
this ordering detail remains important when evaluating future macOS runner
changes.

### 4. Flutter's macOS windowing API exposes usable native window handles

The experimental Flutter macOS windowing API exposes an `NSWindow` handle
through the platform window controller, which made it possible to keep the same
general registration seam used on Linux and Windows.

That is what allows the current macOS runner to:

- register the root window once Dart has created it
- register detached windows after they are created
- use native `NSWindow` identity for hover targeting and whole-window docking

## Current Native Behavior Model

The current macOS bridge does not use a system drag-and-drop session. Instead,
it uses app-managed native event monitoring around the existing Dart docking
model.

For tab tear-off drags, the bridge currently:

- starts a native drag session on mouse-drag detection
- tracks cursor movement across registered windows
- emits hover/leave events back to Dart
- can attach a newly created detached Flutter window to the active drag so the
  window follows the cursor during the same gesture
- emits a final `dragEnded` event when the mouse is released

For detached-window title-bar docking, the bridge currently:

- detects title-bar-originated moves for registered detached windows
- starts a native whole-window docking session when the window begins moving
- updates hovered dock targets while the window moves
- emits `windowHeaderDragStarted` / `windowHeaderDragEnded` back to Dart

This keeps the actual docking model in the existing Dart controller while the
runner provides the missing macOS-native routing signals.

## Known Constraints

The current macOS state should still be treated as a POC implementation, not a
finished platform backend.

Important current constraints:

- the richer native drag behavior should be revalidated on a real Mac after the
  final squashed commit, since the last macOS verification cycle happened
  before the final native gesture expansion
- the current title-bar docking path is a first-pass implementation based on
  native move observation rather than a deeply integrated AppKit docking model
- the current tab tear-off path is app-managed and same-process only; it is not
  a general macOS drag-and-drop solution

## Relevant Code

Relevant current code state:

- macOS runner bootstrap lives in `macos/Runner/AppDelegate.swift`
- the macOS drag bridge lives in `macos/Runner/dock_drag_bridge.mm`
- exported macOS drag bridge declarations live in
  `macos/Runner/dock_drag_bridge.h`
- Dart macOS backend bindings live in
  `lib/src/native_dock_drag/native_dock_drag_macos.dart`
- Dart macOS window-handle extraction lives in
  `lib/src/experimental_window_api/experimental_window_api_macos.dart`

## Verification Guidance

macOS verification should cover:

1. Launch with Flutter windowing enabled and confirm the first window renders
   real Flutter content rather than a black bootstrap window.
2. Tear off a tab and confirm a real detached native window can be created.
3. Re-test whether the detached window now follows the cursor during the same
   drag gesture or still waits for mouse release.
4. Drag a detached window by its title bar over another existing window and
   verify hover highlighting and final docking behavior.
5. Release with no valid target and verify the detached window remains
   detached.
