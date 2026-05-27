#include "dock_drag_bridge_internal.h"

#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

namespace dock_drag_bridge_internal {

bool CanFollowWithX11(GtkWidget* view) {
  if (view == nullptr) {
    return false;
  }

#ifdef GDK_WINDOWING_X11
  return GDK_IS_X11_DISPLAY(gtk_widget_get_display(view));
#else
  return false;
#endif
}

gboolean SupportsLiveDetachedWindowDuringDrag(GHashTable* views_by_window_id) {
  if (views_by_window_id == nullptr) {
    return FALSE;
  }

  GHashTableIter iter;
  gpointer key = nullptr;
  gpointer value = nullptr;
  g_hash_table_iter_init(&iter, views_by_window_id);
  while (g_hash_table_iter_next(&iter, &key, &value)) {
    GtkWidget* view = GTK_WIDGET(value);
    if (CanFollowWithX11(view)) {
      return TRUE;
    }
  }

  return FALSE;
}

}  // namespace dock_drag_bridge_internal