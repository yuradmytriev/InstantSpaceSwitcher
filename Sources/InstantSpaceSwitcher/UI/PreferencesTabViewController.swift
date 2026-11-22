import AppKit

final class PreferencesTabViewController: NSTabViewController {
  override func viewDidLoad() {
    super.viewDidLoad()

    tabStyle = .toolbar

    let generalTab = NSTabViewItem(viewController: GeneralSettingsViewController())
    generalTab.label = "General"
    generalTab.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "General")

    let shortcutsTab = NSTabViewItem(viewController: KeyboardShortcutsViewController())
    shortcutsTab.label = "Keyboard"
    shortcutsTab.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "Keyboard")

    let appsTab = NSTabViewItem(viewController: AppShortcutsViewController())
    appsTab.label = "Apps"
    appsTab.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "Apps")

    addTabViewItem(generalTab)
    addTabViewItem(shortcutsTab)
    addTabViewItem(appsTab)
  }
}
