import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  static let sharedFlutterEngine: FlutterEngine = {
    let flutterEngine = FlutterEngine(name: "kddw-poc", project: nil)
    flutterEngine.perform(NSSelectorFromString("enableMultiView"))
    flutterEngine.run(withEntrypoint: nil)
    RegisterGeneratedPlugins(registry: flutterEngine)

    let registrar = flutterEngine.registrar(forPlugin: "KDDockWidgetsNativeDockDrag")
    let dockDragChannel = FlutterMethodChannel(
      name: "kddw_native_dock_drag",
      binaryMessenger: registrar.messenger)
    dock_drag_bridge_bootstrap(dockDragChannel)

    return flutterEngine
  }()

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    _ = Self.sharedFlutterEngine
    super.applicationDidFinishLaunching(notification)
  }
}
