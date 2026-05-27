// ignore_for_file: invalid_use_of_internal_member, public_member_api_docs, implementation_imports This is an experimental API wrapper, so we need to reach into Flutter's private APIs for now.

import 'dart:io';

import 'package:flutter/src/widgets/_window.dart';
import 'package:flutter/widgets.dart';

import 'experimental_window_api/experimental_window_api_backend.dart';
import 'experimental_window_api/experimental_window_api_linux.dart';
import 'experimental_window_api/experimental_window_api_macos.dart';
import 'experimental_window_api/experimental_window_api_windows.dart';

// Centralizes the experimental Flutter multi-window dependency used by this
// POC. These symbols currently live under `package:flutter/src/...`, so the
// rest of the example should consume the wrappers below rather than private
// Flutter libraries directly.

final ExperimentalWindowPlatformBackend _windowPlatformBackend = _createWindowPlatformBackend();

final class ExperimentalWindowController {
  ExperimentalWindowController({required Size preferredSize, required String title, VoidCallback? onDestroyed})
    : _controller = RegularWindowController(
        preferredSize: preferredSize,
        title: title,
        delegate: _CallbackWindowDelegate(onDestroyed: onDestroyed),
      );

  final RegularWindowController _controller;

  int get nativeWindowHandleAddress => _windowPlatformBackend.nativeWindowHandleAddress(_controller);

  void setTitle(String title) {
    _controller.setTitle(title);
  }

  void destroy() {
    _controller.destroy();
  }

  void dispose() {
    _controller.dispose();
  }
}

final class ExperimentalWindowEntryHandle {
  const ExperimentalWindowEntryHandle._(this._entry);

  final WindowEntry _entry;
}

final class ExperimentalWindowRegistryHandle {
  const ExperimentalWindowRegistryHandle._(this._registry);

  final WindowRegistry _registry;

  ExperimentalWindowEntryHandle register({
    required ExperimentalWindowController controller,
    required WidgetBuilder builder,
  }) {
    final entry = WindowEntry(controller: controller._controller, builder: builder);
    _registry.register(entry);
    return ExperimentalWindowEntryHandle._(entry);
  }

  void unregister(ExperimentalWindowEntryHandle entry) {
    _registry.unregister(entry._entry);
  }
}

ExperimentalWindowRegistryHandle experimentalWindowRegistryOf(BuildContext context) =>
    ExperimentalWindowRegistryHandle._(WindowRegistry.of(context));

final class ExperimentalWindowHost extends StatelessWidget {
  const ExperimentalWindowHost({required this.controller, required this.child, super.key});

  final ExperimentalWindowController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) => RegularWindow(controller: controller._controller, child: child);
}

class _CallbackWindowDelegate with RegularWindowControllerDelegate {
  _CallbackWindowDelegate({this.onDestroyed});

  final VoidCallback? onDestroyed;

  @override
  void onWindowDestroyed() {
    onDestroyed?.call();
    super.onWindowDestroyed();
  }
}

ExperimentalWindowPlatformBackend _createWindowPlatformBackend() {
  if (Platform.isLinux) {
    return LinuxExperimentalWindowPlatformBackend();
  }

  if (Platform.isWindows) {
    return WindowsExperimentalWindowPlatformBackend();
  }

  if (Platform.isMacOS) {
    return MacOSExperimentalWindowPlatformBackend();
  }

  throw UnsupportedError(
    'Experimental windowing handles are only implemented for Linux, '
    'Windows, and macOS in this POC.',
  );
}
