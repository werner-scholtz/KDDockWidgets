// ignore_for_file: implementation_imports, invalid_use_of_internal_member, public_member_api_docs This is a POC, so we can be a bit more lax on documentation for now.

import 'package:flutter/src/widgets/_window.dart';

abstract interface class ExperimentalWindowPlatformBackend {
  int nativeWindowHandleAddress(RegularWindowController controller);
}
