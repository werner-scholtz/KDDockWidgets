import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterEngine = AppDelegate.sharedFlutterEngine

    let flutterViewController = FlutterViewController(
      engine: flutterEngine,
      nibName: nil,
      bundle: nil)
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    dock_drag_bridge_set_main_window(
      Int(bitPattern: Unmanaged.passUnretained(self).toOpaque()))

    let registrar = flutterEngine.registrar(forPlugin: "KDDockWidgetsNativeDockDrag")
    let dockDragChannel = FlutterMethodChannel(
      name: "kddw_native_dock_drag",
      binaryMessenger: registrar.messenger)
    dock_drag_bridge_bootstrap(dockDragChannel)

    super.awakeFromNib()
  }
}
