library;

abstract interface class NativeDockDragPlatformBackend {
  int? get mainWindowHandle;

  void setWindowHeaderDockTargetingMode(int mode);

  bool registerWindowHandle({
    required int windowId,
    required int nativeWindowHandle,
  });

  void unregisterWindow({required int windowId});

  bool attachDragWindow({
    required int windowId,
    required int anchorX,
    required int anchorY,
  });

  bool startDrag({required int sourceWindowId, required int tabId});
}

abstract base class BaseNativeDockDragPlatformBackend
    implements NativeDockDragPlatformBackend {
  @override
  int? get mainWindowHandle => null;

  @override
  void setWindowHeaderDockTargetingMode(int mode) {}
}

final class UnsupportedNativeDockDragPlatformBackend
    extends BaseNativeDockDragPlatformBackend {

  @override
  bool registerWindowHandle({
    required int windowId,
    required int nativeWindowHandle,
  }) => false;

  @override
  void unregisterWindow({required int windowId}) {}

  @override
  bool attachDragWindow({
    required int windowId,
    required int anchorX,
    required int anchorY,
  }) => false;

  @override
  bool startDrag({required int sourceWindowId, required int tabId}) => false;
}
