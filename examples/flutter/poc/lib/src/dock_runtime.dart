import 'package:flutter/material.dart';

import 'native_dock_drag.dart';
import 'dock_controller.dart';
import 'experimental_window_api.dart';

typedef DetachedWindowRootBuilder = Widget Function(int windowId);

final class DockRuntimeCoordinator {
  DockRuntimeCoordinator({
    required this.controller,
    required ExperimentalWindowController rootWindowController,
  }) {
    nativeDockDragCoordinator = NativeDockDragCoordinator(
      onHoveredWindowChanged: (int windowId) {
        controller.updateHoveredDockTarget(windowId: windowId);
      },
      onHoveredWindowLeft: (int windowId) {
        controller.clearHoveredDockTargetIfCurrent(windowId: windowId);
      },
      onNativeDragFinished: _handleNativeDragFinished,
    );
    _rootWindowController = rootWindowController;
  }

  final DockController controller;
  late final ExperimentalWindowController _rootWindowController;
  late final NativeDockDragCoordinator nativeDockDragCoordinator;
  final Map<int, ExperimentalWindowController> _detachedWindowHandles =
      <int, ExperimentalWindowController>{};
  final Set<int> _closingWindowIds = <int>{};
  bool _rootWindowRegistered = false;

  VoidCallback? _syncRequest;

  void setSyncRequestHandler(VoidCallback handler) {
    _syncRequest = handler;
  }

  void registerRootWindow() {
    if (_rootWindowRegistered) {
      return;
    }

    _registerWindowAfterFrame(
      windowId: DockController.mainWindowId,
      controller: _rootWindowController,
      onRegistered: () {
        _rootWindowRegistered = true;
      },
    );
  }

  void syncDetachedNativeWindows({
    required GlobalKey<NavigatorState> navigatorKey,
    required DetachedWindowRootBuilder buildDetachedWindowRoot,
  }) {
    final BuildContext? context = navigatorKey.currentContext;
    if (context == null) {
      return;
    }

    final ExperimentalWindowRegistryHandle registry =
        experimentalWindowRegistryOf(context);
    final Set<int> expectedWindowIds = controller.detachedWindows
        .map((DockWindowModel window) => window.id)
        .toSet();

    pocLog(
      'runtime syncDetachedNativeWindows expected=$expectedWindowIds '
      'open=${_detachedWindowHandles.keys.toList()} '
      'dragState=${controller.debugDragState()}',
    );

    for (final DockWindowModel window in controller.detachedWindows) {
      if (_detachedWindowHandles.containsKey(window.id)) {
        continue;
      }

      _openDetachedWindow(
        registry: registry,
        windowId: window.id,
        buildDetachedWindowRoot: buildDetachedWindowRoot,
      );
    }

    for (final int windowId in _detachedWindowHandles.keys.toList()) {
      if (expectedWindowIds.contains(windowId)) {
        continue;
      }

      _closingWindowIds.add(windowId);
      nativeDockDragCoordinator.unregisterWindow(windowId: windowId);
      _detachedWindowHandles[windowId]?.destroy();
    }
  }

  void dispose() {
    nativeDockDragCoordinator.unregisterWindow(
      windowId: DockController.mainWindowId,
    );
    for (final int windowId in _detachedWindowHandles.keys.toList()) {
      nativeDockDragCoordinator.unregisterWindow(windowId: windowId);
    }
    nativeDockDragCoordinator.dispose();
  }

  void _openDetachedWindow({
    required ExperimentalWindowRegistryHandle registry,
    required int windowId,
    required DetachedWindowRootBuilder buildDetachedWindowRoot,
  }) {
    pocLog('runtime openDetachedWindow window=$windowId');
    late final ExperimentalWindowEntryHandle entry;
    final ExperimentalWindowController windowController =
        ExperimentalWindowController(
          title: 'Dock window $windowId',
          preferredSize: const Size(560, 420),
          onDestroyed: () {
            pocLog('runtime detachedWindowDestroyed window=$windowId');
            registry.unregister(entry);
            _detachedWindowHandles.remove(windowId);
            nativeDockDragCoordinator.unregisterWindow(windowId: windowId);

            if (_closingWindowIds.remove(windowId)) {
              pocLog(
                'runtime detachedWindowDestroyed window=$windowId '
                'reason=sync-close',
              );
              return;
            }

            if (controller.windowById(windowId) != null) {
              pocLog(
                'runtime detachedWindowDestroyed window=$windowId '
                'reason=user-close',
              );
              controller.closeDetachedWindow(windowId);
            }
          },
        );

    entry = registry.register(
      controller: windowController,
      builder: (BuildContext context) => buildDetachedWindowRoot(windowId),
    );
    _detachedWindowHandles[windowId] = windowController;

    _registerWindowAfterFrame(
      windowId: windowId,
      controller: windowController,
      onRegistered: () {
        if (controller.activeDetachedWindowId == windowId) {
          nativeDockDragCoordinator.attachDragWindow(
            windowId: windowId,
            dragAnchor: controller.activeDragAnchor,
          );
        }
      },
    );
  }

  void _registerWindowAfterFrame({
    required int windowId,
    required ExperimentalWindowController controller,
    required VoidCallback onRegistered,
    int attempt = 0,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final bool stillExpected =
          windowId == DockController.mainWindowId ||
          identical(_detachedWindowHandles[windowId], controller);
      if (!stillExpected) {
        return;
      }

      final bool registered = nativeDockDragCoordinator.registerWindow(
        windowId: windowId,
        controller: controller,
      );
      if (registered) {
        onRegistered();
        return;
      }

      if (attempt >= 2) {
        pocLog(
          'runtime registerWindow failed window=$windowId after=${attempt + 1}',
        );
        return;
      }

      _registerWindowAfterFrame(
        windowId: windowId,
        controller: controller,
        onRegistered: onRegistered,
        attempt: attempt + 1,
      );
    });
  }

  void _handleNativeDragFinished() {
    if (!controller.hasActiveDrag) {
      return;
    }

    controller.endDockedTabDrag();
    _syncRequest?.call();
  }
}

final class DockTabPointerCoordinator {
  DockTabPointerCoordinator({
    required this.controller,
    required this.nativeDockDragCoordinator,
    required this.pageWindowId,
  });

  final DockController controller;
  final NativeDockDragCoordinator nativeDockDragCoordinator;
  final int pageWindowId;

  _PendingTabPan? _pendingTabPan;

  void handlePointerDown({
    required DockWindowModel window,
    required DockTabModel tab,
    required PointerDownEvent event,
  }) {
    _pendingTabPan = _PendingTabPan(
      pointer: event.pointer,
      windowId: window.id,
      tabId: tab.id,
      startGlobalPosition: event.position,
      anchor: Offset(
        event.localPosition.dx.clamp(
          16,
          DockController.dragProxySize.width - 16,
        ),
        DockController.dragProxySize.height / 2,
      ),
    );
  }

  void handlePointerMove({
    required DockWindowModel window,
    required DockTabModel tab,
    required PointerMoveEvent event,
  }) {
    if (nativeDockDragCoordinator.isNativeDragActive) {
      return;
    }

    final _PendingTabPan? pendingTabPan = _pendingTabPan;
    if (pendingTabPan == null ||
        pendingTabPan.pointer != event.pointer ||
        pendingTabPan.windowId != window.id ||
        pendingTabPan.tabId != tab.id) {
      return;
    }

    final bool movedFarEnough =
        (event.position - pendingTabPan.startGlobalPosition).distance >=
        DockController.detachThreshold;
    if (!movedFarEnough) {
      return;
    }

    pocLog('page[$pageWindowId] startDetachDrag tab=${tab.id}');
    controller.beginDockedTabDrag(
      windowId: window.id,
      tabId: tab.id,
      startGlobalPosition: pendingTabPan.startGlobalPosition,
      anchor: pendingTabPan.anchor,
    );
    controller.updateDockedTabDrag(
      globalPosition: event.position,
      windowId: window.id,
    );
    _pendingTabPan = null;

    final bool started = nativeDockDragCoordinator.startDrag(
      sourceWindowId: window.id,
      tabId: tab.id,
    );
    if (started) {
      controller.updateHoveredDockTarget(windowId: null);
      return;
    }

    controller.cancelDockedTabDrag();
  }

  void handlePointerEnd({
    required int windowId,
    required int tabId,
    required int pointer,
  }) {
    pocLog(
      'page[$pageWindowId] pointerUp tab=$tabId '
      'state=${controller.debugDragState()}',
    );

    final _PendingTabPan? pendingTabPan = _pendingTabPan;
    final bool selectOnly =
        pendingTabPan != null &&
        pendingTabPan.pointer == pointer &&
        pendingTabPan.windowId == windowId &&
        pendingTabPan.tabId == tabId;
    _clearPendingTabPan(windowId: windowId, tabId: tabId, pointer: pointer);
    if (nativeDockDragCoordinator.isNativeDragActive ||
        !controller.hasActiveDrag) {
      if (selectOnly && !nativeDockDragCoordinator.isNativeDragActive) {
        controller.selectDockedTab(windowId: windowId, tabId: tabId);
      }
      return;
    }

    controller.cancelDockedTabDrag();
  }

  void dispose() {
    _pendingTabPan = null;
  }

  void _clearPendingTabPan({
    required int windowId,
    required int tabId,
    int? pointer,
  }) {
    final _PendingTabPan? pendingTabPan = _pendingTabPan;
    if (pendingTabPan == null ||
        (pointer != null && pendingTabPan.pointer != pointer) ||
        pendingTabPan.windowId != windowId ||
        pendingTabPan.tabId != tabId) {
      return;
    }

    _pendingTabPan = null;
  }
}

class _PendingTabPan {
  const _PendingTabPan({
    required this.pointer,
    required this.windowId,
    required this.tabId,
    required this.startGlobalPosition,
    required this.anchor,
  });

  final int pointer;
  final int windowId;
  final int tabId;
  final Offset startGlobalPosition;
  final Offset anchor;
}
