import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/native_dock_drag.dart';
import 'src/dock_controller.dart';
import 'src/dock_runtime.dart';
import 'src/experimental_window_api.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runWidget(const MainApp());
}

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  final DockController _controller = DockController();
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  final bool _windowingEnabled = experimentalWindowingEnabled;
  late final ExperimentalWindowController? _rootWindowController =
      _windowingEnabled
      ? ExperimentalWindowController(
          preferredSize: const Size(980, 680),
          title: 'KDDockWidgets Flutter POC',
        )
      : null;
  late final DockRuntimeCoordinator? _runtimeCoordinator =
      _windowingEnabled && _rootWindowController != null
      ? DockRuntimeCoordinator(
          controller: _controller,
          rootWindowController: _rootWindowController,
        )
      : null;
  final bool _isWaylandSession =
      Platform.isLinux && Platform.environment.containsKey('WAYLAND_DISPLAY');

  @override
  void initState() {
    super.initState();
    if (!_windowingEnabled || _runtimeCoordinator == null) {
      return;
    }

    _controller.addListener(_syncDetachedNativeWindows);
    _runtimeCoordinator.setSyncRequestHandler(_syncDetachedNativeWindows);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      _runtimeCoordinator.registerRootWindow();
    });
  }

  @override
  void dispose() {
    if (_windowingEnabled) {
      _controller.removeListener(_syncDetachedNativeWindows);
      _runtimeCoordinator?.dispose();
      _rootWindowController?.dispose();
    }
    _controller.dispose();
    super.dispose();
  }

  ThemeData _buildTheme() => ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1F6F78)),
    useMaterial3: true,
  );

  @override
  Widget build(BuildContext context) {
    if (!_windowingEnabled || _rootWindowController == null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'KDDockWidgets Flutter POC',
        theme: _buildTheme(),
        home: const _WindowingDisabledPage(),
      );
    }

    return ExperimentalWindowHost(
      controller: _rootWindowController,
      child: MaterialApp(
        navigatorKey: _navigatorKey,
        debugShowCheckedModeBanner: false,
        title: 'KDDockWidgets Flutter POC',
        theme: _buildTheme(),
        home: DockWindowPage(
          controller: _controller,
          windowId: DockController.mainWindowId,
          windowLabel: 'Main dock area',
          windowSubtitle:
              'Drag a tab into another existing window to dock it there, or '
              'release outside every dock to create a new native window.',
          nativeDockDragCoordinator:
              _runtimeCoordinator!.nativeDockDragCoordinator,
          detachedWindowCountBuilder: () => _controller.detachedWindows.length,
        ),
      ),
    );
  }

  void _syncDetachedNativeWindows() =>
      _runtimeCoordinator!.syncDetachedNativeWindows(
        navigatorKey: _navigatorKey,
        buildDetachedWindowRoot: (int windowId) => MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: _buildTheme(),
          home: DockWindowPage(
            controller: _controller,
            windowId: windowId,
            windowLabel: 'Dock window $windowId',
            windowSubtitle: _isWaylandSession
                ? 'This detached window now uses native drag routing for '
                      'cross-window hover on Linux/Wayland.'
                : 'This native window can accept tabs dragged from the main '
                      'window or other detached windows.',
            nativeDockDragCoordinator:
                _runtimeCoordinator.nativeDockDragCoordinator,
            onDockBackRequested: () {
              _controller.closeDetachedWindow(windowId);
              _syncDetachedNativeWindows();
            },
          ),
        ),
      );
}

class _WindowingDisabledPage extends StatelessWidget {
  const _WindowingDisabledPage();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Experimental windowing is required',
                      style: theme.textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      describeExperimentalWindowingRequirement(),
                      style: theme.textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 16),
                    SelectableText(
                      experimentalWindowingEnableCommand,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class DockWindowPage extends StatefulWidget {
  const DockWindowPage({
    super.key,
    required this.controller,
    required this.nativeDockDragCoordinator,
    required this.windowId,
    required this.windowLabel,
    required this.windowSubtitle,
    this.detachedWindowCountBuilder,
    this.onDockBackRequested,
  });

  final DockController controller;
  final NativeDockDragCoordinator nativeDockDragCoordinator;
  final int windowId;
  final String windowLabel;
  final String windowSubtitle;
  final int Function()? detachedWindowCountBuilder;
  final VoidCallback? onDockBackRequested;

  @override
  State<DockWindowPage> createState() => _DockWindowPageState();
}

class _DockWindowPageState extends State<DockWindowPage> {
  final GlobalKey _canvasKey = GlobalKey();
  late DockTabPointerCoordinator _tabPointerCoordinator;

  @override
  void initState() {
    super.initState();
    _tabPointerCoordinator = _createTabPointerCoordinator();
  }

  @override
  void didUpdateWidget(covariant DockWindowPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller &&
        oldWidget.nativeDockDragCoordinator ==
            widget.nativeDockDragCoordinator &&
        oldWidget.windowId == widget.windowId) {
      return;
    }

    _tabPointerCoordinator.dispose();
    _tabPointerCoordinator = _createTabPointerCoordinator();
  }

  @override
  void dispose() {
    _tabPointerCoordinator.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        widget.controller,
        widget.nativeDockDragCoordinator,
      ]),
      builder: (BuildContext context, Widget? child) {
        final DockWindowModel? window = widget.controller.windowById(
          widget.windowId,
        );
        if (window == null) {
          return const SizedBox.shrink();
        }

        final DragProxyModel? dragProxy = widget.controller.activeDragProxy;
        final bool showDragProxy =
            !widget.nativeDockDragCoordinator.isNativeDragActive &&
            widget.controller.shouldShowDragProxyInWindow(widget.windowId);
        final Rect? canvasRect = _canvasGlobalRect();

        return Material(
          color: Theme.of(context).colorScheme.surface,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Stack(
                key: _canvasKey,
                clipBehavior: Clip.none,
                children: <Widget>[
                  Positioned.fill(child: _buildWindowSurface(context, window)),
                  if (showDragProxy &&
                      dragProxy != null &&
                      dragProxy.movedFarEnough &&
                      canvasRect != null)
                    _buildDragProxy(dragProxy, canvasRect),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  DockTabPointerCoordinator _createTabPointerCoordinator() {
    return DockTabPointerCoordinator(
      controller: widget.controller,
      nativeDockDragCoordinator: widget.nativeDockDragCoordinator,
      pageWindowId: widget.windowId,
    );
  }

  Widget _buildWindowSurface(BuildContext context, DockWindowModel window) {
    final ThemeData theme = Theme.of(context);
    final DockTabModel? selectedTab = widget.controller.selectedTabForWindow(
      window.id,
    );
    final bool dockTargetActive = widget.controller.isDockTargetActive(
      windowId: window.id,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      widget.windowLabel,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.windowSubtitle,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              if (widget.detachedWindowCountBuilder != null)
                Text(
                  '${widget.detachedWindowCountBuilder!()} detached',
                  style: theme.textTheme.labelLarge,
                ),
              if (widget.onDockBackRequested != null) ...<Widget>[
                const SizedBox(width: 12),
                FilledButton.tonal(
                  onPressed: widget.onDockBackRequested,
                  child: const Text('Dock Window Back'),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: Stack(
            children: <Widget>[
              AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                curve: Curves.easeOut,
                decoration: BoxDecoration(
                  color: dockTargetActive
                      ? theme.colorScheme.primary.withValues(alpha: 0.06)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: dockTargetActive
                        ? theme.colorScheme.primary
                        : const Color(0xFFCCCCCC),
                    width: dockTargetActive ? 2 : 1,
                  ),
                  boxShadow: dockTargetActive
                      ? <BoxShadow>[
                          BoxShadow(
                            color: theme.colorScheme.primary.withValues(
                              alpha: 0.16,
                            ),
                            blurRadius: 18,
                            spreadRadius: 2,
                          ),
                        ]
                      : const <BoxShadow>[],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Container(
                      height: 40,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: const BoxDecoration(
                        color: Color(0xFFF2F2F2),
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(11),
                        ),
                      ),
                      child: Row(
                        children: <Widget>[
                          Text(
                            window.isMainWindow ? 'Main dock' : 'Detached dock',
                          ),
                          const Spacer(),
                          Text('${window.tabs.length} tabs'),
                        ],
                      ),
                    ),
                    _buildTabStrip(window),
                    const Divider(height: 1),
                    Expanded(
                      child: selectedTab == null
                          ? const Center(
                              child: Text(
                                'Drop a tab here from another window',
                              ),
                            )
                          : Padding(
                              padding: const EdgeInsets.all(12),
                              child: _TabContentCard(
                                tab: selectedTab,
                                message:
                                    'This window is a valid drop target. Drag a '
                                    'tab from any other existing window and release '
                                    'over this dock area to move it here.',
                              ),
                            ),
                    ),
                  ],
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 120),
                    curve: Curves.easeOut,
                    opacity: dockTargetActive ? 1 : 0,
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withValues(
                            alpha: 0.08,
                          ),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: theme.colorScheme.primary.withValues(
                              alpha: 0.35,
                            ),
                          ),
                        ),
                        child: Center(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 10,
                              ),
                              child: Text(
                                'Release to dock here',
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: theme.colorScheme.onPrimary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTabStrip(DockWindowModel window) {
    if (window.tabs.isEmpty) {
      return const SizedBox(
        height: 56,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Text('No tabs in this window'),
          ),
        ),
      );
    }

    return SizedBox(
      height: 56,
      child: FocusTraversalGroup(
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          scrollDirection: Axis.horizontal,
          itemCount: window.tabs.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (BuildContext context, int index) {
            final DockTabModel tab = window.tabs[index];
            final bool isSelected = window.selectedTabId == tab.id;
            final bool isBeingDragged = widget.controller.isDockedTabActive(
              windowId: window.id,
              tabId: tab.id,
            );

            return _DockTabHandle(
              controller: widget.controller,
              tabPointerCoordinator: _tabPointerCoordinator,
              window: window,
              tab: tab,
              isSelected: isSelected,
              isBeingDragged: isBeingDragged,
            );
          },
        ),
      ),
    );
  }

  Widget _buildDragProxy(DragProxyModel dragProxy, Rect canvasRect) {
    return Positioned(
      left: dragProxy.globalTopLeft.dx - canvasRect.left,
      top: dragProxy.globalTopLeft.dy - canvasRect.top,
      width: dragProxy.size.width,
      height: dragProxy.size.height,
      child: IgnorePointer(
        child: Opacity(
          opacity: 0.92,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: dragProxy.tab.accentColor, width: 2),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x22000000),
                  blurRadius: 14,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  dragProxy.tab.title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Rect? _canvasGlobalRect() {
    final RenderBox? renderBox =
        _canvasKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) {
      return null;
    }

    final Offset origin = renderBox.localToGlobal(Offset.zero);

    return origin & renderBox.size;
  }
}

class _TabContentCard extends StatelessWidget {
  const _TabContentCard({required this.tab, required this.message});

  final DockTabModel tab;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: tab.accentColor),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(tab.title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(message),
        ],
      ),
    );
  }
}

class _DockTabHandle extends StatefulWidget {
  const _DockTabHandle({
    required this.controller,
    required this.tabPointerCoordinator,
    required this.window,
    required this.tab,
    required this.isSelected,
    required this.isBeingDragged,
  });

  final DockController controller;
  final DockTabPointerCoordinator tabPointerCoordinator;
  final DockWindowModel window;
  final DockTabModel tab;
  final bool isSelected;
  final bool isBeingDragged;

  @override
  State<_DockTabHandle> createState() => _DockTabHandleState();
}

class _DockTabHandleState extends State<_DockTabHandle> {
  final FocusNode _focusNode = FocusNode();
  bool _showFocusHighlight = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _selectTab() {
    widget.controller.selectDockedTab(
      windowId: widget.window.id,
      tabId: widget.tab.id,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color borderColor = widget.isBeingDragged
        ? widget.tab.accentColor
        : _showFocusHighlight
        ? theme.colorScheme.primary
        : const Color(0xFFCCCCCC);

    return Semantics(
      button: true,
      selected: widget.isSelected,
      label: '${widget.tab.title} tab',
      hint:
          'Press Enter or Space to select. Use left and right arrows to move focus between tabs.',
      onTap: _selectTab,
      child: FocusableActionDetector(
        focusNode: _focusNode,
        includeFocusSemantics: false,
        mouseCursor: SystemMouseCursors.grab,
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.arrowRight): NextFocusIntent(),
          SingleActivator(LogicalKeyboardKey.arrowLeft): PreviousFocusIntent(),
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (ActivateIntent intent) {
              _selectTab();
              return null;
            },
          ),
        },
        onShowFocusHighlight: (bool value) {
          if (_showFocusHighlight == value) {
            return;
          }

          setState(() {
            _showFocusHighlight = value;
          });
        },
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (PointerDownEvent event) {
            _focusNode.requestFocus();
            widget.tabPointerCoordinator.handlePointerDown(
              window: widget.window,
              tab: widget.tab,
              event: event,
            );
          },
          onPointerMove: (PointerMoveEvent event) {
            widget.tabPointerCoordinator.handlePointerMove(
              window: widget.window,
              tab: widget.tab,
              event: event,
            );
          },
          onPointerUp: (PointerUpEvent event) {
            widget.tabPointerCoordinator.handlePointerEnd(
              windowId: widget.window.id,
              tabId: widget.tab.id,
              pointer: event.pointer,
            );
          },
          onPointerCancel: (PointerCancelEvent event) {
            widget.tabPointerCoordinator.handlePointerEnd(
              windowId: widget.window.id,
              tabId: widget.tab.id,
              pointer: event.pointer,
            );
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: widget.isSelected ? const Color(0xFFEAEAEA) : Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: borderColor),
              boxShadow: _showFocusHighlight
                  ? const <BoxShadow>[
                      BoxShadow(
                        color: Color(0x22000000),
                        blurRadius: 8,
                        offset: Offset(0, 2),
                      ),
                    ]
                  : const <BoxShadow>[],
            ),
            child: Text(widget.tab.title),
          ),
        ),
      ),
    );
  }
}
