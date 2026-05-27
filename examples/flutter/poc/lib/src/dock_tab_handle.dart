// ignore_for_file: public_member_api_docs This is a POC, so we can be a bit more lax on documentation for now.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'dock_controller.dart';
import 'dock_runtime.dart';

class DockTabHandle extends StatefulWidget {
  const DockTabHandle({
    required this.controller,
    required this.tabPointerCoordinator,
    required this.window,
    required this.tab,
    required this.isSelected,
    required this.isBeingDragged,
    super.key,
  });

  final DockController controller;
  final DockTabPointerCoordinator tabPointerCoordinator;
  final DockWindowModel window;
  final DockTabModel tab;
  final bool isSelected;
  final bool isBeingDragged;

  @override
  State<DockTabHandle> createState() => _DockTabHandleState();
}

class _DockTabHandleState extends State<DockTabHandle> {
  final FocusNode _focusNode = FocusNode();
  bool _showFocusHighlight = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _selectTab() {
    widget.controller.selectDockedTab(windowId: widget.window.id, tabId: widget.tab.id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final indicatorColor = widget.isBeingDragged
        ? widget.tab.accentColor.withValues(alpha: 0.5)
        : widget.isSelected
        ? widget.tab.accentColor
        : _showFocusHighlight
        ? theme.colorScheme.primary
        : Colors.transparent;

    return Semantics(
      button: true,
      selected: widget.isSelected,
      label: '${widget.tab.title} tab',
      hint: 'Press Enter or Space to select. Use left and right arrows to move focus between tabs.',
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
            widget.tabPointerCoordinator.handlePointerDown(window: widget.window, tab: widget.tab, event: event);
          },
          onPointerMove: (PointerMoveEvent event) {
            widget.tabPointerCoordinator.handlePointerMove(window: widget.window, tab: widget.tab, event: event);
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
              color: widget.isSelected
                  ? widget.tab.accentColor.withValues(alpha: 0.08)
                  : _showFocusHighlight
                  ? Colors.black.withValues(alpha: 0.04)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              border: Border(bottom: BorderSide(color: indicatorColor, width: 3)),
            ),
            child: Text(
              widget.tab.title,
              style: TextStyle(
                fontWeight: widget.isSelected ? FontWeight.w600 : FontWeight.w400,
                color: widget.isSelected ? const Color(0xFF222222) : const Color(0xFF666666),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
