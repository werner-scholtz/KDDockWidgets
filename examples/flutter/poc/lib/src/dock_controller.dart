import 'dart:math' as math;

import 'package:flutter/material.dart';

const bool kDebugLogs = false;

void pocLog(String message) {
  if (!kDebugLogs) {
    return;
  }

  debugPrint('[KDDW-poc] $message');
}

class DockController extends ChangeNotifier {
  static const int mainWindowId = 0;
  static const double detachThreshold = 28;
  static const Size dragProxySize = Size(220, 56);

  final List<DockWindowModel> _windows = <DockWindowModel>[
    DockWindowModel(
      id: mainWindowId,
      isMainWindow: true,
      tabs: <DockTabModel>[
        const DockTabModel(
          id: 1,
          title: 'Inspector',
          accentColor: Color(0xFF1F6F78),
        ),
        const DockTabModel(
          id: 2,
          title: 'Console',
          accentColor: Color(0xFFAA6C39),
        ),
        const DockTabModel(
          id: 3,
          title: 'Timeline',
          accentColor: Color(0xFF6C4BA6),
        ),
      ],
      selectedTabId: 1,
    ),
  ];

  _DockDragSession? _activeDrag;
  int _nextWindowId = 1;
  int? _hoveredDockTargetWindowId;

  List<DockWindowModel> get windows =>
      List<DockWindowModel>.unmodifiable(_windows);

  DockWindowModel get mainWindow => _windows.first;

  List<DockWindowModel> get detachedWindows =>
      List<DockWindowModel>.unmodifiable(
        _windows.where((DockWindowModel window) => !window.isMainWindow),
      );

  bool get hasActiveDrag => _activeDrag != null;

  int? get activeDetachedWindowId => _activeDrag?.detachedWindowId;

  Offset? get activeDragAnchor => _activeDrag?.anchor;

  String debugDragState() {
    final _DockDragSession? session = _activeDrag;
    if (session == null) {
      return 'idle';
    }

    return 'src=${session.sourceWindowId} '
        'cur=${session.currentWindowId} '
        'dock=${session.currentDockTargetWindowId?.toString() ?? 'none'} '
        'detached=${session.detachedWindowId?.toString() ?? 'none'} '
        'tab=${session.tabId}';
  }

  DockWindowModel? windowById(int windowId) {
    for (final DockWindowModel window in _windows) {
      if (window.id == windowId) {
        return window;
      }
    }

    return null;
  }

  DockTabModel? selectedTabForWindow(int windowId) {
    final DockWindowModel? window = windowById(windowId);
    if (window == null) {
      return null;
    }

    if (window.selectedTabId != null) {
      for (final DockTabModel tab in window.tabs) {
        if (tab.id == window.selectedTabId) {
          return tab;
        }
      }
    }

    if (window.tabs.isEmpty) {
      return null;
    }

    return window.tabs.first;
  }

  DragProxyModel? get activeDragProxy {
    final _DockDragSession? session = _activeDrag;
    if (session == null) {
      return null;
    }

    final double totalDistance =
        (session.latestGlobalPosition - session.startGlobalPosition).distance;

    return DragProxyModel(
      tab: session.draggedTab,
      globalTopLeft: session.latestGlobalPosition - session.anchor,
      size: dragProxySize,
      movedFarEnough: totalDistance >= detachThreshold,
    );
  }

  bool shouldShowDragProxyInWindow(int windowId) {
    return _activeDrag?.currentWindowId == windowId;
  }

  bool isDockedTabActive({required int windowId, required int tabId}) {
    final _DockDragSession? session = _activeDrag;
    if (session == null || session.tabId != tabId) {
      return false;
    }

    return (session.detachedWindowId ?? session.sourceWindowId) == windowId;
  }

  bool isDockTargetActive({required int windowId}) {
    final _DockDragSession? session = _activeDrag;
    if (session == null) {
      return false;
    }

    final bool movedFarEnough =
        (session.latestGlobalPosition - session.startGlobalPosition).distance >=
        detachThreshold;
    return movedFarEnough && session.currentDockTargetWindowId == windowId;
  }

  void selectDockedTab({required int windowId, required int tabId}) {
    final DockWindowModel? window = windowById(windowId);
    if (window == null) {
      return;
    }

    window.selectedTabId = tabId;
    notifyListeners();
  }

  void updateHoveredDockTarget({required int? windowId}) {
    if (_hoveredDockTargetWindowId == windowId) {
      return;
    }

    _hoveredDockTargetWindowId = windowId;
    final _DockDragSession? session = _activeDrag;
    if (session == null) {
      return;
    }

    _activeDrag = session.copyWith(
      currentWindowId: windowId ?? session.currentWindowId,
      currentDockTargetWindowId: windowId,
    );
    pocLog('controller hoverTarget window=${windowId?.toString() ?? 'none'}');
    notifyListeners();
  }

  void clearHoveredDockTargetIfCurrent({required int windowId}) {
    if (_hoveredDockTargetWindowId != windowId) {
      return;
    }

    updateHoveredDockTarget(windowId: null);
  }

  void beginDockedTabDrag({
    required int windowId,
    required int tabId,
    required Offset startGlobalPosition,
    required Offset anchor,
  }) {
    final DockWindowModel? window = windowById(windowId);
    if (window == null) {
      return;
    }

    final DockTabModel? tab = _tabById(windowId: windowId, tabId: tabId);
    if (tab == null) {
      return;
    }

    _hoveredDockTargetWindowId = windowId;
    _activeDrag = _DockDragSession(
      sourceWindowId: windowId,
      currentWindowId: windowId,
      currentDockTargetWindowId: windowId,
      tabId: tabId,
      draggedTab: tab,
      startGlobalPosition: startGlobalPosition,
      latestGlobalPosition: startGlobalPosition,
      anchor: anchor,
      detachedWindowId: null,
    );
    pocLog('controller beginDrag window=$windowId tab=$tabId');
    notifyListeners();
  }

  void updateDockedTabDrag({
    required Offset globalPosition,
    required int windowId,
  }) {
    final _DockDragSession? session = _activeDrag;
    if (session == null) {
      return;
    }

    int? resolvedDockTargetWindowId = _hoveredDockTargetWindowId;
    final int? detachedWindowId = session.detachedWindowId;

    final int nextWindowId =
        resolvedDockTargetWindowId ?? detachedWindowId ?? windowId;
    final bool routeChanged =
        session.currentWindowId != nextWindowId ||
        session.currentDockTargetWindowId != resolvedDockTargetWindowId ||
        session.detachedWindowId != detachedWindowId;

    _activeDrag = session.copyWith(
      latestGlobalPosition: globalPosition,
      currentWindowId: nextWindowId,
      currentDockTargetWindowId: resolvedDockTargetWindowId,
      detachedWindowId: detachedWindowId,
    );
    if (routeChanged) {
      pocLog(
        'controller dragRoute currentWindow=$nextWindowId '
        'hovered=${resolvedDockTargetWindowId?.toString() ?? 'none'} '
        'detached=${detachedWindowId?.toString() ?? 'none'}',
      );
    }
    notifyListeners();
  }

  bool endDockedTabDrag() {
    final _DockDragSession? session = _activeDrag;
    if (session == null) {
      return false;
    }

    final bool movedFarEnough =
        (session.latestGlobalPosition - session.startGlobalPosition).distance >=
        detachThreshold;
    final int? targetWindowId = session.currentDockTargetWindowId;
    final int? detachedWindowId = session.detachedWindowId;

    pocLog(
      'controller endDrag movedFarEnough=$movedFarEnough '
      'targetWindow=${targetWindowId?.toString() ?? 'none'} '
      'detachedWindow=${detachedWindowId?.toString() ?? 'none'}',
    );

    _activeDrag = null;
    _hoveredDockTargetWindowId = null;

    if (!movedFarEnough) {
      pocLog('controller endDrag outcome=cancel-too-short');
      notifyListeners();
      return false;
    }

    if (detachedWindowId != null) {
      if (targetWindowId != null && targetWindowId != detachedWindowId) {
        pocLog(
          'controller endDrag outcome=move-existing '
          'source=$detachedWindowId target=$targetWindowId '
          'tab=${session.tabId}',
        );
        _moveTabToExistingWindow(
          sourceWindowId: detachedWindowId,
          targetWindowId: targetWindowId,
          tabId: session.tabId,
        );
      } else {
        pocLog(
          'controller endDrag outcome=keep-detached '
          'window=$detachedWindowId tab=${session.tabId}',
        );
      }
      _removeWindowIfEmpty(session.sourceWindowId);
      notifyListeners();
      return true;
    }

    if (targetWindowId != null) {
      if (targetWindowId != session.sourceWindowId) {
        pocLog(
          'controller endDrag outcome=move-existing '
          'source=${session.sourceWindowId} target=$targetWindowId '
          'tab=${session.tabId}',
        );
        _moveTabToExistingWindow(
          sourceWindowId: session.sourceWindowId,
          targetWindowId: targetWindowId,
          tabId: session.tabId,
        );
      } else {
        pocLog(
          'controller endDrag outcome=drop-on-source-window '
          'window=$targetWindowId tab=${session.tabId}',
        );
      }
      notifyListeners();
      return true;
    }

    pocLog(
      'controller endDrag outcome=create-new-window '
      'source=${session.sourceWindowId} tab=${session.tabId}',
    );
    _moveTabToNewWindow(
      sourceWindowId: session.sourceWindowId,
      tabId: session.tabId,
    );
    notifyListeners();
    return true;
  }

  void cancelDockedTabDrag() {
    final _DockDragSession? session = _activeDrag;
    if (session == null) {
      return;
    }

    pocLog('controller cancelDrag');
    _activeDrag = null;
    _hoveredDockTargetWindowId = null;

    if (session.detachedWindowId != null) {
      _moveTabToExistingWindow(
        sourceWindowId: session.detachedWindowId!,
        targetWindowId: session.sourceWindowId,
        tabId: session.tabId,
      );
    }

    notifyListeners();
  }

  void closeDetachedWindow(int windowId) {
    if (windowId == mainWindowId) {
      return;
    }

    final DockWindowModel? window = windowById(windowId);
    if (window == null) {
      return;
    }

    pocLog(
      'controller closeDetachedWindow window=$windowId '
      'tabs=${window.tabs.map((DockTabModel tab) => tab.id).toList()}',
    );

    final List<DockTabModel> tabsToReturn = List<DockTabModel>.from(
      window.tabs,
    );
    mainWindow.tabs.addAll(tabsToReturn);
    if (tabsToReturn.isNotEmpty) {
      mainWindow.selectedTabId = tabsToReturn.first.id;
    }
    _windows.remove(window);
    if (_hoveredDockTargetWindowId == windowId) {
      _hoveredDockTargetWindowId = null;
    }
    notifyListeners();
  }

  DockTabModel? _tabById({required int windowId, required int tabId}) {
    final DockWindowModel? window = windowById(windowId);
    if (window == null) {
      return null;
    }

    for (final DockTabModel tab in window.tabs) {
      if (tab.id == tabId) {
        return tab;
      }
    }

    return null;
  }

  void _moveTabToExistingWindow({
    required int sourceWindowId,
    required int targetWindowId,
    required int tabId,
  }) {
    if (sourceWindowId == targetWindowId) {
      return;
    }

    final DockTabModel? extractedTab = _takeTab(
      windowId: sourceWindowId,
      tabId: tabId,
    );
    final DockWindowModel? targetWindow = windowById(targetWindowId);
    if (extractedTab == null || targetWindow == null) {
      pocLog(
        'controller moveTabToExistingWindow failed '
        'source=$sourceWindowId target=$targetWindowId tab=$tabId '
        'extracted=${extractedTab != null} targetExists=${targetWindow != null}',
      );
      return;
    }

    targetWindow.tabs.add(extractedTab);
    targetWindow.selectedTabId = extractedTab.id;
    pocLog(
      'controller moveTabToExistingWindow success '
      'source=$sourceWindowId target=$targetWindowId tab=$tabId '
      'targetTabs=${targetWindow.tabs.map((DockTabModel tab) => tab.id).toList()}',
    );
    _removeWindowIfEmpty(sourceWindowId);
  }

  int? _moveTabToNewWindow({required int sourceWindowId, required int tabId}) {
    final DockTabModel? extractedTab = _takeTab(
      windowId: sourceWindowId,
      tabId: tabId,
    );
    if (extractedTab == null) {
      pocLog(
        'controller moveTabToNewWindow failed source=$sourceWindowId tab=$tabId',
      );
      return null;
    }

    final int newWindowId = _nextWindowId++;

    _windows.add(
      DockWindowModel(
        id: newWindowId,
        isMainWindow: false,
        tabs: <DockTabModel>[extractedTab],
        selectedTabId: extractedTab.id,
      ),
    );
    pocLog(
      'controller moveTabToNewWindow success '
      'source=$sourceWindowId newWindow=$newWindowId tab=$tabId',
    );
    _removeWindowIfEmpty(sourceWindowId);
    return newWindowId;
  }

  DockTabModel? _takeTab({required int windowId, required int tabId}) {
    final DockWindowModel? window = windowById(windowId);
    if (window == null) {
      return null;
    }

    for (int index = 0; index < window.tabs.length; index += 1) {
      final DockTabModel tab = window.tabs[index];
      if (tab.id == tabId) {
        window.tabs.removeAt(index);
        _selectFallbackTab(window, removedIndex: index);
        return tab;
      }
    }

    return null;
  }

  void _selectFallbackTab(DockWindowModel window, {required int removedIndex}) {
    if (window.tabs.isEmpty) {
      window.selectedTabId = null;
      return;
    }

    final int fallbackIndex = math.min(removedIndex, window.tabs.length - 1);
    window.selectedTabId = window.tabs[fallbackIndex].id;
  }

  void _removeWindowIfEmpty(int windowId) {
    final DockWindowModel? window = windowById(windowId);
    if (window == null || window.isMainWindow || window.tabs.isNotEmpty) {
      return;
    }

    if (_activeDrag?.sourceWindowId == windowId) {
      return;
    }

    _windows.remove(window);
    if (_hoveredDockTargetWindowId == windowId) {
      _hoveredDockTargetWindowId = null;
    }
  }
}

class DockWindowModel {
  DockWindowModel({
    required this.id,
    required this.isMainWindow,
    required this.tabs,
    required this.selectedTabId,
  });

  final int id;
  final bool isMainWindow;
  final List<DockTabModel> tabs;
  int? selectedTabId;
}

class DockTabModel {
  const DockTabModel({
    required this.id,
    required this.title,
    required this.accentColor,
  });

  final int id;
  final String title;
  final Color accentColor;
}

class DragProxyModel {
  const DragProxyModel({
    required this.tab,
    required this.globalTopLeft,
    required this.size,
    required this.movedFarEnough,
  });

  final DockTabModel tab;
  final Offset globalTopLeft;
  final Size size;
  final bool movedFarEnough;
}

class _DockDragSession {
  const _DockDragSession({
    required this.sourceWindowId,
    required this.currentWindowId,
    required this.currentDockTargetWindowId,
    required this.tabId,
    required this.draggedTab,
    required this.startGlobalPosition,
    required this.latestGlobalPosition,
    required this.anchor,
    required this.detachedWindowId,
  });

  final int sourceWindowId;
  final int currentWindowId;
  final int? currentDockTargetWindowId;
  final int tabId;
  final DockTabModel draggedTab;
  final Offset startGlobalPosition;
  final Offset latestGlobalPosition;
  final Offset anchor;
  final int? detachedWindowId;

  _DockDragSession copyWith({
    Offset? latestGlobalPosition,
    int? currentWindowId,
    Object? currentDockTargetWindowId = _sentinel,
    Object? detachedWindowId = _sentinel,
  }) {
    return _DockDragSession(
      sourceWindowId: sourceWindowId,
      currentWindowId: currentWindowId ?? this.currentWindowId,
      currentDockTargetWindowId: currentDockTargetWindowId == _sentinel
          ? this.currentDockTargetWindowId
          : currentDockTargetWindowId as int?,
      tabId: tabId,
      draggedTab: draggedTab,
      startGlobalPosition: startGlobalPosition,
      latestGlobalPosition: latestGlobalPosition ?? this.latestGlobalPosition,
      anchor: anchor,
      detachedWindowId: detachedWindowId == _sentinel
          ? this.detachedWindowId
          : detachedWindowId as int?,
    );
  }
}

const Object _sentinel = Object();
