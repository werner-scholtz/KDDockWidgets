// ignore_for_file: invalid_use_of_internal_member, implementation_imports, public_member_api_docs This is a POC, so we can be a bit more lax on documentation for now.

import 'package:flutter/src/widgets/_window.dart';
import 'package:flutter/src/widgets/_window_macos.dart';

import 'experimental_window_api_backend.dart';

final class MacOSExperimentalWindowPlatformBackend implements ExperimentalWindowPlatformBackend {
  @override
  int nativeWindowHandleAddress(RegularWindowController controller) {
    final macOSController = controller as WindowControllerMacOS;
    return macOSController.windowHandle.address;
  }
}
