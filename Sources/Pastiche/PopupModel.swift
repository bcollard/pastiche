import Combine
import Foundation

/// The popup's type filter, matching Copy 'Em's "All Types" dropdown.
enum TypeFilter: String, CaseIterable, Identifiable {
    case all
    case text
    case image

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "All"
        case .text: return "Text"
        case .image: return "Images"
        }
    }

    var symbolName: String {
        switch self {
        case .all: return "square.stack"
        case .text: return "textformat"
        case .image: return "photo"
        }
    }

    func matches(_ item: ClipboardItem) -> Bool {
        switch self {
        case .all: return true
        case .text: return item.kind == .text
        case .image: return item.kind == .image
        }
    }
}

/// View state for the popup: the query, the filter, and the derived list.
///
/// Selection is tracked by item id rather than index so that a history change
/// underneath the popup (a new copy arriving while it is open) keeps the
/// highlight on the row the user was looking at.
@MainActor
final class PopupModel: ObservableObject {
    @Published var query: String = "" { didSet { refresh() } }
    @Published var typeFilter: TypeFilter = .all { didSet { refresh() } }
    @Published var searchFocused: Bool = false
    @Published private(set) var visibleItems: [ClipboardItem] = []
    @Published var selectedID: UUID?
    /// Mirrors the Accessibility grant, refreshed whenever the popup opens so
    /// the banner never contradicts what the system actually thinks.
    @Published var accessibilityGranted: Bool = true

    let store: ClipboardStore
    private var cancellable: AnyCancellable?

    init(store: ClipboardStore) {
        self.store = store
        cancellable = store.$items
            .receive(on: RunLoop.main)
            .sink { [weak self] items in self?.refresh(with: items) }
        refresh()
    }

    /// Resets to the state the popup should open in.
    func reset() {
        query = ""
        searchFocused = false
        refresh()
        selectedID = visibleItems.first?.id
    }

    private func refresh() {
        refresh(with: store.items)
    }

    private func refresh(with items: [ClipboardItem]) {
        // Every whitespace-separated term must appear somewhere in the item,
        // so "png kong" narrows the way a user expects rather than matching the
        // literal phrase.
        let terms = query
            .lowercased()
            .split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)

        visibleItems = items.filter { item in
            guard typeFilter.matches(item) else { return false }
            guard !terms.isEmpty else { return true }
            let haystack = item.searchableText.lowercased()
            return terms.allSatisfy { haystack.contains($0) }
        }

        if let selectedID, visibleItems.contains(where: { $0.id == selectedID }) { return }
        selectedID = visibleItems.first?.id
    }

    // MARK: - Selection

    var selectedIndex: Int? {
        guard let selectedID else { return nil }
        return visibleItems.firstIndex { $0.id == selectedID }
    }

    var selectedItem: ClipboardItem? {
        guard let index = selectedIndex else { return nil }
        return visibleItems[index]
    }

    /// Moves the highlight by `offset` rows, clamped to the ends of the list.
    func moveSelection(by offset: Int) {
        guard !visibleItems.isEmpty else { return }
        let current = selectedIndex ?? 0
        let next = min(max(current + offset, 0), visibleItems.count - 1)
        selectedID = visibleItems[next].id
    }

    func selectFirst() {
        selectedID = visibleItems.first?.id
    }

    func selectLast() {
        selectedID = visibleItems.last?.id
    }

    /// Steps the type filter, which is what ← and → do in the popup.
    func cycleTypeFilter(by offset: Int) {
        let all = TypeFilter.allCases
        guard let index = all.firstIndex(of: typeFilter) else { return }
        let next = (index + offset + all.count) % all.count
        typeFilter = all[next]
    }

    /// Row number shown on the right of each row: 1…9 then 0 for the tenth,
    /// matching the ⌘-digit shortcuts.
    func shortcutDigit(forRow row: Int) -> String? {
        switch row {
        case 0..<9: return String(row + 1)
        case 9: return "0"
        default: return nil
        }
    }

    /// Maps a ⌘-digit keystroke back to a row index.
    func item(forDigit digit: Int) -> ClipboardItem? {
        let row = digit == 0 ? 9 : digit - 1
        guard visibleItems.indices.contains(row) else { return nil }
        return visibleItems[row]
    }

    func deleteSelected() {
        guard let item = selectedItem, let index = selectedIndex else { return }
        // Pick the neighbour before deleting: the store publishes
        // asynchronously, so `visibleItems` is still the pre-delete list here.
        let nextID: UUID?
        if visibleItems.indices.contains(index + 1) {
            nextID = visibleItems[index + 1].id
        } else if index > 0 {
            nextID = visibleItems[index - 1].id
        } else {
            nextID = nil
        }
        store.delete(item)
        selectedID = nextID
    }
}
