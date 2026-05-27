#include "dock_drag_bridge_internal.h"

#ifdef GDK_WINDOWING_WAYLAND
#include <gdk/gdkwayland.h>
#endif

namespace {

constexpr char kHeaderBarKey[] = "kddw-header-bar";
constexpr char kHeaderDockRegionKey[] = "kddw-header-dock-region";
constexpr char kHeaderDockActiveKey[] = "kddw-header-dock-active";
constexpr char kHeaderDockHandlersRegisteredKey[] =
    "kddw-header-dock-handlers-registered";

void sync_header_bar_title(GObject* window_object,
                           GParamSpec* /*pspec*/,
                           gpointer /*user_data*/) {
  GtkWindow* window = GTK_WINDOW(window_object);
  GtkWidget* header_bar = GTK_WIDGET(
      g_object_get_data(window_object, kHeaderBarKey));
  if (!GTK_IS_HEADER_BAR(header_bar)) {
    return;
  }

  gtk_header_bar_set_title(GTK_HEADER_BAR(header_bar),
                           gtk_window_get_title(window));
}

GtkWidget* ensure_header_bar(GtkWindow* window) {
  if (window == nullptr) {
    return nullptr;
  }

  GtkWidget* titlebar = gtk_window_get_titlebar(window);
  if (GTK_IS_HEADER_BAR(titlebar)) {
    g_object_set_data(G_OBJECT(window), kHeaderBarKey, titlebar);
    sync_header_bar_title(G_OBJECT(window), nullptr, nullptr);
    return titlebar;
  }

  if (titlebar != nullptr) {
    return nullptr;
  }

  GtkWidget* header_bar = gtk_header_bar_new();
  gtk_header_bar_set_show_close_button(GTK_HEADER_BAR(header_bar), TRUE);
  gtk_widget_show(header_bar);
  gtk_window_set_titlebar(window, header_bar);
  g_object_set_data(G_OBJECT(window), kHeaderBarKey, header_bar);
  g_signal_connect(window, "notify::title", G_CALLBACK(sync_header_bar_title),
                   nullptr);
  sync_header_bar_title(G_OBJECT(window), nullptr, nullptr);
  return header_bar;
}

}  // namespace

namespace dock_drag_bridge_internal {

bool IsWaylandDisplay(GdkDisplay* display) {
#ifdef GDK_WINDOWING_WAYLAND
  return display != nullptr && GDK_IS_WAYLAND_DISPLAY(display);
#else
  return false;
#endif
}

gboolean SupportsWindowHeaderDockGesture(GHashTable* views_by_window_id) {
  if (views_by_window_id == nullptr) {
    return FALSE;
  }

  GHashTableIter iter;
  gpointer key = nullptr;
  gpointer value = nullptr;
  g_hash_table_iter_init(&iter, views_by_window_id);
  while (g_hash_table_iter_next(&iter, &key, &value)) {
    GtkWidget* view = GTK_WIDGET(value);
    if (IsWaylandDisplay(gtk_widget_get_display(view))) {
      return TRUE;
    }
  }

  return FALSE;
}

GtkWidget* EnsureWaylandHeaderDockRegion(GtkWidget* view) {
  GtkWindow* window = ToplevelWindowForView(view);
  if (window == nullptr) {
    return nullptr;
  }

  if (WindowIdForWidget(view) == 0) {
    return nullptr;
  }

  GtkWidget* existing_region = GTK_WIDGET(
      g_object_get_data(G_OBJECT(window), kHeaderDockRegionKey));
  if (existing_region != nullptr) {
    return existing_region;
  }

  GtkWidget* titlebar = ensure_header_bar(window);
  if (!GTK_IS_HEADER_BAR(titlebar)) {
    return nullptr;
  }

  GtkWidget* region = gtk_button_new();
  gtk_button_set_relief(GTK_BUTTON(region), GTK_RELIEF_NONE);
  gtk_widget_set_can_focus(region, FALSE);
  gtk_widget_set_tooltip_text(region,
                              "Drag this region to dock the window");
  gtk_widget_set_size_request(region, 132, -1);

  GtkStyleContext* style_context = gtk_widget_get_style_context(region);
  gtk_style_context_add_class(style_context, "flat");

  GtkWidget* content = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 6);
  gtk_widget_set_margin_start(content, 8);
  gtk_widget_set_margin_end(content, 8);
  gtk_widget_set_margin_top(content, 4);
  gtk_widget_set_margin_bottom(content, 4);

  GtkWidget* icon = gtk_image_new_from_icon_name("window-new-symbolic",
                                                 GTK_ICON_SIZE_MENU);
  GtkWidget* label = gtk_label_new("Dock Window");
  gtk_label_set_xalign(GTK_LABEL(label), 0.0);
  gtk_box_pack_start(GTK_BOX(content), icon, FALSE, FALSE, 0);
  gtk_box_pack_start(GTK_BOX(content), label, FALSE, FALSE, 0);
  gtk_container_add(GTK_CONTAINER(region), content);

  gtk_drag_source_set(region, GDK_BUTTON1_MASK, nullptr, 0, GDK_ACTION_MOVE);

  GtkTargetEntry entries[] = {{kTargetName, GTK_TARGET_SAME_APP, 0}};
  GtkTargetList* target_list = gtk_target_list_new(entries, 1);
  gtk_drag_source_set_target_list(region, target_list);
  gtk_target_list_unref(target_list);

  gtk_header_bar_pack_end(GTK_HEADER_BAR(titlebar), region);
  gtk_widget_show_all(region);
  g_object_set_data(G_OBJECT(region), kWindowIdKey,
                    GINT_TO_POINTER(WindowIdForWidget(view)));
  g_object_set_data(G_OBJECT(window), kHeaderDockRegionKey, region);
  return region;
}

void InstallWaylandHeaderDragHandlers(GtkWidget* view,
                                      GtkWidget* region,
                                      GCallback drag_begin_callback,
                                      GCallback drag_data_get_callback,
                                      GCallback drag_failed_callback,
                                      GCallback drag_end_callback) {
  if (region == nullptr) {
    return;
  }

  if (g_object_get_data(G_OBJECT(region),
                        kHeaderDockHandlersRegisteredKey) != nullptr) {
    return;
  }

  g_object_set_data(G_OBJECT(region), kHeaderDockHandlersRegisteredKey,
                    GINT_TO_POINTER(1));
  g_signal_connect(region, "drag-begin", drag_begin_callback, view);
  g_signal_connect(region, "drag-data-get", drag_data_get_callback, nullptr);
  g_signal_connect(region, "drag-failed", drag_failed_callback, nullptr);
  g_signal_connect(region, "drag-end", drag_end_callback, nullptr);
}

void MarkWaylandHeaderDragActive(GtkWidget* widget) {
  GtkWidget* toplevel = gtk_widget_get_toplevel(widget);
  if (toplevel == nullptr) {
    return;
  }

  g_object_set_data(G_OBJECT(toplevel), kHeaderDockActiveKey,
                    GINT_TO_POINTER(1));
}

void ClearWaylandHeaderDragState(GtkWidget* widget) {
  GtkWidget* toplevel = gtk_widget_get_toplevel(widget);
  if (toplevel == nullptr) {
    return;
  }

  g_object_set_data(G_OBJECT(toplevel), kHeaderDockActiveKey, nullptr);
}

}  // namespace dock_drag_bridge_internal