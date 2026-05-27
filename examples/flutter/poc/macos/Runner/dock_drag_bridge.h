#ifndef RUNNER_DOCK_DRAG_BRIDGE_H_
#define RUNNER_DOCK_DRAG_BRIDGE_H_

#include <stdint.h>

#if defined(__GNUC__)
#define KDDW_DOCK_DRAG_EXPORT __attribute__((visibility("default")))
#else
#define KDDW_DOCK_DRAG_EXPORT
#endif

#ifdef __OBJC__
#import <FlutterMacOS/FlutterMacOS.h>

#ifdef __cplusplus
extern "C" {
#endif

KDDW_DOCK_DRAG_EXPORT void dock_drag_bridge_bootstrap(
    FlutterMethodChannel* channel);

KDDW_DOCK_DRAG_EXPORT void dock_drag_bridge_set_main_window(
    intptr_t native_window_handle);

#ifdef __cplusplus
}
#endif
#endif

#ifdef __cplusplus
extern "C" {
#endif

KDDW_DOCK_DRAG_EXPORT int KddwDockDragBridge_SupportsWindowHeaderDockGesture();

KDDW_DOCK_DRAG_EXPORT int KddwDockDragBridge_SupportsLiveDetachedWindowDuringDrag();

KDDW_DOCK_DRAG_EXPORT intptr_t KddwDockDragBridge_GetMainWindowHandle();

KDDW_DOCK_DRAG_EXPORT void KddwDockDragBridge_SetWindowHeaderDockTargetingMode(
    int mode);

KDDW_DOCK_DRAG_EXPORT int KddwDockDragBridge_RegisterWindow(
    int window_id,
    intptr_t native_window_handle);

KDDW_DOCK_DRAG_EXPORT void KddwDockDragBridge_UnregisterWindow(int window_id);

KDDW_DOCK_DRAG_EXPORT int KddwDockDragBridge_AttachDragWindow(
    int window_id,
    int anchor_x,
    int anchor_y);

KDDW_DOCK_DRAG_EXPORT int KddwDockDragBridge_StartDrag(
    int source_window_id,
    int tab_id);

#ifdef __cplusplus
}
#endif

#endif  // RUNNER_DOCK_DRAG_BRIDGE_H_