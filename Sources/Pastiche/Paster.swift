import AppKit
import Carbon.HIToolbox
import Foundation

/// Puts an item back on the pasteboard and, when allowed, presses ⌘V in the
/// app the user came from.
@MainActor
enum Paster {
    /// Writes the item to the general pasteboard.
    ///
    /// Returns the fingerprint written, so the monitor can ignore the change
    /// it is about to observe instead of re-recording our own write.
    @discardableResult
    static func copyToPasteboard(_ item: ClipboardItem, store: ClipboardStore) -> String? {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch item.kind {
        case .text:
            guard let text = item.text else { return nil }
            pasteboard.setString(text, forType: .string)
            return item.fingerprint
        case .image:
            // Write the stored PNG as-is. Writing the NSImage would put a TIFF
            // on the board, which is several times larger.
            if let png = store.pngData(for: item) {
                pasteboard.setData(png, forType: .png)
            } else if let image = store.image(for: item) {
                pasteboard.writeObjects([image])
            } else {
                return nil
            }
            return item.fingerprint
        }
    }

    /// Terminal emulators. In these, ⌘V with an image makes the terminal
    /// handle the image itself (iTerm2 asks how to paste it), while ⌃V reaches
    /// the program running inside, such as Claude Code, which reads the image
    /// from the pasteboard on its own.
    static let terminalBundleIDs: Set<String> = [
        "com.googlecode.iterm2",
        "com.apple.Terminal",
        "com.mitchellh.ghostty",
        "com.github.wez.wezterm",
        "net.kovidgoyal.kitty",
        "io.alacritty",
        "dev.warp.Warp-Stable",
    ]

    /// Sends ⌘V to whatever is frontmost, or ⌃V when an image goes into a
    /// terminal and the user enabled that in Settings.
    ///
    /// The caller must have already given focus back to the target app;
    /// synthetic events go to the frontmost application, not to a chosen one.
    ///
    /// Never prompts: the permission is requested only when the user turns on
    /// automatic pasting in Settings. Without it the popup shows a banner.
    static func sendPasteKeystroke(for kind: ItemKind, controlVInTerminals: Bool) {
        guard hasAccessibilityPermission(prompt: false) else { return }
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        // Don't let our own synthetic ⌘V be swallowed by a stale modifier the
        // user is still physically holding from the hotkey.
        source.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )

        let vKey = CGKeyCode(kVK_ANSI_V)
        let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        let useControl = controlVInTerminals && kind == .image && terminalBundleIDs.contains(frontmost)
        let flags: CGEventFlags = useControl ? .maskControl : .maskCommand
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    // MARK: - Accessibility permission

    static func hasAccessibilityPermission(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    /// Quits and reopens the app.
    ///
    /// A fresh Accessibility grant is normally picked up live, but not always;
    /// when it is not, only a new process sees it.
    /// Environment marker telling the replacement process that the instance
    /// it can see is on its way out, not a rival to defer to.
    static let relaunchMarker = "PASTICHE_RELAUNCH"

    static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.environment = [relaunchMarker: "1"]
        // Terminate only once the replacement is actually on its way, so a
        // failed launch does not leave the user with no app at all.
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            if let error {
                NSLog("Pastiche: relaunch failed: \(error.localizedDescription)")
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                NSApp.terminate(nil)
            }
        }
    }

    /// Shows the system prompt and opens the right Settings pane, because the
    /// prompt alone is easy to dismiss and hard to find again.
    static func requestAccessibilityPermission() {
        _ = hasAccessibilityPermission(prompt: true)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
