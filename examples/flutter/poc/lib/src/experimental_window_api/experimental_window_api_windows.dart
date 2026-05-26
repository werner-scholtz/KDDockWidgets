// ignore_for_file: implementation_imports
// ignore_for_file: invalid_use_of_internal_member

library;

import 'package:flutter/src/widgets/_window.dart';
import 'package:flutter/src/widgets/_window_win32.dart';

import 'experimental_window_api_backend.dart';

final class WindowsExperimentalWindowPlatformBackend
    implements ExperimentalWindowPlatformBackend {
  @override
  int nativeWindowHandleAddress(RegularWindowController controller) {
    final WindowControllerWin32 windowsController =
        controller as WindowControllerWin32;
    return windowsController.windowHandle.address;
  }
}
