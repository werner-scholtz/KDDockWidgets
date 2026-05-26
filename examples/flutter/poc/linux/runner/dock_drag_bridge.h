#ifndef FLUTTER_DOCK_DRAG_BRIDGE_H_
#define FLUTTER_DOCK_DRAG_BRIDGE_H_

#include <flutter_linux/flutter_linux.h>

G_BEGIN_DECLS

void dock_drag_bridge_init(FlBinaryMessenger* messenger);

gboolean KddwDockDragBridge_RegisterWindow(gint window_id,
                                           gpointer fl_view_handle);

void KddwDockDragBridge_UnregisterWindow(gint window_id);

gboolean KddwDockDragBridge_AttachDragWindow(gint window_id,
                                             gint anchor_x,
                                             gint anchor_y);

gboolean KddwDockDragBridge_StartDrag(gint source_window_id, gint tab_id);

G_END_DECLS

#endif  // FLUTTER_DOCK_DRAG_BRIDGE_H_