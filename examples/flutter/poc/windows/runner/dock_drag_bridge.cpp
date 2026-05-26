#include "dock_drag_bridge.h"

#include <windows.h>

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <map>
#include <memory>
#include <optional>
#include <string>

namespace {

constexpr char kChannelName[] = "kddw_native_dock_drag";
constexpr UINT kDragTimerIntervalMs = 16;
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

struct WindowAtPointSearch {
  POINT point;
  std::optional<int> excluded_window_id;
  int result_window_id = -1;
};

struct ActiveWindowHeaderDrag {
  int source_window_id;
  int hovered_window_id = -1;
};

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> s_channel;
std::map<int, HWND> s_hwnds_by_window_id;
std::map<HWND, int> s_window_ids_by_hwnd;
std::map<HWND, WNDPROC> s_original_window_procs;
std::unique_ptr<ActiveDockDrag> s_active_drag;
std::unique_ptr<ActiveWindowHeaderDrag> s_active_window_header_drag;
UINT_PTR s_drag_timer_id = 0;
int s_pending_window_header_drag_source = -1;
intptr_t s_main_window_handle = 0;
WindowHeaderDockTargetingMode s_window_header_dock_targeting_mode =
  WindowHeaderDockTargetingMode::kCursor;

HWND lookup_window(int window_id) {
  const auto it = s_hwnds_by_window_id.find(window_id);
  if (it == s_hwnds_by_window_id.end()) {
    return nullptr;
  }

  return it->second;
}

void invoke_method(const std::string& method,
                   flutter::EncodableMap arguments) {
  if (!s_channel) {
    return;
  }

  s_channel->InvokeMethod(
      method,
      std::make_unique<flutter::EncodableValue>(std::move(arguments)));
}

void emit_window_event(const std::string& method, int window_id) {
  flutter::EncodableMap arguments;
  arguments[flutter::EncodableValue("windowId")] =
      flutter::EncodableValue(window_id);
  invoke_method(method, std::move(arguments));
}

void emit_drag_ended(bool accepted, std::optional<int> target_window_id) {
  flutter::EncodableMap arguments;
  arguments[flutter::EncodableValue("accepted")] =
      flutter::EncodableValue(accepted);
  if (target_window_id.has_value()) {
    arguments[flutter::EncodableValue("windowId")] =
        flutter::EncodableValue(*target_window_id);
  }
  invoke_method("dragEnded", std::move(arguments));
}

void emit_window_header_drag_started(int source_window_id) {
  flutter::EncodableMap arguments;
  arguments[flutter::EncodableValue("sourceWindowId")] =
      flutter::EncodableValue(source_window_id);
  invoke_method("windowHeaderDragStarted", std::move(arguments));
}

void emit_window_header_drag_ended(int source_window_id,
                                   std::optional<int> target_window_id) {
  flutter::EncodableMap arguments;
  arguments[flutter::EncodableValue("sourceWindowId")] =
      flutter::EncodableValue(source_window_id);
  if (target_window_id.has_value()) {
    arguments[flutter::EncodableValue("targetWindowId")] =
        flutter::EncodableValue(*target_window_id);
  }
  invoke_method("windowHeaderDragEnded", std::move(arguments));
}

std::wstring utf8_to_wide(const std::string& utf8) {
  if (utf8.empty()) {
    return std::wstring();
  }

  const int wide_length = MultiByteToWideChar(
      CP_UTF8, 0, utf8.c_str(), -1, nullptr, 0);
  if (wide_length <= 0) {
    return std::wstring();
  }

  std::wstring wide(static_cast<size_t>(wide_length - 1), L'\0');
  MultiByteToWideChar(
      CP_UTF8, 0, utf8.c_str(), -1, wide.data(), wide_length);
  return wide;
}

void set_window_title(HWND window, const std::string& title) {
  if (window == nullptr || !IsWindow(window)) {
    return;
  }

  const std::wstring wide_title = utf8_to_wide(title);
  SetWindowTextW(window, wide_title.c_str());
}

bool window_contains_point(HWND hwnd, POINT point) {
  if (hwnd == nullptr || !IsWindow(hwnd) || !IsWindowVisible(hwnd) ||
      IsIconic(hwnd)) {
    return false;
  }

  RECT rect;
  if (!GetWindowRect(hwnd, &rect)) {
    return false;
  }

  return PtInRect(&rect, point) != FALSE;
}

bool window_rect(HWND hwnd, RECT* rect) {
  return hwnd != nullptr && IsWindow(hwnd) && GetWindowRect(hwnd, rect) != 0;
}

double rect_area(const RECT& rect) {
  const double width = static_cast<double>(rect.right - rect.left);
  const double height = static_cast<double>(rect.bottom - rect.top);
  if (width <= 0 || height <= 0) {
    return 0;
  }

  return width * height;
}

double overlap_score(const RECT& source_rect, const RECT& target_rect) {
  RECT overlap_rect;
  if (!IntersectRect(&overlap_rect, &source_rect, &target_rect)) {
    return 0;
  }

  const double overlap_area = rect_area(overlap_rect);
  const double source_area = rect_area(source_rect);
  const double target_area = rect_area(target_rect);
  if (overlap_area <= 0 || source_area <= 0 || target_area <= 0) {
    return 0;
  }

  POINT source_center = {
      source_rect.left + ((source_rect.right - source_rect.left) / 2),
      source_rect.top + ((source_rect.bottom - source_rect.top) / 2),
  };
  const bool center_inside_target = PtInRect(&target_rect, source_center) != 0;
  const double normalized_overlap =
      overlap_area / std::min(source_area, target_area);
  return center_inside_target ? 1.0 + normalized_overlap : normalized_overlap;
}

std::optional<int> hovered_window_for_moving_rect(const RECT& moving_rect,
                                                  int source_window_id) {
  int best_window_id = -1;
  double best_score = 0;

  for (const auto& entry : s_hwnds_by_window_id) {
    if (entry.first == source_window_id) {
      continue;
    }

    RECT target_rect;
    if (!window_rect(entry.second, &target_rect) || IsIconic(entry.second)) {
      continue;
    }

    const double score = overlap_score(moving_rect, target_rect);
    if (score <= kWindowMoveDockOverlapThreshold || score <= best_score) {
      continue;
    }

    best_score = score;
    best_window_id = entry.first;
  }

  if (best_window_id < 0) {
    return std::nullopt;
  }

  return best_window_id;
}

BOOL CALLBACK find_topmost_registered_window(HWND hwnd, LPARAM data) {
  auto* search = reinterpret_cast<WindowAtPointSearch*>(data);
  const auto it = s_window_ids_by_hwnd.find(hwnd);
  if (it == s_window_ids_by_hwnd.end()) {
    return TRUE;
  }

  if (search->excluded_window_id.has_value() &&
      it->second == *search->excluded_window_id) {
    return TRUE;
  }

  if (!window_contains_point(hwnd, search->point)) {
    return TRUE;
  }

  search->result_window_id = it->second;
  return FALSE;
}

std::optional<int> topmost_registered_window_at_point(
    POINT point,
    std::optional<int> excluded_window_id = std::nullopt) {
  WindowAtPointSearch search;
  search.point = point;
  search.excluded_window_id = excluded_window_id;
  EnumWindows(find_topmost_registered_window,
              reinterpret_cast<LPARAM>(&search));
  if (search.result_window_id < 0) {
    return std::nullopt;
  }

  return search.result_window_id;
}

std::optional<int> hovered_window_for_cursor(POINT cursor) {
  if (s_active_drag && s_active_drag->detached_window_id >= 0) {
    const std::optional<int> underlying_target =
        topmost_registered_window_at_point(
            cursor, s_active_drag->detached_window_id);
    if (underlying_target.has_value()) {
      return underlying_target;
    }

    if (window_contains_point(lookup_window(s_active_drag->detached_window_id),
                              cursor)) {
      return s_active_drag->detached_window_id;
    }
  }

  return topmost_registered_window_at_point(cursor);
}

std::optional<int> hovered_window_for_window_header_drag_cursor(
    POINT cursor,
    int source_window_id) {
  return topmost_registered_window_at_point(cursor, source_window_id);
}

std::optional<int> hovered_window_for_window_header_drag(
    const RECT& moving_rect,
    int source_window_id) {
  switch (s_window_header_dock_targeting_mode) {
    case WindowHeaderDockTargetingMode::kOverlap:
      return hovered_window_for_moving_rect(moving_rect, source_window_id);
    case WindowHeaderDockTargetingMode::kCursor: {
      POINT cursor;
      if (!GetCursorPos(&cursor)) {
        return std::nullopt;
      }
      return hovered_window_for_window_header_drag_cursor(
          cursor, source_window_id);
    }
    case WindowHeaderDockTargetingMode::kHybrid: {
      POINT cursor;
      if (GetCursorPos(&cursor)) {
        const std::optional<int> cursor_target =
            hovered_window_for_window_header_drag_cursor(
                cursor, source_window_id);
        if (cursor_target.has_value()) {
          return cursor_target;
        }
      }
      return hovered_window_for_moving_rect(moving_rect, source_window_id);
    }
  }

  return hovered_window_for_moving_rect(moving_rect, source_window_id);
}

void transition_hovered_window(int* current_window_id,
                               std::optional<int> hovered_window_id) {
  if (current_window_id == nullptr) {
    return;
  }

  const int next_window_id = hovered_window_id.value_or(-1);
  if (*current_window_id == next_window_id) {
    return;
  }

  if (*current_window_id >= 0) {
    emit_window_event("dragLeave", *current_window_id);
  }

  *current_window_id = next_window_id;
  if (next_window_id >= 0) {
    emit_window_event("dragHover", next_window_id);
  }
}

void update_hovered_window(std::optional<int> hovered_window_id) {
  if (!s_active_drag) {
    return;
  }

  transition_hovered_window(&s_active_drag->hovered_window_id,
                            hovered_window_id);
}

void update_window_header_drag_hover(
    std::optional<int> hovered_window_id) {
  if (!s_active_window_header_drag) {
    return;
  }

  transition_hovered_window(&s_active_window_header_drag->hovered_window_id,
                            hovered_window_id);
}

void follow_detached_window(POINT cursor) {
  if (!s_active_drag || s_active_drag->detached_window_id < 0) {
    return;
  }

  HWND detached_window = lookup_window(s_active_drag->detached_window_id);
  if (detached_window == nullptr || !IsWindow(detached_window) ||
      IsIconic(detached_window)) {
    return;
  }

  SetWindowPos(detached_window, HWND_TOP,
               cursor.x - s_active_drag->drag_anchor_x,
               cursor.y - s_active_drag->drag_anchor_y, 0, 0,
               SWP_NOSIZE | SWP_NOACTIVATE);
}

void stop_drag_timer() {
  if (s_drag_timer_id == 0) {
    return;
  }

  KillTimer(nullptr, s_drag_timer_id);
  s_drag_timer_id = 0;
}

void clear_active_drag() {
  stop_drag_timer();
  s_active_drag.reset();
}

void clear_active_window_header_drag() {
  s_pending_window_header_drag_source = -1;
  s_active_window_header_drag.reset();
}

void update_active_drag() {
  if (!s_active_drag) {
    stop_drag_timer();
    return;
  }

  POINT cursor;
  if (!GetCursorPos(&cursor)) {
    return;
  }

  follow_detached_window(cursor);
  update_hovered_window(hovered_window_for_cursor(cursor));

  if ((GetAsyncKeyState(VK_LBUTTON) & 0x8000) != 0) {
    return;
  }

  std::optional<int> target_window_id;
  if (s_active_drag->hovered_window_id >= 0) {
    target_window_id = s_active_drag->hovered_window_id;
  }

  emit_drag_ended(target_window_id.has_value(), target_window_id);
  clear_active_drag();
}

void CALLBACK on_drag_timer(HWND,
                            UINT,
                            UINT_PTR,
                            DWORD) {
  update_active_drag();
}

bool ensure_drag_timer() {
  if (s_drag_timer_id != 0) {
    return true;
  }

  s_drag_timer_id = SetTimer(nullptr, 0, kDragTimerIntervalMs, on_drag_timer);
  return s_drag_timer_id != 0;
}

LRESULT CALLBACK registered_window_proc(HWND hwnd,
                                        UINT message,
                                        WPARAM w_param,
                                        LPARAM l_param) {
  const auto proc_it = s_original_window_procs.find(hwnd);
  const WNDPROC original_proc =
      proc_it != s_original_window_procs.end() ? proc_it->second : DefWindowProc;
  const auto window_id_it = s_window_ids_by_hwnd.find(hwnd);
  const int window_id =
      window_id_it != s_window_ids_by_hwnd.end() ? window_id_it->second : -1;

  switch (message) {
    case WM_NCLBUTTONDOWN:
      if (window_id > 0 && w_param == HTCAPTION) {
        s_pending_window_header_drag_source = window_id;
      }
      break;
    case WM_NCLBUTTONUP:
      if (s_pending_window_header_drag_source == window_id) {
        s_pending_window_header_drag_source = -1;
      }
      break;
    case WM_ENTERSIZEMOVE:
      if (window_id > 0 && s_pending_window_header_drag_source == window_id &&
          !s_active_drag && !s_active_window_header_drag) {
        s_active_window_header_drag = std::make_unique<ActiveWindowHeaderDrag>();
        s_active_window_header_drag->source_window_id = window_id;
        emit_window_header_drag_started(window_id);

        RECT window_rect_value;
        if (window_rect(hwnd, &window_rect_value)) {
          update_window_header_drag_hover(
              hovered_window_for_window_header_drag(
                  window_rect_value, window_id));
        }
      }
      break;
    case WM_MOVING:
      if (s_active_window_header_drag &&
          s_active_window_header_drag->source_window_id == window_id) {
        auto* moving_rect = reinterpret_cast<RECT*>(l_param);
        if (moving_rect != nullptr) {
          update_window_header_drag_hover(
              hovered_window_for_window_header_drag(*moving_rect, window_id));
        }
      }
      break;
    case WM_EXITSIZEMOVE:
      if (s_active_window_header_drag &&
          s_active_window_header_drag->source_window_id == window_id) {
        std::optional<int> target_window_id;
        if (s_active_window_header_drag->hovered_window_id >= 0) {
          target_window_id = s_active_window_header_drag->hovered_window_id;
        }
        emit_window_header_drag_ended(window_id, target_window_id);
        clear_active_window_header_drag();
      }
      s_pending_window_header_drag_source = -1;
      break;
  }

  const LRESULT result = CallWindowProc(original_proc, hwnd, message, w_param,
                                        l_param);
  if (message == WM_NCDESTROY) {
    s_original_window_procs.erase(hwnd);
    if (window_id >= 0) {
      s_hwnds_by_window_id.erase(window_id);
      if (s_active_window_header_drag) {
        if (s_active_window_header_drag->hovered_window_id == window_id) {
          emit_window_event("dragLeave", window_id);
          s_active_window_header_drag->hovered_window_id = -1;
        }
        if (s_active_window_header_drag->source_window_id == window_id) {
          clear_active_window_header_drag();
        }
      }
      if (s_active_drag) {
        if (s_active_drag->hovered_window_id == window_id) {
          emit_window_event("dragLeave", window_id);
          s_active_drag->hovered_window_id = -1;
        }
        if (s_active_drag->detached_window_id == window_id) {
          s_active_drag->detached_window_id = -1;
        }
      }
    }
    s_window_ids_by_hwnd.erase(hwnd);
  }

  return result;
}

}  // namespace

void dock_drag_bridge_set_main_window(intptr_t native_window_handle) {
  s_main_window_handle = native_window_handle;
}

void dock_drag_bridge_init(flutter::FlutterEngine* engine) {
  if (s_channel || engine == nullptr) {
    return;
  }

  s_channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          engine->messenger(), kChannelName,
          &flutter::StandardMethodCodec::GetInstance());
  s_channel->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<
             flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() != "setMainWindowTitle") {
          result->NotImplemented();
          return;
        }

        const auto* arguments = std::get_if<flutter::EncodableMap>(call.arguments());
        if (arguments == nullptr) {
          result->Error("bad-args", "Expected map arguments.");
          return;
        }

        const auto title_it =
            arguments->find(flutter::EncodableValue("title"));
        if (title_it == arguments->end()) {
          result->Error("bad-args", "Missing title.");
          return;
        }

        const auto* title = std::get_if<std::string>(&title_it->second);
        if (title == nullptr) {
          result->Error("bad-args", "Title must be a string.");
          return;
        }

        set_window_title(reinterpret_cast<HWND>(s_main_window_handle), *title);
        result->Success();
      });
}

extern "C" int KddwDockDragBridge_RegisterWindow(
    int window_id,
    intptr_t native_window_handle) {
  if (native_window_handle == 0) {
    return 0;
  }

  HWND window = reinterpret_cast<HWND>(native_window_handle);
  window = GetAncestor(window, GA_ROOT);
  if (window == nullptr || !IsWindow(window)) {
    return 0;
  }

  const auto existing_window = s_hwnds_by_window_id.find(window_id);
  if (existing_window != s_hwnds_by_window_id.end()) {
    const auto existing_proc = s_original_window_procs.find(existing_window->second);
    if (existing_proc != s_original_window_procs.end() &&
        IsWindow(existing_window->second)) {
      SetWindowLongPtr(existing_window->second, GWLP_WNDPROC,
                       reinterpret_cast<LONG_PTR>(existing_proc->second));
      s_original_window_procs.erase(existing_proc);
    }
    s_window_ids_by_hwnd.erase(existing_window->second);
  }

  const auto existing_window_id = s_window_ids_by_hwnd.find(window);
  if (existing_window_id != s_window_ids_by_hwnd.end()) {
    const auto existing_proc = s_original_window_procs.find(window);
    if (existing_proc != s_original_window_procs.end() && IsWindow(window)) {
      SetWindowLongPtr(window, GWLP_WNDPROC,
                       reinterpret_cast<LONG_PTR>(existing_proc->second));
      s_original_window_procs.erase(existing_proc);
    }
    s_hwnds_by_window_id.erase(existing_window_id->second);
  }

  const auto subclass_it = s_original_window_procs.find(window);
  if (subclass_it == s_original_window_procs.end()) {
    const auto original_proc = reinterpret_cast<WNDPROC>(SetWindowLongPtr(
        window, GWLP_WNDPROC, reinterpret_cast<LONG_PTR>(registered_window_proc)));
    if (original_proc == nullptr && GetLastError() != 0) {
      return 0;
    }
    s_original_window_procs[window] = original_proc;
  }

  s_hwnds_by_window_id[window_id] = window;
  s_window_ids_by_hwnd[window] = window_id;
  return 1;
}

extern "C" void KddwDockDragBridge_UnregisterWindow(int window_id) {
  const auto it = s_hwnds_by_window_id.find(window_id);
  if (it == s_hwnds_by_window_id.end()) {
    return;
  }

  const HWND window = it->second;

  const auto original_proc = s_original_window_procs.find(window);
  if (original_proc != s_original_window_procs.end() && IsWindow(window)) {
    SetWindowLongPtr(window, GWLP_WNDPROC,
                     reinterpret_cast<LONG_PTR>(original_proc->second));
    s_original_window_procs.erase(original_proc);
  }

  s_window_ids_by_hwnd.erase(window);
  s_hwnds_by_window_id.erase(it);

  if (!s_active_drag) {
    if (s_active_window_header_drag) {
      if (s_active_window_header_drag->hovered_window_id == window_id) {
        emit_window_event("dragLeave", window_id);
        s_active_window_header_drag->hovered_window_id = -1;
      }
      if (s_active_window_header_drag->source_window_id == window_id) {
        clear_active_window_header_drag();
      }
    }
    return;
  }

  if (s_active_drag->hovered_window_id == window_id) {
    emit_window_event("dragLeave", window_id);
    s_active_drag->hovered_window_id = -1;
  }

  if (s_active_drag->detached_window_id == window_id) {
    s_active_drag->detached_window_id = -1;
  }

  if (s_active_window_header_drag) {
    if (s_active_window_header_drag->hovered_window_id == window_id) {
      emit_window_event("dragLeave", window_id);
      s_active_window_header_drag->hovered_window_id = -1;
    }
    if (s_active_window_header_drag->source_window_id == window_id) {
      clear_active_window_header_drag();
    }
  }
  update_active_drag();
}

extern "C" intptr_t KddwDockDragBridge_GetMainWindowHandle() {
  return s_main_window_handle;
}

extern "C" void KddwDockDragBridge_SetWindowHeaderDockTargetingMode(int mode) {
  switch (mode) {
    case 1:
      s_window_header_dock_targeting_mode =
          WindowHeaderDockTargetingMode::kCursor;
      return;
    case 2:
      s_window_header_dock_targeting_mode =
          WindowHeaderDockTargetingMode::kHybrid;
      return;
    case 0:
    default:
      s_window_header_dock_targeting_mode =
          WindowHeaderDockTargetingMode::kCursor;
      return;
  }
}

extern "C" int KddwDockDragBridge_AttachDragWindow(int window_id,
                                                     int anchor_x,
                                                     int anchor_y) {
  if (!s_active_drag) {
    return 0;
  }

  const HWND detached_window = lookup_window(window_id);
  if (detached_window == nullptr || !IsWindow(detached_window)) {
    return 0;
  }

  s_active_drag->detached_window_id = window_id;
  s_active_drag->drag_anchor_x = anchor_x;
  s_active_drag->drag_anchor_y = anchor_y;
  update_active_drag();
  return 1;
}

extern "C" int KddwDockDragBridge_StartDrag(int source_window_id,
                                              int tab_id) {
  const HWND source_window = lookup_window(source_window_id);
  if (s_active_drag || source_window == nullptr || !IsWindow(source_window)) {
    return 0;
  }

  s_active_drag = std::make_unique<ActiveDockDrag>();
  s_active_drag->source_window_id = source_window_id;
  s_active_drag->tab_id = tab_id;

  if (!ensure_drag_timer()) {
    s_active_drag.reset();
    return 0;
  }

  update_active_drag();
  return 1;
}