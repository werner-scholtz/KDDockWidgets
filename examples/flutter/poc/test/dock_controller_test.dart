import 'package:flutter_test/flutter_test.dart';
import 'package:poc/src/dock_controller.dart';

void main() {
  test('crossing the detach threshold creates a detached window immediately', () {
    final controller = DockController()
      ..beginDockedTabDrag(
        windowId: DockController.mainWindowId,
        tabId: 1,
        startGlobalPosition: const Offset(20, 20),
        anchor: const Offset(20, 20),
      )
      ..updateHoveredDockTarget(windowId: null)
      ..updateDockedTabDrag(globalPosition: const Offset(140, 180), windowId: DockController.mainWindowId);

    expect(controller.detachedWindows, hasLength(1));
    expect(controller.detachedWindows.single.tabs.single.id, 1);
    expect(controller.mainWindow.tabs.any((DockTabModel tab) => tab.id == 1), isFalse);
  });

  test('window titles follow the selected tab for each window', () {
    final controller = DockController();

    expect(controller.windowTitle(DockController.mainWindowId), 'Main Window - Inspector');

    controller.selectDockedTab(windowId: DockController.mainWindowId, tabId: 2);

    expect(controller.windowTitle(DockController.mainWindowId), 'Main Window - Console');

    controller
      ..beginDockedTabDrag(
        windowId: DockController.mainWindowId,
        tabId: 2,
        startGlobalPosition: const Offset(20, 20),
        anchor: const Offset(20, 20),
      )
      ..updateHoveredDockTarget(windowId: null)
      ..updateDockedTabDrag(globalPosition: const Offset(140, 180), windowId: DockController.mainWindowId)
      ..endDockedTabDrag();

    final detachedWindowId = controller.detachedWindows.single.id;
    expect(controller.windowTitle(detachedWindowId), 'Console');
  });

  test('releasing outside any dock creates a new detached window', () {
    final controller = DockController()
      ..beginDockedTabDrag(
        windowId: DockController.mainWindowId,
        tabId: 1,
        startGlobalPosition: const Offset(20, 20),
        anchor: const Offset(20, 20),
      )
      ..updateHoveredDockTarget(windowId: null)
      ..updateDockedTabDrag(globalPosition: const Offset(140, 180), windowId: DockController.mainWindowId)
      ..endDockedTabDrag();

    expect(controller.detachedWindows, hasLength(1));
    expect(controller.detachedWindows.single.tabs.single.id, 1);
    expect(controller.mainWindow.tabs.any((DockTabModel tab) => tab.id == 1), isFalse);
  });

  test('dropping a tab on another existing window docks it there', () {
    final controller = DockController()
      ..beginDockedTabDrag(
        windowId: DockController.mainWindowId,
        tabId: 1,
        startGlobalPosition: const Offset(20, 20),
        anchor: const Offset(20, 20),
      )
      ..updateHoveredDockTarget(windowId: null)
      ..updateDockedTabDrag(globalPosition: const Offset(140, 180), windowId: DockController.mainWindowId)
      ..endDockedTabDrag();

    final detachedWindow = controller.detachedWindows.single;

    controller
      ..beginDockedTabDrag(
        windowId: DockController.mainWindowId,
        tabId: 2,
        startGlobalPosition: const Offset(20, 20),
        anchor: const Offset(20, 20),
      )
      ..updateHoveredDockTarget(windowId: detachedWindow.id)
      ..updateDockedTabDrag(globalPosition: const Offset(260, 40), windowId: detachedWindow.id)
      ..endDockedTabDrag();

    final updatedDetachedWindow = controller.detachedWindows.singleWhere(
      (DockWindowModel window) => window.id == detachedWindow.id,
    );

    expect(updatedDetachedWindow.tabs.map((DockTabModel tab) => tab.id), [1, 2]);
    expect(controller.mainWindow.tabs.any((DockTabModel tab) => tab.id == 2), isFalse);
  });

  test('small drags do not detach a tab', () {
    final controller = DockController()
      ..beginDockedTabDrag(
        windowId: DockController.mainWindowId,
        tabId: 3,
        startGlobalPosition: const Offset(20, 20),
        anchor: const Offset(20, 20),
      )
      ..updateDockedTabDrag(globalPosition: const Offset(35, 30), windowId: DockController.mainWindowId)
      ..endDockedTabDrag();

    expect(controller.mainWindow.tabs.any((DockTabModel tab) => tab.id == 3), isTrue);
    expect(controller.detachedWindows, isEmpty);
  });

  test('canceling a live detached drag restores the detached source window', () {
    final controller = DockController()
      ..beginDockedTabDrag(
        windowId: DockController.mainWindowId,
        tabId: 1,
        startGlobalPosition: const Offset(20, 20),
        anchor: const Offset(20, 20),
      )
      ..updateHoveredDockTarget(windowId: null)
      ..updateDockedTabDrag(globalPosition: const Offset(140, 180), windowId: DockController.mainWindowId)
      ..endDockedTabDrag();

    final sourceWindow = controller.detachedWindows.single;

    controller
      ..beginDockedTabDrag(
        windowId: sourceWindow.id,
        tabId: 1,
        startGlobalPosition: const Offset(40, 40),
        anchor: const Offset(20, 20),
      )
      ..updateHoveredDockTarget(windowId: null)
      ..updateDockedTabDrag(globalPosition: const Offset(220, 260), windowId: sourceWindow.id);

    expect(controller.detachedWindows, hasLength(2));

    controller.cancelDockedTabDrag();

    expect(controller.detachedWindows, hasLength(1));
    expect(controller.detachedWindows.single.id, sourceWindow.id);
    expect(controller.detachedWindows.single.tabs.map((DockTabModel tab) => tab.id), [1]);
  });

  test('closing a detached window returns its tabs to the main window', () {
    final controller = DockController()
      ..beginDockedTabDrag(
        windowId: DockController.mainWindowId,
        tabId: 1,
        startGlobalPosition: const Offset(20, 20),
        anchor: const Offset(20, 20),
      )
      ..updateHoveredDockTarget(windowId: null)
      ..updateDockedTabDrag(globalPosition: const Offset(140, 180), windowId: DockController.mainWindowId)
      ..endDockedTabDrag();

    final detachedWindowId = controller.detachedWindows.single.id;
    controller.closeDetachedWindow(detachedWindowId);

    expect(controller.detachedWindows, isEmpty);
    expect(controller.mainWindow.tabs.any((DockTabModel tab) => tab.id == 1), isTrue);
    expect(controller.mainWindow.selectedTabId, 1);
  });

  test('native window header move highlights the hovered dock target', () {
    final controller = DockController()
      ..beginDockedTabDrag(
        windowId: DockController.mainWindowId,
        tabId: 1,
        startGlobalPosition: const Offset(20, 20),
        anchor: const Offset(20, 20),
      )
      ..updateHoveredDockTarget(windowId: null)
      ..updateDockedTabDrag(globalPosition: const Offset(140, 180), windowId: DockController.mainWindowId)
      ..endDockedTabDrag();

    final detachedWindowId = controller.detachedWindows.single.id;

    controller
      ..beginWindowHeaderDrag(sourceWindowId: detachedWindowId)
      ..updateHoveredDockTarget(windowId: DockController.mainWindowId);

    expect(controller.isDockTargetActive(windowId: DockController.mainWindowId), isTrue);

    controller.updateHoveredDockTarget(windowId: null);

    expect(controller.isDockTargetActive(windowId: DockController.mainWindowId), isFalse);
  });

  test('ending a native window header move docks the detached window', () {
    final controller = DockController()
      ..beginDockedTabDrag(
        windowId: DockController.mainWindowId,
        tabId: 1,
        startGlobalPosition: const Offset(20, 20),
        anchor: const Offset(20, 20),
      )
      ..updateHoveredDockTarget(windowId: null)
      ..updateDockedTabDrag(globalPosition: const Offset(140, 180), windowId: DockController.mainWindowId)
      ..endDockedTabDrag();

    final detachedWindowId = controller.detachedWindows.single.id;

    controller
      ..beginWindowHeaderDrag(sourceWindowId: detachedWindowId)
      ..updateHoveredDockTarget(windowId: DockController.mainWindowId);

    final docked = controller.endWindowHeaderDrag(
      sourceWindowId: detachedWindowId,
      targetWindowId: DockController.mainWindowId,
    );

    expect(docked, isTrue);
    expect(controller.detachedWindows, isEmpty);
    expect(controller.mainWindow.tabs.map((DockTabModel tab) => tab.id), [2, 3, 1]);
    expect(controller.mainWindow.selectedTabId, 1);
  });

  test('ending a native window header move without a target is a no-op', () {
    final controller = DockController()
      ..beginDockedTabDrag(
        windowId: DockController.mainWindowId,
        tabId: 1,
        startGlobalPosition: const Offset(20, 20),
        anchor: const Offset(20, 20),
      )
      ..updateHoveredDockTarget(windowId: null)
      ..updateDockedTabDrag(globalPosition: const Offset(140, 180), windowId: DockController.mainWindowId)
      ..endDockedTabDrag();

    final detachedWindowId = controller.detachedWindows.single.id;
    controller.beginWindowHeaderDrag(sourceWindowId: detachedWindowId);

    final docked = controller.endWindowHeaderDrag(sourceWindowId: detachedWindowId, targetWindowId: null);

    expect(docked, isFalse);
    expect(controller.detachedWindows, hasLength(1));
    expect(controller.detachedWindows.single.id, detachedWindowId);
  });

  test('the drag proxy is only visible in the latest window receiving moves', () {
    final controller = DockController()
      ..beginDockedTabDrag(
        windowId: DockController.mainWindowId,
        tabId: 1,
        startGlobalPosition: const Offset(20, 20),
        anchor: const Offset(20, 20),
      );

    expect(controller.shouldShowDragProxyInWindow(DockController.mainWindowId), isTrue);
    expect(controller.shouldShowDragProxyInWindow(1), isFalse);

    controller
      ..updateHoveredDockTarget(windowId: 1)
      ..updateDockedTabDrag(globalPosition: const Offset(260, 40), windowId: 1);

    expect(controller.shouldShowDragProxyInWindow(DockController.mainWindowId), isFalse);
    expect(controller.shouldShowDragProxyInWindow(1), isTrue);
  });

  test('drag release resolves against the last dock target window, not the caller', () {
    final controller = DockController()
      ..beginDockedTabDrag(
        windowId: DockController.mainWindowId,
        tabId: 1,
        startGlobalPosition: const Offset(20, 20),
        anchor: const Offset(20, 20),
      )
      ..updateHoveredDockTarget(windowId: null)
      ..updateDockedTabDrag(globalPosition: const Offset(140, 180), windowId: DockController.mainWindowId)
      ..endDockedTabDrag();

    final detachedWindow = controller.detachedWindows.single;

    controller
      ..beginDockedTabDrag(
        windowId: DockController.mainWindowId,
        tabId: 2,
        startGlobalPosition: const Offset(20, 20),
        anchor: const Offset(20, 20),
      )
      ..updateHoveredDockTarget(windowId: detachedWindow.id)
      ..updateDockedTabDrag(globalPosition: const Offset(260, 40), windowId: DockController.mainWindowId)
      // Simulate the source window still being the one that calls endDrag.
      ..endDockedTabDrag();

    final updatedDetachedWindow = controller.detachedWindows.singleWhere(
      (DockWindowModel window) => window.id == detachedWindow.id,
    );
    expect(updatedDetachedWindow.tabs.map((DockTabModel tab) => tab.id), [1, 2]);
  });

  test('hovered dock target window controls cross-window docking', () {
    final controller = DockController()
      ..beginDockedTabDrag(
        windowId: DockController.mainWindowId,
        tabId: 3,
        startGlobalPosition: const Offset(20, 20),
        anchor: const Offset(20, 20),
      )
      ..updateHoveredDockTarget(windowId: null)
      ..updateDockedTabDrag(globalPosition: const Offset(140, 180), windowId: DockController.mainWindowId)
      ..endDockedTabDrag();

    final detachedWindow = controller.detachedWindows.single;

    controller
      ..beginDockedTabDrag(
        windowId: detachedWindow.id,
        tabId: 3,
        startGlobalPosition: const Offset(40, 40),
        anchor: const Offset(20, 20),
      )
      ..updateHoveredDockTarget(windowId: DockController.mainWindowId)
      ..updateDockedTabDrag(globalPosition: const Offset(140, 40), windowId: detachedWindow.id)
      ..endDockedTabDrag();

    expect(controller.detachedWindows, isEmpty);
    expect(controller.mainWindow.tabs.map((DockTabModel tab) => tab.id), [1, 2, 3]);
    expect(controller.mainWindow.selectedTabId, 3);
  });

  test('stale exit from another window does not clear the active dock target', () {
    final controller = DockController()
      ..beginDockedTabDrag(
        windowId: DockController.mainWindowId,
        tabId: 1,
        startGlobalPosition: const Offset(20, 20),
        anchor: const Offset(20, 20),
      )
      ..updateHoveredDockTarget(windowId: null)
      ..updateDockedTabDrag(globalPosition: const Offset(140, 180), windowId: DockController.mainWindowId)
      ..endDockedTabDrag();

    final detachedWindow = controller.detachedWindows.single;

    controller
      ..beginDockedTabDrag(
        windowId: DockController.mainWindowId,
        tabId: 2,
        startGlobalPosition: const Offset(20, 20),
        anchor: const Offset(20, 20),
      )
      ..updateHoveredDockTarget(windowId: detachedWindow.id)
      ..clearHoveredDockTargetIfCurrent(windowId: DockController.mainWindowId)
      ..updateDockedTabDrag(globalPosition: const Offset(260, 40), windowId: DockController.mainWindowId)
      ..endDockedTabDrag();

    final updatedDetachedWindow = controller.detachedWindows.singleWhere(
      (DockWindowModel window) => window.id == detachedWindow.id,
    );
    expect(updatedDetachedWindow.tabs.map((DockTabModel tab) => tab.id), [1, 2]);
  });
}
