// ignore_for_file: invalid_use_of_internal_member, implementation_imports, public_member_api_docs This is a POC, so we can be a bit more lax on documentation for now.
import 'package:flutter/src/widgets/_window.dart';
import 'package:flutter/src/widgets/_window_linux.dart';

import 'experimental_window_api_backend.dart';

final class LinuxExperimentalWindowPlatformBackend implements ExperimentalWindowPlatformBackend {
  @override
  int nativeWindowHandleAddress(RegularWindowController controller) {
    final linuxController = controller as WindowControllerLinux;
    return linuxController.flutterViewHandle.address;
  }
}
