import AppKit
import Carbon

class HotKeyManager {
  static let shared = HotKeyManager()

  private struct Entry {
    let combination: HotkeyCombination
    let handler: () -> Void
  }

  // Keyed by HotkeyIdentifier.rawValue for built-in actions, "app.<uuid>" for app hotkeys
  private var entries: [String: Entry] = [:]
  private var eventTap: CFMachPort?
  private var runLoopSource: CFRunLoopSource?
  private var retryScheduled = false

  private init() {
    installEventTap()
  }

  func register(
    identifier: HotkeyIdentifier, combination: HotkeyCombination, handler: @escaping () -> Void
  ) {
    register(key: identifier.rawValue, combination: combination, handler: handler)
  }

  func register(key: String, combination: HotkeyCombination, handler: @escaping () -> Void) {
    entries[key] = Entry(combination: combination, handler: handler)
    installEventTap()
  }

  func unregister(identifier: HotkeyIdentifier) {
    unregister(key: identifier.rawValue)
  }

  func unregister(key: String) {
    entries.removeValue(forKey: key)
  }

  func unregisterAll(withPrefix prefix: String) {
    entries = entries.filter { !$0.key.hasPrefix(prefix) }
  }

  func unregisterAll() {
    entries.removeAll()
  }

  private func installEventTap() {
    if let eventTap {
      if CFMachPortIsValid(eventTap) {
        return
      }
      self.eventTap = nil
      runLoopSource = nil
    }

    let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)
    guard
      let eventTap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: eventMask,
        callback: { _, type, event, userInfo in
          guard let userInfo else { return Unmanaged.passUnretained(event) }
          let manager = Unmanaged<HotKeyManager>.fromOpaque(userInfo).takeUnretainedValue()

          if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap = manager.eventTap {
              CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
          }

          guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
          }

          if manager.dispatch(event: event) {
            return nil
          }
          return Unmanaged.passUnretained(event)
        },
        userInfo: Unmanaged.passUnretained(self).toOpaque()
      )
    else {
      print("Failed to install hotkey event tap")
      scheduleEventTapRetry()
      return
    }

    retryScheduled = false
    self.eventTap = eventTap
    runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
    if let runLoopSource {
      CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
    }
    CGEvent.tapEnable(tap: eventTap, enable: true)
  }

  private func scheduleEventTapRetry() {
    guard !retryScheduled else { return }
    retryScheduled = true

    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
      guard let self else { return }
      self.retryScheduled = false
      self.installEventTap()
    }
  }

  private func dispatch(event: CGEvent) -> Bool {
    let keyCode = UInt32(event.getIntegerValueField(.keyboardEventKeycode))
    let rawFlags = event.flags.rawValue
    let selectedEntry = Self.preferredEntry(from: Array(entries.values), keyCode: keyCode, flags: rawFlags)

    if let selectedEntry {
      DispatchQueue.main.async {
        selectedEntry.handler()
      }
      return true
    }

    return false
  }

  static func preferredCombination(
    from combinations: [HotkeyCombination], keyCode: UInt32, eventModifierFlags flags: UInt64
  ) -> HotkeyCombination? {
    combinations.filter {
      $0.keyCode == keyCode && $0.matches(eventModifierFlags: flags)
    }.max {
      priority(for: $0) < priority(for: $1)
    }
  }

  private static func preferredEntry(
    from entries: [Entry], keyCode: UInt32, flags: UInt64
  ) -> Entry? {
    entries.filter {
      $0.combination.keyCode == keyCode && $0.combination.matches(eventModifierFlags: flags)
    }.max {
      priority(for: $0.combination) < priority(for: $1.combination)
    }
  }

  private static func priority(for combination: HotkeyCombination) -> Int {
    combination.optionKeyKind == .right ? 1 : 0
  }
}
