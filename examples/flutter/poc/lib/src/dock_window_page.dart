import 'package:flutter/material.dart';

import 'dock_controller.dart';
import 'dock_tab_handle.dart';
import 'dock_runtime.dart';
import 'native_dock_drag.dart';

class DockWindowPage extends StatefulWidget {
  const DockWindowPage({
    super.key,
    required this.controller,
    required this.nativeDockDragCoordinator,
    required this.windowId,
    this.detachedWindowCountBuilder,
    this.onDockBackRequested,
  });

  final DockController controller;
  final NativeDockDragCoordinator nativeDockDragCoordinator;
  final int windowId;
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
    final bool showTabHandles = window.tabs.length >= 2;
    final bool dockTargetActive = widget.controller.isDockTargetActive(
      windowId: window.id,
    );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      color: dockTargetActive
          ? theme.colorScheme.primary.withValues(alpha: 0.25)
          : Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _buildTabStrip(
            theme,
            window,
            showTabHandles: showTabHandles,
          ),
          const Divider(height: 1),
          Expanded(
            child: selectedTab == null
                ? Center(
                    child: Text(
                      'Drop a tab here from another window',
                      style: theme.textTheme.bodyLarge,
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                    child: _TabContentCard(
                      tab: selectedTab,
                      message:
                          'This window is a valid drop target. Drag a tab '
                          'from any other existing window and release over '
                          'this dock area to move it here.',
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabStrip(
    ThemeData theme,
    DockWindowModel window, {
    required bool showTabHandles,
  }) {
    return Container(
      height: showTabHandles ? 56 : 44,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: const Color(0xFFF7F7F7),
      child: Row(
        children: <Widget>[
          if (showTabHandles)
            Expanded(
              child: window.tabs.isEmpty
                  ? const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('No tabs in this window'),
                    )
                  : FocusTraversalGroup(
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: window.tabs.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemBuilder: (BuildContext context, int index) {
                          final DockTabModel tab = window.tabs[index];
                          final bool isSelected = window.selectedTabId == tab.id;
                          final bool isBeingDragged = widget.controller
                              .isDockedTabActive(
                                windowId: window.id,
                                tabId: tab.id,
                              );

                          return DockTabHandle(
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
            ),
          if (showTabHandles) const SizedBox(width: 12),
          Chip(
            label: Text(widget.controller.windowRoleLabel(window.id)),
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          if (widget.detachedWindowCountBuilder != null) ...<Widget>[
            const SizedBox(width: 8),
            Chip(
              label: Text('${widget.detachedWindowCountBuilder!()} detached'),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ],
          if (widget.onDockBackRequested != null) ...<Widget>[
            const SizedBox(width: 8),
            TextButton(
              onPressed: widget.onDockBackRequested,
              child: const Text('Dock Back'),
            ),
          ] else ...<Widget>[
            const SizedBox(width: 8),
            Text(
              '${window.tabs.length} tabs',
              style: theme.textTheme.labelMedium,
            ),
          ],
        ],
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(tab.title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Text(message),
        ),
      ],
    );
  }
}