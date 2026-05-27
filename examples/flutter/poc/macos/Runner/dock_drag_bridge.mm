#import "dock_drag_bridge.h"

#import <Cocoa/Cocoa.h>

#include <algorithm>
#include <map>
#include <memory>

namespace {

constexpr double kWindowMoveDockOverlapThreshold = 0.2;

enum class WindowHeaderDockTargetingMode {
  kOverlap = 0,
  kCursor = 1,
  kHybrid = 2,
};

struct ActiveDockDrag {
  int source_window_id;
  int tab_id;
  int hovered_window_id = -1;
  int detached_window_id = -1;
  int drag_anchor_x = 0;
  int drag_anchor_y = 0;
};

struct ActiveWindowHeaderDrag {
  int source_window_id;
  int hovered_window_id = -1;
};

FlutterMethodChannel* s_channel = nil;
std::map<int, NSWindow*> s_windows_by_window_id;
std::map<NSWindow*, int> s_window_ids_by_window;
std::unique_ptr<ActiveDockDrag> s_active_drag;
std::unique_ptr<ActiveWindowHeaderDrag> s_active_window_header_drag;
id s_local_drag_monitor = nil;
id s_global_drag_monitor = nil;
id s_local_mouse_up_monitor = nil;
id s_global_mouse_up_monitor = nil;
NSTimer* s_hover_timer = nil;
intptr_t s_main_window_handle = 0;
int s_pending_window_header_drag_source = -1;
WindowHeaderDockTargetingMode s_window_header_dock_targeting_mode =
    WindowHeaderDockTargetingMode::kCursor;
id s_local_window_header_mouse_down_monitor = nil;
id s_local_window_header_mouse_up_monitor = nil;
id s_global_window_header_mouse_up_monitor = nil;
id s_window_did_move_observer = nil;

void invoke_method(NSString* method, NSDictionary* arguments) {
  FlutterMethodChannel* channel = s_channel;
  if (channel == nil) {
    return;
  }

  dispatch_async(dispatch_get_main_queue(), ^{
    [channel invokeMethod:method arguments:arguments];
  });
}

void emit_window_event(NSString* method, int window_id) {
  invoke_method(method, @{ @"windowId": @(window_id) });
}

void emit_drag_ended(BOOL accepted, int target_window_id) {
  NSMutableDictionary* arguments =
      [@{ @"accepted": @(accepted) } mutableCopy];
  if (accepted && target_window_id >= 0) {
    arguments[@"windowId"] = @(target_window_id);
  }

  invoke_method(@"dragEnded", arguments);
}

void emit_window_header_drag_started(int source_window_id) {
  invoke_method(@"windowHeaderDragStarted",
                @{ @"sourceWindowId": @(source_window_id) });
}

void emit_window_header_drag_ended(int source_window_id,
                                   int target_window_id) {
  NSMutableDictionary* arguments =
      [@{ @"sourceWindowId": @(source_window_id) } mutableCopy];
  if (target_window_id >= 0) {
    arguments[@"targetWindowId"] = @(target_window_id);
  }

  invoke_method(@"windowHeaderDragEnded", arguments);
}

void cleanup_drag_monitors() {
  if (s_local_drag_monitor != nil) {
    [NSEvent removeMonitor:s_local_drag_monitor];
    s_local_drag_monitor = nil;
  }
  if (s_global_drag_monitor != nil) {
    [NSEvent removeMonitor:s_global_drag_monitor];
    s_global_drag_monitor = nil;
  }
  if (s_local_mouse_up_monitor != nil) {
    [NSEvent removeMonitor:s_local_mouse_up_monitor];
    s_local_mouse_up_monitor = nil;
  }
  if (s_global_mouse_up_monitor != nil) {
    [NSEvent removeMonitor:s_global_mouse_up_monitor];
    s_global_mouse_up_monitor = nil;
  }
  if (s_hover_timer != nil) {
    [s_hover_timer invalidate];
    s_hover_timer = nil;
  }
}

int hovered_window_at_point(NSPoint point, int excluded_window_id) {
  for (NSWindow* window in [NSApp orderedWindows]) {
    const auto window_id_it = s_window_ids_by_window.find(window);
    if (window_id_it == s_window_ids_by_window.end()) {
      continue;
    }

    const int window_id = window_id_it->second;
    const BOOL is_effectively_visible =
        window.isVisible && !window.isMiniaturized &&
        ((window.occlusionState & NSWindowOcclusionStateVisible) != 0);
    if (window_id == excluded_window_id || !is_effectively_visible) {
      continue;
    }

    if (NSPointInRect(point, window.frame)) {
      return window_id;
    }
  }

  return -1;
}

double rect_area(NSRect rect) {
  if (rect.size.width <= 0 || rect.size.height <= 0) {
    return 0;
  }

  return rect.size.width * rect.size.height;
}

double overlap_score(NSRect source_rect, NSRect target_rect) {
  const NSRect overlap_rect = NSIntersectionRect(source_rect, target_rect);
  const double overlap_area = rect_area(overlap_rect);
  const double source_area = rect_area(source_rect);
  const double target_area = rect_area(target_rect);
  if (overlap_area <= 0 || source_area <= 0 || target_area <= 0) {
    return 0;
  }

  const NSPoint source_center =
      NSMakePoint(NSMidX(source_rect), NSMidY(source_rect));
  const BOOL center_inside_target = NSPointInRect(source_center, target_rect);
  const double normalized_overlap =
      overlap_area / std::min(source_area, target_area);
  return center_inside_target ? 1.0 + normalized_overlap : normalized_overlap;
}

int hovered_window_for_moving_rect(NSRect moving_rect, int source_window_id) {
  int best_window_id = -1;
  double best_score = 0;

  for (const auto& entry : s_windows_by_window_id) {
    if (entry.first == source_window_id) {
      continue;
    }

    NSWindow* window = entry.second;
    if (window == nil || !window.isVisible || window.isMiniaturized) {
      continue;
    }

    const double score = overlap_score(moving_rect, window.frame);
    if (score <= kWindowMoveDockOverlapThreshold || score <= best_score) {
      continue;
    }

    best_score = score;
    best_window_id = entry.first;
  }

  return best_window_id;
}

void transition_hovered_window(int* current_window_id, int next_window_id) {
  if (current_window_id == nullptr || *current_window_id == next_window_id) {
    return;
  }

  if (*current_window_id >= 0) {
    emit_window_event(@"dragLeave", *current_window_id);
  }

  *current_window_id = next_window_id;
  if (next_window_id >= 0) {
    emit_window_event(@"dragHover", next_window_id);
  }
}

void update_window_header_drag_hover(int hovered_window_id) {
  if (!s_active_window_header_drag) {
    return;
  }

  transition_hovered_window(
      &s_active_window_header_drag->hovered_window_id,
      hovered_window_id);
}

int hovered_window_for_window_header_drag(NSWindow* source_window,
                                          int source_window_id) {
  if (source_window == nil) {
    return -1;
  }

  switch (s_window_header_dock_targeting_mode) {
    case WindowHeaderDockTargetingMode::kOverlap:
      return hovered_window_for_moving_rect(source_window.frame,
                                            source_window_id);
    case WindowHeaderDockTargetingMode::kHybrid: {
      const int cursor_target = hovered_window_at_point(
          [NSEvent mouseLocation], source_window_id);
      if (cursor_target >= 0) {
        return cursor_target;
      }

      return hovered_window_for_moving_rect(source_window.frame,
                                            source_window_id);
    }
    case WindowHeaderDockTargetingMode::kCursor:
    default:
      return hovered_window_at_point([NSEvent mouseLocation],
                                     source_window_id);
  }
}

bool point_hits_window_titlebar(NSWindow* window, NSPoint screen_point) {
  if (window == nil || !NSPointInRect(screen_point, window.frame)) {
    return false;
  }

  const NSRect frame = window.frame;
  const NSRect content_rect = [window contentRectForFrameRect:frame];
  const CGFloat titlebar_height = NSMaxY(frame) - NSMaxY(content_rect);
  if (titlebar_height <= 0) {
    return false;
  }

  const NSRect titlebar_rect = NSMakeRect(
      frame.origin.x,
      NSMaxY(content_rect),
      frame.size.width,
      titlebar_height);
  return NSPointInRect(screen_point, titlebar_rect);
}

void clear_active_window_header_drag() {
  s_pending_window_header_drag_source = -1;
  s_active_window_header_drag.reset();
}

void finish_active_window_header_drag() {
  if (!s_active_window_header_drag) {
    s_pending_window_header_drag_source = -1;
    return;
  }

  emit_window_header_drag_ended(
      s_active_window_header_drag->source_window_id,
      s_active_window_header_drag->hovered_window_id);
  clear_active_window_header_drag();
}

void install_window_header_tracking() {
  if (s_local_window_header_mouse_down_monitor == nil) {
    s_local_window_header_mouse_down_monitor = [NSEvent
        addLocalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDown
                                     handler:^NSEvent*(NSEvent* event) {
                                       if (s_active_drag) {
                                         return event;
                                       }

                                       NSWindow* window = event.window;
                                       const auto window_it =
                                           s_window_ids_by_window.find(window);
                                       if (window_it == s_window_ids_by_window.end() ||
                                           window_it->second <= 0) {
                                         s_pending_window_header_drag_source = -1;
                                         return event;
                                       }

                                       const NSPoint screen_point =
                                           [window convertPointToScreen:event.locationInWindow];
                                       s_pending_window_header_drag_source =
                                           point_hits_window_titlebar(window, screen_point)
                                               ? window_it->second
                                               : -1;
                                       return event;
                                     }];
  }

  if (s_local_window_header_mouse_up_monitor == nil) {
    s_local_window_header_mouse_up_monitor = [NSEvent
        addLocalMonitorForEventsMatchingMask:NSEventMaskLeftMouseUp
                                     handler:^NSEvent*(NSEvent* event) {
                                       if (!s_active_drag) {
                                         finish_active_window_header_drag();
                                       }
                                       return event;
                                     }];
  }

  if (s_global_window_header_mouse_up_monitor == nil) {
    s_global_window_header_mouse_up_monitor = [NSEvent
        addGlobalMonitorForEventsMatchingMask:NSEventMaskLeftMouseUp
                                      handler:^(NSEvent* event) {
                                        (void)event;
                                        if (!s_active_drag) {
                                          finish_active_window_header_drag();
                                        }
                                      }];
  }

  if (s_window_did_move_observer == nil) {
    s_window_did_move_observer = [[NSNotificationCenter defaultCenter]
        addObserverForName:NSWindowDidMoveNotification
                    object:nil
                     queue:nil
                usingBlock:^(NSNotification* notification) {
                  if (s_active_drag) {
                    return;
                  }

                  NSWindow* window = (NSWindow*)notification.object;
                  const auto window_it = s_window_ids_by_window.find(window);
                  if (window_it == s_window_ids_by_window.end() ||
                      window_it->second <= 0) {
                    return;
                  }

                  const int window_id = window_it->second;
                  if (s_pending_window_header_drag_source == window_id &&
                      !s_active_window_header_drag) {
                    s_active_window_header_drag =
                        std::make_unique<ActiveWindowHeaderDrag>();
                    s_active_window_header_drag->source_window_id = window_id;
                    emit_window_header_drag_started(window_id);
                  }

                  if (!s_active_window_header_drag ||
                      s_active_window_header_drag->source_window_id != window_id) {
                    return;
                  }

                  update_window_header_drag_hover(
                      hovered_window_for_window_header_drag(window, window_id));
                }];
  }
}

void follow_detached_window_for_cursor(NSPoint cursor) {
  if (!s_active_drag || s_active_drag->detached_window_id < 0) {
    return;
  }

  const auto detached_window_it =
      s_windows_by_window_id.find(s_active_drag->detached_window_id);
  if (detached_window_it == s_windows_by_window_id.end()) {
    return;
  }

  NSWindow* detached_window = detached_window_it->second;
  if (detached_window == nil || !detached_window.isVisible ||
      detached_window.isMiniaturized) {
    return;
  }

  const NSRect frame = detached_window.frame;
  const NSPoint origin = NSMakePoint(
      cursor.x - s_active_drag->drag_anchor_x,
      cursor.y - (frame.size.height - s_active_drag->drag_anchor_y));
  [detached_window setFrameOrigin:origin];
  [detached_window orderFront:nil];
}

void update_hovered_window_for_cursor() {
  if (!s_active_drag) {
    return;
  }

  const NSPoint cursor = [NSEvent mouseLocation];
  follow_detached_window_for_cursor(cursor);

  int hovered_window_id =
      hovered_window_at_point(cursor, s_active_drag->source_window_id);
  if (s_active_drag->detached_window_id >= 0 &&
      hovered_window_id == s_active_drag->detached_window_id) {
    hovered_window_id = hovered_window_at_point(
        cursor, s_active_drag->detached_window_id);
    if (hovered_window_id < 0) {
      hovered_window_id = s_active_drag->detached_window_id;
    }
  }

  if (hovered_window_id == s_active_drag->hovered_window_id) {
    return;
  }

  if (s_active_drag->hovered_window_id >= 0) {
    emit_window_event(@"dragLeave", s_active_drag->hovered_window_id);
  }

  s_active_drag->hovered_window_id = hovered_window_id;
  if (hovered_window_id >= 0) {
    emit_window_event(@"dragHover", hovered_window_id);
  }
}

void finish_active_drag() {
  if (!s_active_drag) {
    return;
  }

  update_hovered_window_for_cursor();
  const int target_window_id = s_active_drag->hovered_window_id;
  s_active_drag.reset();
  cleanup_drag_monitors();
  emit_drag_ended(target_window_id >= 0, target_window_id);
}

int register_window_on_main(int window_id, intptr_t native_window_handle) {
  if (window_id < 0 || native_window_handle == 0) {
    return 0;
  }

  NSWindow* window = (__bridge NSWindow*)reinterpret_cast<void*>(
      native_window_handle);
  if (window == nil) {
    return 0;
  }

  const auto existing_window_it = s_windows_by_window_id.find(window_id);
  if (existing_window_it != s_windows_by_window_id.end()) {
    s_window_ids_by_window.erase(existing_window_it->second);
  }

  s_windows_by_window_id[window_id] = window;
  s_window_ids_by_window[window] = window_id;
  install_window_header_tracking();
  return 1;
}

void unregister_window_on_main(int window_id) {
  const auto window_it = s_windows_by_window_id.find(window_id);
  if (window_it == s_windows_by_window_id.end()) {
    return;
  }

  s_window_ids_by_window.erase(window_it->second);
  s_windows_by_window_id.erase(window_it);

  if (s_active_drag && s_active_drag->hovered_window_id == window_id) {
    s_active_drag->hovered_window_id = -1;
  }
  if (s_active_drag && s_active_drag->source_window_id == window_id) {
    finish_active_drag();
  }
  if (s_active_drag && s_active_drag->detached_window_id == window_id) {
    s_active_drag->detached_window_id = -1;
  }
  if (s_active_window_header_drag &&
      s_active_window_header_drag->source_window_id == window_id) {
    clear_active_window_header_drag();
  }
  if (s_active_window_header_drag &&
      s_active_window_header_drag->hovered_window_id == window_id) {
    s_active_window_header_drag->hovered_window_id = -1;
  }
  if (s_pending_window_header_drag_source == window_id) {
    s_pending_window_header_drag_source = -1;
  }
}

void install_drag_monitors() {
  cleanup_drag_monitors();

  s_local_drag_monitor = [NSEvent
      addLocalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDragged
                                   handler:^NSEvent*(NSEvent* event) {
                                     update_hovered_window_for_cursor();
                                     return event;
                                   }];
  s_global_drag_monitor = [NSEvent
      addGlobalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDragged
                                    handler:^(NSEvent* event) {
                                      (void)event;
                                      update_hovered_window_for_cursor();
                                    }];
  s_local_mouse_up_monitor = [NSEvent
      addLocalMonitorForEventsMatchingMask:NSEventMaskLeftMouseUp
                                   handler:^NSEvent*(NSEvent* event) {
                                     finish_active_drag();
                                     return event;
                                   }];
  s_global_mouse_up_monitor = [NSEvent
      addGlobalMonitorForEventsMatchingMask:NSEventMaskLeftMouseUp
                                    handler:^(NSEvent* event) {
                                      (void)event;
                                      finish_active_drag();
                                    }];
  s_hover_timer = [NSTimer
      scheduledTimerWithTimeInterval:(1.0 / 60.0)
                              repeats:YES
                                block:^(NSTimer* timer) {
                                  if (!s_active_drag) {
                                    [timer invalidate];
                                    return;
                                  }

                                  update_hovered_window_for_cursor();
                                }];
}

int start_drag_on_main(int source_window_id, int tab_id) {
  if (s_channel == nil || s_active_drag ||
      s_windows_by_window_id.find(source_window_id) ==
          s_windows_by_window_id.end()) {
    return 0;
  }

  s_active_drag = std::make_unique<ActiveDockDrag>();
  s_active_drag->source_window_id = source_window_id;
  s_active_drag->tab_id = tab_id;
  install_drag_monitors();
  update_hovered_window_for_cursor();
  return 1;
}

}  // namespace

extern "C" void dock_drag_bridge_bootstrap(FlutterMethodChannel* channel) {
  s_channel = channel;
}

extern "C" void dock_drag_bridge_set_main_window(
    intptr_t native_window_handle) {
  s_main_window_handle = native_window_handle;
}

extern "C" {

int KddwDockDragBridge_SupportsWindowHeaderDockGesture() {
  return 1;
}

int KddwDockDragBridge_SupportsLiveDetachedWindowDuringDrag() {
  return 1;
}

intptr_t KddwDockDragBridge_GetMainWindowHandle() {
  return s_main_window_handle;
}

void KddwDockDragBridge_SetWindowHeaderDockTargetingMode(int mode) {
  switch (mode) {
    case 0:
      s_window_header_dock_targeting_mode =
          WindowHeaderDockTargetingMode::kOverlap;
      return;
    case 2:
      s_window_header_dock_targeting_mode =
          WindowHeaderDockTargetingMode::kHybrid;
      return;
    case 1:
    default:
      s_window_header_dock_targeting_mode =
          WindowHeaderDockTargetingMode::kCursor;
      return;
  }
}

int KddwDockDragBridge_RegisterWindow(int window_id,
                                      intptr_t native_window_handle) {
  if ([NSThread isMainThread]) {
    return register_window_on_main(window_id, native_window_handle);
  }

  __block int result = 0;
  dispatch_sync(dispatch_get_main_queue(), ^{
    result = register_window_on_main(window_id, native_window_handle);
  });
  return result;
}

void KddwDockDragBridge_UnregisterWindow(int window_id) {
  if ([NSThread isMainThread]) {
    unregister_window_on_main(window_id);
    return;
  }

  dispatch_sync(dispatch_get_main_queue(), ^{
    unregister_window_on_main(window_id);
  });
}

int KddwDockDragBridge_AttachDragWindow(int window_id,
                                        int anchor_x,
                                        int anchor_y) {
  if ([NSThread isMainThread]) {
    if (!s_active_drag) {
      return 0;
    }

    const auto window_it = s_windows_by_window_id.find(window_id);
    if (window_it == s_windows_by_window_id.end()) {
      return 0;
    }

    NSWindow* detached_window = window_it->second;
    if (detached_window == nil) {
      return 0;
    }

    s_active_drag->detached_window_id = window_id;
    s_active_drag->drag_anchor_x = anchor_x;
    s_active_drag->drag_anchor_y = anchor_y;
    follow_detached_window_for_cursor([NSEvent mouseLocation]);
    update_hovered_window_for_cursor();
    return 1;
  }

  __block int result = 0;
  dispatch_sync(dispatch_get_main_queue(), ^{
    result = KddwDockDragBridge_AttachDragWindow(window_id, anchor_x, anchor_y);
  });
  return result;
}

int KddwDockDragBridge_StartDrag(int source_window_id, int tab_id) {
  if ([NSThread isMainThread]) {
    return start_drag_on_main(source_window_id, tab_id);
  }

  __block int result = 0;
  dispatch_sync(dispatch_get_main_queue(), ^{
    result = start_drag_on_main(source_window_id, tab_id);
  });
  return result;
}

}  // extern "C"