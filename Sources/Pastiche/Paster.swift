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
            guard let image = store.image(for: item) else { return nil }
            pasteboard.writeObjects([image])
            return item.fingerprint
        }
    }

    /// Sends ⌘V to whatever is frontmost.
    ///
    /// The caller must have already given focus back to the target app;
    /// synthetic events go to the frontmost application, not to a chosen one.
    /// Whether the system prompt has already been shown in this run.
    ///
    /// Without this the modal reappears on every single paste, which is worse
    /// than useless once the user has decided to deal with it later. The popup
    /// shows a persistent inline banner instead.
    private static var hasPromptedForAccessibility = false

    static func sendPasteKeystroke() {
        guard hasAccessibilityPermission(prompt: false) else {
            if !hasPromptedForAccessibility {
                hasPromptedForAccessibility = true
                requestAccessibilityPermission()
            }
            return
        }
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
        down?.flags = .maskCommand
        up?.flags = .maskCommand
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
