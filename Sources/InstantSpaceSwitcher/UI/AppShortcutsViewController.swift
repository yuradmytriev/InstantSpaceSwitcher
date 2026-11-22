import AppKit
import Combine
import UniformTypeIdentifiers

/// Raycast-style app hotkeys: pick an app, record a shortcut, the hotkey toggles that app.
final class AppShortcutsViewController: NSViewController {
  private let store = AppHotkeyStore.shared
  private var cancellables = Set<AnyCancellable>()
  private let tableView = NSTableView()

  override func loadView() {
    view = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 300))
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    let appColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("app"))
    appColumn.title = "App"
    appColumn.width = 260
    tableView.addTableColumn(appColumn)

    let shortcutColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("shortcut"))
    shortcutColumn.title = "Shortcut"
    shortcutColumn.width = 210
    tableView.addTableColumn(shortcutColumn)

    tableView.delegate = self
    tableView.dataSource = self
    tableView.rowHeight = 28
    tableView.usesAlternatingRowBackgroundColors = true

    let scrollView = NSScrollView()
    scrollView.documentView = tableView
    scrollView.hasVerticalScroller = true
    scrollView.borderType = .bezelBorder
    scrollView.translatesAutoresizingMaskIntoConstraints = false

    let buttons = NSSegmentedControl(
      images: [
        NSImage(systemSymbolName: "plus", accessibilityDescription: "Add app")!,
        NSImage(systemSymbolName: "minus", accessibilityDescription: "Remove selected app")!,
      ],
      trackingMode: .momentary, target: self, action: #selector(buttonClicked(_:)))
    buttons.translatesAutoresizingMaskIntoConstraints = false

    let hint = NSTextField(
      labelWithString: "The hotkey brings the app forward, or hides it when it is already in front.")
    hint.textColor = .secondaryLabelColor
    hint.font = .systemFont(ofSize: 11)
    hint.translatesAutoresizingMaskIntoConstraints = false

    view.addSubview(scrollView)
    view.addSubview(buttons)
    view.addSubview(hint)

    NSLayoutConstraint.activate([
      scrollView.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
      scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
      scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
      scrollView.bottomAnchor.constraint(equalTo: buttons.topAnchor, constant: -8),

      buttons.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
      buttons.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),

      hint.leadingAnchor.constraint(equalTo: buttons.trailingAnchor, constant: 12),
      hint.centerYAnchor.constraint(equalTo: buttons.centerYAnchor),
    ])

    store.$apps.receive(on: RunLoop.main).sink { [weak self] _ in self?.tableView.reloadData() }
      .store(in: &cancellables)
  }

  @objc private func buttonClicked(_ sender: NSSegmentedControl) {
    if sender.selectedSegment == 0 {
      addApp()
    } else if tableView.selectedRow >= 0, tableView.selectedRow < store.apps.count {
      store.remove(id: store.apps[tableView.selectedRow].id)
    }
  }

  private func addApp() {
    let panel = NSOpenPanel()
    panel.directoryURL = URL(fileURLWithPath: "/Applications")
    panel.allowedContentTypes = [.application]
    panel.allowsMultipleSelection = true
    panel.prompt = "Add"
    guard panel.runModal() == .OK else { return }
    panel.urls.forEach { store.add(appAt: $0) }
  }

  private func handleRecording(_ combination: HotkeyCombination, for app: AppHotkey) {
    let builtIn = HotkeyIdentifier.allCases.first {
      HotkeyStore.shared.isEnabled($0) && HotkeyStore.shared.combination(for: $0) == combination
    }
    let otherApp = store.apps.first { $0.id != app.id && $0.combination == combination }
    if let owner = builtIn?.displayName ?? otherApp?.name {
      NSSound.beep()
      let alert = NSAlert()
      alert.messageText = "Shortcut already in use"
      alert.informativeText = "This shortcut is already assigned to \(owner)."
      alert.runModal()
      tableView.reloadData()
      return
    }
    store.setCombination(combination, for: app.id)
  }
}

extension AppShortcutsViewController: NSTableViewDataSource {
  func numberOfRows(in tableView: NSTableView) -> Int { store.apps.count }
}

extension AppShortcutsViewController: NSTableViewDelegate {
  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    let app = store.apps[row]
    let cell = NSTableCellView()

    if tableColumn?.identifier.rawValue == "app" {
      let icon = NSImageView(image: NSWorkspace.shared.icon(forFile: app.path))
      let label = NSTextField(labelWithString: app.name)
      [icon, label].forEach {
        $0.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview($0)
      }
      NSLayoutConstraint.activate([
        icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
        icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        icon.widthAnchor.constraint(equalToConstant: 20),
        icon.heightAnchor.constraint(equalToConstant: 20),
        label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
        label.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -4),
        label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
      ])
      return cell
    }

    let recorder = ShortcutRecorderControl(frame: NSRect(x: 0, y: 0, width: 150, height: 22))
    recorder.currentShortcut = app.combination
    recorder.translatesAutoresizingMaskIntoConstraints = false
    recorder.onRecordingComplete = { [weak self] in self?.handleRecording($0, for: app) }
    cell.addSubview(recorder)

    let clearButton = NSButton(
      image: NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: "Clear shortcut")!,
      target: self, action: #selector(clearShortcut(_:)))
    clearButton.isBordered = false
    clearButton.tag = row
    clearButton.isHidden = app.combination == nil
    clearButton.translatesAutoresizingMaskIntoConstraints = false
    cell.addSubview(clearButton)

    NSLayoutConstraint.activate([
      recorder.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
      recorder.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
      recorder.widthAnchor.constraint(equalToConstant: 150),
      recorder.heightAnchor.constraint(equalToConstant: 22),
      clearButton.leadingAnchor.constraint(equalTo: recorder.trailingAnchor, constant: 8),
      clearButton.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
    ])
    return cell
  }

  @objc private func clearShortcut(_ sender: NSButton) {
    guard sender.tag < store.apps.count else { return }
    store.setCombination(nil, for: store.apps[sender.tag].id)
  }
}
