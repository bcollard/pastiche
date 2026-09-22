import CoreGraphics
for w in (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []) {
    guard (w[kCGWindowOwnerName as String] as? String) == "Pastiche" else { continue }
    let b = w[kCGWindowBounds as String] as? [String: Any] ?? [:]
    print("id=\(w[kCGWindowNumber as String] ?? 0) pid=\(w[kCGWindowOwnerPID as String] ?? 0) layer=\(w[kCGWindowLayer as String] ?? 0) \(Int((b["Width"] as? Double) ?? 0))x\(Int((b["Height"] as? Double) ?? 0)) name=\(w[kCGWindowName as String] ?? "")")
}
