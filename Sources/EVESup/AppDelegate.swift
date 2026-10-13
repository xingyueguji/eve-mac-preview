import AppKit
import EVESupCore

/// Command-line options, mainly for testing.
struct LaunchOptions {
    var configURL = ConfigStore.defaultURL
    /// Render each settings page to a PNG in this folder, then quit.
    var snapshotDirectory: URL?
    /// Accept test commands over distributed notifications.
    var debugIPC = false

    init(arguments: [String]) {
        var index = 1
        while index < arguments.count {
            let argument = arguments[index]
            let value = index + 1 < arguments.count ? arguments[index + 1] : nil
            switch argument {
            case "--config":
                if let value { configURL = URL(fileURLWithPath: value) }
                index += 1
            case "--snapshot":
                if let value { snapshotDirectory = URL(fileURLWithPath: value) }
                index += 1
            case "--debug-ipc":
                debugIPC = true
            default:
                break
            }
            index += 1
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private(set) var state: AppState!
    private var statusItem: NSStatusItem?
    private var settingsController: SettingsWindowController?
    private let options = LaunchOptions(arguments: CommandLine.arguments)


    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = Self.makeMainMenu()
        let state = AppState(configURL: options.configURL)
        self.state = state
        state.start()
        installStatusItem()

        if let directory = options.snapshotDirectory {
            Snapshots.run(into: directory, delegate: self)
            return
        }
        if options.debugIPC {
            DebugIPC.install(state: state)
            return  // test runs shouldn't open windows
        }
        if state.isFirstLaunch || !state.permissions.screenRecording {
            showSettings(pane: state.permissions.screenRecording ? .cycling : .general)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        state?.save()
    }

    func showSettings(pane: SettingsPane? = nil) {
        if let pane { state.settingsPane = pane }
        makeSettingsWindowIfNeeded()
        settingsController?.present()
    }

    @discardableResult
    func makeSettingsWindowIfNeeded() -> NSWindow? {
        if settingsController == nil { settingsController = SettingsWindowController(state: state) }
        return settingsController?.window
    }

    // MARK: Menu bar item

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let image = NSImage(systemSymbolName: "rectangle.3.group", accessibilityDescription: "EVESup")
        image?.isTemplate = true
        item.button?.image = image
        item.button?.toolTip = "EVESup"
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let clients = state.monitor.clients

        let header = NSMenuItem(title: clients.isEmpty ? "No EVE clients running" : "Switch to", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        for client in clients {
            menu.addItem(ClosureMenuItem(client.label, checked: client.pid == state.monitor.activePID) { [weak self] in
                self?.state.switchTo(client, reason: "menu")
            })
        }

        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Show Previews", checked: state.config.previews.isEnabled) { [weak self] in
            self?.state.config.previews.isEnabled.toggle()
        })
        menu.addItem(ClosureMenuItem("Lock Preview Positions", checked: state.config.previews.locksPositions) { [weak self] in
            self?.state.config.previews.locksPositions.toggle()
        })
        if state.previews?.hasHiddenPreviews == true {
            menu.addItem(ClosureMenuItem("Show Hidden Previews") { [weak self] in
                self?.state.previews?.showHiddenPreviews()
            })
        }

        menu.addItem(.separator())
        let settings = ClosureMenuItem("Settings…") { [weak self] in self?.showSettings() }
        settings.keyEquivalent = ","
        menu.addItem(settings)
        menu.addItem(NSMenuItem(title: "Quit EVESup", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    /// EVESup has no visible menu bar, but text fields still need ⌘C/⌘V/⌘A and ⌘W.
    private static func makeMainMenu() -> NSMenu {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        appMenu.addItem(NSMenuItem(title: "Quit EVESup", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editItem.submenu = editMenu
        main.addItem(editItem)
        return main
    }
}
