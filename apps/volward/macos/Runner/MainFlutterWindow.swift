import Cocoa
import FlutterMacOS
import UserNotifications

/// Posts notifications as Volward itself (an `osascript` notification belongs to
/// Script Editor, so clicking it never reaches the app) and routes clicks back to
/// Dart as `openCoverageResult(snapshotId)`.
final class CoverageNotifier: NSObject, UNUserNotificationCenterDelegate {
  static let shared = CoverageNotifier()

  private static let snapshotKey = "snapshotId"
  private var channel: FlutterMethodChannel?
  /// Click that arrived before Dart asked for it (e.g. app launched by the click).
  private var pendingSnapshotId: String?

  func attach(messenger: FlutterBinaryMessenger) {
    UNUserNotificationCenter.current().delegate = self
    let channel = FlutterMethodChannel(
      name: "com.volward/notifications",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return }
      switch call.method {
      case "show":
        let args = call.arguments as? [String: Any] ?? [:]
        self.show(
          title: args["title"] as? String ?? "",
          body: args["body"] as? String ?? "",
          snapshotId: args["snapshotId"] as? String,
          result: result
        )
      case "takePendingOpen":
        result(self.pendingSnapshotId)
        self.pendingSnapshotId = nil
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    self.channel = channel
  }

  private func show(
    title: String,
    body: String,
    snapshotId: String?,
    result: @escaping FlutterResult
  ) {
    let center = UNUserNotificationCenter.current()
    center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
      guard granted else {
        DispatchQueue.main.async { result(false) }
        return
      }
      let content = UNMutableNotificationContent()
      content.title = title
      content.body = body
      content.sound = .default
      if let snapshotId {
        content.userInfo = [CoverageNotifier.snapshotKey: snapshotId]
      }
      let request = UNNotificationRequest(
        identifier: "coverage-\(snapshotId ?? UUID().uuidString)",
        content: content,
        trigger: nil
      )
      center.add(request) { error in
        DispatchQueue.main.async { result(error == nil) }
      }
    }
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler:
      @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .sound])
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let snapshotId =
      response.notification.request.content.userInfo[CoverageNotifier.snapshotKey]
      as? String
    DispatchQueue.main.async {
      NSApp.activate(ignoringOtherApps: true)
      NSApp.windows.first { $0 is MainFlutterWindow }?.makeKeyAndOrderFront(nil)
      if let snapshotId {
        self.pendingSnapshotId = snapshotId
        self.channel?.invokeMethod("openCoverageResult", arguments: snapshotId) { reply in
          if reply is Bool, reply as? Bool == true {
            self.pendingSnapshotId = nil
          }
        }
      }
      completionHandler()
    }
  }
}

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

private enum StorageOverviewBridge {
  private static let capacityKeys: Set<URLResourceKey> = [
    .volumeURLKey,
    .volumeNameKey,
    .volumeIsLocalKey,
    .volumeIsReadOnlyKey,
    .volumeTotalCapacityKey,
    .volumeAvailableCapacityKey,
  ]

  private static func volume(for path: String) throws -> [String: Any] {
    let url = URL(fileURLWithPath: path.isEmpty ? "/" : path)
      .resolvingSymlinksInPath()
    let values = try url.resourceValues(forKeys: capacityKeys)
    guard values.volumeIsLocal == true,
      values.volumeIsReadOnly != true,
      let volumeURL = values.volume,
      let total = values.volumeTotalCapacity,
      let available = values.volumeAvailableCapacity,
      total > 0,
      available >= 0
    else {
      throw NSError(domain: "StorageOverview", code: 1)
    }

    return [
      "id": volumeURL.path,
      "name": values.volumeName ?? volumeURL.lastPathComponent,
      "rootPath": volumeURL.path,
      "totalBytes": Int64(total),
      "availableBytes": min(Int64(total), Int64(available)),
    ]
  }

  private static func location(
    id: String,
    kind: String,
    url: URL,
    volumeId: String
  ) -> [String: Any]? {
    var isDirectory: ObjCBool = false
    guard
      FileManager.default.fileExists(
        atPath: url.path,
        isDirectory: &isDirectory
      ), isDirectory.boolValue,
      directoryContentsAreReadable(at: url)
    else {
      return nil
    }

    return [
      "id": id,
      "name": url.lastPathComponent,
      "path": url.path,
      "kind": kind,
      "volumeId": volumeId,
    ]
  }

  private static func directoryContentsAreReadable(at url: URL) -> Bool {
    var enumerationError: Error?
    guard
      let enumerator = FileManager.default.enumerator(
        at: url,
        includingPropertiesForKeys: nil,
        options: [.skipsSubdirectoryDescendants],
        errorHandler: { _, error in
          enumerationError = error
          return false
        }
      )
    else {
      return false
    }

    _ = enumerator.nextObject()
    return enumerationError == nil
  }

  static func load(selectedPath: String?) throws -> [String: Any] {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let path = selectedPath.flatMap { $0.isEmpty ? nil : $0 } ?? home.path
    let selectedVolume = try volume(for: path)
    guard let selectedVolumeId = selectedVolume["id"] as? String else {
      throw NSError(domain: "StorageOverview", code: 2)
    }

    let candidates: [(id: String, kind: String, url: URL)] = [
      ("home", "home", home),
      ("applications", "applications", URL(fileURLWithPath: "/Applications")),
      ("desktop", "desktop", home.appendingPathComponent("Desktop")),
      ("downloads", "downloads", home.appendingPathComponent("Downloads")),
      ("documents", "documents", home.appendingPathComponent("Documents")),
    ]
    var volumesById: [String: [String: Any]] = [
      selectedVolumeId: selectedVolume
    ]
    var locations: [[String: Any]] = []

    for candidate in candidates {
      guard let candidateVolume = try? volume(for: candidate.url.path),
        let candidateVolumeId = candidateVolume["id"] as? String,
        let item = location(
          id: candidate.id,
          kind: candidate.kind,
          url: candidate.url,
          volumeId: candidateVolumeId
        )
      else {
        continue
      }
      volumesById[candidateVolumeId] = candidateVolume
      locations.append(item)
    }

    let otherVolumes =
      volumesById
      .filter { $0.key != selectedVolumeId }
      .sorted { $0.key < $1.key }
      .map { $0.value }
    return [
      "selectedVolumeId": selectedVolumeId,
      "volumes": [selectedVolume] + otherVolumes,
      "locations": locations,
    ]
  }
}

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // The smallest content box the dashboard is tested at (see the responsive
    // sweeps in storage_steward_home_test.dart). 900x700 was larger than the
    // usable area of a 1024x640 scaled display, so the window could not be
    // opened at all there.
    self.contentMinSize = NSSize(width: 620, height: 600)

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

    let storageChannel = FlutterMethodChannel(
      name: "com.volward/storage_overview",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    storageChannel.setMethodCallHandler { call, result in
      guard call.method == "loadOverview" else {
        result(FlutterMethodNotImplemented)
        return
      }

      let arguments = call.arguments as? [String: Any]
      do {
        result(
          try StorageOverviewBridge.load(
            selectedPath: arguments?["selectedPath"] as? String
          ))
      } catch {
        result(
          FlutterError(
            code: "capacity_unavailable",
            message: error.localizedDescription,
            details: nil
          ))
      }
    }

    CoverageNotifier.shared.attach(messenger: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()

    NSApp.activate(ignoringOtherApps: true)
    makeKeyAndOrderFront(nil)
  }
}
