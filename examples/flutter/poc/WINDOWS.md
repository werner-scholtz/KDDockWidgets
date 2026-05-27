# Windows Findings

Date: 2026-05-27

This note captures the current Windows status for the Flutter POC in this
directory.

## Current Status

Windows is the platform where the Flutter POC currently has the closest match
to the intended native whole-window docking behavior.

The Windows runner owns a native whole-window header-dock path for already
registered windows and emits the corresponding method-channel events consumed by
the existing Dart docking controller.

## What Is Implemented

The Windows runner currently provides:

- native tab-drag support for same-app docking
- native whole-window header drag detection from the real window caption area
- hover target updates while a detached window is moving
- whole-window docking completion through `windowHeaderDragStarted` /
  `windowHeaderDragEnded` events
- live detached-window follow behavior during tab tear-off drags

## Native Control Path

The current Windows implementation works by subclassing registered native
windows and observing the native move loop:

- `WM_NCLBUTTONDOWN` on `HTCAPTION` marks a pending whole-window header drag
- `WM_ENTERSIZEMOVE` starts the active whole-window header drag session
- `WM_MOVING` updates hovered dock targets while the native move loop runs
- `WM_EXITSIZEMOVE` ends the session and emits the final dock target if one was
  found

## Targeting Behavior

The Windows runner contains native target-detection logic for whole-window
header docking, including:

- cursor-based targeting against registered windows
- moving-rect overlap scoring for native moving windows
- a backend seam for selecting the active targeting mode from Dart

## Implication For The POC

The Windows behavior is the current native whole-window docking path for the
POC.

That means:

- Windows remains the native title-bar move-and-dock path for the POC.
- The native move loop and hover-target tracking both stay inside the runner.
- The Dart controller path can stay small because completion is surfaced
  through the existing method-channel events.

## Relevant Code

Relevant current code state:

- Windows native drag and header-dock logic lives in
  `windows/runner/dock_drag_bridge.cpp`
- exported native bridge declarations live in
  `windows/runner/dock_drag_bridge.h`
- Dart Windows backend bindings live in
  `lib/src/native_dock_drag/native_dock_drag_windows.dart`

## Verification Guidance

Windows verification should cover:

1. Regular tab dragging between registered windows.
2. Tear-off to detached window behavior, including live detached-window follow.
3. Native title-bar dragging of a detached window over another existing window.
4. Hover highlighting and final docking when the window is released over a
   valid target.
5. No-op completion when the window is released with no dock target.
