import Carbon.HIToolbox
import Foundation

/// Registers system-wide hotkeys through Carbon's `RegisterEventHotKey`.
///
/// Carbon is the only API that gives a real global hotkey without requiring
/// Accessibility permission — an `NSEvent` global monitor would need it, and
/// asking for that just to open a window is a worse trade. The app still needs
/// Accessibility for pasting, but the popup opens either way.
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private var registrations: [UInt32: (ref: EventHotKeyRef, action: () -> Void)] = [:]
    private var nextIdentifier: UInt32 = 1
    private var eventHandler: EventHandlerRef?
    private let lock = NSLock()

    /// 'PSTC' — distinguishes our hotkeys from any other app's in the
    /// process-wide Carbon namespace.
    private static let signature: OSType = 0x5053_5443

    private init() {}

    /// Replaces any previously registered hotkey for `token` with `shortcut`.
    /// Returns false when the combination is already taken system-wide.
    @discardableResult
    func register(_ shortcut: Shortcut, token: inout UInt32?, action: @escaping () -> Void) -> Bool {
        installHandlerIfNeeded()
        if let existing = token { unregister(token: existing) }

        lock.lock()
        let identifier = nextIdentifier
        nextIdentifier += 1
        lock.unlock()

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: identifier)
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else {
            NSLog("Pastiche: hotkey \(shortcut.displayString) unavailable (status \(status))")
            token = nil
            return false
        }

        lock.lock()
        registrations[identifier] = (ref, action)
        lock.unlock()
        token = identifier
        return true
    }

    func unregister(token: UInt32) {
        lock.lock()
        let entry = registrations.removeValue(forKey: token)
        lock.unlock()
        if let entry { UnregisterEventHotKey(entry.ref) }
    }

    fileprivate func fire(identifier: UInt32) {
        lock.lock()
        let action = registrations[identifier]?.action
        lock.unlock()
        guard let action else { return }
        DispatchQueue.main.async(execute: action)
    }

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(GetApplicationEventTarget(), hotKeyEventCallback, 1, &spec, nil, &eventHandler)
    }
}

/// C callback Carbon invokes on the main thread when a registered hotkey fires.
private func hotKeyEventCallback(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return status }
    HotKeyCenter.shared.fire(identifier: hotKeyID.id)
    return noErr
}
