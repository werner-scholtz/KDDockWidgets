# Platform Capabilities

Date: 2026-05-27

This note summarizes the current Flutter POC behavior by desktop platform.
It is meant to be the quick reference that sits above the deeper platform
notes in `WINDOWS.md`, `MACOS.md`, `WAYLAND.md`, and `X11.md`.

## Capability Matrix

| Platform | Launches | Extra Windows | Live Detached Follow | Whole-Window Dock Gesture | Notes |
| --- | --- | --- | --- | --- | --- |
| Windows | Yes | Yes | Yes | Yes, native title bar | Closest match to intended native behavior |
| macOS | Yes | Yes | Yes, first-pass | Yes, first-pass native title bar | Needs fresh real-Mac revalidation after the latest native gesture work |
| Linux/Wayland | Yes | Yes | No | Yes, fallback header region | Ordinary title-bar drag still only moves the window |
| Linux/X11 | Blocked upstream | Not reliable | Intended seam exists | Not the current validation target | Flutter multi-window launch path currently appears blocked upstream |

## Practical Interpretation

- Windows is the strongest current reference platform for the POC.
- macOS now follows the same broad architecture as Windows, but its richer
  native drag behavior should still be treated as a first-pass runner path
  until it is re-smoke-tested on real hardware after the latest changes.
- Wayland intentionally stays on the safer deferred-detach model for new tear
  offs and uses a fallback whole-window docking gesture rather than title-bar
  parity behavior.
- X11 should currently be treated as an upstream Flutter/Linux multi-window
  blocker rather than as a useful signal about KDDockWidgets docking behavior.

## Related Notes

- `WINDOWS.md` explains the current Windows native move-and-dock path.
- `MACOS.md` records the macOS bootstrap findings and current native bridge
  behavior.
- `WAYLAND.md` explains why live Wayland tear-off handoff was not kept and why
  the Linux/Wayland path uses a fallback dock gesture.
- `X11.md` records the current upstream X11 blocker findings.