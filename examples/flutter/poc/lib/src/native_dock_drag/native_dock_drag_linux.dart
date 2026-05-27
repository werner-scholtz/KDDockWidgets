// ignore_for_file: public_member_api_docs This is a POC, so we can be a bit more lax on documentation for now.

import 'dart:ffi' as ffi;

import 'native_dock_drag_backend.dart';

final class LinuxNativeDockDragPlatformBackend extends BaseNativeDockDragPlatformBackend {
  static final _LinuxNativeDockDragBindings? _bindings = _LinuxNativeDockDragBindings.maybeLoad();

  @override
  bool get supportsWindowHeaderDockGesture {
    final bindings = _bindings;
    return bindings != null && bindings.supportsWindowHeaderDockGesture();
  }

  @override
  bool get supportsLiveDetachedWindowDuringDrag {
    final bindings = _bindings;
    return bindings != null && bindings.supportsLiveDetachedWindowDuringDrag();
  }

  @override
  bool registerWindowHandle({required int windowId, required int nativeWindowHandle}) {
    final bindings = _bindings;
    if (bindings == null || nativeWindowHandle == 0) {
      return false;
    }

    return bindings.registerWindow(windowId, nativeWindowHandle);
  }

  @override
  void unregisterWindow({required int windowId}) {
    _bindings?.unregisterWindow(windowId);
  }

  @override
  bool attachDragWindow({required int windowId, required int anchorX, required int anchorY}) {
    final bindings = _bindings;
    if (bindings == null) {
      return false;
    }

    return bindings.attachDragWindow(windowId, anchorX, anchorY);
  }

  @override
  bool startDrag({required int sourceWindowId, required int tabId}) {
    final bindings = _bindings;
    if (bindings == null) {
      return false;
    }

    return bindings.startDrag(sourceWindowId, tabId);
  }
}

final class _LinuxNativeDockDragBindings {
  _LinuxNativeDockDragBindings._({
    required this.supportsWindowHeaderDockGesture,
    required this.supportsLiveDetachedWindowDuringDrag,
    required this.registerWindow,
    required this.unregisterWindow,
    required this.attachDragWindow,
    required this.startDrag,
  });

  final bool Function() supportsWindowHeaderDockGesture;
  final bool Function() supportsLiveDetachedWindowDuringDrag;
  final bool Function(int windowId, int nativeWindowHandle) registerWindow;
  final void Function(int windowId) unregisterWindow;
  final bool Function(int windowId, int anchorX, int anchorY) attachDragWindow;
  final bool Function(int sourceWindowId, int tabId) startDrag;

  static _LinuxNativeDockDragBindings? maybeLoad() {
    try {
      final library = ffi.DynamicLibrary.executable();
      final supportsWindowHeaderDockGestureRaw = library.lookupFunction<ffi.Int32 Function(), int Function()>(
        'KddwDockDragBridge_SupportsWindowHeaderDockGesture',
      );
      final supportsLiveDetachedWindowDuringDragRaw = library.lookupFunction<ffi.Int32 Function(), int Function()>(
        'KddwDockDragBridge_SupportsLiveDetachedWindowDuringDrag',
      );
      final registerWindowRaw = library
          .lookupFunction<ffi.Int32 Function(ffi.Int32, ffi.IntPtr), int Function(int, int)>(
            'KddwDockDragBridge_RegisterWindow',
          );
      final unregisterWindow = library.lookupFunction<ffi.Void Function(ffi.Int32), void Function(int)>(
        'KddwDockDragBridge_UnregisterWindow',
      );
      final attachDragWindowRaw = library
          .lookupFunction<ffi.Int32 Function(ffi.Int32, ffi.Int32, ffi.Int32), int Function(int, int, int)>(
            'KddwDockDragBridge_AttachDragWindow',
          );
      final startDragRaw = library.lookupFunction<ffi.Int32 Function(ffi.Int32, ffi.Int32), int Function(int, int)>(
        'KddwDockDragBridge_StartDrag',
      );

      return _LinuxNativeDockDragBindings._(
        supportsWindowHeaderDockGesture: () => supportsWindowHeaderDockGestureRaw() != 0,
        supportsLiveDetachedWindowDuringDrag: () => supportsLiveDetachedWindowDuringDragRaw() != 0,
        registerWindow: (int windowId, int nativeWindowHandle) => registerWindowRaw(windowId, nativeWindowHandle) != 0,
        unregisterWindow: unregisterWindow,
        attachDragWindow: (int windowId, int anchorX, int anchorY) =>
            attachDragWindowRaw(windowId, anchorX, anchorY) != 0,
        startDrag: (int sourceWindowId, int tabId) => startDragRaw(sourceWindowId, tabId) != 0,
      );
    } catch (_) {
      return null;
    }
  }
}
