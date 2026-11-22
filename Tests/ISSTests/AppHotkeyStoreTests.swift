import Carbon
@testable import InstantSpaceSwitcher
import XCTest

final class AppHotkeyStoreTests: XCTestCase {
    func testAddSetAndRemovePersist() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "AppHotkeyStoreTests"))
        defaults.removePersistentDomain(forName: "AppHotkeyStoreTests")
        let store = AppHotkeyStore(defaults: defaults)
        let finder = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")

        store.add(appAt: finder)
        store.add(appAt: finder) // duplicates are ignored
        XCTAssertEqual(store.apps.map(\.bundleID), ["com.apple.finder"])

        let combo = HotkeyCombination(
            keyCode: UInt32(kVK_ANSI_F), modifiers: UInt32(cmdKey | optionKey | controlKey | shiftKey),
            displayKey: "F", keyEquivalent: "f")
        store.setCombination(combo, for: store.apps[0].id)
        XCTAssertEqual(AppHotkeyStore(defaults: defaults).apps.first?.combination, combo)

        store.remove(id: store.apps[0].id)
        XCTAssertTrue(AppHotkeyStore(defaults: defaults).apps.isEmpty)
    }
}
