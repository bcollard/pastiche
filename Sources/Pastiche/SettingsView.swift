import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: Settings
    @ObservedObject var store: ClipboardStore

    /// Permission changes happen in System Settings, which publishes no
    /// notification we can subscribe to, so this is polled while the window is
    /// open. `.onAppear` alone fired once and then went stale for the whole
    /// session, which is exactly when the user is looking at it.
    @State private var hasAccessibility = Paster.hasAccessibilityPermission(prompt: false)
    private let permissionPoll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var newBundleID = ""
    @State private var showingClearConfirmation = false
    /// `PASTICHE_SETTINGS_TAB` (general, privacy or about) opens Settings on a
    /// given tab. Used by the store-listing screenshots.
    @State private var tab = ProcessInfo.processInfo.environment["PASTICHE_SETTINGS_TAB"] ?? "general"

    var body: some View {
        TabView(selection: $tab) {
            general.tabItem { Label("General", systemImage: "gearshape") }.tag("general")
            privacy.tabItem { Label("Privacy", systemImage: "hand.raised") }.tag("privacy")
            about.tabItem { Label("About", systemImage: "info.circle") }.tag("about")
        }
        .frame(width: 460, height: 430)
        .onAppear { refreshPermission() }
        .onReceive(permissionPoll) { _ in refreshPermission() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermission()
        }
    }

    // MARK: - General

    private var general: some View {
        Form {
            Section {
                LabeledContent("Open clipboard") {
                    ShortcutRecorder(shortcut: $settings.shortcut)
                }
                Picker("Paste with", selection: $settings.commitKey) {
                    ForEach(CommitKey.allCases) { key in
                        Text(key.label).tag(key)
                    }
                }
                Picker("Delete entry with", selection: $settings.deleteKey) {
                    ForEach(DeleteKey.allCases) { key in
                        Text(key.label).tag(key)
                    }
                }
                if settings.deleteKey == .delete {
                    Text("Backspace deletes only when the caret is outside the search field; ⌘⌫ always works.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Toggle("Paste into the active app automatically", isOn: $settings.autoPaste)
                Text(settings.autoPaste
                     ? "The selected item is copied and ⌘V is sent to the app you came from."
                     : "The selected item is only copied; paste it yourself.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            } header: {
                Text("Shortcuts")
            }

            Section {
                LabeledContent("Keep at most") {
                    HStack(spacing: 6) {
                        TextField("", value: $settings.maxItems, format: .number)
                            .frame(width: 70)
                            .multilineTextAlignment(.trailing)
                        Stepper("", value: $settings.maxItems, in: 10...10_000, step: 50)
                            .labelsHidden()
                        Text("items").foregroundStyle(.secondary)
                    }
                }
                Toggle("Move pasted item to the top", isOn: $settings.moveToTopOnPaste)
                Toggle("Open at login", isOn: $settings.launchAtLogin)
            } header: {
                Text("History")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Privacy

    private var privacy: some View {
        Form {
            Section {
                Toggle("Ignore items marked as concealed", isOn: $settings.skipConcealed)
                Text("Apps that follow the nspasteboard.org convention (1Password does) mark copied secrets with org.nspasteboard.ConcealedType.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                Toggle("Ignore transient and auto-generated items", isOn: $settings.skipTransient)
                Text("Content apps put on the pasteboard programmatically, which you never explicitly copied.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            } header: {
                Text("Pasteboard markers")
            }

            Section {
                if settings.ignoredBundleIDs.isEmpty {
                    Text("No apps ignored.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(settings.ignoredBundleIDs, id: \.self) { bundleID in
                        HStack {
                            Text(bundleID)
                                .font(.system(size: 11, design: .monospaced))
                            Spacer()
                            Button {
                                settings.ignoredBundleIDs.removeAll { $0 == bundleID }
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }

                HStack(spacing: 6) {
                    TextField("com.example.app", text: $newBundleID)
                        .font(.system(size: 11, design: .monospaced))
                        .onSubmit(addBundleID)
                    Button("Add", action: addBundleID)
                        .disabled(newBundleID.trimmingCharacters(in: .whitespaces).isEmpty)
                    Menu("Running…") {
                        ForEach(runningApps, id: \.0) { bundleID, name in
                            Button(name) { add(bundleID) }
                        }
                    }
                    .frame(width: 100)
                }
            } header: {
                Text("Never record copies from")
            }
        }
        .formStyle(.grouped)
    }

    private var runningApps: [(String, String)] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in
                guard let bundleID = app.bundleIdentifier,
                      !settings.ignoredBundleIDs.contains(bundleID) else { return nil }
                return (bundleID, app.localizedName ?? bundleID)
            }
            .sorted { $0.1.localizedCaseInsensitiveCompare($1.1) == .orderedAscending }
    }

    private func addBundleID() {
        add(newBundleID)
        newBundleID = ""
    }

    private func add(_ bundleID: String) {
        let trimmed = bundleID.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !settings.ignoredBundleIDs.contains(trimmed) else { return }
        settings.ignoredBundleIDs.append(trimmed)
    }

    private func refreshPermission() {
        let granted = Paster.hasAccessibilityPermission(prompt: false)
        if granted != hasAccessibility { hasAccessibility = granted }
    }

    // MARK: - About

    private var about: some View {
        Form {
            Section {
                LabeledContent("Accessibility") {
                    HStack(spacing: 8) {
                        Label(
                            hasAccessibility ? "Granted" : "Not granted",
                            systemImage: hasAccessibility ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(hasAccessibility ? Color.green : Color.orange)
                        .font(.system(size: 11))

                        if !hasAccessibility {
                            Button("Grant…") {
                                Paster.requestAccessibilityPermission()
                            }
                            Button("Relaunch") {
                                Paster.relaunch()
                            }
                        }
                    }
                }
                Text(hasAccessibility
                     ? "Pastiche can paste into the app you came from."
                     : "Required only to paste automatically. The popup and its shortcut work without it. If this still says “Not granted” just after you granted it, use Relaunch.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            } header: {
                Text("Permissions")
            }

            Section {
                LabeledContent("Stored items", value: String(store.items.count))
                Button("Clear history…", role: .destructive) {
                    showingClearConfirmation = true
                }
                .confirmationDialog(
                    "Delete all \(String(store.items.count)) items?",
                    isPresented: $showingClearConfirmation
                ) {
                    Button("Delete All", role: .destructive) { store.clearAll() }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This cannot be undone.")
                }
            } header: {
                Text("History")
            }

            Section {
                LabeledContent("Version", value: Bundle.main.shortVersion)
                Text("An open-source clipboard manager for macOS.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

extension Bundle {
    var shortVersion: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(version) (\(build))"
    }
}
