import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Click-to-record field for the global hotkey.
///
/// While recording it installs a local key monitor and swallows everything, so
/// the combination being recorded cannot also trigger whatever it normally
/// does inside the settings window.
struct ShortcutRecorder: View {
    @Binding var shortcut: Shortcut

    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var warning: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: toggleRecording) {
                Text(isRecording ? "Press keys…" : shortcut.displayString)
                    .font(.system(size: 12, weight: .medium))
                    .frame(minWidth: 110)
                    .padding(.vertical, 3)
            }
            .buttonStyle(.bordered)
            .tint(isRecording ? .accentColor : nil)

            if let warning {
                Text(warning)
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
            }
        }
        .onDisappear(perform: stopRecording)
    }

    private func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        warning = nil
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            guard event.type == .keyDown else { return nil }
            handle(event)
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
    }

    private func handle(_ event: NSEvent) {
        if Int(event.keyCode) == kVK_Escape {
            stopRecording()
            return
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let carbon = Self.carbonModifiers(from: flags)
        // A bare key would fire in every app the moment it is pressed.
        guard carbon != 0 else {
            warning = "Include at least one of ⌘ ⌥ ⌃ ⇧."
            return
        }

        shortcut = Shortcut(keyCode: UInt32(event.keyCode), carbonModifiers: carbon)
        stopRecording()
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }
}
