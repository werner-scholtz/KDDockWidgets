#include "dock_drag_bridge.h"
#include "dock_drag_bridge_internal.h"

#include <gtk/gtk.h>

namespace dock_drag_bridge_internal {

const gchar kWindowIdKey[] = "kddw-window-id";
const gchar kRegisteredKey[] = "kddw-native-dnd-registered";
gchar kTargetName[] = "application/x-kddw-tab";

gint WindowIdForWidget(GtkWidget* widget) {
  return GPOINTER_TO_INT(g_object_get_data(G_OBJECT(widget), kWindowIdKey));
}

GtkWindow* ToplevelWindowForView(GtkWidget* view) {
  if (view == nullptr) {
    return nullptr;
  }

  GtkWidget* toplevel = gtk_widget_get_toplevel(view);
  if (!GTK_IS_WINDOW(toplevel)) {
    return nullptr;
  }

  return GTK_WINDOW(toplevel);
}

}  // namespace dock_drag_bridge_internal

namespace {

constexpr char kChannelName[] = "kddw_native_dock_drag";

enum class DragKind {
  kTab,
  kWindowHeader,
};

struct ActiveDockDrag {
  DragKind kind;
  gint source_window_id;
  gint tab_id;
  GtkWidget* source_view;
  GtkWidget* source_widget;
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

gboolean on_drag_failed(GtkWidget* widget,
                        GdkDragContext* context,
                        GtkDragResult result,
                        gpointer user_data);

GtkWidget* lookup_view(gint window_id) {
  if (s_views_by_window_id == nullptr) {
    return nullptr;
  }

  return GTK_WIDGET(g_hash_table_lookup(s_views_by_window_id,
                                        GINT_TO_POINTER(window_id)));
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

void emit_window_header_drag_started(gint source_window_id) {
  if (s_channel == nullptr) {
    return;
  }

  g_autoptr(FlValue) args = fl_value_new_map();
  fl_value_set_string_take(args, "sourceWindowId",
                           fl_value_new_int(source_window_id));
  fl_method_channel_invoke_method(s_channel, "windowHeaderDragStarted", args,
                                  nullptr, nullptr, nullptr);
}

void emit_window_header_drag_ended(gint source_window_id,
                                   gint target_window_id) {
  if (s_channel == nullptr) {
    return;
  }

  g_autoptr(FlValue) args = fl_value_new_map();
  fl_value_set_string_take(args, "sourceWindowId",
                           fl_value_new_int(source_window_id));
  if (target_window_id >= 0) {
    fl_value_set_string_take(args, "targetWindowId",
                             fl_value_new_int(target_window_id));
  }
  fl_method_channel_invoke_method(s_channel, "windowHeaderDragEnded", args,
                                  nullptr, nullptr, nullptr);
}

void finish_active_drag() {
  if (s_active_drag == nullptr) {
    return;
  }

  if (s_active_drag->kind == DragKind::kWindowHeader) {
    emit_window_header_drag_ended(s_active_drag->source_window_id,
                                  s_active_drag->drop_target_window_id);
  } else {
    emit_drag_ended(s_active_drag->drop_succeeded,
                    s_active_drag->drop_target_window_id);
  }
}

void clear_active_drag() {
  if (s_active_drag != nullptr && s_active_drag->follow_pointer_source_id != 0) {
    g_source_remove(s_active_drag->follow_pointer_source_id);
    s_active_drag->follow_pointer_source_id = 0;
  }

  g_clear_pointer(&s_active_drag, g_free);
}

ActiveDockDrag* begin_active_drag(DragKind kind,
                                  gint source_window_id,
                                  gint tab_id,
                                  GtkWidget* source_view,
                                  GtkWidget* source_widget) {
  if (s_active_drag != nullptr) {
    return nullptr;
  }

  s_active_drag = g_new0(ActiveDockDrag, 1);
  s_active_drag->kind = kind;
  s_active_drag->source_window_id = source_window_id;
  s_active_drag->tab_id = tab_id;
  s_active_drag->source_view = source_view;
  s_active_drag->source_widget = source_widget;
  s_active_drag->drop_succeeded = FALSE;
  s_active_drag->drop_target_window_id = -1;
  s_active_drag->detached_window_id = -1;
  s_active_drag->drag_anchor_x = 0;
  s_active_drag->drag_anchor_y = 0;
  s_active_drag->follow_pointer_source_id = 0;
  return s_active_drag;
}

gboolean follow_drag_window(gpointer /*user_data*/) {
  if (s_active_drag == nullptr || s_active_drag->detached_window_id < 0) {
    return G_SOURCE_REMOVE;
  }

  GtkWidget* detached_view = lookup_view(s_active_drag->detached_window_id);
  if (detached_view == nullptr || !gtk_widget_get_realized(detached_view)) {
    return G_SOURCE_CONTINUE;
  }

  if (!dock_drag_bridge_internal::CanFollowWithX11(detached_view)) {
    return G_SOURCE_REMOVE;
  }

  GtkWindow* detached_window =
      dock_drag_bridge_internal::ToplevelWindowForView(detached_view);
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
  if (!dock_drag_bridge_internal::CanFollowWithX11(detached_view)) {
    return;
  }

  if (s_active_drag->follow_pointer_source_id == 0) {
    s_active_drag->follow_pointer_source_id =
        g_timeout_add(16, follow_drag_window, nullptr);
  }

  follow_drag_window(nullptr);
}

void on_registered_view_destroy(GtkWidget* widget, gpointer /*user_data*/) {
  const gint window_id = dock_drag_bridge_internal::WindowIdForWidget(widget);
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
  emit_window_event("dragHover",
                    dock_drag_bridge_internal::WindowIdForWidget(widget));
  return TRUE;
}

void on_drag_leave(GtkWidget* widget,
                   GdkDragContext* /*context*/,
                   guint /*time*/,
                   gpointer /*user_data*/) {
  emit_window_event("dragLeave",
                    dock_drag_bridge_internal::WindowIdForWidget(widget));
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
        success ? dock_drag_bridge_internal::WindowIdForWidget(widget) : -1;
  }

  if (success) {
    emit_window_event("dragHover",
                      dock_drag_bridge_internal::WindowIdForWidget(widget));
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

void on_header_drag_begin(GtkWidget* widget,
                          GdkDragContext* /*context*/,
                          gpointer user_data) {
  GtkWidget* view = GTK_WIDGET(user_data);
  const gint source_window_id =
      dock_drag_bridge_internal::WindowIdForWidget(view);
  ActiveDockDrag* active_drag = begin_active_drag(DragKind::kWindowHeader,
                                                  source_window_id, -1, view,
                                                  widget);
  if (active_drag == nullptr) {
    return;
  }

  dock_drag_bridge_internal::MarkWaylandHeaderDragActive(widget);
  emit_window_header_drag_started(source_window_id);
}

void on_header_drag_data_get(GtkWidget* widget,
                             GdkDragContext* context,
                             GtkSelectionData* selection_data,
                             guint info,
                             guint time,
                             gpointer /*user_data*/) {
  on_drag_data_get(widget, context, selection_data, info, time, nullptr);
}

gboolean on_header_drag_failed(GtkWidget* widget,
                               GdkDragContext* context,
                               GtkDragResult result,
                               gpointer /*user_data*/) {
  return on_drag_failed(widget, context, result, nullptr);
}

void on_header_drag_end(GtkWidget* widget,
                        GdkDragContext* /*context*/,
                        gpointer /*user_data*/) {
  dock_drag_bridge_internal::ClearWaylandHeaderDragState(widget);

  if (s_active_drag == nullptr || s_active_drag->source_widget != widget) {
    return;
  }

  finish_active_drag();
  clear_active_drag();
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

  finish_active_drag();
  clear_active_drag();
}

void on_window_realize(GtkWidget* view, gpointer /*user_data*/) {
  GdkDisplay* display = gtk_widget_get_display(view);
  if (!dock_drag_bridge_internal::IsWaylandDisplay(display)) {
    return;
  }

  GtkWidget* region = dock_drag_bridge_internal::EnsureWaylandHeaderDockRegion(
      view);
  if (region == nullptr) {
    return;
  }

  dock_drag_bridge_internal::InstallWaylandHeaderDragHandlers(
      view, region, G_CALLBACK(on_header_drag_begin),
      G_CALLBACK(on_header_drag_data_get), G_CALLBACK(on_header_drag_failed),
      G_CALLBACK(on_header_drag_end));
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

extern "C" gboolean KddwDockDragBridge_SupportsWindowHeaderDockGesture() {
  return dock_drag_bridge_internal::SupportsWindowHeaderDockGesture(
      s_views_by_window_id);
}

extern "C" gboolean KddwDockDragBridge_SupportsLiveDetachedWindowDuringDrag() {
  return dock_drag_bridge_internal::SupportsLiveDetachedWindowDuringDrag(
      s_views_by_window_id);
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
  g_object_set_data(G_OBJECT(view), dock_drag_bridge_internal::kWindowIdKey,
                    GINT_TO_POINTER(window_id));

  if (g_object_get_data(G_OBJECT(view),
                        dock_drag_bridge_internal::kRegisteredKey) != nullptr) {
    return TRUE;
  }

  g_object_set_data(G_OBJECT(view), dock_drag_bridge_internal::kRegisteredKey,
                    GINT_TO_POINTER(1));

  GtkTargetEntry entries[] = {
      {dock_drag_bridge_internal::kTargetName, GTK_TARGET_SAME_APP, 0}};
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
  g_signal_connect(view, "realize", G_CALLBACK(on_window_realize), nullptr);

  if (gtk_widget_get_realized(view)) {
    on_window_realize(view, nullptr);
  }

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

  GtkTargetEntry entries[] = {
      {dock_drag_bridge_internal::kTargetName, GTK_TARGET_SAME_APP, 0}};
  GtkTargetList* target_list = gtk_target_list_new(entries, 1);
  GdkDragContext* context = gtk_drag_begin_with_coordinates(
      view, target_list, GDK_ACTION_MOVE, 1, nullptr, -1, -1);
  gtk_target_list_unref(target_list);

  if (context == nullptr) {
    return FALSE;
  }

  begin_active_drag(DragKind::kTab, source_window_id, tab_id, view, view);

  gtk_drag_set_icon_name(context, "text-x-generic", -2, -2);
  return TRUE;
}