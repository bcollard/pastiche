import AppKit
import SwiftUI

/// The popup's contents. All keyboard handling lives in `PopupController`'s
/// event monitor; this view only renders state and handles mouse input.
struct PopupView: View {
    @ObservedObject var model: PopupModel
    @ObservedObject var settings: Settings

    var onCommit: (ClipboardItem) -> Void
    var onOpenSettings: () -> Void
    var onClose: () -> Void
    var onGrantAccessibility: () -> Void

    @FocusState private var searchFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            searchBar
            Divider().opacity(0.5)
            listOrEmptyState
            Divider().opacity(0.5)
            if settings.autoPaste && !model.accessibilityGranted {
                accessibilityBanner
                Divider().opacity(0.5)
            }
            footer
        }
        .frame(width: 460, height: 580)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
        // The controller drives focus from key events; these two keep the
        // SwiftUI focus state and the model in step in both directions.
        .onChange(of: model.searchFocused) { _, focused in
            searchFieldFocused = focused
        }
        .onChange(of: searchFieldFocused) { _, focused in
            model.searchFocused = focused
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Text("Clipboard")
                .font(.system(size: 13, weight: .semibold))
            Text(verbatim: "\(model.visibleItems.count)")
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.primary.opacity(0.08), in: Capsule())

            Spacer(minLength: 8)

            Picker("Type", selection: $model.typeFilter) {
                ForEach(TypeFilter.allCases) { filter in
                    Label(filter.label, systemImage: filter.symbolName).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 190)
            .help("Filter by type (← →)")

            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Settings (⌘,)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Search

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 12))
            TextField("Search (⇥)", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($searchFieldFocused)
            if !model.query.isEmpty {
                Button {
                    model.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(searchFieldFocused ? 0.10 : 0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(searchFieldFocused ? 0.8 : 0), lineWidth: 1.5)
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 9)
    }

    // MARK: - List

    @ViewBuilder
    private var listOrEmptyState: some View {
        if model.visibleItems.isEmpty {
            emptyState
        } else {
            itemList
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: model.query.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.tertiary)
            Text(emptyMessage)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var emptyMessage: String {
        if !model.query.isEmpty { return "Nothing matches “\(model.query)”." }
        switch model.typeFilter {
        case .all: return "Nothing copied yet.\nCopy something and it will show up here."
        case .text: return "No text snippets yet."
        case .image: return "No images yet."
        }
    }

    private var itemList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(model.visibleItems.enumerated()), id: \.element.id) { index, item in
                        ItemRow(
                            item: item,
                            digit: model.shortcutDigit(forRow: index),
                            isSelected: item.id == model.selectedID,
                            image: item.kind == .image ? model.store.image(for: item) : nil
                        )
                        .id(item.id)
                        .contentShape(Rectangle())
                        .onTapGesture { onCommit(item) }
                        .contextMenu {
                            Button("Paste") { onCommit(item) }
                            Button("Delete") {
                                model.selectedID = item.id
                                model.deleteSelected()
                            }
                        }
                        Divider().opacity(0.35)
                    }
                }
            }
            .onChange(of: model.selectedID) { _, id in
                guard let id else { return }
                proxy.scrollTo(id, anchor: .center)
            }
        }
    }

    /// Shown instead of re-raising the system modal on every paste: the item
    /// still reaches the pasteboard, only the automatic ⌘V is missing.
    private var accessibilityBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.orange)
            Text("Items are copied but not pasted — Accessibility is off.")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Button("Grant…", action: onGrantAccessibility)
                .buttonStyle(.borderless)
                .font(.system(size: 10.5, weight: .medium))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.12))
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            hint("↑↓", "Navigate")
            hint("←→", "Type")
            hint("⇥", "Search")
            hint(settings.deleteKey.glyph, "Delete")
            hint(settings.commitKey == .return ? "↩" : "⌘↩", settings.autoPaste ? "Paste" : "Copy")
            Spacer()
            Button(action: onClose) {
                Text("⎋").font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Close")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 10, weight: .semibold))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.primary.opacity(0.10), in: RoundedRectangle(cornerRadius: 3))
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }
}

/// One row: the payload on the left, its ⌘-digit on the right.
private struct ItemRow: View {
    let item: ClipboardItem
    let digit: String?
    let isSelected: Bool
    let image: NSImage?

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            content
                .frame(maxWidth: .infinity, alignment: .leading)

            if let digit {
                Text(digit)
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? Color.white.opacity(0.9) : Color.secondary)
                    .frame(width: 14, alignment: .trailing)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Color.accentColor : Color.clear)
    }

    @ViewBuilder
    private var content: some View {
        switch item.kind {
        case .text:
            VStack(alignment: .leading, spacing: 3) {
                Text(item.previewText)
                    .font(.system(size: 12.5))
                    .lineLimit(3)
                    .truncationMode(.tail)
                    .foregroundStyle(textColor)
                if let source = item.sourceAppName {
                    Text(source)
                        .font(.system(size: 10))
                        .foregroundStyle(isSelected ? Color.white.opacity(0.7) : Color.secondary)
                }
            }
        case .image:
            // Centred and large, the way Copy 'Em renders an image row: the
            // picture is the content, not an icon next to a caption.
            VStack(spacing: 5) {
                Group {
                    if let image {
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.medium)
                            .aspectRatio(contentMode: .fit)
                    } else {
                        Image(systemName: "photo")
                            .font(.system(size: 26))
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(width: thumbnailSize.width, height: thumbnailSize.height)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5)
                )

                HStack(spacing: 5) {
                    Text(verbatim: "\(item.pixelWidth ?? 0) × \(item.pixelHeight ?? 0)")
                        .monospacedDigit()
                    if let source = item.sourceAppName {
                        Text("·")
                        Text(source)
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(isSelected ? Color.white.opacity(0.75) : Color.secondary)
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// Sizes the thumbnail to the image's own aspect ratio rather than
    /// reserving a fixed box, so a wide screenshot and a square icon both sit
    /// flush against their caption.
    private var thumbnailSize: CGSize {
        let maxWidth: CGFloat = 330
        let maxHeight: CGFloat = 150
        let width = CGFloat(item.pixelWidth ?? 0)
        let height = CGFloat(item.pixelHeight ?? 0)
        guard width > 0, height > 0 else { return CGSize(width: 64, height: 64) }

        // Never upscale: a 16x16 favicon should stay small rather than blur up
        // to fill the row.
        let scale = min(maxWidth / width, maxHeight / height, 1)
        return CGSize(width: max(width * scale, 24), height: max(height * scale, 24))
    }

    private var textColor: Color {
        if isSelected { return .white }
        return item.isLink ? .accentColor : .primary
    }
}
