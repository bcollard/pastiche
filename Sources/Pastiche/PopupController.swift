import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Borderless floating panel that can still take key focus, which a plain
/// borderless `NSWindow` cannot.
final class PopupPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Owns the popup window and every keystroke that happens while it is open.
///
/// Keyboard handling deliberately lives here rather than in SwiftUI: a single
/// local event monitor sees keys before the focused text field does, which is
/// what lets ↑/↓ drive the list while the user is typing in the search box.
@MainActor
final class PopupController {
    let model: PopupModel

    private let store: ClipboardStore
    private let settings: Settings
    private let monitor: PasteboardMonitor

    private var panel: PopupPanel?
    private var keyMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    /// The app to hand focus back to, captured before we steal it.
    private var previousApp: NSRunningApplication?

    var onOpenSettings: (() -> Void)?

    var isVisible: Bool { panel?.isVisible ?? false }

    init(store: ClipboardStore, monitor: PasteboardMonitor, settings: Settings) {
        self.store = store
        self.monitor = monitor
        self.settings = settings
        self.model = PopupModel(store: store)
    }

    // MARK: - Presentation

    func toggle() {
        isVisible ? hide(restoreFocus: true) : show()
    }

    func show() {
        let frontmost = NSWorkspace.shared.frontmostApplication
        if frontmost?.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousApp = frontmost
        }

        model.reset()
        model.accessibilityGranted = Paster.hasAccessibilityPermission(prompt: false)
        let panel = panel ?? makePanel()
        self.panel = panel
        position(panel)

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        installKeyMonitor()
        observeResignKey(for: panel)
    }

    func hide(restoreFocus: Bool) {
        removeKeyMonitor()
        removeResignObserver()
        panel?.orderOut(nil)
        if restoreFocus, let previousApp {
            previousApp.activate()
        }
    }

    private func makePanel() -> PopupPanel {
        let panel = PopupPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 580),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.animationBehavior = .utilityWindow

        let root = PopupView(
            model: model,
            settings: settings,
            onCommit: { [weak self] item in self?.commit(item) },
            onOpenSettings: { [weak self] in
                self?.hide(restoreFocus: false)
                self?.onOpenSettings?()
            },
            onClose: { [weak self] in self?.hide(restoreFocus: true) },
            onGrantAccessibility: { [weak self] in
                self?.hide(restoreFocus: false)
                Paster.requestAccessibilityPermission()
            }
        )
        panel.contentView = NSHostingView(rootView: root)
        return panel
    }

    /// Centres the panel on whichever screen the pointer is on, biased a
    /// little above centre so it sits where the eye already is.
    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let size = panel.frame.size
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2 + visible.height * 0.06
        )
        panel.setFrameOrigin(origin)
    }

    /// Closing on focus loss is what makes the popup feel like a HUD rather
    /// than a window you have to tidy away.
    private func observeResignKey(for panel: NSPanel) {
        removeResignObserver()
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide(restoreFocus: false) }
        }
    }

    private func removeResignObserver() {
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
        }
        resignObserver = nil
    }

    // MARK: - Commit

    /// Puts the item on the pasteboard, gives focus back, and presses ⌘V.
    private func commit(_ item: ClipboardItem) {
        hide(restoreFocus: true)

        guard let fingerprint = Paster.copyToPasteboard(item, store: store) else { return }
        // Our own write is about to bump the pasteboard's change count; tell
        // the monitor to let that one through untouched.
        monitor.suppressedFingerprint = fingerprint

        if settings.moveToTopOnPaste { store.moveToTop(item) }

        guard settings.autoPaste else { return }
        // Give the reactivated app a moment to become frontmost, otherwise the
        // synthetic ⌘V lands on whatever was still in front.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            Paster.sendPasteKeystroke()
        }
    }

    private func commitSelection() {
        guard let item = model.selectedItem else { return }
        commit(item)
    }

    // MARK: - Keyboard

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            // The monitor already fires on the main thread; `handle` returns a
            // Bool rather than the event so nothing non-Sendable crosses the
            // isolation boundary.
            let consumed = MainActor.assumeIsolated { self.handle(event) }
            return consumed ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    /// Returns true when the event was handled here and should not reach
    /// the focused control (the search field).
    private func handle(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let command = flags.contains(.command)
        let shift = flags.contains(.shift)
        let option = flags.contains(.option)
        let control = flags.contains(.control)

        switch Int(event.keyCode) {
        case kVK_Escape:
            if !model.query.isEmpty {
                model.query = ""
            } else {
                hide(restoreFocus: true)
            }
            return true

        case kVK_DownArrow:
            model.moveSelection(by: 1)
            return true

        case kVK_UpArrow:
            model.moveSelection(by: -1)
            return true

        case kVK_PageDown:
            model.moveSelection(by: 8)
            return true

        case kVK_PageUp:
            model.moveSelection(by: -8)
            return true

        case kVK_Home:
            model.selectFirst()
            return true

        case kVK_End:
            model.selectLast()
            return true

        // Left/right only steer the filter when the caret isn't in the search
        // field, where they have to stay as cursor movement.
        case kVK_LeftArrow where !model.searchFocused:
            model.cycleTypeFilter(by: -1)
            return true

        case kVK_RightArrow where !model.searchFocused:
            model.cycleTypeFilter(by: 1)
            return true

        case kVK_Tab:
            model.searchFocused.toggle()
            return true

        case kVK_Return, kVK_ANSI_KeypadEnter:
            if (settings.commitKey == .commandReturn) == command {
                commitSelection()
            }
            // Swallow either way: an unhandled Return in the panel just beeps.
            return true

        case kVK_Delete where command && shift:
            store.clearAll()
            return true

        case kVK_Delete where command:
            model.deleteSelected()
            return true

        // Bare Backspace deletes only while the caret is out of the search
        // field, where it has to stay as ordinary text editing.
        case kVK_Delete where settings.deleteKey == .delete && !model.searchFocused:
            model.deleteSelected()
            return true

        case kVK_ANSI_Comma where command:
            hide(restoreFocus: false)
            onOpenSettings?()
            return true

        default:
            break
        }

        // ⌘1…⌘9, ⌘0 paste the row carrying that number.
        if command, !option, !control,
           let characters = event.charactersIgnoringModifiers,
           characters.count == 1,
           let digit = Int(characters),
           let item = model.item(forDigit: digit) {
            commit(item)
            return true
        }

        // Typing with the list focused drops straight into search rather than
        // doing nothing, so the user never has to remember to press Tab first.
        if !model.searchFocused, !command, !control, !option,
           let characters = event.characters,
           characters.count == 1,
           let scalar = characters.unicodeScalars.first,
           Self.searchStartSet.contains(scalar) {
            model.searchFocused = true
            model.query.append(characters)
            return true
        }

        return false
    }

    private static let searchStartSet: CharacterSet = {
        CharacterSet.alphanumerics
            .union(.punctuationCharacters)
            .union(.symbols)
            .subtracting(.whitespacesAndNewlines)
    }()
}
