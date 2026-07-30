import Cocoa
import FlutterMacOS

private enum MacSettings {
  private static func protectedProbeURLs() -> [URL] {
    let home = FileManager.default.homeDirectoryForCurrentUser
    return [
      home.appendingPathComponent("Library/Safari/Bookmarks.plist"),
      home.appendingPathComponent("Library/Messages/chat.db"),
      home.appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db"),
      URL(fileURLWithPath: "/Library/Application Support/com.apple.TCC/TCC.db"),
    ]
  }

  private static func touchProbeURL(_ url: URL) {
    guard let handle = try? FileHandle(forReadingFrom: url) else {
      return
    }
    defer {
      try? handle.close()
    }
    _ = handle.readData(ofLength: 1)
  }

  /// Trigger TCC from the main app executable (not the Rust dylib).
  /// Metadata/stat alone does not register the app in the FDA list.
  static func touchFullDiskAccessProbe() {
    for url in protectedProbeURLs() {
      touchProbeURL(url)
    }
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
