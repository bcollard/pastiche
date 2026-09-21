import AppKit
import CryptoKit
import Foundation

/// The two payload kinds the app records. Used both as a storage tag and as the
/// value backing the popup's type filter.
enum ItemKind: String, Codable, CaseIterable {
    case text
    case image
}

/// One entry in the clipboard history.
///
/// Text payloads live inline; image payloads live as PNG files under the
/// support directory and are referenced by `imageFile`. `fingerprint` is what
/// deduplication compares, so it is derived from the payload only — never from
/// the timestamp or the source app.
struct ClipboardItem: Identifiable, Codable, Equatable {
    let id: UUID
    let kind: ItemKind
    /// Full text for `.text` items. Nil for images.
    let text: String?
    /// Filename (not path) inside the `images/` directory. Nil for text.
    let imageFile: String?
    /// Pixel size of the image, kept so the row can label it without decoding.
    let pixelWidth: Int?
    let pixelHeight: Int?
    let sourceBundleID: String?
    let sourceAppName: String?
    let createdAt: Date
    let fingerprint: String

    init(
        id: UUID = UUID(),
        kind: ItemKind,
        text: String? = nil,
        imageFile: String? = nil,
        pixelWidth: Int? = nil,
        pixelHeight: Int? = nil,
        sourceBundleID: String? = nil,
        sourceAppName: String? = nil,
        createdAt: Date = Date(),
        fingerprint: String
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.imageFile = imageFile
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.sourceBundleID = sourceBundleID
        self.sourceAppName = sourceAppName
        self.createdAt = createdAt
        self.fingerprint = fingerprint
    }

    static func fingerprint(for data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func fingerprint(for string: String) -> String {
        fingerprint(for: Data(string.utf8))
    }

    /// Single-line label used by search and by the row when it has to collapse.
    var searchableText: String {
        switch kind {
        case .text: return text ?? ""
        case .image: return "image \(pixelWidth ?? 0)x\(pixelHeight ?? 0) \(sourceAppName ?? "")"
        }
    }

    /// Text trimmed to something a three-line row can render without hauling a
    /// megabyte of string through SwiftUI's layout pass.
    var previewText: String {
        guard let text else { return "" }
        let collapsed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if collapsed.count <= 400 { return collapsed }
        return String(collapsed.prefix(400)) + "…"
    }

    /// True when the text is a single well-formed http(s) URL, which the row
    /// renders in accent colour the way Copy 'Em does.
    var isLink: Bool {
        guard kind == .text, let text else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains(" "), trimmed.count < 2048 else { return false }
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() else { return false }
        return (scheme == "http" || scheme == "https") && url.host != nil
    }
}
