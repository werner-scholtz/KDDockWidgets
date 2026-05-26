// ignore_for_file: implementation_imports
// ignore_for_file: invalid_use_of_internal_member

library;

import 'package:flutter/src/widgets/_window.dart';

abstract interface class ExperimentalWindowPlatformBackend {
  int nativeWindowHandleAddress(RegularWindowController controller);
}
