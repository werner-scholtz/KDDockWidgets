#include "dock_drag_bridge.h"

#include <gtk/gtk.h>

#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

namespace {

constexpr char kChannelName[] = "kddw_native_dock_drag";
constexpr char kWindowIdKey[] = "kddw-window-id";
constexpr char kRegisteredKey[] = "kddw-native-dnd-registered";
gchar kTargetName[] = "application/x-kddw-tab";

struct ActiveDockDrag {
  gint source_window_id;
  gint tab_id;
  GtkWidget* source_view;
  gboolean drop_succeeded;
  gint drop_target_window_id;
  gint detached_window_id;
  gint drag_anchor_x;
  gint drag_anchor_y;
  guint follow_pointer_source_id;
};

FlMethodChannel* s_channel = nullptr;
GHashTable* s_views_by_window_id = nullptr;
ActiveDockDrag* s_active_drag = nullptr;

GtkWidget* lookup_view(gint window_id) {
  if (s_views_by_window_id == nullptr) {
    return nullptr;
  }

  return GTK_WIDGET(g_hash_table_lookup(s_views_by_window_id,
                                        GINT_TO_POINTER(window_id)));
}

gint window_id_for_widget(GtkWidget* widget) {
  return GPOINTER_TO_INT(
      g_object_get_data(G_OBJECT(widget), kWindowIdKey));
}

void emit_window_event(const gchar* method, gint window_id) {
  if (s_channel == nullptr) {
    return;
  }

  g_autoptr(FlValue) args = fl_value_new_map();
  fl_value_set_string_take(args, "windowId", fl_value_new_int(window_id));
  fl_method_channel_invoke_method(s_channel, method, args, nullptr, nullptr,
                                  nullptr);
}

void emit_drag_ended(gboolean accepted, gint target_window_id) {
  if (s_channel == nullptr) {
    return;
  }

  g_autoptr(FlValue) args = fl_value_new_map();
  fl_value_set_string_take(args, "accepted", fl_value_new_bool(accepted));
  if (target_window_id >= 0) {
    fl_value_set_string_take(args, "windowId",
                             fl_value_new_int(target_window_id));
  }
  fl_method_channel_invoke_method(s_channel, "dragEnded", args, nullptr,
                                  nullptr, nullptr);
}

void clear_active_drag() {
  if (s_active_drag != nullptr && s_active_drag->follow_pointer_source_id != 0) {
    g_source_remove(s_active_drag->follow_pointer_source_id);
    s_active_drag->follow_pointer_source_id = 0;
  }

  g_clear_pointer(&s_active_drag, g_free);
}

GtkWindow* toplevel_window_for_view(GtkWidget* view) {
  if (view == nullptr) {
    return nullptr;
  }

  GtkWidget* toplevel = gtk_widget_get_toplevel(view);
  if (!GTK_IS_WINDOW(toplevel)) {
    return nullptr;
  }

  return GTK_WINDOW(toplevel);
}

bool can_follow_with_x11(GtkWidget* view) {
  if (view == nullptr) {
    return false;
  }

#ifdef GDK_WINDOWING_X11
  return GDK_IS_X11_DISPLAY(gtk_widget_get_display(view));
#else
  return false;
#endif
}

gboolean follow_drag_window(gpointer /*user_data*/) {
  if (s_active_drag == nullptr || s_active_drag->detached_window_id < 0) {
    return G_SOURCE_REMOVE;
  }

  GtkWidget* detached_view = lookup_view(s_active_drag->detached_window_id);
  if (detached_view == nullptr || !gtk_widget_get_realized(detached_view)) {
    return G_SOURCE_CONTINUE;
  }

  if (!can_follow_with_x11(detached_view)) {
    return G_SOURCE_REMOVE;
  }

  GtkWindow* detached_window = toplevel_window_for_view(detached_view);
  if (detached_window == nullptr) {
    return G_SOURCE_CONTINUE;
  }

  GdkDisplay* display = gtk_widget_get_display(detached_view);
  if (display == nullptr) {
    return G_SOURCE_CONTINUE;
  }

  GdkSeat* seat = gdk_display_get_default_seat(display);
  if (seat == nullptr) {
    return G_SOURCE_CONTINUE;
  }

  GdkDevice* pointer = gdk_seat_get_pointer(seat);
  if (pointer == nullptr) {
    return G_SOURCE_CONTINUE;
  }

  gint cursor_x = 0;
  gint cursor_y = 0;
  gdk_device_get_position(pointer, nullptr, &cursor_x, &cursor_y);
  gtk_window_move(detached_window, cursor_x - s_active_drag->drag_anchor_x,
                  cursor_y - s_active_drag->drag_anchor_y);
  return G_SOURCE_CONTINUE;
}

void ensure_follow_drag_window() {
  if (s_active_drag == nullptr || s_active_drag->detached_window_id < 0) {
    return;
  }

  GtkWidget* detached_view = lookup_view(s_active_drag->detached_window_id);
  if (!can_follow_with_x11(detached_view)) {
    return;
  }

  if (s_active_drag->follow_pointer_source_id == 0) {
    s_active_drag->follow_pointer_source_id =
        g_timeout_add(16, follow_drag_window, nullptr);
  }

  follow_drag_window(nullptr);
}

void on_registered_view_destroy(GtkWidget* widget, gpointer /*user_data*/) {
  const gint window_id = window_id_for_widget(widget);
  if (s_views_by_window_id != nullptr) {
    g_hash_table_remove(s_views_by_window_id, GINT_TO_POINTER(window_id));
  }

  if (s_active_drag != nullptr && s_active_drag->source_view == widget) {
    s_active_drag->drop_succeeded = FALSE;
    s_active_drag->drop_target_window_id = -1;
  }

  if (s_active_drag != nullptr && s_active_drag->detached_window_id == window_id) {
    s_active_drag->detached_window_id = -1;
  }
}

gboolean on_drag_motion(GtkWidget* widget,
                        GdkDragContext* context,
                        gint /*x*/,
                        gint /*y*/,
                        guint time,
                        gpointer /*user_data*/) {
  if (gtk_drag_dest_find_target(widget, context, nullptr) == GDK_NONE) {
    gdk_drag_status(context, static_cast<GdkDragAction>(0), time);
    return FALSE;
  }

  gdk_drag_status(context, GDK_ACTION_MOVE, time);
  emit_window_event("dragHover", window_id_for_widget(widget));
  return TRUE;
}

void on_drag_leave(GtkWidget* widget,
                   GdkDragContext* /*context*/,
                   guint /*time*/,
                   gpointer /*user_data*/) {
  emit_window_event("dragLeave", window_id_for_widget(widget));
}

gboolean on_drag_drop(GtkWidget* widget,
                      GdkDragContext* context,
                      gint /*x*/,
                      gint /*y*/,
                      guint time,
                      gpointer /*user_data*/) {
  const GdkAtom target = gtk_drag_dest_find_target(widget, context, nullptr);
  if (target == GDK_NONE) {
    return FALSE;
  }

  gtk_drag_get_data(widget, context, target, time);
  return TRUE;
}

void on_drag_data_received(GtkWidget* widget,
                           GdkDragContext* context,
                           gint /*x*/,
                           gint /*y*/,
                           GtkSelectionData* selection_data,
                           guint /*info*/,
                           guint time,
                           gpointer /*user_data*/) {
  const gboolean success =
      gtk_selection_data_get_length(selection_data) >= 0;
  if (s_active_drag != nullptr) {
    s_active_drag->drop_succeeded = success;
    s_active_drag->drop_target_window_id =
        success ? window_id_for_widget(widget) : -1;
  }

  if (success) {
    emit_window_event("dragHover", window_id_for_widget(widget));
  }

  gtk_drag_finish(context, success, FALSE, time);
}

void on_drag_data_get(GtkWidget* /*widget*/,
                      GdkDragContext* /*context*/,
                      GtkSelectionData* selection_data,
                      guint /*info*/,
                      guint /*time*/,
                      gpointer /*user_data*/) {
  gchar* payload = g_strdup_printf("%d:%d",
                                   s_active_drag != nullptr
                                       ? s_active_drag->source_window_id
                                       : -1,
                                   s_active_drag != nullptr
                                       ? s_active_drag->tab_id
                                       : -1);
  gtk_selection_data_set(selection_data,
                         gtk_selection_data_get_target(selection_data), 8,
                         reinterpret_cast<const guchar*>(payload),
                         static_cast<gint>(strlen(payload)));
  g_free(payload);
}

gboolean on_drag_failed(GtkWidget* /*widget*/,
                        GdkDragContext* /*context*/,
                        GtkDragResult /*result*/,
                        gpointer /*user_data*/) {
  if (s_active_drag != nullptr) {
    s_active_drag->drop_succeeded = FALSE;
    s_active_drag->drop_target_window_id = -1;
  }

  return FALSE;
}

void on_drag_end(GtkWidget* widget,
                 GdkDragContext* /*context*/,
                 gpointer /*user_data*/) {
  if (s_active_drag == nullptr || s_active_drag->source_view != widget) {
    return;
  }

  emit_drag_ended(s_active_drag->drop_succeeded,
                  s_active_drag->drop_target_window_id);
  clear_active_drag();
}

}  // namespace

void dock_drag_bridge_init(FlBinaryMessenger* messenger) {
  if (s_channel != nullptr) {
    return;
  }

  FlStandardMethodCodec* codec = fl_standard_method_codec_new();
  s_channel = fl_method_channel_new(messenger, kChannelName,
                                    FL_METHOD_CODEC(codec));
  g_object_unref(codec);
  s_views_by_window_id = g_hash_table_new(g_direct_hash, g_direct_equal);
}

extern "C" gboolean KddwDockDragBridge_RegisterWindow(
    gint window_id,
    gpointer fl_view_handle) {
  if (s_views_by_window_id == nullptr || fl_view_handle == nullptr) {
    return FALSE;
  }

  GtkWidget* view = GTK_WIDGET(fl_view_handle);
  if (!GTK_IS_WIDGET(view)) {
    return FALSE;
  }

  g_hash_table_insert(s_views_by_window_id, GINT_TO_POINTER(window_id), view);
  g_object_set_data(G_OBJECT(view), kWindowIdKey, GINT_TO_POINTER(window_id));

  if (g_object_get_data(G_OBJECT(view), kRegisteredKey) != nullptr) {
    return TRUE;
  }

  g_object_set_data(G_OBJECT(view), kRegisteredKey, GINT_TO_POINTER(1));

  GtkTargetEntry entries[] = {{kTargetName, GTK_TARGET_SAME_APP, 0}};
  gtk_drag_dest_set(view, static_cast<GtkDestDefaults>(0), entries, 1,
                    GDK_ACTION_MOVE);

  g_signal_connect(view, "drag-motion", G_CALLBACK(on_drag_motion), nullptr);
  g_signal_connect(view, "drag-leave", G_CALLBACK(on_drag_leave), nullptr);
  g_signal_connect(view, "drag-drop", G_CALLBACK(on_drag_drop), nullptr);
  g_signal_connect(view, "drag-data-received",
                   G_CALLBACK(on_drag_data_received), nullptr);
  g_signal_connect(view, "drag-data-get", G_CALLBACK(on_drag_data_get),
                   nullptr);
  g_signal_connect(view, "drag-failed", G_CALLBACK(on_drag_failed), nullptr);
  g_signal_connect(view, "drag-end", G_CALLBACK(on_drag_end), nullptr);
  g_signal_connect(view, "destroy", G_CALLBACK(on_registered_view_destroy),
                   nullptr);

  return TRUE;
}

extern "C" void KddwDockDragBridge_UnregisterWindow(gint window_id) {
  if (s_views_by_window_id == nullptr) {
    return;
  }

  GtkWidget* view = lookup_view(window_id);
  if (view == nullptr) {
    return;
  }

  g_hash_table_remove(s_views_by_window_id, GINT_TO_POINTER(window_id));

  if (s_active_drag != nullptr && s_active_drag->source_view == view) {
    s_active_drag->drop_succeeded = FALSE;
  }

  if (s_active_drag != nullptr && s_active_drag->detached_window_id == window_id) {
    s_active_drag->detached_window_id = -1;
  }
}

extern "C" gboolean KddwDockDragBridge_AttachDragWindow(gint window_id,
                                                         gint anchor_x,
                                                         gint anchor_y) {
  if (s_active_drag == nullptr) {
    return FALSE;
  }

  GtkWidget* view = lookup_view(window_id);
  if (view == nullptr) {
    return FALSE;
  }

  s_active_drag->detached_window_id = window_id;
  s_active_drag->drag_anchor_x = anchor_x;
  s_active_drag->drag_anchor_y = anchor_y;
  ensure_follow_drag_window();
  return TRUE;
}

extern "C" gboolean KddwDockDragBridge_StartDrag(gint source_window_id,
                                                   gint tab_id) {
  if (s_views_by_window_id == nullptr || s_active_drag != nullptr) {
    return FALSE;
  }

  GtkWidget* view = lookup_view(source_window_id);
  if (view == nullptr || !gtk_widget_get_realized(view)) {
    return FALSE;
  }

  GtkTargetEntry entries[] = {{kTargetName, GTK_TARGET_SAME_APP, 0}};
  GtkTargetList* target_list = gtk_target_list_new(entries, 1);
  GdkDragContext* context = gtk_drag_begin_with_coordinates(
      view, target_list, GDK_ACTION_MOVE, 1, nullptr, -1, -1);
  gtk_target_list_unref(target_list);

  if (context == nullptr) {
    return FALSE;
  }

  s_active_drag = g_new0(ActiveDockDrag, 1);
  s_active_drag->source_window_id = source_window_id;
  s_active_drag->tab_id = tab_id;
  s_active_drag->source_view = view;
  s_active_drag->drop_succeeded = FALSE;
  s_active_drag->drop_target_window_id = -1;
  s_active_drag->detached_window_id = -1;
  s_active_drag->drag_anchor_x = 0;
  s_active_drag->drag_anchor_y = 0;
  s_active_drag->follow_pointer_source_id = 0;

  gtk_drag_set_icon_name(context, "text-x-generic", -2, -2);
  return TRUE;
}