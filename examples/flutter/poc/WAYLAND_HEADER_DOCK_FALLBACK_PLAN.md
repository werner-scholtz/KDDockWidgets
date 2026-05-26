## Wayland Header Dock Fallback

Implement a Wayland-specific fallback for the Flutter POC that approximates
Windows whole-window header docking without depending on compositor-owned
native move events.

The recommended approach is to keep normal native/header-bar window movement
unchanged, but add an explicit header-bar dock gesture on Linux/Wayland that
starts an app-managed same-app drag for an already detached window, reusing the
existing Dart whole-window docking state.

Exact parity with Windows native-titlebar dragging is excluded because once
Wayland/GTK transfers the gesture to compositor window-move, the app no longer
receives the motion/drop stream needed to target and complete docking.

## Steps

1. Confirm the UX contract and platform split.
   Treat exact native-titlebar move-and-dock parity as out of scope on
   Wayland, and target the closest viable fallback only for the Flutter POC on
   Linux/Wayland. Keep tab dragging behavior unchanged. Keep ordinary window
   movement available through the existing GTK title bar.
2. Introduce a Linux-specific whole-window header-dock gesture in the runner,
   modeled on the Windows callback shape but not on Windows native-move
   behavior.
   Add Linux runner events that can emit `windowHeaderDragStarted`,
   intermediate hover transitions through the existing `dragHover` /
   `dragLeave` channel methods, and `windowHeaderDragEnded` with an optional
   target window id. This is the new owning seam for detached-window docking
   from the header region.
3. Decide the header interaction surface and wire it in the Linux runner.
   Recommended: add a dedicated header-bar control or hit region inside the GTK
   header bar rather than hijacking the full bar. That preserves ordinary move
   semantics while giving users a discoverable dock gesture.
   Alternative but riskier: gesture-threshold logic on the full header bar that
   delays move initiation; this is more fragile on Wayland and not recommended
   for the first pass.
4. Reuse the existing same-app drag/drop routing in the Linux bridge instead of
   trying to track compositor moves.
   Extend `linux/runner/dock_drag_bridge.cc` and `.h` so header-dock drags can
   reuse registered windows, target detection, and method-channel
   notifications already used for tab drags. The drag payload can identify a
   source window id instead of a source tab id.
   The detached window itself should stay in place during the drag; this avoids
   the unsupported "move while compositor owns the drag" problem.
5. Keep Dart orchestration minimal by reusing the current whole-window docking
   controller path.
   `DockRuntimeCoordinator` already maps `windowHeaderDragStarted` to
   `DockController.beginWindowHeaderDrag()` and `windowHeaderDragEnded` to
   `DockController.endWindowHeaderDrag(...)`. Preserve that shape and only add
   any Linux-specific registration or capability gating needed in
   `NativeDockDragCoordinator` and the Linux backend.
6. Add platform capability gating so Linux/Wayland exposes this as a fallback
   feature, not parity behavior.
   Surface a `supportsWindowHeaderDockGesture` style capability from the
   platform backend, default it on for Linux only once the runner path exists,
   and leave Windows behavior untouched.
   If desired, use that capability to show a subtle in-app hint that whole-
   window docking is available from the header-bar dock control, while the rest
   of the title bar still moves the window.
7. Decide whether hover targeting should be cursor-based or overlap-based for
   Linux.
   Recommended first pass: cursor-based targeting through the existing
   registered-view drag destination path, because the actual source window will
   not be moving. Do not port the Windows overlap algorithm directly; it
   assumes live moving-rect updates that Wayland fallback will not have.
8. Keep deferred detach for Wayland tear-off exactly as documented.
   Do not attempt live handoff to a newly created detached window during the
   same pointer gesture. That is already documented as blocked in
   `WAYLAND_FINDINGS.md` and should remain out of scope for this change.
9. Add focused tests around controller semantics and manual verification around
   runner integration.
   The controller already supports whole-window header drag state
   independently of tab drags, so add tests that cover begin/end whole-window
   header dragging, hover target updates, successful docking into another
   window, and cancel/no-target behavior.
   Manual Linux/Wayland verification should cover: regular title-bar move still
   works; dedicated dock gesture starts hover targeting; dropping over another
   existing window docks the detached window; releasing with no target leaves
   the window detached and unchanged.
10. Document the behavior explicitly.
    Update the POC notes to state that on Wayland, whole-window docking from
    the header is available only through the dedicated header-bar dock gesture,
    while ordinary title-bar dragging remains plain window movement. Keep the
    repo's broader Wayland limitation statement intact.

## Relevant files

- `linux/runner/dock_drag_bridge.cc`
- `linux/runner/dock_drag_bridge.h`
- `linux/runner/my_application.cc`
- `lib/src/native_dock_drag.dart`
- `lib/src/native_dock_drag/native_dock_drag_linux.dart`
- `lib/src/dock_runtime.dart`
- `lib/src/dock_controller.dart`
- `test/dock_controller_test.dart`
- `WAYLAND_FINDINGS.md`

## Verification

1. Run the existing Flutter POC unit tests, then add and run focused tests in
   `test/dock_controller_test.dart` covering whole-window header drag
   begin/hover/end semantics.
2. Run `flutter analyze` from this directory after any Dart-side capability or
   runtime changes.
3. Build and run the Linux desktop POC under Wayland, then manually verify:
   normal header-bar drag still moves the window; the new dock gesture starts
   whole-window docking mode; hover highlights appear over other existing
   windows; releasing over a target docks all tabs into that window; releasing
   with no target leaves the window as-is.
4. Repeat a quick smoke check under X11 to ensure the new Linux runner code
   does not regress the existing tab-drag path or ordinary header-bar behavior.