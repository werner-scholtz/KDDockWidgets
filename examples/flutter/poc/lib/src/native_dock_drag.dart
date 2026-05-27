// ignore_for_file: public_member_api_docs This is a POC, so we can be a bit more lax on documentation for now.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'dock_controller.dart';
import 'experimental_window_api.dart';
import 'native_dock_drag/native_dock_drag_backend.dart';
import 'native_dock_drag/native_dock_drag_linux.dart';
import 'native_dock_drag/native_dock_drag_macos.dart';
import 'native_dock_drag/native_dock_drag_windows.dart';

typedef NativeDockHoverChanged = void Function(int windowId);
typedef NativeDockHoverCleared = void Function(int windowId);
typedef NativeDockDragFinished = void Function();
typedef NativeWindowHeaderDragStarted = void Function(int sourceWindowId);
typedef NativeWindowHeaderDragFinished = void Function({required int sourceWindowId, required int? targetWindowId});

enum NativeWindowHeaderDockTargetingMode {
  overlap,
  cursor,
  hybrid;

  int get nativeValue => switch (this) {
    NativeWindowHeaderDockTargetingMode.overlap => 0,
    NativeWindowHeaderDockTargetingMode.cursor => 1,
    NativeWindowHeaderDockTargetingMode.hybrid => 2,
  };
}

final NativeDockDragPlatformBackend _nativeDockDragPlatformBackend = _createNativeDockDragPlatformBackend();

final class NativeDockDragCoordinator extends ChangeNotifier {
  NativeDockDragCoordinator({
    required NativeDockHoverChanged onHoveredWindowChanged,
    required NativeDockHoverCleared onHoveredWindowLeft,
    required NativeDockDragFinished onNativeDragFinished,
    required NativeWindowHeaderDragStarted onWindowHeaderDragStarted,
    required NativeWindowHeaderDragFinished onWindowHeaderDragFinished,
    NativeWindowHeaderDockTargetingMode windowHeaderDockTargetingMode = NativeWindowHeaderDockTargetingMode.cursor,
  }) : _onHoveredWindowChanged = onHoveredWindowChanged,
       _onHoveredWindowLeft = onHoveredWindowLeft,
       _onNativeDragFinished = onNativeDragFinished,
       _onWindowHeaderDragStarted = onWindowHeaderDragStarted,
       _onWindowHeaderDragFinished = onWindowHeaderDragFinished {
    _channel.setMethodCallHandler(_handleMethodCall);
    setWindowHeaderDockTargetingMode(windowHeaderDockTargetingMode);
  }

  static const MethodChannel _channel = MethodChannel('kddw_native_dock_drag');

  final NativeDockHoverChanged _onHoveredWindowChanged;
  final NativeDockHoverCleared _onHoveredWindowLeft;
  final NativeDockDragFinished _onNativeDragFinished;
  final NativeWindowHeaderDragStarted _onWindowHeaderDragStarted;
  final NativeWindowHeaderDragFinished _onWindowHeaderDragFinished;

  bool _nativeDragActive = false;
  _PendingAttachedDragWindow? _pendingAttachedDragWindow;

  bool get isNativeDragActive => _nativeDragActive;
  bool get supportsWindowHeaderDockGesture => _nativeDockDragPlatformBackend.supportsWindowHeaderDockGesture;
  bool get supportsLiveDetachedWindowDuringDrag => _nativeDockDragPlatformBackend.supportsLiveDetachedWindowDuringDrag;
  int? get mainWindowHandle => _nativeDockDragPlatformBackend.mainWindowHandle;

  void setWindowHeaderDockTargetingMode(NativeWindowHeaderDockTargetingMode mode) {
    _nativeDockDragPlatformBackend.setWindowHeaderDockTargetingMode(mode.nativeValue);
    pocLog('nativeDrag setWindowHeaderDockTargetingMode mode=$mode');
  }

  void setMainWindowTitle(String title) {
    if (!Platform.isWindows) {
      return;
    }

    unawaited(
      _channel.invokeMethod<void>('setMainWindowTitle', <String, Object?>{'title': title}).catchError((Object error) {
        pocLog('nativeDrag setMainWindowTitle error=$error');
      }),
    );
  }

  bool registerWindow({required int windowId, required ExperimentalWindowController controller}) =>
      registerWindowHandle(windowId: windowId, nativeWindowHandle: controller.nativeWindowHandleAddress);

  bool registerWindowHandle({required int windowId, required int nativeWindowHandle}) {
    final registered = _nativeDockDragPlatformBackend.registerWindowHandle(
      windowId: windowId,
      nativeWindowHandle: nativeWindowHandle,
    );
    pocLog('nativeDrag registerWindow window=$windowId ok=$registered');
    return registered;
  }

  void unregisterWindow({required int windowId}) {
    _nativeDockDragPlatformBackend.unregisterWindow(windowId: windowId);
    pocLog('nativeDrag unregisterWindow window=$windowId');
  }

  bool attachDragWindow({required int windowId, required Offset? dragAnchor}) {
    if (dragAnchor == null) {
      return false;
    }

    if (!_nativeDragActive) {
      _pendingAttachedDragWindow = _PendingAttachedDragWindow(windowId: windowId, dragAnchor: dragAnchor);
      pocLog(
        'nativeDrag queueAttachDragWindow window=$windowId '
        'anchor=${dragAnchor.dx.round()},${dragAnchor.dy.round()}',
      );
      return true;
    }

    return _attachDragWindowNow(windowId: windowId, dragAnchor: dragAnchor);
  }

  bool _attachDragWindowNow({required int windowId, required Offset dragAnchor}) {
    final attached = _nativeDockDragPlatformBackend.attachDragWindow(
      windowId: windowId,
      anchorX: dragAnchor.dx.round(),
      anchorY: dragAnchor.dy.round(),
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

    final started = _nativeDockDragPlatformBackend.startDrag(sourceWindowId: sourceWindowId, tabId: tabId);
    pocLog('nativeDrag start source=$sourceWindowId tab=$tabId ok=$started');
    if (!started) {
      _pendingAttachedDragWindow = null;
      return false;
    }

    _nativeDragActive = true;
    final pendingAttachedDragWindow = _pendingAttachedDragWindow;
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
    final args = call.arguments as Map<Object?, Object?>?;
    switch (call.method) {
      case 'dragHover':
        final windowId = (args?['windowId'] as num?)?.toInt();
        if (windowId != null) {
          _onHoveredWindowChanged(windowId);
        }
      case 'dragLeave':
        final windowId = (args?['windowId'] as num?)?.toInt();
        if (windowId != null) {
          _onHoveredWindowLeft(windowId);
        }
      case 'dragEnded':
        if (!_nativeDragActive) {
          return;
        }
        final accepted = args?['accepted'] == true;
        final windowId = (args?['windowId'] as num?)?.toInt();
        if (accepted && windowId != null) {
          _onHoveredWindowChanged(windowId);
        }
        _pendingAttachedDragWindow = null;
        _nativeDragActive = false;
        notifyListeners();
        _onNativeDragFinished();
      case 'windowHeaderDragStarted':
        final sourceWindowId = (args?['sourceWindowId'] as num?)?.toInt();
        if (sourceWindowId != null) {
          _onWindowHeaderDragStarted(sourceWindowId);
        }
      case 'windowHeaderDragEnded':
        final sourceWindowId = (args?['sourceWindowId'] as num?)?.toInt();
        if (sourceWindowId == null) {
          return;
        }
        final targetWindowId = (args?['targetWindowId'] as num?)?.toInt();
        _onWindowHeaderDragFinished(sourceWindowId: sourceWindowId, targetWindowId: targetWindowId);
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
  const _PendingAttachedDragWindow({required this.windowId, required this.dragAnchor});

  final int windowId;
  final Offset dragAnchor;
}

NativeDockDragPlatformBackend _createNativeDockDragPlatformBackend() {
  if (Platform.isLinux) {
    return LinuxNativeDockDragPlatformBackend();
  }

  if (Platform.isWindows) {
    return WindowsNativeDockDragPlatformBackend();
  }

  if (Platform.isMacOS) {
    return MacOSNativeDockDragPlatformBackend();
  }

  return UnsupportedNativeDockDragPlatformBackend();
}
