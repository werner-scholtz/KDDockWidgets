import 'package:flutter_test/flutter_test.dart';
import 'package:poc/src/dock_controller.dart';

void main() {
  test(
    'crossing the detach threshold creates a detached window immediately',
    () {
      final DockController controller = DockController();

      controller.beginDockedTabDrag(
        windowId: DockController.mainWindowId,
        tabId: 1,
        startGlobalPosition: const Offset(20, 20),
        anchor: const Offset(20, 20),
      );
      controller.updateHoveredDockTarget(windowId: null);
      controller.updateDockedTabDrag(
        globalPosition: const Offset(140, 180),
        windowId: DockController.mainWindowId,
      );

      expect(controller.detachedWindows, hasLength(1));
      expect(controller.detachedWindows.single.tabs.single.id, 1);
      expect(
        controller.mainWindow.tabs.any((DockTabModel tab) => tab.id == 1),
        isFalse,
      );
    },
  );

  test('releasing outside any dock creates a new detached window', () {
    final DockController controller = DockController();

    controller.beginDockedTabDrag(
      windowId: DockController.mainWindowId,
      tabId: 1,
      startGlobalPosition: const Offset(20, 20),
      anchor: const Offset(20, 20),
    );
    controller.updateHoveredDockTarget(windowId: null);
    controller.updateDockedTabDrag(
      globalPosition: const Offset(140, 180),
      windowId: DockController.mainWindowId,
    );
    controller.endDockedTabDrag();

    expect(controller.detachedWindows, hasLength(1));
    expect(controller.detachedWindows.single.tabs.single.id, 1);
    expect(
      controller.mainWindow.tabs.any((DockTabModel tab) => tab.id == 1),
      isFalse,
    );
  });

  test('dropping a tab on another existing window docks it there', () {
    final DockController controller = DockController();

    controller.beginDockedTabDrag(
      windowId: DockController.mainWindowId,
      tabId: 1,
      startGlobalPosition: const Offset(20, 20),
      anchor: const Offset(20, 20),
    );
    controller.updateHoveredDockTarget(windowId: null);
    controller.updateDockedTabDrag(
      globalPosition: const Offset(140, 180),
      windowId: DockController.mainWindowId,
    );
    controller.endDockedTabDrag();

    final DockWindowModel detachedWindow = controller.detachedWindows.single;

    controller.beginDockedTabDrag(
      windowId: DockController.mainWindowId,
      tabId: 2,
      startGlobalPosition: const Offset(20, 20),
      anchor: const Offset(20, 20),
    );
    controller.updateHoveredDockTarget(windowId: detachedWindow.id);
    controller.updateDockedTabDrag(
      globalPosition: const Offset(260, 40),
      windowId: detachedWindow.id,
    );
    controller.endDockedTabDrag();

    final DockWindowModel updatedDetachedWindow = controller.detachedWindows
        .singleWhere(
          (DockWindowModel window) => window.id == detachedWindow.id,
        );

    expect(updatedDetachedWindow.tabs.map((DockTabModel tab) => tab.id), [
      1,
      2,
    ]);
    expect(
      controller.mainWindow.tabs.any((DockTabModel tab) => tab.id == 2),
      isFalse,
    );
  });

  test('small drags do not detach a tab', () {
    final DockController controller = DockController();

    controller.beginDockedTabDrag(
      windowId: DockController.mainWindowId,
      tabId: 3,
      startGlobalPosition: const Offset(20, 20),
      anchor: const Offset(20, 20),
    );
    controller.updateDockedTabDrag(
      globalPosition: const Offset(35, 30),
      windowId: DockController.mainWindowId,
    );
    controller.endDockedTabDrag();

    expect(
      controller.mainWindow.tabs.any((DockTabModel tab) => tab.id == 3),
      isTrue,
    );
    expect(controller.detachedWindows, isEmpty);
  });

  test(
    'canceling a live detached drag restores the detached source window',
    () {
      final DockController controller = DockController();

      controller.beginDockedTabDrag(
        windowId: DockController.mainWindowId,
        tabId: 1,
        startGlobalPosition: const Offset(20, 20),
        anchor: const Offset(20, 20),
      );
      controller.updateHoveredDockTarget(windowId: null);
      controller.updateDockedTabDrag(
        globalPosition: const Offset(140, 180),
        windowId: DockController.mainWindowId,
      );
      controller.endDockedTabDrag();

      final DockWindowModel sourceWindow = controller.detachedWindows.single;

      controller.beginDockedTabDrag(
        windowId: sourceWindow.id,
        tabId: 1,
        startGlobalPosition: const Offset(40, 40),
        anchor: const Offset(20, 20),
      );
      controller.updateHoveredDockTarget(windowId: null);
      controller.updateDockedTabDrag(
        globalPosition: const Offset(220, 260),
        windowId: sourceWindow.id,
      );

      expect(controller.detachedWindows, hasLength(2));

      controller.cancelDockedTabDrag();

      expect(controller.detachedWindows, hasLength(1));
      expect(controller.detachedWindows.single.id, sourceWindow.id);
      expect(
        controller.detachedWindows.single.tabs.map(
          (DockTabModel tab) => tab.id,
        ),
        [1],
      );
    },
  );

  test('closing a detached window returns its tabs to the main window', () {
    final DockController controller = DockController();

    controller.beginDockedTabDrag(
      windowId: DockController.mainWindowId,
      tabId: 1,
      startGlobalPosition: const Offset(20, 20),
      anchor: const Offset(20, 20),
    );
    controller.updateHoveredDockTarget(windowId: null);
    controller.updateDockedTabDrag(
      globalPosition: const Offset(140, 180),
      windowId: DockController.mainWindowId,
    );
    controller.endDockedTabDrag();

    final int detachedWindowId = controller.detachedWindows.single.id;
    controller.closeDetachedWindow(detachedWindowId);

    expect(controller.detachedWindows, isEmpty);
    expect(
      controller.mainWindow.tabs.any((DockTabModel tab) => tab.id == 1),
      isTrue,
    );
    expect(controller.mainWindow.selectedTabId, 1);
  });

  test(
    'the drag proxy is only visible in the latest window receiving moves',
    () {
      final DockController controller = DockController();

      controller.beginDockedTabDrag(
        windowId: DockController.mainWindowId,
        tabId: 1,
        startGlobalPosition: const Offset(20, 20),
        anchor: const Offset(20, 20),
      );

      expect(
        controller.shouldShowDragProxyInWindow(DockController.mainWindowId),
        isTrue,
      );
      expect(controller.shouldShowDragProxyInWindow(1), isFalse);

      controller.updateHoveredDockTarget(windowId: 1);
      controller.updateDockedTabDrag(
        globalPosition: const Offset(260, 40),
        windowId: 1,
      );

      expect(
        controller.shouldShowDragProxyInWindow(DockController.mainWindowId),
        isFalse,
      );
      expect(controller.shouldShowDragProxyInWindow(1), isTrue);
    },
  );

  test(
    'drag release resolves against the last dock target window, not the caller',
    () {
      final DockController controller = DockController();

      controller.beginDockedTabDrag(
        windowId: DockController.mainWindowId,
        tabId: 1,
        startGlobalPosition: const Offset(20, 20),
        anchor: const Offset(20, 20),
      );
      controller.updateHoveredDockTarget(windowId: null);
      controller.updateDockedTabDrag(
        globalPosition: const Offset(140, 180),
        windowId: DockController.mainWindowId,
      );
      controller.endDockedTabDrag();

      final DockWindowModel detachedWindow = controller.detachedWindows.single;

      controller.beginDockedTabDrag(
        windowId: DockController.mainWindowId,
        tabId: 2,
        startGlobalPosition: const Offset(20, 20),
        anchor: const Offset(20, 20),
      );
      controller.updateHoveredDockTarget(windowId: detachedWindow.id);
      controller.updateDockedTabDrag(
        globalPosition: const Offset(260, 40),
        windowId: DockController.mainWindowId,
      );

      // Simulate the source window still being the one that calls endDrag.
      controller.endDockedTabDrag();

      final DockWindowModel updatedDetachedWindow = controller.detachedWindows
          .singleWhere(
            (DockWindowModel window) => window.id == detachedWindow.id,
          );
      expect(updatedDetachedWindow.tabs.map((DockTabModel tab) => tab.id), [
        1,
        2,
      ]);
    },
  );

  test('hovered dock target window controls cross-window docking', () {
    final DockController controller = DockController();

    controller.beginDockedTabDrag(
      windowId: DockController.mainWindowId,
      tabId: 3,
      startGlobalPosition: const Offset(20, 20),
      anchor: const Offset(20, 20),
    );
    controller.updateHoveredDockTarget(windowId: null);
    controller.updateDockedTabDrag(
      globalPosition: const Offset(140, 180),
      windowId: DockController.mainWindowId,
    );
    controller.endDockedTabDrag();

    final DockWindowModel detachedWindow = controller.detachedWindows.single;

    controller.beginDockedTabDrag(
      windowId: detachedWindow.id,
      tabId: 3,
      startGlobalPosition: const Offset(40, 40),
      anchor: const Offset(20, 20),
    );
    controller.updateHoveredDockTarget(windowId: DockController.mainWindowId);
    controller.updateDockedTabDrag(
      globalPosition: const Offset(140, 40),
      windowId: detachedWindow.id,
    );
    controller.endDockedTabDrag();

    expect(controller.detachedWindows, isEmpty);
    expect(controller.mainWindow.tabs.map((DockTabModel tab) => tab.id), [
      1,
      2,
      3,
    ]);
    expect(controller.mainWindow.selectedTabId, 3);
  });

  test(
    'stale exit from another window does not clear the active dock target',
    () {
      final DockController controller = DockController();

      controller.beginDockedTabDrag(
        windowId: DockController.mainWindowId,
        tabId: 1,
        startGlobalPosition: const Offset(20, 20),
        anchor: const Offset(20, 20),
      );
      controller.updateHoveredDockTarget(windowId: null);
      controller.updateDockedTabDrag(
        globalPosition: const Offset(140, 180),
        windowId: DockController.mainWindowId,
      );
      controller.endDockedTabDrag();

      final DockWindowModel detachedWindow = controller.detachedWindows.single;

      controller.beginDockedTabDrag(
        windowId: DockController.mainWindowId,
        tabId: 2,
        startGlobalPosition: const Offset(20, 20),
        anchor: const Offset(20, 20),
      );
      controller.updateHoveredDockTarget(windowId: detachedWindow.id);
      controller.clearHoveredDockTargetIfCurrent(
        windowId: DockController.mainWindowId,
      );
      controller.updateDockedTabDrag(
        globalPosition: const Offset(260, 40),
        windowId: DockController.mainWindowId,
      );
      controller.endDockedTabDrag();

      final DockWindowModel updatedDetachedWindow = controller.detachedWindows
          .singleWhere(
            (DockWindowModel window) => window.id == detachedWindow.id,
          );
      expect(updatedDetachedWindow.tabs.map((DockTabModel tab) => tab.id), [
        1,
        2,
      ]);
    },
  );
}
