import AppKit
import ApplicationServices
import ISS

/// A hotkey that brings an app to the front, switching instantly to the desktop of its window.
struct AppHotkey: Codable, Equatable, Identifiable {
  var id = UUID()
  var name: String
  var bundleID: String
  var path: String
  var combination: HotkeyCombination?

  var hotkeyKey: String { "app.\(id.uuidString)" }
}

final class AppHotkeyStore: ObservableObject {
  static let shared = AppHotkeyStore()
  static let defaultsKey = "appHotkeys"

  @Published private(set) var apps: [AppHotkey]
  private let defaults: UserDefaults

  // Stored as a JSON string so it can also be set with `defaults write … appHotkeys -string`
  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    let json = defaults.string(forKey: Self.defaultsKey) ?? "[]"
    apps = (try? JSONDecoder().decode([AppHotkey].self, from: Data(json.utf8))) ?? []
  }

  func add(appAt url: URL) {
    guard let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier,
          !apps.contains(where: { $0.bundleID == bundleID }) else { return }
    let name = FileManager.default.displayName(atPath: url.path)
      .replacingOccurrences(of: ".app", with: "")
    apps.append(AppHotkey(name: name, bundleID: bundleID, path: url.path))
    save()
  }

  func remove(id: UUID) {
    apps.removeAll { $0.id == id }
    save()
  }

  func setCombination(_ combination: HotkeyCombination?, for id: UUID) {
    guard let index = apps.firstIndex(where: { $0.id == id }) else { return }
    apps[index].combination = combination
    save()
  }

  private func save() {
    guard let data = try? JSONEncoder().encode(apps) else { return }
    defaults.set(String(decoding: data, as: UTF8.self), forKey: Self.defaultsKey)
  }
}

/// In-process port of `ISSCli focus <app> --toggle`: no process launch per keypress.
@MainActor
enum AppFocuser {
  static func toggle(_ entry: AppHotkey) {
    let url = URL(fileURLWithPath: entry.path)
    guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: entry.bundleID).first
    else {
      open(url)
      return
    }

    if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier {
      app.hide()
      return
    }
    if app.isHidden { app.unhide() }

    // On failure the app still activates, just with the normal space animation
    guard let index = spaceIndex(of: app.processIdentifier), iss_switch_to_index(index) else {
      activate(app, fallback: url)
      return
    }
    // The posted gestures need the main run loop, so wait asynchronously for the Dock to land
    waitForSpace(index, attempts: 25) { activate(app, fallback: url) }
  }

  private static func waitForSpace(_ index: UInt32, attempts: Int, then done: @escaping () -> Void) {
    var info = ISSSpaceInfo()
    if attempts == 0 || (iss_get_space_info(&info) && info.currentIndex == index) {
      done()
      return
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
      waitForSpace(index, attempts: attempts - 1, then: done)
    }
  }

  private static func activate(_ app: NSRunningApplication, fallback url: URL) {
    let element = AXUIElementCreateApplication(app.processIdentifier)
    AXUIElementSetAttributeValue(element, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
    // Some apps (e.g. Spark) report success but stay in the background, so check before trusting it
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
      if NSWorkspace.shared.frontmostApplication?.processIdentifier != app.processIdentifier {
        open(url)
      }
    }
  }

  private static func open(_ url: URL) {
    NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
  }

  /// Space index of the app's frontmost real window on the cursor's display.
  private static func spaceIndex(of pid: pid_t) -> UInt32? {
    let options: CGWindowListOption = [.optionAll, .excludeDesktopElements]
    guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
    else { return nil }

    for window in windows {
      guard window[kCGWindowOwnerPID as String] as? pid_t == pid,
            window[kCGWindowLayer as String] as? Int == 0,
            let boundsDict = window[kCGWindowBounds as String] as CFTypeRef?,
            let bounds = CGRect(dictionaryRepresentation: boundsDict as! CFDictionary),
            // Apps keep tiny helper windows around; a real window is bigger than this
            bounds.width >= 100, bounds.height >= 100,
            let windowID = window[kCGWindowNumber as String] as? UInt32
      else { continue }

      var index: UInt32 = 0
      // Hidden helper windows (e.g. Electron's) belong to no space, so they are skipped here
      if iss_get_window_space_index(windowID, &index) { return index }
    }
    return nil
  }
}
