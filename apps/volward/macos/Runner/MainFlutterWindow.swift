import Cocoa
import FlutterMacOS

private enum MacSettings {
  /// Trigger TCC from the main app executable (not the Rust dylib).
  /// Metadata/stat alone does not register the app in the FDA list.
  static func touchFullDiskAccessProbe() {
    let safari = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Safari/Bookmarks.plist")
    _ = try? Data(contentsOf: safari)

    // Apple Developer Forums #757768: a real open attempt can prepopulate FDA.
    let tcc = URL(fileURLWithPath: "/Library/Application Support/com.apple.TCC/TCC.db")
    _ = try? Data(contentsOf: tcc)
  }

  static func openFullDiskAccessSettings() {
    let urls = [
      "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles",
      "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles",
    ]
    for raw in urls {
      if let url = URL(string: raw), NSWorkspace.shared.open(url) {
        return
      }
    }
  }
}

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    let channel = FlutterMethodChannel(
      name: "com.volward/macos_settings",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "touchFullDiskAccessProbe":
        MacSettings.touchFullDiskAccessProbe()
        result(nil)
      case "openFullDiskAccessSettings":
        MacSettings.openFullDiskAccessSettings()
        result(nil)
      case "bundlePath":
        result(Bundle.main.bundlePath)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()

    NSApp.activate(ignoringOtherApps: true)
    makeKeyAndOrderFront(nil)
  }
}
