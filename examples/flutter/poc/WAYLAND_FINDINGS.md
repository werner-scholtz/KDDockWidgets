# Wayland Findings

Date: 2026-05-26

This note captures the outcome of the Wayland tear-off investigation for the
Flutter POC in this directory.

## Goal

Prove whether a self-contained Flutter/GTK Linux POC can create a torn-off
window on Wayland and hand the active drag over to that new window while the
pointer is still down.

## What Was Proven

- The runner can bind the relevant Wayland protocol stack for drag startup,
  including `wl_data_device_manager`, `wl_data_device`, `wl_pointer`,
  `xdg_wm_base`, and `xdg_toplevel_drag_manager_v1`.
- The runner can capture the required Wayland button serial from the live
  pointer path.
- The runner can issue `wl_data_device.start_drag(...)` successfully.
- A detached Flutter window can be created during the active drag.
- The runner can observe that detached Flutter window and recover its
  `wl_surface` through public GTK/GDK APIs.

## What Was Not Proven

- The POC could not obtain the detached Flutter window's `xdg_toplevel`
  through public GTK/GDK or Flutter Linux APIs.
- Because of that, the POC could not send a reliable
  `xdg_toplevel_drag_v1.attach(...)` request for the real detached Flutter
  window.
- Creating a raw replacement `xdg_surface` / `xdg_toplevel` directly in the
  runner was not a reliable workaround on this compositor. Those experiments
  disconnected the client, so they were treated as unsafe and removed.

## Conclusion

For a self-contained Flutter/GTK POC that only uses public APIs, the Wayland
investigation reached a hard boundary:

- drag startup works
- detached-window creation during drag works
- detached Flutter windows expose `wl_surface`
- live Wayland tear-off handoff still fails because the attachable
  `xdg_toplevel` is not available

That means the public GTK/Flutter route is not sufficient to deliver reliable
live tear-off handoff on Wayland.

## Implication For The POC

This POC stays on the safer deferred-detach architecture:

- show a proxy drag while the pointer is down
- create the real native window on drop/release when the drag ends outside any
  dock target
- use native cross-window hover routing only for already existing windows

## Reliable Next-Step Options

If live Wayland tear-off handoff is still required later, the realistic paths
are outside this POC layer:

1. Upstream or otherwise obtain Flutter Linux/embedder support that exposes the
   attachable Wayland toplevel for a Flutter window.
2. Move detached-window ownership for Wayland handoff to Qt/KDDockWidgets,
   where the native Wayland objects are already part of the frontend stack.

Unsafe GTK-private probing was intentionally not kept in this repo, because it
would not produce a reliable or maintainable solution.
