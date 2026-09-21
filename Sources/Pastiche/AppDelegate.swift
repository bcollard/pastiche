import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = Settings.shared
    private lazy var store = ClipboardStore(settings: settings)
    private lazy var monitor = PasteboardMonitor(store: store, settings: settings)
    private lazy var popup = PopupController(store: store, monitor: monitor, settings: settings)

    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var hotKeyToken: UInt32?
    /// True when this process is a duplicate that is bowing out.
    private var isHandingOff = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !handOffToRunningInstance() else { return }

        NSApp.setActivationPolicy(.accessory)
        buildMainMenu()
        buildStatusItem()

        popup.onOpenSettings = { [weak self] in self?.openSettings() }
        settings.onShortcutChange = { [weak self] shortcut in
            self?.registerHotKey(shortcut)
        }
        registerHotKey(settings.shortcut)
        monitor.start()
        showSettingsOnFirstLaunch()
    }

    /// An accessory app has no Dock icon and no window, so a first-time user
    /// has nowhere to discover the shortcut or the Accessibility requirement.
    /// Open Settings once, the first time only.
    private func showSettingsOnFirstLaunch() {
        let key = "hasLaunchedBefore"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        openSettings()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // `store` and `monitor` are lazy. A duplicate instance never started
        // them, and touching them here would construct a second store that
        // reads and rewrites the history file underneath the live instance.
        guard !isHandingOff else { return }

        monitor.stop()
        store.save()
        if let hotKeyToken { HotKeyCenter.shared.unregister(token: hotKeyToken) }
    }

    /// Re-launching an accessory app (from Finder, Spotlight or `open`) has no
    /// window to restore, so treat it as a request for the popup.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        popup.show()
        return true
    }

    /// A second copy would register a duplicate hotkey and race the first on
    /// the history file, so defer to whichever instance got there first.
    private func handOffToRunningInstance() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        func others() -> [NSRunningApplication] {
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .filter { $0.processIdentifier != ownPID }
        }

        // A relaunch overlaps with the instance it replaces on purpose. Wait
        // for that one to finish saving and exit, rather than deferring to it
        // and leaving the user with no app running at all.
        if ProcessInfo.processInfo.environment[Paster.relaunchMarker] == "1" {
            let deadline = Date().addingTimeInterval(5)
            while !others().isEmpty, Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            }
            return false
        }

        guard let existing = others().first else { return false }
        isHandingOff = true
        existing.activate()
        NSApp.terminate(nil)
        return true
    }

    // MARK: - Hotkey

    private func registerHotKey(_ shortcut: Shortcut) {
        let registered = HotKeyCenter.shared.register(shortcut, token: &hotKeyToken) { [weak self] in
            self?.popup.toggle()
        }
        if !registered {
            presentHotKeyConflict(shortcut)
        }
        refreshStatusMenuShortcut()
    }

    private func presentHotKeyConflict(_ shortcut: Shortcut) {
        let alert = NSAlert()
        alert.messageText = "“\(shortcut.displayString)” is already in use"
        alert.informativeText = "Another app or a system shortcut has claimed this combination. Pick a different one in Settings."
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            openSettings()
        }
    }

    // MARK: - Status item

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(
            systemSymbolName: "doc.on.clipboard",
            accessibilityDescription: "Pastiche"
        )
        item.button?.image?.isTemplate = true
        item.menu = buildStatusMenu()
        statusItem = item
    }

    private func buildStatusMenu() -> NSMenu {
        let menu = NSMenu()

        let open = NSMenuItem(title: "Open Clipboard", action: #selector(togglePopup), keyEquivalent: "")
        open.target = self
        open.tag = MenuTag.open.rawValue
        menu.addItem(open)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let clear = NSMenuItem(title: "Clear History…", action: #selector(clearHistory), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Pastiche", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        return menu
    }

    private enum MenuTag: Int {
        case open = 1
    }

    /// Shows the current hotkey next to "Open Clipboard" so the menu stays
    /// truthful after the user rebinds it.
    private func refreshStatusMenuShortcut() {
        guard let item = statusItem?.menu?.item(withTag: MenuTag.open.rawValue) else { return }
        item.title = "Open Clipboard  (\(settings.shortcut.displayString))"
    }

    // MARK: - Actions

    @objc private func togglePopup() {
        popup.toggle()
    }

    @objc private func clearHistory() {
        let alert = NSAlert()
        alert.messageText = "Delete all \(store.items.count) items?"
        alert.informativeText = "This cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete All")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            store.clearAll()
        }
    }

    @objc private func openSettings() {
        if let settingsWindow {
            NSApp.activate(ignoringOtherApps: true)
            settingsWindow.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 400),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Pastiche Settings"
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(rootView: SettingsView(settings: settings, store: store))
        settingsWindow = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: - Main menu

    /// An accessory app still needs a main menu: without an Edit menu the
    /// standard text shortcuts (⌘A, ⌘C, ⌘V, ⌘Z) do nothing in our own fields.
    private func buildMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Hide Pastiche", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Quit Pastiche", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
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
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }
}
