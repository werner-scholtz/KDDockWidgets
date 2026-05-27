// ignore_for_file: public_member_api_docs This is a POC, so we can be a bit more lax on documentation for now.

import 'dart:ffi' as ffi;

import 'native_dock_drag_backend.dart';

final class MacOSNativeDockDragPlatformBackend extends BaseNativeDockDragPlatformBackend {
  static final _MacOSNativeDockDragBindings? _bindings = _MacOSNativeDockDragBindings.maybeLoad();

  @override
  int? get mainWindowHandle {
    final bindings = _bindings;
    if (bindings == null) {
      return null;
    }

    final nativeWindowHandle = bindings.getMainWindowHandle();
    return nativeWindowHandle == 0 ? null : nativeWindowHandle;
  }

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
  void setWindowHeaderDockTargetingMode(int mode) {
    _bindings?.setWindowHeaderDockTargetingMode(mode);
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

final class _MacOSNativeDockDragBindings {
  _MacOSNativeDockDragBindings._({
    required this.getMainWindowHandle,
    required this.supportsWindowHeaderDockGesture,
    required this.supportsLiveDetachedWindowDuringDrag,
    required this.setWindowHeaderDockTargetingMode,
    required this.registerWindow,
    required this.unregisterWindow,
    required this.attachDragWindow,
    required this.startDrag,
  });

  final int Function() getMainWindowHandle;
  final bool Function() supportsWindowHeaderDockGesture;
  final bool Function() supportsLiveDetachedWindowDuringDrag;
  final void Function(int mode) setWindowHeaderDockTargetingMode;
  final bool Function(int windowId, int nativeWindowHandle) registerWindow;
  final void Function(int windowId) unregisterWindow;
  final bool Function(int windowId, int anchorX, int anchorY) attachDragWindow;
  final bool Function(int sourceWindowId, int tabId) startDrag;

  static _MacOSNativeDockDragBindings? maybeLoad() {
    try {
      final library = ffi.DynamicLibrary.executable();
      final getMainWindowHandle = library.lookupFunction<ffi.IntPtr Function(), int Function()>(
        'KddwDockDragBridge_GetMainWindowHandle',
      );
      final supportsWindowHeaderDockGestureRaw = library.lookupFunction<ffi.Int32 Function(), int Function()>(
        'KddwDockDragBridge_SupportsWindowHeaderDockGesture',
      );
      final supportsLiveDetachedWindowDuringDragRaw = library.lookupFunction<ffi.Int32 Function(), int Function()>(
        'KddwDockDragBridge_SupportsLiveDetachedWindowDuringDrag',
      );
      final setWindowHeaderDockTargetingMode = library.lookupFunction<ffi.Void Function(ffi.Int32), void Function(int)>(
        'KddwDockDragBridge_SetWindowHeaderDockTargetingMode',
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

      return _MacOSNativeDockDragBindings._(
        getMainWindowHandle: getMainWindowHandle,
        supportsWindowHeaderDockGesture: () => supportsWindowHeaderDockGestureRaw() != 0,
        supportsLiveDetachedWindowDuringDrag: () => supportsLiveDetachedWindowDuringDragRaw() != 0,
        setWindowHeaderDockTargetingMode: setWindowHeaderDockTargetingMode,
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
