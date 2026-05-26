library;

import 'dart:ffi' as ffi;

import 'native_dock_drag_backend.dart';

final class LinuxNativeDockDragPlatformBackend
  extends BaseNativeDockDragPlatformBackend {
  static final _LinuxNativeDockDragBindings? _bindings =
      _LinuxNativeDockDragBindings.maybeLoad();

  @override
  bool registerWindowHandle({
    required int windowId,
    required int nativeWindowHandle,
  }) {
    final _LinuxNativeDockDragBindings? bindings = _bindings;
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
  bool attachDragWindow({
    required int windowId,
    required int anchorX,
    required int anchorY,
  }) {
    final _LinuxNativeDockDragBindings? bindings = _bindings;
    if (bindings == null) {
      return false;
    }

    return bindings.attachDragWindow(windowId, anchorX, anchorY);
  }

  @override
  bool startDrag({required int sourceWindowId, required int tabId}) {
    final _LinuxNativeDockDragBindings? bindings = _bindings;
    if (bindings == null) {
      return false;
    }

    return bindings.startDrag(sourceWindowId, tabId);
  }
}

final class _LinuxNativeDockDragBindings {
  _LinuxNativeDockDragBindings._({
    required this.registerWindow,
    required this.unregisterWindow,
    required this.attachDragWindow,
    required this.startDrag,
  });

  final bool Function(int windowId, int nativeWindowHandle) registerWindow;
  final void Function(int windowId) unregisterWindow;
  final bool Function(int windowId, int anchorX, int anchorY) attachDragWindow;
  final bool Function(int sourceWindowId, int tabId) startDrag;

  static _LinuxNativeDockDragBindings? maybeLoad() {
    try {
      final ffi.DynamicLibrary library = ffi.DynamicLibrary.executable();
      final int Function(int, int) registerWindowRaw = library
          .lookupFunction<
            ffi.Int32 Function(ffi.Int32, ffi.IntPtr),
            int Function(int, int)
          >('KddwDockDragBridge_RegisterWindow');
      final void Function(int) unregisterWindow = library
          .lookupFunction<ffi.Void Function(ffi.Int32), void Function(int)>(
            'KddwDockDragBridge_UnregisterWindow',
          );
      final int Function(int, int, int) attachDragWindowRaw = library
          .lookupFunction<
            ffi.Int32 Function(ffi.Int32, ffi.Int32, ffi.Int32),
            int Function(int, int, int)
          >('KddwDockDragBridge_AttachDragWindow');
      final int Function(int, int) startDragRaw = library
          .lookupFunction<
            ffi.Int32 Function(ffi.Int32, ffi.Int32),
            int Function(int, int)
          >('KddwDockDragBridge_StartDrag');

      return _LinuxNativeDockDragBindings._(
        registerWindow: (int windowId, int nativeWindowHandle) =>
            registerWindowRaw(windowId, nativeWindowHandle) != 0,
        unregisterWindow: unregisterWindow,
        attachDragWindow: (int windowId, int anchorX, int anchorY) =>
            attachDragWindowRaw(windowId, anchorX, anchorY) != 0,
        startDrag: (int sourceWindowId, int tabId) =>
            startDragRaw(sourceWindowId, tabId) != 0,
      );
    } catch (_) {
      return null;
    }
  }
}
