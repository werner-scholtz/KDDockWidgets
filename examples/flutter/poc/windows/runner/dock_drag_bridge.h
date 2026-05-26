#ifndef RUNNER_DOCK_DRAG_BRIDGE_H_
#define RUNNER_DOCK_DRAG_BRIDGE_H_

#include <cstdint>

#include <flutter/flutter_engine.h>

#if defined(_WIN32)
#define KDDW_DOCK_DRAG_EXPORT __declspec(dllexport)
#else
#define KDDW_DOCK_DRAG_EXPORT
#endif

void dock_drag_bridge_init(flutter::FlutterEngine* engine);
void dock_drag_bridge_set_main_window(intptr_t native_window_handle);

extern "C" {

KDDW_DOCK_DRAG_EXPORT int KddwDockDragBridge_RegisterWindow(
    int window_id,
    intptr_t native_window_handle);

KDDW_DOCK_DRAG_EXPORT void KddwDockDragBridge_UnregisterWindow(
    int window_id);

KDDW_DOCK_DRAG_EXPORT intptr_t KddwDockDragBridge_GetMainWindowHandle();

KDDW_DOCK_DRAG_EXPORT void KddwDockDragBridge_SetWindowHeaderDockTargetingMode(
    int mode);

KDDW_DOCK_DRAG_EXPORT int KddwDockDragBridge_AttachDragWindow(
    int window_id,
    int anchor_x,
    int anchor_y);

KDDW_DOCK_DRAG_EXPORT int KddwDockDragBridge_StartDrag(
    int source_window_id,
    int tab_id);

}

#endif  // RUNNER_DOCK_DRAG_BRIDGE_H_