#ifndef FLUTTER_DOCK_DRAG_BRIDGE_INTERNAL_H_
#define FLUTTER_DOCK_DRAG_BRIDGE_INTERNAL_H_

#include <gtk/gtk.h>

namespace dock_drag_bridge_internal {

extern const gchar kWindowIdKey[];
extern const gchar kRegisteredKey[];
extern gchar kTargetName[];

gint WindowIdForWidget(GtkWidget* widget);

GtkWindow* ToplevelWindowForView(GtkWidget* view);

bool IsWaylandDisplay(GdkDisplay* display);

bool CanFollowWithX11(GtkWidget* view);

gboolean SupportsWindowHeaderDockGesture(GHashTable* views_by_window_id);

gboolean SupportsLiveDetachedWindowDuringDrag(GHashTable* views_by_window_id);

GtkWidget* EnsureWaylandHeaderDockRegion(GtkWidget* view);

void InstallWaylandHeaderDragHandlers(GtkWidget* view,
                                      GtkWidget* region,
                                      GCallback drag_begin_callback,
                                      GCallback drag_data_get_callback,
                                      GCallback drag_failed_callback,
                                      GCallback drag_end_callback);

void MarkWaylandHeaderDragActive(GtkWidget* widget);

void ClearWaylandHeaderDragState(GtkWidget* widget);

}  // namespace dock_drag_bridge_internal

#endif  // FLUTTER_DOCK_DRAG_BRIDGE_INTERNAL_H_