import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'dock_controller.dart';
import 'experimental_window_api.dart';

typedef NativeDockHoverChanged = void Function(int windowId);
typedef NativeDockHoverCleared = void Function(int windowId);
typedef NativeDockDragFinished = void Function();

final class NativeDockDragCoordinator extends ChangeNotifier {
  NativeDockDragCoordinator({
    required NativeDockHoverChanged onHoveredWindowChanged,
    required NativeDockHoverCleared onHoveredWindowLeft,
    required NativeDockDragFinished onNativeDragFinished,
  }) : _onHoveredWindowChanged = onHoveredWindowChanged,
       _onHoveredWindowLeft = onHoveredWindowLeft,
       _onNativeDragFinished = onNativeDragFinished {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  static const MethodChannel _channel = MethodChannel('kddw_native_dock_drag');

  final NativeDockHoverChanged _onHoveredWindowChanged;
  final NativeDockHoverCleared _onHoveredWindowLeft;
  final NativeDockDragFinished _onNativeDragFinished;

  bool _nativeDragActive = false;
  _PendingAttachedDragWindow? _pendingAttachedDragWindow;

  bool get isNativeDragActive => _nativeDragActive;

  bool registerWindow({
    required int windowId,
    required ExperimentalWindowController controller,
  }) {
    final _NativeDockDragBindings? bindings =
        _NativeDockDragBindings.maybeLoad();
    if (bindings == null) {
      return false;
    }

    final bool registered = bindings.registerWindow(
      windowId,
      controller.linuxFlutterViewHandleAddress,
    );
    pocLog('nativeDrag registerWindow window=$windowId ok=$registered');
    return registered;
  }

  void unregisterWindow({required int windowId}) {
    final _NativeDockDragBindings? bindings =
        _NativeDockDragBindings.maybeLoad();
    if (bindings == null) {
      return;
    }

    bindings.unregisterWindow(windowId);
    pocLog('nativeDrag unregisterWindow window=$windowId');
  }

  bool attachDragWindow({required int windowId, required Offset? dragAnchor}) {
    if (dragAnchor == null) {
      return false;
    }

    if (!_nativeDragActive) {
      _pendingAttachedDragWindow = _PendingAttachedDragWindow(
        windowId: windowId,
        dragAnchor: dragAnchor,
      );
      pocLog(
        'nativeDrag queueAttachDragWindow window=$windowId '
        'anchor=${dragAnchor.dx.round()},${dragAnchor.dy.round()}',
      );
      return true;
    }

    return _attachDragWindowNow(windowId: windowId, dragAnchor: dragAnchor);
  }

  bool _attachDragWindowNow({
    required int windowId,
    required Offset dragAnchor,
  }) {
    final _NativeDockDragBindings? bindings =
        _NativeDockDragBindings.maybeLoad();
    if (bindings == null) {
      return false;
    }

    final bool attached = bindings.attachDragWindow(
      windowId,
      dragAnchor.dx.round(),
      dragAnchor.dy.round(),
    );
    pocLog(
      'nativeDrag attachDragWindow window=$windowId '
      'anchor=${dragAnchor.dx.round()},${dragAnchor.dy.round()} ok=$attached',
    );
    return attached;
  }

  bool startDrag({required int sourceWindowId, required int tabId}) {
    if (_nativeDragActive) {
      return false;
    }

    final _NativeDockDragBindings? bindings =
        _NativeDockDragBindings.maybeLoad();
    if (bindings == null) {
      return false;
    }

    final bool started = bindings.startDrag(sourceWindowId, tabId);
    pocLog('nativeDrag start source=$sourceWindowId tab=$tabId ok=$started');
    if (!started) {
      _pendingAttachedDragWindow = null;
      return false;
    }

    _nativeDragActive = true;
    final _PendingAttachedDragWindow? pendingAttachedDragWindow =
        _pendingAttachedDragWindow;
    if (pendingAttachedDragWindow != null) {
      _attachDragWindowNow(
        windowId: pendingAttachedDragWindow.windowId,
        dragAnchor: pendingAttachedDragWindow.dragAnchor,
      );
      _pendingAttachedDragWindow = null;
    }
    notifyListeners();
    return true;
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    if (!_nativeDragActive && call.method != 'dragEnded') {
      return;
    }

    final Map<Object?, Object?>? args =
        call.arguments as Map<Object?, Object?>?;
    switch (call.method) {
      case 'dragHover':
        final int? windowId = (args?['windowId'] as num?)?.toInt();
        if (windowId != null) {
          _onHoveredWindowChanged(windowId);
        }
        break;
      case 'dragLeave':
        final int? windowId = (args?['windowId'] as num?)?.toInt();
        if (windowId != null) {
          _onHoveredWindowLeft(windowId);
        }
        break;
      case 'dragEnded':
        final bool accepted = args?['accepted'] == true;
        final int? windowId = (args?['windowId'] as num?)?.toInt();
        if (accepted && windowId != null) {
          _onHoveredWindowChanged(windowId);
        }
        _pendingAttachedDragWindow = null;
        _nativeDragActive = false;
        notifyListeners();
        _onNativeDragFinished();
        break;
    }
  }

  @override
  void dispose() {
    _pendingAttachedDragWindow = null;
    _channel.setMethodCallHandler(null);
    super.dispose();
  }
}

final class _PendingAttachedDragWindow {
  const _PendingAttachedDragWindow({
    required this.windowId,
    required this.dragAnchor,
  });

  final int windowId;
  final Offset dragAnchor;
}

final class _NativeDockDragBindings {
  _NativeDockDragBindings._({
    required this.registerWindow,
    required this.unregisterWindow,
    required this.attachDragWindow,
    required this.startDrag,
  });

  final bool Function(int windowId, int viewHandle) registerWindow;
  final void Function(int windowId) unregisterWindow;
  final bool Function(int windowId, int anchorX, int anchorY) attachDragWindow;
  final bool Function(int sourceWindowId, int tabId) startDrag;

  static _NativeDockDragBindings? _instance;
  static bool _loadAttempted = false;

  static _NativeDockDragBindings? maybeLoad() {
    if (!Platform.isLinux) {
      return null;
    }

    if (_instance != null || _loadAttempted) {
      return _instance;
    }

    _loadAttempted = true;

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

      _instance = _NativeDockDragBindings._(
        registerWindow: (int windowId, int viewHandle) =>
            registerWindowRaw(windowId, viewHandle) != 0,
        unregisterWindow: unregisterWindow,
        attachDragWindow: (int windowId, int anchorX, int anchorY) =>
            attachDragWindowRaw(windowId, anchorX, anchorY) != 0,
        startDrag: (int sourceWindowId, int tabId) =>
            startDragRaw(sourceWindowId, tabId) != 0,
      );
    } catch (_) {
      _instance = null;
    }

    return _instance;
  }
}
