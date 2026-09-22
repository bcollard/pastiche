// Draws three generic demo images for the store-listing screenshots.
// Usage: swift make_demo_images.swift <output-dir>
import AppKit

guard CommandLine.arguments.count == 2 else { FileHandle.standardError.write(Data("usage: make_demo_images.swift <dir>\n".utf8)); exit(2) }
let out = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func color(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: a)
}
func render(_ name: String, _ w: Int, _ h: Int, _ draw: (NSRect) -> Void) throws {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(NSRect(x: 0, y: 0, width: w, height: h))
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name))
}
func rounded(_ r: NSRect, _ radius: CGFloat, _ c: NSColor) { c.setFill(); NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius).fill() }

// 1. A generic app-design mockup.
try render("design.png", 1440, 900) { b in
    NSGradient(colors: [color(0xE9ECFF), color(0xF6E9FF)])!.draw(in: b, angle: -30)
    rounded(NSRect(x: 60, y: 60, width: 300, height: 780), 24, color(0x4F5FE8))
    for i in 0..<5 { rounded(NSRect(x: 90, y: 760 - CGFloat(i) * 70, width: 240, height: 40), 12, color(0xFFFFFF, i == 1 ? 0.95 : 0.25)) }
    rounded(NSRect(x: 400, y: 700, width: 980, height: 140), 24, .white)
    rounded(NSRect(x: 430, y: 770, width: 420, height: 26), 8, color(0x1B1A22, 0.85))
    rounded(NSRect(x: 430, y: 730, width: 300, height: 18), 8, color(0x1B1A22, 0.25))
    for i in 0..<3 {
        let x = 400 + CGFloat(i) * 336
        rounded(NSRect(x: x, y: 380, width: 308, height: 280), 24, .white)
        rounded(NSRect(x: x + 24, y: 560, width: 260, height: 70), 16, [color(0xFF8A5B), color(0x4F5FE8), color(0x35C7A5)][i])
        rounded(NSRect(x: x + 24, y: 500, width: 200, height: 20), 8, color(0x1B1A22, 0.8))
        rounded(NSRect(x: x + 24, y: 460, width: 240, height: 14), 7, color(0x1B1A22, 0.22))
        rounded(NSRect(x: x + 24, y: 425, width: 160, height: 14), 7, color(0x1B1A22, 0.22))
    }
    rounded(NSRect(x: 400, y: 60, width: 980, height: 280), 24, .white)
    rounded(NSRect(x: 430, y: 290, width: 240, height: 22), 8, color(0x1B1A22, 0.8))
    for i in 0..<5 { rounded(NSRect(x: 430, y: 240 - CGFloat(i) * 38, width: CGFloat(880 - i * 90), height: 14), 7, color(0x1B1A22, 0.16)) }
}

// 2. A generic bar-and-line chart.
try render("chart.png", 1200, 720) { b in
    color(0xFFFFFF).setFill(); b.fill()
    color(0x1B1A22, 0.08).setStroke()
    for i in 0..<6 { let y = 90 + CGFloat(i) * 105; let l = NSBezierPath(); l.move(to: NSPoint(x: 90, y: y)); l.line(to: NSPoint(x: 1120, y: y)); l.lineWidth = 2; l.stroke() }
    let values: [CGFloat] = [0.35, 0.5, 0.42, 0.66, 0.58, 0.8, 0.72, 0.92]
    for (i, v) in values.enumerated() {
        rounded(NSRect(x: 130 + CGFloat(i) * 124, y: 90, width: 76, height: v * 520), 14, color(i == 7 ? 0xFF8A5B : 0x4F5FE8, i == 7 ? 1 : 0.85))
    }
    let line = NSBezierPath()
    for (i, v) in values.enumerated() {
        let p = NSPoint(x: 168 + CGFloat(i) * 124, y: 90 + v * 480 + 30)
        i == 0 ? line.move(to: p) : line.line(to: p)
    }
    color(0x35C7A5).setStroke(); line.lineWidth = 8; line.lineJoinStyle = .round; line.stroke()
    rounded(NSRect(x: 90, y: 650, width: 260, height: 26), 10, color(0x1B1A22, 0.8))
}

// 3. A generic landscape.
try render("landscape.png", 1600, 900) { b in
    NSGradient(colors: [color(0xFFB88C), color(0xF5C2E7), color(0x8FA3FF)])!.draw(in: b, angle: 90)
    color(0xFFF3D6).setFill(); NSBezierPath(ovalIn: NSRect(x: 1080, y: 470, width: 220, height: 220)).fill()
    for (i, c) in [color(0x5B5FA8), color(0x3F4488), color(0x2A2E63)].enumerated() {
        let path = NSBezierPath(); path.move(to: NSPoint(x: 0, y: 0))
        for x in stride(from: 0, through: 1600, by: 40) {
            let y = 250 + CGFloat(i) * 70 + sin(CGFloat(x) / (170 - CGFloat(i) * 30) + CGFloat(i)) * (70 - CGFloat(i) * 12)
            path.line(to: NSPoint(x: CGFloat(x), y: y))
        }
        path.line(to: NSPoint(x: 1600, y: 0)); path.close(); c.setFill(); path.fill()
    }
}
print("wrote 3 images to \(out.path)")
