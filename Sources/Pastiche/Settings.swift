import Carbon.HIToolbox
import Combine
import Foundation
import ServiceManagement

/// A global hotkey expressed in Carbon terms, which is what
/// `RegisterEventHotKey` wants and what the recorder produces.
struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    /// Carbon modifier mask (`cmdKey`, `optionKey`, `controlKey`, `shiftKey`).
    var carbonModifiers: UInt32

    /// Cmd+' — the default the user asked for.
    static let `default` = Shortcut(keyCode: UInt32(kVK_ANSI_Quote), carbonModifiers: UInt32(cmdKey))

    var displayString: String {
        var parts = ""
        if carbonModifiers & UInt32(controlKey) != 0 { parts += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { parts += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { parts += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { parts += "⌘" }
        return parts + KeyCodeNames.name(for: keyCode)
    }
}

/// Which keystroke in the popup commits the selection.
enum CommitKey: String, Codable, CaseIterable, Identifiable {
    case `return`
    case commandReturn

    var id: String { rawValue }

    var label: String {
        switch self {
        case .return: return "Return (↩)"
        case .commandReturn: return "Command-Return (⌘↩)"
        }
    }
}

/// Which keystroke removes the highlighted entry.
enum DeleteKey: String, Codable, CaseIterable, Identifiable {
    case delete
    case commandDelete

    var id: String { rawValue }

    var label: String {
        switch self {
        case .delete: return "Backspace (⌫)"
        case .commandDelete: return "Command-Backspace (⌘⌫)"
        }
    }

    var glyph: String {
        switch self {
        case .delete: return "⌫"
        case .commandDelete: return "⌘⌫"
        }
    }
}

/// User preferences, persisted in `UserDefaults` and observed by the UI.
///
/// Every property writes through on `didSet`, so there is no separate save
/// step and the settings window can bind directly to it.
@MainActor
final class Settings: ObservableObject {
    static let shared = Settings()

    private let defaults = UserDefaults.standard

    @Published var shortcut: Shortcut {
        didSet { store(shortcut, forKey: Keys.shortcut); onShortcutChange?(shortcut) }
    }
    @Published var maxItems: Int {
        didSet { defaults.set(maxItems, forKey: Keys.maxItems) }
    }
    @Published var commitKey: CommitKey {
        didSet { defaults.set(commitKey.rawValue, forKey: Keys.commitKey) }
    }
    /// When false the popup only puts the item on the pasteboard and leaves
    /// the actual paste to the user.
    @Published var autoPaste: Bool {
        didSet { defaults.set(autoPaste, forKey: Keys.autoPaste) }
    }
    /// After pasting an item from the popup, move it to the top of the list.
    @Published var moveToTopOnPaste: Bool {
        didSet { defaults.set(moveToTopOnPaste, forKey: Keys.moveToTopOnPaste) }
    }
    @Published var deleteKey: DeleteKey {
        didSet { defaults.set(deleteKey.rawValue, forKey: Keys.deleteKey) }
    }
    @Published var skipConcealed: Bool {
        didSet { defaults.set(skipConcealed, forKey: Keys.skipConcealed) }
    }
    @Published var skipTransient: Bool {
        didSet { defaults.set(skipTransient, forKey: Keys.skipTransient) }
    }
    @Published var ignoredBundleIDs: [String] {
        didSet { defaults.set(ignoredBundleIDs, forKey: Keys.ignoredBundleIDs) }
    }
    @Published var launchAtLogin: Bool {
        didSet { applyLaunchAtLogin() }
    }

    /// Set by the app delegate so a shortcut edit re-registers the hotkey.
    var onShortcutChange: ((Shortcut) -> Void)?

    private enum Keys {
        static let shortcut = "shortcut"
        static let maxItems = "maxItems"
        static let commitKey = "commitKey"
        static let autoPaste = "autoPaste"
        static let moveToTopOnPaste = "moveToTopOnPaste"
        static let deleteKey = "deleteKey"
        static let skipConcealed = "skipConcealed"
        static let skipTransient = "skipTransient"
        static let ignoredBundleIDs = "ignoredBundleIDs"
    }

    private init() {
        if let data = defaults.data(forKey: Keys.shortcut),
           let decoded = try? JSONDecoder().decode(Shortcut.self, from: data) {
            shortcut = decoded
        } else {
            shortcut = .default
        }
        maxItems = defaults.object(forKey: Keys.maxItems) as? Int ?? 500
        commitKey = CommitKey(rawValue: defaults.string(forKey: Keys.commitKey) ?? "") ?? .return
        autoPaste = defaults.object(forKey: Keys.autoPaste) as? Bool ?? true
        moveToTopOnPaste = defaults.object(forKey: Keys.moveToTopOnPaste) as? Bool ?? true
        deleteKey = DeleteKey(rawValue: defaults.string(forKey: Keys.deleteKey) ?? "") ?? .delete
        skipConcealed = defaults.object(forKey: Keys.skipConcealed) as? Bool ?? true
        skipTransient = defaults.object(forKey: Keys.skipTransient) as? Bool ?? true
        ignoredBundleIDs = defaults.stringArray(forKey: Keys.ignoredBundleIDs) ?? Settings.defaultIgnoredBundleIDs
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    /// Password managers and the keychain, pre-filled because they are the
    /// cases where a stray recorded copy actually matters.
    static let defaultIgnoredBundleIDs = [
        "com.apple.keychainaccess",
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.bitwarden.desktop",
    ]

    private func store<T: Encodable>(_ value: T, forKey key: String) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
    }

    private func applyLaunchAtLogin() {
        // Only meaningful for a registered bundle; a `swift run` binary has no
        // login item to toggle, so failures are logged rather than surfaced.
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Pastiche: launch-at-login change failed: \(error.localizedDescription)")
        }
    }
}

/// Maps virtual key codes to the glyphs a shortcut field should show.
enum KeyCodeNames {
    private static let special: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫",
        kVK_Escape: "⎋", kVK_LeftArrow: "←", kVK_RightArrow: "→",
        kVK_UpArrow: "↑", kVK_DownArrow: "↓", kVK_ANSI_Quote: "'",
        kVK_ANSI_Comma: ",", kVK_ANSI_Period: ".", kVK_ANSI_Slash: "/",
        kVK_ANSI_Semicolon: ";", kVK_ANSI_Backslash: "\\",
        kVK_ANSI_LeftBracket: "[", kVK_ANSI_RightBracket: "]",
        kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "=", kVK_ANSI_Grave: "`",
    ]

    static func name(for keyCode: UInt32) -> String {
        if let special = special[Int(keyCode)] { return special }
        if let layout = characterForKeyCode(keyCode) { return layout.uppercased() }
        return "Key \(keyCode)"
    }

    /// Asks the current keyboard layout what this key types, so a French or
    /// Dvorak layout shows its own glyph rather than the US one.
    private static func characterForKeyCode(_ keyCode: UInt32) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data

        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0

        let status = data.withUnsafeBytes { raw -> OSStatus in
            guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return -1 }
            return UCKeyTranslate(
                layout,
                UInt16(keyCode),
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                chars.count,
                &length,
                &chars
            )
        }
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: length)
    }
}
