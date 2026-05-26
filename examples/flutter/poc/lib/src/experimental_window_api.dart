// ignore_for_file: implementation_imports
// ignore_for_file: invalid_use_of_internal_member

library;

import 'package:flutter/widgets.dart';
import 'package:flutter/src/foundation/_features.dart';
import 'package:flutter/src/widgets/_window.dart';
import 'package:flutter/src/widgets/_window_linux.dart';

// Centralizes the experimental Flutter multi-window dependency used by this
// POC. These symbols currently live under `package:flutter/src/...`, so the
// rest of the example should consume the wrappers below rather than private
// Flutter libraries directly.

const String experimentalWindowingEnableCommand =
    'fvm flutter config --enable-windowing';

bool get experimentalWindowingEnabled => isWindowingEnabled;

String describeExperimentalWindowingRequirement() {
  return 'Flutter windowing is disabled for this checkout. '
      'This POC depends on Flutter\'s experimental multi-window API.\n\n'
      'Enable it once with:\n'
      '$experimentalWindowingEnableCommand\n\n'
      'Then rebuild or rerun the Linux app.';
}

final class ExperimentalWindowController {
  ExperimentalWindowController({
    required Size preferredSize,
    required String title,
    VoidCallback? onDestroyed,
  }) : _controller = RegularWindowController(
         preferredSize: preferredSize,
         title: title,
         delegate: _CallbackWindowDelegate(onDestroyed: onDestroyed),
       );

  final RegularWindowController _controller;

  int get linuxFlutterViewHandleAddress {
    final WindowControllerLinux linuxController =
        _controller as WindowControllerLinux;
    return linuxController.flutterViewHandle.address;
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
    final WindowEntry entry = WindowEntry(
      controller: controller._controller,
      builder: builder,
    );
    _registry.register(entry);
    return ExperimentalWindowEntryHandle._(entry);
  }

  void unregister(ExperimentalWindowEntryHandle entry) {
    _registry.unregister(entry._entry);
  }
}

ExperimentalWindowRegistryHandle experimentalWindowRegistryOf(
  BuildContext context,
) {
  return ExperimentalWindowRegistryHandle._(WindowRegistry.of(context));
}

final class ExperimentalWindowHost extends StatelessWidget {
  const ExperimentalWindowHost({
    super.key,
    required this.controller,
    required this.child,
  });

  final ExperimentalWindowController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return RegularWindow(controller: controller._controller, child: child);
  }
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
