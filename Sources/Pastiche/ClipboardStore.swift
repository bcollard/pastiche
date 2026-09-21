import AppKit
import Combine
import Foundation

/// The clipboard history: an ordered, deduplicated, capped list of items plus
/// its on-disk mirror.
///
/// Newest item is always at index 0. Text lives in `history.json`; images live
/// as PNGs beside it and are loaded lazily into a small in-memory cache so a
/// long history does not pin every bitmap in RAM.
@MainActor
final class ClipboardStore: ObservableObject {
    @Published private(set) var items: [ClipboardItem] = []

    private let settings: Settings
    private let directory: URL
    private let imagesDirectory: URL
    private let historyFile: URL

    private var imageCache: [UUID: NSImage] = [:]
    private var saveWorkItem: DispatchWorkItem?

    init(settings: Settings) {
        self.settings = settings
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent("Pastiche", isDirectory: true)
        imagesDirectory = directory.appendingPathComponent("images", isDirectory: true)
        historyFile = directory.appendingPathComponent("history.json")

        try? FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        load()
    }

    // MARK: - Mutation

    /// Records a text copy, promoting an existing identical entry instead of
    /// creating a duplicate.
    func addText(_ text: String, source: SourceApp?) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let fingerprint = ClipboardItem.fingerprint(for: text)
        if promoteExisting(fingerprint: fingerprint) { return }

        let item = ClipboardItem(
            kind: .text,
            text: text,
            sourceBundleID: source?.bundleID,
            sourceAppName: source?.name,
            fingerprint: fingerprint
        )
        insert(item)
    }

    /// Records an image copy. The bitmap is re-encoded to PNG so the on-disk
    /// format is predictable regardless of what the source app offered.
    func addImage(_ image: NSImage, pngData: Data, source: SourceApp?) {
        let fingerprint = ClipboardItem.fingerprint(for: pngData)
        if promoteExisting(fingerprint: fingerprint) { return }

        let id = UUID()
        let filename = "\(id.uuidString).png"
        do {
            try pngData.write(to: imagesDirectory.appendingPathComponent(filename))
        } catch {
            NSLog("Pastiche: could not write image: \(error.localizedDescription)")
            return
        }

        let pixelSize = Self.pixelSize(of: image)
        let item = ClipboardItem(
            id: id,
            kind: .image,
            imageFile: filename,
            pixelWidth: pixelSize.width,
            pixelHeight: pixelSize.height,
            sourceBundleID: source?.bundleID,
            sourceAppName: source?.name,
            fingerprint: fingerprint
        )
        imageCache[id] = image
        insert(item)
    }

    func delete(_ item: ClipboardItem) {
        items.removeAll { $0.id == item.id }
        discardResources(for: item)
        scheduleSave()
    }

    func clearAll() {
        for item in items { discardResources(for: item) }
        items.removeAll()
        scheduleSave()
    }

    /// Moves an existing entry back to the top when the same content is copied
    /// again. Returns false when nothing matched.
    private func promoteExisting(fingerprint: String) -> Bool {
        guard let index = items.firstIndex(where: { $0.fingerprint == fingerprint }) else { return false }
        guard index != 0 else { return true }
        let item = items.remove(at: index)
        items.insert(item, at: 0)
        scheduleSave()
        return true
    }

    private func insert(_ item: ClipboardItem) {
        items.insert(item, at: 0)
        prune()
        scheduleSave()
    }

    private func prune() {
        let cap = max(10, settings.maxItems)
        guard items.count > cap else { return }
        let dropped = items[cap...]
        for item in dropped { discardResources(for: item) }
        items.removeLast(items.count - cap)
    }

    private func discardResources(for item: ClipboardItem) {
        imageCache[item.id] = nil
        guard let file = item.imageFile else { return }
        try? FileManager.default.removeItem(at: imagesDirectory.appendingPathComponent(file))
    }

    // MARK: - Images

    /// Returns the bitmap for an image item, decoding from disk on first use.
    func image(for item: ClipboardItem) -> NSImage? {
        if let cached = imageCache[item.id] { return cached }
        guard let file = item.imageFile,
              let image = NSImage(contentsOf: imagesDirectory.appendingPathComponent(file))
        else { return nil }
        imageCache[item.id] = image
        return image
    }

    private static func pixelSize(of image: NSImage) -> (width: Int, height: Int) {
        if let rep = image.representations.first {
            return (rep.pixelsWide, rep.pixelsHigh)
        }
        return (Int(image.size.width), Int(image.size.height))
    }

    // MARK: - Persistence

    /// Coalesces bursts of copies into one write a moment later, so holding
    /// Cmd-C down does not turn into a write per keystroke.
    private func scheduleSave() {
        saveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.save() }
        saveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    func save() {
        saveWorkItem?.cancel()
        saveWorkItem = nil
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(items)
            try data.write(to: historyFile, options: .atomic)
        } catch {
            NSLog("Pastiche: could not save history: \(error.localizedDescription)")
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: historyFile) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let decoded = try? decoder.decode([ClipboardItem].self, from: data) else {
            NSLog("Pastiche: history file unreadable, starting empty")
            return
        }
        // Drop entries whose image file disappeared (manual cleanup, migration,
        // a half-finished write) so the list never shows an empty row.
        items = decoded.filter { item in
            guard let file = item.imageFile else { return true }
            return FileManager.default.fileExists(atPath: imagesDirectory.appendingPathComponent(file).path)
        }
        collectOrphanImages()
    }

    /// Removes PNGs on disk that no longer belong to any item.
    private func collectOrphanImages() {
        let referenced = Set(items.compactMap(\.imageFile))
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: imagesDirectory.path) else { return }
        for file in files where !referenced.contains(file) {
            try? FileManager.default.removeItem(at: imagesDirectory.appendingPathComponent(file))
        }
    }
}
