library;

import 'dart:ffi' as ffi;

import 'native_dock_drag_backend.dart';

final class WindowsNativeDockDragPlatformBackend
    extends BaseNativeDockDragPlatformBackend {
  static final _WindowsNativeDockDragBindings? _bindings =
      _WindowsNativeDockDragBindings.maybeLoad();

  @override
  bool get supportsLiveDetachedWindowDuringDrag => true;

  @override
  int? get mainWindowHandle {
    final _WindowsNativeDockDragBindings? bindings = _bindings;
    if (bindings == null) {
      return null;
    }

    final int nativeWindowHandle = bindings.getMainWindowHandle();
    return nativeWindowHandle == 0 ? null : nativeWindowHandle;
  }

  @override
  void setWindowHeaderDockTargetingMode(int mode) {
    _bindings?.setWindowHeaderDockTargetingMode(mode);
  }

  @override
  bool registerWindowHandle({
    required int windowId,
    required int nativeWindowHandle,
  }) {
    final _WindowsNativeDockDragBindings? bindings = _bindings;
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
    final _WindowsNativeDockDragBindings? bindings = _bindings;
    if (bindings == null) {
      return false;
    }

    return bindings.attachDragWindow(windowId, anchorX, anchorY);
  }

  @override
  bool startDrag({required int sourceWindowId, required int tabId}) {
    final _WindowsNativeDockDragBindings? bindings = _bindings;
    if (bindings == null) {
      return false;
    }

    return bindings.startDrag(sourceWindowId, tabId);
  }
}

final class _WindowsNativeDockDragBindings {
  _WindowsNativeDockDragBindings._({
    required this.registerWindow,
    required this.getMainWindowHandle,
    required this.setWindowHeaderDockTargetingMode,
    required this.unregisterWindow,
    required this.attachDragWindow,
    required this.startDrag,
  });

  final bool Function(int windowId, int nativeWindowHandle) registerWindow;
  final int Function() getMainWindowHandle;
  final void Function(int mode) setWindowHeaderDockTargetingMode;
  final void Function(int windowId) unregisterWindow;
  final bool Function(int windowId, int anchorX, int anchorY) attachDragWindow;
  final bool Function(int sourceWindowId, int tabId) startDrag;

  static _WindowsNativeDockDragBindings? maybeLoad() {
    try {
      final ffi.DynamicLibrary library = ffi.DynamicLibrary.executable();
      final int Function(int, int) registerWindowRaw = library
          .lookupFunction<
            ffi.Int32 Function(ffi.Int32, ffi.IntPtr),
            int Function(int, int)
          >('KddwDockDragBridge_RegisterWindow');
      final int Function() getMainWindowHandle = library
          .lookupFunction<ffi.IntPtr Function(), int Function()>(
            'KddwDockDragBridge_GetMainWindowHandle',
          );
      final void Function(int) setWindowHeaderDockTargetingMode = library
          .lookupFunction<ffi.Void Function(ffi.Int32), void Function(int)>(
            'KddwDockDragBridge_SetWindowHeaderDockTargetingMode',
          );
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

      return _WindowsNativeDockDragBindings._(
        registerWindow: (int windowId, int nativeWindowHandle) =>
            registerWindowRaw(windowId, nativeWindowHandle) != 0,
        getMainWindowHandle: getMainWindowHandle,
        setWindowHeaderDockTargetingMode: setWindowHeaderDockTargetingMode,
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
